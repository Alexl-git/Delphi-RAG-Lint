unit DragLint.Plugin.RefactorForm;

{ Refactor preview forms for drag-lint rename symbol and extract method.
  Replaces the two-InputBox flow with a richer dialog that supports
  dry-run preview and a one-click apply.
  Call ShowRefactorDialog() / ShowExtractMethodDialog() from the main IDE
  thread only. }

interface

uses
  System.Classes
  , System.SysUtils
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.Controls
  , Vcl.ExtCtrls
  , Vcl.Dialogs
  ;

type
  /// <summary>Receives one refactor CLI run's result on the MAIN thread.</summary>
  /// <param name="AExitCode">The child's exit code; ProcRun's PROCRUN_TIMED_OUT_EXIT_CODE
  /// when it was killed for making no progress; -1 when it could not start.</param>
  /// <param name="AOutput">stdout and stderr, interleaved (a CLI refusal included).</param>
  TRefactorRunDone = reference to procedure(AExitCode: Integer; const AOutput: string);

const
  /// <summary>STALL budget of a refactor CLI run (ProcRun semantics): the child is
  /// killed only after this long with neither output nor CPU. A run that keeps
  /// working is never cut short -- its answer is always delivered.</summary>
  REFACTOR_STALL_MS = 60000;

/// <summary>Runs one drag-lint refactor command line on a worker thread and hands
/// the result to ADone on the main thread (IDE-HANG, 1.40).</summary>
/// <param name="ACmdLine">Full command line, as CreateProcessW takes it.</param>
/// <param name="ADone">Called exactly once, on the main thread, however late.</param>
/// <param name="AStallMs">Stall budget; defaults to REFACTOR_STALL_MS.</param>
/// <remarks>Never waits: returns before the child is spawned. The dialogs keep
/// pumping messages meanwhile and refuse to close until ADone has run.</remarks>
procedure RunRefactorCliAsync(const ACmdLine: string; const ADone: TRefactorRunDone; AStallMs: Integer = REFACTOR_STALL_MS);  // dl:ok unused-public-symbol@f8e3 -- public as the test seam: LspNonBlockingTests R1-R3 drive it (not in the plugin index)

/// <summary>Shows the drag-lint Rename Symbol preview dialog (modal).</summary>
/// <param name="ASuggestedQName">Initial symbol qname (the Symbol field). The
/// rename verb needs the QUALIFIED name; callers pass the typeat-resolved name
/// of the symbol under the caret, or '' to let the user type it.</param>
/// <param name="AProjectDb">Project database ('' = the exe's default resolution).</param>
/// <param name="AExePath">Path to drag-lint.exe.</param>
/// <param name="ASuggestedNewName">Initial text of the New name field ('' = empty);
/// the caller passes the bare identifier under the caret so the user edits it.</param>
/// <param name="AFromFile">File the symbol was picked from ('' = unknown); passed to the rename verb as --in so a not-found answer ranks candidates from that file first.</param>
/// <remarks>Main thread only. Preview / Apply run the CLI off the main thread.</remarks>
procedure ShowRefactorDialog(const ASuggestedQName: string; const AProjectDb: string; const AExePath: string; const ASuggestedNewName: string = ''; const AFromFile: string = '');

/// <summary>Builds the rename command line the dialog runs.</summary>
/// <param name="AExePath">drag-lint.exe.</param>
/// <param name="AQName">Qualified symbol name.</param>
/// <param name="ANewName">New identifier.</param>
/// <param name="ADb">Project DB ('' = omit --db).</param>
/// <param name="AFromFile">Active file ('' = omit --in).</param>
/// <param name="ADryRun">Append --dry-run.</param>
/// <param name="ABackup">False appends --no-backup.</param>
/// <returns>The full command line.</returns>
/// <remarks>Pure.</remarks>
function DLRenameCmdLine(const AExePath, AQName, ANewName, ADb, AFromFile: string; ADryRun, ABackup: Boolean): string;

