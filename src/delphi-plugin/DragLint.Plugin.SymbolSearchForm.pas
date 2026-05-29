unit DragLint.Plugin.SymbolSearchForm;

{ v0.33 Symbol Search form.
  Modal TForm with a debounced TEdit that queries drag-lint for symbols
  matching the typed text.  Enter on a selected row returns the location
  as "file:line"; ESC returns empty string.

  Call ShowSymbolSearch() from the main IDE thread only. }

interface

function ShowSymbolSearch(const AExePath, ADbPath: string): string;

implementation

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Winapi.Windows,
  ToolsAPI;

{ ---- TSymbolSearchForm ---- }

type
  TSymbolItem = record
    QName:    string;
    Kind:     string;
    FilePath: string;
    Line:     Integer;
  end;

  TSymbolSearchHandler = class(TComponent)
  private
    FForm:      TForm;
    FEdit:      TEdit;
    FList:      TListView;
    FLblStatus: TLabel;
    FTimer:     TTimer;
    FExePath:   string;
    FDbPath:    string;
    FResult:    string;
    FItems:     array of TSymbolItem;
    procedure TimerFired(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Accept;
    procedure RunSearch(const AText: string);
  public
    constructor Create(AOwner: TComponent; AForm: TForm;
      AEdit: TEdit; AList: TListView; ALblStatus: TLabel;
      const AExePath, ADbPath: string); reintroduce;
    function GetResult: string;
  end;

{ ---- helper: spawn drag-lint and capture stdout ---- }

function RunCapture(const ACmdLine: string;
  out AOutput: string; ATimeoutMs: Integer): Integer;
var
  SA:         TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  SI:         TStartupInfoW;
  PI:         TProcessInformation;
  Buf:        array[0..4095] of AnsiChar;
  BytesRead:  DWORD;
  ExitCode:   DWORD;
  WideCmd:    string;
  SB:         TStringBuilder;
  TV:         DWORD;
begin
  Result  := -1;
  AOutput := '';
  SA.nLength              := SizeOf(SA);
  SA.bInheritHandle       := True;
  SA.lpSecurityDescriptor := nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb         := SizeOf(SI);
    SI.dwFlags    := STARTF_USESTDHANDLES;
    SI.hStdOutput := WritePipe;
    SI.hStdError  := WritePipe;
    SI.hStdInput  := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd := ACmdLine;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd),
       nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    SB := TStringBuilder.Create;
    try
      repeat
        BytesRead := 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then
          Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead] := #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;
    if ATimeoutMs <= 0 then TV := INFINITE
    else                     TV := DWORD(ATimeoutMs);
    WaitForSingleObject(PI.hProcess, TV);
    GetExitCodeProcess(PI.hProcess, ExitCode);
    Result := Integer(ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  finally
    CloseHandle(ReadPipe);
  end;
end;

{ ---- TSymbolSearchHandler ---- }

constructor TSymbolSearchHandler.Create(AOwner: TComponent; AForm: TForm;
  AEdit: TEdit; AList: TListView; ALblStatus: TLabel;
  const AExePath, ADbPath: string);
begin
  inherited Create(AOwner);
  FForm       := AForm;
  FEdit       := AEdit;
  FList       := AList;
  FLblStatus  := ALblStatus;
  FExePath    := AExePath;
  FDbPath     := ADbPath;
  FResult     := '';

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 300;
  FTimer.Enabled  := False;
  FTimer.OnTimer  := TimerFired;

  FEdit.OnChange      := EditChange;
  FList.OnDblClick    := ListDblClick;
  FForm.OnKeyDown     := FormKeyDown;
end;

function TSymbolSearchHandler.GetResult: string;
begin
  Result := FResult;
end;

procedure TSymbolSearchHandler.EditChange(Sender: TObject);
begin
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TSymbolSearchHandler.TimerFired(Sender: TObject);
begin
  FTimer.Enabled := False;
  RunSearch(FEdit.Text);
end;

procedure TSymbolSearchHandler.RunSearch(const AText: string);
var
  CmdLine, Output: string;
  ExitCode:        Integer;
  Lines:           TStringList;
  i, j, Count:    Integer;
  Line:            string;
  Parts:           TArray<string>;
  Location:        string;
  ColonPos:        Integer;
  Item:            TListItem;
begin
  if (FExePath = '') or (Trim(AText) = '') then
  begin
    FList.Items.Clear;
    SetLength(FItems, 0);
    FLblStatus.Caption := 'Type to search...';
    Exit;
  end;

  FLblStatus.Caption := 'Searching...';
  FForm.Update;

  CmdLine := Format('"%s" query --name "%s"', [FExePath, Trim(AText)]);
  if FDbPath <> '' then
    CmdLine := CmdLine + Format(' --db "%s"', [FDbPath]);

  ExitCode := RunCapture(CmdLine, Output, 15000);

  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    SetLength(FItems, 0);

    if ExitCode < 0 then
    begin
      FLblStatus.Caption := 'Failed to spawn drag-lint.exe';
      Exit;
    end;

    Lines := TStringList.Create;
    try
      Lines.Text := Output;
      Count := 0;
      for i := 0 to Lines.Count - 1 do
      begin
        if Count >= 30 then Break;
        Line := Trim(Lines[i]);
        if Line = '' then Continue;

        { Expected text format: <qname>  [<kind>]  <file>:<line>
          Split on two or more spaces }
        Parts := Line.Split(['  '], TStringSplitOptions.ExcludeEmpty);
        if Length(Parts) < 3 then Continue;

        { Find location (last part that looks like file:N) }
        Location := Trim(Parts[Length(Parts) - 1]);
        ColonPos := 0;
        for j := Length(Location) downto 1 do
          if Location[j] = ':' then
          begin
            ColonPos := j;
            Break;
          end;

        SetLength(FItems, Count + 1);
        FItems[Count].QName    := Trim(Parts[0]);
        FItems[Count].Kind     := Trim(Parts[1]);
        if ColonPos > 0 then
        begin
          FItems[Count].FilePath := Copy(Location, 1, ColonPos - 1);
          FItems[Count].Line     := StrToIntDef(
            Copy(Location, ColonPos + 1, MaxInt), 0);
        end
        else
        begin
          FItems[Count].FilePath := Location;
          FItems[Count].Line     := 0;
        end;

        Item := FList.Items.Add;
        Item.Caption    := FItems[Count].QName;
        Item.SubItems.Add(FItems[Count].Kind);
        Item.SubItems.Add(Format('%s:%d',
          [ExtractFileName(FItems[Count].FilePath), FItems[Count].Line]));
        Inc(Count);
      end;

      FLblStatus.Caption := Format('%d result(s)', [Count]);
    finally
      Lines.Free;
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TSymbolSearchHandler.Accept;
var
  Idx: Integer;
begin
  if FList.Selected = nil then Exit;
  Idx := FList.Selected.Index;
  if (Idx < 0) or (Idx >= Length(FItems)) then Exit;
  FResult := Format('%s:%d',
    [FItems[Idx].FilePath, FItems[Idx].Line]);
  FForm.ModalResult := mrOk;
end;

procedure TSymbolSearchHandler.ListDblClick(Sender: TObject);
begin
  Accept;
end;

procedure TSymbolSearchHandler.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = 13 then
  begin
    Key := 0;
    Accept;
  end
  else if Key = 27 then
  begin
    Key := 0;
    FResult := '';
    FForm.ModalResult := mrCancel;
  end;
end;

{ ---- ShowSymbolSearch ---- }

function ShowSymbolSearch(const AExePath, ADbPath: string): string;
var
  Form:      TForm;
  Edit:      TEdit;
  List:      TListView;
  LblStatus: TLabel;
  Handler:   TSymbolSearchHandler;
  Col:       TListColumn;
const
  FORM_W = 620;
  FORM_H = 480;
  MARGIN = 8;
  EDIT_H = 24;
  STAT_H = 20;
begin
  Result := '';
  Form := TForm.Create(nil);
  try
    Form.Caption     := 'drag-lint Symbol Search';
    Form.BorderStyle := bsDialog;
    Form.Position    := poScreenCenter;
    Form.Width       := FORM_W;
    Form.Height      := FORM_H;
    Form.KeyPreview  := True;

    Edit := TEdit.Create(Form);
    Edit.Parent    := Form;
    Edit.Left      := MARGIN;
    Edit.Top       := MARGIN;
    Edit.Width     := FORM_W - MARGIN * 2 - 16;
    Edit.Height    := EDIT_H;
    Edit.Anchors   := [akLeft, akTop, akRight];
    Edit.TextHint  := 'Type symbol name...';

    List := TListView.Create(Form);
    List.Parent      := Form;
    List.Left        := MARGIN;
    List.Top         := MARGIN + EDIT_H + 6;
    List.Width       := FORM_W - MARGIN * 2 - 16;
    List.Height      := FORM_H - MARGIN * 3 - EDIT_H - STAT_H - 32;
    List.Anchors     := [akLeft, akTop, akRight, akBottom];
    List.ViewStyle   := vsReport;
    List.ReadOnly    := True;
    List.FullDrag    := False;
    List.HideSelection := False;
    List.RowSelect   := True;

    Col := List.Columns.Add;
    Col.Caption := 'Qualified Name';
    Col.Width   := 240;

    Col := List.Columns.Add;
    Col.Caption := 'Kind';
    Col.Width   := 80;

    Col := List.Columns.Add;
    Col.Caption := 'Location';
    Col.Width   := 260;

    LblStatus := TLabel.Create(Form);
    LblStatus.Parent   := Form;
    LblStatus.Left     := MARGIN;
    LblStatus.Top      := FORM_H - STAT_H - MARGIN - 16;
    LblStatus.Width    := FORM_W - MARGIN * 2 - 16;
    LblStatus.Anchors  := [akLeft, akBottom, akRight];
    LblStatus.Caption  := 'Type to search...';
    LblStatus.AutoSize := False;

    Handler := TSymbolSearchHandler.Create(Form, Form, Edit, List, LblStatus,
      AExePath, ADbPath);

    if Form.ShowModal = mrOk then
      Result := Handler.GetResult;
  finally
    Form.Free;
  end;
end;

end.
