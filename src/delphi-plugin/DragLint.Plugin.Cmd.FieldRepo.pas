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
/// <remarks>Pure; no side effects. The engine resolves the repository file from
/// the project's fieldRepository key.</remarks>
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
/// <remarks>Pure; no side effects.</remarks>
function FieldRepoGenArgs(const pCodeDir, pServerDir, pClientDir, pTables: string; pApply: Boolean): string;  // dl:ok unused-public-symbol@30ea -- REVIEWED 2026-11-18 v152 BK-TTFINISH: test seam: run_v152_TTIDE_menu.ps1 checks it in a console build outside the plugin index

/// <summary>The lines of a generator dry run worth a message box: the diff lines
/// ('--- ', '+++ ', '@@', '-', '+') are dropped.</summary>
/// <param name="pOutput">The verb's stdout.</param>
/// <param name="pMaxLines">Most lines kept; the rest is counted in a final '... n more lines' line.</param>
/// <returns>The kept lines joined with CRLF.</returns>
/// <remarks>Pure; no side effects.</remarks>
function FieldRepoRunSummary(const pOutput: string; pMaxLines: Integer): string;  // dl:ok unused-public-symbol@3193 -- REVIEWED 2026-11-18 v152 BK-TTFINISH: test seam: run_v152_TTIDE_menu.ps1 checks it in a console build outside the plugin index

function MaskedPrompt(const pText: string): string;  // dl:ok unused-public-symbol@9ebf -- test seam: run_v152_TTIDE_menu.ps1 checks it in a console build outside the plugin index

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
  Vcl.FileCtrl,
  ToolsAPI,
  {$ENDIF}
  DragLint.Plugin.Cmd152;

const
  PARENT_PATH = 'Field Repository';
  OWNER_LANE = 'TTIDE';
  EDITOR_EXE = 'dl-field-repo.exe';
  INFO_TIMEOUT_MS = 20000;
  REPO_STALL_MS = 300000;
  SUMMARY_LINES = 40;
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
  RunCliAsync(FieldRepoCommandLine(Exe, 'refresh-schema', Project, '--connection "' + Connection + '"'),
    procedure(pExitCode: Integer; const pOutput: string)
    begin
      ShowRunResult('repo refresh-schema', pExitCode, pOutput);
    end, REPO_STALL_MS);
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

{ pBaseCmd + pDryArgs (dry run), summary, confirm, then pBaseCmd + pApplyArgs. }
procedure RunDryThenApply(const pTitle, pBaseCmd, pDryArgs, pApplyArgs: string);
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
        sLineBreak + sLineBreak + 'Write these files now?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
      RunCliAsync(pBaseCmd + ' ' + pApplyArgs,
        procedure(pApplyExit: Integer; const pApplyOutput: string)
        begin
          ShowRunResult(pTitle, pApplyExit, FieldRepoRunSummary(pApplyOutput, SUMMARY_LINES));
        end, REPO_STALL_MS);
    end, REPO_STALL_MS);
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

{$ELSE}

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
end;

initialization
  RegisterCommands;

end.
