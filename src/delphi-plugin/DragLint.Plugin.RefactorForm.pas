unit DragLint.Plugin.RefactorForm;

{ Refactor preview form for drag-lint rename symbol.
  Replaces the two-InputBox flow with a richer dialog that supports
  dry-run preview and a one-click apply.
  Call ShowRefactorDialog() from the main IDE thread only. }

interface

uses
  System.Classes, System.SysUtils,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.Dialogs;

procedure ShowRefactorDialog(const ASuggestedQName: string;
  const AProjectDb: string; const AExePath: string);

implementation

uses
  Winapi.Windows, Winapi.Messages,
  Vcl.Graphics;

{ ---- TRefactorHandler ---- }

type
  TRefactorHandler = class(TComponent)
  private
    FForm:      TForm;
    FEdQName:   TEdit;
    FEdNewName: TEdit;
    FCbBackup:  TCheckBox;
    FMemo:      TMemo;
    FBtnApply:  TButton;
    FBtnClose:  TButton;
    FExePath:   string;
    FProjectDb: string;
    FPreviewOk: Boolean;
    function RunRename(ADryRun: Boolean; out AOutput: string): Boolean;
  public
    constructor Create(AOwner: TComponent; AForm: TForm;
      AEdQName, AEdNewName: TEdit; ACbBackup: TCheckBox;
      AMemo: TMemo; ABtnApply, ABtnClose: TButton;
      const AExePath, AProjectDb: string); reintroduce;
    procedure DoPreview(Sender: TObject);
    procedure DoApply(Sender: TObject);
    procedure DoClose(Sender: TObject);
  end;

constructor TRefactorHandler.Create(AOwner: TComponent; AForm: TForm;
  AEdQName, AEdNewName: TEdit; ACbBackup: TCheckBox;
  AMemo: TMemo; ABtnApply, ABtnClose: TButton;
  const AExePath, AProjectDb: string);
begin
  inherited Create(AOwner);
  FForm      := AForm;
  FEdQName   := AEdQName;
  FEdNewName := AEdNewName;
  FCbBackup  := ACbBackup;
  FMemo      := AMemo;
  FBtnApply  := ABtnApply;
  FBtnClose  := ABtnClose;
  FExePath   := AExePath;
  FProjectDb := AProjectDb;
  FPreviewOk := False;
end;

function TRefactorHandler.RunRename(ADryRun: Boolean;
  out AOutput: string): Boolean;
var
  SA:          TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  SI:          TStartupInfoW;
  PI:          TProcessInformation;
  Buf:         array[0..4095] of AnsiChar;
  BytesRead:   DWORD;
  ExitCode:    DWORD;
  CmdLine:     string;
  WideCmd:     string;
  SB:          TStringBuilder;
const
  TIMEOUT_MS = 60000;