/// <summary>Reads the symbol the typeat verb resolved from its JSON answer.</summary>
/// <param name="AOutput">Captured text of `typeat ... --format json` (stderr may
/// be merged in, so text before the first `{` is ignored).</param>
/// <param name="AToken">Receives the bare identifier under the caret ('' when absent).</param>
/// <returns>The `resolved` qualified name, or '' when the output is not JSON, the
/// token did not resolve, or `resolved` is missing / empty.</returns>
/// <remarks>Pure; never raises.</remarks>
function DLParseTypeAtResolved(const AOutput: string; out AToken: string): string;

/// <summary>Shows the drag-lint Extract Method preview dialog for a fixed
/// source range [AFromLine..AToLine] in AFilePath. Prompts for the new
/// method name, runs "extract-method --dry-run" for a preview, and lets
/// the user Apply (re-runs with --apply, honoring the backup checkbox).
/// A refuse reason from the CLI (stderr, exit 2) surfaces in the preview
/// memo exactly like a successful dry-run render.</summary>
/// <param name="AFilePath">Absolute path of the file to modify; must be the
/// on-disk (saved) content the CLI will read -- caller must save first.</param>
/// <param name="AFromLine">1-based inclusive start line of the selection.</param>
/// <param name="AToLine">1-based inclusive end line of the selection.</param>
/// <param name="AExePath">Path to drag-lint.exe (caller resolves it).</param>
/// <returns>True iff Apply completed successfully (exit 0), signalling the
/// caller should reload the buffer from disk. False if the user cancelled
/// or Apply did not succeed.</returns>
/// <remarks>Call from the main IDE thread only (creates/shows a TForm).</remarks>
function ShowExtractMethodDialog(const AFilePath: string; AFromLine, AToLine: Integer; const AExePath: string): Boolean;

implementation

uses
  Winapi.Windows
  , Winapi.Messages
  , Vcl.Graphics
  , System.Generics.Collections
  , System.JSON
  , DragLint.Plugin.ProcRun  { RunCaptureStdout -- stall-bounded spawn } // dl:unit DragLint.Plugin.ProcRun accepted -- PROCRUN_TIMED_OUT_EXIT_CODE is the exit code RunCaptureStdout returns on a stall; it travels with the spawn this unit calls
  , DragLint.Plugin.Telemetry { DLT }
  ;

const
  MSEC_PER_SEC = 1000;   { for the stall-budget message }

procedure RunRefactorCliAsync(const ACmdLine: string; const ADone: TRefactorRunDone; AStallMs: Integer);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Output: string;
      Code  : Integer;
    begin
      Code  := -1;   { what ADone sees if the run raises }
      Output:= '';
      try
        Code:= RunCaptureStdout(ACmdLine, Output, AStallMs);
      except
        on E: Exception do
        begin
          DLT('refactor', 'refactor run raised ' + E.ClassName + ': ' + E.Message);
          Output:= 'drag-lint: the run raised ' + E.ClassName + ': ' + E.Message;
        end;
      end;
      { Reached whatever the run did (every Exception is caught above): ADone
        must run, or the dialog would stay busy for good. }
      TThread.Queue(nil, procedure begin ADone(Code, Output); end);
    end).Start;
end;

{ ---- TCliDialogHandler: the shared busy state of both dialogs ---- }

var
  { Every live handler; main thread only. A late answer reaches only a handler
    still listed (its dialog has not been freed). }
  GLiveHandlers: TList<TObject> = nil;

