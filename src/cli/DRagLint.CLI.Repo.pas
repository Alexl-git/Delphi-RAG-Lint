unit DRagLint.CLI.Repo;

{ drag-lint 1.52 -- verb family `repo` (TableTools field repository, PLAN D10/D11;
  docs\superpowers\plans\2026-11-16-tabletools-phase1.md section 6).
  DRagLint.CLI.pas parses the flags and calls RunRepoVerb in ONE dispatch line;
  everything else lives here (lane TTE). Implemented: init, info, import-fb, seed-fb,
  refresh-schema, backup, restore, gen-memtable. Firebird is only READ. }

interface

/// <summary>Runs `drag-lint repo &lt;sub-verb&gt; ...`: init, info, import-fb, seed-fb,
/// refresh-schema, backup, restore, gen-memtable, gen-param-array, gen-orm, update-orm, gen-dataservice,
/// migrate, check (the last two: DRagLint.CLI.RepoModel, 1.53) (PLAN D11;
/// gen-param-array is DRagLint.CLI.RepoParamArray and needs no repository; the generator verbs take
/// --code-dir / --server-dir / --client-dir / --table, print a dry-run diff and write only with --apply,
/// --no-backup skips the .BCKn copy).</summary>
/// <param name="pSub">The sub-verb (first positional after `repo`), '' when absent.</param>
/// <param name="pRepo">--repo path, '' when absent (then the project decides the path).</param>
/// <param name="pProject">--project value (a project file), '' when absent.</param>
/// <param name="pConnection">--connection Firebird connection string, '' when absent.</param>
/// <param name="pInFile">--in value, '' when absent.</param>
/// <param name="pOutFile">--output value, '' when absent.</param>
/// <param name="pReplace">--replace.</param>
/// <param name="pJson">--json (or --format json); honoured by `repo info`.</param>
/// <returns>0 = success; 1 = failure or usage error; 2 = schema drift (import-fb) or a
/// malformed input file (restore, gen-memtable).</returns>
/// <remarks>
/// The repository path: --repo wins; else the project's `fieldRepository` key
/// (`_D-RAG\drag-lint-project.json`, relative to the project folder) -- one repository per
/// DATABASE, several projects may point at the same file (ruling A2); else
/// DefaultRepoPath(project). Neither --repo nor --project: usage error, 1. The flags
/// --dry-run and --name are read from the command line here (the dispatch signature is the
/// FRAME contract). Never prints a connection string or password. Not thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Repo.DispatchRepo, DRagLint.CLI.Repo.IsImplementedSub, DRagLint.CLI.Repo.PrintError, DRagLint.CLI.RepoParamArray.RunGenParamArray, SameText, Writeln</para>
/// <para>Returns: EXIT_FAIL; DispatchRepo(pSub, pRepo, pProject, pConnection, pInFile, pOutFile, pReplace, pJson); EXIT_FORMAT; if (E is ERepoError) and E.Message.Contains('does not match') then EXIT_FORMAT</para>
/// <para>Catches: ERepoBackupFormatError (swallowed); Exception (swallowed)</para>
/// <seealso cref="DRagLint.CLI.Repo.DispatchRepo"/>
/// <seealso cref="DRagLint.CLI.Repo.IsImplementedSub"/>
/// <seealso cref="DRagLint.CLI.Repo.PrintError"/>
/// <seealso cref="DRagLint.CLI.RepoParamArray.RunGenParamArray"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RunRepoVerb(const pSub, pRepo, pProject, pConnection, pInFile, pOutFile: string;
  pReplace, pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.DateUtils,
  System.TimeSpan,
  System.JSON,
  FireDAC.Comp.Client,
  DRagLint.Core.Model,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.TextBackup,
  DRagLint.FieldRepo.FbImport,
  DRagLint.FieldRepo.SchemaSeed,
  DRagLint.FieldRepo.CsvMemTable,
  DRagLint.FieldRepo.OrmGen,
  DRagLint.FieldRepo.DataServiceGen,
  DRagLint.CLI.RepoParamArray,
  DRagLint.CLI.RepoModel
  ;

