unit DragLint.Plugin.Cmd.FieldRepo;

{ 1.52 command unit, owned by lane TTIDE: TableTools migration M10-M11: the
  "Field Repository" submenu that replaces the TableTools Tables menu.

  Six rows are registered in the 1.52 command table (DragLint.Plugin.Cmd152),
  all visible: Open editor (launches dl-field-repo.exe on the active project's
  repository), Refresh schema, FDMemTable from CSV, ORM source (repo gen-orm /
  update-orm), DataService units (repo gen-dataservice) and the Param Array
  assistant (repo gen-param-array on the active unit). The three generator rows
  run a dry run first, show its summary and write only after the user confirms
  (B33 / BK-TTFINISH unhid them once the ORM golden passed).

  1.54 (TT-DIALOG) adds three rows for the form in the editor: Read Fields from
  Dataset, Read Fields of All Datasets of Form (repo read-dfm) and Select Fields
  of Dataset (repo write-dfm). Each is a dry run, a list of the changes to check
  (DragLint.Plugin.FieldSelectDialog) and one run with the --select file of it.

  The IDE parts (active project, engine exe, async runner) sit behind
  a not-CONSOLE conditional so that the headless console runners
  (run_v152_PLUGFRAME_cmdtable.ps1, run_v152_TTIDE_menu.ps1) compile this unit
  without ToolsAPI; DragLint.Plugin.Editor is not edited. }

interface

/// <summary>The command line of one `drag-lint repo` verb on a project.</summary>
/// <param name="pExe">Full path of the engine exe; quoted in the result.</param>
/// <param name="pVerb">The repo sub-verb, e.g. 'refresh-schema'.</param>
/// <param name="pProject">The project file whose repository is meant
/// (--project); quoted in the result.</param>
/// <param name="pExtra">Further arguments, already quoted; '' for none.</param>
/// <returns>'"exe" repo verb --project "proj"' plus ' ' + pExtra when given.</returns>
/// <remarks>
/// Pure; no side effects. The engine resolves the repository file from
/// the project's fieldRepository key.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Cmd.FieldRepo.InvokeDataService (DragLint.Plugin.Cmd.FieldRepo.pas), DragLint.Plugin.Cmd.FieldRepo.InvokeOpenEditor (DragLint.Plugin.Cmd.FieldRepo.pas), DragLint.Plugin.Cmd.FieldRepo.InvokeOrmSource (DragLint.Plugin.Cmd.FieldRepo.pas), DragLint.Plugin.Cmd.FieldRepo.InvokeRefreshSchema (DragLint.Plugin.Cmd.FieldRepo.pas)</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FieldRepoCommandLine(const pExe, pVerb, pProject, pExtra: string): string;  // dl:ok unused-public-symbol@9ebf -- test seam: run_v152_TTIDE_menu.ps1 checks the command line in a console build outside the plugin index

/// <summary>Prompt text that makes the VCL InputQuery mask its edit (password character).</summary>
/// <param name="pText">The visible prompt, e.g. a label.</param>
/// <returns>#31 followed by pText; Vcl.Dialogs.InputQuery treats a leading #31 as "mask the input" and drops it from the label.</returns>
/// <remarks>Pure. Used for the Refresh Schema connection string, which can carry a password; the value is never echoed or logged.</remarks>
/// <summary>Folder / table / apply arguments of a repo generator verb.</summary>
/// <param name="pCodeDir">--code-dir folder; '' leaves the flag out.</param>
/// <param name="pServerDir">--server-dir folder; '' leaves the flag out.</param>
/// <param name="pClientDir">--client-dir folder; '' leaves the flag out.</param>
/// <param name="pTables">--table value (comma-separated); '' leaves the flag out.</param>
/// <param name="pApply">True appends --apply (write); False = dry run.</param>
/// <returns>The arguments, each value double-quoted, separated by one blank; '' when none.</returns>
/// <remarks>
/// Pure; no side effects.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Cmd.FieldRepo.InvokeDataService (DragLint.Plugin.Cmd.FieldRepo.pas), DragLint.Plugin.Cmd.FieldRepo.InvokeOrmSource (DragLint.Plugin.Cmd.FieldRepo.pas)</para>
/// <para>Calls: DragLint.Plugin.Cmd.FieldRepo.FieldRepoGenArgs.Add, Trim</para>
/// <seealso cref="DragLint.Plugin.Cmd.FieldRepo.FieldRepoGenArgs.Add"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FieldRepoGenArgs(const pCodeDir, pServerDir, pClientDir, pTables: string; pApply: Boolean): string;  // dl:ok unused-public-symbol@30ea -- REVIEWED 2026-11-18 v152 BK-TTFINISH: test seam: run_v152_TTIDE_menu.ps1 checks it in a console build outside the plugin index

