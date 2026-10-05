unit DragLint.Plugin.Reports;

{ The drag-lint > Reports submenu: every question of charts\src\Ask-Report.ps1,
  asked from inside RAD Studio.

  WHAT A CLICK DOES.
    1. Picks the target. Caret questions (routine / field / type) save first
       if the active unit is modified -- otherwise the caret line need not
       match the index -- then ask `drag-lint typeat --format json` for the
       resolved qualified name, falling back to the bare identifier. A control
       question (feeds-from, lands-where, round-trip) rewrites
       Unit.TForm.Control to <FormInstance>.<Control> from the unit's DFM,
       because feeds-from and lands-where refuse the typeat form. Project
       questions send 'project'; table questions prompt for a name. Every
       target except 'project' is shown in an editable prompt first.
    2. Runs `pwsh -File Ask-Report.ps1 ... -Open` through the plugin's ONE
       background runner, the job queue (no second runner), so a report never
       collides with a reindex or lint-all on the same database. Charts open in
       the browser (-Open).
    3. On exit 0 the text answer becomes a DocInsight block
       (DragLint.Plugin.ReportText), put on the clipboard and shown in a small
       modeless window with a Copy button. Exit 1 and 2 show Ask-Report's
       reason; exit 3 (stale index) shows the reindex command and offers to run
       it as the incremental index job -- never a folder target, never a
       --rebuild.

  Everything that decides what is sent and what is shown lives in
  DragLint.Plugin.ReportText, which has no ToolsAPI and is unit-tested. }

interface

uses
  Vcl.Menus;

type
  /// <summary>Adds one clickable menu item wired to InvokeReportQuestion.</summary>
  /// <param name="pParent">The submenu to add to.</param>
  /// <param name="pCaption">The item caption.</param>
  /// <returns>The new item; BuildReportsMenu stores the question index in its Tag.</returns>
  TReportsAddItem = reference to function(pParent: TMenuItem; const pCaption: string): TMenuItem;

  /// <summary>Adds a separator line to a submenu.</summary>
  /// <param name="pParent">The submenu to add to.</param>
  TReportsAddSeparator = reference to procedure(pParent: TMenuItem);

  /// <summary>Adds a disabled section header to a submenu.</summary>
  /// <param name="pParent">The submenu to add to.</param>
  /// <param name="pCaption">The header text.</param>
  TReportsAddHeader = reference to procedure(pParent: TMenuItem; const pCaption: string);

/// <summary>Fills the Reports submenu: one section header per selection kind,
/// then that kind's questions, in catalog order.</summary>
/// <param name="pParent">The (empty) Reports submenu.</param>
/// <param name="pAddItem">The host's item factory; it must wire the item's
/// click to InvokeReportQuestion. Ownership of items and click wrappers stays
/// with the host's existing menu teardown.</param>
/// <param name="pAddSeparator">The host's separator factory.</param>
/// <param name="pAddHeader">The host's section-header factory.</param>
/// <remarks>Main thread only. The host passes factories rather than this unit
/// creating items itself so every drag-lint menu item keeps ONE owner and ONE
/// teardown path (Editor's GMenuItems / GWrappers).</remarks>
procedure BuildReportsMenu(pParent: TMenuItem; const pAddItem: TReportsAddItem;
  const pAddSeparator: TReportsAddSeparator; const pAddHeader: TReportsAddHeader);

/// <summary>Click handler for every Reports item: asks the question whose
/// index is the item's Tag.</summary>
/// <param name="Sender">The clicked TMenuItem.</param>
/// <remarks>Main thread only. Returns as soon as the run is queued; the
/// answer arrives later on the main thread.</remarks>
procedure InvokeReportQuestion(Sender: TObject);

implementation

uses
  System.SysUtils
  , System.Classes
  , System.UITypes
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.Dialogs
  , Vcl.Clipbrd
  , ToolsAPI
  , DragLint.Plugin.ReportText  // dl:unit DragLint.Plugin.ReportText accepted -- REPORT_QUESTIONS is the catalog this unit builds the menu from; it travels with the unit by design
  , DragLint.Plugin.JobQueue
  , DragLint.Plugin.IndexJob  // dl:unit DragLint.Plugin.IndexJob accepted -- a section reindex shares the save-time reindex ceiling INDEX_JOB_TIMEOUT_MS on purpose
  , DragLint.Plugin.ProcRun
  , DragLint.Plugin.ExeResolver
  , DragLint.Plugin.Theme
  , DragLint.Plugin.Fonts
  , DragLint.Plugin.LspClient
  , DragLint.Plugin.Editor
  ;

