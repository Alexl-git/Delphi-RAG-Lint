unit DRagLint.CLI;

interface

const
  VERSION = '0.65.1-alpha';

function Run: Integer;

implementation

uses
  Winapi.Windows
  , Winapi.ShellAPI
  , System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , System.StrUtils
  , System.DateUtils
  , System.RegularExpressions
  , System.Generics.Collections
  , System.Math
  , Data.DB
  , FireDAC.Comp.Client
  , FireDAC.Phys.SQLite
  , FireDAC.Stan.Async
  , FireDAC.Stan.Def
  , FireDAC.Stan.Param
  , { v0.42: lets TFDParam.SetAsX inline (was H2443) }
    FireDAC.DApt
  , DRagLint.Core   .Model
  , DRagLint.Core   .Interfaces
  , DRagLint.Core   .Indexer
  , DRagLint.Storage.SQLite
  , DRagLint.Parser .Delphi13
  , DRagLint.Parser .DFM
  , DRagLint.Parser .Sql
  , DRagLint.Sql    .FbSnapshot
  , DRagLint.Sql    .OrmLinker
  , DRagLint.Lint   .Linter
  , DRagLint.Lint   .ProjectChecks
  , DRagLint.Lint   .ProjectRules
  , DRagLint.Project.Resolver
  , DRagLint.FormsMap
  , DRagLint.MCP        .Server
  , DRagLint.LSP        .Server
  , DRagLint.Hover      .Renderer
  , DRagLint.Context    .Bundler
  , DRagLint.Resolver   .TypeAt
  , DRagLint.Refactor   .Rename
  , DRagLint.Refactor   .DocStub
  , DRagLint.Refactor   .DeadCode
  , DRagLint.Refactor   .TestStub
  , DRagLint.Format     .Yadf
  , DRagLint.Diagnostics.CompileCheck
  , DRagLint.Diagnostics.AstChecks
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Workspace  .Config
  , DRagLint.Index      .Manifest
  , DRagLint.Index      .Glob
  , DRagLint.Index      .IgnoreFiles
  , DRagLint.Index      .Closure
  , DRagLint.Index      .Reconcile
  , DRagLint.Index      .Plan
  , DRagLint.Index      .DbSelect
  , DRagLint.Index      .Drift
  , DRagLint.Index      .Coverage
  , DRagLint.Wiring
  ;

type
  TArgs = record
    Command         : string        ;
    SubCommand      : string        ;
    Path            : string        ;
    DbPath          : string        ;
    DbPaths         : TArray<string>;
    ExcludeUnder    : TArray<string>; // v0.42: --exclude-under <dir> (repeatable)
    Deep            : Boolean       ; // v0.42: emit identifier usage refs
    DeepExplicit    : Boolean       ; // --deep/--shallow was given on the cmd line
    Width           : string        ; // v0.42: usages width narrow|wide|very-wide
    Name            : string        ;
    QName           : string        ;
    OfName          : string        ; // v11 (M1): query ancestors --of <ancestor> (is-descendant check)
    InFile          : string        ; // --in <file.pas> (resolve-uses scope context)
    Rule            : string        ;
    ProjectPath     : string        ;
    RulesDir        : string        ; // --rules-dir <path>: external .scm rules location (default <exe-dir>\rules)
    Disable         : string        ; // --disable id1,id2,...: rule ids to drop from lint output
    LayersPath      : string        ; // --layers <file.json>: architecture-layer config for lint-project
    Format          : string        ;
    Output          : string        ;
    OutputDir       : string        ;
    Limit           : Integer       ;
    SortBy          : string        ;
    ScanLibraries   : Boolean       ;
    ScanLibrariesAll: Boolean       ; // --scan-libraries-all: every platform subkey
    AsJson          : Boolean       ;
    DryRun          : Boolean       ;
    Watch           : Boolean       ;
    Interval        : Integer       ;
    Open            : Boolean       ;
    ShowHelp        : Boolean       ;
    ShowVersion     : Boolean       ;
    // v0.16: query find flags
    DocTag     : string ;
    DocContains: string ;
    NoDocs     : Boolean;
    Kind       : string ;
    PublicOnly : Boolean;
    // v0.40.4: uses-report flags
    IncludeExternal: Boolean; // --include-external
    AllSources     : Boolean; // --all-sources (default: only first DB's files)
    // v0.40.5 Tier 2/3: Firebird snapshot + ORM linker
    FbConnection: string ; // --connection "Database=...;User=...;Password=...;DriverID=FB"
    OrmTtl      : Integer; // unused for now; reserved for cache-invalidation control
    // v0.16 Task 13: .drag-lint.json "docs" section
    Docs: TDocConfig;
    // v0.17: blast-radius pack
    Depth         : Integer;
    IncludeImpl   : Boolean;
    AllVisibility : Boolean;
    WiringCoverage: Boolean; // v8: --coverage for the wiring command
    ContextLines  : Integer; // v0.17: find-callers --context N
    // v0.18: context bundle
    Task               : string ; // raw --task value
    Verb               : string ; // parsed verb (modify/inspect/refactor/delete/extend)
    BundleQName        : string ; // parsed qname from --task
    MaxCallers         : Integer; // --max-callers N (default 5)
    IncludeClassSurface: Boolean; // default true
    FullSurface        : Boolean; // --full-surface: keep DFM component fields (default lean)
    BenchN             : Integer; // --n N for bench-context (default 20)
    // v0.19: typeat
    Position: string; // raw <file>:<line>:<col>
    // v0.24: rename
    RenameTo: string ; // --to <NewName>
    NoBackup: Boolean; // --no-backup
    // v0.25: doc-stub generator + dead-code finder
    DocStubFormat : string ; // --format xmldoc|pasdoc (default 'xmldoc')
    IncludePrivate: Boolean; // --include-private
    // v0.26: compile-check
    Target: string; // --target <file.dproj|.pas>
    // v0.43: check-unit (in-memory semantic check) + uses-audit
    Shadow         : string ; // --shadow <dir> (unsaved-buffer overlay)
    ResolveUsesFlag: Boolean; // --resolve-uses (enrich undeclared errors)
    CheckPlatform  : string ; // --platform win32|win64 (matches project config)
    Edges          : Boolean; // --edges (cycles: show the actual uses edges)
    Causes         : Boolean; // --causes (cycles: pinpoint the symbols forcing each interface edge)
    Plan           : Boolean; // --plan (cycles: emit a followable markdown refactoring playbook)
    Apply          : Boolean; // --apply (uses-fix: write changes, not dry-run)
    RemoveUnused   : Boolean; // --remove-unused (uses-fix: also comment unused)
    // v0.27: generate-test + format
    TestFramework: string; // --framework dunitx|dunit (default 'dunitx')
    YadfPath     : string; // --yadf-path <YADF.exe>
    // v0.34: workspace
    WorkspaceConfig: string; // --config <path>
    // forms-csv
    RootForm: string; // forms-csv: --root <TfrmMAIN> (auto-detect if '')
    // library-drift / selftest drift
    Roots: TArray<string>; // --root <dir> repeatable (drift check)
    // v0.45: index manifest (Task 1)
    IndexAll: Boolean; // --all  (index all sections from manifest)
    // v0.45: index walk filter (Task 4)
    ExcludeGlobs    : TArray<string>; // --exclude <glob> (repeatable)
    IncludeOnlyGlobs: TArray<string>; // --include-only <glob> (repeatable)
    UseIgnore       : Boolean       ; // --use-ignore
    NoSqlMS         : Boolean       ; // --no-sql-ms
    // v0.45: index manifest (Task 7)
    OnlySections: TArray<string>; // --only <Sec1,Sec2,...>  restrict sections to build
    // v0.45: index manifest (Task 8)
    Jobs: Integer; // --jobs <n>  parallel worker processes (0 = manifest/auto)
    // v0.45: index manifest (Task 9) -- DB selection + size guard
    Force32       : Boolean; // --force32  treat this run as 32-bit for size-guard testing
    SizeGuardMB   : Integer; // --size-guard-mb <n>  override manifest sizeGuardMB (0=warn always)
    SizeGuardMBSet: Boolean; // True when --size-guard-mb was explicitly given
    // v0.46: file-size guard (tree-sitter native stack overflow prevention)
    MaxFileKB   : Integer; // --max-file-kb <n>  override default 2048; 0=unlimited; -1=not set
    MaxFileKBSet: Boolean; // True when --max-file-kb was explicitly given
    // v0.47: lifecycle -- when the IDE plugin spawns a long-running server
    // (lsp), it passes --parent-pid <IDE pid> so we self-exit if the IDE dies
    // (belt-and-suspenders alongside the BPL's kill-on-close job object).
    ParentPid: Cardinal; // --parent-pid <n>  (0 = not set)
    // v0.47: ghost-check -- compile the project with one unit's content replaced
    // by an unsaved buffer, with a guaranteed restore.
    GhostUnit  : string; // --unit <real .pas to overlay>
    GhostBuffer: string; // --buffer <temp file holding the buffer>
    // v0.48: multi-overlay -- a manifest with one 'realpath<TAB>bufferpath' per
    // line, so ALL unsaved units are overlaid for a single compile.
    GhostOverlays: string; // --overlays <manifest>
    // v0.57: text-constant search (Tasks 3-8)
    TextQuery    : string ; // --text "<phrase>"
    TextAnyOrder : Boolean; // --any-order
    TextSubstring: Boolean; // --substring
    TextSource   : string ; // --source pas|dfm|sql ('' = all)
    // v0.64: lint-all progress
    Quiet        : Boolean; // --quiet  suppress per-file progress to stderr
  end; // record

procedure PrintHelp;
begin
  Writeln('drag-lint ', VERSION, ' - Delphi-RAG-Lint: symbol-aware index + RAG + lint for Delphi/Pascal');
  Writeln('');
  Writeln('Usage:');
  Writeln('  drag-lint index <path>                              [--db <file.sqlite>] [--watch [--interval N]]');
  Writeln('  drag-lint index --project <file.dproj>              [--db <file.sqlite>] [--dry-run] [--watch [--interval N]]');
  Writeln('  drag-lint index --scan-libraries-win                [--db <file.sqlite>] [--dry-run]   (Win32+Win64 Library+Browsing paths)');
  Writeln('  drag-lint index --scan-libraries-all                [--db <file.sqlite>] [--dry-run]   (every platform: +Android/iOS/Linux/OSX)');
  Writeln('  drag-lint index --all [--config <path>] [--only <Sec1,Sec2>] [--platform win32|win64] [--dry-run [--json]] [--jobs <n>]');
  Writeln('  drag-lint query              --name  <symbol-name>  [--db ...] [--json]');
  Writeln('  drag-lint query              --qname <qualified>    [--db ...] [--json]');
  Writeln('  drag-lint query              --text "<phrase>" [--any-order|--substring] [--source pas|dfm|sql] [--limit N] [--db ...] [--json]');
  Writeln('  drag-lint query find-callers --name  <callee-name>  [--context N] [--db ...] [--json]');
  Writeln('  drag-lint query find         [--doc-tag X | --doc-contains Y | --no-docs] [--kind K] [--public] [--db ...]');
  Writeln('  drag-lint query ancestors    --name <type> [--of <ancestor>] [--db ...] [--json]   (transitive class/interface hierarchy)');
  Writeln('  drag-lint query typecat      --name <type> [--db ...] [--json]   (resolve type category: float/string/class/interface/...)');
  Writeln('  drag-lint lint  <path>       [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json]');
  Writeln('  drag-lint lint  --project <file.dproj> [--rule unit-not-in-dpr] [--json]');
  Writeln('  drag-lint lint-project --db <file.sqlite> [--rule god-class|unused-public-symbol|interface-reference-cycle|layering-violation] [--layers <f.json>] [--json]');
  Writeln('  drag-lint lint-all           [--db <file.sqlite>] [--project <.dproj>] [--disable id,...] [--output <report.txt>] [--json] [--quiet]');
  Writeln('                               --quiet: suppress per-file progress lines written to stderr');
  Writeln('  drag-lint serve              --db <file.sqlite>    (MCP stdio server)');
  Writeln('  drag-lint lsp                --db <file.sqlite>    (LSP stdio server)');
  Writeln('  drag-lint export enums       --db <file.sqlite>    [--format firebird-sql|csv|json|delphi-const]');
  Writeln('  drag-lint export obsidian    --db <file.sqlite>    --output-dir <dir>  [--open]');
  Writeln('  drag-lint top                --db <file.sqlite>    [--by fanin] [--limit N] [--json]');
  Writeln('  drag-lint graph              --db <file.sqlite>    [--format dot|mermaid] [--name <root-substr>] [--output <file>]');
  Writeln('  drag-lint todos              [<path>]                (TODO/FIXME/HACK/XXX/REVIEW/NOTE scanner; [--json])');
  Writeln('  drag-lint diff               --db <old.sqlite> --db <new.sqlite>  [--json]');
  Writeln('  drag-lint import-log <logfile> --db <file.sqlite>  (parse dcc/msbuild log)');
  Writeln('  drag-lint query hints        --db <file.sqlite>    [--name <code>] [--rule <severity>]');
  Writeln('  drag-lint hover              --qname <Foo.Bar>     [--db <file.sqlite>] [--format plain|md|json]');
  Writeln('  drag-lint impact             --qname <Foo.Bar>     [--db <file.sqlite>] [--depth N] [--format text|json]');
  Writeln('  drag-lint wiring             --qname <IIntf|TForm> [--db <file.sqlite>] [--format text|json]   (Spring4D DI + DFM event edges)');
  Writeln('  drag-lint wiring             --coverage           [--db <file.sqlite>] [--format text|json]   (DI registrations not resolved to I->T)');
  Writeln('  drag-lint surface            --qname <Foo.TBar>   [--db <file.sqlite>] [--include-impl] [--all-visibility] [--format text|json]');
  Writeln('  drag-lint slice              --qname <Foo.TBar>   [--db <file.sqlite>] [--format text|json]');
  Writeln('  drag-lint context            --task "verb qname" [--db <file.sqlite>] [--format md|json|raw]');
  Writeln('                               [--max-callers N] [--context N] [--no-docs]');
  Writeln('  drag-lint bench-context      [--db <file.sqlite>] [--n N]');
  Writeln('  drag-lint typeat <file>:<line>:<col> [--db <file.sqlite>] [--format text|json]');
  Writeln('  drag-lint uses-report --output <out.csv> [--db ...] [--depth N] [--include-external] [--all-sources] [--name <pattern>]');
  Writeln('  drag-lint fb-snapshot --connection "Database=...;User=...;Password=...;DriverID=FB" --db <sql.sqlite>');
  Writeln('  drag-lint link-orm    --db <projDb.sqlite> --db <sqlDb.sqlite>');
  Writeln('  drag-lint rename --qname <Foo.TBar.Baz> --to <NewName> [--db PATH] [--dry-run] [--no-backup]');
  Writeln('  drag-lint generate-docs --qname <Foo.TBar.Baz> [--format xmldoc|pasdoc] [--db PATH]');
  Writeln('  drag-lint find-deadcode [--kind method|function|...] [--include-private] [--db PATH]');
  Writeln('  drag-lint compile-check <target.dproj|.pas> [--db PATH] [--format json|text]');
  Writeln('  drag-lint check-unit <unit.pas> [--project <dproj>] [--platform win32|win64] [--shadow <dir>] [--resolve-uses] [--db PATH] [--format json|text]');
  Writeln('  drag-lint cycles             --db <file.sqlite>    [--edges] [--causes] [--plan] [--format json|text]   (circular unit deps; --plan = followable refactoring playbook)');
  Writeln('  drag-lint uses-audit <unit.pas> --db <file.sqlite> [--format json|text]   (interface->impl moves + unused units)');
  Writeln('  drag-lint uses-fix <unit.pas> --project <dproj> --db <file.sqlite> [--platform win32|win64] [--apply] [--remove-unused]   (compiler-verified uses cleanup)');
  Writeln('  drag-lint generate-test --qname <Foo.TBar.Baz> [--framework dunitx|dunit] [--db PATH]');
  Writeln('  drag-lint format <file> [--yadf-path PATH]');
  Writeln('  drag-lint check-ast <file> [--db PATH] [--format text|json]');
  Writeln('  drag-lint workspace index  [--config <.drag-lint-workspace.json>]');
  Writeln('  drag-lint workspace status [--config <.drag-lint-workspace.json>]');
  Writeln('  drag-lint workspace add <projfile> [--config <.drag-lint-workspace.json>]');
  Writeln('  drag-lint forms-csv --project <X.dproj> --db <file.sqlite> [--out <f.csv>] [--root <TfrmMAIN>]   (test-helper navigation CSV, one row per form)');
  Writeln('  drag-lint resolve-dbs [--platform win32|win64] [--config <path>] [--json]   (print the consumer DB list query/lsp/serve would use)');
  Writeln('  drag-lint reconcile-project <App.dpr|.dproj> [--apply] [--json] [--config <path>]  - sync project member list; flag stale used units');
  Writeln('  drag-lint library-drift [--platform <p>] [--config <path>] [--json]               - registry roots missing from library index (exit 2 if drift)');
  Writeln('  drag-lint --version');
  Writeln('  drag-lint --help');
  Writeln('');
  Writeln('Defaults:');
  Writeln('  --db = .\drag-lint.sqlite next to the cwd');
end; // procedure

// v0.45 Task 9: forward declarations so DoQuery (declared early) can call
// these helpers that are defined later in the file.
procedure SizeGuardCheck(const ADbPath: string; ASizeGuardMB: Integer; AForce32: Boolean); forward;
function ResolveConsumerDbs(const AArgs: TArgs): TArray<string>; forward;

// v0.14: load defaults from `.drag-lint.json` in cwd (or any parent),
// before CLI flags. Recognized keys:
//   { "db": "...", "project": "...", "path": "...", "rule": "...",
//     "watch": { "interval": N },
//     "docs": { "captureLooseComments": bool, "allowBlankLineGap": N,
//               "implPrecedence": "interface" } }
// CLI flags override config values. Missing file is silently ignored.
procedure LoadConfigDefaults(var AArgs: TArgs);
var
  Dir      : string     ;
  Candidate: string     ;
  Content  : string     ;
  J        : TJSONObject;
  JWatch   : TJSONObject;
  JDocs    : TJSONObject;
  V        : TJSONValue ;
  N        : TJSONNumber;
  B        : TJSONBool  ;
begin
  Dir      := GetCurrentDir;
  Candidate:= '';
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, '.drag-lint.json')) then
    begin
      Candidate:= TPath.Combine(Dir, '.drag-lint.json');
      Break;
    end;
    if Dir = ExtractFilePath(Dir.TrimRight(['\','/'])) then Break;
    Dir:= ExtractFilePath(Dir.TrimRight(['\','/']));
  end;
  if Candidate = '' then Exit;
  try
    Content:= TFile.ReadAllText(Candidate);
    J:= TJSONObject.ParseJSONValue(Content) as TJSONObject;
  except
    Exit;
  end;
  if J = nil then Exit;
  try
    V:= J.GetValue('db');
    if (V <> nil) and (V.Value <> '') then AArgs.DbPath:= V.Value;
    V:= J.GetValue('project');
    if (V <> nil) and (V.Value <> '') then AArgs.ProjectPath:= V.Value;
    V:= J.GetValue('path');
    if (V <> nil) and (V.Value <> '') then AArgs.Path:= V.Value;
    V:= J.GetValue('rule');
    if (V <> nil) and (V.Value <> '') then AArgs.Rule:= V.Value;
    V:= J.GetValue('watch');
    if V is TJSONObject then
    begin
      JWatch:= TJSONObject(V);
      AArgs.Watch:= True;
      N:= JWatch.GetValue('interval') as TJSONNumber;
      if N <> nil then AArgs.Interval:= N.AsInt;
    end;
    // v0.16 Task 13: "docs" section
    V:= J.GetValue('docs');
    if V is TJSONObject then
    begin
      JDocs:= TJSONObject(V);
      B:= JDocs.GetValue('captureLooseComments') as TJSONBool;
      if B <> nil then AArgs.Docs.CaptureLooseComments:= B.AsBoolean;
      N:= JDocs.GetValue('allowBlankLineGap') as TJSONNumber;
      if N <> nil then AArgs.Docs.AllowBlankLineGap:= N.AsInt;
      V:= JDocs.GetValue('implPrecedence');
      if (V <> nil) and (V.Value <> '') then AArgs.Docs.ImplPrecedence:= V.Value;
    end;
  finally
    J.Free;
  end; // try
  Writeln(ErrOutput, '(loaded defaults from ', Candidate, ')');
end; // procedure

function ParseArgs: TArgs;
var
  i: Integer;
  A: string ;
begin
  Result:= Default(TArgs);
  Result.DbPath:= TPath.Combine(GetCurrentDir, 'drag-lint.sqlite');
  Result.Docs               := DefaultDocConfig;
  Result.Depth              := 3;
  Result.MaxCallers         := 5;
  Result.IncludeClassSurface:= True;
  Result.ContextLines       := 3;
  Result.BenchN             := 20;
  LoadConfigDefaults(Result);
  if ParamCount = 0 then
  begin
    Result.ShowHelp:= True;
    Exit;
  end;
  Result.Command:= ParamStr(1);
  if (Result.Command = '--help') or (Result.Command = '-h') then
  begin
    Result.ShowHelp:= True;
    Exit;
  end;
  if Result.Command = '--version' then
  begin
    Result.ShowVersion:= True;
    Exit;
  end;

  // Optional subcommand: ParamStr(2) if it doesn't start with '--'.
  i:= 2;
  if ((Result.Command = 'query') or (Result.Command = 'export') or (Result.Command = 'workspace') or (Result.Command = 'selftest')) and (ParamCount >= 2) then
  begin
    A:= ParamStr(2);
    if (A <> '') and (not A.StartsWith('--')) then
    begin
      Result.SubCommand:= A;
      i:= 3;
    end;
  end;

  while i <= ParamCount do
  begin
    A:= ParamStr(i);
    if (A = '--db') and (i < ParamCount) then
    begin
      Inc(i);
      Result.DbPath:= ParamStr(i);
      SetLength(Result.DbPaths, Length(Result.DbPaths) + 1);
      Result.DbPaths[High(Result.DbPaths)]:= ParamStr(i);
    end
    else if (A = '--name') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Name:= ParamStr(i);
    end
    else if ((A = '--in') or (A = '--file')) and (i < ParamCount) then
    begin
      Inc(i);
      Result.InFile:= ParamStr(i);
    end
    else if (A = '--qname') and (i < ParamCount) then
    begin
      Inc(i);
      Result.QName:= ParamStr(i);
    end
    else if (A = '--of') and (i < ParamCount) then { v11 (M1): query ancestors --of }
    begin
      Inc(i);
      Result.OfName:= ParamStr(i);
    end
    else if (A = '--rule') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Rule:= ParamStr(i);
    end
    else if (A = '--exclude-under') and (i < ParamCount) then
    begin
      Inc(i);
      SetLength(Result.ExcludeUnder, Length(Result.ExcludeUnder) + 1);
      Result.ExcludeUnder[High(Result.ExcludeUnder)]:= ParamStr(i);
    end
    else if A = '--deep' then
    begin
      Result.Deep:= True; Result.DeepExplicit:= True;
    end
    else if A = '--shallow' then
    begin
      Result.Deep:= False; Result.DeepExplicit:= True;
    end
    else if (A = '--width') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Width:= ParamStr(i);
    end
    else if (A = '--project') and (i < ParamCount) then
    begin
      Inc(i);
      Result.ProjectPath:= ParamStr(i);
    end
    else if (A = '--rules-dir') and (i < ParamCount) then
    begin
      Inc(i);
      Result.RulesDir:= ParamStr(i);
    end
    else if (A = '--disable') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Disable:= ParamStr(i);
    end
    else if (A = '--layers') and (i < ParamCount) then
    begin
      Inc(i);
      Result.LayersPath:= ParamStr(i);
    end
    else if A = '--json'    then Result.AsJson:= True
    else if A = '--dry-run' then Result.DryRun:= True
    else if A = '--quiet' then Result.Quiet:= True
    else if (A = '--scan-libraries') or (A = '--scan-libraries-win') then Result.ScanLibraries:= True // Win32 + Win64 (--scan-libraries is the back-compat alias)
    else if A = '--scan-libraries-all' then
    begin
      Result.ScanLibraries   := True;
      Result.ScanLibrariesAll:= True; // every registered platform
    end
    else if A = '--watch' then Result.Watch:= True
    else if A = '--open'  then Result.Open := True
    else if (A = '--interval') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Interval:= StrToIntDef(ParamStr(i), 5);
    end
    else if (A = '--format') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Format:= ParamStr(i);
    end
    else if ((A = '--output') or (A = '--out')) and (i < ParamCount) then
    begin
      Inc(i);
      Result.Output:= ParamStr(i);
    end
    else if (A = '--output-dir') and (i < ParamCount) then
    begin
      Inc(i);
      Result.OutputDir:= ParamStr(i);
    end
    else if A = '--include-external' then Result.IncludeExternal:= True
    else if A = '--all-sources'      then Result.AllSources     := True
    else if A = '--all'              then Result.IndexAll       := True
    else if (A = '--only') and (i < ParamCount) then
    begin
      Inc(i);
      // Split comma-separated section names, trim each, skip empties.
      var Parts:= ParamStr(i).Split([',']);
      for var P in Parts do
      begin
        var T:= Trim(P);
        if T <> '' then
        begin
          SetLength(Result.OnlySections, Length(Result.OnlySections) + 1);
          Result.OnlySections[High(Result.OnlySections)]:= T;
        end;
      end;
    end
    else if (A = '--exclude') and (i < ParamCount) then
    begin
      Inc(i);
      SetLength(Result.ExcludeGlobs, Length(Result.ExcludeGlobs) + 1);
      Result.ExcludeGlobs[High(Result.ExcludeGlobs)]:= ParamStr(i);
    end
    else if (A = '--include-only') and (i < ParamCount) then
    begin
      Inc(i);
      SetLength(Result.IncludeOnlyGlobs, Length(Result.IncludeOnlyGlobs) + 1);
      Result.IncludeOnlyGlobs[High(Result.IncludeOnlyGlobs)]:= ParamStr(i);
    end
    else if A = '--use-ignore' then Result.UseIgnore:= True
    else if A = '--no-sql-ms'  then Result.NoSqlMS  := True
    else if (A = '--jobs') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Jobs:= StrToIntDef(ParamStr(i), 0);
    end
    else if A = '--force32' then Result.Force32:= True
    else if (A = '--size-guard-mb') and (i < ParamCount) then
    begin
      Inc(i);
      Result.SizeGuardMB:= StrToIntDef(ParamStr(i), 0);
      Result.SizeGuardMBSet:= True;
    end
    else if (A = '--max-file-kb') and (i < ParamCount) then
    begin
      Inc(i);
      Result.MaxFileKB:= StrToIntDef(ParamStr(i), 2048);
      Result.MaxFileKBSet:= True;
    end
    else if (A = '--connection') and (i < ParamCount) then
    begin
      Inc(i);
      Result.FbConnection:= ParamStr(i);
    end
    else if (A = '--limit') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Limit:= StrToIntDef(ParamStr(i), 50);
    end
    else if (A = '--by') and (i < ParamCount) then
    begin
      Inc(i);
      Result.SortBy:= ParamStr(i);
    end
    else if (A = '--doc-tag') and (i < ParamCount) then
    begin
      Inc(i);
      Result.DocTag:= ParamStr(i);
    end
    else if (A = '--doc-contains') and (i < ParamCount) then
    begin
      Inc(i);
      Result.DocContains:= ParamStr(i);
    end
    else if (A = '--no-docs') then Result.NoDocs:= True
    else if (A = '--kind') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Kind:= ParamStr(i);
    end
    else if (A = '--public') then Result.PublicOnly:= True
    else if (A = '--depth') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Depth:= StrToIntDef(ParamStr(i), 3);
    end
    else if A = '--include-impl'   then Result.IncludeImpl   := True
    else if A = '--full-surface'   then Result.FullSurface   := True
    else if A = '--all-visibility' then Result.AllVisibility := True
    else if A = '--coverage'       then Result.WiringCoverage:= True
    else if (A = '--context') and (i < ParamCount) then
    begin
      Inc(i);
      Result.ContextLines:= StrToIntDef(ParamStr(i), 0);
    end
    else if (A = '--task') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Task:= ParamStr(i);
      // Parse "verb qname" or just "qname".
      // Recognized verbs: modify, inspect, refactor, delete, extend.
      var SpPos:= Pos(' ', Result.Task);
      if SpPos > 0 then
      begin
        var FirstToken:= LowerCase(Copy(Result.Task, 1, SpPos - 1));
        if (FirstToken = 'modify') or (FirstToken = 'inspect') or (FirstToken = 'refactor') or (FirstToken = 'delete') or (FirstToken = 'extend') then
        begin
          Result.Verb:= FirstToken;
          Result.BundleQName:= Trim(Copy(Result.Task, SpPos + 1, MaxInt));
        end
        else
        begin
          Result.Verb:= 'modify';
          Result.BundleQName:= Result.Task;
        end;
      end
      else
      begin
        Result.Verb:= 'modify';
        Result.BundleQName:= Result.Task;
      end;
    end // if
    else if (A = '--max-callers') and (i < ParamCount) then
    begin
      Inc(i);
      Result.MaxCallers:= StrToIntDef(ParamStr(i), 5);
    end
    else if (A = '--n') and (i < ParamCount) then
    begin
      Inc(i);
      Result.BenchN:= StrToIntDef(ParamStr(i), 20);
    end
    else if (A = '--to') and (i < ParamCount) then
    begin
      Inc(i);
      Result.RenameTo:= ParamStr(i);
    end
    else if A = '--no-backup'       then Result.NoBackup      := True
    else if A = '--include-private' then Result.IncludePrivate:= True
    else if (A = '--target') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Target:= ParamStr(i);
    end
    else if (A = '--shadow') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Shadow:= ParamStr(i);
    end
    else if A = '--resolve-uses'  then Result.ResolveUsesFlag:= True
    else if A = '--edges'         then Result.Edges          := True
    else if A = '--causes'        then Result.Causes         := True
    else if A = '--plan'          then Result.Plan           := True
    else if A = '--apply'         then Result.Apply          := True
    else if A = '--remove-unused' then Result.RemoveUnused   := True
    else if (A = '--platform') and (i < ParamCount) then
    begin
      Inc(i);
      Result.CheckPlatform:= ParamStr(i);
    end
    else if (A = '--framework') and (i < ParamCount) then
    begin
      Inc(i);
      Result.TestFramework:= ParamStr(i);
    end
    else if (A = '--yadf-path') and (i < ParamCount) then
    begin
      Inc(i);
      Result.YadfPath:= ParamStr(i);
    end
    else if (A = '--config') and (i < ParamCount) then
    begin
      Inc(i);
      Result.WorkspaceConfig:= ParamStr(i);
    end
    else if (A = '--root') and (i < ParamCount) then
    begin
      Inc(i);
      if (Result.Command = 'selftest') or (Result.Command = 'library-drift') then
      begin
        SetLength(Result.Roots, Length(Result.Roots) + 1);
        Result.Roots[High(Result.Roots)]:= ParamStr(i);
      end
      else Result.RootForm:= ParamStr(i);
    end
    else if (Result.Command = 'typeat') and (Result.Position = '') and (not A.StartsWith('--')) then Result.Position:= A
    else if ((Result.Command = 'compile-check') or (Result.Command = 'ghost-check') or (Result.Command = 'ghost-recover'))
            and (Result.Target = '') and (not A.StartsWith('--')) then Result.Target:= A
    else if ((Result.Command = 'check-unit') or (Result.Command = 'uses-audit') or (Result.Command = 'uses-fix')) and (Result.Target = '') and (not A.StartsWith('--')) then
      Result.Target:= A
    else if (Result.Command = 'check-ast') and (Result.Target = '') and (not A.StartsWith('--')) then Result.Target:= A
    else if (Result.Command = 'format'   ) and (Result.Target = '') and (not A.StartsWith('--')) then Result.Target:= A
    else if (Result.Command = 'workspace') and (Result.SubCommand = 'add') and (Result.Target = '') and (not A.StartsWith('--')) then Result.Target:= A
    else if (A = '--dir') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Path:= ParamStr(i);
    end
    else if (A = '--parent-pid') and (i < ParamCount) then
    begin
      Inc(i);
      Result.ParentPid:= Cardinal(StrToInt64Def(ParamStr(i), 0));
    end
    else if (A = '--unit') and (i < ParamCount) then
    begin
      Inc(i);
      Result.GhostUnit:= ParamStr(i);
    end
    else if (A = '--buffer') and (i < ParamCount) then
    begin
      Inc(i);
      Result.GhostBuffer:= ParamStr(i);
    end
    else if (A = '--overlays') and (i < ParamCount) then
    begin
      Inc(i);
      Result.GhostOverlays:= ParamStr(i);
    end
    // v0.57: text-constant search flags
    else if (A = '--text') and (i < ParamCount) then
    begin
      Inc(i);
      Result.TextQuery:= ParamStr(i);
    end
    else if (A = '--source') and (i < ParamCount) then
    begin
      Inc(i);
      Result.TextSource:= ParamStr(i);
    end
    else if A = '--any-order'  then Result.TextAnyOrder := True
    else if A = '--substring'  then Result.TextSubstring:= True
    else if (Result.Path = '') and (not A.StartsWith('--')) then Result.Path:= A
    else raise Exception.CreateFmt('Unknown argument: %s', [A]);
    Inc(i);
  end; // while
end; // function

{ v0.47: parent-process exit watcher. When --parent-pid is passed (by the IDE
  plugin for the long-running lsp server), a thread blocks on the parent process
  handle and force-exits THIS process when the parent dies -- so a crashed or
  Task-Manager-killed IDE never leaves an orphaned engine. Raw CreateThread (no
  RTL TThread) keeps it dependency-free and immune to a hung main thread;
  TerminateProcess(self) guarantees teardown. Complements the BPL job object. }
function ParentWatchProc(P: Pointer): DWORD; stdcall;
var
  H: THandle;
begin
  Result:= 0;
  H:= OpenProcess(SYNCHRONIZE, False, DWORD(NativeUInt(P)));
  if H = 0 then Exit;
  try
    if WaitForSingleObject(H, INFINITE) = WAIT_OBJECT_0 then TerminateProcess(GetCurrentProcess, 0);
  finally
    CloseHandle(H);
  end;
end;

procedure StartParentExitWatch(APid: Cardinal);
var
  Tid: DWORD  ;
  H  : THandle;
begin
  if APid = 0 then Exit;
  H:= CreateThread(nil, 0, @ParentWatchProc, Pointer(NativeUInt(APid)), 0, Tid);
  if H <> 0 then CloseHandle(H);
end;

procedure PrintReferences(const AStore: ISymbolStore; const ARefs: TArray<TReference>; AsJson: Boolean);
var
  JArr: TJSONArray ;
  JObj: TJSONObject;
  R   : TReference ;
  Path: string     ;
begin
  if AsJson then
  begin
    JArr:= TJSONArray.Create;
    try
      for R in ARefs do
      begin
        Path:= AStore.GetFilePath(R.FileId);
        JObj:= TJSONObject.Create;
        JObj.AddPair('id', TJSONNumber.Create(R.Id));
        JObj.AddPair('kind'     , R.Kind    );
        JObj.AddPair('name_text', R.NameText);
        JObj.AddPair('file_path', Path);
        JObj.AddPair('start_line', TJSONNumber.Create(R.StartLine));
        JObj.AddPair('start_col' , TJSONNumber.Create(R.StartCol ));
        JObj.AddPair('end_line'  , TJSONNumber.Create(R.EndLine  ));
        JObj.AddPair('end_col'   , TJSONNumber.Create(R.EndCol   ));
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end; // try
  end // if
  else
  begin
    for R in ARefs do
    begin
      Path:= AStore.GetFilePath(R.FileId);
      Writeln(Format('%s:%d:%d  %s', [Path, R.StartLine, R.StartCol, R.NameText]));
    end;
    Writeln(Format('%d caller(s)', [Length(ARefs)]));
  end;
end; // procedure

// v0.17: Print references with optional context lines
procedure PrintReferencesWithContext(const AStore: ISymbolStore; const ARefs: TArray<TReference>; AContextLines: Integer; AsJson: Boolean);
var
  JArr: TJSONArray ;
  JObj: TJSONObject;
  R   : TReference ;
  Path: string     ;
begin
  if AsJson then
  begin
    JArr:= TJSONArray.Create;
    try
      for R in ARefs do
      begin
        Path:= AStore.GetFilePath(R.FileId);
        JObj:= TJSONObject.Create;
        JObj.AddPair('id', TJSONNumber.Create(R.Id));
        JObj.AddPair('kind'     , R.Kind    );
        JObj.AddPair('name_text', R.NameText);
        JObj.AddPair('file_path', Path);
        JObj.AddPair('start_line', TJSONNumber.Create(R.StartLine));
        JObj.AddPair('start_col' , TJSONNumber.Create(R.StartCol ));
        JObj.AddPair('end_line'  , TJSONNumber.Create(R.EndLine  ));
        JObj.AddPair('end_col'   , TJSONNumber.Create(R.EndCol   ));
        if R.ContextText <> '' then JObj.AddPair('context', R.ContextText);
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end; // try
  end // if
  else
  begin
    for R in ARefs do
    begin
      Path:= AStore.GetFilePath(R.FileId);
      Writeln(Format('%s:%d:%d  %s', [Path, R.StartLine, R.StartCol, R.NameText]));
      if R.ContextText <> '' then
      begin
        Writeln('  ' + StringReplace(R.ContextText, sLineBreak, sLineBreak + '  ', [rfReplaceAll]));
      end;
    end;
    Writeln(Format('%d caller(s)', [Length(ARefs)]));
  end;
end; // procedure

// v0.45: serialise a TIndexManifest to a TJSONObject for the dry-run JSON view.
// Delegates to TManifestIO.ToJson for the canonical manifest structure, then
// adds the extra 'indexes.rootDir' field (richer than the saved file). Caller owns + frees.
function ManifestToJson(const AManifest: TIndexManifest): TJSONObject;
var
  JIndexes: TJSONObject;
begin
  Result:= TManifestIO.ToJson(AManifest);
  // Inject rootDir into indexes (dry-run view is intentionally richer than the saved file)
  JIndexes:= Result.GetValue('indexes') as TJSONObject;
  if JIndexes <> nil then JIndexes.AddPair('rootDir', AManifest.RootDir);
end;

// v0.45 Task 6: serialise a TIndexPlan to a TJSONObject alongside the settings
// echo from the manifest. Shape:
//   { "settings": { "currentProjectsIndexing": "...", ... },
//     "sections": [ { "name": ..., "mode": ..., "db": ...,
//                     "platform": ..., "roots"|"rootsCount": ...,
//                     "dedupExcludeRoots": [...] }, ... ] }
// Library sections emit rootsCount (integer) instead of the full roots array
// to keep output sane (libraries have hundreds of folders).
// Caller owns + must free the returned object.
function PlanToJson(const AManifest: TIndexManifest; const APlan: TIndexPlan): TJSONObject;
var
  JSettings: TJSONObject ;
  JSecObj  : TJSONObject ;
  JSections: TJSONArray  ;
  JRoots   : TJSONArray  ;
  JDedup   : TJSONArray  ;
  PS       : TPlanSection;
  S        : string      ;

  function ModeStr(M: TPlanSectionMode): string;
  begin
    case M of
      smFolderTree: Result:= 'folderTree';
      smClosure   : Result:= 'closure';
      smLibrary   : Result:= 'library';
      else Result:= 'folderTree';
    end;
  end;

begin
  Result:= TJSONObject.Create;

  // Settings echo (preserves "currentProjectsIndexing":"perProject" assertion)
  JSettings:= TJSONObject.Create;
  Result.AddPair('settings', JSettings);
  JSettings.AddPair(
    'currentProjectsIndexing',
    (function: string begin case AManifest.Settings.CurrentProjectsIndexing of piPerGroup: Result:= 'perGroup'; piSingle: Result:= 'single'; else Result:= 'perProject'; end; end)()
  );
  JSettings.AddPair('defaultPlatform', AManifest.Settings.DefaultPlatform);
  JSettings.AddPair('sizeGuardMB', TJSONNumber.Create(AManifest.Settings.SizeGuardMB));
  JSettings.AddPair('enginePath', AManifest.Settings.EnginePath);
  JSettings.AddPair('maxJobs', TJSONNumber.Create(AManifest.Settings.MaxJobs));

  // Plan sections
  JSections:= TJSONArray.Create;
  Result.AddPair('sections', JSections);
  for PS in APlan.Items do
  begin
    JSecObj:= TJSONObject.Create;
    JSections.AddElement(JSecObj);
    JSecObj.AddPair('name', PS.Name);
    JSecObj.AddPair('mode', ModeStr(PS.Mode));
    JSecObj.AddPair('db'      , PS.DbPath  );
    JSecObj.AddPair('platform', PS.Platform);

    if PS.Mode = smLibrary then
      // Library sections: emit count only (hundreds of folders)
      JSecObj.AddPair('rootsCount', TJSONNumber.Create(Length(PS.Roots)))
    else
    begin
      JRoots:= TJSONArray.Create;
      JSecObj.AddPair('roots', JRoots);
      for S in PS.Roots do JRoots.AddElement(TJSONString.Create(S));
    end;

    JDedup:= TJSONArray.Create;
    JSecObj.AddPair('dedupExcludeRoots', JDedup);
    for S in PS.DedupExcludeRoots do JDedup.AddElement(TJSONString.Create(S));
  end; // for
end; // begin

// v0.46: a full `index --all` / `--only` is a CLEAN rebuild of each section's
// DB. Re-running a build into an existing DB doubled symbols: a scoped reindex
// during development and a separate full reindex both wrote into the same file,
// and the incremental FileIsUpToDate skip did not catch every file (path-spelling
// / sha drift between two engine builds), so rows accumulated. Deleting the
// section DB plus its WAL/SHM/journal sidecars before (re)creating the store
// guarantees one clean copy. The incremental per-file reindex path (LSP save)
// still uses FileIsUpToDate against an existing DB and does NOT come through here.
procedure RecreateSectionDb(const ADbPath: string);
const
  Sidecars: array[0..2] of string = ('-wal', '-shm', '-journal');
var
  Suffix: string;
begin
  if TFile.Exists(ADbPath) then TFile.Delete(ADbPath);
  for Suffix in Sidecars do
    if TFile.Exists(ADbPath + Suffix) then TFile.Delete(ADbPath + Suffix);
end;

// v0.45 Task 7: build one plan item into its SQLite database.
// Creates the Store + Indexer, applies filter + dedup roots, walks per mode,
// then calls ResolveUnitUseTargets. Writes a one-line summary to stdout.
// Returns True on success, False (and prints the error) on failure.
function BuildPlanItem(const AItem: TPlanSection; const ADocs: TDocConfig): Boolean;
var
  Store          : ISymbolStore                              ;
  Indexer        : IIndexer                                  ;
  DParser        : TDelphi13Parser                           ;
  Cl             : TClosureResolver                          ;
  Resolver       : DRagLint.Project.Resolver.TProjectResolver;
  CR             : TClosureResult                            ;
  F              : string                                    ;
  W              : string                                    ;
  ExDir          : string                                    ;
  T0             : TDateTime                                 ;
  Elapsed        : Double                                    ;
  ProjectFile    : string                                    ;
  ExcludePatterns: TArray<string>                            ;
begin
  // Ensure output directory exists before creating the SQLite file.
  var DbDir:= ExtractFilePath(AItem.DbPath);
  if (DbDir <> '') and (not TDirectory.Exists(DbDir)) then TDirectory.CreateDirectory(DbDir);

  // v0.46: clean rebuild -- drop any prior DB so symbols never accumulate
  // across runs (see RecreateSectionDb).
  RecreateSectionDb(AItem.DbPath);

  T0:= Now;
  try
    Store:= TSQLiteSymbolStore.Create(AItem.DbPath);
    Store.Migrate;

    DParser:= TDelphi13Parser.Create;
    // Library sections: shallow (no usage refs -- would ~double the DB size).
    DParser.EmitUsageRefs:= (AItem.Mode <> smLibrary);
    Indexer:= TIndexer.Create(Store, [DParser, TDFMParser.Create, TFirebirdSqlParser.Create], ADocs);

    // Apply walk filter from the resolved plan item.
    Indexer.SetWalkFilter(AItem.Filter);

    // Cross-index dedup: exclude roots already covered by other sections.
    for ExDir in AItem.DedupExcludeRoots do Indexer.AddExcludeRoot(ExDir);

    case AItem.Mode of
      smFolderTree, smLibrary:
      begin
        for F in AItem.Roots do
        begin
          if TDirectory.Exists(F) then Indexer.IndexFolder(F, True)
          else if TFile.Exists(F) then Indexer.IndexFile(F)
          else Writeln(Format('  (skip, not found) %s', [F]));
        end;
      end;

      smClosure:
      begin
        // AItem.Roots for closure = the .dpr/.dproj paths.
        // Build library roots for exclusion from the closure walk.
        Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
        try
          Cl:= TClosureResolver.Create(Resolver.ResolveLibraryPaths);
          try
            for F in AItem.Roots do
            begin
              if not TFile.Exists(F) then
              begin
                Writeln(Format('  (skip, project file not found) %s', [F]));
                Continue;
              end;
              // Combine global + section exclude patterns for the closure.
              ExcludePatterns:= Concat( AItem.Filter.GlobalExclude, AItem.Filter.SectionExclude);
              CR:= Cl.Resolve(F, ExcludePatterns);
              for W in CR.Warnings do Writeln('  ', W);
              for ProjectFile in CR.Files do Indexer.IndexFile(ProjectFile);
            end;
          finally
            Cl.Free;
          end; // try
        finally
          Resolver.Free;
        end; // try
      end; // begin
    end; // case

    Store.ResolveUnitUseTargets;
    Store.ResolveAncestry; { v11 (M1): link class/interface heritage cross-unit }
    Elapsed:= (Now - T0) * 86400;

    var PlatSuffix:= '';
    if AItem.Platform <> '' then PlatSuffix:= ' [' + AItem.Platform + ']';
    Writeln(Format('=== %s%s -> %s : files=%d symbols=%d [%.1fs] ===', [AItem.Name, PlatSuffix, AItem.DbPath, Store.CountFiles, Store.CountSymbols, Elapsed]));
    Result:= True;
  except
    on E: Exception do
    begin
      var PlatSuffix:= '';
      if AItem.Platform <> '' then PlatSuffix:= ' [' + AItem.Platform + ']';
      Writeln(ErrOutput, Format( 'ERROR building section %s%s: %s: %s', [AItem.Name, PlatSuffix, E.ClassName, E.Message]));
      Result:= False;
    end;
  end; // try
end; // function

// v0.45: index --all [--config <path>] [--dry-run [--json]] [--only <Secs>] [--platform <P>]
// Loads the manifest (from --config if given, else TManifestIO.Load(enginedir, cwd)),
// validates it, resolves the build plan, optionally filters by --only / --platform,
// then builds each section sequentially. Returns 0 if all sections succeeded.
function DoIndexAll(const AArgs: TArgs): Integer;
var
  Manifest  : TIndexManifest                            ;
  EngineDir : string                                    ;
  ConfigPath: string                                    ;
  ErrMsg    : string                                    ;
  JRoot     : TJSONObject                               ;
  Plan      : TIndexPlan                                ;
  Resolver  : DRagLint.Project.Resolver.TProjectResolver;
  PlatFilter: TArray<string>                            ;
  AnyFailed : Boolean                                   ;
  i         : Integer                                   ;
begin
  EngineDir:= ExtractFilePath(ParamStr(0));
  ConfigPath:= AArgs.WorkspaceConfig; // --config <path>

  if ConfigPath <> '' then
  begin
    if not TFile.Exists(ConfigPath) then
    begin
      Writeln('ERROR: config file not found: ', ConfigPath);
      Exit(2);
    end;
    var Content:= TFile.ReadAllText(ConfigPath);
    var RootDir:= ExtractFilePath(TPath.GetFullPath(ConfigPath));
    Manifest:= TManifestIO.ParseText(Content, RootDir);
  end
  else Manifest:= TManifestIO.Load(EngineDir, GetCurrentDir);

  ErrMsg:= TManifestIO.Validate(Manifest);
  if ErrMsg <> '' then
  begin
    Writeln(ErrOutput, 'ERROR: manifest invalid: ', ErrMsg);
    Exit(2);
  end;

  // Build platform filter from --platform (reuses CheckPlatform field).
  if AArgs.CheckPlatform <> '' then PlatFilter:= [AArgs.CheckPlatform]
  else PlatFilter:= nil;

  // Resolve the full build plan.
  Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    Plan:= ResolvePlan(Manifest, PlatFilter, Resolver);
  finally
    Resolver.Free;
  end;

  // v0.46: CLI --max-file-kb overrides the filter on every plan item.
  // 0 = unlimited (explicit opt-out); positive = new limit.
  if AArgs.MaxFileKBSet then
  begin
    for i:= 0 to High(Plan.Items) do
    begin
      var PS2:= Plan.Items[i];
      PS2.Filter.MaxFileKB:= AArgs.MaxFileKB;
      Plan.Items[i]:= PS2;
    end;
  end;

  // Apply --only filter: keep only items whose Name is in OnlySections.
  if Length(AArgs.OnlySections) > 0 then
  begin
    var Filtered: TArray<TPlanSection>;
    for i:= 0 to High(Plan.Items) do
    begin
      var PS:= Plan.Items[i];
      var Keep:= False;
      for var OnlyName in AArgs.OnlySections do
        if SameText(PS.Name, OnlyName) then
        begin
          Keep:= True;
          Break;
        end;
      if Keep then
      begin
        SetLength(Filtered, Length(Filtered) + 1);
        Filtered[High(Filtered)]:= PS;
      end;
    end;
    Plan.Items:= Filtered;
  end; // if

  if AArgs.DryRun then
  begin
    if AArgs.AsJson then
    begin
      JRoot:= PlanToJson(Manifest, Plan);
      try
        Writeln(JRoot.Format(2));
      finally
        JRoot.Free;
      end;
      Exit(0);
    end
    else
    begin
      // Text dry-run: print a human-readable summary
      Writeln('Index manifest (dry-run):');
      Writeln('  RootDir: ', Manifest.RootDir);
      Writeln('  OutDir:  ', Manifest.OutDir );
      Writeln(Format('  Sections to build: %d', [Length(Plan.Items)]));
      for var PS in Plan.Items do Writeln(Format(
          '    [%s] mode=%s db=%s', [
            PS.Name + (if PS.Platform <> '' then '[' + PS.Platform + ']' else ''),
            (function: string begin case PS.Mode of smFolderTree: Result:= 'folderTree'; smClosure: Result:= 'closure'; smLibrary: Result:= 'library'; else Result:= '?'; end; end)(),
            PS.DbPath]));
      Exit(0);
    end; // else
  end; // if

  // Build each section: sequential or parallel based on --jobs / manifest.maxJobs.
  // Compute effective job count.
  // Priority: --jobs CLI > manifest.settings.maxJobs > auto (min(CpuCount, sections)).
  var EffJobs  : Integer;
  var NSections: Integer;
  var SysInfo2 : TSystemInfo;
  var CpuCount : Integer;
  NSections:= Length(Plan.Items);
  if AArgs.Jobs > 0 then EffJobs:= AArgs.Jobs
  else if Manifest.Settings.MaxJobs > 0 then EffJobs:= Manifest.Settings.MaxJobs
  else
  begin
    // Auto: use Windows GetSystemInfo; avoids pulling in System.Threading.
    GetSystemInfo(SysInfo2);
    CpuCount:= Integer(SysInfo2.dwNumberOfProcessors);
    if CpuCount < 1 then CpuCount:= 1;
    EffJobs:= CpuCount;
    if NSections < EffJobs then EffJobs:= NSections;
  end;
  if EffJobs < 1 then EffJobs:= 1;
  if EffJobs > 63 then EffJobs:= 63; // WaitForMultipleObjects caps at 64 handles

  // Sequential path (jobs <= 1): existing in-process build.
  if EffJobs <= 1 then
  begin
    AnyFailed:= False;
    for i:= 0 to High(Plan.Items) do
    begin
      if not BuildPlanItem(Plan.Items[i], AArgs.Docs) then AnyFailed:= True;
    end;
    if AnyFailed then Result:= 1 else Result:= 0;
    Exit;
  end;

  // Parallel path: --jobs N > 1.
  // Requires --config so the child gets a deterministic config path.
  // If no --config was given (discovered mode), warn and fall back to sequential.
  if AArgs.WorkspaceConfig = '' then
  begin
    Writeln(ErrOutput, 'NOTE: --jobs >1 requires --config <path>; running sequentially.');
    AnyFailed:= False;
    for i:= 0 to High(Plan.Items) do
    begin
      if not BuildPlanItem(Plan.Items[i], AArgs.Docs) then AnyFailed:= True;
    end;
    if AnyFailed then Result:= 1 else Result:= 0;
    Exit;
  end;

  // Spawn one child process per plan item, throttled to EffJobs concurrent.
  // Each child runs: "<self>" index --all --only "<Name>" [--platform "<P>"]
  //                             --config "<cfg>" --jobs 1
  var SelfExe: string               ;
  var TotalSections: Integer;
  var FailedCount  : Integer;
  var ProcHandles: array of THandle;
  var ProcItemIdx: array of Integer;
  var PoolCount : Integer;
  var WaitResult: DWORD;
  var SlotDW    : DWORD;
  var ExitCode  : DWORD;
  var SpawnSI   : TStartupInfoW;
  var SpawnPI   : TProcessInformation;
  var ChildCmdLine: string          ;
  var ChildCmdBuf: array of WideChar;
  var OkCount: Integer              ;
  SelfExe:= ParamStr(0);
  TotalSections:= NSections;
  FailedCount  := 0;
  SetLength(ProcHandles, TotalSections);
  SetLength(ProcItemIdx, TotalSections);
  PoolCount:= 0;

  // Inner helpers inline because Delphi nested procs cannot follow inline var decls.
  // Use local labels and gotos instead -- actually just inline all pool operations below.

  try
    for i:= 0 to TotalSections - 1 do
    begin
      // Drain one slot from pool if it is full.
      while PoolCount >= EffJobs do
      begin
        WaitResult:= WaitForMultipleObjects(PoolCount, @ProcHandles[0], False { bWaitAll }, INFINITE);
        if (WaitResult >= WAIT_OBJECT_0) and (WaitResult < WAIT_OBJECT_0 + DWORD(PoolCount)) then SlotDW:= WaitResult - WAIT_OBJECT_0
        else SlotDW:= 0;
        ExitCode:= 0;
        GetExitCodeProcess(ProcHandles[SlotDW], ExitCode);
        CloseHandle(ProcHandles[SlotDW]);
        if ExitCode <> 0 then Inc(FailedCount);
        // Compact pool: swap finished slot with last entry.
        if SlotDW < DWORD(PoolCount) - 1 then
        begin
          ProcHandles[SlotDW]:= ProcHandles[PoolCount - 1];
          ProcItemIdx[SlotDW]:= ProcItemIdx[PoolCount - 1];
        end;
        Dec(PoolCount);
      end; // while

      // Build child command line.
      ChildCmdLine:= '"' + SelfExe + '" index --all --only "' + Plan.Items[i].Name + '"';
      if Plan.Items[i].Platform <> '' then ChildCmdLine:= ChildCmdLine + ' --platform "' + Plan.Items[i].Platform + '"';
      ChildCmdLine:= ChildCmdLine + ' --config "' + AArgs.WorkspaceConfig + '"' + ' --jobs 1';

      SetLength(ChildCmdBuf, Length(ChildCmdLine) + 1);
      Move(PChar(ChildCmdLine)^, ChildCmdBuf[0], (Length(ChildCmdLine) + 1) * SizeOf(WideChar));

      ZeroMemory(@SpawnSI, SizeOf(SpawnSI));
      SpawnSI.cb:= SizeOf(SpawnSI);
      ZeroMemory(@SpawnPI, SizeOf(SpawnPI));

      // Inherit console handles so child output interleaves on same stdout/stderr.
      if not CreateProcessW(nil, @ChildCmdBuf[0], nil, nil, True { bInheritHandles }, 0 { dwCreationFlags }, nil, nil, SpawnSI, SpawnPI) then
      begin
        Writeln(ErrOutput, 'ERROR: failed to spawn child for section "', Plan.Items[i].Name, '": GetLastError=', GetLastError);
        Inc(FailedCount);
        Continue;
      end;

      // Close thread handle; keep only the process handle.
      CloseHandle(SpawnPI.hThread);
      ProcHandles[PoolCount]:= SpawnPI.hProcess;
      ProcItemIdx[PoolCount]:= i;
      Inc(PoolCount);
    end; // for

    // Drain remaining pool.
    while PoolCount > 0 do
    begin
      WaitResult:= WaitForMultipleObjects(PoolCount, @ProcHandles[0], False { bWaitAll }, INFINITE);
      if (WaitResult >= WAIT_OBJECT_0) and (WaitResult < WAIT_OBJECT_0 + DWORD(PoolCount)) then SlotDW:= WaitResult - WAIT_OBJECT_0
      else SlotDW:= 0;
      ExitCode:= 0;
      GetExitCodeProcess(ProcHandles[SlotDW], ExitCode);
      CloseHandle(ProcHandles[SlotDW]);
      if ExitCode <> 0 then Inc(FailedCount);
      if SlotDW < DWORD(PoolCount) - 1 then
      begin
        ProcHandles[SlotDW]:= ProcHandles[PoolCount - 1];
        ProcItemIdx[SlotDW]:= ProcItemIdx[PoolCount - 1];
      end;
      Dec(PoolCount);
    end; // while

  finally
    // Safety net: close any handles still open after an exception.
    for i:= 0 to PoolCount - 1 do CloseHandle(ProcHandles[i]);
    PoolCount:= 0;
  end; // try

  OkCount:= TotalSections - FailedCount;
  Writeln(Format('parallel build: %d/%d sections OK (jobs=%d)', [OkCount, TotalSections, EffJobs]));

  if FailedCount > 0 then Result:= 1 else Result:= 0;
end; // function

/// <summary>Resolves the DB path for an index operation. If --db was given
/// explicitly, returns it unchanged. Otherwise finds the manifest section
/// whose include path covers AIndexPath (longest-prefix match) and returns
/// that section's resolved db. Falls back to AArgs.DbPath when no match.</summary>
/// <param name="AArgs">Parsed arguments; explicit DbPaths short-circuit the lookup.</param>
/// <param name="AIndexPath">Path being indexed (folder or file); used for matching.</param>
/// <returns>Absolute path to the DB to use for this index operation.</returns>
/// <remarks>Library sections (source=registry-libraries) are skipped. Not thread-safe.</remarks>
function ResolveIndexDb(const AArgs: TArgs; const AIndexPath: string): string;
var
  Manifest : TIndexManifest  ;
  Sec      : TIndexSection   ;
  IncPath  : string          ;
  PathNorm : string          ;
  IncNorm  : string          ;
  BestLen  : Integer         ;
  BestDb   : string          ;
  EngineDir: string          ;
  OutDir   : string          ;
  DbRaw    : string          ;
begin
  // Explicit --db always wins.
  if Length(AArgs.DbPaths) > 0 then Exit(AArgs.DbPath);

  BestLen:= -1;
  BestDb := '';
  try
    EngineDir:= ExtractFilePath(ParamStr(0));
    Manifest:= TManifestIO.Load(EngineDir, AIndexPath);
    PathNorm:= IncludeTrailingPathDelimiter(
                 TPath.GetFullPath(AIndexPath)).ToLower;

    for Sec in Manifest.Sections do
    begin
      // Skip library sections -- never auto-select them for index.
      if SameText(Sec.Source, 'registry-libraries') then Continue;
      for IncPath in Sec.Include do
      begin
        IncNorm:= IncludeTrailingPathDelimiter(
                    TPath.GetFullPath(IncPath)).ToLower;
        if PathNorm.StartsWith(IncNorm) and (Length(IncNorm) > BestLen) then
        begin
          BestLen:= Length(IncNorm);
          // Resolve Db to absolute using manifest OutDir/RootDir if relative.
          DbRaw:= Sec.Db;
          if DbRaw = '' then DbRaw:= Sec.Name + '.sqlite';
          if not TPath.IsPathRooted(DbRaw) then
          begin
            OutDir:= Manifest.OutDir;
            if OutDir <> '' then
            begin
              if TPath.IsPathRooted(OutDir) then
                BestDb:= TPath.Combine(OutDir, DbRaw)
              else
                BestDb:= TPath.Combine(TPath.Combine(Manifest.RootDir, OutDir), DbRaw);
            end
            else BestDb:= TPath.Combine(Manifest.RootDir, DbRaw);
          end
          else BestDb:= DbRaw;
        end;
      end; // for IncPath
    end; // for Sec
  except
    // Manifest unavailable -- fall through to default.
  end;

  if BestDb <> '' then Result:= BestDb
  else Result:= AArgs.DbPath; // default: drag-lint.sqlite in CWD
end; // function ResolveIndexDb

function DoIndex(const AArgs: TArgs): Integer;
var
  Store    : ISymbolStore                              ;
  Indexer  : IIndexer                                  ;
  Parser   : IParser                                   ;
  StartTime: TDateTime                                 ;
  Elapsed  : Double                                    ;
  Resolver : DRagLint.Project.Resolver.TProjectResolver;
  Folders  : TArray<string>                            ;
  F        : string                                    ;
begin
  if (AArgs.Path = '') and (AArgs.ProjectPath = '') and (not AArgs.ScanLibraries) then
  begin
    Writeln('ERROR: index requires a <path>, --project <file.dproj>, ' + 'or --scan-libraries');
    Exit(2);
  end;
  if AArgs.Path <> '' then
  begin
    if not (TDirectory.Exists(AArgs.Path) or TFile.Exists(AArgs.Path)) then
    begin
      Writeln('ERROR: path does not exist: ', AArgs.Path);
      Exit(2);
    end;
  end;
  if AArgs.ProjectPath <> '' then
  begin
    if not TFile.Exists(AArgs.ProjectPath) then
    begin
      Writeln('ERROR: .dproj not found: ', AArgs.ProjectPath);
      Exit(2);
    end;
  end;

  var ResolvedDb: string:= ResolveIndexDb(AArgs,
    IfThen(AArgs.Path <> '', AArgs.Path, GetCurrentDir));
  Writeln('Database: ', ResolvedDb);

  Store:= TSQLiteSymbolStore.Create(ResolvedDb);
  Store.Migrate;
  { v0.42: deep scan emits identifier usage refs. Default deep, except a
    --scan-libraries scan defaults shallow (libraries are queried by call/type,
    and usage-refs would ~double the 1.3 GB library DB). --deep/--shallow wins.
    Set on the concrete parser before it's held as IParser. }
  var DP: TDelphi13Parser:= TDelphi13Parser.Create;
  if AArgs.DeepExplicit then DP.EmitUsageRefs:= AArgs.Deep
  else DP.EmitUsageRefs:= not AArgs.ScanLibraries;
  Writeln('Usage refs (deep): ', BoolToStr(DP.EmitUsageRefs, True));
  Parser:= DP;
  // v0.16 Task 13: pass docs config from .drag-lint.json so the indexer
  // applies AllowBlankLineGap and CaptureLooseComments when associating
  // doc regions to symbols.
  { v0.40.5 Tier 1: register the Firebird SQL parser alongside Delphi/DFM. }
  Indexer:= TIndexer.Create(Store, [Parser, TDFMParser.Create, TFirebirdSqlParser.Create], AArgs.Docs);

  { v0.42: cross-dictionary dedup -- exclude any subtree the caller says is
    already covered by another index (library / active-project DB). }
  for var ExDir in AArgs.ExcludeUnder do
  begin
    Indexer.AddExcludeRoot(ExDir);
    Writeln('Excluding subtree: ', ExDir);
  end;

  { v0.45/v0.46: apply walk filter when any filter flag is present. Start from
    TWalkFilter.Create (SqlOnlyMS=True, MaxFileKB=2048 by default) so the
    safe defaults are preserved; --no-sql-ms clears SqlOnlyMS;
    --max-file-kb N overrides MaxFileKB (0 = unlimited). }
  if (Length(AArgs.ExcludeGlobs) > 0) or (Length(AArgs.IncludeOnlyGlobs) > 0) or AArgs.UseIgnore or AArgs.NoSqlMS or AArgs.MaxFileKBSet then
  begin
    var WF: TWalkFilter:= TWalkFilter.Create;
    WF.SectionExclude:= AArgs.ExcludeGlobs;
    WF.IncludeOnly   := AArgs.IncludeOnlyGlobs;
    WF.UseIgnoreFiles:= AArgs.UseIgnore;
    WF.SqlOnlyMS:= not AArgs.NoSqlMS;
    if AArgs.MaxFileKBSet then WF.MaxFileKB:= AArgs.MaxFileKB; // 0 = unlimited (caller opted out)
    Indexer.SetWalkFilter(WF);
  end;

  // Resolve target folders once (--scan-libraries / --project) or fall back
  // to the explicit path. The watch loop re-walks these on every tick;
  // unchanged files are skipped via mtime+sha256.
  if AArgs.ScanLibraries then
  begin
    if AArgs.ScanLibrariesAll then Writeln('Scope: Delphi Library + Browsing paths (registry, ALL platforms)')
    else Writeln('Scope: Delphi Library + Browsing paths (registry, Win32+Win64)');
    Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
    try
      Folders:= Resolver.ResolveLibraryPaths(AArgs.ScanLibrariesAll);
    finally
      Resolver.Free;
    end;
    Writeln(Format('Resolved %d unique library/browsing folders:', [Length(Folders)]));
    for F in Folders do Writeln('  ', F);
  end
  else if AArgs.ProjectPath <> '' then
  begin
    Writeln('Project: ', AArgs.ProjectPath);
    Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
    try
      Folders:= Resolver.Resolve(AArgs.ProjectPath);
    finally
      Resolver.Free;
    end;
    Writeln(Format('Resolved %d unique scan folders:', [Length(Folders)]));
    for F in Folders do Writeln('  ', F);
  end
  else Folders:= [AArgs.Path];

  if AArgs.DryRun then
  begin
    Writeln('--dry-run: NOT indexing. Re-run without --dry-run to index.');
    Result:= 0;
    Exit;
  end;

  var Interval:= AArgs.Interval;
  if AArgs.Watch and (Interval <= 0) then Interval:= 5;

  while True do
  begin
    StartTime:= Now;
    if AArgs.Watch then Writeln(Format('[%s] Indexing tick (interval=%ds)...', [FormatDateTime('hh:nn:ss', Now), Interval]))
    else Writeln('Indexing...');
    for F in Folders do
    begin
      if TFile.Exists(F) then Indexer.IndexFile(F)
      else Indexer.IndexFolder(F, True);
    end;
    { v0.40.4: post-pass resolves target_file_id for every unit_uses row.
      Done here (not inside the per-file transaction) because resolution
      needs to see every file the indexer has just written. }
    Store.ResolveUnitUseTargets;
    Store.ResolveAncestry; { v11 (M1): link class/interface heritage cross-unit }
    Elapsed:= (Now - StartTime) * 86400;
    if Indexer.SkippedUpToDate > 0 then Writeln(Format(
        'Done. Files: %d, Symbols: %d, Refs: %d, skipped %d up-to-date, %.2fs', [Store.CountFiles, Store.CountSymbols, Store.CountReferences, Indexer.SkippedUpToDate, Elapsed]))
    else Writeln(Format('Done. Files: %d, Symbols: %d, Refs: %d, %.2fs', [Store.CountFiles, Store.CountSymbols, Store.CountReferences, Elapsed]));
    if not AArgs.Watch then Break;
    Sleep(Interval * 1000);
  end; // while

  Result:= 0;
end; // function

// v0.42: build ONE dictionary database in-process from a set of folders/files,
// honouring the scan-hygiene filters (.scanignore, *BACKUP*, MS*.SQL) plus any
// caller-supplied exclude roots (cross-dictionary dedup).
function IndexDictionary(const ADbPath: string; const AFolders, AExcludeRoots: TArray<string>; const ADocs: TDocConfig; ADeep: Boolean; out AElapsedSec: Double): Boolean;
var
  Store  : ISymbolStore   ;
  Indexer: IIndexer       ;
  DParser: TDelphi13Parser;
  F      : string         ;
  Ex     : string         ;
  T0     : TDateTime      ;
begin
  Writeln('');
  Writeln('=== Dictionary: ', ADbPath, '  (deep=', BoolToStr(ADeep, True), ') ===');
  T0:= Now;
  Store:= TSQLiteSymbolStore.Create(ADbPath);
  Store.Migrate;
  { Each library/project ROOT is walked RECURSIVELY (soAllDirectories), so a
    unit whose .pas lives in a subfolder that is NOT itself on the Library/
    Browsing path -- only its DCU's folder is -- still gets indexed as long as
    it sits anywhere beneath a listed root. }
  DParser:= TDelphi13Parser.Create;
  DParser.EmitUsageRefs:= ADeep; { v0.42: deep dictionaries get usage refs }
  Indexer:= TIndexer.Create(Store, [DParser, TDFMParser.Create, TFirebirdSqlParser.Create], ADocs);
  for Ex in AExcludeRoots do Indexer.AddExcludeRoot(Ex);
  for F in AFolders do
  begin
    if TDirectory.Exists(F) then
    begin
      Writeln('  + ', F, '  (recursive, incl. subfolders)');
      Indexer.IndexFolder(F, True);
    end
    else if TFile.Exists(F) then Indexer.IndexFile(F)
    else Writeln('  (skip, not found) ', F);
  end;
  Store.ResolveUnitUseTargets;
  Store.ResolveAncestry; { v11 (M1): link class/interface heritage cross-unit }
  AElapsedSec:= (Now - T0) * 86400;
  Writeln(Format('  Done. Files: %d, Symbols: %d, Refs: %d  [%.1fs]', [Store.CountFiles, Store.CountSymbols, Store.CountReferences, AElapsedSec]));
  Result:= True;
end; // function

// v0.42: locate the nearest .drag-lint.json (cwd or any parent) and return its
// "scan" object, or nil. Caller frees the returned ROOT via the out param.
function FindScanConfig(out ARoot: TJSONObject): TJSONObject;
var
  Dir      : string;
  Candidate: string;
  Content  : string;
begin
  Result:= nil;
  ARoot := nil;
  Dir      := GetCurrentDir;
  Candidate:= '';
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, '.drag-lint.json')) then
    begin
      Candidate:= TPath.Combine(Dir, '.drag-lint.json');
      Break;
    end;
    if Dir = ExtractFilePath(Dir.TrimRight(['\','/'])) then Break;
    Dir:= ExtractFilePath(Dir.TrimRight(['\','/']));
  end;
  if Candidate = '' then Exit;
  try
    Content:= TFile.ReadAllText(Candidate);
    ARoot:= TJSONObject.ParseJSONValue(Content) as TJSONObject;
  except
    ARoot:= nil;
  end;
  if ARoot = nil then Exit;
  Writeln('(scan config: ', Candidate, ')');
  Result:= ARoot.GetValue('scan') as TJSONObject;
end; // function

// v0.42: drag-lint scan-all [--dry-run]
// DEPRECATED (v0.45): the manifest-driven `index --all` command supersedes
// scan-all. scan-all continues to work but emits a deprecation notice.
// Builds the user's THREE dictionaries with automatic cross-dedup, driven by
// the "scan" section of .drag-lint.json:
//   "scan": {
//     "outDir": "C:\\Projects\\.drag-lint",
//     "library": true,
//     "projects": ["C:\\Projects\\DB\\ORM3", ...],
//     "projectsRoot": "C:\\Projects"
//   }
// 1. library.sqlite        = Delphi Library + Browsing paths (registry).
// 2. active-projects.sqlite = every "projects" folder, frequently reindexed.
// 3. projects.sqlite       = projectsRoot, EXCLUDING every library root and
//                            every active-project root (so nothing is scanned
//                            into more than one dictionary).
// v0.45 Cleanup 1: translate the legacy "scan" block from .drag-lint.json into a
// TIndexManifest and delegate to the same ResolvePlan + BuildPlanItem core that
// `index --all` uses, so there is one build path. Mapping:
//   scan.library:true       -> section {name:"Library", source:"registry-libraries",
//                              platforms:["*"], db:"library-{platform}.sqlite"}
//   scan.projects[]:folder  -> folderTree section per folder (name = leaf name)
//   scan.projectsRoot:dir   -> section {name:"AllProjects", include:[dir],
//                              dedupAgainst:["*"]}
//   scan.outDir             -> manifest OutDir
// If no "scan" block is found, emits creation guidance and exits 2 (unchanged).
function DoScanAll(const AArgs: TArgs): Integer;
var
  Root        : TJSONObject                               ;
  Scan        : TJSONObject                               ;
  JProjects   : TJSONArray                                ;
  V           : TJSONValue                                ;
  i           : Integer                                   ;
  OutDir      : string                                    ;
  ProjectsRoot: string                                    ;
  DoLibrary   : Boolean                                   ;
  Manifest    : TIndexManifest                            ;
  Sec         : TIndexSection                             ;
  Plan        : TIndexPlan                                ;
  Resolver    : DRagLint.Project.Resolver.TProjectResolver;
  AnyFailed   : Boolean                                   ;
  JRoot       : TJSONObject                               ;
begin
  Writeln(ErrOutput, 'DEPRECATED: scan-all is superseded by `index --all`. ' + 'See global.drag-lint.json for the manifest format.');
  Scan:= FindScanConfig(Root);
  try
    if Scan = nil then
    begin
      Writeln('No "scan" section found in .drag-lint.json.'          );
      Writeln('Create one, e.g.:'                                    );
      Writeln('  { "scan": { "outDir": "C:\\Projects\\.drag-lint",'  );
      Writeln('              "library": true,'                       );
      Writeln('              "projects": ["C:\\Projects\\DB\\ORM3"],');
      Writeln('              "projectsRoot": "C:\\Projects" } }'     );
      Exit   (2                                                      );
    end;

    // --- Parse "scan" block fields ---
    OutDir:= '';
    V:= Scan.GetValue('outDir');
    if (V <> nil) and (V.Value <> '') then OutDir:= V.Value;
    if OutDir = '' then OutDir:= TPath.Combine(GetCurrentDir, '.drag-lint');

    DoLibrary:= True;
    V:= Scan.GetValue('library');
    if V is TJSONBool then DoLibrary:= TJSONBool(V).AsBoolean;

    ProjectsRoot:= '';
    V:= Scan.GetValue('projectsRoot');
    if (V <> nil) and (V.Value <> '') then ProjectsRoot:= V.Value;

    // --- Build TIndexManifest from the parsed scan block ---
    Manifest:= Default(TIndexManifest);
    Manifest.RootDir:= GetCurrentDir;
    Manifest.OutDir := OutDir;
    Manifest.Sections:= nil;

    // Library section: one per registered platform, shallow (no usage refs).
    if DoLibrary then
    begin
      Sec:= Default(TIndexSection);
      Sec.Name  := 'Library';
      Sec.Source:= 'registry-libraries';
      Sec.Platforms:= ['*']; // expand to all registered platforms
      Sec.DB:= 'library-{platform}.sqlite';
      SetLength(Manifest.Sections, Length(Manifest.Sections) + 1);
      Manifest.Sections[High(Manifest.Sections)]:= Sec;
    end;

    // One folderTree section per "projects" entry (name = folder leaf).
    if Scan.TryGetValue<TJSONArray>('projects', JProjects) then
      for i:= 0 to JProjects.Count - 1 do
      begin
        var ProjFolder:= JProjects.Items[i].Value;
        Sec:= Default(TIndexSection);
        Sec.Name:= ExtractFileName( ExcludeTrailingPathDelimiter(TPath.GetFullPath(ProjFolder)));
        if Sec.Name = '' then Sec.Name:= 'Project' + IntToStr(i + 1);
        Sec.Include:= [ProjFolder];
        SetLength(Manifest.Sections, Length(Manifest.Sections) + 1);
        Manifest.Sections[High(Manifest.Sections)]:= Sec;
      end;

    // AllProjects section: everything under projectsRoot, deduped against all others.
    if ProjectsRoot <> '' then
    begin
      Sec:= Default(TIndexSection);
      Sec.Name:= 'AllProjects';
      Sec.Include     := [ProjectsRoot];
      Sec.DedupAgainst:= ['*'         ];
      SetLength(Manifest.Sections, Length(Manifest.Sections) + 1);
      Manifest.Sections[High(Manifest.Sections)]:= Sec;
    end;

    // --- Resolve plan and dispatch ---
    Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
    try
      Plan:= ResolvePlan(Manifest, nil, Resolver);
    finally
      Resolver.Free;
    end;

    if AArgs.DryRun then
    begin
      if AArgs.AsJson then
      begin
        JRoot:= PlanToJson(Manifest, Plan);
        try
          Writeln(JRoot.Format(2));
        finally
          JRoot.Free;
        end;
      end
      else
      begin
        Writeln('scan-all --dry-run: plan derived from "scan" block:');
        Writeln('  OutDir:  ', OutDir);
        Writeln(Format('  Sections: %d', [Length(Plan.Items)]));
        for var PS in Plan.Items do Writeln(Format(
            '    [%s] mode=%s db=%s', [
              PS.Name + (if PS.Platform <> '' then '[' + PS.Platform + ']' else ''),
              (function: string begin case PS.Mode of smFolderTree: Result:= 'folderTree'; smClosure: Result:= 'closure'; smLibrary: Result:= 'library'; else Result:= '?'; end; end)(),
              PS.DbPath]));
      end;
      Exit(0);
    end; // if

    TDirectory.CreateDirectory(OutDir);
    AnyFailed:= False;
    for var PS in Plan.Items do
      if not BuildPlanItem(PS, AArgs.Docs) then AnyFailed:= True;

    if AnyFailed then Result:= 1 else Result:= 0;
  finally
    Root.Free;
  end; // try
end; // function

procedure PrintSymbols(const ASymbols: TArray<TSymbol>; AsJson: Boolean; const AFilePaths: TArray<string> = nil);
var
  JArr: TJSONArray ;
  JObj: TJSONObject;
  Sym : TSymbol    ;
  Line: string     ;
  i   : Integer    ;
begin
  if AsJson then
  begin
    JArr:= TJSONArray.Create;
    try
      for i:= 0 to High(ASymbols) do
      begin
        Sym:= ASymbols[i];
        JObj:= TJSONObject.Create;
        JObj.AddPair('id', TJSONNumber.Create(Sym.Id));
        JObj.AddPair('kind', Sym.Kind.ToText);
        JObj.AddPair('name'          , Sym.Name         );
        JObj.AddPair('qualified_name', Sym.QualifiedName);
        JObj.AddPair('signature'     , Sym.Signature    );
        JObj.AddPair('modifiers'     , Sym.Modifiers    );
        JObj.AddPair('section'       , Sym.Section      );
        { v11 (M1): class/interface ancestor list; omitted when empty. }
        if Sym.Heritage <> '' then JObj.AddPair('heritage', Sym.Heritage);
        { interface-section symbols (and members of interface-section types) are
          callable from another unit; implementation-only ones are not. }
        JObj.AddPair('usable_from_other_units', TJSONBool.Create(Sym.Section <> 'implementation'));
        JObj.AddPair('file_id', TJSONNumber.Create(Sym.FileId));
        { v8: resolved absolute path (the index has it in files.path; the JSON
          used to drop it, leaving only the internal file_id). Per-symbol so a
          multi-db query reports each symbol's own store path. }
        if (i <= High(AFilePaths)) and (AFilePaths[i] <> '') then JObj.AddPair('file', AFilePaths[i]);
        JObj.AddPair('start_line', TJSONNumber.Create(Sym.StartLine));
        JObj.AddPair('start_col' , TJSONNumber.Create(Sym.StartCol ));
        JObj.AddPair('end_line'  , TJSONNumber.Create(Sym.EndLine  ));
        JObj.AddPair('end_col'   , TJSONNumber.Create(Sym.EndCol   ));
        { v9: the routine's implementation BODY span (header..final 'end');
          0 when the symbol has no body. start_line/end_line stay the decl. }
        JObj.AddPair('impl_start_line', TJSONNumber.Create(Sym.ImplStartLine));
        JObj.AddPair('impl_end_line'  , TJSONNumber.Create(Sym.ImplEndLine  ));
        JArr.AddElement(JObj);
      end; // for
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end; // try
  end // if
  else
  begin
    Writeln(Format('%-12s %-30s %s', ['kind', 'name', 'qualified_name']));
    Writeln(StringOfChar('-', 75));
    for Sym in ASymbols do
    begin
      Line:= Format('%-12s %-30s %s', [Sym.Kind.ToText, Sym.Name, Sym.QualifiedName]);
      if Sym.Signature <> '' then { gap #1/#2: show sig, distinguish overloads }
      begin
        { v0.42: Signature now carries the full param list (+ return type).
          A function's sig already begins with ': ' (e.g. ': Boolean'), so
          only inject the separator when it doesn't start with '(' or ':'. }
        if (Sym.Signature[1] = '(') or (Sym.Signature[1] = ':') then Line:= Line + ' ' + Sym.Signature
        else Line:= Line + ' : ' + Sym.Signature;
      end;
      if Sym.Section = 'implementation' then { gap #3: not usable from other units }
        Line:= Line + '  [impl-only]';
      Writeln(Line);
    end;
    Writeln(Format('%d match(es)', [Length(ASymbols)]));
  end; // else
end; // procedure

function DoQueryHints(const AArgs: TArgs): Integer; forward;

// v0.16: query find --doc-tag X | --doc-contains Y | --no-docs [--kind K] [--public]
// Output per result: "<qualified_name>  [<kind>]  <file_path>:<start_line>"
// Exit 0 if any results, 1 if none.
function DoQueryFind(const AArgs: TArgs): Integer;
var
  Store   : ISymbolStore   ;
  Syms    : TArray<TSymbol>;
  S       : TSymbol        ;
  FilePath: string         ;
begin
  if (AArgs.DocTag = '') and (AArgs.DocContains = '') and (not AArgs.NoDocs) then
  begin
    Writeln('Usage: drag-lint query find [--doc-tag X | --doc-contains Y | --no-docs] ' + '[--kind K] [--public] [--db <file.sqlite>]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit   (2                                    );
  end;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  if AArgs.NoDocs then Syms:= Store.FindUndocumented(AArgs.Kind, AArgs.PublicOnly)
  else if AArgs.DocTag <> '' then Syms:= Store.FindByDocTag(AArgs.DocTag)
  else Syms:= Store.FindByDocContains(AArgs.DocContains);

  for S in Syms do
  begin
    FilePath:= Store.GetFilePath(S.FileId);
    Writeln(System.SysUtils.Format('%s  [%s]  %s:%d', [S.QualifiedName, S.Kind.ToText, FilePath, S.StartLine]));
  end;

  if Length(Syms) = 0 then Result:= 1
  else Result:= 0;
end; // function

{ resolve-uses: "which unit defines this symbol, and which should I add to my
  uses clause?"  Finds every indexed symbol named <name>, groups by defining
  unit (first segment of the qualified name), and ranks:
    1. units NOT already in the caller's uses (--in) -- the actionable add
    2. project units before library/RTL units (path heuristic)
    3. units defining the requested --kind
    4. more definitions of the name, then alphabetical
  Value-type affinity is intentionally out of scope (the index stores a const's
  location, not its resolved value type) -- this is a ranked suggestion, not a
  compiler. }
function DoResolveUses(const AArgs: TArgs): Integer;
type
  TUnitHit = record
    UnitName   : string ;
    BestKind   : string ;
    Kinds      : string ;
    SampleFile : string ;
    SampleLine : Integer;
    Count      : Integer;
    AlreadyUsed: Boolean;
    IsLibrary  : Boolean;
    HasUsable  : Boolean; { symbol declared in this unit's interface section }
    Score      : Integer;
  end;

  function IsLibraryPath(const P: string): Boolean;
  var
    L: string;
  begin
    L:= LowerCase(P);
    Result:= (Pos('\embarcadero\', L) > 0) or (Pos('\program files', L) > 0) or (Pos('\dcc\', L) > 0);
  end;

var
  Store    : ISymbolStore                ;
  Syms     : TArray<TSymbol>             ;
  S        : TSymbol                     ;
  Map      : TDictionary<string, Integer>;
  UsedUnits: TDictionary<string, Boolean>;
  Hits     : TArray<TUnitHit>            ;
  H        : TUnitHit                    ;
  UnitName : string                      ;
  DotPos   : Integer                     ;
  InFileId : Int64                       ;
  UU       : TArray<TUnitUse>            ;
  U        : TUnitUse                    ;
  FilePath : string                      ;
  i        : Integer                     ;
  J        : Integer                     ;
  Idx      : Integer                     ;
  JArr     : TJSONArray                  ;
  JO       : TJSONObject                 ;
begin
  if AArgs.Name = '' then
  begin
    Writeln('Usage: drag-lint resolve-uses --name <Symbol> [--in <file.pas>] ' + '[--kind K] [--json] [--db <file.sqlite>]');
    Writeln('  Finds which unit(s) define <Symbol> and ranks which to add to ' + 'your uses clause.'                       );
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit   (2                                    );
  end;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  Syms:= Store.FindSymbolsByExactName(AArgs.Name);

  UsedUnits:= TDictionary<string, Boolean>.Create;
  Map      := TDictionary<string, Integer>.Create;
  try
    { units already imported by the caller (from the index, not re-parsed) }
    if AArgs.InFile <> '' then
    begin
      InFileId:= Store.FindFileIdByPath(TPath.GetFullPath(AArgs.InFile));
      if InFileId <= 0 then InFileId:= Store.FindFileIdByPath(AArgs.InFile);
      if InFileId > 0 then
      begin
        UU:= Store.GetUnitUsesForFile(InFileId);
        for U in UU do UsedUnits.AddOrSetValue(LowerCase(U.UnitName), True);
      end;
    end;

    SetLength(Hits, 0);
    for S in Syms do
    begin
      if (AArgs.Kind <> '') and not SameText(S.Kind.ToText, AArgs.Kind) then Continue;
      { Unit name = the .pas file's basename stem.  Delphi requires the unit
        name to equal the file name, and this is correct for DOTTED unit names
        (Blueprint4.Interfaces.pas -> "Blueprint4.Interfaces"), unlike taking
        the first segment of the qualified name. }
      FilePath:= Store.GetFilePath(S.FileId);
      UnitName:= ChangeFileExt(ExtractFileName(FilePath), '');
      if UnitName = '' then
      begin
        DotPos:= Pos('.', S.QualifiedName);
        if DotPos > 0 then UnitName:= Copy(S.QualifiedName, 1, DotPos - 1)
        else UnitName:= S.QualifiedName;
      end;
      if UnitName = '' then Continue;

      if Map.TryGetValue(LowerCase(UnitName), Idx) then
      begin
        Inc(Hits[Idx].Count);
        if Pos(S.Kind.ToText, Hits[Idx].Kinds) = 0 then Hits[Idx].Kinds:= Hits[Idx].Kinds + ',' + S.Kind.ToText;
        if S.Section <> 'implementation' then Hits[Idx].HasUsable:= True;
      end
      else
      begin
        H:= Default(TUnitHit);
        H.UnitName:= UnitName;
        H.BestKind:= S.Kind.ToText;
        H.Kinds   := S.Kind.ToText;
        H.SampleFile:= FilePath;
        H.SampleLine:= S.StartLine;
        H.Count:= 1;
        H.AlreadyUsed:= UsedUnits.ContainsKey(LowerCase(UnitName));
        H.IsLibrary:= IsLibraryPath(FilePath);
        H.HasUsable:= S.Section <> 'implementation';
        SetLength(Hits, Length(Hits) + 1);
        Hits[High(Hits)]:= H;
        Map.AddOrSetValue(LowerCase(UnitName), High(Hits));
      end;
    end; // for

    { score }
    for i:= 0 to High(Hits) do
    begin
      Hits[i].Score:= 0;
      { a unit where the symbol is only in the implementation section can't be
        satisfied by a `uses` -- push it well below usable units. }
      if Hits[i].HasUsable then Inc(Hits[i].Score, 10000);
      if not Hits[i].AlreadyUsed then Inc(Hits[i].Score, 1000);
      if not Hits[i].IsLibrary   then Inc(Hits[i].Score, 100 );
      if (AArgs.Kind <> '') and SameText(Hits[i].BestKind, AArgs.Kind) then Inc(Hits[i].Score, 10);
      Inc(Hits[i].Score, Hits[i].Count);
    end;

    { sort: score desc, then unit name asc (bubble -- result sets are tiny) }
    for i:= 0 to High(Hits) - 1 do
      for J:= 0 to High(Hits) - 2 - i do
        if (Hits[J].Score < Hits[J + 1].Score) or ((Hits[J].Score = Hits[J + 1].Score) and (CompareText(Hits[J].UnitName, Hits[J + 1].UnitName) > 0)) then
        begin
          H:= Hits[J]; Hits[J]:= Hits[J + 1]; Hits[J + 1]:= H;
        end;

    if AArgs.AsJson then
    begin
      JArr:= TJSONArray.Create;
      try
        for i:= 0 to High(Hits) do
        begin
          JO:= TJSONObject.Create;
          JO.AddPair('unit' , Hits[i].UnitName  );
          JO.AddPair('kinds', Hits[i].Kinds     );
          JO.AddPair('file' , Hits[i].SampleFile);
          JO.AddPair('line'           , TJSONNumber.Create(Hits[i].SampleLine ));
          JO.AddPair('count'          , TJSONNumber.Create(Hits[i].Count      ));
          JO.AddPair('already_in_uses', TJSONBool  .Create(Hits[i].AlreadyUsed));
          JO.AddPair('library'        , TJSONBool  .Create(Hits[i].IsLibrary  ));
          JArr.AddElement(JO);
        end;
        Writeln(JArr.ToJson);
      finally
        JArr.Free;
      end; // try
    end // if
    else if Length(Hits) = 0 then Writeln(Format('No unit in the index defines "%s".', [AArgs.Name]))
    else
    begin
      Writeln(Format('"%s" is defined in %d unit(s):', [AArgs.Name, Length(Hits)]));
      for i:= 0 to High(Hits) do Writeln(Format(
          '  %-28s [%s]%s%s%s  (%s:%d)', [
            Hits[i].UnitName, Hits[i].Kinds, IfThen(Hits[i].AlreadyUsed, '  <already in uses>', ''), IfThen(Hits[i].IsLibrary, '  <library>', ''),
            IfThen(not Hits[i].HasUsable, '  <impl-only: NOT usable via uses>', ''), Hits[i].SampleFile, Hits[i].SampleLine]));
      { suggest the top unit only if it is actually usable + not already used }
      if Hits[0].HasUsable and (not Hits[0].AlreadyUsed) then Writeln(Format('Suggestion: add "%s" to your uses clause.', [Hits[0].UnitName]));
    end; // else

    if Length(Hits) = 0 then Result:= 1 else Result:= 0;
  finally
    Map.Free;
    UsedUnits.Free;
  end; // try
end; // begin

// v0.57 Task 8: text-constant search (phrase / any-order / substring).
// Placed immediately before DoQuery so no forward declaration is needed.
function DoQueryText(const AArgs: TArgs): Integer;
var
  PathsToScan: TArray<string>        ;
  DbPath     : string                ;
  Store      : ISymbolStore          ;
  Mode       : string                ;
  Lim        : Integer               ;
  Matches    : TArray<TStringLitMatch>;
  AllMatches : TArray<TStringLitMatch>;
  M          : TStringLitMatch       ;
  JArr       : TJSONArray            ;
  JObj       : TJSONObject           ;
begin
  if AArgs.TextQuery = '' then begin Writeln('ERROR: query --text requires a phrase'); Exit(2); end;
  if AArgs.TextSubstring then Mode:= 'substring'
  else if AArgs.TextAnyOrder then Mode:= 'anyorder'
  else Mode:= 'phrase';
  if AArgs.Limit > 0 then Lim:= AArgs.Limit else Lim:= 200;
  if (Mode = 'substring') and (Length(Trim(AArgs.TextQuery)) < 3) then
    Writeln('NOTE: --substring needs a query of at least 3 characters (trigram tokenizer); "' + AArgs.TextQuery + '" is too short - try --any-order for shorter terms.');

  PathsToScan:= ResolveConsumerDbs(AArgs);
  for DbPath in PathsToScan do
    if not TFile.Exists(DbPath) then
    begin
      Writeln('ERROR: database not found: ', DbPath);
      Writeln('Run "drag-lint index <path>" first.');
      Exit(2);
    end;

  SetLength(AllMatches, 0);
  for DbPath in PathsToScan do
  begin
    Store:= TSQLiteSymbolStore.Create(DbPath);
    Store.Migrate;
    Matches:= Store.SearchText(AArgs.TextQuery, Mode, AArgs.TextSource, Lim);
    for M in Matches do
    begin
      SetLength(AllMatches, Length(AllMatches) + 1);
      AllMatches[High(AllMatches)]:= M;
    end;
  end;
  if Length(AllMatches) > Lim then SetLength(AllMatches, Lim);

  if AArgs.AsJson then
  begin
    JArr:= TJSONArray.Create;
    try
      for M in AllMatches do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('file_path',   M.FilePath  );
        JObj.AddPair('start_line',  TJSONNumber.Create(M.StartLine));
        JObj.AddPair('start_col',   TJSONNumber.Create(M.StartCol ));
        JObj.AddPair('source',      M.Source    );
        JObj.AddPair('kind',        M.Kind      );
        JObj.AddPair('owner_name',  M.OwnerName );
        JObj.AddPair('text',        M.Text      );
        JObj.AddPair('enclosing',   M.EnclosingQName);
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end;
  end
  else
  begin
    for M in AllMatches do
      Writeln(Format('%s:%d:%d  [%s/%s]  %s%s',
        [M.FilePath, M.StartLine, M.StartCol, M.Source, M.Kind, M.Text,
         IfThen(M.EnclosingQName <> '', '  -> ' + M.EnclosingQName, '')]));
    Writeln(Format('%d match(es)', [Length(AllMatches)]));
  end;
  if Length(AllMatches) > 0 then Result:= 0 else Result:= 1;
end;

function DoQuery(const AArgs: TArgs): Integer;
var
  Symbols       : TArray<TSymbol>                 ;
  AllSymbols    : TArray<TSymbol>                 ;
  AllPaths      : TArray<string>                  ; { v8: abs path per AllSymbols entry (own store) }
  Refs          : TArray<TReference>              ;
  AllRefs       : TArray<TReference>              ;
  DbPath        : string                          ;
  DbPaths       : TArray<string>                  ;
  Store         : ISymbolStore                    ;
  StoresByDb    : TDictionary<Int64, ISymbolStore>;
  PathsToScan   : TArray<string>                  ;
  S             : TSymbol                         ;
  R             : TReference                      ;
  LastStore     : ISymbolStore                    ;
  EffSizeGuardMB: Integer                         ;
begin
  // v0.57 Task 8: text-content search routes to its own handler.
  if AArgs.TextQuery <> '' then Exit(DoQueryText(AArgs));

  // v0.45 Task 9: resolve DB list (explicit --db or manifest-driven).
  PathsToScan:= ResolveConsumerDbs(AArgs);
  for DbPath in PathsToScan do
  begin
    if not TFile.Exists(DbPath) then
    begin
      Writeln('ERROR: database not found: ', DbPath);
      Writeln('Run "drag-lint index <path>" first.');
      Exit   (2                                    );
    end;
  end;
  // Size guard: determine effective threshold then check each DB.
  if AArgs.SizeGuardMBSet then EffSizeGuardMB:= AArgs.SizeGuardMB
  else
  begin
    // Load manifest for sizeGuardMB setting (best-effort; ignore errors).
    EffSizeGuardMB:= 1500; // default
    try
      var SgManifest:= TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
      EffSizeGuardMB:= SgManifest.Settings.SizeGuardMB;
    except
      // ignore
    end;
  end;
  for DbPath in PathsToScan do SizeGuardCheck(DbPath, EffSizeGuardMB, AArgs.Force32);

  SetLength(AllSymbols, 0);
  SetLength(AllRefs   , 0);
  LastStore:= nil;

  // For find-callers we need to render with the store that owns each ref
  // (for GetFilePath). Easiest: iterate DBs, accumulate, render once we know
  // the dominant store. Or render per-db. For v0.3 minimum, just print
  // header once and concat. PrintReferences walks per-row; we pass the
  // store that owns the rows in that batch.
  if AArgs.SubCommand = 'find-callers' then
  begin
    if AArgs.Name = '' then
    begin
      Writeln('ERROR: find-callers requires --name <callee>');
      Exit   (2                                             );
    end;
    var TotalRefs:= 0;
    for DbPath in PathsToScan do
    begin
      Store:= TSQLiteSymbolStore.Create(DbPath);
      Store.Migrate;
      // v0.17: use context variant if --context N is provided
      if AArgs.ContextLines > 0 then Refs:= Store.FindCallersByNameWithContext(AArgs.Name, AArgs.ContextLines)
      else Refs:= Store.FindCallersByName(AArgs.Name);
      if Length(Refs) > 0 then
      begin
        if AArgs.ContextLines > 0 then PrintReferencesWithContext(Store, Refs, AArgs.ContextLines, AArgs.AsJson)
        else PrintReferences(Store, Refs, AArgs.AsJson);
        Inc(TotalRefs, Length(Refs));
      end;
    end; // for
    if (TotalRefs = 0) and (not AArgs.AsJson) then Writeln('0 caller(s)');
    if TotalRefs = 0 then Result:= 1
    else Result:= 0;
    Exit;
  end; // if

  if AArgs.SubCommand = 'hints' then
  begin
    Result:= DoQueryHints(AArgs);
    Exit;
  end;

  if AArgs.SubCommand = 'find' then
  begin
    Result:= DoQueryFind(AArgs);
    Exit;
  end;

  // v11 (M1): transitive type ancestry. `--name T` lists T's resolved ancestor
  // closure; adding `--of A` reports whether T descends from / implements A.
  if AArgs.SubCommand = 'ancestors' then
  begin
    if AArgs.Name = '' then
    begin
      Writeln('ERROR: query ancestors requires --name <type>');
      Exit(2);
    end;
    for DbPath in PathsToScan do
    begin
      Store:= TSQLiteSymbolStore.Create(DbPath);
      Store.Migrate;
      var StartId  : Int64  := 0;
      var StartKind: string := '';
      for S in Store.FindSymbolsByExactName(AArgs.Name) do
        if S.Kind in [skClass, skInterface, skRecord] then
        begin
          StartId  := S.Id;
          StartKind:= S.Kind.ToText;
          Break;
        end;
      if StartId <= 0 then Continue; { try the next DB }

      if AArgs.OfName <> '' then
      begin
        var IsDesc:= Store.IsDescendantOf(AArgs.Name, AArgs.OfName, 0);
        var Impl  := Store.ImplementsInterface(AArgs.Name, AArgs.OfName, 0);
        if AArgs.AsJson then
        begin
          var JO:= TJSONObject.Create;
          try
            JO.AddPair('name', AArgs.Name);
            JO.AddPair('of'  , AArgs.OfName);
            JO.AddPair('is_descendant', TJSONBool.Create(IsDesc));
            JO.AddPair('implements'   , TJSONBool.Create(Impl  ));
            Writeln(JO.Format(2));
          finally JO.Free; end;
        end
        else Writeln(Format('%s descends %s: %s; implements: %s',
          [AArgs.Name, AArgs.OfName, BoolToStr(IsDesc, True), BoolToStr(Impl, True)]));
        Exit(0);
      end;

      var Ancs:= Store.GetTransitiveAncestors(StartId);
      if AArgs.AsJson then
      begin
        var JO:= TJSONObject.Create;
        try
          JO.AddPair('name', AArgs.Name);
          JO.AddPair('kind', StartKind);
          var Arr:= TJSONArray.Create;
          for var A in Ancs do
          begin
            var AO:= TJSONObject.Create;
            AO.AddPair('name'    , A.Name);
            AO.AddPair('kind'    , A.Kind);
            AO.AddPair('resolved', TJSONBool.Create(A.Resolved));
            Arr.AddElement(AO);
          end;
          JO.AddPair('ancestors', Arr);
          Writeln(JO.Format(2));
        finally JO.Free; end;
      end
      else
      begin
        Writeln(AArgs.Name, ' ancestors:');
        for var A in Ancs do
          if A.Resolved then Writeln(Format('  %s [%s]', [A.Name, A.Kind]))
          else Writeln(Format('  %s [%s] (unresolved)', [A.Name, A.Kind]));
        if Length(Ancs) = 0 then Writeln('  (none)');
      end;
      Exit(0);
    end; // for DbPath

    if AArgs.AsJson then Writeln(Format('{"name":"%s","ancestors":[]}', [AArgs.Name]))
    else Writeln('type not found: ', AArgs.Name);
    Exit(1);
  end;

  // v11 (M1): resolve a type name to its broad category (intrinsic / declared /
  // alias-chased). Useful standalone and as the test surface for the resolver.
  if AArgs.SubCommand = 'typecat' then
  begin
    if AArgs.Name = '' then
    begin
      Writeln('ERROR: query typecat requires --name <type>');
      Exit(2);
    end;
    Store:= TSQLiteSymbolStore.Create(PathsToScan[0]);
    Store.Migrate;
    var Cat:= Store.ResolveTypeCategory(AArgs.Name, 0).ToText;
    if AArgs.AsJson then
    begin
      var JO:= TJSONObject.Create;
      try
        JO.AddPair('name', AArgs.Name);
        JO.AddPair('category', Cat);
        Writeln(JO.Format(2));
      finally JO.Free; end;
    end
    else Writeln(Format('%s: %s', [AArgs.Name, Cat]));
    Exit(0);
  end;

  if AArgs.SubCommand <> '' then
  begin
    Writeln('ERROR: unknown query subcommand: ', AArgs.SubCommand);
    Exit(2);
  end;

  if (AArgs.QName = '') and (AArgs.Name = '') then
  begin
    Writeln('ERROR: query requires --name or --qname');
    Exit   (2                                        );
  end;

  for DbPath in PathsToScan do
  begin
    Store:= TSQLiteSymbolStore.Create(DbPath);
    Store.Migrate;
    if AArgs.QName <> '' then Symbols:= Store.FindSymbolsByQualifiedName(AArgs.QName)
    else Symbols:= Store.FindSymbolsByExactName(AArgs.Name);
    for S in Symbols do
    begin
      SetLength(AllSymbols, Length(AllSymbols) + 1);
      AllSymbols[High(AllSymbols)]:= S;
      SetLength(AllPaths, Length(AllPaths) + 1);
      AllPaths[High(AllPaths)]:= Store.GetFilePath(S.FileId);
    end;
    LastStore:= Store;
  end; // for

  if (Length(AllSymbols) = 0) and (AArgs.Name <> '') then
  begin
    // Fuzzy fallback: hit each DB, accumulate, top-K overall.
    for DbPath in PathsToScan do
    begin
      Store:= TSQLiteSymbolStore.Create(DbPath);
      Store.Migrate;
      Symbols:= Store.FindSymbolsFuzzy(AArgs.Name, 10);
      for S in Symbols do
      begin
        SetLength(AllSymbols, Length(AllSymbols) + 1);
        AllSymbols[High(AllSymbols)]:= S;
        SetLength(AllPaths, Length(AllPaths) + 1);
        AllPaths[High(AllPaths)]:= Store.GetFilePath(S.FileId);
      end;
    end;
    if Length(AllSymbols) > 0 then
    begin
      if not AArgs.AsJson then Writeln(Format('(no exact match for "%s" - closest matches:)', [AArgs.Name]));
      PrintSymbols(AllSymbols, AArgs.AsJson, AllPaths);
      Exit(0);
    end;
  end; // if
  PrintSymbols(AllSymbols, AArgs.AsJson, AllPaths);
  if Length(AllSymbols) = 0 then Result:= 1
  else Result:= 0;
end; // function

// --- export -----------------------------------------------------------------

type
  TEnumRow = record
    EnumQName: string ;
    EnumName : string ;
    Ordinal  : Integer;
    ValueName: string ;
  end;

function FetchEnumRows(const ADbPath: string): TArray<TEnumRow>;
var
  Conn    : TFDConnection  ;
  Q       : TFDQuery       ;
  List    : TList<TEnumRow>;
  Row     : TEnumRow       ;
  LastEnum: string         ;
  Ord     : Integer        ;
begin
  List:= TList<TEnumRow>.Create;
  Conn:= TFDConnection.Create(nil);
  Q   := TFDQuery     .Create(nil);
  try
    Conn.DriverName:= 'SQLite';
    Conn.Params.Values['Database']:= ADbPath;
    Conn.LoginPrompt:= False;
    Conn.Connected  := True;
    Q   .Connection := Conn;
    Q.Sql.Text:= 'SELECT enum.qualified_name AS enum_qname, enum.name AS enum_name, ' + '       val.name AS value_name, val.start_line AS line_no ' + 'FROM symbols enum ' +
    'JOIN symbols val ON val.parent_id = enum.id ' + 'WHERE enum.kind = ''enum'' AND val.kind = ''enum_value'' ' + 'ORDER BY enum.qualified_name, val.start_line, val.id';
    Q.Open;
    LastEnum:= '';
    Ord     := 0;
    while not Q.Eof do
    begin
      Row.EnumQName:= Q.FieldByName('enum_qname').AsString;
      Row.EnumName := Q.FieldByName('enum_name' ).AsString;
      Row.ValueName:= Q.FieldByName('value_name').AsString;
      if Row.EnumQName <> LastEnum then
      begin
        Ord:= 0;
        LastEnum:= Row.EnumQName;
      end;
      Row.Ordinal:= Ord;
      Inc(Ord);
      List.Add(Row);
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    Conn.Free;
    List.Free;
  end; // try
end; // function

function SqlQuote(const S: string): string;
begin
  Result:= '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
end;

procedure EmitEnumsFirebird(const ARows: TArray<TEnumRow>; AOut: TTextWriter);
var
  R: TEnumRow;
begin
  AOut.WriteLine('-- Generated by drag-lint export enums --format firebird-sql'      );
  AOut.WriteLine('-- One row per (enum_type, enum_value); ordinal is 0-based'        );
  AOut.WriteLine('-- declaration order within the enum.'                             );
  AOut.WriteLine(''                                                                  );
  AOut.WriteLine('CREATE TABLE IF NOT EXISTS FIB$ENUMVALUES ('                       );
  AOut.WriteLine('  ENUM_TYPE  VARCHAR(255) NOT NULL,'                               );
  AOut.WriteLine('  ENUM_NAME  VARCHAR(63)  NOT NULL,'                               );
  AOut.WriteLine('  ORDINAL    INTEGER      NOT NULL,'                               );
  AOut.WriteLine('  VALUE_NAME VARCHAR(63)  NOT NULL,'                               );
  AOut.WriteLine('  CONSTRAINT PK_FIB_ENUMVALUES PRIMARY KEY (ENUM_TYPE, VALUE_NAME)');
  AOut.WriteLine(');'                                                                );
  AOut.WriteLine(''                                                                  );
  for R in ARows do AOut.WriteLine(Format(
      'INSERT INTO FIB$ENUMVALUES (ENUM_TYPE, ENUM_NAME, ORDINAL, VALUE_NAME) ' + 'VALUES (%s, %s, %d, %s);',
      [SqlQuote(R.EnumQName), SqlQuote(R.EnumName), R.Ordinal, SqlQuote(R.ValueName)]));
end; // procedure

procedure EmitEnumsCsv(const ARows: TArray<TEnumRow>; AOut: TTextWriter);
var
  R: TEnumRow;
begin
  AOut.WriteLine('enum_qname,enum_name,ordinal,value_name');
  for R in ARows do AOut.WriteLine(Format('%s,%s,%d,%s', [R.EnumQName, R.EnumName, R.Ordinal, R.ValueName]));
end;

procedure EmitEnumsJson(const ARows: TArray<TEnumRow>; AOut: TTextWriter);
var
  Doc     : TJSONArray ;
  Cur     : TJSONObject;
  Vals    : TJSONArray ;
  V       : TJSONObject;
  R       : TEnumRow   ;
  LastEnum: string     ;
begin
  Doc:= TJSONArray.Create;
  Cur := nil;
  Vals:= nil;
  LastEnum:= '';
  try
    for R in ARows do
    begin
      if R.EnumQName <> LastEnum then
      begin
        Cur:= TJSONObject.Create;
        Cur.AddPair('enum_qname', R.EnumQName);
        Cur.AddPair('enum_name' , R.EnumName );
        Vals:= TJSONArray.Create;
        Cur.AddPair('values', Vals);
        Doc.AddElement(Cur);
        LastEnum:= R.EnumQName;
      end;
      V:= TJSONObject.Create;
      V.AddPair('ordinal', TJSONNumber.Create(R.Ordinal));
      V.AddPair('name', R.ValueName);
      Vals.AddElement(V);
    end; // for
    AOut.WriteLine(Doc.Format(2));
  finally
    Doc.Free;
  end; // try
end; // procedure

function LastSegment(const S: string; ASep: Char): string;
var
  DotPos: Integer;
begin
  DotPos:= LastDelimiter(ASep, S);
  if DotPos > 0 then Result:= Copy(S, DotPos + 1, MaxInt)
  else Result:= S;
end;

procedure EmitEnumsDelphiConst(const ARows: TArray<TEnumRow>; AOut: TTextWriter);
var
  R            : TEnumRow   ;
  LastEnum     : string     ;
  Names        : TStringList;
  EnumShortName: string     ;
  FlatName     : string     ;

  procedure FlushBlock;
  begin
    if Names.Count = 0 then Exit;
    EnumShortName:= LastSegment(LastEnum, '.');
    FlatName:= StringReplace(LastEnum, '.', '_', [rfReplaceAll]);
    AOut.WriteLine(Format('  %s_Names: array[%s] of string = (%s);', [FlatName, EnumShortName, string.Join(', ', Names.ToStringArray)]));
    Names.Clear;
  end;

begin
  AOut.WriteLine('// Generated by drag-lint export enums --format delphi-const');
  AOut.WriteLine('// Paste into a Delphi unit''s implementation section.'      );
  AOut.WriteLine(''                                                            );
  AOut.WriteLine('const'                                                       );
  LastEnum:= '';
  Names:= TStringList.Create;
  try
    for R in ARows do
    begin
      if R.EnumQName <> LastEnum then
      begin
        FlushBlock;
        LastEnum:= R.EnumQName;
      end;
      Names.Add('''' + R.ValueName + '''');
    end;
    FlushBlock;
  finally
    Names.Free;
  end;
end; // begin

function DoExportEnums(const AArgs: TArgs): Integer;
var
  Rows  : TArray<TEnumRow>;
  Buf   : TStringStream   ;
  Writer: TStreamWriter   ;
  Fmt   : string          ;
begin
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: export enums requires --db <file.sqlite>');
    Exit   (2                                                );
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  Fmt:= AArgs.Format;
  if Fmt = '' then Fmt:= 'firebird-sql';

  Rows:= FetchEnumRows(AArgs.DbPath);

  // Render into a memory buffer, then either write to file or write to stdout.
  Buf:= TStringStream.Create('', TEncoding.UTF8);
  Writer:= TStreamWriter.Create(Buf);
  try
    if Fmt      = 'firebird-sql' then EmitEnumsFirebird(Rows, Writer)
    else if Fmt = 'csv' then EmitEnumsCsv(Rows, Writer)
    else if Fmt = 'json' then EmitEnumsJson(Rows, Writer)
    else if Fmt = 'delphi-const' then EmitEnumsDelphiConst(Rows, Writer)
    else
    begin
      Writeln('ERROR: unknown format: ', Fmt);
      Exit(2);
    end;
    Writer.Flush;
    if AArgs.Output <> '' then
    begin
      TFile.WriteAllText(AArgs.Output, Buf.DataString, TEncoding.UTF8);
      Writeln(Format('Wrote %d enum value row(s) (%d enums) to %s', [Length(Rows), 0 { let user grep -c 'INSERT' for now }, AArgs.Output]));
    end
    else Write(Buf.DataString);
  finally
    Writer.Free;
    Buf.Free;
  end; // try
  Result:= 0;
end; // function

// --- export obsidian --------------------------------------------------------

function ObsidianSanitizeFilename(const S: string): string;
const
  Bad: array[0..6] of Char = ('\', '/', ':', '*', '?', '"', '|');
var
  C: Char;
begin
  Result:= S;
  for C in Bad do Result:= StringReplace(Result, C, '_', [rfReplaceAll]);
end;

// Generate a 16-char lowercase hex ID for the Obsidian vault registry.
// Obsidian uses 16-hex vault IDs in obsidian.json; we just need something
// unique-enough that doesn't collide with existing entries.
function NewVaultId: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result:= LowerCase(StringReplace(StringReplace(G.ToString, '{', '', []), '}', '', []));
  Result:= StringReplace(Result, '-', '', [rfReplaceAll]);
  Result:= Copy(Result, 1, 16);
end;

// v0.15: register the freshly-exported folder as an Obsidian vault and
// open it. Three steps: create .obsidian/, add the path to
// %APPDATA%\obsidian\obsidian.json (idempotent -- skip if already
// registered), launch obsidian://open?vault=<basename>. Failures are
// non-fatal (Obsidian not installed, registry malformed, etc.); we
// print a hint and continue.
procedure OpenInObsidian(const AVaultPath: string);
var
  AbsPath          : string       ;
  BaseName         : string       ;
  ObsCfg           : string       ;
  ObsDir           : string       ;
  Existing         : string       ;
  Body             : string       ;
  Uri              : string       ;
  Cfg              : TJSONObject  ;
  Vaults           : TJSONObject  ;
  NewEntry         : TJSONObject  ;
  V                : TJSONValue   ;
  PathV            : TJSONValue   ;
  AlreadyRegistered: Boolean      ;
  i                : Integer      ;
  Stream           : TStringStream;
begin
  AbsPath:= TPath.GetFullPath(AVaultPath);
  BaseName:= ExtractFileName(ExcludeTrailingPathDelimiter(AbsPath));

  // (1) Mark the folder as an Obsidian vault by creating an empty
  //     .obsidian subdirectory if Obsidian hasn't done so yet.
  ObsDir:= TPath.Combine(AbsPath, '.obsidian');
  if not DirectoryExists(ObsDir) then ForceDirectories(ObsDir);

  // (2) Add to Obsidian's vault registry.
  ObsCfg:= TPath.Combine( GetEnvironmentVariable('APPDATA'), 'obsidian\obsidian.json');
  if not TFile.Exists(ObsCfg) then
  begin
    Writeln('  (Obsidian config not found at ', ObsCfg, ' - is Obsidian installed?)');
    Exit;
  end;
  Cfg:= nil;
  try
    try
      Body:= TFile.ReadAllText(ObsCfg, TEncoding.UTF8);
      Cfg:= TJSONObject.ParseJSONValue(Body) as TJSONObject;
    except
      Cfg:= nil;
    end;
    if Cfg = nil then
    begin
      Writeln('  (could not parse ', ObsCfg, ')');
      Exit;
    end;

    Vaults:= Cfg.GetValue('vaults') as TJSONObject;
    if Vaults = nil then
    begin
      Vaults:= TJSONObject.Create;
      Cfg.AddPair('vaults', Vaults);
    end;

    AlreadyRegistered:= False;
    for i:= 0 to Vaults.Count - 1 do
    begin
      V:= Vaults.Pairs[i].JsonValue;
      if V is TJSONObject then
      begin
        PathV:= TJSONObject(V).GetValue('path');
        if PathV <> nil then
        begin
          Existing:= PathV.Value;
          if SameText(Existing, AbsPath) then
          begin
            AlreadyRegistered:= True;
            Break;
          end;
        end;
      end;
    end; // for

    if not AlreadyRegistered then
    begin
      NewEntry:= TJSONObject.Create;
      NewEntry.AddPair('path', AbsPath);
      NewEntry.AddPair('ts', TJSONNumber.Create( DateTimeToUnix(Now, False) * Int64(1000)));
      Vaults.AddPair(NewVaultId, NewEntry);
      Stream:= TStringStream.Create(Cfg.ToJson, TEncoding.UTF8);
      try
        Stream.SaveToFile(ObsCfg);
      finally
        Stream.Free;
      end;
      Writeln('  Registered as Obsidian vault.');
    end
    else Writeln('  Vault already registered with Obsidian.');
  finally
    Cfg.Free;
  end; // try

  // (3) Launch. obsidian:// URI is handled by Obsidian's registered
  //     protocol handler. ShellExecute with the URI returns whatever
  //     handler is registered for it.
  Uri:= 'obsidian://open?vault=' + BaseName;
  ShellExecute(0, 'open', PChar(Uri), nil, nil, SW_SHOWNORMAL);
  Writeln('  Launched Obsidian. Vault path: ', AbsPath);
end; // procedure

function DoExportObsidian(const AArgs: TArgs): Integer;
var
  Conn       : TFDConnection ;
  Q          : TFDQuery      ;
  QSyms      : TFDQuery      ;
  QRefs      : TFDQuery      ;
  UnitId     : Int64         ;
  UnitName   : string        ;
  UnitPath   : string        ;
  OutPath    : string        ;
  SanName    : string        ;
  Sb         : TStringBuilder;
  KindCount  : Integer       ;
  Sym        : record
    Id       : Int64  ;
    Kind     : string ;
    Name     : string ;
    QName    : string ;
    ParentId : Int64  ;
    StartLine: Integer;
  end;
  UnitsByName : TDictionary<string, string> ;
  CallerLine  : string                      ;
  Visited     : TDictionary<string, Boolean>;
  WrittenCount: Integer                     ;
begin
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: export obsidian requires --db');
    Exit   (2                                     );
  end;
  if AArgs.OutputDir = '' then
  begin
    Writeln('ERROR: export obsidian requires --output-dir <dir>');
    Exit   (2                                                   );
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  if not TDirectory.Exists(AArgs.OutputDir) then TDirectory.CreateDirectory(AArgs.OutputDir);

  Conn:= TFDConnection.Create(nil);
  Conn.DriverName:= 'SQLite';
  Conn.Params.Values['Database']:= AArgs.DbPath;
  Conn.LoginPrompt:= False;
  Conn.Connected  := True;
  WrittenCount:= 0;
  try
    // First pass: build a name -> md-filename map so cross-links resolve.
    UnitsByName:= TDictionary<string, string>.Create;
    try
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= Conn;
        Q.Sql.Text:= 'SELECT u.name AS unit_name FROM symbols u WHERE u.kind = ''unit''';
        Q.Open;
        while not Q.Eof do
        begin
          UnitName:= Q.FieldByName('unit_name').AsString;
          UnitsByName.AddOrSetValue(UnitName, ObsidianSanitizeFilename(UnitName));
          Q.Next;
        end;
      finally
        Q.Free;
      end;

      // Second pass: per unit, write one markdown file.
      Q    := TFDQuery.Create(nil);
      QSyms:= TFDQuery.Create(nil);
      QRefs:= TFDQuery.Create(nil);
      try
        Q.Connection:= Conn;
        Q.Sql.Text:= 'SELECT u.id AS unit_id, u.name AS unit_name, f.path AS file_path ' + 'FROM symbols u JOIN files f ON f.id = u.file_id ' +
        'WHERE u.kind = ''unit'' ORDER BY u.name';
        Q.Open;
        QSyms.Connection:= Conn;
        QSyms.Sql.Text:= 'SELECT s.id, s.kind, s.name, s.qualified_name, s.parent_id, ' + '       s.start_line ' + 'FROM symbols s WHERE s.file_id = :fid AND s.kind <> ''unit'' ' +
        'ORDER BY s.start_line';
        QRefs.Connection:= Conn;
        QRefs.Sql.Text:= 'SELECT DISTINCT u2.name AS by_unit, COUNT(*) AS hits ' + 'FROM refs r ' + 'JOIN files f2 ON f2.id = r.file_id ' +
        'JOIN symbols u2 ON u2.kind = ''unit'' AND u2.file_id = f2.id ' + 'JOIN symbols s ON s.name = r.name_text ' + 'WHERE s.file_id = (SELECT u.file_id FROM symbols u ' +
        '                    WHERE u.kind = ''unit'' AND u.name = :u LIMIT 1) ' + '  AND u2.name <> :u ' + 'GROUP BY u2.name ORDER BY hits DESC LIMIT 20';

        while not Q.Eof do
        begin
          UnitId  := Q.FieldByName('unit_id'  ).AsLargeInt;
          UnitName:= Q.FieldByName('unit_name').AsString;
          UnitPath:= Q.FieldByName('file_path').AsString;
          SanName:= ObsidianSanitizeFilename(UnitName);
          OutPath:= TPath.Combine(AArgs.OutputDir, SanName + '.md');

          Sb:= TStringBuilder.Create;
          try
            Sb.AppendLine(Format('---'#10'unit: %s'#10'source: %s'#10'---', [UnitName, UnitPath]));
            Sb.AppendLine('');
            Sb.AppendLine(Format('# %s', [UnitName]));
            Sb.AppendLine('');
            Sb.AppendLine('Source: `' + UnitPath + '`');
            Sb.AppendLine('');

            // Symbols grouped by kind.
            QSyms.Close;
            QSyms.ParamByName('fid').AsLargeInt:= 0; // resolve via SQL - actually we need file_id, not unit_id
            // Easier: fetch file_id of the unit symbol first.
            var FileIdQ:= TFDQuery.Create(nil);
            try
              FileIdQ.Connection:= Conn;
              FileIdQ.Sql.Text:= 'SELECT file_id FROM symbols WHERE id = :id';
              FileIdQ.ParamByName('id').AsLargeInt:= UnitId;
              FileIdQ.Open;
              if FileIdQ.IsEmpty then Continue;
              QSyms.ParamByName('fid').AsLargeInt:= FileIdQ.FieldByName('file_id').AsLargeInt;
            finally
              FileIdQ.Free;
            end;
            QSyms.Open;
            Sb.AppendLine('## Symbols');
            Sb.AppendLine(''          );
            KindCount:= 0;
            while not QSyms.Eof do
            begin
              Sym.Kind     := QSyms.FieldByName('kind'          ).AsString;
              Sym.Name     := QSyms.FieldByName('name'          ).AsString;
              Sym.QName    := QSyms.FieldByName('qualified_name').AsString;
              Sym.StartLine:= QSyms.FieldByName('start_line'    ).AsInteger;
              Sb.AppendLine(Format('- **%s** `%s` - line %d', [Sym.Kind, Sym.QName, Sym.StartLine]));
              Inc(KindCount);
              QSyms.Next;
            end;
            QSyms.Close;
            Sb.AppendLine('');
            Sb.AppendLine(Format('_%d symbols_', [KindCount]));
            Sb.AppendLine('');

            // Referenced by other units.
            QRefs.Close;
            QRefs.ParamByName('u').AsString:= UnitName;
            QRefs.Open;
            if not QRefs.IsEmpty then
            begin
              Sb.AppendLine('## Referenced by');
              Sb.AppendLine(''                );
              Visited:= TDictionary<string, Boolean>.Create;
              try
                while not QRefs.Eof do
                begin
                  CallerLine:= QRefs.FieldByName('by_unit').AsString;
                  if not Visited.ContainsKey(CallerLine) then
                  begin
                    Visited.Add(CallerLine, True);
                    if UnitsByName.ContainsKey(CallerLine) then Sb.AppendLine(Format('- [[%s]] - %d hit(s)', [CallerLine, QRefs.FieldByName('hits').AsInteger]))
                    else Sb.AppendLine(Format('- %s - %d hit(s)', [CallerLine, QRefs.FieldByName('hits').AsInteger]));
                  end;
                  QRefs.Next;
                end;
              finally
                Visited.Free;
              end; // try
              Sb.AppendLine('');
            end; // if

            TFile.WriteAllText(OutPath, Sb.ToString, TEncoding.UTF8);
            Inc(WrittenCount);
          finally
            Sb.Free;
          end; // try
          Q.Next;
        end; // while
      finally
        QRefs.Free;
        QSyms.Free;
        Q.Free;
      end; // try
    finally
      UnitsByName.Free;
    end; // try
  finally
    Conn.Free;
  end; // try
  Writeln(Format('Wrote %d unit notes to %s', [WrittenCount, AArgs.OutputDir]));

  // v0.15: --open ships the user straight into Obsidian. Steps:
  //   (1) Create .obsidian/ inside the vault so Obsidian recognises it.
  //   (2) Register the vault in %APPDATA%\obsidian\obsidian.json
  //       (so the obsidian:// URI scheme can find it by basename).
  //   (3) Launch obsidian://open?vault=<basename>.
  if AArgs.Open then OpenInObsidian(AArgs.OutputDir);

  Result:= 0;
end; // begin

// --- top --------------------------------------------------------------------

function DoTop(const AArgs: TArgs): Integer;
var
  Conn : TFDConnection;
  Q    : TFDQuery     ;
  Limit: Integer      ;
  JArr : TJSONArray   ;
  JObj : TJSONObject  ;
  Rows : Integer      ;
begin
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: top requires --db');
    Exit   (2                         );
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  if AArgs.Limit > 0 then Limit:= AArgs.Limit else Limit:= 50;

  Conn:= TFDConnection.Create(nil);
  Q   := TFDQuery     .Create(nil);
  try
    Conn.DriverName:= 'SQLite';
    Conn.Params.Values['Database']:= AArgs.DbPath;
    Conn.LoginPrompt:= False;
    Conn.Connected  := True;
    Q   .Connection := Conn;
    // Default sort: fan-in count (refs whose name_text matches the symbol).
    // Limits to the symbol kinds that callers typically reach for.
    // Strategy: aggregate refs by name first (fast - there's an index on
    // refs.name_text), then pick one sample symbol per name for context.
    // This collapses "every method named Add" into a single Add row, which
    // is what users actually want from a "what's referenced most" question.
    // Until v0.6 lands index-time symbol resolution (refs.symbol_id), this
    // is the most honest aggregation.
    Q.Sql.Text:= 'WITH ref_counts AS (' + '  SELECT name_text, COUNT(*) AS fanin FROM refs ' + '  GROUP BY name_text ORDER BY fanin DESC LIMIT :lim' + ') ' +
    'SELECT rc.name_text AS name, rc.fanin, ' + '       (SELECT kind FROM symbols WHERE name = rc.name_text LIMIT 1) ' + '         AS kind, ' +
    '       (SELECT qualified_name FROM symbols WHERE name = rc.name_text ' + '        ORDER BY id LIMIT 1) AS sample_qname ' + 'FROM ref_counts rc ORDER BY rc.fanin DESC';
    Q.ParamByName('lim').AsInteger:= Limit;
    Q.Open;
    Rows:= 0;
    if AArgs.AsJson then
    begin
      JArr:= TJSONArray.Create;
      try
        while not Q.Eof do
        begin
          JObj:= TJSONObject.Create;
          JObj.AddPair('name', Q.FieldByName('name').AsString);
          JObj.AddPair('fanin', TJSONNumber.Create( Q.FieldByName('fanin').AsInteger));
          JObj.AddPair('sample_kind'          , Q.FieldByName('kind'        ).AsString);
          JObj.AddPair('sample_qualified_name', Q.FieldByName('sample_qname').AsString);
          JArr.AddElement(JObj);
          Inc(Rows);
          Q.Next;
        end;
        Writeln(JArr.Format(2));
      finally
        JArr.Free;
      end; // try
    end // if
    else
    begin
      Writeln(Format('%6s  %-22s  %-10s  %s', ['fan-in', 'name', 'kind', 'sample qualified name']));
      Writeln(StringOfChar('-', 90));
      while not Q.Eof do
      begin
        Writeln(Format(
            '%6d  %-22s  %-10s  %s', [Q.FieldByName('fanin').AsInteger, Q.FieldByName('name').AsString, Q.FieldByName('kind').AsString, Q.FieldByName('sample_qname').AsString]));
        Inc(Rows);
        Q.Next;
      end;
      Writeln(Format('%d row(s) (fan-in = how many references in the index ' + 'use this name; ambiguous if multiple symbols share it)', [Rows]));
    end;
  finally
    Q.Free;
    Conn.Free;
  end; // try
  Result:= 0;
end; // function

// --- import-log -------------------------------------------------------------

function DoImportLog(const AArgs: TArgs): Integer;
var
  Conn       : TFDConnection ;
  Q          : TFDQuery      ;
  FileQ      : TFDQuery      ;
  LogPath    : string        ;
  Lines      : TArray<string>;
  Line       : string        ;
  PatternMsb : TRegEx        ;
  M          : TMatch        ;
  Severity   : string        ;
  Code       : string        ;
  Msg        : string        ;
  RawPath    : string        ;
  LineNo     : Integer       ;
  ColNo      : Integer       ;
  FileId     : Int64         ;
  ImportedAt : Int64         ;
  Count      : Integer       ;
  MatchedFile: Integer       ;
  FirstChar  : Char          ;
begin
  if AArgs.Path = '' then
  begin
    Writeln('ERROR: import-log requires a <logfile> argument');
    Exit   (2                                                );
  end;
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: import-log requires --db');
    Exit   (2                                );
  end;
  LogPath:= AArgs.Path;
  if not TFile.Exists(LogPath) then
  begin
    Writeln('ERROR: log file not found: ', LogPath);
    Exit(2);
  end;

  // Three common formats (we strip severity tokens and derive from code prefix):
  //   1. msbuild/dcc errors:   "Foo.pas(45,10): Error E2010: Incompatible types..."
  //   2. msbuild/dcc hints:    "Foo.pas(45): Hint warning H2077: Value assigned ..."
  //   3. BDS bracketed format: "[dcc64 Error] Foo.pas(45,10): E2010 ..."
  // Trailing "[...dproj]" tag from msbuild is stripped from the message.
  PatternMsb:= TRegEx.Create(
    '^(?:\[[^\]]*\]\s*)?(.+?\.[a-zA-Z]+)\((\d+)(?:,(\d+))?\)\s*:?\s*' + '(?:(?:Fatal|Error|Warning|Hint)\s+)*' + '([EFWH]\d{4})\s*:?\s*' + '(.*?)(?:\s*\[[^\]]+\])?$',
    [roIgnoreCase]);

  Conn := TFDConnection.Create(nil);
  Q    := TFDQuery     .Create(nil);
  FileQ:= TFDQuery     .Create(nil);
  try
    Conn.DriverName:= 'SQLite';
    Conn.Params.Values['Database']:= AArgs.DbPath;
    Conn.LoginPrompt:= False;
    Conn.Connected  := True;
    Q   .Connection := Conn;
    Q.Sql.Text:= 'INSERT INTO compiler_findings(file_id, raw_path, code, severity, ' + '  line_no, col_no, message, imported_at) ' +
    'VALUES (:fid, :rp, :code, :sev, :ln, :cn, :msg, :t)';
    Q.Params.ParamByName('fid' ).DataType:= ftLargeint;
    Q.Params.ParamByName('rp'  ).DataType:= ftString;
    Q.Params.ParamByName('code').DataType:= ftString;
    Q.Params.ParamByName('sev' ).DataType:= ftString;
    Q.Params.ParamByName('ln'  ).DataType:= ftInteger;
    Q.Params.ParamByName('cn'  ).DataType:= ftInteger;
    Q.Params.ParamByName('msg' ).DataType:= ftString;
    Q.Params.ParamByName('t'   ).DataType:= ftLargeint;
    FileQ.Connection:= Conn;
    FileQ.Sql.Text:= 'SELECT id FROM files WHERE path = :p OR ' + '  path LIKE :p2 LIMIT 1';
    FileQ.Params.ParamByName('p' ).DataType:= ftString;
    FileQ.Params.ParamByName('p2').DataType:= ftString;

    ImportedAt:= DateTimeToUnix(Now, False);
    Lines:= TFile.ReadAllLines(LogPath);
    Count      := 0;
    MatchedFile:= 0;
    Conn.StartTransaction;
    try
      for Line in Lines do
      begin
        M:= PatternMsb.Match(Line);
        if not M.Success then Continue;
        RawPath:= Trim(M.Groups[1].Value);
        LineNo:= StrToIntDef(M.Groups[2].Value, 0);
        if M.Groups[3].Success then ColNo:= StrToIntDef(M.Groups[3].Value, 0)
        else ColNo:= 0;
        Code:= M.Groups[4].Value;
        // Derive severity from code prefix (F/E/W/H).
        if Code <> '' then FirstChar:= UpCase(Code[1])
        else FirstChar:= '?';
        if FirstChar      = 'F' then Severity:= 'Fatal'
        else if FirstChar = 'E' then Severity:= 'Error'
        else if FirstChar = 'W' then Severity:= 'Warning'
        else if FirstChar = 'H' then Severity:= 'Hint'
        else Severity:= 'Info';
        Msg:= Trim(M.Groups[5].Value);

        FileId:= 0;
        FileQ.Close;
        FileQ.ParamByName('p').AsString:= RawPath;
        FileQ.ParamByName('p2').AsString:= '%' + ExtractFileName(RawPath);
        FileQ.Open;
        if not FileQ.IsEmpty then
        begin
          FileId:= FileQ.FieldByName('id').AsLargeInt;
          Inc(MatchedFile);
        end;
        FileQ.Close;

        if FileId > 0 then Q.ParamByName('fid').AsLargeInt:= FileId
        else Q.ParamByName('fid').Clear;
        Q.ParamByName('rp').AsString:= RawPath;
        Q.ParamByName('code').AsString:= Code.ToUpper;
        Q.ParamByName('sev').AsString  := Severity;
        Q.ParamByName('ln' ).AsInteger := LineNo;
        Q.ParamByName('cn' ).AsInteger := ColNo;
        Q.ParamByName('msg').AsString  := Msg;
        Q.ParamByName('t'  ).AsLargeInt:= ImportedAt;
        Q.ExecSQL;
        Inc(Count);
      end; // for
      Conn.Commit;
    except
      Conn.Rollback;
      raise;
    end; // try
    Writeln(Format('Imported %d compiler findings (%d cross-referenced ' + 'with indexed files)', [Count, MatchedFile]));
  finally
    FileQ.Free;
    Q.Free;
    Conn.Free;
  end; // try
  Result:= 0;
end; // function

// --- query hints ------------------------------------------------------------

function DoQueryHints(const AArgs: TArgs): Integer;
var
  Conn : TFDConnection;
  Q    : TFDQuery     ;
  Where: string       ;
  Sql  : string       ;
  Rows : Integer      ;
begin
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: query hints requires --db');
    Exit   (2                                 );
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  Conn:= TFDConnection.Create(nil);
  Q   := TFDQuery     .Create(nil);
  try
    Conn.DriverName:= 'SQLite';
    Conn.Params.Values['Database']:= AArgs.DbPath;
    Conn.LoginPrompt:= False;
    Conn.Connected  := True;
    Where:= '';
    if AArgs.Name <> '' then Where:= 'WHERE UPPER(code) = ''' + UpperCase(AArgs.Name) + '''';
    if AArgs.Rule <> '' then // reuse --rule arg as --severity filter
    begin
      if Where = '' then Where:= 'WHERE ' else Where:= Where + ' AND ';
      Where:= Where + 'LOWER(severity) = ''' + LowerCase(AArgs.Rule) + '''';
    end;
    Sql:= 'SELECT code, severity, raw_path, line_no, col_no, message ' + 'FROM compiler_findings ' + Where + ' ORDER BY raw_path, line_no LIMIT 500';
    Q.Connection:= Conn;
    Q.Sql.Text:= Sql;
    Q.Open;
    Rows:= 0;
    while not Q.Eof do
    begin
      Writeln(Format(
          '%s:%d:%d  [%s %s] %s', [
            Q.FieldByName('raw_path').AsString, Q.FieldByName('line_no').AsInteger, Q.FieldByName('col_no').AsInteger, Q.FieldByName('severity').AsString,
            Q.FieldByName('code').AsString, Q.FieldByName('message').AsString]));
      Inc(Rows);
      Q.Next;
    end;
    Writeln(Format('%d finding(s)', [Rows]));
  finally
    Q.Free;
    Conn.Free;
  end; // try
  Result:= 0;
end; // function

function DoExport(const AArgs: TArgs): Integer;
begin
  if AArgs.SubCommand      = 'enums' then Result:= DoExportEnums(AArgs)
  else if AArgs.SubCommand = 'obsidian' then Result:= DoExportObsidian(AArgs)
  else
  begin
    Writeln('ERROR: unknown export subcommand: ', AArgs.SubCommand);
    Writeln('Available: enums, obsidian');
    Result:= 2;
  end;
end;

// --- graph ------------------------------------------------------------------

// v0.10: emit a unit-level dependency graph in Graphviz DOT or Mermaid
// syntax. One node per indexed source file; one edge per (referring-file
// -> defining-file) pair, weighted by reference count. Edge labels and
// node shape adapt to format.
function DoGraph(const AArgs: TArgs): Integer;
var
  Conn       : TFDConnection ;
  Q          : TFDQuery      ;
  Format     : string        ;
  RootSubstr : string        ;
  WhereClause: string        ;
  Sql        : string        ;
  Buf        : TStringBuilder;
  FromPath   : string        ;
  ToPath     : string        ;
  FromUnit   : string        ;
  ToUnit     : string        ;
  Weight     : Integer       ;
  Output     : string        ;

  function UnitName(const APath: string): string;
  begin
    Result:= ChangeFileExt(ExtractFileName(APath), '');
  end;

  function SanitizeId(const AName: string): string;
  var
    Ch: Char;
  begin
    Result:= '';
    for Ch in AName do
      if CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Result:= Result + Ch
    else Result:= Result + '_';
    if (Result = '') or CharInSet(Result[1], ['0'..'9']) then Result:= '_' + Result;
  end;

begin
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: graph requires --db');
    Exit   (2                           );
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  if AArgs.Format <> '' then Format:= LowerCase(AArgs.Format)
  else Format:= 'dot';
  if (Format <> 'dot') and (Format <> 'mermaid') then
  begin
    Writeln('ERROR: graph supports --format dot|mermaid (got "', Format, '")');
    Exit(2);
  end;
  RootSubstr:= AArgs.Name;

  Conn:= TFDConnection.Create(nil);
  Q   := TFDQuery     .Create(nil);
  Buf:= TStringBuilder.Create;
  try
    Conn.DriverName:= 'SQLite';
    Conn.Params.Values['Database']:= AArgs.DbPath;
    Conn.LoginPrompt:= False;
    Conn.Connected  := True;
    Q   .Connection := Conn;

    // Resolve refs by name_text -> symbols.name (the indexer leaves
    // symbol_id NULL today; that's a future cleanup but doesn't gate this
    // query). Restrict to symbol kinds worth drawing an arrow at.
    WhereClause:= 'f1.id <> f2.id AND s.kind IN (' + '''class'', ''interface'', ''record'', ''method'', ''procedure'', ' +
    '''function'', ''constructor'', ''destructor'', ''enum'', ''unit'')';
    if RootSubstr <> '' then WhereClause:= WhereClause + ' AND (f1.path LIKE ''%' + RootSubstr + '%'' OR f2.path LIKE ''%' + RootSubstr + '%'')';
    Sql:= 'SELECT f1.path AS from_path, f2.path AS to_path, ' + '       COUNT(DISTINCT r.id) AS weight ' + 'FROM refs r ' + 'JOIN files f1 ON r.file_id = f1.id ' +
    'JOIN symbols s ON LOWER(s.name) = LOWER(r.name_text) ' + 'JOIN files f2 ON s.file_id = f2.id ' + 'WHERE ' + WhereClause + ' ' + 'GROUP BY f1.id, f2.id ' +
    'ORDER BY weight DESC';
    Q.Sql.Text:= Sql;
    Q.Open;

    if Format = 'dot' then
    begin
      Buf.AppendLine('// Generated by drag-lint graph'                        );
      Buf.AppendLine('// One node per unit; one edge per A-references-B pair.');
      Buf.AppendLine('digraph DragLintDeps {'                                 );
      Buf.AppendLine('  rankdir=LR;'                                          );
      Buf.AppendLine('  node [shape=box, style=filled, fillcolor="#eef"];'    );
      Buf.AppendLine('  edge [color="#888"];'                                 );
    end
    else // mermaid
    begin
      Buf.AppendLine('%% Generated by drag-lint graph');
      Buf.AppendLine('graph LR'                       );
    end;

    while not Q.Eof do
    begin
      FromPath:= Q.FieldByName('from_path').AsString;
      ToPath  := Q.FieldByName('to_path'  ).AsString;
      Weight  := Q.FieldByName('weight'   ).AsInteger;
      FromUnit:= UnitName(FromPath);
      ToUnit  := UnitName(ToPath  );

      if Format = 'dot' then Buf.AppendLine(System.SysUtils.Format( '  "%s" -> "%s" [label="%d", weight=%d];', [FromUnit, ToUnit, Weight, Weight]))
      else Buf.AppendLine(System.SysUtils.Format('  %s --|%d|--> %s', [SanitizeId(FromUnit), Weight, SanitizeId(ToUnit)]));

      Q.Next;
    end;

    if Format = 'dot' then Buf.AppendLine('}');

    Output:= Buf.ToString;
    if AArgs.Output <> '' then
    begin
      TFile.WriteAllText(AArgs.Output, Output);
      Writeln('Wrote ', AArgs.Output);
    end
    else Writeln(Output);
  finally
    Buf.Free;
    Q.Free;
    Conn.Free;
  end; // try
  Result:= 0;
end; // begin

// --- diff -------------------------------------------------------------------

// v0.13: diff two indexes by qualified_name. Pass two --db args:
//   drag-lint diff --db old.sqlite --db new.sqlite
// Reports added, removed, and signature-changed symbols. Useful for
// reviewing the API impact of a refactor commit.
function DoDiff(const AArgs: TArgs): Integer;
var
  DbA    : string                     ;
  DbB    : string                     ;
  ConnA  : TFDConnection              ;
  ConnB  : TFDConnection              ;
  QA     : TFDQuery                   ;
  QB     : TFDQuery                   ;
  SetA   : TDictionary<string, string>; // qname -> "kind|signature"
  SetB   : TDictionary<string, string>;
  Pair   : TPair<string, string>      ;
  Added  : Integer                    ;
  Removed: Integer                    ;
  Changed: Integer                    ;
  JArr   : TJSONArray                 ;
  JObj   : TJSONObject                ;
  Tag    : string                     ;
begin
  if Length(AArgs.DbPaths) < 2 then
  begin
    Writeln('ERROR: diff requires two --db arguments ' + '(--db <old.sqlite> --db <new.sqlite>)');
    Exit(2);
  end;
  DbA:= AArgs.DbPaths[0];
  DbB:= AArgs.DbPaths[1];
  if not TFile.Exists(DbA) then
  begin
    Writeln('ERROR: --db ', DbA, ' not found');
    Exit(2);
  end;
  if not TFile.Exists(DbB) then
  begin
    Writeln('ERROR: --db ', DbB, ' not found');
    Exit(2);
  end;

  ConnA:= TFDConnection.Create(nil);
  ConnB:= TFDConnection.Create(nil);
  QA   := TFDQuery     .Create(nil);
  QB   := TFDQuery     .Create(nil);
  SetA:= TDictionary<string, string>.Create;
  SetB:= TDictionary<string, string>.Create;
  try
    ConnA.DriverName:= 'SQLite';
    ConnA.Params.Values['Database']:= DbA;
    ConnA.LoginPrompt:= False;
    ConnA.Connected  := True;
    ConnB.DriverName := 'SQLite';
    ConnB.Params.Values['Database']:= DbB;
    ConnB.LoginPrompt:= False;
    ConnB.Connected  := True;
    QA   .Connection := ConnA;
    QB   .Connection := ConnB;
    QA.Sql.Text:= 'SELECT qualified_name, kind, COALESCE(signature, '''') AS sig ' + 'FROM symbols WHERE qualified_name <> '''' ';
    QB.Sql.Text:= QA.Sql.Text;
    QA.Open;
    while not QA.Eof do
    begin
      SetA.AddOrSetValue( QA.FieldByName('qualified_name').AsString, QA.FieldByName('kind').AsString + '|' + QA.FieldByName('sig').AsString);
      QA.Next;
    end;
    QB.Open;
    while not QB.Eof do
    begin
      SetB.AddOrSetValue( QB.FieldByName('qualified_name').AsString, QB.FieldByName('kind').AsString + '|' + QB.FieldByName('sig').AsString);
      QB.Next;
    end;

    Added  := 0;
    Removed:= 0;
    Changed:= 0;

    if AArgs.AsJson then
    begin
      JArr:= TJSONArray.Create;
      try
        for Pair in SetB do
          if not SetA.ContainsKey(Pair.Key) then
          begin
            JObj:= TJSONObject.Create;
            JObj.AddPair('change', 'added');
            JObj.AddPair('qualified_name', Pair.Key);
            JObj.AddPair('kind', Pair.Value.Split(['|'])[0]);
            JArr.AddElement(JObj);
            Inc(Added);
          end
        else if SetA[Pair.Key] <> Pair.Value then
        begin
          JObj:= TJSONObject.Create;
          JObj.AddPair('change', 'changed');
          JObj.AddPair('qualified_name', Pair.Key);
          JObj.AddPair('from', SetA[Pair.Key]);
          JObj.AddPair('to', Pair.Value);
          JArr.AddElement(JObj);
          Inc(Changed);
        end;
        for Pair in SetA do
          if not SetB.ContainsKey(Pair.Key) then
          begin
            JObj:= TJSONObject.Create;
            JObj.AddPair('change', 'removed');
            JObj.AddPair('qualified_name', Pair.Key);
            JObj.AddPair('kind', Pair.Value.Split(['|'])[0]);
            JArr.AddElement(JObj);
            Inc(Removed);
          end;
        Writeln(JArr.Format(2));
      finally
        JArr.Free;
      end; // try
    end // if
    else
    begin
      for Pair in SetB do
        if not SetA.ContainsKey(Pair.Key) then
        begin
          Tag:= Pair.Value.Split(['|'])[0];
          Writeln('+ ', Pair.Key, '  [', Tag, ']');
          Inc(Added);
        end
      else if SetA[Pair.Key] <> Pair.Value then
      begin
        Writeln('~ ', Pair.Key);
        Writeln('    from: ', SetA[Pair.Key]);
        Writeln('    to:   ', Pair.Value);
        Inc(Changed);
      end;
      for Pair in SetA do
        if not SetB.ContainsKey(Pair.Key) then
        begin
          Tag:= Pair.Value.Split(['|'])[0];
          Writeln('- ', Pair.Key, '  [', Tag, ']');
          Inc(Removed);
        end;
      Writeln(Format('Summary: %d added, %d removed, %d changed', [Added, Removed, Changed]));
    end; // else

    Result:= 0;
  finally
    SetA.Free;
    SetB.Free;
    QA.Free;
    QB.Free;
    ConnA.Free;
    ConnB.Free;
  end; // try
end; // function

// --- todos ------------------------------------------------------------------

// v0.12: scan .pas/.dpr/.dpk files for TODO/FIXME/HACK/XXX/REVIEW/NOTE
// comments and report them with file:line:col + optional author tag.
// Standalone - no index needed. Intended workflow: run before commits,
// or pipe into `--json` for CI dashboards.
function DoTodos(const AArgs: TArgs): Integer;
type
  TTodo = record
    FilePath: string ;
    LineNo  : Integer;
    ColNo   : Integer;
    Keyword : string ;
    Author  : string ;
    Body    : string ;
  end;
var
  Path    : string        ;
  Files   : TArray<string>;
  Patterns: TArray<string>;
  Pattern : string        ;
  FileName: string        ;
  Lines   : TArray<string>;
  Line    : string        ;
  Tail    : string        ;
  RE      : TRegEx        ;
  M       : TMatch        ;
  Todos   : TList<TTodo>  ;
  T       : TTodo         ;
  i       : Integer       ;
  JArr    : TJSONArray    ;
  JObj    : TJSONObject   ;
begin
  if AArgs.Path = '' then Path:= GetCurrentDir
  else Path:= AArgs.Path;
  if not (TDirectory.Exists(Path) or TFile.Exists(Path)) then
  begin
    Writeln('ERROR: path does not exist: ', Path);
    Exit(2);
  end;
  // Keyword set is intentionally narrow and word-boundaried so noise like
  // "fixmessage" doesn't false-trip. Author tag accepts @alex or "Alex:"
  // forms, matching common Delphi codebase conventions.
  // Author tag accepts @alex or "Alex:" forms (starts with a letter, to
  // avoid swallowing Delphi's built-in priority digits like `TODO 1`).
  RE:= TRegEx.Create( '//\s*(TODO|FIXME|HACK|XXX|REVIEW|NOTE)\b' + '(?:[@\s]([A-Za-z]\w*))?[\s:]*(.*)$', [roIgnoreCase]);

  Todos:= TList<TTodo>.Create;
  try
    if TFile.Exists(Path) then Files:= [Path]
    else
    begin
      Patterns:= ['*.pas', '*.dpr', '*.dpk', '*.inc'];
      Files:= nil;
      for Pattern in Patterns do Files:= Files + TDirectory.GetFiles(Path, Pattern, TSearchOption.soAllDirectories);
    end;
    for FileName in Files do
    begin
      try
        Lines:= TFile.ReadAllLines(FileName);
      except
        Continue;
      end;
      for i:= 0 to High(Lines) do
      begin
        Line:= Lines[i];
        M:= RE.Match(Line);
        if not M.Success then Continue;
        // Skip when `//` lives inside a quoted string by checking the
        // count of `'` chars before the `//` position - odd count means
        // we're inside a string literal.
        Tail:= Copy(Line, 1, M.Index - 1);
        if (Length(Tail) - Length(StringReplace( Tail, '''', '', [rfReplaceAll]))) mod 2 = 1 then Continue;
        T:= Default(TTodo);
        T.FilePath:= FileName;
        T.LineNo:= i + 1;
        T.ColNo:= M.Index;
        T.Keyword:= UpperCase(M.Groups[1].Value);
        if M.Groups[2].Success then T.Author:= M.Groups[2].Value
        else T.Author:= '';
        T.Body:= Trim(M.Groups[3].Value);
        Todos.Add(T);
      end; // for
    end; // for

    if AArgs.AsJson then
    begin
      JArr:= TJSONArray.Create;
      try
        for T in Todos do
        begin
          JObj:= TJSONObject.Create;
          JObj.AddPair('file_path', T.FilePath);
          JObj.AddPair('line', TJSONNumber.Create(T.LineNo));
          JObj.AddPair('col' , TJSONNumber.Create(T.ColNo ));
          JObj.AddPair('keyword', T.Keyword);
          JObj.AddPair('author' , T.Author );
          JObj.AddPair('body'   , T.Body   );
          JArr.AddElement(JObj);
        end;
        Writeln(JArr.Format(2));
      finally
        JArr.Free;
      end; // try
    end // if
    else
    begin
      for T in Todos do
      begin
        if T.Author <> '' then Writeln(Format('%s:%d:%d  [%s @%s] %s', [T.FilePath, T.LineNo, T.ColNo, T.Keyword, T.Author, T.Body]))
        else Writeln(Format('%s:%d:%d  [%s] %s', [T.FilePath, T.LineNo, T.ColNo, T.Keyword, T.Body]));
      end;
      Writeln(Format('%d todo(s)', [Todos.Count]));
    end;
  finally
    Todos.Free;
  end; // try
  Result:= 0;
end; // begin

// --- hover ------------------------------------------------------------------

// v0.16: drag-lint hover --qname <Foo.Bar> [--db <path>] [--format md|plain|json]
// Looks up the first symbol matching the qualified name, retrieves its doc
// comment from symbol_docs, and renders it in the requested format.

// RenderHover* functions are now in DRagLint.Hover.Renderer (shared with LSP).
// These local wrappers forward to the shared unit so existing callers
// (DoHover below) continue to compile without change.

function RenderHoverPlain(const ASym: TSymbol; const ADoc: TParsedDoc): string;
begin
  Result:= DRagLint.Hover.Renderer.RenderHoverPlain(ASym, ADoc);
end;

function RenderHoverMarkdown(const ASym: TSymbol; const ADoc: TParsedDoc): string;
begin
  Result:= DRagLint.Hover.Renderer.RenderHoverMarkdown(ASym, ADoc);
end;

function RenderHoverJson(const ASym: TSymbol; const ADoc: TParsedDoc): string;
begin
  Result:= DRagLint.Hover.Renderer.RenderHoverJson(ASym, ADoc);
end;

function DoHover(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore   ;
  Syms : TArray<TSymbol>;
  Doc  : TParsedDoc     ;
  Fmt  : string         ;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint hover --qname <Foo.Bar> [--db <path>] ' + '[--format md|plain|json]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit   (2                                    );
  end;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Syms:= Store.FindSymbolsByQualifiedName(AArgs.QName);
  if Length(Syms) = 0 then
  begin
    Writeln(System.SysUtils.Format('No symbol matched qname: %s', [AArgs.QName]));
    Exit(1);
  end;

  Doc:= Store.GetSymbolDoc(Syms[0].Id);
  { v0.43: no doc comment is no longer fatal -- the renderer still shows the
    qualified name + an IDE-style Parameters block parsed from the signature,
    which is exactly what the LSP hover does. }

  Fmt:= LowerCase(AArgs.Format);
  if Fmt = '' then Fmt:= 'plain';

  if Fmt      = 'json' then Write(RenderHoverJson(Syms[0], Doc))
  else if Fmt = 'md' then Write(RenderHoverMarkdown(Syms[0], Doc))
  else Write(RenderHoverPlain(Syms[0], Doc));
  Result:= 0;
end; // function

// v0.17: drag-lint impact --qname <X> [--depth N] [--db <path>] [--format text|json]
// Walks transitive callers of the last segment of <X> up to depth N.
// Exit 0 if callers found, 1 if none.
// v8: drag-lint wiring --qname <Interface> [--db <path>] [--format text|json]
//     drag-lint wiring --coverage      [--db <path>] [--format text|json]
// Spring4D DI wiring edges: implementations (+lifetime) and resolve-sites of an
// interface; --coverage lists DI registrations not resolved into I->T edges.
function DoWiring(const AArgs: TArgs): Integer;
var
  Store   : ISymbolStore         ;
  Impls   : TArray<TDiBindingRow>;
  Sites   : TArray<TReference>   ;
  Unres   : TArray<TReference>   ;
  Handlers: TArray<TReference>   ;
  B       : TDiBindingRow        ;
  R       : TReference           ;
  JRoot   : TJSONObject          ;
  JO      : TJSONObject          ;
  JSites  : TJSONArray           ;
  Dbs     : TArray<string>       ;
  DbToUse : string               ;
  D       : string               ;
begin
  { v8: resolve the DB like query/hover -- explicit --db if given, else
    manifest-driven. Fixes projects whose index is NOT named <Project>.sqlite
    beside the .dproj (e.g. ORM3 -> C:\Projects\DB\ORM3\drag-lint.sqlite). Use the
    first existing resolved DB (the project/primary index). }
  Dbs:= ResolveConsumerDbs(AArgs);
  DbToUse:= '';
  for D in Dbs do
    if TFile.Exists(D) then begin DbToUse:= D; Break; end;
  if DbToUse = '' then
  begin
    Writeln('ERROR: no drag-lint index found (tried ', Length(Dbs), ' resolved path(s)). Pass --db <file.sqlite> or build the index first.');
    Exit(2);
  end;
  Store:= TSQLiteSymbolStore.Create(DbToUse);
  Store.Migrate;

  if AArgs.WiringCoverage then
  begin
    Unres:= Store.FindDiUnresolved;
    if LowerCase(AArgs.Format) = 'json' then
    begin
      JRoot:= TJSONObject.Create;
      try
        // Adopt JSites into JRoot, and each JO into JSites, before GetFilePath
        // (a DB query that can raise) so a mid-loop exception frees the whole
        // tree via JRoot (review fix).
        JSites:= TJSONArray.Create;
        JRoot.AddPair('unresolved', JSites);
        for R in Unres do
        begin
          JO:= TJSONObject.Create;
          JSites.AddElement(JO);
          JO.AddPair('method', R.NameText);
          JO.AddPair('file', Store      .GetFilePath(R.FileId   ));
          JO.AddPair('line', TJSONNumber.Create     (R.StartLine));
        end;
        Writeln(JRoot.Format(2));
      finally
        JRoot.Free;
      end; // try
    end // if
    else
    begin
      Writeln(Format('DI registrations not resolved into I->T edges (%d):', [Length(Unres)]));
      for R in Unres do Writeln(Format('  %s  %s:%d', [R.NameText, Store.GetFilePath(R.FileId), R.StartLine]));
      if Length(Unres) = 0 then Writeln('  (none)');
    end;
    Exit(0);
  end; // if

  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint wiring --qname <Interface> [--db <path>] ' + '[--format text|json]');
    Writeln('       drag-lint wiring --coverage [--db <path>] [--format text|json]');
    Exit   (2                                                                      );
  end;

  if LowerCase(AArgs.Format) = 'json' then
  begin
    // Shared builder so CLI json and MCP get_wiring return identical data.
    JRoot:= BuildWiringJson(AArgs.QName, Store);
    try
      Writeln(JRoot.Format(2));
    finally
      JRoot.Free;
    end;
  end
  else
  begin
    Impls   := Store.FindImplementationsOf   (AArgs.QName);
    Sites   := Store.FindDiResolveSites      (AArgs.QName);
    Handlers:= Store.FindEventHandlersForForm(AArgs.QName);
    Writeln(AArgs.QName);
    if Length(Impls) > 0 then
      for B in Impls do Writeln(Format('  impl: %s [%s]  %s:%d', [B.ImplName, B.Lifetime, Store.GetFilePath(B.FileId), B.StartLine]));
    if Length(Sites) > 0 then
    begin
      Writeln(Format('  resolved at %d site(s):', [Length(Sites)]));
      for R in Sites do Writeln(Format('    %s:%d', [Store.GetFilePath(R.FileId), R.StartLine]));
    end;
    if Length(Handlers) > 0 then
    begin
      Writeln('  event handlers:');
      for R in Handlers do Writeln(Format('    %s <- %s:%d', [R.NameText, Store.GetFilePath(R.FileId), R.StartLine]));
    end;
    if (Length(Impls) = 0) and (Length(Sites) = 0) and (Length(Handlers) = 0) then Writeln('  (no DI or DFM wiring found)');
  end; // else
  Result:= 0;
end; // function

function DoImpact(const AArgs: TArgs): Integer;
var
  Store     : ISymbolStore        ;
  Levels    : TArray<TImpactLevel>;
  L         : TImpactLevel        ;
  Prev      : Integer             ;
  Depth     : Integer             ;
  TargetName: string              ;
  JRoot     : TJSONObject         ;
  JLevel    : TJSONObject         ;
  JArr      : TJSONArray          ;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint impact --qname <Qualified.Name> ' + '[--depth N] [--db <path>] [--format text|json]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit   (2                                    );
  end;
  Depth:= AArgs.Depth;
  if Depth <= 0 then
  begin
    Writeln(AArgs.QName);
    Writeln('  (depth 0 returns nothing)');
    Exit   (1                            );
  end;
  // Use the bare name (last segment) as the target for the CTE ref lookup,
  // since refs store the bare identifier name, not the qualified name.
  TargetName:= LastSegment(AArgs.QName, '.');
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Levels:= Store.FindTransitiveCallers(TargetName, Depth);
  if LowerCase(AArgs.Format) = 'json' then
  begin
    JRoot:= TJSONObject.Create;
    JArr := TJSONArray .Create;
    try
      JRoot.AddPair('qname', AArgs.QName);
      for L in Levels do
      begin
        JLevel:= TJSONObject.Create;
        JLevel.AddPair('depth'  , TJSONNumber.Create(L.Depth      ));
        JLevel.AddPair('callers', TJSONNumber.Create(L.CallerCount));
        JLevel.AddPair('units'  , TJSONNumber.Create(L.UnitCount  ));
        JArr.AddElement(JLevel);
      end;
      JRoot.AddPair('levels', JArr);
      Writeln(JRoot.Format(2));
    finally
      JRoot.Free;
    end;
  end // if
  else
  begin
    Writeln(AArgs.QName);
    Prev:= 0;
    for L in Levels do
    begin
      if Prev > 0 then Writeln(Format('  Depth %d: %3d callers in %d units (+%d)', [L.Depth, L.CallerCount, L.UnitCount, L.CallerCount - Prev]))
      else Writeln(Format('  Depth %d: %3d callers in %d units', [L.Depth, L.CallerCount, L.UnitCount]));
      Prev:= L.CallerCount;
    end;
    if Length(Levels) = 0 then
    begin
      Writeln('  (no callers)');
      Exit   (1               );
    end;
  end; // else
  Result:= 0;
end; // function

// v0.17: drag-lint surface --qname <Foo.TBar> [--db <path>]
//   [--include-impl] [--all-visibility] [--format text|json]
// Reads start_line..end_line of the class symbol from the source file and
// prints each line. For a well-formed Delphi unit the class symbol spans only
// the interface-section declaration, so no implementation bodies leak through.
// Exit 2 on usage error, 1 if symbol not found or wrong kind, 0 on success.
function DoSurface(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore        ;
  Lines: TArray<TSurfaceLine>;
  L    : TSurfaceLine        ;
  Syms : TArray<TSymbol>     ;
  JArr : TJSONArray          ;
  JObj : TJSONObject         ;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint surface --qname <Foo.TBar> ' + '[--db <path>] [--include-impl] [--all-visibility] ' + '[--format text|json]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit   (2                                    );
  end;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  // Validate that the symbol exists and is a class/record/interface.
  Syms:= Store.FindSymbolsByQualifiedName(AArgs.QName);
  if Length(Syms) = 0 then
  begin
    Writeln(System.SysUtils.Format('No symbol matched qname: %s', [AArgs.QName]));
    Exit(1);
  end;
  if not (Syms[0].Kind in [skClass, skRecord, skInterface]) then
  begin
    Writeln(System.SysUtils.Format( 'Symbol %s has kind "%s"; surface requires a class, record, or interface.', [Syms[0].QualifiedName, Syms[0].Kind.ToText]));
    Exit(2);
  end;

  Lines:= Store.GetClassSurface(AArgs.QName, AArgs.IncludeImpl, AArgs.AllVisibility);
  if Length(Lines) = 0 then
  begin
    Writeln('(no surface lines returned)');
    Exit   (1                            );
  end;

  if LowerCase(AArgs.Format) = 'json' then
  begin
    JArr:= TJSONArray.Create;
    try
      for L in Lines do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('kind', L.Kind);
        JObj.AddPair('text', L.Text);
        JObj.AddPair('line', TJSONNumber.Create(L.StartLine));
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end;
  end // if
  else
  begin
    for L in Lines do Writeln(L.Text);
  end;
  Result:= 0;
end; // function

// v0.42: drag-lint outline --file <path.pas> [--db <path>] [--format text|json]
// Lists every symbol declared in one file, ordered by position. Backs the
// IDE Structure form (which previously mis-used the class-scoped 'surface').
// JSON shape: [{"kind","name","qname","line","signature","modifiers"}, ...]
// Exit 2 on usage error / db missing, 0 otherwise (empty list is not an error
// -- a file with no indexed symbols legitimately returns []).
function DoOutline(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore   ;
  Syms : TArray<TSymbol>;
  S    : TSymbol        ;
  JArr : TJSONArray     ;
  JObj : TJSONObject    ;
begin
  if AArgs.InFile = '' then
  begin
    Writeln('Usage: drag-lint outline --file <path.pas> ' + '[--db <path>] [--format text|json]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit   (2                                    );
  end;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Syms:= Store.FindSymbolsByFile(AArgs.InFile);

  if LowerCase(AArgs.Format) = 'json' then
  begin
    JArr:= TJSONArray.Create;
    try
      for S in Syms do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('kind', S.Kind.ToText);
        JObj.AddPair('name' , S.Name         );
        JObj.AddPair('qname', S.QualifiedName);
        JObj.AddPair('line', TJSONNumber.Create(S.StartLine));
        JObj.AddPair('signature', S.Signature);
        JObj.AddPair('modifiers', S.Modifiers);
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end; // try
  end // if
  else
  begin
    for S in Syms do Writeln(System.SysUtils.Format('%-10s %-40s %d', [S.Kind.ToText, S.QualifiedName, S.StartLine]));
  end;
  Result:= 0;
end; // function

// v0.42: drag-lint usages --name <X> [--width narrow|wide|very-wide]
//        [--db ...] [--depth N] [--format text|json]
// Find every place a symbol is used -- not just calls. After a DEEP index,
// 'refs' includes read/write/attribute usages, so this finds variable and
// component usages (e.g. dxDBGrid1.DataSource := X). Width:
//   narrow    - the declaration(s) + every reference to exactly <X>.
//   wide      - narrow + transitive callers to depth 2 (blast radius).
//   very-wide - narrow + transitive callers to --depth (default 4).
// Output is grouped by category. Multi-DB via repeated --db.
function DoUsages(const AArgs: TArgs): Integer;
var
  PathsToScan: TArray<string>;
  DbPath     : string        ;
  Width      : string        ;
  Store      : ISymbolStore  ;
  Depth      : Integer       ;
  JRoot      : TJSONObject   ;
  JDecls     : TJSONArray    ;
  JReads     : TJSONArray    ;
  JWrites    : TJSONArray    ;
  JCalls     : TJSONArray    ;
  JTypes     : TJSONArray    ;
  JAttrs     : TJSONArray    ;
  JEvents    : TJSONArray    ;
  JImpact    : TJSONArray    ;

  procedure AddRefRow(AArr: TJSONArray; const AFile: string; ALine, ACol: Integer);
  var
    O: TJSONObject;
  begin
    O:= TJSONObject.Create;
    O.AddPair('file', AFile);
    O.AddPair('line', TJSONNumber.Create(ALine));
    O.AddPair('col' , TJSONNumber.Create(ACol ));
    AArr.AddElement(O);
  end;

  function GroupFor(const AKind: string): TJSONArray;
  begin
    if AKind      = 'read' then Result:= JReads
    else if AKind = 'write'         then Result:= JWrites
    else if AKind = 'type_use'      then Result:= JTypes
    else if AKind = 'attribute'     then Result:= JAttrs
    else if AKind = 'event-binding' then Result:= JEvents
    else Result:= JCalls; { call + anything else }
  end;

var
  S    : TSymbol     ;
  R    : TReference  ;
  L    : TImpactLevel;
  DeclO: TJSONObject ;
begin
  if AArgs.Name = '' then
  begin
    Writeln('Usage: drag-lint usages --name <X> ' + '[--width narrow|wide|very-wide] [--db <path>] [--depth N] [--format json]');
    Exit(2);
  end;
  Width:= LowerCase(AArgs.Width);
  if Width = '' then Width:= 'narrow';

  if Width = 'very-wide' then Depth:= AArgs.Depth
  else Depth:= 2;
  if Depth <= 0 then Depth:= 4;

  PathsToScan:= AArgs.DbPaths;
  if Length(PathsToScan) = 0 then PathsToScan:= [AArgs.DbPath];

  JRoot:= TJSONObject.Create;
  JDecls := TJSONArray.Create; JReads := TJSONArray.Create;
  JWrites:= TJSONArray.Create; JCalls := TJSONArray.Create;
  JTypes := TJSONArray.Create; JAttrs := TJSONArray.Create;
  JEvents:= TJSONArray.Create; JImpact:= TJSONArray.Create;
  try
    for DbPath in PathsToScan do
    begin
      if not TFile.Exists(DbPath) then Continue;
      Store:= TSQLiteSymbolStore.Create(DbPath);
      Store.Migrate;

      for S in Store.FindSymbolsByExactName(AArgs.Name) do
      begin
        DeclO:= TJSONObject.Create;
        DeclO.AddPair('kind', S.Kind.ToText);
        DeclO.AddPair('qname', S.QualifiedName);
        DeclO.AddPair('file', Store      .GetFilePath(S.FileId   ));
        DeclO.AddPair('line', TJSONNumber.Create     (S.StartLine));
        DeclO.AddPair('signature', S.Signature);
        JDecls.AddElement(DeclO);
      end;

      for R in Store.FindCallersByName(AArgs.Name) do AddRefRow(GroupFor(R.Kind), Store.GetFilePath(R.FileId), R.StartLine, R.StartCol);

      if (Width = 'wide') or (Width = 'very-wide') then
        for L in Store.FindTransitiveCallers(AArgs.Name, Depth) do
        begin
          { TImpactLevel is an aggregate per transitive depth: how many distinct
            callers / units reference the symbol at that level. }
          var IO: TJSONObject:= TJSONObject.Create;
          IO.AddPair('depth'  , TJSONNumber.Create(L.Depth      ));
          IO.AddPair('callers', TJSONNumber.Create(L.CallerCount));
          IO.AddPair('units'  , TJSONNumber.Create(L.UnitCount  ));
          JImpact.AddElement(IO);
        end;

      Store:= nil;
    end; // for

    JRoot.AddPair('name', AArgs.Name);
    JRoot.AddPair('width'       , Width  );
    JRoot.AddPair('declarations', JDecls );
    JRoot.AddPair('reads'       , JReads );
    JRoot.AddPair('writes'      , JWrites);
    JRoot.AddPair('calls'       , JCalls );
    JRoot.AddPair('types'       , JTypes );
    JRoot.AddPair('attributes'  , JAttrs );
    JRoot.AddPair('events'      , JEvents);
    JRoot.AddPair('impact'      , JImpact);

    if LowerCase(AArgs.Format) = 'json' then Writeln(JRoot.Format(2))
    else
    begin
      Writeln(Format('usages of "%s" (width=%s)', [AArgs.Name, Width]));
      Writeln(Format('  declarations: %d', [JDecls.Count]));
      Writeln(Format(
          '  reads: %d  writes: %d  calls: %d  types: %d  attributes: %d  events: %d', [JReads.Count, JWrites.Count, JCalls.Count, JTypes.Count, JAttrs.Count, JEvents.Count]));
      if JImpact.Count > 0 then Writeln(Format('  impact (transitive): %d', [JImpact.Count]));
    end;
    Result:= 0;
  finally
    JRoot.Free; { owns the arrays once AddPair'd; arrays added are freed with root }
  end; // try
end; // begin

// v0.17: drag-lint slice --qname <Foo.TBar> [--db <path>] [--format text|json]
// Returns symbol-relevant chunks of the unit:
//   1. unit-header  ? lines 1 through the "interface" keyword line
//   2. class-decl   ? class symbol's start_line..end_line
//   3. impl-method  ? implementation body for each method child
//   4. unit-trailer ? the "end." line
// Text format: chunks separated by "--- <kind> ---" headers.
// JSON format: {"qname":..., "chunks":[{"kind":..., "start_line":...,
//               "end_line":..., "text":...}]}
// Exit 2 on usage error, 1 if symbol not found, 0 on success.
function DoSlice(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore       ;
  Slice: TArray<TSliceChunk>;
  C    : TSliceChunk        ;
  JRoot: TJSONObject        ;
  JArr : TJSONArray         ;
  JObj : TJSONObject        ;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint slice --qname <Foo.TBar> ' + '[--db <path>] [--format text|json]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit   (2                                    );
  end;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Slice:= Store.GetSymbolSlice(AArgs.QName);

  if Length(Slice) = 0 then
  begin
    Writeln(System.SysUtils.Format( 'No slice returned for qname: %s', [AArgs.QName]));
    Exit(1);
  end;

  if LowerCase(AArgs.Format) = 'json' then
  begin
    JRoot:= TJSONObject.Create;
    JArr := TJSONArray .Create;
    try
      JRoot.AddPair('qname', AArgs.QName);
      for C in Slice do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('kind', C.Kind);
        JObj.AddPair('start_line', TJSONNumber.Create(C.StartLine));
        JObj.AddPair('end_line'  , TJSONNumber.Create(C.EndLine  ));
        JObj.AddPair('text', C.Text);
        JArr.AddElement(JObj);
      end;
      JRoot.AddPair('chunks', JArr);
      Writeln(JRoot.Format(2));
    finally
      JRoot.Free;
    end; // try
  end // if
  else
  begin
    for C in Slice do
    begin
      Writeln('--- ', C.Kind, ' ---');
      Writeln(C.Text);
    end;
  end;
  Result:= 0;
end; // function

{ Drops findings whose source line carries a '// drag-lint:ignore' directive.
  Forms: '// drag-lint:ignore' (suppress every rule on that line) or
  '// drag-lint:ignore <rule-id> [<rule-id> ...]' (suppress only those rule ids).
  The marker must be inside a // line comment. File lines are cached per path. }
function ApplyLineSuppressions(const AFindings: TArray<TLintFinding>): TArray<TLintFinding>;
const
  MARK = 'drag-lint:ignore';
var
  LineCache : TDictionary<string, TArray<string>>;
  Lines     : TArray<string>     ;
  Kept      : TList<TLintFinding>;
  F         : TLintFinding       ;
  LineTxt   : string             ;
  Rest      : string             ;
  Tok       : string             ;
  Toks      : TArray<string>     ;
  CPos      : Integer            ;
  MPos      : Integer            ;
  Suppressed: Boolean            ;
begin
  if Length(AFindings) = 0 then Exit(AFindings);
  LineCache:= TDictionary<string, TArray<string>>.Create;
  Kept     := TList<TLintFinding>.Create;
  try
    for F in AFindings do
    begin
      if not LineCache.TryGetValue(F.FilePath, Lines) then
      begin
        if TFile.Exists(F.FilePath) then Lines:= TFile.ReadAllLines(F.FilePath) else SetLength(Lines, 0);
        LineCache.Add(F.FilePath, Lines);
      end;
      Suppressed:= False;
      if (F.StartLine >= 1) and (F.StartLine <= Length(Lines)) then
      begin
        LineTxt:= Lines[F.StartLine - 1];
        CPos:= Pos('//', LineTxt);
        MPos:= Pos(MARK, LowerCase(LineTxt));
        if (CPos > 0) and (MPos > CPos) then
        begin
          Rest:= Trim(Copy(LineTxt, MPos + Length(MARK), MaxInt));
          if Rest = '' then Suppressed:= True
          else
          begin
            Toks:= Rest.Split([' ', ',', #9]);
            for Tok in Toks do
              if SameText(Trim(Tok), F.RuleId) then
              begin
                Suppressed:= True;
                Break;
              end;
          end;
        end;
      end;
      if not Suppressed then Kept.Add(F);
    end;
    Result:= Kept.ToArray;
  finally
    Kept.Free;
    LineCache.Free;
  end;
end; // function

function DoLint(const AArgs: TArgs): Integer;
var
  Linter      : DRagLint.Lint.Linter.TLinter;
  Findings    : TArray<TLintFinding>        ;
  ProjFindings: TArray<TLintFinding>        ;
  F           : TLintFinding                ;
  JArr        : TJSONArray                  ;
  JObj        : TJSONObject                 ;
begin
  if (AArgs.Path = '') and (AArgs.ProjectPath = '') then
  begin
    Writeln('ERROR: lint requires a <path> or --project <file.dproj>');
    Exit   (2                                                        );
  end;
  if (AArgs.Rule <> '') and (AArgs.Rule <> 'field-by-name-in-loop') and (AArgs.Rule <> 'unit-not-in-dpr') and (AArgs.Rule <> 'inline-comment-in-multiline-args') and
  (AArgs.Rule <> 'unused-local') and (AArgs.Rule <> 'syntax-error') and (AArgs.Rule <> 'unbalanced-begin-end') and (AArgs.Rule <> 'raise-in-finally') and
  (AArgs.Rule <> 'code-after-exit') and (AArgs.Rule <> 'missing-inherited-ctor') and (AArgs.Rule <> 'missing-inherited-dtor') and
  (AArgs.Rule <> 'control-flow-in-finally') and (AArgs.Rule <> 'too-many-parameters') and (AArgs.Rule <> 'too-many-locals') and
  (AArgs.Rule <> 'method-too-long') and (AArgs.Rule <> 'deep-nesting') and (AArgs.Rule <> 'float-equality-comparison') and
  (AArgs.Rule <> 'freeandnil-on-interface') and (AArgs.Rule <> 'firedac-open-execsql-mismatch') and (AArgs.Rule <> 'unprotected-object-free') and
  (AArgs.Rule <> 'use-after-free') and (AArgs.Rule <> 'win64-pointer-cast') and (AArgs.Rule <> 'ui-access-in-thread') and
  (AArgs.Rule <> 'global-form-variable') and (AArgs.Rule <> 'unsafe-shellexecute') and (AArgs.Rule <> 'path-traversal') and (AArgs.Rule <> 'loop-executes-at-most-once') and
  (AArgs.Rule <> 'format-argument-count') and (AArgs.Rule <> 'format-specifier-type-mismatch') and (AArgs.Rule <> 'try-except-swallowed') and (AArgs.Rule <> 'dataset-open-without-close') and (AArgs.Rule <> 'criticalsection-not-released') and (AArgs.Rule <> 'too-many-exit-points') and (AArgs.Rule <> 'cyclomatic-complexity') and (AArgs.Rule <> 'virtual-method-in-constructor') then
  begin
    Writeln(Format(
        'ERROR: unknown rule "%s" (known: field-by-name-in-loop, ' + 'unit-not-in-dpr, inline-comment-in-multiline-args, unused-local, ' + 'syntax-error, unbalanced-begin-end, raise-in-finally, code-after-exit, ' + 'missing-inherited-ctor, missing-inherited-dtor, control-flow-in-finally, ' + 'too-many-parameters, too-many-locals, method-too-long, deep-nesting, ' + 'float-equality-comparison, freeandnil-on-interface, firedac-open-execsql-mismatch, unprotected-object-free, ' + 'use-after-free, win64-pointer-cast, ui-access-in-thread, global-form-variable, unsafe-shellexecute, path-traversal, loop-executes-at-most-once, format-argument-count, format-specifier-type-mismatch, try-except-swallowed, dataset-open-without-close, criticalsection-not-released, too-many-exit-points, cyclomatic-complexity, virtual-method-in-constructor)',
        [AArgs.Rule]));
    Exit(2);
  end;
  Findings:= nil;
  // Project-level lint: --project triggers DCC/DPR membership check.
  if AArgs.ProjectPath <> '' then
  begin
    if (AArgs.Rule = '') or (AArgs.Rule = 'unit-not-in-dpr') then
    begin
      ProjFindings:= DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr(AArgs.ProjectPath);
      Findings:= Findings + ProjFindings;
    end;
  end;
  if AArgs.Path <> '' then
  begin
    Linter:= DRagLint.Lint.Linter.TLinter.Create(AArgs.RulesDir);
    try
      { Surface the deploy gap instead of silently running with no external rules:
        the exe loads <exe-dir>\rules by default (or --rules-dir). }
      if Linter.ExternalRuleCount = 0 then
        Writeln(ErrOutput, 'drag-lint: note: 0 external .scm rules loaded -- place a "rules" folder next to drag-lint.exe, or pass --rules-dir <path> (built-in checks still run).');
      if TFile.Exists(AArgs.Path) then Findings:= Findings + Linter.LintFile(AArgs.Path)
      else if TDirectory.Exists(AArgs.Path) then Findings:= Findings + Linter.LintFolder(AArgs.Path, True)
      else
      begin
        Writeln('ERROR: path does not exist: ', AArgs.Path);
        Exit(2);
      end;
    finally
      Linter.Free;
    end;
    { v0.46: AST checks that need no DB -- single .pas file only. The plugin's
      lint provider runs `lint <buffer>` with no --rule, so all of these surface
      as live edit-time diagnostics. }
    if TFile.Exists(AArgs.Path) and (SameText(ExtractFileExt(AArgs.Path), '.pas') or SameText(ExtractFileExt(AArgs.Path), '.inc')) then
    begin
      { unused local variables (H2164) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'unused-local') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals(AArgs.Path);
      { syntax errors (tree-sitter ERROR/MISSING) -- this is what makes a typed
        syntax error show up in the editor like the IDE's Error Insight. }
      if (AArgs.Rule = '') or (AArgs.Rule = 'syntax-error') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors(AArgs.Path);
      { unbalanced begin/end (a common edit-time mistake) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'unbalanced-begin-end') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnbalancedBeginEnd(AArgs.Path);
      { v0.47: raise inside a finally block (masks the in-flight exception) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'raise-in-finally') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRaiseInFinally(AArgs.Path);
      { v0.47: unreachable code after Exit/raise/Break/Continue/Halt }
      if (AArgs.Rule = '') or (AArgs.Rule = 'code-after-exit') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit(AArgs.Path);
      { v0.47: Exit/Break/Continue/Halt inside a finally block }
      if (AArgs.Rule = '') or (AArgs.Rule = 'control-flow-in-finally') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally(AArgs.Path);
      { v0.47: constructor/destructor without an inherited call (one walk emits both ids) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'missing-inherited-ctor') or (AArgs.Rule = 'missing-inherited-dtor') then
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckMissingInherited(AArgs.Path) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.48: routine size/complexity metrics (conservative defaults: params>7, locals>25, body>120 lines, nesting>5) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'too-many-parameters') or (AArgs.Rule = 'too-many-locals') or (AArgs.Rule = 'method-too-long') or (AArgs.Rule = 'deep-nesting') then
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRoutineMetrics(AArgs.Path, 7, 25, 120, 5) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.48: type-aware checks (float equality, FreeAndNil-on-interface, v0.52 win64 cast) via a per-file type map }
      if (AArgs.Rule = '') or (AArgs.Rule = 'float-equality-comparison') or (AArgs.Rule = 'freeandnil-on-interface') or (AArgs.Rule = 'win64-pointer-cast') then
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware(AArgs.Path) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.49: FireDAC Open/ExecSQL vs SQL-kind mismatch }
      if (AArgs.Rule = '') or (AArgs.Rule = 'firedac-open-execsql-mismatch') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFireDacSqlMismatch(AArgs.Path);
      { v0.50: object created + freed without try-finally (leak on exception) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'unprotected-object-free') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnprotectedFree(AArgs.Path);
      { v0.52: use of an object after X.Free (dangling reference) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'use-after-free') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUseAfterFree(AArgs.Path);
      { v0.56: UI access inside a TThread.Execute (not thread-safe) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'ui-access-in-thread') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUiThread(AArgs.Path);
      { v0.61: unit-level global variable whose type is the form class -- potential leak }
      if (AArgs.Rule = '') or (AArgs.Rule = 'global-form-variable') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckGlobalFormVars(AArgs.Path);
      { v0.63: WinExec/ShellExecute/CreateProcess with a non-literal command -- injection risk }
      if (AArgs.Rule = '') or (AArgs.Rule = 'unsafe-shellexecute') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckShellExec(AArgs.Path);
      { v0.63: concatenated path to a file API -- path traversal risk }
      if (AArgs.Rule = '') or (AArgs.Rule = 'path-traversal') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckPathTraversal(AArgs.Path);
      { v0.63: loop whose first body statement is Exit/Break/raise -- runs at most once }
      if (AArgs.Rule = '') or (AArgs.Rule = 'loop-executes-at-most-once') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckLoopAtMostOnce(AArgs.Path);
      { v0.63: Format() specifier/argument count + literal type mismatch (one walk, two ids) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'format-argument-count') or (AArgs.Rule = 'format-specifier-type-mismatch') then
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFormatCall(AArgs.Path) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.63: try..except that swallows the exception (no raise/log/HandleException) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'try-except-swallowed') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSwallowedExcept(AArgs.Path);
      { v0.63: dataset opened without a matching Close in a finally block }
      if (AArgs.Rule = '') or (AArgs.Rule = 'dataset-open-without-close') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckDatasetOpen(AArgs.Path);
      { v0.63: critical section acquired without a matching Leave/Release in finally }
      if (AArgs.Rule = '') or (AArgs.Rule = 'criticalsection-not-released') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCriticalSection(AArgs.Path);
      { v0.63: routine with more than 5 Exit statements }
      if (AArgs.Rule = '') or (AArgs.Rule = 'too-many-exit-points') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints(AArgs.Path);
      { v0.63: cyclomatic complexity over 15 }
      if (AArgs.Rule = '') or (AArgs.Rule = 'cyclomatic-complexity') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity(AArgs.Path);
      { v0.63: virtual/dynamic method called from a constructor of its own class }
      if (AArgs.Rule = '') or (AArgs.Rule = 'virtual-method-in-constructor') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckVirtualInConstructor(AArgs.Path);
      { Free cached tree after single-file lint }
      DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear;
    end;
  end; // if
  { v0.47: honor '// drag-lint:ignore [rule ...]' line suppressions across all findings }
  Findings:= ApplyLineSuppressions(Findings);
  { v0.48: --disable id1,id2,... drops those rule ids entirely }
  if AArgs.Disable <> '' then
  begin
    var DisabledIds: TArray<string>:= AArgs.Disable.Split([',', ' ', ';']);
    var KeptF: TArray<TLintFinding>:= nil;
    var DId: string;
    var Drop: Boolean;
    for F in Findings do
    begin
      Drop:= False;
      for DId in DisabledIds do
        if SameText(Trim(DId), F.RuleId) then begin Drop:= True; Break; end;
      if not Drop then KeptF:= KeptF + [F];
    end;
    Findings:= KeptF;
  end;
  if AArgs.AsJson then
  begin
    JArr:= TJSONArray.Create;
    try
      for F in Findings do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('rule'     , F.RuleId  );
        JObj.AddPair('severity' , F.Severity);
        JObj.AddPair('file_path', F.FilePath);
        JObj.AddPair('start_line', TJSONNumber.Create(F.StartLine));
        JObj.AddPair('start_col' , TJSONNumber.Create(F.StartCol ));
        JObj.AddPair('end_line'  , TJSONNumber.Create(F.EndLine  ));
        JObj.AddPair('end_col'   , TJSONNumber.Create(F.EndCol   ));
        JObj.AddPair('message', F.Message);
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end; // try
  end // if
  else
  begin
    for F in Findings do Writeln(Format('%s:%d:%d  [%s] %s: %s', [F.FilePath, F.StartLine, F.StartCol, F.Severity, F.RuleId, F.Message]));
    Writeln(Format('%d finding(s)', [Length(Findings)]));
  end;
  if Length(Findings) > 0 then Result:= 1
  else Result:= 0;
end; // function

// v0.18: drag-lint context --task "verb qname" [--db <path>]
//   [--format md|json|raw] [--max-callers N] [--context N] [--no-docs]
// Builds a TContextBundle and renders it in the requested format.
// Exit 2 on usage error, 1 if symbol not found, 0 on success.
function DoContext(const AArgs: TArgs): Integer;
var
  Store     : ISymbolStore  ;
  Bundle    : TContextBundle;
  IncDocs   : Boolean       ;
  IncSurface: Boolean       ;
  IncImpl   : Boolean       ;
begin
  if AArgs.Task = '' then
  begin
    Writeln('Usage: drag-lint context --task "verb qname" [--db PATH] ' + '[--format md|json|raw]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s', [AArgs.DbPath]));
    Exit(2);
  end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  IncDocs:= not AArgs.NoDocs;
  IncSurface:= AArgs.IncludeClassSurface;
  IncImpl:= SameText(AArgs.Verb, 'modify') or SameText(AArgs.Verb, 'refactor') or SameText(AArgs.Verb, 'extend');
  Bundle:= TContextBundler.Build(
    Store, AArgs.Verb, AArgs.BundleQName, AArgs.ContextLines, AArgs.MaxCallers, IncDocs, IncSurface, IncImpl, {AExcludeDfmFields=}
    not AArgs.FullSurface);
  if Bundle.QName = '' then
  begin
    Writeln(Format('No symbol matched: %s', [AArgs.BundleQName]));
    Exit(1);
  end;
  if SameText(AArgs.Format, 'json') then Writeln(TContextBundler.RenderJson(Bundle))
  else if SameText(AArgs.Format, 'raw') then Writeln(TContextBundler.RenderRaw(Bundle))
  else Writeln(TContextBundler.RenderMarkdown(Bundle));
  Result:= 0;
end; // function

// v0.18: drag-lint bench-context [--db PATH] [--n N]
// Lists up to N documented symbols, builds a context bundle for each (verb
// 'modify'), computes bundle token estimate vs source-file baseline
// (chars / 3.7), and prints average reduction ratio.
function DoBenchContext(const AArgs: TArgs): Integer;
var
  Store         : ISymbolStore               ;
  Syms          : TArray<TSymbol>            ;
  Sym           : TSymbol                    ;
  N             : Integer                    ;
  i             : Integer                    ;
  Bundle        : TContextBundle             ;
  FilePath      : string                     ;
  FileCache     : TDictionary<string, string>;
  FileSource    : string                     ;
  BaselineTokens: Double                     ;
  BundleTokens  : Double                     ;
  TotalBundle   : Double                     ;
  TotalBaseline : Double                     ;
  Count         : Integer                    ;
begin
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s', [AArgs.DbPath]));
    Exit(2);
  end;

  N:= AArgs.BenchN;
  if N <= 0 then N:= 20;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  // Fetch documented symbols (clamped to N).
  Syms:= Store.ListDocumentedSymbols(N);
  if Length(Syms) = 0 then
  begin
    Writeln('No documented symbols found in: ', AArgs.DbPath);
    Exit(1);
  end;

  FileCache:= TDictionary<string, string>.Create;
  TotalBundle  := 0;
  TotalBaseline:= 0;
  Count        := 0;
  try
    for i:= 0 to High(Syms) do
    begin
      Sym:= Syms[i];
      FilePath:= Store.GetFilePath(Sym.FileId);
      if (FilePath = '') or (not TFile.Exists(FilePath)) then Continue;

      // Build context bundle for this symbol.
      Bundle:= TContextBundler.Build( Store, 'modify', Sym.QualifiedName, 3, 5, True, True, True);

      // Baseline: entire source file chars / 3.7.
      if not FileCache.TryGetValue(FilePath, FileSource) then
      begin
        try
          FileSource:= TFile.ReadAllText(FilePath, TEncoding.ANSI);
        except
          FileSource:= '';
        end;
        FileCache.AddOrSetValue(FilePath, FileSource);
      end;

      BundleTokens:= Bundle.TokenEstimate;
      BaselineTokens:= Length(FileSource) / 3.7;

      TotalBundle  := TotalBundle   + BundleTokens;
      TotalBaseline:= TotalBaseline + BaselineTokens;
      Inc(Count);
    end; // for
  finally
    FileCache.Free;
  end; // try

  if Count = 0 then
  begin
    Writeln('No valid symbols with accessible source files.');
    Exit   (1                                               );
  end;

  var AvgBundle  := TotalBundle   / Count;
  var AvgBaseline:= TotalBaseline / Count;
  var Reduction: Double;
  if AvgBundle > 0 then Reduction:= AvgBaseline / AvgBundle
  else Reduction:= 0;

  Writeln(Format('Bench: %s (N=%d)', [AArgs.DbPath, Count]));
  Writeln(Format('  Average bundle tokens:    %d', [Round(AvgBundle  )]));
  Writeln(Format('  Average baseline tokens:  %d', [Round(AvgBaseline)]));
  Writeln(Format('  Reduction:                %.1fx', [Reduction]));

  Result:= 0;
end; // function

// v0.40.5 Tier 2: drag-lint fb-snapshot --connection "..." --db sql.sqlite
function DoFbSnapshot(const AArgs: TArgs): Integer;
var
  Store : TSQLiteSymbolStore;
  Stats : TFbSnapshotStats  ;
  DbPath: string            ;
begin
  if AArgs.FbConnection = '' then
  begin
    Writeln(ErrOutput, 'fb-snapshot: --connection "Database=...;User=...;Password=...;DriverID=FB" required');
    Exit(2);
  end;
  if Length(AArgs.DbPaths) > 0 then DbPath:= AArgs.DbPaths[0]
  else DbPath:= AArgs.DbPath;
  if DbPath = '' then
  begin
    Writeln(ErrOutput, 'fb-snapshot: --db <sql.sqlite> required');
    Exit(2);
  end;
  Store:= TSQLiteSymbolStore.Create(DbPath);
  try
    Store.Migrate;
    try
      Stats:= TFbSnapshot.Run(AArgs.FbConnection, Store);
      Writeln(Format(
          'fb-snapshot: %d relations, %d columns, %d field_info, %d datasets, %d enums (snapshot_at=%d)',
          [Stats.Relations, Stats.Columns, Stats.FieldInfos, Stats.Datasets, Stats.EnumValues, Stats.SnapshotAt]));
      Result:= 0;
    except
      on E: Exception do
      begin
        Writeln(ErrOutput, 'fb-snapshot FAILED: ', E.ClassName, ': ', E.Message);
        Result:= 3;
      end;
    end;
  finally
    Store.Free;
  end; // try
end; // function

// v0.40.5 Tier 3: drag-lint link-orm --db proj.sqlite --db sql.sqlite
function DoLinkOrm(const AArgs: TArgs): Integer;
var
  Stats: TOrmLinkerStats;
begin
  if Length(AArgs.DbPaths) < 1 then
  begin
    Writeln(ErrOutput, 'link-orm: pass each project + sql DB as --db <path>');
    Exit(2);
  end;
  try
    Stats:= TOrmLinker.Run(AArgs.DbPaths);
    Writeln(Format(
        'link-orm: %d class_to_table, %d iface_to_table, %d field_to_column (across %d DBs)', [Stats.ClassLinks, Stats.IfaceLinks, Stats.FieldLinks, Length(AArgs.DbPaths)]));
    Result:= 0;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'link-orm FAILED: ', E.ClassName, ': ', E.Message);
      Result:= 3;
    end;
  end;
end; // function

// v0.40.4: drag-lint uses-report --output <out.csv> [--db ...] [...]
//
// Emits a CSV row per (source_unit, transitively_used_unit) for every unit
// in the project (or, with --all-sources, every unit across every --db).
// BFS with a per-source visited set so each downstream unit appears at most
// once per source. Cycles are broken automatically by the visited set;
// unresolved (external) units terminate the walk at depth 1 unless
// --include-external is passed (in which case they appear in the output
// but still terminate as leaves since we don't have their uses indexed).
//
// CSV columns:
//   source_unit       ? basename stem (no ext, no dir) of the source file
//   used_unit         ? verbatim unit_name as written in the uses clause
//   depth             ? 1 = direct use, 2 = via one hop, ...
//   first_section     ? section the edge was first reached through
//   via_chain         ? '>' separated unit chain from source -> used (excl. self)
//   external          ? 1 when target_file_id couldn't be resolved, else 0
function DoUsesReport(const AArgs: TArgs): Integer;
type
  TUsesEdge = record
    UnitName    : string; { verbatim }
    UnitNameNorm: string; { lowercase trailing segment }
    TargetFileId: Int64 ; { -1 = external/unresolved }
    Section     : string; { 'interface'|'implementation'|'program'|'package' }
  end;

  TFileMeta = record
    Path      : string ;
    Stem      : string ; { lowercase basename without extension }
    StoreIndex: Integer; { which --db this file came from }
    FileId    : Int64  ; { id INSIDE that store; needed for joins }
  end;

  TBfsQueueItem = record
    FileId      : Int64  ;
    Depth       : Integer;
    UsedUnit    : string ;
    UnitNameNorm: string ;
    Section     : string ;
    Via         : string ; { chain so far, '>' separated, excludes self }
    External    : Boolean;
  end;
var
  Stores      : TArray<ISymbolStore>                   ;
  AllFiles    : TList<TFileMeta>                       ;
  StemToGlobal: TDictionary<string, Integer>           ; { stem -> index into AllFiles }
  Edges       : TDictionary<Integer, TArray<TUsesEdge>>; { source = global file index }
  CsvOut      : TStreamWriter                          ;
  MaxDepth    : Integer                                ;
  RootPattern : string                                 ;

  procedure OpenStores;
  var
    DbList: TArray<string>;
    i     : Integer       ;
    Path  : string        ;
  begin
    if Length(AArgs.DbPaths) > 0 then DbList:= AArgs.DbPaths
    else if AArgs.DbPath <> '' then DbList:= TArray<string>.Create(AArgs.DbPath)
    else
    begin
      Writeln(ErrOutput, 'uses-report: need at least one --db');
      Result:= 2;
      Exit;
    end;
    SetLength(Stores, 0);
    for i:= 0 to High(DbList) do
    begin
      Path:= DbList[i];
      if not TFile.Exists(Path) then
      begin
        Writeln(ErrOutput, 'uses-report: db not found, skipping: ', Path);
        Continue;
      end;
      SetLength(Stores, Length(Stores) + 1);
      Stores[High(Stores)]:= TSQLiteSymbolStore.Create(Path);
      Stores[High(Stores)].Migrate;
    end;
  end; // procedure

  function ComputeStem(const APath: string): string;
  var
    Base: string ;
    Dot : Integer;
  begin
    Base:= APath;
    while Length(Base) > 0 do
    begin
      if CharInSet(Base[Length(Base)], ['\','/']) then
      begin
        Delete(Base, Length(Base), 1);
        Break;
      end;
      Break;
    end;
    Result:= LowerCase(ExtractFileName(Base));
    Dot:= LastDelimiter('.', Result);
    if Dot > 0 then Result:= Copy(Result, 1, Dot - 1);
  end;

  procedure LoadFilesAndEdges;
  var
    StoreIdx      : Integer                               ;
    QFiles        : TFDQuery                              ;
    QUses         : TFDQuery                              ;
    SQLiteStore   : TSQLiteSymbolStore                    ;
    Meta          : TFileMeta                             ;
    PathStr       : string                                ;
    LocalFileId   : Int64                                 ;
    GlobalIdx     : Integer                               ;
    FileIdToGlobal: TDictionary<Int64, Integer>           ;
    LocalUses     : TList<TUsesEdge>                      ;
    PerStore      : TDictionary<Integer, TList<TUsesEdge>>;
    TargetFid     : Int64                                 ;
    TargetPath    : string                                ;
    TargetGlobal  : Integer                               ;
    Edge          : TUsesEdge                             ;
    Kv            : TPair<Integer, TList<TUsesEdge>>      ;
    AssistQ       : TFDQuery                              ;
  begin
    AllFiles:= TList<TFileMeta>.Create;
    StemToGlobal:= TDictionary<string, Integer>.Create;
    Edges   := TDictionary<Integer, TArray<TUsesEdge>>.Create;
    PerStore:= TDictionary<Integer, TList <TUsesEdge>>.Create;

    { Step 1: gather every file across every store, build stem -> global index. }
    for StoreIdx:= 0 to High(Stores) do
    begin
      SQLiteStore:= TSQLiteSymbolStore(Stores[StoreIdx]);
      QFiles:= TFDQuery.Create(nil);
      try
        QFiles.Connection:= SQLiteStore.GetConnection;
        { Filter out DFM rows ? uses clauses only exist in pascal sources.
          Language tag is 'delphi13' for .pas/.dpr/.dpk in v0.40.x indexes. }
        QFiles.Sql.Text:= 'SELECT id, path FROM files ' + 'WHERE language NOT IN (''dfm'', ''json'', ''text'')';
        QFiles.Open;
        while not QFiles.Eof do
        begin
          PathStr:= QFiles.FieldByName('path').AsString;
          Meta.Path:= PathStr;
          Meta.Stem:= ComputeStem(PathStr);
          Meta.StoreIndex:= StoreIdx;
          Meta.FileId:= QFiles.FieldByName('id').AsLargeInt;
          AllFiles.Add(Meta);
          { First-write-wins: project DB (first --db) takes priority. }
          if not StemToGlobal.ContainsKey(Meta.Stem) then StemToGlobal.Add(Meta.Stem, AllFiles.Count - 1);
          QFiles.Next;
        end;
      finally
        QFiles.Free;
      end; // try
    end; // for

    { Step 2: gather every unit_uses edge, group by global source file index. }
    FileIdToGlobal:= TDictionary<Int64, Integer>.Create;
    try
      for GlobalIdx:= 0 to AllFiles.Count - 1 do FileIdToGlobal.AddOrSetValue( (Int64(AllFiles[GlobalIdx].StoreIndex) shl 40) or Int64(AllFiles[GlobalIdx].FileId), GlobalIdx);

      for StoreIdx:= 0 to High(Stores) do
      begin
        SQLiteStore:= TSQLiteSymbolStore(Stores[StoreIdx]);
        QUses:= TFDQuery.Create(nil);
        try
          QUses.Connection:= SQLiteStore.GetConnection;
          QUses.Sql.Text:= 'SELECT file_id, unit_name, unit_name_norm, section, target_file_id ' + 'FROM unit_uses';
          QUses.Open;
          while not QUses.Eof do
          begin
            LocalFileId:= QUses.FieldByName('file_id').AsLargeInt;
            if not FileIdToGlobal.TryGetValue( (Int64(StoreIdx) shl 40) or LocalFileId, GlobalIdx) then
            begin
              QUses.Next;
              Continue;
            end;

            Edge.UnitName    := QUses.FieldByName('unit_name'     ).AsString;
            Edge.UnitNameNorm:= QUses.FieldByName('unit_name_norm').AsString;
            Edge.Section     := QUses.FieldByName('section'       ).AsString;
            { Resolve target: prefer the in-DB target_file_id; fall back to
              cross-DB lookup by stem. }
            Edge.TargetFileId:= -1;
            if not QUses.FieldByName('target_file_id').IsNull then
            begin
              TargetFid:= QUses.FieldByName('target_file_id').AsLargeInt;
              if FileIdToGlobal.TryGetValue( (Int64(StoreIdx) shl 40) or TargetFid, TargetGlobal) then Edge.TargetFileId:= TargetGlobal;
            end;
            if Edge.TargetFileId = -1 then
              if StemToGlobal.TryGetValue(Edge.UnitNameNorm, TargetGlobal) then Edge.TargetFileId:= TargetGlobal;

            if not PerStore.ContainsKey(GlobalIdx) then PerStore.Add(GlobalIdx, TList<TUsesEdge>.Create);
            PerStore[GlobalIdx].Add(Edge);

            QUses.Next;
          end; // while
        finally
          QUses.Free;
        end; // try
      end; // for
    finally
      FileIdToGlobal.Free;
    end; // try

    for Kv in PerStore do Edges.AddOrSetValue(Kv.Key, Kv.Value.ToArray);
    for Kv in PerStore do Kv.Value.Free;
    PerStore.Free;
  end; // procedure

  procedure EmitCsvHeader;
  begin
    CsvOut.WriteLine('source_unit,used_unit,depth,first_section,via_chain,external');
  end;

  function CsvEscape(const S: string): string;
  begin
    if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) then Result:= '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
    else Result:= S;
  end;

  procedure EmitCsvRow(const ASource, AUsed: string; ADepth: Integer; const ASection, AVia: string; AExternal: Boolean);
  begin
    CsvOut.WriteLine( CsvEscape(ASource) + ',' + CsvEscape(AUsed) + ',' + IntToStr(ADepth) + ',' + CsvEscape(ASection) + ',' + CsvEscape(AVia) + ',' + IfThen(AExternal, '1', '0'));
  end;

  procedure WalkBfs(ASourceIdx: Integer; var ARowCount: Integer);
  var
    Queue     : System.Generics.Collections.TQueue<TBfsQueueItem>;
    Visited   : TDictionary<string, Boolean>                     ;
    Item      : TBfsQueueItem                                    ;
    Nx        : TBfsQueueItem                                    ;
    Edge      : TUsesEdge                                        ;
    EdgeList  : TArray<TUsesEdge>                                ;
    SourceMeta: TFileMeta                                        ;
    NextVia   : string                                           ;
  begin
    Queue:= System.Generics.Collections.TQueue<TBfsQueueItem>.Create;
    Visited:= TDictionary<string, Boolean>.Create;
    try
      SourceMeta:= AllFiles[ASourceIdx];

      { Seed: direct uses from the source file. }
      if Edges.TryGetValue(ASourceIdx, EdgeList) then
        for Edge in EdgeList do
        begin
          if Visited.ContainsKey(Edge.UnitNameNorm) then Continue;
          Item.FileId:= Edge.TargetFileId;
          Item.Depth:= 1;
          Item.UsedUnit    := Edge.UnitName;
          Item.UnitNameNorm:= Edge.UnitNameNorm;
          Item.Section     := Edge.Section;
          Item.Via:= '';
          Item.External:= (Edge.TargetFileId < 0);
        Queue.Enqueue(Item);
      end;

    while Queue.Count > 0 do
    begin
      Item:= Queue.Dequeue;
      if Visited.ContainsKey(Item.UnitNameNorm) then Continue;
      Visited.Add(Item.UnitNameNorm, True);

      if Item.External and (not AArgs.IncludeExternal) then
      begin
        { Skip external rows when not requested, but DO still mark visited
            so we don't repeat them later via a different chain. }
      end
      else
      begin
        EmitCsvRow(SourceMeta.Stem, Item.UsedUnit, Item.Depth, Item.Section, Item.Via, Item.External);
        Inc(ARowCount);
      end;

      if Item.External then Continue;
      if Item.Depth >= MaxDepth then Continue;
      if not Edges.TryGetValue(Integer(Item.FileId), EdgeList) then Continue;

      if Item.Via = '' then NextVia:= Item.UsedUnit
      else NextVia:= Item.Via + '>' + Item.UsedUnit;

      for Edge in EdgeList do
      begin
        if Visited.ContainsKey(Edge.UnitNameNorm) then Continue;
        Nx.FileId:= Edge.TargetFileId;
        Nx.Depth:= Item.Depth + 1;
        Nx.UsedUnit    := Edge.UnitName;
        Nx.UnitNameNorm:= Edge.UnitNameNorm;
        Nx.Section     := Edge.Section;
        Nx.Via:= NextVia;
        Nx.External:= (Edge.TargetFileId < 0);
        Queue.Enqueue(Nx);
      end;
    end; // while
  finally
    Visited.Free;
    Queue.Free;
  end; // try
end; // procedure

var
  GlobalIdx   : Integer  ;
  SourceMeta  : TFileMeta;
  RowCount    : Integer  ;
  SourceCount : Integer  ;
  RootPatLower: string   ;
begin
  Result:= 0;

  if AArgs.Output = '' then
  begin
    Writeln(ErrOutput, 'uses-report: --output <path.csv> is required');
    Exit(2);
  end;

  MaxDepth:= AArgs.Depth;
  if MaxDepth <= 0 then MaxDepth:= 50;
  RootPattern:= LowerCase(AArgs.Name);

  AllFiles    := nil;
  StemToGlobal:= nil;
  Edges       := nil;
  CsvOut      := nil;
  try
    OpenStores;
    if Result <> 0 then Exit;
    if Length(Stores) = 0 then
    begin
      Writeln(ErrOutput, 'uses-report: no usable DB');
      Exit(2);
    end;

    LoadFilesAndEdges;

    CsvOut:= TStreamWriter.Create(AArgs.Output, False, TEncoding.UTF8);
    EmitCsvHeader;

    RowCount    := 0;
    SourceCount := 0;
    RootPatLower:= RootPattern;
    for GlobalIdx:= 0 to AllFiles.Count - 1 do
    begin
      SourceMeta:= AllFiles[GlobalIdx];
      { Default: emit only files from the first DB (the "project"). With
        --all-sources, include all. }
      if (not AArgs.AllSources) and (SourceMeta.StoreIndex <> 0) then Continue;
      if (RootPatLower <> '') and (Pos(RootPatLower, SourceMeta.Stem) = 0) then Continue;
      WalkBfs(GlobalIdx, RowCount);
      Inc(SourceCount);
    end;
    CsvOut.Flush;

    Writeln(Format('uses-report: %d source units, %d rows written to %s', [SourceCount, RowCount, AArgs.Output]));
  finally
    if CsvOut       <> nil then CsvOut      .Free;
    if Edges        <> nil then Edges       .Free;
    if StemToGlobal <> nil then StemToGlobal.Free;
    if AllFiles     <> nil then AllFiles    .Free;
  end; // try
end; // begin

// v0.19: drag-lint typeat <file>:<line>:<col> [--db <path>] [--format text|json]
// Resolves the identifier at the given position to a symbol in the index.
// The position argument has the form: C:\path\to\File.pas:17:8
// (Windows paths may contain a drive letter colon, so we parse the LAST
// two colon-delimited segments as line and column.)
function DoTypeAt(const AArgs: TArgs): Integer;
var
  Pos     : string        ;
  FilePart: string        ;
  Parts   : TArray<string>;
  Line    : Integer       ;
  Col     : Integer       ;
  Store   : ISymbolStore  ;
  TAResult: TTypeAtResult ;
  Fmt     : string        ;
begin
  Pos:= AArgs.Position;
  if Pos = '' then
  begin
    Writeln('Usage: drag-lint typeat <file>:<line>:<col> [--db <path>] ' + '[--format text|json]');
    Exit(2);
  end;

  // Parse last two colon segments as line:col.
  // e.g. "C:\foo\bar.pas:17:8" -> Parts=[..,"17","8"]
  Parts:= Pos.Split([':']);
  if Length(Parts) < 3 then
  begin
    Writeln('ERROR: position must be <file>:<line>:<col>, got: ', Pos);
    Exit(2);
  end;
  Col:= StrToIntDef(Parts[High(Parts)], 0);
  Line:= StrToIntDef(Parts[High(Parts) - 1], 0);
  // Everything before the last two segments is the file path.
  // Re-join first (n-2) parts with ':' to handle drive letters.
  var PartCount:= Length(Parts) - 2;
  FilePart:= string.Join(':', System.Copy(Parts, 0, PartCount));

  if (Line <= 0) or (Col <= 0) then
  begin
    Writeln('ERROR: line and col must be positive integers');
    Exit   (2                                              );
  end;

  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit   (2                                    );
  end;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  TAResult:= TTypeAtResolver.Resolve(Store, FilePart, Line, Col);

  Fmt:= LowerCase(AArgs.Format);
  if Fmt = 'json' then Write(TTypeAtResolver.RenderJson(TAResult))
  else Write(TTypeAtResolver.RenderText(TAResult));

  if TAResult.HasResolved then Result:= 0
  else Result:= 1;
end; // function

// v0.25: drag-lint generate-docs --qname X [--format xmldoc|pasdoc] [--db PATH]
// Generates a doc stub (XMLDoc or PasDoc format) for the given symbol and
// prints it to stdout. Exit 2 on usage error, 1 if symbol not found, 0 on success.
function DoGenerateDocs(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore  ;
  Fmt  : TDocStubFormat;
  Stub : string        ;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint generate-docs --qname X [--format xmldoc|pasdoc] [--db PATH]');
    Exit   (2                                                                              );
  end;
  if not FileExists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s', [AArgs.DbPath]));
    Exit(2);
  end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  if SameText(AArgs.Format, 'pasdoc') then Fmt:= dsfPasDoc
  else Fmt:= dsfXmlDoc;
  Stub:= TDocStubGenerator.Generate(Store, AArgs.QName, Fmt);
  if Stub = '' then
  begin
    Writeln(Format('No stub generated for %s (symbol not found)', [AArgs.QName]));
    Exit(1);
  end;
  Writeln(Stub);
  Result:= 0;
end; // function

// v0.25: drag-lint find-deadcode [--kind K] [--include-private] [--db PATH]
// Lists symbols with no callers in the index. Exit 0 if any found, 1 if none,
// 2 on usage error.
function DoFindDeadCode(const AArgs: TArgs): Integer;
var
  Store  : ISymbolStore   ;
  Symbols: TArray<TSymbol>;
begin
  if not FileExists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s', [AArgs.DbPath]));
    Exit(2);
  end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Symbols:= TDeadCodeFinder.Find(Store, AArgs.Kind, AArgs.IncludePrivate);
  if Length(Symbols) > 0 then Writeln(TDeadCodeFinder.RenderText(Symbols, Store));
  Writeln(Format('Found %d dead-code candidate(s)', [Length(Symbols)]));
  if Length(Symbols) > 0 then Result:= 0
  else Result:= 1;
end; // function

// v0.61: drag-lint lint-all [--db <index.sqlite>] [--project <.dproj>]
//   [--disable id,...] [--output <report.txt>] [--json]
// Batch lint runner: runs ALL per-file AST rules over every indexed .pas file,
// then all project-wide rules, and writes a consolidated report.
// Exit 1 if any findings, 0 if none, 2 on usage error.
function DoLintAll(const AArgs: TArgs): Integer;
var
  Dbs      : TArray<string>              ;
  ProjectDb: string                      ;
  LibDb    : string                      ;
  Store    : ISymbolStore                ;
  Findings : TArray<TLintFinding>        ;
  FilePaths: TArray<string>              ;
  Fid      : Int64                       ;
  PasPath  : string                      ;
  Linter   : DRagLint.Lint.Linter.TLinter;
  F        : TLintFinding                ;
  DisIds   : TArray<string>              ;
  KeptF    : TArray<TLintFinding>        ;
  DId      : string                      ;
  Drop     : Boolean                     ;
  OutPath  : string                      ;
  OutLines : TStringBuilder              ;
  JArr     : TJSONArray                  ;
  JObj     : TJSONObject                 ;
  ErrCnt   : Integer                     ;
  WarnCnt  : Integer                     ;
  LayersCfg: string                      ;
  FileIdx  : Integer                     ;
  LastPct  : Integer                     ;
  Pct      : Integer                     ;
begin
  { Resolve DBs: first existing = project index; second = library index }
  Dbs:= ResolveConsumerDbs(AArgs);
  ProjectDb:= '';
  LibDb    := '';
  for var D in Dbs do
  begin
    if not TFile.Exists(D) then Continue;
    if ProjectDb = '' then ProjectDb:= D
    else if LibDb = '' then LibDb:= D;
  end;
  if ProjectDb = '' then
  begin
    Writeln('ERROR: no drag-lint index found. Pass --db <index.sqlite> or build the index first.');
    Exit(2);
  end;

  { Open project store }
  Store:= TSQLiteSymbolStore.Create(ProjectDb);
  Store.Migrate;
  Findings:= nil;

  { Enumerate all indexed .pas files from the project store }
  FilePaths:= nil;
  for Fid in Store.GetAllFileIds do
  begin
    PasPath:= Store.GetFilePath(Fid);
    if SameText(ExtractFileExt(PasPath), '.pas') and TFile.Exists(PasPath) then
      FilePaths:= FilePaths + [PasPath];
  end;
  Writeln(Format('lint-all: scanning %d .pas file(s)', [Length(FilePaths)]));

  { Per-file rules: external .scm rules + all built-in AST checks }
  Linter:= DRagLint.Lint.Linter.TLinter.Create(AArgs.RulesDir);
  LastPct:= -1;
  try
    for FileIdx:= 0 to Length(FilePaths) - 1 do
    begin
      PasPath:= FilePaths[FileIdx];
      try
        { Progress output (throttled by percentage) }
        if (not AArgs.Quiet) then
        begin
          Pct:= ((FileIdx + 1) * 100) div Max(1, Length(FilePaths));
          if (FileIdx = 0) or (FileIdx = Length(FilePaths) - 1) or (Pct <> LastPct) then
          begin
            Writeln(ErrOutput, Format('lint-all: [%d/%d] %d%% %s',
              [FileIdx + 1, Length(FilePaths), Pct, ExtractFileName(PasPath)]));
            Flush(ErrOutput);
            LastPct:= Pct;
          end;
        end;
        Findings:= Findings + Linter.LintFile(PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals    (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors    (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnbalancedBeginEnd(PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRaiseInFinally  (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit   (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally(PasPath);
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckMissingInherited(PasPath) do
          Findings:= Findings + [F];
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRoutineMetrics(PasPath, 7, 25, 120, 5) do
          Findings:= Findings + [F];
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware(PasPath) do
          Findings:= Findings + [F];
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFireDacSqlMismatch(PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnprotectedFree (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUseAfterFree    (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUiThread        (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckGlobalFormVars  (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckShellExec       (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckPathTraversal   (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckLoopAtMostOnce  (PasPath);
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFormatCall(PasPath) do
          Findings:= Findings + [F];
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSwallowedExcept(PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckDatasetOpen    (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCriticalSection(PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints(PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity(PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckVirtualInConstructor(PasPath);
      except
        on E: Exception do
          Writeln(ErrOutput, Format('lint-all: skip %s (%s: %s)',
            [ExtractFileName(PasPath), E.ClassName, E.Message]));
      end;
      { Free cached tree for this file before moving to the next }
      DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear;
    end;
  finally
    Linter.Free;
  end;

  { Project-wide rules }
  Findings:= Findings +
    DRagLint.Lint.ProjectRules.TProjectLintRules.Run(Store, '');
  { Interface reference cycles (needs all file paths) }
  Findings:= Findings +
    DRagLint.Diagnostics.AstChecks.TAstChecker.CheckInterfaceCycles(FilePaths);
  { Architecture layering (only if config present) }
  LayersCfg:= AArgs.LayersPath;
  if (LayersCfg = '') and FileExists('drag-lint-layers.json') then LayersCfg:= 'drag-lint-layers.json';
  if LayersCfg <> '' then
    Findings:= Findings +
      DRagLint.Lint.ProjectRules.TProjectLintRules.CheckLayering(Store, LayersCfg);
  { DPR/dproj membership cross-check (unit-not-in-dpr) }
  if AArgs.ProjectPath <> '' then
    Findings:= Findings +
      DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr(AArgs.ProjectPath);
  { Unit membership against library DB (unit-not-in-project) }
  Findings:= Findings +
    DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitMembership(Store, LibDb, AArgs.ProjectPath);

  { Honor drag-lint:ignore suppressions }
  Findings:= ApplyLineSuppressions(Findings);

  { --disable id,... drops those rule ids entirely }
  if AArgs.Disable <> '' then
  begin
    DisIds:= AArgs.Disable.Split([',', ' ', ';']);
    KeptF := nil;
    for F in Findings do
    begin
      Drop:= False;
      for DId in DisIds do
        if SameText(Trim(DId), F.RuleId) then begin Drop:= True; Break; end;
      if not Drop then KeptF:= KeptF + [F];
    end;
    Findings:= KeptF;
  end;

  { Count by severity }
  ErrCnt := 0;
  WarnCnt:= 0;
  for F in Findings do
    if SameText(F.Severity, 'error') then Inc(ErrCnt) else Inc(WarnCnt);

  { Resolve output path: --output, or lint-report-YYYYMMDD.txt beside the DB }
  OutPath:= AArgs.Output;
  if OutPath = '' then
  begin
    var BaseDir: string;
    if AArgs.ProjectPath <> '' then BaseDir:= ExtractFilePath(AArgs.ProjectPath)
    else BaseDir:= ExtractFilePath(ProjectDb);
    OutPath:= TPath.Combine(BaseDir, 'lint-report-' + FormatDateTime('YYYYMMDD', Now) + '.txt');
  end;

  if AArgs.AsJson then
  begin
    JArr:= TJSONArray.Create;
    try
      for F in Findings do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('rule'      , F.RuleId  );
        JObj.AddPair('severity'  , F.Severity);
        JObj.AddPair('file_path' , F.FilePath);
        JObj.AddPair('start_line', TJSONNumber.Create(F.StartLine));
        JObj.AddPair('start_col' , TJSONNumber.Create(F.StartCol ));
        JObj.AddPair('end_line'  , TJSONNumber.Create(F.EndLine  ));
        JObj.AddPair('end_col'   , TJSONNumber.Create(F.EndCol   ));
        JObj.AddPair('message'   , F.Message );
        JArr.AddElement(JObj);
      end;
      TFile.WriteAllText(OutPath, JArr.ToJSON, TEncoding.UTF8);
      Writeln(JArr.ToJSON);
    finally
      JArr.Free;
    end;
  end
  else
  begin
    OutLines:= TStringBuilder.Create;
    try
      for F in Findings do
        OutLines.AppendLine(Format('%s:%d:%d  [%s] %s: %s',
          [F.FilePath, F.StartLine, F.StartCol, F.Severity, F.RuleId, F.Message]));
      OutLines.AppendLine(Format(
        'lint-all: %d finding(s) -- %d error(s), %d warning(s) -- %d file(s) scanned',
        [Length(Findings), ErrCnt, WarnCnt, Length(FilePaths)]));
      TFile.WriteAllText(OutPath, OutLines.ToString, TEncoding.UTF8);
    finally
      OutLines.Free;
    end;
    for F in Findings do
      Writeln(Format('%s:%d:%d  [%s] %s: %s',
        [F.FilePath, F.StartLine, F.StartCol, F.Severity, F.RuleId, F.Message]));
    Writeln(Format(
      'lint-all: %d finding(s) -- %d error(s), %d warning(s) -- %d file(s) -- report: %s',
      [Length(Findings), ErrCnt, WarnCnt, Length(FilePaths), OutPath]));
  end;

  if Length(Findings) > 0 then Result:= 1 else Result:= 0;
end; // function

// v0.48: drag-lint lint-project --db <index.sqlite> [--rule <id>] [--json]
// Index-wide ("project") lint rules (god-class, unused-public-symbol) that need
// the whole symbol/refs graph. Exit 1 if any findings, 0 if none, 2 on usage error.
function DoLintProject(const AArgs: TArgs): Integer;
var
  Store   : ISymbolStore        ;
  Findings: TArray<TLintFinding> ;
  F       : TLintFinding         ;
  JArr    : TJSONArray           ;
  JObj    : TJSONObject          ;
begin
  if not FileExists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s (pass --db <index.sqlite>)', [AArgs.DbPath]));
    Exit(2);
  end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Findings:= DRagLint.Lint.ProjectRules.TProjectLintRules.Run(Store, AArgs.Rule);
  { v0.51: interface reference cycles -- needs the AST of all project files (parsed here) }
  if (AArgs.Rule = '') or (AArgs.Rule = 'interface-reference-cycle') then
  begin
    var Paths: TArray<string>:= nil;
    var Fid2 : Int64;
    for Fid2 in Store.GetAllFileIds do Paths:= Paths + [Store.GetFilePath(Fid2)];
    Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckInterfaceCycles(Paths);
  end;
  { v0.54: architecture layering -- needs a layer config (--layers, or drag-lint-layers.json in CWD) }
  if (AArgs.Rule = '') or (AArgs.Rule = 'layering-violation') then
  begin
    var Cfg: string:= AArgs.LayersPath;
    if (Cfg = '') and FileExists('drag-lint-layers.json') then Cfg:= 'drag-lint-layers.json';
    if Cfg <> '' then Findings:= Findings + DRagLint.Lint.ProjectRules.TProjectLintRules.CheckLayering(Store, Cfg);
  end;
  { v0.61: unit-not-in-project -- cross-checks used units vs library DB and project .dpr/.dproj }
  if (AArgs.Rule = '') or (AArgs.Rule = 'unit-not-in-project') then
  begin
    var LibDbPath2: string:= '';
    if Length(AArgs.DbPaths) > 1 then LibDbPath2:= AArgs.DbPaths[1];
    Findings:= Findings + DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitMembership(
      Store, LibDbPath2, AArgs.ProjectPath);
  end;
  if AArgs.AsJson then
  begin
    JArr:= TJSONArray.Create;
    try
      for F in Findings do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('rule'      , F.RuleId  );
        JObj.AddPair('severity'  , F.Severity);
        JObj.AddPair('file_path' , F.FilePath);
        JObj.AddPair('start_line', TJSONNumber.Create(F.StartLine));
        JObj.AddPair('start_col' , TJSONNumber.Create(F.StartCol ));
        JObj.AddPair('end_line'  , TJSONNumber.Create(F.EndLine  ));
        JObj.AddPair('end_col'   , TJSONNumber.Create(F.EndCol   ));
        JObj.AddPair('message'   , F.Message );
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.ToJSON);
    finally
      JArr.Free;
    end;
  end
  else
  begin
    for F in Findings do
      Writeln(Format('%s:%d:%d  [%s] %s: %s', [F.FilePath, F.StartLine, F.StartCol, F.Severity, F.RuleId, F.Message]));
    Writeln(Format('%d finding(s)', [Length(Findings)]));
  end;
  if Length(Findings) > 0 then Result:= 1 else Result:= 0;
end; // function

// v0.24: count distinct file paths across edit set.
function CountDistinctFiles(const AEdits: TArray<TRenameEdit>): Integer;
var
  Seen: TDictionary<string, Boolean>;
  E   : TRenameEdit                 ;
begin
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for E in AEdits do Seen.AddOrSetValue(E.FilePath, True);
    Result:= Seen.Count;
  finally
    Seen.Free;
  end;
end;

// v0.24: drag-lint rename --qname Foo.TBar.Baz --to NewName
//   [--db PATH] [--dry-run] [--no-backup]
// Resolves the symbol, finds all caller refs, builds an edit set, then
// either dry-runs (prints plan) or applies edits in-place with .bak backup.
function DoRename(const AArgs: TArgs): Integer;
var
  Store       : ISymbolStore       ;
  Edits       : TArray<TRenameEdit>;
  FilesTouched: Integer            ;
begin
  if (AArgs.QName = '') or (AArgs.RenameTo = '') then
  begin
    Writeln('Usage: drag-lint rename --qname Foo.TBar.Baz --to NewName ' + '[--db PATH] [--dry-run] [--no-backup]');
    Exit(2);
  end;
  if not FileExists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s', [AArgs.DbPath]));
    Exit(1);
  end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Edits:= TRenameRefactoring.Build(Store, AArgs.QName, AArgs.RenameTo);
  if Length(Edits) = 0 then
  begin
    Writeln(Format('No edits computed for %s (symbol may not exist)', [AArgs.QName]));
    Exit(1);
  end;

  if AArgs.DryRun then
  begin
    Writeln(TRenameRefactoring.RenderDryRun(Edits));
    Writeln(Format('Dry run: %d edits across %d files', [Length(Edits), CountDistinctFiles(Edits)]));
    Exit(0);
  end;

  FilesTouched:= TRenameRefactoring.Apply(Edits, not AArgs.NoBackup);
  Writeln(Format('Renamed: %d edits, %d files touched. ' + 'Re-run `drag-lint index` to refresh.', [Length(Edits), FilesTouched]));
  Result:= 0;
end; // function

// v0.26: drag-lint compile-check <target.dproj|.pas> [--db PATH] [--format json|text]
// Runs a compiler build, parses findings, stores them in the DB (if --db
// points to an existing database), and reports results to stdout.
// Exit 0 = no errors; 1 = errors found; 2 = usage error.
{ v0.47: the RAD Studio msbuild dcc wrapper prints findings RELATIVE to the
  project directory and emits each one TWICE (inline + the summary block). Make
  paths absolute (so the IDE can match an open buffer) and de-duplicate. }
function NormalizeFindings(const AFindings: TArray<TCompilerFinding>; const ABaseDir: string): TArray<TCompilerFinding>;
var
  Seen: TDictionary<string, Boolean>;
  Acc : TList<TCompilerFinding>     ;
  F   : TCompilerFinding            ;
  Rec : TCompilerFinding            ;
  Key : string                      ;
  P   : string                      ;
begin
  Seen:= TDictionary<string, Boolean>.Create;
  Acc:= TList<TCompilerFinding>.Create;
  try
    for F in AFindings do
    begin
      Rec:= F; { F is the for-in loop var (read-only) -- mutate a copy }
      P:= Rec.RawPath;
      if (P <> '') and (ABaseDir <> '') and (not TPath.IsPathRooted(P)) then
      try P:= TPath.GetFullPath(TPath.Combine(ABaseDir, P)); except end;
      Rec.RawPath:= P;
      { msbuild appends " [<full>\<project>.dproj]" to every message -- strip ONLY
        that trailing project-file reference, not a legitimate bracketed tail such
        as "[WEAKPACKAGEUNIT]" (over-stripping would also corrupt the dedup key). }
      Rec.Message:= TRegEx.Replace(Rec.Message, '\s*\[[^\]]*\.(?:dproj|dpk|dpr|proj)\]\s*$', '', [roIgnoreCase]);
      Key:= LowerCase(P) + '|' + IntToStr(Rec.LineNo) + '|' + Rec.Code + '|' + Rec.Message;
      if not Seen.ContainsKey(Key) then
      begin
        Seen.Add(Key, True);
        Acc.Add(Rec);
      end;
    end;
    Result:= Acc.ToArray;
  finally
    Acc.Free;
    Seen.Free;
  end; // try
end; // function

function DoCompileCheck(const AArgs: TArgs): Integer;
var
  Target   : string             ;
  Store    : ISymbolStore       ;
  Res      : TCompileCheckResult;
  ErrCount : Integer            ;
  WarnCount: Integer            ;
  HintCount: Integer            ;
  F        : TCompilerFinding   ;
  Fmt      : string             ;
  Sb       : TStringBuilder     ;
  FilePath : string             ;
begin
  Target:= AArgs.Target;
  if Target = '' then Target:= AArgs.QName; // fallback: --qname used as target
  if Target = '' then
  begin
    Writeln('Usage: drag-lint compile-check <target.dproj or target.pas> ' + '[--db PATH] [--format json|text]');
    Exit(2);
  end;

  Writeln('Compiling: ', Target);
  Res:= TCompileChecker.Run(Target);
  { v0.47: absolutize relative paths + drop msbuild's duplicate lines. }
  Res.Findings:= NormalizeFindings(Res.Findings, ExtractFilePath(Target));

  ErrCount:= 0; WarnCount:= 0; HintCount:= 0;
  for F in Res.Findings do
  begin
    if SameText(F.Severity, 'Error') then Inc(ErrCount)
    else if SameText(F.Severity, 'Warning') then Inc(WarnCount)
    else if SameText(F.Severity, 'Hint') then Inc(HintCount);
  end;

  if TFile.Exists(AArgs.DbPath) then
  begin
    Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
    Store.Migrate;
    TCompileChecker.InsertFindings(Store, Res.Findings);
  end;

  Fmt:= LowerCase(AArgs.Format);

  if Fmt = 'json' then
  begin
    Sb:= TStringBuilder.Create;
    try
      Sb.Append('[');
      var First:= True;
      for F in Res.Findings do
      begin
        if not First then Sb.Append(',');
        First:= False;
        FilePath:= F.RawPath;
        Sb.Append(Format(
            '{"file":"%s","line":%d,"col":%d,' + '"severity":"%s","code":"%s","message":"%s"}',
            [JsonEscape(FilePath), F.LineNo, F.ColNo, JsonEscape(F.Severity), JsonEscape(F.Code), JsonEscape(F.Message)]));
      end;
      Sb.Append(']');
      Writeln(Sb.ToString);
    finally
      Sb.Free;
    end; // try
  end // if
  else
  begin
    for F in Res.Findings do Writeln(Format('%s(%d,%d): %s %s: %s', [F.RawPath, F.LineNo, F.ColNo, F.Severity, F.Code, F.Message]));
    Writeln(Format('Findings: %d errors, %d warnings, %d hints', [ErrCount, WarnCount, HintCount]));
  end;

  if ErrCount > 0 then Result:= 1
  else Result:= 0;
end; // function

{ Resolve <unit>.dcu inside the project's DCU output dir (DCC_DcuOutput in the
  .dproj, with $(Platform)/$(Config) expanded) so ghost-check can delete it and
  force a recompile. Best-effort; '' if it cannot be determined. }
function ResolveGhostDcu(const ADproj, AUnit, APlatform: string): string;
var
  Content: string;
  DcuOut : string;
  Plat   : string;
  M      : TMatch;
begin
  Result:= '';
  Plat  := APlatform;
  if Plat = '' then Plat:= 'Win64';
  DcuOut:= '.\' + Plat + '\Debug\DCU';
  try
    Content:= TFile.ReadAllText(ADproj);
    M:= TRegEx.Match(Content, '<DCC_DcuOutput>(.*?)</DCC_DcuOutput>', [roIgnoreCase, roSingleLine]);
    if M.Success and (Trim(M.Groups[1].Value) <> '') then DcuOut:= Trim(M.Groups[1].Value);
  except
  end;
  DcuOut:= StringReplace(DcuOut, '$(Platform)', Plat   , [rfReplaceAll, rfIgnoreCase]);
  DcuOut:= StringReplace(DcuOut, '$(Config)'  , 'Debug', [rfReplaceAll, rfIgnoreCase]);
  if not TPath.IsPathRooted(DcuOut) then
  try DcuOut:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ADproj), DcuOut)); except end;
  Result:= TPath.Combine(DcuOut, ChangeFileExt(ExtractFileName(AUnit), '.dcu'));
end; // function

{ v0.47: ensure a hidden "_D-RAG" working folder exists (like the IDE's _history
  / _recovery). Holds ghost-check crash-recovery journals. }
function GhostDir(const ADproj: string): string;
var
  Attrs: Cardinal;
begin
  Result:= TPath.Combine(ExtractFilePath(ADproj), '_D-RAG');
  try
    if not TDirectory.Exists(Result) then TDirectory.CreateDirectory(Result);
    Attrs:= GetFileAttributes(PChar(Result));
    if Attrs <> INVALID_FILE_ATTRIBUTES then SetFileAttributes(PChar(Result), Attrs or FILE_ATTRIBUTE_HIDDEN);
  except
  end;
end;

{ Byte-exact buffer compare (dependency-free; files here are small). Used by
  ghost-check to decide whether its overlay is still on disk before restoring. }
function BytesSame(const A, B: TBytes): Boolean;
var
  i: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  for i:= 0 to High(A) do
    if A[i] <> B[i] then Exit(False);
  Result:= True;
end;

{ Raw last-write FILETIME read/write (100ns ticks). ghost-check restores the
  EXACT original timestamp this way -- a TDateTime round-trip would lose
  sub-second precision and the IDE's "changed on disk" check could then fire. }
function FileTimeToI64(const AFT: TFileTime): Int64;
begin
  Result:= (Int64(AFT.dwHighDateTime) shl 32) or Int64(Cardinal(AFT.dwLowDateTime));
end;

function I64ToFileTime(const AValue: Int64): TFileTime;
begin
  Result.dwLowDateTime:= Cardinal(AValue and $FFFFFFFF);
  Result.dwHighDateTime:= Cardinal((AValue shr 32) and $FFFFFFFF);
end;

function ReadFileWriteTime(const APath: string; out AFT: TFileTime): Boolean;
var
  H: THandle;
begin
  Result:= False;
  H:= CreateFile(PChar(APath), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try Result:= GetFileTime(H, nil, nil, @AFT); finally CloseHandle(H); end;
end;

function SetFileWriteTime(const APath: string; const AFT: TFileTime): Boolean;
var
  H: THandle;
begin
  Result:= False;
  H:= CreateFile(PChar(APath), FILE_WRITE_ATTRIBUTES, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try Result:= SetFileTime(H, nil, nil, @AFT); finally CloseHandle(H); end;
end;

type { v0.48: one unsaved file to overlay during a ghost-check (a .pas now; a .dfm in
    a later phase). Carries everything needed to restore it EXACTLY afterwards. }
  TGhostOverlay = record
    RealPath : string   ; { the real file we briefly overwrite }
    BufPath  : string   ; { temp file holding the unsaved buffer }
    DcuPath  : string   ; { stale .dcu to drop (forces recompile); '' if none }
    OrigBak  : string   ; { _D-RAG\<name>.ghost-orig (crash backup) }
    Journal  : string   ; { _D-RAG\<name>.ghost-journal }
    OrigBytes: TBytes   ;
    BufBytes : TBytes   ;
    OrigMtime: TDateTime;
    OrigFT   : TFileTime;
    HaveFT   : Boolean  ;
  end;

  { Apply one overlay: write the crash-recovery journal, overlay the buffer, stamp a
  CURRENT mtime so the incremental compiler rebuilds the unit, and drop the stale
  .dcu. Best-effort; GhostRestoreOverlay is the guarantee. }
procedure GhostApplyOverlay(const E: TGhostOverlay);
var
  JournalText: string;
begin
  try
    TFile.WriteAllBytes(E.OrigBak, E.OrigBytes);
    JournalText:= 'unit=' + E.RealPath + sLineBreak + 'orig=' + E.OrigBak + sLineBreak +
    'mtime=' + FloatToStrF(Double(E.OrigMtime), ffGeneral, 17, 0, TFormatSettings.Invariant) + sLineBreak;
    if E.HaveFT then JournalText:= JournalText + 'ft=' + IntToStr(FileTimeToI64(E.OrigFT)) + sLineBreak;
    TFile.WriteAllText(E.Journal, JournalText);
  except end;
  TFile.WriteAllBytes(E.RealPath, E.BufBytes);
  try TFile.SetLastWriteTime(E.RealPath, Now); except end;
  if (E.DcuPath <> '') and TFile.Exists(E.DcuPath) then
  try TFile.Delete(E.DcuPath); except end;
end; // procedure

{ Restore one overlay: put the original content + EXACT timestamp back (verified),
  never clobbering a concurrent external save; drop the buffer-built .dcu; clear
  the journal ONLY if the restore is provable (else keep it so ghost-recover can
  finish on next startup). }
procedure GhostRestoreOverlay(const E: TGhostOverlay);
var
  CurBytes   : TBytes ;
  RestoreDone: Boolean;
begin
  RestoreDone:= False;
  try
    CurBytes:= TFile.ReadAllBytes(E.RealPath);
    if BytesSame(CurBytes, E.OrigBytes) or BytesSame(CurBytes, E.BufBytes) then
    begin
      { disk holds our overlay (or already-original content) -> normalize back to
        the saved original: rewrite content only if needed, but ALWAYS restore the
        ORIGINAL timestamp (the overlay stamped 'Now' to force the rebuild), VERIFY. }
      if not BytesSame(CurBytes, E.OrigBytes) then TFile.WriteAllBytes(E.RealPath, E.OrigBytes);
      if not (E.HaveFT and SetFileWriteTime(E.RealPath, E.OrigFT)) then
      try TFile.SetLastWriteTime(E.RealPath, E.OrigMtime); except end;
      try RestoreDone:= BytesSame(TFile.ReadAllBytes(E.RealPath), E.OrigBytes);
      except RestoreDone:= False; end;
    end
    else
    begin
      { changed by something else (e.g. an IDE save) during the window -- that is
        the user's content, not our overlay. Leave it. }
      RestoreDone:= True;
      Writeln('ghost-check: NOTE -- ', E.RealPath, ' changed externally during the check; left as-is.');
    end;
  except
    RestoreDone:= False;
  end; // try
  if (E.DcuPath <> '') and TFile.Exists(E.DcuPath) then
  try TFile.Delete(E.DcuPath); except end;
  if RestoreDone then
  begin
    try if TFile.Exists(E.Journal) then TFile.Delete(E.Journal); except end;
    try if TFile.Exists(E.OrigBak) then TFile.Delete(E.OrigBak); except end;
  end
  else Writeln('ghost-check: WARNING -- could not safely restore ', E.RealPath, '; recovery journal kept (run ghost-recover or restart the IDE).');
end; // procedure

{ v0.48: ghost-check -- compile the project with one or more units' content
  replaced by their UNSAVED buffers, WITHOUT a lasting change to any file. Each
  overlay is stamped with a current mtime to force its recompile, the project is
  compiled ONCE, then EVERY file is restored to its original content + EXACT
  timestamp (verified, crash-journaled in _D-RAG). Overlays come from --overlays
  <manifest> ('realpath'<TAB>'bufferpath' per line) or a single --unit/--buffer. }
function DoGhostCheck(const AArgs: TArgs): Integer;
var
  Dproj        : string              ;
  Fmt          : string              ;
  FilePath     : string              ;
  DragDir      : string              ;
  Ln           : string              ;
  Entries      : TList<TGhostOverlay>;
  E            : TGhostOverlay       ;
  ManifestLines: TArray<string>      ;
  Parts        : TArray<string>      ;
  Res          : TCompileCheckResult ;
  ErrCount     : Integer             ;
  WarnCount    : Integer             ;
  HintCount    : Integer             ;
  i            : Integer             ;
  F            : TCompilerFinding    ;
  Sb           : TStringBuilder      ;
const
  USAGE = 'Usage: drag-lint ghost-check <dproj> ( --unit <real.pas> --buffer <buf>' + ' | --overlays <manifest> ) [--platform win32|win64] [--format json|text]';
begin
  Dproj:= AArgs.Target;
  if Dproj = '' then begin Writeln(USAGE); Exit(2); end;

  Entries:= TList<TGhostOverlay>.Create;
  try
    DragDir:= GhostDir(Dproj);

    { Build the overlay list from a manifest, or a single --unit/--buffer pair. }
    if AArgs.GhostOverlays <> '' then
    begin
      if not TFile.Exists(AArgs.GhostOverlays) then
      begin Writeln('ERROR: overlays manifest not found: ', AArgs.GhostOverlays); Exit(2); end;
      try ManifestLines:= TFile.ReadAllLines(AArgs.GhostOverlays);
      except SetLength(ManifestLines, 0); end;
      for Ln in ManifestLines do
      begin
        if Trim(Ln) = '' then Continue;
        Parts:= Ln.Split([#9]);
        if Length(Parts) < 2 then Continue;
        E:= Default(TGhostOverlay);
        E.RealPath:= Parts[0];
        E.BufPath := Parts[1];
        Entries.Add(E);
      end;
    end // if
    else if (AArgs.GhostUnit <> '') and (AArgs.GhostBuffer <> '') then
    begin
      E:= Default(TGhostOverlay);
      E.RealPath:= AArgs.GhostUnit;
      E.BufPath := AArgs.GhostBuffer;
      Entries.Add(E);
    end
    else
    begin Writeln(USAGE); Exit(2); end;

    { Load + validate each entry (drop any whose files are missing). }
    for i:= Entries.Count - 1 downto 0 do
    begin
      E:= Entries[i];
      if (not TFile.Exists(E.RealPath)) or (not TFile.Exists(E.BufPath)) then
      begin
        Writeln('ghost-check: skip (missing): ', E.RealPath);
        Entries.Delete(i);
        Continue;
      end;
      E.OrigBytes:= TFile.ReadAllBytes    (E.RealPath);
      E.OrigMtime:= TFile.GetLastWriteTime(E.RealPath);
      E.HaveFT:= ReadFileWriteTime(E.RealPath, E.OrigFT);
      E.BufBytes:= TFile.ReadAllBytes(E.BufPath);
      E.OrigBak:= TPath.Combine(DragDir, ExtractFileName(E.RealPath) + '.ghost-orig'   );
      E.Journal:= TPath.Combine(DragDir, ExtractFileName(E.RealPath) + '.ghost-journal');
      if SameText(ExtractFileExt(E.RealPath), '.pas') then E.DcuPath:= ResolveGhostDcu(Dproj, E.RealPath, AArgs.CheckPlatform)
      else E.DcuPath:= '';
      Entries[i]:= E;
    end; // for

    if Entries.Count = 0 then
    begin Writeln('ghost-check: nothing to overlay.'); Exit(2); end;

    Res:= Default(TCompileCheckResult);
    try
      for E in Entries do GhostApplyOverlay(E);
      Res:= TCompileChecker.Run(Dproj);
      Res.Findings:= NormalizeFindings(Res.Findings, ExtractFilePath(Dproj));
    finally
      { ALWAYS restore EVERY overlaid file (each independently hardened). }
      for E in Entries do GhostRestoreOverlay(E);
    end;

    ErrCount:= 0; WarnCount:= 0; HintCount:= 0;
    for F in Res.Findings do
      if SameText(F.Severity, 'Error') then Inc(ErrCount)
    else if SameText(F.Severity, 'Warning') then Inc(WarnCount)
    else if SameText(F.Severity, 'Hint') then Inc(HintCount);

    Fmt:= LowerCase(AArgs.Format);
    if Fmt = 'json' then
    begin
      Sb:= TStringBuilder.Create;
      try
        Sb.Append('[');
        var First:= True;
        for F in Res.Findings do
        begin
          if not First then Sb.Append(',');
          First:= False;
          FilePath:= F.RawPath;
          Sb.Append(Format(
              '{"file":"%s","line":%d,"col":%d,' + '"severity":"%s","code":"%s","message":"%s"}',
              [JsonEscape(FilePath), F.LineNo, F.ColNo, JsonEscape(F.Severity), JsonEscape(F.Code), JsonEscape(F.Message)]));
        end;
        Sb.Append(']');
        Writeln(Sb.ToString);
      finally
        Sb.Free;
      end; // try
    end // if
    else
    begin
      for F in Res.Findings do Writeln(Format('%s(%d,%d): %s %s: %s', [F.RawPath, F.LineNo, F.ColNo, F.Severity, F.Code, F.Message]));
      Writeln(Format('Findings: %d errors, %d warnings, %d hints', [ErrCount, WarnCount, HintCount]));
    end;

    if ErrCount > 0 then Result:= 1 else Result:= 0;
  finally
    Entries.Free;
  end; // try
end; // function

{ v0.47: ghost-recover -- on IDE startup, scan a project's hidden _D-RAG folder
  for ghost-check journals left by a crash mid-overlay and put the file back. To
  lose NOTHING without a prompt, the crash-time content (current on disk) is first
  copied to _D-RAG\<unit>.crash-buffer, THEN the saved original is restored. }
function DoGhostRecover(const AArgs: TArgs): Integer;
var
  Root     : string        ;
  DragDir  : string        ;
  J        : string        ;
  UnitPath : string        ;
  OrigBak  : string        ;
  MtimeStr : string        ;
  FtStr    : string        ;
  CrashBuf : string        ;
  Ln       : string        ;
  Journals : TArray<string>;
  Lines    : TArray<string>;
  Recovered: Integer       ;
  FtVal    : Int64         ;
begin
  Root:= AArgs.Target;
  if Root = '' then Root:= AArgs.Path;
  if Root = '' then Root:= GetCurrentDir;
  if SameText(ExtractFileExt(Root), '.dproj') then Root:= ExtractFilePath(Root);
  DragDir:= TPath.Combine(Root, '_D-RAG');
  Recovered:= 0;
  if not TDirectory.Exists(DragDir) then
  begin
    Writeln('ghost-recover: nothing pending.');
    Exit   (0                                );
  end;
  try
    Journals:= TDirectory.GetFiles(DragDir, '*.ghost-journal');
  except
    SetLength(Journals, 0);
  end;
  for J in Journals do
  begin
    UnitPath:= ''; OrigBak:= ''; MtimeStr:= ''; FtStr:= '';
    try
      Lines:= TFile.ReadAllLines(J);
      for Ln in Lines do
        if Ln.StartsWith('unit=') then UnitPath:= Copy(Ln, 6, MaxInt)
      else if Ln.StartsWith('orig=' ) then OrigBak := Copy(Ln, 6, MaxInt)
      else if Ln.StartsWith('mtime=') then MtimeStr:= Copy(Ln, 7, MaxInt)
      else if Ln.StartsWith('ft=') then FtStr:= Copy(Ln, 4, MaxInt);
    except end;
    if (UnitPath <> '') and (OrigBak <> '') and TFile.Exists(OrigBak) and TFile.Exists(UnitPath) then
    begin
      try
        { keep the crash-time content so nothing is ever lost }
        CrashBuf:= TPath.Combine(DragDir, ExtractFileName(UnitPath) + '.crash-buffer');
        try TFile.Copy(UnitPath, CrashBuf, True); except end;
        { restore the saved original + mtime (prefer the exact FILETIME) }
        TFile.Copy(OrigBak, UnitPath, True);
        if (FtStr <> '') and TryStrToInt64(FtStr, FtVal) then
        begin
          if not SetFileWriteTime(UnitPath, I64ToFileTime(FtVal)) then
            if MtimeStr <> '' then
            try TFile.SetLastWriteTime(UnitPath, TDateTime(StrToFloat(MtimeStr, TFormatSettings.Invariant))); except end;
        end
        else if MtimeStr <> '' then
        try TFile.SetLastWriteTime(UnitPath, TDateTime(StrToFloat(MtimeStr, TFormatSettings.Invariant))); except end;
        try TFile.Delete(OrigBak); except end;
        try TFile.Delete(J); except end;
        Inc(Recovered);
        Writeln('Recovered ', UnitPath, ' (crash content kept at ', CrashBuf, ')');
      except
        Writeln('FAILED to recover ', UnitPath);
      end; // try
    end // if
    else
    begin
      { stale/incomplete journal -> drop it }
      try TFile.Delete(J); except end;
      try if (OrigBak <> '') and TFile.Exists(OrigBak) then TFile.Delete(OrigBak); except end;
    end;
  end; // for
  Writeln(Format('ghost-recover: %d file(s) restored.', [Recovered]));
  Result:= 0;
end; // function

{ ====================================================================== }
{ v0.43: check-unit -- in-memory semantic check of one unit               }
{ ====================================================================== }

type
  TUsesSuggestion = record
    Found   : Boolean;
    UnitName: string ;
    Usable  : Boolean; { symbol is in the unit's interface -> addable via uses }
  end;

  // Given an undeclared identifier, find the best unit to add to the uses clause
  // (interface-visible, not already imported, project before library). Reuses the
  // same ranking idea as resolve-uses, distilled to the single best hit.
function SuggestUnitForSymbol(const AStore: ISymbolStore; const AName, AInFile: string): TUsesSuggestion;
var
  Syms       : TArray<TSymbol>             ;
  S          : TSymbol                     ;
  UsedUnits  : TDictionary<string, Boolean>;
  InFileId   : Int64                       ;
  U          : TUnitUse                    ;
  FilePath   : string                      ;
  UnitName   : string                      ;
  LP         : string                      ;
  Usable     : Boolean                     ;
  AlreadyUsed: Boolean                     ;
  IsLib      : Boolean                     ;
  Score      : Integer                     ;
  BestScore  : Integer                     ;
begin
  Result:= Default(TUsesSuggestion);
  Syms:= AStore.FindSymbolsByExactName(AName);
  if Length(Syms) = 0 then Exit;

  UsedUnits:= TDictionary<string, Boolean>.Create;
  try
    if AInFile <> '' then
    begin
      InFileId:= AStore.FindFileIdByPath(TPath.GetFullPath(AInFile));
      if InFileId <= 0 then InFileId:= AStore.FindFileIdByPath(AInFile);
      if InFileId > 0 then
        for U in AStore.GetUnitUsesForFile(InFileId) do UsedUnits.AddOrSetValue(LowerCase(U.UnitName), True);
    end;

    BestScore:= -1;
    for S in Syms do
    begin
      FilePath:= AStore.GetFilePath(S.FileId);
      UnitName:= ChangeFileExt(ExtractFileName(FilePath), '');
      if UnitName = '' then Continue;
      Usable:= S.Section <> 'implementation';
      AlreadyUsed:= UsedUnits.ContainsKey(LowerCase(UnitName));
      LP:= LowerCase(FilePath);
      IsLib:= (Pos('\embarcadero\', LP) > 0) or (Pos('\program files', LP) > 0);

      Score:= 0;
      if Usable then Inc(Score, 10000);
      if not AlreadyUsed then Inc(Score, 1000);
      if not IsLib       then Inc(Score, 100 );
      if Score > BestScore then
      begin
        BestScore:= Score;
        Result.Found   := True;
        Result.UnitName:= UnitName;
        Result.Usable  := Usable;
      end;
    end; // for
  finally
    UsedUnits.Free;
  end; // try
end; // function

// Read DCC_Namespace from a .dproj (so dotted-down 'uses Forms' etc. resolve),
// falling back to a broad default covering the common RTL/VCL roots.
function ReadDccNamespaces(const ADprojPath: string): string;
const
  DEFAULT_NS = 'System;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win;Vcl;' + 'Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell;Data.Win;Bde;FireDAC';
var
  Content: string;
  M      : TMatch;
begin
  Result:= DEFAULT_NS;
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then Exit;
  try
    Content:= TFile.ReadAllText(ADprojPath);
  except
    Exit;
  end;
  M:= TRegEx.Match(Content, '<DCC_Namespace>(.*?)</DCC_Namespace>', [roIgnoreCase, roSingleLine]);
  if M.Success then
  begin
    var NS: string:= M.Groups[1].Value;
    NS:= StringReplace(NS, '$(DCC_Namespace)', DEFAULT_NS, [rfReplaceAll, rfIgnoreCase]);
    NS:= Trim(NS);
    if NS <> '' then Result:= NS;
  end;
end; // function

// v0.43: drag-lint check-unit <unit.pas> [--project <dproj>] [--shadow <dir>]
//        [--resolve-uses] [--db <sqlite>] [--format json|text]
// Compiles ONE unit in full project context (single-unit dcc, deps from DCUs)
// and reports findings FOR THAT UNIT. With --shadow, the unit is read from the
// shadow dir (an overlay of the unsaved editor buffer) so errors reflect edits
// that are not yet saved -- without touching the real file. With --resolve-uses,
// each "Undeclared identifier" error is annotated with the unit to add.
function DoCheckUnit(const AArgs: TArgs): Integer;
var
  Resolver     : DRagLint.Project.Resolver.TProjectResolver;
  Folders      : TArray<string>                            ;
  P            : string                                    ;
  UPath        : string                                    ;
  Namespaces   : string                                    ;
  CompileTarget: string                                    ;
  TargetBase   : string                                    ;
  TmpRoot      : string                                    ;
  CfgDir       : string                                    ;
  DcuDir       : string                                    ;
  RsVars       : string                                    ;
  Cmd          : string                                    ;
  Disp         : string                                    ;
  Ident        : string                                    ;
  Note         : string                                    ;
  Res          : TCompileCheckResult                       ;
  Store        : ISymbolStore                              ;
  HasStore     : Boolean                                   ;
  Sb           : TStringBuilder                            ;
  First        : Boolean                                   ;
  F            : TCompilerFinding                          ;
  ErrCount     : Integer                                   ;
  WarnCount    : Integer                                   ;
  Sug          : TUsesSuggestion                           ;
  MID          : TMatch                                    ;
  Keep         : Boolean                                   ;
begin
  if AArgs.Target = '' then
  begin
    Writeln('Usage: drag-lint check-unit <unit.pas> [--project <dproj>] ' + '[--shadow <dir>] [--resolve-uses] [--db <sqlite>] [--format json|text]');
    Exit(2);
  end;

  TargetBase:= ExtractFileName(AArgs.Target);

  { 1. search path: the project's folders (incl. library + DCU output) or, with
       no project, just the IDE library paths. }
  Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    if AArgs.ProjectPath <> '' then Folders:= Resolver.Resolve(AArgs.ProjectPath)
    else Folders:= Resolver.ResolveLibraryPaths;
  finally
    Resolver.Free;
  end;

  { 2. which file to compile: the shadow (unsaved) copy if given, else the real }
  if AArgs.Shadow <> '' then CompileTarget:= TPath.Combine(AArgs.Shadow, TargetBase)
  else CompileTarget:= AArgs.Target;

  { 3. platform. The compiler + DCUs MUST match the project's active platform:
       a Win32 System.dcu first on the path for a dcc64 compile triggers F2048
       (bad unit format). So we pick dcc32/dcc64 to match, prepend that
       platform's RTL lib, and drop the OTHER platform's DCU/lib/dcp dirs. The
       plugin passes --platform from the project's active config; default win64
       (ORM3 client + server). }
  var Plat: string:= LowerCase(AArgs.CheckPlatform);
  if (Plat <> 'win32') and (Plat <> 'win64') then Plat:= 'win64';

  var DccExe  : string:= IfThen(Plat = 'win32', 'dcc32'  , 'dcc64'  );
  var PlatDir : string:= IfThen(Plat = 'win32', 'Win32'  , 'Win64'  );
  var WrongDir: string:= IfThen(Plat = 'win32', '\win64\', '\win32\');

  var BdsDir: string:= GetEnvironmentVariable('BDS');
  if BdsDir = '' then BdsDir:= 'C:\Program Files (x86)\Embarcadero\Studio\37.0';
  var LibRelease: string:= TPath.Combine(BdsDir, 'lib\' + PlatDir + '\release');

  { unit search path -- shadow first so the unsaved overlay wins }
  UPath:= '';
  if AArgs.Shadow <> '' then UPath:= AArgs.Shadow;
  if TDirectory.Exists(LibRelease) then
    if UPath = '' then UPath:= LibRelease else UPath:= UPath + ';' + LibRelease;
  { compile against precompiled DCUs only: drop the wrong platform AND any RTL/VCL
    SOURCE dir under the IDE install. The registry Browsing path contributes
    <BDS>\source\... entries; with those on -U, dcc recompiles e.g.
    System.Variants from source against the already-loaded System.dcu and dies
    with E2158 'unit out of date or corrupted' BEFORE it ever reaches the target
    unit -- so no real finding is ever reported. Project + Library (DCU) paths are
    kept (the project's own \Source\ stays, as it lives outside <BDS>). }
  var BdsSrc: string:= LowerCase(IncludeTrailingPathDelimiter(BdsDir) + 'source');
  for P in Folders do
    if (P <> '') and (Pos(WrongDir, LowerCase(P)) = 0) and (Pos(BdsSrc, LowerCase(P)) = 0) then
      if UPath = '' then UPath:= P else UPath:= UPath + ';' + P;

  Namespaces:= ReadDccNamespaces(AArgs.ProjectPath);

  { 4. write a dcc64.cfg (avoids the ~8 KB command-line limit on the path list)
       in a temp dir, and run dcc64 there so it auto-reads the cfg. }
  TmpRoot:= TPath.Combine(TPath.GetTempPath, 'draglint_checkunit');
  CfgDir:= TPath.Combine(TmpRoot, 'cfg');
  DcuDir:= TPath.Combine(TmpRoot, 'dcu');
  TDirectory.CreateDirectory(CfgDir);
  TDirectory.CreateDirectory(DcuDir);
  { dcc reads <compiler>.cfg from its working dir, so name the cfg to match }
  TFile.WriteAllText(TPath.Combine(CfgDir, DccExe + '.cfg'), Format('-U"%s"'#13#10'-NS%s'#13#10'-NU"%s"'#13#10'-Q'#13#10, [UPath, Namespaces, DcuDir]));

  RsVars:= 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat';
  Cmd:= Format('cmd.exe /c "call "%s" && cd /d "%s" && %s "%s" 2>&1"', [RsVars, CfgDir, DccExe, CompileTarget]);

  Res:= TCompileChecker.RunCommand(Cmd);

  if GetEnvironmentVariable('DRAGLINT_DEBUG') <> '' then
  begin
    Writeln(ErrOutput, '[check-unit] CMD: ' + Cmd);
    Writeln(ErrOutput, '[check-unit] EXIT: ' + IntToStr(Res.ExitCode));
    Writeln(ErrOutput, '[check-unit] RAW OUTPUT >>>');
    Writeln(ErrOutput, Res.StdoutText);
    Writeln(ErrOutput, '[check-unit] <<< END, findings=' + IntToStr(Length(Res.Findings)));
  end;

  { open the index only if --resolve-uses asked AND the db exists }
  HasStore:= AArgs.ResolveUsesFlag and TFile.Exists(AArgs.DbPath);
  if HasStore then
  begin
    Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
    Store.Migrate;
  end;

  ErrCount:= 0; WarnCount:= 0;
  Sb:= TStringBuilder.Create;
  try
    Sb.Append('[');
    First:= True;
    for F in Res.Findings do
    begin
      { keep only findings for the target unit (deps compile silently from DCUs,
        but be defensive about path/basename). }
      Keep:= SameText(ExtractFileName(F.RawPath), TargetBase);
      if not Keep then Continue;

      if SameText(F.Severity, 'Error') then Inc(ErrCount)
      else if SameText(F.Severity, 'Warning') then Inc(WarnCount);

      { map the shadow path back to the real unit for display }
      Disp:= AArgs.Target;

      { missing-unit annotation for undeclared identifiers }
      Note:= '';
      var AddUnit: string:= ''; { v0.46: dedicated field for the IDE quick-fix }
      if HasStore and SameText(F.Code, 'E2003') then
      begin
        MID:= TRegEx.Match(F.Message, '''([A-Za-z_][A-Za-z0-9_]*)''');
        if MID.Success then
        begin
          Ident:= MID.Groups[1].Value;
          Sug:= SuggestUnitForSymbol(Store, Ident, AArgs.Target);
          if Sug.Found and Sug.Usable then
          begin
            AddUnit:= Sug.UnitName;
            Note:= Format(' -- add unit %s to the uses clause', [Sug.UnitName]);
          end;
        end;
      end;

      if not First then Sb.Append(',');
      First:= False;
      Sb.Append(Format(
          '{"file":"%s","line":%d,"col":%d,"severity":"%s","code":"%s",' + '"message":"%s","fix":"%s","addUnit":"%s"}',
          [JsonEscape(Disp), F.LineNo, F.ColNo, JsonEscape(F.Severity), JsonEscape(F.Code), JsonEscape(F.Message + Note), JsonEscape(Note), JsonEscape(AddUnit)]));
    end; // for
    Sb.Append(']');

    if SameText(AArgs.Format, 'json') then Writeln(Sb.ToString)
    else
    begin
      for F in Res.Findings do
        if SameText(ExtractFileName(F.RawPath), TargetBase) then Writeln(Format('%s(%d): %s %s: %s', [AArgs.Target, F.LineNo, F.Severity, F.Code, F.Message]));
      Writeln(Format('-- %d error(s), %d warning(s) in %s', [ErrCount, WarnCount, TargetBase]));
    end;
  finally
    Sb.Free;
  end; // try

  if ErrCount > 0 then Result:= 1 else Result:= 0;
end; // function

// v0.43: drag-lint cycles --db <sqlite> [--edges] [--format json|text]
// Reports circular unit dependencies (strongly-connected components of the
// unit-uses graph). These all compile (a pure interface cycle is illegal F2047,
// broken here by an implementation back-edge); we flag cycles that carry
// interface coupling (widest recompile blast radius) and, with --edges, list
// the actual uses edges + move-to-implementation candidates + layering
// inversions (e.g. COMMON -> CLIENT) so you can see exactly which line to cut.
function DoCycles(const AArgs: TArgs): Integer;
type
  TEdgeSet = TDictionary<string, Boolean>;
var
  Store    : ISymbolStore                      ;
  FilePath : string                            ;
  Adj      : TDictionary<string, TList<string>>; { unit -> used units (lower) }
  IntfEdges: TEdgeSet                          ; { "a->b" if a uses b in intf }
  UnitFile : TDictionary<string, string>       ; { unit stem -> source path }
  UnitFid  : TDictionary<string, Int64>        ; { unit stem -> file_id (--causes) }
  // Tarjan state
  Index  : TDictionary<string, Integer>;
  Lowlink: TDictionary<string, Integer>;
  OnStack: TDictionary<string, Boolean>;
  Stack  : TList<string>               ;
  Counter: Integer                     ;
  Sccs   : TList<TArray<string>>       ;
  JArr   : TJSONArray                  ;
  i      : Integer                     ;

  function UnitNameOfFile(const APath: string): string;
  var
    S: string;
  begin
    { indexed paths may use '/' -- normalise so ExtractFileName strips the dir }
    S:= StringReplace(APath, '/', '\', [rfReplaceAll]);
    Result:= LowerCase(ChangeFileExt(ExtractFileName(S), ''));
  end;

{ coarse layer from the path so we can flag inverted dependencies }
  function LayerOf(const APath: string): string;
  var
    L: string;
  begin
    L:= LowerCase(APath);
    if Pos('\common\', L) > 0 then Result:= 'COMMON'
    else if Pos('\client\', L) > 0 then Result:= 'CLIENT'
    else if Pos('\server\', L) > 0 then Result:= 'SERVER'
    else Result:= '';
  end;

  procedure StrongConnect(const AV: string);
  var
    W        : string       ;
    Comp     : TList<string>;
    Top      : string       ;
    Neighbors: TList<string>;
  begin
    Index  .AddOrSetValue(AV, Counter);
    Lowlink.AddOrSetValue(AV, Counter);
    Inc(Counter);
    Stack.Add(AV);
    OnStack.AddOrSetValue(AV, True);

    if Adj.TryGetValue(AV, Neighbors) then
      for W in Neighbors do
      begin
        if not Index.ContainsKey(W) then
        begin
          if Adj.ContainsKey(W) then StrongConnect(W)
          else
          begin
            { external/library unit -- a leaf, cannot be part of a cycle }
            Continue;
          end;
          if Lowlink[W] < Lowlink[AV] then Lowlink[AV]:= Lowlink[W];
        end
        else if OnStack.ContainsKey(W) and OnStack[W] then
          if Index[W] < Lowlink[AV] then Lowlink[AV]:= Index[W];
      end;

    if Lowlink[AV] = Index[AV] then
    begin
      Comp:= TList<string>.Create;
      repeat
        Top:= Stack[Stack.Count - 1];
        Stack.Delete(Stack.Count - 1);
        OnStack.AddOrSetValue(Top, False);
        Comp.Add(Top);
      until Top = AV;
      if Comp.Count > 1 then Sccs.Add(Comp.ToArray);
      Comp.Free;
    end;
  end; // procedure

var
  UU   : TArray<TUnitUse>;
  Uo   : TUnitUse        ;
  FId  : Int64           ;
  UFrom: string          ;
  UTo  : string          ;
  Key  : string          ;
  K    : string          ;
  L    : TList<string>   ;
begin
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  Adj:= TDictionary<string, TList<string>>.Create;
  IntfEdges:= TEdgeSet.Create;
  UnitFile:= TDictionary<string, string>.Create;
  UnitFid:= TDictionary<string, Int64  >.Create;
  Index  := TDictionary<string, Integer>.Create;
  Lowlink:= TDictionary<string, Integer>.Create;
  OnStack:= TDictionary<string, Boolean>.Create;
  Stack:= TList<string>.Create;
  Sccs:= TList<TArray<string>>.Create;
  try
    { build the adjacency from every indexed file's uses clauses }
    for FId in Store.GetAllFileIds do
    begin
      FilePath:= Store.GetFilePath(FId);
      if not SameText(ExtractFileExt(FilePath), '.pas') then Continue;
      UFrom:= UnitNameOfFile(FilePath);
      if UFrom = '' then Continue;
      UnitFile.AddOrSetValue(UFrom, FilePath);
      UnitFid .AddOrSetValue(UFrom, FId     );
      UU:= Store.GetUnitUsesForFile(FId);
      if not Adj.TryGetValue(UFrom, L) then
      begin
        L:= TList<string>.Create;
        Adj.AddOrSetValue(UFrom, L);
      end;
      for Uo in UU do
      begin
        UTo:= LowerCase(Uo.UnitName);
        if UTo = '' then Continue;
        if not L.Contains(UTo) then L.Add(UTo);
        if Uo.Section = uusInterface then IntfEdges.AddOrSetValue(UFrom + '->' + UTo, True);
      end;
    end; // for

    { Tarjan SCC over the in-project units }
    Counter:= 0;
    for K in Adj.Keys do
      if not Index.ContainsKey(K) then StrongConnect(K);

    if AArgs.Plan then
    begin
      { followable markdown refactoring playbook -- concrete files, lines,
        symbols + step-by-step instructions a junior dev or small model can run }
      Writeln('# Cycle refactoring playbook'                                         );
      Writeln(''                                                                     );
      Writeln('Generated by `drag-lint cycles --plan`. Recommendations are'          );
      Writeln('best-effort -- the index can miss references (e.g. `set` types) -- so');
      Writeln('**build CLIENT + SERVER after each cycle** and re-run `drag-lint'     );
      Writeln('cycles` to confirm the group is gone. If a build breaks, revert and'  );
      Writeln('inspect by hand.'                                                     );
      Writeln(''                                                                     );
      if Sccs.Count = 0 then Writeln('No circular unit dependencies. Nothing to do.');
      for i:= 0 to Sccs.Count - 1 do
      begin
        var Comp:= Sccs[i];
        var HasIntf:= False;
        for var A in Comp do
        for var B in Comp do
            if (A <> B) and IntfEdges.ContainsKey(A + '->' + B) then HasIntf:= True;

        Writeln(Format('## Cycle %d: %s', [i + 1, string.Join(' <-> ', Comp)]));
        Writeln('');
        if not HasIntf then
        begin
          Writeln('Status: **implementation-only** (legal in Delphi, low impact). ' + 'Skip unless it hurts build times.');
          Writeln('');
          Continue;
        end;

        Writeln('Files:');
        for var A in Comp do
        begin
          var P: string:= ''; UnitFile.TryGetValue(A, P);
          Writeln(Format('- `%s` -> `%s`', [A, P]));
        end;
        Writeln('');

        { detect a layering inversion edge (COMMON depending on CLIENT/SERVER) }
        var InvFrom: string:= ''; var InvTo: string:= '';
        for var A in Comp do
        begin
          var NbrL: TList<string>;
          if not Adj.TryGetValue(A, NbrL) then Continue;
          for var B in Comp do
            if (A <> B) and NbrL.Contains(B) then
            begin
              var pa: string:= ''; var pb: string:= '';
              UnitFile.TryGetValue(A, pa); UnitFile.TryGetValue(B, pb);
              if (LayerOf(pa) = 'COMMON') and ((LayerOf(pb) = 'CLIENT') or (LayerOf(pb) = 'SERVER')) then
              begin InvFrom:= A; InvTo:= B; end;
            end;
        end;

        Writeln('### Why it cycles');
        for var A in Comp do
        for var B in Comp do
          begin
            if (A = B) or not IntfEdges.ContainsKey(A + '->' + B) then Continue;
            var Afid: Int64;
            if not UnitFid.TryGetValue(A, Afid) then Continue;
            var APath: string:= ''; UnitFile.TryGetValue(A, APath);
            var ImplL: Integer:= MaxInt                           ;
            if TFile.Exists(APath) then
            begin
              var Ls:= TStringList.Create;
              try
                Ls.LoadFromFile(APath);
                for var z:= 0 to Ls.Count - 1 do
                  if SameText(Trim(Ls[z]), 'implementation') then
                  begin ImplL:= z + 1; Break; end;
              finally Ls.Free; end;
            end;
            var Seen:= TDictionary<string, Boolean>.Create;
            var AnyFound:= False;
            try
              for var R in Store.GetReferencesFromFile(Afid) do
              begin
                if R.StartLine >= ImplL then Continue;
                if Seen.ContainsKey(LowerCase(R.NameText)) then Continue;
                for var Sym in Store.FindSymbolsByExactName(R.NameText) do
                  if SameText(UnitNameOfFile(Store.GetFilePath(Sym.FileId)), B) then
                  begin
                    var Bp: string:= Store.GetFilePath(Sym.FileId);
                    Writeln(Format(
                        '- `%s` interface uses `%s` (%s) at `%s:%d`; ' + 'declared in `%s:%d`.',
                        [A, R.NameText, Sym.Kind.ToText, ExtractFileName(APath), R.StartLine, ExtractFileName(Bp), Sym.StartLine]));
                    Seen.AddOrSetValue(LowerCase(R.NameText), True);
                    AnyFound:= True;
                    Break;
                  end;
              end; // for
              if not AnyFound then Writeln(Format(
                  '- `%s` interface uses `%s` but the index could not ' + 'resolve the symbol (likely a `set` type). **Open `%s` and find '
                      + 'what its interface uses from `%s` by hand.**', [A, B, ExtractFileName(APath), B]));
            finally Seen.Free; end; // try
          end; // for
        Writeln('');

        Writeln('### Recommended fix');
        if InvFrom <> '' then
        begin
          Writeln(Format('**Invert the dependency.** `%s` (COMMON) must not depend ' + 'on `%s` (CLIENT/SERVER) -- that inversion is what closes the cycle.', [InvFrom, InvTo]));
          Writeln(''      );
          Writeln('Steps:');
          Writeln(Format('1. Find what `%s` uses from `%s` (the `%s uses %s ' + '[implementation]` edge).', [InvFrom, InvTo, InvFrom, InvTo]));
          Writeln(Format('2. Declare an **interface** in `%s` (or a new COMMON leaf ' + 'unit) for that behaviour.', [InvFrom]));
          Writeln(Format('3. Make `%s` IMPLEMENT that interface; have `%s` use the ' + 'interface, not `%s`.', [InvTo, InvFrom, InvTo]));
          Writeln(Format('4. Remove `%s` from `%s`''s uses clause.', [InvTo, InvFrom]));
        end
        else
        begin
          Writeln('**Extract the shared contract** into a new leaf unit both can ' + 'depend on (it must use NEITHER unit in this cycle).');
          Writeln(''      );
          Writeln('Steps:');
          Writeln('1. For each symbol under "Why it cycles", create/reuse a leaf ' + 'unit (e.g. `<Unit>.Contracts.pas`) holding ONLY that declaration.');
          Writeln('2. Move the declaration there; add the new unit to the declaring ' + 'unit''s uses.');
          Writeln('3. In each consumer, replace the cycle-partner in the ' + '**interface** uses with the new contracts unit.');
          Writeln('4. Register the new unit in the .dpr/.dproj.');
        end;
        Writeln('5. Build CLIENT + SERVER.');
        Writeln(Format('6. **Verify:** `drag-lint cycles --db <db>` -- cycle %d ' + 'should be gone.', [i + 1]));
        Writeln('');
      end; // for
    end // if
    else if SameText(AArgs.Format, 'json') then
    begin
      JArr:= TJSONArray.Create;
      try
        for i:= 0 to Sccs.Count - 1 do
        begin
          var Comp:= Sccs[i];
          var JO      := TJSONObject.Create;
          var JMembers:= TJSONArray .Create;
          var HasIntf:= False;
          for var A in Comp do
          for var B in Comp do
              if (A <> B) and IntfEdges.ContainsKey(A + '->' + B) then HasIntf:= True;
          for var A in Comp do JMembers.Add(A);
          JO.AddPair('units', JMembers);
          JO.AddPair('size', TJSONNumber.Create(Length(Comp)));
          JO.AddPair('interface_cycle', TJSONBool.Create(HasIntf));
          JArr.AddElement(JO);
        end;
        Writeln(JArr.ToJson);
      finally
        JArr.Free;
      end; // try
    end // if
    else
    begin
      if Sccs.Count = 0 then Writeln('No circular unit dependencies found.')
      else
      begin
        Writeln(Format('%d circular unit group(s) found:', [Sccs.Count]));
        for i:= 0 to Sccs.Count - 1 do
        begin
          var Comp:= Sccs[i];
          var HasIntf:= False;
          for var A in Comp do
          for var B in Comp do
              if (A <> B) and IntfEdges.ContainsKey(A + '->' + B) then HasIntf:= True;
          Write(Format('  [%d units] %s', [Length(Comp), string.Join(' <-> ', Comp)]));
          if HasIntf then Writeln('   (has interface coupling -- widest recompile blast radius)')
          else Writeln('   (implementation-only -- legal, lower impact)');

          { --edges: list the actual uses edges inside the cycle, with section
            and layering, so you see exactly which line to move/cut. }
          if AArgs.Edges then
          begin
            for var A in Comp do
            begin
              var NeighborsL: TList<string>;
              if not Adj.TryGetValue(A, NeighborsL) then Continue;
              for var B in NeighborsL do
              begin
                { only edges that stay inside this cycle }
                var InComp:= False;
                for var C in Comp do if C = B then InComp:= True;
                if not InComp then Continue;

                var Sect: string;
                if IntfEdges.ContainsKey(A + '->' + B) then Sect:= 'interface  <-- move-to-implementation candidate'
                else Sect:= 'implementation';

                var PathA, PathB, Lay: string;
                UnitFile.TryGetValue(A, PathA);
                UnitFile.TryGetValue(B, PathB);
                Lay:= '';
                if (LayerOf(PathA) = 'COMMON') and ((LayerOf(PathB) = 'CLIENT') or (LayerOf(PathB) = 'SERVER')) then
                  Lay:= Format('   [LAYERING: %s -> %s, inverted]', [LayerOf(PathA), LayerOf(PathB)]);

                Writeln(Format('      %s uses %s  [%s]%s', [A, B, Sect, Lay]));
              end; // for
            end; // for
          end; // if

          { --causes: for each INTERFACE edge A->B, pinpoint the exact symbols in
            A's interface that reference B -- the things to move/extract to break
            the dependency. (Best-effort: the index can miss refs like set types,
            so treat as a starting point, not exhaustive.) }
          if AArgs.Causes then
          begin
            for var A in Comp do
            for var B in Comp do
              begin
                if (A = B) or not IntfEdges.ContainsKey(A + '->' + B) then Continue;
                var Afid: Int64;
                if not UnitFid.TryGetValue(A, Afid) then Continue;
                var APath: string:= '';
                UnitFile.TryGetValue(A, APath);

                var ImplL: Integer:= MaxInt;
                if TFile.Exists(APath) then
                begin
                  var Ls:= TStringList.Create;
                  try
                    Ls.LoadFromFile(APath);
                    for var kk:= 0 to Ls.Count - 1 do
                      if SameText(Trim(Ls[kk]), 'implementation') then
                      begin ImplL:= kk + 1; Break; end;
                  finally Ls.Free; end;
                end;

                var Seen:= TDictionary<string, Boolean>.Create;
                var HdrShown:= False;
                try
                  for var R in Store.GetReferencesFromFile(Afid) do
                  begin
                    if R.StartLine >= ImplL then Continue; { interface only }
                    if Seen.ContainsKey(LowerCase(R.NameText)) then Continue;
                    for var Sym in Store.FindSymbolsByExactName(R.NameText) do
                      if SameText(UnitNameOfFile(Store.GetFilePath(Sym.FileId)), B) then
                      begin
                        if not HdrShown then
                        begin
                          Writeln(Format('      * %s''s INTERFACE needs %s via:', [A, B]));
                          HdrShown:= True;
                        end;
                        Writeln(Format('          line %d: %s  [%s]  -> move/extract this', [R.StartLine, R.NameText, Sym.Kind.ToText]));
                        Seen.AddOrSetValue(LowerCase(R.NameText), True);
                        Break;
                      end;
                  end; // for
                  if not HdrShown then
                    Writeln(Format('      * %s -> %s interface dep: no specific symbol ' + 'resolved (index gap -- inspect %s''s interface uses of %s by hand)', [A, B, A, B]));
                finally Seen.Free; end; // try
              end; // for
          end; // if
        end; // for
        if not (AArgs.Edges or AArgs.Causes) then Writeln('  (add --edges for the uses lines, --causes for the symbols to refactor)');
      end; // else
    end; // else
    Result:= 0;
  finally
    for L in Adj.Values do L.Free;
    Adj.Free; IntfEdges.Free; UnitFile.Free; UnitFid.Free; Index.Free; Lowlink.Free;
    OnStack.Free; Stack.Free; Sccs.Free;
  end; // try
end; // begin

// v0.43: drag-lint uses-audit <unit.pas> --db <sqlite> [--format json|text]
// Index-based PROPOSAL of uses-clause cleanups for one unit:
//   - units in the INTERFACE uses that are only referenced from the
//     implementation section -> "move to implementation"
//   - units that are not referenced at all -> "appears unused"
// Only audits project units that are in the index (never RTL/library uses).
// These are CANDIDATES: the rewriter (uses-fix) compiler-verifies each before
// applying, because the tree-sitter index can miss some references.
function DoUsesAudit(const AArgs: TArgs): Integer;
var
  Store       : ISymbolStore                       ;
  FileId      : Int64                              ;
  ThisStem    : string                             ;
  UU          : TArray<TUnitUse>                   ;
  Uo          : TUnitUse                           ;
  Refs        : TArray<TReference>                 ;
  R           : TReference                         ;
  Lines       : TStringList                        ;
  ImplLine    : Integer                            ;
  i           : Integer                            ;
  RefIntf     : TDictionary<string, Boolean>       ;
  RefImpl     : TDictionary<string, Boolean>       ;
  IndexedUnits: TDictionary<string, Int64>         ; { stem -> file_id }
  NameCache   : TDictionary<string, TArray<string>>;
  Syms        : TArray<TSymbol>                    ;
  S           : TSymbol                            ;
  UnitsForName: TArray<string>                     ;
  U           : string                             ;
  uStem       : string                             ;
  JArr        : TJSONArray                         ;
  nMove       : Integer                            ;
  nUnused     : Integer                            ;

  function UnitStemOf(const APath: string): string;
  begin
    Result:= LowerCase(ChangeFileExt(ExtractFileName( StringReplace(APath, '/', '\', [rfReplaceAll])), ''));
  end;

{ distinct indexed-unit stems that define a symbol named AName (cached) }
  function UnitsDefining(const AName: string): TArray<string>;
  var
    Sm: TSymbol      ;
    Us: TList<string>;
    St: string       ;
  begin
    if NameCache.TryGetValue(AName, Result) then Exit;
    Us:= TList<string>.Create;
    try
      for Sm in Store.FindSymbolsByExactName(AName) do
      begin
        St:= UnitStemOf(Store.GetFilePath(Sm.FileId));
        if (St <> '') and not Us.Contains(St) then Us.Add(St);
      end;
      Result:= Us.ToArray;
    finally
      Us.Free;
    end;
    NameCache.AddOrSetValue(AName, Result);
  end;

begin
  if AArgs.Target = '' then
  begin
    Writeln('Usage: drag-lint uses-audit <unit.pas> --db <sqlite> [--format json|text]');
    Exit   (2                                                                          );
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  RefIntf     := TDictionary<string, Boolean>.Create;
  RefImpl     := TDictionary<string, Boolean>.Create;
  IndexedUnits:= TDictionary<string, Int64  >.Create;
  NameCache:= TDictionary<string, TArray<string>>.Create;
  try
    { stem -> file_id for every indexed unit. Also lets us resolve the target by
      unit name, tolerant of the stored-path separator quirks that defeat a
      direct path lookup. }
    for var Fid2 in Store.GetAllFileIds do
    begin
      U:= UnitStemOf(Store.GetFilePath(Fid2));
      if U <> '' then IndexedUnits.AddOrSetValue(U, Fid2);
    end;

    ThisStem:= UnitStemOf(AArgs.Target);
    if not IndexedUnits.TryGetValue(ThisStem, FileId) then
    begin
      Writeln('Not indexed (re-run "drag-lint index"): ', AArgs.Target);
      Exit(2);
    end;

    { which section references each indexed unit }
    ImplLine:= MaxInt;
    var SrcPath: string:= Store.GetFilePath(FileId);
    if not TFile.Exists(SrcPath) then SrcPath:= AArgs.Target;
    if TFile.Exists(SrcPath) then
    begin
      Lines:= TStringList.Create;
      try
        Lines.LoadFromFile(SrcPath);
        for i:= 0 to Lines.Count - 1 do
          if SameText(Trim(Lines[i]), 'implementation') then
          begin
            ImplLine:= i + 1;
            Break;
          end;
      finally
        Lines.Free;
      end;
    end;

    Refs:= Store.GetReferencesFromFile(FileId);
    for R in Refs do
    begin
      UnitsForName:= UnitsDefining(R.NameText);
      for U in UnitsForName do
      begin
        if SameText(U, ThisStem) then Continue;
        if R.StartLine < ImplLine then RefIntf.AddOrSetValue(U, True)
        else RefImpl.AddOrSetValue(U, True);
      end;
    end;

    UU:= Store.GetUnitUsesForFile(FileId);
    JArr:= TJSONArray.Create;
    nMove:= 0; nUnused:= 0;
    try
      for Uo in UU do
      begin
        uStem:= LowerCase(Uo.UnitName);
        { audit only project units we can actually see in the index }
        if not IndexedUnits.ContainsKey(uStem) then Continue;
        if SameText(uStem, ThisStem) then Continue;

        var Verdict: string:= '';
        if (not RefIntf.ContainsKey(uStem)) and (not RefImpl.ContainsKey(uStem)) then
        begin
          Verdict:= 'unused';
          Inc(nUnused);
        end
        else if (Uo.Section = uusInterface) and (not RefIntf.ContainsKey(uStem)) then
        begin
          Verdict:= 'move-to-implementation';
          Inc(nMove);
        end;
        if Verdict = '' then Continue;

        if SameText(AArgs.Format, 'json') then
        begin
          var JO:= TJSONObject.Create;
          JO.AddPair('unit', Uo.UnitName);
          JO.AddPair('verdict', Verdict);
          JO.AddPair('section', IfThen(Uo.Section = uusInterface, 'interface', 'implementation'));
          JO.AddPair('line', TJSONNumber.Create(Uo.StartLine));
          JArr.AddElement(JO);
        end
        else
        begin
          if Verdict = 'unused' then Writeln(Format('  line %d: %s  -- appears UNUSED (comment out?)', [Uo.StartLine, Uo.UnitName]))
          else Writeln(Format('  line %d: %s  -- in interface uses, only used by ' + 'implementation -> MOVE down', [Uo.StartLine, Uo.UnitName]));
        end;
      end; // for

      if SameText(AArgs.Format, 'json') then Writeln(JArr.ToJson)
      else
      begin
        if nMove + nUnused = 0 then Writeln('  No interface->implementation moves or unused units found.')
        else Writeln(Format('-- %d move candidate(s), %d unused candidate(s). ' + 'Candidates only -- verify by compiling before applying.', [nMove, nUnused]));
      end;
    finally
      JArr.Free;
    end; // try
    Result:= 0;
  finally
    RefIntf.Free; RefImpl.Free; IndexedUnits.Free; NameCache.Free;
  end; // try
end; // begin

// v0.43: compile ONE unit in full project context (the engine behind
// check-unit, factored so uses-fix can reuse it). AShadow, if set, is put first
// on the unit search path so a modified copy of the unit there is compiled
// instead of the on-disk file. Picks dcc32/dcc64 + that platform's lib to match
// the project (avoids F2048). Returns parsed compiler findings.
function CompileUnitInContext(const AUnitPath, AProject, APlatform, AShadow: string): TCompileCheckResult;
var
  Resolver     : DRagLint.Project.Resolver.TProjectResolver;
  Folders      : TArray<string>                            ;
  P            : string                                    ;
  UPath        : string                                    ;
  Namespaces   : string                                    ;
  CompileTarget: string                                    ;
  TargetBase   : string                                    ;
  RsVars       : string                                    ;
  Cmd          : string                                    ;
  BdsDir       : string                                    ;
  LibRelease   : string                                    ;
  Plat         : string                                    ;
  DccExe       : string                                    ;
  PlatDir      : string                                    ;
  WrongDir     : string                                    ;
  CfgDir       : string                                    ;
  DcuDir       : string                                    ;
  TmpRoot      : string                                    ;
begin
  TargetBase:= ExtractFileName(AUnitPath);
  Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    if AProject <> '' then Folders:= Resolver.Resolve(AProject)
    else Folders:= Resolver.ResolveLibraryPaths;
  finally
    Resolver.Free;
  end;

  if AShadow <> '' then CompileTarget:= TPath.Combine(AShadow, TargetBase)
  else CompileTarget:= AUnitPath;

  Plat:= LowerCase(APlatform);
  if (Plat <> 'win32') and (Plat <> 'win64') then Plat:= 'win64';
  DccExe  := IfThen(Plat = 'win32', 'dcc32'  , 'dcc64'  );
  PlatDir := IfThen(Plat = 'win32', 'Win32'  , 'Win64'  );
  WrongDir:= IfThen(Plat = 'win32', '\win64\', '\win32\');

  BdsDir:= GetEnvironmentVariable('BDS');
  if BdsDir = '' then BdsDir:= 'C:\Program Files (x86)\Embarcadero\Studio\37.0';
  LibRelease:= TPath.Combine(BdsDir, 'lib\' + PlatDir + '\release');

  UPath:= '';
  if AShadow <> '' then UPath:= AShadow;
  if TDirectory.Exists(LibRelease) then
    if UPath = '' then UPath:= LibRelease else UPath:= UPath + ';' + LibRelease;
  for P in Folders do
    if (P <> '') and (Pos(WrongDir, LowerCase(P)) = 0) then
      if UPath = '' then UPath:= P else UPath:= UPath + ';' + P;

  Namespaces:= ReadDccNamespaces(AProject);

  TmpRoot:= TPath.Combine(TPath.GetTempPath, 'draglint_checkunit');
  CfgDir:= TPath.Combine(TmpRoot, 'cfg');
  DcuDir:= TPath.Combine(TmpRoot, 'dcu');
  TDirectory.CreateDirectory(CfgDir);
  TDirectory.CreateDirectory(DcuDir);
  TFile.WriteAllText(TPath.Combine(CfgDir, DccExe + '.cfg'), Format('-U"%s"'#13#10'-NS%s'#13#10'-NU"%s"'#13#10'-Q'#13#10, [UPath, Namespaces, DcuDir]));

  RsVars:= 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat';
  Cmd:= Format('cmd.exe /c "call "%s" && cd /d "%s" && %s "%s" 2>&1"', [RsVars, CfgDir, DccExe, CompileTarget]);
  Result:= TCompileChecker.RunCommand(Cmd);
end; // function

// set of error+fatal signatures (code|line|message) from a compile -- used to
// tell whether an edit INTRODUCED a new error vs the baseline (so we can verify
// edits even on projects that are already red).
function ErrorSignatures(const ARes: TCompileCheckResult): TArray<string>;
var
  F  : TCompilerFinding;
  L  : TList<string>   ;
  Sig: string          ;
begin
  L:= TList<string>.Create;
  try
    for F in ARes.Findings do
      if SameText(F.Severity, 'Error') or SameText(F.Severity, 'Fatal') then
      begin
        Sig:= Format('%s|%d|%s', [F.Code, F.LineNo, F.Message]);
        if not L.Contains(Sig) then L.Add(Sig);
      end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

// v0.43: drag-lint uses-fix --project <dproj> --db <sqlite> [--remove-unused]
// PROJECT SWEEP (no <unit> target): a fast, index-only DRY-RUN report of every
// proposed uses-clause change across all indexed units -- move interface->impl
// and (with --remove-unused) unused units that have no init/final section. No
// compiling here: this is the report you review before applying per-unit (where
// each edit IS compiler-verified). Filtered to a directory with --in <dir>.
function DoUsesFixSweep(const AArgs: TArgs): Integer;
var
  Store           : ISymbolStore                       ;
  IndexedUnits    : TDictionary<string, Int64>         ;
  NameCache       : TDictionary<string, TArray<string>>;
  RefIntf         : TDictionary<string, Boolean>       ;
  RefImpl         : TDictionary<string, Boolean>       ;
  TotalMove       : Integer                            ;
  TotalUnused     : Integer                            ;
  UnitsWithChanges: Integer                            ;
  RootFilter      : string                             ;

  function UnitStemOf(const APath: string): string;
  begin
    Result:= LowerCase(ChangeFileExt(ExtractFileName( StringReplace(APath, '/', '\', [rfReplaceAll])), ''));
  end;

  function UnitsDefining(const AName: string): TArray<string>;
  var
    Sm: TSymbol; Us: TList<string>; St: string;
  begin
    if NameCache.TryGetValue(AName, Result) then Exit;
    Us:= TList<string>.Create;
    try
      for Sm in Store.FindSymbolsByExactName(AName) do
      begin
        St:= UnitStemOf(Store.GetFilePath(Sm.FileId));
        if (St <> '') and not Us.Contains(St) then Us.Add(St);
      end;
      Result:= Us.ToArray;
    finally Us.Free; end;
    NameCache.AddOrSetValue(AName, Result);
  end;

  function HasInitSection(const AStem: string): Boolean;
  var
    FId: Int64; Sym: TSymbol; Syms: TArray<TSymbol>;
  begin
    Result:= True;
    if not IndexedUnits.TryGetValue(AStem, FId) then Exit;
    Syms:= Store.FindSymbolsByFile(Store.GetFilePath(FId));
    if Length(Syms) = 0 then Exit;
    Result:= False;
    for Sym in Syms do
      if SameText(Sym.Kind.ToText, 'initialization') or SameText(Sym.Kind.ToText, 'finalization') then Exit(True);
  end;

var
  FId        : Int64             ;
  Path       : string            ;
  ThisStem   : string            ;
  SrcPath    : string            ;
  uStem      : string            ;
  U          : string            ;
  Lines      : TStringList       ;
  ImplLine   : Integer           ;
  i          : Integer           ;
  Refs       : TArray<TReference>;
  R          : TReference        ;
  UU         : TArray<TUnitUse>  ;
  Uo         : TUnitUse          ;
  HeaderShown: Boolean           ;
begin
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  RootFilter:= LowerCase(StringReplace(AArgs.InFile, '/', '\', [rfReplaceAll]));
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  IndexedUnits:= TDictionary<string, Int64>.Create;
  NameCache:= TDictionary<string, TArray<string>>.Create;
  RefIntf:= TDictionary<string, Boolean>.Create;
  RefImpl:= TDictionary<string, Boolean>.Create;
  Lines:= TStringList.Create;
  try
    for FId in Store.GetAllFileIds do
    begin
      U:= UnitStemOf(Store.GetFilePath(FId));
      if U <> '' then IndexedUnits.AddOrSetValue(U, FId);
    end;

    TotalMove:= 0; TotalUnused:= 0; UnitsWithChanges:= 0;
    Writeln('Project uses sweep (DRY-RUN, index proposal -- apply per-unit to verify):');
    Writeln(''                                                                         );

    for FId in Store.GetAllFileIds do
    begin
      Path:= StringReplace(Store.GetFilePath(FId), '/', '\', [rfReplaceAll]);
      if not SameText(ExtractFileExt(Path), '.pas') then Continue;
      if (RootFilter <> '') and (Pos(RootFilter, LowerCase(Path)) = 0) then Continue;
      ThisStem:= UnitStemOf(Path);

      ImplLine:= MaxInt;
      if TFile.Exists(Path) then
      begin
        try Lines.LoadFromFile(Path); except Continue; end;
        for i:= 0 to Lines.Count - 1 do
          if SameText(Trim(Lines[i]), 'implementation') then begin ImplLine:= i + 1; Break; end;
      end;

      RefIntf.Clear; RefImpl.Clear;
      Refs:= Store.GetReferencesFromFile(FId);
      for R in Refs do
        for U in UnitsDefining(R.NameText) do
        begin
          if SameText(U, ThisStem) then Continue;
          if R.StartLine < ImplLine then RefIntf.AddOrSetValue(U, True)
          else RefImpl.AddOrSetValue(U, True);
        end;

      HeaderShown:= False;
      UU:= Store.GetUnitUsesForFile(FId);
      for Uo in UU do
      begin
        uStem:= LowerCase(Uo.UnitName);
        if not IndexedUnits.ContainsKey(uStem) then Continue;
        if SameText(uStem, ThisStem) then Continue;

        var Verdict: string:= '';
        if (Uo.Section = uusInterface) and (not RefIntf.ContainsKey(uStem)) and (RefImpl.ContainsKey(uStem)) then
        begin Verdict:= 'MOVE   ' + Uo.UnitName + ' -> implementation'; Inc(TotalMove); end
        else if AArgs.RemoveUnused and (not RefIntf.ContainsKey(uStem)) and (not RefImpl.ContainsKey(uStem)) then
        begin
          if HasInitSection(uStem) then Continue; { side-effect unit, leave it }
          Verdict:= 'UNUSED ' + Uo.UnitName + ' (comment out)'; Inc(TotalUnused);
        end;
        if Verdict = '' then Continue;

        if not HeaderShown then
        begin
          Writeln(Format('%s  (%s)', [ExtractFileName(Path), Path]));
          HeaderShown:= True;
          Inc(UnitsWithChanges);
        end;
        Writeln(Format('    line %4d: %s', [Uo.StartLine, Verdict]));
      end; // for
    end; // for

    Writeln('');
    Writeln(Format('== %d unit(s) with proposals: %d move(s), %d unused candidate(s). ==', [UnitsWithChanges, TotalMove, TotalUnused]));
    Writeln('Apply per unit (verified): drag-lint uses-fix <unit.pas> --project <dproj> --apply [--remove-unused]');
    Result:= 0;
  finally
    IndexedUnits.Free; NameCache.Free; RefIntf.Free; RefImpl.Free; Lines.Free;
  end; // try
end; // begin

// v0.43: drag-lint uses-fix <unit.pas> --project <dproj> --db <sqlite>
//        [--platform win32|win64] [--apply] [--remove-unused]
// Compiler-VERIFIED uses-clause cleanup for one unit:
//   * move: an interface-uses unit only referenced from the implementation is
//           moved down to the implementation uses (breaks interface cycles).
//   * remove (only with --remove-unused): a never-referenced unit is commented
//           out -- but ONLY if it has no initialization/finalization section
//           (those are side-effect/registration units; removing them compiles
//           clean but breaks runtime, which the compiler cannot see).
// Every edit is applied to a shadow + compiled; it is kept ONLY if it adds no
// new compiler error vs the baseline. Default is dry-run (prints a diff);
// --apply writes the file after a .bak backup.
function DoUsesFix(const AArgs: TArgs): Integer;
var
  Store       : ISymbolStore                       ;
  FileId      : Int64                              ;
  ThisStem    : string                             ;
  SrcPath     : string                             ;
  Plat        : string                             ;
  Proj        : string                             ;
  Orig        : TStringList                        ;
  Work        : TStringList                        ;
  UU          : TArray<TUnitUse>                   ;
  Refs        : TArray<TReference>                 ;
  RefIntf     : TDictionary<string, Boolean>       ;
  RefImpl     : TDictionary<string, Boolean>       ;
  IndexedUnits: TDictionary<string, Int64>         ;
  NameCache   : TDictionary<string, TArray<string>>;
  ImplLine    : Integer                            ;
  i           : Integer                            ;
  Baseline    : TArray<string>                     ;
  nMove       : Integer                            ;
  nRemove     : Integer                            ;
  nSkip       : Integer                            ;
  nApplied    : Integer                            ;

  function UnitStemOf(const APath: string): string;
  begin
    Result:= LowerCase(ChangeFileExt(ExtractFileName( StringReplace(APath, '/', '\', [rfReplaceAll])), ''));
  end;

  function UnitsDefining(const AName: string): TArray<string>;
  var
    Sm: TSymbol; Us: TList<string>; St: string;
  begin
    if NameCache.TryGetValue(AName, Result) then Exit;
    Us:= TList<string>.Create;
    try
      for Sm in Store.FindSymbolsByExactName(AName) do
      begin
        St:= UnitStemOf(Store.GetFilePath(Sm.FileId));
        if (St <> '') and not Us.Contains(St) then Us.Add(St);
      end;
      Result:= Us.ToArray;
    finally Us.Free; end;
    NameCache.AddOrSetValue(AName, Result);
  end;

{ does unit U (by stem) have an initialization/finalization section? if we
    cannot tell, assume YES (never auto-remove a possible side-effect unit). }
  function HasInitSection(const AStem: string): Boolean;
  var
    FId: Int64; Sym: TSymbol; Syms: TArray<TSymbol>;
  begin
    Result:= True;
    if not IndexedUnits.TryGetValue(AStem, FId) then Exit;
    Syms:= Store.FindSymbolsByFile(Store.GetFilePath(FId));
    if Length(Syms) = 0 then Exit; { unknown -> be safe }
    Result:= False;
    for Sym in Syms do
      if SameText(Sym.Kind.ToText, 'initialization') or SameText(Sym.Kind.ToText, 'finalization') then Exit(True);
  end;

{ comment out the unit on AEntryLine and repair a dangling comma so the list
    stays valid. Returns False if the line isn't a clean single-unit entry. }
  function CommentEntry(AEntryLine: Integer; const AUnitName: string): Boolean;
  var
    raw : string ;
    Body: string ;
    P   : Integer;
  begin
    Result:= False;
    if (AEntryLine < 0) or (AEntryLine >= Work.Count) then Exit;
    raw:= Work[AEntryLine];
    Body:= Trim(raw);
    { strip a leading/trailing comma to test that the line holds ONLY this unit }
    var Core:= Body;
    if Core.StartsWith(',') then Core:= Trim(Core.Substring(1));
    if Core.EndsWith(',') then Core:= Trim(Core.Substring(0, Core.Length - 1));
    if not SameText(Core, AUnitName) then Exit; { not a clean one-per-line entry }

    var hadTrailingComma:= Body.EndsWith  (',');
    var hadLeadingComma := Body.StartsWith(',');

    { comment the line, preserving indentation }
    P:= 1;
    while (P <= Length(raw)) and (raw[P] = ' ') do Inc(P);
    Work[AEntryLine]:= Copy(raw, 1, P - 1) + '// ' + Copy(raw, P, MaxInt) + '   { drag-lint: moved/removed }';

    { repair commas: if this entry had NO trailing comma (it was the last), the
      previous real entry's trailing comma now dangles before ';' -> strip it.
      If it had NO leading comma (it was the first) in a leading-comma list, the
      next entry's leading comma now dangles after 'uses' -> strip it. }
    if not hadTrailingComma then
    begin
      var J:= AEntryLine - 1;
      while (J >= 0) and (Trim(Work[J]) = '') do Dec(J);
      if (J >= 0) then
      begin
        var sj:= Work[J];
        if Trim(sj).EndsWith(',') then
        begin
          var Q:= Length(sj);
          while (Q > 0) and (sj[Q] <> ',') do Dec(Q);
          if Q > 0 then begin Delete(sj, Q, 1); Work[J]:= sj; end;
        end;
      end;
    end;
    if not hadLeadingComma then
    begin
      var J:= AEntryLine + 1;
      while (J < Work.Count) and (Trim(Work[J]) = '') do Inc(J);
      if (J < Work.Count) then
      begin
        var sj:= Work[J];
        if Trim(sj).StartsWith(',') then
        begin
          var Q:= Pos(',', sj);
          if Q > 0 then begin Delete(sj, Q, 1); Work[J]:= sj; end;
        end;
      end;
    end;
    Result:= True;
  end; // function

{ add AUnitName to the implementation uses as the FIRST entry. Inserting at
    the front with a trailing comma is valid for BOTH leading-comma and
    trailing-comma list styles (the original first entry never has a leading
    comma). Creates the block right after `implementation` if none exists. }
  procedure AddToImplUses(const AUnitName: string);
  var
    K       : Integer;
    usesLine: Integer;
    P       : Integer;
    T       : string ;
  begin
    usesLine:= -1;
    for K:= ImplLine - 1 to Work.Count - 1 do
    begin
      T:= LowerCase(Trim(Work[K]));
      if (T = 'uses') or T.StartsWith('uses ') then begin usesLine:= K; Break; end;
    end;

    if usesLine < 0 then
    begin
      for K:= 0 to Work.Count - 1 do
        if SameText(Trim(Work[K]), 'implementation') then
        begin
          Work.Insert(K + 1, 'uses');
          Work.Insert(K + 2, '  ' + AUnitName + ';   { drag-lint: moved here }');
          Break;
        end;
      Exit;
    end;

    if SameText(Trim(Work[usesLine]), 'uses') then { 'uses' on its own line -> new entry on the next line }
      Work.Insert(usesLine + 1, '  ' + AUnitName + ',   { drag-lint: moved here }')
    else
    begin
      { 'uses Foo, Bar;' inline -> inject right after the keyword }
      var S:= Work[usesLine];
      P:= Pos('uses', LowerCase(S));
      System.Insert(' ' + AUnitName + ',', S, P + 4);
      Work[usesLine]:= S;
    end;
  end; // procedure

{ try one edit on a fresh copy, compile it, accept into Work only if it adds
    no new error vs the baseline. AKind: 'move' | 'remove'. }
  function TryEdit(const AUnitName: string; AEntryLine: Integer; const AKind: string): Boolean;
  var
    Trial    : TStringList        ;
    ShadowDir: string             ;
    Res      : TCompileCheckResult;
    AfterSig : TArray<string>     ;
    sg       : string             ;
    NewErr   : Boolean            ;
  begin
    Result:= False;
    Trial:= TStringList.Create;
    try
      Trial.Assign(Work);
      { editing helpers operate on Work, so swap temporarily }
      var Saved:= Work;
      Work:= Trial;
      try
        if not CommentEntry(AEntryLine, AUnitName) then Exit;
        if AKind = 'move' then AddToImplUses(AUnitName);
      finally
        Work:= Saved;
      end;

      ShadowDir:= TPath.Combine(TPath.GetTempPath, 'draglint_usesfix');
      TDirectory.CreateDirectory(ShadowDir);
      Trial.SaveToFile(TPath.Combine(ShadowDir, ExtractFileName(SrcPath)));

      Res:= CompileUnitInContext(SrcPath, Proj, Plat, ShadowDir);

      { SAFETY GUARD: a Fatal (F-code) means the compile ABORTED -- usually on a
        dependency it couldn't resolve in this single-unit context -- BEFORE it
        ever validated the target unit's interface. Such a compile validated
        NOTHING, so the edit must never be accepted on its basis (this is the
        false-pass that let a bad move through: the same fatal appeared in both
        baseline and after, so the diff saw "no new error"). Reject = inconclusive. }
      for var Ft in Res.Findings do
        if SameText(Ft.Severity, 'Fatal') then Exit; { Result stays False -> skipped }

      AfterSig:= ErrorSignatures(Res);

      NewErr:= False;
      for sg in AfterSig do
      begin
        var Found:= False;
        var B: string;
        for B in Baseline do if B = sg then begin Found:= True; Break; end;
        if not Found then begin NewErr:= True; Break; end;
      end;

      if not NewErr then
      begin
        Work.Assign(Trial); { accept }
        Result:= True;
      end;
    finally
      Trial.Free;
    end; // try
  end; // function

  procedure PrintDiff;
  var
    K: Integer;
  begin
    { show only the lines we touched (they carry a drag-lint marker) + 1 line of
      context, so an inserted line doesn't make every following line look changed }
    Writeln('--- ', SrcPath, ' (proposed uses-clause changes) ---');
    for K:= 0 to Work.Count - 1 do
      if Pos('{ drag-lint:', Work[K]) > 0 then
      begin
        if (K > 0) and (Pos('{ drag-lint:', Work[K - 1]) = 0) then Writeln(Format('  %4d: %s', [K, Work[K - 1]]));
        Writeln(Format('  %4d: %s', [K + 1, Work[K]]));
      end;
  end;

var
  Uo          : TUnitUse      ;
  uStem       : string        ;
  R           : TReference    ;
  UnitsForName: TArray<string>;
  U           : string        ;
  Lines2      : TStringList   ;
begin
  { no <unit> target -> project-wide dry-run report (fast, index-only) }
  if AArgs.Target = '' then Exit(DoUsesFixSweep(AArgs));

  if AArgs.ProjectPath = '' then
  begin
    Writeln('Usage: drag-lint uses-fix <unit.pas> --project <dproj> --db <sqlite> ' + '[--platform win32|win64] [--apply] [--remove-unused]');
    Writeln('   or: drag-lint uses-fix --project <dproj> --db <sqlite> [--in <dir>] [--remove-unused]   (sweep report)');
    Exit   (2                                                                                                          );
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  Proj:= AArgs.ProjectPath;
  Plat:= AArgs.CheckPlatform;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  RefIntf     := TDictionary<string, Boolean>.Create;
  RefImpl     := TDictionary<string, Boolean>.Create;
  IndexedUnits:= TDictionary<string, Int64  >.Create;
  NameCache:= TDictionary<string, TArray<string>>.Create;
  Orig:= TStringList.Create;
  Work:= TStringList.Create;
  try
    for var Fid2 in Store.GetAllFileIds do
    begin
      U:= UnitStemOf(Store.GetFilePath(Fid2));
      if U <> '' then IndexedUnits.AddOrSetValue(U, Fid2);
    end;
    ThisStem:= UnitStemOf(AArgs.Target);
    if not IndexedUnits.TryGetValue(ThisStem, FileId) then
    begin
      Writeln('Not indexed (re-run "drag-lint index"): ', AArgs.Target);
      Exit(2);
    end;
    { normalise separators: stored paths can be mixed ('C:/x\y.pas'), which
      breaks ExtractFileName -> wrong shadow filename -> the verify would compile
      the REAL file instead of the edit (a false pass). }
    SrcPath:= StringReplace(Store.GetFilePath(FileId), '/', '\', [rfReplaceAll]);
    if not TFile.Exists(SrcPath) then SrcPath:= AArgs.Target;
    if not TFile.Exists(SrcPath) then
    begin
      Writeln('Source file not found on disk: ', SrcPath);
      Exit(2);
    end;
    Orig.LoadFromFile(SrcPath);
    Work.Assign      (Orig   );

    { implementation line + outgoing-ref sections (uses-audit logic) }
    ImplLine:= MaxInt;
    for i:= 0 to Orig.Count - 1 do
      if SameText(Trim(Orig[i]), 'implementation') then begin ImplLine:= i + 1; Break; end;

    Refs:= Store.GetReferencesFromFile(FileId);
    for R in Refs do
    begin
      UnitsForName:= UnitsDefining(R.NameText);
      for U in UnitsForName do
      begin
        if SameText(U, ThisStem) then Continue;
        if R.StartLine < ImplLine then RefIntf.AddOrSetValue(U, True)
        else RefImpl.AddOrSetValue(U, True);
      end;
    end;

    { baseline compile (so we only reject edits that add NEW errors) }
    Baseline:= ErrorSignatures(CompileUnitInContext(SrcPath, Proj, Plat, ''));

    nMove:= 0; nRemove:= 0; nSkip:= 0;
    UU:= Store.GetUnitUsesForFile(FileId);
    for Uo in UU do
    begin
      uStem:= LowerCase(Uo.UnitName);
      if not IndexedUnits.ContainsKey(uStem) then Continue;
      if SameText(uStem, ThisStem) then Continue;

      { MOVE: interface entry, not referenced from the interface section }
      if (Uo.Section = uusInterface) and (not RefIntf.ContainsKey(uStem)) and (RefImpl.ContainsKey(uStem)) then
      begin
        if TryEdit(Uo.UnitName, Uo.StartLine - 1, 'move') then
        begin
          Inc(nMove);
          Writeln(Format('  MOVED  %s  interface -> implementation (line %d)', [Uo.UnitName, Uo.StartLine]));
        end
        else
        begin
          Inc(nSkip);
          Writeln(Format('  skip   %s  (move did not verify / not a clean entry)', [Uo.UnitName]));
        end;
      end
      { REMOVE: never referenced, only with --remove-unused, and only if it has
        no init/final section (side-effect units stay) }
      else if AArgs.RemoveUnused and (not RefIntf.ContainsKey(uStem)) and (not RefImpl.ContainsKey(uStem)) then
      begin
        if HasInitSection(uStem) then
        begin
          Inc(nSkip);
          Writeln(Format('  skip   %s  (unreferenced but has init/final -- ' + 'possible side-effect unit, NOT removed)', [Uo.UnitName]));
        end
        else if TryEdit(Uo.UnitName, Uo.StartLine - 1, 'remove') then
        begin
          Inc(nRemove);
          Writeln(Format('  REMOVE %s  commented out (line %d)', [Uo.UnitName, Uo.StartLine]));
        end
        else
        begin
          Inc(nSkip);
          Writeln(Format('  skip   %s  (remove did not verify / not a clean entry)', [Uo.UnitName]));
        end;
      end; // if
    end; // for

    if (nMove + nRemove) = 0 then
    begin
      Writeln('  Nothing to change.');
      Exit   (0                     );
    end;

    if AArgs.Apply then
    begin
      TFile.Copy(SrcPath, SrcPath + '.bak', True);
      { preserve CRLF + ANSI }
      Lines2:= TStringList.Create;
      try
        Lines2.Assign(Work);
        Lines2.WriteBOM:= False;
        Lines2.SaveToFile(SrcPath, TEncoding.ANSI);
      finally
        Lines2.Free;
      end;
      Writeln(Format('-- APPLIED %d move(s), %d remove(s) to %s (backup: %s.bak)', [nMove, nRemove, ExtractFileName(SrcPath), ExtractFileName(SrcPath)]));
      Writeln('** WARNING: the per-unit verify is BEST-EFFORT, not a faithful'    );
      Writeln('   full-build check (dcc can reuse a stale .dcu or abort on an RTL');
      Writeln('   dependency, masking a real error). You MUST do a full project'  );
      Writeln('   build to confirm; revert from .bak if it fails.'                );
    end // if
    else
    begin
      PrintDiff;
      Writeln(Format('-- DRY-RUN: %d move(s), %d remove(s) (best-effort verify -- ' + 'a full project build is required to confirm).', [nMove, nRemove]));
    end;
    Result:= 0;
  finally
    RefIntf.Free; RefImpl.Free; IndexedUnits.Free; NameCache.Free;
    Orig.Free; Work.Free;
  end; // try
end; // begin

// v0.27: drag-lint generate-test --qname X [--framework dunitx|dunit] [--db PATH]
// Generates a DUnitX (default) or DUnit test scaffold for the given symbol.
// Exit 2 on usage error, 1 if no stub generated, 0 on success.
function DoGenerateTest(const AArgs: TArgs): Integer;
var
  Store    : ISymbolStore  ;
  Framework: TTestFramework;
  Stub     : string        ;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint generate-test --qname X [--framework dunitx|dunit] [--db PATH]');
    Exit   (2                                                                                );
  end;
  if not FileExists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s', [AArgs.DbPath]));
    Exit(2);
  end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  if SameText(AArgs.TestFramework, 'dunit') then Framework:= tfDUnit
  else Framework:= tfDUnitX;
  Stub:= TTestStubGenerator.Generate(Store, AArgs.QName, Framework);
  if Stub = '' then
  begin
    Writeln(Format('No stub generated for %s', [AArgs.QName]));
    Exit(1);
  end;
  Writeln(Stub);
  Result:= 0;
end; // function

// v0.31: drag-lint check-ast <file> [--db PATH] [--format text|json]
// Runs AST-based diagnostics without requiring dcc.exe.
// Checks: unbalanced begin/end, undeclared identifiers (vs index).
// Exit 0 if no findings, 1 if findings present, 2 on usage error.
function DoCheckAst(const AArgs: TArgs): Integer;
var
  Store   : ISymbolStore        ;
  Findings: TArray<TLintFinding>;
  F       : TLintFinding        ;
  JArr    : TJSONArray          ;
  JObj    : TJSONObject         ;
begin
  if AArgs.Target = '' then
  begin
    Writeln('Usage: drag-lint check-ast <file> [--db PATH] [--format text|json]');
    Exit   (2                                                                   );
  end;
  if not TFile.Exists(AArgs.Target) then
  begin
    Writeln('ERROR: file not found: ', AArgs.Target);
    Exit(2);
  end;
  if TFile.Exists(AArgs.DbPath) then
  begin
    Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
    Store.Migrate;
  end
  else Store:= nil;
  Findings:= TAstChecker.Check(Store, AArgs.Target);
  DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear;

  if SameText(AArgs.Format, 'json') then
  begin
    JArr:= TJSONArray.Create;
    try
      for F in Findings do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('rule'     , F.RuleId  );
        JObj.AddPair('severity' , F.Severity);
        JObj.AddPair('file_path', F.FilePath);
        JObj.AddPair('start_line', TJSONNumber.Create(F.StartLine));
        JObj.AddPair('start_col' , TJSONNumber.Create(F.StartCol ));
        JObj.AddPair('end_line'  , TJSONNumber.Create(F.EndLine  ));
        JObj.AddPair('end_col'   , TJSONNumber.Create(F.EndCol   ));
        JObj.AddPair('message', F.Message);
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end; // try
  end // if
  else
  begin
    for F in Findings do Writeln(Format('%s(%d,%d): %s %s: %s', [AArgs.Target, F.StartLine, F.StartCol, F.Severity, F.RuleId, F.Message]));
    Writeln(Format('AST findings: %d', [Length(Findings)]));
  end;

  if Length(Findings) > 0 then Result:= 1
  else Result:= 0;
end; // function

// v0.27: drag-lint format <file> [--yadf-path PATH]
// Runs YADF formatter on the given file (YADF rewrites in place).
// Exit 2 on usage error, 1 on formatter failure, 0 on success.
function DoFormat(const AArgs: TArgs): Integer;
var
  Res   : TFormatResult;
  Target: string       ;
begin
  Target:= AArgs.Target;
  if Target = '' then Target:= AArgs.QName; // fallback: reuse qname slot
  if Target = '' then
  begin
    Writeln('Usage: drag-lint format <file> [--yadf-path PATH]');
    Exit   (2                                                  );
  end;
  if not FileExists(Target) then
  begin
    Writeln(Format('File not found: %s', [Target]));
    Exit(2);
  end;
  Res:= TYadfFormatter.Format(Target, AArgs.YadfPath);
  if not Res.Success then
  begin
    Writeln(Format('YADF format failed (exit %d):'#13#10'%s', [Res.ExitCode, Res.StdoutText]));
    Exit(1);
  end;
  Writeln(Format('Formatted: %s', [Target]));
  Result:= 0;
end; // function

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
    if not CreateProcessW(nil, CmdLineBuf, nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      Writeln('ERROR: failed to spawn: ', ACmd);
      Result:= -1;
      Exit;
    end;
    // Drain stdout/stderr while child runs
    CloseHandle(WritePipe);
    WritePipe:= INVALID_HANDLE_VALUE;
    repeat
      if ReadFile(ReadPipe, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then
      begin
        Buffer[BytesRead]:= #0;
        Write(AnsiString(Buffer));
      end
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
    else
    begin
      Writeln('ERROR: .drag-lint-workspace.json not found. ' + 'Use --config <path> or run from a workspace root.');
      Exit(2);
    end;
  end;
  if not TFile.Exists(CfgPath) then
  begin
    Writeln('ERROR: workspace config not found: ', CfgPath);
    Exit(2);
  end;

  // --- workspace add ---
  if AArgs.SubCommand = 'add' then
  begin
    if AArgs.Target = '' then
    begin
      Writeln('Usage: drag-lint workspace add <projfile> [--config PATH]');
      Exit   (2                                                          );
    end;
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
      Conn.DriverName:= 'SQLite';
      Conn.Params.Values['Database']:= SharedDbPath;
      Conn.LoginPrompt:= False;
      Conn.Connected  := True;
      Q   .Connection := Conn;
      for P in Cfg.Projects do
      begin
        AbsProjPath:= TPath.GetFullPath( TPath.Combine(Cfg.RootDir, P.Path));
        PathPrefix:= IncludeTrailingPathDelimiter(AbsProjPath);
        Q.Close;
        Q.Sql.Text:= 'SELECT COUNT(*) AS cnt FROM files WHERE path LIKE :prefix';
        Q.ParamByName('prefix').AsString:= PathPrefix + '%';
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
    if ReadPipe <> INVALID_HANDLE_VALUE then
    begin
      CloseHandle(ReadPipe);
      ReadPipe:= INVALID_HANDLE_VALUE;
    end;
    if WritePipe <> INVALID_HANDLE_VALUE then
    begin
      CloseHandle(WritePipe);
      WritePipe:= INVALID_HANDLE_VALUE;
    end;
    if EC = 0 then Inc(SuccessCount)
    else Writeln(Format('WARNING: index returned exit code %d for: %s', [EC, P.Path]));
  end; // for

  Writeln('');
  Writeln(Format('Done: %d/%d projects indexed into %s', [SuccessCount, ProjectCount, SharedDbPath]));

  if SuccessCount = ProjectCount then Result:= 0
  else Result:= 1;
end; // begin

/// <summary>Implements the forms-csv CLI command: generates a navigation-map CSV
/// for a project index and writes it to --out or stdout.</summary>
function DoFormsCsv(const AArgs: TArgs): Integer;
var
  DbPath: string;
  Csv   : string;
begin
  if Length(AArgs.DbPaths) > 0 then DbPath:= AArgs.DbPaths[0]
  else DbPath:= AArgs.DbPath;
  if DbPath = '' then
  begin
    Writeln(ErrOutput, 'forms-csv: need --db <index.sqlite>');
    Exit(2);
  end;
  if not TFile.Exists(DbPath) then
  begin
    Writeln(ErrOutput, 'forms-csv: db not found: ', DbPath);
    Exit(2);
  end;
  try
    Csv:= DRagLint.FormsMap.GenerateFormsCsv(DbPath, AArgs.ProjectPath, AArgs.RootForm);
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'forms-csv: ', E.Message);
      Exit(1);
    end;
  end;
  if AArgs.Output <> '' then
  begin
    TFile.WriteAllText(AArgs.Output, Csv, TEncoding.ANSI);
    Writeln('forms-csv: wrote ', AArgs.Output);
  end
  else Write(Csv);
  Result:= 0;
end; // function

// v0.45 Task 9: 32-bit size guard.
// Emits a WARNING to ErrOutput when the process is 32-bit (or AForce32=True for
// testing) and the DB file exceeds ASizeGuardMB.
// Semantics for ASizeGuardMB:
//   0  -> warn for ANY non-empty file (deterministic threshold for tests)
//   >0 -> warn when file size in MB > ASizeGuardMB
// Does NOT abort; advisory only.
procedure SizeGuardCheck(const ADbPath: string; ASizeGuardMB: Integer; AForce32: Boolean);
var
  Is32Bit   : Boolean;
  FileSizeMB: Int64  ;
  FileSize64: Int64  ;
begin
  {$IFNDEF WIN64}
  Is32Bit:= True;
  {$ELSE}
  Is32Bit:= AForce32;
  {$ENDIF}
  if not Is32Bit then Exit;
  if not TFile.Exists(ADbPath) then Exit;
  try
    FileSize64:= TFile.GetSize(ADbPath);
  except
    Exit;
  end;
  FileSizeMB:= FileSize64 div (1024 * 1024);
  // ASizeGuardMB=0 -> warn for any non-empty file; else warn when size > threshold.
  if (ASizeGuardMB = 0) or (FileSizeMB > ASizeGuardMB) then
    Writeln(ErrOutput, Format( 'WARNING: %s is %d MB; a 32-bit process may run out of memory. ' + 'Use the Win64 drag-lint.exe (third_party\dll-win64).', [ADbPath, FileSizeMB]));
end; // procedure

/// <summary>Reads the default platform from the first .dproj found under the
/// manifest section that covers ACwd. Returns '' if not found.</summary>
/// <param name="AManifest">Parsed manifest providing section include paths.</param>
/// <param name="ACwd">Current working directory; used for longest-prefix match.</param>
/// <returns>'Win32', 'Win64', or '' when no .dproj or Platform element is found.</returns>
/// <remarks>Performs a top-directory-first search, then recursive if none found
/// at the top level.  Not thread-safe; call from the main thread only.</remarks>
function DetectPlatformFromDproj(const AManifest: TIndexManifest;
  const ACwd: string): string;
var
  Sections  : TArray<TIndexSection>;
  Sec       : TIndexSection        ;
  IncPath   : string               ;
  BestLen   : Integer              ;
  BestInc   : string               ;
  CwdNorm   : string               ;
  IncNorm   : string               ;
  DprojFile : string               ;
  DprojFiles: TArray<string>       ;
  Xml       : string               ;
  P1, P2    : Integer              ;
begin
  Result:= '';
  CwdNorm:= IncludeTrailingPathDelimiter(
              TPath.GetFullPath(ACwd)).ToLower;
  BestLen:= -1;
  BestInc:= '';

  // Find manifest section whose include is the longest ancestor of ACwd.
  Sections:= AManifest.Sections;
  for Sec in Sections do
  begin
    if SameText(Sec.Source, 'registry-libraries') then Continue;
    for IncPath in Sec.Include do
    begin
      IncNorm:= IncludeTrailingPathDelimiter(
                  TPath.GetFullPath(IncPath)).ToLower;
      if CwdNorm.StartsWith(IncNorm) and (Length(IncNorm) > BestLen) then
      begin
        BestLen:= Length(IncNorm);
        BestInc:= IncPath;
      end;
    end;
  end;

  if BestInc = '' then Exit;

  // Find first .dproj under that include path (top dir first, then recursive).
  try
    DprojFiles:= TDirectory.GetFiles(BestInc, '*.dproj',
                   TSearchOption.soTopDirectoryOnly);
    if Length(DprojFiles) = 0 then
      DprojFiles:= TDirectory.GetFiles(BestInc, '*.dproj',
                     TSearchOption.soAllDirectories);
    if Length(DprojFiles) = 0 then Exit;
    DprojFile:= DprojFiles[0];
  except
    Exit;
  end;

  // Parse <Platform Condition="'$(Platform)'==''">Win64</Platform>
  try
    Xml:= TFile.ReadAllText(DprojFile);
  except
    Exit;
  end;

  // Find <Platform Condition=...>Win64</Platform> ? search for the opening tag
  // directly so we are not confused by attribute quote style.
  P1:= Pos('<Platform Condition=', Xml);
  if P1 = 0 then
    P1:= Pos('<platform condition=', Xml.ToLower);
  while P1 > 0 do
  begin
    P1:= Pos('>', Xml, P1);
    if P1 = 0 then Break;
    P2:= Pos('<', Xml, P1 + 1);
    if P2 = 0 then Break;
    Result:= Xml.Substring(P1, P2 - P1 - 1).Trim;
    if (Result = 'Win32') or (Result = 'Win64') then Exit;
    Result:= '';
    // Search again from after this element (handles multiple Platform elements).
    P1:= Pos('<Platform Condition=', Xml, P2);
    if P1 = 0 then Break;
  end;
end; // function DetectPlatformFromDproj

// v0.45 Task 9: resolve the DB list for consumer commands (query/lsp/serve)
// when the user supplied no --db flags.
// Steps:
//   1. If the user gave --db flags, return those unchanged.
//   2. Otherwise load the manifest, pick platform, call TDbSelect.Resolve,
//      use that list.
//   3. If no manifest is found or the resolved list is empty, fall back to the
//      default .\drag-lint.sqlite so existing behaviour is preserved.
function ResolveConsumerDbs(const AArgs: TArgs): TArray<string>;
var
  Manifest : TIndexManifest                            ;
  Resolver : DRagLint.Project.Resolver.TProjectResolver;
  EngineDir: string                                    ;
  Platform : string                                    ;
  Resolved : TArray<string>                            ;
begin
  // User supplied explicit --db: honour without modification.
  if Length(AArgs.DbPaths) > 0 then
  begin
    Result:= AArgs.DbPaths;
    Exit;
  end;

  // Try manifest-driven selection.
  try
    EngineDir:= ExtractFilePath(ParamStr(0));
    Manifest:= TManifestIO.Load(EngineDir, GetCurrentDir);

    // Pick platform: CLI --platform > .dproj detection > manifest defaultPlatform.
    if AArgs.CheckPlatform <> '' then
      Platform:= AArgs.CheckPlatform
    else
    begin
      Platform:= DetectPlatformFromDproj(Manifest, GetCurrentDir);
      if Platform = '' then Platform:= Manifest.Settings.DefaultPlatform;
    end;

    Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
    try
      Resolved:= TDbSelect.Resolve(Manifest, Platform, Resolver, True);
    finally
      Resolver.Free;
    end;
  except
    // Any manifest parse / IO error: fall through to default.
    Resolved:= nil;
  end; // try

  if Length(Resolved) > 0 then Result:= Resolved
  else
  begin
    // Fallback: single default DB (preserves pre-Task-9 behaviour).
    Result:= [AArgs.DbPath];
  end;
end; // function

// v0.45 Task 10: resolve-dbs command.
// Prints the consumer DB list that query/lsp/serve would use when invoked with
// the same --platform / --config flags and no explicit --db.
// Output: one absolute path per line, or a JSON array with --json.
// Platform defaults to manifest defaultPlatform when --platform is omitted.
// Exit 0 always (an empty list prints nothing and still exits 0).
// When --config is given, the manifest is loaded directly from that file
// (matching the behaviour of index --all); otherwise TManifestIO.Load
// performs the standard engine-dir/cwd discovery (matching ResolveConsumerDbs).
/// <summary>Implements the resolve-dbs command: prints the ordered consumer
/// DB list a tool (query/lsp/serve) would open when invoked with no
/// explicit --db flags.  Useful for scripting and diagnostics.</summary>
/// <param name="AArgs">Parsed CLI arguments; uses CheckPlatform, WorkspaceConfig,
///   AsJson.  When DbPaths is non-empty (explicit --db flags) those paths are
///   printed as-is (matching ResolveConsumerDbs behaviour).</param>
/// <returns>0 always.</returns>
/// <remarks>Not thread-safe; call from the main thread only.</remarks>
function DoResolveDbsList(const AArgs: TArgs): Integer;
var
  Manifest  : TIndexManifest                            ;
  Resolver  : DRagLint.Project.Resolver.TProjectResolver;
  EngineDir : string                                    ;
  ConfigPath: string                                    ;
  Platform  : string                                    ;
  Paths     : TArray<string>                            ;
  P         : string                                    ;
  J         : TJSONArray                                ;
begin
  // --- Resolve the DB list -------------------------------------------------
  if Length(AArgs.DbPaths) > 0 then
  begin
    // Explicit --db flags: honour without modification (same as ResolveConsumerDbs).
    Paths:= AArgs.DbPaths;
  end
  else
  begin
    EngineDir:= ExtractFilePath(ParamStr(0));
    ConfigPath:= AArgs.WorkspaceConfig; // --config <path>

    try
      if ConfigPath <> '' then
      begin
        var Content:= TFile.ReadAllText(ConfigPath);
        var RootDir:= ExtractFilePath(TPath.GetFullPath(ConfigPath));
        Manifest:= TManifestIO.ParseText(Content, RootDir);
      end
      else Manifest:= TManifestIO.Load(EngineDir, GetCurrentDir);

      // Pick platform: CLI --platform > .dproj detection > manifest defaultPlatform.
      if AArgs.CheckPlatform <> '' then
        Platform:= AArgs.CheckPlatform
      else
      begin
        Platform:= DetectPlatformFromDproj(Manifest, GetCurrentDir);
        if Platform = '' then Platform:= Manifest.Settings.DefaultPlatform;
      end;

      Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
      try
        Paths:= TDbSelect.Resolve(Manifest, Platform, Resolver, True);
      finally
        Resolver.Free;
      end;
    except
      // Any manifest parse / IO error: empty list (do not crash).
      Paths:= nil;
    end; // try

    // Fallback: preserve pre-Task-9 default when no manifest is found.
    if Length(Paths) = 0 then Paths:= [AArgs.DbPath];
  end; // else

  // --- Emit output ---------------------------------------------------------
  if AArgs.AsJson then
  begin
    J:= TJSONArray.Create;
    try
      for P in Paths do J.Add(P);
      Writeln(J.ToString);
    finally
      J.Free;
    end;
  end
  else
  begin
    for P in Paths do Writeln(P);
  end;

  Result:= 0;
end; // function

// selftest dbselect: load the manifest from --config, resolve DB list via
// TDbSelect.Resolve (ARequireExists=False so library paths can be asserted
// without building the library index), and print each resolved DB path on its
// own line.  Platform is taken from --platform (required).
function DoSelfTestDbSelect(const AArgs: TArgs): Integer;
var
  Manifest  : TIndexManifest                            ;
  Resolver  : DRagLint.Project.Resolver.TProjectResolver;
  ConfigPath: string                                    ;
  Platform  : string                                    ;
  Paths     : TArray<string>                            ;
  P         : string                                    ;
begin
  ConfigPath:= AArgs.WorkspaceConfig;
  if ConfigPath = '' then
  begin
    Writeln(ErrOutput, 'selftest dbselect requires --config <path>');
    Exit(2);
  end;
  if not TFile.Exists(ConfigPath) then
  begin
    Writeln(ErrOutput, 'selftest dbselect: config not found: ', ConfigPath);
    Exit(2);
  end;

  Platform:= AArgs.CheckPlatform;
  if Platform = '' then
  begin
    Writeln(ErrOutput, 'selftest dbselect requires --platform <p>');
    Exit(2);
  end;

  var Content:= TFile.ReadAllText(ConfigPath);
  var RootDir:= ExtractFilePath(TPath.GetFullPath(ConfigPath));
  Manifest:= TManifestIO.ParseText(Content, RootDir);

  Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    // ARequireExists=False: assert paths even when library DB is not built.
    Paths:= TDbSelect.Resolve(Manifest, Platform, Resolver, False);
  finally
    Resolver.Free;
  end;

  for P in Paths do Writeln(P);
  Result:= 0;
end; // function

// selftest manifest-merge: builds a global manifest with currentProjectsIndexing=piPerGroup,
// merges a local manifest parsed from JSON with NO settings block, and asserts the
// merged value is still piPerGroup. Prints MERGE-OK on success or MERGE-FAIL: <detail>.
function DoSelfTestManifestMerge: Integer;
const
  GlobalJson = '{"settings":{"currentProjectsIndexing":"perGroup","defaultPlatform":"Win32",' + '"sizeGuardMB":1500,"enginePath":"auto","maxJobs":0},' +
  '"indexes":{"outDir":"OUT","exclude":[],"sections":[' + '{"name":"Proj","include":["proj"]}]}}';
  LocalJson = '{"indexes":{"outDir":"LOCAL","sections":[{"name":"Extra","include":["extra"]}]}}';
var
  Global   : TIndexManifest ;
  Local    : TIndexManifest ;
  Merged   : TIndexManifest ;
  LocalKeys: TSettingsKeySet;
  OldLen   : Integer        ;
  K        : Integer        ;
begin
  Global:= TManifestIO.ParseText(GlobalJson, 'C:\global');
  Local:= TManifestIO.ParseTextEx(LocalJson, 'C:\local', LocalKeys);

  { Replicate the merge logic from TManifestIO.Load }
  Merged:= Global;
  if Local.OutDir <> '' then Merged.OutDir:= Local.OutDir;
  if Length(Local.GlobalExclude) > 0 then
  begin
    OldLen:= Length(Merged.GlobalExclude);
    SetLength(Merged.GlobalExclude, OldLen + Length(Local.GlobalExclude));
    for K:= 0 to High(Local.GlobalExclude) do Merged.GlobalExclude[OldLen + K]:= Local.GlobalExclude[K];
  end;
  if skDefaultPlatform         in LocalKeys then Merged.Settings.DefaultPlatform        := Local.Settings.DefaultPlatform;
  if skEnginePath              in LocalKeys then Merged.Settings.EnginePath             := Local.Settings.EnginePath;
  if skSizeGuardMB             in LocalKeys then Merged.Settings.SizeGuardMB            := Local.Settings.SizeGuardMB;
  if skMaxJobs                 in LocalKeys then Merged.Settings.MaxJobs                := Local.Settings.MaxJobs;
  if skCurrentProjectsIndexing in LocalKeys then Merged.Settings.CurrentProjectsIndexing:= Local.Settings.CurrentProjectsIndexing;

  if Merged.Settings.CurrentProjectsIndexing = piPerGroup then
  begin
    Writeln('MERGE-OK');
    Result:= 0;
  end
  else
  begin
    Writeln('MERGE-FAIL: expected piPerGroup but got ', Ord(Merged.Settings.CurrentProjectsIndexing));
    Result:= 1;
  end;
end; // function

// selftest glob: runs all TGlob.Matches / MatchesAny cases.
// Prints GLOB-FAIL: <desc> and exits 1 on first failure; GLOB-OK and 0 on success.
function DoSelfTestGlob: Integer;

  procedure Expect(const ADesc: string; AActual, AExpected: Boolean);
  begin
    if AActual <> AExpected then
    begin
      Writeln('GLOB-FAIL: ', ADesc);
      Halt(1);
    end;
  end;

begin
  // Single wildcard cases
  Expect('* - Copy.pas'    , TGlob.Matches('Foo - Copy.pas', '* - Copy.pas'), True );
  Expect('*_OLD*.pas true' , TGlob.Matches('Unit_OLD.pas'  , '*_OLD*.pas'  ), True );
  Expect('*BACKUP* true'   , TGlob.Matches('BACKUP_ALL'    , '*BACKUP*'    ), True );
  Expect('*_OLD*.pas false', TGlob.Matches('Unit.pas'      , '*_OLD*.pas'  ), False);
  // Double-star cross-directory
  Expect('**/c.pas', TGlob.Matches('a/b/c.pas', '**/c.pas'), True);
  // SQL extensions
  Expect('MS*.SQL true' , TGlob.Matches('MSData.SQL', 'MS*.SQL'), True );
  Expect('MS*.SQL false', TGlob.Matches('Other.SQL' , 'MS*.SQL'), False);
  // MatchesAny
  Expect('MatchesAny hit' , TGlob.MatchesAny('x.tmp', ['*.bak', '*.tmp']), True );
  Expect('MatchesAny miss', TGlob.MatchesAny('x.pas', ['*.bak', '*.tmp']), False);
  Writeln('GLOB-OK');
  Result:= 0;
end; // begin

// selftest ignore: exercises TIgnoreStack against the fixture tree at
// tests/fixtures/manifest/proj/ (pass --dir <path> to override).
// Prints IGNORE-FAIL: <desc> and exits 1 on first failure; IGNORE-OK on success.
function DoSelfTestIgnoreFiles(const AArgs: TArgs): Integer;
var
  ProjDir: string      ;
  SubDir : string      ;
  Stack  : TIgnoreStack;

  procedure Assert(const ADesc: string; AActual, AExpected: Boolean);
  begin
    if AActual <> AExpected then
    begin
      Writeln('IGNORE-FAIL: ', ADesc, ' (expected=', BoolToStr(AExpected, True), ' got=', BoolToStr(AActual, True), ')');
      Halt(1);
    end;
  end;

begin
  ProjDir:= AArgs.Path;
  if ProjDir = '' then
  begin
    Writeln('IGNORE-FAIL: --dir <proj> required');
    Halt   (1                                   );
  end;
  SubDir:= TPath.Combine(ProjDir, 'sub');

  Stack:= TIgnoreStack.Create;
  try
    // --- Layer 1: proj/.hgignore (*.log, build/) ---
    Stack.PushDir(ProjDir);
    Assert('drop.log ignored'    , Stack.IsIgnored('drop.log', False), True );
    Assert('keep.pas not ignored', Stack.IsIgnored('keep.pas', False), False);
    Assert('build dir ignored'   , Stack.IsIgnored('build'   , True ), True );

    // --- Layer 2: proj/sub/.gitignore (*.tmp, !keep.tmp) ---
    Stack.PushDir(SubDir);
    Assert('a.tmp ignored'    , Stack.IsIgnored('a.tmp'   , False), True );
    Assert('keep.tmp included', Stack.IsIgnored('keep.tmp', False), False);
    Assert('b.pas not ignored', Stack.IsIgnored('b.pas'   , False), False);

    Stack.PopDir;
    Stack.PopDir;
  finally
    Stack.Free;
  end; // try

  Writeln('IGNORE-OK');
  Result:= 0;
end; // begin

// selftest closure: resolves the compile closure of --project <dpr/.dproj>,
// applying any --exclude <glob> patterns, and prints one file per line then
// WARN lines. Used by tests to assert the closure file set.
function DoSelfTestClosure(const AArgs: TArgs): Integer;
var
  Resolver    : TClosureResolver                          ;
  LibRoots    : TArray<string>                            ;
  ProjResolver: DRagLint.Project.Resolver.TProjectResolver;
  CR          : TClosureResult                            ;
  F           : string                                    ;
  W           : string                                    ;
begin
  if AArgs.ProjectPath = '' then
  begin
    Writeln('ERROR: selftest closure requires --project <dpr/.dproj>');
    Exit   (2                                                        );
  end;
  ProjResolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    LibRoots:= ProjResolver.ResolveLibraryPaths;
  finally
    ProjResolver.Free;
  end;
  Resolver:= TClosureResolver.Create(LibRoots);
  try
    CR:= Resolver.Resolve(AArgs.ProjectPath, AArgs.ExcludeGlobs);
  finally
    Resolver.Free;
  end;
  for F in CR.Files    do Writeln(F);
  for W in CR.Warnings do Writeln(W);
  Result:= 0;
end; // function

// selftest files: open the DB at --db read-only and print every distinct path
// from the files table, one per line. Used by tests to assert the indexed
// file set after a filtered index run.
function DoSelfTestFiles(const AArgs: TArgs): Integer;
var
  Store  : ISymbolStore ;
  FileIds: TArray<Int64>;
  Id     : Int64        ;
  Path   : string       ;
begin
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  FileIds:= Store.GetAllFileIds;
  for Id in FileIds do
  begin
    Path:= Store.GetFilePath(Id);
    if Path <> '' then Writeln(Path);
  end;
  Result:= 0;
end; // function

// selftest drift: call AnalyzeLibraryDrift with roots from --root flags.
// Prints MISSING <root> for each missing root, then DRIFT-OK or DRIFT-MISSING N.
// Exits 0 in all cases (test assertions are done by the caller script).
function DoSelfTestDrift(const AArgs: TArgs): Integer;
var
  Missing: TArray<string>;
  M      : string        ;
begin
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  Missing:= AnalyzeLibraryDrift(AArgs.DbPath, AArgs.Roots);
  for M in Missing do Writeln('MISSING ', M);
  if Length(Missing) = 0 then Writeln('DRIFT-OK')
  else Writeln('DRIFT-MISSING ', Length(Missing));
  Result:= 0;
end;

// selftest coverage --config <path> --root <dir>
// Load the manifest from --config (WorkspaceConfig), build a TProjectResolver,
// call ComputeCoverage for the directory given by --root (Roots[0]), and print
// one line per item: "<leaf> <kind> <detail>". Exits 0 on success.
function DoSelfTestCoverage(const AArgs: TArgs): Integer;
var
  ConfigPath: string                                    ;
  RootDir   : string                                    ;
  Content   : string                                    ;
  Manifest  : TIndexManifest                            ;
  Resolver  : DRagLint.Project.Resolver.TProjectResolver;
  Items     : TArray<TCoverageItem>                     ;
  Item      : TCoverageItem                             ;
  Leaf      : string                                    ;
  Line      : string                                    ;
begin
  ConfigPath:= AArgs.WorkspaceConfig;
  if ConfigPath = '' then
  begin
    Writeln(ErrOutput, 'selftest coverage requires --config <path>');
    Exit(2);
  end;
  if not TFile.Exists(ConfigPath) then
  begin
    Writeln(ErrOutput, 'selftest coverage: config not found: ', ConfigPath);
    Exit(2);
  end;

  if Length(AArgs.Roots) = 0 then
  begin
    Writeln(ErrOutput, 'selftest coverage requires --root <dir>');
    Exit(2);
  end;
  RootDir:= AArgs.Roots[0];

  Content:= TFile.ReadAllText(ConfigPath);
  Manifest:= TManifestIO.ParseText(Content, TPath.GetDirectoryName(TPath.GetFullPath(ConfigPath)));

  Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    Items:= ComputeCoverage(Manifest, RootDir, Resolver);
  finally
    Resolver.Free;
  end;

  for Item in Items do
  begin
    Leaf:= TPath.GetFileName(Item.Folder);
    Line:= Leaf + ' ' + CoverageKindStr(Item.Kind);
    if Item.Detail <> '' then Line:= Line + ' ' + Item.Detail;
    Writeln(Line);
  end;
  Result:= 0;
end; // function

// selftest recreate: build a one-file folder-tree section into a temp DB TWICE
// via BuildPlanItem and assert the symbol count is identical (not doubled).
// Regression for the duplicate-symbol bug where re-running index --all into an
// existing DB accumulated rows. PASS requires Count1 = Count2 > 0.
function DoSelfTestRecreate: Integer;
var
  TmpRoot: string      ;
  SrcDir : string      ;
  DbPath : string      ;
  PasFile: string      ;
  Item   : TPlanSection;
  Docs   : TDocConfig  ;
  Store  : ISymbolStore;
  Count1 : Int64       ;
  Count2 : Int64       ;
begin
  Result:= 0;
  TmpRoot:= TPath.Combine(TPath.GetTempPath, 'draglint_selftest_recreate_' + IntToStr(Int64(GetTickCount)));
  SrcDir:= TPath.Combine(TmpRoot, 'src');
  TDirectory.CreateDirectory(SrcDir);
  PasFile:= TPath.Combine(SrcDir, 'UFoo.pas');
  TFile.WriteAllText(
    PasFile, 'unit UFoo;'#13#10 + 'interface'#13#10 + 'type'#13#10 + '  TFoo = class'#13#10 + '  public'#13#10 + '    procedure Bar;'#13#10 + '    function Baz: Integer;'#13#10
      + '  end;'#13#10 + 'implementation'#13#10 + 'procedure TFoo.Bar; begin end;'#13#10 + 'function TFoo.Baz: Integer; begin Result := 0; end;'#13#10 + 'end.'#13#10);
  DbPath:= TPath.Combine(TmpRoot, 'sec.sqlite');

  // Minimal folder-tree section with the standard safe filter defaults.
  Item:= Default(TPlanSection);
  Item.Name  := 'selftest';
  Item.Mode  := smFolderTree;
  Item.DbPath:= DbPath;
  Item.Roots:= [SrcDir];
  Item.Platform:= '';
  Item.Filter:= TWalkFilter.Create;

  Docs:= Default(TDocConfig);

  try
    if not BuildPlanItem(Item, Docs) then
    begin
      Writeln('FAIL recreate: first build failed');
      Exit   (1                                  );
    end;
    // Create() only connects; Migrate() prepares the count statements (and is
    // idempotent against the already-built schema).
    Store:= TSQLiteSymbolStore.Create(DbPath);
    Store.Migrate;
    Count1:= Store.CountSymbols;
    Store:= nil; // close before second build deletes the file

    if not BuildPlanItem(Item, Docs) then
    begin
      Writeln('FAIL recreate: second build failed');
      Exit   (1                                   );
    end;
    Store:= TSQLiteSymbolStore.Create(DbPath);
    Store.Migrate;
    Count2:= Store.CountSymbols;
    Store:= nil;

    Writeln(Format('recreate: build1=%d build2=%d symbols', [Count1, Count2]));
    if Count1 = 0 then
    begin
      Writeln('FAIL recreate: no symbols indexed (parser/setup issue)');
      Result:= 1;
    end
    else if Count1 <> Count2 then
    begin
      Writeln(Format('FAIL recreate: symbol count changed on rebuild (%d -> %d)', [Count1, Count2]));
      Result:= 1;
    end
    else Writeln('PASS recreate: stable symbol count across rebuilds');
  finally
    Store:= nil;
    try TDirectory.Delete(TmpRoot, True); except end;
  end; // try
end; // function

// selftest unused-locals: CheckUnusedLocals must flag UnusedX + UnusedZ (each
// occurs only at its declaration) and spare UsedY + AlsoUsed (referenced in the
// body) + the parameter. Regression for the H2164 unused-local-var rule.
function DoSelfTestUnusedLocals: Integer;
var
  TmpDir  : string              ;
  PasFile : string              ;
  Findings: TArray<TLintFinding>;
  F       : TLintFinding        ;
  GotX    : Boolean             ;
  GotZ    : Boolean             ;
  FalsePos: Boolean             ;
begin
  Result:= 0;
  TmpDir:= TPath.Combine(TPath.GetTempPath, 'draglint_unusedlocals_' + IntToStr(Int64(GetTickCount)));
  TDirectory.CreateDirectory(TmpDir);
  PasFile:= TPath.Combine(TmpDir, 'UTest.pas');
  TFile.WriteAllText(PasFile, 'unit UTest;'#13#10 + 'interface'#13#10 + 'implementation'#13#10 + 'procedure Foo(AParam: Integer);'#13#10 + 'var'#13#10 +
    '  UnusedX: Integer;'#13#10 + // unused -> flag
    '  UsedY: Integer;'#13#10 + // used -> spare
    '  UnusedZ, AlsoUsed: Integer;'#13#10 + // UnusedZ flag, AlsoUsed spare
    'begin'#13#10 + '  UsedY := AParam;'#13#10 + '  AlsoUsed := UsedY + 2;'#13#10 + '  if AlsoUsed > 0 then ;'#13#10 + 'end;'#13#10 + 'end.'#13#10);
  try
    Findings:= DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals(PasFile);
    GotX:= False; GotZ:= False; FalsePos:= False;
    for F in Findings do
    begin
      if Pos('UnusedX', F.Message) > 0 then GotX:= True
      else if Pos('UnusedZ', F.Message) > 0 then GotZ:= True
      else FalsePos:= True; // any OTHER var flagged = false positive
    end;
    Writeln(Format('unused-locals: findings=%d (want UnusedX + UnusedZ only)', [Length(Findings)]));
    if GotX and GotZ and not FalsePos then Writeln('PASS unused-locals')
    else
    begin
      Writeln(Format('FAIL unused-locals: UnusedX=%s UnusedZ=%s falsePositive=%s', [BoolToStr(GotX, True), BoolToStr(GotZ, True), BoolToStr(FalsePos, True)]));
      Result:= 1;
    end;
  finally
    try TDirectory.Delete(TmpDir, True); except end;
  end; // try
end; // function

// --selftest-fts5: prove FTS5 + trigram tokenizer are compiled in.
function DoSelfTestFts5: Integer;
var
  Conn: TFDConnection;
  Q   : TFDQuery;
begin
  Result:= 1;
  Conn:= TFDConnection.Create(nil);
  try
    try
      Conn.DriverName:= 'SQLite';
      Conn.Params.Values['Database']:= ':memory:';
      Conn.Connected:= True;
      Conn.ExecSQL('CREATE VIRTUAL TABLE t USING fts5(x, tokenize=''trigram'')');
      Conn.ExecSQL('INSERT INTO t(rowid, x) VALUES (1, ''Folder not found'')');
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= Conn;
        Q.SQL.Text:= 'SELECT rowid FROM t WHERE t MATCH ''older''';  // substring
        Q.Open;
        if (not Q.Eof) and (Q.FieldByName('rowid').AsInteger = 1) then
        begin
          Writeln('FTS5+trigram OK');
          Result:= 0;
        end
        else Writeln('FTS5 present but trigram match failed');
      finally
        Q.Free;
      end;
    except
      on E: Exception do Writeln('FTS5 unavailable: ', E.Message);
    end;
  finally
    Conn.Free;
  end;
end;

// --selftest-schema: open --db and print all table/view names from sqlite_master.
function DoSelfTestSchema(const ADbPath: string): Integer;
var
  Conn: TFDConnection;
  Q   : TFDQuery;
begin
  Result:= 1;
  Conn:= TFDConnection.Create(nil);
  try
    try
      Conn.DriverName:= 'SQLite';
      Conn.Params.Values['Database']:= ADbPath;
      Conn.Connected:= True;
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= Conn;
        Q.SQL.Text:= 'SELECT name FROM sqlite_master WHERE type IN (''table'',''view'') ORDER BY name';
        Q.Open;
        while not Q.Eof do
        begin
          Write(Q.Fields[0].AsString, ' ');
          Q.Next;
        end;
        Writeln;
        Result:= 0;
      finally
        Q.Free;
      end;
    except
      on E: Exception do Writeln('selftest-schema error: ', E.Message);
    end;
  finally
    Conn.Free;
  end;
end;

function DoSelfTest(const AArgs: TArgs): Integer;
begin
  if AArgs.SubCommand      = 'manifest-merge' then Result:= DoSelfTestManifestMerge
  else if AArgs.SubCommand = 'glob' then Result:= DoSelfTestGlob
  else if AArgs.SubCommand = 'ignore'   then Result:= DoSelfTestIgnoreFiles(AArgs)
  else if AArgs.SubCommand = 'files'    then Result:= DoSelfTestFiles      (AArgs)
  else if AArgs.SubCommand = 'closure'  then Result:= DoSelfTestClosure    (AArgs)
  else if AArgs.SubCommand = 'dbselect' then Result:= DoSelfTestDbSelect   (AArgs)
  else if AArgs.SubCommand = 'drift'    then Result:= DoSelfTestDrift      (AArgs)
  else if AArgs.SubCommand = 'coverage' then Result:= DoSelfTestCoverage   (AArgs)
  else if AArgs.SubCommand = 'recreate'      then Result:= DoSelfTestRecreate
  else if AArgs.SubCommand = 'unused-locals' then Result:= DoSelfTestUnusedLocals
  else
  begin
    Writeln('ERROR: unknown selftest subcommand: ', AArgs.SubCommand);
    Writeln('Available: manifest-merge, glob, ignore, files, closure, dbselect, drift, coverage, recreate, unused-locals');
    Result:= 2;
  end;
end; // function

// reconcile-project <App.dpr|.dproj> [--apply] [--json] [--config <path>]
// Dry-run (default): print MISSING/EXTRA/STALE report, exit 0, write nothing.
// --apply: back up .dpr/.dproj and insert Missing units (Task 2).
// --json: emit a JSON object {missing,extra,stale} to stdout instead of text.
//         When --apply is also given, apply still runs; apply messages go to
//         ErrOutput so stdout remains valid JSON.
function DoReconcileProject(const AArgs: TArgs): Integer;
var
  ProjectFile : string                                    ;
  EngineDir   : string                                    ;
  Reconciler  : TProjectReconciler                        ;
  LibRoots    : TArray<string>                            ;
  StaleGlobs  : TArray<string>                            ;
  Manifest    : TIndexManifest                            ;
  ProjResolver: DRagLint.Project.Resolver.TProjectResolver;
  RR          : TReconcileResult                          ;
  Item        : TReconcileItem                            ;
  JRoot       : TJSONObject                               ;
  JObj        : TJSONObject                               ;
  JMissing    : TJSONArray                                ;
  JExtra      : TJSONArray                                ;
  JStale      : TJSONArray                                ;
begin
  // Accept either positional arg (AArgs.Path) or explicit --project.
  ProjectFile:= AArgs.Path;
  if (ProjectFile = '') and (AArgs.ProjectPath <> '') then ProjectFile:= AArgs.ProjectPath;
  if ProjectFile = '' then
  begin
    Writeln('ERROR: reconcile-project requires a .dpr or .dproj file path');
    Exit   (2                                                             );
  end;
  if not TFile.Exists(ProjectFile) then
  begin
    Writeln('ERROR: project file not found: ', ProjectFile);
    Exit(2);
  end;

  // Resolve library roots (used to exclude library files from the closure).
  ProjResolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    LibRoots:= ProjResolver.ResolveLibraryPaths;
  finally
    ProjResolver.Free;
  end;

  // Load manifest stale globs from indexes.exclude.
  // Use --config if given; else auto-discover (engine dir + cwd walk).
  StaleGlobs:= nil;
  try
    EngineDir:= ExtractFilePath(ParamStr(0));
    if AArgs.WorkspaceConfig <> '' then
    begin
      if TFile.Exists(AArgs.WorkspaceConfig) then
      begin
        var Content:= TFile.ReadAllText(AArgs.WorkspaceConfig);
        var RootDir:= ExtractFilePath(TPath.GetFullPath(AArgs.WorkspaceConfig));
        Manifest:= TManifestIO.ParseText(Content, RootDir);
      end
      else Manifest:= Default(TIndexManifest);
    end
    else Manifest:= TManifestIO.Load(EngineDir, GetCurrentDir);
    StaleGlobs:= Manifest.GlobalExclude;
  except
    // Advisory: if manifest load fails, proceed with built-in globs only.
    StaleGlobs:= nil;
  end; // try

  Reconciler:= TProjectReconciler.Create(LibRoots, StaleGlobs);
  try
    RR:= Reconciler.Analyze(ProjectFile);

    if AArgs.AsJson then
    begin
      // JSON output: { "missing": [...], "extra": [...], "stale": [...] }
      // stdout stays valid JSON; --apply messages go to ErrOutput.
      JRoot:= TJSONObject.Create;
      try
        JMissing:= TJSONArray.Create;
        for Item in RR.Missing do
        begin
          JObj:= TJSONObject.Create;
          JObj.AddPair('unit'   , Item.UnitName);
          JObj.AddPair('file'   , Item.FilePath);
          JObj.AddPair('relPath', Item.RelPath );
          JObj.AddPair('usedBy' , Item.UsedBy  );
          JMissing.AddElement(JObj);
        end;
        JRoot.AddPair('missing', JMissing);

        JExtra:= TJSONArray.Create;
        for Item in RR.Extra do
        begin
          JObj:= TJSONObject.Create;
          JObj.AddPair('unit'   , Item.UnitName);
          JObj.AddPair('file'   , Item.FilePath);
          JObj.AddPair('relPath', Item.RelPath );
          JObj.AddPair('usedBy' , Item.UsedBy  );
          JExtra.AddElement(JObj);
        end;
        JRoot.AddPair('extra', JExtra);

        JStale:= TJSONArray.Create;
        for Item in RR.Stale do
        begin
          JObj:= TJSONObject.Create;
          JObj.AddPair('unit'   , Item.UnitName);
          JObj.AddPair('file'   , Item.FilePath);
          JObj.AddPair('relPath', Item.RelPath );
          JObj.AddPair('usedBy' , Item.UsedBy  );
          JStale.AddElement(JObj);
        end;
        JRoot.AddPair('stale', JStale);

        Writeln(JRoot.Format(2));
      finally
        JRoot.Free;
      end; // try

      // --apply still runs; write messages to stderr so stdout stays clean.
      if AArgs.Apply then
      begin
        Reconciler.Apply(ProjectFile, RR);
        Writeln(ErrOutput, 'Applied: Missing units added to .dpr and .dproj (.bak backups written).');
      end;
    end // if
    else
    begin
      // Text report.
      Writeln(Format('MISSING (%d) - used but not listed (will be added with --apply):', [Length(RR.Missing)]));
      for Item in RR.Missing do
      begin
        if Item.UsedBy <> '' then Writeln(Format('  %s -> %s   (used by %s)', [Item.UnitName, Item.RelPath, Item.UsedBy]))
        else Writeln(Format('  %s -> %s', [Item.UnitName, Item.RelPath]));
      end;

      Writeln(Format('EXTRA (%d) - listed but never reached via uses (review):', [Length(RR.Extra)]));
      for Item in RR.Extra do Writeln(Format('  %s -> %s', [Item.UnitName, Item.RelPath]));

      Writeln(Format('STALE (%d) - used but looks stale (investigate):', [Length(RR.Stale)]));
      for Item in RR.Stale do
      begin
        if Item.UsedBy <> '' then Writeln(Format('  %s -> %s   (used by %s)', [Item.UnitName, Item.RelPath, Item.UsedBy]))
        else Writeln(Format('  %s -> %s', [Item.UnitName, Item.RelPath]));
      end;

      Writeln('Run a full project build to verify after --apply.');

      // --apply: write changes to .dpr/.dproj (with .bak backups).
      if AArgs.Apply then
      begin
        Reconciler.Apply(ProjectFile, RR);
        Writeln('Applied: Missing units added to .dpr and .dproj (.bak backups written).');
      end;
    end; // else
  finally
    Reconciler.Free;
  end; // try

  Result:= 0;
end; // function

// library-drift [--platform <p>] [--config <path>] [--json]
// Resolves the manifest, enumerates library plan items (smLibrary),
// and for each platform whose DB exists reports registry roots that
// have no indexed files in that DB. Exit 2 if any drift, else 0.
function DoLibraryDrift(const AArgs: TArgs): Integer;
var
  EngineDir : string                                    ;
  ConfigPath: string                                    ;
  Manifest  : TIndexManifest                            ;
  Plan      : TIndexPlan                                ;
  Resolver  : DRagLint.Project.Resolver.TProjectResolver;
  Item      : TPlanSection                              ;
  PFilter   : TArray<string>                            ;
  Roots     : TArray<string>                            ;
  Missing   : TArray<string>                            ;
  TotalMiss : Integer                                   ;
  PlatCnt   : Integer                                   ;
  R         : string                                    ;
  JRoot     : TJSONObject                               ;
  JPlatArr  : TJSONArray                                ;
  JPlatObj  : TJSONObject                               ;
  JMissArr  : TJSONArray                                ;
begin
  EngineDir:= ExtractFilePath(ParamStr(0));
  ConfigPath:= AArgs.WorkspaceConfig;

  if ConfigPath <> '' then
  begin
    if not TFile.Exists(ConfigPath) then
    begin
      Writeln(ErrOutput, 'library-drift: config not found: ', ConfigPath);
      Exit(2);
    end;
    var Content:= TFile.ReadAllText(ConfigPath);
    var RootDir:= ExtractFilePath(TPath.GetFullPath(ConfigPath));
    Manifest:= TManifestIO.ParseText(Content, RootDir);
  end
  else Manifest:= TManifestIO.Load(EngineDir, GetCurrentDir);

  // Build platform filter from --platform arg.
  if AArgs.CheckPlatform <> '' then
  begin
    SetLength(PFilter, 1);
    PFilter[0]:= AArgs.CheckPlatform;
  end
  else PFilter:= nil;

  Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    Plan:= ResolvePlan(Manifest, PFilter, Resolver);

    TotalMiss:= 0;
    PlatCnt  := 0;

    if AArgs.AsJson then
    begin
      JRoot   := TJSONObject.Create;
      JPlatArr:= TJSONArray .Create;
      try
        for Item in Plan.Items do
        begin
          if Item.Mode <> smLibrary then Continue;
          if not TFile.Exists(Item.DbPath) then Continue;
          Inc(PlatCnt);
          Roots:= Resolver.ReadPlatformLibraryPaths(Item.Platform);
          Missing:= AnalyzeLibraryDrift(Item.DbPath, Roots);
          Inc(TotalMiss, Length(Missing));
          JPlatObj:= TJSONObject.Create;
          JPlatObj.AddPair('platform', Item.Platform);
          JPlatObj.AddPair('db'      , Item.DbPath  );
          JMissArr:= TJSONArray.Create;
          for R in Missing do JMissArr.Add(R);
          JPlatObj.AddPair('missingRoots', JMissArr);
          JPlatArr.AddElement(JPlatObj);
        end; // for
        JRoot.AddPair('platforms', JPlatArr);
        Writeln(JRoot.Format(2));
      finally
        JRoot.Free;
      end; // try
    end // if
    else
    begin
      for Item in Plan.Items do
      begin
        if Item.Mode <> smLibrary then Continue;
        if not TFile.Exists(Item.DbPath) then Continue;
        Inc(PlatCnt);
        Roots:= Resolver.ReadPlatformLibraryPaths(Item.Platform);
        Missing:= AnalyzeLibraryDrift(Item.DbPath, Roots);
        Inc(TotalMiss, Length(Missing));
        Writeln('platform: ', Item.Platform, ', db: ', Item.DbPath);
        for R in Missing do Writeln('  MISSING: ', R);
        if Length(Missing) = 0 then Writeln('  (clean)');
      end;
      Writeln('library-drift: ', PlatCnt, ' platforms checked, ', TotalMiss, ' roots missing from index');
    end; // else
  finally
    Resolver.Free;
  end; // try

  if TotalMiss > 0 then Result:= 2
  else Result:= 0;
end; // function

function Run: Integer;
var
  Args: TArgs;
begin
  if (ParamStr(1) = '--selftest-fts5') then Exit(DoSelfTestFts5);
  if (ParamStr(1) = '--selftest-schema') then Exit(DoSelfTestSchema(ParamStr(3)));
  try
    Args:= ParseArgs;
    if Args.ShowHelp then
    begin
      PrintHelp;
      Exit(0);
    end;
    if Args.ShowVersion then
    begin
      Writeln('drag-lint ', VERSION);
      Exit(0);
    end;
    if Args.Command = 'index' then
    begin
      if Args.IndexAll then Result:= DoIndexAll(Args)
      else Result:= DoIndex(Args)
    end
    else if Args.Command = 'query'             then Result:= DoQuery           (Args)
    else if Args.Command = 'lint'              then Result:= DoLint            (Args)
    else if Args.Command = 'export'            then Result:= DoExport          (Args)
    else if Args.Command = 'top'               then Result:= DoTop             (Args)
    else if Args.Command = 'import-log'        then Result:= DoImportLog       (Args)
    else if Args.Command = 'graph'             then Result:= DoGraph           (Args)
    else if Args.Command = 'todos'             then Result:= DoTodos           (Args)
    else if Args.Command = 'hover'             then Result:= DoHover           (Args)
    else if Args.Command = 'impact'            then Result:= DoImpact          (Args)
    else if Args.Command = 'wiring'            then Result:= DoWiring          (Args)
    else if Args.Command = 'surface'           then Result:= DoSurface         (Args)
    else if Args.Command = 'outline'           then Result:= DoOutline         (Args)
    else if Args.Command = 'usages'            then Result:= DoUsages          (Args)
    else if Args.Command = 'scan-all'          then Result:= DoScanAll         (Args)
    else if Args.Command = 'slice'             then Result:= DoSlice           (Args)
    else if Args.Command = 'context'           then Result:= DoContext         (Args)
    else if Args.Command = 'bench-context'     then Result:= DoBenchContext    (Args)
    else if Args.Command = 'typeat'            then Result:= DoTypeAt          (Args)
    else if Args.Command = 'uses-report'       then Result:= DoUsesReport      (Args)
    else if Args.Command = 'resolve-uses'      then Result:= DoResolveUses     (Args)
    else if Args.Command = 'fb-snapshot'       then Result:= DoFbSnapshot      (Args)
    else if Args.Command = 'link-orm'          then Result:= DoLinkOrm         (Args)
    else if Args.Command = 'rename'            then Result:= DoRename          (Args)
    else if Args.Command = 'generate-docs'     then Result:= DoGenerateDocs    (Args)
    else if Args.Command = 'find-deadcode'     then Result:= DoFindDeadCode    (Args)
    else if Args.Command = 'compile-check'     then Result:= DoCompileCheck    (Args)
    else if Args.Command = 'ghost-check'       then Result:= DoGhostCheck      (Args)
    else if Args.Command = 'ghost-recover'     then Result:= DoGhostRecover    (Args)
    else if Args.Command = 'check-unit'        then Result:= DoCheckUnit       (Args)
    else if Args.Command = 'lint-all'           then Result:= DoLintAll         (Args)
    else if Args.Command = 'lint-project'      then Result:= DoLintProject     (Args)
    else if Args.Command = 'cycles'            then Result:= DoCycles          (Args)
    else if Args.Command = 'uses-audit'        then Result:= DoUsesAudit       (Args)
    else if Args.Command = 'uses-fix'          then Result:= DoUsesFix         (Args)
    else if Args.Command = 'forms-csv'         then Result:= DoFormsCsv        (Args)
    else if Args.Command = 'generate-test'     then Result:= DoGenerateTest    (Args)
    else if Args.Command = 'format'            then Result:= DoFormat          (Args)
    else if Args.Command = 'check-ast'         then Result:= DoCheckAst        (Args)
    else if Args.Command = 'diff'              then Result:= DoDiff            (Args)
    else if Args.Command = 'workspace'         then Result:= DoWorkspace       (Args)
    else if Args.Command = 'selftest'          then Result:= DoSelfTest        (Args)
    else if Args.Command = 'reconcile-project' then Result:= DoReconcileProject(Args)
    else if Args.Command = 'library-drift'     then Result:= DoLibraryDrift    (Args)
    else if Args.Command = 'resolve-dbs' then
      // v0.45 Task 10: print the consumer DB list (same as query/lsp/serve use).
      Result:= DoResolveDbsList(Args)
    else if Args.Command = 'lsp' then
    begin
      { v0.40.3: forward EVERY --db flag to the LSP server. Multi-DB
        query support inside TLSPServer iterates all stores.
        v0.45 Task 9: when no --db given, resolve from manifest.
        Cleanup 2: run size guard for each resolved DB at startup.
        Writes to ErrOutput only -- must NOT pollute the JSON-RPC stdout stream. }
      { Self-exit if the spawning IDE dies (no-op when --parent-pid absent). }
      StartParentExitWatch(Args.ParentPid);
      var DbList: TArray<string>;
      DbList:= ResolveConsumerDbs(Args);
      var LspSGMB: Integer;
      if Args.SizeGuardMBSet then LspSGMB:= Args.SizeGuardMB
      else
      begin
        LspSGMB:= 1500;
        try
          var LspM:= TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
          LspSGMB:= LspM.Settings.SizeGuardMB;
        except
          // ignore -- advisory only
        end;
      end;
      for var LspDb in DbList do SizeGuardCheck(LspDb, LspSGMB, Args.Force32);
      var LSP:= DRagLint.LSP.Server.TLSPServer.Create(DbList);
      try
        LSP.Run;
        Result:= 0;
      finally
        LSP.Free;
      end;
    end // if
    else if Args.Command = 'serve' then
    begin
      // Start MCP server. Reads JSON-RPC 2.0 over stdin, writes responses
      // to stdout. Holds the --db open for the lifetime of the session.
      // v0.45 Task 9: when no --db given, resolve from manifest.
      // Cleanup 2: run size guard for each resolved DB at startup.
      // Writes to ErrOutput only -- must NOT pollute the JSON-RPC stdout stream.
      var DbList: TArray<string>;
      DbList:= ResolveConsumerDbs(Args);
      var ServeSGMB: Integer;
      if Args.SizeGuardMBSet then ServeSGMB:= Args.SizeGuardMB
      else
      begin
        ServeSGMB:= 1500;
        try
          var ServeM:= TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
          ServeSGMB:= ServeM.Settings.SizeGuardMB;
        except
          // ignore -- advisory only
        end;
      end;
      for var ServeDb in DbList do SizeGuardCheck(ServeDb, ServeSGMB, Args.Force32);
      var Server:= DRagLint.MCP.Server.TMCPServer.Create(DbList);
      try
        Server.Run;
        Result:= 0;
      finally
        Server.Free;
      end;
    end // if
    else
    begin
      Writeln('ERROR: unknown command: ', Args.Command);
      PrintHelp;
      Result:= 2;
    end;
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      Result:= 3;
    end;
  end; // try
end; // function

end.