begin
  Result  := False;
  AOutput := '';

  { Build command line }
  CmdLine := Format('"%s" rename --qname "%s" --to "%s"',
    [FExePath, FEdQName.Text, FEdNewName.Text]);
  if FProjectDb <> '' then
    CmdLine := CmdLine + Format(' --db "%s"', [FProjectDb]);
  if ADryRun then
    CmdLine := CmdLine + ' --dry-run';
  if not FCbBackup.Checked then
    CmdLine := CmdLine + ' --no-backup';

  SA.nLength              := SizeOf(SA);
  SA.bInheritHandle       := True;
  SA.lpSecurityDescriptor := nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then
    Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb         := SizeOf(SI);
    SI.dwFlags    := STARTF_USESTDHANDLES;
    SI.hStdOutput := WritePipe;
    SI.hStdError  := WritePipe;
    SI.hStdInput  := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd := CmdLine;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd),
       nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      AOutput := 'Failed to spawn: ' + CmdLine;
      Exit;
    end;
    CloseHandle(WritePipe);
    SB := TStringBuilder.Create;
    try
      repeat
        BytesRead := 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then
          Break;
        if BytesRead = 0 then
          Break;
        Buf[BytesRead] := #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;
    WaitForSingleObject(PI.hProcess, TIMEOUT_MS);
    GetExitCodeProcess(PI.hProcess, ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
    Result := (Integer(ExitCode) = 0);
  finally
    CloseHandle(ReadPipe);
  end;
end;

procedure TRefactorHandler.DoPreview(Sender: TObject);
var
  Output: string;
  Ok:     Boolean;
begin
  if Trim(FEdQName.Text) = '' then
  begin
    ShowMessage('drag-lint: Symbol qname must not be empty.');
    FEdQName.SetFocus;
    Exit;
  end;
  if Trim(FEdNewName.Text) = '' then
  begin
    ShowMessage('drag-lint: New name must not be empty.');
    FEdNewName.SetFocus;
    Exit;
  end;

  FMemo.Lines.Text := '(running dry-run...)';
  FBtnApply.Enabled := False;
  FPreviewOk        := False;
  FMemo.Update;

  Ok := RunRename(True, Output);
  FMemo.Lines.Text := Output;
  FPreviewOk        := Ok;
  FBtnApply.Enabled := Ok;
  FBtnClose.Caption := 'Cancel';
end;

procedure TRefactorHandler.DoApply(Sender: TObject);
var
  Output: string;
  Ok:     Boolean;
begin
  if MessageDlg(
    Format('Apply rename ''%s'' -> ''%s''?'#13#10 +
      'This will modify source files on disk.',
      [FEdQName.Text, FEdNewName.Text]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  FMemo.Lines.Text := '(applying...)';
  FBtnApply.Enabled := False;
  FMemo.Update;

  Ok := RunRename(False, Output);
  FMemo.Lines.Text := Output;

  if Ok then
  begin
    FBtnClose.Caption := 'Close';
    ShowMessage('drag-lint: Rename applied successfully.');
    FForm.ModalResult := mrOk;
  end
  else
  begin
    FBtnApply.Enabled := True;
    ShowMessage('drag-lint: Rename apply failed. See output for details.');
  end;
end;

procedure TRefactorHandler.DoClose(Sender: TObject);
begin
  FForm.ModalResult := mrCancel;
end;

{ ---- ShowRefactorDialog ---- }

procedure ShowRefactorDialog(const ASuggestedQName: string;
  const AProjectDb: string; const AExePath: string);
var
  Form:      TForm;
  Handler:   TRefactorHandler;
  edQName:   TEdit;
  edNewName: TEdit;
  cbBackup:  TCheckBox;
  memOutput: TMemo;
  btnPreview, btnApply, btnClose: TButton;
  lblQName, lblNewName: TLabel;
  Y: Integer;
const
  FORM_W = 600;
  FORM_H = 480;
  MARGIN = 12;
  LBL_H  = 18;
  EDIT_H = 24;
  BTN_H  = 28;
  BTN_W  = 90;
  CHK_H  = 24;
begin
  Form := TForm.Create(nil);
  try
    Form.Caption     := 'drag-lint Rename Symbol';
    Form.BorderStyle := bsDialog;
    Form.Position    := poScreenCenter;
    Form.Width       := FORM_W;
    Form.Height      := FORM_H;
    Form.KeyPreview  := True;

    Y := MARGIN;

    { Symbol qname label + edit }
    lblQName        := TLabel.Create(Form);
    lblQName.Parent  := Form;
    lblQName.Caption := 'Symbol qname:';
    lblQName.Left    := MARGIN;
    lblQName.Top     := Y;
    lblQName.AutoSize := True;
    Inc(Y, LBL_H + 2);

    edQName        := TEdit.Create(Form);
    edQName.Parent  := Form;
    edQName.Left    := MARGIN;
    edQName.Top     := Y;
    edQName.Width   := FORM_W - MARGIN * 2 - 16;
    edQName.Text    := ASuggestedQName;
    Inc(Y, EDIT_H + 8);

    { New name label + edit }
    lblNewName        := TLabel.Create(Form);
    lblNewName.Parent  := Form;
    lblNewName.Caption := 'New name:';
    lblNewName.Left    := MARGIN;
    lblNewName.Top     := Y;
    lblNewName.AutoSize := True;
    Inc(Y, LBL_H + 2);

    edNewName        := TEdit.Create(Form);
    edNewName.Parent  := Form;
    edNewName.Left    := MARGIN;
    edNewName.Top     := Y;
    edNewName.Width   := FORM_W - MARGIN * 2 - 16;
    Inc(Y, EDIT_H + 8);

    { Write .bak backup checkbox }
    cbBackup          := TCheckBox.Create(Form);
    cbBackup.Parent   := Form;
    cbBackup.Caption  := 'Write .bak backup before applying';
    cbBackup.Left     := MARGIN;
    cbBackup.Top      := Y;
    cbBackup.Width    := FORM_W - MARGIN * 2 - 16;
    cbBackup.Checked  := True;
    Inc(Y, CHK_H + 6);

    { Output memo (fills the middle; bottom reserved for buttons) }
    memOutput             := TMemo.Create(Form);
    memOutput.Parent      := Form;
    memOutput.Left        := MARGIN;
    memOutput.Top         := Y;
    memOutput.Width       := FORM_W - MARGIN * 2 - 16;
    memOutput.Height      := FORM_H - Y - BTN_H - MARGIN * 4 - 16;
    memOutput.ReadOnly    := True;
    memOutput.ScrollBars  := ssBoth;
    memOutput.WordWrap    := False;
    memOutput.Font.Name   := 'Consolas';
    memOutput.Font.Size   := 9;
    memOutput.Anchors     := [akLeft, akTop, akRight, akBottom];

    { Bottom buttons }
    btnPreview          := TButton.Create(Form);
    btnPreview.Parent   := Form;
    btnPreview.Caption  := 'Preview (dry-run)';
    btnPreview.Width    := 120;
    btnPreview.Height   := BTN_H;
    btnPreview.Left     := MARGIN;
    btnPreview.Anchors  := [akLeft, akBottom];
    btnPreview.Top      := FORM_H - BTN_H - MARGIN * 2 - 16;

    btnApply          := TButton.Create(Form);
    btnApply.Parent   := Form;
    btnApply.Caption  := 'Apply';
    btnApply.Width    := BTN_W;
    btnApply.Height   := BTN_H;
    btnApply.Left     := FORM_W - MARGIN * 2 - 16 - BTN_W * 2 - 8;
    btnApply.Anchors  := [akRight, akBottom];
    btnApply.Top      := FORM_H - BTN_H - MARGIN * 2 - 16;
    btnApply.Enabled  := False;

    btnClose          := TButton.Create(Form);
    btnClose.Parent   := Form;
    btnClose.Caption  := 'Cancel';
    btnClose.Width    := BTN_W;
    btnClose.Height   := BTN_H;
    btnClose.Left     := FORM_W - MARGIN * 2 - 16 - BTN_W;
    btnClose.Anchors  := [akRight, akBottom];
    btnClose.Top      := FORM_H - BTN_H - MARGIN * 2 - 16;
    btnClose.Cancel   := True;

    { Wire handler (owned by Form, freed with it) }
    Handler := TRefactorHandler.Create(Form, Form,
      edQName, edNewName, cbBackup, memOutput, btnApply, btnClose,
      AExePath, AProjectDb);

    btnPreview.OnClick := Handler.DoPreview;
    btnApply.OnClick   := Handler.DoApply;
    btnClose.OnClick   := Handler.DoClose;

    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