/// <summary>The lines of a generator dry run worth a message box: the diff lines
/// ('--- ', '+++ ', '@@', '-', '+') are dropped.</summary>
/// <param name="pOutput">The verb's stdout.</param>
/// <param name="pMaxLines">Most lines kept; the rest is counted in a final '... n more lines' line.</param>
/// <returns>The kept lines joined with CRLF.</returns>
/// <remarks>
/// Pure; no side effects.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Cmd.FieldRepo.RunDryThenApply (DragLint.Plugin.Cmd.FieldRepo.pas)</para>
/// <para>Calls: Format</para>
/// <para>Returns: String.Join(sLineBreak, Kept.ToStringArray)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FieldRepoRunSummary(const pOutput: string; pMaxLines: Integer): string;  // dl:ok unused-public-symbol@3193 -- REVIEWED 2026-11-18 v152 BK-TTFINISH: test seam: run_v152_TTIDE_menu.ps1 checks it in a console build outside the plugin index

/// <param name="pText"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: #31 + pText.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Cmd.FieldRepo.InvokeRefreshSchema (DragLint.Plugin.Cmd.FieldRepo.pas)</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MaskedPrompt(const pText: string): string;  // dl:ok unused-public-symbol@2bdb -- test seam: run_v152_TTIDE_menu.ps1 checks it in a console build outside the plugin index

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Dialogs,
  {$IFNDEF CONSOLE}
  Winapi.Windows,
  System.JSON,
  DragLint.Plugin.ProcRun,
  DragLint.Plugin.CliAsync,
  DragLint.Plugin.ExeResolver,
  System.UITypes,
  System.IOUtils,
  Vcl.FileCtrl,
  ToolsAPI,
  DragLint.Plugin.Telemetry,
  DragLint.Plugin.Theme,
  DragLint.Plugin.FieldSelectModel,
  DragLint.Plugin.FieldSelectDialog,
  {$ENDIF}
  DragLint.Plugin.Cmd152;

const
  PARENT_PATH = 'Field Repository';
  OWNER_LANE = 'TTIDE';
  EDITOR_EXE = 'dl-field-repo.exe';
  INFO_TIMEOUT_MS = 20000;
  REPO_STALL_MS = 300000;
  SUMMARY_LINES = 40;
  WRITE_FILES_ASK = 'Write these files now?';
  REFRESH_ASK = 'Write the checked changes to the repository now? Deletes of vanished columns are not checked and stay out.';
  SUB_READ_DFM = 'read-dfm';
  SUB_WRITE_DFM = 'write-dfm';
  JSON_FLAG = '--json';
  NO_PROJECT_MSG = 'drag-lint: open a project first; the field repository belongs to the active project.';

function MaskedPrompt(const pText: string): string;
begin
  Result:= #31 + pText;
end;

function FieldRepoGenArgs(const pCodeDir, pServerDir, pClientDir, pTables: string; pApply: Boolean): string;

  procedure Add(const pFlag, pValue: string);
  begin
    if pValue = '' then Exit;
    if Result <> '' then Result:= Result + ' ';
    Result:= Result + pFlag + ' "' + pValue + '"';
  end;

begin
  Result:= '';
  Add('--code-dir', pCodeDir);
  Add('--server-dir', pServerDir);
  Add('--client-dir', pClientDir);
  Add('--table', pTables);
  if pApply then Result:= Trim(Result + ' --apply');
end;

function FieldRepoRunSummary(const pOutput: string; pMaxLines: Integer): string;
var
  Lines, Kept: TStringList;
  Line: string;
  Dropped: Integer;
