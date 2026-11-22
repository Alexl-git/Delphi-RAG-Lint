unit DRagLint.CLI.Workspace;

// ---------------------------------------------------------------------------
// The `workspace`, `forms-csv`, `menu-tree` and `menu-drift` verbs (lane v1511 SPLIT T07).
// Moved verbatim out of DRagLint.CLI.
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint workspace index|status|add [--config PATH]: index each project of the workspace config into the shared DB, list its projects and file counts, or append a project entry.</summary>
/// <param name="AArgs">SubCommand index|status|add, --config, the project file for add.</param>
/// <returns>0 on success, nonzero on a usage or I/O error.</returns>
/// <exception cref="Exception"><!-- drag-lint:auto exc -->via DRagLint.Workspace.Config.TWorkspaceConfigIO.LoadFromFile: Invalid JSON in workspace config: %s</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: AnsiString, BoolToStr, CloseHandle, CreatePipe, CreateProcessW, Default, DRagLint.CLI.Workspace.DoWorkspace.CreatePipes, DRagLint.CLI.Workspace.DoWorkspace.SpawnSync, DRagLint.Storage.FileMembership.ConnectReadOnly, DRagLint.Workspace.Config.TWorkspaceConfigIO.FindWorkspaceRoot (+16 more)</para>
/// <para>Returns: 0; 2; 1</para>
/// <para>Complexity: 16 (cyclomatic, outer body), 178 lines (full implementation)</para>
/// <para>SQL: reads FILES</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Workspace.DoWorkspace.CreatePipes"/>
/// <seealso cref="DRagLint.CLI.Workspace.DoWorkspace.SpawnSync"/>
/// <seealso cref="DRagLint.Storage.FileMembership.ConnectReadOnly"/>
/// <seealso cref="DRagLint.Workspace.Config.TWorkspaceConfigIO.FindWorkspaceRoot"/>
/// <seealso cref="DRagLint.Workspace.Config.TWorkspaceConfigIO.LoadFromFile"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoWorkspace(const AArgs: TArgs): Integer;

/// <summary>Implements the forms-csv CLI command: generates a navigation-map CSV
/// for a project index and writes it to --output or stdout. Multi-DB: when the
/// caller supplies no --db, falls back through ResolveConsumerDbs (manifest /
/// platform resolution) so forms-csv sees the same DB set as query/lsp/serve;
/// the first resolved path is primary (drives enumeration), the rest widen the
/// caller-search scope so cross-DB launch chains (e.g. CLIENT -> COMMON) are
/// not misreported as dead.</summary>
/// <param name="AArgs"><!-- drag-lint:auto type -->const TArgs</param>
/// <returns><!-- drag-lint:auto -->Integer -- Observed: 0.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs, DRagLint.Core.OutputEncoding.WriteOutputFile, DRagLint.FormsMap.GenerateFormsCsv/3, Write, Writeln</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs"/>
/// <seealso cref="DRagLint.Core.OutputEncoding.WriteOutputFile"/>
/// <seealso cref="DRagLint.FormsMap.GenerateFormsCsv"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoFormsCsv(const AArgs: TArgs): Integer;