const
  EXIT_OK     = 0;
  EXIT_FAIL   = 1;
  EXIT_FORMAT = 2;
  CFG_KEY     = 'fieldRepository';
  CFG_FILE    = 'drag-lint-project.json';
  { positions in the two sub-verb lists of DispatchRepo / RepoFbVerb }
  LOCAL_INIT    = 0;
  LOCAL_INFO    = 1;
  LOCAL_BACKUP  = 2;
  LOCAL_RESTORE = 3;
  FB_IMPORT     = 0;
  FB_SEED       = 1;
  FB_REFRESH    = 2;
  { positions in the --save-form value list of RepoOrmVerb }
  SAVE_FORM_LEGACY  = 0;
  SAVE_FORM_CURRENT = 1;
  SUB_VERBS   = 'init, info, import-fb, seed-fb, refresh-schema, backup, restore, gen-memtable, gen-param-array, gen-orm, update-orm, gen-dataservice, migrate, check';

function CommandLineFlag(const pFlag: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= 1 to ParamCount do
    if SameText(ParamStr(I), pFlag) then Exit(True);
end;

function CommandLineValue(const pFlag, pDefault: string): string;
var
  I: Integer;
begin
  Result:= pDefault;
  for I:= 1 to ParamCount - 1 do
    if SameText(ParamStr(I), pFlag) then Exit(ParamStr(I + 1));
end;

function ProjectConfigRepo(const pProject: string): string;
var
  Cfg, Dir: string;
  Root: TJSONValue;
  Node: TJSONValue;
begin
  Result:= '';
  Dir:= ExtractFilePath(ExpandFileName(pProject));
  Cfg:= TPath.Combine(TPath.Combine(Dir, DRAG_HOME_DIR), CFG_FILE);
  if not TFile.Exists(Cfg) then Exit;
  Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Cfg));
  if Root = nil then Exit;
  try
    Node:= Root.FindValue(CFG_KEY);
    if (Node is TJSONString) and (TJSONString(Node).Value <> '') then
      Result:= TPath.GetFullPath(TPath.Combine(Dir, TJSONString(Node).Value));
  finally
    Root.Free;
  end;
end;

function ResolveRepoPath(const pRepo, pProject: string; out pPath: string): Boolean;
begin
  pPath:= '';
  if pRepo <> '' then pPath:= ExpandFileName(pRepo)
  else if pProject <> '' then
  begin
    pPath:= ProjectConfigRepo(pProject);
    if pPath = '' then pPath:= DefaultRepoPath(ExpandFileName(pProject));
  end;
  Result:= pPath <> '';
  if not Result then
    Writeln(ErrOutput, 'repo: give --repo <file> or --project <project file>');
end;

procedure PrintError(const pVerb: string; E: Exception);
begin
  Writeln(ErrOutput, 'repo ', pVerb, ': ', E.Message);
end;

{ Best-effort removal of a scratch file: a file that is already gone is not an error. }
procedure RemoveFile(const pFile: string);
begin
  if not DeleteFile(pFile) then Exit;
end;

function RepoInit(const pPath: string): Integer;
begin
  if TFile.Exists(pPath) then
  begin
    Writeln(ErrOutput, 'repo init: the file exists: ', pPath);
    Exit(EXIT_FAIL);
  end;
  CreateRepository(pPath);
  Writeln(pPath);
  Result:= EXIT_OK;
end;

function RepoInfo(const pPath: string; pJson: Boolean): Integer;
var
  Conn: TFDConnection;
  Query: TFDQuery;
  Table: TRepoTable;
  Root, Tables, Meta: TJSONObject;
  Version: Integer;
begin
  if not TFile.Exists(pPath) then
  begin
    Writeln(ErrOutput, 'repo info: not a repository (file missing): ', pPath);
    Exit(EXIT_FAIL);
  end;
  Conn:= OpenRepository(pPath, True);
  try
    Version:= RepoSchemaVersion(Conn);
    Query:= TFDQuery.Create(nil);
    try
      Query.Connection:= Conn;
      Query.FormatOptions.StrsTrim:= False;
      Query.Open('SELECT META_KEY, META_VALUE FROM DL_META ORDER BY META_KEY');
      if pJson then
      begin
        Root:= TJSONObject.Create;
        try
          Root.AddPair('path', pPath);
          Root.AddPair('schema_version', TJSONNumber.Create(Version));
          Tables:= TJSONObject.Create;
          Root.AddPair('tables', Tables);
          for Table in RepoTablesFor(Version) do
            Tables.AddPair(Table.Name, TJSONNumber.Create(RepoRowCount(Conn, Table.Name)));
          Meta:= TJSONObject.Create;
          Root.AddPair('meta', Meta);
          while not Query.Eof do
          begin
            Meta.AddPair(Query.Fields[0].AsString, Query.Fields[1].AsString);
            Query.Next;
          end;
          Writeln(Root.ToJSON);
        finally
          Root.Free;
        end;
      end
      else
      begin
        Writeln('repository: ', pPath);
        Writeln('schema_version: ', Version);
        for Table in RepoTablesFor(Version) do
          Writeln(Table.Name, ': ', RepoRowCount(Conn, Table.Name), ' rows');
        while not Query.Eof do
        begin
          Writeln('meta ', Query.Fields[0].AsString, ': ', Query.Fields[1].AsString);
          Query.Next;
        end;
      end;
    finally
      Query.Free;
    end;
  finally
    Conn.Free;
  end;
  Result:= EXIT_OK;
