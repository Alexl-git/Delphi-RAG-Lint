unit DRagLint.CLI.Common;  // dl:ok unit-too-large@890d -- REVIEWED 2026-11-22 SLZ-S02: unit-too-large measured 2127 lines (limit 2000), pre-existing shape; splitting it is a refactor of its own, out of scope for a lint pass (Q10 a)

// ---------------------------------------------------------------------------
// What every verb unit of the CLI shares (lane v1511 SPLIT, T07): the parsed command line (TArgs), the
// read-only store opener with its once-per-process freshness notes, the one-index-run-per-database lock,
// the database checks every verb makes first (NoDbResolved, ExplicitDbsExist, StaleDbRefusesRun) and the stdout
// document writer. Moved verbatim out of DRagLint.CLI so verb families can live in their own units;
// DRagLint.CLI keeps the argument parsing and the dispatch.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Generics.Collections, System.JSON,
  DRagLint.Core.Model, DRagLint.Core.Interfaces, DRagLint.Index.Manifest, DRagLint.Index.Plan;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.EvaluateLibraryGate (DRagLint.CLI.pas), DRagLint.CLI.ManifestLibraryStores (DRagLint.CLI.pas), DRagLint.CLI.ParseArgs (DRagLint.CLI.pas), DRagLint.CLI.PlanLibraryResolve (DRagLint.CLI.pas) (+256 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.CLI.CallGraph, DRagLint.CLI.Common, DRagLint.CLI.Compare, DRagLint.CLI.ConsumerDbs, DRagLint.CLI.Convert, DRagLint.CLI.ConvertApply, DRagLint.CLI.Export, DRagLint.CLI.Format, DRagLint.CLI.Graph (+9 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TArgs = record
    Command         : string        ;
    SubCommand      : string        ;
    Path            : string        ;
    DbPath          : string        ;
    DbPaths         : TArray<string>;
    { True while DbPaths holds ONLY a "db" key from a .drag-lint.json. That key
      is an explicit --db (owner ruling 2026-08-13, recorded in Run), so it is
      put in DbPaths; the first command-line --db then REPLACES it rather than
      appending, because the command line beats the config file. }
    DbFromConfig    : Boolean       ;
    { The .drag-lint.json whose "db" key DbPaths holds, while DbFromConfig is
      True; '' otherwise. Named wherever that db decides a write or a refusal,
      because the user typed no --db (INBOX 2026-09-29 items 4b/5). }
    DbConfigFile    : string        ;
    { True while ProjectPath holds ONLY a "project" key from a .drag-lint.json.
      A --project on the command line clears it; a POSITIONAL .dpr/.dproj/.dpk
      then wins over the key too (X-11, ApplyPositionalProjectPrecedence). }
    ProjectFromConfig: Boolean      ;
    { True while Path holds ONLY a "path" key from a .drag-lint.json. The first POSITIONAL path
      or --dir replaces it (command line beats the config file, W5-C). }
    PathFromConfig  : Boolean       ;
    { '<file>: <key path>: expected <type>, got <type>' when the .drag-lint.json
      defaults file could not be read (LoadConfigDefaults); '' otherwise. Readers
      carry on with what was read; Run makes the WRITE verbs refuse. }
    ConfigError     : string        ;    { 1.26.2: a convert-* verb does not read a .drag-lint.json. When the file it
      ignored held keys the defaults reader applies, ConvertIgnoredFile names it,
      ConvertIgnoredKeys lists them ('"db", "rule"'), and ConvertIgnoredIndexKey
      is the first of "db" / "project" among them -- a key that would have chosen
      the INDEX, so without an explicit --db the run is refused rather than left
      to pick one on its own (CheckConvertIgnoredDefaults). '' otherwise. }
    ConvertIgnoredFile    : string;
    ConvertIgnoredKeys    : string;
    ConvertIgnoredIndexKey: string;
    { v21: --library-db, repeatable. Extra indexes consulted ONLY for calls the
      primary index cannot resolve; a hit is recorded as a qualified NAME on
      refs.external_target. Explicit rather than auto-opened from the manifest
      so `index` never silently changes what it reads. }
    LibraryDbs      : TArray<string>;
    ExcludeUnder    : TArray<string>; // v0.42: --exclude-under <dir> (repeatable)
    Deep            : Boolean       ; // v0.42: emit identifier usage refs
    DeepExplicit    : Boolean       ; // --deep/--shallow was given on the cmd line
    Width           : string        ; // v0.42: usages width narrow|wide|very-wide
    UsagesScope     : string        ; // 1.52 FUSCOPE: usages --scope symbol|project|group|everywhere
    UsagesGroup     : string        ; // 1.52 FUSCOPE: usages --group <x.groupproj> (scope group)
    Name            : string        ;
    QName           : string        ;
    OfName          : string        ; // v11 (M1): query ancestors --of <ancestor> (is-descendant check)
    InFile          : string        ; // --in <file.pas> (resolve-uses scope context)
    TypeNames       : string        ; // --names A,B,C: type names for `query type-usage`
    NamesFile       : string        ; // --names-file <f>: same list, one name per line
    UnitName        : string        ; // --unit <UnitName>: unit name for `query unit-usage`
    { `sql`: the statement itself, and the wall-clock cap that keeps a bad
      join from wedging the IDE holding a multi-gigabyte index open. The
      OTHER source, --file, reuses InFile above rather than adding a field. }
    NameLike        : string        ; // --name-like <substr>: substring search over symbol names
    HoldSeconds     : Integer       ; // --seconds N: `ide-release` hold length
    Resume          : Boolean       ; // --resume: `ide-release` clears the hold instead of setting it
    StatusOnly      : Boolean       ; // --status: `ide-release` reports the hold without changing it
    GainSince       : string        ; // --since <yyyy-mm-dd>: `gain` skips usage-log lines older than this
    WaitSeconds     : Integer       ; // --wait N: `stop-now` graceful deadline per engine (default 5)
    ForceKill       : Boolean       ; // --force: `stop-now` escalates to TerminateProcess -- only after a refusal
    SqlQuery        : string        ; // --query "SELECT ...": the one statement `sql` runs
    TimeoutMs       : Integer       ; // --timeout-ms N: `sql` wall-clock cap (default 10000)
    { `wiki`: the three modes. Term is the human phrase to look up; the two
      Booleans select --list / --check. Separate fields rather than one mode
      string so "no mode given" stays distinguishable from "an unknown mode",
      which is what lets the verb print usage instead of guessing. }
    Term            : string        ; // --term "<phrase>": `wiki` alias/name lookup
    WikiList        : Boolean       ; // --list : every topic in the resolved DBs
    WikiCheck       : Boolean       ; // --check: SeeCode drift + duplicate-name gate
    Rule            : string        ;
    { N-02: '<first>, <second>' when --rule was given twice with DIFFERENT ids.
      Rule holds one id, so the earlier one used to be dropped in silence; Run
      refuses the command line instead (exit 2). '' otherwise. }
    RuleConflict    : string        ;
    RuleList        : string        ; // --rule a,b: the ids the run is narrowed to (execution and report; v1511 B16); Rule is '' then
    ProjectPath     : string        ;
    RulesDir        : string        ; // --rules-dir <path>: external .scm rules location (default <exe-dir>\rules)
    RuleCategory    : string        ; // --category <name>: filter `rules` output
    RuleStandard    : string        ; // --standard cwe|cert|misra: `rules` lists only rules labelled under it
    ShowLabels      : Boolean       ; // --labels: `lint` / `lint-all` text findings get a  [CWE-476] suffix
    Disable         : string        ; // --disable id1,id2,...: rule ids to drop from lint output
    LayersPath      : string        ; // --layers <file.json>: architecture-layer config for lint-project
    Format          : string        ;
    Output          : string        ;
    OutputDir       : string        ;
    Limit           : Integer       ;
    LimitGiven      : Boolean       ; // --limit was on the command line (sql: `--limit 0` = every row)
    MaxRows        : Integer       ; // --max-rows N: per-section row cap of `overview`
    SortBy          : string        ;
    ScanLibraries   : Boolean       ;
    ScanLibrariesAll: Boolean       ; // --scan-libraries-all: every platform subkey
    AsJson          : Boolean       ;
    DryRun          : Boolean       ;
    ShowDiff        : Boolean       ; // v(row 2): `format --diff` -- format a COPY, print the diff, write nothing
    Watch           : Boolean       ;
    Interval        : Integer       ;
    Open            : Boolean       ;
    ShowHelp        : Boolean       ;
    HelpVerb        : string        ; // verb whose OWN help <verb> --help prints (menu-tree, menu-drift); empty = the global banner
    ShowVersion     : Boolean       ;
    // v0.66: ergonomics #12 output/CI flags
    FailOn       : string ; // --fail-on error|warning|info|none (ergonomics #12)
    Baseline     : string ; // --baseline <file>: report only findings NOT in it
    WriteBaseline: string ; // --write-baseline <file>: record current findings, exit 0
    { lint-tree. --unit/--buffer/--project/--db/--baseline/--write-baseline/
      --platform/--format are REUSED from the fields above; only these two are
      new. `--with-rules`, not `--rules`: --rules already takes a VALUE
      (RulesFile, for convert-*), so a boolean spelled --rules would swallow
      the next argument. }
    TreeCompile  : Boolean; // --compile   : lint-tree tier 3 (shadow compile)
    TreeWithRules: Boolean; // --with-rules: also harvest dependent lint findings
    ConfigPath   : string ; // --config <file>: drag-lint-lint.json override path
    Enable       : string ; // --enable id1,id2: re-include disabled/off-by-default rules
    Profile      : string ; // --profile <name>: merge a named enable/disable set
    NoStandDown  : Boolean; // --no-stand-down (1.52 B17): lint-all opens no stand-down channel, so a measurement run is never cut to PARTIAL
    TargetCompiler: string ; // --target-compiler <ver|auto> (1.38): lint / lint-all / rules; '' = config, then 37
    // v0.16: query find flags
    DocTag     : string ;
    DocContains: string ;
    // v(A2): --decl-contains <phrase>. Matches the DECLARING SOURCE LINE,
    // not the doc comment and not a string literal -- the clauses the
    // extractor does not model (`stored X`, `default V`, `read F write S`).
    DeclContains: string ;
    NoDocs     : Boolean;
    Kind       : string ;
    PublicOnly : Boolean;
    NoLocals   : Boolean; // outline --no-locals: drop local_var and param rows (Gitea #38)
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
    // 1.20.6 (T2d): --depth was given at all, and its raw text. proptree and
    // convert-scaffold need both: Depth alone cannot tell "--depth 3" from the
    // parse default 3, nor "--depth x" from a number (see ResolveTreeDepth).
    DepthGiven    : Boolean;
    DepthRaw      : string ;
    // 1.20.6 (T2e): --progress-interval S was given, and its raw text (not
    // given = 0 = off).
    // Parsed only for proptree / convert-scaffold (any other verb rejects the
    // flag as an unknown argument, exit 3); validated by
    // ResolveProgressInterval (not decimal digits = exit 2).
    ProgressIntervalGiven: Boolean;
    ProgressIntervalRaw  : string ;
    IncludeImpl   : Boolean;
    AllVisibility : Boolean;
    WiringCoverage: Boolean; // v8: --coverage for the wiring command
    ContextLines  : Integer; // v0.17: find-callers --context N
    Resolved      : Boolean; // v14 (D5 T8): find-callers --resolved (precise callers via call_edges)
    UsagesRw      : Boolean; // usages --rw: the users of a member split into readers and writers
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
    MaxBodyTokens      : Integer; // context --max-body-tokens N: a TYPE target's body budget (default 20000; 0 = uncapped)
    BenchN             : Integer; // --n N for bench-context (default 20)
    // v0.19: typeat
    Position: string; // raw <file>:<line>:<col>
    // v0.24: rename
    RenameTo: string ; // --to <NewName>
    NoBackup: Boolean; // --no-backup
    NoCreate: Boolean; // --no-create (C8: do not build a missing project index on first use)
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
    // 1.40 implementors (interface report): --uses, --max-sites N, --include-library
    IfrUses       : Boolean;
    IfrMaxSites   : Integer;
    IncludeLibrary: Boolean;
    AllProjects   : Boolean; // impact --all-projects: every manifest DB, not one
    // v0.43: check-unit (in-memory semantic check) + uses-audit
    Shadow         : string ; // --shadow <dir> (unsaved-buffer overlay)
    { ghost-check --in-place: restore the pre-2026-09-08 behaviour of
      OVERWRITING the real files for the duration of the compile. Default
      False = shadow compile, which never writes them. Opt-in because the
      owner's ruling is that a file modified in the editor after its save
      must not be rewritten -- and every entry this verb gets is one. }
    GhostInPlace   : Boolean; // --in-place (ghost-check; DANGEROUS)
    ResolveUsesFlag: Boolean; // --resolve-uses (enrich undeclared errors)
    CheckPlatform  : string ; // --platform win32|win64 (matches project config)
    // fresh compiler findings: refresh-findings --full (force a full build even
    // when fewer than 2 files are stale)
    Full           : Boolean;
    Edges          : Boolean; // --edges (cycles: show the actual uses edges)
    Causes         : Boolean; // --causes (cycles: pinpoint the symbols forcing each interface edge)
    Plan           : Boolean; // --plan (cycles: emit a followable markdown refactoring playbook)
    F2047          : Boolean; // --f2047 (cycles: only the interface-only cycles dcc rejects, N-09)
    Hub            : Boolean; // --hub (cycles: hub analysis per group, spec 2026-11-08-hub-scc-phased P1)
    HubSurface     : Boolean; // --hub-surface (cycles: recipe R3 asked for by name, spec 2026-11-08-hub-scc-phased P2; needed for --apply and for --causes --format json)
    NoHubSurface   : Boolean; // --no-hub-surface (cycles --plan: the planner's own plan for every group; since 1.51 the dry run asks R3 first, phase P6)
    FixCycle       : Integer; // --cycle <n> (cycles --fix: the 1-based group to plan)
    FixCycleGiven  : Boolean; // --cycle was on the command line (so 0 / junk is an error, not 'absent')
    FixPart        : string ; // --part a|b|all (cycles --fix)
    NoCompile      : Boolean; // --no-compile (cycles --fix: skip the baseline build)
    CompileGate    : Boolean; // --compile-gate (lint --fix --apply: write through the --project build gate; the default with a .dproj since 1.51)
    NoCompileGate  : Boolean; // --no-compile-gate (lint --fix --apply --project <X.dproj>: write unbuilt; naming renames stay gated)
    ShadowOut      : string ; // --shadow-out <dir> (cycles --fix, debug: where the shadow tree is staged)
    CycleRsVars    : string ; // --rsvars <rsvars.bat> (cycles --fix: the Studio build environment, for a Studio the registry does not name)
    CycleBuildTimeout: string ; // --build-timeout <s> (cycles --fix: whole seconds one build may take; '' / 0 = no limit, the default)
    Apply          : Boolean; // --apply (uses-fix / autofix: write changes, not dry-run)
    Fix            : Boolean; // --fix (lint: autofix findings that have a quick-fix; dry-run unless --apply)
    // AutoFix Chunk 1 (Task 3): single-finding fix targeting. Each SET flag
    // narrows the fixable set; unset = no filter. Default FixLine:=0, FixRule:=''.
    FixLine      : Integer; // --fix-line <L> (1-based; 0 = all lines)
    FixRule      : string ; // --fix-rule <id> ('' = all rules)
    NpRoutine    : string ; // narrow-param --routine <QName>
    NpParam      : string ; // narrow-param --param <name>
    NpShowBound  : Boolean; // narrow-param --show-bound
    EiClass      : string ; // extract-interface --class <name>
    EiMembers    : string ; // extract-interface --members <a,b>
    EiReparent   : Boolean; // extract-interface --reparent-interfaced
    EiNoRefCount : Boolean; // extract-interface --reparent-interfaced=norefcount
    EiRetype     : string ; // extract-interface --retype-consumer <Routine>.<param> (v151 REPARENT, P22)
    LiDefer      : Boolean; // lazy-init --defer (lane 147 G3P)
    FixNaming    : Boolean; // --fix-naming (batch --fix: explicit consent to the opt-in naming fixes)
    { --stand-in-for <realpath>: analyse THIS file's text, but answer as though
      it were <realpath>. The IDE lints an unsaved buffer by writing a snapshot
      to %TEMP%\drag-lint-live-<tick>.pas; every question that is really about
      IDENTITY rather than text -- which index contains me, what is my file id,
      does my unit name match my file name, which drag-lint-lint.json owns me,
      what path do I report -- must be asked about the real file, or the answer
      is about a temp file nobody has. Measured before it was built:
      `[flowdb] eff=C:\TEMP\drag-lint-live-...pas db= store=False fid=0`. }
    StandInFor   : string ; // --stand-in-for <realpath> ('' = the target is itself)
    { --project-rules: also run the store-backed PER-DECL doc rules (doc-drift,
      missing-doc) for this one file. OFF by default, and the default is a
      MEASUREMENT, not caution: doc-drift rebuilds the expected facts block per
      declaration -- ~16 ms each -- so a 53-decl unit costs 0.83 s and this
      repo's own DRagLint.CLI.pas costs 60.84 s. The IDE spawns `lint` per
      buffer against a HARD 8 s timeout whose failure branch shows NO
      diagnostics at all, so running these by default would replace a partial
      gutter with an EMPTY one on exactly the largest files. }
    ProjectRules : Boolean; // --project-rules (per-file doc-drift + missing-doc)
    RemoveUnused : Boolean; // --remove-unused (uses-fix: also comment unused)
    WithDfm      : Boolean; // --with-dfm (menu-tree / menu-drift: .dfm menus as roots, code links grafted)
    // v0.27: generate-test + format
    TestFramework: string; // --framework dunitx|dunit (default 'dunitx')
    YadfPath     : string; // --yadf-path <YADF.exe>
    // v0.34: workspace
    WorkspaceConfig: string; // --config <path>
    // forms-csv
    RootForm: string; // forms-csv: --root <TfrmMAIN> (auto-detect if '')
    RegistryDir: string; // menu-drift: --registry <features dir>
    // library-drift / selftest drift
    Roots: TArray<string>; // --root <dir> repeatable (drift check)
    // v0.45: index manifest (Task 1)
    IndexAll: Boolean; // --all  (index all sections from manifest)
    { --prune / --no-prune: after the walk, drop indexed files under the walked
      roots that no longer exist on disk. DEFAULT ON for a folder walk (a stale
      row silently corrupts every reference-derived output); --no-prune opts out,
      and --prune still forces it for a single-file walk. }
    Prune  : Boolean;
    NoPrune: Boolean;
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
    OnlyTypes   : TArray<string>; // --only-type <T1,T2,...>  convert-apply: every instance of these bare #convert From types (exclusive with --only)
    // v0.45: index manifest (Task 8)
    Jobs: Integer; // --jobs <n>  parallel worker processes (0 = manifest/auto)
    // v0.45: index manifest (Task 9) -- DB selection + size guard
    Force32       : Boolean; // --force32  treat this run as 32-bit for size-guard testing
    ForceReparse  : Boolean; // INBOX 2.3: --force-reparse  ignore the incremental up-to-date skip
    // The index MODE axis. Orthogonal to SCAN TYPE (project closure vs folder
    // tree), which is declared by what the target is, not chosen per run.
    //   Rebuild   -- clear every indexed file from the DB, then walk.
    //   Recompile -- update in place. THE DEFAULT, so this field records only
    //                that the flag was given explicitly, which is what makes
    //                `--rebuild --recompile` detectable as a usage error rather
    //                than resolved by a silent precedence rule.
    Rebuild       : Boolean; // --rebuild
    Recompile     : Boolean; // --recompile (explicit; the default either way)
    SizeGuardMB   : Integer; // --size-guard-mb <n>  override manifest sizeGuardMB (0=warn always)
    SizeGuardMBSet: Boolean; // True when --size-guard-mb was explicitly given
    // v0.46: file-size guard (tree-sitter native stack overflow prevention)
    MaxFileKB   : Integer; // --max-file-kb <n>  override default 2048; 0=unlimited; -1=not set
    MaxFileKBSet: Boolean; // True when --max-file-kb was explicitly given
    // v0.47: lifecycle -- when the IDE plugin spawns a long-running server
    // (lsp), it passes --parent-pid <IDE pid> so we self-exit if the IDE dies
    // (belt-and-suspenders alongside the BPL's kill-on-close job object).
    ParentPid: Cardinal; // --parent-pid <n>  (0 = not set)
    // v1.7 Task 1: `lsp --proxy` runs the transparent relay in front of
    // DelphiLSP instead of drag-lint's own LSP server. The two are mutually
    // exclusive by construction -- the relay never opens a database, because
    // in relay form it answers nothing itself.
    LspProxy    : Boolean; // --proxy
    LspDelphiBits: Integer;  // --delphi-lsp-bits <32|64> (0 = not given = 64)
    LspDelphiExe: string;  // --delphi-lsp <path>  ('' = resolve from the installed Studio)
    LspTraceFile: string;  // --trace <file>       ('' = no trace, the default)
    LspMergeDiagnostics: Boolean; // --merge-diagnostics (merge plan P0; OFF by default)
    LspMergeCompletion : Boolean; // --merge-completion (merge plan A3; OFF by default)
    LspMergeHover      : Boolean; // --merge-hover (merge plan A4; OFF by default)
    LspMergeDefinition : Boolean; // --merge-definition (merge plan A5; OFF by default)
    LspMergeNavigation : Boolean; // --merge-navigation (hierarchy, typeDefinition, highlight, folding; OFF by default)
    LspFullRules       : Boolean; // --full-rules (C1; OFF by default)
    LspNoExceptionFacts: Boolean; // --no-exception-facts (D1, wave 148: the Raises: hover line + exception lens are ON by default)
    LspMergeBudgetMs   : Integer; // --merge-budget-ms <n>
    LspMergeBudgetSet  : Boolean; // False = LSP_MERGE_BUDGET_DEFAULT_MS
    ResolveOnly : Boolean; // index --resolve-only: re-derive edges, skip the walk
    StallExitMin: Integer; // index --stall-exit-min: minutes without progress before the run gives up; 0 = warn only
    WaitLibraryMin : Integer; // index --wait-library <minutes>: poll a not-ready platform library, then continue
    RequireLibrary : Boolean; // index --require-library: a not-ready platform library is ERROR, exit 2
    RuleCacheWarm: string; // index --rule-cache-warm background|wait|off ('' = DRAGLINT_RULE_CACHE_WARM, else wait)
    WarmDetached : Boolean; // warm-rule-cache --detached: spawned by an index run, no console
    // v0.47: ghost-check -- compile the project with one unit's content replaced
    // by an unsaved buffer, with a guaranteed restore. Track 3 sub-project B
    // Task 2: convert-apply's --unit (the .pas being converted) ALSO reuses
    // this field (same non-document-command routing as ghost-check).
    GhostUnit  : string; // --unit <real .pas to overlay | convert-apply target .pas>
    ConvertUnits: TArray<string>; // every --unit in order (convert-apply batch mode, C13 b2); GhostUnit is the last
    GhostBuffer: string; // --buffer <temp file holding the buffer>
    // AutoDocument (whole-unit batch): --unit <file.pas> for the `document`
    // command means "document every public decl in this unit". It shares the
    // --unit flag with ghost-check's GhostUnit, so it is parsed into a DISTINCT
    // field ONLY when Command='document' to avoid the ghost-check collision.
    DocUnit    : string; // document --unit <file.pas>
    { 152b DOCU2: '<first>, <second>' when `document` got --unit twice with
      DIFFERENT values. DocUnit holds one file, so the earlier one used to be
      dropped in silence; Run refuses the command line instead (exit 2). }
    DocUnitConflict: string;
    // AutoDocument (batch scope): --stubs flips the facts-only default. Off
    // (default) documents only facts-backed / already-documented decls; on keeps
    // the pure all-TODO create too (opt-in TODO stubs). Consumed by document /
    // document --project / document-all via TDocBatchOptions.Stubs.
    DocStubs   : Boolean; // document [...] --stubs
    // AutoDocument Phase 3 T2: --strip removes engine-owned doc output
    // (AUTO_MARK tags + AUTO_BEGIN..AUTO_END regions) instead of generating
    // it. Mutually exclusive with --stubs (rejected, exit 2). Consumed by
    // document / document --unit / --project / document-all via
    // TDocBatchOptions.Strip, and by document --qname directly via
    // TDocStripper.StripSymbolRegion.
    DocStrip   : Boolean; // document [...] --strip
    // AutoDocument (ADF T4): the <seealso> doc-source (related symbols from the
    // call graph + siblings). ON BY DEFAULT since the Phase C doc pass; use
    // --no-seealso to suppress it. Consumed by document --qname / --unit /
    // --project / document-all via TDocBatchOptions.IncludeSeeAlso (and
    // BuildFor's AIncludeSeeAlso). --seealso is still accepted, and is now a
    // no-op that restates the default rather than an error.
    DocSeeAlso : Boolean; // document [...] --no-seealso to turn OFF
    // AutoDocument (ADF T5): --since opts in the <since> doc-source (git commit
    // date of the decl line). Off by default; git is spawned ONLY when set.
    // DocBaseDir is the repo root for the git lookup ('' -> the file's own dir).
    // Consumed by document --qname / --unit / --project / document-all via
    // TDocBatchOptions.IncludeSince / BaseDir (and BuildFor's AIncludeSince / ABaseDir).
    DocSince   : Boolean; // document [...] --since
    DocBaseDir : string ; // document [...] --base-dir <repoRoot>
    // 2026-09-23: --migrate-pure lets `document` regenerate a stored legacy
    // `Pure` fact line (purity v1). Off by default: a block whose ONLY
    // difference from a fresh render is that line is left byte-identical, per
    // the owner's deferral of the purity migration to one explicit run.
    // Consumed by DoDocument / DoDocumentAll via TSharedFacts.MigrateLegacyPure.
    DocMigratePure: Boolean; // document [...] --migrate-pure
    // doc-forget (2026-09-23): the project-tag reaping command. --project <Name>
    // is shared with the other verbs' ProjectPath field (the verb reads it as a
    // TAG name, not a path); these four are its own.
    DocForgetScope   : string ; // doc-forget --scope <file.pas|dir>
    DocForgetRename  : string ; // doc-forget --rename OLD=NEW
    DocForgetList    : Boolean; // doc-forget --list-tags
    DocForgetUntagged: Boolean; // doc-forget --untagged
    // ADP1 T2: --include-accessors disables the batch modes' trivial-property-
    // accessor skip filter for this run (document --unit/--project/-all only;
    // document --qname is never filtered). Off by default (filter ON).
    // Consumed via TDocBatchOptions.IncludeAccessors.
    DocIncludeAccessors: Boolean; // document [...] --include-accessors
    // ADP1: --reindex (CLI equivalent of IDE menu self-freshening) self-brackets
    // document --project --apply with index: index -> document --apply -> index.
    // INCREMENTAL index auto-detects stale/absent, reindex after document fixes
    // the stale-index-after-document trap (line-shift after --apply).
    DocReindex: Boolean; // document [...] --reindex
    // v0.48: multi-overlay -- a manifest with one 'realpath<TAB>bufferpath' per
    // line, so ALL unsaved units are overlaid for a single compile.
    GhostOverlays: string; // --overlays <manifest>
    // v0.57: text-constant search (Tasks 3-8)
    TextQuery    : string ; // --text "<phrase>"
    ConceptQuery : string ; // --concept "<words>" (xj-5 concept search)
    TextAnyOrder : Boolean; // --any-order
    TextSubstring: Boolean; // --substring
    NearQName    : string ; // query --text --near <QName> (call-graph neighbourhood filter)
    HopsRaw      : string ; // --hops N ('' = default 2; 1..3 accepted)
    HopsUses     : Boolean; // --hops-uses: unit-uses edges join the neighbourhood
    NearBoost    : Boolean; // --near-boost: keep every row, neighbourhood first
    TextSource   : string ; // --source pas|dfm|sql ('' = all)
    { `query --text --kind` reuses the EXISTING Kind field rather than adding a
      second one. --kind is parsed unconditionally further up this chain, so a
      second branch for it would be unreachable dead code -- the same shape as
      the document/ghost-check --unit collision noted above. The two senses are
      disjoint by subcommand: `query find --kind property` means a SYMBOL kind,
      `query --text --kind comment` means a string_literals row kind. }
    // v0.64: lint-all progress
    Quiet : Boolean; // --quiet  suppress per-file progress to stderr
    // Task 5: lint-all ownership scope. --lint-third-party restores the pre-
    // Task-5 behaviour (every indexed .pas file, vendored code included).
    LintThirdParty: Boolean;
    // 1.52 BUDGET (D9): lint / lint-all --no-budget -- no rule is skipped for exceeding rule_time_budget_ms.
    NoBudget: Boolean;
    // lint-all --shared-db <db> (repeatable): other project indexes whose findings
    // count as evidence for a closure-dependent review marker on a shared unit.
    SharedDbs: TArray<string>;
    // The same scope question for `document --project`, which WRITES rather
    // than reports and so needs it more: without it a YADF run put its only two
    // edits into the vendored DelphiAST checkout. Separate flag from
    // --lint-third-party because opting into reporting on vendored code is a far
    // smaller decision than opting into rewriting it.
    DocumentThirdParty: Boolean;
    // PP-Task-3: dump-pp-eval diagnostic verb (the {$IF expr} evaluator)
    PpExpr    : string        ; // --expr "<E>"        the compile-time expression to evaluate
    PpDefines : TArray<string>; // --define <SYM>      repeatable defined symbols (lowercased on use)
    PpNumeric : TArray<string>; // --numeric <K=V>     repeatable numeric defines (K=V, K lowercased on use)
    // PP-Task-6: preprocess-file include handling
    PpIncludeMode: string     ; // --include-mode <off|defines-only>  ('' => default 'off')
    PpNoNearSearch: Boolean   ; // --no-near-search  (v1.2.1 #2) strict BaseDir-only include resolution
    PpTolerances : Boolean    ; // --tolerances  (v1.2.1 #5) opt-in dcc-tolerance ';' replacement pass
    PpIncludeSites: Boolean  ; // --include-sites (N-06) preprocess-file prints the active include sites instead of the source
    // PP-Task-7: pp-profile define-profile resolver diagnostic verb
    PpDproj      : string     ; // --dproj <file.dproj>  the project whose config defines to resolve
    // PP-Task-9: index-time preprocessing. Preprocessing is ON by default in the
    // index AND lint verbs (per-config conditional resolution before parsing); --no-preprocess
    // reverts to the prior raw all-branch behaviour.
    NoPreprocess : Boolean    ; // --no-preprocess  disable the in-process directive preprocessor for this index run
    BuildConfig  : string     ; // --build-config <name>  index: parse a PROJECT against this build config instead of its ACTIVE one ('' = the .dproj's Config marker)
    // Task 5: create-enum-helper CLI verb (--qname reuses QName; --db/--apply/
    // --no-backup/--json already shared). EnumMethodsStr is the raw --methods
    // CSV ('' = default all 6, parsed by DoCreateEnumHelper); EnumToString is
    // the raw --tostring value ('' -> tsmRtti default, else 'rtti'|'case').
    EnumMethodsStr: string; // --methods tobyte,frombyte,...
    EnumToString  : string; // --tostring rtti|case
    // Track 3 Batch 1 (Task 1): proptree deep-property enumerator. Depth reuses
    // Depth (--depth; proptree / convert-scaffold resolve --depth > the --rules
    // book's #depth > 5 in ResolveTreeDepth). ToPersistent defaults ON (stop the ancestor climb at
    // TPersistent/TObject); --no-to-persistent turns it OFF.
    ToPersistent  : Boolean; // proptree: stop ancestor climb at TPersistent/TObject (default True)
    RefsAsLeaves  : Boolean; // proptree: TComponent-typed props are reference leaves, not expanded (default False)
    ExactOnly     : Boolean; // query: --exact, suppress the fuzzy fallback (INBOX 2.4)
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
    CastLibFile   : string ; // --castlib <file>  (class + enum cast library)
    GlyphStitch   : Boolean; // --glyph-stitch (convert-apply, convert-validate): realise G-links, N reader check; OFF = refusal
    NoWarnUnlinked: Boolean; // --no-warn-unlinked  (convert-apply: keep the unlinked count, drop the warnings)
    NoReconcileUses: Boolean; // --no-reconcile-uses (convert-apply, C9: the 1.26.6 unit rules exactly)
    NoReindex     : Boolean; // --no-reindex (convert-apply, C9: do not refresh the unit's project DB after --apply)
    UnitProgress  : Boolean; // --progress (convert-apply, 1.33.0 G1: one stderr JSON line per finished unit)
    RaiseEncoding : TArray<string>; // --raise-encoding "<path>=utf8-bom" (convert-apply, 1.34.1 E2; repeatable)
    OldPlatformDbs: TArray<string>; // --old-platform-db <file> (convert-apply, 1.43 ENUMMAP; repeatable)
    PrintParsed   : Boolean; // --print-parsed  (dump parsed rule count + lines)
    // Track 3 Batch 2a-i (Task 8): convert-reemit HIDDEN test verb. FromBlockFile
    // is the --from-block path (one F DFM `object` block, verbatim text).
    FromBlockFile : string ; // --from-block <file>  (F DFM object block file)
    // proptree assignability engine (Task 5): convert-scaffold --surface
    // dfm|pas picks the TARGET (To-side) visibility bar for auto-'#link'
    // matching. '' (default/unset) -> DoConvertScaffold applies 'dfm'.
    Surface       : string ; // convert-scaffold: --surface dfm|pas ('' = default 'dfm')
    // shared-unit (dl:shared marker). The unit is --in and the write switch is
    // --apply -- both already parsed into InFile/Apply, so this command adds one
    // field, not three. A second field for a flag that already exists is how two
    // switches with the same name end up meaning different things.
    AddProjectName: string ; // shared-unit: --add-project <ProjectName>
    // glyph-vacuum: --append merges this run into an existing --output (rows keyed
    // on dfm_path+object_path+property, images keyed on sha) instead of replacing it.
    AppendOut     : Boolean; // glyph-vacuum: --append
    // compare (charts step 1): the old-side sources and the actions. --in/--file, --line,
    // --project, --target, --format, --output, --open and --db are the existing fields.
    CompareOld    : string ; // --old <report|csv|.dot|bundle dir>
    CompareNew    : string ; // --new <same kinds> (two saved outputs; no rerun)
    CompareOldDb  : string ; // --old-db <old.sqlite> (S4)
    CompareCommand: string ; // --command "<id> -Target ... -Project ..."
    Question      : string ; // --question <id>  (with --target; builds the command)
    CompareAuto   : Boolean; // --auto  (old side = newest auto snapshot; with --save writes one)
    CompareSave   : Boolean; // --save
    CompareShow   : string ; // --show <report|csv|bundle> (F4)
    UpdateDoc     : Boolean; // --update-doc (with --in/--line)
    SnapshotDir   : string ; // --snapshot-dir <dir>
    CompareOutRoot: string ; // --out-root <dir>  (compare: where the rerun's per-run bundle folder is made; '' = %TEMP%\drag-lint-reports)
    // 1.52 FRAME F2: flags of the verbs check-init, repo, explain and rules disable / enable.
    // The verb itself lives in its own unit (DRagLint.CLI.CheckInit / .Repo / .Explain / .RuleScope);
    // --in/--file (InFile), --line (RefLine), --rule, --project, --config, --connection (FbConnection),
    // --output, --rules-dir, --json and --format are the existing fields.
    At          : string ; // --at <file>:<line>[:<col>]  (check-init target by position)
    HbExplain   : Boolean; // --explain  (check-init: roots and reasons in the answer)
    MaxRoutines : Integer; // --max-routines N  (check-init budget; 0 = absent / the verb's default, -1 = not a number)
    MaxSeconds  : string ; // --max-seconds S  (check-init wall-clock cap, v152 HBFIX; '' = absent, validated by the verb)
    RepoPath    : string ; // --repo <file.dlrepo>  (repo verbs; '' = derived from --project)
    Replace     : Boolean; // --replace  (repo import-fb / restore)
    RuleScope   : string ; // --scope line|unit|project  (rules disable / enable only; other verbs keep DocForgetScope)
    Reason      : string ; // --reason "<text>"  (rules disable: stored beside the entry)
  end; // record

  /// <summary>The post-apply refresh of the unit's project index (C9,
  /// apply/1 uses_reindex).</summary>
  /// <remarks>
  /// Status: 'done', 'skipped' (Reason says why: no single project
  /// DB holds the unit, nothing was written), 'failed' (the child index
  /// run's exit code is in Reason), 'dry-run' (Db / Project name what --apply
  /// would refresh) or 'off' (--no-reindex / --no-reconcile-uses). Ms is the
  /// child run's wall time.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.Common.pas) ?, declaration (DRagLint.CLI.ConvertApplyJson.pas) ?, DRagLint.CLI.Common.RefreshProjectIndex (DRagLint.CLI.Common.pas) ?, DRagLint.CLI.Common.ReindexOwnerProject (DRagLint.CLI.Common.pas), DRagLint.CLI.ConvertApply.ReindexPreview (DRagLint.CLI.ConvertApply.pas)</para>
  /// <para>Used in units: DRagLint.CLI.Common, DRagLint.CLI.ConvertApply, DRagLint.CLI.ConvertApplyJson</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TUsesReindex = record
    Status : string;
    Db     : string;
    Project: string;
    Reason : string;
    Ms     : Int64;
  end;

{ Declared up here because the MANIFEST index path uses them well before the
  single-root one does, and that is the path tools\reindex-all.ps1 drives. }
const RESOLVER_FP_KEY = 'resolver_fingerprint';

{ The database's own statement of what it IS -- see the long comment at the
  writers further down. Hoisted up here with RESOLVER_FP_KEY because
  NoteIndexFreshnessOnce, immediately below, reads it to decide which repair
  command a staleness note may honestly advise. }
const
  SCAN_TYPE_KEY     = 'scan_type';
  SCAN_TYPE_PROJECT = 'project';
  SCAN_TYPE_LIBRARY = 'library';
  { How many rows a PROJECT scan found outside its own compile closure. Written
    by DoIndex, read by the freshness note below so the advice it gives can be
    honest: `index --project` never visits a non-member, so for those rows the
    note's own remedy cannot work and only --rebuild can. Absent/'' means
    "unknown" (a DB written before this existed), which reads as zero. }
  OUT_OF_CLOSURE_KEY = 'out_of_closure_count';

const
  { <db>.rule-cache-warm.pid: the pid of the background warm of that database. }
  RULE_CACHE_WARM_MARKER_SUFFIX = '.rule-cache-warm.pid';

/// <summary>Writes one whole stdout document -- a JSON document (proptree,
/// convert-apply / convert-reemit, info, query / outline --json, sql) or a text
/// document (proptree's tree, convert-scaffold's book) -- with the same bytes as
/// Write(Output, ADoc), after every pending STDERR byte (engine 1.20.6, T2i).</summary>
/// <param name="ADoc">The complete document, line breaks included. Converted to
/// stdout's code page by the RTL exactly as Write/Writeln would convert it.</param>
/// <remarks>
/// Output and ErrOutput are Text files whose Writeln does NOT flush
/// when the handle is a file or a pipe -- only a console flushes per line -- so
/// before this, a stderr note (even the "(loaded defaults ...)" banner) sat in
/// its 128-byte buffer and reached a merged pipe (the editor runs the engine
/// with stdout and stderr on ONE pipe) AFTER, or split around, the document;
/// and the document itself went out in 128-byte WriteFile calls, which is what
/// made a 37 MB proptree take minutes. Order here: flush ErrOutput, flush
/// Output, write ADoc through a buffer swapped in for the call, flush, restore
/// Output's own 128-byte buffer. The buffer is 1 MiB for a file or a pipe (one
/// write for most documents) and 32 KiB when stdout is a console
/// (GetFileType = FILE_TYPE_CHAR), so no single console WriteFile exceeds 32
/// KiB. Nothing else writes to either stream in between (single-threaded;
/// proptree's progress lines are only emitted while the tree builds).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Convert.DoConvertReemit (DRagLint.CLI.Convert.pas), DRagLint.CLI.Convert.DoConvertScaffold (DRagLint.CLI.Convert.pas), DRagLint.CLI.Convert.DoPropTree (DRagLint.CLI.Convert.pas), DRagLint.CLI.ConvertApply.DoConvertApply (DRagLint.CLI.ConvertApply.pas), DRagLint.CLI.ConvertApply.DoConvertApply.EmitBatchJson (DRagLint.CLI.ConvertApply.pas) (+5 more)</para>
/// <para>Calls: Flush, GetFileType, SetTextBuf, TTextRec, Write</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure WriteStdoutDocument(const ADoc: string);

/// <summary>The version limb of a stored fingerprint whose FIRST limb is `&lt;APrefix&gt;&lt;ver&gt;`, or ''.</summary>
/// <param name="AFingerprint">The stored stamp, e.g. `v=1.39.0-alpha;...`.</param>
/// <param name="APrefix">`v=` (indexer) or `r=` (resolver).</param>
/// <returns>The version text, or '' when the stamp is absent or not in that form.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Common.ResolverVersionOfFingerprint (DRagLint.CLI.Common.pas), DRagLint.CLI.ExtractorVersionOfFingerprint (DRagLint.CLI.pas)</para>
/// <para>Calls: Copy, Pos</para>
/// <para>Returns: ''; if SemiPos &gt; 0 then Copy(Rest, 1, SemiPos - 1)</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FingerprintVersionLimb(const AFingerprint, APrefix: string): string;

/// <summary>The `r=` limb of a stored resolver fingerprint (`r=&lt;ver&gt;;schema=N`), or ''.</summary>
/// <param name="AFingerprint">The stored resolver fingerprint.</param>
/// <returns>The resolver version, or ''.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Common.NoteIndexFreshnessOnce (DRagLint.CLI.Common.pas), DRagLint.CLI.ComputeInfoIndexVerdict (DRagLint.CLI.pas), DRagLint.CLI.ConvertApply.ResolverRefusal (DRagLint.CLI.ConvertApply.pas), DRagLint.CLI.RefuseIfEngineOlderThanDb (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.FingerprintVersionLimb</para>
/// <para>Returns: FingerprintVersionLimb(AFingerprint, RESOLVER_LIMB_PREFIX)</para>
/// <para>Effect-free (proven)</para>
/// <seealso cref="DRagLint.CLI.Common.FingerprintVersionLimb"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolverVersionOfFingerprint(const AFingerprint: string): string;

/// <summary>Adds the staleness fact of ADbPath (`stale`, `stale_files`) to an index-reading verb's JSON envelope (ENG-3).</summary>
/// <param name="AObj">The envelope; nil is ignored.</param>
/// <param name="ADbPath">The index the answer came from.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CallGraph.DoButterfly (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoCallGraph (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoReverseCallTree (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.Schema.DoSchema (DRagLint.CLI.Schema.pas), DRagLint.CLI.Sql.DoSql (DRagLint.CLI.Sql.pas) (+1 more)</para>
/// <para>Calls: Default, DRagLint.CLI.Common.AddLibraryPendingNotes, DRagLint.Index.Freshness.ProbeIndexFreshness, DRagLint.Storage.SQLite.TSQLiteSymbolStore.OpenReadable, ExpandFileName, SameText</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.AddLibraryPendingNotes"/>
/// <seealso cref="DRagLint.Index.Freshness.ProbeIndexFreshness"/>
/// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.OpenReadable"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure AddStalenessPairs(const AObj: TJSONObject; const ADbPath: string);

/// <summary>The command that refreshes AStore, shaped by the database's own scan type: the project-file form for a PROJECT database, the folder form for a library.</summary>
/// <param name="AStore">The open index.</param>
/// <param name="ADbPath">Its path, as printed in the command.</param>
/// <param name="AResolveOnly">True: the cheap re-derive (`--resolve-only`), False: the re-parse.</param>
/// <returns>The command line to advise.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Common.AddLibraryPendingNotes (DRagLint.CLI.Common.pas), DRagLint.CLI.Common.NoteIndexFreshnessOnce (DRagLint.CLI.Common.pas), DRagLint.CLI.ComputeInfoIndexVerdict (DRagLint.CLI.pas), DRagLint.CLI.ConvertApply.ResolverRefusal (DRagLint.CLI.ConvertApply.pas), DRagLint.CLI.FinishLibraryResolve (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetMetaValue, Format, IfThen, SameText</para>
/// <para>Returns: Format('index --project &lt;file.dproj&gt; --db "%s"%s', [ADbPath, Suffix]); Format('index &lt;dir&gt; --db "%s"%s', [ADbPath, Suffix])</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetMetaValue"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IndexRemedyFor(const AStore: ISymbolStore; const ADbPath: string; AResolveOnly: Boolean): string;

/// <summary>Opens ADbPath READ-ONLY for a query verb and validates its schema without any DDL; prints the once-per-process freshness notes.</summary>
/// <param name="ADbPath">The index to open.</param>
/// <param name="AOk">False when the schema is behind (the caller exits nonzero).</param>
/// <param name="AQuiet">True: no schema-behind line (a caller that only sharpens an analysis).</param>
/// <returns>The store; never nil on a successful open -- check AOk.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CallGraph.DoAmbiguousCalls (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoButterfly (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoCallGraph (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoCallPath (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoDumpCallEdges (DRagLint.CLI.CallGraph.pas) (+75 more)</para>
/// <para>Calls: DRagLint.CLI.Common.NoteIndexFreshnessOnce, DRagLint.CLI.Common.NoteIndexIncompleteOnce, DRagLint.CLI.Common.NoteIndexRunInProgressOnce, DRagLint.Core.Interfaces.ISymbolStore.IsSchemaCurrent, DRagLint.Storage.Schema.IsSchemaReadable, DRagLint.Storage.Schema.SchemaUnreadableReason, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create, Format, Writeln</para>
/// <para>Returns: TSQLiteSymbolStore.Create(ADbPath, True)</para>
/// <para>Owns returned: new (caller owns)</para>
/// <para>Mutates: AOk (out)</para>
/// <seealso cref="DRagLint.CLI.Common.NoteIndexFreshnessOnce"/>
/// <seealso cref="DRagLint.CLI.Common.NoteIndexIncompleteOnce"/>
/// <seealso cref="DRagLint.CLI.Common.NoteIndexRunInProgressOnce"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.IsSchemaCurrent"/>
/// <seealso cref="DRagLint.Storage.Schema.IsSchemaReadable"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OpenReadOnlyStore(const ADbPath: string; out AOk: Boolean; AQuiet: Boolean = False): ISymbolStore;

/// <summary>Takes `&lt;db&gt;.indexing.lock` for ADbPath: one index run per database, refused at the start (Gitea drag-lint#17).</summary>
/// <param name="ADbPath">The database an index run writes.</param>
/// <param name="AQuiet">True: no refusal line.</param>
/// <param name="AVerb">The verb named in the refusal.</param>
/// <returns>True when this process holds the lock (also when it already did).</returns>
/// <remarks>
/// Held until ReleaseIndexLock or process exit; the OS releases it however the process dies.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoFbSnapshot (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.DoRefreshFindings (DRagLint.CLI.pas) (+1 more)</para>
/// <para>Calls: CreateFile, DRagLint.CLI.Common.StopStaleWarm, DRagLint.Lint.RuleCache.TRuleCache.SweepStaleTmp, Format, LowerCase, PChar, Sleep, SysErrorMessage, Writeln</para>
/// <para>Returns: False; True</para>
/// <para>Complexity: 12 (cyclomatic, outer body), 42 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.StopStaleWarm"/>
/// <seealso cref="DRagLint.Lint.RuleCache.TRuleCache.SweepStaleTmp"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AcquireIndexLock(const ADbPath: string; AQuiet: Boolean = False; const AVerb: string = 'index'): Boolean;

/// <summary>Gives back the lock AcquireIndexLock took for ADbPath; a no-op when this process holds none.</summary>
/// <param name="ADbPath">The database whose lock is released.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas)</para>
/// <para>Calls: CloseHandle, LowerCase</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ReleaseIndexLock(const ADbPath: string);

/// <summary>True when there is no database to open, having said why on STDERR (B-21); every caller exits 2 on True.</summary>
/// <param name="ADbPath">The resolved database, '' when none.</param>
/// <param name="AVerb">The verb named in the message.</param>
/// <returns>True when the caller must stop.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.CLI.DoCheckUnit (DRagLint.CLI.pas), DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.CLI.DoCycles (DRagLint.CLI.pas) (+17 more)</para>
/// <para>Calls: Writeln</para>
/// <para>Returns: ADbPath = ''</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function NoDbResolved(const ADbPath, AVerb: string): Boolean;

/// <summary>Refuses a run whose EXPLICIT --db list names a file that does not
/// exist. Every missing path is reported -- ordinal, path, repair command -- on
/// stderr; the caller must Exit(2) on False.</summary>
/// <param name="AArgs">Parsed args. ONLY DbPaths (the explicit list) is read.</param>
/// <param name="AVerb">Verb name for the message prefix, e.g. 'proptree'.</param>
/// <returns>True when the run may proceed: no --db was given, or all exist.</returns>
/// <remarks>
/// <para>NoDbResolved's sibling: that one says WHY there is no database, this
/// says WHICH named database is not there.</para>
///
/// <para>WHY IT READS AArgs.DbPaths AND NOT THE RESOLVED LIST. DbPaths is
/// non-empty iff the user typed --db. A manifest-resolved run leaves it empty,
/// and those are already filtered by TDbSelect.Resolve(ARequireExists=True), so
/// manifest runs cannot reach this check -- by construction, not by care.</para>
///
/// <para>WHY STDERR. stdout is the DOCUMENT under --format json|sarif, and an
/// error printed there corrupts what a consumer parses. Exit 2 is the
/// machine-readable signal; the prose is for a human, who sees both streams.</para>
///
/// <para>WHY EVERY MISSING PATH AND NOT THE FIRST. Two typos should cost one run,
/// not two.</para>
///
/// <para>The defect this closes: verbs did `if not TFile.Exists(Db) then
/// Continue`, answering from the databases that happened to exist and exiting 0.
/// `convert-scaffold --db app --db lib-typo` drafted rules from a corpus smaller
/// than the operator named, convert-validate then passed them, and convert-apply
/// rewrote a form on that basis -- each step reporting success.</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CallGraph.DoButterfly (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoReverseCallTree (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.Convert.DoConvertReemit (DRagLint.CLI.Convert.pas), DRagLint.CLI.Convert.DoConvertScaffold (DRagLint.CLI.Convert.pas), DRagLint.CLI.Convert.DoConvertValidate (DRagLint.CLI.Convert.pas) (+33 more)</para>
/// <para>Calls: Flush, Format, Writeln</para>
/// <para>Returns: True; False</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExplicitDbsExist(const AArgs: TArgs; const AVerb: string): Boolean;

/// <summary>True when at least one of the databases is READABLE (schema &gt;= SCHEMA_READ_MIN; 150 SC).</summary>
/// <param name="APaths">Existing database files, as ResolveConsumerDbs returned them.</param>
/// <returns>True on the first store at the current schema; False when every store
///  is stale or cannot be opened.</returns>
/// <remarks>
/// Opens each store directly rather than through OpenReadOnlyStore, so
/// the probe prints neither the schema note nor the freshness note -- the verb's
/// own loop prints them once when it opens the store for real. A store the probe
/// cannot open (zero-byte, corrupt, locked) counts as not current and the probe
/// moves on: a probe must not turn one bad manifest database into a FATAL.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.IsSchemaCurrent, DRagLint.Storage.Schema.IsSchemaReadable, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create</para>
/// <para>Returns: False</para>
/// <para>Catches: Exception (swallowed)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.IsSchemaCurrent"/>
/// <seealso cref="DRagLint.Storage.Schema.IsSchemaReadable"/>
/// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AnyDbSchemaCurrent(const APaths: TArray<string>): Boolean;

/// <summary>Decides what a STALE-SCHEMA database means for the run in hand: a
/// refusal when the operator named it with --db, a skip when the manifest chose
/// it. Reports the refusal on stderr; the caller must Exit(2) on True.</summary>
/// <param name="AArgs">Parsed args. ONLY DbPaths (the explicit list) is read.</param>
/// <param name="AVerb">Verb name for the message prefix, e.g. 'proptree'.</param>
/// <param name="ADbPath">The database whose schema is too old to answer from.</param>
/// <returns>True when the run must refuse (the caller Exit(2)s); False when the
/// caller should Continue to the next database.</returns>
/// <remarks>
/// <para>ExplicitDbsExist's sibling. That one refuses a --db that is not THERE;
/// this one refuses a --db that is too OLD TO ANSWER. Both close one hazard:
/// answering from fewer stores than the operator named, and exiting 0.</para>
///
/// <para>WHY `Length(DbPaths) &gt; 0` IS THE WHOLE TEST. ResolveConsumerDbs
/// returns AArgs.DbPaths UNCHANGED when the user typed --db, so inside these
/// loops the explicit list and the iterated list are the same array -- there is
/// no manifest-derived member to mistake for an explicit one. Testing the LIST
/// rather than matching THIS path also cannot fail OPEN on a spelling or
/// separator difference, which a per-path string comparison could.</para>
///
/// <para>WHY IT REFUSES RATHER THAN WARNS -- the 2026-08-13 ruling, verbatim: a
/// stale DB is not authoritative, and the answer is to RESCAN, not to report.
/// The CLI already agreed for single-DB verbs (`outline --db &lt;v12&gt;` exits
/// non-zero) while the multi-DB loops skipped, so one stale database refused one
/// verb and was quietly dropped by the next -- the same file, two contracts.</para>
///
/// <para>THE COST, STATED PLAINLY: an operator whose standing `--db P --db L`
/// list has a stale L is blocked on EVERY verb until they reindex. That is what
/// the ruling asks for, and it will be felt.</para>
///
/// <para>The schema gap itself (`index schema v12 &lt; v22`) is already named on
/// stderr by OpenReadOnlyStore / OpenWritableStore, so this adds the VERDICT and
/// the REPAIR, not the diagnosis.</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CallGraph.DoButterfly (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoReverseCallTree (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.Convert.ConvertClassIn (DRagLint.CLI.Convert.pas), DRagLint.CLI.Convert.DoConvertScaffold (DRagLint.CLI.Convert.pas), DRagLint.CLI.Convert.DoGlyphVacuum (DRagLint.CLI.Convert.pas) (+33 more)</para>
/// <para>Calls: Flush, Format, Writeln</para>
/// <para>Returns: Length(AArgs.DbPaths) &gt; 0</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function StaleDbRefusesRun(const AArgs: TArgs; const AVerb, ADbPath: string): Boolean;

/// <summary>The ONE database a --project run may treat as its own: the exact
/// manifest owner of the project file, else the documented default
/// &lt;project dir&gt;\_D-RAG\&lt;project base name&gt;.sqlite.</summary>
/// <param name="AManifest">The manifest this run loaded.</param>
/// <param name="AProjectFile">The --project argument (.dproj/.dpr); a relative
/// path resolves against the process CWD, as ResolveProjectDb does.</param>
/// <param name="ADb">Receives the owner's DB path: the section's DB on
/// pdmUnique, the _D-RAG default on pdmNone, '' on pdmAmbiguous.</param>
/// <param name="AClaimants">Receives the names of the sections that claim the
/// project -- two or more on pdmAmbiguous, which is what a refusal names.</param>
/// <returns>pdmUnique, pdmNone or pdmAmbiguous, exactly as ResolveProjectDb.</returns>
/// <remarks>
/// <para>Never consults manifest ORDER or a folder prefix. Before 1.20.4 a
/// --project run with no --db took the FIRST manifest section whose DB existed,
/// and `index --project` wrote an unregistered project into it -- live, into
/// Micronite2027.sqlite. Owner ruling 2026-08-13: the authoritative set is the
/// platform library plus the project's own DB, nothing else; a guessed owner is
/// worse than none.</para>
/// <para>Does not test existence. Whether a missing file is created (index) or
/// refused (every reader) is the caller's decision.</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConsumerDbs.LoadManifestForProject (DRagLint.CLI.ConsumerDbs.pas), DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs (DRagLint.CLI.ConsumerDbs.pas), DRagLint.CLI.ResolveCompileCheckDb (DRagLint.CLI.pas), DRagLint.CLI.ResolveProjectWriteDbIn (DRagLint.CLI.pas), DRagLint.CLI.RunCommand (DRagLint.CLI.pas) (+1 more)</para>
/// <para>Calls: DRagLint.Index.Manifest.ResolveProjectDb, ExpandFileName, ExtractFilePath</para>
/// <para>Returns: ResolveProjectDb(AManifest, AProjectFile, ADb, AClaimants)</para>
/// <para>Mutates: ADb (out)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Index.Manifest.ResolveProjectDb"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveOwnProjectDb(const AManifest: TIndexManifest; const AProjectFile: string;
  out ADb: string; out AClaimants: TArray<string>): TProjectDbMatch;

/// <summary>Writes the refusal for a project that two or more manifest sections
/// claim, naming every claimant, on stderr.</summary>
/// <param name="AVerb">Verb name for the message prefix.</param>
/// <param name="AProjectFile">The project file as the user typed it.</param>
/// <param name="AClaimants">The claiming section names, from ResolveOwnProjectDb.</param>
/// <remarks>
/// Same wording as `resolve-dbs --project`, so the two cannot drift
/// into two instructions for one manifest defect. Naming the claimants IS the
/// fix instruction.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ResolveCompileCheckDb (DRagLint.CLI.pas), DRagLint.CLI.ResolveProjectWriteDbIn (DRagLint.CLI.pas), DRagLint.CLI.UsagesDbForFile (DRagLint.CLI.pas)</para>
/// <para>Calls: Flush, Format, Writeln</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ReportAmbiguousProject(const AVerb, AProjectFile: string; const AClaimants: TArray<string>);

/// <summary>Every database a LIBRARY section of AManifest names, for every
/// platform the section expands to, as expanded absolute paths.</summary>
/// <param name="AManifest">The manifest this run loaded.</param>
/// <returns>The library-section DB paths; empty when the manifest has none.</returns>
/// <remarks>
/// Keyed on the section KIND (ResolvePlan's smLibrary), not on a
/// `library-` file-name prefix: a library section may name its DB anything,
/// and a project DB may happen to start with that prefix.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Common.SplitConsumerDbs (DRagLint.CLI.Common.pas), DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs (DRagLint.CLI.ConsumerDbs.pas), DRagLint.CLI.DoCycles.OpenPlanLibrary (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoUnwith (DRagLint.CLI.pas) (+3 more)</para>
/// <para>Calls: DRagLint.Index.Plan.ResolvePlan, DRagLint.Project.Resolver.TProjectResolver.Create, ExpandFileName</para>
/// <seealso cref="DRagLint.Index.Plan.ResolvePlan"/>
/// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LibrarySectionDbs(const AManifest: TIndexManifest): TArray<string>;

/// <summary>True when ADb is one of ALibraryDbs (case-insensitive, after
/// expansion).</summary>
/// <param name="ALibraryDbs">From LibrarySectionDbs.</param>
/// <param name="ADb">The database path to classify.</param>
/// <returns>True for a library-section database.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Common.SplitConsumerDbs (DRagLint.CLI.Common.pas), DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs (DRagLint.CLI.ConsumerDbs.pas), DRagLint.CLI.DoCycles.OpenPlanLibrary (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas), DRagLint.CLI.DoUnwith (DRagLint.CLI.pas) (+5 more)</para>
/// <para>Calls: ExpandFileName, SameText</para>
/// <para>Returns: False</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsLibrarySectionDb(const ALibraryDbs: TArray<string>; const ADb: string): Boolean;

/// <summary>The resolver fingerprint of AStore, `r=&lt;resolver version&gt;;schema=&lt;expected schema&gt;`: would this build DERIVE different edges?</summary>
/// <param name="AStore">The index.</param>
/// <returns>The fingerprint text.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.CommitAfterResolveOnly (DRagLint.CLI.pas), DRagLint.CLI.CommitIndexerFingerprint (DRagLint.CLI.pas), DRagLint.CLI.Common.NoteIndexFreshnessOnce (DRagLint.CLI.Common.pas), DRagLint.CLI.ComputeInfoIndexVerdict (DRagLint.CLI.pas) (+1 more)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.IsSchemaCurrent, Format</para>
/// <para>Returns: Format('r=%s;schema=%d', [DRAGLINT_RESOLVER_VERSION, Expected])</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.IsSchemaCurrent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolverFingerprint(const AStore: ISymbolStore): string;

/// <summary>Stops the previous background rule-cache warm of a database, named by AMarker; only a process running THIS engine's image is stopped.</summary>
/// <param name="AMarker">`&lt;db&gt;.rule-cache-warm.pid`.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Common.AcquireIndexLock (DRagLint.CLI.Common.pas), DRagLint.CLI.DoWarmRuleCache (DRagLint.CLI.pas)</para>
/// <para>Calls: CloseHandle, Copy, DRagLint.CLI.Common.SameFileIdentity, DRagLint.CLI.Common.WarmQueryImageName, DRagLint.Core.ControlChannel.ControlPipeNameFor, DRagLint.Core.ControlChannel.ControlRequest, ExpandFileName, IntToStr, OpenProcess, ParamStr (+7 more)</para>
/// <para>Complexity: 16 (cyclomatic, outer body), 50 lines (full implementation)</para>
/// <para>Catches: EInOutError (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.SameFileIdentity"/>
/// <seealso cref="DRagLint.CLI.Common.WarmQueryImageName"/>
/// <seealso cref="DRagLint.Core.ControlChannel.ControlPipeNameFor"/>
/// <seealso cref="DRagLint.Core.ControlChannel.ControlRequest"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure StopStaleWarm(const AMarker: string);

/// <summary>Runs `&lt;this exe&gt; index --project &lt;P&gt; --db &lt;D&gt;` as a CHILD process for ARx (C9); never raises.</summary>
/// <param name="ARx">From ReindexPreview with Status 'dry-run'; ends 'done' or 'failed' (the exit code in Reason).</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Common.ReindexOwnerProject (DRagLint.CLI.Common.pas), DRagLint.CLI.ConvertApply.DoConvertApply.RunUnit (DRagLint.CLI.ConvertApply.pas)</para>
/// <para>Calls: Cardinal, CloseHandle, CreateProcess, FillChar, Format, GetEnvironmentVariable, GetExitCodeProcess, ParamStr, PChar, StrToIntDef, SysErrorMessage, TerminateProcess, UniqueString, WaitForSingleObject</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure RefreshProjectIndex(var ARx: TUsesReindex);

/// <summary>An incremental `index --project &lt;AProjectFile&gt; --db &lt;ADbPath&gt;` in a CHILD engine, never the folder form.</summary>
/// <param name="AProjectFile">The .dproj to index.</param>
/// <param name="ADbPath">Its project index.</param>
/// <param name="AVerb">The caller named in the failure line.</param>
/// <returns>True when the child exited 0; on failure the reason goes to stderr.</returns>
/// <remarks>
/// <!-- drag-lint:auto -->The multi-project rename's reindex callback (RefreshOwner's AReindex): an
/// incremental `index --project &lt;AProjectFile&gt; --db &lt;ADbPath&gt;` in a CHILD engine, never
/// the folder form. A child, not DoIndex in-process, because DoIndex writes its progress to STDOUT,
/// which is the lint run's output (and, under --json, a JSON document). True when the child exited
/// 0; on failure its reason goes to stderr and RefreshOwner reports the owner unverified.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConsumerDbs.AutoCreateMissingProjectDb (DRagLint.CLI.ConsumerDbs.pas), DRagLint.CLI.PlanMultiOwnerNaming (DRagLint.CLI.pas), DRagLint.CLI.RenameReach (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.CLI.Common.RefreshProjectIndex, Writeln</para>
/// <para>Returns: Rx.Status = 'done'</para>
/// <seealso cref="DRagLint.CLI.Common.RefreshProjectIndex"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReindexOwnerProject(const AProjectFile, ADbPath: string; const AVerb: string = 'rename'): Boolean;

const
  { Milliseconds per second: proptree / convert progress, the shutdown and ide-release waits, the child re-index. }
  MS_PER_SECOND = 1000;

/// <summary>Prints a "not found" diagnostic: to stderr when the verb was asked for JSON (stdout must stay parseable), to stdout otherwise.</summary>
/// <param name="AJson">The verb's own JSON test -- AsJson, SameText(Format, 'json'), or both, whichever the verb accepts.</param>
/// <param name="AMsg">The diagnostic line.</param>
/// <remarks>
/// The caller passes the test so each verb reads only the output flags it documents (run_flag_verb_map.ps1 attributes a field read to every verb that reaches it).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CallGraph.DoButterfly (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoReverseCallTree (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.Common.ReportNotFound (DRagLint.CLI.Common.pas), DRagLint.CLI.Convert.DoPropTree (DRagLint.CLI.Convert.pas), DRagLint.CLI.DoBookmarks (DRagLint.CLI.pas) (+10 more)</para>
/// <para>Calls: Writeln</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ReportNotFoundFor(AJson: Boolean; const AMsg: string);

/// <summary>Opens ADbPath WRITABLE with the same schema-current guard as OpenReadOnlyStore (proptree's write-back).</summary>
/// <param name="ADbPath">The index to open.</param>
/// <param name="AOk">False when the open failed or the schema is behind (line on stderr).</param>
/// <returns>The store, or nil when the writable open threw (the caller falls back to read-only).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Convert.DoPropTree (DRagLint.CLI.Convert.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.IsSchemaCurrent, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create, Format, Writeln</para>
/// <para>Returns: TSQLiteSymbolStore.Create(ADbPath, False); nil</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Mutates: AOk (out)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.IsSchemaCurrent"/>
/// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OpenWritableStore(const ADbPath: string; out AOk: Boolean): ISymbolStore;

/// <summary>The one place a capped list says so (XERJ item 2): a text note, or `omitted` / `cap` keys in AJson.</summary>
/// <param name="AOmitted">Rows the cap hid (a lower bound when AAtLeast).</param>
/// <param name="ACap">The cap in force.</param>
/// <param name="AAtLeast">True when the reader fetched cap + 1, so AOmitted is a lower bound.</param>
/// <param name="AFlag">The flag that raises the cap, named in the note.</param>
/// <param name="ARerun">The value the note suggests for AFlag.</param>
/// <param name="AJson">When given, receives the keys (always, 0 included) instead of a text note.</param>
/// <param name="AAsJsonStream">True: the text note goes to STDERR (stdout is a bare JSON array).</param>
/// <remarks>
/// The exit code is never touched here.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoQueryText (DRagLint.CLI.pas), DRagLint.CLI.Export.DoTop (DRagLint.CLI.Export.pas)</para>
/// <para>Calls: DRagLint.Core.Model.CapOmittedNote, Max, Writeln</para>
/// <seealso cref="DRagLint.Core.Model.CapOmittedNote"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ReportCap(AOmitted, ACap: Integer; AAtLeast: Boolean; const AFlag: string; ARerun: Integer; AJson: TJSONObject; AAsJsonStream: Boolean);

/// <summary>The text after the last ASep in S (all of S when ASep does not occur).</summary>
/// <param name="S">A dotted / separated name.</param>
/// <param name="ASep">The separator.</param>
/// <returns>The last segment.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Export.EmitEnumsDelphiConst.FlushBlock (DRagLint.CLI.Export.pas), DRagLint.CLI.Wiring.DoImpact (DRagLint.CLI.Wiring.pas)</para>
/// <para>Calls: Copy, LastDelimiter</para>
/// <para>Returns: Copy(S, DotPos + 1, MaxInt); S</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LastSegmentAfter(const S: string; ASep: Char): string;

/// <summary>Prints a "not found" diagnostic: to stderr under --json (stdout must stay parseable JSON), to stdout otherwise.</summary>
/// <param name="AArgs">Parsed arguments; AsJson selects the stream.</param>
/// <param name="AMsg">The diagnostic line.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CallGraph.DoCallGraph (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoCallPath (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoFindCallees (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.DoDocDrift (DRagLint.CLI.pas), DRagLint.CLI.DoFindUnit (DRagLint.CLI.pas) (+4 more)</para>
/// <para>Calls: DRagLint.CLI.Common.ReportNotFoundFor</para>
/// <seealso cref="DRagLint.CLI.Common.ReportNotFoundFor"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ReportNotFound(const AArgs: TArgs; const AMsg: string);

/// <summary>Refuses a WRITING verb whose database came only from a "db" key of a
/// .drag-lint.json found by walking up from the CWD, when the target it writes for is
/// not under that file's folder (1.40 CFG-DBREDIRECT; INBOX 2026-09-29 4b-1).</summary>
/// <param name="AVerb">The verb, for the message.</param>
/// <param name="AArgs">The parsed arguments; DbFromConfig / DbConfigFile say where the db came from.</param>
/// <param name="ATarget">The project or folder the verb writes for; '' when it has none
/// (then a config db is never accepted: a destructive verb must act on a database the
/// user named).</param>
/// <returns>True when the verb must stop (the ERROR is already on stderr; exit 2).</returns>
/// <remarks>
/// `index` has its own, softer rule (it ignores the key with a WARNING and goes on);
/// these verbs have no fallback database, so they stop. --db on the command line always wins.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoFbSnapshot (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.DoRefreshFindings (DRagLint.CLI.pas), DRagLint.CLI.Format.DoPurgeLocals (DRagLint.CLI.Format.pas)</para>
/// <para>Calls: ExtractFilePath, Format, IncludeTrailingPathDelimiter, Writeln</para>
/// <para>Returns: False; True</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ConfigDbRedirectsWrite(const AVerb: string; const AArgs: TArgs; const ATarget: string): Boolean;

/// <summary>The command that builds one plan section's database, as the
/// resolve-dbs never-built NOTE advises it.</summary>
/// <param name="AItem">The plan item whose DbPath has never been built.</param>
/// <param name="AConfigPath">The --config the caller named, or '' for the
/// default manifest lookup; carried into the advice so it reads the same manifest.</param>
/// <returns>"drag-lint index --all --only &lt;Name&gt;", plus " --platform
/// &lt;P&gt;" when the item is a per-platform (library) expansion and
/// " --config &lt;path&gt;" when one was given.</returns>
/// <remarks>
/// --only matches the SECTION name. The advice used to guess it from the
/// DB file's base name, which is wrong for a library ("library-Win64" vs the
/// section "Library") and for a project section ("Foo" for a section "P-Foo"
/// whose DB is _D-RAG\Foo.sqlite): both advised commands exited 2.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoResolveDbsList (DRagLint.CLI.pas), DRagLint.CLI.MissingDbBuildCommand (DRagLint.CLI.pas), DRagLint.CLI.Wiring.DoImpactAllProjects (DRagLint.CLI.Wiring.pas)</para>
/// <para>Calls: AnsiQuotedStr</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IndexSectionCommand(const AItem: TPlanSection; const AConfigPath: string): string;

/// <summary>Splits a consumer DB list into the PROJECT store and the platform
/// LIBRARY store.</summary>
/// <param name="AArgs">Parsed args; an explicit --db list changes the rule.</param>
/// <param name="ADbs">The list, normally ResolveConsumerDbs(AArgs).</param>
/// <param name="AProjectDb">Receives the project store, or '' when there is none.</param>
/// <param name="ALibraryDb">Receives the first existing library-section DB, or ''.</param>
/// <remarks>
/// <para>Manifest-resolved list: the project store is the first EXISTING DB
/// that is not a library section's. A --project with no index of its own gets
/// a library-only list from ResolveConsumerDbs, and before 1.20.4 the "first
/// existing" rule then took the platform library as the project store --
/// exceptions-sync --apply would have harvested RTL/VCL raise sites into the
/// user's unit.</para>
/// <para>Explicit --db list: the first existing DB, whatever it is. The user
/// named it; that is the documented meaning of `--db &lt;proj&gt; --db &lt;lib&gt;`.</para>
/// <para>A manifest that fails to load classifies nothing as a library, and
/// says so on stderr.</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CallGraph.FindCalleesLibraryDb (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.Common.FirstProjectDb (DRagLint.CLI.Common.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.MakeLspContextDbResolver (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.IsLibrarySectionDb, DRagLint.CLI.Common.LibrarySectionDbs, DRagLint.Index.Manifest.TManifestIO.Load, ExtractFilePath, Format, ParamStr, Writeln</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Mutates: AProjectDb (out), ALibraryDb (out)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.IsLibrarySectionDb"/>
/// <seealso cref="DRagLint.CLI.Common.LibrarySectionDbs"/>
/// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Load"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SplitConsumerDbs(const AArgs: TArgs; const ADbs: TArray<string>; out AProjectDb, ALibraryDb: string);

/// <summary>The PROJECT store of a consumer DB list: see SplitConsumerDbs.</summary>
/// <param name="AArgs">Parsed args.</param>
/// <param name="ADbs">The list, normally ResolveConsumerDbs(AArgs).</param>
/// <returns>The project store, or '' -- a verb that writes source from it must
/// then refuse and name --db.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoExceptionsSync (DRagLint.CLI.pas), DRagLint.CLI.Wiring.DoWiring (DRagLint.CLI.Wiring.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.SplitConsumerDbs</para>
/// <seealso cref="DRagLint.CLI.Common.SplitConsumerDbs"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FirstProjectDb(const AArgs: TArgs; const ADbs: TArray<string>): string;

implementation

uses
  Winapi.Windows, System.IOUtils, DRagLint.CLI.LibraryMarker, DRagLint.Core.Versions, System.NetEncoding,
  System.StrUtils, System.DateUtils, System.Diagnostics, System.SyncObjs, System.Math, Data.DB,
  FireDAC.Stan.Async, FireDAC.DApt, DRagLint.Lint.RuleCache, DRagLint.Storage.SQLite, DRagLint.Storage.Schema,
  DRagLint.Core.ControlChannel, DRagLint.Project.Resolver, DRagLint.Index.Freshness;

const
  STDOUT_DOCUMENT_BUFFER = 1 shl 20; // 1 MiB: TFDQuery depth 5 (37 MB) is ~36 WriteFile calls, not ~290,000
  STDOUT_CONSOLE_CHUNK   = 32 shl 10; // 32 KiB: a 1 MiB WriteFile to a CONSOLE handle can fail on older Windows

procedure WriteStdoutDocument(const ADoc: string);
var
  Buf: TBytes;
begin
  Flush(ErrOutput);
  Flush(Output);
  if GetFileType(TTextRec(Output).Handle) = FILE_TYPE_CHAR then SetLength(Buf, STDOUT_CONSOLE_CHUNK)
  else SetLength(Buf, STDOUT_DOCUMENT_BUFFER);
  SetTextBuf(Output, Buf[0], Length(Buf));
  try
    Write(Output, ADoc);
    Flush(Output);
  finally
    SetTextBuf(Output, TTextRec(Output).Buffer, SizeOf(TTextRec(Output).Buffer));
  end;
end;

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
// AQuiet suppresses the schema-behind line. That line goes to STDOUT, and on a
// machine-readable run (`lint --format sarif|json`) it lands INSIDE the document
// and stops it parsing -- the hazard that gates the --fix store in DoLint, and
// that tests/ergonomics/run_pipeline_tests.ps1 pins. A caller that opens a store
// merely to sharpen an analysis (rather than because the user asked for the
// index) has no business printing anything, so it passes True and simply gets
// AOk=False when the schema is behind.
{ Once per process, and that is the whole noise-control strategy. A command may
  open the primary index, a library index and several extra stores; saying the
  same thing about each of them would train the reader to skip the line. The
  FIRST store a command opens is the one it is actually asking about.

  WHERE THIS IS CALLED FROM, AND WHERE IT IS NOT -- stated because the obvious
  reading of "it lives in OpenReadOnlyStore" is WRONG and cost a red test to
  find out. OpenReadOnlyStore has 51 callers, but the CLI ALSO constructs
  TSQLiteSymbolStore directly in 44 places, and `lint-all` is one of them -- so
  putting the probe in the helper alone left the single most important command
  silent while every assertion around it passed vacuously.

  Covered today: OpenReadOnlyStore (query, context, hover, find-unit, per-file
  lint, ...), DoLintAll, DoLintProject. NOT covered: the other direct
  constructions, most of which are write paths or self-tests where a staleness
  note would be noise or actively wrong (the indexer is ABOUT to fix the
  staleness).

  Deliberately not made universal by hooking TSQLiteSymbolStore.Create: that
  would make src\storage depend on src\index, and it would fire during indexing.
  Universal coverage is also exactly the ruling's open "where does the gate
  live" question, which is the owner's to answer, not a side effect of this. }

{ The version limb of a stored fingerprint whose FIRST limb is `<APrefix><ver>`
  (`v=` for the indexer, `r=` for the resolver), or '' when the stamp is absent
  or not in that form. }
function FingerprintVersionLimb(const AFingerprint, APrefix: string): string;
var
  Rest   : string ;
  SemiPos: Integer;
begin
  Result:= '';
  if Pos(APrefix, AFingerprint) <> 1 then Exit;
  Rest   := Copy(AFingerprint, Length(APrefix) + 1, MaxInt);
  SemiPos:= Pos(';', Rest);
  Result := if SemiPos > 0 then Copy(Rest, 1, SemiPos - 1) else Rest;
end;

{ The `r=` limb of a stored resolver fingerprint (`r=<ver>;schema=N`), or ''.
  Read by the never-downgrade refusal and by the freshness note, which must
  both know the DIRECTION of a difference, not only that there is one. }
function ResolverVersionOfFingerprint(const AFingerprint: string): string;
const
  RESOLVER_LIMB_PREFIX = 'r=';
begin
  Result:= FingerprintVersionLimb(AFingerprint, RESOLVER_LIMB_PREFIX);
end;

var GFreshnessNoted: Boolean = False;
    { The last freshness probe and the database it was taken of, so the json
      envelope (AddStalenessPairs) does not sweep the same index twice. }
    GFreshnessDb    : string  = '';
    GFreshnessRep   : TFreshnessReport;


{ Adds the top-level `index_notes` array to an object JSON envelope when ADbPath is marked library-pending. }
procedure AddLibraryPendingNotes(const AObj: TJSONObject; const ADbPath: string);
var
  Remedy: string;
begin
  if (AObj = nil) or (ADbPath = '') or not TFile.Exists(ADbPath) then Exit;
  { 150 TL: the schema read gate -- an index below SCHEMA_READ_MIN gets no note (its statements are never built). }
  var Why: string;
  var Probe: ISymbolStore:= TSQLiteSymbolStore.OpenReadable(ADbPath, Why);
  if Probe = nil then Exit;
  var M: TLibraryMarker:= LibraryMarkerFromJson(Probe.GetMetaValue(LIBRARY_RESOLVE_STATE_META_KEY));
  if M.State <> LIBSTATE_PENDING then Exit;
  Remedy:= 'drag-lint ' + IndexRemedyFor(Probe, ADbPath, {AResolveOnly=}True);
  var Notes: TJSONArray:= TJSONArray.Create;
  var One: TJSONObject:= TJSONObject.Create;
  One.AddPair('db', ADbPath);
  One.AddPair('kind', 'library-pending');
  One.AddPair('reason', M.Reason);
  One.AddPair('since_unix', TJSONNumber.Create(M.SinceUnix));
  One.AddPair('remedy', Remedy);
  Notes.AddElement(One);
  AObj.AddPair('index_notes', Notes);
end;

{ ENG-3 (2026-09-23): THE STALENESS FACT, CARRIED IN THE JSON ENVELOPE.

  The human note ("N of M indexed file(s) changed since this index was built")
  goes to stderr and was never meant to reach a document -- but a consumer that
  merges the two streams, or one that simply cannot see stderr, then parses an
  answer with no way to know it came from a stale index. So the object
  envelopes of the index-reading json verbs carry the fact itself, the way
  sql/1 carries "truncated": "stale" (true only for a PROVEN change -- an index
  too old to carry the freshness stamp is not called stale, matching the note,
  which is silent then too) and "stale_files" (how many indexed files changed).
  Pinned by tests\autotest\run_json_stdout_parses_on_stale_index.ps1. }
procedure AddStalenessPairs(const AObj: TJSONObject; const ADbPath: string);
var
  Rep: TFreshnessReport;
begin
  if AObj = nil then Exit;
  Rep:= Default(TFreshnessReport);
  if (ADbPath <> '') and SameText(ExpandFileName(ADbPath), GFreshnessDb) then Rep:= GFreshnessRep
  else if (ADbPath <> '') and TFile.Exists(ADbPath) then
  begin
    { A local, not an inline temporary: a freshly created object passed
      straight into a const interface parameter is never reference-counted
      and never freed. }
    var Why: string;
    var Probe: ISymbolStore:= TSQLiteSymbolStore.OpenReadable(ADbPath, Why);
    { 150 TL: below SCHEMA_READ_MIN -> no freshness probe (Rep stays default), never an AV }
    if Probe <> nil then Rep:= ProbeIndexFreshness(Probe, 0);
  end;
  AObj.AddPair('stale'      , TJSONBool.Create(Rep.Verdict = fvStale));
  AObj.AddPair('stale_files', TJSONNumber.Create(Rep.Changed));
  AddLibraryPendingNotes(AObj, ADbPath);
end;

{ The command that refreshes AStore, shaped by the database's own scan type.

  A PROJECT database is refreshed through its project file. The advisories used
  to print `index <dir> --db <db>` for every database -- the one form the house
  rules forbid against a project DB, because a folder walk adds every loose .pas
  under the folder and then adopts the widened set as the DB's scope (measured
  2026-09-02: DataCopy 39 -> 72 files). `--resolve-only` is exempt from that
  refusal and harmless, but an operator copying the advice does not know that,
  and the same text without `--resolve-only` is the widening command. So the
  advice names the form that is right for the DB it is printed about. A library
  (folder) database keeps the `<dir>` form, which is correct for it.

  AResolveOnly selects the cheap re-derive (minutes) over the re-parse (hours).
  Guarded by tests\autotest\run_resolver_advice_names_project_form.ps1. }
function IndexRemedyFor(const AStore: ISymbolStore; const ADbPath: string; AResolveOnly: Boolean): string;
var
  ScanType: string;
  Suffix  : string;
begin
  ScanType:= '';
  if AStore <> nil then ScanType:= AStore.GetMetaValue(SCAN_TYPE_KEY);
  Suffix:= if AResolveOnly then ' --resolve-only' else '';
  Result:= if SameText(ScanType, SCAN_TYPE_PROJECT) then Format('index --project <file.dproj> --db "%s"%s', [ADbPath, Suffix]) else Format('index <dir> --db "%s"%s', [ADbPath, Suffix]);
end;

procedure NoteIndexFreshnessOnce(const AStore: ISymbolStore; const ADbPath: string);
var Note: string;
begin
  if GFreshnessNoted or (AStore = nil) then Exit;
  GFreshnessNoted:= True;

  { THE ADVICE MUST BE A COMMAND THIS ENGINE ACCEPTS.

    FreshnessNote says "refresh with: drag-lint index <dir> --db <db>". Since
    5e4d6c6 that is REFUSED against a project database (exit 2, "refusing to
    index a FOLDER into a PROJECT database") -- so on the commonest case of all,
    a project index gone stale because a member unit was saved, the engine was
    telling the operator to run something it rejects.

    Session 61 corrected --help, README.md and the shared C:\Projects\CLAUDE.md
    in the same change that shipped the refusal. It did not correct the runtime
    advice strings, because the DOCS-IN-SYNC guard walks documents and not
    Writeln. Every "use instead" string in this engine carries that same drift
    risk with none of the coverage.

    The wording deliberately MATCHES the refusal message's own "Use instead"
    block, so an operator who hits both sees one consistent instruction.

    FreshnessNote is still the right text for a LIBRARY database -- a folder
    target is exactly what those take -- and for a database with no scan_type,
    where nothing has been established and the older, broader advice is the
    honest one. It keeps its caller for that reason. }
  var Rep: TFreshnessReport:= ProbeIndexFreshness(AStore);
  GFreshnessDb := ExpandFileName(ADbPath);
  GFreshnessRep:= Rep;
  { No try/except: GetMetaValue's contract is to answer '' for a missing table
    AND a missing key, never to raise -- callers read '' as "unknown". Guarding
    it would buy nothing and cost two real findings (bare-except and
    try-except-swallowed). The older reader at the folder refusal still wraps it;
    that predates this and is left alone deliberately. }
  var ScanType: string:= AStore.GetMetaValue(SCAN_TYPE_KEY);
  var OutOfClosure: Integer:= StrToIntDef(AStore.GetMetaValue(OUT_OF_CLOSURE_KEY), 0);

  if (Rep.Verdict = fvStale) and SameText(ScanType, SCAN_TYPE_PROJECT) then
  begin
    var Extra: string:= '';
    if Length(Rep.Examples) > 0 then Extra:= ' e.g. ' + TPath.GetFileName(Rep.Examples[0]);
    Writeln(ErrOutput, Format(
      'drag-lint: note: %d of %d indexed file(s) changed since this index was built%s.' +
      ' Answers may be stale -- this is a PROJECT index, so refresh it with:' +
      ' drag-lint index --project <file.dproj> --db %s   (or: drag-lint index --all --only <Section>)',
      [Rep.Changed, Rep.Checked, Extra, ADbPath]));

    { THE ADVICE ABOVE CAN BE IMPOSSIBLE TO FOLLOW, AND SAYING SO IS THE POINT.

      A project DB can hold rows that are NOT project members -- historically
      from a folder target aimed at a project DB, which widened the scope
      permanently. index --project walks the compile closure, so it never
      visits those rows and can never refresh them; and EvictOutOfScopeFiles is
      bounded to ProjectScopeRoots, so it never removes them either. They are
      immortal, they are counted by the freshness sweep above, and following
      the note's own instruction does NOTHING -- which is exactly the reported
      symptom (INBOX-project-db-permanently-stale, defect 1: 81 of 199 rows on
      this repo's own self-index).

      A standing note nobody can clear is worse than no note: it trains the
      reader to skim every freshness warning, including the ones that matter.
      So when the DB knows it has such rows, the note names the only remedy
      that actually works for them. }
    if OutOfClosure > 0 then
      Writeln(ErrOutput, Format(
        'drag-lint: note: %d of those indexed file(s) lie OUTSIDE this project''s compile closure.' +
        ' They are not project members, so index --project never visits them and CANNOT clear this note.' +
        ' If the changed file(s) are among them, rebuild the scope: drag-lint index --project <file.dproj> --db %s --rebuild',
        [OutOfClosure, ADbPath]));
  end
  else
  begin
    Note:= FreshnessNote(Rep, ADbPath);
    if Note <> '' then Writeln(ErrOutput, Note);

    { A CURRENT INDEX CAN STILL ANSWER WITH ROWS THAT ARE NOT THE PROJECT'S
      (Gitea drag-lint#8). The rows outside the closure are not stale when no
      file changed, so the note above stays silent -- and they still take part
      in every answer: a .dpr copied from another folder counted as one more
      unit-usage user, a deleted unit that every `uses` resolved to. index
      --project reports the count on every run, but whoever only QUERIES never
      sees that output. The database knows; the reader must too. }
    if (OutOfClosure > 0) and SameText(ScanType, SCAN_TYPE_PROJECT) then
      Writeln(ErrOutput, Format(
        'drag-lint: note: %d indexed file(s) lie OUTSIDE this project''s compile closure and may appear in answers.' +
        ' index --project never evicts them; drop them with: drag-lint index --project <file.dproj> --db %s --rebuild',
        [OutOfClosure, ADbPath]));
  end;

  { THE RESOLVE PASS IS A SECOND FRESHNESS QUESTION, AND IT HAD NO VOICE.
    ProbeIndexFreshness answers "was this DB parsed by the current parser?" and
    cannot answer "were its edges derived by the current resolver?" -- two
    different questions with two different remedies (hours vs minutes).

    This is the residual of INBOX-resolve-pass-staleness-has-no-fingerprint, and
    2026-08-31 is why it earned its place: `index --all` skipped the resolve on
    25 of 31 sections and stamped them current, and NOTHING SAID SO. An operator
    watching for a re-resolve had no way to ask whether one was owed. The
    detection is fixed; this makes the answer visible.

    DELIBERATELY IMPLEMENTED HERE AND NOT IN DRagLint.Index.Freshness, which is
    where it naturally belongs. `src\index` is inside the extractor fingerprint's
    hash surface, so editing that unit bills a ~5 hour re-parse of every database
    for a change that alters not one stored parse. The guard is directory-scoped
    -- exactly the flaw DRAGLINT_RESOLVER_VERSION was created to avoid on the
    resolve side -- so the reporting lives on this side of the line until that
    guard is scoped by function too. }
  var Prev: string:= AStore.GetMetaValue(RESOLVER_FP_KEY);
  var Cur : string:= ResolverFingerprint(AStore);
  { THE DIRECTION IS THE ADVICE. "Edges are stale, re-derive" is right when the
    index is OLDER than this build and is exactly the downgrade when it is NEWER
    -- and the old `Prev <> Cur` gave that advice for both (ENG-2). An index
    newer than this build is refused by RefuseIfEngineOlderThanDb anyway, so
    the note says so rather than advising a command that would fail.

    THE ENGINE IS NAMED BY ITS PRODUCT VERSION, THE EDGES BY THE RESOLVER'S
    (Gitea drag-lint#19). "this build is r=1.19.0-alpha" read as the version of
    the exe while `--version` said 1.18.0-alpha. }
  var PrevVer: string:= ResolverVersionOfFingerprint(Prev);
  var Engine : string:= 'drag-lint ' + DRAGLINT_VERSION;
  if Prev = '' then
    Writeln(ErrOutput, Format('  resolver: this index carries NO resolver stamp; this engine (%s) resolves with %s -- its edges will be re-derived on the next index run.', [Engine, Cur]))
  else if (PrevVer <> '') and (CompareDottedVersions(DRAGLINT_RESOLVER_VERSION, PrevVer) < 0) then
    Writeln(ErrOutput, Format('  resolver: edges were derived by a NEWER resolver (%s) than this engine''s (%s, resolver %s) -- reads are fine; ' +
      'an index run with this engine is refused. Use the engine that resolved it.', [Prev, Engine, Cur]))
  else if Prev <> Cur then
    Writeln(ErrOutput, Format('  resolver: edges were derived by resolver %s; this engine (%s) resolves with %s -- re-derive with `%s` (minutes, not a re-parse).',
      [Prev, Engine, Cur, IndexRemedyFor(AStore, ADbPath, {AResolveOnly=}True)]));

  { LIBRARY-FIRST RESOLVE: a DB marked `pending` was resolved without its platform library, so
    callers/callees into the library are missing. A reader never writes the marker and never
    re-resolves; it says the answer is incomplete, once, with the exact remedy. }
  var LibMarker: TLibraryMarker:= LibraryMarkerFromJson(AStore.GetMetaValue(LIBRARY_RESOLVE_STATE_META_KEY));
  if LibMarker.State = LIBSTATE_PENDING then
    Writeln(ErrOutput, LibraryPendingNote(LibMarker, ADbPath, 'drag-lint ' + IndexRemedyFor(AStore, ADbPath, {AResolveOnly=}True)));

  { Every note above is written BEFORE the verb's first stdout line, and most
    are longer than the RTL's 128-byte text buffer, which only flushes per line
    on a console. With stdout and stderr on one pipe (bash, cmd `2>&1`) the tail
    of a note was printed after the results (#27 in plans\correcoes). }
  Flush(ErrOutput);
end;

{ Defined beside AcquireIndexLock: True when THIS process holds ADbPath's index lock. }
function HoldsIndexLock(const ADbPath: string): Boolean; forward;

var GInProgressNoted: string = ''; { lower-cased db paths already noted, ';'-joined }

{ 1.41 IDX-HALFREAD: a reader whose database is being written by an index run RIGHT NOW is
  told so, once per database, on stderr. <db>.indexing.lock is opened DELETE_ON_CLOSE by every
  index run (AcquireIndexLock), so it exists only while a holder lives -- the file walk commits
  every 256 files / 5 s, and between those commits and the end of the calls pass a re-emitted
  file's refs are unresolved. No stdout, no exit code. Guard run_index_halfread_guard.ps1 HR3/HR4. }
procedure NoteIndexRunInProgressOnce(const ADbPath: string);
begin
  var Key: string:= LowerCase(ExpandFileName(ADbPath));
  if (';' + GInProgressNoted).Contains(';' + Key + ';') then Exit;
  if (not TFile.Exists(ADbPath + '.indexing.lock')) or HoldsIndexLock(ADbPath) then Exit;
  GInProgressNoted:= GInProgressNoted + Key + ';';
  Writeln(ErrOutput, Format('NOTE: an index run is writing %s right now -- answers may reflect a partly written ' +
    'index until it finishes.', [ADbPath]));
  Flush(ErrOutput);
end;

var GIncompleteNoted: string = ''; { lower-cased db paths already noted, ';'-joined }

{ 149 IC (148 IX row): a database no index run ever COMPLETED -- an auto-create child killed at its
  timeout after the parse wrote the file, or a --rebuild that did not finish -- is announced by
  EVERY reader, once per database, on stderr. Before, only the run that built it said so, and every
  later run read the half index as complete. The evidence is what CommitIndexerFingerprint writes
  last: no indexer_fingerprint, or rebuild_in_progress still '1'. Silent while an index run holds
  the lock (NoteIndexRunInProgressOnce speaks then, or it is this process's own run). No stdout,
  no exit code. Guard run_autocreate_project_db.ps1 arm N. }
procedure NoteIndexIncompleteOnce(const AStore: ISymbolStore; const ADbPath: string);
begin
  var Key: string:= LowerCase(ExpandFileName(ADbPath));
  if (';' + GIncompleteNoted).Contains(';' + Key + ';') then Exit;
  if TFile.Exists(ADbPath + '.indexing.lock') then Exit;
  var Why: string:=
    if AStore.GetMetaValue(REBUILD_IN_PROGRESS_META_KEY) = '1' then 'a --rebuild of it did not finish'
    else if AStore.GetMetaValue(INDEXER_FINGERPRINT_META_KEY) = '' then 'no index run ever completed it (no indexer fingerprint)'
    else '';
  if Why = '' then Exit;
  GIncompleteNoted:= GIncompleteNoted + Key + ';';
  Writeln(ErrOutput, Format('NOTE: %s is INCOMPLETE -- %s; answers are short until an index run completes it: ' +
    'drag-lint index --project <file.dproj> --db "%s"', [ADbPath, Why, ADbPath]));
  Flush(ErrOutput);
end;

function OpenReadOnlyStore(const ADbPath: string; out AOk: Boolean; AQuiet: Boolean = False): ISymbolStore;
var
  Found   : Integer;
  Expected: Integer;
begin
  Result:= TSQLiteSymbolStore.Create(ADbPath, {AReadOnly=}True);
  { 150 SC: the READ gate is IsSchemaReadable (>= SCHEMA_READ_MIN), not current: an index one
    additive version old answers every read verb (spec 2026-11-09-schema-read-compat.md). }
  Result.IsSchemaCurrent(Found, Expected);
  if IsSchemaReadable(Found) then AOk:= True
  else
  begin
    AOk:= False;
    if not AQuiet then
      { Both forms, because at this point the schema is too old to be trusted to
        tell us which kind of database this is -- scan_type may predate it. The
        folder form alone would be refused on a project index.

        ErrOutput, not Writeln. This line went to STDOUT until 2026-09-14, which
        is why AQuiet exists at all: callers emitting JSON or SARIF had to ask to
        be spared a diagnostic that would corrupt the document they were writing.
        A diagnostic belongs on stderr in EVERY output format, where it needs no
        opt-out -- and where the 11 verbs measured printing it to stdout stop
        corrupting machine-readable output. AQuiet is kept: it still lets a
        caller that reports the schema gap ITSELF avoid saying it twice. }
      Writeln(ErrOutput, Format('index schema v%d < v%d (%s): to migrate, run "drag-lint index --project <file.dproj> --db <db>"'
                   + ' for a project index, or "drag-lint index <dir> --db <db>" for a library index',
                   [Found, SCHEMA_READ_MIN, SchemaUnreadableReason(Found)]));
  end;
  { INDEX FRESHNESS -- the 2026-08-13 owner ruling, warn-only half.
    "A stale DB is not authoritative; the answer is to rescan, not to report."
    Until now nothing said so: a session in THIS repo watched type-name-prefix
    fire on a minutes-old exception class purely because the index had not seen
    it yet, and the finding was plausible, confident and wrong.

    ErrOutput, NOT Writeln -- as the schema line above now is too (both moved
    2026-09-14; the schema one used to go to stdout and corrupt --format sarif,
    which is the reason AQuiet was invented). A note on stderr is safe on every
    output path, so it is not gated on AQuiet.

    Advisory only: no finding, no exit code, no stdout. The ruling's open
    questions -- refuse vs warn vs auto-reindex, and whether the gate lives here
    or per-command -- stay open, and a warning cannot pre-empt them. }
  if AOk then NoteIndexFreshnessOnce(Result, ADbPath);
  NoteIndexRunInProgressOnce(ADbPath);
  if AOk then NoteIndexIncompleteOnce(Result, ADbPath);
end;

var GIndexLocks: TDictionary<string, THandle> = nil;

const
  { A delete-pending lock file is retried this often, this far apart (~2 s). }
  INDEX_LOCK_PENDING_TRIES    = 20;
  INDEX_LOCK_PENDING_SLEEP_MS = 100;

{ ONE INDEX RUN PER DATABASE, REFUSED AT THE START (Gitea drag-lint#17).

  Two `index` runs on one database used to find each other only at the END:
  the second parsed all ~2,000 files and then died on its first big write with
  `FATAL: ... database is locked` (exit 3), after the first had already
  cleared and was refilling the tables -- so for minutes the index answered
  queries with a third of its rows. Measured on ProjectA, 2026-10-09.

  The lock is `<db>.indexing.lock`, opened with NO sharing and DELETE_ON_CLOSE
  and held until the process exits. The operating system releases it when the
  process dies, however it dies, so a killed run never leaves a stale lock
  behind -- the failure mode a PID file would have. Readers (query, lint ...)
  never take it; only the writers that index do. The same process asking again
  for a database it already holds is told yes. }
function AcquireIndexLock(const ADbPath: string; AQuiet: Boolean = False; const AVerb: string = 'index'): Boolean;
begin
  if GIndexLocks = nil then GIndexLocks:= TDictionary<string, THandle>.Create;
  var Key: string:= LowerCase(TPath.GetFullPath(ADbPath));
  if GIndexLocks.ContainsKey(Key) then Exit(True);
  var LockPath: string:= ADbPath + '.indexing.lock';
  { A lock file whose delete is still PENDING -- its holder closed it while a
    scanner or the search indexer still had it open -- answers ACCESS_DENIED
    until that last handle goes. Retry for a moment before calling it a failure. }
  var H: THandle:= INVALID_HANDLE_VALUE;
  var Err: DWORD:= ERROR_SUCCESS;
  for var Attempt: Integer:= 1 to INDEX_LOCK_PENDING_TRIES do
  begin
    H:= CreateFile(PChar(LockPath), GENERIC_WRITE, 0, nil, OPEN_ALWAYS,
      FILE_ATTRIBUTE_NORMAL or FILE_FLAG_DELETE_ON_CLOSE, 0);
    if H <> INVALID_HANDLE_VALUE then Break;
    Err:= GetLastError;
    if (Err <> ERROR_ACCESS_DENIED) or (Attempt = INDEX_LOCK_PENDING_TRIES) then Break;
    Sleep(INDEX_LOCK_PENDING_SLEEP_MS);  // console CLI, no VCL message loop; a 100 ms wait between lock retries
  end;
  if H = INVALID_HANDLE_VALUE then
  begin
    if AQuiet then Exit(False); { the caller words the refusal (index --watch skips a tick) }
    if Err = ERROR_SHARING_VIOLATION then
      Writeln(ErrOutput, Format('ERROR: %s: another index run is writing %s (its lock %s is held). ' +
        'Wait for it to finish -- two runs on one database end with "database is locked" after parsing everything.',
        [AVerb, ADbPath, LockPath]))
    else if Err = ERROR_ACCESS_DENIED then
      Writeln(ErrOutput, Format('ERROR: %s: the lock file %s is still being deleted -- another index run on %s ' +
        'is just finishing, or a scanner holds the file open. Retry in a moment. (%s)',
        [AVerb, LockPath, ADbPath, SysErrorMessage(Err)]))
    else
      Writeln(ErrOutput, Format('ERROR: %s: cannot create the lock file %s: %s', [AVerb, LockPath, SysErrorMessage(Err)]));
    Exit(False);
  end;
  GIndexLocks.Add(Key, H); { held until exit or ReleaseIndexLock; the OS closes and deletes it }
  { 1.39.1: a background warm of this database computes on what this run is about
    to rewrite, and would only find its key moved at the end -- stop it now. }
  StopStaleWarm(ADbPath + RULE_CACHE_WARM_MARKER_SUFFIX);
  { 1.41 WARM-TMP: a warm stopped mid-Save leaves rules-<hash>.json.tmp-<pid>; its writer is gone now. }
  TRuleCache.SweepStaleTmp(ADbPath);
  Result:= True;
end;

{ Gives back the lock AcquireIndexLock took for ADbPath (no-op when this process
  holds none). Called once a run has released its WRITE connection: the rule-cache
  warm that follows only reads, and holding the lock through it (minutes on a large
  project) made a save-reindex or agent reindex of the same database exit 2
  (whole-branch review of 1.39). }
function HoldsIndexLock(const ADbPath: string): Boolean;
begin
  Result:= (GIndexLocks <> nil) and GIndexLocks.ContainsKey(LowerCase(TPath.GetFullPath(ADbPath)));
end;

procedure ReleaseIndexLock(const ADbPath: string);
begin
  if GIndexLocks = nil then Exit;
  var Key: string:= LowerCase(TPath.GetFullPath(ADbPath));
  var H: THandle;
  if not GIndexLocks.TryGetValue(Key, H) then Exit;
  CloseHandle(H);
  GIndexLocks.Remove(Key);
end;

{ ONE PLACE THAT SAYS WHY THERE IS NO DATABASE (2026-08-26).

  Every consumer below used to test TFile.Exists(DbPath) alone. With the cwd
  default gone DbPath can now legitimately be empty, and 'database not found: '
  with a blank path is not a diagnosis. Worse, TFile.Exists was ALREADY tried as
  the fix for the stray-index problem and changed nothing -- a stray that exists
  passes an existence test. Existence is not sufficiency.

  Returns True when there is nothing to open, having said so -- on STDERR
  (B-21, 2026-10-19: it went to stdout, where a caller parsing the verb's
  answer read the refusal AS the answer). Every caller exits 2 on True.
  Pinned by run_nodb_error_on_stderr.ps1. }
function NoDbResolved(const ADbPath, AVerb: string): Boolean;
begin
  Result:= ADbPath = '';
  if not Result then Exit;
  Writeln(ErrOutput, 'ERROR: ', AVerb, ': no --db was given and no project database resolves here.');
  Writeln(ErrOutput, '       Run "drag-lint resolve-dbs" to list the configured databases,');
  Writeln(ErrOutput, '       or pass --db <file.sqlite> explicitly.');
end;

function ExplicitDbsExist(const AArgs: TArgs; const AVerb: string): Boolean;
var
  I    : Integer;
  P    : string ;
  Shown: string ;
begin
  Result:= True;
  for I:= 0 to High(AArgs.DbPaths) do
  begin
    P:= AArgs.DbPaths[I];
    if TFile.Exists(P) then Continue;
    Result:= False;
    Shown:= if P = '' then '(empty)' else P;
    if AArgs.DbFromConfig then
    begin
      { The user typed no --db: name the file that supplied it (INBOX 2026-09-29 item 5). }
      Writeln(ErrOutput, Format('ERROR: %s: --db #%d of %d (the "db" key of %s) does not exist: %s',
        [AVerb, I + 1, Length(AArgs.DbPaths), AArgs.DbConfigFile, Shown]));
      Writeln(ErrOutput, '       A .drag-lint.json "db" counts as an explicit --db and must be an existing index. ' +
        'Nothing was answered.');
    end
    else
    begin
      Writeln(ErrOutput, Format('ERROR: %s: --db #%d of %d does not exist: %s',
        [AVerb, I + 1, Length(AArgs.DbPaths), Shown]));
      Writeln(ErrOutput, '       An explicit --db must be an existing index. Nothing was answered.');
    end;
    Writeln(ErrOutput, '       Find it:  drag-lint resolve-dbs --project <x.dproj>   (or --in <x.pas>)');
    Writeln(ErrOutput, Format('       Build it: drag-lint index --project <x.dproj> --db "%s"', [Shown]));
  end;
  if not Result then Flush(ErrOutput);
end;

function AnyDbSchemaCurrent(const APaths: TArray<string>): Boolean;
var
  Found   : Integer;
  Expected: Integer;
begin
  for var P: string in APaths do
  begin
    try
      var Probe: ISymbolStore:= TSQLiteSymbolStore.Create(P, {AReadOnly=}True);
      Probe.IsSchemaCurrent(Found, Expected);
      if IsSchemaReadable(Found) then Exit(True); // 150 SC: readable counts, as at every read gate
    except  // dl:ok try-except-swallowed@5384 -- probe only: an unopenable store counts as not current; the verb's own open reports it
      on E: Exception do Continue;
    end; // try
  end;
  Result:= False;
end; // function

function StaleDbRefusesRun(const AArgs: TArgs; const AVerb, ADbPath: string): Boolean;
begin
  Result:= Length(AArgs.DbPaths) > 0;
  if not Result then Exit; { manifest-resolved: a stale sibling is not what was asked for }
  Writeln(ErrOutput, Format('ERROR: %s: the explicit --db is at an OLD SCHEMA: %s', [AVerb, ADbPath]));
  Writeln(ErrOutput, '       A stale index is not authoritative. Nothing was answered.');
  Writeln(ErrOutput, Format('       Migrate it: drag-lint index --project <x.dproj> --db "%s"   (project index)', [ADbPath]));
  Writeln(ErrOutput, Format('               or: drag-lint index <dir> --db "%s"                 (library index)', [ADbPath]));
  Flush(ErrOutput);
end;

function ResolveOwnProjectDb(const AManifest: TIndexManifest; const AProjectFile: string;
  out ADb: string; out AClaimants: TArray<string>): TProjectDbMatch;
begin
  Result:= ResolveProjectDb(AManifest, AProjectFile, ADb, AClaimants);
  if Result = pdmAmbiguous then ADb:= ''
  else if (Result = pdmNone) and (AProjectFile <> '') then
    ADb:= TPath.Combine(TPath.Combine(ExtractFilePath(ExpandFileName(AProjectFile)), DRAG_HOME_DIR),
                        TPath.GetFileNameWithoutExtension(AProjectFile) + '.sqlite');
end;

procedure ReportAmbiguousProject(const AVerb, AProjectFile: string; const AClaimants: TArray<string>);
begin
  Writeln(ErrOutput, Format('ERROR: %s: %d manifest sections claim %s -- refusing to guess which index it belongs to.',
                            [AVerb, Length(AClaimants), AProjectFile]));
  for var C: string in AClaimants do Writeln(ErrOutput, '  section: ' + C);
  Writeln(ErrOutput, 'Fix the manifest so exactly one section includes this project file, or pass --db.');
  Flush(ErrOutput);
end;

function LibrarySectionDbs(const AManifest: TIndexManifest): TArray<string>;
var
  Resolver: DRagLint.Project.Resolver.TProjectResolver;
  PS      : TPlanSection;
begin
  Result:= nil;
  Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    for PS in ResolvePlan(AManifest, nil, Resolver).Items do
      if PS.Mode = smLibrary then Result:= Result + [ExpandFileName(PS.DbPath)];
  finally
    Resolver.Free;
  end; // try
end;

function IsLibrarySectionDb(const ALibraryDbs: TArray<string>; const ADb: string): Boolean;
begin
  Result:= False;
  for var L: string in ALibraryDbs do
    if SameText(L, ExpandFileName(ADb)) then Exit(True);
end;

{ The identity of what this build DERIVES from parses it already holds --
  call_edges, type_ancestors, type_helpers, unit_uses targets.

  SEPARATE FROM THE INDEXER FINGERPRINT ON PURPOSE. That one answers "would this
  build PARSE differently?" and a mismatch costs a ~5 hour re-parse of every
  index. This one answers "would it DERIVE different edges?" and a mismatch
  costs a re-resolve measured in minutes -- `index --resolve-only`. Conflating
  them is what left 42 resolve-write commits, one every 2.2 days, moving nothing
  at all while indexes went quietly stale.

  IT CARRIES NO PLATFORM OR PREPROCESS TOKEN, and that is not an oversight: the
  resolve pass consumes symbols and refs that are already in the database, so
  the platform that produced them is the INDEXER's question and is already
  recorded there. Adding it here would invalidate on a change that cannot alter
  a derived edge. The schema is included because a schema migration can change
  the shape of the very tables this pass writes. }
function ResolverFingerprint(const AStore: ISymbolStore): string;
var
  Found, Expected: Integer;
begin
  AStore.IsSchemaCurrent(Found, Expected);
  Result:= Format('r=%s;schema=%d', [DRAGLINT_RESOLVER_VERSION, Expected]);
end;

function WarmQueryImageName(hProcess: THandle; dwFlags: DWORD; lpExeName: PWideChar;  // dl:ok param-name-prefix@4a6c -- REVIEWED 2026-11-22 SLZ-S02: param-name-prefix external Win32 import; parameter names mirror the SDK prototype
  var lpdwSize: DWORD): BOOL; stdcall; external kernel32 name 'QueryFullProcessImageNameW';  // dl:ok param-name-prefix@2a60 -- REVIEWED 2026-11-22 SLZ-S02: param-name-prefix external Win32 import; parameter names mirror the SDK prototype

{ True when A and B name the SAME FILE on disk, compared by volume serial and
  file index rather than by spelling: QueryFullProcessImageName gives the long
  path, while ParamStr(0) keeps whatever spelling the engine was started by --
  an 8.3 short path, or a path through a junction -- so a text compare called
  the engine's own previous warm "another program" and left it running. When
  either file cannot be opened, the spellings are compared after expansion. }
function SameFileIdentity(const A, B: string): Boolean;

  function Identify(const APath: string; out AInfo: TByHandleFileInformation): Boolean;
  var
    H: THandle;
  begin
    Result:= False;
    AInfo:= Default(TByHandleFileInformation);
    H:= CreateFile(PChar(APath), 0, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      nil, OPEN_EXISTING, 0, 0);
    if H = INVALID_HANDLE_VALUE then Exit;
    try
      Result:= GetFileInformationByHandle(H, AInfo);
    finally
      CloseHandle(H);
    end;
  end;

var
  IA, IB: TByHandleFileInformation;
begin
  Result:=
    if Identify(A, IA) and Identify(B, IB) then
      (IA.dwVolumeSerialNumber = IB.dwVolumeSerialNumber)
        and (IA.nFileIndexHigh = IB.nFileIndexHigh) and (IA.nFileIndexLow = IB.nFileIndexLow)
    else
      SameText(ExpandFileName(A), ExpandFileName(B));
end;

{ ONE BACKGROUND WARM PER DATABASE. Every index run starts a warm, and a warm
  of a large project takes minutes, so an edit-index loop would pile them up --
  measured 2026-10-15: three alive at once after three runs -- and every one
  but the newest throws its result away (the index moved under it). The newest
  therefore stops the previous one, named by AMarker (<db>.rule-cache-warm.pid).
  Only a process running THIS engine's image is stopped: a pid the OS has since
  given to another program is left alone.
  1.39.1: an `index` of the database calls this too (AcquireIndexLock), and a warm
  of ANOTHER engine image is asked first over its control channel -- but only
  when that engine's status names this database and nothing else, the shape of a
  warm; an LSP engine that inherited the pid holds a library beside it. }
procedure StopStaleWarm(const AMarker: string);
const
  IMAGE_NAME_CHARS = MAX_PATH * 4; // QueryFullProcessImageName takes long (\\?\) paths
  STOP_WAIT_MS     = 5000;         // how long the stopped warm gets to release the index
  ASK_CONNECT_MS   = 1000;         // WaitNamedPipe for the warm's control pipe
  STATUS_DB_FIELD  = 4;            // status<TAB>pid<TAB>version<TAB>extractor<TAB>db
var
  Pid : Cardinal          ;
  H   : THandle           ;
  Len : DWORD             ;
  Name: array of WideChar ;
begin
  if not TFile.Exists(AMarker) then Exit;
  try
    Pid:= StrToIntDef(Trim(TFile.ReadAllText(AMarker)), 0);
  except
    on E: EInOutError do Pid:= 0; { another warm is rewriting it: nothing to stop }
  end;
  if (Pid = 0) or (Pid = GetCurrentProcessId) then Exit;
  var Db: string:= ExpandFileName(Copy(AMarker, 1, Length(AMarker) - Length(RULE_CACHE_WARM_MARKER_SUFFIX)));
  var Pipe: string:= ControlPipeNameFor(Pid);
  var Reply, Err: string;
  if ControlRequest(Pipe, CONTROL_MSG_STATUS, ASK_CONNECT_MS, Reply, Err) then
  begin
    var Fields: TArray<string>:= Reply.Split([#9]);
    if (Length(Fields) = STATUS_DB_FIELD + 1) and SameText(ExpandFileName(Fields[STATUS_DB_FIELD]), Db)
      and ControlRequest(Pipe, CONTROL_MSG_SHUTDOWN + #9 + IntToStr(STOP_WAIT_MS), ASK_CONNECT_MS, Reply, Err)
      and StartsText(CONTROL_REPLY_EXITING, Reply) then
    begin
      H:= OpenProcess(SYNCHRONIZE, False, Pid);
      if H <> 0 then
      try
        WaitForSingleObject(H, STOP_WAIT_MS);
      finally
        CloseHandle(H);
      end;
      Exit;
    end;
  end;
  H:= OpenProcess(PROCESS_TERMINATE or SYNCHRONIZE or PROCESS_QUERY_LIMITED_INFORMATION_ACCESS, False, Pid);
  if H = 0 then Exit; { already gone }
  try
    SetLength(Name, IMAGE_NAME_CHARS);
    Len:= Length(Name);
    if WarmQueryImageName(H, 0, @Name[0], Len) and SameFileIdentity(string(PChar(@Name[0])), ParamStr(0))
      and TerminateProcess(H, 1) then
      WaitForSingleObject(H, STOP_WAIT_MS);
  finally
    CloseHandle(H);
  end;
end;

{ 1.27.0 (C9): runs `<this exe> index --project <P> --db <D>` -- the
  incremental, sanctioned refresh -- as a CHILD process, so its progress lines
  never reach convert-apply's stdout (a JSON document). ARx must come from
  ReindexPreview with Status 'dry-run'; it ends 'done' or 'failed' (the exit
  code in Reason). Never raises; a failure leaves the converted files as
  written -- only the index is behind, and Reason names the command. A child
  still running after REINDEX_TIMEOUT_MS is TERMINATED and reported 'failed'
  (a hung re-index must not hang convert-apply, nor a batch's later units);
  SQLite rolls its open transaction back, so the DB is left as it was before
  the child's last commit. }
procedure RefreshProjectIndex(var ARx: TUsesReindex);
const
  { An incremental `index --project` after one unit changed takes seconds
    (fixture) to about a minute (a large project's resolve pass); ten
    minutes is far past either and still bounds a hung child. }
  REINDEX_TIMEOUT_MS   = 600000;
  { how long to wait for a terminated child to actually exit }
  REINDEX_KILL_WAIT_MS = 5000;
  { the exit code a terminated child is given }
  REINDEX_KILLED_EXIT  = 1;
  MS_PER_SECOND        = 1000;
var
  SI      : TStartupInfo;
  PI      : TProcessInformation;
  Cmd     : string;
  ExitCode: Cardinal;
  WaitRes : Cardinal;
  WaitErr : string;
  Watch   : TStopwatch;
begin
  Cmd:= Format('"%s" index --project "%s" --db "%s"', [ParamStr(0), ARx.Project, ARx.Db]);
  FillChar(SI, SizeOf(SI), 0);
  SI.cb         := SizeOf(SI);
  SI.dwFlags    := STARTF_USESHOWWINDOW;
  SI.wShowWindow:= SW_HIDE;
  Watch:= TStopwatch.StartNew;
  UniqueString(Cmd);
  if not CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW, nil, nil, SI, PI) then  // dl:ok unsafe-shellexecute@d2cc -- REVIEWED 2026-11-19 SLZ-MARK: spawns this executable's own ParamStr(0)
  begin
    ARx.Status:= 'failed';
    ARx.Reason:= Format('could not start the re-index (%s) -- run: drag-lint index --project "%s" --db "%s"',
      [SysErrorMessage(GetLastError), ARx.Project, ARx.Db]);
    Exit;
  end;
  ExitCode:= 0;
  try
    { TEST SEAM (148 IX): DRAGLINT_TEST_REINDEX_TIMEOUT_MS shortens the wait, so a guard can time a child out. }
    WaitRes:= WaitForSingleObject(PI.hProcess, Cardinal(StrToIntDef(GetEnvironmentVariable('DRAGLINT_TEST_REINDEX_TIMEOUT_MS'), REINDEX_TIMEOUT_MS)));
    WaitErr:= if WaitRes = WAIT_FAILED then SysErrorMessage(GetLastError) else '';
    if WaitRes = WAIT_OBJECT_0 then
      GetExitCodeProcess(PI.hProcess, ExitCode)
    else
    begin
      TerminateProcess(PI.hProcess, REINDEX_KILLED_EXIT);
      WaitForSingleObject(PI.hProcess, REINDEX_KILL_WAIT_MS);
    end;
  finally
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
  end;
  ARx.Ms:= Watch.ElapsedMilliseconds;
  if WaitRes <> WAIT_OBJECT_0 then
  begin
    ARx.Status:= 'failed';
    ARx.Reason:= Format('%s -- the child was terminated; run: drag-lint index --project "%s" --db "%s"',
      [if WaitRes = WAIT_TIMEOUT then Format('index did not finish within %d s', [ARx.Ms div MS_PER_SECOND])
       else 'waiting for the index failed (' + WaitErr + ')', ARx.Project, ARx.Db]);
  end
  else if ExitCode = 0 then ARx.Status:= 'done'
  else
  begin
    ARx.Status:= 'failed';
    ARx.Reason:= Format('index exited %d -- run: drag-lint index --project "%s" --db "%s"', [ExitCode, ARx.Project, ARx.Db]);
  end;
end;

{ The multi-project rename's reindex callback (RefreshOwner's AReindex): an
  incremental `index --project <AProjectFile> --db <ADbPath>` in a CHILD
  engine, never the folder form. A child, not DoIndex in-process, because
  DoIndex writes its progress to STDOUT, which is the lint run's output (and,
  under --json, a JSON document). True when the child exited 0; on failure its
  reason goes to stderr and RefreshOwner reports the owner unverified. }
function ReindexOwnerProject(const AProjectFile, ADbPath: string; const AVerb: string): Boolean;
var
  Rx: TUsesReindex;
begin
  Rx        := Default(TUsesReindex);
  Rx.Project:= AProjectFile;
  Rx.Db     := ADbPath;
  RefreshProjectIndex(Rx);
  Result:= Rx.Status = 'done';
  { 149 IC: AVerb names the caller -- the auto-create path printed 'rename:' too (148 IX). }
  if not Result then Writeln(ErrOutput, 'drag-lint: ' + AVerb + ': reindex failed -- ' + Rx.Reason);
end;

procedure ReportNotFoundFor(AJson: Boolean; const AMsg: string);
begin
  if AJson then Writeln(ErrOutput, AMsg) else Writeln(AMsg);
end; // procedure

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
  except  // dl:ok bare-except@db13 -- REVIEWED 2026-11-19 SLZ-MARK: best-effort probe or file read with a documented fallback; the handler assigns that fallback or exits, so no result is lost silently
    Result:= nil;
    Exit; // writable open failed (locked / read-only file) -> caller falls back
  end;
  if Result.IsSchemaCurrent(Found, Expected) then AOk:= True
  { ErrOutput for the same reason as OpenReadOnlyStore's twin above: proptree
    opens WRITABLE by default, so this -- not that one -- is the line a stale
    `proptree --db <old>` actually printed, and it printed it onto stdout. }
  else
  begin
    AOk:= False;
    Writeln(ErrOutput, Format('index schema v%d < v%d: run "drag-lint index <dir> --db <db>" to migrate', [Found, Expected]));
  end;
end;

{ XERJ item 2: the one place a capped list says so. AOmitted is the number of
  rows the cap hid (a lower bound when AAtLeast: the reader fetched cap + 1).
  AJson, when given, receives `omitted` and `cap` keys (always, 0 included, so
  a consumer can read them unconditionally). Without it the note is a text line
  -- on STDERR when the verb's stdout is a bare JSON array (AAsJsonStream), so
  the array stays parseable. The exit code is never touched here. }
procedure ReportCap(AOmitted, ACap: Integer; AAtLeast: Boolean; const AFlag: string; ARerun: Integer; AJson: TJSONObject; AAsJsonStream: Boolean);
begin
  if AJson <> nil then
  begin
    AJson.AddPair('omitted', TJSONNumber.Create(Max(0, AOmitted)));
    AJson.AddPair('cap'    , TJSONNumber.Create(ACap));
    if AAtLeast and (AOmitted > 0) then AJson.AddPair('omitted_is_lower_bound', TJSONBool.Create(True));
    Exit;
  end;
  if AOmitted <= 0 then Exit;
  if AAsJsonStream then Writeln(ErrOutput, CapOmittedNote(AOmitted, ACap, AAtLeast, AFlag, ARerun))
  else Writeln(CapOmittedNote(AOmitted, ACap, AAtLeast, AFlag, ARerun));
end; // procedure

function LastSegmentAfter(const S: string; ASep: Char): string;
var
  DotPos: Integer;
begin
  DotPos:= LastDelimiter(ASep, S);
  Result:= if DotPos > 0 then Copy(S, DotPos + 1, MaxInt) else S;
end;

procedure ReportNotFound(const AArgs: TArgs; const AMsg: string);
begin
  ReportNotFoundFor(AArgs.AsJson, AMsg);
end; // procedure

function ConfigDbRedirectsWrite(const AVerb: string; const AArgs: TArgs; const ATarget: string): Boolean;
begin
  Result:= False;
  if not AArgs.DbFromConfig then Exit;
  if ATarget <> '' then
  begin
    var CfgDir: string:= IncludeTrailingPathDelimiter(TPath.GetFullPath(ExtractFilePath(AArgs.DbConfigFile)));
    if IncludeTrailingPathDelimiter(TPath.GetFullPath(ATarget)).StartsWith(CfgDir, True) then Exit;
  end;
  Writeln(ErrOutput, Format('ERROR: %s: refusing to write the database named by the "db" key of %s -- ' +
    'that file''s tree does not own this target. Pass --db <file.sqlite> to choose the database.',
    [AVerb, AArgs.DbConfigFile]));
  Result:= True;
end;

function IndexSectionCommand(const AItem: TPlanSection; const AConfigPath: string): string;
begin
  Result:= 'drag-lint index --all --only ' + (if AItem.Name.Contains(' ') or AItem.Name.Contains('"') then '"' + AItem.Name.Replace('"', '\"') + '"' else AItem.Name);
  if AItem.Platform <> '' then Result:= Result + ' --platform ' + AItem.Platform;
  if AConfigPath <> '' then Result:= Result + ' --config ' + AnsiQuotedStr(TPath.GetFullPath(AConfigPath), '"');
end;

procedure SplitConsumerDbs(const AArgs: TArgs; const ADbs: TArray<string>; out AProjectDb, ALibraryDb: string);
var
  LibDbs: TArray<string>;
begin
  AProjectDb:= '';
  ALibraryDb:= '';
  LibDbs    := nil;
  try
    LibDbs:= LibrarySectionDbs(TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir));
  except
    on E: Exception do
    begin
      LibDbs:= nil;
      Writeln(ErrOutput, Format('NOTE: could not load the manifest (%s: %s); no database is treated as the library.',
                                [E.ClassName, E.Message]));
    end;
  end; // try
  for var D: string in ADbs do
  begin
    if not TFile.Exists(D) then Continue;
    var IsLib: Boolean:= IsLibrarySectionDb(LibDbs, D);
    if (ALibraryDb = '') and IsLib then ALibraryDb:= D;
    if (AProjectDb = '') and ((Length(AArgs.DbPaths) > 0) or not IsLib) then AProjectDb:= D;
  end;
end;

function FirstProjectDb(const AArgs: TArgs; const ADbs: TArray<string>): string;
var
  LibDb: string;
begin
  SplitConsumerDbs(AArgs, ADbs, Result, LibDb);
end;

end.