/// <summary>menu-tree: the menu tree a project BUILDS IN CODE, read statically
/// (spec docs\superpowers\specs\2026-10-23-code-built-menu-reader-design.md, section 5).</summary>
/// <param name="AArgs">--project, --db (required), --root &lt;QName&gt;, --with-dfm, --format text|json|paths, --output.</param>
/// <returns>0 when it ran; 2 usage / setup (no --db, project not in the db,
/// unknown --root); 3 stale index (a file it must read changed since it was
/// indexed -- refused, never answered from); 1 any other error.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.Core.CliError.WriteCliError, DRagLint.Core.OutputEncoding.WriteOutputFile, DRagLint.MenuTree.Dfm.AddDfmRoots, DRagLint.MenuTree.TMenuTree.ToJson, DRagLint.MenuTree.TMenuTree.ToPaths, DRagLint.MenuTree.TMenuTree.ToText, DRagLint.MenuTree.TMenuWalker.Create, DRagLint.MenuTree.TMenuWalker.Walk, LowerCase, Write, Writeln</para>
/// <para>Returns: 2; EXIT_STALE_INDEX; 1; 0</para>
/// <para>Complexity: 12 (cyclomatic, outer body), 66 lines (full implementation)</para>
/// <para>Catches: EMenuTreeSetup (swallowed); EMenuTreeStale (swallowed); Exception (swallowed)</para>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.Core.CliError.WriteCliError"/>
/// <seealso cref="DRagLint.Core.OutputEncoding.WriteOutputFile"/>
/// <seealso cref="DRagLint.MenuTree.Dfm.AddDfmRoots"/>
/// <seealso cref="DRagLint.MenuTree.TMenuTree.ToJson"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoMenuTree(const AArgs: TArgs): Integer;

/// <summary>menu-drift: the code-built menu tree (menu-tree) against the
/// registry's ide-menu surfaces (spec section 7): MISSING / MOVED /
/// UNREGISTERED / NOTE lines and 'menu-drift: missing=N unregistered=N moved=N notes=N'.</summary>
/// <param name="AArgs">--project, --db (required), --registry &lt;features dir&gt; (required), --with-dfm, --format text|json, --output.</param>
/// <returns>0 no drift; 1 drift; 2 usage / setup (no --db / --registry,
/// project not in the db, unreadable registry); 3 stale index (refused).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.Core.CliError.WriteCliError, DRagLint.Core.OutputEncoding.WriteOutputFile, DRagLint.MenuDrift.ComputeMenuDrift, DRagLint.MenuDrift.TMenuDriftReport.HasDrift, DRagLint.MenuDrift.TMenuDriftReport.ToJson, DRagLint.MenuDrift.TMenuDriftReport.ToText, DRagLint.MenuDrift.TMenuRegistry.Create, DRagLint.MenuDrift.TMenuRegistry.HasAppMenus, DRagLint.MenuDrift.TMenuRegistry.LoadFromDir (+8 more)</para>
/// <para>Returns: 2; EXIT_STALE_INDEX; 1; if Rep.HasDrift then 1</para>
/// <para>Complexity: 16 (cyclomatic, outer body), 88 lines (full implementation)</para>
/// <para>Catches: EMenuDriftSetup (swallowed); EMenuTreeSetup (swallowed); EMenuTreeStale (swallowed); Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.Core.CliError.WriteCliError"/>
/// <seealso cref="DRagLint.Core.OutputEncoding.WriteOutputFile"/>
/// <seealso cref="DRagLint.MenuDrift.ComputeMenuDrift"/>
/// <seealso cref="DRagLint.MenuDrift.TMenuDriftReport.HasDrift"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoMenuDrift(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.Model, DRagLint.CLI.ConsumerDbs, Winapi.Windows, DRagLint.Core.CliError,
  DRagLint.Core.OutputEncoding, System.SysUtils, System.Classes, System.IOUtils, System.NetEncoding,
  System.JSON, System.DateUtils, System.Generics.Collections, System.SyncObjs, FireDAC.Comp.Client,
  FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DApt, DRagLint.Storage.FileMembership, DRagLint.FormsMap,
  DRagLint.MenuTree, DRagLint.MenuTree.Dfm, DRagLint.MenuDrift, DRagLint.Workspace.Config;