end;

{ Opens the repository read-write, creating it when it is missing. }
function OpenOrCreateRepo(const pPath: string): TFDConnection;
begin
  if not TFile.Exists(pPath) then CreateRepository(pPath);
  Result:= OpenRepository(pPath, False);
end;

function RepoImportFb(const pPath, pConnection: string; pReplace: Boolean): Integer;
var
  Conn, Fb: TFDConnection;
  Stats: TArray<TRepoImportStat>;
  Stat: TRepoImportStat;
  Table: TRepoTable;
  Backup, Database: string;
  Copied, SrcCount: Integer;
begin
  Result:= EXIT_OK;
  Conn:= OpenOrCreateRepo(pPath);
  try
    if not RepoIsEmpty(Conn) then
    begin
      if not pReplace then
      begin
        Writeln(ErrOutput, 'repo import-fb: the repository is not empty; use --replace to overwrite it');
        Exit(EXIT_FAIL);
      end;
      Backup:= pPath + '.before-import-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.txt';
      BackupRepository(Conn, Backup);
      Writeln('before-import backup: ', Backup);
    end;
    Stats:= ImportFromFirebird(pConnection, Conn, pReplace);
    Fb:= OpenSourceConnection(pConnection, Database);
    try
      for Stat in Stats do
      begin
        Copied:= RepoRowCount(Conn, Stat.TableName);
        FindRepoTable(Stat.TableName, Table);
        if Stat.SourceRows < 0 then
          Writeln(Stat.TableName, ': ', Copied, ' rows (source table ', Table.SourceName, ' missing)')
        else
        begin
          SrcCount:= Integer(Fb.ExecSQLScalar('SELECT COUNT(*) FROM "' + Table.SourceName + '"'));
          Writeln(Stat.TableName, ': ', Copied, ' rows (source ', SrcCount, ')');
          if Copied <> SrcCount then Result:= EXIT_FAIL;
        end;
      end;
    finally
      Fb.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure PrintSeedResult(const pR: TSchemaSeedResult; pDryRun: Boolean);
var
  Line: string;
begin
  if pDryRun then Writeln('dry run: nothing written');
  Writeln('fields added: ', pR.Added, ', changed: ', pR.Changed, ', orphaned: ', pR.Orphaned);
  Writeln('datasets inserted: ', pR.DatasetsInserted, ', updated: ', pR.DatasetsUpdated,
    ', skipped: ', pR.DatasetsSkipped);
  if pDryRun then
    for Line in pR.Diff do Writeln(Line);
  for Line in pR.Warnings do Writeln('warning: ', Line);
end;

function RepoSeed(const pPath, pConnection: string; pMode: TSchemaSeedMode): Integer;
var
  Conn, Fb: TFDConnection;
  Sources: TSchemaSources;
  SeedResult: TSchemaSeedResult;
  Database: string;
  DryRun: Boolean;
begin
  DryRun:= CommandLineFlag('--dry-run');
  if (pMode = ssmRefresh) and (not TFile.Exists(pPath)) then
  begin
    Writeln(ErrOutput, 'repo refresh-schema: the repository does not exist: ', pPath);
    Exit(EXIT_FAIL);
  end;
  if DryRun and (not TFile.Exists(pPath)) then
  begin
    Writeln(ErrOutput, 'repo seed-fb --dry-run: the repository does not exist (run repo init first): ', pPath);
    Exit(EXIT_FAIL);
  end;
  Conn:= OpenOrCreateRepo(pPath);
  try
    Fb:= OpenSourceConnection(pConnection, Database);
    try
      Sources:= OpenSchemaSources(Fb);
      try
        SeedResult:= RunSchemaSeed(Conn, Sources, pMode, DryRun, TTimeZone.Local.ToUniversalTime(Now));
      finally
        FreeSchemaSources(Sources);
      end;
      if (pMode = ssmSeed) and (not DryRun) then SetRepoMeta(Conn, 'source_database', Database);
    finally
      Fb.Free;
    end;
    PrintSeedResult(SeedResult, DryRun);
  finally
    Conn.Free;
  end;
  Result:= EXIT_OK;