type
  TCliDialogHandler = class(TComponent)
    protected
      FForm    : TForm  ;
      FMemo    : TMemo  ;
      FBtnApply: TButton;
      FBtnClose: TButton;
      FBusy    : Boolean;
      { Starts ACmdLine off the main thread; shows ABusyText and disables Apply
        and Close until ADone has run. False (nothing started) while busy. }
      function RunAsync(const ACmdLine, ABusyText: string; const ADone: TRefactorRunDone): Boolean;
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      { The dialog cannot close while a run is in flight: its answer -- above
        all an APPLY's -- must be shown, never dropped. }
      procedure DoCloseQuery(Sender: TObject; var CanClose: Boolean);
  end;

constructor TCliDialogHandler.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  if GLiveHandlers <> nil then GLiveHandlers.Add(Self);
end;

destructor TCliDialogHandler.Destroy;
begin
  if GLiveHandlers <> nil then GLiveHandlers.Remove(Self);
  inherited Destroy;
end;

function TCliDialogHandler.RunAsync(const ACmdLine, ABusyText: string; const ADone: TRefactorRunDone): Boolean;
var
  Me: TObject;
begin
  Result:= not FBusy;
  if not Result then Exit;
  FBusy:= True;
  FMemo.Lines.Text := ABusyText;
  FBtnApply.Enabled:= False;
  FBtnClose.Enabled:= False;
  Screen.Cursor    := crAppStart;
  Me:= Self;
  RunRefactorCliAsync(ACmdLine,
    procedure(AExitCode: Integer; const AOutput: string)
    begin
      Screen.Cursor:= crDefault;
      if (GLiveHandlers = nil) or not GLiveHandlers.Contains(Me) then Exit;
      FBusy:= False;
      FBtnClose.Enabled:= True;
      FMemo.Lines.Text:= if AExitCode = PROCRUN_TIMED_OUT_EXIT_CODE then
                           AOutput + sLineBreak + Format('(drag-lint made no progress for %d s and was stopped)', [REFACTOR_STALL_MS div MSEC_PER_SEC])
                         else AOutput;
      ADone(AExitCode, AOutput);
    end);
end;

procedure TCliDialogHandler.DoCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose:= not FBusy;
end;


{ ---- TRefactorHandler ---- }

type
  TRefactorHandler = class(TCliDialogHandler)
    private
      FEdQName  : TEdit    ;
      FEdNewName: TEdit    ;
      FCbBackup : TCheckBox;
      FExePath  : string   ;
      FProjectDb: string   ;
      FFromFile : string   ;
      FPreviewOk: Boolean  ;
      function RenameCmdLine(ADryRun: Boolean): string;
    public
      constructor Create(
        AOwner: TComponent; AForm: TForm; AEdQName, AEdNewName: TEdit; ACbBackup: TCheckBox; AMemo: TMemo; ABtnApply, ABtnClose: TButton; const AExePath, AProjectDb, AFromFile: string
      ); reintroduce;
      procedure DoPreview(Sender: TObject);
      procedure DoApply  (Sender: TObject);
      procedure DoClose  (Sender: TObject);
  end;

constructor TRefactorHandler.Create(
  AOwner: TComponent; AForm: TForm; AEdQName, AEdNewName: TEdit; ACbBackup: TCheckBox; AMemo: TMemo; ABtnApply, ABtnClose: TButton; const AExePath, AProjectDb, AFromFile: string);
begin
  inherited Create(AOwner);
  FForm     := AForm;
  FEdQName  := AEdQName;
  FEdNewName:= AEdNewName;
  FCbBackup := ACbBackup;
  FMemo     := AMemo;
  FBtnApply := ABtnApply;
  FBtnClose := ABtnClose;
  FExePath  := AExePath;
  FProjectDb:= AProjectDb;
  FFromFile := AFromFile;
  FPreviewOk:= False;
end;

function DLRenameCmdLine(const AExePath, AQName, ANewName, ADb, AFromFile: string; ADryRun, ABackup: Boolean): string;
begin
  Result:= Format('"%s" rename --qname "%s" --to "%s"', [AExePath, AQName, ANewName]);
  if ADb <> '' then Result:= Result + Format(' --db "%s"', [ADb]);
  if AFromFile <> '' then Result:= Result + Format(' --in "%s"', [AFromFile]);
  if ADryRun then Result:= Result + ' --dry-run';
  if not ABackup then Result:= Result + ' --no-backup';
end;

function TRefactorHandler.RenameCmdLine(ADryRun: Boolean): string;
begin
  Result:= DLRenameCmdLine(FExePath, FEdQName.Text, FEdNewName.Text, FProjectDb, FFromFile, ADryRun, FCbBackup.Checked);
end;

procedure TRefactorHandler.DoPreview(Sender: TObject);
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

  FPreviewOk:= False;
  RunAsync(RenameCmdLine(True), '(running dry-run...)',
    procedure(AExitCode: Integer; const AOutput: string)
    begin
      FPreviewOk:= AExitCode = 0;
      FBtnApply.Enabled:= FPreviewOk;
      FBtnClose.Caption:= 'Cancel';
    end);
end; // procedure

procedure TRefactorHandler.DoApply(Sender: TObject);
begin
  if MessageDlg( Format('Apply rename ''%s'' -> ''%s''?'#13#10 + 'This will modify source files on disk.', [FEdQName.Text, FEdNewName.Text]), mtConfirmation, [mbYes, mbNo],
    0) <> mrYes then Exit;

  RunAsync(RenameCmdLine(False), '(applying...)',
    procedure(AExitCode: Integer; const AOutput: string)
    begin
      if AExitCode = 0 then
      begin
        FBtnClose.Caption:= 'Close';
        ShowMessage('drag-lint: Rename applied successfully.');
        FForm.ModalResult:= mrOk;
      end
      else
      begin
        FBtnApply.Enabled:= True;
        ShowMessage('drag-lint: Rename apply failed. See output for details.');
      end;
    end);
end; // procedure

procedure TRefactorHandler.DoClose(Sender: TObject);
begin
  FForm.ModalResult:= mrCancel;
end;
{ ---- ShowRefactorDialog ---- }

function DLParseTypeAtResolved(const AOutput: string; out AToken: string): string;
var
  Start: Integer;
  Obj  : TJSONValue;
begin
  Result:= '';
  AToken:= '';
  Start:= Pos('{', AOutput);
  if Start = 0 then Exit;
  Obj:= TJSONObject.ParseJSONValue(Copy(AOutput, Start, MaxInt)); { nil on malformed text -- does not raise }
  if Obj = nil then Exit;
  try
    if Obj is not TJSONObject then Exit;
    AToken:= TJSONObject(Obj).GetValue<string>('token', '');
    Result:= TJSONObject(Obj).GetValue<string>('resolved', '');
  finally
    Obj.Free;
  end;
end;

procedure ShowRefactorDialog(const ASuggestedQName: string; const AProjectDb: string; const AExePath: string; const ASuggestedNewName: string; const AFromFile: string);
var
  Form      : TForm           ;
  Handler   : TRefactorHandler;
  edQName   : TEdit           ;
  edNewName : TEdit           ;
  cbBackup  : TCheckBox       ;
  memOutput : TMemo           ;
  btnPreview: TButton         ;
  btnApply  : TButton         ;
  btnClose  : TButton         ;
  lblQName  : TLabel          ;
  lblNewName: TLabel          ;
  Y         : Integer         ;
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
  Form:= TForm.Create(nil);
  try
    Form.Caption    := 'drag-lint Rename Symbol';
    Form.BorderStyle:= bsDialog;
    Form.Position   := poScreenCenter;
    Form.Width      := FORM_W;
    Form.Height     := FORM_H;
    Form.KeyPreview := True;

    Y:= MARGIN;

    { Symbol qname label + edit }
    lblQName:= TLabel.Create(Form);
    lblQName.Parent  := Form;
    lblQName.Caption := 'Symbol qname:';
    lblQName.Left    := MARGIN;
    lblQName.Top     := Y;
    lblQName.AutoSize:= True;
    Inc(Y, LBL_H + 2);

    edQName:= TEdit.Create(Form);
    edQName.Parent:= Form;
    edQName.Left  := MARGIN;
    edQName.Top   := Y;
    edQName.Width:= FORM_W - MARGIN * 2 - 16;
    edQName.Text:= ASuggestedQName;
    Inc(Y, EDIT_H + 8);

    { New name label + edit }
    lblNewName:= TLabel.Create(Form);
    lblNewName.Parent  := Form;
    lblNewName.Caption := 'New name:';
    lblNewName.Left    := MARGIN;
    lblNewName.Top     := Y;
    lblNewName.AutoSize:= True;
    Inc(Y, LBL_H + 2);

    edNewName:= TEdit.Create(Form);
    edNewName.Parent:= Form;
    edNewName.Left  := MARGIN;
    edNewName.Top   := Y;
    edNewName.Width:= FORM_W - MARGIN * 2 - 16;
    edNewName.Text:= ASuggestedNewName;
    Inc(Y, EDIT_H + 8);

    { Write .bak backup checkbox }
    cbBackup:= TCheckBox.Create(Form);
    cbBackup.Parent := Form;
    cbBackup.Caption:= 'Write .bak backup before applying';
    cbBackup.Left   := MARGIN;
    cbBackup.Top    := Y;
    cbBackup.Width:= FORM_W - MARGIN * 2 - 16;
    cbBackup.Checked:= True;
    Inc(Y, CHK_H + 6);

    { Output memo (fills the middle; bottom reserved for buttons) }
    memOutput:= TMemo.Create(Form);
    memOutput.Parent:= Form;
    memOutput.Left  := MARGIN;
    memOutput.Top   := Y;
    memOutput.Width:= FORM_W - MARGIN * 2 - 16;
    memOutput.Height:= FORM_H - Y - BTN_H - MARGIN * 4 - 16;
    memOutput.ReadOnly  := True;
    memOutput.ScrollBars:= ssBoth;
    memOutput.WordWrap  := False;
    memOutput.Font.Name:= 'Consolas';
    memOutput.Font.Size:= 9;
    memOutput.Anchors:= [akLeft, akTop, akRight, akBottom];

    { Bottom buttons }
    btnPreview:= TButton.Create(Form);
    btnPreview.Parent := Form;
    btnPreview.Caption:= 'Preview (dry-run)';
    btnPreview.Width  := 120;
    btnPreview.Height := BTN_H;
    btnPreview.Left   := MARGIN;
    btnPreview.Anchors:= [akLeft, akBottom];
    btnPreview.Top:= FORM_H - BTN_H - MARGIN * 2 - 16;

    btnApply:= TButton.Create(Form);
    btnApply.Parent := Form;
    btnApply.Caption:= 'Apply';
    btnApply.Width  := BTN_W;
    btnApply.Height := BTN_H;
    btnApply.Left:= FORM_W - MARGIN * 2 - 16 - BTN_W * 2 - 8;
    btnApply.Anchors:= [akRight, akBottom];
    btnApply.Top:= FORM_H - BTN_H - MARGIN * 2 - 16;
    btnApply.Enabled:= False;

    btnClose:= TButton.Create(Form);
    btnClose.Parent := Form;
    btnClose.Caption:= 'Cancel';
    btnClose.Width  := BTN_W;
    btnClose.Height := BTN_H;
    btnClose.Left:= FORM_W - MARGIN * 2 - 16 - BTN_W;
    btnClose.Anchors:= [akRight, akBottom];
    btnClose.Top:= FORM_H - BTN_H - MARGIN * 2 - 16;
    btnClose.Cancel:= True;

    { Wire handler (owned by Form, freed with it) }
    Handler:= TRefactorHandler.Create(Form, Form, edQName, edNewName, cbBackup, memOutput, btnApply, btnClose, AExePath, AProjectDb, AFromFile);

    btnPreview.OnClick:= Handler.DoPreview;
    btnApply  .OnClick:= Handler.DoApply;
    btnClose  .OnClick:= Handler.DoClose;
    Form.OnCloseQuery := Handler.DoCloseQuery;

    Form.ShowModal;
  finally
    Form.Free;
  end; // try
end; // procedure

{ ---- TExtractMethodHandler ---- }

type
  TExtractMethodHandler = class(TCliDialogHandler)
    private
      FEdName   : TEdit    ;
      FCbBackup : TCheckBox;
      FExePath  : string   ;
      FFilePath : string   ;
      FFromLine : Integer  ;
      FToLine   : Integer  ;
      FApplied  : Boolean  ;
      function ExtractCmdLine(ADryRun: Boolean): string;
    public
      constructor Create(
        AOwner: TComponent; AForm: TForm; AEdName: TEdit; ACbBackup: TCheckBox; AMemo: TMemo; ABtnApply, ABtnClose: TButton;
        const AExePath, AFilePath: string; AFromLine, AToLine: Integer
      ); reintroduce;
      procedure DoPreview(Sender: TObject);
      procedure DoApply  (Sender: TObject);
      procedure DoClose  (Sender: TObject);
      property Applied: Boolean read FApplied;
  end;

constructor TExtractMethodHandler.Create(
  AOwner: TComponent; AForm: TForm; AEdName: TEdit; ACbBackup: TCheckBox; AMemo: TMemo; ABtnApply, ABtnClose: TButton;
  const AExePath, AFilePath: string; AFromLine, AToLine: Integer);
begin
  inherited Create(AOwner);
  FForm    := AForm;
  FEdName  := AEdName;
  FCbBackup:= ACbBackup;
  FMemo    := AMemo;
  FBtnApply:= ABtnApply;
  FBtnClose:= ABtnClose;
  FExePath := AExePath;
  FFilePath:= AFilePath;
  FFromLine:= AFromLine;
  FToLine  := AToLine;
  FApplied := False;
end;

function TExtractMethodHandler.ExtractCmdLine(ADryRun: Boolean): string;
{ stdout and stderr share one pipe (RunCaptureStdout), so a REFUSED reason
  (written by the CLI to stderr, exit 2) lands in the same preview memo as a
  successful dry-run/apply message. NOTE: unlike the legacy "rename" verb
  (which writes by default and takes --dry-run to opt OUT), "extract-method"
  PREVIEWS by default and writes only with an explicit --apply -- so the apply
  spawn must pass --apply or it silently re-runs the preview and changes nothing. }
begin
  Result:= Format('"%s" extract-method --file "%s" --from-line %d --to-line %d --name "%s"',
    [FExePath, FFilePath, FFromLine, FToLine, FEdName.Text]);
  Result:= Result + (if ADryRun then ' --dry-run' else ' --apply');
  if not FCbBackup.Checked then Result:= Result + ' --no-backup';
end;

procedure TExtractMethodHandler.DoPreview(Sender: TObject);
begin
  if Trim(FEdName.Text) = '' then
  begin
    ShowMessage('drag-lint: Method name must not be empty.');
    FEdName.SetFocus;
    Exit;
  end;

  { A REFUSED reason (stderr, exit 2) still lands in the memo -- exactly like
    a successful preview. Apply stays disabled unless the run exited 0. }
  RunAsync(ExtractCmdLine(True), '(running dry-run...)',
    procedure(AExitCode: Integer; const AOutput: string)
    begin
      FBtnApply.Enabled:= AExitCode = 0;
      FBtnClose.Caption:= 'Cancel';
    end);
end; // procedure

procedure TExtractMethodHandler.DoApply(Sender: TObject);
begin
  if MessageDlg( Format('Extract method ''%s'' from lines %d-%d?'#13#10 + 'This will modify the source file on disk.', [FEdName.Text, FFromLine, FToLine]), mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then Exit;

  RunAsync(ExtractCmdLine(False), '(applying...)',
    procedure(AExitCode: Integer; const AOutput: string)
    begin
      if AExitCode = 0 then
      begin
        FApplied:= True;
        FBtnClose.Caption:= 'Close';
        ShowMessage('drag-lint: Extract Method applied successfully.');
        FForm.ModalResult:= mrOk;
      end
      else
      begin
        FBtnApply.Enabled:= True;
        ShowMessage('drag-lint: Extract Method apply failed. See output for details.');
      end;
    end);
end; // procedure

procedure TExtractMethodHandler.DoClose(Sender: TObject);
begin
  FForm.ModalResult:= mrCancel;
end;
{ ---- ShowExtractMethodDialog ---- }

function ShowExtractMethodDialog(const AFilePath: string; AFromLine, AToLine: Integer; const AExePath: string): Boolean;
var
  Form      : TForm                 ;
  Handler   : TExtractMethodHandler ;
  edName    : TEdit                 ;
  cbBackup  : TCheckBox             ;
  memOutput : TMemo                 ;
  btnPreview: TButton               ;
  btnApply  : TButton               ;
  btnClose  : TButton               ;
  lblRange  : TLabel                ;
  lblName   : TLabel                ;
  Y         : Integer               ;
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
  Form:= TForm.Create(nil);
  try
    Form.Caption    := 'drag-lint Extract Method';
    Form.BorderStyle:= bsDialog;
    Form.Position   := poScreenCenter;
    Form.Width      := FORM_W;
    Form.Height     := FORM_H;
    Form.KeyPreview := True;

    Y:= MARGIN;

    { Selection range (read-only info; the range comes from the editor
      selection made before the dialog opened) }
    lblRange:= TLabel.Create(Form);
    lblRange.Parent  := Form;
    lblRange.Caption := Format('Selection: %s, lines %d-%d', [ExtractFileName(AFilePath), AFromLine, AToLine]);
    lblRange.Left    := MARGIN;
    lblRange.Top     := Y;
    lblRange.AutoSize:= True;
    Inc(Y, LBL_H + 8);

    { New method name label + edit }
    lblName:= TLabel.Create(Form);
    lblName.Parent  := Form;
    lblName.Caption := 'New method name:';
    lblName.Left    := MARGIN;
    lblName.Top     := Y;
    lblName.AutoSize:= True;
    Inc(Y, LBL_H + 2);

    edName:= TEdit.Create(Form);
    edName.Parent:= Form;
    edName.Left  := MARGIN;
    edName.Top   := Y;
    edName.Width:= FORM_W - MARGIN * 2 - 16;
    Inc(Y, EDIT_H + 8);

    { Write .bak backup checkbox }
    cbBackup:= TCheckBox.Create(Form);
    cbBackup.Parent := Form;
    cbBackup.Caption:= 'Write .bak backup before applying';
    cbBackup.Left   := MARGIN;
    cbBackup.Top    := Y;
    cbBackup.Width:= FORM_W - MARGIN * 2 - 16;
    cbBackup.Checked:= True;
    Inc(Y, CHK_H + 6);

    { Output memo (fills the middle; bottom reserved for buttons) }
    memOutput:= TMemo.Create(Form);
    memOutput.Parent:= Form;
    memOutput.Left  := MARGIN;
    memOutput.Top   := Y;
    memOutput.Width:= FORM_W - MARGIN * 2 - 16;
    memOutput.Height:= FORM_H - Y - BTN_H - MARGIN * 4 - 16;
    memOutput.ReadOnly  := True;
    memOutput.ScrollBars:= ssBoth;
    memOutput.WordWrap  := False;
    memOutput.Font.Name:= 'Consolas';
    memOutput.Font.Size:= 9;
    memOutput.Anchors:= [akLeft, akTop, akRight, akBottom];

    { Bottom buttons }
    btnPreview:= TButton.Create(Form);
    btnPreview.Parent := Form;
    btnPreview.Caption:= 'Preview (dry-run)';
    btnPreview.Width  := 120;
    btnPreview.Height := BTN_H;
    btnPreview.Left   := MARGIN;
    btnPreview.Anchors:= [akLeft, akBottom];
    btnPreview.Top:= FORM_H - BTN_H - MARGIN * 2 - 16;

    btnApply:= TButton.Create(Form);
    btnApply.Parent := Form;
    btnApply.Caption:= 'Apply';
    btnApply.Width  := BTN_W;
    btnApply.Height := BTN_H;
    btnApply.Left:= FORM_W - MARGIN * 2 - 16 - BTN_W * 2 - 8;
    btnApply.Anchors:= [akRight, akBottom];
    btnApply.Top:= FORM_H - BTN_H - MARGIN * 2 - 16;
    btnApply.Enabled:= False;

    btnClose:= TButton.Create(Form);
    btnClose.Parent := Form;
    btnClose.Caption:= 'Cancel';
    btnClose.Width  := BTN_W;
    btnClose.Height := BTN_H;
    btnClose.Left:= FORM_W - MARGIN * 2 - 16 - BTN_W;
    btnClose.Anchors:= [akRight, akBottom];
    btnClose.Top:= FORM_H - BTN_H - MARGIN * 2 - 16;
    btnClose.Cancel:= True;

    { Wire handler (owned by Form, freed with it) }
    Handler:= TExtractMethodHandler.Create(Form, Form, edName, cbBackup, memOutput, btnApply, btnClose, AExePath, AFilePath, AFromLine, AToLine);

    btnPreview.OnClick:= Handler.DoPreview;
    btnApply  .OnClick:= Handler.DoApply;
    btnClose  .OnClick:= Handler.DoClose;
    Form.OnCloseQuery := Handler.DoCloseQuery;

    Form.ShowModal;
    Result:= Handler.Applied;
  finally
    Form.Free;
  end; // try
end; // function

initialization
GLiveHandlers:= TList<TObject>.Create;

finalization
FreeAndNil(GLiveHandlers);

end.
