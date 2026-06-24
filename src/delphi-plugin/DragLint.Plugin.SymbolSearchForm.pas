unit DragLint.Plugin.SymbolSearchForm;

{ v0.33 Symbol Search form.
  Modal TForm with a debounced TEdit that queries drag-lint for symbols
  matching the typed text.  Enter on a selected row returns the location
  as "file:line"; ESC returns empty string.

  Call ShowSymbolSearch() from the main IDE thread only. }

interface

uses
  System.Classes
  , Vcl.Controls
  ;

function ShowSymbolSearch(const AExePath, ADbPath: string): string;

{ v0.42: build the symbol-search UI embedded in a dock-panel tab (non-modal).
  Double-click / Enter opens the symbol's source instead of returning a result.
  ADbArgs is a pre-built ' --db "x" --db "y"' string (multi-DB). }
procedure CreateEmbeddedSymbolSearch(AOwner: TComponent; AParent: TWinControl; const AExePath, ADbArgs: string);

implementation

uses
  System.SysUtils
  , Vcl.Forms
  , Vcl.ComCtrls
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Winapi.Windows
  , ToolsAPI
  , DragLint.Plugin.HoverForm
  , DragLint.Plugin.ProcRun
  ; { OpenSourceAt }

{ ---- TSymbolSearchForm ---- }

type
  TSymbolItem = record
    QName   : string ;
    Kind    : string ;
    FilePath: string ;
    Line    : Integer;
  end;

  TSymbolSearchHandler = class(TComponent)
    private
      FForm     : TForm               ;
      FEdit     : TEdit               ;
      FList     : TListView           ;
      FLblStatus: TLabel              ;
      FTimer    : TTimer              ;
      FExePath  : string              ;
      FDbPath   : string              ;
      FDbArgs   : string              ; { v0.42: full ' --db "..." --db "..."' (multi-DB) }
      FEmbedded : Boolean             ; { v0.42: tab mode -> open source instead of modal }
      FResult   : string              ;
      FItems    : array of TSymbolItem;
      procedure TimerFired  (Sender: TObject);
      procedure EditChange  (Sender: TObject);
      procedure ListDblClick(Sender: TObject);
      procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure Accept;
      procedure RunSearch(const AText: string);
    public
      constructor Create(AOwner: TComponent; AForm: TForm; AEdit: TEdit; AList: TListView; ALblStatus: TLabel; const AExePath, ADbPath: string); reintroduce;
      function GetResult: string;
  end;

{ ---- TSymbolSearchHandler ---- }

