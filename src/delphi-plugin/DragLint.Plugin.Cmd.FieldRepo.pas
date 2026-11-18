unit DragLint.Plugin.Cmd.FieldRepo;

{ 1.52 command unit, owned by lane TTIDE: TableTools migration M10-M11: the
  "Field Repository" submenu that replaces the TableTools Tables menu.

  Six rows are registered in the 1.52 command table (DragLint.Plugin.Cmd152).
  Three are visible: Open editor (launches dl-field-repo.exe on the active
  project's repository), Refresh schema and FDMemTable from CSV (each shells
  `drag-lint repo <verb>`). Three stay hidden until their engine verbs ship
  (ORM source, DataService units, Param Array assistant): hidden, not removed.

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
function MaskedPrompt(const pText: string): string;  // dl:ok unused-public-symbol@9ebf -- test seam: run_v152_TTIDE_menu.ps1 checks it in a console build outside the plugin index

implementation

uses
  System.SysUtils,
  Vcl.Dialogs,
  {$IFNDEF CONSOLE}
  Winapi.Windows,
  System.JSON,
  DragLint.Plugin.ProcRun,
  DragLint.Plugin.CliAsync,
  DragLint.Plugin.ExeResolver,
  ToolsAPI,
  {$ENDIF}
  DragLint.Plugin.Cmd152;

const
  PARENT_PATH = 'Field Repository';
  OWNER_LANE = 'TTIDE';
  EDITOR_EXE = 'dl-field-repo.exe';
  INFO_TIMEOUT_MS = 20000;
  REPO_STALL_MS = 300000;
  NO_PROJECT_MSG = 'drag-lint: open a project first; the field repository belongs to the active project.';

function MaskedPrompt(const pText: string): string;
begin
  Result:= #31 + pText;
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

{$ENDIF}

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
  RegisterRow('field-repository-03-orm', 'Generate / Update ORM Source...', False, InvokeOrmSource);
  RegisterRow('field-repository-04-dataservice', 'Generate DataService Units...', False, InvokeDataService);
  RegisterRow('field-repository-05-memtable', 'FDMemTable from CSV...', True, InvokeMemTableFromCsv);
  RegisterRow('field-repository-06-paramarray', 'Param Array Assistant...', False, InvokeParamArray);
end;

initialization
  RegisterCommands;

end.