// v0.34: drag-lint workspace index|status|add [--config PATH]
// index: loads workspace config, indexes each project into the shared DB.
// status: lists projects and file counts in the shared DB.
// add <projfile>: appends a project entry and saves.
function DoWorkspace(const AArgs: TArgs): Integer;
var
  CfgPath     : string                    ;
  Cfg         : TWorkspaceConfig          ;
  SharedDbPath: string                    ;
  P           : TWorkspaceProject         ;
  CmdLine     : string                    ;
  CmdLineBuf  : array[0..2047] of WideChar;
  SA          : TSecurityAttributes       ;
  SD          : TSecurityDescriptor       ;
  ReadPipe    : THandle                   ;
  WritePipe   : THandle                   ;
  SI          : TStartupInfoW             ;
  PI          : TProcessInformation       ;
  Buffer      : array[0..4095] of AnsiChar;
  BytesRead   : DWORD                     ;
  NewProj     : TWorkspaceProject         ;

  function SpawnSync(const ACmd: string): Integer;
  begin
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput := INVALID_HANDLE_VALUE;
    FillChar(PI, SizeOf(PI), 0);
    StrPCopy(CmdLineBuf, ACmd);
    if not CreateProcessW(nil, CmdLineBuf, nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then begin Writeln('ERROR: failed to spawn: ', ACmd);
    Result:= -1; Exit; end;
    // Drain stdout/stderr while child runs
    CloseHandle(WritePipe);
    WritePipe:= INVALID_HANDLE_VALUE;
    repeat
      if ReadFile(ReadPipe, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then begin Buffer[BytesRead]:= #0;
      Write(AnsiString(Buffer)); end
      else Break;
    until BytesRead = 0;
    WaitForSingleObject(PI.hProcess, INFINITE);
    var ExitCodeVal: DWORD:= 0;
    GetExitCodeProcess(PI.hProcess, ExitCodeVal);
    Result:= Integer(ExitCodeVal);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread );
  end; // function

// Re-create pipes for each project spawn
  procedure CreatePipes;
  begin
    FillChar(SA, SizeOf(SA), 0);
    SA.nLength:= SizeOf(SA);
    SA.bInheritHandle:= True;
    InitializeSecurityDescriptor(@SD, SECURITY_DESCRIPTOR_REVISION);
    SetSecurityDescriptorDacl(@SD, True, nil, False);
    SA.lpSecurityDescriptor:= @SD;
    CreatePipe(ReadPipe, WritePipe, @SA, 0);
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
  end;

var
  ExeName     : string       ;
  AbsProjPath : string       ;
  ProjectCount: Integer      ;
  SuccessCount: Integer      ;
  Conn        : TFDConnection;
  Q           : TFDQuery     ;
  FileCount   : Integer      ;
  PathPrefix  : string       ;
begin
  // --- Locate workspace config ---
  CfgPath:= AArgs.WorkspaceConfig;
  if CfgPath = '' then
  begin
    // Try current dir and parents
    CfgPath:= TWorkspaceConfigIO.FindWorkspaceRoot(GetCurrentDir);
    if CfgPath <> '' then CfgPath:= TPath.Combine(CfgPath, WORKSPACE_FILENAME)
    else begin Writeln('ERROR: .drag-lint-workspace.json not found. ' + 'Use --config <path> or run from a workspace root.');
    Exit(2); end;
  end;
  if not TFile.Exists(CfgPath) then begin Writeln('ERROR: workspace config not found: ', CfgPath);
  Exit(2); end;

  // --- workspace add ---
  if AArgs.SubCommand = 'add' then
  begin
    if AArgs.Target = '' then begin Writeln('Usage: drag-lint workspace add <projfile> [--config PATH]');
    Exit (2 ); end;
    Cfg:= TWorkspaceConfigIO.LoadFromFile(CfgPath);
    NewProj:= Default(TWorkspaceProject);
    NewProj.Path:= AArgs.Target;
    NewProj.ScanDir:= TDirectory.Exists( TPath.Combine(Cfg.RootDir, AArgs.Target));
    SetLength(Cfg.Projects, Length(Cfg.Projects) + 1);
    Cfg.Projects[High(Cfg.Projects)]:= NewProj;
    TWorkspaceConfigIO.SaveToFile(Cfg, CfgPath);
    Writeln(Format('Added project "%s" to workspace config: %s', [AArgs.Target, CfgPath]));
    Exit(0);
  end; // if

  // --- workspace status ---
  if AArgs.SubCommand = 'status' then
  begin
    Cfg:= TWorkspaceConfigIO.LoadFromFile(CfgPath);
    SharedDbPath:= TPath.Combine(Cfg.RootDir, Cfg.SharedDb);
    Writeln(Format('Workspace: %s', [Cfg.Name]));
    Writeln(Format('Config:    %s', [CfgPath     ]));
    Writeln(Format('SharedDB:  %s', [SharedDbPath]));
    Writeln(Format('Projects:  %d', [Length(Cfg.Projects)]));
    Writeln('');
    if not TFile.Exists(SharedDbPath) then
    begin
      Writeln('(shared DB not yet created -- run "workspace index" first)');
      for P in Cfg.Projects do Writeln(Format('  %s  [scan_dir=%s]', [P.Path, BoolToStr(P.ScanDir, True)]));
      Exit(0);
    end;
    Conn:= TFDConnection.Create(nil);
    Q   := TFDQuery     .Create(nil);
    try
      ConnectReadOnly(Conn, SharedDbPath); { a reader: never FireDAC's Exclusive/Delete defaults }
      Q   .Connection := Conn;
      for P in Cfg.Projects do
      begin
        AbsProjPath:= TPath.GetFullPath( TPath.Combine(Cfg.RootDir, P.Path));
        PathPrefix:= IncludeTrailingPathDelimiter(AbsProjPath);
        Q.Close;
        Q.Sql.Text:= 'SELECT COUNT(*) AS cnt FROM files WHERE path LIKE :prefix';
        Q.ParamByName('prefix').AsWideString:= PathPrefix + '%';
        Q.Open;
        FileCount:= 0;
        if not Q.IsEmpty then FileCount:= Q.FieldByName('cnt').AsInteger;
        Writeln(Format('  %-50s  %d file(s)', [P.Path, FileCount]));
      end;
    finally
      Q.Free;
      Conn.Free;
    end; // try
    Exit(0);
  end; // if

  // --- workspace index ---
  if (AArgs.SubCommand <> 'index') and (AArgs.SubCommand <> '') then
  begin
    Writeln('ERROR: unknown workspace subcommand: ', AArgs.SubCommand);
    Writeln('Available: index, status, add');
    Exit   (2                              );
  end;

  Cfg:= TWorkspaceConfigIO.LoadFromFile(CfgPath);
  SharedDbPath:= TPath.Combine(Cfg.RootDir, Cfg.SharedDb);

  ExeName:= ParamStr(0); // path to this executable

  Writeln(Format('Workspace: %s', [Cfg.Name]));
  Writeln(Format('SharedDB:  %s', [SharedDbPath]));
  Writeln(Format('Projects:  %d', [Length(Cfg.Projects)]));

  ProjectCount:= Length(Cfg.Projects);
  SuccessCount:= 0;
  ReadPipe    := INVALID_HANDLE_VALUE;
  WritePipe   := INVALID_HANDLE_VALUE;

  for P in Cfg.Projects do
  begin
    AbsProjPath:= TPath.GetFullPath(TPath.Combine(Cfg.RootDir, P.Path));
    Writeln('');
    Writeln(Format('[%s]', [P.Path]));

    if P.ScanDir then CmdLine:= Format('"%s" index "%s" --db "%s"', [ExeName, AbsProjPath, SharedDbPath])
    else CmdLine:= Format('"%s" index --project "%s" --db "%s"', [ExeName, AbsProjPath, SharedDbPath]);

    Writeln(CmdLine);
    CreatePipes;
    var EC:= SpawnSync(CmdLine);
    if ReadPipe <> INVALID_HANDLE_VALUE then begin CloseHandle(ReadPipe);
    ReadPipe:= INVALID_HANDLE_VALUE; end;
    if WritePipe <> INVALID_HANDLE_VALUE then begin CloseHandle(WritePipe);
    WritePipe:= INVALID_HANDLE_VALUE; end;
    if EC = 0 then Inc(SuccessCount)
    else Writeln(Format('WARNING: index returned exit code %d for: %s', [EC, P.Path]));
  end; // for

  Writeln('');
  Writeln(Format('Done: %d/%d projects indexed into %s', [SuccessCount, ProjectCount, SharedDbPath]));

  if SuccessCount = ProjectCount then Result:= 0
  else Result:= 1;
end; // begin

function DoFormsCsv(const AArgs: TArgs): Integer;
var
  DbPaths: TArray<string>;
  Csv    : string;
  P      : string;
begin
  if not ExplicitDbsExist(AArgs, 'forms-csv') then Exit(2);
  DbPaths:= ResolveConsumerDbs(AArgs);
  if Length(DbPaths) = 0 then begin Writeln(ErrOutput, 'forms-csv: need --db <index.sqlite>');
  Exit(2); end;
  for P in DbPaths do
    if not TFile.Exists(P) then begin Writeln(ErrOutput, 'forms-csv: db not found: ', P);
    Exit(2); end;
  try
    Csv:= DRagLint.FormsMap.GenerateFormsCsv(DbPaths, AArgs.ProjectPath, AArgs.RootForm);
  except
    on E: Exception do begin Writeln(ErrOutput, 'forms-csv: ', E.Message);
    Exit(1); end;
  end;
  if AArgs.Output <> '' then
  begin
    WriteOutputFile(AArgs.Output, Csv);
    Writeln('forms-csv: wrote ', AArgs.Output);
  end
  else Write(Csv);
  Result:= 0;
end; // function

function DoMenuTree(const AArgs: TArgs): Integer;  // dl:ok too-many-exit-points@9176 -- verb guard clauses: each Exit is one documented exit code (2 usage / setup, 3 stale, 1 other)
const
  EXIT_STALE_INDEX = 3;  { spec 5: a stale index is refused, never answered from }
var
  Walker: TMenuWalker;
  Tree  : TMenuTree;
  Fmt   : string;
  Txt   : string;
begin
  if not ExplicitDbsExist(AArgs, 'menu-tree') then Exit(2);
  if Length(AArgs.DbPaths) = 0 then
  begin
    Writeln(ErrOutput, 'menu-tree: need --db <index.sqlite>');
    Exit(2);
  end;
  if AArgs.ProjectPath = '' then
  begin
    Writeln(ErrOutput, 'menu-tree: need --project <X.dproj>');
    Exit(2);
  end;
  Fmt:= if AArgs.Format = '' then 'text' else LowerCase(AArgs.Format);
  if (Fmt <> 'text') and (Fmt <> 'json') and (Fmt <> 'paths') then
  begin
    Writeln(ErrOutput, 'menu-tree: --format must be text, json or paths');
    Exit(2);
  end;
  Tree:= nil;
  try
    Walker:= TMenuWalker.Create(AArgs.DbPaths, AArgs.ProjectPath);
    try
      Tree:= Walker.Walk(AArgs.RootForm);
    finally
      Walker.Free;
    end;
    if AArgs.WithDfm then AddDfmRoots(Tree, AArgs.DbPaths[0], AArgs.ProjectPath);
  except
    on E: EMenuTreeStale do
    begin
      WriteCliError(CLI_ERR_STALE_INDEX, 'menu-tree: stale index: ' + E.Message, AArgs.AsJson, '', '');
      Exit(EXIT_STALE_INDEX);
    end;
    on E: EMenuTreeSetup do
    begin
      Writeln(ErrOutput, 'menu-tree: ', E.Message);
      Exit(2);
    end;
    on E: Exception do
    begin
      Writeln(ErrOutput, 'menu-tree: ', E.ClassName, ': ', E.Message);
      Exit(1);
    end;
  end;
  try
    if Fmt = 'json' then Txt:= Tree.ToJson(DRAGLINT_VERSION, AArgs.ProjectPath, AArgs.DbPaths[0])
    else if Fmt = 'paths' then Txt:= Tree.ToPaths
    else Txt:= Tree.ToText;
  finally
    Tree.Free;
  end;
  if AArgs.Output <> '' then
  begin
    WriteOutputFile(AArgs.Output, Txt);
    Writeln('menu-tree: wrote ', AArgs.Output);
  end
  else Write(Txt);
  Result:= 0;
end; // function
function DoMenuDrift(const AArgs: TArgs): Integer;  // dl:ok too-many-exit-points@50e0 -- verb guard clauses: each Exit is one documented exit code (2 usage / setup, 3 stale, 1 drift or other)
const
  EXIT_STALE_INDEX = 3;  { spec 5: a stale index is refused, never answered from }
var
  Walker: TMenuWalker;
  Tree  : TMenuTree;
  Reg   : TMenuRegistry;
  Rep   : TMenuDriftReport;
  Fmt   : string;
  Txt   : string;
  RegDir: string;
begin
  if not ExplicitDbsExist(AArgs, 'menu-drift') then Exit(2);
  if Length(AArgs.DbPaths) = 0 then
  begin
    Writeln(ErrOutput, 'menu-drift: need --db <index.sqlite>');
    Exit(2);
  end;
  { dxBar spec decision 6: an application's registry lives in <project>\_D-RAG\menu-registry }
  RegDir:= AArgs.RegistryDir;
  if (RegDir = '') and (AArgs.ProjectPath <> '') then
  begin
    RegDir:= TPath.Combine(TPath.Combine(ExtractFilePath(ExpandFileName(AArgs.ProjectPath)), '_D-RAG'), 'menu-registry');
    if not TDirectory.Exists(RegDir) then RegDir:= '';
  end;
  if (AArgs.ProjectPath = '') or (RegDir = '') then
  begin
    Writeln(ErrOutput, 'menu-drift: need --project <X.dproj> and --registry <features dir> (or a <project>\_D-RAG\menu-registry folder)');
    Exit(2);
  end;
  Fmt:= if AArgs.Format = '' then 'text' else LowerCase(AArgs.Format);
  if (Fmt <> 'text') and (Fmt <> 'json') then
  begin
    Writeln(ErrOutput, 'menu-drift: --format must be text or json');
    Exit(2);
  end;
  Tree:= nil;
  Reg := TMenuRegistry.Create;
  try
    try
      Reg.LoadFromDir(RegDir);
      Walker:= TMenuWalker.Create(AArgs.DbPaths, AArgs.ProjectPath);
      try
        Tree:= Walker.Walk;
      finally
        Walker.Free;
      end;
      { an app-menu surface is a .dfm menu: compare the .dfm tree too }
      if AArgs.WithDfm or Reg.HasAppMenus then AddDfmRoots(Tree, AArgs.DbPaths[0], AArgs.ProjectPath);
    except
      on E: EMenuTreeStale do
      begin
        WriteCliError(CLI_ERR_STALE_INDEX, 'menu-drift: stale index: ' + E.Message, AArgs.AsJson, '', '');
        Exit(EXIT_STALE_INDEX);
      end;
      on E: EMenuTreeSetup do
      begin
        Writeln(ErrOutput, 'menu-drift: ', E.Message);
        Exit(2);
      end;
      on E: EMenuDriftSetup do
      begin
        Writeln(ErrOutput, 'menu-drift: ', E.Message);
        Exit(2);
      end;
      on E: Exception do
      begin
        Writeln(ErrOutput, 'menu-drift: ', E.ClassName, ': ', E.Message);
        Exit(1);
      end;
    end;
    Rep:= ComputeMenuDrift(Tree, Reg);
    try
      Txt:= if Fmt = 'json' then Rep.ToJson else Rep.ToText;
      Result:= if Rep.HasDrift then 1 else 0;
    finally
      Rep.Free;
    end;
  finally
    Tree.Free;
    Reg.Free;
  end;
  if AArgs.Output <> '' then
  begin
    WriteOutputFile(AArgs.Output, Txt);
    Writeln('menu-drift: wrote ', AArgs.Output);
  end
  else Write(Txt);
end; // function

end.