constructor TSymbolSearchHandler.Create(AOwner: TComponent; AForm: TForm; AEdit: TEdit; AList: TListView; ALblStatus: TLabel; const AExePath, ADbPath: string);
begin
  inherited Create(AOwner);
  FForm     := AForm;
  FEdit     := AEdit;
  FList     := AList;
  FLblStatus:= ALblStatus;
  FExePath  := AExePath;
  FDbPath   := ADbPath;
  if ADbPath <> '' then FDbArgs:= Format(' --db "%s"', [ADbPath])
  else FDbArgs:= '';
  FEmbedded:= False;
  FResult  := '';

  FTimer:= TTimer.Create(Self);
  FTimer.Interval:= 300;
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerFired;

  FEdit.OnChange  := EditChange;
  FList.OnDblClick:= ListDblClick;
  if FForm <> nil then FForm.OnKeyDown:= FormKeyDown;

  { v0.49: opt these controls out of VCL Styles so their WndProc/paint never calls
    TStyleManager.GetStyle -- that AV'd inside the IDE's theme engine during the
    search timer's repaint (under some IDE themes / RDP). Best-effort + guarded. }
  try
    if FForm      <> nil then FForm.StyleElements      := [];
    if FEdit      <> nil then FEdit.StyleElements      := [];
    if FList      <> nil then FList.StyleElements      := [];
    if FLblStatus <> nil then FLblStatus.StyleElements := [];
  except
  end;
end; // constructor

function TSymbolSearchHandler.GetResult: string;
begin
  Result:= FResult;
end;

procedure TSymbolSearchHandler.EditChange(Sender: TObject);
begin
  FTimer.Enabled:= False;
  FTimer.Enabled:= True;
end;

procedure TSymbolSearchHandler.TimerFired(Sender: TObject);
begin
  FTimer.Enabled:= False;
  RunSearch(FEdit.Text);
end;

procedure TSymbolSearchHandler.RunSearch(const AText: string);
var
  CmdLine : string        ;
  Output  : string        ;
  ExitCode: Integer       ;
  Lines   : TStringList   ;
  i       : Integer       ;
  j       : Integer       ;
  Count   : Integer       ;
  Line    : string        ;
  Parts   : TArray<string>;
  Location: string        ;
  ColonPos: Integer       ;
  Item    : TListItem     ;
begin
  { v0.49: defensive -- the timer can fire after the form/controls are gone, and
    the IDE's VCL Styles (TStyleManager.GetStyle) can AV during a styled repaint
    of these controls under some themes / RDP. Guard nils and NEVER force a
    synchronous repaint here (FForm.Update was the AV trigger), and wrap every
    caption set so a theming fault can't crash the IDE. }
  if (FList = nil) or (FLblStatus = nil) then Exit;
  if (FExePath = '') or (Trim(AText) = '') then
  begin
    FList.Items.Clear;
    SetLength(FItems, 0);
    try FLblStatus.Caption:= 'Type to search...'; except end;
    Exit;
  end;

  try FLblStatus.Caption:= 'Searching...'; except end;

  CmdLine:= Format('"%s" query --name "%s"', [FExePath, Trim(AText)]) + FDbArgs;

  ExitCode:= RunCaptureStdout(CmdLine, Output, 15000);

  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    SetLength(FItems, 0);

    if ExitCode < 0 then
    begin
      try FLblStatus.Caption:= 'Failed to spawn drag-lint.exe'; except end;
      Exit;
    end;

    Lines:= TStringList.Create;
    try
      Lines.Text:= Output;
      Count:= 0;
      for i:= 0 to Lines.Count - 1 do
      begin
        if Count >= 30 then Break;
        Line:= Trim(Lines[i]);
        if Line = '' then Continue;

        { Expected text format: <qname>  [<kind>]  <file>:<line>
          Split on two or more spaces }
        Parts:= Line.Split(['  '], TStringSplitOptions.ExcludeEmpty);
        if Length(Parts) < 3 then Continue;

        { Find location (last part that looks like file:N) }
        Location:= Trim(Parts[Length(Parts) - 1]);
        ColonPos:= 0;
        for j:= Length(Location) downto 1 do
          if Location[j] = ':' then
          begin
            ColonPos:= j;
            Break;
          end;

        SetLength(FItems, Count + 1);
        FItems[Count].QName:= Trim(Parts[0]);
        FItems[Count].Kind := Trim(Parts[1]);
        if ColonPos > 0 then
        begin
          FItems[Count].FilePath:= Copy(Location, 1, ColonPos - 1);
          FItems[Count].Line:= StrToIntDef( Copy(Location, ColonPos + 1, MaxInt), 0);
        end
        else
        begin
          FItems[Count].FilePath:= Location;
          FItems[Count].Line    := 0;
        end;

        Item:= FList.Items.Add;
        Item.Caption:= FItems[Count].QName;
        Item.SubItems.Add(FItems[Count].Kind);
        Item.SubItems.Add(Format('%s:%d', [ExtractFileName(FItems[Count].FilePath), FItems[Count].Line]));
        Inc(Count);
      end; // for

      try FLblStatus.Caption:= Format('%d result(s)', [Count]); except end;
    finally
      Lines.Free;
    end; // try
  finally
    FList.Items.EndUpdate;
  end; // try
end; // procedure

procedure TSymbolSearchHandler.Accept;
var
  Idx: Integer;
begin
  if FList.Selected = nil then Exit;
  Idx:= FList.Selected.Index;
  if (Idx < 0) or (Idx >= Length(FItems)) then Exit;
  if FEmbedded then
  begin
    { tab mode: jump the editor straight to the symbol's definition }
    if FItems[Idx].FilePath <> '' then OpenSourceAt(FItems[Idx].FilePath, FItems[Idx].Line);
    Exit;
  end;
  FResult:= Format('%s:%d', [FItems[Idx].FilePath, FItems[Idx].Line]);
  if FForm <> nil then FForm.ModalResult:= mrOk;
end;

procedure TSymbolSearchHandler.ListDblClick(Sender: TObject);
begin
  Accept;
end;

procedure TSymbolSearchHandler.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = 13 then
  begin
    Key:= 0;
    Accept;
  end
  else if Key = 27 then
  begin
    Key    := 0;
    FResult:= '';
    FForm.ModalResult:= mrCancel;
  end;
end;

{ ---- ShowSymbolSearch ---- }

function ShowSymbolSearch(const AExePath, ADbPath: string): string;
var
  Form     : TForm               ;
  Edit     : TEdit               ;
  List     : TListView           ;
  LblStatus: TLabel              ;
  Handler  : TSymbolSearchHandler;
  Col      : TListColumn         ;
const
  FORM_W = 620;
  FORM_H = 480;
  MARGIN = 8;
  EDIT_H = 24;
  STAT_H = 20;
begin
  Result:= '';
  Form:= TForm.Create(nil);
  try
    Form.Caption    := 'drag-lint Symbol Search';
    Form.BorderStyle:= bsDialog;
    Form.Position   := poScreenCenter;
    Form.Width      := FORM_W;
    Form.Height     := FORM_H;
    Form.KeyPreview := True;

    Edit:= TEdit.Create(Form);
    Edit.Parent:= Form;
    Edit.Left  := MARGIN;
    Edit.Top   := MARGIN;
    Edit.Width:= FORM_W - MARGIN * 2 - 16;
    Edit.Height:= EDIT_H;
    Edit.Anchors:= [akLeft, akTop, akRight];
    Edit.TextHint:= 'Type symbol name...';

    List:= TListView.Create(Form);
    List.Parent:= Form;
    List.Left  := MARGIN;
    List.Top:= MARGIN + EDIT_H + 6;
    List.Width:= FORM_W - MARGIN * 2 - 16;
    List.Height:= FORM_H - MARGIN * 3 - EDIT_H - STAT_H - 32;
    List.Anchors:= [akLeft, akTop, akRight, akBottom];
    List.ViewStyle    := vsReport;
    List.ReadOnly     := True;
    List.FullDrag     := False;
    List.HideSelection:= False;
    List.RowSelect    := True;

    Col:= List.Columns.Add;
    Col.Caption:= 'Qualified Name';
    Col.Width  := 240;

    Col:= List.Columns.Add;
    Col.Caption:= 'Kind';
    Col.Width  := 80;

    Col:= List.Columns.Add;
    Col.Caption:= 'Location';
    Col.Width  := 260;

    LblStatus:= TLabel.Create(Form);
    LblStatus.Parent:= Form;
    LblStatus.Left  := MARGIN;
    LblStatus.Top:= FORM_H - STAT_H - MARGIN - 16;
    LblStatus.Width:= FORM_W - MARGIN * 2 - 16;
    LblStatus.Anchors:= [akLeft, akBottom, akRight];
    LblStatus.Caption := 'Type to search...';
    LblStatus.AutoSize:= False;

    Handler:= TSymbolSearchHandler.Create(Form, Form, Edit, List, LblStatus, AExePath, ADbPath);

    if Form.ShowModal = mrOk then Result:= Handler.GetResult;
  finally
    Form.Free;
  end; // try
end; // function

{ ---- CreateEmbeddedSymbolSearch (dock tab) ---- }

procedure CreateEmbeddedSymbolSearch(AOwner: TComponent; AParent: TWinControl; const AExePath, ADbArgs: string);
var
  Edit     : TEdit               ;
  List     : TListView           ;
  LblStatus: TLabel              ;
  Handler  : TSymbolSearchHandler;
  Col      : TListColumn         ;
begin
  Edit:= TEdit.Create(AOwner);
  Edit.Parent  := AParent;
  Edit.Align   := alTop;
  Edit.TextHint:= 'Type symbol name...';

  LblStatus:= TLabel.Create(AOwner);
  LblStatus.Parent  := AParent;
  LblStatus.Align   := alBottom;
  LblStatus.Layout  := tlCenter;
  LblStatus.Caption := 'Type to search...';
  LblStatus.AutoSize:= False;
  LblStatus.Height  := 18;

  List:= TListView.Create(AOwner);
  List.Parent       := AParent;
  List.Align        := alClient;
  List.ViewStyle    := vsReport;
  List.ReadOnly     := True;
  List.HideSelection:= False;
  List.RowSelect    := True;

  Col:= List.Columns.Add; Col.Caption:= 'Qualified Name'; Col.Width:= 240;
  Col:= List.Columns.Add; Col.Caption:= 'Kind'          ; Col.Width:= 80;
  Col:= List.Columns.Add; Col.Caption:= 'Location'      ; Col.Width:= 260;

  { Owner = AOwner so the handler lives as long as the dock frame. FForm = nil
    (no modal host); double-click opens the source via OpenSourceAt. }
  Handler:= TSymbolSearchHandler.Create(AOwner, nil, Edit, List, LblStatus, AExePath, '');
  Handler.FDbArgs  := ADbArgs;
  Handler.FEmbedded:= True;
end; // procedure

end.