begin
  Lines:= TStringList.Create;
  Kept:= TStringList.Create;
  try
    Lines.Text:= pOutput;
    Dropped:= 0;
    for Line in Lines do
    begin
      if Line.StartsWith('-') or Line.StartsWith('+') or Line.StartsWith('@@') then Continue;
      if Kept.Count < pMaxLines then Kept.Add(Line) else Inc(Dropped);
    end;
    if Dropped > 0 then Kept.Add(Format('... %d more lines', [Dropped]));
    Result:= String.Join(sLineBreak, Kept.ToStringArray);
  finally
    Kept.Free;
    Lines.Free;
  end;
end;

function FieldRepoCommandLine(const pExe, pVerb, pProject, pExtra: string): string;
begin
  Result:= '"' + pExe + '" repo ' + pVerb + ' --project "' + pProject + '"';
  if pExtra <> '' then Result:= Result + ' ' + pExtra;
end;

{$IFNDEF CONSOLE}

{ The active project's file, or '' when no project is open. }
function ActiveProjectFile: string;
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
begin
  Result:= '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then Exit;
  Group:= Services.MainProjectGroup;
  if (Group <> nil) and (Group.ActiveProject <> nil) then Result:= Group.ActiveProject.FileName;
end;

{ Engine exe and active project, or False after telling the user why not. }
function ResolveContext(out pExe, pProject: string): Boolean;
begin
  pProject:= '';
  Result:= RequireEngine(pExe);
  if not Result then
  begin
    ReportEngineMissing;
    Exit;
  end;
  pProject:= ActiveProjectFile;
  Result:= pProject <> '';
  if not Result then ShowMessage(NO_PROJECT_MSG);
end;

procedure ShowRunResult(const pTitle: string; pExitCode: Integer; const pOutput: string);
begin
  ShowMessage(pTitle + ' -- exit ' + IntToStr(pExitCode) + sLineBreak + sLineBreak + Trim(pOutput));
end;

{ Starts the editor detached; the IDE does not wait for it. }
procedure LaunchEditor(const pEditorExe, pRepoPath: string);
var
  StartInfo: TStartupInfo;
  ProcInfo: TProcessInformation;
  CmdLine: string;
begin
  CmdLine:= '"' + pEditorExe + '" --repo "' + pRepoPath + '"';
  ZeroMemory(@StartInfo, SizeOf(StartInfo));
  StartInfo.cb:= SizeOf(StartInfo);
  if CreateProcess(PChar(pEditorExe), PChar(CmdLine), nil, nil, False, 0, nil, nil, StartInfo, ProcInfo) then
  begin
    CloseHandle(ProcInfo.hThread);
    CloseHandle(ProcInfo.hProcess);
  end
  else ShowMessage('drag-lint: could not start ' + pEditorExe);
end;

procedure InvokeOpenEditor(Sender: TObject);
var
  Exe, Project, Output, RepoPath, EditorExe, PathValue: string;
  Json: TJSONValue;
  ExitCode: Integer;
begin
  if not ResolveContext(Exe, Project) then Exit;
  ExitCode:= RunCaptureStdout(FieldRepoCommandLine(Exe, 'info', Project, '--json'), Output, INFO_TIMEOUT_MS);
  if ExitCode <> 0 then
  begin
    ShowRunResult('repo info', ExitCode, Output);
    Exit;
  end;
  RepoPath:= '';
  Json:= TJSONObject.ParseJSONValue(Output);
  try
    if (Json <> nil) and Json.TryGetValue<string>('path', PathValue) then RepoPath:= PathValue;
  finally
    Json.Free;
  end;
  EditorExe:= ExtractFilePath(Exe) + EDITOR_EXE;
  if not FileExists(EditorExe) then
  begin
    ShowMessage('drag-lint: ' + EDITOR_EXE + ' not found next to the engine (' + ExtractFilePath(Exe) + ').');
    Exit;
  end;
  LaunchEditor(EditorExe, RepoPath);
end;

{ pBaseCmd + pDryArgs (dry run), summary, the question pAsk, then pBaseCmd + pApplyArgs. }
procedure RunDryThenApply(const pTitle, pBaseCmd, pDryArgs, pApplyArgs: string; const pAsk: string = WRITE_FILES_ASK);
begin
  RunCliAsync(Trim(pBaseCmd + ' ' + pDryArgs),
    procedure(pExitCode: Integer; const pOutput: string)
    begin
      if pExitCode <> 0 then
      begin
        ShowRunResult(pTitle + ' (dry run)', pExitCode, FieldRepoRunSummary(pOutput, SUMMARY_LINES));
        Exit;
      end;
      if MessageDlg(pTitle + ' -- dry run' + sLineBreak + sLineBreak + FieldRepoRunSummary(pOutput, SUMMARY_LINES) +
        sLineBreak + sLineBreak + pAsk, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
      RunCliAsync(pBaseCmd + ' ' + pApplyArgs,
        procedure(pApplyExit: Integer; const pApplyOutput: string)
        begin
          ShowRunResult(pTitle, pApplyExit, FieldRepoRunSummary(pApplyOutput, SUMMARY_LINES));
        end, REPO_STALL_MS);
    end, REPO_STALL_MS);
end;

procedure InvokeRefreshSchema(Sender: TObject);
var
  Exe, Project, Connection: string;
begin
  if not ResolveContext(Exe, Project) then Exit;
  Connection:= '';
  if not InputQuery('Refresh schema from database', MaskedPrompt('Firebird connection string (read-only, hidden):'), Connection) then Exit;
  Connection:= Trim(Connection);
  if (Connection = '') or Connection.Contains('"') then
  begin
    ShowMessage('drag-lint: give the connection string without double quotes');
    Exit;
  end;
  // 1.53: refresh-schema is a change set (dry run unless --apply); '--dry-run' keeps an older engine from writing here too.
  RunDryThenApply('repo refresh-schema',
    FieldRepoCommandLine(Exe, 'refresh-schema', Project, '--connection "' + Connection + '"'), '--dry-run', '--apply', REFRESH_ASK);
end;

procedure InvokeMemTableFromCsv(Sender: TObject);
var
  Exe, Csv, OutFile: string;
  Dlg: TOpenDialog;
begin
  if not RequireEngine(Exe) then
  begin
    ReportEngineMissing;
    Exit;
  end;
  Dlg:= TOpenDialog.Create(nil);
  try
    Dlg.Filter:= 'Field definition CSV (*.csv)|*.csv|All files (*.*)|*.*';
    if not Dlg.Execute then Exit;
    Csv:= Dlg.FileName;
  finally
    Dlg.Free;
  end;
  OutFile:= ChangeFileExt(Csv, '.memtable.pas');
  RunCliAsync('"' + Exe + '" repo gen-memtable --in "' + Csv + '" --output "' + OutFile + '"',
    procedure(pExitCode: Integer; const pOutput: string)
    begin
      ShowRunResult('repo gen-memtable -> ' + OutFile, pExitCode, pOutput);
    end, REPO_STALL_MS);
end;

var
  { last folders picked in this IDE session (generator rows) }
  GCodeDir, GServerDir, GClientDir: string;

{ Lets the user pick a folder; starts in pStart (or the project folder). }
function PickFolder(const pCaption, pProject: string; var pDir: string): Boolean;
var
  Dir: string;
begin
  Dir:= if pDir <> '' then pDir else ExtractFileDir(pProject);
  Result:= SelectDirectory(pCaption, '', Dir, [sdNewUI], nil);
  if Result then pDir:= Dir;
end;

{ repo gen-orm (tables given) or update-orm (no tables: every existing unit). }
procedure InvokeOrmSource(Sender: TObject);
var
  Exe, Project, Tables, Sub, ServerDir, ClientDir: string;
begin
  if not ResolveContext(Exe, Project) then Exit;
  if not PickFolder('Folder of the i<T>/u<T> ORM units (COMMON\OBJECTS)', Project, GCodeDir) then Exit;
  Tables:= '';
  if not InputQuery('Generate / Update ORM Source', 'Tables for NEW units (comma-separated; empty = update the existing units of every table):', Tables) then Exit;
  Tables:= Trim(Tables);
  ServerDir:= '';
  ClientDir:= '';
  if Tables <> '' then Sub:= 'gen-orm'
  else
  begin
    Sub:= 'update-orm';
    if MessageDlg('Also update the _SERVER and _CLIENT units?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      if not PickFolder('Folder of the _SERVER units', Project, GServerDir) then Exit;
      if not PickFolder('Folder of the _CLIENT units', Project, GClientDir) then Exit;
      ServerDir:= GServerDir;
      ClientDir:= GClientDir;
    end;
  end;
  RunDryThenApply('repo ' + Sub,
    FieldRepoCommandLine(Exe, Sub, Project, FieldRepoGenArgs(GCodeDir, ServerDir, ClientDir, Tables, False)), '', '--apply');
end;

{ repo gen-dataservice for the named tables. }
procedure InvokeDataService(Sender: TObject);
var
  Exe, Project, Tables: string;
begin
  if not ResolveContext(Exe, Project) then Exit;
  Tables:= '';
  if not InputQuery('Generate DataService Units', 'Tables (comma-separated):', Tables) then Exit;
  Tables:= Trim(Tables);
  if Tables = '' then
  begin
    ShowMessage('drag-lint: name at least one table');
    Exit;
  end;
  if not PickFolder('Folder of the _SERVER units', Project, GServerDir) then Exit;
  if not PickFolder('Folder of the _CLIENT units', Project, GClientDir) then Exit;
  RunDryThenApply('repo gen-dataservice',
    FieldRepoCommandLine(Exe, 'gen-dataservice', Project, FieldRepoGenArgs('', GServerDir, GClientDir, Tables, False)), '', '--apply');
end;

{ The unit in the active editor (.pas of a form), or ''. }
function ActiveUnitFile: string;
var
  Services: IOTAModuleServices;
  Module: IOTAModule;
begin
  Result:= '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then Exit;
  Module:= Services.CurrentModule;
  if Module <> nil then Result:= ChangeFileExt(Module.FileName, '.pas');
end;

{ repo gen-param-array on the active unit: --plan, confirm, --apply through the compile gate. }
procedure InvokeParamArray(Sender: TObject);
var
  Exe, Project, UnitFile, Prep, Base: string;
begin
  if not ResolveContext(Exe, Project) then Exit;
  UnitFile:= ActiveUnitFile;
  if (UnitFile = '') or not FileExists(UnitFile) then
  begin
    ShowMessage('drag-lint: open the form unit first (and save it); the assistant reads its .pas and .dfm from disk.');
    Exit;
  end;
  case MessageDlg('Prepare the queries first (SELECT -> the update object''s INSERT SQL, update object / schema adapter renamed ZZZ*, persistent fields removed)?',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: Prep:= ' --prepare-queries';
    mrNo: Prep:= '';
  else
    Exit;
  end;
  Base:= '"' + Exe + '" repo gen-param-array --in "' + UnitFile + '"' + Prep;
  RunDryThenApply('repo gen-param-array', Base, '--plan', '--apply --project "' + Project + '"');
end;

{ ---- 1.54 TT-DIALOG: the form in the editor ---- }

type
  { The form a field command works on, read at the click. }
  TFormContext = record
    Title: string;
    Exe: string;
    Project: string;
    Dfm: string;
    Selected: TArray<string>; // components selected in the designer
    procedure Show(const pText: string);
  end;

  TFormStep = reference to procedure(const pOutput: string);
  TDatasetStep = reference to procedure(const pForm: TFormContext; const pDataset: string);

procedure TFormContext.Show(const pText: string);
begin
  ShowMessage(Title + sLineBreak + sLineBreak + pText);
end;

{ The open module of a form's unit, or nil. }
function OpenModuleOf(const pDfm: string): IOTAModule;
var
  Services: IOTAModuleServices;
begin
  Result:= nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) then Result:= Services.FindModule(ChangeFileExt(pDfm, '.pas'));
end;

function ModuleIsDirty(const pModule: IOTAModule): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if pModule = nil then Exit;
  for I:= 0 to pModule.ModuleFileCount - 1 do
    if pModule.ModuleFileEditors[I].Modified then Exit(True);
end;

{ The engine reads the form from disk. }
function SavedOrClean(const pModule: IOTAModule): Boolean;
begin
  Result:= not ModuleIsDirty(pModule);
  if Result then Exit;
  if MessageDlg(ExtractFileName(pModule.FileName) + ' has unsaved changes. Save it and continue?',
    mtConfirmation, [mbYes, mbCancel], 0) = mrYes then Result:= pModule.Save(False, True);
end;

{ The designer holds real components in this process, so the handle is the component. }
function SelectedComponents(const pModule: IOTAModule): TArray<string>;
var
  Designer: IOTAFormEditor;
  Obj: TObject;
  I, J: Integer;
begin
  Result:= nil;
  for I:= 0 to pModule.ModuleFileCount - 1 do
  begin
    if not Supports(pModule.ModuleFileEditors[I], IOTAFormEditor, Designer) then Continue;
    for J:= 0 to Designer.GetSelCount - 1 do
    begin
      Obj:= TObject(Designer.GetSelComponent(J).GetComponentHandle);
      if Obj is TComponent then Result:= Result + [TComponent(Obj).Name];
    end;
  end;
end;

{ Engine, project and the saved form in the editor, or False after telling the user why not. }
function ResolveForm(const pTitle: string; out pForm: TFormContext): Boolean;
var
  Services: IOTAModuleServices;
  Module: IOTAModule;
begin
  pForm:= Default(TFormContext);
  pForm.Title:= 'drag-lint: ' + pTitle;
  Result:= ResolveContext(pForm.Exe, pForm.Project);
  if not Result then Exit;
  Module:= nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) then Module:= Services.CurrentModule;
  if Module <> nil then
  begin
    pForm.Dfm:= ChangeFileExt(Module.FileName, '.dfm');
    pForm.Selected:= SelectedComponents(Module);
    if FileExists(pForm.Dfm) then Exit(SavedOrClean(Module));
  end;
  Result:= False;
  pForm.Show('open the form first; its fields are read from the .dfm on disk.');
end;

{ One `repo` run off the main thread; pNext gets the output of a run that succeeded. }
procedure RunFormStep(const pForm: TFormContext; const pSub, pArgs: string; const pNext: TFormStep);
var
  Title: string;
  Next: TFormStep;
begin
  Title:= pForm.Title;
  Next:= pNext;
  RunCliAsync(FieldRepoCommandLine(pForm.Exe, pSub, pForm.Project, pArgs),
    procedure(pExitCode: Integer; const pOutput: string)
    begin
      if pExitCode = 0 then Next(pOutput) else ShowRunResult(Title, pExitCode, ApplyLog(pOutput, SUMMARY_LINES));
    end, REPO_STALL_MS);
end;

{ Reloads the form after its files were written; a form edited meanwhile is left alone. }
procedure ReloadForm(const pDfm: string);
var
  Module: IOTAModule;
begin
  try
    Module:= OpenModuleOf(pDfm);
    if (Module <> nil) and not ModuleIsDirty(Module) then Module.Refresh(True);
  except
    on E: Exception do DLT('field-repository', 'reload ' + pDfm + ': ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ The run that writes exactly the checked changes. }
procedure ApplySelection(const pForm: TFormContext; const pSub, pArgs: string; const pPlan: TFsPlan);
var
  SelectFile, SubVerb: string;
  Form: TFormContext;
begin
  Form:= pForm;
  SubVerb:= pSub;
  SelectFile:= TPath.Combine(TPath.GetTempPath, 'drag-lint-select-' + TGUID.NewGuid.ToString + '.txt');
  TFile.WriteAllText(SelectFile, pPlan.SelectFileText);
  RunCliAsync(FieldRepoCommandLine(Form.Exe, SubVerb, Form.Project, pArgs + SelectArg(SelectFile)),
    procedure(pExitCode: Integer; const pOutput: string)
    begin
      System.SysUtils.DeleteFile(SelectFile);
      if (pExitCode = 0) and (SubVerb = SUB_WRITE_DFM) then ReloadForm(Form.Dfm);
      ShowRunResult(Form.Title, pExitCode, ApplyLog(pOutput, SUMMARY_LINES));
    end, REPO_STALL_MS);
end;

{ The plan of a dry run, or False after showing why there is none. }
function PlanOf(const pForm: TFormContext; const pOutput: string; out pPlan: TFsPlan): Boolean;
var
  Error: string;
begin
  Result:= ParsePlan(pOutput, pPlan, Error);
  if not Result then pForm.Show(Error);
end;

{ Asks for the changes of a dry run; False = nothing to write. }
function Confirmed(const pForm: TFormContext; var pPlan: TFsPlan): Boolean;
begin
  Result:= Length(pPlan.Changes) > 0;
  if Result then Result:= ConfirmChanges(pForm.Title, pPlan, ApplyIdeTheme) and (pPlan.CheckedCount > 0)
  else pForm.Show('no difference' + sLineBreak + string.Join(sLineBreak, pPlan.Warnings));
end;

{ repo read-dfm: dry run, confirm, dry run again (its ids have no plan id), apply. }
procedure ReadFields(const pForm: TFormContext; const pDataset: string);
var
  Form: TFormContext;
  Args: string;
begin
  Form:= pForm;
  Args:= ReadDfmArgs(Form.Dfm, pDataset, '');
  RunFormStep(Form, SUB_READ_DFM, Args + JSON_FLAG,
    procedure(const pOutput: string)
    var
      Plan: TFsPlan;
    begin
      if not PlanOf(Form, pOutput, Plan) or not Confirmed(Form, Plan) then Exit;
      RunFormStep(Form, SUB_READ_DFM, Args + JSON_FLAG,
        procedure(const pAgain: string)
        var
          Newer: TFsPlan;
        begin
          if not PlanOf(Form, pAgain, Newer) then Exit;
          if Newer.Fingerprint = Plan.Fingerprint then ApplySelection(Form, SUB_READ_DFM, Args, Plan)
          else Form.Show('the form or the repository changed meanwhile: nothing written');
        end);
    end);
end;

{ repo write-dfm for the fields the user selected: dry run, confirm, apply with the plan id. }
procedure WriteSelection(const pForm: TFormContext; const pDataset: string; pSelection: TFieldSelection);
var
  Form: TFormContext;
  Args: string;
  Removed: TArray<string>;
begin
  Form:= pForm;
  Args:= WriteDfmArgs(Form.Dfm, pDataset, pSelection.Names, '');
  Removed:= pSelection.RemovedComponents;
  RunFormStep(Form, SUB_WRITE_DFM, Args + JSON_FLAG,
    procedure(const pOutput: string)
    var
      Plan: TFsPlan;
    begin
      if not PlanOf(Form, pOutput, Plan) then Exit;
      Plan.KeepAllBut(Removed);
      if not Confirmed(Form, Plan) then Exit;
      if ModuleIsDirty(OpenModuleOf(Form.Dfm)) then Form.Show('the form has unsaved changes now: nothing written')
      else ApplySelection(Form, SUB_WRITE_DFM, Args, Plan);
    end);
end;

{ The field-selection dialog of one dataset (FR-2). }
procedure SelectDatasetFields(const pForm: TFormContext; const pDataset: string);
var
  Form: TFormContext;
begin
  Form:= pForm;
  RunFormStep(Form, SUB_READ_DFM, ReadDfmArgs(Form.Dfm, pDataset, JSON_FLAG),
    procedure(const pOutput: string)
    var
      Datasets: TArray<TFsDataset>;
      Selection: TFieldSelection;
      Error, Title: string;
    begin
      if not ParseDatasets(pOutput, Datasets, Error) or (Length(Datasets) = 0) then
      begin
        Form.Show(Error);
        Exit;
      end;
      Title:= Form.Title + ' -- ' + Datasets[0].Caption + ', table ' + Datasets[0].TableName;
      Selection:= TFieldSelection.Create(Datasets[0]);
      try
        if not Selection.HasTable then Form.Show(Selection.Refusal)
        else if SelectFields(Title, Selection, ApplyIdeTheme) then WriteSelection(Form, Datasets[0].Name, Selection);
      finally
        Selection.Free;
      end;
    end);
end;

{ The dataset selected in the designer, the only one, or the one the user picks. }
procedure ForDataset(const pForm: TFormContext; const pNext: TDatasetStep);
var
  Form: TFormContext;
  Next: TDatasetStep;
begin
  Form:= pForm;
  Next:= pNext;
  RunFormStep(Form, SUB_READ_DFM, ReadDfmArgs(Form.Dfm, '', JSON_FLAG),
    procedure(const pOutput: string)
    var
      Datasets: TArray<TFsDataset>;
      Error: string;
      Index: Integer;
    begin
      if ParseDatasets(pOutput, Datasets, Error) and (Length(Datasets) = 0) then Error:= 'the form has no dataset';
      if Error <> '' then
      begin
        Form.Show(Error);
        Exit;
      end;
      Index:= DatasetToUse(Datasets, Form.Selected);
      if (Index >= 0) or PickDataset(Form.Title, Datasets, ApplyIdeTheme, Index) then Next(Form, Datasets[Index].Name);
    end);
end;

procedure InvokeReadDataset(Sender: TObject);
var
  Form: TFormContext;
begin
  if ResolveForm('Read Fields from Dataset', Form) then ForDataset(Form, ReadFields);
end;

procedure InvokeReadForm(Sender: TObject);
var
  Form: TFormContext;
begin
  if ResolveForm('Read Fields of All Datasets of Form', Form) then ReadFields(Form, '');
end;

procedure InvokeSelectFields(Sender: TObject);
var
  Form: TFormContext;
begin
  if ResolveForm('Select Fields of Dataset', Form) then ForDataset(Form, SelectDatasetFields);
end;

{$ELSE}

procedure InvokeReadDataset(Sender: TObject);
begin
  Cmd152NotYetAvailable('field-repository-07-read-dataset');
end;

procedure InvokeReadForm(Sender: TObject);
begin
  Cmd152NotYetAvailable('field-repository-08-read-form');
end;

procedure InvokeSelectFields(Sender: TObject);
begin
  Cmd152NotYetAvailable('field-repository-09-select-fields');
end;

procedure InvokeOpenEditor(Sender: TObject);
begin
  Cmd152NotYetAvailable('field-repository');
end;

procedure InvokeRefreshSchema(Sender: TObject);
begin
  Cmd152NotYetAvailable('field-repository-02-refresh');
end;

procedure InvokeMemTableFromCsv(Sender: TObject);
begin
  Cmd152NotYetAvailable('field-repository-05-memtable');
end;

procedure InvokeOrmSource(Sender: TObject);
begin
  Cmd152NotYetAvailable('field-repository-03-orm');
end;

procedure InvokeDataService(Sender: TObject);
begin
  Cmd152NotYetAvailable('field-repository-04-dataservice');
end;

procedure InvokeParamArray(Sender: TObject);
begin
  Cmd152NotYetAvailable('field-repository-06-paramarray');
end;

{$ENDIF}

procedure RegisterRow(const pId, pCaption: string; pVisible: Boolean; pClick: TCmd152Click);
var
  Command: TCmd152Command;
begin
  Command.Id:= pId;
  Command.OwnerLane:= OWNER_LANE;
  Command.ParentPath:= PARENT_PATH;
  Command.AfterCaption:= '';
  Command.Caption:= pCaption;
  Command.Visible:= pVisible;
  Command.Click:= pClick;
  Command.Surfaces:= [csMainMenu];
  Command.Needs:= cnNothing;
  RegisterCmd152(Command);
end;

procedure RegisterCommands;
begin
  RegisterRow('field-repository', 'Open Field Repository Editor...', True, InvokeOpenEditor);
  RegisterRow('field-repository-02-refresh', 'Refresh Schema from Database...', True, InvokeRefreshSchema);
  RegisterRow('field-repository-03-orm', 'Generate / Update ORM Source...', True, InvokeOrmSource);
  RegisterRow('field-repository-04-dataservice', 'Generate DataService Units...', True, InvokeDataService);
  RegisterRow('field-repository-05-memtable', 'FDMemTable from CSV...', True, InvokeMemTableFromCsv);
  RegisterRow('field-repository-06-paramarray', 'Param Array Assistant...', True, InvokeParamArray);
  RegisterRow('field-repository-07-read-dataset', 'Read Fields from Dataset...', True, InvokeReadDataset);
  RegisterRow('field-repository-08-read-form', 'Read Fields of All Datasets of Form...', True, InvokeReadForm);
  RegisterRow('field-repository-09-select-fields', 'Select Fields of Dataset...', True, InvokeSelectFields);
end;

initialization
  RegisterCommands;

end.