const
  MSG_PREFIX = 'drag-lint Reports: ';
  { Ask-Report.ps1's documented exit codes }
  ASK_EXIT_ANSWERED = 0;
  ASK_EXIT_REFUSED = 1;
  ASK_EXIT_SETUP = 2;
  ASK_EXIT_STALE = 3;
  { A round-trip measured ~55-60 s on ORM3; the queue's timeout is advisory for
    a non-streaming job, so this is a ceiling, not a kill. }
  REPORT_TIMEOUT_MS = 600000;
  TYPEAT_TIMEOUT_MS = 20000;
  PWSH_REL = 'PowerShell\7\pwsh.exe';
  ASK_REPORT_REL = '..\..\charts\src\Ask-Report.ps1';
  PROJECT_TARGET = 'project';
  { the report window }
  WIN_WIDTH = 820;
  WIN_HEIGHT = 460;
  BAR_HEIGHT = 38;
  BTN_WIDTH = 90;
  GAP = 6;
  DEFAULT_FONT_NAME = 'Consolas';
  DEFAULT_FONT_SIZE = 9;

type
  { A small modeless window: the DocInsight block in a read-only memo, with
    Copy and Close. Frees itself on close; any number may be open. }
  TDragLintReportTextForm = class(TForm)
  private
    FMemo: TMemo;
    procedure HandleCopy(Sender: TObject);
    procedure HandleClose(Sender: TObject);
  protected
    procedure DoClose(var Action: TCloseAction); override;
  public
    constructor CreateReport(AOwner: TComponent; const ACaption, AText: string);
  end;

constructor TDragLintReportTextForm.CreateReport(AOwner: TComponent; const ACaption, AText: string);
var
  Bar     : TPanel;
  FontName: string;
  FontSize: Integer;

  function AddButton(const pCaption: string; pClick: TNotifyEvent): TButton;
  begin
    Result:= TButton.Create(Self);
    Result.Parent:= Bar;
    Result.Caption:= pCaption;
    Result.Width:= BTN_WIDTH;
    Result.Align:= alRight;
    Result.AlignWithMargins:= True;
    Result.Margins.SetBounds(GAP, GAP, GAP, GAP);
    Result.OnClick:= pClick;
  end;

begin
  inherited CreateNew(AOwner);
  Caption:= ACaption;
  BorderStyle:= bsSizeToolWin;
  Position:= poScreenCenter;
  Width:= WIN_WIDTH;
  Height:= WIN_HEIGHT;

  Bar:= TPanel.Create(Self);
  Bar.Parent:= Self;
  Bar.Align:= alBottom;
  Bar.Height:= BAR_HEIGHT;
  Bar.BevelOuter:= bvNone;
  { alRight stacks right-to-left in creation order: Close ends up rightmost }
  AddButton('Close', HandleClose).Cancel:= True;
  AddButton('Copy', HandleCopy).Default:= True;

  FMemo:= TMemo.Create(Self);
  FMemo.Parent:= Self;
  FMemo.Align:= alClient;
  FMemo.ReadOnly:= True;
  FMemo.WordWrap:= False;
  FMemo.ScrollBars:= ssBoth;
  if not GetIdeEditorFont(FontName, FontSize) then
  begin
    FontName:= DEFAULT_FONT_NAME;
    FontSize:= DEFAULT_FONT_SIZE;
  end;
  FMemo.Font.Name:= FontName;
  FMemo.Font.Size:= FontSize;
  FMemo.Lines.Text:= AText;

  ApplyIdeTheme(Self, TDragLintReportTextForm);
end;

procedure TDragLintReportTextForm.DoClose(var Action: TCloseAction);
begin
  inherited DoClose(Action);
  Action:= caFree;
end;

procedure TDragLintReportTextForm.HandleCopy(Sender: TObject);
begin
  Clipboard.AsText:= FMemo.Lines.Text;
end;

procedure TDragLintReportTextForm.HandleClose(Sender: TObject);
begin
  Close;
end;

{ ---- target selection ---- }

{ PowerShell 7's default install, else pwsh.exe on PATH. ProgramW6432 first:
  bds.exe is a 32-bit process, and in it %ProgramFiles% names the (x86)
  folder, where PowerShell 7 x64 is never installed. }
function DefaultPwshPath: string;
begin
  Result:= GetEnvironmentVariable('ProgramW6432');
  if Result = '' then Result:= GetEnvironmentVariable('ProgramFiles');
  Result:= IncludeTrailingPathDelimiter(Result) + PWSH_REL;
end;

function FindPwsh: string;
begin
  if FileExists(DefaultPwshPath) then Exit(DefaultPwshPath);
  Result:= FileSearch('pwsh.exe', GetEnvironmentVariable('PATH'));
  if Result <> '' then Result:= ExpandFileName(Result);
end;

function ActiveEditView: IOTAEditView;
var
  ESS: IOTAEditorServices;
begin
  Result:= nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Result:= ESS.TopView;
  if (Result <> nil) and (Result.Buffer = nil) then Result:= nil;
end;

function ModuleIsModified(const pModule: IOTAModule): Boolean;
begin
  for var I: Integer:= 0 to pModule.ModuleFileCount - 1 do
    if pModule.ModuleFileEditors[I].Modified then Exit(True);
  Result:= False;
end;

{ False = the user cancelled. Asked only for caret questions: a modified buffer
  means the caret line may not be the line the index holds. }
function SaveAllIfModified: Boolean;
var
  MS: IOTAModuleServices;
  M : IOTAModule;
begin
  Result:= True;
  if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
  M:= MS.CurrentModule;
  if (M = nil) or not ModuleIsModified(M) then Exit;
  if MessageDlg('The active unit has unsaved changes, so the caret line may not match the index.' +
                sLineBreak + sLineBreak + 'Save all first?', mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then
    Exit(False);
  MS.SaveAll;
end;

function ReadFirstLine(const pFile: string): string;
var
  R: TStreamReader;
begin
  Result:= '';
  if not FileExists(pFile) then Exit;
  try
    R:= TStreamReader.Create(pFile, TEncoding.ANSI, False);
    try
      Result:= R.ReadLine;
    finally
      R.Free;
    end;
  except
    on EStreamError do Result:= ''; { an unreadable DFM only means no rewrite }
    on EEncodingError do Result:= '';
  end;
end;

{ Unit.TForm.Control -> <FormInstance>.Control when the unit's text DFM says
  the form class is TForm. The DFM is looked for beside the active file under
  the qname's unit name, then as the active file's own sibling. }
function ControlTargetFromDfm(const pQName, pInFile: string): string;
var
  UnitName : string;
  RootName : string;
  RootClass: string;
begin
  Result:= pQName;
  UnitName:= QNameUnitName(pQName);
  if UnitName = '' then Exit;
  for var Dfm: string in [ExtractFilePath(pInFile) + UnitName + '.dfm', ChangeFileExt(pInFile, '.dfm')] do
    if ParseDfmRootObject(ReadFirstLine(Dfm), RootName, RootClass) then
    begin
      Result:= FormControlTarget(pQName, RootName, RootClass);
      if Result <> pQName then Exit;
    end;
end;

{ typeat's resolved name at the caret, or the bare identifier. }
function CaretTarget(const pView: IOTAEditView; const pInFile: string): string;
var
  Db    : string;
  Answer: string;
begin
  Result:= '';
  Db:= ResolvePrimaryIndexDb;
  if Db <> '' then
  begin
    var Cmd: string:= Format('"%s" typeat "%s:%d:%d" --db "%s" --format json',
      [DragLintExe, pInFile, pView.Position.Row, pView.Position.Column, Db]);
    DebugLog('Reports: ' + Cmd);
    if RunCaptureStdout(Cmd, Answer, TYPEAT_TIMEOUT_MS) = 0 then Result:= ParseTypeAtResolved(Answer);
  end;
  if Result = '' then Result:= IdentifierAtCursor;
end;

function PromptTarget(const pQuestion: TReportQuestion; var pTarget: string): Boolean;
begin
  Result:= InputQuery('drag-lint Reports', pQuestion.Caption.TrimRight(['.']) + ' -- target:', pTarget);
  if not Result then Exit;
  pTarget:= Trim(pTarget);
  if Pos('"', pTarget) > 0 then
  begin
    ShowMessage(MSG_PREFIX + 'the target must not contain a double-quote (").');
    Exit(False);
  end;
  Result:= IsValidReportTarget(pTarget);
end;

function ChooseTarget(const pQuestion: TReportQuestion; const pInFile: string; out pTarget: string): Boolean;
var
  View: IOTAEditView;
begin
  pTarget:= '';
  case pQuestion.Kind of
    rtkProject:
      begin
        pTarget:= PROJECT_TARGET;
        Exit(True);
      end;
    rtkUnit   : pTarget:= ChangeFileExt(ExtractFileName(pInFile), '');
    rtkName   : pTarget:= '';
  else
    if not SaveAllIfModified then Exit(False);
    View:= ActiveEditView;
    if View = nil then
    begin
      ShowMessage(MSG_PREFIX + 'no active editor.');
      Exit(False);
    end;
    pTarget:= CaretTarget(View, pInFile);
    if QuestionTakesFormControl(pQuestion.Id) then pTarget:= ControlTargetFromDfm(pTarget, pInFile);
  end;
  Result:= PromptTarget(pQuestion, pTarget);
end;

{ ---- the answer ---- }

procedure ShowReportText(const pCaption, pText: string);
begin
  TDragLintReportTextForm.CreateReport(Application, pCaption, pText).Show;
end;

function SectionReindexJob(const pExe, pSection: string): TDragLintJob;
begin
  Result:= TDragLintJob.Create;
  Result.Kind       := jkReindex;
  Result.Title      := 'Reindex ' + pSection;
  Result.CoalesceKey:= 'index-section:' + LowerCase(pSection);
  Result.CmdLine    := Format('"%s" index --all --only %s', [pExe, pSection]);
  Result.TimeoutMs  := INDEX_JOB_TIMEOUT_MS;
  Result.Streaming  := False;
end;

procedure OfferReindex(const pOutput: string);
var
  Cmds: TArray<TReindexCommand>;
  Msg : string;
begin
  Cmds:= ParseReindexCommands(pOutput);
  Msg:= MSG_PREFIX + 'an index is stale, so the answer would be short or wrong.' +
        sLineBreak + sLineBreak + AskReportReason(pOutput);
  if Length(Cmds) = 0 then
  begin
    ShowMessage(Msg + sLineBreak + sLineBreak +
                'No incremental reindex command could be derived for it; refresh that index, then ask again.');
    Exit;
  end;
  if MessageDlg(Msg + sLineBreak + sLineBreak +
                'Run the incremental reindex now, in the background? Ask the question again when it finishes.',
                mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  for var Cmd: TReindexCommand in Cmds do
    if Cmd.Kind = rikProject then JobQueue.Enqueue(BuildProjectIndexJob(DragLintExe, Cmd.ProjectFile, Cmd.Db, ''))
    else JobQueue.Enqueue(SectionReindexJob(DragLintExe, Cmd.Section));
end;

procedure HandleReportDone(const pQuestionId, pTarget: string; pExit: Integer; const pOutput: string);
var
  Text: string;
begin
  DebugLog(Format('Reports: %s %s -> exit %d', [pQuestionId, pTarget, pExit]));
  case pExit of
    ASK_EXIT_ANSWERED:
      begin
        Text:= FormatReportAsDocInsight(pQuestionId, pTarget, Now, pOutput);
        try
          Clipboard.AsText:= Text;
        except
          { the window below still carries the text and its own Copy button }
        end;
        ShowReportText(Format('drag-lint report: %s -- %s (copied to the clipboard)', [pQuestionId, pTarget]), Text);
      end;
    ASK_EXIT_REFUSED:
      ShowMessage(MSG_PREFIX + 'the question was refused.' + sLineBreak + sLineBreak + AskReportReason(pOutput));
    ASK_EXIT_SETUP:
      ShowMessage(MSG_PREFIX + 'setup problem -- the indexes could not be resolved.' + sLineBreak + sLineBreak +
                  AskReportReason(pOutput));
    ASK_EXIT_STALE:
      OfferReindex(pOutput);
  else
    ShowMessage(Format(MSG_PREFIX + 'Ask-Report.ps1 ended with exit %d.', [pExit]) + sLineBreak + sLineBreak +
                AskReportReason(pOutput));
  end;
end;

procedure EnqueueReport(const pQuestionId, pTarget, pCmdLine: string);
var
  Job: TDragLintJob;
begin
  DebugLog('Reports: enqueue ' + pCmdLine);
  Job:= TDragLintJob.Create;
  Job.Kind       := jkGeneric;
  Job.Title      := Format('Report %s %s', [pQuestionId, pTarget]);
  Job.CoalesceKey:= 'report:' + pQuestionId + ':' + LowerCase(pTarget);
  Job.CmdLine    := pCmdLine;
  Job.TimeoutMs  := REPORT_TIMEOUT_MS;
  Job.Streaming  := False;
  Job.OnDone     :=
    procedure(AExit: Integer; AOut: string)
    begin
      HandleReportDone(pQuestionId, pTarget, AExit, AOut);
    end;
  JobQueue.Enqueue(Job);
end;

{ ---- public ---- }

procedure BuildReportsMenu(pParent: TMenuItem; const pAddItem: TReportsAddItem;
  const pAddSeparator: TReportsAddSeparator; const pAddHeader: TReportsAddHeader);
var
  First: Boolean;
begin
  First:= True;
  for var Kind: TReportTargetKind:= Low(TReportTargetKind) to High(TReportTargetKind) do
  begin
    if not First then pAddSeparator(pParent);
    First:= False;
    pAddHeader(pParent, ReportGroupCaption(Kind));
    for var I: Integer:= Low(REPORT_QUESTIONS) to High(REPORT_QUESTIONS) do
      if REPORT_QUESTIONS[I].Kind = Kind then pAddItem(pParent, REPORT_QUESTIONS[I].Caption).Tag:= I;
  end;
  { SLOT RESERVED for the 'Forms for testers (CSV)...' item, which another task
    adds here: after a separator, as the last entry of this submenu. Nothing is
    added for it yet. }
end;

{ Everything a run needs besides the target; says plainly what is missing. }
function ResolveRunTools(out pExe, pScript, pPwsh, pInFile: string): Boolean;
var
  Problem: string;
begin
  pExe:= DragLintExe;
  pScript:= ExpandFileName(ExtractFilePath(pExe) + ASK_REPORT_REL);
  pPwsh:= FindPwsh;
  pInFile:= '';
  var View: IOTAEditView:= ActiveEditView;
  if View <> nil then pInFile:= View.Buffer.FileName;
  if not FileExists(pScript) then
    Problem:= 'Ask-Report.ps1 is not there, so no report can run:' + sLineBreak + pScript +
              sLineBreak + sLineBreak + 'The reports run the chart scripts of a drag-lint repository clone ' +
              '(charts\src, two folders above the engine at ' + pExe + ').'
  else if pPwsh = '' then
    Problem:= 'PowerShell 7 (pwsh.exe) was not found at ' + DefaultPwshPath + ' or on PATH.'
  else if pInFile = '' then
    Problem:= 'open a unit of the project first -- the report finds the index from the active file.'
  else
    Problem:= '';
  Result:= Problem = '';
  if not Result then ShowMessage(MSG_PREFIX + Problem);
end;

procedure InvokeReportQuestion(Sender: TObject);
var
  Exe   : string;
  Script: string;
  Pwsh  : string;
  InFile: string;
  Target: string;
begin
  if not (Sender is TMenuItem) then Exit;
  var Idx: Integer:= TMenuItem(Sender).Tag;
  if (Idx < Low(REPORT_QUESTIONS)) or (Idx > High(REPORT_QUESTIONS)) then Exit;
  var Q: TReportQuestion:= REPORT_QUESTIONS[Idx];
  if ResolveRunTools(Exe, Script, Pwsh, InFile) and ChooseTarget(Q, InFile, Target) then
    EnqueueReport(Q.Id, Target, BuildAskReportCmdLine(Pwsh, Script, Q.Id, Target, InFile, Exe));
end;

end.
