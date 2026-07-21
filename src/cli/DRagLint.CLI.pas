unit DRagLint.CLI;

interface

const
  VERSION = '1.1.0-alpha';

/// <summary>TODO: describe.</summary>
/// <returns>TODO: describe.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoFbSnapshot (DRagLint.CLI.pas), DRagLint.CLI.DoLinkOrm (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas), DRagLint.CLI.DoCompileCheck (DRagLint.CLI.pas), DRagLint.CLI.DoGhostCheck (DRagLint.CLI.pas), DRagLint.CLI.Run (DRagLint.CLI.pas), Config.IndexesFrame.TIndexesFrame.RunEngine (Config.IndexesFrame.pas), Run caller (drag-lint-config.dpr), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas) (+6 more)
/// <!-- drag-lint:auto END -->
/// </remarks>
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
  , TreeSitter
  , DRagLint.Core   .Model
  , DRagLint.Core   .Interfaces
  , DRagLint.Core   .Indexer
  , DRagLint.Storage.SQLite
  , DRagLint.Parser .Delphi13
  , DRagLint.Parser .DFM
  , DRagLint.Parser .Sql
  , DRagLint.Sql    .FbSnapshot
  , DRagLint.Sql    .OrmLinker
  , DRagLint.Lint   .Config
  , DRagLint.Lint   .RuleCatalog
  , DRagLint.Lint   .Linter
  , DRagLint.Lint   .ProjectChecks
  , DRagLint.Lint   .ProjectRules
  , DRagLint.Lint   .ClassMetrics
  , DRagLint.Lint   .DocRules
  , DRagLint.Project.Resolver
  , DRagLint.Project.Members
  , DRagLint.Project.Coherence
  , DRagLint.FormsMap
  , DRagLint.MCP        .Server
  , DRagLint.LSP        .Server
  , Vcl.Graphics // v0.95 Task 1: clBlack/clRed for DoContrastSelfTest
  , DRagLint.Hover      .Renderer
  , DRagLint.Hover      .Returns
  , DRagLint.Hover      .Contrast
  , DRagLint.Context    .Bundler
  , DRagLint.Resolver   .TypeAt
  , DRagLint.Refactor   .Rename
  , DRagLint.Refactor   .TextEdit
  , DRagLint.Refactor   .NamingFix
  , DRagLint.Refactor   .DocStub
  , DRagLint.Doc        .Facts
  , DRagLint.Doc        .Regions
  , DRagLint.Doc        .Document
  , DRagLint.Doc        .Drift
  , DRagLint.Doc        .Batch
  , DRagLint.Refactor   .DeadCode
  , DRagLint.Refactor   .TestStub
  , DRagLint.Refactor   .ExtractMethod
  , DRagLint.Refactor   .EnumHelper
  , DRagLint.Format     .Yadf
  , DRagLint.Diagnostics.CompileCheck
  , DRagLint.Diagnostics.AstChecks
  , DRagLint.Diagnostics.NamingChecks
  , DRagLint.Diagnostics.DeadCodeChecks
  , DRagLint.Diagnostics.CloneChecks
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Diagnostics.FlowChecks
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
  , DRagLint.Index      .CallResolver
  , DRagLint.Wiring
  , DRagLint.Output.Sarif
  , DRagLint.Output.ExitCode
  , DRagLint.Lint  .Baseline
  , DRagLint.Preprocess.Types
  , DRagLint.Preprocess.Lexer
  , DRagLint.Preprocess.Expr
  , DRagLint.Preprocess
  , DRagLint.Preprocess.Profile
  , DRagLint.Report    .Deps
  , DRagLint.Report    .RCallTree
  , DRagLint.Convert   .PropTree
  , DRagLint.Convert   .Rules
  , DRagLint.Convert   .DfmReemit
  , DRagLint.Convert   .Apply
  , DRagLint.Convert   .Backup
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
    RuleCategory    : string        ; // --category <name>: filter `rules` output
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
    // v0.66: ergonomics #12 output/CI flags
    FailOn       : string ; // --fail-on error|warning|info|none (ergonomics #12)
    Baseline     : string ; // --baseline <file>: report only findings NOT in it
    WriteBaseline: string ; // --write-baseline <file>: record current findings, exit 0
    ConfigPath   : string ; // --config <file>: drag-lint-lint.json override path
    Enable       : string ; // --enable id1,id2: re-include disabled/off-by-default rules
    Profile      : string ; // --profile <name>: merge a named enable/disable set
    // v0.16: query find flags
    DocTag     : string ;
    DocContains: string ;
    NoDocs     : Boolean;
    Kind       : string ;
    PublicOnly : Boolean;
    // v0.40.4: uses-report flags
    IncludeExternal: Boolean; // --include-external
    AllSources     : Boolean; // --all-sources (default: only first DB's files)
    // NOTE: deps-report's --edges reuses the existing Edges field (declared
    // above near CheckPlatform, originally for 'cycles'); see its parse branch.
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
    Resolved      : Boolean; // v14 (D5 T8): find-callers --resolved (precise callers via call_edges)
    // v14 (D5 T11): call-graph traversal verbs (call-path / callgraph)
    CallFrom : string ; // --from <A>  (call-path source routine name/qname)
    // CallTo reuses RenameTo: --to is parsed into RenameTo (rename verb); call-path
    // and rename never run together, so call-path reads its --to from RenameTo.
    MaxDepth : Integer; // --max-depth N (call-path BFS safety cap; default 20)
    // Depth (--depth, above, default 3) is reused as callgraph's tree depth.
    Direction: string ; // --direction callers|callees; '' default -> each verb applies own (reverse-calltree=callers, callgraph=callees)
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
    // v0.69 D2a: rename --kind symbol|param
    // RenameKind reuses Kind (--kind already parsed into Kind)
    // RefFile    reuses InFile (--file already parsed into InFile)
    RefLine : Integer; // --line <L> (param rename, 1-based)
    RefCol  : Integer; // --col <C>  (param rename, 1-based)
    // v0.84: extract-method
    // ExFile reuses InFile (--file already parsed into InFile)
    // ExName reuses Name    (--name already parsed into Name)
    FromLine: Integer; // --from-line <L1> (1-based, inclusive)
    ToLine  : Integer; // --to-line <L2>   (1-based, inclusive)
    // v0.25: doc-stub generator + dead-code finder
    DocStubFormat : string ; // --format xmldoc|pasdoc (default 'xmldoc')
    IncludePrivate: Boolean; // --include-private
    // v0.26: compile-check
    Target: string; // --target <file.dproj|.pas>
    // v0.43: check-unit (in-memory semantic check) + uses-audit
    Shadow         : string ; // --shadow <dir> (unsaved-buffer overlay)
    ResolveUsesFlag: Boolean; // --resolve-uses (enrich undeclared errors)
    CheckPlatform  : string ; // --platform win32|win64 (matches project config)
    // fresh compiler findings: refresh-findings --full (force a full build even
    // when fewer than 2 files are stale)
    Full           : Boolean;
    Edges          : Boolean; // --edges (cycles: show the actual uses edges)
    Causes         : Boolean; // --causes (cycles: pinpoint the symbols forcing each interface edge)
    Plan           : Boolean; // --plan (cycles: emit a followable markdown refactoring playbook)
    Apply          : Boolean; // --apply (uses-fix / autofix: write changes, not dry-run)
    Fix            : Boolean; // --fix (lint: autofix findings that have a quick-fix; dry-run unless --apply)
    // AutoFix Chunk 1 (Task 3): single-finding fix targeting. Each SET flag
    // narrows the fixable set; unset = no filter. Default FixLine:=0, FixRule:=''.
    FixLine      : Integer; // --fix-line <L> (1-based; 0 = all lines)
    FixRule      : string ; // --fix-rule <id> ('' = all rules)
    RemoveUnused : Boolean; // --remove-unused (uses-fix: also comment unused)
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
    // v0.45: index manifest (Task 7). Track 3 sub-project B Task 2: convert-
    // apply's --only (instance-name allow-list) ALSO reuses this field -- same
    // comma-split parsing, just a different meaning per-command (documented at
    // the call site).
    OnlySections: TArray<string>; // --only <Sec1,Sec2,...>  restrict sections to build | convert-apply instance allow-list
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
    // by an unsaved buffer, with a guaranteed restore. Track 3 sub-project B
    // Task 2: convert-apply's --unit (the .pas being converted) ALSO reuses
    // this field (same non-document-command routing as ghost-check).
    GhostUnit  : string; // --unit <real .pas to overlay | convert-apply target .pas>
    GhostBuffer: string; // --buffer <temp file holding the buffer>
    // AutoDocument (whole-unit batch): --unit <file.pas> for the `document`
    // command means "document every public decl in this unit". It shares the
    // --unit flag with ghost-check's GhostUnit, so it is parsed into a DISTINCT
    // field ONLY when Command='document' to avoid the ghost-check collision.
    DocUnit    : string; // document --unit <file.pas>
    // AutoDocument (batch scope): --stubs flips the facts-only default. Off
    // (default) documents only facts-backed / already-documented decls; on keeps
    // the pure all-TODO create too (opt-in TODO stubs). Consumed by document /
    // document --project / document-all via TDocBatchOptions.Stubs.
    DocStubs   : Boolean; // document [...] --stubs
    // AutoDocument (ADF T4): --seealso opts in the <seealso> doc-source (related
    // symbols from the call graph + siblings). Off by default. Consumed by
    // document --qname / --unit / --project / document-all via
    // TDocBatchOptions.IncludeSeeAlso (and BuildFor's AIncludeSeeAlso).
    DocSeeAlso : Boolean; // document [...] --seealso
    // AutoDocument (ADF T5): --since opts in the <since> doc-source (git commit
    // date of the decl line). Off by default; git is spawned ONLY when set.
    // DocBaseDir is the repo root for the git lookup ('' -> the file's own dir).
    // Consumed by document --qname / --unit / --project / document-all via
    // TDocBatchOptions.IncludeSince / BaseDir (and BuildFor's AIncludeSince / ABaseDir).
    DocSince   : Boolean; // document [...] --since
    DocBaseDir : string ; // document [...] --base-dir <repoRoot>
    // v0.48: multi-overlay -- a manifest with one 'realpath<TAB>bufferpath' per
    // line, so ALL unsaved units are overlaid for a single compile.
    GhostOverlays: string; // --overlays <manifest>
    // v0.57: text-constant search (Tasks 3-8)
    TextQuery    : string ; // --text "<phrase>"
    TextAnyOrder : Boolean; // --any-order
    TextSubstring: Boolean; // --substring
    TextSource   : string ; // --source pas|dfm|sql ('' = all)
    // v0.64: lint-all progress
    Quiet : Boolean; // --quiet  suppress per-file progress to stderr
    // PP-Task-3: dump-pp-eval diagnostic verb (the {$IF expr} evaluator)
    PpExpr    : string        ; // --expr "<E>"        the compile-time expression to evaluate
    PpDefines : TArray<string>; // --define <SYM>      repeatable defined symbols (lowercased on use)
    PpNumeric : TArray<string>; // --numeric <K=V>     repeatable numeric defines (K=V, K lowercased on use)
    // PP-Task-6: preprocess-file include handling
    PpIncludeMode: string     ; // --include-mode <off|defines-only>  ('' => default 'off')
    PpNoNearSearch: Boolean   ; // --no-near-search  (v1.2.1 #2) strict BaseDir-only include resolution
    PpTolerances : Boolean    ; // --tolerances  (v1.2.1 #5) opt-in dcc-tolerance ';' replacement pass
    // PP-Task-7: pp-profile define-profile resolver diagnostic verb
    PpDproj      : string     ; // --dproj <file.dproj>  the project whose config defines to resolve
    // PP-Task-9: index-time preprocessing. Preprocessing is ON by default in the
    // index verbs (per-config {$IFDEF} resolution before parsing); --no-preprocess
    // reverts to the prior raw all-branch behaviour.
    NoPreprocess : Boolean    ; // --no-preprocess  disable the in-process directive preprocessor for this index run
    // Task 5: create-enum-helper CLI verb (--qname reuses QName; --db/--apply/
    // --no-backup/--json already shared). EnumMethodsStr is the raw --methods
    // CSV ('' = default all 6, parsed by DoCreateEnumHelper); EnumToString is
    // the raw --tostring value ('' -> tsmRtti default, else 'rtti'|'case').
    EnumMethodsStr: string; // --methods tobyte,frombyte,...
    EnumToString  : string; // --tostring rtti|case
    // Track 3 Batch 1 (Task 1): proptree deep-property enumerator. Depth reuses
    // Depth (--depth; proptree applies its own default 6 inside DoPropTree when
    // Depth<=0). ToPersistent defaults ON (stop the ancestor climb at
    // TPersistent/TObject); --no-to-persistent turns it OFF.
    ToPersistent  : Boolean; // proptree: stop ancestor climb at TPersistent/TObject (default True)
    // proptree write-back is AUTOMATIC by default: the resolving index is opened
    // WRITABLE so a type recovered by the lazy ancestry-bridge is memoized back
    // onto the property row (next query is a plain hit; self-limiting -- once
    // written it never re-fires). --no-write-back forces a read-only (query_only)
    // open that never mutates the DB. A writable open that fails falls back to
    // read-only automatically (resolution still works; memoization skipped).
    NoWriteBack   : Boolean; // proptree: force read-only, no memoization (default False = auto write-back)
    // proptree/2 (Task 2, R2): --min-visibility published|public filters emitted
    // leaves by EFFECTIVE (most-derived) visibility. '' (default/unset) = emit
    // ALL leaves, exactly as proptree/1 did (back-compat).
    MinVisibility : string ; // proptree: --min-visibility published|public ('' = all, back-compat)
    // Track 3 Batch 1 (Task 2): convert-validate. RulesFile is the --rules path
    // (the reFind-superset DSL file). PrintParsed dumps the parsed rules (parse-
    // only diagnostics). --from/--to reuse CallFrom/RenameTo (the From/To types).
    RulesFile     : string ; // --rules <file>  (conversion-rules DSL)
    PrintParsed   : Boolean; // --print-parsed  (dump parsed rule count + lines)
    // Track 3 Batch 2a-i (Task 8): convert-reemit HIDDEN test verb. FromBlockFile
    // is the --from-block path (one F DFM `object` block, verbatim text).
    FromBlockFile : string ; // --from-block <file>  (F DFM object block file)
    // proptree assignability engine (Task 5): convert-scaffold --surface
    // dfm|pas picks the TARGET (To-side) visibility bar for auto-'#link'
    // matching. '' (default/unset) -> DoConvertScaffold applies 'dfm'.
    Surface       : string ; // convert-scaffold: --surface dfm|pas ('' = default 'dfm')
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
  Writeln('  drag-lint query find-callers --name  <callee-name>  [--context N] [--resolved] [--db ...] [--json]');
  Writeln('                               --resolved: precise callers via resolved call_edges (grouped by target, certain|ambiguous)');
  Writeln('  drag-lint query find         [--doc-tag X | --doc-contains Y | --no-docs] [--kind K] [--public] [--db ...]');
  Writeln('  drag-lint query ancestors    --name <type> [--of <ancestor>] [--db ...] [--json]   (transitive class/interface hierarchy)');
  Writeln('  drag-lint query typecat      --name <type> [--db ...] [--json]   (resolve type category: float/string/class/interface/...)');
  Writeln('  drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]   - list every lint rule (catalog)');
  Writeln('  drag-lint lint  <path>       [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json]');
  Writeln('  drag-lint lint  --project <file.dproj> [--rule unit-not-in-dpr] [--json]');
  Writeln('  drag-lint lint-project --db <file.sqlite> [--rule god-class|unused-public-symbol|interface-reference-cycle|layering-violation|unused-private-member|unused-unit-in-uses|circular-uses|repeated-type-switch] [--layers <f.json>] [--json]');
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
  Writeln('  drag-lint deps-report --db <file.sqlite> [--db ...] [--depth N] [--edges] [--all-sources] [--name <pat>] [--format text|json|csv] [--output <file>]   (third-party dependency rollup)');
  Writeln('  drag-lint schema --db <file.sqlite> [--format text|json] [--output <file>]   (self-documenting LIVE index schema: schema_version + tables + columns + row counts, read-only)');
  Writeln('  drag-lint info [--json]                              (engine self-info: version, build date, MIT, tree-sitter + capabilities; read-only)');
  Writeln('  drag-lint fb-snapshot --connection "Database=...;User=...;Password=...;DriverID=FB" --db <sql.sqlite>');
  Writeln('  drag-lint link-orm    --db <projDb.sqlite> --db <sqlDb.sqlite>');
  Writeln('  drag-lint rename --kind symbol --name <QName> --to <New> [--json|--apply|--no-backup] --db <db>   - cross-unit rename');
  Writeln('  drag-lint rename --kind param  --file <F> --line <L> --col <C> --to <New> [--json|--apply|--no-backup]  - routine-local rename (param/var autofix)');
  Writeln('  drag-lint rename --qname <Foo.TBar.Baz> --to <NewName> [--db PATH] [--dry-run] [--no-backup]');
  Writeln('  drag-lint generate-docs --qname <Foo.TBar.Baz> [--format xmldoc|pasdoc] [--db PATH]');
  Writeln('  drag-lint document --qname <Foo.TBar.Baz> [--apply|--json|--no-backup] [--db PATH]   - generate/repair a managed DocInsight comment');
  Writeln('  drag-lint document --unit <file.pas> [--apply|--json|--no-backup] [--db PATH]         - document every public decl in the unit (facts-only)');
  Writeln('  drag-lint document --project <p.dpr|.dproj> [--stubs|--apply|--json|--no-backup] [--db PATH]  - document every public decl in the project''s compile closure');
  Writeln('  drag-lint document-all [--stubs|--apply|--json|--no-backup] [--db PATH]               - document every public decl in every indexed unit (no project scope)');
  Writeln('     batch modes (--unit/--project/document-all) default facts-only (summary/param left as TODO); add --stubs to also create all-TODO stub comments');
  Writeln('     add --seealso to any document mode to emit <seealso cref> links to related symbols (callees + siblings)');
  Writeln('     add --since [--base-dir <repoRoot>] to emit a git-derived <since> date; degrades silently when git is absent');
  Writeln('     @deprecated is auto-detected from the Pascal ''deprecated'' directive on the decl -- no flag needed');
  Writeln('  drag-lint create-enum-helper --qname <TEnum> [--apply|--json|--no-backup] [--methods <csv>] [--tostring rtti|case] [--db PATH]  - generate a Byte-family record helper for an enum');
  Writeln('     --methods tobyte,frombyte,tointeger,frominteger,tostring,fromstring (default: all 6); --tostring rtti (default, RTTI GetEnumName) or case (explicit case statement)');
  Writeln('     idempotent: a helper for the enum already indexed anywhere -> action=exists, no edit');
  Writeln('  drag-lint helpers-of <T> [--json] --db <db>   - list record/class helper edges targeting type T anywhere in the index');
  Writeln('  drag-lint find-unit --name <Symbol> --in <file> [--json|--apply|--no-backup] --db <db>  - add the declaring unit to uses');
  Writeln('  drag-lint safe-delete --name <QName> [--json|--apply|--no-backup] --db <db>   - delete a symbol iff it has zero references');
  Writeln('  drag-lint extract-method --file <F> --from-line <L1> --to-line <L2> --name <N> [--json|--apply|--no-backup]  - pull a statement run into a new method');
  Writeln('  drag-lint find-deadcode [--kind method|function|...] [--include-private] [--db PATH]');
  Writeln('  drag-lint compile-check <target.dproj|.pas> [--db PATH] [--format json|text]');
  Writeln('  drag-lint refresh-findings --project <X.dproj> --db <db> [--full] [--json]   (recompile stale units + refresh compiler_findings; >=2 stale -> full build)');
  Writeln('  drag-lint check-unit <unit.pas> [--project <dproj>] [--platform win32|win64] [--shadow <dir>] [--resolve-uses] [--db PATH] [--format json|text]');
  Writeln('  drag-lint cycles             --db <file.sqlite>    [--edges] [--causes] [--plan] [--format json|text]   (circular unit deps; --plan = followable refactoring playbook)');
  Writeln('  drag-lint uses-audit <unit.pas> --db <file.sqlite> [--format json|text]   (interface->impl moves + unused units)');
  Writeln('  drag-lint uses-fix <unit.pas> --project <dproj> --db <file.sqlite> [--platform win32|win64] [--apply] [--remove-unused]   (compiler-verified uses cleanup)');
  Writeln('  drag-lint generate-test --qname <Foo.TBar.Baz> [--framework dunitx|dunit] [--db PATH]');
  Writeln('  drag-lint format <file> [--yadf-path PATH]');
  Writeln('  drag-lint check-ast <file> [--db PATH] [--format text|json]');
  Writeln('  drag-lint dump-refs <file> --db PATH   (diagnostic: refs + enclosing_symbol_id attribution)');
  Writeln('  drag-lint doc-drift --qname X --db PATH [--json]   (diagnostic: deterministic doc-vs-code drift findings for one symbol)');
  Writeln('  drag-lint dump-call-edges --db PATH     (diagnostic: resolved call edges: ref_id|target_qname|confidence)');
  Writeln('  drag-lint find-callees --qname <Foo.Bar> --db PATH [--json]   (resolved outgoing calls of routine X)');
  Writeln('  drag-lint ambiguous-calls [--qname <Foo.Bar>|--file <file>] --db PATH [--json]   (resolver-coverage diagnostic: unresolved/ambiguous call sites)');
  Writeln('  drag-lint call-path --from <A> --to <B> [--max-depth N] --db PATH [--json]   (shortest resolved call path A -> ... -> B; exit 1 = no path)');
  Writeln('  drag-lint callgraph --qname <X> [--direction callers|callees] [--depth N] --db PATH [--json]   (N-deep resolved call tree; cycle-guarded)');
  Writeln('  drag-lint reverse-calltree --qname <X> [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH [--db ...]   (N-deep call tree; callers=who calls X (default), callees=what X calls; cycle-guarded)');
  Writeln('  drag-lint proptree --qname <X> [--depth N] [--no-to-persistent] [--no-write-back] [--min-visibility published|public] [--format text|json] [--json] --db PATH [--db ...]   (recursive deep-property enumerator: flattened dotted paths of a class''s own+inherited properties, recursing into class-typed types; types recovered by the ancestry-bridge are memoized back into the index automatically -- --no-write-back forces a read-only, non-mutating query; --min-visibility filters emitted leaves by effective visibility, default = all, schema proptree/2)');
  Writeln('  drag-lint convert-validate --rules <file> [--from <FromType>] [--to <ToType>] [--print-parsed] [--db PATH ...]   (parse+validate a reFind-superset conversion-rules DSL; checks #link/#default paths against the real property trees)');
  Writeln('  drag-lint convert-scaffold --from <FromType> --to <ToType> [--out <file>] [--surface dfm|pas] --db PATH [--db ...]   (auto-generate a VALID conversion-rules file from the real F/T property trees: concrete #link where 1 source matches by leaf-name+type, ??? for ambiguities, DROPPED notes for orphaned F props; --surface picks the TO-side target bar, default dfm=published-properties-only, pas=published+public incl. public fields; is_writable=false targets are never auto-linked on either surface)');
  Writeln('  drag-lint convert-apply --unit <F.pas> --rules <file> --db PATH [--db ...] [--only Name1,Name2,...] [--apply] [--no-backup]   (locates .dfm component instances matching a #convert rule and rewrites all 5 surfaces: declaration retype + uses-add + .dfm re-emit + property/event access-site rewrite + runtime-creator retype/TODO markers; without --apply this is DRY-RUN ONLY (preview, writes nothing); --apply writes for real with backups + a recovery.txt unless --no-backup)');
  Writeln('  drag-lint butterfly --qname <X> [--depth N] [--format dot|mermaid|text|json] [--output F] --db PATH [--db ...]   (composes callers (upward wing) + callees (downward wing) of X into one chart; default format dot)');
  Writeln('  drag-lint purge-locals --db PATH [--json]   (size escape hatch: drop skLocalVar/skParam symbols + VACUUM; call graph unchanged; re-inflated on next index)');
  Writeln('  drag-lint preprocess-file --file PATH [--define SYM]... [--numeric K=V]... [--include-mode off|defines-only] [--no-near-search] [--tolerances]   (diagnostic: print {$IFDEF}-resolved source to stdout)');
  Writeln('  drag-lint pp-profile [--dproj PATH] [--platform win32|win64] [--config Release|Debug]   (diagnostic: print the resolved define profile, one symbol per line)');
  Writeln('');
  Writeln('  Output/CI (lint, lint-all, check-ast):');
  Writeln('    --format sarif            emit SARIF 2.1.0 (in addition to text|json)');
  Writeln('    --fail-on <level>         exit nonzero iff a surviving finding is >= error|warning|info (or none)');
  Writeln('    --config <file>           drag-lint-lint.json (else auto-discovered in CWD)');
  Writeln('    --enable id1,id2          re-include disabled / off-by-default rules');
  Writeln('    --profile <name>          merge a named enable/disable set from the config');
  Writeln('    --baseline <file>         report only findings absent from the baseline');
  Writeln('    --write-baseline <file>   record current findings as the baseline and exit 0');
  Writeln('  drag-lint workspace index  [--config <.drag-lint-workspace.json>]');
  Writeln('  drag-lint workspace status [--config <.drag-lint-workspace.json>]');
  Writeln('  drag-lint workspace add <projfile> [--config <.drag-lint-workspace.json>]');
  Writeln('  drag-lint forms-csv --project <X.dproj> --db <file.sqlite> [--out <f.csv>] [--root <TfrmMAIN>]   (test-helper navigation CSV, one row per form)');
  Writeln('  drag-lint resolve-dbs [--platform win32|win64] [--config <path>] [--json]   (print the consumer DB list query/lsp/serve would use)');
  Writeln('  drag-lint reconcile-project <App.dpr|.dproj> [--apply] [--db <db>] [--full] [--json] [--config <path>]  - sync project member list; flag stale used units');
  Writeln('                             --db heals the index+findings for every project member (re-scan + recompile) WITHOUT editing the .dpr; --full forces the recompile even when nothing is incoherent');
  Writeln('  drag-lint library-drift [--platform <p>] [--config <path>] [--json]               - registry library roots that have source on disk but none in the index (exit 2 if drift)');
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
    if TFile.Exists(TPath.Combine(Dir, '.drag-lint.json')) then begin Candidate:= TPath.Combine(Dir, '.drag-lint.json'); Break; end;
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
    if V is TJSONObject then begin JWatch:= TJSONObject(V); AArgs.Watch:= True; N:= JWatch.GetValue('interval') as TJSONNumber; if N <> nil then AArgs.Interval:= N.AsInt; end;
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
  Result.MaxDepth           := 20;        // v14 (D5 T11): call-path BFS safety cap
  Result.Direction          := '';        // per-verb default applied in DoCallGraph/DoReverseCallTree (empty = unset)
  Result.ToPersistent       := True;       // proptree: stop ancestor climb at TPersistent/TObject unless --no-to-persistent
  Result.NoWriteBack        := False;      // proptree: auto write-back ON; --no-write-back forces read-only
  Result.MinVisibility      := '';        // proptree: --min-visibility unset = emit ALL leaves (back-compat)
  Result.FromBlockFile      := '';        // convert-reemit: --from-block <file>
  LoadConfigDefaults(Result);
  if ParamCount = 0 then begin Result.ShowHelp:= True; Exit; end;
  Result.Command:= ParamStr(1);
  if (Result.Command = '--help') or (Result.Command = '-h') then begin Result.ShowHelp:= True; Exit; end;
  if Result.Command = '--version' then begin Result.ShowVersion:= True; Exit; end;

  // Optional subcommand: ParamStr(2) if it doesn't start with '--'.
  i:= 2;
  if ((Result.Command = 'query') or (Result.Command = 'export') or (Result.Command = 'workspace') or (Result.Command = 'selftest')) and (ParamCount >= 2) then
  begin
    A:= ParamStr(2);
    if (A <> '') and (not A.StartsWith('--')) then begin Result.SubCommand:= A; i:= 3; end;
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
    else if (A = '--name') and (i < ParamCount) then begin Inc(i); Result.Name:= ParamStr(i); end
    else if ((A = '--in') or (A = '--file')) and (i < ParamCount) then begin Inc(i); Result.InFile:= ParamStr(i); end
    else if (A = '--qname') and (i < ParamCount) then begin Inc(i); Result.QName:= ParamStr(i); end
    else if (A = '--of') and (i < ParamCount) then { v11 (M1): query ancestors --of }
    begin
      Inc(i);
      Result.OfName:= ParamStr(i);
    end
    else if (A = '--rule') and (i < ParamCount) then begin Inc(i); Result.Rule:= ParamStr(i); end
    else if (A = '--exclude-under') and (i < ParamCount) then
    begin
      Inc(i);
      SetLength(Result.ExcludeUnder, Length(Result.ExcludeUnder) + 1);
      Result.ExcludeUnder[High(Result.ExcludeUnder)]:= ParamStr(i);
    end
    else if A = '--deep' then begin Result.Deep:= True; Result.DeepExplicit:= True; end
    else if A = '--shallow' then begin Result.Deep:= False; Result.DeepExplicit:= True; end
    else if A = '--no-preprocess' then Result.NoPreprocess:= True { PP-Task-9: revert index to raw all-branch parsing }
    else if (A = '--width') and (i < ParamCount) then begin Inc(i); Result.Width:= ParamStr(i); end
    else if (A = '--project') and (i < ParamCount) then begin Inc(i); Result.ProjectPath:= ParamStr(i); end
    else if (A = '--rules-dir') and (i < ParamCount) then begin Inc(i); Result.RulesDir:= ParamStr(i); end
    else if (A = '--category') and (i < ParamCount) then begin Inc(i); Result.RuleCategory:= ParamStr(i); end
    else if (A = '--disable') and (i < ParamCount) then begin Inc(i); Result.Disable:= ParamStr(i); end
    else if (A = '--layers') and (i < ParamCount) then begin Inc(i); Result.LayersPath:= ParamStr(i); end
    else if A = '--json'    then Result.AsJson:= True
    else if A = '--full'    then Result.Full  := True // refresh-findings: force a full build
    else if A = '--dry-run' then Result.DryRun:= True
    else if A = '--quiet'   then Result.Quiet := True
    else if (A = '--scan-libraries') or (A = '--scan-libraries-win') then Result.ScanLibraries:= True // Win32 + Win64 (--scan-libraries is the back-compat alias)
    else if A = '--scan-libraries-all' then
    begin
      Result.ScanLibraries   := True;
      Result.ScanLibrariesAll:= True; // every registered platform
    end
    else if A = '--watch' then Result.Watch:= True
    else if A = '--open'  then Result.Open := True
    else if (A = '--interval') and (i < ParamCount) then begin Inc(i); Result.Interval:= StrToIntDef(ParamStr(i), 5); end
    else if (A = '--format') and (i < ParamCount) then begin Inc(i); Result.Format:= ParamStr(i); end
    else if (A = '--fail-on') and (i < ParamCount) then begin Inc(i); Result.FailOn:= ParamStr(i); end
    else if (A = '--baseline') and (i < ParamCount) then begin Inc(i); Result.Baseline:= ParamStr(i); end
    else if (A = '--write-baseline') and (i < ParamCount) then begin Inc(i); Result.WriteBaseline:= ParamStr(i); end
    else if (A = '--config') and (i < ParamCount) then
    begin
      Inc(i);
      { --config is shared: lint/lint-all/check-ast read ConfigPath (drag-lint-lint.json);
        index/workspace/reconcile/library-drift/selftest read WorkspaceConfig (the manifest).
        A single CLI run targets one command, so populating both is harmless. }
      Result.ConfigPath     := ParamStr(i);
      Result.WorkspaceConfig:= ParamStr(i);
    end
    else if (A = '--enable') and (i < ParamCount) then begin Inc(i); Result.Enable:= ParamStr(i); end
    else if (A = '--profile') and (i < ParamCount) then begin Inc(i); Result.Profile:= ParamStr(i); end
    else if ((A = '--output') or (A = '--out')) and (i < ParamCount) then begin Inc(i); Result.Output:= ParamStr(i); end
    else if (A = '--output-dir') and (i < ParamCount) then begin Inc(i); Result.OutputDir:= ParamStr(i); end
    else if A = '--include-external' then Result.IncludeExternal:= True
    else if A = '--all-sources'      then Result.AllSources     := True
    // NOTE: --edges is parsed once, near --resolve-uses/--causes (originally
    // for 'cycles'); deps-report reuses that same Result.Edges field.
    else if A = '--all'              then Result.IndexAll       := True
    else if (A = '--only') and (i < ParamCount) then
    begin
      Inc(i);
      // Split comma-separated section names, trim each, skip empties.
      var Parts:= ParamStr(i).Split([',']);
      for var P in Parts do
      begin
        var T:= Trim(P);
        if T <> '' then begin SetLength(Result.OnlySections, Length(Result.OnlySections) + 1); Result.OnlySections[High(Result.OnlySections)]:= T; end;
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
    else if (A = '--jobs') and (i < ParamCount) then begin Inc(i); Result.Jobs:= StrToIntDef(ParamStr(i), 0); end
    else if A = '--force32' then Result.Force32:= True
    else if (A = '--size-guard-mb') and (i < ParamCount) then begin Inc(i); Result.SizeGuardMB:= StrToIntDef(ParamStr(i), 0); Result.SizeGuardMBSet:= True; end
    else if (A = '--max-file-kb') and (i < ParamCount) then begin Inc(i); Result.MaxFileKB:= StrToIntDef(ParamStr(i), 2048); Result.MaxFileKBSet:= True; end
    else if (A = '--connection') and (i < ParamCount) then begin Inc(i); Result.FbConnection:= ParamStr(i); end
    else if (A = '--limit') and (i < ParamCount) then begin Inc(i); Result.Limit:= StrToIntDef(ParamStr(i), 50); end
    else if (A = '--by') and (i < ParamCount) then begin Inc(i); Result.SortBy:= ParamStr(i); end
    else if (A = '--doc-tag') and (i < ParamCount) then begin Inc(i); Result.DocTag:= ParamStr(i); end
    else if (A = '--doc-contains') and (i < ParamCount) then begin Inc(i); Result.DocContains:= ParamStr(i); end
    else if (A = '--no-docs') then Result.NoDocs:= True
    else if (A = '--kind') and (i < ParamCount) then begin Inc(i); Result.Kind:= ParamStr(i); end
    else if (A = '--public') then Result.PublicOnly:= True
    else if (A = '--depth') and (i < ParamCount) then begin Inc(i); Result.Depth:= StrToIntDef(ParamStr(i), 3); end
    else if A = '--include-impl'   then Result.IncludeImpl   := True
    else if A = '--full-surface'   then Result.FullSurface   := True
    else if A = '--all-visibility' then Result.AllVisibility := True
    else if A = '--coverage'       then Result.WiringCoverage:= True
    else if (A = '--context') and (i < ParamCount) then begin Inc(i); Result.ContextLines:= StrToIntDef(ParamStr(i), 0); end
    else if A = '--resolved' then Result.Resolved:= True // v14 (D5 T8): find-callers --resolved
    // v14 (D5 T11): call-path / callgraph traversal flags.
    else if (A = '--from') and (i < ParamCount) then begin Inc(i); Result.CallFrom:= ParamStr(i); end
    else if (A = '--max-depth') and (i < ParamCount) then begin Inc(i); Result.MaxDepth:= StrToIntDef(ParamStr(i), 20); end
    else if (A = '--direction') and (i < ParamCount) then begin Inc(i); Result.Direction:= ParamStr(i); end
    else if A = '--no-to-persistent' then Result.ToPersistent:= False // proptree: climb past TPersistent/TObject
    else if A = '--no-write-back' then Result.NoWriteBack:= True // proptree: force read-only (no memoization)
    else if (A = '--min-visibility') and (i < ParamCount) then begin Inc(i); Result.MinVisibility:= ParamStr(i); end // proptree/2: --min-visibility published|public
    else if (A = '--surface') and (i < ParamCount) then begin Inc(i); Result.Surface:= ParamStr(i); end // convert-scaffold (Task 5): --surface dfm|pas
    else if (A = '--rules') and (i < ParamCount) then begin Inc(i); Result.RulesFile:= ParamStr(i); end // convert-validate: rules DSL file
    else if (A = '--from-block') and (i < ParamCount) then begin Inc(i); Result.FromBlockFile:= ParamStr(i); end // convert-reemit: F DFM object block file
    else if A = '--print-parsed' then Result.PrintParsed:= True // convert-validate: dump parsed rules
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
        else begin Result.Verb:= 'modify'; Result.BundleQName:= Result.Task; end;
      end
      else begin Result.Verb:= 'modify'; Result.BundleQName:= Result.Task; end;
    end // if
    else if (A = '--max-callers') and (i < ParamCount) then begin Inc(i); Result.MaxCallers:= StrToIntDef(ParamStr(i), 5); end
    else if (A = '--n') and (i < ParamCount) then begin Inc(i); Result.BenchN:= StrToIntDef(ParamStr(i), 20); end
    else if (A = '--to') and (i < ParamCount) then begin Inc(i); Result.RenameTo:= ParamStr(i); end
    else if A = '--no-backup' then Result.NoBackup:= True
    // v0.69 D2a: rename --kind param positional args
    // Note: --kind  already parsed into Result.Kind   (line ~638)
    //       --file  already parsed into Result.InFile (line ~433)
    else if (A = '--line') and (i < ParamCount) then begin Inc(i); Result.RefLine:= StrToIntDef(ParamStr(i), 0); end
    else if (A = '--col' ) and (i < ParamCount) then begin Inc(i); Result.RefCol := StrToIntDef(ParamStr(i), 0); end
    // v0.84: extract-method --from-line/--to-line (1-based, inclusive)
    else if (A = '--from-line') and (i < ParamCount) then begin Inc(i); Result.FromLine:= StrToIntDef(ParamStr(i), 0); end
    else if (A = '--to-line'  ) and (i < ParamCount) then begin Inc(i); Result.ToLine  := StrToIntDef(ParamStr(i), 0); end
    // AutoFix Chunk 1 (Task 3): single-finding fix targeting (lint --fix)
    else if (A = '--fix-line') and (i < ParamCount) then begin Inc(i); Result.FixLine:= StrToIntDef(ParamStr(i), 0); end
    else if (A = '--fix-rule') and (i < ParamCount) then begin Inc(i); Result.FixRule:= ParamStr(i); end
    else if A = '--include-private' then Result.IncludePrivate:= True
    else if (A = '--target') and (i < ParamCount) then begin Inc(i); Result.Target:= ParamStr(i); end
    else if (A = '--shadow') and (i < ParamCount) then begin Inc(i); Result.Shadow:= ParamStr(i); end
    else if A = '--resolve-uses'  then Result.ResolveUsesFlag:= True
    else if A = '--edges'         then Result.Edges          := True
    else if A = '--causes'        then Result.Causes         := True
    else if A = '--plan'          then Result.Plan           := True
    else if A = '--apply'         then Result.Apply          := True
    else if A = '--fix'           then Result.Fix            := True
    else if A = '--remove-unused' then Result.RemoveUnused   := True
    else if (A = '--platform') and (i < ParamCount) then begin Inc(i); Result.CheckPlatform:= ParamStr(i); end
    else if (A = '--framework') and (i < ParamCount) then begin Inc(i); Result.TestFramework:= ParamStr(i); end
    else if (A = '--yadf-path') and (i < ParamCount) then begin Inc(i); Result.YadfPath:= ParamStr(i); end
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
    else if (Result.Command = 'dump-refs') and (Result.Target = '') and (not A.StartsWith('--')) then Result.Target:= A
    else if (Result.Command = 'format'   ) and (Result.Target = '') and (not A.StartsWith('--')) then Result.Target:= A
    else if (Result.Command = 'workspace') and (Result.SubCommand = 'add') and (Result.Target = '') and (not A.StartsWith('--')) then Result.Target:= A
    else if (A = '--dir') and (i < ParamCount) then begin Inc(i); Result.Path:= ParamStr(i); end
    else if (A = '--parent-pid') and (i < ParamCount) then begin Inc(i); Result.ParentPid:= Cardinal(StrToInt64Def(ParamStr(i), 0)); end
    // --unit routes to DocUnit for the `document` command (whole-unit batch),
    // else to GhostUnit (ghost-check overlay). Distinct fields avoid a collision.
    else if (A = '--unit') and (i < ParamCount) then
    begin
      Inc(i);
      if (Result.Command = 'document') or (Result.Command = 'document-all') then Result.DocUnit:= ParamStr(i)
      else Result.GhostUnit:= ParamStr(i);
    end
    // AutoDocument batch: --stubs opt-in (flips the facts-only default for
    // document / document --project / document-all).
    else if A = '--stubs' then Result.DocStubs:= True
    // AutoDocument (ADF T4): --seealso opts in the <seealso> doc-source.
    else if A = '--seealso' then Result.DocSeeAlso:= True
    // AutoDocument (ADF T5): --since opts in the git <since> doc-source; --base-dir
    // sets the repo root for the git lookup (defaults to the file's own dir).
    else if A = '--since' then Result.DocSince:= True
    // Task 5: create-enum-helper --methods <csv> / --tostring rtti|case.
    // Kept as raw strings here; DoCreateEnumHelper parses/validates them (usage
    // errors need access to Writeln/Exit, which the arg parser does not use).
    else if (A = '--methods') and (i < ParamCount) then begin Inc(i); Result.EnumMethodsStr:= ParamStr(i); end
    else if (A = '--tostring') and (i < ParamCount) then begin Inc(i); Result.EnumToString:= ParamStr(i); end
    else if (A = '--base-dir') and (i < ParamCount) then begin Inc(i); Result.DocBaseDir:= ParamStr(i); end
    else if (A = '--buffer') and (i < ParamCount) then begin Inc(i); Result.GhostBuffer:= ParamStr(i); end
    else if (A = '--overlays') and (i < ParamCount) then begin Inc(i); Result.GhostOverlays:= ParamStr(i); end
    // v0.57: text-constant search flags
    else if (A = '--text') and (i < ParamCount) then begin Inc(i); Result.TextQuery:= ParamStr(i); end
    else if (A = '--source') and (i < ParamCount) then begin Inc(i); Result.TextSource:= ParamStr(i); end
    else if A = '--any-order' then Result.TextAnyOrder := True
    else if A = '--substring' then Result.TextSubstring:= True
    // PP-Task-3: dump-pp-eval flags. --expr is the expression; --define and
    // --numeric are repeatable and accumulate into TArrays (parsed in DoDumpPpEval).
    else if (A = '--expr') and (i < ParamCount) then begin Inc(i); Result.PpExpr:= ParamStr(i); end
    else if (A = '--define') and (i < ParamCount) then
    begin
      Inc(i);
      SetLength(Result.PpDefines, Length(Result.PpDefines) + 1);
      Result.PpDefines[High(Result.PpDefines)]:= ParamStr(i);
    end
    else if (A = '--numeric') and (i < ParamCount) then
    begin
      Inc(i);
      SetLength(Result.PpNumeric, Length(Result.PpNumeric) + 1);
      Result.PpNumeric[High(Result.PpNumeric)]:= ParamStr(i);
    end
    // PP-Task-6: preprocess-file include handling mode (off | defines-only).
    else if (A = '--include-mode') and (i < ParamCount) then begin Inc(i); Result.PpIncludeMode:= ParamStr(i); end
    // v1.2.1 port change #2: opt out of nearest-first include resolution.
    else if A = '--no-near-search' then Result.PpNoNearSearch:= True
    // v1.2.1 port change #5: opt into the dcc-tolerance pass.
    else if A = '--tolerances' then Result.PpTolerances:= True
    // PP-Task-7: pp-profile define-profile resolver -- the project whose config
    // defines to resolve (--platform reuses CheckPlatform, --config reuses
    // WorkspaceConfig from the shared arg handlers above).
    else if (A = '--dproj') and (i < ParamCount) then begin Inc(i); Result.PpDproj:= ParamStr(i); end
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
    for R in ARefs do begin Path:= AStore.GetFilePath(R.FileId); Writeln(Format('%s:%d:%d  %s', [Path, R.StartLine, R.StartCol, R.NameText])); end;
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
      if R.ContextText <> '' then begin Writeln('  ' + StringReplace(R.ContextText, sLineBreak, sLineBreak + '  ', [rfReplaceAll])); end;
    end;
    Writeln(Format('%d caller(s)', [Length(ARefs)]));
  end;
end; // procedure

// v0.86 Task 4: open a store READ-ONLY for a query verb and validate its schema
// without any DDL-on-read. Read verbs (outline, query, surface, context,
// dump-refs, find-unit) use this instead of `Create + Migrate`: a read-only open
// cannot mutate the shared index (no stamp, no FTS5 probe, no DROP TRIGGER),
// which is what silently dropped the string_literals sync triggers on the win32
// sqlite3.dll. On a pre-current schema the DB is NOT migrated (read verbs never
// write): AOk is set False and the actionable stale-schema line is printed --
//   index schema v%d < v%d: run "drag-lint index <dir> --db <db>" to migrate
// -- so the caller exits nonzero instead of hitting a "no such column" field
// error. Returns the store (never nil on a successful open); check AOk.
function OpenReadOnlyStore(const ADbPath: string; out AOk: Boolean): ISymbolStore;
var
  Found   : Integer;
  Expected: Integer;
begin
  Result:= TSQLiteSymbolStore.Create(ADbPath, {AReadOnly=}True);
  if Result.IsSchemaCurrent(Found, Expected) then AOk:= True
  else begin AOk:= False; Writeln(Format('index schema v%d < v%d: run "drag-lint index <dir> --db <db>" to migrate', [Found, Expected])); end;
end;

// WRITABLE open (same schema-current guard as OpenReadOnlyStore). Used by
// proptree's default (automatic) write-back so a type recovered by the lazy
// ancestry-bridge is memoized back into the index. Exception-safe: a writable
// open that throws (read-only file, exclusive lock) returns AOk=False + nil so
// the caller can fall back to a read-only open -- the ancestry RESOLUTION still
// works, only the (best-effort) memoization is skipped. NOTE: a normal proptree
// query now opens writable by default; --no-write-back forces read-only.
function OpenWritableStore(const ADbPath: string; out AOk: Boolean): ISymbolStore;
var
  Found   : Integer;
  Expected: Integer;
begin
  AOk:= False;
  try
    Result:= TSQLiteSymbolStore.Create(ADbPath, {AReadOnly=}False);
  except
    Result:= nil; Exit; // writable open failed (locked / read-only file) -> caller falls back
  end;
  if Result.IsSchemaCurrent(Found, Expected) then AOk:= True
  else begin AOk:= False; Writeln(Format('index schema v%d < v%d: run "drag-lint index <dir> --db <db>" to migrate', [Found, Expected])); end;
end;

// AutoDoc multi-DB (Task 6): resolves every --db the user passed (via
// ResolveConsumerDbs) OTHER than the primary AArgs.DbPath, opens each
// read-only, and returns the ones that opened cleanly. Used to populate
// TDocBatchOptions.ExtraStores / BuildFor's AExtraStores so a symbol's
// name-based callers/used-in facts can span multiple index DBs. A store
// that fails to open (schema stale, file missing) is silently skipped --
// this is a facts-enrichment path, not a hard dependency. Returns an empty
// (non-nil) array when the user passed a single --db or none.
function OpenExtraStores(const AArgs: TArgs): TArray<ISymbolStore>;
var
  DbList: TArray<string>;
  D     : string        ;
  EOk   : Boolean       ;
  ES    : ISymbolStore  ;
begin
  SetLength(Result, 0);
  DbList:= ResolveConsumerDbs(AArgs);
  for D in DbList do
    if not SameText(D, AArgs.DbPath) then
    begin
      ES:= OpenReadOnlyStore(D, EOk);
      if EOk and (ES <> nil) then Result:= Result + [ES];
    end;
end;

// Task 10 (Batch A item 1): reads the docs.max_return_cases cap for the doc
// verbs (document / document --project / document-all). Loads the manifest
// the same way ResolveConsumerDbs/size-guard do (TManifestIO.Load(engine dir
// beside the exe, current working dir walking up for a local override)) and
// returns Manifest.Docs.MaxReturnCases. Best-effort: any load failure (missing
// files, malformed JSON) falls back to 20 (TDocSettings.Defaults), so a doc
// verb never errors out over a manifest problem -- it just enumerates with the
// default cap.
function LoadDocMaxReturnCases: Integer;
var
  DocManifest: TIndexManifest;
begin
  Result:= 20;
  try
    DocManifest:= TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
    Result:= DocManifest.Docs.MaxReturnCases;
  except
    Result:= 20;
  end;
end;

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
    else begin JRoots:= TJSONArray.Create; JSecObj.AddPair('roots', JRoots); for S in PS.Roots do JRoots.AddElement(TJSONString.Create(S)); end;

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

/// <summary>PP-Task-9: resolve the define profile the indexer preprocesses
/// against. When a .dproj is given, derive the per-config profile from it
/// (ProfileFromDproj: Base + selected-config DCC_Define, unioned with the
/// platform built-ins); otherwise fall back to PlatformBuiltins for the target
/// platform (default Win64 -- the library/no-project fallback the plan
/// specifies). ADproj '' selects the built-ins path. APlatform '' defaults to
/// Win64 inside the resolver. AConfig '' is treated as Release by
/// ProfileFromDproj.</summary>
/// <param name="ADproj">Path to a .dproj, or '' for the built-ins fallback.</param>
/// <param name="APlatform">Target platform ('Win32'/'Win64'); '' -&gt; Win64.</param>
/// <param name="AConfig">'Release'/'Debug'; '' -&gt; Release. Ignored without a .dproj.</param>
/// <returns>The active define profile for the index run.</returns>
function ResolveIndexProfile(const ADproj, APlatform, AConfig: string): TDefineProfile;
var
  Plat: string;
begin
  Plat:= APlatform;
  if Plat = '' then Plat:= 'Win64'; // library / no-project fallback (plan default)
  if ADproj <> '' then Result:= ProfileFromDproj(ADproj, Plat, AConfig)
  else Result:= Default(TDefineProfile);
  if ADproj = '' then Result.Defines:= PlatformBuiltins(Plat);
end;

// v0.45 Task 7: build one plan item into its SQLite database.
// Creates the Store + Indexer, applies filter + dedup roots, walks per mode,
// then calls ResolveUnitUseTargets. Writes a one-line summary to stdout.
// Returns True on success, False (and prints the error) on failure.
// PP-Task-9: APreprocess (default True) enables per-config directive
// resolution for this section's index. The profile is derived from the
// section's platform (library sections carry it; folder/closure default Win64)
// -- unioned with a .dproj's config defines when the section is a single-project
// closure. --no-preprocess (from index --all) passes False for a raw all-branch
// build.
function BuildPlanItem(const AItem: TPlanSection; const ADocs: TDocConfig; APreprocess: Boolean = True): Boolean;
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

    // PP-Task-9: per-config directive resolution for this section (default ON).
    // A single-project closure section resolves defines from its .dproj; every
    // other section uses the platform built-ins (library sections carry their
    // platform; folder/multi-root sections default to Win64).
    var SectionDproj: string:= '';
    if (AItem.Mode = smClosure) and (Length(AItem.Roots) = 1) and
       SameText(ExtractFileExt(AItem.Roots[0]), '.dproj') then
      SectionDproj:= AItem.Roots[0];
    // Resolve the section profile ONCE and reuse it for both the indexer and
    // (PP-Task-10) the closure resolver, so uses-discovery and symbol-extraction
    // honour the SAME active define profile.
    var SectionProfile: TDefineProfile:= ResolveIndexProfile(SectionDproj, AItem.Platform, '');
    Indexer.SetPreprocess(APreprocess, SectionProfile);

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
            // PP-Task-10: per-config uses-discovery -- honour the SAME profile
            // the indexer uses for this section (default ON; --no-preprocess -> False).
            Cl.SetPreprocess(APreprocess, SectionProfile);
            for F in AItem.Roots do
            begin
              if not TFile.Exists(F) then begin Writeln(Format('  (skip, project file not found) %s', [F])); Continue; end;
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
    Store.ResolveHelpers;  { v15: link record/class helper targets cross-unit }
    Store.ResolveCallTargets; { v14 (D5): resolve call sites to target symbols }
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
    if not TFile.Exists(ConfigPath) then begin Writeln('ERROR: config file not found: ', ConfigPath); Exit(2); end;
    var Content:= TFile.ReadAllText(ConfigPath);
    var RootDir:= ExtractFilePath(TPath.GetFullPath(ConfigPath));
    Manifest:= TManifestIO.ParseText(Content, RootDir);
  end
  else Manifest:= TManifestIO.Load(EngineDir, GetCurrentDir);

  ErrMsg:= TManifestIO.Validate(Manifest);
  if ErrMsg <> '' then begin Writeln(ErrOutput, 'ERROR: manifest invalid: ', ErrMsg); Exit(2); end;

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
    for i:= 0 to High(Plan.Items) do begin var PS2:= Plan.Items[i]; PS2.Filter.MaxFileKB:= AArgs.MaxFileKB; Plan.Items[i]:= PS2; end;
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
        if SameText(PS.Name, OnlyName) then begin Keep:= True; Break; end;
      if Keep then begin SetLength(Filtered, Length(Filtered) + 1); Filtered[High(Filtered)]:= PS; end;
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
    for i:= 0 to High(Plan.Items) do begin if not BuildPlanItem(Plan.Items[i], AArgs.Docs, not AArgs.NoPreprocess) then AnyFailed:= True; end;
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
    for i:= 0 to High(Plan.Items) do begin if not BuildPlanItem(Plan.Items[i], AArgs.Docs, not AArgs.NoPreprocess) then AnyFailed:= True; end;
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
        if SlotDW < DWORD(PoolCount) - 1 then begin ProcHandles[SlotDW]:= ProcHandles[PoolCount - 1]; ProcItemIdx[SlotDW]:= ProcItemIdx[PoolCount - 1]; end;
        Dec(PoolCount);
      end; // while

      // Build child command line.
      ChildCmdLine:= '"' + SelfExe + '" index --all --only "' + Plan.Items[i].Name + '"';
      if Plan.Items[i].Platform <> '' then ChildCmdLine:= ChildCmdLine + ' --platform "' + Plan.Items[i].Platform + '"';
      ChildCmdLine:= ChildCmdLine + ' --config "' + AArgs.WorkspaceConfig + '"' + ' --jobs 1';
      // PP-Task-9: propagate --no-preprocess to the child so a parallel --all
      // build honours the raw all-branch request across every spawned worker.
      if AArgs.NoPreprocess then ChildCmdLine:= ChildCmdLine + ' --no-preprocess';

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
      if SlotDW < DWORD(PoolCount) - 1 then begin ProcHandles[SlotDW]:= ProcHandles[PoolCount - 1]; ProcItemIdx[SlotDW]:= ProcItemIdx[PoolCount - 1]; end;
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
  Manifest : TIndexManifest ;
  Sec      : TIndexSection  ;
  IncPath  : string         ;
  PathNorm : string         ;
  IncNorm  : string         ;
  BestLen  : Integer        ;
  BestDb   : string         ;
  EngineDir: string         ;
  OutDir   : string         ;
  DbRaw    : string         ;
begin
  // Explicit --db always wins.
  if Length(AArgs.DbPaths) > 0 then Exit(AArgs.DbPath);

  BestLen:= -1;
  BestDb:= '';
  try
    EngineDir:= ExtractFilePath(ParamStr(0));
    Manifest:= TManifestIO.Load(EngineDir, AIndexPath);
    PathNorm:= IncludeTrailingPathDelimiter( TPath.GetFullPath(AIndexPath)).ToLower;

    for Sec in Manifest.Sections do
    begin
      // Skip library sections -- never auto-select them for index.
      if SameText(Sec.Source, 'registry-libraries') then Continue;
      for IncPath in Sec.Include do
      begin
        IncNorm:= IncludeTrailingPathDelimiter( TPath.GetFullPath(IncPath)).ToLower;
        if PathNorm.StartsWith(IncNorm) and (Length(IncNorm) > BestLen) then
        begin
          BestLen:= Length(IncNorm);
          // Resolve Db to absolute using manifest OutDir/RootDir if relative.
          DbRaw:= Sec.DB;
          if DbRaw = '' then DbRaw:= Sec.Name + '.sqlite';
          if not TPath.IsPathRooted(DbRaw) then
          begin
            OutDir:= Manifest.OutDir;
            if OutDir <> '' then
            begin
              if TPath.IsPathRooted(OutDir) then BestDb:= TPath.Combine(OutDir, DbRaw)
              else BestDb:= TPath.Combine(TPath.Combine(Manifest.RootDir, OutDir), DbRaw);
            end
            else BestDb:= TPath.Combine(Manifest.RootDir, DbRaw);
          end
          else BestDb:= DbRaw;
        end; // if
      end; // for IncPath
    end; // for Sec
  except
    // Manifest unavailable -- fall through to default.
  end; // try

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
    if not (TDirectory.Exists(AArgs.Path) or TFile.Exists(AArgs.Path)) then begin Writeln('ERROR: path does not exist: ', AArgs.Path); Exit(2); end;
  end;
  if AArgs.ProjectPath <> '' then
  begin
    if not TFile.Exists(AArgs.ProjectPath) then begin Writeln('ERROR: .dproj not found: ', AArgs.ProjectPath); Exit(2); end;
  end;

  var ResolvedDb: string:= ResolveIndexDb(AArgs, IfThen(AArgs.Path <> '', AArgs.Path, GetCurrentDir));
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

  // PP-Task-9: enable the in-process directive preprocessor by default so
  // conditional-compilation branches are resolved PER-CONFIG before parsing;
  // --no-preprocess reverts to the prior raw all-branch behaviour. Profile comes
  // from --project (a .dproj -> per-config defines) when given, else the platform
  // built-ins (--platform, default Win64). Build config defaults to Release.
  var PpPlatform: string:= AArgs.CheckPlatform;
  if PpPlatform = '' then PpPlatform:= 'Win64';
  Indexer.SetPreprocess(not AArgs.NoPreprocess,
    ResolveIndexProfile(AArgs.ProjectPath, AArgs.CheckPlatform, ''));
  if not AArgs.NoPreprocess then Writeln('Preprocess: ON  (per-config directive resolution; platform=', PpPlatform, ')')
  else Writeln('Preprocess: OFF  (--no-preprocess: raw all-branch parsing)');

  { v0.42: cross-dictionary dedup -- exclude any subtree the caller says is
    already covered by another index (library / active-project DB). }
  for var ExDir in AArgs.ExcludeUnder do begin Indexer.AddExcludeRoot(ExDir); Writeln('Excluding subtree: ', ExDir); end;

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

  if AArgs.DryRun then begin Writeln('--dry-run: NOT indexing. Re-run without --dry-run to index.'); Result:= 0; Exit; end;

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
    Store.ResolveHelpers;  { v15: link record/class helper targets cross-unit }
    Store.ResolveCallTargets; { v14 (D5): resolve call sites to target symbols }
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
    if TDirectory.Exists(F) then begin Writeln('  + ', F, '  (recursive, incl. subfolders)'); Indexer.IndexFolder(F, True); end
    else if TFile.Exists(F) then Indexer.IndexFile(F)
    else Writeln('  (skip, not found) ', F);
  end;
  Store.ResolveUnitUseTargets;
  Store.ResolveAncestry; { v11 (M1): link class/interface heritage cross-unit }
  Store.ResolveHelpers;  { v15: link record/class helper targets cross-unit }
  Store.ResolveCallTargets; { v14 (D5): resolve call sites to target symbols }
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
    if TFile.Exists(TPath.Combine(Dir, '.drag-lint.json')) then begin Candidate:= TPath.Combine(Dir, '.drag-lint.json'); Break; end;
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
      if not BuildPlanItem(PS, AArgs.Docs, not AArgs.NoPreprocess) then AnyFailed:= True;

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
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Writeln('Run "drag-lint index <path>" first.'); Exit (2 ); end;

  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(1);

  if AArgs.NoDocs then Syms:= Store.FindUndocumented(AArgs.Kind, AArgs.PublicOnly)
  else if AArgs.DocTag <> '' then Syms:= Store.FindByDocTag(AArgs.DocTag)
  else Syms:= Store.FindByDocContains(AArgs.DocContains);

  for S in Syms do begin FilePath:= Store.GetFilePath(S.FileId); Writeln(System.SysUtils.Format('%s  [%s]  %s:%d', [S.QualifiedName, S.Kind.ToText, FilePath, S.StartLine])); end;

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
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Writeln('Run "drag-lint index <path>" first.'); Exit (2 ); end;

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
      if InFileId > 0 then begin UU:= Store.GetUnitUsesForFile(InFileId); for U in UU do UsedUnits.AddOrSetValue(LowerCase(U.UnitName), True); end;
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
  PathsToScan: TArray<string>         ;
  DbPath     : string                 ;
  Store      : ISymbolStore           ;
  Mode       : string                 ;
  Lim        : Integer                ;
  Matches    : TArray<TStringLitMatch>;
  AllMatches : TArray<TStringLitMatch>;
  M          : TStringLitMatch        ;
  JArr       : TJSONArray             ;
  JObj       : TJSONObject            ;
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
    if not TFile.Exists(DbPath) then begin Writeln('ERROR: database not found: ', DbPath); Writeln('Run "drag-lint index <path>" first.'); Exit (2 ); end;

  SetLength(AllMatches, 0);
  for DbPath in PathsToScan do
  begin
    var RoOk: Boolean;
    Store:= OpenReadOnlyStore(DbPath, RoOk);
    if not RoOk then Continue; { stale DB reported; skip, scan the rest }
    Matches:= Store.SearchText(AArgs.TextQuery, Mode, AArgs.TextSource, Lim);
    for M in Matches do begin SetLength(AllMatches, Length(AllMatches) + 1); AllMatches[High(AllMatches)]:= M; end;
  end;
  if Length(AllMatches) > Lim then SetLength(AllMatches, Lim);

  if AArgs.AsJson then
  begin
    JArr:= TJSONArray.Create;
    try
      for M in AllMatches do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('file_path', M.FilePath );
        JObj.AddPair('start_line', TJSONNumber.Create(M.StartLine));
        JObj.AddPair('start_col' , TJSONNumber.Create(M.StartCol ));
        JObj.AddPair('source'    , M.Source        );
        JObj.AddPair('kind'      , M.Kind          );
        JObj.AddPair('owner_name', M.OwnerName     );
        JObj.AddPair('text'      , M.Text          );
        JObj.AddPair('enclosing' , M.EnclosingQName);
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end; // try
  end // if
  else
  begin
    for M in AllMatches do
      Writeln(Format('%s:%d:%d  [%s/%s]  %s%s', [M.FilePath, M.StartLine, M.StartCol, M.Source, M.Kind, M.Text, IfThen(M.EnclosingQName <> '', '  -> ' + M.EnclosingQName, '')]));
    Writeln(Format('%d match(es)', [Length(AllMatches)]));
  end;
  if Length(AllMatches) > 0 then Result:= 0 else Result:= 1;
end; // function

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
    if not TFile.Exists(DbPath) then begin Writeln('ERROR: database not found: ', DbPath); Writeln('Run "drag-lint index <path>" first.'); Exit (2 ); end;
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
    if AArgs.Name = '' then begin Writeln('ERROR: find-callers requires --name <callee>'); Exit (2 ); end;

    // v14 (D5 T8): --resolved is a pure additive branch -- WITHOUT it, the
    // name-based path below (unchanged) still runs. With it, we resolve
    // --name to its matching target symbol(s) PER STORE and render only the
    // PRECISE callers (via call_edges), grouped by which target they resolved
    // to -- this is what fixes the name-collision noise the plain path has.
    if AArgs.Resolved then
    begin
      var TotalCallers:= 0;
      var JOut: TJSONArray:= nil;
      if AArgs.AsJson then JOut:= TJSONArray.Create;
      try
        for DbPath in PathsToScan do
        begin
          var RoOk: Boolean;
          Store:= OpenReadOnlyStore(DbPath, RoOk);
          if not RoOk then Continue; { stale DB reported; skip, scan the rest }
          var Targets:= Store.FindSymbolsByExactName(AArgs.Name);
          for var T in Targets do
          begin
            var RCallers:= Store.FindResolvedCallers(T.Id);
            if Length(RCallers) = 0 then Continue;
            if not AArgs.AsJson then Writeln(Format('  %s:', [T.QualifiedName]));
            for var RC in RCallers do
            begin
              if AArgs.AsJson then
              begin
                var JObj:= TJSONObject.Create;
                JObj.AddPair('caller_qname', RC.EnclosingQName);
                JObj.AddPair('file'        , RC.Location      );
                JObj.AddPair('confidence'  , RC.Confidence    );
                JObj.AddPair('target_qname', T.QualifiedName  );
                // Location is file-name-only (idempotency design, Task 7); the
                // line number is sourced from the caller SYMBOL's own start
                // line (routine-granular, not the exact call-site line).
                if RC.EnclosingSymbolId > 0 then
                  JObj.AddPair('line', TJSONNumber.Create(Store.GetSymbolById(RC.EnclosingSymbolId).StartLine));
                JOut.AddElement(JObj);
              end
              else Writeln(Format('    %s  (%s)  [%s]', [RC.EnclosingQName, RC.Location, RC.Confidence]));
              Inc(TotalCallers);
            end; // for RC
          end; // for T
        end; // for DbPath
        if AArgs.AsJson then Writeln(JOut.Format(2))
        else if TotalCallers = 0 then Writeln('0 caller(s)');
      finally
        JOut.Free;
      end; // try
      if TotalCallers = 0 then Result:= 1 else Result:= 0;
      Exit;
    end; // if AArgs.Resolved

    var TotalRefs:= 0;
    for DbPath in PathsToScan do
    begin
      var RoOk: Boolean;
      Store:= OpenReadOnlyStore(DbPath, RoOk);
      if not RoOk then Continue; { stale DB reported; skip, scan the rest }
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

  if AArgs.SubCommand = 'hints' then begin Result:= DoQueryHints(AArgs); Exit; end;

  if AArgs.SubCommand = 'find' then begin Result:= DoQueryFind(AArgs); Exit; end;

  // v11 (M1): transitive type ancestry. `--name T` lists T's resolved ancestor
  // closure; adding `--of A` reports whether T descends from / implements A.
  if AArgs.SubCommand = 'ancestors' then
  begin
    if AArgs.Name = '' then begin Writeln('ERROR: query ancestors requires --name <type>'); Exit (2 ); end;
    for DbPath in PathsToScan do
    begin
      var RoOk: Boolean;
      Store:= OpenReadOnlyStore(DbPath, RoOk);
      if not RoOk then Continue; { stale DB reported; skip, scan the rest }
      var StartId : Int64:= 0   ;
      var StartKind: string:= '';
      for S in Store.FindSymbolsByExactName(AArgs.Name) do
        if S.Kind in [skClass, skInterface, skRecord] then begin StartId:= S.Id; StartKind:= S.Kind.ToText; Break; end;
      if StartId <= 0 then Continue; { try the next DB }

      if AArgs.OfName <> '' then
      begin
        var IsDesc:= Store.IsDescendantOf     (AArgs.Name, AArgs.OfName, 0);
        var Impl  := Store.ImplementsInterface(AArgs.Name, AArgs.OfName, 0);
        if AArgs.AsJson then
        begin
          var JO:= TJSONObject.Create;
          try
            JO.AddPair('name', AArgs.Name  );
            JO.AddPair('of'  , AArgs.OfName);
            JO.AddPair('is_descendant', TJSONBool.Create(IsDesc));
            JO.AddPair('implements'   , TJSONBool.Create(Impl  ));
            Writeln(JO.Format(2));
          finally JO.Free; end;
        end
        else Writeln(Format('%s descends %s: %s; implements: %s', [AArgs.Name, AArgs.OfName, BoolToStr(IsDesc, True), BoolToStr(Impl, True)]));
        Exit(0);
      end; // if

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
            AO.AddPair('name' , A.Name);
            AO.AddPair('kind' , A.Kind);
            AO.AddPair('resolved', TJSONBool.Create(A.Resolved));
            Arr.AddElement(AO);
          end;
          JO.AddPair('ancestors', Arr);
          Writeln(JO.Format(2));
        finally JO.Free; end;
      end // if
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
  end; // if

  // Reverse of ancestors: list every class that descends from --of <ancestor>.
  // Aggregates the distinct descendant names across all scanned DBs. One indexed
  // lookup per DB (type_ancestors.ancestor_name). Backs the conversion editor's
  // control-class pickers ("all TControl descendants").
  if AArgs.SubCommand = 'descendants' then
  begin
    if AArgs.OfName = '' then begin Writeln('ERROR: query descendants requires --of <ancestor>'); Exit(2); end;
    var Names: TStringList:= TStringList.Create;
    try
      Names.Sorted:= True; Names.Duplicates:= dupIgnore; Names.CaseSensitive:= False;
      for DbPath in PathsToScan do
      begin
        var RoOk: Boolean;
        Store:= OpenReadOnlyStore(DbPath, RoOk);
        if not RoOk then Continue; { stale DB reported; skip, scan the rest }
        for var Nm in Store.FindDescendantNames(AArgs.OfName) do
          Names.Add(Nm);
      end;
      if AArgs.AsJson then
      begin
        var JO:= TJSONObject.Create;
        try
          JO.AddPair('of', AArgs.OfName);
          var Arr:= TJSONArray.Create;
          for var Nm in Names do Arr.Add(Nm);
          JO.AddPair('descendants', Arr);
          Writeln(JO.Format(2));
        finally JO.Free; end;
      end
      else
      begin
        for var Nm in Names do Writeln(Nm);
        if Names.Count = 0 then Writeln('(none)');
      end;
    finally
      Names.Free;
    end;
    if Names.Count = 0 then Result:= 1 else Result:= 0;
    Exit;
  end; // if

  // v11 (M1): resolve a type name to its broad category (intrinsic / declared /
  // alias-chased). Useful standalone and as the test surface for the resolver.
  if AArgs.SubCommand = 'typecat' then
  begin
    if AArgs.Name = '' then begin Writeln('ERROR: query typecat requires --name <type>'); Exit (2 ); end;
    var RoOk: Boolean;
    Store:= OpenReadOnlyStore(PathsToScan[0], RoOk);
    if not RoOk then Exit(1);
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
  end; // if

  if AArgs.SubCommand <> '' then begin Writeln('ERROR: unknown query subcommand: ', AArgs.SubCommand); Exit(2); end;

  if (AArgs.QName = '') and (AArgs.Name = '') then begin Writeln('ERROR: query requires --name or --qname'); Exit (2 ); end;

  for DbPath in PathsToScan do
  begin
    var RoOk: Boolean;
    Store:= OpenReadOnlyStore(DbPath, RoOk);
    if not RoOk then Continue; { stale DB reported; skip, scan the rest }
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
      var RoOk: Boolean;
      Store:= OpenReadOnlyStore(DbPath, RoOk);
      if not RoOk then Continue; { stale DB reported; skip, scan the rest }
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
      if Row.EnumQName <> LastEnum then begin Ord:= 0; LastEnum:= Row.EnumQName; end;
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
      if R.EnumQName <> LastEnum then begin FlushBlock; LastEnum:= R.EnumQName; end;
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
  if AArgs.DbPath = '' then begin Writeln('ERROR: export enums requires --db <file.sqlite>'); Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
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
    else begin Writeln('ERROR: unknown format: ', Fmt); Exit(2); end;
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
  if not TFile.Exists(ObsCfg) then begin Writeln('  (Obsidian config not found at ', ObsCfg, ' - is Obsidian installed?)'); Exit; end;
  Cfg:= nil;
  try
    try
      Body:= TFile.ReadAllText(ObsCfg, TEncoding.UTF8);
      Cfg:= TJSONObject.ParseJSONValue(Body) as TJSONObject;
    except
      Cfg:= nil;
    end;
    if Cfg = nil then begin Writeln('  (could not parse ', ObsCfg, ')'); Exit; end;

    Vaults:= Cfg.GetValue('vaults') as TJSONObject;
    if Vaults = nil then begin Vaults:= TJSONObject.Create; Cfg.AddPair('vaults', Vaults); end;

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
          if SameText(Existing, AbsPath) then begin AlreadyRegistered:= True; Break; end;
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
  if AArgs.DbPath = '' then begin Writeln('ERROR: export obsidian requires --db'); Exit (2 ); end;
  if AArgs.OutputDir = '' then begin Writeln('ERROR: export obsidian requires --output-dir <dir>'); Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
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
        while not Q.Eof do begin UnitName:= Q.FieldByName('unit_name').AsString; UnitsByName.AddOrSetValue(UnitName, ObsidianSanitizeFilename(UnitName)); Q.Next; end;
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
  if AArgs.DbPath = '' then begin Writeln('ERROR: top requires --db'); Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
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
  if AArgs.Path = '' then begin Writeln('ERROR: import-log requires a <logfile> argument'); Exit (2 ); end;
  if AArgs.DbPath = '' then begin Writeln('ERROR: import-log requires --db'); Exit (2 ); end;
  LogPath:= AArgs.Path;
  if not TFile.Exists(LogPath) then begin Writeln('ERROR: log file not found: ', LogPath); Exit(2); end;

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
        if not FileQ.IsEmpty then begin FileId:= FileQ.FieldByName('id').AsLargeInt; Inc(MatchedFile); end;
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
  if AArgs.DbPath = '' then begin Writeln('ERROR: query hints requires --db'); Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
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
  else begin Writeln('ERROR: unknown export subcommand: ', AArgs.SubCommand); Writeln('Available: enums, obsidian'); Result:= 2; end;
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
  if AArgs.DbPath = '' then begin Writeln('ERROR: graph requires --db'); Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
  if AArgs.Format <> '' then Format:= LowerCase(AArgs.Format)
  else Format:= 'dot';
  if (Format <> 'dot') and (Format <> 'mermaid') then begin Writeln('ERROR: graph supports --format dot|mermaid (got "', Format, '")'); Exit(2); end;
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
    if AArgs.Output <> '' then begin TFile.WriteAllText(AArgs.Output, Output); Writeln('Wrote ', AArgs.Output); end
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
  if Length(AArgs.DbPaths) < 2 then begin Writeln('ERROR: diff requires two --db arguments ' + '(--db <old.sqlite> --db <new.sqlite>)'); Exit(2); end;
  DbA:= AArgs.DbPaths[0];
  DbB:= AArgs.DbPaths[1];
  if not TFile.Exists(DbA) then begin Writeln('ERROR: --db ', DbA, ' not found'); Exit(2); end;
  if not TFile.Exists(DbB) then begin Writeln('ERROR: --db ', DbB, ' not found'); Exit(2); end;

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
    while not QA.Eof do begin SetA.AddOrSetValue( QA.FieldByName('qualified_name').AsString, QA.FieldByName('kind').AsString + '|' + QA.FieldByName('sig').AsString); QA.Next; end;
    QB.Open;
    while not QB.Eof do begin SetB.AddOrSetValue( QB.FieldByName('qualified_name').AsString, QB.FieldByName('kind').AsString + '|' + QB.FieldByName('sig').AsString); QB.Next; end;

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
        if not SetA.ContainsKey(Pair.Key) then begin Tag:= Pair.Value.Split(['|'])[0]; Writeln('+ ', Pair.Key, '  [', Tag, ']'); Inc(Added); end
      else if SetA[Pair.Key] <> Pair.Value then begin Writeln('~ ', Pair.Key); Writeln('    from: ', SetA[Pair.Key]); Writeln('    to:   ', Pair.Value); Inc(Changed); end;
      for Pair in SetA do
        if not SetB.ContainsKey(Pair.Key) then begin Tag:= Pair.Value.Split(['|'])[0]; Writeln('- ', Pair.Key, '  [', Tag, ']'); Inc(Removed); end;
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
  if not (TDirectory.Exists(Path) or TFile.Exists(Path)) then begin Writeln('ERROR: path does not exist: ', Path); Exit(2); end;
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
  Dbs  : TArray<string> ;
  Db   : string         ;
  UsedDb: string        ;
begin
  if AArgs.QName = '' then begin Writeln('Usage: drag-lint hover --qname <Foo.Bar> [--db <path>] ' + '[--format md|plain|json]'); Exit(2); end;

  // v0.94.1 BUGFIX: hover must search ALL --db paths, not just one. The IDE (and
  // manifest resolution) pass several --db values -- e.g. a project index, a SQL
  // index, and a platform library index. The old code used AArgs.DbPath, which
  // the parser sets to the LAST --db, so hovering a symbol that lives in an
  // EARLIER db returned "No symbol matched" and the IDE silently fell back to the
  // plain string popup. Now: iterate every resolved db and use the FIRST one that
  // contains the qname (mirrors how query find-callers walks multiple dbs).
  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.'); Exit(2); end;

  Store := nil;
  UsedDb:= '';
  SetLength(Syms, 0);
  for Db in Dbs do
  begin
    if not TFile.Exists(Db) then Continue;
    Store:= TSQLiteSymbolStore.Create(Db);
    Store.Migrate;
    Syms:= Store.FindSymbolsByQualifiedName(AArgs.QName);
    if Length(Syms) > 0 then begin UsedDb:= Db; Break; end;
    Store:= nil; { release before trying the next db }
  end;
  if (Length(Syms) = 0) or (Store = nil) then begin Writeln(System.SysUtils.Format('No symbol matched qname: %s', [AArgs.QName])); Exit(1); end;

  Doc:= Store.GetSymbolDoc(Syms[0].Id);
  { v0.43: no doc comment is no longer fatal -- the renderer still shows the
    qualified name + an IDE-style Parameters block parsed from the signature,
    which is exactly what the LSP hover does. }

  // v0.95: mine Result:= / Exit() RHS from the routine body span (if any).
  var Rhs: TArray<string>;
  SetLength(Rhs, 0);
  if (Syms[0].ImplStartLine > 0) and (Syms[0].ImplEndLine >= Syms[0].ImplStartLine) then
  begin
    var Path: string:= Store.GetFilePath(Syms[0].FileId);
    if (Path <> '') and TFile.Exists(Path) then
    begin
      var AllLines: TArray<string>:= TFile.ReadAllLines(Path, TEncoding.ANSI);
      var Lo: Integer:= Syms[0].ImplStartLine - 1; // 1-based -> 0-based
      var Hi: Integer:= Syms[0].ImplEndLine   - 1;
      if Lo < 0 then Lo:= 0;
      if Hi > High(AllLines) then Hi:= High(AllLines);
      var Body: TArray<string>;
      if Hi < Lo then
        SetLength(Body, 0)   // stale/invalid span -> no returns, no crash
      else
      begin
        SetLength(Body, Hi - Lo + 1);
        for var k:= Lo to Hi do Body[k - Lo]:= AllLines[k];
      end;
      Rhs:= MineReturnExpressions(Body);
    end;
  end;

  var UnitFile: string:= ExtractFileName(Store.GetFilePath(Syms[0].FileId));
  var Model: THoverModel:= BuildHoverModel(Syms[0], Doc, UnitFile, Rhs);

  Fmt:= LowerCase(AArgs.Format);
  if Fmt = '' then Fmt:= 'plain';

  if Fmt      = 'json' then Write(DRagLint.Hover.Renderer.RenderHoverJson(Model))
  else if Fmt = 'md' then Write(RenderHoverMarkdown(Syms[0], Doc))
  else Write(RenderHoverPlain(Syms[0], Doc));
  Result:= 0;
end; // function

// v0.95 Task 1: hidden self-test verb for the WCAG contrast unit (no --db,
// no fixture -- just known-answer ratios so the .ps1 can assert without an index).
function DoContrastSelfTest: Integer;
begin
  // Known-answer lines: NAME=<ratio to 2dp> and READABLE=<hex of EnsureReadable>.
  Writeln(Format('BLACK_ON_WHITE=%.2f', [ContrastRatio(clBlack, clWhite)]));      // 21.00
  Writeln(Format('SAME=%.2f',           [ContrastRatio(clRed, clRed)]));          // 1.00
  // #0B57D0 keyword-blue on a dark (#1E1E1E) bg fails 4.5; EnsureReadable fixes it.
  Writeln(Format('DARKFAIL=%.2f',       [ContrastRatio($00D0570B, $001E1E1E)]));  // < 4.5
  Writeln(Format('FIXED=%.2f',
    [ContrastRatio(EnsureReadable($00D0570B, $001E1E1E, 4.5), $001E1E1E)]));       // >= 4.5
  Result:= 0;
end;

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
  if DbToUse = '' then begin Writeln('ERROR: no drag-lint index found (tried ', Length(Dbs), ' resolved path(s)). Pass --db <file.sqlite> or build the index first.'); Exit(2); end;
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
  if AArgs.QName = '' then begin Writeln('Usage: drag-lint impact --qname <Qualified.Name> ' + '[--depth N] [--db <path>] [--format text|json]'); Exit(2); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Writeln('Run "drag-lint index <path>" first.'); Exit (2 ); end;
  Depth:= AArgs.Depth;
  if Depth <= 0 then begin Writeln(AArgs.QName); Writeln('  (depth 0 returns nothing)'); Exit (1 ); end;
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
    if Length(Levels) = 0 then begin Writeln('  (no callers)'); Exit (1 ); end;
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
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Writeln('Run "drag-lint index <path>" first.'); Exit (2 ); end;

  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(1);

  // Validate that the symbol exists and is a class/record/interface.
  Syms:= Store.FindSymbolsByQualifiedName(AArgs.QName);
  if Length(Syms) = 0 then begin Writeln(System.SysUtils.Format('No symbol matched qname: %s', [AArgs.QName])); Exit(1); end;
  if not (Syms[0].Kind in [skClass, skRecord, skInterface]) then
  begin
    Writeln(System.SysUtils.Format( 'Symbol %s has kind "%s"; surface requires a class, record, or interface.', [Syms[0].QualifiedName, Syms[0].Kind.ToText]));
    Exit(2);
  end;

  Lines:= Store.GetClassSurface(AArgs.QName, AArgs.IncludeImpl, AArgs.AllVisibility);
  if Length(Lines) = 0 then begin Writeln('(no surface lines returned)'); Exit (1 ); end;

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
  else begin for L in Lines do Writeln(L.Text); end;
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
  if AArgs.InFile = '' then begin Writeln('Usage: drag-lint outline --file <path.pas> ' + '[--db <path>] [--format text|json]'); Exit(2); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Writeln('Run "drag-lint index <path>" first.'); Exit (2 ); end;

  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(1);
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
  else begin for S in Syms do Writeln(System.SysUtils.Format('%-10s %-40s %d', [S.Kind.ToText, S.QualifiedName, S.StartLine])); end;
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
  if AArgs.Name = '' then begin Writeln('Usage: drag-lint usages --name <X> ' + '[--width narrow|wide|very-wide] [--db <path>] [--depth N] [--format json]'); Exit(2); end;
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
  if AArgs.QName = '' then begin Writeln('Usage: drag-lint slice --qname <Foo.TBar> ' + '[--db <path>] [--format text|json]'); Exit(2); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Writeln('Run "drag-lint index <path>" first.'); Exit (2 ); end;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Slice:= Store.GetSymbolSlice(AArgs.QName);

  if Length(Slice) = 0 then begin Writeln(System.SysUtils.Format( 'No slice returned for qname: %s', [AArgs.QName])); Exit(1); end;

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
    for C in Slice do begin Writeln('--- ', C.Kind, ' ---'); Writeln(C.Text); end;
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
  Lines     : TArray<string>                     ;
  Kept      : TList<TLintFinding>                ;
  F         : TLintFinding                       ;
  LineTxt   : string                             ;
  Rest      : string                             ;
  Tok       : string                             ;
  Toks      : TArray<string>                     ;
  CPos      : Integer                            ;
  MPos      : Integer                            ;
  Suppressed: Boolean                            ;
begin
  if Length(AFindings) = 0 then Exit(AFindings);
  LineCache:= TDictionary<string, TArray<string>>.Create;
  Kept:= TList<TLintFinding>.Create;
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
              if SameText(Trim(Tok), F.RuleId) then begin Suppressed:= True; Break; end;
          end;
        end;
      end; // if
      if not Suppressed then Kept.Add(F);
    end; // for
    Result:= Kept.ToArray;
  finally
    Kept.Free;
    LineCache.Free;
  end; // try
end; // function

/// <summary>Builds the effective TLintConfig for a command: discovers the config
/// file (--config, else drag-lint-lint.json in CWD), applies the named --profile,
/// and composes --disable/--enable from the command line.</summary>
function LoadLintConfig(const AArgs: TArgs): TLintConfig;
var
  Path: string;
begin
  Path:= AArgs.ConfigPath;
  if (Path = '') and TFile.Exists('drag-lint-lint.json') then Path:= 'drag-lint-lint.json';
  Result:= TLintConfig.Load(Path, AArgs.Profile);
  if AArgs.Disable <> '' then Result.AddDisabled(AArgs.Disable.Split([',', ' ', ';']));
  if AArgs.Enable  <> '' then Result.AddEnabled (AArgs.Enable .Split([',', ' ', ';']));
end;

{ The set of rule-ids that have a registered, mechanical, side-effect-free
  quick-fix. Single source of truth for both the rules-catalog 'fixable' flag
  and the fix verbs. Widening AutoFix = add an id here AND a branch in
  BuildAutofixEdits (kept in lockstep; a guard test asserts they agree).
  EXCEPTION: store-backed fixes (doc-drift, missing-doc, method-pascalcase,
  local-var-casing, const-casing, field-name-prefix, param-name-prefix,
  type-name-prefix) are fixable but have NO BuildAutofixEdits branch --
  doc-drift/missing-doc edits come from TDocumenter.BuildFor and the naming
  re-casing/prefix-adding edits come from DRagLint.Refactor.NamingFix.Build-
  NamingFixEdits (the rename engine), both via a store-backed append in
  FinalizeAndOutput, not from the pure-text edit builder. }
const
  FIXABLE_RULE_IDS: array[0..16] of string = (
    'self-assignment', 'redundant-parentheses', 'redundant-cast', 'redundant-not-not', 'redundant-as-tobject', 'boolean-comparison-true', 'reserved-word-casing',
    'redundant-assigned-free', 'off-by-one-count', 'doc-drift', 'missing-doc',
    'method-pascalcase', 'local-var-casing', 'const-casing',
    'field-name-prefix', 'param-name-prefix', 'type-name-prefix');

function IsFixableRule(const ARuleId: string): Boolean;
var
  S: string;
begin
  for S in FIXABLE_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result:= False;
end;

function FixableRuleIds: TArray<string>;
var
  i: Integer;
begin
  SetLength(Result, Length(FIXABLE_RULE_IDS));
  for i:= 0 to High(FIXABLE_RULE_IDS) do Result[i]:= FIXABLE_RULE_IDS[i];
end;

{ Behaviour-CHANGING fixes: still applied by Fix-it/Fix-all, but tagged so a
  human/AI orchestrator is warned. Currently only off-by-one-count (appends
  ' - 1' to a loop bound, which breaks an intentionally-inclusive loop). }
const
  RISKY_FIX_RULE_IDS: array[0..0] of string = ('off-by-one-count');

  /// <summary>True iff the rule's registered fix is behaviour-CHANGING (not merely
  /// a redundant-code cleanup). Such fixes are still applied, but callers surface a
  /// 'risky' flag so a human/AI reviews before trusting a batch apply.</summary>
function IsRiskyFixRule(const ARuleId: string): Boolean;
var
  S: string;
begin
  for S in RISKY_FIX_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result:= False;
end;

{ Fixable rules whose fix is offered ONLY for a single targeted finding (the IDE
  "Fix it" on one decl, or `lint-all --fix --fix-line/--fix-rule`), and DELIBERATELY
  EXCLUDED from the blanket batch (`lint-all --fix` / "Fix all"). Currently only
  missing-doc: batch-documenting every undocumented decl project-wide is what
  `document --project` is for (facts-only default + --stubs control); folding it
  into the blanket batch would inject TODO stubs across a whole project. }
const
  SINGLE_FIX_ONLY_RULE_IDS: array[0..0] of string = ('missing-doc');

  /// <summary>True iff the rule's registered fix is SINGLE-FIX-ONLY: applied for a
  /// single targeted finding (IDE "Fix it" / --fix-line + --fix-rule) but excluded
  /// from the blanket `lint-all --fix` batch so it does not mass-inject edits.</summary>
function IsSingleFixOnlyRule(const ARuleId: string): Boolean;
var
  S: string;
begin
  for S in SINGLE_FIX_ONLY_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result:= False;
end;

/// <summary>True iff S (trimmed) needs NO extra parentheses to be the operand of
/// a unary 'not'. That holds when S is either (a) a lone primary term -- an
/// identifier or dotted chain, optionally followed only by balanced call '(...)'
/// / index '[...]' groups and '.ident' segments, with NO top-level operator and
/// NO top-level whitespace -- OR (b) already a single fully-enclosing '(...)'
/// group (the opening paren balances exactly at the last character).
/// Errs toward False (compound): over-wrapping 'not (X)' is harmless, but
/// under-wrapping 'not a and b' silently changes meaning.</summary>
function IsSingleTokenAtom(const S: string): Boolean;
var
  T    : string                           ;
  i    : Integer                          ;
  Depth: Integer                          ;
  C    : Char                             ;
  function IsIdentStart(Ch: Char): Boolean;
  begin Result:= CharInSet(Ch, ['A'..'Z','a'..'z','_']); end;
  function IsIdentChar(Ch: Char): Boolean;
  begin Result:= CharInSet(Ch, ['A'..'Z','a'..'z','_','0'..'9']); end;
begin
  T:= Trim(S);
  if T = '' then Exit(False);

  { (b) already a single fully-enclosing '(...)' group: the leading '(' must
    balance to depth 0 only at the very last character (so '(a) and (b)' does
    NOT qualify -- its first '(' closes mid-string). }
  if T[1] = '(' then
  begin
    Depth:= 0;
    for i:= 1 to Length(T) do
    begin
      if T[i]      = '(' then Inc(Depth)
      else if T[i] = ')' then
      begin
        Dec(Depth);
        if (Depth = 0) then Exit(i = Length(T)); { balanced only at the end => atomic }
      end;
    end;
    Exit(False); { unbalanced }
  end;

  { (a) lone primary term. }
  if not IsIdentStart(T[1]) then Exit(False);
  Depth:= 0;
  i    := 1;
  while i <= Length(T) do
  begin
    C:= T[i];
    if (C = '(') or (C = '[') then Inc(Depth)
    else if (C = ')') or (C = ']') then begin Dec(Depth); if Depth < 0 then Exit(False); end
    else if Depth = 0 then
    begin
      { at top level, only identifier chars and a '.' between segments are allowed;
        anything else (whitespace, operator char, ',', ':', etc.) => compound. }
      if not (IsIdentChar(C) or (C = '.')) then Exit(False);
    end;
    Inc(i);
  end;
  Result:= (Depth = 0);
end; // begin

/// <summary>Builds the quick-fix text edits for the subset of AFindings whose
/// rule has a registered autofix (the FIXABLE_RULE_IDS set). Mechanical, no
/// type info:
///   self-assignment       -> delete the offending statement line(s);
///   redundant-parentheses -> strip the outer '(' ')' of the flagged span;
///   redundant-cast        -> strip a 'TFoo(x)' cast where x is one identifier;
///   redundant-not-not     -> strip the two leading 'not' keywords;
///   redundant-as-tobject  -> strip the ' as TObject' suffix;
///   boolean-comparison-true -> X=True/X&lt;&gt;False->X; X=False/X&lt;&gt;True->not X;
///   reserved-word-casing  -> lowercase the keyword token;
///   redundant-assigned-free -> drop the 'if Assigned(X) then' guard;
///   off-by-one-count      -> append ' - 1' to the loop bound (RISKY).
/// AFixableCount returns how many findings produced a fix. Rules without a fix
/// are silently skipped.</summary>
/// <remarks>Deliberately conservative: only rules whose fix is an exact,
/// side-effect-free text edit are wired. redundant-parentheses is fixed only
/// when the flagged span is single-line and literally starts with '(' and ends
/// with ')'. Best for non-overlapping findings; same-line multi-fixes are not
/// column-reconciled (the applier orders by line).</remarks>
function BuildAutofixEdits(const AFindings: TArray<TLintFinding>; out AFixableCount: Integer): TArray<TTextEdit>;
var
  F    : TLintFinding                    ;
  E    : TTextEdit                       ;
  EndL : Integer                         ;
  Cache: TDictionary<string, TStringList>;
  SL   : TStringList                     ;
  Ln   : string                          ;
  Span : string                          ;
  Repl : string                          ;

  function LinesFor(const APath: string): TStringList;
  begin
    if not Cache.TryGetValue(APath, Result) then
    begin
      Result:= TStringList.Create;
      if TFile.Exists(APath) then Result.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(APath));
      Cache.Add(APath, Result);
    end;
  end;
begin
  Result:= nil;
  AFixableCount:= 0;
  Cache:= TDictionary<string, TStringList>.Create;
  try
    for F in AFindings do
    begin
      if SameText(F.RuleId, 'self-assignment') then
      begin
        EndL:= F.EndLine;
        if EndL < F.StartLine then EndL:= F.StartLine;
        E:= Default(TTextEdit);
        E.FilePath:= F.FilePath;
        E.Kind:= tekDeleteLines;
        E.Line:= F.StartLine;
        E.EndLine:= EndL;
        Result:= Result + [E];
        Inc(AFixableCount);
      end
      else if SameText(F.RuleId, 'redundant-parentheses') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if (Length(Span) >= 2) and (Span[1] = '(') and (Span[Length(Span)] = ')') then
          begin
            Repl:= Copy(Span, 2, Length(Span) - 2); { strip the outer parens }
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind:= tekReplaceInLine;
            E.Line  := F.StartLine;
            E.Col   := F.StartCol;
            E.EndCol:= F.EndCol;
            E.Text:= Repl;
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'redundant-cast') and (F.StartLine = F.EndLine) then
      begin
        { redundant-cast fires only on 'TFoo(x)' with x a SINGLE identifier (the
          rule's precondition), so there is no nested paren: the ')' is the first
          one after the '('. The finding span [StartCol, EndCol) covers the entity
          name 'TFoo'; scan on to '(' then to ')' and replace 'TFoo(x)' with 'x'. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          var OpenP: Integer:= F.EndCol; { 1-based; '(' expected at/after the name }
          while (OpenP <= Length(Ln)) and (Ln[OpenP] <> '(') do Inc(OpenP);
          if (OpenP <= Length(Ln)) and (Ln[OpenP] = '(') then
          begin
            var CloseP: Integer:= OpenP + 1;
            while (CloseP <= Length(Ln)) and (Ln[CloseP] <> ')') do Inc(CloseP);
            if (CloseP <= Length(Ln)) and (Ln[CloseP] = ')') then
            begin
              var Inner: string:= Trim(Copy(Ln, OpenP + 1, CloseP - OpenP - 1));
              if Inner <> '' then
              begin
                E:= Default(TTextEdit);
                E.FilePath:= F.FilePath;
                E.Kind:= tekReplaceInLine;
                E.Line:= F.StartLine;
                E.Col := F.StartCol;
                E.EndCol:= CloseP + 1; { exclusive end -- one past the ')' }
                E.Text:= Inner;
                Result:= Result + [E];
                Inc(AFixableCount);
              end;
            end;
          end; // if
        end; // if
      end // if
      else if SameText(F.RuleId, 'redundant-not-not') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'not not X' (the outer exprUnary). Strip the two leading
          'not' keywords + their trailing whitespace; the remainder is X. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Rest: string:= Span;
          var Ok: Boolean:= True ;
          { consume 'not' then >=1 whitespace, twice }
          for var Pass: Integer:= 1 to 2 do
          begin
            var LR: string:= TrimLeft(Rest);
            if (Length(LR) >= 3) and SameText(Copy(LR, 1, 3), 'not') and ((Length(LR) = 3) or (LR[4] <= ' ')) then Rest:= TrimLeft(Copy(LR, 4, MaxInt))
            else
            begin Ok:= False; Break; end;
          end;
          if Ok and (Rest <> '') then
          begin
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind:= tekReplaceInLine;
            E.Line  := F.StartLine;
            E.Col   := F.StartCol;
            E.EndCol:= F.EndCol;
            E.Text:= Rest;
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'redundant-as-tobject') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'X as TObject' (the exprBinary). Find the depth-0 whole-word
          'as' keyword; the lhs before it is X. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          { scan for ' as ' at bracket depth 0 (whole word, case-insensitive) }
          var Depth: Integer:= 0;
          var AsPos: Integer:= 0;
          for var K: Integer:= 2 to Length(Span) - 2 do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if (Depth = 0) and (Span[K - 1] <= ' ') and SameText(Copy(Span, K, 2), 'as') and ((K + 2 > Length(Span)) or (Span[K + 2] <= ' ')) then
            begin AsPos:= K; Break; end;
          end;
          if AsPos > 1 then
          begin
            Repl:= TrimRight(Copy(Span, 1, AsPos - 1));
            if Repl <> '' then
            begin
              E:= Default(TTextEdit);
              E.FilePath:= F.FilePath;
              E.Kind:= tekReplaceInLine;
              E.Line  := F.StartLine;
              E.Col   := F.StartCol;
              E.EndCol:= F.EndCol;
              E.Text:= Repl;
              Result:= Result + [E];
              Inc(AFixableCount);
            end;
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'boolean-comparison-true') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'X op bool', op is '=' or '<>', bool is True or False.
          Scan for the LAST depth-0 '=' or '<>' operator; split into lhs/op/rhs.
          positive (= True / <> False) -> lhs; negative (= False / <> True) ->
          'not ' + (lhs, parenthesized when not a single-token atom). }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Depth: Integer:= 0;
          var OpPos: Integer:= 0;
          var OpLen: Integer:= 0;
          for var K: Integer:= 1 to Length(Span) do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if Depth = 0 then
            begin
              if (K < Length(Span)) and (Ch = '<') and (Span[K + 1] = '>') then
              begin OpPos:= K; OpLen:= 2; end
              else if Ch = '=' then
              begin OpPos:= K; OpLen:= 1; end;
            end;
          end;
          if OpPos > 1 then
          begin
            var LhsText: string:= Trim(Copy(Span, 1, OpPos - 1))         ;
            var OpText : string:= Copy(Span, OpPos, OpLen)               ;
            var RhsText: string:= Trim(Copy(Span, OpPos + OpLen, MaxInt));
            var IsTrue : Boolean:= SameText(RhsText, 'True' );
            var IsFalse: Boolean:= SameText(RhsText, 'False');
            var Positive: Boolean                                        ;
            if (LhsText <> '') and (IsTrue or IsFalse) then
            begin
              { (= True) or (<> False) => positive; (= False) or (<> True) => negative }
              if OpText = '=' then Positive:= IsTrue else Positive:= IsFalse;
              if Positive then Repl:= LhsText
              else if IsSingleTokenAtom(LhsText) then Repl:= 'not ' + LhsText
              else Repl:= 'not (' + LhsText + ')';
              E:= Default(TTextEdit);
              E.FilePath:= F.FilePath;
              E.Kind:= tekReplaceInLine;
              E.Line  := F.StartLine;
              E.Col   := F.StartCol;
              E.EndCol:= F.EndCol;
              E.Text:= Repl;
              Result:= Result + [E];
              Inc(AFixableCount);
            end; // if
          end; // if
        end; // if
      end // if
      else if SameText(F.RuleId, 'reserved-word-casing') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers the keyword token; keywords are case-insensitive and have no
          reference sites, so lowercasing the span is a safe local edit. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if (Span <> '') and (Span <> LowerCase(Span)) then
          begin
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind:= tekReplaceInLine;
            E.Line  := F.StartLine;
            E.Col   := F.StartCol;
            E.EndCol:= F.EndCol;
            E.Text:= LowerCase(Span);
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'redundant-assigned-free') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'if Assigned(X) then <stmt>;'. Take the text after the
          delimited 'then' keyword (whole word, not a substring of an identifier)
          to end of span. The Assigned guard is redundant -- Free is nil-safe. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Depth  : Integer:= 0;
          var ThenEnd: Integer:= 0; { 1-based index one past the 'then' }
          var LS: string:= LowerCase(Span);
          for var K: Integer:= 1 to Length(Span) - 3 do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if (Depth = 0) and (Copy(LS, K, 4) = 'then') and ((K = 1) or (Span[K - 1] <= ' ') or (Span[K - 1] = ')')) and ((K + 4 > Length(Span)) or (Span[K + 4] <= ' ')) then
            begin ThenEnd:= K + 4; Break; end;
          end;
          if ThenEnd > 0 then
          begin
            Repl:= TrimLeft(Copy(Span, ThenEnd, MaxInt));
            if Repl <> '' then
            begin
              E:= Default(TTextEdit);
              E.FilePath:= F.FilePath;
              E.Kind:= tekReplaceInLine;
              E.Line  := F.StartLine;
              E.Col   := F.StartCol;
              E.EndCol:= F.EndCol;
              E.Text:= Repl;
              Result:= Result + [E];
              Inc(AFixableCount);
            end;
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'off-by-one-count') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers the loop end-bound (X.Count / Length(X)). Append ' - 1'.
          BEHAVIOUR-CHANGING (tagged risky via IsRiskyFixRule). The bound is
          isolated by 'to .. do', so no precedence hazard. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if Trim(Span) <> '' then
          begin
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind:= tekReplaceInLine;
            E.Line  := F.StartLine;
            E.Col   := F.StartCol;
            E.EndCol:= F.EndCol;
            E.Text:= Span + ' - 1';
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end; // if
      end; // if
    end; // for
  finally
    for SL in Cache.Values do SL.Free;
    Cache.Free;
  end; // try
end; // begin

/// <summary>Shared output tail for the finding-producing commands. Applies line
/// suppressions, config (severity remap + enable/disable), and the baseline, then
/// emits the survivors as SARIF, JSON, or -- via AEmitText -- the command's own
/// text, and returns the policy exit code.</summary>
/// <param name="AArgs">Parsed CLI args (format, fail-on, baseline, config...).</param>
/// <param name="AFindings">Raw findings the command produced.</param>
/// <param name="ADefaultDisabled">Off-by-default rule ids (TLinter.DefaultDisabledRuleIds), or nil.</param>
/// <param name="AEmitText">Renders the text output for this command; called only on the text path.</param>
/// <returns>The process exit code.</returns>
/// <remarks>v0.81 review Minor: the --fail-on-absent default exit code is derived
/// from the post-ShouldKeep/baseline Survivors set computed inside this function,
/// not from the caller's raw AFindings -- so a bare command whose only matches were
/// OFF-by-default (suppressed) rules prints "0 finding(s)" AND exits 0.</remarks>
function FinalizeAndOutput(const AArgs: TArgs; AFindings: TArray<TLintFinding>; const ADefaultDisabled: TArray<string>; const AEmitText: TProc<TArray<TLintFinding>>;
  const AStore: ISymbolStore = nil): Integer;
var
  Cfg      : TLintConfig         ;
  Survivors: TArray<TLintFinding>;
  F        : TLintFinding        ;
  MF       : TLintFinding        ;
  IsDefDis : Boolean             ;
  DId      : string              ;
  JArr     : TJSONArray          ;
  JObj     : TJSONObject         ;
begin
  { 0: source-level ignore directives. }
  AFindings:= ApplyLineSuppressions(AFindings);

  { 1: config -- severity remap + enable/disable filter. }
  Cfg:= LoadLintConfig(AArgs);
  Survivors:= nil;
  for F in AFindings do
  begin
    IsDefDis:= False;
    for DId in ADefaultDisabled do
      if SameText(DId, F.RuleId) then begin IsDefDis:= True; Break; end;
    if Cfg.ShouldKeep(F.RuleId, IsDefDis) then begin MF:= F; MF.Severity:= Cfg.ApplySeverity(F.RuleId, F.Severity); Survivors:= Survivors + [MF]; end;
  end;

  { 2a: --write-baseline records the current (config-filtered) state and exits. }
  if AArgs.WriteBaseline <> '' then
  begin
    DRagLint.Lint.Baseline.TBaseline.Write(AArgs.WriteBaseline, Survivors);
    Writeln(Format('baseline written: %d fingerprint(s) -> %s', [Length(Survivors), AArgs.WriteBaseline]));
    Exit(0);
  end;

  { 2b: --baseline keeps only findings absent from the baseline. }
  if AArgs.Baseline <> '' then Survivors:= DRagLint.Lint.Baseline.TBaseline.Filter(AArgs.Baseline, Survivors);

  { 2c: --fix -- apply (or preview) quick-fixes for the config-surviving findings.
    Dry-run by default; --apply writes (with .bak unless --no-backup). }
  if AArgs.Fix then
  begin
    { Minor 2: fix mode cannot emit SARIF. Warn on stderr and fall through to
      JSON/text output rather than silently swallowing --format sarif. }
    if SameText(AArgs.Format, 'sarif') then Writeln(ErrOutput, '--fix does not support SARIF output; using text output.');

    { AutoFix Chunk 1 (Task 3): narrow to a single finding when --fix-line and/or
      --fix-rule are given. Each SET flag filters; an unset flag matches all. With
      neither flag the set is unchanged, so whole-file --fix is byte-identical. }
    var Targeted: TArray<TLintFinding>;
    if (AArgs.FixLine > 0) or (AArgs.FixRule <> '') then
    begin
      Targeted:= nil;
      for F in Survivors do
        if ((AArgs.FixLine = 0) or (F.StartLine = AArgs.FixLine)) and ((AArgs.FixRule = '') or SameText(F.RuleId, AArgs.FixRule)) then Targeted:= Targeted + [F];
    end
    else Targeted:= Survivors;

    var FixCount: Integer                                               ;
    var Edits: TArray<TTextEdit>:= BuildAutofixEdits(Targeted, FixCount);

    { ADF Task 8: doc-drift is store-backed, so its fix cannot be produced by the
      pure-text BuildAutofixEdits above -- it needs the store (facts + MergeComment).
      When a store is present AND the surviving set carries a fixable doc-drift
      finding, append the MergeComment-based repair edits (refresh managed facts
      block + add missing <param>/<returns> stubs; hand prose preserved, report-only
      signals untouched). Computed ONCE per decl by FixEditsForDocDrift regardless
      of how many doc-drift findings target it, so the edits do not overlap. }
    if AStore <> nil then
    begin
      var WantDocDrift: Boolean:= False;
      for F in Targeted do
        if SameText(F.RuleId, 'doc-drift') then begin WantDocDrift:= True; Break; end;
      if WantDocDrift then
      begin
        var DDEdits: TArray<TTextEdit>:= DRagLint.Lint.DocRules.TDocLintRules.FixEditsForDocDrift(AStore);
        if Length(DDEdits) > 0 then
        begin
          Edits:= Edits + DDEdits;
          { Count one fix per repaired doc span. BuildFor emits a delete+insert
            PAIR per span, so the number of repaired decls is (pairs) = half the
            edit count; count the insert edits (tekInsertLines) to avoid
            double-counting. }
          for var DDE: TTextEdit in DDEdits do
            if DDE.Kind = tekInsertLines then Inc(FixCount);
        end;
      end;

      { ADF Task 11c: missing-doc is store-backed like doc-drift, BUT it is
        SINGLE-FIX-ONLY (IsSingleFixOnlyRule) -- its "Fix it" inserts the exact
        document-qname DocInsight comment for ONE targeted decl, and is
        DELIBERATELY excluded from the blanket batch (batch-documenting a whole
        project is `document --project`'s job, not a mass --fix that would inject
        TODO stubs everywhere). THE GATE: append missing-doc's fix ONLY when this
        is a TARGETED single-fix -- i.e. --fix-line and/or --fix-rule narrowed the
        set (AArgs.FixLine > 0 or AArgs.FixRule <> ''). In the blanket batch
        (FixLine = 0 AND FixRule = ''), Targeted = all Survivors and missing-doc is
        SKIPPED. FixEditsForMissingDoc re-resolves each targeted missing-doc
        finding's decl (by file+line) and runs BuildFor once per decl. }
      var IsTargetedFix: Boolean:= (AArgs.FixLine > 0) or (AArgs.FixRule <> '');
      var WantMissingDoc: Boolean:= False;
      if IsTargetedFix then
        for F in Targeted do
          if SameText(F.RuleId, 'missing-doc') and IsSingleFixOnlyRule(F.RuleId) then begin WantMissingDoc:= True; Break; end;
      if WantMissingDoc then
      begin
        var MDEdits: TArray<TTextEdit>:= DRagLint.Lint.DocRules.TDocLintRules.FixEditsForMissingDoc(AStore, Targeted);
        if Length(MDEdits) > 0 then
        begin
          Edits:= Edits + MDEdits;
          { One inserted doc-comment per decl -- count the insert edits so FixCount
            reflects the number of decls documented (BuildFor on a fresh decl emits
            an insert). }
          for var MDE: TTextEdit in MDEdits do
            if MDE.Kind = tekInsertLines then Inc(FixCount);
        end;
      end;

      { Naming autofix: store-backed like doc-drift. Covers phase 1 (re-casing:
        method-pascalcase, local-var-casing, const-casing) AND phase 2
        (prefix-adding: field-name-prefix, param-name-prefix, type-name-prefix).
        Only for findings whose rule is BOTH registered-fixable AND opted-in via
        AutoFixIds (config "autofix": [...], tested via Cfg.IsAutoFix -- naming
        fixes rewrite call sites project-wide, so they stay opt-in rather than
        joining the always-on doc-drift append). The synthesizers + rename
        engine live in DRagLint.Refactor.NamingFix. }
      var NamingTargets: TArray<TLintFinding>:= nil;
      for F in Targeted do
        if (SameText(F.RuleId, 'method-pascalcase') or SameText(F.RuleId, 'local-var-casing')
            or SameText(F.RuleId, 'const-casing') or SameText(F.RuleId, 'field-name-prefix')
            or SameText(F.RuleId, 'param-name-prefix') or SameText(F.RuleId, 'type-name-prefix')) and Cfg.IsAutoFix(F.RuleId) then
          NamingTargets:= NamingTargets + [F];
      if Length(NamingTargets) > 0 then
      begin
        { Naming-prefix autofixes rewrite the declaration + every use the ref
          index knows about. Coverage status per rule:
          - type-name-prefix: FULLY covered as of ref-gap E (v-next). The index
            now captures impl-header qualifier + param/return types, local-var
            type annotations, and is/as operands (ref-gap E), on top of the
            ordinary typeref sites; ref-gap D already covered Self.-qualified
            uses. So a type rename no longer strands references -- NO warning.
          - field-name-prefix: ref-gap D covers Self.-qualified field uses, but
            a BARE field read used as an expression operand (e.g.
            `Result := client + 1;`) is still NOT indexed as a ref, so that one
            site can be left on the old name -- the file can fail to compile
            with exit code 0 and no other diagnostic. So field-name-prefix STILL
            warrants the warning, narrowed to that remaining shape.
          param-name-prefix uses BuildLocal's pure-AST scope walk and needs no
          warning. When ref-gaps close the bare-field-read shape, drop this too. }
        for F in NamingTargets do
          if SameText(F.RuleId, 'field-name-prefix') then
          begin
            Writeln(ErrOutput, 'drag-lint: warning: field-name-prefix autofix may leave a bare field '
              + 'read used as an expression operand (e.g. `X := field + 1`) unrenamed (the index does '
              + 'not yet capture that site) -- review the diff and recompile.');
            Break;
          end;

        var NFCount: Integer;
        var NFEdits: TArray<TTextEdit>:= DRagLint.Refactor.NamingFix.BuildNamingFixEdits(AStore, NamingTargets, Cfg.Naming, NFCount);
        if Length(NFEdits) > 0 then
        begin
          Edits:= Edits + NFEdits;
          Inc(FixCount, NFCount);
        end;
      end;
    end;

    if AArgs.AsJson or SameText(AArgs.Format, 'json') then
    begin
      { Structured per-finding output so an AI orchestrator can drive fixes
        token-free. Build the JSON from the TARGETED findings, apply (when
        --apply) writing a .bak unless --no-backup, then emit the array.
        Minor 1: 'applied'/'preview' reflect whether an edit was actually
        produced for THIS finding (keyed by file|line), not merely that --apply
        was passed -- a fixable-rule finding whose branch guard produced no edit
        (or a non-fixable finding) reports applied=false. }
      { Key edits by file|line|rule so two findings on the same line are not
        conflated -- BuildAutofixEdits emits at most one edit per fixable finding,
        and the edit's line matches the finding's StartLine, so file|line|rule
        uniquely maps an emitted edit back to its finding. }
      var EditedKeys: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
      try
        { Edits carry no rule id, so re-derive the edited keys from the Targeted
          findings whose rule produced a fix: an edit exists at (file, StartLine)
          AND the rule is fixable. This is exact because each fixable finding emits
          one edit on its own StartLine. }
        var EditLineKeys: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
        try
          for var Ed: TTextEdit in Edits do EditLineKeys.AddOrSetValue(LowerCase(Ed.FilePath) + '|' + IntToStr(Ed.Line), True);
          for F in Targeted do
            if IsFixableRule(F.RuleId) and EditLineKeys.ContainsKey(LowerCase(F.FilePath) + '|' + IntToStr(F.StartLine)) then
              EditedKeys.AddOrSetValue( LowerCase(F.FilePath) + '|' + IntToStr(F.StartLine) + '|' + LowerCase(F.RuleId), True);
        finally
          EditLineKeys.Free;
        end;
        if AArgs.Apply and (FixCount > 0) then TTextEditApplier.Apply(Edits, not AArgs.NoBackup);
        JArr:= TJSONArray.Create;
        try
          for F in Targeted do
          begin
            var HasEdit: Boolean:= EditedKeys.ContainsKey( LowerCase(F.FilePath) + '|' + IntToStr(F.StartLine) + '|' + LowerCase(F.RuleId));
            JObj:= TJSONObject.Create;
            JObj.AddPair('file' , F.FilePath);
            JObj.AddPair('line' , TJSONNumber.Create(F.StartLine));
            JObj.AddPair('rule' , F.RuleId);
            JObj.AddPair('fixable', TJSONBool.Create(IsFixableRule(F.RuleId)));
            JObj.AddPair('applied', TJSONBool.Create(AArgs.Apply and HasEdit));
            JObj.AddPair('preview', TJSONBool.Create((not AArgs.Apply) and HasEdit));
            JObj.AddPair('risky' , TJSONBool.Create(IsRiskyFixRule(F.RuleId)));
            JArr.AddElement(JObj);
          end;
          Writeln(JArr.Format(2));
        finally
          JArr.Free;
        end; // try
      finally
        EditedKeys.Free;
      end; // try
      Exit(0);
    end; // if

    if FixCount = 0 then Writeln('autofix: no fixable findings (of ' + IntToStr(Length(Targeted)) + ' finding(s))')
    else if AArgs.Apply then
    begin
      var Touched: Integer:= TTextEditApplier.Apply(Edits, not AArgs.NoBackup);
      Writeln(Format('autofix: applied %d fix(es) across %d file(s)%s', [FixCount, Touched, IfThen(AArgs.NoBackup, '', ' (.bak written)')]));
    end
    else
    begin
      Write(TTextEditApplier.RenderDryRun(Edits));
      var HasRisky: Boolean:= False;
      for F in Targeted do
        if IsRiskyFixRule(F.RuleId) then begin HasRisky:= True; Break; end;
      if HasRisky then Writeln('[risky] one or more fixes are behaviour-changing -- review before --apply.');
      Writeln(Format('autofix: %d fixable finding(s) -- pass --apply to write', [FixCount]));
    end;
    Exit(0);
  end; // if

  { 3: output. }
  if SameText(AArgs.Format, 'sarif') then Writeln(DRagLint.Output.Sarif.TSarifWriter.ToJson(Survivors, VERSION))
  else if AArgs.AsJson or SameText(AArgs.Format, 'json') then
  begin
    JArr:= TJSONArray.Create;
    try
      for F in Survivors do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('rule'      , F.RuleId  );
        JObj.AddPair('severity'  , F.Severity);
        JObj.AddPair('file_path' , F.FilePath);
        JObj.AddPair('start_line', TJSONNumber.Create(F.StartLine));
        JObj.AddPair('start_col' , TJSONNumber.Create(F.StartCol ));
        JObj.AddPair('end_line'  , TJSONNumber.Create(F.EndLine  ));
        JObj.AddPair('end_col'   , TJSONNumber.Create(F.EndCol   ));
        JObj.AddPair('message' , F.Message );
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end; // try
  end // if
  else if Assigned(AEmitText) then AEmitText(Survivors);

  { 4: exit code. }
  Result:= ExitCodeFor(Survivors, AArgs.FailOn, IfThen(Length(Survivors) > 0, 1, 0));
end; // function

/// <summary>`drag-lint rules [--json] [--category &lt;name&gt;] [--rules-dir &lt;dir&gt;]` --
/// emit the full rule catalog (built-ins + external .scm). Default = grouped text
/// table; --json = the structured catalog + summary.</summary>
function DoRules(const AArgs: TArgs): Integer;
var
  Cat   : TArray<TRuleInfo>     ;
  Sum   : TCatalogSummary       ;
  R     : TRuleInfo             ;
  P     : TRuleParam            ;
  Pr    : TPair<string, Integer>;
  Sb    : TStringBuilder        ;
  CurCat: string                ;
  procedure AddParamsJson(AObj: TJSONObject; const AParams: TArray<TRuleParam>);
  var
    PA: TJSONArray; Q: TRuleParam; PO: TJSONObject;
  begin
    PA:= TJSONArray.Create;
    for Q in AParams do begin PO:= TJSONObject.Create; PO.AddPair('name' , Q.Name ); PO.AddPair('type' , Q.ParamType ); PO.AddPair('default', Q.DefaultVal); PA.AddElement(PO); end;
    AObj.AddPair('params', PA);
  end;
begin
  Cat:= TRuleCatalog.BuildCatalog(AArgs.RulesDir, AArgs.RuleCategory);
  Sum:= TRuleCatalog.Summarize(Cat);

  if AArgs.AsJson then
  begin
    var Root: TJSONObject:= TJSONObject.Create;
    try
      var Arr: TJSONArray:= TJSONArray.Create;
      for R in Cat do
      begin
        var O: TJSONObject:= TJSONObject.Create;
        O.AddPair('id'              , R.Id             );
        O.AddPair('category'        , R.Category       );
        O.AddPair('title'           , R.Title          );
        O.AddPair('default_severity', R.DefaultSeverity);
        O.AddPair('default_enabled', TJSONBool.Create(R.DefaultEnabled));
        O.AddPair('source', R.Source);
        O.AddPair('fixable', TJSONBool.Create(IsFixableRule(R.Id)));
        AddParamsJson(O, R.Params);
        Arr.AddElement(O);
      end;
      Root.AddPair('rules', Arr);
      var SumO: TJSONObject:= TJSONObject.Create;
      SumO.AddPair('total'     , TJSONNumber.Create(Sum.Total     ));
      SumO.AddPair('categories', TJSONNumber.Create(Sum.Categories));
      var PcA: TJSONArray:= TJSONArray.Create;
      for Pr in Sum.PerCategory do
      begin
        var PcO: TJSONObject:= TJSONObject.Create;
        PcO.AddPair('category', Pr.Key);
        PcO.AddPair('count', TJSONNumber.Create(Pr.Value));
        PcA.AddElement(PcO);
      end;
      SumO.AddPair('per_category', PcA );
      Root.AddPair('summary'     , SumO);
      Writeln(Root.ToJson);
    finally
      Root.Free;
    end; // try
    Exit(0);
  end; // if

  { text mode: header + grouped table }
  Sb:= TStringBuilder.Create;
  try
    Sb.AppendLine(Format('%d rules across %d categories', [Sum.Total, Sum.Categories]));
    CurCat:= #1; { sentinel so the first real category prints a header }
    for R in Cat do
    begin
      if R.Category <> CurCat then begin CurCat:= R.Category; Sb.AppendLine(''); Sb.AppendLine('[' + CurCat + ']'); end;
      var Flags: string:= R.DefaultSeverity;
      if not R.DefaultEnabled then Flags:= Flags + ', off';
      if Length(R.Params) > 0 then
      begin
        var Names: string:= '';
        for P in R.Params do begin if Names <> '' then Names:= Names + ','; Names:= Names + P.Name + '=' + P.DefaultVal; end;
        Flags:= Flags + '; ' + Names;
      end;
      Sb.AppendLine(Format('  %-34s %-8s (%s)', [R.Id, R.Source, Flags]));
    end; // for
    Writeln(Sb.ToString);
  finally
    Sb.Free;
  end; // try
  Result:= 0;
end; // begin

function DoLint(const AArgs: TArgs): Integer;
var
  Linter      : DRagLint.Lint.Linter.TLinter;
  Findings    : TArray<TLintFinding>        ;
  ProjFindings: TArray<TLintFinding>        ;
  F           : TLintFinding                ;
  DefDisabled : TArray<string>              ;
  EffPath     : string                      ;
begin
  DefDisabled:= nil;
  { AutoFix Chunk 1: accept --file <F> as an alias for the positional <path>.
    The AutoFix spec's fix contract and the IDE spawn (Task 7) both invoke
    `lint --file <FCurrentFile> --fix ...`, but lint otherwise reads its target
    positionally into AArgs.Path. Positional path wins if both are supplied;
    otherwise fall back to AArgs.InFile (--file/--in). Computed once and used for
    every path check below so the whole `lint` command honours --file, not just
    the fix path. }
  EffPath:= IfThen(AArgs.Path <> '', AArgs.Path, AArgs.InFile);
  if (EffPath = '') and (AArgs.ProjectPath = '') then begin Writeln('ERROR: lint requires a <path> or --project <file.dproj>'); Exit (2 ); end;
  if (AArgs.Rule <> '') and (AArgs.Rule <> 'field-by-name-in-loop') and (AArgs.Rule <> 'unit-not-in-dpr') and (AArgs.Rule <> 'inline-comment-in-multiline-args') and
  (AArgs.Rule <> 'unused-local') and (AArgs.Rule <> 'syntax-error') and (AArgs.Rule <> 'unbalanced-begin-end') and (AArgs.Rule <> 'raise-in-finally') and
  (AArgs.Rule <> 'code-after-exit') and (AArgs.Rule <> 'missing-inherited-ctor') and (AArgs.Rule <> 'missing-inherited-dtor') and
  (AArgs.Rule <> 'control-flow-in-finally') and (AArgs.Rule <> 'too-many-parameters') and (AArgs.Rule <> 'too-many-locals') and
  (AArgs.Rule <> 'method-too-long') and (AArgs.Rule <> 'deep-nesting') and (AArgs.Rule <> 'float-equality-comparison') and
  (AArgs.Rule <> 'freeandnil-on-interface') and (AArgs.Rule <> 'firedac-open-execsql-mismatch') and (AArgs.Rule <> 'unprotected-object-free') and
  (AArgs.Rule <> 'use-after-free') and (AArgs.Rule <> 'win64-pointer-cast') and (AArgs.Rule <> 'redundant-cast') and (AArgs.Rule <> 'unsafe-typecast-without-is')
    and (AArgs.Rule <> 'exhaustive-enum-case') and (AArgs.Rule <> 'length-zero-compare') and (AArgs.Rule <> 'ui-access-in-thread') and (AArgs.Rule <> 'interface-object-mixing') and
  (AArgs.Rule <> 'global-form-variable') and (AArgs.Rule <> 'unsafe-shellexecute') and (AArgs.Rule <> 'path-traversal') and (AArgs.Rule <> 'loop-executes-at-most-once') and
  (AArgs.Rule <> 'format-argument-count') and (AArgs.Rule <> 'format-specifier-type-mismatch') and (AArgs.Rule <> 'try-except-swallowed')
    and (AArgs.Rule <> 'dataset-open-without-close') and (AArgs.Rule <> 'criticalsection-not-released') and (AArgs.Rule <> 'too-many-exit-points')
    and (AArgs.Rule <> 'cyclomatic-complexity') and (AArgs.Rule <> 'virtual-method-in-constructor') and
  (AArgs.Rule <> 'used-before-assignment') and (AArgs.Rule <> 'function-result-not-set') and (AArgs.Rule <> 'out-param-not-set'  ) and
  (AArgs.Rule <> 'overwrite-before-read' ) and (AArgs.Rule <> 'write-only-local'       ) and (AArgs.Rule <> 'loop-var-after-loop') and
  (AArgs.Rule <> 'object-leak') and (AArgs.Rule <> 'not-assigned-interface') and (AArgs.Rule <> 'split-variable') and (AArgs.Rule <> 'separate-query-from-modifier') and
  (AArgs.Rule <> 'type-name-prefix') and (AArgs.Rule <> 'field-name-prefix') and (AArgs.Rule <> 'param-name-prefix') and
  (AArgs.Rule <> 'method-pascalcase') and (AArgs.Rule <> 'const-casing') and (AArgs.Rule <> 'local-var-casing') and (AArgs.Rule <> 'unit-name-matches-file') and
  (AArgs.Rule <> 'reserved-word-casing') and (AArgs.Rule <> 'hungarian-or-short-identifier') and (AArgs.Rule <> 'unused-parameter') and (AArgs.Rule <> 'identical-then-else') and
  (AArgs.Rule <> 'referenced-never-set') and (AArgs.Rule <> 'redundant-parentheses') and (AArgs.Rule <> 'commented-out-code') and (AArgs.Rule <> 'function-result-ignored') and
  (AArgs.Rule <> 'destructor-without-override'  ) and (AArgs.Rule <> 'case-with-too-few-branches'          ) and
  (AArgs.Rule <> 'boolean-expression-complexity') and (AArgs.Rule <> 'exception-constructed-but-not-raised') and
  (AArgs.Rule <> 'duplicate-exception-handler'  ) and (AArgs.Rule <> 'repeated-else-if-condition'          ) and
  (AArgs.Rule <> 'property-references-itself') and (AArgs.Rule <> 'unit-too-large') and (AArgs.Rule <> 'weak-random-for-security') and (AArgs.Rule <> 'create-inside-try') and
  (AArgs.Rule <> 'dfm-hardcoded-credential') and (AArgs.Rule <> 'insecure-temp-file') and (AArgs.Rule <> 'multiple-statements-per-line') and
  (AArgs.Rule <> 'abstract-method-instantiation') and (AArgs.Rule <> 'nativeint-truncation') and (AArgs.Rule <> 'lossy-cast') and (AArgs.Rule <> 'cognitive-complexity') and
  (AArgs.Rule <> 'duplicate-code') and (AArgs.Rule <> 'magic-literal') and (AArgs.Rule <> 'boolean-flag-parameter') and
  (AArgs.Rule <> 'message-chain') and (AArgs.Rule <> 'public-writable-field') and (AArgs.Rule <> 'loop-control-flag') and (AArgs.Rule <> 'double-free') and
  (AArgs.Rule <> 'mutable-global-variable') and (AArgs.Rule <> 'default-encoding-io') then
  begin
    Writeln(Format(
        'ERROR: unknown rule "%s" (known: field-by-name-in-loop, ' + 'unit-not-in-dpr, inline-comment-in-multiline-args, unused-local, '
          + 'syntax-error, unbalanced-begin-end, raise-in-finally, code-after-exit, ' + 'missing-inherited-ctor, missing-inherited-dtor, control-flow-in-finally, '
          + 'too-many-parameters, too-many-locals, method-too-long, deep-nesting, '
          + 'float-equality-comparison, freeandnil-on-interface, firedac-open-execsql-mismatch, unprotected-object-free, '
          + 'use-after-free, win64-pointer-cast, redundant-cast, unsafe-typecast-without-is, exhaustive-enum-case, length-zero-compare, ui-access-in-thread, global-form-variable, unsafe-shellexecute, path-traversal, loop-executes-at-most-once, format-argument-count, format-specifier-type-mismatch, try-except-swallowed, dataset-open-without-close, criticalsection-not-released, too-many-exit-points, cyclomatic-complexity, virtual-method-in-constructor, '
          + 'used-before-assignment, function-result-not-set, out-param-not-set, overwrite-before-read, write-only-local, loop-var-after-loop, object-leak, not-assigned-interface, split-variable, separate-query-from-modifier, double-free, '
          + 'type-name-prefix, field-name-prefix, param-name-prefix, method-pascalcase, const-casing, local-var-casing, unit-name-matches-file, reserved-word-casing, hungarian-or-short-identifier, '
          + 'unused-parameter, identical-then-else, referenced-never-set, redundant-parentheses, commented-out-code, function-result-ignored, destructor-without-override, case-with-too-few-branches, boolean-expression-complexity, exception-constructed-but-not-raised, duplicate-exception-handler, repeated-else-if-condition, property-references-itself, unit-too-large, weak-random-for-security, create-inside-try, dfm-hardcoded-credential, insecure-temp-file, multiple-statements-per-line, abstract-method-instantiation, nativeint-truncation, lossy-cast, cognitive-complexity, duplicate-code, magic-literal, boolean-flag-parameter, message-chain, public-writable-field, loop-control-flag, mutable-global-variable, default-encoding-io, interface-object-mixing)',
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
  if EffPath <> '' then
  begin
    Linter:= DRagLint.Lint.Linter.TLinter.Create(AArgs.RulesDir);
    try
      { Surface the deploy gap instead of silently running with no external rules:
        the exe loads <exe-dir>\rules by default (or --rules-dir). }
      if Linter.ExternalRuleCount = 0 then Writeln(ErrOutput,
        'drag-lint: note: 0 external .scm rules loaded -- place a "rules" folder next to drag-lint.exe, or pass --rules-dir <path> (built-in checks still run).');
      DefDisabled:= Linter.DefaultDisabledRuleIds; // capture before Free
      { v0.71: function-result-ignored ships OFF by default (FP-prone -- builders/
        adders/runners legitimately discard results). Opt in via drag-lint-lint.json
        "enabled": ["function-result-ignored"] or --rule function-result-ignored. }
      if AArgs.Rule <> 'function-result-ignored' then DefDisabled:= DefDisabled + ['function-result-ignored'];
      { v0.71: unsafe-typecast-without-is also OFF by default (an unguarded hard cast
        is often provably safe to the author -> too noisy for the default set). }
      if AArgs.Rule <> 'unsafe-typecast-without-is' then DefDisabled:= DefDisabled + ['unsafe-typecast-without-is'];
      { v0.74: exhaustive-enum-case OFF by default (a case that intentionally handles
        a subset of an enum with no else is common -> opt in for enum-heavy code). }
      if AArgs.Rule <> 'exhaustive-enum-case' then DefDisabled:= DefDisabled + ['exhaustive-enum-case'];
      { v0.82: interface-object-mixing OFF by default (#4 first cut -- a same-routine
        object/interface dual-handle heuristic; conservative but still opt-in). }
      if AArgs.Rule <> 'interface-object-mixing' then DefDisabled:= DefDisabled + ['interface-object-mixing'];
      { v0.76: multiple-statements-per-line OFF by default (pure style). }
      if AArgs.Rule <> 'multiple-statements-per-line' then DefDisabled:= DefDisabled + ['multiple-statements-per-line'];
      { v0.79: magic-literal OFF by default (medium-FP -- opt in via
        drag-lint-lint.json "enabled": ["magic-literal"] or --rule magic-literal). }
      if AArgs.Rule <> 'magic-literal' then DefDisabled:= DefDisabled + ['magic-literal'];
      { v0.79: boolean-flag-parameter OFF by default (Boolean flag params are
        common in this codebase -- opt in via "enabled": ["boolean-flag-parameter"]
        or --rule boolean-flag-parameter). }
      if AArgs.Rule <> 'boolean-flag-parameter' then DefDisabled:= DefDisabled + ['boolean-flag-parameter'];
      { v0.79: public-writable-field OFF by default -- FP-sanity over src/ found
        44 findings concentrated in 6/103 files, almost all intentional public
        field-bag "record-like classes" (TCfgBlock/TCfg internal data carriers,
        plugin form-helper classes) -- a deliberate codebase idiom, not scattered
        accidental encapsulation breaks. Opt in via "enabled": ["public-writable-
        field"] or --rule public-writable-field. }
      if AArgs.Rule <> 'public-writable-field' then DefDisabled:= DefDisabled + ['public-writable-field'];
      { v0.79: loop-control-flag OFF by default -- the riskiest heuristic of
        the batch (a while/repeat condition identifier also reset to a bare
        True/False inside the body). Opt in via "enabled": ["loop-control-
        flag"] or --rule loop-control-flag. }
      if AArgs.Rule <> 'loop-control-flag' then DefDisabled:= DefDisabled + ['loop-control-flag'];
      { v0.80: mutable-global-variable OFF by default -- FP-sanity over src/ found
        68 findings across 27/103 files (mostly legitimate G-prefixed plugin
        singletons/caches) -- too common in this codebase to be ON. Opt in via
        "enabled": ["mutable-global-variable"] or --rule mutable-global-variable. }
      if AArgs.Rule <> 'mutable-global-variable' then DefDisabled:= DefDisabled + ['mutable-global-variable'];
      { v0.81: default-encoding-io OFF by default -- FP-sanity over src/ found 65
        findings across 16/103 files, mostly TFile.ReadAllText on known-ASCII
        project/config files (dproj/json) -- a common, often-intentional pattern
        in this codebase. Opt in via "enabled": ["default-encoding-io"] or
        --rule default-encoding-io. }
      if AArgs.Rule <> 'default-encoding-io' then DefDisabled:= DefDisabled + ['default-encoding-io'];
      { v0.83: split-variable OFF by default -- M2 two-live-range flow signal
        (a local reused for two unrelated purposes). Linear-routine-only, low-FP,
        but a refactoring hint rather than a bug. Opt in via "enabled":
        ["split-variable"] or --rule split-variable. }
      if AArgs.Rule <> 'split-variable' then DefDisabled:= DefDisabled + ['split-variable'];
      { v0.83: separate-query-from-modifier OFF by default -- Command-Query Separation
        is inherently noisy (lazy-caching getters, fluent mutators). Conservative
        field-write predicate keeps FP low, but ships OFF. Opt in via "enabled":
        ["separate-query-from-modifier"] or --rule separate-query-from-modifier. }
      if AArgs.Rule <> 'separate-query-from-modifier' then DefDisabled:= DefDisabled + ['separate-query-from-modifier'];
      if TFile.Exists(EffPath) then Findings:= Findings + Linter.LintFile(EffPath)
      else if TDirectory.Exists(EffPath) then Findings:= Findings + Linter.LintFolder(EffPath, True)
      else begin Writeln('ERROR: path does not exist: ', EffPath); Exit(2); end;
    finally
      Linter.Free;
    end; // try
    { v0.46: AST checks that need no DB -- single .pas file only. The plugin's
      lint provider runs `lint <buffer>` with no --rule, so all of these surface
      as live edit-time diagnostics. }
    if TFile.Exists(EffPath) and (SameText(ExtractFileExt(EffPath), '.pas') or SameText(ExtractFileExt(EffPath), '.inc')) then
    begin
      var Cfg: TLintConfig:= LoadLintConfig(AArgs);
      { unused local variables (H2164) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'unused-local') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals(EffPath);
      { syntax errors (tree-sitter ERROR/MISSING) -- this is what makes a typed
        syntax error show up in the editor like the IDE's Error Insight. }
      if (AArgs.Rule = '') or (AArgs.Rule = 'syntax-error') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors(EffPath);
      { unbalanced begin/end (a common edit-time mistake) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'unbalanced-begin-end') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnbalancedBeginEnd(EffPath);
      { v0.47: raise inside a finally block (masks the in-flight exception) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'raise-in-finally') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRaiseInFinally(EffPath);
      { v0.47: unreachable code after Exit/raise/Break/Continue/Halt }
      if (AArgs.Rule = '') or (AArgs.Rule = 'code-after-exit') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit(EffPath);
      { v0.47: Exit/Break/Continue/Halt inside a finally block }
      if (AArgs.Rule = '') or (AArgs.Rule = 'control-flow-in-finally') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally(EffPath);
      { v0.47: constructor/destructor without an inherited call (one walk emits both ids) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'missing-inherited-ctor') or (AArgs.Rule = 'missing-inherited-dtor') then
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckMissingInherited(EffPath) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.48: routine size/complexity metrics (conservative defaults: params>7, locals>25, body>120 lines, nesting>5) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'too-many-parameters') or (AArgs.Rule = 'too-many-locals') or (AArgs.Rule = 'method-too-long') or (AArgs.Rule = 'deep-nesting') then
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRoutineMetrics(
          EffPath, Cfg.ThresholdFor('too-many-parameters', 7), Cfg.ThresholdFor('too-many-locals', 25), Cfg.ThresholdFor('method-too-long', 120),
          Cfg.ThresholdFor('deep-nesting', 5)) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.48: type-aware checks (float equality, FreeAndNil-on-interface, v0.52 win64 cast) via a per-file type map }
      if (AArgs.Rule = '') or (AArgs.Rule = 'float-equality-comparison') or (AArgs.Rule = 'freeandnil-on-interface') or (AArgs.Rule = 'win64-pointer-cast')
        or (AArgs.Rule = 'redundant-cast') or (AArgs.Rule = 'unsafe-typecast-without-is') or (AArgs.Rule = 'exhaustive-enum-case') or (AArgs.Rule = 'lossy-cast')
        or (AArgs.Rule = 'nativeint-truncation') or (AArgs.Rule = 'abstract-method-instantiation') or (AArgs.Rule = 'length-zero-compare')
        or (AArgs.Rule = 'interface-object-mixing') then
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware(EffPath) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.49: FireDAC Open/ExecSQL vs SQL-kind mismatch }
      if (AArgs.Rule = '') or (AArgs.Rule = 'firedac-open-execsql-mismatch') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFireDacSqlMismatch(EffPath);
      { v0.50: object created + freed without try-finally (leak on exception) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'unprotected-object-free') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnprotectedFree(EffPath);
      { v0.52: use of an object after X.Free (dangling reference) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'use-after-free') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUseAfterFree(EffPath);
      { v0.56: UI access inside a TThread.Execute (not thread-safe) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'ui-access-in-thread') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUiThread(EffPath);
      { v0.61: unit-level global variable whose type is the form class -- potential leak }
      if (AArgs.Rule = '') or (AArgs.Rule = 'global-form-variable') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckGlobalFormVars(EffPath);
      { v0.80: any unit-level writable var -- Fowler "Global Data" refactoring smell (#14) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'mutable-global-variable') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckMutableGlobalVars(EffPath);
      { v0.83: value-returning function that also mutates a field -- Command-Query Separation (OFF) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'separate-query-from-modifier') then Findings:= Findings
        + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSeparateQueryFromModifier(EffPath);
      { v0.63: WinExec/ShellExecute/CreateProcess with a non-literal command -- injection risk }
      if (AArgs.Rule = '') or (AArgs.Rule = 'unsafe-shellexecute') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckShellExec(EffPath);
      { v0.63: concatenated path to a file API -- path traversal risk }
      if (AArgs.Rule = '') or (AArgs.Rule = 'path-traversal') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckPathTraversal(EffPath);
      { v0.63: loop whose first body statement is Exit/Break/raise -- runs at most once }
      if (AArgs.Rule = '') or (AArgs.Rule = 'loop-executes-at-most-once') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckLoopAtMostOnce(EffPath);
      { v0.63: Format() specifier/argument count + literal type mismatch (one walk, two ids) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'format-argument-count') or (AArgs.Rule = 'format-specifier-type-mismatch') then
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFormatCall(EffPath) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.63: try..except that swallows the exception (no raise/log/HandleException) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'try-except-swallowed') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSwallowedExcept(EffPath);
      { v0.63: dataset opened without a matching Close in a finally block }
      if (AArgs.Rule = '') or (AArgs.Rule = 'dataset-open-without-close') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckDatasetOpen(EffPath);
      { v0.63: critical section acquired without a matching Leave/Release in finally }
      if (AArgs.Rule = '') or (AArgs.Rule = 'criticalsection-not-released') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCriticalSection(EffPath);
      { v0.63: routine with more than 5 Exit statements }
      if (AArgs.Rule = '') or (AArgs.Rule = 'too-many-exit-points') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints(
        EffPath, Cfg.ThresholdFor('too-many-exit-points', 5));
      { v0.63: cyclomatic complexity over 15 }
      if (AArgs.Rule = '') or (AArgs.Rule = 'cyclomatic-complexity') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity(
        EffPath, Cfg.ThresholdFor('cyclomatic-complexity', 15));
      if (AArgs.Rule = '') or (AArgs.Rule = 'cognitive-complexity') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity(
        EffPath, Cfg.ThresholdFor('cognitive-complexity', 25));
      { v0.63: virtual/dynamic method called from a constructor of its own class }
      if (AArgs.Rule = '') or (AArgs.Rule = 'virtual-method-in-constructor') then Findings:= Findings
        + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckVirtualInConstructor(EffPath);
      { M2: flow-sensitive checks (definite-assignment etc.); no store on the bare lint path }
      for F in DRagLint.Diagnostics.FlowChecks.TFlowChecker.Check(EffPath) do
        if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.68: naming-convention prefix rules (config-driven, no store on bare lint path) }
      if (AArgs.Rule = '') or (AArgs.Rule = 'type-name-prefix') or (AArgs.Rule = 'field-name-prefix') or (AArgs.Rule = 'param-name-prefix') or
      (AArgs.Rule = 'method-pascalcase') or (AArgs.Rule = 'const-casing') or (AArgs.Rule = 'local-var-casing') or (AArgs.Rule = 'unit-name-matches-file') or
      (AArgs.Rule = 'reserved-word-casing') or (AArgs.Rule = 'hungarian-or-short-identifier') then
        for F in DRagLint.Diagnostics.NamingChecks.TNamingChecker.Check(EffPath, Cfg.Naming) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.68: dead-code checks (unused-parameter, identical-then-else, referenced-never-set)
        v0.70: + redundant-parentheses + commented-out-code
        v0.71: + function-result-ignored
        v0.72: + destructor-without-override (#5) + case-with-too-few-branches +
        boolean-expression-complexity (#6, thresholds) + exception-constructed-but-not-raised
        + duplicate-exception-handler (#7) -- all from the same TDeadCodeChecker.Check }
      if (AArgs.Rule = '') or (AArgs.Rule = 'unused-parameter') or (AArgs.Rule = 'identical-then-else') or (AArgs.Rule = 'referenced-never-set')
        or (AArgs.Rule = 'redundant-parentheses') or (AArgs.Rule = 'commented-out-code') or (AArgs.Rule = 'function-result-ignored')
        or (AArgs.Rule = 'destructor-without-override') or (AArgs.Rule = 'case-with-too-few-branches') or (AArgs.Rule = 'boolean-expression-complexity')
          or (AArgs.Rule = 'exception-constructed-but-not-raised') or (AArgs.Rule = 'duplicate-exception-handler')
        or (AArgs.Rule = 'repeated-else-if-condition') or (AArgs.Rule = 'property-references-itself') or (AArgs.Rule = 'unit-too-large')
        or (AArgs.Rule = 'weak-random-for-security') or (AArgs.Rule = 'create-inside-try') or (AArgs.Rule = 'insecure-temp-file') or (AArgs.Rule = 'multiple-statements-per-line')
        or (AArgs.Rule = 'magic-literal') or (AArgs.Rule = 'boolean-flag-parameter') or (AArgs.Rule = 'message-chain')
        or (AArgs.Rule = 'public-writable-field') or (AArgs.Rule = 'loop-control-flag') or (AArgs.Rule = 'default-encoding-io') then
        for F in DRagLint.Diagnostics.DeadCodeChecks.TDeadCodeChecker.Check(
          EffPath, Cfg.ThresholdFor('case-with-too-few-branches', 2), Cfg.ThresholdFor('boolean-expression-complexity', 4), Cfg.ThresholdFor('unit-too-large', 2000),
          Cfg.ThresholdFor('message-chain', 4)) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { v0.77: clone / duplicate-code detection (#6) -- within-file (single-file lint).
        lint-all uses CheckProject instead (LATER task) so within-file clones are
        not double-reported. }
      if (AArgs.Rule = '') or (AArgs.Rule = 'duplicate-code') then
        for F in DRagLint.Diagnostics.CloneChecks.TCloneChecker.Check(EffPath, Cfg.ThresholdFor('duplicate-code', 90)) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
      { Free cached tree after single-file lint }
      DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear;
    end; // if
  end; // if
  Result:= FinalizeAndOutput(
    AArgs, Findings, DefDisabled,
    procedure(ASurv: TArray<TLintFinding>) var FF: TLintFinding; begin for FF in ASurv do Writeln(Format('%s:%d:%d  [%s] %s: %s', [FF.FilePath, FF.StartLine, FF.StartCol,
            FF.Severity, FF.RuleId, FF.Message])); Writeln(Format('%d finding(s)', [Length(ASurv)])); end
  );
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
  if AArgs.Task = '' then begin Writeln('Usage: drag-lint context --task "verb qname" [--db PATH] ' + '[--format md|json|raw]'); Exit(2); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(1);
  IncDocs:= not AArgs.NoDocs;
  IncSurface:= AArgs.IncludeClassSurface;
  IncImpl:= SameText(AArgs.Verb, 'modify') or SameText(AArgs.Verb, 'refactor') or SameText(AArgs.Verb, 'extend');
  Bundle:= TContextBundler.Build(
    Store, AArgs.Verb, AArgs.BundleQName, AArgs.ContextLines, AArgs.MaxCallers, IncDocs, IncSurface, IncImpl, {AExcludeDfmFields=}
    not AArgs.FullSurface);
  if Bundle.QName = '' then begin Writeln(Format('No symbol matched: %s', [AArgs.BundleQName])); Exit(1); end;
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
  if not TFile.Exists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;

  N:= AArgs.BenchN;
  if N <= 0 then N:= 20;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  // Fetch documented symbols (clamped to N).
  Syms:= Store.ListDocumentedSymbols(N);
  if Length(Syms) = 0 then begin Writeln('No documented symbols found in: ', AArgs.DbPath); Exit(1); end;

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

  if Count = 0 then begin Writeln('No valid symbols with accessible source files.'); Exit (1 ); end;

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
  if AArgs.FbConnection = '' then begin Writeln(ErrOutput, 'fb-snapshot: --connection "Database=...;User=...;Password=...;DriverID=FB" required'); Exit(2); end;
  if Length(AArgs.DbPaths) > 0 then DbPath:= AArgs.DbPaths[0]
  else DbPath:= AArgs.DbPath;
  if DbPath = '' then begin Writeln(ErrOutput, 'fb-snapshot: --db <sql.sqlite> required'); Exit(2); end;
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
      on E: Exception do begin Writeln(ErrOutput, 'fb-snapshot FAILED: ', E.ClassName, ': ', E.Message); Result:= 3; end;
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
  if Length(AArgs.DbPaths) < 1 then begin Writeln(ErrOutput, 'link-orm: pass each project + sql DB as --db <path>'); Exit(2); end;
  try
    Stats:= TOrmLinker.Run(AArgs.DbPaths);
    Writeln(Format(
        'link-orm: %d class_to_table, %d iface_to_table, %d field_to_column (across %d DBs)', [Stats.ClassLinks, Stats.IfaceLinks, Stats.FieldLinks, Length(AArgs.DbPaths)]));
    Result:= 0;
  except
    on E: Exception do begin Writeln(ErrOutput, 'link-orm FAILED: ', E.ClassName, ': ', E.Message); Result:= 3; end;
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
    else begin Writeln(ErrOutput, 'uses-report: need at least one --db'); Result:= 2; Exit; end;
    SetLength(Stores, 0);
    for i:= 0 to High(DbList) do
    begin
      Path:= DbList[i];
      if not TFile.Exists(Path) then begin Writeln(ErrOutput, 'uses-report: db not found, skipping: ', Path); Continue; end;
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
      if CharInSet(Base[Length(Base)], ['\','/']) then begin Delete(Base, Length(Base), 1); Break; end;
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
            if not FileIdToGlobal.TryGetValue( (Int64(StoreIdx) shl 40) or LocalFileId, GlobalIdx) then begin QUses.Next; Continue; end;

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
      else begin EmitCsvRow(SourceMeta.Stem, Item.UsedUnit, Item.Depth, Item.Section, Item.Via, Item.External); Inc(ARowCount); end;

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

  if AArgs.Output = '' then begin Writeln(ErrOutput, 'uses-report: --output <path.csv> is required'); Exit(2); end;

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
    if Length(Stores) = 0 then begin Writeln(ErrOutput, 'uses-report: no usable DB'); Exit(2); end;

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

/// <summary>drag-lint deps-report: third-party dependency rollup over the index
/// uses-graph. Rollup by default (per-external unit: used-by count, resolved
/// state, shortest import path); --edges switches to the flat
/// (project-unit -&gt; external-unit) list. Formats: text|json|csv. Opens each
/// --db as a TSQLiteSymbolStore (multi-DB, first-store-wins for stems),
/// borrows them into BuildDepsReport, and frees them afterward.</summary>
function DoDepsReport(const AArgs: TArgs): Integer;
var
  Stores: TArray<ISymbolStore>;

  procedure OpenStores;
  var
    DbList: TArray<string>;
    i     : Integer       ;
    Path  : string        ;
  begin
    if Length(AArgs.DbPaths) > 0 then DbList:= AArgs.DbPaths
    else if AArgs.DbPath <> '' then DbList:= TArray<string>.Create(AArgs.DbPath)
    else begin Writeln(ErrOutput, 'deps-report: need at least one --db'); Result:= 2; Exit; end;
    SetLength(Stores, 0);
    for i:= 0 to High(DbList) do
    begin
      Path:= DbList[i];
      if not TFile.Exists(Path) then begin Writeln(ErrOutput, 'deps-report: db not found, skipping: ', Path); Continue; end;
      SetLength(Stores, Length(Stores) + 1);
      Stores[High(Stores)]:= TSQLiteSymbolStore.Create(Path);
      Stores[High(Stores)].Migrate;
    end;
  end; // procedure

  function CsvEscape(const S: string): string;
  begin
    if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) then Result:= '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
    else Result:= S;
  end;

  function ResolvedStr(AResolved: Boolean): string;
  begin
    if AResolved then Result:= 'resolved' else Result:= 'not-indexed';
  end;

  function RenderText(const ARep: TDepsReport): string;
  var
    SB       : TStringBuilder;
    G        : TDepsGroup    ;
    Ext      : TDepsExternal ;
    Edge     : TDepsEdge     ;
    GC       : TDepsGroupCount;
    UsedByStr: string        ;
  begin
    SB:= TStringBuilder.Create;
    try
      if AArgs.Edges then
      begin
        for Edge in ARep.Edges do
          SB.AppendLine(Format('%s -> %s  [%s]  [%s]  [%s]',
            [Edge.SourceUnit, Edge.ExternalUnit, DepsGroupStr(Edge.Group), Edge.Section, ResolvedStr(Edge.Resolved)]));
      end
      else
      begin
        for G:= Low(TDepsGroup) to High(TDepsGroup) do
        begin
          var AnyInGroup: Boolean:= False;
          for Ext in ARep.Externals do if Ext.Group = G then begin AnyInGroup:= True; Break; end;
          if not AnyInGroup then Continue;

          SB.AppendLine(Format('== %s ==', [DepsGroupStr(G)]));
          for Ext in ARep.Externals do
          begin
            if Ext.Group <> G then Continue;
            SB.AppendLine(Format('%s  (used by %d)  [%s]', [Ext.UnitName, Ext.UsedByCount, ResolvedStr(Ext.Resolved)]));
            if Ext.ShortestPath <> '' then SB.AppendLine(Format('  path: %s', [Ext.ShortestPath]));
            if Length(Ext.UsedBy) > 0 then
            begin
              UsedByStr:= string.Join(', ', Ext.UsedBy);
              if Ext.UsedByMore > 0 then UsedByStr:= UsedByStr + Format(' (+%d more)', [Ext.UsedByMore]);
              SB.AppendLine(Format('  used by: %s', [UsedByStr]));
            end;
          end;
        end;

        SB.AppendLine(Format('%d external units, %d edges, %d not indexed',
          [ARep.Summary.ExternalUnitCount, ARep.Summary.ExternalEdgeCount, ARep.Summary.UnresolvedCount]));
        for GC in ARep.Summary.GroupCounts do
          SB.AppendLine(Format('%s: %d units / %d project units', [DepsGroupStr(GC.Group), GC.UnitCount, GC.ProjectUnitCount]));
      end;
      Result:= SB.ToString;
    finally
      SB.Free;
    end;
  end; // function

  function RenderJson(const ARep: TDepsReport): string;
  var
    JRoot    : TJSONObject   ;
    JSummary : TJSONObject   ;
    JGroups  : TJSONArray    ;
    JGroup   : TJSONObject   ;
    JExts    : TJSONArray    ;
    JExt     : TJSONObject   ;
    JUsedBy  : TJSONArray    ;
    JSections: TJSONArray    ;
    JEdges   : TJSONArray    ;
    JEdge    : TJSONObject   ;
    GC       : TDepsGroupCount;
    Ext      : TDepsExternal ;
    U        : string        ;
    Sec      : string        ;
    Edge     : TDepsEdge     ;
  begin
    JRoot:= TJSONObject.Create;
    try
      JRoot.AddPair('schema', 'deps-report/1');

      JSummary:= TJSONObject.Create;
      JSummary.AddPair('external_unit_count', TJSONNumber.Create(ARep.Summary.ExternalUnitCount));
      JSummary.AddPair('external_edge_count', TJSONNumber.Create(ARep.Summary.ExternalEdgeCount));
      JSummary.AddPair('unresolved_count'   , TJSONNumber.Create(ARep.Summary.UnresolvedCount));
      JGroups:= TJSONArray.Create;
      for GC in ARep.Summary.GroupCounts do
      begin
        JGroup:= TJSONObject.Create;
        JGroup.AddPair('group'             , DepsGroupStr(GC.Group));
        JGroup.AddPair('unit_count'        , TJSONNumber.Create(GC.UnitCount));
        JGroup.AddPair('project_unit_count', TJSONNumber.Create(GC.ProjectUnitCount));
        JGroups.AddElement(JGroup);
      end;
      JSummary.AddPair('groups', JGroups);
      JRoot.AddPair('summary', JSummary);

      JExts:= TJSONArray.Create;
      for Ext in ARep.Externals do
      begin
        JExt:= TJSONObject.Create;
        JExt.AddPair('unit'         , Ext.UnitName);
        JExt.AddPair('group'        , DepsGroupStr(Ext.Group));
        JExt.AddPair('resolved'     , TJSONBool.Create(Ext.Resolved));
        JExt.AddPair('used_by_count', TJSONNumber.Create(Ext.UsedByCount));
        JUsedBy:= TJSONArray.Create;
        for U in Ext.UsedBy do JUsedBy.Add(U);
        JExt.AddPair('used_by', JUsedBy);
        JExt.AddPair('used_by_more', TJSONNumber.Create(Ext.UsedByMore));
        JExt.AddPair('shortest_path', Ext.ShortestPath);
        JSections:= TJSONArray.Create;
        for Sec in Ext.Sections do JSections.Add(Sec);
        JExt.AddPair('sections', JSections);
        JExts.AddElement(JExt);
      end;
      JRoot.AddPair('externals', JExts);

      if AArgs.Edges then
      begin
        JEdges:= TJSONArray.Create;
        for Edge in ARep.Edges do
        begin
          JEdge:= TJSONObject.Create;
          JEdge.AddPair('source_unit'  , Edge.SourceUnit);
          JEdge.AddPair('external_unit', Edge.ExternalUnit);
          JEdge.AddPair('group'        , DepsGroupStr(Edge.Group));
          JEdge.AddPair('section'      , Edge.Section);
          JEdge.AddPair('resolved'     , TJSONBool.Create(Edge.Resolved));
          JEdges.AddElement(JEdge);
        end;
        JRoot.AddPair('edges', JEdges);
      end;

      Result:= JRoot.Format(2);
    finally
      JRoot.Free;
    end;
  end; // function

  function RenderCsv(const ARep: TDepsReport): string;
  var
    SB  : TStringBuilder;
    Ext : TDepsExternal ;
    Edge: TDepsEdge      ;
  begin
    SB:= TStringBuilder.Create;
    try
      if AArgs.Edges then
      begin
        SB.AppendLine('source_unit,external_unit,group,section,resolved');
        for Edge in ARep.Edges do
          SB.AppendLine(CsvEscape(Edge.SourceUnit) + ',' + CsvEscape(Edge.ExternalUnit) + ',' +
            CsvEscape(DepsGroupStr(Edge.Group)) + ',' + CsvEscape(Edge.Section) + ',' +
            IfThen(Edge.Resolved, '1', '0'));
      end
      else
      begin
        SB.AppendLine('unit,group,resolved,used_by_count,shortest_path');
        for Ext in ARep.Externals do
          SB.AppendLine(CsvEscape(Ext.UnitName) + ',' + CsvEscape(DepsGroupStr(Ext.Group)) + ',' +
            IfThen(Ext.Resolved, '1', '0') + ',' + IntToStr(Ext.UsedByCount) + ',' +
            CsvEscape(Ext.ShortestPath));
      end;
      Result:= SB.ToString;
    finally
      SB.Free;
    end;
  end; // function

var
  Opts  : TDepsOptions;
  Rep   : TDepsReport ;
  Fmt   : string       ;
  Output: string       ;
  i     : Integer      ;
begin
  Result:= 0;
  Stores:= nil;
  try
    OpenStores;
    if Result <> 0 then Exit;
    if Length(Stores) = 0 then begin Writeln(ErrOutput, 'deps-report: no usable DB'); Exit(2); end;

    Opts.Depth      := AArgs.Depth;
    Opts.AllSources := AArgs.AllSources;
    Opts.NamePattern:= AArgs.Name;
    Opts.MaxList    := 20;

    Rep:= BuildDepsReport(Stores, Opts);

    Fmt:= LowerCase(AArgs.Format);
    if Fmt = '' then Fmt:= 'text';

    if Fmt = 'json' then Output:= RenderJson(Rep)
    else if Fmt = 'csv' then Output:= RenderCsv(Rep)
    else Output:= RenderText(Rep);

    if AArgs.Output <> '' then TFile.WriteAllText(AArgs.Output, Output, TEncoding.ANSI)
    else Writeln(Output);
  finally
    for i:= 0 to High(Stores) do Stores[i]:= nil;
  end; // try
end; // function

/// <summary>drag-lint schema: dumps the LIVE index schema of --db -- schema_version,
/// each table with its columns (PRAGMA table_info) + row count. --format json (or
/// --json) emits a machine-readable structure so other tools can introspect the
/// index. Strictly READ-ONLY: opens the store read-only and never calls Migrate
/// or issues any DDL/INSERT/UPDATE -- the verb must never mutate the DB it
/// inspects.</summary>
/// <param name="AArgs">Parsed CLI args; DbPath/DbPaths[0] is the index to
/// introspect (first --db wins when several are given), Format='json' or
/// AsJson selects JSON, Output redirects to a file (else stdout).</param>
/// <returns>0 on success; 2 (with a usage line on stderr) when --db is missing.</returns>
function DoSchema(const AArgs: TArgs): Integer;
var
  DbPath      : string        ;
  Store       : TSQLiteSymbolStore;
  Conn        : TFDConnection ;
  Q           : TFDQuery      ;
  QCols       : TFDQuery      ;
  QCount      : TFDQuery      ;
  SchemaVer   : Integer       ;
  TableNames  : TArray<string>;
  T           : string        ;
  UseJson     : Boolean       ;
  SB          : TStringBuilder;
  JRoot       : TJSONObject   ;
  JTables     : TJSONArray    ;
  JTable      : TJSONObject   ;
  JCols       : TJSONArray    ;
  JCol        : TJSONObject   ;
  RowCount    : Int64         ;
  OutStr      : string        ;

  function IsSafeIdent(const AName: string): Boolean;
  var
    Ch: Char;
    Idx: Integer;
  begin
    Result:= False;
    if AName = '' then Exit;
    Ch:= AName[1];
    if not (CharInSet(Ch, ['A'..'Z', 'a'..'z', '_'])) then Exit;
    for Idx:= 2 to Length(AName) do
      if not (CharInSet(AName[Idx], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) then Exit;
    Result:= True;
  end;

begin
  Result:= 0;
  if Length(AArgs.DbPaths) > 0 then DbPath:= AArgs.DbPaths[0]
  else DbPath:= AArgs.DbPath;
  if DbPath = '' then
  begin
    Writeln(ErrOutput, 'Usage: drag-lint schema --db <file.sqlite> [--format text|json]');
    Exit(2);
  end;

  UseJson:= AArgs.AsJson or SameText(AArgs.Format, 'json');

  { READ-ONLY open: no Migrate call anywhere in this verb. Reads only. }
  Store:= TSQLiteSymbolStore.Create(DbPath, {AReadOnly=}True);
  try
    Conn:= Store.GetConnection;

    { schema_version -- best-effort; 0/absent when schema_meta itself is missing
      (mirrors IsSchemaCurrent's own guarded probe). }
    SchemaVer:= 0;
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= Conn;
      Q.SQL.Text:= 'SELECT value FROM schema_meta WHERE key = ''schema_version'' LIMIT 1';
      try
        Q.Open;
        if not Q.IsEmpty then SchemaVer:= StrToIntDef(Q.Fields[0].AsString, 0);
      except
        SchemaVer:= 0;
      end;
    finally
      Q.Free;
    end;

    { Table list -- trusted names from sqlite_master, but each is re-validated
      against ^[A-Za-z_][A-Za-z0-9_]*$ before being inlined into SQL below. }
    SetLength(TableNames, 0);
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= Conn;
      Q.SQL.Text:= 'SELECT name FROM sqlite_master WHERE type=''table'' AND name NOT LIKE ''sqlite_%'' ORDER BY name';
      Q.Open;
      while not Q.Eof do
      begin
        TableNames:= TableNames + [Q.FieldByName('name').AsString];
        Q.Next;
      end;
    finally
      Q.Free;
    end;

    if UseJson then
    begin
      JRoot:= TJSONObject.Create;
      try
        JRoot.AddPair('schema_version', TJSONNumber.Create(SchemaVer));
        JTables:= TJSONArray.Create;
        for T in TableNames do
        begin
          if not IsSafeIdent(T) then Continue; // defensive: skip anything non-identifier-shaped

          JTable:= TJSONObject.Create;
          JTable.AddPair('name', T);

          QCount:= TFDQuery.Create(nil);
          try
            QCount.Connection:= Conn;
            QCount.SQL.Text:= 'SELECT COUNT(*) FROM "' + T + '"';
            QCount.Open;
            RowCount:= QCount.Fields[0].AsLargeInt;
          finally
            QCount.Free;
          end;
          JTable.AddPair('row_count', TJSONNumber.Create(RowCount));

          JCols:= TJSONArray.Create;
          QCols:= TFDQuery.Create(nil);
          try
            QCols.Connection:= Conn;
            QCols.SQL.Text:= 'PRAGMA table_info(''' + T + ''')';
            QCols.Open;
            while not QCols.Eof do
            begin
              JCol:= TJSONObject.Create;
              JCol.AddPair('name', QCols.FieldByName('name').AsString);
              JCol.AddPair('type', QCols.FieldByName('type').AsString);
              JCols.AddElement(JCol);
              QCols.Next;
            end;
          finally
            QCols.Free;
          end;
          JTable.AddPair('columns', JCols);

          JTables.AddElement(JTable);
        end; // for T
        JRoot.AddPair('tables', JTables);

        OutStr:= JRoot.Format(2);
      finally
        JRoot.Free;
      end;
    end
    else
    begin
      SB:= TStringBuilder.Create;
      try
        SB.AppendLine(Format('schema_version: %d', [SchemaVer]));
        for T in TableNames do
        begin
          if not IsSafeIdent(T) then Continue;

          QCount:= TFDQuery.Create(nil);
          try
            QCount.Connection:= Conn;
            QCount.SQL.Text:= 'SELECT COUNT(*) FROM "' + T + '"';
            QCount.Open;
            RowCount:= QCount.Fields[0].AsLargeInt;
          finally
            QCount.Free;
          end;
          SB.AppendLine(Format('%s (%d rows):', [T, RowCount]));

          QCols:= TFDQuery.Create(nil);
          try
            QCols.Connection:= Conn;
            QCols.SQL.Text:= 'PRAGMA table_info(''' + T + ''')';
            QCols.Open;
            while not QCols.Eof do
            begin
              SB.AppendLine(Format('  %s %s', [QCols.FieldByName('name').AsString, QCols.FieldByName('type').AsString]));
              QCols.Next;
            end;
          finally
            QCols.Free;
          end;
        end; // for T
        OutStr:= SB.ToString;
      finally
        SB.Free;
      end;
    end; // else

    if AArgs.Output <> '' then TFile.WriteAllText(AArgs.Output, OutStr, TEncoding.ANSI)
    else Writeln(OutStr);
  finally
    Store.Free;
  end; // try
end; // function

{ Local re-declarations of the tree-sitter grammar entry points, mirroring the
  pattern already used by DRagLint.Parser.Delphi13 (interface-visible, so not
  re-declared here) and DRagLint.Lint.Linter (implementation-only, NOT visible
  outside that unit -- so tree_sitter_dfm needs its own local decl here). Both
  DLLs (tree-sitter-delphi13.dll / tree-sitter-dfm.dll) are already runtime
  dependencies of this exe via the indexer/linter, so this adds no new deploy
  requirement. }
function tree_sitter_dfm: PTSLanguage; cdecl;
external 'tree-sitter-dfm';

const
  CLI_VERB_COUNT = 60; // informational only, not load-bearing; approximate verb count

/// <summary>Returns the tree-sitter ABI version for the given grammar, or
/// 'unknown' if the grammar's entry point cannot be called (never fabricated).</summary>
/// <param name="AGetLanguage">The grammar's cdecl entry-point function pointer
/// (e.g. @tree_sitter_delphi13 or @tree_sitter_dfm).</param>
/// <returns>The integer ABI version as a string, or 'unknown' on any failure.</returns>
function TreeSitterGrammarVersion(AGetLanguage: TTSGetLanguageFunc): string;
var
  Lang: PTSLanguage;
begin
  try
    Lang:= AGetLanguage();
    if Lang = nil then Result:= 'unknown'
    else Result:= IntToStr(Lang.Version);
  except
    Result:= 'unknown';
  end;
end;

/// <summary>Best-effort probe for FTS5 + trigram tokenizer availability, using
/// the same in-memory create-and-match check as DoSelfTestFts5 but returning a
/// Boolean instead of printing.</summary>
/// <returns>True if FTS5 with the trigram tokenizer works in this SQLite build;
/// False on any exception.</returns>
function ProbeFts5Available: Boolean;
var
  Conn: TFDConnection;
  Q   : TFDQuery     ;
begin
  Conn:= TFDConnection.Create(nil);
  try
    try
      Conn.DriverName:= 'SQLite';
      Conn.Params.Values['Database']:= ':memory:';
      Conn.Connected:= True;
      Conn.ExecSQL('CREATE VIRTUAL TABLE t USING fts5(x, tokenize=''trigram'')');
      Conn.ExecSQL('INSERT INTO t(rowid, x) VALUES (1, ''Folder not found'')'  );
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= Conn;
        Q.Sql.Text:= 'SELECT rowid FROM t WHERE t MATCH ''older'''; // substring
        Q.Open;
        Result:= (not Q.Eof) and (Q.FieldByName('rowid').AsInteger = 1);
      finally
        Q.Free;
      end;
    except
      Result:= False;
    end; // try
  finally
    Conn.Free;
  end; // try
end; // function

/// <summary>drag-lint info [--json] -- prints engine self-info: version, build
/// date (from the exe's own file timestamp), MIT license, description,
/// tree-sitter grammar versions, capabilities (FTS5, CLI verb count), the exe
/// path, and the build platform. Read-only; no DB, no side effects. --json emits
/// the stable schema "info/1"; without it, a human-readable block. Consumed by
/// the IDE About box.</summary>
/// <returns>0 always.</returns>
function DoInfo(const AArgs: TArgs): Integer;
var
  UseJson  : Boolean;
  BuildDate: string;
  Age      : TDateTime;
  ExePath  : string;
  Plat     : string;
  Fts5     : Boolean;
  TsDelphi : string;
  TsDfm    : string;
  JRoot, JTs, JCap: TJSONObject;
begin
  Result:= 0;
  UseJson:= AArgs.AsJson or SameText(AArgs.Format, 'json');
  ExePath:= ParamStr(0);
  if FileAge(ExePath, Age) then BuildDate:= FormatDateTime('yyyy-mm-dd hh:nn:ss', Age)
  else BuildDate:= 'unknown';
  {$IFDEF WIN64} Plat:= 'Win64'; {$ELSE} Plat:= 'Win32'; {$ENDIF}
  Fts5:= ProbeFts5Available;                                    { small helper: try/except the FTS5 create, mirrors DoSelfTestFts5 }
  TsDelphi:= TreeSitterGrammarVersion(tree_sitter_delphi13);     { returns 'N' or 'unknown' }
  TsDfm:= TreeSitterGrammarVersion(tree_sitter_dfm);

  if UseJson then
  begin
    JRoot:= TJSONObject.Create;
    try
      JRoot.AddPair('schema', 'info/1');
      JRoot.AddPair('name', 'drag-lint');
      JRoot.AddPair('version', VERSION);
      JRoot.AddPair('build_date', BuildDate);
      JRoot.AddPair('license', 'MIT');
      JRoot.AddPair('description', 'symbol-aware index + RAG + lint for Delphi/Pascal');
      JTs:= TJSONObject.Create;
      JTs.AddPair('delphi13', TsDelphi);
      JTs.AddPair('dfm', TsDfm);
      JRoot.AddPair('tree_sitter', JTs);
      JCap:= TJSONObject.Create;
      JCap.AddPair('fts5', TJSONBool.Create(Fts5));
      JCap.AddPair('cli_verbs', TJSONNumber.Create(CLI_VERB_COUNT));
      JRoot.AddPair('capabilities', JCap);
      JRoot.AddPair('exe_path', ExePath);
      JRoot.AddPair('platform', Plat);
      Writeln(JRoot.ToJSON);
    finally
      JRoot.Free;
    end;
  end
  else
  begin
    Writeln('drag-lint ', VERSION, '  (built ', BuildDate, ')');
    Writeln('License: MIT');
    Writeln('symbol-aware index + RAG + lint for Delphi/Pascal');
    Writeln('tree-sitter: delphi13 ', TsDelphi, ' / dfm ', TsDfm);
    Writeln('capabilities: FTS5=', BoolToStr(Fts5, True), ', CLI verbs=', CLI_VERB_COUNT);
    Writeln('exe: ', ExePath, '   platform: ', Plat);
  end;
end; // function

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
  if Pos = '' then begin Writeln('Usage: drag-lint typeat <file>:<line>:<col> [--db <path>] ' + '[--format text|json]'); Exit(2); end;

  // Parse last two colon segments as line:col.
  // e.g. "C:\foo\bar.pas:17:8" -> Parts=[..,"17","8"]
  Parts:= Pos.Split([':']);
  if Length(Parts) < 3 then begin Writeln('ERROR: position must be <file>:<line>:<col>, got: ', Pos); Exit(2); end;
  Col:= StrToIntDef(Parts[High(Parts)], 0);
  Line:= StrToIntDef(Parts[High(Parts) - 1], 0);
  // Everything before the last two segments is the file path.
  // Re-join first (n-2) parts with ':' to handle drive letters.
  var PartCount:= Length(Parts) - 2;
  FilePart:= string.Join(':', System.Copy(Parts, 0, PartCount));

  if (Line <= 0) or (Col <= 0) then begin Writeln('ERROR: line and col must be positive integers'); Exit (2 ); end;

  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Writeln('Run "drag-lint index <path>" first.'); Exit (2 ); end;

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
  if AArgs.QName = '' then begin Writeln('Usage: drag-lint generate-docs --qname X [--format xmldoc|pasdoc] [--db PATH]'); Exit (2 ); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  if SameText(AArgs.Format, 'pasdoc') then Fmt:= dsfPasDoc
  else Fmt:= dsfXmlDoc;
  Stub:= TDocStubGenerator.Generate(Store, AArgs.QName, Fmt);
  if Stub = '' then begin Writeln(Format('No stub generated for %s (symbol not found)', [AArgs.QName])); Exit(1); end;
  Writeln(Stub);
  Result:= 0;
end; // function

// AutoDocument (whole-unit batch): drag-lint document --unit <file.pas> [--apply|--json|--no-backup] [--db PATH]
// Documents every PUBLIC (interface-section) decl in the unit via TDocBatch.
// Facts-only default: decls that would produce only an all-TODO comment (no
// facts, no prior doc) are skipped. Dry-run (edit preview) unless --apply.
// Exit 0 on ok (even when 0 decls changed), 2 on usage/db error.
function DoDocumentUnit(const AArgs: TArgs): Integer;
var
  Store  : ISymbolStore     ;
  Ok     : Boolean          ;
  Opts   : TDocBatchOptions ;
  Res    : TDocBatchResult  ;
  O      : TJSONObject      ;
  Applied: Boolean          ;
begin
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  Store:= OpenReadOnlyStore(AArgs.DbPath, Ok);
  if not Ok then Exit(2);

  Opts:= Default(TDocBatchOptions);
  // --stubs flips the facts-only default: on = keep pure all-TODO creates too.
  Opts.Stubs:= AArgs.DocStubs;
  Opts.IncludeSeeAlso:= AArgs.DocSeeAlso; // ADF T4: --seealso opts in <seealso> crefs.
  Opts.IncludeSince:= AArgs.DocSince; Opts.BaseDir:= AArgs.DocBaseDir; // ADF T5: --since opts in the git <since> date.
  Opts.ExtraStores:= OpenExtraStores(AArgs); // multi-db: other resolved --db's searched for callers.
  Opts.MaxReturnCases:= LoadDocMaxReturnCases; // Task 10: manifest docs.max_return_cases cap (default 20 on any load failure).
  Res:= TDocBatch.DocumentUnit(Store, AArgs.DocUnit, Opts);

  Applied:= AArgs.Apply and (Length(Res.Edits) > 0);
  if Applied then TTextEditApplier.Apply(Res.Edits, not AArgs.NoBackup);

  if AArgs.AsJson then
  begin
    O:= TJSONObject.Create;
    try
      O.AddPair('unit', AArgs.DocUnit);
      O.AddPair('declCount', TJSONNumber.Create(Res.DeclCount));
      O.AddPair('docCount' , TJSONNumber.Create(Res.DocCount ));
      O.AddPair('edits'    , TJSONNumber.Create(Length(Res.Edits)));
      O.AddPair('applied'  , TJSONBool.Create(Applied));
      Writeln(O.ToJson);
    finally
      O.Free;
    end;
    Exit(0);
  end;

  if Length(Res.Edits) = 0 then Writeln(Format('doc: %d public decl(s), nothing to document', [Res.DeclCount]))
  else if not AArgs.Apply then begin Writeln(TTextEditApplier.RenderDryRun(Res.Edits)); Writeln(Format('doc: %d/%d decl(s), %d edit(s) -- pass --apply to write', [Res.DocCount, Res.DeclCount, Length(Res.Edits)])); end
  else Writeln(Format('doc: %d/%d decl(s) documented, %d edit(s) applied%s', [Res.DocCount, Res.DeclCount, Length(Res.Edits), IfThen(AArgs.NoBackup, '', ' (.bak written)')]));
  Result:= 0;
end; // function

// Shared apply/report path for the multi-file AutoDocument batch results
// (document --project / document-all). AScope names the source in --json
// ('project' | 'all'); AScopeVal is the .dpr/.dproj path or '' for document-all.
// Applies the aggregated per-file edits (TTextEditApplier groups+sorts per file)
// unless dry-run, then prints the summary or the --json aggregate. Exit 0.
function ReportDocBatch(const AArgs: TArgs; const ARes: TDocBatchResult;
  const AScope, AScopeVal: string): Integer;
var
  O      : TJSONObject;
  Applied: Boolean    ;
begin
  Applied:= AArgs.Apply and (Length(ARes.Edits) > 0);
  if Applied then TTextEditApplier.Apply(ARes.Edits, not AArgs.NoBackup);

  if AArgs.AsJson then
  begin
    O:= TJSONObject.Create;
    try
      O.AddPair(AScope, AScopeVal);
      O.AddPair('declCount', TJSONNumber.Create(ARes.DeclCount));
      O.AddPair('docCount' , TJSONNumber.Create(ARes.DocCount ));
      O.AddPair('edits'    , TJSONNumber.Create(Length(ARes.Edits)));
      O.AddPair('applied'  , TJSONBool.Create(Applied));
      Writeln(O.ToJson);
    finally
      O.Free;
    end;
    Exit(0);
  end;

  if Length(ARes.Edits) = 0 then Writeln(Format('doc: %d public decl(s), nothing to document', [ARes.DeclCount]))
  else if not AArgs.Apply then begin Writeln(TTextEditApplier.RenderDryRun(ARes.Edits)); Writeln(Format('doc: %d/%d decl(s), %d edit(s) -- pass --apply to write', [ARes.DocCount, ARes.DeclCount, Length(ARes.Edits)])); end
  else Writeln(Format('doc: %d/%d decl(s) documented, %d edit(s) applied%s', [ARes.DocCount, ARes.DeclCount, Length(ARes.Edits), IfThen(AArgs.NoBackup, '', ' (.bak written)')]));
  Result:= 0;
end; // function

// AutoDocument (project-wide batch): drag-lint document --project <p.dpr/.dproj>
//   [--stubs|--apply|--json|--no-backup] [--db PATH]
// Documents every public decl across the project's compile closure via
// TDocBatch.DocumentProject. Facts-only default; --stubs opts in the all-TODO
// creates. Dry-run unless --apply. Exit 0 on ok, 2 on usage/db error.
function DoDocumentProject(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore    ;
  Ok   : Boolean         ;
  Opts : TDocBatchOptions;
  Res  : TDocBatchResult ;
begin
  if not TFile.Exists(AArgs.ProjectPath) then begin Writeln(Format('Project file not found: %s', [AArgs.ProjectPath])); Exit(2); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  Store:= OpenReadOnlyStore(AArgs.DbPath, Ok);
  if not Ok then Exit(2);

  Opts:= Default(TDocBatchOptions);
  Opts.Stubs:= AArgs.DocStubs;
  Opts.IncludeSeeAlso:= AArgs.DocSeeAlso; // ADF T4: --seealso opts in <seealso> crefs.
  Opts.IncludeSince:= AArgs.DocSince; Opts.BaseDir:= AArgs.DocBaseDir; // ADF T5: --since opts in the git <since> date.
  Opts.ExtraStores:= OpenExtraStores(AArgs); // multi-db: other resolved --db's searched for callers.
  Opts.MaxReturnCases:= LoadDocMaxReturnCases; // Task 10: manifest docs.max_return_cases cap (default 20 on any load failure).
  Res:= TDocBatch.DocumentProject(Store, AArgs.ProjectPath, Opts);
  Result:= ReportDocBatch(AArgs, Res, 'project', AArgs.ProjectPath);
end; // function

// AutoDocument (whole-index batch): drag-lint document-all
//   [--stubs|--apply|--json|--no-backup] [--db PATH]
// Documents every public decl in EVERY indexed unit (no project scope) via
// TDocBatch.DocumentAll. Facts-only default; --stubs opts in the all-TODO
// creates. Dry-run unless --apply. Exit 0 on ok, 2 on usage/db error.
function DoDocumentAll(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore    ;
  Ok   : Boolean         ;
  Opts : TDocBatchOptions;
  Res  : TDocBatchResult ;
begin
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  Store:= OpenReadOnlyStore(AArgs.DbPath, Ok);
  if not Ok then Exit(2);

  Opts:= Default(TDocBatchOptions);
  Opts.Stubs:= AArgs.DocStubs;
  Opts.IncludeSeeAlso:= AArgs.DocSeeAlso; // ADF T4: --seealso opts in <seealso> crefs.
  Opts.IncludeSince:= AArgs.DocSince; Opts.BaseDir:= AArgs.DocBaseDir; // ADF T5: --since opts in the git <since> date.
  Opts.ExtraStores:= OpenExtraStores(AArgs); // multi-db: other resolved --db's searched for callers.
  Opts.MaxReturnCases:= LoadDocMaxReturnCases; // Task 10: manifest docs.max_return_cases cap (default 20 on any load failure).
  Res:= TDocBatch.DocumentAll(Store, Opts);
  Result:= ReportDocBatch(AArgs, Res, 'scope', 'all');
end; // function

// AutoDocument Chunk 1: drag-lint document --qname X [--apply|--json|--no-backup] [--db PATH]
// Generates or repairs a managed-region DocInsight comment for the symbol. Dry-run
// (prints the edit preview) unless --apply. Exit 0 on ok/unchanged, 1 not found,
// 2 usage/db error. Read-only DB access (writes source files, not the index).
// When --unit is given (instead of --qname), delegates to the whole-unit batch.
function DoDocument(const AArgs: TArgs): Integer;
var
  Store  : ISymbolStore                         ;
  Res    : DRagLint.Doc.Document.TDocumentResult;
  Ok     : Boolean                              ;
  O      : TJSONObject                          ;
  Applied: Boolean                              ;
begin
  if AArgs.ProjectPath <> '' then Exit(DoDocumentProject(AArgs));
  if AArgs.DocUnit <> '' then Exit(DoDocumentUnit(AArgs));
  if AArgs.QName = '' then begin Writeln('Usage: drag-lint document (--qname X | --unit F | --project P) [--stubs|--apply|--json|--no-backup] [--db PATH]'); Exit (2 ); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  Store:= OpenReadOnlyStore(AArgs.DbPath, Ok);
  if not Ok then Exit(2);

  Res:= DRagLint.Doc.Document.TDocumenter.BuildFor(Store, AArgs.QName, AArgs.DocSeeAlso,
    AArgs.DocSince, AArgs.DocBaseDir, OpenExtraStores(AArgs), LoadDocMaxReturnCases); // ADF T5: --since (git <since> date) + --base-dir repo root; multi-db: other resolved --db's searched for callers; Task 10: manifest docs.max_return_cases cap.

  if Res.Action = DRagLint.Doc.Document.daNotFound then begin Writeln(Format('symbol not found: %s', [AArgs.QName])); Exit(1); end;

  Applied:= AArgs.Apply and (Length(Res.Edits) > 0);
  if Applied then TTextEditApplier.Apply(Res.Edits, not AArgs.NoBackup);

  if AArgs.AsJson then
  begin
    O:= TJSONObject.Create;
    try
      O.AddPair('qname', Res.QName   );
      O.AddPair('file' , Res.FilePath);
      O.AddPair('line', TJSONNumber.Create(Res.Line));
      // daNotFound already returned above (text + exit 1) before this --json
      // block, so it can never reach here; the else is a defensive fallback for
      // an unexpected action value, NOT a reachable 'not_found' result.
      case Res.Action of
        DRagLint.Doc.Document.daCreated  : O.AddPair('action', 'created'  );
        DRagLint.Doc.Document.daExtended : O.AddPair('action', 'extended' );
        DRagLint.Doc.Document.daUnchanged: O.AddPair('action', 'unchanged');
        else O.AddPair('action', 'unknown' );
      end;
      O.AddPair('edits', TJSONNumber.Create(Length(Res.Edits)));
      O.AddPair('applied', TJSONBool.Create(Applied));
      Writeln(O.ToJson);
    finally
      O.Free;
    end; // try
    Exit(0);
  end; // if

  if Res.Action = DRagLint.Doc.Document.daUnchanged then Writeln('doc: up to date (no change)')
  else if not AArgs.Apply then begin Writeln(TTextEditApplier.RenderDryRun(Res.Edits)); Writeln(Format('doc: %d edit(s) -- pass --apply to write', [Length(Res.Edits)])); end
  else Writeln(Format(
      'doc: %s -- %d edit(s) applied%s',
      [IfThen(Res.Action = DRagLint.Doc.Document.daCreated, 'created', 'extended'), Length(Res.Edits), IfThen(AArgs.NoBackup, '', ' (.bak written)')]));
  Result:= 0;
end; // function

// Task 5: parses the --methods <csv> flag into a TEnumHelperMethods set.
// '' (flag absent) -> all 6 (the documented default). Recognized tokens:
// tobyte,frombyte,tointeger,frominteger,tostring,fromstring (case-insensitive,
// comma-separated, blank entries skipped). Returns False (AMethods undefined)
// on any unrecognized token so the caller can raise a usage error -- this
// mirrors --disable/--enable's CSV-of-ids convention elsewhere in this file,
// but those are validated downstream by the rule catalog; enum-helper methods
// have no catalog to check against, so parsing itself is the validation gate.
function TryParseEnumMethods(const ACsv: string; out AMethods: TEnumHelperMethods): Boolean;
const
  cAllMethods = [ehmToByte, ehmFromByte, ehmToInteger, ehmFromInteger, ehmToString, ehmFromString];
var
  Token: string;
  T    : string;
begin
  if Trim(ACsv) = '' then begin AMethods:= cAllMethods; Exit(True); end;
  AMethods:= [];
  for Token in ACsv.Split([',']) do
  begin
    T:= LowerCase(Trim(Token));
    if T = '' then Continue
    else if T = 'tobyte'      then Include(AMethods, ehmToByte)
    else if T = 'frombyte'    then Include(AMethods, ehmFromByte)
    else if T = 'tointeger'   then Include(AMethods, ehmToInteger)
    else if T = 'frominteger' then Include(AMethods, ehmFromInteger)
    else if T = 'tostring'    then Include(AMethods, ehmToString)
    else if T = 'fromstring'  then Include(AMethods, ehmFromString)
    else Exit(False);
  end;
  Result:= True;
end; // function

/// <summary>drag-lint create-enum-helper --qname &lt;TEnum&gt; [--apply|--json|
/// --no-backup] [--methods &lt;csv&gt;] [--tostring rtti|case] [--db PATH].
/// Generates a Byte-family record helper for an enum type via
/// TEnumHelperRefactoring.Build (Resolve+Generate+Place). Dry-run (preview)
/// unless --apply. Mirrors the `document --qname` verb's shape.</summary>
/// <param name="AArgs">Consumes QName (--qname), DbPath (--db), Apply,
/// NoBackup, AsJson, EnumMethodsStr (--methods), EnumToString (--tostring).</param>
/// <returns>0 when Action=ehaBuilt (preview, --json, or --apply all succeed);
/// 1 when the enum resolves but Build refuses (ehaExists/ehaNoImplSection) or
/// AEnumQName does not resolve (ehaNotFound); 2 on a usage/db error.</returns>
/// <remarks>Idempotent: once the generated helper is indexed, a second
/// --apply run resolves Action=ehaExists and makes no edit (Build never
/// overwrites a hand-written or previously-generated helper). Refusal reasons
/// are written to stderr (and to the JSON 'action'/'file' fields under
/// --json) so scripts can detect them independently of stdout.</remarks>
function DoCreateEnumHelper(const AArgs: TArgs): Integer;
var
  Store     : ISymbolStore     ;
  Ok        : Boolean          ;
  Methods   : TEnumHelperMethods;
  ToStrMode : TToStringMode    ;
  Res       : TEnumHelperResult;
  O         : TJSONObject      ;
  Applied   : Boolean          ;
  ActionStr : string           ;
begin
  if AArgs.QName = '' then
  begin
    Writeln(ErrOutput, 'Usage: drag-lint create-enum-helper --qname <TEnum> [--apply|--json|--no-backup] [--methods <csv>] [--tostring rtti|case] [--db PATH]');
    Exit(2);
  end;
  if not TryParseEnumMethods(AArgs.EnumMethodsStr, Methods) then
  begin
    Writeln(ErrOutput, Format('ERROR: unrecognized --methods token in "%s" (expected tobyte,frombyte,tointeger,frominteger,tostring,fromstring)', [AArgs.EnumMethodsStr]));
    Exit(2);
  end;
  if SameText(AArgs.EnumToString, 'case') then ToStrMode:= tsmCase
  else if (AArgs.EnumToString = '') or SameText(AArgs.EnumToString, 'rtti') then ToStrMode:= tsmRtti
  else begin Writeln(ErrOutput, Format('ERROR: --tostring must be rtti or case, got "%s"', [AArgs.EnumToString])); Exit(2); end;

  if not FileExists(AArgs.DbPath) then begin Writeln(ErrOutput, Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  Store:= OpenReadOnlyStore(AArgs.DbPath, Ok);
  if not Ok then Exit(2);

  Res:= TEnumHelperRefactoring.Build(Store, AArgs.QName, Methods, ToStrMode);

  case Res.Action of
    ehaBuilt          : ActionStr:= 'built';
    ehaExists         : ActionStr:= 'exists';
    ehaNoImplSection  : ActionStr:= 'no_impl_section';
    ehaNotFound       : ActionStr:= 'not_found';
    else                ActionStr:= 'unknown';
  end;

  Applied:= AArgs.Apply and (Res.Action = ehaBuilt) and (Length(Res.Edits) > 0);
  if Applied then TTextEditApplier.Apply(Res.Edits, not AArgs.NoBackup);

  if AArgs.AsJson then
  begin
    O:= TJSONObject.Create;
    try
      O.AddPair('qname' , Res.EnumName);
      O.AddPair('file'  , Res.FilePath);
      O.AddPair('action', ActionStr   );
      O.AddPair('edits' , TJSONNumber.Create(Length(Res.Edits)));
      O.AddPair('applied', TJSONBool.Create(Applied));
      Writeln(O.ToJson);
    finally
      O.Free;
    end; // try
    if Res.Action <> ehaBuilt then Exit(1);
    Exit(0);
  end; // if

  if Res.Action <> ehaBuilt then
  begin
    Writeln(ErrOutput, Format('REFUSED: %s', [Res.Message]));
    Exit(1);
  end;

  if not AArgs.Apply then
  begin
    Writeln(TTextEditApplier.RenderDryRun(Res.Edits));
    Writeln(Format('create-enum-helper: %d edit(s) for %s -- pass --apply to write', [Length(Res.Edits), Res.EnumName]));
  end
  else
    Writeln(Format('create-enum-helper: %s helper built, %d edit(s) applied%s',
      [Res.EnumName, Length(Res.Edits), IfThen(AArgs.NoBackup, '', ' (.bak written)')]));
  Result:= 0;
end; // function

/// <summary>drag-lint helpers-of &lt;T&gt; [--json] [--db PATH]. Prints every
/// record/class helper edge targeting type T by NAME anywhere in the indexed
/// codebase, via ISymbolStore.FindHelpersOfType. Read-only; used by the IDE
/// menu enablement predicate (Task 8). Note: the enum-helper generator's own
/// existing-helper guard uses the symbol-identity-scoped
/// FindHelpersOfTypeSymbol (Task 9b), not this bare-name verb.</summary>
/// <param name="AArgs">Consumes Name (positional &lt;T&gt; or --name), DbPath
/// (--db), AsJson.</param>
/// <returns>0 always (zero edges is a valid, non-error result -- "no helper
/// exists yet" is exactly what the IDE enablement check wants to see); 2 on a
/// usage/db error.</returns>
function DoHelpersOf(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore     ;
  Ok   : Boolean          ;
  Edges: TArray<THelperEdge>;
  E    : THelperEdge      ;
  TargetName: string      ;
  HelperSym : TSymbol     ;
  UnitPath  : string      ;
begin
  TargetName:= AArgs.Name;
  if TargetName = '' then TargetName:= AArgs.Path; // positional <T> falls into Path (no --name given)
  if TargetName = '' then begin Writeln(ErrOutput, 'Usage: drag-lint helpers-of <T> [--json] --db <db>'); Exit(2); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(ErrOutput, Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  Store:= OpenReadOnlyStore(AArgs.DbPath, Ok);
  if not Ok then Exit(2);

  Edges:= Store.FindHelpersOfType(TargetName);

  if AArgs.AsJson then
  begin
    var Arr: TJSONArray:= TJSONArray.Create;
    try
      for E in Edges do
      begin
        HelperSym:= Store.GetSymbolById(E.HelperSymbolId);
        UnitPath := Store.GetFilePath(HelperSym.FileId);
        var O: TJSONObject:= TJSONObject.Create;
        O.AddPair('helper', HelperSym.Name);
        O.AddPair('target', E.TargetName  );
        O.AddPair('unit'  , UnitPath       );
        Arr.AddElement(O);
      end;
      Writeln(Arr.ToJson);
    finally
      Arr.Free;
    end; // try
    Exit(0);
  end; // if

  if Length(Edges) = 0 then Writeln(Format('helpers-of %s: no helper found', [TargetName]))
  else
    for E in Edges do
    begin
      HelperSym:= Store.GetSymbolById(E.HelperSymbolId);
      UnitPath := Store.GetFilePath(HelperSym.FileId);
      Writeln(Format('%s helper for %s in %s', [HelperSym.Name, E.TargetName, UnitPath]));
    end;
  Result:= 0;
end; // function

// v0.69 D2b: drag-lint find-unit --name <Symbol> --in <file> [--json|--apply|--no-backup] --db <db>
// Resolves the unit declaring Symbol and inserts it into InFile's uses clause.
// Exit 0 on success or already-used; 1 if unresolvable or no edit; 2 on usage error.
function DoFindUnit(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore; Edits: TArray<TTextEdit>; ResolvedUnit: string; Already: Boolean;
begin
  if (AArgs.Name = '') or (AArgs.InFile = '') then
  begin Writeln('ERROR: find-unit needs --name <Symbol> --in <file>'); Exit(2); end;
  if AArgs.DbPath = '' then begin Writeln('ERROR: --db required'); Exit(2); end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(1);
  Edits:= TFindUnitRefactoring.Build(Store, AArgs.Name, AArgs.InFile, ResolvedUnit, Already);
  if Already then begin Writeln(Format('"%s" is already in the uses clause.', [ResolvedUnit])); Exit(0); end;
  if ResolvedUnit  = '' then begin Writeln(Format('Could not resolve a unit declaring "%s".', [AArgs.Name])); Exit(1); end;
  if Length(Edits) = 0 then begin Writeln('No edit computed.'); Exit(1); end;
  if AArgs.AsJson then
  begin
    var Arr: TJSONArray:= TJSONArray.Create;
    try
      for var E in Edits do
      begin
        var O: TJSONObject:= TJSONObject.Create;
        O.AddPair('file', E.FilePath);
        O.AddPair('unit', ResolvedUnit);
        O.AddPair('line', TJSONNumber.Create(E.Line));
        O.AddPair('text', E.Text);
        Arr.AddElement(O);
      end;
      Writeln(Arr.ToJson);
    finally Arr.Free; end;
    Exit(0);
  end; // if
  if not AArgs.Apply then begin Writeln(TTextEditApplier.RenderDryRun(Edits)); Writeln(Format('Dry run: add unit "%s". Pass --apply to write.', [ResolvedUnit])); Exit(0); end;
  var Touched: Integer:= TTextEditApplier.Apply(Edits, not AArgs.NoBackup);
  Writeln(Format('Applied: added "%s" (%d file).', [ResolvedUnit, Touched]));
  Result:= 0;
end; // function

// v0.69 D2b: drag-lint safe-delete --name <QName> [--json|--apply|--no-backup] --db <db>
// Deletes the declaration (and impl body) of QName iff it has zero references.
// Exit 0 on success; 2 on refused (referenced symbol) or usage error; 1 on no edit.
function DoSafeDelete(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore; Edits: TArray<TTextEdit>; Reason: string;
begin
  if AArgs.Name   = '' then begin Writeln('ERROR: safe-delete needs --name <QualifiedName>'); Exit(2); end;
  if AArgs.DbPath = '' then begin Writeln('ERROR: --db required'                           ); Exit(2); end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath); Store.Migrate;
  Edits:= TSafeDeleteRefactoring.Build(Store, AArgs.Name, Reason);
  if Reason <> '' then begin Writeln('REFUSED: ' + Reason); Exit(2); end;
  if Length(Edits) = 0 then begin Writeln('No edit computed.'); Exit(1); end;
  if AArgs.AsJson then
  begin
    var Arr: TJSONArray:= TJSONArray.Create;
    try
      for var E in Edits do
      begin
        var O: TJSONObject:= TJSONObject.Create;
        O.AddPair('file', E.FilePath);
        O.AddPair('delete_from', TJSONNumber.Create(E.Line   ));
        O.AddPair('delete_to'  , TJSONNumber.Create(E.EndLine));
        Arr.AddElement(O);
      end;
      Writeln(Arr.ToJson);
    finally Arr.Free; end;
    Exit(0);
  end;
  if not AArgs.Apply then begin Writeln(TTextEditApplier.RenderDryRun(Edits)); Writeln(Format('Dry run: delete "%s". Pass --apply to write.', [AArgs.Name])); Exit(0); end;
  var Touched: Integer:= TTextEditApplier.Apply(Edits, not AArgs.NoBackup);
  Writeln(Format('Deleted "%s" (%d file).', [AArgs.Name, Touched]));
  Result:= 0;
end; // function

/// <summary>drag-lint extract-method --file &lt;F&gt; --from-line &lt;L1&gt;
/// --to-line &lt;L2&gt; --name &lt;N&gt; [--json|--apply|--no-backup]. Pulls the
/// complete-statement run [L1..L2] out of its enclosing routine in F into a
/// new method/procedure named N, replacing the run with a call. Single-file,
/// no index/--db needed (TExtractMethodRefactoring.Build parses F directly).</summary>
/// <param name="AArgs">Parsed CLI args; consumes InFile (--file), FromLine
/// (--from-line), ToLine (--to-line), Name (--name), AsJson, Apply,
/// NoBackup.</param>
/// <returns>0 on success (dry-run preview, --json edit set, or --apply
/// applied); 2 on a refused/unsafe selection or usage error.</returns>
/// <remarks>Dry-run (default) prints TExtractMethodRefactoring.RenderDryRun;
/// --json prints the raw TTextEdit array; --apply writes via
/// TTextEditApplier.Apply (backup unless --no-backup). Every refusal reason
/// is written to stderr so scripts can capture it independently of stdout.</remarks>
function DoExtractMethod(const AArgs: TArgs): Integer;
var
  Edits : TArray<TTextEdit>;
  Refuse: string           ;
begin
  if (AArgs.InFile = '') or (AArgs.FromLine <= 0) or (AArgs.ToLine <= 0) or (AArgs.Name = '') then
  begin
    Writeln(ErrOutput, 'ERROR: extract-method needs --file <F> --from-line <L1> --to-line <L2> --name <N>');
    Exit(2);
  end;
  Edits:= TExtractMethodRefactoring.Build(AArgs.InFile, AArgs.FromLine, AArgs.ToLine, AArgs.Name, Refuse);
  if Refuse <> '' then begin Writeln(ErrOutput, 'REFUSED: ' + Refuse); Exit(2); end;
  if Length(Edits) = 0 then begin Writeln(ErrOutput, 'No edit computed.'); Exit(1); end;
  if AArgs.AsJson then
  begin
    var Arr: TJSONArray:= TJSONArray.Create;
    try
      for var E in Edits do
      begin
        var O: TJSONObject:= TJSONObject.Create;
        O.AddPair('file', E.FilePath);
        O.AddPair('line'   , TJSONNumber.Create(E.Line   ));
        O.AddPair('col'    , TJSONNumber.Create(E.Col    ));
        O.AddPair('endLine', TJSONNumber.Create(E.EndLine));
        O.AddPair('endCol' , TJSONNumber.Create(E.EndCol ));
        O.AddPair('text', E.Text);
        Arr.AddElement(O);
      end;
      Writeln(Arr.ToJson);
    finally Arr.Free; end;
    Exit(0);
  end; // if
  if not AArgs.Apply then
  begin
    Writeln(TExtractMethodRefactoring.RenderDryRun(Edits));
    Writeln(Format('Dry run: extract "%s". Pass --apply to write.', [AArgs.Name]));
    Exit(0);
  end;
  var Touched: Integer:= TTextEditApplier.Apply(Edits, not AArgs.NoBackup);
  Writeln(Format('Applied: extracted "%s" (%d file).', [AArgs.Name, Touched]));
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
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
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
  OutPath  : string                      ;
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
    if ProjectDb  = '' then ProjectDb:= D
    else if LibDb = '' then LibDb:= D;
  end;
  if ProjectDb = '' then begin Writeln('ERROR: no drag-lint index found. Pass --db <index.sqlite> or build the index first.'); Exit (2 ); end;

  { Open project store }
  Store:= TSQLiteSymbolStore.Create(ProjectDb);
  Store.Migrate;
  Findings:= nil;

  { Enumerate all indexed .pas files from the project store }
  FilePaths:= nil;
  for Fid in Store.GetAllFileIds do
  begin
    PasPath:= Store.GetFilePath(Fid);
    if SameText(ExtractFileExt(PasPath), '.pas') and TFile.Exists(PasPath) then FilePaths:= FilePaths + [PasPath];
  end;
  Writeln(Format('lint-all: scanning %d .pas file(s)', [Length(FilePaths)]));

  { Per-file rules: external .scm rules + all built-in AST checks }
  var Cfg: TLintConfig:= LoadLintConfig(AArgs);
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
            Writeln(ErrOutput, Format('lint-all: [%d/%d] %d%% %s', [FileIdx + 1, Length(FilePaths), Pct, ExtractFileName(PasPath)]));
            Flush(ErrOutput);
            LastPct:= Pct;
          end;
        end;
        { v12 (M1): the precise store-path string-equality built-in (in CheckTypeAware
          below) supersedes the broad .scm rule when a store is present -- drop the
          .scm findings so we don't double-report and so its type-blind FPs are gone. }
        var LintF:= Linter.LintFile(PasPath);
        if Store <> nil then
        begin
          var KeptSE: TArray<TLintFinding>;
          for var LF in LintF do
            if not SameText(LF.RuleId, 'string-equality-comparison') then KeptSE:= KeptSE + [LF];
          LintF:= KeptSE;
        end;
        Findings:= Findings + LintF;
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals        (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors        (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnbalancedBeginEnd  (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRaiseInFinally      (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit       (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally(PasPath);
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckMissingInherited(PasPath) do Findings:= Findings + [F];
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRoutineMetrics(
          PasPath, Cfg.ThresholdFor('too-many-parameters', 7), Cfg.ThresholdFor('too-many-locals', 25), Cfg.ThresholdFor('method-too-long', 120),
          Cfg.ThresholdFor('deep-nesting', 5)) do Findings:= Findings + [F];
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware(PasPath, Store, Store.FindFileIdByPath(PasPath)) do { v11 (M1): exact type resolution }
          Findings:= Findings + [F];
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFireDacSqlMismatch       (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnprotectedFree          (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUseAfterFree             (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUiThread                 (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckGlobalFormVars           (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckMutableGlobalVars        (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSeparateQueryFromModifier(PasPath); { v0.83: CQS (OFF) }
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckShellExec                (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckPathTraversal            (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckLoopAtMostOnce           (PasPath);
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckFormatCall(PasPath) do Findings:= Findings + [F];
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSwallowedExcept(PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckDatasetOpen    (PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCriticalSection(PasPath);
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints(PasPath, Cfg.ThresholdFor('too-many-exit-points', 5));
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity(PasPath, Cfg.ThresholdFor('cyclomatic-complexity', 15));
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity(PasPath, Cfg.ThresholdFor('cognitive-complexity', 25));
        Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckVirtualInConstructor(PasPath, Store, Store.FindFileIdByPath(PasPath)); { v12 (M1): cross-unit }
        Findings:= Findings + DRagLint.Diagnostics.FlowChecks.TFlowChecker.Check(PasPath, Store, Store.FindFileIdByPath(PasPath)); { M2: flow checks, store-exact managed types }
        { v0.68: naming-convention prefix rules (store-optional; enables exception-ancestry sub-check) }
        for F in DRagLint.Diagnostics.NamingChecks.TNamingChecker.Check(PasPath, Cfg.Naming, Store, Store.FindFileIdByPath(PasPath)) do Findings:= Findings + [F];
        { v0.68: dead-code checks (unused-parameter, identical-then-else, referenced-never-set);
          v0.70-72: + redundant-parens/commented-out-code/function-result-ignored + #5/#6/#7 rules }
        for F in DRagLint.Diagnostics.DeadCodeChecks.TDeadCodeChecker.Check(
          PasPath, Cfg.ThresholdFor('case-with-too-few-branches', 2), Cfg.ThresholdFor('boolean-expression-complexity', 4), Cfg.ThresholdFor('unit-too-large', 2000),
          Cfg.ThresholdFor('message-chain', 4)) do Findings:= Findings + [F];
      except
        on E: Exception do Writeln(ErrOutput, Format('lint-all: skip %s (%s: %s)', [ExtractFileName(PasPath), E.ClassName, E.Message]));
      end; // try
      { Free cached tree for this file before moving to the next }
      DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear;
    end; // for
  finally
    Linter.Free;
  end; // try

  { Project-wide rules }
  Findings:= Findings + DRagLint.Lint.ProjectRules.TProjectLintRules.Run(Store, '');
  { v0.78: CK class metrics (DIT/NOC/CBO/RFC/LCOM4). Project-wide; runs only here. }
  Findings:= Findings + DRagLint.Lint.ClassMetrics.TClassMetrics.Run(Store, Cfg, '');
  { ADF Task 7: missing-doc -- store-backed (symbol_docs join), so it can only
    run where a store is open; ON by default (see RuleCatalog). }
  Findings:= Findings + DRagLint.Lint.DocRules.TDocLintRules.RunMissingDoc(Store);
  { ADF Task 8: doc-drift -- store-backed (needs the doc graph + Raises facts);
    ON by default. Its --fix subset is applied in FinalizeAndOutput (Store passed). }
  Findings:= Findings + DRagLint.Lint.DocRules.TDocLintRules.RunDocDrift(Store);
  { v0.77: cross-file + within-file clone detection (#6). Runs ONLY here in
    lint-all (never the per-file Check) so within-file clones are reported once. }
  Findings:= Findings + DRagLint.Diagnostics.CloneChecks.TCloneChecker.CheckProject(FilePaths, Cfg.ThresholdFor('duplicate-code', 90));
  { Interface reference cycles (needs all file paths) }
  Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckInterfaceCycles(FilePaths);
  { Architecture layering (only if config present) }
  LayersCfg:= AArgs.LayersPath;
  if (LayersCfg = '') and FileExists('drag-lint-layers.json') then LayersCfg:= 'drag-lint-layers.json';
  if LayersCfg <> '' then Findings:= Findings + DRagLint.Lint.ProjectRules.TProjectLintRules.CheckLayering(Store, LayersCfg);
  { DPR/dproj membership cross-check (unit-not-in-dpr) }
  if AArgs.ProjectPath <> '' then Findings:= Findings + DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr(AArgs.ProjectPath);
  { Used-unit resolvability (used-unit-not-resolvable) }
  Findings := Findings + DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable(Store, LibDb);

  { Resolve output path: --output, or lint-report-YYYYMMDD.txt beside the DB }
  OutPath:= AArgs.Output;
  if OutPath = '' then
  begin
    var BaseDir: string;
    if AArgs.ProjectPath <> '' then BaseDir:= ExtractFilePath(AArgs.ProjectPath)
    else BaseDir:= ExtractFilePath(ProjectDb);
    OutPath:= TPath.Combine(BaseDir, 'lint-report-' + FormatDateTime('YYYYMMDD', Now) + '.txt');
  end;

  { v0.71/v0.74/v0.79/v0.80/v0.81/v0.82: function-result-ignored + unsafe-typecast-without-is +
    exhaustive-enum-case + multiple-statements-per-line + magic-literal +
    boolean-flag-parameter + public-writable-field + loop-control-flag +
    mutable-global-variable + repeated-type-switch + middle-man + default-encoding-io +
    fan-out + fan-in + feature-envy + instability + split-variable +
    separate-query-from-modifier + missing-doc
    are OFF by default here too (opt in via config "enabled"). middle-man / fan-out /
    fan-in / feature-envy / instability are emitted by TClassMetrics.Run above; catalog
    False alone does not suppress CLI output, so they must be listed here for the
    ShouldKeep filter to drop them by default. split-variable (flow) and
    separate-query-from-modifier (AST) are emitted above -- same reasoning.
    ADF Task 13 fix: missing-doc ships OFF (catalog default_enabled=false) but is
    a PROJECT-level rule (TDocLintRules), so it is NOT in Linter.DefaultDisabledRuleIds
    and would otherwise fire on every bare lint-all (the measured 1302-finding wave).
    List it here so ShouldKeep drops it by default; config "enabled":["missing-doc"]
    still overrides (opt-in). doc-drift stays ON -- do NOT list it. }
  Result:= FinalizeAndOutput(
    AArgs, Findings, [
      'function-result-ignored', 'unsafe-typecast-without-is', 'exhaustive-enum-case', 'multiple-statements-per-line', 'magic-literal', 'boolean-flag-parameter',
      'public-writable-field', 'loop-control-flag', 'mutable-global-variable', 'repeated-type-switch', 'middle-man', 'default-encoding-io', 'fan-out', 'fan-in', 'feature-envy',
      'instability', 'interface-object-mixing', 'split-variable', 'separate-query-from-modifier', 'missing-doc'],
    procedure(ASurv: TArray<TLintFinding>) var FF: TLintFinding; EC, WC: Integer; OL: TStringBuilder; begin EC:= 0; WC:= 0; for FF in ASurv do if SameText(FF.Severity,
        'error') then Inc(EC) else Inc(WC); OL:= TStringBuilder.Create; try for FF in ASurv do OL.AppendLine(Format('%s:%d:%d  [%s] %s: %s', [FF.FilePath, FF.StartLine,
              FF.StartCol, FF.Severity, FF.RuleId, FF.Message])); OL.AppendLine(Format('lint-all: %d finding(s) -- %d error(s), %d warning(s) -- %d file(s) scanned', [Length(ASurv), EC, WC, Length(FilePaths)])); TFile.WriteAllText(OutPath, OL.ToString, TEncoding.UTF8); finally OL.Free; end; for FF in ASurv do Writeln(Format('%s:%d:%d  [%s] %s: %s', [FF.FilePath, FF.StartLine, FF.StartCol, FF.Severity, FF.RuleId, FF.Message])); Writeln(Format('lint-all: %d finding(s) -- %d error(s), %d warning(s) -- %d file(s) -- report: %s', [Length(ASurv), EC, WC, Length(FilePaths), OutPath])); end,
    Store { ADF Task 8: enables the store-backed doc-drift --fix path }
  );
end; // function

// v0.48: drag-lint lint-project --db <index.sqlite> [--rule <id>] [--json]
// Index-wide ("project") lint rules (god-class, unused-public-symbol) that need
// the whole symbol/refs graph. Exit 1 if any findings, 0 if none, 2 on usage error.
function DoLintProject(const AArgs: TArgs): Integer;
var
  Store      : ISymbolStore         ;
  Findings   : TArray<TLintFinding> ;
  DefDisabled: TArray<string>       ;
begin
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s (pass --db <index.sqlite>)', [AArgs.DbPath])); Exit(2); end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  { v0.80 review fix: repeated-type-switch is OFF by default (medium name-based FP --
    see .superpowers/sdd/v080-task-4-report.md). Route through FinalizeAndOutput below
    so the DefDisabled + ShouldKeep filter actually applies to lint-project output
    (previously this command wrote Findings straight to stdout, unfiltered). }
  DefDisabled:= nil;
  if AArgs.Rule <> 'repeated-type-switch' then DefDisabled:= DefDisabled + ['repeated-type-switch'];
  { ADF Task 13 fix: missing-doc ships OFF by default (catalog default_enabled=false)
    but is a PROJECT-level rule (TDocLintRules), not in Linter.DefaultDisabledRuleIds,
    so without this it fires on every bare lint-project. Add it to the default-disabled
    set here too; the --rule guard keeps explicit --rule missing-doc opt-in-able, and
    config "enabled":["missing-doc"] still overrides via ShouldKeep. doc-drift stays ON. }
  if AArgs.Rule <> 'missing-doc' then DefDisabled:= DefDisabled + ['missing-doc'];
  Findings:= DRagLint.Lint.ProjectRules.TProjectLintRules.Run(Store, AArgs.Rule);
  { v0.51: interface reference cycles -- needs the AST of all project files (parsed here) }
  if (AArgs.Rule = '') or (AArgs.Rule = 'interface-reference-cycle') then
  begin
    var Paths: TArray<string>:= nil;
    var Fid2 : Int64               ;
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
  { used-unit-not-resolvable -- flags used units resolving to no known unit }
  if (AArgs.Rule = '') or (AArgs.Rule = 'used-unit-not-resolvable') then
  begin
    var LibDbPath2: string := '';
    for var DbI := 0 to High(AArgs.DbPaths) do
      if ContainsText(ExtractFileName(AArgs.DbPaths[DbI]), 'library-') then
      begin LibDbPath2 := AArgs.DbPaths[DbI]; Break; end;
    if (LibDbPath2 = '') and (Length(AArgs.DbPaths) > 1) then LibDbPath2 := AArgs.DbPaths[High(AArgs.DbPaths)];
    Findings := Findings + DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable(Store, LibDbPath2);
  end;
  { ADF Task 7: missing-doc -- store-backed (symbol_docs join); ON by default. }
  if (AArgs.Rule = '') or (AArgs.Rule = 'missing-doc') then
    Findings:= Findings + DRagLint.Lint.DocRules.TDocLintRules.RunMissingDoc(Store);
  { ADF Task 8: doc-drift -- store-backed; ON by default. --fix subset applied in
    FinalizeAndOutput (Store passed below). }
  if (AArgs.Rule = '') or (AArgs.Rule = 'doc-drift') then
    Findings:= Findings + DRagLint.Lint.DocRules.TDocLintRules.RunDocDrift(Store);
  Result:= FinalizeAndOutput(
    AArgs, Findings, DefDisabled,
    procedure(ASurv: TArray<TLintFinding>) var FF: TLintFinding; begin for FF in ASurv do Writeln(Format('%s:%d:%d  [%s] %s: %s', [FF.FilePath, FF.StartLine, FF.StartCol,
            FF.Severity, FF.RuleId, FF.Message])); Writeln(Format('%d finding(s)', [Length(ASurv)])); end,
    Store { ADF Task 8: enables the store-backed doc-drift --fix path }
  );
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
  { v0.69 D2a: --kind symbol|param path (dry-run default, --apply writes, --json edit set).
    Collision notes: --kind parsed into AArgs.Kind; --file parsed into AArgs.InFile.
    Legacy --qname path below is unchanged. }
  if AArgs.Kind <> '' then
  begin
    if SameText(AArgs.Kind, 'param') then
    begin
      if (AArgs.InFile = '') or (AArgs.RefLine <= 0) or (AArgs.RefCol <= 0) or (AArgs.RenameTo = '') then
      begin
        Writeln('ERROR: rename --kind param needs --file --line --col --to');
        Exit   (2                                                          );
      end;
      if TRenameRefactoring.IsReservedWord(AArgs.RenameTo) then begin Writeln(Format('ERROR: "%s" is a reserved word', [AArgs.RenameTo])); Exit(2); end;
      Edits:= TRenameRefactoring.BuildLocal( AArgs.InFile, AArgs.RefLine, AArgs.RefCol, AArgs.RenameTo);
    end
    else if SameText(AArgs.Kind, 'symbol') then
    begin
      var QN: string:= AArgs.QName;
      if QN = '' then QN:= AArgs.Name;
      if QN = '' then begin Writeln('ERROR: rename --kind symbol needs --name <QualifiedName> --to <New>'); Exit (2 ); end;
      if AArgs.RenameTo = '' then
      begin Writeln('ERROR: --to required'); Exit(2); end;
      if AArgs.DbPath = '' then
      begin Writeln('ERROR: --db required for --kind symbol'); Exit(2); end;
      var KStore: ISymbolStore:= TSQLiteSymbolStore.Create(AArgs.DbPath);
      KStore.Migrate;
      var Reason: string:= TRenameRefactoring.ConflictReason(KStore, QN, AArgs.RenameTo);
      if Reason <> '' then
      begin Writeln('ERROR: cannot rename -- ' + Reason); Exit(2); end;
      Edits:= TRenameRefactoring.Build(KStore, QN, AArgs.RenameTo);
    end // if
    else begin Writeln('ERROR: --kind must be symbol or param'); Exit (2 ); end;

    if Length(Edits) = 0 then
    begin Writeln('No edits computed.'); Exit(1); end;

    if AArgs.AsJson then
    begin
      var Arr: TJSONArray:= TJSONArray.Create;
      try
        for var Ed in Edits do
        begin
          var O: TJSONObject:= TJSONObject.Create;
          O.AddPair('file', Ed.FilePath);
          O.AddPair('line', TJSONNumber.Create(Ed.Line));
          O.AddPair('col' , TJSONNumber.Create(Ed.Col ));
          O.AddPair('old', Ed.OldName);
          O.AddPair('new', Ed.NewName);
          Arr.AddElement(O);
        end;
        Writeln(Arr.ToJson);
      finally
        Arr.Free;
      end;
      Exit(0);
    end; // if

    if not AArgs.Apply then begin Writeln(TRenameRefactoring.RenderDryRun(Edits)); Writeln(Format('Dry run: %d edit(s). Pass --apply to write.', [Length(Edits)])); Exit(0); end;

    var Touched: Integer:= TRenameRefactoring.Apply(Edits, not AArgs.NoBackup);
    Writeln(Format('Applied: %d edit(s), %d file(s).', [Length(Edits), Touched]));
    Exit(0);
  end; // if
  { ----- legacy --qname path below (unchanged) ----- }

  if (AArgs.QName = '') or (AArgs.RenameTo = '') then
  begin
    Writeln('Usage: drag-lint rename --qname Foo.TBar.Baz --to NewName ' + '[--db PATH] [--dry-run] [--no-backup]');
    Exit(2);
  end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(1); end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Edits:= TRenameRefactoring.Build(Store, AArgs.QName, AArgs.RenameTo);
  if Length(Edits) = 0 then begin Writeln(Format('No edits computed for %s (symbol may not exist)', [AArgs.QName])); Exit(1); end;

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
var
  BaseDir: string;
begin
  { The caller derives ABaseDir via ExtractFilePath(ProjectPath). Delphi's
    ExtractFilePath treats ONLY '\' (and ':') as separators, NOT '/', so a
    forward-slash project path (e.g. a CLI arg 'C:/proj/App.dproj') yields a
    truncated base like 'C:/' -- and bare project-file findings (the RAD msbuild
    wrapper emits 'uMain.pas' with no directory) then absolutize against the
    wrong base (the process CWD), so FindFileIdByPath misses them and every
    project-file hint is silently dropped. Normalize separators to '\' up front
    so absolutization works regardless of how the project path was spelled. }
  BaseDir:= StringReplace(ABaseDir, '/', '\', [rfReplaceAll]);
  Seen:= TDictionary<string, Boolean>.Create;
  Acc:= TList<TCompilerFinding>.Create;
  try
    for F in AFindings do
    begin
      Rec:= F; { F is the for-in loop var (read-only) -- mutate a copy }
      P:= StringReplace(Rec.RawPath, '/', '\', [rfReplaceAll]);
      if (P <> '') and (BaseDir <> '') and (not TPath.IsPathRooted(P)) then
      try P:= TPath.GetFullPath(TPath.Combine(BaseDir, P)); except end;
      Rec.RawPath:= P;
      { msbuild appends " [<full>\<project>.dproj]" to every message -- strip ONLY
        that trailing project-file reference, not a legitimate bracketed tail such
        as "[WEAKPACKAGEUNIT]" (over-stripping would also corrupt the dedup key). }
      Rec.Message:= TRegEx.Replace(Rec.Message, '\s*\[[^\]]*\.(?:dproj|dpk|dpr|proj)\]\s*$', '', [roIgnoreCase]);
      Key:= LowerCase(P) + '|' + IntToStr(Rec.LineNo) + '|' + Rec.Code + '|' + Rec.Message;
      if not Seen.ContainsKey(Key) then begin Seen.Add(Key, True); Acc.Add(Rec); end;
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
  if Target = '' then begin Writeln('Usage: drag-lint compile-check <target.dproj or target.pas> ' + '[--db PATH] [--format json|text]'); Exit(2); end;

  Writeln('Compiling: ', Target);
  Res:= TCompileChecker.Run(Target);
  { v0.47: absolutize relative paths + drop msbuild's duplicate lines.
    Normalize '/' -> '\' first so ExtractFilePath yields the real project dir for
    a forward-slash target (else bare project findings absolutize to CWD). }
  Res.Findings:= NormalizeFindings(Res.Findings,
    ExtractFilePath(StringReplace(Target, '/', '\', [rfReplaceAll])));

  ErrCount:= 0; WarnCount:= 0; HintCount:= 0;
  for F in Res.Findings do
  begin
    if SameText(F.Severity, 'Error') then Inc(ErrCount)
    else if SameText(F.Severity, 'Warning') then Inc(WarnCount)
    else if SameText(F.Severity, 'Hint') then Inc(HintCount);
  end;

  if TFile.Exists(AArgs.DbPath) then begin Store:= TSQLiteSymbolStore.Create(AArgs.DbPath); Store.Migrate; TCompileChecker.InsertFindings(Store, Res.Findings); end;

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

/// <summary>Compile-and-capture core shared by refresh-findings and
/// reconcile-project's index/findings coherence phase -- steps 5-9 of the
/// refresh-findings algorithm. Recompiles AProjectPath (full or incremental),
/// normalizes the findings, resolves the covered file_id set (AFullBuild -> all
/// indexed .pas/.dpr/.dpk; incremental -> AStale plus every finding's resolved
/// file), then per covered file clears+reinserts its compiler_findings and --
/// only when the compile did not fail with an Error -- stamps last_compiled_unix
/// = now. Operates on the ALREADY-OPEN AStore (no second connection is opened on
/// the same DB file). AJson selects the JSON vs text summary shape.
/// AEmitSummary=False silences ALL stdout (the 'Compiling:' line and the
/// summary) so a caller that owns its own output stream -- e.g.
/// reconcile-project's single-JSON-object report -- is never corrupted.</summary>
/// <param name="AStore">Open, migrated symbol store to read and update.</param>
/// <param name="AProjectPath">.dproj/.dpr/.dpk target to compile.</param>
/// <param name="AFullBuild">True forces a full rebuild covering every indexed unit.</param>
/// <param name="AStale">Incremental-mode stale file ids; ignored when AFullBuild.</param>
/// <param name="AJson">True emits the machine JSON summary; False the text summary.</param>
/// <param name="AEmitSummary">False suppresses all stdout for a caller-owned stream.</param>
/// <returns>1 iff an Error-severity finding survived, else 0.</returns>
function RefreshProjectFindingsCore(const AStore: ISymbolStore;
  const AProjectPath: string; AFullBuild: Boolean; const AStale: TArray<Int64>;
  AJson: Boolean; AEmitSummary: Boolean; const ATargetPlatform: string = ''): Integer;
var
  Res          : TCompileCheckResult;
  Covered      : TDictionary<Int64, Boolean>;
  AllFileIds   : TArray<Int64>      ;
  FileId       : Int64              ;
  FilePath     : string             ;
  Ext          : string             ;
  F            : TCompilerFinding   ;
  Rec          : TCompilerFinding   ;
  HasErrorFind : Boolean            ;
  CompileFailed: Boolean            ;
  NowUnix      : Int64              ;
  FindingsByFid: TDictionary<Int64, TList<TCompilerFinding>>;
  FidList      : TList<TCompilerFinding>;
  StampedCount : Integer            ;
  FindingCount : Integer            ;
  ModeStr      : string             ;
  Pair         : TPair<Int64, TList<TCompilerFinding>>;
begin
  // Step 5: compile + normalize (absolutize paths, drop msbuild dupes).
  // ExtractFilePath treats only '\' as a separator, so normalize '/' first --
  // a forward-slash --project would otherwise yield a truncated base dir ('C:/'),
  // dropping every bare-filename project finding (see NormalizeFindings).
  if AEmitSummary then
    Writeln('Compiling: ', AProjectPath, IfThen(AFullBuild, ' (full build)', ' (incremental)'));
  Res:= TCompileChecker.Run(AProjectPath, AFullBuild, '', '', ATargetPlatform);
  Res.Findings:= NormalizeFindings(Res.Findings,
    ExtractFilePath(StringReplace(AProjectPath, '/', '\', [rfReplaceAll])));

  // Step 6: determine the covered file_id set.
  Covered:= TDictionary<Int64, Boolean>.Create;
  try
    if AFullBuild then
    begin
      AllFileIds:= AStore.GetAllFileIds;
      for FileId in AllFileIds do
      begin
        FilePath:= AStore.GetFilePath(FileId);
        Ext:= LowerCase(ExtractFileExt(FilePath));
        if (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') then
          Covered.AddOrSetValue(FileId, True);
      end;
    end
    else
    begin
      for FileId in AStale do Covered.AddOrSetValue(FileId, True);
      for F in Res.Findings do
      begin
        FileId:= AStore.FindFileIdByPath(F.RawPath);
        if FileId > 0 then Covered.AddOrSetValue(FileId, True);
      end;
    end;

    // Step 7: compile-failure gate -- detect whether an Error/Fatal finding
    // survived. (NormalizeFindings/ParseLine already canonicalize severity to
    // 'Error' for both raw 'error' and 'fatal' lines -- see
    // TCompileChecker.NormalizeSeverity.)
    HasErrorFind:= False;
    for F in Res.Findings do
      if SameText(F.Severity, 'Error') then begin HasErrorFind:= True; Break; end;
    CompileFailed:= (Res.ExitCode <> 0) and HasErrorFind;

    // Step 8: per covered file, clear + insert + (on success) stamp.
    // Bucket findings by resolved file_id first (one pass) instead of
    // rescanning Res.Findings once per covered file.
    FindingsByFid:= TDictionary<Int64, TList<TCompilerFinding>>.Create;
    try
      for F in Res.Findings do
      begin
        FileId:= AStore.FindFileIdByPath(F.RawPath);
        if FileId <= 0 then Continue; // not indexed; nothing to bucket it under
        if not FindingsByFid.TryGetValue(FileId, FidList) then
        begin
          FidList:= TList<TCompilerFinding>.Create;
          FindingsByFid.Add(FileId, FidList);
        end;
        Rec:= F;
        Rec.FileId:= FileId;
        FidList.Add(Rec);
      end;

      NowUnix:= DateTimeToUnix(Now, False);
      StampedCount:= 0;
      FindingCount:= 0;
      for FileId in Covered.Keys do
      begin
        AStore.ClearCompilerFindingsForFile(FileId);
        if FindingsByFid.TryGetValue(FileId, FidList) then
          for Rec in FidList do
          begin
            AStore.InsertCompilerFinding(Rec);
            Inc(FindingCount);
          end;
        if not CompileFailed then
        begin
          AStore.SetFileCompiledAt(FileId, NowUnix);
          Inc(StampedCount);
        end;
      end;
    finally
      for Pair in FindingsByFid do Pair.Value.Free;
      FindingsByFid.Free;
    end; // try
  finally
    Covered.Free;
  end; // try

  // Step 9: summary (suppressed when the caller owns the output stream).
  if AEmitSummary then
  begin
    if AFullBuild then ModeStr:= 'full' else ModeStr:= 'incremental';
    if AJson then
      Writeln(Format('{"mode":"%s","compiled":%d,"stale":%d,"stamped":%d,"findings":%d,"exitCode":%d}',
        [ModeStr, IfThen(CompileFailed, 0, 1), Length(AStale), StampedCount, FindingCount, Res.ExitCode]))
    else
    begin
      Writeln(Format('refresh-findings: mode=%s stale=%d stamped=%d findings=%d exitCode=%d',
        [ModeStr, Length(AStale), StampedCount, FindingCount, Res.ExitCode]));
      if CompileFailed then Writeln('Compile FAILED -- files left stale for retry.');
    end;
  end;

  if HasErrorFind then Result:= 1 else Result:= 0;
end; // function

// fresh compiler findings: drag-lint refresh-findings --project <X.dproj|.dpr>
// --db <db> [--platform win32|win64] [--full] [--json]
//
// Recompiles only what is STALE (files.mtime_unix newer than
// files.last_compiled_unix) and refreshes compiler_findings for exactly the
// files the compile actually covered, so compiler_findings never drifts stale
// after an edit and never requires a whole-project rescan on every call.
//
// Algorithm (see docs/superpowers/plans/2026-07-14-fresh-compiler-findings.md
// Task 4 brief for the full spec this mirrors 1:1):
//   1. Require --project + a readable --db.
//   2. Open the store, Migrate.
//   3. Stale := GetStaleFileIds. Nothing stale and no --full -> noop, exit 0.
//   4. FullBuild := --full or (>= 2 files stale) -- a full build is not much
//      slower than 2 incremental single-unit compiles and is authoritative.
//   5. Compile (incremental Make, or full Build when FullBuild).
//   6. Covered set: FullBuild -> every indexed .pas/.dpr/.dpk file id;
//      incremental -> the one stale file id + every finding's resolved file id.
//   7. If the compile failed with an Error/Fatal finding, still store the
//      findings (so the error is visible) but do NOT stamp last_compiled_unix
//      for the covered files -- leave them stale so the next call retries.
//   8. Per covered file: clear its old findings, insert the fresh ones, and
//      (only on the non-failure path) stamp last_compiled_unix = now.
//   9. Print/emit a summary; exit 1 iff an Error-severity finding survived.
function DoRefreshFindings(const AArgs: TArgs): Integer;
var
  Store    : ISymbolStore ;
  Stale    : TArray<Int64>;
  FullBuild: Boolean      ;
  IsJson   : Boolean      ;
begin
  if (AArgs.ProjectPath = '') or (AArgs.DbPath = '') then
  begin
    Writeln('Usage: drag-lint refresh-findings --project <X.dproj|.dpr> --db <db> ' +
      '[--platform win32|win64] [--full] [--json]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  // Step 3: nothing stale and no forced --full -> noop.
  Stale:= Store.GetStaleFileIds;
  IsJson:= (LowerCase(AArgs.Format) = 'json') or AArgs.AsJson;
  if (Length(Stale) = 0) and (not AArgs.Full) then
  begin
    if IsJson then
      Writeln('{"mode":"noop","compiled":0,"stale":0,"stamped":0,"findings":0}')
    else
      Writeln('0 stale, up to date');
    Exit(0);
  end;

  // Step 4: >= 2 stale files makes a full build cheaper than N incremental
  // single-unit recompiles, and guarantees every affected unit's hints are
  // re-emitted (DCC skips hints for units it considers already up to date).
  FullBuild:= AArgs.Full or (Length(Stale) >= 2);

  // Steps 5-9: shared compile-and-capture core (also driven by the
  // reconcile-project index/findings coherence phase). Emits the summary here.
  Result:= RefreshProjectFindingsCore(Store, AArgs.ProjectPath, FullBuild, Stale, IsJson, True, AArgs.CheckPlatform);
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
      if (not TFile.Exists(E.RealPath)) or (not TFile.Exists(E.BufPath)) then begin Writeln('ghost-check: skip (missing): ', E.RealPath); Entries.Delete(i); Continue; end;
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
      Res.Findings:= NormalizeFindings(Res.Findings,
        ExtractFilePath(StringReplace(Dproj, '/', '\', [rfReplaceAll])));
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
  if not TDirectory.Exists(DragDir) then begin Writeln('ghost-recover: nothing pending.'); Exit (0 ); end;
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
      if Score > BestScore then begin BestScore:= Score; Result.Found := True; Result.UnitName:= UnitName; Result.Usable := Usable; end;
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
  if HasStore then begin Store:= TSQLiteSymbolStore.Create(AArgs.DbPath); Store.Migrate; end;

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
          if Sug.Found and Sug.Usable then begin AddUnit:= Sug.UnitName; Note:= Format(' -- add unit %s to the uses clause', [Sug.UnitName]); end;
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
  Fid  : Int64           ;
  UFrom: string          ;
  UTo  : string          ;
  Key  : string          ;
  K    : string          ;
  L    : TList<string>   ;
begin
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
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
    for Fid in Store.GetAllFileIds do
    begin
      FilePath:= Store.GetFilePath(Fid);
      if not SameText(ExtractFileExt(FilePath), '.pas') then Continue;
      UFrom:= UnitNameOfFile(FilePath);
      if UFrom = '' then Continue;
      UnitFile.AddOrSetValue(UFrom, FilePath);
      UnitFid .AddOrSetValue(UFrom, Fid     );
      UU:= Store.GetUnitUsesForFile(Fid);
      if not Adj.TryGetValue(UFrom, L) then begin L:= TList<string>.Create; Adj.AddOrSetValue(UFrom, L); end;
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
          { Implementation-only cycle: legal in Delphi and low-impact (no
            interface-recompile blast radius), so it is OPTIONAL to fix -- but
            still emit the how, in case the user wants a clean acyclic graph.
            The interface-edge analysis below doesn't apply (there are none), so
            report the implementation-section edges from Adj instead. }
          Writeln('Status: **implementation-only** (legal in Delphi, low ' +
            'impact -- no interface-recompile blast radius). Optional to fix; ' +
            'the steps below are for when you want a fully acyclic uses-graph.');
          Writeln('');
          Writeln('Files:');
          for var A in Comp do begin var P: string:= ''; UnitFile.TryGetValue(A, P); Writeln(Format('- `%s` -> `%s`', [A, P])); end;
          Writeln('');
          Writeln('### Why it cycles (implementation-section edges)');
          for var A in Comp do
          begin
            var NbrL: TList<string>;
            if not Adj.TryGetValue(A, NbrL) then Continue;
            for var B in Comp do
              if (A <> B) and NbrL.Contains(B) then
              begin
                var PA: string:= ''; UnitFile.TryGetValue(A, PA);
                Writeln(Format('- `%s` uses `%s` in its **implementation** ' +
                  'section (`%s`) via:', [A, B, ExtractFileName(PA)]));

                { Pinpoint exactly WHICH symbols A's implementation uses from B --
                  the concrete things to move/extract/inline to cut this edge.
                  Same resolution as the interface --causes path, but filtered to
                  refs AT OR AFTER the `implementation` line. Best-effort: the
                  index can miss refs (e.g. set types). }
                var Afid: Int64;
                if UnitFid.TryGetValue(A, Afid) then
                begin
                  var ImplL: Integer:= 0;   { 0 = show all refs if we can't find the keyword }
                  if TFile.Exists(PA) then
                  begin
                    var LS:= TStringList.Create;
                    try
                      LS.LoadFromFile(PA);
                      for var kk:= 0 to LS.Count - 1 do
                        if SameText(Trim(LS[kk]), 'implementation') then
                        begin ImplL:= kk + 1; Break; end;
                    finally LS.Free; end;
                  end;
                  var Seen:= TDictionary<string, Boolean>.Create;
                  var AnyHit:= False;
                  try
                    for var R in Store.GetReferencesFromFile(Afid) do
                    begin
                      if R.StartLine < ImplL then Continue;   { implementation only }
                      if Seen.ContainsKey(LowerCase(R.NameText)) then Continue;
                      for var Sym in Store.FindSymbolsByExactName(R.NameText) do
                      begin
                        { A local var / parameter is routine-scoped -- it can NEVER
                          be a genuine cross-unit reference, so a name match here is
                          a false positive (both units just happen to have a local
                          `I`/`Sender`/etc.). Skip those kinds; only unit-level
                          declarations (routines, types, forms, fields, consts) are
                          real coupling to move/extract. }
                        if Sym.Kind in [skLocalVar, skParam] then Continue;
                        if SameText(UnitNameOfFile(Store.GetFilePath(Sym.FileId)), B) then
                        begin
                          Writeln(Format('    - line %d: `%s`  [%s]  -> declared in `%s`',
                            [R.StartLine, R.NameText, Sym.Kind.ToText, B]));
                          Seen.AddOrSetValue(LowerCase(R.NameText), True);
                          AnyHit:= True;
                          Break;
                        end;
                      end;
                    end; // for
                    if not AnyHit then
                      Writeln(Format('    - (no specific symbol resolved -- index ' +
                        'gap, e.g. a `set` type; open `%s` and scan its ' +
                        'implementation uses of `%s` by hand)', [ExtractFileName(PA), B]));
                  finally Seen.Free; end; // try
                end;
              end;
          end;
          Writeln('');
          Writeln('### Recommended fix (optional)');
          Writeln('An implementation-only cycle already compiles and does not ' +
            'trigger cascading recompiles, so fixing it is a code-hygiene ' +
            'choice, not a correctness one. To remove it:');
          Writeln('');
          Writeln('1. Pick the edge that is easiest to cut (the smaller / more ' +
            'incidental dependency -- compare the symbol lists under "Why it ' +
            'cycles" above; the edge with fewer / more incidental symbols is ' +
            'usually easier).');
          Writeln('2. Those symbols (listed above, with line + kind) are exactly ' +
            'what that unit uses from its cycle partner -- they are what to ' +
            'move, extract, or inline.');
          Writeln('3. Either **extract** the shared routine(s)/type(s) into a ' +
            'new leaf unit both can use (it must use NEITHER unit in the cycle), ' +
            'or **inline / relocate** the small piece so the `uses` line is no ' +
            'longer needed.');
          Writeln('4. Remove the now-unneeded unit from that implementation ' +
            'uses clause.');
          Writeln('5. Build.');
          Writeln(Format('6. **Verify:** `drag-lint cycles --db <db>` -- cycle ' +
            '%d should be gone.', [i + 1]));
          Writeln('');
          Continue;
        end;

        Writeln('Files:');
        for var A in Comp do begin var P: string:= ''; UnitFile.TryGetValue(A, P); Writeln(Format('- `%s` -> `%s`', [A, P])); end;
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
              var PA: string:= ''; var pb: string:= '';
              UnitFile.TryGetValue(A, PA); UnitFile.TryGetValue(B, pb);
              if (LayerOf(PA) = 'COMMON') and ((LayerOf(pb) = 'CLIENT') or (LayerOf(pb) = 'SERVER')) then
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
              var LS:= TStringList.Create;
              try
                LS.LoadFromFile(APath);
                for var z:= 0 to LS.Count - 1 do
                  if SameText(Trim(LS[z]), 'implementation') then
                  begin ImplL:= z + 1; Break; end;
              finally LS.Free; end;
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
                  var LS:= TStringList.Create;
                  try
                    LS.LoadFromFile(APath);
                    for var kk:= 0 to LS.Count - 1 do
                      if SameText(Trim(LS[kk]), 'implementation') then
                      begin ImplL:= kk + 1; Break; end;
                  finally LS.Free; end;
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
                        if not HdrShown then begin Writeln(Format('      * %s''s INTERFACE needs %s via:', [A, B])); HdrShown:= True; end;
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
      for Sm in Store.FindSymbolsByExactName(AName) do begin St:= UnitStemOf(Store.GetFilePath(Sm.FileId)); if (St <> '') and not Us.Contains(St) then Us.Add(St); end;
      Result:= Us.ToArray;
    finally
      Us.Free;
    end;
    NameCache.AddOrSetValue(AName, Result);
  end;

begin
  if AArgs.Target = '' then begin Writeln('Usage: drag-lint uses-audit <unit.pas> --db <sqlite> [--format json|text]'); Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
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
    for var Fid2 in Store.GetAllFileIds do begin U:= UnitStemOf(Store.GetFilePath(Fid2)); if U <> '' then IndexedUnits.AddOrSetValue(U, Fid2); end;

    ThisStem:= UnitStemOf(AArgs.Target);
    if not IndexedUnits.TryGetValue(ThisStem, FileId) then begin Writeln('Not indexed (re-run "drag-lint index"): ', AArgs.Target); Exit(2); end;

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
          if SameText(Trim(Lines[i]), 'implementation') then begin ImplLine:= i + 1; Break; end;
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
        if (not RefIntf.ContainsKey(uStem)) and (not RefImpl.ContainsKey(uStem)) then begin Verdict:= 'unused'; Inc(nUnused); end
        else if (Uo.Section = uusInterface) and (not RefIntf.ContainsKey(uStem)) then begin Verdict:= 'move-to-implementation'; Inc(nMove); end;
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
      for Sm in Store.FindSymbolsByExactName(AName) do begin St:= UnitStemOf(Store.GetFilePath(Sm.FileId)); if (St <> '') and not Us.Contains(St) then Us.Add(St); end;
      Result:= Us.ToArray;
    finally Us.Free; end;
    NameCache.AddOrSetValue(AName, Result);
  end;

  function HasInitSection(const AStem: string): Boolean;
  var
    Fid: Int64; Sym: TSymbol; Syms: TArray<TSymbol>;
  begin
    Result:= True;
    if not IndexedUnits.TryGetValue(AStem, Fid) then Exit;
    Syms:= Store.FindSymbolsByFile(Store.GetFilePath(Fid));
    if Length(Syms) = 0 then Exit;
    Result:= False;
    for Sym in Syms do
      if SameText(Sym.Kind.ToText, 'initialization') or SameText(Sym.Kind.ToText, 'finalization') then Exit(True);
  end;

var
  Fid        : Int64             ;
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
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
  RootFilter:= LowerCase(StringReplace(AArgs.InFile, '/', '\', [rfReplaceAll]));
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  IndexedUnits:= TDictionary<string, Int64>.Create;
  NameCache:= TDictionary<string, TArray<string>>.Create;
  RefIntf:= TDictionary<string, Boolean>.Create;
  RefImpl:= TDictionary<string, Boolean>.Create;
  Lines:= TStringList.Create;
  try
    for Fid in Store.GetAllFileIds do begin U:= UnitStemOf(Store.GetFilePath(Fid)); if U <> '' then IndexedUnits.AddOrSetValue(U, Fid); end;

    TotalMove:= 0; TotalUnused:= 0; UnitsWithChanges:= 0;
    Writeln('Project uses sweep (DRY-RUN, index proposal -- apply per-unit to verify):');
    Writeln(''                                                                         );

    for Fid in Store.GetAllFileIds do
    begin
      Path:= StringReplace(Store.GetFilePath(Fid), '/', '\', [rfReplaceAll]);
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
      Refs:= Store.GetReferencesFromFile(Fid);
      for R in Refs do
        for U in UnitsDefining(R.NameText) do
        begin
          if SameText(U, ThisStem) then Continue;
          if R.StartLine < ImplLine then RefIntf.AddOrSetValue(U, True)
          else RefImpl.AddOrSetValue(U, True);
        end;

      HeaderShown:= False;
      UU:= Store.GetUnitUsesForFile(Fid);
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

        if not HeaderShown then begin Writeln(Format('%s  (%s)', [ExtractFileName(Path), Path])); HeaderShown:= True; Inc(UnitsWithChanges); end;
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
      for Sm in Store.FindSymbolsByExactName(AName) do begin St:= UnitStemOf(Store.GetFilePath(Sm.FileId)); if (St <> '') and not Us.Contains(St) then Us.Add(St); end;
      Result:= Us.ToArray;
    finally Us.Free; end;
    NameCache.AddOrSetValue(AName, Result);
  end;

{ does unit U (by stem) have an initialization/finalization section? if we
    cannot tell, assume YES (never auto-remove a possible side-effect unit). }
  function HasInitSection(const AStem: string): Boolean;
  var
    Fid: Int64; Sym: TSymbol; Syms: TArray<TSymbol>;
  begin
    Result:= True;
    if not IndexedUnits.TryGetValue(AStem, Fid) then Exit;
    Syms:= Store.FindSymbolsByFile(Store.GetFilePath(Fid));
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
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
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
    for var Fid2 in Store.GetAllFileIds do begin U:= UnitStemOf(Store.GetFilePath(Fid2)); if U <> '' then IndexedUnits.AddOrSetValue(U, Fid2); end;
    ThisStem:= UnitStemOf(AArgs.Target);
    if not IndexedUnits.TryGetValue(ThisStem, FileId) then begin Writeln('Not indexed (re-run "drag-lint index"): ', AArgs.Target); Exit(2); end;
    { normalise separators: stored paths can be mixed ('C:/x\y.pas'), which
      breaks ExtractFileName -> wrong shadow filename -> the verify would compile
      the REAL file instead of the edit (a false pass). }
    SrcPath:= StringReplace(Store.GetFilePath(FileId), '/', '\', [rfReplaceAll]);
    if not TFile.Exists(SrcPath) then SrcPath:= AArgs.Target;
    if not TFile.Exists(SrcPath) then begin Writeln('Source file not found on disk: ', SrcPath); Exit(2); end;
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
        else begin Inc(nSkip); Writeln(Format('  skip   %s  (move did not verify / not a clean entry)', [Uo.UnitName])); end;
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
        else if TryEdit(Uo.UnitName, Uo.StartLine - 1, 'remove') then begin Inc(nRemove); Writeln(Format('  REMOVE %s  commented out (line %d)', [Uo.UnitName, Uo.StartLine])); end
        else begin Inc(nSkip); Writeln(Format('  skip   %s  (remove did not verify / not a clean entry)', [Uo.UnitName])); end;
      end; // if
    end; // for

    if (nMove + nRemove) = 0 then begin Writeln('  Nothing to change.'); Exit (0 ); end;

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
    else begin PrintDiff; Writeln(Format('-- DRY-RUN: %d move(s), %d remove(s) (best-effort verify -- ' + 'a full project build is required to confirm).', [nMove, nRemove])); end;
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
  if AArgs.QName = '' then begin Writeln('Usage: drag-lint generate-test --qname X [--framework dunitx|dunit] [--db PATH]'); Exit (2 ); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  if SameText(AArgs.TestFramework, 'dunit') then Framework:= tfDUnit
  else Framework:= tfDUnitX;
  Stub:= TTestStubGenerator.Generate(Store, AArgs.QName, Framework);
  if Stub = '' then begin Writeln(Format('No stub generated for %s', [AArgs.QName])); Exit(1); end;
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
begin
  if AArgs.Target = '' then begin Writeln('Usage: drag-lint check-ast <file> [--db PATH] [--format text|json]'); Exit (2 ); end;
  if not TFile.Exists(AArgs.Target) then begin Writeln('ERROR: file not found: ', AArgs.Target); Exit(2); end;
  if TFile.Exists(AArgs.DbPath) then begin Store:= TSQLiteSymbolStore.Create(AArgs.DbPath); Store.Migrate; end
  else Store:= nil;
  Findings:= TAstChecker.Check(Store, AArgs.Target);
  { v11 (M1): type-aware rules with exact resolution when a store is present
    (store-bearing path per the M1 plan); heuristic fallback when --db is absent. }
  var TcFid: Int64:= 0;
  if Store <> nil then TcFid:= Store.FindFileIdByPath(AArgs.Target);
  Findings:= Findings + TAstChecker.CheckTypeAware           (AArgs.Target, Store, TcFid);
  Findings:= Findings + TAstChecker.CheckVirtualInConstructor(AArgs.Target, Store, TcFid); { v12 (M1) }
  Findings:= Findings + DRagLint.Diagnostics.FlowChecks.TFlowChecker.Check(AArgs.Target, Store, TcFid); { M2: flow checks }
  DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear;

  Result:= FinalizeAndOutput(
    AArgs, Findings, nil,
    procedure(ASurv: TArray<TLintFinding>) var FF: TLintFinding; begin for FF in ASurv do Writeln(Format('%s(%d,%d): %s %s: %s', [AArgs.Target, FF.StartLine, FF.StartCol,
            FF.Severity, FF.RuleId, FF.Message])); Writeln(Format('AST findings: %d', [Length(ASurv)])); end
  );
end; // function

/// <summary>v0.82: drag-lint dump-refs &lt;file&gt; --db PATH -- diagnostic dump of
/// every indexed reference in &lt;file&gt;, one per line, as
/// name_text|start_line|enclosing_symbol_id|enclosing_symbol_name. The enclosing
/// name is resolved from enclosing_symbol_id (empty when 0/NULL). Used to verify
/// per-file enclosing-method attribution (refs.enclosing_symbol_id).</summary>
/// <param name="AArgs">Parsed CLI args; Target is the source file, DbPath the index.</param>
/// <returns>0 on success, 2 on usage error / missing file / file not indexed.</returns>
function DoDumpRefs(const AArgs: TArgs): Integer;
var
  Store : ISymbolStore      ;
  FileId: Int64             ;
  Refs  : TArray<TReference>;
  R     : TReference        ;
  EnclNm: string            ;
begin
  if AArgs.Target = '' then begin Writeln('Usage: drag-lint dump-refs <file> --db PATH'); Exit (2 ); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(1);
  FileId:= Store.FindFileIdByPath(TPath.GetFullPath(AArgs.Target));
  if FileId <= 0 then FileId:= Store.FindFileIdByPath(AArgs.Target);
  if FileId <= 0 then begin Writeln(Format('File not indexed: %s', [AArgs.Target])); Exit(2); end;
  Refs:= Store.GetReferencesFromFile(FileId);
  for R in Refs do
  begin
    if R.EnclosingSymbolId > 0 then EnclNm:= Store.GetSymbolById(R.EnclosingSymbolId).Name
    else EnclNm:= '';
    Writeln(Format('%s|%d|%d|%s', [R.NameText, R.StartLine, R.EnclosingSymbolId, EnclNm]));
  end;
  Result:= 0;
end; // function

// Maps a TDocDriftKind to its exact camelCase identifier for the --json output.
function DocDriftKindStr(AKind: TDocDriftKind): string;
begin
  case AKind of
    ddParamRenamedOrRemoved: Result:= 'ddParamRenamedOrRemoved';
    ddParamMissing         : Result:= 'ddParamMissing';
    ddParamVolatileMode    : Result:= 'ddParamVolatileMode';
    ddReturnsButNoValue    : Result:= 'ddReturnsButNoValue';
    ddValueButNoReturns    : Result:= 'ddValueButNoReturns';
    ddReturnTypeChanged    : Result:= 'ddReturnTypeChanged';
    ddExceptionNotRaised   : Result:= 'ddExceptionNotRaised';
    ddIdentifierGone       : Result:= 'ddIdentifierGone';
    ddFactsBlockStale      : Result:= 'ddFactsBlockStale';
    else Result:= 'unknown';
  end;
end;

/// <summary>ADF Task 6: drag-lint doc-drift --qname X --db PATH [--json] --
/// diagnostic dump of the TDocDrift engine's findings for ONE symbol. Resolves
/// the qname, scans its on-disk DocInsight comment live, runs the deterministic
/// doc-vs-code diff, and prints one line per finding. With --json each line is a
/// compact object {kind, detail, fixable, line}; without --json it is a readable
/// 'kind[FIXABLE] detail (line N)' line. The verb exists to exercise the engine
/// through the exe (tests/autodoc/run_doc_drift_engine.ps1); the missing-doc /
/// doc-drift LINT rules + --fix are separate tasks that consume the same engine.</summary>
/// <param name="AArgs">Parsed CLI args; QName is the symbol, DbPath the index,
/// AsJson selects the JSON-per-line format.</param>
/// <returns>0 on success (findings printed, or none), 1 when the symbol is not
/// found / has no doc-comment, 2 on usage error / missing db.</returns>
function DoDocDrift(const AArgs: TArgs): Integer;
var
  Store   : ISymbolStore              ;
  RoOk    : Boolean                   ;
  Sym     : TSymbol                   ;
  Doc     : TParsedDoc                ;
  Found   : Boolean                   ;
  HasDoc  : Boolean                   ;
  Findings: TArray<TDocDriftFinding>  ;
  F       : TDocDriftFinding          ;
  O       : TJSONObject               ;
begin
  if AArgs.QName = '' then begin Writeln('Usage: drag-lint doc-drift --qname X --db PATH [--json]'); Exit(2); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(1);

  Doc:= DRagLint.Doc.Document.TDocumenter.ExistingDocFor(Store, AArgs.QName, Sym, Found, HasDoc);
  if not Found then begin Writeln(Format('symbol not found: %s', [AArgs.QName])); Exit(1); end;
  if not HasDoc then begin Writeln(Format('no doc-comment on: %s', [AArgs.QName])); Exit(1); end;

  Findings:= TDocDrift.Analyze(Store, Sym, Doc);

  for F in Findings do
  begin
    if AArgs.AsJson then
    begin
      O:= TJSONObject.Create;
      try
        O.AddPair('kind'   , DocDriftKindStr(F.Kind));
        O.AddPair('detail' , F.Detail);
        O.AddPair('fixable', TJSONBool.Create(F.Fixable));
        O.AddPair('line'   , TJSONNumber.Create(F.Line));
        Writeln(O.ToJson);
      finally
        O.Free;
      end;
    end
    else
      Writeln(Format('%s%s %s (line %d)',
        [DocDriftKindStr(F.Kind), IfThen(F.Fixable, ' [FIXABLE]', ''), F.Detail, F.Line]));
  end;
  Result:= 0;
end; // function

/// <summary>PP-Task-2: drag-lint dump-pp-lex --file PATH -- diagnostic dump of
/// the directive lexer output. Reads the file at --file, runs LexDirectives, and
/// prints ONE LINE PER CHUNK as kind|dir|srcStart|srcEnd|line|value-escaped
/// (newline bytes in value rendered as a literal backslash-n so each chunk is one
/// line). Used by tests/preprocess/run_lexer.ps1 to verify the port of lexer.js.</summary>
/// <param name="AArgs">Parsed CLI args; InFile (--file) is the source to lex.</param>
/// <returns>0 on success, 2 on usage error / missing file.</returns>
function DoDumpPpLex(const AArgs: TArgs): Integer;
var
  Src   : string            ;
  Chunks: TArray<TPPChunk>  ;
  C     : TPPChunk          ;
  KindS : string            ;
  Esc   : string            ;
begin
  if AArgs.InFile = '' then begin Writeln('Usage: drag-lint dump-pp-lex --file PATH'); Exit(2); end;
  if not FileExists(AArgs.InFile) then begin Writeln(Format('File not found: %s', [AArgs.InFile])); Exit(2); end;
  Src:= TFile.ReadAllText(AArgs.InFile, TEncoding.UTF8);
  Chunks:= LexDirectives(Src);
  for C in Chunks do
  begin
    if C.Kind = ckDirective then KindS:= 'directive' else KindS:= 'text';
    // Escape both CR and LF so each chunk stays on one output line. The value
    // field for a directive is its Args; for text it is the raw slice text.
    Esc:= C.Value;
    if C.Kind = ckDirective then Esc:= C.Args;
    Esc:= StringReplace(Esc, #13, '\r', [rfReplaceAll]);
    Esc:= StringReplace(Esc, #10, '\n', [rfReplaceAll]);
    Writeln(Format('%s|%s|%d|%d|%d|%s', [KindS, C.Dir, C.SrcStart, C.SrcEnd, C.Line, Esc]));
  end;
  Result:= 0;
end; // function

/// <summary>PP-Task-3: drag-lint dump-pp-eval --expr "E" [--define SYM]... [--numeric K=V]...
/// -- diagnostic dump of the {$IF expr} evaluator. Builds a defines dictionary
/// (each --define lowercased -> True) and a numeric dictionary (each --numeric
/// K=V lowercased K -> integer V), calls EvalPPExpr, and prints the lowercase
/// literal 'true' or 'false'. Used by tests/preprocess/run_expr.ps1 to verify the
/// port of evalExpr.js.</summary>
/// <param name="AArgs">Parsed CLI args; PpExpr (--expr) is the expression,
/// PpDefines (--define) the symbols, PpNumeric (--numeric K=V) the numeric map.</param>
/// <returns>Always 0 (the boolean result is on stdout; a bad --numeric token is
/// skipped rather than treated as an error, matching the evaluator's conservatism).</returns>
function DoDumpPpEval(const AArgs: TArgs): Integer;
var
  Defines: TDictionary<string, Boolean>;
  Numeric: TDictionary<string, Integer>;
  D      : string ;
  N      : string ;
  EqPos  : Integer;
  Key    : string ;
  ValStr : string ;
  ValInt : Integer;
begin
  Defines:= TDictionary<string, Boolean>.Create;
  Numeric:= TDictionary<string, Integer>.Create;
  try
    for D in AArgs.PpDefines do
      if D <> '' then Defines.AddOrSetValue(D.ToLower, True);
    for N in AArgs.PpNumeric do
    begin
      // Each --numeric token is 'KEY=VALUE'; split on the first '='. A token
      // without '=' or with a non-integer value is skipped (best-effort).
      EqPos:= Pos('=', N);
      if EqPos <= 1 then Continue;
      Key   := Copy(N, 1, EqPos - 1);
      ValStr:= Copy(N, EqPos + 1, Length(N));
      if TryStrToInt(ValStr, ValInt) then Numeric.AddOrSetValue(Key.ToLower, ValInt);
    end;
    if EvalPPExpr(AArgs.PpExpr, Defines, Numeric) then Writeln('true') else Writeln('false');
  finally
    Numeric.Free;
    Defines.Free;
  end;
  Result:= 0;
end; // function

/// <summary>PP-Task-4/6: drag-lint preprocess-file --file PATH [--define SYM]...
/// [--numeric K=V]... [--include-mode off|defines-only] -- diagnostic dump of the
/// chunk processor. Reads --file as raw BYTES, builds a TDefineProfile from the
/// repeatable --define (lowercased) and --numeric (K=V) flags, and a TPPOptions
/// whose IncludeMode is --include-mode (default 'off') and whose BaseDir is the
/// directory of --file (so a {$I config.inc} resolves next to the source), runs
/// Preprocess, and writes the resulting BYTES to stdout VERBATIM via WriteFile on
/// the raw stdout handle -- no Writeln, so no CR injection, no encoding change, no
/// trailing newline. This keeps the output byte-for-byte comparable to the JS
/// oracle (offset-identity invariant). Used by tests/preprocess/*.ps1.</summary>
/// <param name="AArgs">Parsed CLI args; InFile (--file) is the source; PpDefines
/// (--define) the symbols; PpNumeric (--numeric K=V) the numeric map;
/// PpIncludeMode (--include-mode) the include strategy; PpTolerances
/// (--tolerances, v1.2.1 #5) opts into the dcc-tolerance ';' replacement pass
/// (offset-identity preserved -- replacement, never insertion).</param>
/// <returns>0 on success, 2 on usage error / missing file.</returns>
function DoPreprocessFile(const AArgs: TArgs): Integer;
var
  InBytes : TBytes           ;
  OutBytes: TBytes           ;
  Options : TPPOptions       ;
  D       : string           ;
  N       : string           ;
  EqPos   : Integer          ;
  ValInt  : Integer          ;
  Pairs   : TList<TPair<string, Integer>>;
  StdOut  : THandle          ;
  Written : DWORD            ;
begin
  if AArgs.InFile = '' then begin Writeln('Usage: drag-lint preprocess-file --file PATH [--define SYM]... [--numeric K=V]... [--include-mode off|defines-only] [--no-near-search] [--tolerances]'); Exit(2); end;
  if not FileExists(AArgs.InFile) then begin Writeln(Format('File not found: %s', [AArgs.InFile])); Exit(2); end;

  InBytes:= TFile.ReadAllBytes(AArgs.InFile);

  // Build the define profile: each --define lowercased into Defines; each
  // --numeric 'K=V' (integer V) into NumericDefines (K lowercased on use).
  for D in AArgs.PpDefines do
    if D <> '' then
    begin
      SetLength(Options.Profile.Defines, Length(Options.Profile.Defines) + 1);
      Options.Profile.Defines[High(Options.Profile.Defines)]:= LowerCase(D);
    end;
  Pairs:= TList<TPair<string, Integer>>.Create;
  try
    for N in AArgs.PpNumeric do
    begin
      EqPos:= Pos('=', N);
      if EqPos <= 1 then Continue;
      if TryStrToInt(Copy(N, EqPos + 1, Length(N)), ValInt) then
        Pairs.Add(TPair<string, Integer>.Create(LowerCase(Copy(N, 1, EqPos - 1)), ValInt));
    end;
    Options.Profile.NumericDefines:= Pairs.ToArray;
  finally
    Pairs.Free;
  end;

  // PP-Task-6: include handling. Default 'off' preserves Task-4/5 behavior; the
  // BaseDir is the source file's directory so a relative {$I} resolves beside it.
  if AArgs.PpIncludeMode <> '' then Options.IncludeMode:= AArgs.PpIncludeMode
  else Options.IncludeMode:= 'off';
  Options.BaseDir:= TPath.GetDirectoryName(TPath.GetFullPath(AArgs.InFile));
  // v1.2.1 port change #2: nearest-first include resolution is ON by default
  // (matching the JS oracle's options.nearSearch !== false); --no-near-search
  // restores strict BaseDir-only resolution.
  Options.NearSearch:= not AArgs.PpNoNearSearch;
  // v1.2.1 port change #5: the dcc-tolerance pass is OPT-IN (--tolerances),
  // matching the JS default. Explicit assignment -- Options is a local record,
  // so an unset Boolean would be stack garbage, not False.
  Options.Tolerances:= AArgs.PpTolerances;

  OutBytes:= Preprocess(InBytes, Options);

  // Write the resolved bytes VERBATIM to the raw stdout handle so no newline
  // translation / encoding change touches them (Writeln would corrupt the
  // byte-exact compare against the oracle).
  StdOut:= GetStdHandle(STD_OUTPUT_HANDLE);
  if Length(OutBytes) > 0 then
    WriteFile(StdOut, OutBytes[0], Length(OutBytes), Written, nil);
  Result:= 0;
end; // function

/// <summary>PP-Task-7: drag-lint pp-profile [--dproj PATH] [--platform Win32|Win64]
/// [--config Release|Debug] -- diagnostic dump of the define-profile resolver.
/// With --dproj it resolves ProfileFromDproj (platform built-ins UNION the .dproj
/// Base + selected-config DCC_Define symbols); without --dproj it dumps
/// PlatformBuiltins for the platform. Prints the resolved defines SORTED, one
/// lowercased symbol per line, so tests/preprocess/run_profile.ps1 can grep for
/// membership. --platform defaults to Win64, --config to Release.</summary>
/// <param name="AArgs">Parsed CLI args; PpDproj (--dproj) the project;
/// CheckPlatform (--platform) the target; WorkspaceConfig (--config) the
/// config.</param>
/// <returns>0 always (a missing .dproj degrades to built-ins, never an error).</returns>
function DoPpProfile(const AArgs: TArgs): Integer;
var
  Platform: string        ;
  Config  : string        ;
  Profile : TDefineProfile;
  Defines : TArray<string>;
  Sym     : string        ;
begin
  Platform:= AArgs.CheckPlatform;
  if Platform = '' then Platform:= 'Win64';
  Config:= AArgs.WorkspaceConfig;
  if Config = '' then Config:= 'Release';

  if AArgs.PpDproj <> '' then
    Profile:= ProfileFromDproj(AArgs.PpDproj, Platform, Config)
  else
  begin
    Profile.Defines:= PlatformBuiltins(Platform);
    Profile.NumericDefines:= nil;
  end;

  Defines:= Copy(Profile.Defines, 0, Length(Profile.Defines));
  TArray.Sort<string>(Defines);
  for Sym in Defines do
    Writeln(Sym);
  Result:= 0;
end; // function

/// <summary>v14 (D5): drag-lint dump-call-edges --db PATH -- diagnostic dump of
/// every resolved call edge in the index, one per line, as
/// ref_id|target_qname|confidence. target_qname is the resolved target symbol's
/// qualified name (empty when the symbol is missing). Used to verify the
/// ResolveCallTargets pass populates call_edges with the right resolutions.</summary>
/// <param name="AArgs">Parsed CLI args; DbPath is the index to dump.</param>
/// <returns>0 on success, 2 on usage error / missing db.</returns>
function DoDumpCallEdges(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore     ;
  Edges: TArray<TCallEdge>;
  E    : TCallEdge        ;
  QName: string           ;
begin
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(1);
  Edges:= Store.DumpAllCallEdges;
  for E in Edges do
  begin
    if E.TargetSymbolId > 0 then QName:= Store.GetSymbolById(E.TargetSymbolId).QualifiedName
    else QName:= '';
    Writeln(Format('%d|%s|%s', [E.RefId, QName, E.Confidence]));
  end;
  Result:= 0;
end; // function

/// <summary>v14 (D5 T9): drag-lint find-callees --qname X [--json] --db PATH --
/// the mirror of find-callers --resolved: every RESOLVED outgoing call made
/// from inside routine X's body (via call_edges), rendered as the target's
/// qualified name + confidence. X is resolved via FindSymbolsByQualifiedName;
/// an overloaded/duplicate qname is handled by unioning the callees of every
/// matching symbol. A routine with no resolved outgoing calls prints "0
/// callee(s)" (text) / an empty array (json) -- a valid, non-error answer.</summary>
/// <param name="AArgs">Parsed CLI args; QName is the calling routine, DbPath the index.</param>
/// <returns>0 when the store opened OK and --qname resolved to at least one symbol
/// (even with zero callees); 1 if --qname does not resolve to any symbol; 2 on
/// usage error / missing db.</returns>
function DoFindCallees(const AArgs: TArgs): Integer;
var
  Store  : ISymbolStore     ;
  Targets: TArray<TSymbol>  ;
  T      : TSymbol          ;
  Edges  : TArray<TCallEdge>;
  E      : TCallEdge        ;
  QName  : string           ;
  Total  : Integer          ;
begin
  if AArgs.QName = '' then begin Writeln('Usage: drag-lint find-callees --qname X [--json] --db PATH'); Exit (2 ); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(1);

  Targets:= Store.FindSymbolsByQualifiedName(AArgs.QName);
  if Length(Targets) = 0 then begin Writeln(Format('symbol not found: %s', [AArgs.QName])); Exit(1); end;

  Total:= 0;
  var JOut: TJSONArray:= nil;
  if AArgs.AsJson then JOut:= TJSONArray.Create;
  try
    for T in Targets do
    begin
      Edges:= Store.GetCallEdgesFromSymbol(T.Id);
      for E in Edges do
      begin
        if E.TargetSymbolId > 0 then QName:= Store.GetSymbolById(E.TargetSymbolId).QualifiedName
        else QName:= '';
        if AArgs.AsJson then
        begin
          var JObj:= TJSONObject.Create;
          JObj.AddPair('target_qname', QName        );
          JObj.AddPair('confidence'  , E.Confidence  );
          JOut.AddElement(JObj);
        end
        else Writeln(Format('  %s  [%s]', [QName, E.Confidence]));
        Inc(Total);
      end; // for E
    end; // for T
    if AArgs.AsJson then Writeln(JOut.Format(2))
    else if Total = 0 then Writeln('0 callee(s)');
  finally
    JOut.Free;
  end; // try
  Result:= 0;
end; // function

/// <summary>v14 (D5 T9): drag-lint ambiguous-calls [--qname X|--file F] [--json]
/// --db PATH -- the resolver-coverage diagnostic. Lists call sites that name a
/// known routine/method but that the resolver did NOT pin to a single certain
/// target (confidence='ambiguous' in call_edges, or no call_edges row at all --
/// untypable receiver). Optionally scoped to --qname (the enclosing routine's
/// qualified name) or --file (a source file); with neither, it lists every
/// ambiguous/unverified call site in the whole DB (the global coverage view --
/// can be large; scoping is recommended). An empty result is a VALID "fully
/// resolved" answer, not an error.</summary>
/// <param name="AArgs">Parsed CLI args; QName and/or InFile (--file/--in) scope
/// the query, DbPath is the index.</param>
/// <returns>0 whenever the store opened OK, regardless of result count (empty
/// is a valid answer); 2 on usage error / missing db.</returns>
function DoAmbiguousCalls(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore          ;
  Rows : TArray<TResolvedCaller>;
  R    : TResolvedCaller        ;
begin
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(1);

  Rows:= Store.GetAmbiguousCalls(AArgs.QName, AArgs.InFile);

  if AArgs.AsJson then
  begin
    var JOut:= TJSONArray.Create;
    try
      for R in Rows do
      begin
        var JObj:= TJSONObject.Create;
        JObj.AddPair('enclosing_qname', R.EnclosingQName);
        JObj.AddPair('file'           , R.Location       );
        JObj.AddPair('confidence'     , R.Confidence     );
        JOut.AddElement(JObj);
      end; // for R
      Writeln(JOut.Format(2));
    finally
      JOut.Free;
    end; // try
  end
  else
  begin
    for R in Rows do
      Writeln(Format('  %s  (%s)  [%s]', [R.EnclosingQName, R.Location, R.Confidence]));
    if Length(Rows) = 0 then Writeln('0 ambiguous call(s) -- fully resolved')
    else Writeln(Format('%d ambiguous call(s)', [Length(Rows)]));
  end; // if
  Result:= 0;
end; // function

/// <summary>v14 (D5 T11): resolve a --from/--to/--qname endpoint (a bare name
/// OR a fully-qualified name) to symbol ids, for the call-graph traversal
/// verbs. Tries exact-name first (FindSymbolsByExactName -- lets a test pass a
/// bare method name like 'StepA'), then falls back to qualified-name lookup
/// (FindSymbolsByQualifiedName -- 'unit.TClass.Method'). Returns every matching
/// symbol id (an overloaded/duplicated name yields several); empty array when
/// the name resolves to nothing.</summary>
/// <param name="AStore">The open store to resolve against.</param>
/// <param name="AName">The endpoint name (bare or qualified).</param>
/// <returns>All matching symbol ids (may be empty).</returns>
function ResolveEndpointIds(const AStore: ISymbolStore; const AName: string): TArray<Int64>;
var
  Syms: TArray<TSymbol>;
  S   : TSymbol        ;
  L   : TList<Int64>   ;
begin
  L:= TList<Int64>.Create;
  try
    Syms:= AStore.FindSymbolsByExactName(AName);
    if Length(Syms) = 0 then Syms:= AStore.FindSymbolsByQualifiedName(AName);
    for S in Syms do
      if not L.Contains(S.Id) then L.Add(S.Id);
    Result:= L.ToArray;
  finally
    L.Free;
  end; // try
end; // function

/// <summary>v14 (D5 T11): drag-lint call-path --from A --to B [--max-depth N]
/// [--json] --db PATH -- prints the SHORTEST resolved call path A -&gt; ... -&gt;
/// B over the resolved call_edges (does A eventually call B, and by what
/// route). A and B are resolved via ResolveEndpointIds (bare name or qname).
/// Traversal is a breadth-first search over the CALLEES direction
/// (GetCallEdgesFromSymbol -&gt; TargetSymbolId), starting from every id A
/// resolves to, stopping at the first id B resolves to. A VISITED set guards
/// cycles (a node is never revisited) and the search is additionally bounded by
/// --max-depth (default 20). BFS yields the shortest path; it is rebuilt from a
/// child-&gt;parent map. "No path within the cap" is a VALID answer (exit 1 +
/// "no path from A to B" / json found:false), NOT an error. Traverses within a
/// single DB -- ids are per-DB, so a path that would span indexes is out of
/// scope.</summary>
/// <param name="AArgs">Parsed CLI args; CallFrom is A, RenameTo (--to) is B,
/// MaxDepth the cap, DbPath the index.</param>
/// <returns>0 when a path was found and printed; 1 when both endpoints resolved
/// but no path exists within --max-depth; 2 on usage error / missing or
/// unreadable db (store-open failure) / an endpoint that resolves to no
/// symbol.</returns>
function DoCallPath(const AArgs: TArgs): Integer;
var
  Store   : ISymbolStore              ;
  FromIds : TArray<Int64>             ;
  ToIds   : TArray<Int64>             ;
  ToSet   : TDictionary<Int64,Boolean>;
  Visited : TDictionary<Int64,Boolean>;
  Parent  : TDictionary<Int64,Int64>  ;
  Depths  : TDictionary<Int64,Integer>;
  Frontier: TQueue<Int64>             ;
  Cur     : Int64                     ;
  Hit     : Int64                     ;
  Found   : Boolean                   ;
  Edges   : TArray<TCallEdge>         ;
  E       : TCallEdge                 ;
  PathIds : TList<Int64>              ;
  QNames  : TList<string>             ;
  Walk    : Int64                     ;
  ToB     : string                    ;
  i       : Integer                   ;
begin
  ToB:= AArgs.RenameTo; // --to reuses RenameTo (rename + call-path never co-run)
  if (AArgs.CallFrom = '') or (ToB = '') then
  begin Writeln('Usage: drag-lint call-path --from A --to B [--max-depth N] [--json] --db PATH'); Exit(2); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(2); // store-open/corruption failure = 2 (distinct from no-path = 1)

  FromIds:= ResolveEndpointIds(Store, AArgs.CallFrom);
  if Length(FromIds) = 0 then begin Writeln(Format('symbol not found: %s', [AArgs.CallFrom])); Exit(2); end;
  ToIds:= ResolveEndpointIds(Store, ToB);
  if Length(ToIds) = 0 then begin Writeln(Format('symbol not found: %s', [ToB])); Exit(2); end;

  var Cap: Integer:= AArgs.MaxDepth;
  if Cap <= 0 then Cap:= 20;

  ToSet   := TDictionary<Int64,Boolean>.Create;
  Visited := TDictionary<Int64,Boolean>.Create;
  Parent  := TDictionary<Int64,Int64>.Create;
  Depths  := TDictionary<Int64,Integer>.Create;
  Frontier:= TQueue<Int64>.Create;
  PathIds := TList<Int64>.Create;
  QNames  := TList<string>.Create;
  try
    for Hit in ToIds do ToSet.AddOrSetValue(Hit, True);

    // Seed the BFS with every id A resolves to (multi-source). A source that is
    // itself a target = the trivial length-0 path.
    Found:= False; Hit:= 0;
    for Cur in FromIds do
      if not Visited.ContainsKey(Cur) then
      begin
        Visited.Add(Cur, True);
        Depths.AddOrSetValue(Cur, 0);
        Frontier.Enqueue(Cur);
        if ToSet.ContainsKey(Cur) and not Found then begin Found:= True; Hit:= Cur; end;
      end;

    while (not Found) and (Frontier.Count > 0) do
    begin
      Cur:= Frontier.Dequeue;
      var D: Integer:= Depths[Cur];
      if D >= Cap then Continue; // depth cap: do not expand past the cap
      Edges:= Store.GetCallEdgesFromSymbol(Cur);
      for E in Edges do
      begin
        if E.TargetSymbolId <= 0 then Continue;
        if Visited.ContainsKey(E.TargetSymbolId) then Continue; // cycle/revisit guard
        Visited.Add(E.TargetSymbolId, True);
        Parent.AddOrSetValue(E.TargetSymbolId, Cur);
        Depths.AddOrSetValue(E.TargetSymbolId, D + 1);
        if ToSet.ContainsKey(E.TargetSymbolId) then
        begin Found:= True; Hit:= E.TargetSymbolId; Break; end;
        Frontier.Enqueue(E.TargetSymbolId);
      end; // for E
    end; // while

    if not Found then
    begin
      if AArgs.AsJson then
      begin
        var JNo:= TJSONObject.Create;
        try
          JNo.AddPair('found', TJSONBool.Create(False));
          JNo.AddPair('path' , TJSONArray.Create);
          Writeln(JNo.Format(2));
        finally JNo.Free; end;
      end
      else Writeln(Format('no path from %s to %s (within max-depth %d)', [AArgs.CallFrom, ToB, Cap]));
      Exit(1); // "not found" is a valid answer, signalled by exit 1
    end;

    // Reconstruct: walk parent links from Hit back to a seed (no parent entry).
    Walk:= Hit;
    while True do
    begin
      PathIds.Add(Walk);
      if not Parent.TryGetValue(Walk, Walk) then Break; // reached a BFS seed
    end;
    PathIds.Reverse; // parent-walk is target->source; flip to source->target

    for i:= 0 to PathIds.Count - 1 do
      QNames.Add(Store.GetSymbolById(PathIds[i]).QualifiedName);

    if AArgs.AsJson then
    begin
      var JOut:= TJSONObject.Create;
      try
        JOut.AddPair('found', TJSONBool.Create(True));
        var JArr:= TJSONArray.Create;
        for i:= 0 to QNames.Count - 1 do JArr.Add(QNames[i]);
        JOut.AddPair('path', JArr);
        Writeln(JOut.Format(2));
      finally JOut.Free; end;
    end
    else
    begin
      var Line: string:= '';
      for i:= 0 to QNames.Count - 1 do
      begin
        if i > 0 then Line:= Line + ' -> ';
        Line:= Line + QNames[i];
      end;
      Writeln(Line);
    end;
    Result:= 0;
  finally
    ToSet.Free; Visited.Free; Parent.Free; Depths.Free;
    Frontier.Free; PathIds.Free; QNames.Free;
  end; // try
end; // function

/// <summary>v14 (D5 T11): renders one node of the callgraph text tree (indented
/// 2 spaces per level) and recurses to --depth in the chosen direction. Cycle
/// policy is GLOBAL-VISITED: a symbol is expanded at most once across the whole
/// traversal; a second encounter prints "&lt;qname&gt; (cycle)" and does NOT
/// recurse, so the walk provably terminates (every recursion either hits the
/// depth cap or a node not yet in the visited set, and the id space is finite).
/// callees follows GetCallEdgesFromSymbol.TargetSymbolId; callers follows
/// FindResolvedCallers.EnclosingSymbolId.</summary>
/// <param name="AStore">Open store.</param>
/// <param name="AId">Symbol id of this node.</param>
/// <param name="ADepth">Remaining depth (0 = do not expand children).</param>
/// <param name="ACallees">True = callees direction, False = callers.</param>
/// <param name="AIndent">Current indent prefix.</param>
/// <param name="AVisited">Global visited set (shared across the whole tree).</param>
procedure RenderCallGraphText(const AStore: ISymbolStore; AId: Int64; ADepth: Integer;
  ACallees: Boolean; const AIndent: string; AVisited: TDictionary<Int64,Boolean>);
var
  QName    : string             ;
  Edges    : TArray<TCallEdge>  ;
  E        : TCallEdge          ;
  Callers  : TArray<TResolvedCaller>;
  C        : TResolvedCaller    ;
  ChildIds : TList<Int64>       ;
  Cid      : Int64              ;
begin
  QName:= AStore.GetSymbolById(AId).QualifiedName;
  if AVisited.ContainsKey(AId) then
  begin
    Writeln(Format('%s%s (cycle)', [AIndent, QName]));
    Exit; // already expanded elsewhere -- print marker, do not recurse
  end;
  AVisited.Add(AId, True);
  Writeln(Format('%s%s', [AIndent, QName]));
  if ADepth <= 0 then Exit;

  ChildIds:= TList<Int64>.Create;
  try
    if ACallees then
    begin
      Edges:= AStore.GetCallEdgesFromSymbol(AId);
      for E in Edges do
        if (E.TargetSymbolId > 0) and not ChildIds.Contains(E.TargetSymbolId) then
          ChildIds.Add(E.TargetSymbolId);
    end
    else
    begin
      Callers:= AStore.FindResolvedCallers(AId);
      for C in Callers do
        if (C.EnclosingSymbolId > 0) and not ChildIds.Contains(C.EnclosingSymbolId) then
          ChildIds.Add(C.EnclosingSymbolId);
    end;
    for Cid in ChildIds do
      RenderCallGraphText(AStore, Cid, ADepth - 1, ACallees, AIndent + '  ', AVisited);
  finally
    ChildIds.Free;
  end; // try
end; // procedure

/// <summary>v14 (D5 T11): builds one JSON node {qname, children:[...]} of the
/// callgraph, recursing to --depth with the SAME global-visited cycle policy as
/// the text renderer (a re-encountered node emits {qname, cycle:true} with no
/// children). Caller owns the returned TJSONObject.</summary>
/// <param name="AStore">Open store.</param>
/// <param name="AId">Symbol id of this node.</param>
/// <param name="ADepth">Remaining depth.</param>
/// <param name="ACallees">True = callees, False = callers.</param>
/// <param name="AVisited">Global visited set.</param>
/// <returns>A newly allocated JSON node the caller must free.</returns>
function BuildCallGraphJson(const AStore: ISymbolStore; AId: Int64; ADepth: Integer;
  ACallees: Boolean; AVisited: TDictionary<Int64,Boolean>): TJSONObject;
var
  QName   : string             ;
  Edges   : TArray<TCallEdge>  ;
  E       : TCallEdge          ;
  Callers : TArray<TResolvedCaller>;
  C       : TResolvedCaller    ;
  ChildIds: TList<Int64>       ;
  Cid     : Int64              ;
  Kids    : TJSONArray         ;
begin
  QName:= AStore.GetSymbolById(AId).QualifiedName;
  Result:= TJSONObject.Create;
  Result.AddPair('qname', QName);
  if AVisited.ContainsKey(AId) then
  begin
    Result.AddPair('cycle', TJSONBool.Create(True));
    Exit;
  end;
  AVisited.Add(AId, True);
  Kids:= TJSONArray.Create;
  Result.AddPair('children', Kids);
  if ADepth <= 0 then Exit;

  ChildIds:= TList<Int64>.Create;
  try
    if ACallees then
    begin
      Edges:= AStore.GetCallEdgesFromSymbol(AId);
      for E in Edges do
        if (E.TargetSymbolId > 0) and not ChildIds.Contains(E.TargetSymbolId) then
          ChildIds.Add(E.TargetSymbolId);
    end
    else
    begin
      Callers:= AStore.FindResolvedCallers(AId);
      for C in Callers do
        if (C.EnclosingSymbolId > 0) and not ChildIds.Contains(C.EnclosingSymbolId) then
          ChildIds.Add(C.EnclosingSymbolId);
    end;
    for Cid in ChildIds do
      Kids.AddElement(BuildCallGraphJson(AStore, Cid, ADepth - 1, ACallees, AVisited));
  finally
    ChildIds.Free;
  end; // try
end; // function

/// <summary>v14 (D5 T11): drag-lint callgraph --qname X [--direction
/// callers|callees] [--depth N] [--json] --db PATH -- prints the N-deep
/// resolved call tree rooted at X, over the resolved call_edges. --direction
/// callees (default) follows outgoing calls; callers follows resolved callers.
/// The tree is bounded by BOTH --depth (default 3) AND a global-visited set
/// that guards cycles: a recursive call graph WILL contain cycles (A calls B
/// calls A), and each node is expanded at most once -- a re-encounter prints
/// "&lt;qname&gt; (cycle)" (text) / cycle:true (json) and does not recurse, so
/// the traversal provably terminates. Renders an indented text tree (2 spaces
/// per level) or a nested {qname, children:[...]} JSON object. Traverses within
/// a single DB (ids are per-DB).</summary>
/// <param name="AArgs">Parsed CLI args; QName is the root, Direction the
/// direction, Depth the tree depth, DbPath the index.</param>
/// <returns>0 when the store opened OK and --qname resolved to at least one
/// symbol; 1 if --qname does not resolve to any symbol; 2 on usage error /
/// missing or unreadable db (store-open failure) / a bad --direction
/// value.</returns>
function DoCallGraph(const AArgs: TArgs): Integer;
var
  Store  : ISymbolStore              ;
  RootIds: TArray<Int64>             ;
  Visited: TDictionary<Int64,Boolean>;
  Dir    : string                    ;
  Callees: Boolean                   ;
  Depth  : Integer                   ;
  Rid    : Int64                     ;
begin
  if AArgs.QName = '' then
  begin Writeln('Usage: drag-lint callgraph --qname X [--direction callers|callees] [--depth N] [--json] --db PATH'); Exit(2); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;

  Dir:= LowerCase(Trim(AArgs.Direction));
  if Dir = '' then Dir:= 'callees';
  if (Dir <> 'callees') and (Dir <> 'callers') then
  begin Writeln(Format('ERROR: --direction must be callers|callees (got "%s")', [AArgs.Direction])); Exit(2); end;
  Callees:= (Dir = 'callees');

  Depth:= AArgs.Depth;
  if Depth < 0 then Depth:= 0;

  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(2); // store-open/corruption failure = 2 (distinct from unresolved-qname = 1)

  RootIds:= ResolveEndpointIds(Store, AArgs.QName);
  if Length(RootIds) = 0 then begin Writeln(Format('symbol not found: %s', [AArgs.QName])); Exit(1); end;

  if AArgs.AsJson then
  begin
    var JRoots:= TJSONArray.Create;
    try
      for Rid in RootIds do
      begin
        Visited:= TDictionary<Int64,Boolean>.Create;
        try
          JRoots.AddElement(BuildCallGraphJson(Store, Rid, Depth, Callees, Visited));
        finally Visited.Free; end;
      end;
      // A single root prints the bare object; multiple (overloads) print an array.
      if JRoots.Count = 1 then Writeln((JRoots.Items[0] as TJSONObject).Format(2))
      else Writeln(JRoots.Format(2));
    finally JRoots.Free; end;
  end
  else
  begin
    for Rid in RootIds do
    begin
      Visited:= TDictionary<Int64,Boolean>.Create;
      try
        RenderCallGraphText(Store, Rid, Depth, Callees, '', Visited);
      finally Visited.Free; end;
    end;
  end;
  Result:= 0;
end; // function

/// <summary>drag-lint proptree --qname X [--depth N] [--no-to-persistent]
/// [--min-visibility published|public] [--format text|json] [--json] --db PATH
/// [--db ...] -- Track 3 Batch 1: the index-driven RECURSIVE deep-property
/// enumerator. Resolves class X, walks its own + inherited kind='property'
/// children, parses each property's type from its Signature, and recurses into
/// class-typed property types (depth-capped + a visited-TYPE-name cycle guard) to
/// produce flattened dotted paths (Font.Color, Inner.Shade). --depth defaults to 6
/// (applied here when Depth&lt;=0). ToPersistent (default ON) stops the ancestor
/// climb at TPersistent/TObject; --no-to-persistent climbs past. text = an
/// indented tree (indent = the path's dot-depth); json = schema proptree/2 (v2:
/// adds per-leaf visibility/is_writable/member_kind; additive over proptree/1).
/// --min-visibility published|public filters the EMITTED leaves by EFFECTIVE
/// (most-derived) visibility: unset (default) emits ALL leaves exactly as
/// proptree/1 did (back-compat); 'published' emits only published leaves;
/// 'public' emits published+public leaves. Applies to both text and json output.
/// With multiple --db, the first DB that resolves the qname to a class is used
/// (ids are per-DB). Write-back is AUTOMATIC: the resolving index is opened
/// WRITABLE so a property type recovered by the lazy ancestry-bridge (across an
/// unresolved/type-alias ancestor edge) is memoized back onto the property row
/// (next query is a plain hit; self-limiting). A writable open that fails falls
/// back to read-only (resolution still works; memoization skipped). --no-write-back
/// forces a read-only (query_only) open that never mutates the DB.</summary>
/// <param name="AArgs">QName=class, Depth=recursion cap (default 6),
/// ToPersistent=ancestor-stop, NoWriteBack=force read-only (no memoization),
/// MinVisibility=--min-visibility filter ('' = all), Format/AsJson=output,
/// DbPath/DbPaths=index(es).</param>
/// <returns>0 ok; 1 qname not resolved to a class in any DB; 2 usage error / no
/// readable db / invalid --min-visibility value.</returns>
function DoPropTree(const AArgs: TArgs): Integer;
var
  Dbs   : TArray<string>  ;
  Db    : string          ;
  Store : ISymbolStore    ;
  Tree  : TPropTree       ;
  Found : Boolean         ;
  Depth : Integer         ;
  Fmt   : string          ;
  Opts  : TPropTreeOptions;
  MinVis: string          ;

  function KindLabel(const ANode: TPropNode): string;
  begin
    Result:= ANode.Kind;
  end;

  // proptree/2 (Task 2, R2): does ANode's effective visibility pass the
  // --min-visibility threshold? AMinVis is already lower-cased/trimmed/
  // validated by the caller ('' | 'published' | 'public').
  // R4 (Task 4 review fix): a FIELD is never a DFM-streamable target,
  // regardless of its own declared visibility -- a `published FBtn:
  // TButton;` field is legal Delphi and DOES get Modifiers='published'
  // stamped by the same declField/CurrentVisibility path a published
  // PROPERTY gets, but proptree's 'published' tier specifically means "the
  // Object Inspector / DFM-streamed property surface", which fields (even
  // published ones) are not part of. This is a member_kind-based FILTER
  // exclusion only -- the node's own Visibility value is NEVER altered
  // (KindLabel/JSON emit still reports the field's real, e.g. 'published',
  // visibility); only whether it PASSES the 'published' bar changes.
  function PassesMinVisibility(const ANode: TPropNode; const AMinVis: string): Boolean;
  var
    Vis: string;
  begin
    if AMinVis = '' then Exit(True); // unset = emit ALL leaves (back-compat)
    if (AMinVis = 'published') and (LowerCase(Trim(ANode.MemberKind)) = 'field') then Exit(False);
    Vis:= LowerCase(Trim(ANode.Visibility));
    if AMinVis = 'published' then Exit(Vis = 'published');
    Result:= (Vis = 'published') or (Vis = 'public'); // AMinVis = 'public'
  end;

begin
  if AArgs.QName = '' then
  begin Writeln('Usage: drag-lint proptree --qname X [--depth N] [--no-to-persistent] [--no-write-back] [--min-visibility published|public] [--format text|json] [--json] --db PATH [--db ...]'); Exit(2); end;

  Fmt:= LowerCase(Trim(AArgs.Format));

  // proptree/2 (Task 2, R2): validate --min-visibility up front (usage error,
  // not a silent fall-through) so a typo does not silently emit ALL leaves.
  MinVis:= LowerCase(Trim(AArgs.MinVisibility));
  if (MinVis <> '') and (MinVis <> 'published') and (MinVis <> 'public') then
  begin Writeln(Format('ERROR: --min-visibility must be published|public (got "%s")', [AArgs.MinVisibility])); Exit(2); end;

  // proptree's own default depth is 6 (deeper than the global --depth default of
  // 3), applied here so the shared parse default is untouched.
  Depth:= AArgs.Depth;
  if Depth <= 0 then Depth:= 6;

  Opts.Depth       := Depth;
  Opts.ToPersistent:= AArgs.ToPersistent;

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.'); Exit(2); end;

  // Multi-db resolution: use the FIRST db whose qname resolves to a class
  // (RootType non-empty). Exit 2 if no --db is readable; exit 1 if none resolve.
  Store:= nil;
  Found:= False;
  Tree := Default(TPropTree);
  for Db in Dbs do
  begin
    if not TFile.Exists(Db) then Continue;
    var RoOk: Boolean;
    // Write-back is AUTOMATIC: open the index WRITABLE by default so a bridged type
    // is memoized onto the property row (next query is a plain hit). --no-write-back
    // forces a read-only (query_only) open that never mutates the DB. A writable
    // open that fails (locked / read-only file / stale schema) falls back to
    // read-only so resolution still works -- memoization is best-effort.
    var CandidateStore: ISymbolStore;
    if AArgs.NoWriteBack then CandidateStore:= OpenReadOnlyStore(Db, RoOk)
    else
    begin
      CandidateStore:= OpenWritableStore(Db, RoOk);
      if not RoOk then CandidateStore:= OpenReadOnlyStore(Db, RoOk); // graceful read-only fallback
    end;
    if not RoOk then Continue;
    Store:= CandidateStore; // at least one readable db
    var Candidate: TPropTree:= BuildPropTree(CandidateStore, AArgs.QName, Opts);
    if Candidate.RootType <> '' then
    begin
      Tree := Candidate;
      Found:= True;
      Break;
    end;
  end;
  if Store = nil then begin Writeln('ERROR: no readable drag-lint index among --db path(s)'); Exit(2); end;
  if not Found then begin Writeln(Format('class not found: %s', [AArgs.QName])); Exit(1); end;

  if (Fmt = 'json') or ((Fmt = '') and AArgs.AsJson) then
  begin
    var JRoot: TJSONObject:= TJSONObject.Create;
    try
      JRoot.AddPair('schema'   , 'proptree/2'    );
      JRoot.AddPair('qname'    , AArgs.QName      );
      JRoot.AddPair('root_type', Tree.RootType    );
      JRoot.AddPair('truncated', TJSONBool.Create(Tree.Truncated));
      var JProps: TJSONArray:= TJSONArray.Create;
      for var N in Tree.Nodes do
      begin
        if not PassesMinVisibility(N, MinVis) then Continue;
        var JN: TJSONObject:= TJSONObject.Create;
        JN.AddPair('path'          , N.Path      );
        JN.AddPair('type'          , N.TypeName  );
        JN.AddPair('declared_in'   , N.DeclaredIn);
        JN.AddPair('kind'          , KindLabel(N));
        JN.AddPair('is_class_typed', TJSONBool.Create(N.IsClassTyped));
        JN.AddPair('visibility'    , N.Visibility);
        JN.AddPair('is_writable'   , TJSONBool.Create(N.IsWritable));
        JN.AddPair('member_kind'   , N.MemberKind);
        JProps.AddElement(JN);
      end;
      JRoot.AddPair('properties', JProps);
      Writeln(JRoot.Format(2));
    finally
      JRoot.Free;
    end;
  end
  else // text (default, or explicit --format text)
  begin
    var ShownCount: Integer:= 0;
    for var N in Tree.Nodes do
      if PassesMinVisibility(N, MinVis) then Inc(ShownCount);
    Writeln(Format('%s  (%d properties%s)', [Tree.RootType, ShownCount,
      IfThen(Tree.Truncated, ', truncated', '')]));
    for var N in Tree.Nodes do
    begin
      if not PassesMinVisibility(N, MinVis) then Continue;
      // Indent by the path's dot-depth (top-level = 0).
      var DotDepth: Integer:= 0;
      for var Ch in N.Path do if Ch = '.' then Inc(DotDepth);
      var Leaf: string:= N.Path;
      var LastDot: Integer:= LastDelimiter('.', N.Path);
      if LastDot > 0 then Leaf:= Copy(N.Path, LastDot + 1, MaxInt);
      Writeln(Format('%s%s: %s [%s]', [StringOfChar(' ', DotDepth * 2), Leaf, N.TypeName, KindLabel(N)]));
    end;
  end;
  Result:= 0;
end; // function

/// <summary>drag-lint convert-validate --rules FILE [--from FromType] [--to ToType]
/// [--print-parsed] [--db PATH ...] -- Track 3 Batch 1: parse a reFind-superset
/// conversion-rules DSL file and (when --from/--to types are supplied) validate its
/// #link / #default target/source paths against the REAL property trees of those
/// types (Task 1's BuildPropTree). --rules is required (missing -&gt; usage + exit 2;
/// unreadable -&gt; exit 2). Without --from/--to it is parse-only: only unknown-
/// directive parse errors are reported, path checks are skipped. --print-parsed
/// dumps 'parsed N rule(s)' plus one 'line L: kind ...' summary per rule (so a test
/// can assert the parse result with no trees). A literal '???' path is an explicit
/// STUB marker (the scaffolder emits these) and is NOT a path error. Prints 'OK' on
/// success or a list of 'line N: message' on errors.</summary>
/// <param name="AArgs">RulesFile=--rules; CallFrom=--from (FromType qname),
/// RenameTo=--to (ToType qname); PrintParsed=--print-parsed; DbPath/DbPaths=index(es)
/// used to build the from/to trees.</param>
/// <returns>0 valid / parse-ok; 1 errors found (parse or validation); 2 bad args
/// (no --rules) or unreadable rules file.</returns>
function DoConvertValidate(const AArgs: TArgs): Integer;
var
  RulesText: string             ;
  RuleSet  : TConversionRuleSet ;
  Errors   : TArray<TRuleError> ;
  FromTree : TPropTree          ;
  ToTree   : TPropTree          ;
  Opts     : TPropTreeOptions   ;
  Dbs      : TArray<string>     ;
  E        : TRuleError         ;
  R        : TConversionRule    ;
  Depth    : Integer            ;

  function KindStr(const AKind: TRuleKind): string;
  begin
    case AKind of
      rkUnuse  : Result:= 'unuse';
      rkRemove : Result:= 'remove';
      rkMigrate: Result:= 'migrate';
      rkConvert: Result:= 'convert';
      rkLink   : Result:= 'link';
      rkDefault: Result:= 'default';
      rkNote   : Result:= 'note';
      rkPcre   : Result:= 'pcre';
      rkIgnore : Result:= 'ignore';
    else        Result:= '?';
    end;
  end;

  // One-line summary of a parsed rule's key fields (for --print-parsed).
  function RuleSummary(const R: TConversionRule): string;
  begin
    case R.Kind of
      rkUnuse  : Result:= Format('unuse %s', [R.UnitName]);
      rkRemove : Result:= Format('remove %s%s', [R.PropName, IfThen(R.DfmOnly, ' (DFM-only)', '')]);
      rkMigrate: Result:= Format('migrate %s%s -> %s%s', [R.Scope, R.Old, R.New,
                            IfThen(Length(R.UnitsAdd) > 0, ' [+' + String.Join(',', R.UnitsAdd) + ']', '')]);
      rkConvert: Result:= Format('convert %s -> %s%s', [R.FromType, R.ToType,
                            IfThen(Length(R.UnitsAdd) > 0, ' [+' + String.Join(',', R.UnitsAdd) + ']', '')]);
      rkLink   : Result:= Format('link %s <- %s', [R.ToPath, R.FromPath]);
      rkDefault: Result:= Format('default %s = %s', [R.ToPath, R.Value]);
      rkNote   : Result:= Format('note %s', [R.Text]);
      rkPcre   : Result:= Format('pcre %s -> %s', [R.Search, R.Replace]);
      rkIgnore : Result:= Format('ignore FromPath=%s', [R.FromPath]);
    else        Result:= KindStr(R.Kind);
    end;
  end;

  // Build the property tree for a type qname across the resolved DBs (first DB
  // that resolves it wins). Empty RootType if unresolved / no db.
  function TreeFor(const AQName: string): TPropTree;
  var
    Cand: TPropTree;
    LDb : string   ;
  begin
    Result:= Default(TPropTree);
    if AQName = '' then Exit;
    for LDb in Dbs do
    begin
      if not TFile.Exists(LDb) then Continue;
      var RoOk: Boolean;
      var CandStore: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
      if not RoOk then Continue;
      Cand:= BuildPropTree(CandStore, AQName, Opts);
      if Cand.RootType <> '' then Exit(Cand);
    end;
  end;

begin
  if AArgs.RulesFile = '' then
  begin Writeln('Usage: drag-lint convert-validate --rules FILE [--from FromType] [--to ToType] [--print-parsed] [--db PATH ...]'); Exit(2); end;
  if not TFile.Exists(AArgs.RulesFile) then
  begin Writeln(Format('ERROR: rules file not found: %s', [AArgs.RulesFile])); Exit(2); end;

  try
    RulesText:= TFile.ReadAllText(AArgs.RulesFile);
  except
    on Ex: Exception do
    begin Writeln(Format('ERROR: cannot read rules file: %s (%s)', [AArgs.RulesFile, Ex.Message])); Exit(2); end;
  end;

  RuleSet:= ParseConversionRules(RulesText);

  if AArgs.PrintParsed then
  begin
    Writeln(Format('parsed %d rule(s)', [Length(RuleSet.Rules)]));
    for R in RuleSet.Rules do
      Writeln(Format('line %d: %s', [R.LineNo, RuleSummary(R)]));
    for E in RuleSet.ParseErrors do
      Writeln(Format('line %d: parse error: %s', [E.LineNo, E.Message]));
  end;

  // Build the from/to property trees when the types are supplied. Ids are per-DB,
  // so both trees come from the same resolved DB set. When neither is given this
  // is parse-only: only parse errors surface (empty trees skip path checks).
  Depth:= AArgs.Depth;
  if Depth <= 0 then Depth:= 6;
  Opts.Depth       := Depth;
  Opts.ToPersistent:= AArgs.ToPersistent;

  Dbs     := ResolveConsumerDbs(AArgs);
  FromTree := TreeFor(AArgs.CallFrom); // --from reuses CallFrom
  ToTree   := TreeFor(AArgs.RenameTo); // --to   reuses RenameTo

  Errors:= ValidateConversionRules(RuleSet, FromTree, ToTree);

  if Length(Errors) = 0 then
  begin
    if not AArgs.PrintParsed then Writeln('OK');
    Exit(0);
  end;

  for E in Errors do
    Writeln(Format('line %d: %s', [E.LineNo, E.Message]));
  Result:= 1;
end; // function

/// <summary>drag-lint convert-reemit --from-block FILE --rules FILE --from FromType
/// --to ToType --db PATH -- HIDDEN test verb driving the pure ReemitComponent
/// engine. Prints the emitted T DFM block + report as JSON. Not in help/README;
/// superseded by convert-apply (2a-iii).</summary>
/// <param name="AArgs">FromBlockFile=--from-block (one F DFM object block file);
/// RulesFile=--rules; CallFrom=--from (FromType qname), RenameTo=--to (ToType
/// qname); DbPath/DbPaths=index(es) used to build the from/to trees.</param>
/// <returns>0 when Ok; 1 on a hard re-emit failure; 2 on bad args.</returns>
/// <remarks>Builds the F/T property trees from the index (like convert-validate,
/// same first-DB-that-resolves-wins loop), parses the rules DSL, calls
/// ReemitComponent, and serializes the result. Read-only against the store.</remarks>
function DoConvertReemit(const AArgs: TArgs): Integer;
var
  FromTree : TPropTree          ;
  ToTree   : TPropTree          ;
  Rules    : TConversionRuleSet ;
  Res      : TReemitResult      ;
  Opts     : TPropTreeOptions   ;
  Depth    : Integer            ;
  Dbs      : TArray<string>     ;
  BlockText: string             ;
  RulesText: string             ;
  JRoot    : TJSONObject        ;
  JReport  : TJSONObject        ;

  function ArrJson(const A: TArray<string>): TJSONArray;
  var S: string;
  begin
    Result:= TJSONArray.Create;
    for S in A do Result.Add(S);
  end;

  // Build the property tree for a type qname across the resolved DBs (first DB
  // that resolves it wins). Empty RootType if unresolved / no db. Mirrors
  // DoConvertValidate's TreeFor exactly.
  function TreeFor(const AQName: string): TPropTree;
  var
    Cand: TPropTree;
    LDb : string   ;
  begin
    Result:= Default(TPropTree);
    if AQName = '' then Exit;
    for LDb in Dbs do
    begin
      if not TFile.Exists(LDb) then Continue;
      var RoOk: Boolean;
      var CandStore: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
      if not RoOk then Continue;
      Cand:= BuildPropTree(CandStore, AQName, Opts);
      if Cand.RootType <> '' then Exit(Cand);
    end;
  end;

begin
  if (AArgs.FromBlockFile = '') or (AArgs.RulesFile = '') or
     (AArgs.CallFrom = '') or (AArgs.RenameTo = '') then
  begin
    Writeln('Usage: drag-lint convert-reemit --from-block FILE --rules FILE --from FromType --to ToType --db PATH');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.FromBlockFile) then
  begin Writeln('from-block not found: ' + AArgs.FromBlockFile); Exit(2); end;
  if not TFile.Exists(AArgs.RulesFile) then
  begin Writeln('rules not found: ' + AArgs.RulesFile); Exit(2); end;

  try
    BlockText:= TFile.ReadAllText(AArgs.FromBlockFile);
    RulesText:= TFile.ReadAllText(AArgs.RulesFile);
  except
    on Ex: Exception do
    begin Writeln(Format('ERROR: cannot read input file (%s)', [Ex.Message])); Exit(2); end;
  end;

  Rules:= ParseConversionRules(RulesText);

  // Build F/T trees from the first DB that resolves each qname (mirrors
  // DoConvertValidate's store-open + multi-db loop verbatim).
  Depth:= AArgs.Depth;
  if Depth <= 0 then Depth:= 6;
  Opts.Depth       := Depth;
  Opts.ToPersistent:= AArgs.ToPersistent;

  Dbs     := ResolveConsumerDbs(AArgs);
  FromTree:= TreeFor(AArgs.CallFrom); // --from reuses CallFrom
  ToTree  := TreeFor(AArgs.RenameTo); // --to   reuses RenameTo

  Res:= ReemitComponent(BlockText, Rules, FromTree, ToTree);

  JRoot:= TJSONObject.Create;
  try
    JRoot.AddPair('ok', TJSONBool.Create(Res.Ok));
    JRoot.AddPair('error', Res.Error);
    JRoot.AddPair('dfm', Res.DfmText);
    JReport:= TJSONObject.Create;
    JReport.AddPair('dropped',    ArrJson(Res.Report.Dropped));
    JReport.AddPair('ignored',    ArrJson(Res.Report.Ignored));
    JReport.AddPair('mismatched', ArrJson(Res.Report.Mismatched));
    JReport.AddPair('created',    ArrJson(Res.Report.Created));
    JReport.AddPair('ownedParts', ArrJson(Res.Report.OwnedParts));
    JReport.AddPair('notes',      ArrJson(Res.Report.Notes));
    JRoot.AddPair('report', JReport);
    Writeln(JRoot.ToJSON);
  finally
    JRoot.Free;
  end;

  if Res.Ok then Exit(0) else Exit(1);
end; // function

/// <summary>drag-lint convert-scaffold --from FromType --to ToType [--out FILE]
/// [--surface dfm|pas] --db PATH [--db ...] -- Track 3 Batch 1: auto-generate a
/// VALID reFind-superset conversion-rules file from the REAL deep-property trees
/// of the From and To types (Task 1's BuildPropTree over BOTH), pre-filling the
/// assignments it can safely infer and leaving only genuine ambiguities as '???'
/// for the user to resolve. --from (reuses CallFrom) and --to (reuses RenameTo)
/// are BOTH required (missing -&gt; usage + exit 2). --out (reuses Output) writes
/// an ASCII/CRLF file; omitted -&gt; stdout. Multiple --db are tried in order; the
/// FIRST db that resolves BOTH types is used (ids are per-DB). If either type is
/// unresolved the verb names it and exits 1.
/// proptree assignability engine (Task 5): auto-'#link' TARGETS (the To side
/// only -- From remains an unrestricted candidate SOURCE pool) are restricted to
/// leaves that are actually valid assignment targets, using the is_writable/
/// visibility/member_kind fields BuildPropTree already stamps onto every
/// TPropNode (Tasks 2-4; no extra wiring needed since convert-scaffold's To tree
/// comes from the SAME BuildPropTree call as `proptree`). --surface dfm (the
/// default) requires member_kind='property' AND the effective visibility=
/// 'published' -- the DFM-streamable surface, matching today's dominant
/// component-conversion use case; --surface pas relaxes the bar to visibility in
/// ('published','public'), ANY member_kind (so a public FIELD can be a target
/// too). On EITHER surface a leaf with is_writable=false (a typed class CONST
/// today; a read-only PROPERTY once a later task extracts real property
/// writability) is NEVER a valid target. A To path that fails either bar is
/// fully excluded from the per-To-path loop -- no '#link', no '#default', no
/// '#note' -- mirroring how `proptree --min-visibility` silently drops a
/// tier-failing leaf with no extra annotation (the existing convention for "not
/// part of this surface"; the DSL's own '#ignore' directive was considered and
/// rejected -- it acknowledges an unmapped FROM path, a different direction,
/// not a filtered TO target). A To path's own Visibility='' (defensive-only in
/// practice -- the current parser always stamps a non-empty value; see
/// DRagLint.Convert.PropTree's ResolveInheritedVisibility remark) is treated as
/// PASSING the bar on both surfaces -- graceful degrade so an old/foreign DB
/// row whose visibility could not be resolved is never MORE aggressively
/// filtered than today's "show everything", matching a proptree/1-style
/// consumer's back-compat default. The FROM-side DROPPED-note loop (3) uses the
/// SAME valid-target test, so a From path whose only leaf-name+type counterpart
/// is a filtered-out To leaf is correctly reported DROPPED rather than silently
/// neither linked nor noted.</summary>
/// <param name="AArgs">CallFrom=--from (FromType qname), RenameTo=--to (ToType
/// qname), Output=--out (file; empty=stdout), Surface=--surface dfm|pas ('' =
/// default 'dfm'), DbPath/DbPaths=index(es).</param>
/// <returns>0 success; 1 either type unresolved in every db; 2 bad args (missing
/// --from/--to, invalid --surface value) or no readable db.</returns>
/// <remarks>Output is DETERMINISTIC (paths sorted case-insensitively) so the
/// emitted text is stable across runs. Emission order: (1) a '#convert From -&gt;
/// To' header with a best-guess ', unit' uses-add taken from the qname unit
/// prefix(es) of From/To when discoverable (never fabricated); (2) for each
/// VALID-TARGET To path (sorted; see the surface/writability filter above) the F
/// candidates whose LEAF name equals the To leaf (case-insensitive) AND whose
/// declared TypeName is compatible (equal, case-insensitive) -- exactly ONE
/// candidate -&gt; a concrete '#link ToPath &lt;- FromPath'; MULTIPLE -&gt; '#link
/// ToPath &lt;- ???' immediately followed by '#note candidates: p1, p2, ...';
/// ZERO -&gt; '#default ToPath = ???'; (3) for each From path (sorted) with NO
/// compatible VALID-TARGET To counterpart (same leaf+type test, reversed) a
/// '#note DROPPED FromPath (no T target)'. The matching rule is LEAF-NAME +
/// COMPATIBLE-TYPE (documented, not exact-path), so a leaf name that appears at
/// more than one From path is correctly flagged ambiguous. Every concrete path
/// emitted is guaranteed to exist in the real trees and every '???' is tolerated
/// by the validator, so the emitted file round-trips clean through
/// convert-validate. Read-only.</remarks>
function DoConvertScaffold(const AArgs: TArgs): Integer;
var
  Dbs      : TArray<string>  ;
  LDb      : string          ;
  FromTree : TPropTree       ;
  ToTree   : TPropTree       ;
  HaveStore: Boolean         ;
  Opts     : TPropTreeOptions;
  Depth    : Integer         ;
  Sb       : TStringBuilder  ;
  OutText  : string          ;
  Surface  : string          ;

  // Bare leaf (last dotted segment) of a path, lowercased for matching.
  function LeafLower(const APath: string): string;
  var
    D: Integer;
  begin
    D:= LastDelimiter('.', APath);
    if D > 0 then Result:= Copy(APath, D + 1, MaxInt) else Result:= APath;
    Result:= LowerCase(Result);
  end;

  // Unit prefix of a qualified name ('ConvFix.TFrom' -> 'ConvFix'); '' if none.
  function UnitOf(const AQName: string): string;
  var
    D: Integer;
  begin
    D:= LastDelimiter('.', AQName);
    if D > 0 then Result:= Copy(AQName, 1, D - 1) else Result:= '';
  end;

  // Sorted copy of a tree's paths (case-insensitive). A Sorted TStringList with
  // CaseSensitive=False orders by CompareText -- no custom callback needed.
  function SortedPaths(const ATree: TPropTree): TArray<string>;
  var
    L: TStringList;
    N: TPropNode;
  begin
    L:= TStringList.Create;
    try
      L.CaseSensitive := False;
      L.Duplicates    := dupAccept;
      L.Sorted        := True;
      for N in ATree.Nodes do L.Add(N.Path);
      Result:= L.ToStringArray;
    finally
      L.Free;
    end;
  end;

  // The declared TypeName for a path in a tree ('' if not found).
  function TypeOfPath(const ATree: TPropTree; const APath: string): string;
  var
    N: TPropNode;
  begin
    Result:= '';
    for N in ATree.Nodes do
      if SameText(N.Path, APath) then Exit(N.TypeName);
  end;

  // The full TPropNode for a path in a tree (Path='' -- not present -- if
  // not found; every real leaf has a non-empty Path, so this is a safe
  // not-found sentinel).
  function NodeOfPath(const ATree: TPropTree; const APath: string): TPropNode;
  var
    N: TPropNode;
  begin
    Result:= Default(TPropNode);
    for N in ATree.Nodes do
      if SameText(N.Path, APath) then Exit(N);
  end;

  // proptree assignability engine (Task 5): does ANode qualify as a valid
  // auto-'#link'/'#default' TARGET under ASurface ('dfm' or 'pas', already
  // lower-cased/validated by the caller)? is_writable=false (a typed class
  // CONST today) is NEVER a valid target on EITHER surface. 'dfm' additionally
  // requires member_kind='property' (DFM streaming is properties only -- a
  // FIELD, even a published one, is never DFM-streamable, mirroring
  // DoPropTree's PassesMinVisibility 'published' tier) AND the effective
  // visibility='published'; 'pas' allows visibility in ('published','public')
  // and ANY member_kind (so a public FIELD is a valid PAS-surface target).
  // Graceful degrade: an UNRESOLVABLE effective visibility (Visibility='') is
  // treated as PASSING the bar on BOTH surfaces rather than being silently
  // dropped -- defensive-only in practice (the current parser always stamps a
  // non-empty Modifiers value; see DRagLint.Convert.PropTree's
  // ResolveInheritedVisibility remark), but this keeps an old/foreign DB row
  // whose visibility could not be resolved exactly as visible as it is today
  // (no filter existed before this task) instead of quietly vanishing it.
  function IsValidTarget(const ANode: TPropNode; const ASurface: string): Boolean;
  var
    Vis: string;
  begin
    if not ANode.IsWritable then Exit(False); // read-only -- never a valid target, any surface
    Vis:= LowerCase(Trim(ANode.Visibility));
    if Vis = '' then Exit(True); // unresolvable -- graceful degrade, do not filter (see remarks)
    if ASurface = 'dfm' then
    begin
      if LowerCase(Trim(ANode.MemberKind)) = 'field' then Exit(False); // DFM streams properties only
      Exit(Vis = 'published');
    end;
    Result:= (Vis = 'published') or (Vis = 'public'); // ASurface = 'pas'
  end;

  // From-tree paths whose leaf name = ATLeaf (lowercased) AND whose declared
  // type is compatible (equal, case-insensitive) with ATType. Sorted (a Sorted
  // CaseSensitive=False TStringList orders by CompareText).
  function FromCandidates(const ATLeaf, ATType: string): TArray<string>;
  var
    L: TStringList;
    N: TPropNode;
  begin
    L:= TStringList.Create;
    try
      L.CaseSensitive := False;
      L.Duplicates    := dupAccept;
      L.Sorted        := True;
      for N in FromTree.Nodes do
        if (LeafLower(N.Path) = ATLeaf) and SameText(N.TypeName, ATType) then
          L.Add(N.Path);
      Result:= L.ToStringArray;
    finally
      L.Free;
    end;
  end;

  // True when SOME VALID-TARGET To path has the leaf+compatible-type of the
  // given F node (used to decide whether an F path is DROPPED). Uses the same
  // IsValidTarget test as the #link loop, so a From path whose only
  // leaf+type counterpart is a filtered-out (read-only / wrong-surface) To
  // leaf is correctly reported DROPPED rather than silently neither linked
  // nor noted.
  function ToHasCounterpart(const AFLeaf, AFType: string): Boolean;
  var
    N: TPropNode;
  begin
    Result:= False;
    for N in ToTree.Nodes do
      if (LeafLower(N.Path) = AFLeaf) and SameText(N.TypeName, AFType) and IsValidTarget(N, Surface) then
        Exit(True);
  end;

var
  TPath   : string        ;
  TType   : string        ;
  Cands   : TArray<string>;
  FPath   : string        ;
  FType   : string        ;
  UFrom   : string        ;
  UTo     : string        ;
  Header  : string        ;
begin
  if (AArgs.CallFrom = '') or (AArgs.RenameTo = '') then
  begin Writeln('Usage: drag-lint convert-scaffold --from FromType --to ToType [--out FILE] [--surface dfm|pas] --db PATH [--db ...]'); Exit(2); end;

  // proptree assignability engine (Task 5): --surface dfm|pas picks the
  // TARGET-side visibility bar (see IsValidTarget above); unset defaults to
  // 'dfm' -- component conversion (DFM-streamable published surface) is
  // convert-scaffold's dominant use case today (the existing
  // run_convert_scaffold.ps1 fixture is all-published, so this default does
  // not change its output). A typo'd value is a usage error (exit 2), not a
  // silent fall-through, matching --min-visibility's own validation pattern
  // in DoPropTree.
  Surface:= LowerCase(Trim(AArgs.Surface));
  if Surface = '' then Surface:= 'dfm';
  if (Surface <> 'dfm') and (Surface <> 'pas') then
  begin Writeln(Format('ERROR: --surface must be dfm|pas (got "%s")', [AArgs.Surface])); Exit(2); end;

  Depth:= AArgs.Depth;
  if Depth <= 0 then Depth:= 6;
  Opts.Depth       := Depth;
  Opts.ToPersistent:= AArgs.ToPersistent;

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.'); Exit(2); end;

  // Use the FIRST db that resolves BOTH types (ids are per-DB, so both trees
  // must come from the same store). Exit 2 if no --db is readable.
  HaveStore:= False;
  FromTree := Default(TPropTree);
  ToTree   := Default(TPropTree);
  for LDb in Dbs do
  begin
    if not TFile.Exists(LDb) then Continue;
    var RoOk: Boolean;
    var CandStore: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
    if not RoOk then Continue;
    HaveStore:= True;
    var CF: TPropTree:= BuildPropTree(CandStore, AArgs.CallFrom, Opts);
    var CT: TPropTree:= BuildPropTree(CandStore, AArgs.RenameTo, Opts);
    if (CF.RootType <> '') and (CT.RootType <> '') then
    begin FromTree:= CF; ToTree:= CT; Break; end;
    // Keep the first db's partial trees so we can report which type failed.
    if FromTree.RootType = '' then FromTree:= CF;
    if ToTree.RootType   = '' then ToTree  := CT;
  end;
  if not HaveStore then begin Writeln('ERROR: no readable drag-lint index among --db path(s)'); Exit(2); end;
  if FromTree.RootType = '' then begin Writeln(Format('class not found: %s', [AArgs.CallFrom])); Exit(1); end;
  if ToTree.RootType   = '' then begin Writeln(Format('class not found: %s', [AArgs.RenameTo])); Exit(1); end;

  Sb:= TStringBuilder.Create;
  try
    // (1) #convert header + best-guess uses-add (the qname unit prefixes).
    UFrom:= UnitOf(AArgs.CallFrom);
    UTo  := UnitOf(AArgs.RenameTo);
    Header:= Format('#convert %s -> %s', [AArgs.CallFrom, AArgs.RenameTo]);
    if (UTo <> '') and (not SameText(UTo, UFrom)) then
      Header:= Header + ', ' + UTo
    else if (UTo = '') and (UFrom <> '') then
      Header:= Header + ', ' + UFrom;
    Sb.AppendLine(Header);
    Sb.AppendLine('#note scaffold: review every ??? -- concrete #link lines are inferred by leaf-name+type');

    // (2) One rule per VALID-TARGET To path (sorted). A To path that fails
    // IsValidTarget (read-only on either surface; wrong member_kind/visibility
    // for the DFM surface) is skipped entirely -- no '#link', no '#default',
    // no '#note' -- it is simply not part of this surface's assignable target
    // set (Task 5).
    for TPath in SortedPaths(ToTree) do
    begin
      if not IsValidTarget(NodeOfPath(ToTree, TPath), Surface) then Continue;
      TType:= TypeOfPath(ToTree, TPath);
      Cands:= FromCandidates(LeafLower(TPath), TType);
      if Length(Cands) = 1 then
        Sb.AppendLine(Format('#link %s <- %s', [TPath, Cands[0]]))
      else if Length(Cands) > 1 then
      begin
        Sb.AppendLine(Format('#link %s <- ???', [TPath]));
        Sb.AppendLine('#note candidates: ' + String.Join(', ', Cands));
      end
      else
        Sb.AppendLine(Format('#default %s = ???', [TPath]));
    end;

    // (3) DROPPED note per From path with no compatible To target (sorted).
    for FPath in SortedPaths(FromTree) do
    begin
      FType:= TypeOfPath(FromTree, FPath);
      if not ToHasCounterpart(LeafLower(FPath), FType) then
        Sb.AppendLine(Format('#note DROPPED %s (no T target)', [FPath]));
    end;

    OutText:= Sb.ToString;
  finally
    Sb.Free;
  end;

  if AArgs.Output <> '' then
  begin
    // ASCII / CRLF file (rules DSL is strict 7-bit ASCII). AppendLine already
    // emitted platform CRLFs on Windows; ANSI keeps the bytes 1:1.
    TFile.WriteAllText(AArgs.Output, OutText, TEncoding.ANSI);
    Writeln('Wrote ', AArgs.Output);
  end
  else
    Write(OutText); // already CRLF-terminated per line

  Result:= 0;
end; // function

/// <summary>drag-lint convert-apply --unit F.pas --rules FILE --db PATH [--db ...]
/// [--only Name1,Name2,...] [--apply] [--no-backup] -- Track 3 sub-project B: locates the
/// component instances to convert in the sibling .dfm and rewrites all five surfaces
/// (#1 declaration retype, #2 uses-add, #3 .dfm re-emit, #4 property/event access-site
/// rewrite via ref-gap G's member-access index, #5 runtime-creator retype + TODO markers).
/// Without --apply this
/// is DRY-RUN ONLY (RenderDryRun preview, writes nothing). With --apply (Task 4) it actually writes:
/// a freshness guard runs first (CheckFreshness -- refuses on stale/unindexed F or T
/// types), then each touched file is backed up to its next-free NAME.EXT.BCK&lt;n&gt;
/// (DRagLint.Convert.Backup.BackupFiles) and a recovery.txt block is appended BEFORE the
/// conversion write (WriteRecoveryRecord), then the edits are written
/// (TTextEditApplier.Apply(..., AWriteBackups:=False) -- our own backup layer already
/// backed up, so the applier must NOT also write its own .bak), then the converted .pas
/// is stamped with a provenance comment (PrependConvertComment). --no-backup skips the
/// backup/recovery/comment steps entirely (still converts). --unit reuses GhostUnit (same
/// --unit -> non-document-command routing as ghost-check; see ParseArgs) and --only reuses
/// OnlySections (same comma-split TArray&lt;string&gt; already used by `index --all`).</summary>
/// <param name="AArgs">GhostUnit=--unit (the .pas file to convert); RulesFile=--rules;
/// OnlySections=--only (comma-split instance-name allow-list); Apply=--apply; NoBackup=
/// --no-backup; DbPath/DbPaths=index(es).</param>
/// <returns>0 on success (dry-run preview shown, or --apply wrote successfully); 1 on a
/// hard error (missing .dfm when rules need it, invalid rules, BuildApplyPlan Ok=False, or
/// --apply refused by the freshness guard); 2 on bad args (missing --unit/--rules, file not
/// found, no readable db).</returns>
/// <remarks>Resolves the sibling .dfm as the same base name + '.dfm' next to --unit;
/// missing .dfm is a hard error (exit 1) since every #convert rule needs DFM instances to
/// locate. Rules are read + parsed + validated (ValidateConversionRules) against the
/// From/To property trees BEFORE BuildApplyPlan runs -- a rules error refuses (exit 1)
/// rather than attempting a plan from a broken rule set. From/To trees are built the same
/// first-DB-that-resolves-wins way as convert-validate/convert-scaffold/convert-reemit
/// (TreeFor local fn, copied verbatim). Every readable --db is opened up front into Stores
/// (not just the first); the freshness guard (CheckFreshness) and BuildApplyPlan both
/// resolve From/To TYPES across ALL of Stores (first-that-resolves-wins), while unit/
/// instance-scoped lookups use whichever store actually has --unit/the .dfm indexed -- the
/// From type, To type, and the form's own instances may each live in a DIFFERENT --db. On
/// dry-run a stale/unindexed type only WARNS (the preview still renders), on --apply it
/// REFUSES (exit 1) before any write is attempted.</remarks>
function DoConvertApply(const AArgs: TArgs): Integer;
var
  UnitPas   : string            ;
  DfmPath   : string            ;
  RulesText : string            ;
  Rules     : TConversionRuleSet;
  RuleErrors: TArray<TRuleError>;
  RE        : TRuleError        ;
  FromType  : string            ;
  ToType    : string            ;
  R         : TConversionRule   ;
  FromTree  : TPropTree         ;
  ToTree    : TPropTree         ;
  Opts      : TPropTreeOptions  ;
  Depth     : Integer           ;
  Dbs       : TArray<string>    ;
  Stores    : TArray<ISymbolStore>;
  RoOk      : Boolean           ;
  LDb       : string            ;
  PlanRes   : TApplyResult      ;
  S         : string            ;
  Freshness   : TFreshnessResult;
  TouchedFiles: TList<string>   ;
  TouchedSet  : TDictionary<string, Boolean>;
  Ed          : TTextEdit       ;
  Timestamp   : string          ;
  Mappings    : TArray<string>  ;

  // Build the property tree for a type qname across the resolved DBs (first DB
  // that resolves it wins). Empty RootType if unresolved / no db. Mirrors
  // DoConvertValidate's TreeFor exactly.
  function TreeFor(const AQName: string): TPropTree;
  var
    Cand: TPropTree;
    LDb2: string   ;
  begin
    Result:= Default(TPropTree);
    if AQName = '' then Exit;
    for LDb2 in Dbs do
    begin
      if not TFile.Exists(LDb2) then Continue;
      var RoOk2: Boolean;
      var CandStore: ISymbolStore:= OpenReadOnlyStore(LDb2, RoOk2);
      if not RoOk2 then Continue;
      Cand:= BuildPropTree(CandStore, AQName, Opts);
      if Cand.RootType <> '' then Exit(Cand);
    end;
  end;

begin
  if (AArgs.GhostUnit = '') or (AArgs.RulesFile = '') then
  begin
    Writeln('Usage: drag-lint convert-apply --unit <F.pas> --rules <file> --db PATH [--db ...] [--only Name1,Name2,...] [--apply]');
    Exit(2);
  end;
  UnitPas:= AArgs.GhostUnit;
  if not TFile.Exists(UnitPas) then
  begin Writeln(Format('ERROR: unit not found: %s', [UnitPas])); Exit(2); end;
  if not TFile.Exists(AArgs.RulesFile) then
  begin Writeln(Format('ERROR: rules file not found: %s', [AArgs.RulesFile])); Exit(2); end;

  // Sibling .dfm: same base name + '.dfm', same folder as --unit.
  DfmPath:= TPath.ChangeExtension(UnitPas, '.dfm');
  if not TFile.Exists(DfmPath) then
  begin Writeln(Format('ERROR: sibling .dfm not found: %s (every #convert rule needs .dfm instances to locate)', [DfmPath])); Exit(1); end;

  try
    RulesText:= TFile.ReadAllText(AArgs.RulesFile);
  except
    on Ex: Exception do
    begin Writeln(Format('ERROR: cannot read rules file: %s (%s)', [AArgs.RulesFile, Ex.Message])); Exit(2); end;
  end;
  Rules:= ParseConversionRules(RulesText);

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.'); Exit(2); end;

  Depth:= AArgs.Depth;
  if Depth <= 0 then Depth:= 6;
  Opts.Depth       := Depth;
  Opts.ToPersistent:= AArgs.ToPersistent;

  // Every #convert rule's FromType/ToType gets its property tree built so
  // ValidateConversionRules can check #link/#default paths -- same as
  // convert-validate, just driven from the rules file's own #convert headers
  // rather than --from/--to (convert-apply has neither).
  FromType:= ''; ToType:= '';
  for R in Rules.Rules do
    if R.Kind = rkConvert then begin FromType:= R.FromType; ToType:= R.ToType; Break; end;
  FromTree:= TreeFor(FromType);
  ToTree  := TreeFor(ToType);

  RuleErrors:= ValidateConversionRules(Rules, FromTree, ToTree);
  if Length(RuleErrors) > 0 then
  begin
    Writeln('ERROR: conversion rules failed validation:');
    for RE in RuleErrors do Writeln(Format('  line %d: %s', [RE.LineNo, RE.Message]));
    Exit(1);
  end;

  // Open EVERY readable --db up front (not just the first) -- Bug 2: the
  // From type, To type, and the form's own instances may each live in a
  // DIFFERENT --db, so both the freshness guard and BuildApplyPlan need
  // cross-db type resolution (first-db-that-resolves-wins, same convention
  // as the rule-validation TreeFor above), while unit/instance-scoped
  // lookups use whichever store actually has --unit/the .dfm indexed.
  var StoresList: TList<ISymbolStore>:= TList<ISymbolStore>.Create;
  try
    for LDb in Dbs do
    begin
      if not TFile.Exists(LDb) then Continue;
      var St: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
      if not RoOk then Continue;
      StoresList.Add(St);
    end;
    Stores:= StoresList.ToArray;
  finally
    StoresList.Free;
  end;
  if Length(Stores) = 0 then begin Writeln('ERROR: no readable drag-lint index among --db path(s)'); Exit(2); end;

  // Freshness guard (Task 4): before trusting the index-derived property
  // trees, verify the F and T types are BOTH indexed and current. Covers two
  // failure modes -- "stale" (indexed but the source file changed on disk
  // since) and "not indexed at all" (ResolveClassQName-equivalent lookup
  // fails, which would otherwise silently hand BuildPropTree an empty tree).
  // dry-run: WARN and continue (so a user can still preview a plan while
  // reindexing). --apply: REFUSE outright -- writing a conversion built from
  // a stale/empty property tree could silently drop or mis-map properties.
  Freshness:= CheckFreshness(Stores, Rules);
  if not Freshness.Fresh then
  begin
    if AArgs.Apply then
    begin
      Writeln('ERROR: freshness guard failed -- refusing to --apply:');
      for S in Freshness.Reasons do Writeln('  ' + S);
      Exit(1);
    end
    else
    begin
      Writeln('WARNING: freshness guard failed (dry-run only, would refuse on --apply):');
      for S in Freshness.Reasons do Writeln('  ' + S);
    end;
  end;

  PlanRes:= BuildApplyPlan(Stores, UnitPas, DfmPath, Rules, AArgs.OnlySections);
  if not PlanRes.Ok then
  begin Writeln('ERROR: ' + PlanRes.Error); Exit(1); end;

  if not AArgs.Apply then
  begin
    // DRY-RUN: writes nothing.
    Writeln(TTextEditApplier.RenderDryRun(PlanRes.Edits));
    Writeln('');
    Writeln(Format('convert-apply: %d instance(s) converted, %d edit(s) planned', [Length(PlanRes.Report.Converted), Length(PlanRes.Edits)]));
    for S in PlanRes.Report.Converted do Writeln('  ' + S);
    if Length(PlanRes.Report.AccessSites) > 0 then
    begin
      Writeln('AccessSites:');
      for S in PlanRes.Report.AccessSites do Writeln('  ' + S);
    end;
    if Length(PlanRes.Report.Todos) > 0 then
    begin
      Writeln('Todos:');
      for S in PlanRes.Report.Todos do Writeln('  ' + S);
    end;
    if Length(PlanRes.Report.Warnings) > 0 then
    begin
      Writeln('Warnings:');
      for S in PlanRes.Report.Warnings do Writeln('  ' + S);
    end;
    Exit(0);
  end;

  // -- --apply: actually write. --------------------------------------------
  // 1. Collect the distinct touched file paths from the edit set.
  TouchedFiles:= TList<string>.Create;
  TouchedSet  := TDictionary<string, Boolean>.Create;
  try
    for Ed in PlanRes.Edits do
      if not TouchedSet.ContainsKey(Ed.FilePath) then
      begin TouchedSet.Add(Ed.FilePath, True); TouchedFiles.Add(Ed.FilePath); end;

    Timestamp:= FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);

    // 2. Backup + recovery record BEFORE any conversion write. Writing the
    // recovery record first means a crash between here and the actual write
    // still leaves a complete recovery map alongside the untouched .BCK files.
    if not AArgs.NoBackup then
    begin
      BackupFiles(TouchedFiles.ToArray, Mappings);
      WriteRecoveryRecord(ExtractFileDir(UnitPas), Timestamp, AArgs.RulesFile, Mappings);
    end;

    // 3. Perform the conversion write. AWriteBackups=False: our backup layer
    // (step 2) already backed up every touched file -- letting the applier
    // ALSO write its own .bak would double-backup.
    TTextEditApplier.Apply(PlanRes.Edits, False);

    // 4. Stamp the converted .pas with a provenance comment (skipped along
    // with backups under --no-backup, per the brief: keep --no-backup simple).
    if not AArgs.NoBackup then
      PrependConvertComment(UnitPas, Timestamp, AArgs.RulesFile, Mappings);
  finally
    TouchedFiles.Free;
    TouchedSet.Free;
  end;

  Writeln(Format('convert-apply: %d instance(s) converted, %d edit(s) applied', [Length(PlanRes.Report.Converted), Length(PlanRes.Edits)]));
  for S in PlanRes.Report.Converted do Writeln('  ' + S);
  if Length(PlanRes.Report.AccessSites) > 0 then
  begin
    Writeln('AccessSites:');
    for S in PlanRes.Report.AccessSites do Writeln('  ' + S);
  end;
  if Length(PlanRes.Report.Todos) > 0 then
  begin
    Writeln('Todos:');
    for S in PlanRes.Report.Todos do Writeln('  ' + S);
  end;
  if Length(PlanRes.Report.Warnings) > 0 then
  begin
    Writeln('Warnings:');
    for S in PlanRes.Report.Warnings do Writeln('  ' + S);
  end;

  Result:= 0;
end; // function

/// <summary>drag-lint reverse-calltree --qname X [--direction callers|callees] [--depth N]
/// [--format text|json|dot|mermaid] [--json] --db PATH ... -- the N-deep call tree rooted
/// at X, with call sites (unit:line) and cycle markers. --direction callers (default,
/// back-compat with the original REVERSE tree) walks UPWARD via BuildReverseCallTree
/// (FindResolvedCallers): who calls X, who calls them. --direction callees walks
/// DOWNWARD via BuildForwardCallTree (GetCallEdgesFromSymbol): what X calls, what those
/// call. AArgs.Direction is shared with the callgraph verb, whose parser default is
/// empty (per-verb default applied locally, NOT a shared literal -- see ParseArgs);
/// an empty/absent/invalid --direction here resolves to 'callers', never callgraph's
/// 'callees' default. Both directions emit the SAME schema reverse-calltree/1 (root/
/// summary, per-node qname/site/file/line/cycle under the "callers" JSON key regardless
/// of direction). Text is an indented tree (2 spaces/level); --format dot|mermaid emit
/// a chart. With multiple --db, the first DB that resolves the qname is used (ids are
/// per-DB).</summary>
/// <param name="AArgs">QName=root, Direction=callers|callees (default callers),
/// Depth=tree depth (default 3), Format/AsJson=output, DbPath/DbPaths=index(es).</param>
/// <returns>0 ok; 1 qname unresolved in every DB; 2 usage error / no readable db.</returns>
function DoReverseCallTree(const AArgs: TArgs): Integer;
var
  Dbs    : TArray<string>;
  Db     : string        ;
  Store  : ISymbolStore  ;
  RootIds: TArray<Int64> ;
  Depth  : Integer       ;
  Fmt    : string        ;
  Dir    : string        ;
  Rid    : Int64         ;
  Trees  : TList<TRCallTree>;
  Opts   : TRCallOptions ;

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

  procedure RenderNodeText(const ANode: TRCallNode; const AIndent: string; ALines: TStrings);
  var
    Line : string;
    Kid  : TRCallNode;
  begin
    Line:= AIndent + ANode.QName;
    if ANode.Site <> '' then Line:= Line + Format(' [%s]', [ANode.Site]);
    if ANode.Cycle then Line:= Line + ' (cycle)';
    ALines.Add(Line);
    if ANode.Cycle then Exit; // already expanded elsewhere -- marker only, no recursion
    for Kid in ANode.Callers do
      RenderNodeText(Kid, AIndent + '  ', ALines);
  end; // procedure

  function BuildNodeJson(const ANode: TRCallNode): TJSONObject;
  var
    JKids: TJSONArray;
    Kid  : TRCallNode ;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('qname', ANode.QName);
    Result.AddPair('site' , ANode.Site );
    Result.AddPair('file' , ANode.SiteFile);
    Result.AddPair('line' , TJSONNumber.Create(ANode.SiteLine));
    Result.AddPair('cycle', TJSONBool.Create(ANode.Cycle));
    JKids:= TJSONArray.Create;
    for Kid in ANode.Callers do JKids.AddElement(BuildNodeJson(Kid));
    Result.AddPair('callers', JKids);
  end; // function

  function BuildSummaryJson(const ASummary: TRCallSummary): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('node_count'      , TJSONNumber.Create(ASummary.NodeCount      ));
    Result.AddPair('max_depth_reached', TJSONNumber.Create(ASummary.MaxDepthReached));
    Result.AddPair('cycle_count'     , TJSONNumber.Create(ASummary.CycleCount     ));
    Result.AddPair('truncated'       , TJSONBool.Create(ASummary.Truncated        ));
  end; // function

  function BuildTreeJson(const ATree: TRCallTree): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('schema' , 'reverse-calltree/1'    );
    Result.AddPair('root'   , BuildNodeJson(ATree.Root));
    Result.AddPair('summary', BuildSummaryJson(ATree.Summary));
  end; // function

  procedure RenderNodeChart(const ANode: TRCallNode; ABuf: TStringBuilder; AIsDot: Boolean);
  var
    Kid: TRCallNode;
  begin
    for Kid in ANode.Callers do
    begin
      if AIsDot then ABuf.AppendLine(Format('  "%s" -> "%s";', [Kid.QName, ANode.QName]))
      else ABuf.AppendLine(Format('  %s --> %s', [SanitizeId(Kid.QName), SanitizeId(ANode.QName)]));
      if not Kid.Cycle then RenderNodeChart(Kid, ABuf, AIsDot);
    end;
  end; // procedure

begin
  if AArgs.QName = '' then
  begin Writeln('Usage: drag-lint reverse-calltree --qname X [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH'); Exit(2); end;

  Fmt:= LowerCase(Trim(AArgs.Format));

  Depth:= AArgs.Depth;
  if Depth < 0 then Depth:= 0;

  { --direction is SHARED with callgraph (TArgs.Direction), whose parser
    default is empty (per-verb default applied here, not globally -- see
    ParseArgs). reverse-calltree's historic behaviour is the UPWARD callers
    tree, so empty/absent/invalid --direction must resolve to 'callers', NOT
    callgraph's 'callees' default; only an explicit 'callees' switches this
    verb to the DOWNWARD tree via BuildForwardCallTree. }
  Dir:= LowerCase(Trim(AArgs.Direction));
  if (Dir <> 'callers') and (Dir <> 'callees') then Dir:= 'callers';

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.'); Exit(2); end;

  // Multi-db root resolution: use the FIRST db whose ResolveEndpointIds(qname)
  // is non-empty (mirrors DoHover's multi-db precedent). Exit 1 only if NO db
  // resolves the qname; exit 2 if no --db is even readable.
  Store  := nil;
  RootIds:= nil;
  for Db in Dbs do
  begin
    if not TFile.Exists(Db) then Continue;
    var RoOk: Boolean;
    var CandidateStore: ISymbolStore:= OpenReadOnlyStore(Db, RoOk);
    if not RoOk then Continue;
    var CandidateIds: TArray<Int64>:= ResolveEndpointIds(CandidateStore, AArgs.QName);
    if Length(CandidateIds) > 0 then
    begin
      Store  := CandidateStore;
      RootIds:= CandidateIds;
      Break;
    end;
  end;
  if Store = nil then begin Writeln('ERROR: no readable drag-lint index among --db path(s)'); Exit(2); end;
  if Length(RootIds) = 0 then begin Writeln(Format('symbol not found: %s', [AArgs.QName])); Exit(1); end;

  Opts.Depth:= Depth;

  Trees:= TList<TRCallTree>.Create;
  try
    for Rid in RootIds do
      if Dir = 'callees' then
        Trees.Add(BuildForwardCallTree(Store, Rid, Opts))
      else
        Trees.Add(BuildReverseCallTree(Store, Rid, Opts));

    if (Fmt = 'dot') or (Fmt = 'mermaid') then
    begin
      var Buf: TStringBuilder:= TStringBuilder.Create;
      try
        if Fmt = 'dot' then
        begin
          Buf.AppendLine('// Generated by drag-lint reverse-calltree');
          Buf.AppendLine('digraph DragLintReverseCallTree {');
          Buf.AppendLine('  rankdir=LR;');
          Buf.AppendLine('  node [shape=box, style=filled, fillcolor="#eef"];');
          Buf.AppendLine('  edge [color="#888"];');
        end
        else
        begin
          Buf.AppendLine('%% Generated by drag-lint reverse-calltree');
          Buf.AppendLine('graph LR');
        end;
        for var T in Trees do RenderNodeChart(T.Root, Buf, Fmt = 'dot');
        if Fmt = 'dot' then Buf.AppendLine('}');
        Writeln(Buf.ToString);
      finally
        Buf.Free;
      end;
    end
    else if (Fmt = 'json') or ((Fmt = '') and AArgs.AsJson) then
    begin
      var JRoots: TJSONArray:= TJSONArray.Create;
      try
        for var T in Trees do JRoots.AddElement(BuildTreeJson(T));
        // A single root prints the bare object; multiple (overloads) print an array.
        if JRoots.Count = 1 then Writeln((JRoots.Items[0] as TJSONObject).Format(2))
        else Writeln(JRoots.Format(2));
      finally
        JRoots.Free;
      end;
    end
    else // text (default, or explicit --format text)
    begin
      var Lines: TStringList:= TStringList.Create;
      try
        for var T in Trees do RenderNodeText(T.Root, '', Lines);
        Writeln(Lines.Text);
      finally
        Lines.Free;
      end;
    end;
  finally
    Trees.Free;
  end; // try
  Result:= 0;
end; // function

/// <summary>drag-lint butterfly --qname X [--depth N] [--format dot|mermaid|text|json]
/// [--output F] --db PATH [--db ...] -- Track 5.3 slice (Batch H2): composes a
/// symbol's CALLERS (upward wing, via BuildReverseCallTree) and CALLEES (downward
/// wing, via BuildForwardCallTree) into one "butterfly" chart, the static-export
/// counterpart to the in-IDE butterfly tab (Batch F). No new engine -- both trees
/// are the shipped TRCallTree/TRCallNode shape from DRagLint.Report.RCallTree;
/// composition works because both trees share the same root qname, so a chart
/// renderer that dedupes nodes by qname naturally attaches both wings to one
/// center node. Multi-db root resolution mirrors DoReverseCallTree exactly: the
/// first db whose ResolveEndpointIds(qname) is non-empty wins. --depth applies to
/// BOTH wings. dot/mermaid: callers render `caller -> X` (existing reverse-tree
/// orientation); callees render `X -> callee` (the REVERSED orientation, via the
/// AReverseEdges parameter added to the local RenderNodeChart). Root node is
/// styled distinctly in dot output (bold, `#ffd` fill) so the chart's center is
/// obvious. text: two headed sections (CALLERS upward / CALLEES downward), each
/// via RenderNodeText. json: schema "butterfly/1" wrapping the two full
/// reverse-calltree/1 tree objects under "callers"/"callees". Read-only.</summary>
/// <param name="AArgs">QName=root (required), Depth=tree depth for both wings
/// (default 3, <0 clamped to 0), Format/AsJson=output (default dot),
/// Output=optional file path (else stdout), DbPath/DbPaths=index(es).</param>
/// <returns>0 ok (even with zero callers and/or zero callees -- still a valid
/// 1-node chart); 1 qname unresolved in every DB; 2 usage error / no readable db.</returns>
function DoButterfly(const AArgs: TArgs): Integer;
var
  Dbs      : TArray<string>;
  Db       : string        ;
  Store    : ISymbolStore  ;
  RootIds  : TArray<Int64> ;
  Depth    : Integer       ;
  Fmt      : string        ;
  Opts     : TRCallOptions ;
  ReverseTree: TRCallTree  ;
  ForwardTree: TRCallTree  ;

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

  procedure RenderNodeText(const ANode: TRCallNode; const AIndent: string; ALines: TStrings);
  var
    Line : string;
    Kid  : TRCallNode;
  begin
    Line:= AIndent + ANode.QName;
    if ANode.Site <> '' then Line:= Line + Format(' [%s]', [ANode.Site]);
    if ANode.Cycle then Line:= Line + ' (cycle)';
    ALines.Add(Line);
    if ANode.Cycle then Exit; // already expanded elsewhere -- marker only, no recursion
    for Kid in ANode.Callers do
      RenderNodeText(Kid, AIndent + '  ', ALines);
  end; // procedure

  function BuildNodeJson(const ANode: TRCallNode): TJSONObject;
  var
    JKids: TJSONArray;
    Kid  : TRCallNode ;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('qname', ANode.QName);
    Result.AddPair('site' , ANode.Site );
    Result.AddPair('file' , ANode.SiteFile);
    Result.AddPair('line' , TJSONNumber.Create(ANode.SiteLine));
    Result.AddPair('cycle', TJSONBool.Create(ANode.Cycle));
    JKids:= TJSONArray.Create;
    for Kid in ANode.Callers do JKids.AddElement(BuildNodeJson(Kid));
    Result.AddPair('callers', JKids);
  end; // function

  function BuildSummaryJson(const ASummary: TRCallSummary): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('node_count'      , TJSONNumber.Create(ASummary.NodeCount      ));
    Result.AddPair('max_depth_reached', TJSONNumber.Create(ASummary.MaxDepthReached));
    Result.AddPair('cycle_count'     , TJSONNumber.Create(ASummary.CycleCount     ));
    Result.AddPair('truncated'       , TJSONBool.Create(ASummary.Truncated        ));
  end; // function

  function BuildTreeJson(const ATree: TRCallTree): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('schema' , 'reverse-calltree/1'    );
    Result.AddPair('root'   , BuildNodeJson(ATree.Root));
    Result.AddPair('summary', BuildSummaryJson(ATree.Summary));
  end; // function

  // AReverseEdges=False: caller orientation (Kid -> ANode), the existing
  // reverse-tree emit direction, used for the CALLERS wing. AReverseEdges=True:
  // emits the OPPOSITE (ANode -> Kid), used for the CALLEES wing (ANode.Callers
  // holds the callees for a forward tree; field name kept for record reuse --
  // see TRCallNode doc comment).
  procedure RenderNodeChart(const ANode: TRCallNode; ABuf: TStringBuilder; AIsDot: Boolean; AReverseEdges: Boolean);
  var
    Kid: TRCallNode;
  begin
    for Kid in ANode.Callers do
    begin
      if AIsDot then
      begin
        if AReverseEdges then ABuf.AppendLine(Format('  "%s" -> "%s";', [ANode.QName, Kid.QName]))
        else ABuf.AppendLine(Format('  "%s" -> "%s";', [Kid.QName, ANode.QName]));
      end
      else
      begin
        if AReverseEdges then ABuf.AppendLine(Format('  %s --> %s', [SanitizeId(ANode.QName), SanitizeId(Kid.QName)]))
        else ABuf.AppendLine(Format('  %s --> %s', [SanitizeId(Kid.QName), SanitizeId(ANode.QName)]));
      end;
      if not Kid.Cycle then RenderNodeChart(Kid, ABuf, AIsDot, AReverseEdges);
    end;
  end; // procedure

begin
  if AArgs.QName = '' then
  begin Writeln('Usage: drag-lint butterfly --qname X [--depth N] [--format dot|mermaid|text|json] [--output F] --db PATH'); Exit(2); end;

  Fmt:= LowerCase(Trim(AArgs.Format));
  if Fmt = '' then Fmt:= 'dot'; // chart verb -- default dot (unlike reverse-calltree's text default)

  Depth:= AArgs.Depth;
  if Depth < 0 then Depth:= 0;

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.'); Exit(2); end;

  // Multi-db root resolution: first db whose ResolveEndpointIds(qname) is
  // non-empty wins. AnyDbOpened tracks whether at least one --db path opened
  // read-only successfully, INDEPENDENT of whether the qname resolved in it --
  // this distinguishes "no readable db at all" (exit 2) from "every db opened
  // fine but none of them declares this qname" (exit 1). NOTE: DoReverseCallTree's
  // equivalent loop lacks this distinction (Store only gets assigned on a qname
  // match, so an all-readable-but-unresolved-qname run there falls through to
  // the SAME "no readable index" exit-2 message instead of exit 1 -- a
  // pre-existing bug, not fixed here since it is out of scope for this verb).
  Store  := nil;
  RootIds:= nil;
  var AnyDbOpened: Boolean:= False;
  for Db in Dbs do
  begin
    if not TFile.Exists(Db) then Continue;
    var RoOk: Boolean;
    var CandidateStore: ISymbolStore:= OpenReadOnlyStore(Db, RoOk);
    if not RoOk then Continue;
    AnyDbOpened:= True;
    var CandidateIds: TArray<Int64>:= ResolveEndpointIds(CandidateStore, AArgs.QName);
    if Length(CandidateIds) > 0 then
    begin
      Store  := CandidateStore;
      RootIds:= CandidateIds;
      Break;
    end;
  end;
  if not AnyDbOpened then begin Writeln('ERROR: no readable drag-lint index among --db path(s)'); Exit(2); end;
  if Store = nil then begin Writeln(Format('symbol not found: %s', [AArgs.QName])); Exit(1); end;

  Opts.Depth:= Depth;

  // Overloads: butterfly composes a SINGLE center node, so use the first
  // resolved root id (matches the common case; overload fan-out is out of
  // scope for a v1 chart verb -- reverse-calltree's multi-root loop is not
  // reused here because the composed chart has exactly one center).
  ReverseTree:= BuildReverseCallTree(Store, RootIds[0], Opts);
  ForwardTree:= BuildForwardCallTree(Store, RootIds[0], Opts);

  if (Fmt = 'dot') or (Fmt = 'mermaid') then
  begin
    var Buf: TStringBuilder:= TStringBuilder.Create;
    try
      if Fmt = 'dot' then
      begin
        Buf.AppendLine('// Generated by drag-lint butterfly');
        Buf.AppendLine('digraph DragLintButterfly {');
        Buf.AppendLine('  rankdir=LR;');
        Buf.AppendLine('  node [shape=box, style=filled, fillcolor="#eef"];');
        Buf.AppendLine('  edge [color="#888"];');
        Buf.AppendLine(Format('  "%s" [fillcolor="#ffd", style="filled,bold"];', [ReverseTree.Root.QName]));
      end
      else
      begin
        Buf.AppendLine('%% Generated by drag-lint butterfly');
        Buf.AppendLine('graph LR');
      end;
      RenderNodeChart(ReverseTree.Root, Buf, Fmt = 'dot', False); // callers wing: caller -> X
      RenderNodeChart(ForwardTree.Root, Buf, Fmt = 'dot', True);  // callees wing: X -> callee
      if Fmt = 'dot' then Buf.AppendLine('}');

      if AArgs.Output <> '' then begin TFile.WriteAllText(AArgs.Output, Buf.ToString, TEncoding.UTF8); Writeln('Wrote ', AArgs.Output); end
      else Writeln(Buf.ToString);
    finally
      Buf.Free;
    end;
  end
  else if (Fmt = 'json') or AArgs.AsJson then
  begin
    var JOut: TJSONObject:= TJSONObject.Create;
    try
      JOut.AddPair('schema' , 'butterfly/1'    );
      JOut.AddPair('qname'  , ReverseTree.Root.QName);
      JOut.AddPair('callers', BuildTreeJson(ReverseTree));
      JOut.AddPair('callees', BuildTreeJson(ForwardTree));
      var OutStr: string:= JOut.Format(2);
      if AArgs.Output <> '' then begin TFile.WriteAllText(AArgs.Output, OutStr, TEncoding.UTF8); Writeln('Wrote ', AArgs.Output); end
      else Writeln(OutStr);
    finally
      JOut.Free;
    end;
  end
  else // text (default explicit --format text)
  begin
    var Lines: TStringList:= TStringList.Create;
    try
      Lines.Add('CALLERS (upward):');
      RenderNodeText(ReverseTree.Root, '  ', Lines);
      Lines.Add('CALLEES (downward):');
      RenderNodeText(ForwardTree.Root, '  ', Lines);
      if AArgs.Output <> '' then begin TFile.WriteAllText(AArgs.Output, Lines.Text, TEncoding.UTF8); Writeln('Wrote ', AArgs.Output); end
      else Writeln(Lines.Text);
    finally
      Lines.Free;
    end;
  end;
  Result:= 0;
end; // function

/// <summary>v14 (D5 T12): drag-lint purge-locals --db PATH [--json] -- the SIZE
/// ESCAPE HATCH. Deletes every skLocalVar/skParam symbol (kind IN 'local_var',
/// 'param'), then VACUUMs to reclaim the freed pages, and reports how many rows
/// were removed plus the DB file size before/after. Once ResolveCallTargets has
/// populated call_edges, these numerous per-local / per-param symbols have done
/// their job (they let the resolver type call-site receivers), so purging them
/// slims the index. The resolved CALL GRAPH is unchanged: call_edges references
/// call TARGETS (methods) and receiver TYPES (classes), never a local/param, so
/// no edge can cascade-delete. Requires an explicit --db (it MUTATES a specific
/// index -- never purges across an auto-selected DB set). NOT wired into any
/// auto-index path: a reindex re-emits locals/params and rebuilds call_edges, so
/// this is a manual, point-in-time slim only, correctly re-inflated on the next
/// full index. Idempotent: a second run removes 0 rows and still exits 0.</summary>
/// <param name="AArgs">Parsed CLI args; DbPath is the index to purge; AsJson picks JSON output.</param>
/// <returns>0 on success (including the idempotent 0-removed second run); 2 on
/// usage error / missing --db / missing db file.</returns>
function DoPurgeLocals(const AArgs: TArgs): Integer;
var
  Store     : ISymbolStore;
  Removed   : Int64        ;
  SizeBefore: Int64        ;
  SizeAfter : Int64        ;
begin
  if AArgs.DbPath = '' then begin Writeln('ERROR: purge-locals needs an explicit --db <db>'); Exit(2); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;

  SizeBefore:= TFile.GetSize(AArgs.DbPath);
  { Read-WRITE open (purge MUTATES) -- same path as index/rename/safe-delete, NOT
    the query_only OpenReadOnlyStore used by read verbs. Migrate ensures the
    schema (incl. the symbols.kind values) is current before we touch it. }
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath); Store.Migrate;
  Removed:= Store.PurgeLocals;
  Store:= nil; { close the connection so the VACUUM's file resize is flushed before we stat }
  SizeAfter:= TFile.GetSize(AArgs.DbPath);

  if AArgs.AsJson then
  begin
    var JO: TJSONObject:= TJSONObject.Create;
    try
      JO.AddPair('db'         , AArgs.DbPath                      );
      JO.AddPair('removed'    , TJSONNumber.Create(Removed   )    );
      JO.AddPair('size_before', TJSONNumber.Create(SizeBefore)    );
      JO.AddPair('size_after' , TJSONNumber.Create(SizeAfter )    );
      Writeln(JO.Format(2));
    finally JO.Free; end;
  end
  else
    Writeln(Format('purge-locals: removed %d local/param symbol(s); db size %d -> %d bytes',
      [Removed, SizeBefore, SizeAfter]));
  Result:= 0;
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
  if Target = '' then begin Writeln('Usage: drag-lint format <file> [--yadf-path PATH]'); Exit (2 ); end;
  if not FileExists(Target) then begin Writeln(Format('File not found: %s', [Target])); Exit(2); end;
  Res:= TYadfFormatter.Format(Target, AArgs.YadfPath);
  if not Res.Success then begin Writeln(Format('YADF format failed (exit %d):'#13#10'%s', [Res.ExitCode, Res.StdoutText])); Exit(1); end;
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
    if not CreateProcessW(nil, CmdLineBuf, nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then begin Writeln('ERROR: failed to spawn: ', ACmd); Result:= -1; Exit; end;
    // Drain stdout/stderr while child runs
    CloseHandle(WritePipe);
    WritePipe:= INVALID_HANDLE_VALUE;
    repeat
      if ReadFile(ReadPipe, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then begin Buffer[BytesRead]:= #0; Write(AnsiString(Buffer)); end
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
    else begin Writeln('ERROR: .drag-lint-workspace.json not found. ' + 'Use --config <path> or run from a workspace root.'); Exit(2); end;
  end;
  if not TFile.Exists(CfgPath) then begin Writeln('ERROR: workspace config not found: ', CfgPath); Exit(2); end;

  // --- workspace add ---
  if AArgs.SubCommand = 'add' then
  begin
    if AArgs.Target = '' then begin Writeln('Usage: drag-lint workspace add <projfile> [--config PATH]'); Exit (2 ); end;
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
    if ReadPipe <> INVALID_HANDLE_VALUE then begin CloseHandle(ReadPipe); ReadPipe:= INVALID_HANDLE_VALUE; end;
    if WritePipe <> INVALID_HANDLE_VALUE then begin CloseHandle(WritePipe); WritePipe:= INVALID_HANDLE_VALUE; end;
    if EC = 0 then Inc(SuccessCount)
    else Writeln(Format('WARNING: index returned exit code %d for: %s', [EC, P.Path]));
  end; // for

  Writeln('');
  Writeln(Format('Done: %d/%d projects indexed into %s', [SuccessCount, ProjectCount, SharedDbPath]));

  if SuccessCount = ProjectCount then Result:= 0
  else Result:= 1;
end; // begin

/// <summary>Implements the forms-csv CLI command: generates a navigation-map CSV
/// for a project index and writes it to --out or stdout. Multi-DB: when the
/// caller supplies no --db, falls back through ResolveConsumerDbs (manifest /
/// platform resolution) so forms-csv sees the same DB set as query/lsp/serve;
/// the first resolved path is primary (drives enumeration), the rest widen the
/// caller-search scope so cross-DB launch chains (e.g. CLIENT -> COMMON) are
/// not misreported as dead.</summary>
function DoFormsCsv(const AArgs: TArgs): Integer;
var
  DbPaths: TArray<string>;
  Csv    : string;
  P      : string;
begin
  DbPaths:= ResolveConsumerDbs(AArgs);
  if Length(DbPaths) = 0 then begin Writeln(ErrOutput, 'forms-csv: need --db <index.sqlite>'); Exit(2); end;
  for P in DbPaths do
    if not TFile.Exists(P) then begin Writeln(ErrOutput, 'forms-csv: db not found: ', P); Exit(2); end;
  try
    Csv:= DRagLint.FormsMap.GenerateFormsCsv(DbPaths, AArgs.ProjectPath, AArgs.RootForm);
  except
    on E: Exception do begin Writeln(ErrOutput, 'forms-csv: ', E.Message); Exit(1); end;
  end;
  if AArgs.Output <> '' then begin TFile.WriteAllText(AArgs.Output, Csv, TEncoding.ANSI); Writeln('forms-csv: wrote ', AArgs.Output); end
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
function DetectPlatformFromDproj(const AManifest: TIndexManifest; const ACwd: string): string;
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
  P1        : Integer              ;
  P2        : Integer              ;
begin
  Result:= '';
  CwdNorm:= IncludeTrailingPathDelimiter( TPath.GetFullPath(ACwd)).ToLower;
  BestLen:= -1;
  BestInc:= '';

  // Find manifest section whose include is the longest ancestor of ACwd.
  Sections:= AManifest.Sections;
  for Sec in Sections do
  begin
    if SameText(Sec.Source, 'registry-libraries') then Continue;
    for IncPath in Sec.Include do
    begin
      IncNorm:= IncludeTrailingPathDelimiter( TPath.GetFullPath(IncPath)).ToLower;
      if CwdNorm.StartsWith(IncNorm) and (Length(IncNorm) > BestLen) then begin BestLen:= Length(IncNorm); BestInc:= IncPath; end;
    end;
  end;

  if BestInc = '' then Exit;

  // Find first .dproj under that include path (top dir first, then recursive).
  try
    DprojFiles:= TDirectory.GetFiles(BestInc, '*.dproj', TSearchOption.soTopDirectoryOnly);
    if Length(DprojFiles) = 0 then DprojFiles:= TDirectory.GetFiles(BestInc, '*.dproj', TSearchOption.soAllDirectories);
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
  if P1 = 0 then P1:= Pos('<platform condition=', Xml.ToLower);
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
  if Length(AArgs.DbPaths) > 0 then begin Result:= AArgs.DbPaths; Exit; end;

  // Try manifest-driven selection.
  try
    EngineDir:= ExtractFilePath(ParamStr(0));
    Manifest:= TManifestIO.Load(EngineDir, GetCurrentDir);

    // Pick platform: CLI --platform > .dproj detection > manifest defaultPlatform.
    if AArgs.CheckPlatform <> '' then Platform:= AArgs.CheckPlatform
    else begin Platform:= DetectPlatformFromDproj(Manifest, GetCurrentDir); if Platform = '' then Platform:= Manifest.Settings.DefaultPlatform; end;

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
      if AArgs.CheckPlatform <> '' then Platform:= AArgs.CheckPlatform
      else begin Platform:= DetectPlatformFromDproj(Manifest, GetCurrentDir); if Platform = '' then Platform:= Manifest.Settings.DefaultPlatform; end;

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
  else begin for P in Paths do Writeln(P); end;

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
  if ConfigPath = '' then begin Writeln(ErrOutput, 'selftest dbselect requires --config <path>'); Exit(2); end;
  if not TFile.Exists(ConfigPath) then begin Writeln(ErrOutput, 'selftest dbselect: config not found: ', ConfigPath); Exit(2); end;

  Platform:= AArgs.CheckPlatform;
  if Platform = '' then begin Writeln(ErrOutput, 'selftest dbselect requires --platform <p>'); Exit(2); end;

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

  if Merged.Settings.CurrentProjectsIndexing = piPerGroup then begin Writeln('MERGE-OK'); Result:= 0; end
  else begin Writeln('MERGE-FAIL: expected piPerGroup but got ', Ord(Merged.Settings.CurrentProjectsIndexing)); Result:= 1; end;
end; // function

// selftest glob: runs all TGlob.Matches / MatchesAny cases.
// Prints GLOB-FAIL: <desc> and exits 1 on first failure; GLOB-OK and 0 on success.
function DoSelfTestGlob: Integer;

  procedure Expect(const ADesc: string; AActual, AExpected: Boolean);
  begin
    if AActual <> AExpected then begin Writeln('GLOB-FAIL: ', ADesc); Halt(1); end;
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
    if AActual <> AExpected then begin Writeln('IGNORE-FAIL: ', ADesc, ' (expected=', BoolToStr(AExpected, True), ' got=', BoolToStr(AActual, True), ')'); Halt(1); end;
  end;

begin
  ProjDir:= AArgs.Path;
  if ProjDir = '' then begin Writeln('IGNORE-FAIL: --dir <proj> required'); Halt (1 ); end;
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
  if AArgs.ProjectPath = '' then begin Writeln('ERROR: selftest closure requires --project <dpr/.dproj>'); Exit (2 ); end;
  ProjResolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    LibRoots:= ProjResolver.ResolveLibraryPaths;
  finally
    ProjResolver.Free;
  end;
  Resolver:= TClosureResolver.Create(LibRoots);
  try
    // PP-Task-10: honour per-config uses-discovery (default ON; --no-preprocess
    // reverts to the all-branch scan). Same profile rule the index verbs use:
    // ProfileFromDproj when the project is a .dproj, else PlatformBuiltins for
    // the platform (default Win64). A .dpr project carries no per-config defines
    // of its own, so it resolves to the platform built-ins.
    var Dproj: string:= '';
    if SameText(ExtractFileExt(AArgs.ProjectPath), '.dproj') then Dproj:= AArgs.ProjectPath;
    Resolver.SetPreprocess(not AArgs.NoPreprocess,
      ResolveIndexProfile(Dproj, AArgs.CheckPlatform, ''));
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
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  FileIds:= Store.GetAllFileIds;
  for Id in FileIds do begin Path:= Store.GetFilePath(Id); if Path <> '' then Writeln(Path); end;
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
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
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
  if ConfigPath = '' then begin Writeln(ErrOutput, 'selftest coverage requires --config <path>'); Exit(2); end;
  if not TFile.Exists(ConfigPath) then begin Writeln(ErrOutput, 'selftest coverage: config not found: ', ConfigPath); Exit(2); end;

  if Length(AArgs.Roots) = 0 then begin Writeln(ErrOutput, 'selftest coverage requires --root <dir>'); Exit(2); end;
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
    if not BuildPlanItem(Item, Docs) then begin Writeln('FAIL recreate: first build failed'); Exit (1 ); end;
    // Create() only connects; Migrate() prepares the count statements (and is
    // idempotent against the already-built schema).
    Store:= TSQLiteSymbolStore.Create(DbPath);
    Store.Migrate;
    Count1:= Store.CountSymbols;
    Store:= nil; // close before second build deletes the file

    if not BuildPlanItem(Item, Docs) then begin Writeln('FAIL recreate: second build failed'); Exit (1 ); end;
    Store:= TSQLiteSymbolStore.Create(DbPath);
    Store.Migrate;
    Count2:= Store.CountSymbols;
    Store:= nil;

    Writeln(Format('recreate: build1=%d build2=%d symbols', [Count1, Count2]));
    if Count1 = 0 then begin Writeln('FAIL recreate: no symbols indexed (parser/setup issue)'); Result:= 1; end
    else if Count1 <> Count2 then begin Writeln(Format('FAIL recreate: symbol count changed on rebuild (%d -> %d)', [Count1, Count2])); Result:= 1; end
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
  Q   : TFDQuery     ;
begin
  Result:= 1;
  Conn:= TFDConnection.Create(nil);
  try
    try
      Conn.DriverName:= 'SQLite';
      Conn.Params.Values['Database']:= ':memory:';
      Conn.Connected:= True;
      Conn.ExecSQL('CREATE VIRTUAL TABLE t USING fts5(x, tokenize=''trigram'')');
      Conn.ExecSQL('INSERT INTO t(rowid, x) VALUES (1, ''Folder not found'')'  );
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= Conn;
        Q.Sql.Text:= 'SELECT rowid FROM t WHERE t MATCH ''older'''; // substring
        Q.Open;
        if (not Q.Eof) and (Q.FieldByName('rowid').AsInteger = 1) then begin Writeln('FTS5+trigram OK'); Result:= 0; end
        else Writeln('FTS5 present but trigram match failed');
      finally
        Q.Free;
      end;
    except
      on E: Exception do Writeln('FTS5 unavailable: ', E.Message);
    end; // try
  finally
    Conn.Free;
  end; // try
end; // function

// --selftest-schema: open --db and print all table/view names from sqlite_master.
function DoSelfTestSchema(const ADbPath: string): Integer;
var
  Conn: TFDConnection;
  Q   : TFDQuery     ;
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
        Q.Sql.Text:= 'SELECT name FROM sqlite_master WHERE type IN (''table'',''view'') ORDER BY name';
        Q.Open;
        while not Q.Eof do begin Write(Q.Fields[0].AsString, ' '); Q.Next; end;
        Writeln;
        Result:= 0;
      finally
        Q.Free;
      end;
    except
      on E: Exception do Writeln('selftest-schema error: ', E.Message);
    end; // try
  finally
    Conn.Free;
  end; // try
end; // function

// Hidden self-test verb (not in help text): exercises the Task 2 store
// methods (ClearCompilerFindingsForFile / SetFileCompiledAt /
// GetFileCompiledAt / GetStaleFileIds) end-to-end against --db.
// Exit 0 iff every assertion below passes; exit 1 on the first failure.
function DoTestStoreFreshness(const AArgs: TArgs): Integer;
var
  Store  : ISymbolStore    ;
  FileIds: TArray<Int64>   ;
  FileId : Int64           ;
  Finding: TCompilerFinding;
  Stale  : TArray<Int64>   ;
begin
  Result:= 1;
  if AArgs.DbPath = '' then begin Writeln('ERROR: test-store-freshness requires --db'); Exit(2); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;

  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  FileIds:= Store.GetAllFileIds;
  if Length(FileIds) = 0 then
  begin
    Writeln('FAIL: test-store-freshness: no files in the index (expected the ' +
      'fixture Empty.pas file to have been indexed already)');
    Exit(1);
  end;
  FileId:= FileIds[0];

  // SetFileCompiledAt / GetFileCompiledAt round-trip.
  Store.SetFileCompiledAt(FileId, 1000);
  if Store.GetFileCompiledAt(FileId) <> 1000 then
  begin
    Writeln('FAIL: GetFileCompiledAt did not return the value just set (1000)');
    Exit(1);
  end;

  // ClearCompilerFindingsForFile: insert one finding, clear it, verify empty.
  Finding.FileId  := FileId;
  Finding.RawPath := Store.GetFilePath(FileId);
  Finding.Code    := 'H0000';
  Finding.Severity:= 'Hint';
  Finding.LineNo  := 1;
  Finding.ColNo   := 1;
  Finding.Message := 'test-store-freshness probe finding';
  Store.InsertCompilerFinding(Finding);
  Store.ClearCompilerFindingsForFile(FileId);
  if Length(Store.FindCompilerFindingsForFile(FileId)) <> 0 then
  begin
    Writeln('FAIL: ClearCompilerFindingsForFile did not clear the probe finding');
    Exit(1);
  end;

  // GetStaleFileIds: must return without raising (contents not asserted --
  // staleness depends on mtime_unix vs. the timestamp just written above).
  try
    Stale:= Store.GetStaleFileIds;
  except
    on E: Exception do
    begin
      Writeln('FAIL: GetStaleFileIds raised: ', E.Message);
      Exit(1);
    end;
  end;
  if Length(Stale) < 0 then ; // no-op: silences unused-variable warning, keeps Stale referenced

  Writeln('PASS: test-store-freshness');
  Result:= 0;
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
// --db <db> [--full]: run the index/findings COHERENCE phase against <db>.
//         For each project member (the compile closure + its sibling .dfm) that
//         is not indexed, index-stale, or compile-stale, re-scan it (and its
//         .dfm), then -- if anything was incoherent (or --full) -- full-recompile
//         and refresh compiler_findings for the project. This self-heals the
//         index WITHOUT editing the .dpr (independent of --apply). The recompile
//         is best-effort: a non-buildable target does not fail reconcile. The
//         report gains a `coherence:` line (text) / `"coherence"` object (JSON).
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
  JCoh        : TJSONObject                               ;
  Store       : ISymbolStore                              ;
  DP2         : TDelphi13Parser                           ;
  Indexer2    : TIndexer                                  ;
  Members     : TArray<TProjectMember>                    ;
  Coh         : TArray<TMemberCoherence>                  ;
  MI          : Integer                                   ;
  CohMembers  : Integer                                   ;
  CohIncoher  : Integer                                   ;
  CohScanned  : Integer                                   ;
  CohRecomp   : Boolean                                   ;
  HaveCoh     : Boolean                                   ;
  DbParentDir : string                                    ;
  ProfileTgt  : string                                    ;
  SavedOut    : TTextRec                                  ;
  CohDbPath   : string                                    ;
begin
  // Accept either positional arg (AArgs.Path) or explicit --project.
  ProjectFile:= AArgs.Path;
  if (ProjectFile = '') and (AArgs.ProjectPath <> '') then ProjectFile:= AArgs.ProjectPath;
  if ProjectFile = '' then begin Writeln('ERROR: reconcile-project requires a .dpr or .dproj file path'); Exit (2 ); end;
  if not TFile.Exists(ProjectFile) then begin Writeln('ERROR: project file not found: ', ProjectFile); Exit(2); end;

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

    // Index/findings coherence phase (only with an EXPLICIT --db): ensure every
    // project member is indexed + compile-fresh in <db>, healing missing/stale
    // entries WITHOUT editing the .dpr. Must run BEFORE the report is emitted
    // so the coherence summary can be folded into the same text/JSON output.
    // NOTE: AArgs.DbPath is NEVER '' -- ParseArgs defaults it to
    // <cwd>/drag-lint.sqlite -- so the discriminator for "--db was actually
    // passed" is AArgs.DbPaths (only populated by the --db switch itself; see
    // ResolveIndexDb/:1525, DoFbSnapshot/:5566, DoSchema/:6215 for the same
    // idiom). Guarding on DbPath instead made this phase fire on every plain
    // `reconcile-project` call, silently creating a DB, indexing, and
    // recompiling as an unrequested side effect.
    HaveCoh   := False;
    CohMembers:= 0;
    CohIncoher:= 0;
    CohScanned:= 0;
    CohRecomp := False;
    if Length(AArgs.DbPaths) > 0 then
    begin
      CohDbPath:= AArgs.DbPaths[0];
      DbParentDir:= ExtractFilePath(TPath.GetFullPath(CohDbPath));
      if (DbParentDir <> '') and (not TDirectory.Exists(DbParentDir)) then
        // Error to stderr so a --json run's stdout stays one valid JSON object.
        Writeln(ErrOutput, 'reconcile-project: --db parent directory missing, skipping coherence phase: ', DbParentDir)
      else
      begin
        // Migrate bootstraps a missing DB file -- acceptable; reconcile's job is
        // to ensure coherence. ONE connection is shared by the scan (TIndexer)
        // and the recompile (RefreshProjectFindingsCore) -- no second store.
        Store:= TSQLiteSymbolStore.Create(CohDbPath);
        Store.Migrate;
        HaveCoh:= True;

        // Mirror the CLI index site: Delphi + DFM + Firebird parsers, usage refs
        // on, per-config preprocess profile from the project.
        DP2:= TDelphi13Parser.Create;
        DP2.EmitUsageRefs:= True;
        Indexer2:= TIndexer.Create(Store, [DP2, TDFMParser.Create, TFirebirdSqlParser.Create], AArgs.Docs);
        try
          // The shared TIndexer reports per-file progress ('... -> N symbols') on
          // stdout; redirect stdout to the null device for the whole scan+recompile
          // so reconcile owns its report stream (mandatory for the single-JSON-
          // object --json contract). Restored in the finally, even on exception.
          // Kept as the FIRST statements inside this try (not before it) so a
          // failed Rewrite still reaches the finally that restores stdout,
          // instead of leaking the redirect on an exception.
          Move(TTextRec(Output), SavedOut, SizeOf(TTextRec));
          AssignFile(Output, 'NUL');
          Rewrite(Output);

          ProfileTgt:= AArgs.ProjectPath;
          if ProfileTgt = '' then ProfileTgt:= ProjectFile;
          Indexer2.SetPreprocess(not AArgs.NoPreprocess,
            ResolveIndexProfile(ProfileTgt, AArgs.CheckPlatform, ''));

          Members:= PairDfmSiblings(RR.ClosureFiles);
          Coh:= ComputeCoherence(Store, Members);
          CohMembers:= Length(Coh);

          // Re-scan each incoherent member's .pas (and sibling .dfm) so the
          // index regains a fresh files row for it -- the motivating fix.
          for MI:= 0 to High(Coh) do
            if IsIncoherent(Coh[MI]) then
            begin
              Inc(CohIncoher);
              Indexer2.IndexFile(Coh[MI].Member.UnitPath);
              Inc(CohScanned);
              if Coh[MI].Member.HasDfm then
              begin
                Indexer2.IndexFile(Coh[MI].Member.DfmPath);
                Inc(CohScanned);
              end;
            end;

          // Resolve cross-unit links for what we just scanned (mirror the
          // index site's post-pass) so unit_uses / ancestry / calls resolve.
          if CohScanned > 0 then
          begin
            Store.ResolveUnitUseTargets;
            Store.ResolveAncestry;
            Store.ResolveHelpers;
            Store.ResolveCallTargets;
          end;

          // Recompile + refresh compiler_findings for the whole project when
          // anything was incoherent (or --full forces it). Best-effort: the
          // target may not be msbuild-buildable, so a compile failure/exception
          // must NOT fail reconcile -- the scan above already healed the index.
          // AEmitSummary=False keeps the core silent so our report stream stays
          // clean (one JSON object in --json mode).
          if (CohIncoher > 0) or AArgs.Full then
          begin
            try
              // AJson=False: dead when AEmitSummary=False (core emits no
              // summary in either shape), so pass the literal for clarity
              // rather than AArgs.AsJson.
              RefreshProjectFindingsCore(Store, ProjectFile, True, nil, False, False, AArgs.CheckPlatform);
              CohRecomp:= True;
            except
              CohRecomp:= False;
            end;
          end;
        finally
          Flush(Output);
          CloseFile(Output);
          Move(SavedOut, TTextRec(Output), SizeOf(TTextRec)); // restore stdout
          Indexer2.Free;
          Store:= nil; // release the shared connection
        end; // try
      end;
    end;

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

        // Coherence summary (only when --db ran the phase) -- same JRoot so
        // stdout stays ONE valid JSON object.
        if HaveCoh then
        begin
          JCoh:= TJSONObject.Create;
          JCoh.AddPair('members'   , TJSONNumber.Create(CohMembers));
          JCoh.AddPair('incoherent', TJSONNumber.Create(CohIncoher));
          JCoh.AddPair('scanned'   , TJSONNumber.Create(CohScanned));
          JCoh.AddPair('recompiled', TJSONBool.Create(CohRecomp));
          JRoot.AddPair('coherence', JCoh);
        end;

        Writeln(JRoot.Format(2));
      finally
        JRoot.Free;
      end; // try

      // --apply still runs; write messages to stderr so stdout stays clean.
      if AArgs.Apply then begin Reconciler.Apply(ProjectFile, RR); Writeln(ErrOutput, 'Applied: Missing units added to .dpr and .dproj (.bak backups written).'); end;
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

      // Coherence summary line (only when --db ran the phase).
      if HaveCoh then
        Writeln(Format('coherence: members=%d incoherent=%d scanned=%d recompiled=%s',
          [CohMembers, CohIncoher, CohScanned, IfThen(CohRecomp, 'true', 'false')]));

      // --apply: write changes to .dpr/.dproj (with .bak backups).
      if AArgs.Apply then begin Reconciler.Apply(ProjectFile, RR); Writeln('Applied: Missing units added to .dpr and .dproj (.bak backups written).'); end;
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
    if not TFile.Exists(ConfigPath) then begin Writeln(ErrOutput, 'library-drift: config not found: ', ConfigPath); Exit(2); end;
    var Content:= TFile.ReadAllText(ConfigPath);
    var RootDir:= ExtractFilePath(TPath.GetFullPath(ConfigPath));
    Manifest:= TManifestIO.ParseText(Content, RootDir);
  end
  else Manifest:= TManifestIO.Load(EngineDir, GetCurrentDir);

  // Build platform filter from --platform arg.
  if AArgs.CheckPlatform <> '' then begin SetLength(PFilter, 1); PFilter[0]:= AArgs.CheckPlatform; end
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
        { Reworded (was a bare "MISSING: <root>"): these roots have indexable
          source files (.pas/.inc/.dfm) on disk but none are in the index --
          i.e. source not yet indexed, NOT a phantom path. A compiled-output
          library root (e.g. Lib\...\Win64) that ships only .dcu + orphan .dfm
          with no companion .pas will show here too; its real .pas source
          usually lives in a sibling Source\ folder -- index that folder. }
        for R in Missing do Writeln('  SOURCE NOT INDEXED (.pas/.inc/.dfm on disk, none in index): ', R);
        if Length(Missing) = 0 then Writeln('  (clean)');
      end;
      Writeln('library-drift: ', PlatCnt, ' platforms checked, ', TotalMiss, ' library root(s) with source not yet indexed');
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
    if Args.ShowHelp then begin PrintHelp; Exit(0); end;
    if Args.ShowVersion then begin Writeln('drag-lint ', VERSION); Exit(0); end;
    if Args.Command = 'index' then
    begin
      if Args.IndexAll then Result:= DoIndexAll(Args)
      else Result:= DoIndex(Args)
    end
    else if Args.Command = 'query'             then Result:= DoQuery           (Args)
    else if Args.Command = 'rules'             then Result:= DoRules           (Args)
    else if Args.Command = 'lint'              then Result:= DoLint            (Args)
    else if Args.Command = 'export'            then Result:= DoExport          (Args)
    else if Args.Command = 'top'               then Result:= DoTop             (Args)
    else if Args.Command = 'import-log'        then Result:= DoImportLog       (Args)
    else if Args.Command = 'graph'             then Result:= DoGraph           (Args)
    else if Args.Command = 'todos'             then Result:= DoTodos           (Args)
    else if Args.Command = 'hover'             then Result:= DoHover           (Args)
    else if Args.Command = 'contrast-selftest' then Result:= DoContrastSelfTest
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
    else if Args.Command = 'deps-report'       then Result:= DoDepsReport      (Args)
    else if Args.Command = 'schema'            then Result:= DoSchema          (Args)
    else if Args.Command = 'info'              then Result:= DoInfo            (Args)
    else if Args.Command = 'resolve-uses'      then Result:= DoResolveUses     (Args)
    else if Args.Command = 'fb-snapshot'       then Result:= DoFbSnapshot      (Args)
    else if Args.Command = 'link-orm'          then Result:= DoLinkOrm         (Args)
    else if Args.Command = 'rename'            then Result:= DoRename          (Args)
    else if Args.Command = 'generate-docs'     then Result:= DoGenerateDocs    (Args)
    else if Args.Command = 'document'          then Result:= DoDocument        (Args)
    else if Args.Command = 'document-all'      then Result:= DoDocumentAll     (Args)
    else if Args.Command = 'create-enum-helper' then Result:= DoCreateEnumHelper(Args)
    else if Args.Command = 'helpers-of'         then Result:= DoHelpersOf       (Args)
    else if Args.Command = 'find-unit'         then Result:= DoFindUnit        (Args)
    else if Args.Command = 'safe-delete'       then Result:= DoSafeDelete      (Args)
    else if Args.Command = 'extract-method'    then Result:= DoExtractMethod   (Args)
    else if Args.Command = 'find-deadcode'     then Result:= DoFindDeadCode    (Args)
    else if Args.Command = 'compile-check'     then Result:= DoCompileCheck    (Args)
    else if Args.Command = 'refresh-findings'  then Result:= DoRefreshFindings (Args)
    else if Args.Command = 'ghost-check'       then Result:= DoGhostCheck      (Args)
    else if Args.Command = 'ghost-recover'     then Result:= DoGhostRecover    (Args)
    else if Args.Command = 'check-unit'        then Result:= DoCheckUnit       (Args)
    else if Args.Command = 'lint-all'          then Result:= DoLintAll         (Args)
    else if Args.Command = 'lint-project'      then Result:= DoLintProject     (Args)
    else if Args.Command = 'cycles'            then Result:= DoCycles          (Args)
    else if Args.Command = 'uses-audit'        then Result:= DoUsesAudit       (Args)
    else if Args.Command = 'uses-fix'          then Result:= DoUsesFix         (Args)
    else if Args.Command = 'forms-csv'         then Result:= DoFormsCsv        (Args)
    else if Args.Command = 'generate-test'     then Result:= DoGenerateTest    (Args)
    else if Args.Command = 'format'            then Result:= DoFormat          (Args)
    else if Args.Command = 'check-ast'         then Result:= DoCheckAst        (Args)
    else if Args.Command = 'dump-refs'         then Result:= DoDumpRefs        (Args)
    else if Args.Command = 'doc-drift'         then Result:= DoDocDrift        (Args)
    else if Args.Command = 'dump-pp-lex'       then Result:= DoDumpPpLex       (Args)
    else if Args.Command = 'dump-pp-eval'      then Result:= DoDumpPpEval      (Args)
    else if Args.Command = 'preprocess-file'   then Result:= DoPreprocessFile  (Args)
    else if Args.Command = 'pp-profile'        then Result:= DoPpProfile       (Args)
    else if Args.Command = 'dump-call-edges'   then Result:= DoDumpCallEdges   (Args)
    else if Args.Command = 'find-callees'      then Result:= DoFindCallees     (Args)
    else if Args.Command = 'ambiguous-calls'   then Result:= DoAmbiguousCalls  (Args)
    else if Args.Command = 'call-path'         then Result:= DoCallPath        (Args)
    else if Args.Command = 'callgraph'         then Result:= DoCallGraph       (Args)
    else if Args.Command = 'reverse-calltree'  then Result:= DoReverseCallTree (Args)
    else if Args.Command = 'proptree'          then Result:= DoPropTree        (Args)
    else if Args.Command = 'convert-validate'  then Result:= DoConvertValidate (Args)
    else if Args.Command = 'convert-scaffold'  then Result:= DoConvertScaffold (Args)
    else if Args.Command = 'convert-reemit'    then Result:= DoConvertReemit   (Args)
    else if Args.Command = 'convert-apply'     then Result:= DoConvertApply    (Args)
    else if Args.Command = 'butterfly'         then Result:= DoButterfly       (Args)
    else if Args.Command = 'purge-locals'      then Result:= DoPurgeLocals     (Args)
    else if Args.Command = 'diff'              then Result:= DoDiff            (Args)
    else if Args.Command = 'workspace'         then Result:= DoWorkspace       (Args)
    else if Args.Command = 'selftest'          then Result:= DoSelfTest        (Args)
    else if Args.Command = 'test-store-freshness' then Result:= DoTestStoreFreshness(Args)
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
    else begin Writeln('ERROR: unknown command: ', Args.Command); PrintHelp; Result:= 2; end;
  except
    on E: Exception do begin Writeln('FATAL: ', E.ClassName, ': ', E.Message); Result:= 3; end;
  end; // try
end; // function

end.