end;

function RepoBackup(const pPath, pOutFile: string): Integer;
var
  Conn: TFDConnection;
  Target: string;
begin
  if not TFile.Exists(pPath) then
  begin
    Writeln(ErrOutput, 'repo backup: the repository does not exist: ', pPath);
    Exit(EXIT_FAIL);
  end;
  Target:= if pOutFile <> '' then ExpandFileName(pOutFile) else pPath + '.txt';
  Conn:= OpenRepository(pPath, True);
  try
    BackupRepository(Conn, Target);
  finally
    Conn.Free;
  end;
  Writeln(Target);
  Result:= EXIT_OK;
end;

function RepoRestore(const pPath, pInFile: string; pReplace: Boolean): Integer;
var
  Conn: TFDConnection;
  Work: string;
  Fresh: Boolean;
  FileVersion: Integer;
begin
  if pInFile = '' then
  begin
    Writeln(ErrOutput, 'repo restore: give --in <backup file>');
    Exit(EXIT_FAIL);
  end;
  if not TFile.Exists(pInFile) then
  begin
    Writeln(ErrOutput, 'repo restore: the backup file does not exist: ', pInFile);
    Exit(EXIT_FAIL);
  end;
  Fresh:= not TFile.Exists(pPath);
  { A missing repository is built beside the target and renamed on success, so a
    malformed backup never leaves an empty repository behind. }
  Work:= if Fresh then pPath + '.restoring' else pPath;
  if Fresh then
  begin
    RemoveFile(Work);
    FileVersion:= BackupFileVersion(ExpandFileName(pInFile)); { a missing repository gets the backup's own schema version }
    CreateRepository(Work, if FileVersion = 0 then REPO_SCHEMA_VERSION else FileVersion);
  end;
  try
    Conn:= OpenRepository(Work, False);
    try
      RestoreRepository(Conn, ExpandFileName(pInFile), pReplace);
    finally
      Conn.Free;
    end;
  except
    on E: Exception do
    begin
      if Fresh then RemoveFile(Work);
      raise;
    end;
  end;
  if Fresh then TFile.Move(Work, pPath);
  Writeln(pPath);
  Result:= EXIT_OK;
end;

function GenMemTable(const pInFile, pOutFile: string): Integer;
var
  Source: string;
begin
  if pInFile = '' then
  begin
    Writeln(ErrOutput, 'repo gen-memtable: give --in <csv file>');
    Exit(EXIT_FAIL);
  end;
  try
    Source:= GenMemTableFromCsvFile(ExpandFileName(pInFile), CommandLineValue('--name', 'FDMemTable'));
  except
    on E: ECsvMemTableError do
    begin
      PrintError('gen-memtable', E);
      Exit(EXIT_FORMAT);
    end;
  end;
  if pOutFile <> '' then TFile.WriteAllText(ExpandFileName(pOutFile), Source, TEncoding.ASCII)
  else Write(Source);
  Result:= EXIT_OK;
end;

{ 1.52 TTGEN: the three generator verbs; dry run (diff) unless --apply. }
function RepoOrmVerb(const pSub, pPath: string): Integer;
var
  Opt: TOrmVerbOptions;
  Lines: TStringList;
begin
  Opt:= Default(TOrmVerbOptions);
  Opt.Sub:= pSub;
  Opt.RepoPath:= pPath;
  Opt.CodeDir:= CommandLineValue('--code-dir', '');
  Opt.ServerDir:= CommandLineValue('--server-dir', '');
  Opt.ClientDir:= CommandLineValue('--client-dir', '');
  Opt.Tables:= CommandLineValue('--table', '');
  Opt.Apply:= CommandLineFlag('--apply');
  Opt.Backup:= not CommandLineFlag('--no-backup');
  { B33 (1.52): region 9 binding form; legacy = the form the ORM3 units carry }
  case IndexText(CommandLineValue('--save-form', 'legacy'), ['legacy', 'current']) of
    SAVE_FORM_LEGACY: Opt.SaveForm:= osfLegacy;
    SAVE_FORM_CURRENT: Opt.SaveForm:= osfCurrent;
  else
    Writeln(ErrOutput, 'repo ', pSub, ': --save-form takes legacy or current');
    Exit(EXIT_FAIL);
  end;
  Lines:= TStringList.Create;
  try
    Result:= RunOrmGenVerb(Opt, Lines);
    if Result = EXIT_OK then Write(Lines.Text) else Write(ErrOutput, Lines.Text);
  finally
    Lines.Free;
  end;
end;

{ The three verbs that read Firebird; they need --connection. }
function RepoFbVerb(const pSub, pPath, pConnection: string; pReplace: Boolean): Integer;
begin
  Result:= EXIT_FAIL;
  if pConnection = '' then
    Writeln(ErrOutput, 'repo ', pSub, ': give --connection "Database=...;User=...;Password=..."')
  else
    case IndexText(pSub, ['import-fb', 'seed-fb', 'refresh-schema']) of
      FB_IMPORT: Result:= RepoImportFb(pPath, pConnection, pReplace);
      FB_SEED: Result:= RepoSeed(pPath, pConnection, ssmSeed);
      FB_REFRESH: Result:= RepoSeed(pPath, pConnection, ssmRefresh);
    end;
end;

function DispatchRepo(const pSub, pRepo, pProject, pConnection, pInFile, pOutFile: string;  // dl:ok too-many-parameters@fd6f -- REVIEWED 2026-11-17 v152 TTE: same flag list as RunRepoVerb, split out only to keep the exception handler apart
  pReplace, pJson: Boolean): Integer;
var
  Path: string;
begin
  Result:= EXIT_FAIL;
  if SameText(pSub, 'gen-memtable') then Exit(GenMemTable(pInFile, pOutFile));
  if not ResolveRepoPath(pRepo, pProject, Path) then Exit;
  if MatchText(pSub, ['gen-orm', 'update-orm', 'gen-dataservice']) then Exit(RepoOrmVerb(pSub, Path));
  if IsRepoModelSub(pSub) then Exit(RunRepoModelVerb(pSub, Path, pJson)); // 1.53 FR-MODEL: migrate, check
  case IndexText(pSub, ['init', 'info', 'backup', 'restore']) of
    LOCAL_INIT: Result:= RepoInit(Path);
    LOCAL_INFO: Result:= RepoInfo(Path, pJson);
    LOCAL_BACKUP: Result:= RepoBackup(Path, pOutFile);
    LOCAL_RESTORE: Result:= RepoRestore(Path, pInFile, pReplace);
  else
    Result:= RepoFbVerb(pSub, Path, pConnection, pReplace);
  end;
end;

function IsImplementedSub(const pSub: string): Boolean;
begin
  Result:= MatchText(pSub, ['init', 'info', 'import-fb', 'seed-fb', 'refresh-schema', 'backup',
    'restore', 'gen-memtable', 'gen-orm', 'update-orm', 'gen-dataservice']) or IsRepoModelSub(pSub);
end;

function RunRepoVerb(const pSub, pRepo, pProject, pConnection, pInFile, pOutFile: string;  // dl:ok too-many-parameters@96de -- REVIEWED 2026-11-17 v152 TTE: one positional per CLI flag keeps the CLI.pas dispatch a single line with no options builder there (FRAME contract, TT plan section 6 E1 shape)
  pReplace, pJson: Boolean): Integer;
begin
  if SameText(pSub, 'gen-param-array') then Exit(RunGenParamArray(pProject, pInFile, pJson)); // reads no repository: dispatched before ResolveRepoPath
  if not IsImplementedSub(pSub) then
  begin
    Writeln(ErrOutput, 'repo: unknown sub-verb "', pSub, '"; use one of: ', SUB_VERBS);
    Exit(EXIT_FAIL);
  end;
  try
    Result:= DispatchRepo(pSub, pRepo, pProject, pConnection, pInFile, pOutFile, pReplace, pJson);
  except
    on E: ERepoBackupFormatError do
    begin
      PrintError(pSub, E);
      Result:= EXIT_FORMAT;
    end;
    on E: Exception do
    begin
      PrintError(pSub, E);
      Result:= if (E is ERepoError) and E.Message.Contains('does not match') then EXIT_FORMAT else EXIT_FAIL;
    end;
  end;
end;

end.
