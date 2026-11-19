unit DRagLint.Lint.InitSections;

{ The project rules on index fact F2 (1.44 lane rulesf2): references inside a unit's initialization or
  finalization section belong to the section symbol, so a section is a node of the call graph.

  THE COMPUTED ORDER. Nothing stores the order units initialize in, and it is not needed: it follows
  from the stored `uses` clauses. It is a depth-first post-order from the .dpr's uses list (unit_uses
  section 'program', in source order), each unit visiting its interface uses, then its implementation
  uses, then taking its place; a unit already being visited is skipped, which is what decides the
  order inside a cycle. Checked against the Win64 compiler on a program with four overlapping
  implementation-uses cycles: the printed order matched this model exactly.

  WHAT FOLLOWS. A unit that uses another without a cycle always initializes after it, so an inversion
  needs a uses cycle. Finalization runs in reverse, so "B initializes after A" is also "B is finalized
  before A". A .dpk has no computed order here: only programs are roots, and a unit no program reaches
  has no position and stays silent. }

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  INIT_ORDER_HAZARD_RULE = 'init-order-hazard';
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  FINALIZATION_AFTER_DEPENDENCY_RULE = 'finalization-after-dependency';
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  HEAVY_INITIALIZATION_RULE = 'heavy-initialization';
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  GLOBAL_NEVER_FREED_RULE = 'global-set-in-initialization-never-freed';

/// <summary>An initialization section reaches a global variable of a unit that initializes LATER in
/// the computed order, and that unit's own initialization is what sets the variable: the read sees
/// the value from before it was set.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <returns>One 'init-order-hazard' warning per (section's unit, later unit, variable), anchored at
/// the call or the reference in the section that starts the path.</returns>
/// <remarks>
/// Not thread-safe. Follows call_edges rows of confidence 'certain' only, so virtual dispatch
/// and callbacks are not walked. A routine that also assigns the variable (lazy creation) or tests it
/// against nil stays silent. An index holding no .dpr has no root and yields nothing.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
/// <para>Calls: DRagLint.Lint.InitSections.RunOrderWalk</para>
/// <para>Returns: RunOrderWalk(AStore, skiInit)</para>
/// <seealso cref="DRagLint.Lint.InitSections.RunOrderWalk"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectInitOrderHazard(const AStore: ISymbolStore): TArray<TLintFinding>;

/// <summary>A finalization section reaches a global variable of a unit that is finalized EARLIER, and
/// that unit's own finalization tears the variable down: the read sees a freed object. Finalization runs
/// in reverse, so "finalized earlier" is "initializes later" in the computed order.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <returns>One 'finalization-after-dependency' warning per (section's unit, earlier unit, variable),
/// anchored at the call or the reference in the section that starts the path.</returns>
/// <remarks>
/// Not thread-safe. The same walk and the same silences as init-order-hazard: certain call
/// edges only; a routine that assigns the variable or tests it against nil stays silent, which covers
/// the FreeAndNil + Assigned idiom. An index holding no .dpr yields nothing.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
/// <para>Calls: DRagLint.Lint.InitSections.RunOrderWalk</para>
/// <para>Returns: RunOrderWalk(AStore, skiFinal)</para>
/// <seealso cref="DRagLint.Lint.InitSections.RunOrderWalk"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectFinalizationAfterDependency(const AStore: ISymbolStore): TArray<TLintFinding>;

/// <summary>An initialization section reaches the file system, the registry, the network, a database or
/// a dialog: work that can fail or block before the application has an exception handler or a window,
/// and that every process using the unit pays for at start.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <param name="ALibraryStore">The platform library index, or nil. A call the project index leaves unresolved is
/// followed into the library routine the index bound it to (refs.external_target, e.g. a method called on a
/// variable) when exactly one library symbol has that qualified name; otherwise when exactly one library routine of
/// that name lives in a unit the calling file uses. A bound target, or a visited library routine, whose qualified
/// name has a heavy TYPE segment (TRegistry, TIniFile, THTTPClient ...) shows that category by itself.</param>
/// <returns>One 'heavy-initialization' hint per section, anchored at the call or reference that starts
/// the first path; the message names each category and a routine that shows it.</returns>
/// <remarks>
/// Not thread-safe. Evidence is positive only: the section's refs and the reached routines'
/// refs against the curated names below, plus symbol_facts.touches (registry, network, transactions)
/// and sql_reads / sql_writes of a reached routine. With a library index the walk also enters library routines
/// (certain library call edges, at most LIBRARY_WALK_DEPTH levels). A path behind an `if` counts, because the index has
/// no branch conditions. TPath alone is not a file access. Certain call edges only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas), DRagLint.Refactor.LazyInit.RunLazyInit (DRagLint.Refactor.LazyInit.pas)</para>
/// <para>Calls: ContainsText, Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolFacts, DRagLint.Lint.InitSections.CollectHeavyInitialization.LoadBound, DRagLint.Lint.InitSections.CollectHeavyInitialization.Note, DRagLint.Lint.InitSections.CollectHeavyInitialization.NoteLibrary, DRagLint.Lint.InitSections.CollectHeavyInitialization.NoteVia, DRagLint.Lint.InitSections.HeavyCategoryOfQName (+13 more)</para>
/// <para>Returns: nil; Findings.ToArray</para>
/// <para>Complexity: 22 (cyclomatic, outer body), 177 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolFacts"/>
/// <seealso cref="DRagLint.Lint.InitSections.CollectHeavyInitialization.LoadBound"/>
/// <seealso cref="DRagLint.Lint.InitSections.CollectHeavyInitialization.Note"/>
/// <seealso cref="DRagLint.Lint.InitSections.CollectHeavyInitialization.NoteLibrary"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectHeavyInitialization(const AStore: ISymbolStore; const ALibraryStore: ISymbolStore = nil): TArray<TLintFinding>;

/// <summary>A unit's initialization sets its own global variable to a new object (`G:= TFoo.Create`) and
/// no source that names the variable frees it, so the object lives to process exit and shows as a leak in
/// every leak report.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <param name="ALibraryStore">The platform library index, or nil. It proves a library type is a class:
/// a record has a Create too (TRegEx, TFormatSettings). Without it only project classes and a short list
/// of common RTL classes count, and any other type is silent.</param>
/// <returns>One 'global-set-in-initialization-never-freed' hint per variable, at the assignment.</returns>
/// <remarks>
/// Not thread-safe. Counts a section's assignment and one in a routine of the unit the section
/// calls. Silent on an interface-typed variable, a type not proven a class, a factory call (only `.Create` proves a new
/// object), an owner argument, FreeOnTerminate, a variable handed to a container or a Register* call, and
/// any text that frees it: the check is lexical, so a free in a comment also silences it.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
/// <para>Calls: Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols, DRagLint.Core.Interfaces.ISymbolStore.FindRefsNamingInFiles, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Lint.InitSections.IsInterfaceTyped, DRagLint.Lint.InitSections.IsProvenClass, DRagLint.Lint.InitSections.TextFreesVariable, DRagLint.Lint.InitSections.TInitGraph.Create (+9 more)</para>
/// <para>Returns: nil; Findings.ToArray</para>
/// <para>Complexity: 18 (cyclomatic, outer body), 78 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindRefsNamingInFiles"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Lint.InitSections.IsInterfaceTyped"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectGlobalNeverFreed(const AStore: ISymbolStore; const ALibraryStore: ISymbolStore = nil): TArray<TLintFinding>;

type
  /// <summary>Lane CYC3 (152c, fabcyc case 3): the verdict of ProveInitOrderInversion.</summary>
  /// <remarks>
  /// Proved True: Text is the plan's proof line ("init order: ..."). Proved False: Text is the reason the
  /// order cannot be proved, worded to follow an init-order refusal after "; ".
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.InitSections.pas) ?, DRagLint.Lint.InitSections.ProveInitOrderInversion (DRagLint.Lint.InitSections.pas)</para>
  /// <para>Used in units: DRagLint.Lint.InitSections</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TInitOrderProof = record
    Proved: Boolean;
    Text  : string;
  end;

/// <summary>Lane CYC3 (152c, fabcyc case 3): may AConsumer's initialization call a routine of ADeclaring through a
/// pointer that ADeclaring's initialization assigns, once the uses rows AConsumer -&gt; ADeclaring are cut? Proved
/// when ADeclaring initializes before AConsumer in the computed order (see this unit's header) of EVERY program of
/// the index that reaches both, both with the uses as they stand and with those rows removed.</summary>
/// <param name="AStore">The project index; nil proves nothing.</param>
/// <param name="AConsumer">The unit whose initialization makes the call (any case).</param>
/// <param name="ADeclaring">The unit that declares the routine and would assign the pointer (any case).</param>
/// <returns>Proved with the proof line, or not proved with one of five reasons: a unit with no single position,
/// AConsumer no longer reaching ADeclaring after the cut (then AConsumer initializes first whatever the .dpr
/// order: always the case in a two-unit cycle), a program where AConsumer comes first (naming both 1-based
/// positions, the .dpr and its entry to list AConsumer before), no program reaching both, or a uses entry that
/// comes from an include or sits in a conditional region in the .dpr, either unit, or a unit on the path that
/// carries AConsumer to ADeclaring after the cut.</returns>
/// <remarks>
/// Not thread-safe; reads the index once per call. Sound subset, default refuse: the order is the one of
/// the index's configuration, so a conditional or include-borne entry on the deciding files refuses. Without the
/// pp_regions facts (an index older than schema 24) every such check refuses. The rule init-order-hazard is the
/// net once a later uses change reverses a proved order.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.FinalOrderVerdict (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.InitOrderVerdict (DRagLint.Report.CycleEdge.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Lint.InitSections.OrderDependsOnConfig, DRagLint.Lint.InitSections.PathAfterCut, DRagLint.Lint.InitSections.TInitGraph.ComputeOrder, DRagLint.Lint.InitSections.TInitGraph.Create, DRagLint.Lint.InitSections.TInitGraph.ProgramFiles, ExtractFileName, Format, LowerCase</para>
/// <para>Returns: Default(TInitOrderProof)</para>
/// <para>Complexity: 16 (cyclomatic, outer body), 75 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Lint.InitSections.OrderDependsOnConfig"/>
/// <seealso cref="DRagLint.Lint.InitSections.PathAfterCut"/>
/// <seealso cref="DRagLint.Lint.InitSections.TInitGraph.ComputeOrder"/>
/// <seealso cref="DRagLint.Lint.InitSections.TInitGraph.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ProveInitOrderInversion(const AStore: ISymbolStore; const AConsumer, ADeclaring: string): TInitOrderProof;

type
  /// <summary>Lane INITAPI (1.52): one unit at its place in a program's initialization order.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.InitSections.pas) ?, DRagLint.Lint.InitSections.ProgramInitOrders (DRagLint.Lint.InitSections.pas), DRagLint.Query.HappensBefore.Roots.LoadRoots (DRagLint.Query.HappensBefore.Roots.pas) ?</para>
  /// <para>Used in units: DRagLint.Lint.InitSections, DRagLint.Query.HappensBefore.Roots</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProgramInitUnit = record
    Name   : string;  { as declared }
    FileId : Int64;
    UnitId : Int64;   { the unit symbol }
    InitId : Int64;   { the initialization section symbol, 0 when the unit has none }
    FinalId: Int64;   { the finalization section symbol, 0 when the unit has none }
  end;

  /// <summary>Lane INITAPI (1.52): the order one program initializes its units in -- the computed order of this
  /// unit's header, the same one init-order-hazard and finalization-after-dependency walk.</summary>
  /// <remarks>
  /// Units: first initialized first; finalization runs in reverse. Unreliable: some uses entry of the
  /// program or of a unit in Units comes from an include or sits in a conditional region, so another
  /// configuration may order the units differently; UnreliableReason names the first such site ('file:line').
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.InitSections.pas) ?, DRagLint.Lint.InitSections.ProgramInitOrders (DRagLint.Lint.InitSections.pas), DRagLint.Query.HappensBefore.Roots.LoadRoots (DRagLint.Query.HappensBefore.Roots.pas) ?</para>
  /// <para>Used in units: DRagLint.Lint.InitSections, DRagLint.Query.HappensBefore.Roots</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProgramInitOrder = record
    ProgramFileId   : Int64;
    ProgramName     : string;  { the program file's name, e.g. 'App.dpr' }
    ProgramBlockId  : Int64;   { the program symbol whose body is the main block, 0 when not indexed }
    Units           : TArray<TProgramInitUnit>;
    Unreliable      : Boolean;
    UnreliableReason: string;
  end;

  /// <summary>Lane INITAPI (1.52, ruling B9a): the answer of InitializesBefore.</summary>
  /// <remarks>
  /// ioaUnplaced: no program of the question places both units (unknown or ambiguous name, no program,
  /// a package). ioaBefore: yes. ioaNotBefore: no (B first, or A = B). ioaConfigDependent: the answer of the
  /// index's configuration rests on a conditional or include-borne uses entry.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.InitSections.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TInitOrderAnswer = (ioaUnplaced, ioaBefore, ioaNotBefore, ioaConfigDependent);

  /// <summary>Lane INITAPI (1.52): the answer of InitializesBefore with its one-line evidence.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.InitSections.pas) ?, DRagLint.Lint.InitSections.AnswerInProgram (DRagLint.Lint.InitSections.pas) ?, DRagLint.Lint.InitSections.InitializesBefore (DRagLint.Lint.InitSections.pas)</para>
  /// <para>Used in units: DRagLint.Lint.InitSections</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TInitOrderVerdict = record
    Answer: TInitOrderAnswer;
    Text  : string;
  end;

/// <summary>Lane INITAPI (1.52, happens-before lane ROOTS step 1): the initialization order of every program of
/// the index, as the init-order rules compute it.</summary>
/// <param name="AStore">The project index; nil yields none.</param>
/// <returns>One entry per program file (a file with a program uses clause), in GetAllFileIds order; a unit no
/// program reaches, or whose name the index holds twice, is in no entry.</returns>
/// <param name="AStop">v152 HOVERCAP: asked per unit while the graph loads and per unit of each order; True ends
/// the walk and the result is PARTIAL. nil (the default) never stops.</param>
/// <remarks>Not thread-safe; reads the index once per call. Nothing is cached between calls. check-init passes
/// its wall-clock check and judges nothing after it returned True, so a partial result never decides.</remarks>
function ProgramInitOrders(const AStore: ISymbolStore; const AStop: TFunc<Boolean> = nil): TArray<TProgramInitOrder>;

/// <summary>Lane INITAPI (1.52, ruling B9a): does AUnitA initialize before AUnitB in AProgram?</summary>
/// <param name="AStore">The project index; nil answers ioaUnplaced.</param>
/// <param name="AProgram">The program file name ('App.dpr') or its base name ('App'), any case; '' asks every
/// program of the index that places both units.</param>
/// <param name="AUnitA">The unit asked about (any case).</param>
/// <param name="AUnitB">The unit it is compared with (any case).</param>
/// <returns>ioaBefore / ioaNotBefore with the positions as evidence ("in `App.dpr` `A` (position 1) ..."),
/// ioaConfigDependent naming the deciding 'file:line', or ioaUnplaced with the reason. With AProgram = '':
/// ioaBefore only when every program placing both says before; ioaConfigDependent when any of them is
/// config-dependent; else ioaNotBefore naming a program where A does not come first.</returns>
/// <remarks>
/// Not thread-safe; reads the index once per call. Sound subset, default refuse: the deciding files are
/// the program and every unit placed at or before the later of the two, plus every unit whose uses reach either
/// (a DFS ancestor placed after them); a conditional or include-borne uses entry in any of them answers
/// ioaConfigDependent. Without the pp_regions facts every answer is ioaConfigDependent.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.FinalOrderVerdict (DRagLint.Report.CycleEdge.pas)</para>
/// <para>Calls: ChangeFileExt, Default, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Lint.InitSections.AnswerInProgram, DRagLint.Lint.InitSections.TInitGraph.ComputeOrder, DRagLint.Lint.InitSections.TInitGraph.Create, DRagLint.Lint.InitSections.TInitGraph.ProgramFiles, ExtractFileName, Format, LowerCase, SameText</para>
/// <para>Returns: Default(TInitOrderVerdict); if NotBefore.Answer &lt;&gt; ioaUnplaced then NotBefore</para>
/// <para>Complexity: 19 (cyclomatic, outer body), 51 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Lint.InitSections.AnswerInProgram"/>
/// <seealso cref="DRagLint.Lint.InitSections.TInitGraph.ComputeOrder"/>
/// <seealso cref="DRagLint.Lint.InitSections.TInitGraph.Create"/>
/// <seealso cref="DRagLint.Lint.InitSections.TInitGraph.ProgramFiles"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function InitializesBefore(const AStore: ISymbolStore; const AProgram, AUnitA, AUnitB: string): TInitOrderVerdict;  // dl:ok unused-public-symbol@5b89 -- REVIEWED 2026-11-17: 1.52 API for lanes HBROOTS and FINCUT (merge after INITAPI); today only tests\fixtures\v152-initapi\InitApiHarness.dpr calls it

implementation

uses
  System.IOUtils
  , System.StrUtils
  , System.Math
  , System.RegularExpressions
  , System.Generics.Collections
  , System.Generics.Defaults
  ;

const
  KIND_UNIT  = 'unit';
  KIND_PROGRAM = 'program';
  USES_KEYWORD_PATTERN = '(^|[^\w.])uses\b';
  REF_WRITE  = 'write';
  REF_CALL   = 'call';
  ALLOCATING_INTRINSICS: array[0..2] of string = ('New', 'GetMem', 'SetLength');
  CONFIDENCE_CERTAIN = 'certain';
  SEVERITY_WARNING = 'warning';
  SEVERITY_HINT = 'hint';
  MESSAGE_INIT_ORDER = 'The initialization of %s reaches %s.%s through %s, but %s initializes after %s in %s: '
    + 'its own initialization has not set the variable yet. Break the uses cycle, or move the call out of the section.';
  MESSAGE_FINAL_ORDER = 'The finalization of %s reaches %s.%s through %s, but %s is finalized before %s in %s: '
    + 'its own finalization has already torn the variable down. Break the uses cycle, or test the variable first.';
  CREATE_STATEMENT_LINES = 3;
  KNOWN_RTL_CLASSES: array[0..16] of string = ('TStringList', 'TList', 'TObjectList', 'TThreadList', 'TInterfaceList', 'TDictionary',
    'TObjectDictionary', 'TQueue', 'TStack', 'TMemoryStream', 'TFileStream', 'TCriticalSection', 'TEvent', 'TComponent',
    'TBitmap', 'TIniFile', 'TMemIniFile');
  NOT_AN_OWNER: array[0..2] of string = ('nil', 'True', 'False');
  COMMENT_LINE = '//';
  COMMENT_PAREN_OPEN = '(*';
  COMMENT_PAREN_CLOSE = '*)';
  ASSIGN_TOKEN = ':=';
  CLOSURE_OPENERS: array[0..3] of string = ('begin', 'case', 'try', 'asm');
  ROUTINE_KEYWORDS: array[0..1] of string = ('function', 'procedure');
  CLOSURE_PREDECESSORS: array[0..3] of string = ('(', ',', '[', ASSIGN_TOKEN);
  REF_MEMBER = 'member-access';
  TOUCH_SEPARATOR = '|';
  CATEGORY_FILE = 'file system';
  CATEGORY_REGISTRY = 'registry';
  CATEGORY_NETWORK = 'network';
  CATEGORY_DATABASE = 'database';
  CATEGORY_DIALOG = 'dialog';
  HEAVY_CATEGORY_ORDER: array[0..4] of string = (CATEGORY_DATABASE, CATEGORY_NETWORK, CATEGORY_FILE, CATEGORY_REGISTRY, CATEGORY_DIALOG);
  HEAVY_TYPES_FILE: array[0..5] of string = ('TFile', 'TDirectory', 'TStreamWriter', 'TFileStream', 'TIniFile', 'TMemIniFile');
  HEAVY_TYPES_REGISTRY: array[0..1] of string = ('TRegistry', 'TRegistryIniFile');
  HEAVY_TYPES_NETWORK: array[0..3] of string = ('THTTPClient', 'TIdHTTP', 'TNetHTTPClient', 'TIdTCPClient');
  HEAVY_BARE_FILE: array[0..3] of string = ('AssignFile', 'Rewrite', 'Reset', 'FindFirst');
  HEAVY_MEMBER_FILE: array[0..1] of string = ('LoadFromFile', 'SaveToFile');
  HEAVY_MEMBER_DB: array[0..3] of string = ('ExecSQL', 'StartTransaction', 'Commit', 'Rollback');
  LIBRARY_WALK_DEPTH = 4;
  LIBRARY_WALK_NODES = 200;
  HEAVY_BARE_DIALOG: array[0..3] of string = ('ShowMessage', 'MessageDlg', 'MessageBox', 'InputBox');

type
  TUnitNode = record
    Name   : string;
    FileId : Int64;
    UnitId : Int64;
    InitId : Int64;  { the initialization section symbol, 0 when the unit has none }
    FinalId: Int64;  { the finalization section symbol, 0 when the unit has none }
  end;

  { A unit-level variable a section gives its state to. }
  TStateVar = record
    UnitKey: string;
    VarName: string;
    DeclKey: string;  { lane CYC3: the unit that declares it -- UnitKey, or a unit UnitKey uses (an R1 pointer's leaf) }
  end;

  TSectionKind = (skiInit, skiFinal);

  { A span of source, 1-based lines. }
  TLineSpan = record
    FromLine, FromCol, ToLine, ToCol: Integer;
  end;

  TInitGraph = class;

  { 1.51.1 B08: the unit-level procedural variables an edgeless call can name, and the routines the
    initialization sections assign them. Read once, on first need; owned by its TInitGraph. }
  TProcVarIndex = class
  private
    FGraph  : TInitGraph;
    FVars   : TObjectDictionary<string, TDictionary<string, Int64>>;
    FTargets: TDictionary<Int64, TArray<Int64>>;
    FLoaded : Boolean;
    function UnitVars(const AKey: string): TDictionary<string, Int64>;
    function ByUses(AFileId: Int64; const ALowerName: string): Int64;
    procedure LoadTargets;
  public
    constructor Create(AGraph: TInitGraph);
    destructor Destroy; override;
    { The unit-level variable an edgeless call names: bound by the ref, or declared by the caller's unit, by
      exactly one unit it uses, or by the unit a qualifier names; 0 when none or shadowed by a local. }
    function VarOf(const ACaller: TSymbol; const AReference: TReference): Int64;
    { The project routines the initialization sections assign to AVarId. }
    function Targets(AVarId: Int64): TArray<Int64>;
  end;

  { The index read once, for the rules of this unit: units, uses, refs by enclosing symbol, call edges. }
  TInitGraph = class  // dl:ok high-response@a5ce -- REVIEWED 2026-11-05: one read-once cache over the store for the four rules of this unit; its methods are short readers, and splitting it would only spread the shared maps
  private
    FStore     : ISymbolStore;
    FUnits     : TDictionary<string, TUnitNode>;
    FAmbiguous : TDictionary<string, Boolean>;
    FByFile    : TDictionary<Int64, string>;
    FUses      : TDictionary<Int64, TArray<string>>;
    FRefsLoaded: TDictionary<Int64, Boolean>;
    FRefs      : TObjectDictionary<Int64, TList<TReference>>;
    FEdges     : TDictionary<Int64, TArray<TCallEdge>>;
    FSymbols   : TDictionary<Int64, TSymbol>;
    FLines     : TDictionary<Int64, TArray<string>>;
    FOwnNames  : TObjectDictionary<Int64, TDictionary<string, Boolean>>;
    FLiveRefs  : TDictionary<Int64, TArray<TReference>>;
    FClosureRef: TDictionary<Int64, Boolean>;
    FProcVars  : TProcVarIndex;
    FStop      : TFunc<Boolean>;  { v152 HOVERCAP: LoadUnits ends early when it answers True; nil never }
    procedure LoadUnits;
    function UsesOfFile(AFileId: Int64): TArray<string>;
    procedure LoadRefsOfFile(AFileId: Int64);
    function LinesOf(AFileId: Int64): TArray<string>;
  public
    constructor Create(const AStore: ISymbolStore; const AStop: TFunc<Boolean> = nil);
    destructor Destroy; override;
    /// <summary>The files whose uses clause is a program's.</summary>
    function ProgramFiles: TArray<Int64>;
    /// <summary>Lower-case unit name -> position in the order AProgram initializes its units.</summary>
    /// <param name="AProgram">The program file (ProgramFiles).</param>
    /// <param name="ASkipFrom">Lane CYC3: with ASkipTo, a lower-case unit whose uses entry ASkipTo is left out,
    /// as if the cut were made; '' (the default) leaves every entry in.</param>
    /// <param name="ASkipTo">Lane CYC3: the lower-case unit of the left-out entry.</param>
    /// <param name="ARoots">Lane CYC3: when not nil, receives lower-case unit -> the program's uses entry
    /// (lower case) whose visit placed it.</param>
    /// <remarks>The caller owns the result.</remarks>
    function ComputeOrder(AProgram: Int64; const ASkipFrom: string = ''; const ASkipTo: string = '';
      ARoots: TDictionary<string, string> = nil): TDictionary<string, Integer>;
    /// <summary>The refs enclosed by ASym that run when ASym runs: a reference inside an anonymous
    /// method's body is left out, since passing a closure does not call it.</summary>
    function RefsOf(const ASym: TSymbol): TArray<TReference>;
    /// <summary>The certain, resolved call edges out of ASymbolId.</summary>
    /// <remarks>1.51.1 B05: an edge whose ref is a member access naming a routine as a VALUE is left out --
    /// `Lane(TFoo.Check)` passes the method, it does not run it. A member access counts as a value when no call
    /// ref shares its site and the routine cannot be called bare there: its address is taken (`@`), it needs an
    /// argument, or it is a procedure (a procedure call statement carries its own call ref).</remarks>
    function EdgesOf(ASymbolId: Int64): TArray<TCallEdge>;
    /// <summary>True when the project index resolved the reference to a certain call edge.</summary>
    function HasEdge(ASymbolId, ARefId: Int64): Boolean;
    /// <summary>The symbol row, read once.</summary>
    function Symbol(AId: Int64): TSymbol;
    /// <summary>Does AFileId's source declare a symbol of this lower-case name?</summary>
    function FileDeclares(AFileId: Int64; const ALowerName: string): Boolean;
    /// <summary>Does AFileId's uses clause name this lower-case unit?</summary>
    function FileUses(AFileId: Int64; const ALowerUnit: string): Boolean;
    /// <summary>The body of ASym, joined; '' when the source cannot be read.</summary>
    function BodyText(const ASym: TSymbol): string;
    /// <summary>The whole source of AFileId; '' when it cannot be read.</summary>
    function FileText(AFileId: Int64): string;
    /// <summary>ACount lines of AFileId from the 1-based ALine, joined.</summary>
    function LineText(AFileId: Int64; ALine, ACount: Integer): string;
    /// <summary>Every routine reachable from ASectionId by certain call edges, breadth first, the section
    /// itself first (its anchor is empty); each with the ref in the section that starts its path.</summary>
    /// <remarks>1.51.1 B08: a call with no edge that names a unit-level procedural variable (declared by the
    /// caller's unit, or by exactly one unit it uses) reaches every project routine an initialization section
    /// assigns to that variable (`P := R` / `P := @R`): the shape `cycles --fix` writes for a routine-call
    /// inversion.</remarks>
    function Reach(ASectionId: Int64): TArray<TPair<TSymbol, TReference>>;
    property Units: TDictionary<string, TUnitNode> read FUnits;
    property ByFile: TDictionary<Int64, string> read FByFile;
    property Store: ISymbolStore read FStore;
  end;

function BodyFirstLine(const ASym: TSymbol): Integer;
begin
  Result:= if ASym.ImplStartLine > 0 then ASym.ImplStartLine else ASym.StartLine;
end;

{ The anonymous method bodies in a routine's text. Lexical, because the index keeps no symbol for one: a
  `function` or `procedure` keyword right after `(`, `,`, `[` or `:=` is an expression (`F: function` and
  `T = function` are types, and a named local routine is followed by its name after any other token), and
  its body runs to the `end` that balances the first `begin`. Comments and strings are skipped. }
function ClosureSpans(const AText: string; AFirstLine: Integer): TArray<TLineSpan>;
var
  I, Line, LineStart, Depth: Integer;
  Prev: string;
  InClosure: Boolean;
  Span: TLineSpan;

  function ColHere: Integer;
  begin
    Result:= I - LineStart;
  end;

  procedure SkipUntil(const AStop: string);
  begin
    while (I <= Length(AText)) and (Copy(AText, I, Length(AStop)) <> AStop) do
    begin
      if AText[I] = #10 then
      begin
        Inc(Line);
        LineStart:= I + 1;
      end;
      Inc(I);
    end;
    Inc(I, Length(AStop));
  end;

begin
  Result:= nil;
  I:= 1;
  Line:= AFirstLine;
  LineStart:= 1;
  Depth:= 0;
  Prev:= '';
  InClosure:= False;
  Span:= Default(TLineSpan);
  while I <= Length(AText) do
  begin
    var C: Char:= AText[I];
    if C = #10 then
    begin
      Inc(Line);
      LineStart:= I + 1;
      Inc(I);
    end
    else if CharInSet(C, [#9, #13, ' ']) then Inc(I)
    else if (C = '/') and (Copy(AText, I, Length(COMMENT_LINE)) = COMMENT_LINE) then
    begin
      while (I <= Length(AText)) and (AText[I] <> #10) do Inc(I);
    end
    else if C = '{' then SkipUntil('}')
    else if (C = '(') and (Copy(AText, I, Length(COMMENT_PAREN_OPEN)) = COMMENT_PAREN_OPEN) then SkipUntil(COMMENT_PAREN_CLOSE)
    else if C = '''' then
    begin
      Inc(I);
      while (I <= Length(AText)) and not CharInSet(AText[I], ['''', #10]) do Inc(I);
      Inc(I);
      Prev:= 'literal';
    end
    else if CharInSet(C, ['A'..'Z', 'a'..'z', '_']) then
    begin
      var From: Integer:= I;
      while (I <= Length(AText)) and CharInSet(AText[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(I);
      var Word: string:= LowerCase(Copy(AText, From, I - From));
      if InClosure then
      begin
        if MatchStr(Word, CLOSURE_OPENERS) then Inc(Depth)
        else if (Word = 'end') and (Depth > 0) then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            Span.ToLine:= Line;
            Span.ToCol:= ColHere;
            Result:= Result + [Span];
            InClosure:= False;
          end;
        end;
      end
      else if MatchStr(Word, ROUTINE_KEYWORDS) and MatchStr(Prev, CLOSURE_PREDECESSORS) then
      begin
        InClosure:= True;
        Depth:= 0;
        Span.FromLine:= Line;
        Span.FromCol:= From - LineStart;
      end;
      Prev:= Word;
    end
    else
    begin
      Prev:= if Copy(AText, I, Length(ASSIGN_TOKEN)) = ASSIGN_TOKEN then ASSIGN_TOKEN else string(C);
      Inc(I, Length(Prev));
    end;
  end;
end;

function IsInsideSpan(const ASpans: TArray<TLineSpan>; ALine, ACol: Integer): Boolean;
begin
  Result:= False;
  for var S in ASpans do
  begin
    var AfterStart: Boolean:= (ALine > S.FromLine) or ((ALine = S.FromLine) and (ACol > S.FromCol));
    var BeforeEnd : Boolean:= (ALine < S.ToLine) or ((ALine = S.ToLine) and (ACol <= S.ToCol));
    if AfterStart and BeforeEnd then Exit(True);
  end;
end;

constructor TInitGraph.Create(const AStore: ISymbolStore; const AStop: TFunc<Boolean>);
begin
  inherited Create;
  FStore     := AStore;
  FStop      := AStop;
  FUnits     := TDictionary<string, TUnitNode>.Create;
  FAmbiguous := TDictionary<string, Boolean>.Create;
  FByFile    := TDictionary<Int64, string>.Create;
  FUses      := TDictionary<Int64, TArray<string>>.Create;
  FRefsLoaded:= TDictionary<Int64, Boolean>.Create;
  FRefs      := TObjectDictionary<Int64, TList<TReference>>.Create([doOwnsValues]);
  FEdges     := TDictionary<Int64, TArray<TCallEdge>>.Create;
  FSymbols   := TDictionary<Int64, TSymbol>.Create;
  FLines     := TDictionary<Int64, TArray<string>>.Create;
  FOwnNames  := TObjectDictionary<Int64, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  FLiveRefs  := TDictionary<Int64, TArray<TReference>>.Create;
  FClosureRef:= TDictionary<Int64, Boolean>.Create;
  FProcVars  := TProcVarIndex.Create(Self);
  LoadUnits;
end;

destructor TInitGraph.Destroy;
begin
  FProcVars.Free;
  FClosureRef.Free;
  FLiveRefs.Free;
  FOwnNames.Free;
  FLines.Free;
  FSymbols.Free;
  FEdges.Free;
  FRefs.Free;
  FRefsLoaded.Free;
  FUses.Free;
  FByFile.Free;
  FAmbiguous.Free;
  FUnits.Free;
  inherited Destroy;
end;

{ A name two units of the index share (a directory index over several projects) has no one position:
  neither stays a node, so such a unit is silent rather than placed by a guess. }
procedure TInitGraph.LoadUnits;
begin
  for var U in FStore.FindSymbolsByKind(KIND_UNIT, False, MaxInt) do
  begin
    if Assigned(FStop) and FStop() then Exit;  { v152 HOVERCAP: a stopped caller discards the graph }
    var Key: string:= LowerCase(U.Name);
    if FUnits.ContainsKey(Key) then
    begin
      FAmbiguous.AddOrSetValue(Key, True);
      Continue;
    end;
    var Node: TUnitNode:= Default(TUnitNode);
    Node.Name  := U.Name;
    Node.FileId:= U.FileId;
    Node.UnitId:= U.Id;
    for var Ch in FStore.FindAllChildSymbols(U.Id) do
    begin
      if Ch.Kind = skInitialization then Node.InitId:= Ch.Id;
      if Ch.Kind = skFinalization then Node.FinalId:= Ch.Id;
    end;
    FUnits.Add(Key, Node);
    FByFile.AddOrSetValue(U.FileId, Key);
  end;
  for var Key in FAmbiguous.Keys do
  begin
    FByFile.Remove(FUnits[Key].FileId);
    FUnits.Remove(Key);
  end;
end;

{ Interface uses first, then implementation uses, each in source order: the order the compiler visits. }
function TInitGraph.UsesOfFile(AFileId: Int64): TArray<string>;
begin
  if FUses.TryGetValue(AFileId, Result) then Exit;
  var Rows: TArray<TUnitUse>:= FStore.GetUnitUsesForFile(AFileId);
  TArray.Sort<TUnitUse>(Rows, TComparer<TUnitUse>.Construct(
    function(const A, B: TUnitUse): Integer
    begin
      Result:= (Ord(A.Section) - Ord(B.Section));
      if Result = 0 then Result:= A.HostLine - B.HostLine;
      if Result = 0 then Result:= A.HostCol - B.HostCol;
    end));
  Result:= nil;
  for var R in Rows do Result:= Result + [LowerCase(R.UnitName)];
  FUses.Add(AFileId, Result);
end;

function TInitGraph.ProgramFiles: TArray<Int64>;
begin
  Result:= nil;
  for var Fid in FStore.GetAllFileIds do
    for var R in FStore.GetUnitUsesForFile(Fid) do
      if R.Section = uusProgram then
      begin
        Result:= Result + [Fid];
        Break;
      end;
end;

function TInitGraph.ComputeOrder(AProgram: Int64; const ASkipFrom, ASkipTo: string;
  ARoots: TDictionary<string, string>): TDictionary<string, Integer>;
var
  Visited: TDictionary<string, Boolean>;
  Order  : TDictionary<string, Integer>;
  Root   : string;

  procedure Visit(const AKey: string);
  var
    Node: TUnitNode;
  begin
    if Visited.ContainsKey(AKey) or not FUnits.TryGetValue(AKey, Node) then Exit;
    Visited.Add(AKey, True);
    for var Dep in UsesOfFile(Node.FileId) do
      if (ASkipFrom = '') or (AKey <> ASkipFrom) or (Dep <> ASkipTo) then Visit(Dep);
    Order.Add(AKey, Order.Count);
    if ARoots <> nil then ARoots.AddOrSetValue(AKey, Root);
  end;

begin
  Order:= TDictionary<string, Integer>.Create;
  Visited:= TDictionary<string, Boolean>.Create;
  try
    for var R in UsesOfFile(AProgram) do
    begin
      Root:= R;
      Visit(R);
    end;
  finally
    Visited.Free;
  end;
  Result:= Order;
end;

procedure TInitGraph.LoadRefsOfFile(AFileId: Int64);
begin
  if FRefsLoaded.ContainsKey(AFileId) then Exit;
  FRefsLoaded.Add(AFileId, True);
  for var R in FStore.GetReferencesFromFile(AFileId) do
  begin
    if R.EnclosingSymbolId = 0 then Continue;
    var L: TList<TReference>;
    if not FRefs.TryGetValue(R.EnclosingSymbolId, L) then
    begin
      L:= TList<TReference>.Create;
      FRefs.Add(R.EnclosingSymbolId, L);
    end;
    L.Add(R);
  end;
end;

function TInitGraph.RefsOf(const ASym: TSymbol): TArray<TReference>;
begin
  if FLiveRefs.TryGetValue(ASym.Id, Result) then Exit;
  LoadRefsOfFile(ASym.FileId);
  var L: TList<TReference>;
  Result:= nil;
  if FRefs.TryGetValue(ASym.Id, L) then
  begin
    var Closures: TArray<TLineSpan>:= ClosureSpans(BodyText(ASym), BodyFirstLine(ASym));
    for var R in L do
      if IsInsideSpan(Closures, R.StartLine, R.StartCol) then FClosureRef.AddOrSetValue(R.Id, True)
      else Result:= Result + [R];
  end;
  FLiveRefs.Add(ASym.Id, Result);
end;

{ True when the routine's parameter list has one parameter without a default: it cannot be called bare. }
function NeedsArgument(const ASignature: string): Boolean;
begin
  Result:= False;
  var Sig: string:= Trim(ASignature);
  if not Sig.StartsWith('(') then Exit;
  var Depth: Integer:= 0;
  var PartStart: Integer:= 2;
  for var I:= 1 to Length(Sig) do
  begin
    if Sig[I] = '(' then Inc(Depth)
    else if Sig[I] = ')' then Dec(Depth);
    if ((Depth = 1) and (Sig[I] = ';')) or (Depth = 0) then
    begin
      var Part: string:= Trim(Copy(Sig, PartStart, I - PartStart));
      if (Part <> '') and not Part.Contains('=') then Exit(True);
      PartStart:= I + 1;
      if Depth = 0 then Break;
    end;
  end;
end;

{ True when the routine returns a value: a ':' after its parameter list (or with none). }
function ReturnsValue(const ASignature: string): Boolean;
begin
  var Sig: string:= Trim(ASignature);
  if not Sig.StartsWith('(') then Exit(Sig.StartsWith(':'));
  var Depth: Integer:= 0;
  for var I:= 1 to Length(Sig) do
  begin
    if Sig[I] = '(' then Inc(Depth)
    else if Sig[I] = ')' then Dec(Depth);
    if Depth = 0 then Exit(Trim(Copy(Sig, I + 1, MaxInt)).StartsWith(':'));
  end;
  Result:= False;
end;

{ 1.51.1 B05: the edge's ref names a routine as a VALUE -- see TInitGraph.EdgesOf. }
function IsValueUse(AGraph: TInitGraph; const ALive: TArray<TReference>; const AEdge: TCallEdge): Boolean;
begin
  Result:= False;
  var Ref: TReference:= Default(TReference);
  for var R in ALive do
    if R.Id = AEdge.RefId then Ref:= R;
  if Ref.Kind <> REF_MEMBER then Exit;
  for var R in ALive do
    if (R.Kind = REF_CALL) and (R.StartLine = Ref.StartLine) and (R.StartCol = Ref.StartCol) then Exit;
  var Target: TSymbol:= AGraph.Symbol(AEdge.TargetSymbolId);
  { A property accessor bound through the property's name runs on every access: only the routine's own name. }
  if not ((Target.Kind in [skProcedure, skFunction, skMethod]) and SameText(Target.Name, Ref.NameText)) then Exit;
  var Before: string:= TrimRight(Copy(AGraph.LineText(Ref.FileId, Ref.StartLine, 1), 1, Ref.StartCol - 1));
  if EndsStr('.', Before) then Before:= TrimRight(Copy(Before, 1, Length(Before) - 1));
  if (Ref.ReceiverText <> '') and EndsText(Ref.ReceiverText, Before) then
    Before:= TrimRight(Copy(Before, 1, Length(Before) - Length(Ref.ReceiverText)));
  Result:= EndsStr('@', Before) or NeedsArgument(Target.Signature) or not ReturnsValue(Target.Signature);
end;

function TInitGraph.EdgesOf(ASymbolId: Int64): TArray<TCallEdge>;
begin
  if FEdges.TryGetValue(ASymbolId, Result) then Exit;
  var Live: TArray<TReference>:= RefsOf(Symbol(ASymbolId));
  Result:= nil;
  for var E in FStore.GetCallEdgesFromSymbol(ASymbolId) do
    if (E.TargetSymbolId > 0) and (E.Confidence = CONFIDENCE_CERTAIN) and not FClosureRef.ContainsKey(E.RefId)
       and not IsValueUse(Self, Live, E) then
      Result:= Result + [E];
  FEdges.Add(ASymbolId, Result);
end;

constructor TProcVarIndex.Create(AGraph: TInitGraph);
begin
  inherited Create;
  FGraph  := AGraph;
  FVars   := TObjectDictionary<string, TDictionary<string, Int64>>.Create([doOwnsValues]);
  FTargets:= TDictionary<Int64, TArray<Int64>>.Create;
end;

destructor TProcVarIndex.Destroy;
begin
  FTargets.Free;
  FVars.Free;
  inherited Destroy;
end;

function TProcVarIndex.UnitVars(const AKey: string): TDictionary<string, Int64>;
begin
  if FVars.TryGetValue(AKey, Result) then Exit;
  Result:= TDictionary<string, Int64>.Create;
  FVars.Add(AKey, Result);
  var Node: TUnitNode;
  if not FGraph.Units.TryGetValue(AKey, Node) then Exit;
  for var Ch in FGraph.Store.FindAllChildSymbols(Node.UnitId) do
    if Ch.Kind = skVarDecl then Result.AddOrSetValue(LowerCase(Ch.Name), Ch.Id);
end;

{ The one unit AFileId uses that declares the variable; 0 when none or more than one. }
function TProcVarIndex.ByUses(AFileId: Int64; const ALowerName: string): Int64;
begin
  Result:= 0;
  var Hits: Integer:= 0;
  for var Dep in FGraph.UsesOfFile(AFileId) do
  begin
    var Id: Int64;
    if UnitVars(Dep).TryGetValue(ALowerName, Id) then
    begin
      Inc(Hits);
      Result:= Id;
    end;
  end;
  if Hits <> 1 then Result:= 0;
end;

function TProcVarIndex.VarOf(const ACaller: TSymbol; const AReference: TReference): Int64;
begin
  if AReference.SymbolId > 0 then
    Exit(if FGraph.Symbol(AReference.SymbolId).Kind = skVarDecl then AReference.SymbolId else 0);
  Result:= 0;
  var Name: string:= LowerCase(AReference.NameText);
  var Qual: string:= LowerCase(AReference.ReceiverText);
  var Own : string;
  if Qual <> '' then
  begin
    { `uB.GProc(..)`: only a unit-name qualifier names a unit-level variable. }
    if FGraph.Units.ContainsKey(Qual) and not UnitVars(Qual).TryGetValue(Name, Result) then Result:= 0;
  end
  else if FGraph.ByFile.TryGetValue(ACaller.FileId, Own) then
  begin
    { A local or parameter of the caller of that name shadows any unit-level variable. }
    var Shadowed: Boolean:= False;
    for var Ch in FGraph.Store.FindAllChildSymbols(ACaller.Id) do
      if LowerCase(Ch.Name) = Name then Shadowed:= True;
    if not Shadowed and not UnitVars(Own).TryGetValue(Name, Result) then Result:= ByUses(ACaller.FileId, Name);
  end;
end;

{ Each initialization section's `P := R` / `P := @R`: the write ref binds P, and the ONE ref after it on that
  line that binds a project routine is R. }
procedure TProcVarIndex.LoadTargets;
begin
  FLoaded:= True;
  for var Pair in FGraph.Units do
  begin
    if Pair.Value.InitId = 0 then Continue;
    var Refs: TArray<TReference>:= FGraph.RefsOf(FGraph.Symbol(Pair.Value.InitId));
    for var W in Refs do
    begin
      if (W.Kind <> REF_WRITE) or (W.SymbolId <= 0) or (FGraph.Symbol(W.SymbolId).Kind <> skVarDecl) then Continue;
      var Routine: Int64:= 0;
      var Hits: Integer:= 0;
      for var R in Refs do
        if (R.StartLine = W.StartLine) and (R.StartCol > W.StartCol) and (R.Kind <> REF_WRITE) and (R.SymbolId > 0)
           and (FGraph.Symbol(R.SymbolId).Kind in [skProcedure, skFunction, skMethod]) then
        begin
          Inc(Hits);
          Routine:= R.SymbolId;
        end;
      if Hits <> 1 then Continue;
      var List: TArray<Int64>;
      if not FTargets.TryGetValue(W.SymbolId, List) then List:= nil;
      FTargets.AddOrSetValue(W.SymbolId, List + [Routine]);
    end;
  end;
end;

function TProcVarIndex.Targets(AVarId: Int64): TArray<Int64>;
begin
  if not FLoaded then LoadTargets;
  if not FTargets.TryGetValue(AVarId, Result) then Result:= nil;
end;

function TInitGraph.HasEdge(ASymbolId, ARefId: Int64): Boolean;
begin
  Result:= False;
  for var E in EdgesOf(ASymbolId) do
    if E.RefId = ARefId then Exit(True);
end;

function TInitGraph.Symbol(AId: Int64): TSymbol;
begin
  if FSymbols.TryGetValue(AId, Result) then Exit;
  Result:= FStore.GetSymbolById(AId);
  FSymbols.Add(AId, Result);
end;

function TInitGraph.FileDeclares(AFileId: Int64; const ALowerName: string): Boolean;
var
  Names: TDictionary<string, Boolean>;
begin
  if not FOwnNames.TryGetValue(AFileId, Names) then
  begin
    Names:= TDictionary<string, Boolean>.Create;
    FOwnNames.Add(AFileId, Names);
    for var S in FStore.FindSymbolsByFile(FStore.GetFilePath(AFileId)) do
      Names.AddOrSetValue(LowerCase(S.Name), True);
  end;
  Result:= Names.ContainsKey(ALowerName);
end;

function TInitGraph.FileUses(AFileId: Int64; const ALowerUnit: string): Boolean;
begin
  Result:= False;
  for var U in UsesOfFile(AFileId) do
    if U = ALowerUnit then Exit(True);
end;

function TInitGraph.LinesOf(AFileId: Int64): TArray<string>;
begin
  if FLines.TryGetValue(AFileId, Result) then Exit;
  Result:= nil;
  var Path: string:= FStore.GetFilePath(AFileId);
  if (Path <> '') and TFile.Exists(Path) then
    try
      Result:= TFile.ReadAllLines(Path);
    except
      on EInOutError do Result:= nil;
      on EEncodingError do Result:= nil;
    end;
  FLines.Add(AFileId, Result);
end;

function TInitGraph.LineText(AFileId: Int64; ALine, ACount: Integer): string;
begin
  var Lines: TArray<string>:= LinesOf(AFileId);
  Result:= '';
  for var I:= ALine to ALine + ACount - 1 do
    if InRange(I, 1, Length(Lines)) then Result:= Result + Lines[I - 1] + sLineBreak;
end;

function TInitGraph.FileText(AFileId: Int64): string;
begin
  Result:= string.Join(sLineBreak, LinesOf(AFileId));
end;

function TInitGraph.BodyText(const ASym: TSymbol): string;
begin
  var First: Integer:= BodyFirstLine(ASym);
  var Last : Integer:= if ASym.ImplEndLine > 0 then ASym.ImplEndLine else ASym.EndLine;
  Result:= LineText(ASym.FileId, First, Last - First + 1);
end;

function TInitGraph.Reach(ASectionId: Int64): TArray<TPair<TSymbol, TReference>>;
begin
  var Section: TSymbol:= Symbol(ASectionId);
  var ById: TDictionary<Int64, TReference>:= TDictionary<Int64, TReference>.Create;
  var Done: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
  var Items: TList<TPair<TSymbol, TReference>>:= TList<TPair<TSymbol, TReference>>.Create;
  try
    for var R in RefsOf(Section) do ById.AddOrSetValue(R.Id, R);
    Done.Add(ASectionId, True);
    Items.Add(TPair<TSymbol, TReference>.Create(Section, Default(TReference)));
    var Head: Integer:= 0;
    while Head < Items.Count do
    begin
      var Item: TPair<TSymbol, TReference>:= Items[Head];
      Inc(Head);
      for var E in EdgesOf(Item.Key.Id) do
      begin
        var Anchor: TReference:= Item.Value;
        if (Item.Key.Id = ASectionId) and not ById.TryGetValue(E.RefId, Anchor) then Continue;
        if not Done.ContainsKey(E.TargetSymbolId) then
        begin
          Done.Add(E.TargetSymbolId, True);
          Items.Add(TPair<TSymbol, TReference>.Create(Symbol(E.TargetSymbolId), Anchor));
        end;
      end;
      { B08: a call through a unit-level procedural variable reaches what the initialization sections assign it. }
      for var R in RefsOf(Item.Key) do
      begin
        if (R.Kind <> REF_CALL) or HasEdge(Item.Key.Id, R.Id) then Continue;
        var VarId: Int64:= FProcVars.VarOf(Item.Key, R);
        if VarId = 0 then Continue;
        var Anchor: TReference:= if Item.Key.Id = ASectionId then R else Item.Value;
        for var T in FProcVars.Targets(VarId) do
          if not Done.ContainsKey(T) then
          begin
            Done.Add(T, True);
            Items.Add(TPair<TSymbol, TReference>.Create(Symbol(T), Anchor));
          end;
      end;
    end;
    Result:= Items.ToArray;
  finally
    Items.Free;
    Done.Free;
    ById.Free;
  end;
end;

{ --------------------------------------------------------------------------------------------- }

{ The part of a receiver text a variable can be: `G.List.Add` gives G; `G[1].X` and `G(y).X` give G. }
function ReceiverHead(const AReceiver: string): string;
begin
  var Stop: Integer:= Length(AReceiver) + 1;
  for var I:= 1 to Length(AReceiver) do
    if CharInSet(AReceiver[I], ['.', '[', '(', '^']) then
    begin
      Stop:= I;
      Break;
    end;
  Result:= LowerCase(Copy(AReceiver, 1, Stop - 1));
end;

{ The body tests the variable against nil, or asks Assigned of it: it knows the variable may be unset. }
function BodyGuardsVariable(const ABody, AVarName: string): Boolean;
begin
  var N: string:= TRegEx.Escape(AVarName);
  Result:= TRegEx.IsMatch(ABody, '\bAssigned\s*\(\s*' + N + '\s*\)|\b' + N + '\s*(<>|=)\s*nil\b|\bnil\s*(<>|=)\s*' + N + '\b',
    [roIgnoreCase]);
end;

type
  { The state one section gives its unit's variables, and the walk that finds who reaches it. }
  TOrderWalk = class
  private
    FGraph   : TInitGraph;
    FKind    : TSectionKind;
    FState   : TDictionary<string, TArray<TStateVar>>;  { lower var name -> the units whose section sets it }
    FFindings: TList<TLintFinding>;
    FSeen    : TDictionary<string, Boolean>;
    function SectionOf(const ANode: TUnitNode): Int64;
    procedure LoadStateOfUnit(const AKey: string; const ANode: TUnitNode);
    function MentionKey(const AReference: TReference): string;
    function IsVisible(const ASym: TSymbol; const AState: TStateVar; const ALowerName: string): Boolean;
    procedure WalkFrom(const AKey: string; const ANode: TUnitNode; const AProgramName: string;
      AOrder: TDictionary<string, Integer>);
    procedure CheckBody(const AKey: string; const ASym: TSymbol; const AAnchor: TReference; AHasAnchor: Boolean;
      const AProgramName: string; AOrder: TDictionary<string, Integer>);
    procedure AddFinding(const AKey: string; const AState: TStateVar; const AVia: TSymbol; const AAnchor: TReference;
      const AProgramName: string);
  public
    constructor Create(AGraph: TInitGraph; AKind: TSectionKind);
    destructor Destroy; override;
    function Run: TArray<TLintFinding>;
  end;

constructor TOrderWalk.Create(AGraph: TInitGraph; AKind: TSectionKind);
begin
  inherited Create;
  FGraph   := AGraph;
  FKind    := AKind;
  FState   := TDictionary<string, TArray<TStateVar>>.Create;
  FFindings:= TList<TLintFinding>.Create;
  FSeen    := TDictionary<string, Boolean>.Create;
end;

destructor TOrderWalk.Destroy;
begin
  FSeen.Free;
  FFindings.Free;
  FState.Free;
  inherited Destroy;
end;

function TOrderWalk.SectionOf(const ANode: TUnitNode): Int64;
begin
  Result:= if FKind = skiInit then ANode.InitId else ANode.FinalId;
end;

{ Which of this unit's own variables its section gives state to: walked from the section through the
  unit's OWN routines only, because `InitUnit;` from a section is the same section by another name.
  Initialization counts a bare write and New(G) / GetMem(G) / SetLength(G); finalization counts any
  mention, since a finalization that names a global is tearing it down. }
procedure TOrderWalk.LoadStateOfUnit(const AKey: string; const ANode: TUnitNode);
begin
  var SecId: Int64:= SectionOf(ANode);
  if SecId = 0 then Exit;
  var Vars: TDictionary<string, string>:= TDictionary<string, string>.Create;
  var Done: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
  var Queue: TQueue<Int64>:= TQueue<Int64>.Create;
  var Marked: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  var Foreign: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    for var Ch in FGraph.Store.FindAllChildSymbols(ANode.UnitId) do
      if Ch.Kind = skVarDecl then Vars.AddOrSetValue(LowerCase(Ch.Name), Ch.Name);
    Queue.Enqueue(SecId);
    Done.Add(SecId, True);
    while Queue.Count > 0 do
    begin
      var Sym: TSymbol:= FGraph.Symbol(Queue.Dequeue);
      var AllocLines: TDictionary<Integer, Boolean>:= TDictionary<Integer, Boolean>.Create;
      try
        for var R in FGraph.RefsOf(Sym) do
          if (R.Kind = REF_CALL) and (R.ReceiverText = '') and MatchText(R.NameText, ALLOCATING_INTRINSICS) then
            AllocLines.AddOrSetValue(R.StartLine, True);
        for var R in FGraph.RefsOf(Sym) do
        begin
          var Name: string:= if R.ReceiverText = '' then LowerCase(R.NameText) else ReceiverHead(R.ReceiverText);
          var Counts: Boolean:= if FKind = skiInit then (R.ReceiverText = '') and ((R.Kind = REF_WRITE) or AllocLines.ContainsKey(R.StartLine)) else True;
          if Counts and Vars.ContainsKey(Name) then Marked.AddOrSetValue(Name, True)
          else if Counts and (FKind = skiInit) and (R.ReceiverText = '') and (R.Kind = REF_WRITE) then
            Foreign.AddOrSetValue(Name, True);
        end;
      finally
        AllocLines.Free;
      end;
      for var E in FGraph.EdgesOf(Sym.Id) do
        if (not Done.ContainsKey(E.TargetSymbolId)) and (FGraph.Symbol(E.TargetSymbolId).FileId = ANode.FileId) then
        begin
          Done.Add(E.TargetSymbolId, True);
          Queue.Enqueue(E.TargetSymbolId);
        end;
    end;
    for var Name in Marked.Keys do
    begin
      var S: TStateVar:= Default(TStateVar);
      S.UnitKey:= AKey;
      S.VarName:= Vars[Name];
      S.DeclKey:= AKey;
      var List: TArray<TStateVar>;
      if not FState.TryGetValue(Name, List) then List:= nil;
      FState.AddOrSetValue(Name, List + [S]);
    end;
    { Lane CYC3: the section also sets a unit-level variable that exactly one unit of its uses clause declares -- the
      shape `cycles --fix` writes for a routine-call inversion (the pointer lives in a leaf, the declaring unit assigns
      it first in its initialization): a reader that initializes earlier sees nil. }
    for var Name in Foreign.Keys do
    begin
      var S: TStateVar:= Default(TStateVar);
      var Hits: Integer:= 0;
      for var Dep in FGraph.UsesOfFile(ANode.FileId) do
      begin
        var DNode: TUnitNode;
        if not FGraph.Units.TryGetValue(Dep, DNode) then Continue;
        for var Ch in FGraph.Store.FindAllChildSymbols(DNode.UnitId) do
          if (Ch.Kind = skVarDecl) and (LowerCase(Ch.Name) = Name) then
          begin
            Inc(Hits);
            S.VarName:= Ch.Name;
            S.DeclKey:= Dep;
          end;
      end;
      if Hits <> 1 then Continue;
      S.UnitKey:= AKey;
      var List: TArray<TStateVar>;
      if not FState.TryGetValue(Name, List) then List:= nil;
      FState.AddOrSetValue(Name, List + [S]);
    end;
  finally
    Foreign.Free;
    Marked.Free;
    Queue.Free;
    Done.Free;
    Vars.Free;
  end;
end;

{ The lower-case name this ref can be a global by, or '': bare, or at the head of a receiver, or qualified
  by a unit name (`uB.GList`). }
function TOrderWalk.MentionKey(const AReference: TReference): string;
begin
  if AReference.ReceiverText = '' then Exit(LowerCase(AReference.NameText));
  var Head: string:= ReceiverHead(AReference.ReceiverText);
  Result:= if FGraph.Units.ContainsKey(Head) then LowerCase(AReference.NameText) else Head;
end;

{ Scope, by the name alone (a read ref carries no symbol id): inside the unit itself a local or a parameter
  of the routine wins, and so does a member of its class; from another unit the file must use the unit and
  declare nothing of that name. }
function TOrderWalk.IsVisible(const ASym: TSymbol; const AState: TStateVar; const ALowerName: string): Boolean;
begin
  var Owner: string;
  if not FGraph.ByFile.TryGetValue(ASym.FileId, Owner) then Owner:= '';
  if Owner <> AState.DeclKey then
    Exit(FGraph.FileUses(ASym.FileId, AState.DeclKey) and not FGraph.FileDeclares(ASym.FileId, ALowerName));
  Result:= True;
  for var Ch in FGraph.Store.FindAllChildSymbols(ASym.Id) do
    if LowerCase(Ch.Name) = ALowerName then Exit(False);
  var Parent: TSymbol:= FGraph.Symbol(ASym.ParentId);
  if Parent.Kind in [skClass, skRecord] then
    for var Ch in FGraph.Store.FindAllChildSymbols(Parent.Id) do
      if LowerCase(Ch.Name) = ALowerName then Exit(False);
end;

procedure TOrderWalk.AddFinding(const AKey: string; const AState: TStateVar; const AVia: TSymbol;
  const AAnchor: TReference; const AProgramName: string);
begin
  var DedupKey: string:= AKey + '|' + AState.UnitKey + '|' + AState.DeclKey + '|' + LowerCase(AState.VarName);
  if FSeen.ContainsKey(DedupKey) then Exit;
  FSeen.Add(DedupKey, True);
  var Later: string:= FGraph.Units[AState.UnitKey].Name;
  var Own  : string:= FGraph.Units[AKey].Name;
  var F: TLintFinding:= Default(TLintFinding);
  F.RuleId    := if FKind = skiInit then INIT_ORDER_HAZARD_RULE else FINALIZATION_AFTER_DEPENDENCY_RULE;
  F.Severity  := SEVERITY_WARNING;
  F.FileId    := FGraph.Units[AKey].FileId;
  F.FilePath  := FGraph.Store.GetFilePath(F.FileId);
  F.StartLine := AAnchor.StartLine;
  F.StartCol  := AAnchor.StartCol;
  F.EndLine   := AAnchor.EndLine;
  F.EndCol    := AAnchor.EndCol;
  F.SymbolName:= AState.VarName;
  var Pattern: string:= if FKind = skiInit then MESSAGE_INIT_ORDER else MESSAGE_FINAL_ORDER;
  F.Message:= Format(Pattern, [Own, FGraph.Units[AState.DeclKey].Name, AState.VarName, AVia.QualifiedName, Later, Own,
    AProgramName]);
  FFindings.Add(F);
end;

procedure TOrderWalk.CheckBody(const AKey: string; const ASym: TSymbol; const AAnchor: TReference; AHasAnchor: Boolean;
  const AProgramName: string; AOrder: TDictionary<string, Integer>);
begin
  var Body: string:= '';
  for var R in FGraph.RefsOf(ASym) do
  begin
    var Name: string:= MentionKey(R);
    var States: TArray<TStateVar>;
    if not FState.TryGetValue(Name, States) then Continue;
    for var S in States do
    begin
      var PosA, PosB: Integer;
      if not (AOrder.TryGetValue(AKey, PosA) and AOrder.TryGetValue(S.UnitKey, PosB) and (PosB > PosA)) then Continue;
      if not IsVisible(ASym, S, Name) then Continue;
      if Body = '' then Body:= FGraph.BodyText(ASym);
      if BodyGuardsVariable(Body, S.VarName) then Continue;
      var WritesIt: Boolean:= False;
      for var W in FGraph.RefsOf(ASym) do
        if (W.Kind = REF_WRITE) and (W.ReceiverText = '') and (LowerCase(W.NameText) = Name) then WritesIt:= True;
      if WritesIt then Continue;
      AddFinding(AKey, S, ASym, if AHasAnchor then AAnchor else R, AProgramName);
    end;
  end;
end;

procedure TOrderWalk.WalkFrom(const AKey: string; const ANode: TUnitNode; const AProgramName: string;
  AOrder: TDictionary<string, Integer>);
begin
  var IsSection: Boolean:= True;
  for var Item in FGraph.Reach(SectionOf(ANode)) do
  begin
    CheckBody(AKey, Item.Key, Item.Value, not IsSection, AProgramName, AOrder);
    IsSection:= False;
  end;
end;

function TOrderWalk.Run: TArray<TLintFinding>;
begin
  for var Pair in FGraph.Units do LoadStateOfUnit(Pair.Key, Pair.Value);
  if FState.Count > 0 then
    for var Prog in FGraph.ProgramFiles do
    begin
      var ProgName: string:= TPath.GetFileName(FGraph.Store.GetFilePath(Prog));
      var Order: TDictionary<string, Integer>:= FGraph.ComputeOrder(Prog);
      try
        for var Pair in FGraph.Units do
          if (SectionOf(Pair.Value) <> 0) and Order.ContainsKey(Pair.Key) then
            WalkFrom(Pair.Key, Pair.Value, ProgName, Order);
      finally
        Order.Free;
      end;
    end;
  Result:= FFindings.ToArray;
end;

function RunOrderWalk(const AStore: ISymbolStore; AKind: TSectionKind): TArray<TLintFinding>;
begin
  Result:= nil;
  if AStore = nil then Exit;
  var Graph: TInitGraph:= TInitGraph.Create(AStore);
  try
    var Walk: TOrderWalk:= TOrderWalk.Create(Graph, AKind);
    try
      Result:= Walk.Run;
    finally
      Walk.Free;
    end;
  finally
    Graph.Free;
  end;
end;

{ What one ref shows, or '' for nothing. TYPE names count anywhere, as a receiver or as the ref itself;
  a member name only as a member, a bare routine only with no receiver: `Reset` and `Commit` are ordinary
  names. TPath is not here: it computes strings. }
function HeavyCategoryOfRef(const AReference: TReference): string;
begin
  var Head: string:= ReceiverHead(AReference.ReceiverText);
  var Name: string:= AReference.NameText;
  var IsBare: Boolean:= AReference.ReceiverText = '';
  var IsCall: Boolean:= (AReference.Kind = REF_CALL) or (AReference.Kind = REF_MEMBER);
  Result:=
    if MatchText(Head, HEAVY_TYPES_FILE) or MatchText(Name, HEAVY_TYPES_FILE) then CATEGORY_FILE
    else if MatchText(Head, HEAVY_TYPES_REGISTRY) or MatchText(Name, HEAVY_TYPES_REGISTRY) then CATEGORY_REGISTRY
    else if MatchText(Head, HEAVY_TYPES_NETWORK) or MatchText(Name, HEAVY_TYPES_NETWORK) then CATEGORY_NETWORK
    else if not IsCall then ''
    else if MatchText(Name, HEAVY_BARE_DIALOG) then CATEGORY_DIALOG
    else if IsBare and MatchText(Name, HEAVY_BARE_FILE) then CATEGORY_FILE
    else if (not IsBare) and MatchText(Name, HEAVY_MEMBER_FILE) then CATEGORY_FILE
    else if (not IsBare) and MatchText(Name, HEAVY_MEMBER_DB) then CATEGORY_DATABASE
    else '';
end;

{ What a qualified name shows by its owner: a dotted segment that is a heavy TYPE ('HiLibStore.TRegistry.OpenKey'
  is registry). '' for nothing. Member and bare names are not matched here: only HeavyCategoryOfRef judges those. }
function HeavyCategoryOfQName(const AQName: string): string;
begin
  Result:= '';
  for var Seg in AQName.Split(['.']) do
  begin
    Result:=
      if MatchText(Seg, HEAVY_TYPES_FILE) then CATEGORY_FILE
      else if MatchText(Seg, HEAVY_TYPES_REGISTRY) then CATEGORY_REGISTRY
      else if MatchText(Seg, HEAVY_TYPES_NETWORK) then CATEGORY_NETWORK
      else '';
    if Result <> '' then Exit;
  end;
end;

{ The heavy categories a LIBRARY routine reaches (its own refs, its facts, its certain call edges, depth-bounded):
  category -> the qualified name of the library routine that shows it. Memoised per library symbol. }
procedure LibraryHeavy(const ALib: ISymbolStore; ARootId: Int64; AWitness: TDictionary<string, string>;
  AFileRefs: TObjectDictionary<Int64, TList<TReference>>);
var
  Seen : TDictionary<Int64, Boolean>;
  Queue: TList<TPair<Int64, Integer>>;

  function RefsOfLib(const ASym: TSymbol): TArray<TReference>;
  var
    L: TList<TReference>;
  begin
    if not AFileRefs.ContainsKey(ASym.FileId) then
    begin
      AFileRefs.Add(ASym.FileId, nil);
      for var R in ALib.GetReferencesFromFile(ASym.FileId) do
        if R.EnclosingSymbolId > 0 then
        begin
          if not AFileRefs.TryGetValue(-R.EnclosingSymbolId, L) then
          begin
            L:= TList<TReference>.Create;
            AFileRefs.Add(-R.EnclosingSymbolId, L);
          end;
          L.Add(R);
        end;
    end;
    Result:= nil;
    if AFileRefs.TryGetValue(-ASym.Id, L) then Result:= L.ToArray;
  end;

  procedure Note(const ACategory, AVia: string);
  begin
    if not AWitness.ContainsKey(ACategory) then AWitness.Add(ACategory, AVia);
  end;

begin
  Seen:= TDictionary<Int64, Boolean>.Create;
  Queue:= TList<TPair<Int64, Integer>>.Create;
  try
    Seen.Add(ARootId, True);
    Queue.Add(TPair<Int64, Integer>.Create(ARootId, 0));
    var Head: Integer:= 0;
    while (Head < Queue.Count) and (Queue.Count <= LIBRARY_WALK_NODES) do
    begin
      var Cur: TPair<Int64, Integer>:= Queue[Head];
      Inc(Head);
      var Sym: TSymbol:= ALib.GetSymbolById(Cur.Key);
      if Sym.Id = 0 then Continue;
      var OwnCategory: string:= HeavyCategoryOfQName(Sym.QualifiedName);
      if OwnCategory <> '' then Note(OwnCategory, Sym.QualifiedName);
      for var R in RefsOfLib(Sym) do
      begin
        var Category: string:= HeavyCategoryOfRef(R);
        if Category <> '' then Note(Category, Sym.QualifiedName);
      end;
      var Facts: TSymbolFacts:= ALib.GetSymbolFacts(Cur.Key);
      var Bar: Integer:= Pos(TOUCH_SEPARATOR, Facts.Touches);
      if (Facts.SqlReads <> '') or (Facts.SqlWrites <> '') or ((Bar > 0) and (Bar < Length(Facts.Touches))) then
        Note(CATEGORY_DATABASE, Sym.QualifiedName);
      if ContainsText(Facts.Touches, CATEGORY_REGISTRY) then Note(CATEGORY_REGISTRY, Sym.QualifiedName);
      if ContainsText(Facts.Touches, CATEGORY_NETWORK) then Note(CATEGORY_NETWORK, Sym.QualifiedName);
      if Cur.Value >= LIBRARY_WALK_DEPTH then Continue;
      for var E in ALib.GetCallEdgesFromSymbol(Cur.Key) do
        if (E.TargetSymbolId > 0) and (E.Confidence = CONFIDENCE_CERTAIN) and not Seen.ContainsKey(E.TargetSymbolId) then
        begin
          Seen.Add(E.TargetSymbolId, True);
          Queue.Add(TPair<Int64, Integer>.Create(E.TargetSymbolId, Cur.Value + 1));
        end;
    end;
  finally
    Queue.Free;
    Seen.Free;
  end;
end;

function CollectHeavyInitialization(const AStore: ISymbolStore; const ALibraryStore: ISymbolStore): TArray<TLintFinding>;
var
  Witness   : TDictionary<string, string>;
  Anchor    : TReference;
  Graph     : TInitGraph;
  LibMemo   : TObjectDictionary<Int64, TDictionary<string, string>>;
  LibRefs   : TObjectDictionary<Int64, TList<TReference>>;
  LibTarget : TDictionary<string, Int64>;
  Bound     : TDictionary<Int64, string>;

  { The one library routine an unresolved call names: same name, in a unit the calling file uses, and (with a
    receiver) the same type or unit. 0 when none or when the name is ambiguous. }
  function LibraryTarget(const ACaller: TSymbol; const AReference: TReference; const ABound: string): Int64;
  begin
    if ABound <> '' then
    begin
      { The index bound the call (refs.external_target): take the ONE library symbol of exactly that name. }
      var BoundKey: string:= 'T|' + LowerCase(ABound);
      if LibTarget.TryGetValue(BoundKey, Result) then
      begin
        if Result <> 0 then Exit;
      end
      else
      begin
        Result:= 0;
        var BoundHits: Integer:= 0;
        var Dot: Integer:= LastDelimiter('.', ABound);
        for var S in ALibraryStore.FindSymbolsByExactName(Copy(ABound, Dot + 1, MaxInt)) do
          if SameText(S.QualifiedName, ABound) then
          begin
            Inc(BoundHits);
            Result:= S.Id;
          end;
        if BoundHits <> 1 then Result:= 0;
        LibTarget.Add(BoundKey, Result);
        if Result <> 0 then Exit;
      end;
    end;
    var Key: string:= Format('%d|%s|%s', [ACaller.FileId, LowerCase(AReference.ReceiverText), LowerCase(AReference.NameText)]);
    if LibTarget.TryGetValue(Key, Result) then Exit;
    Result:= 0;
    var Hits: Integer:= 0;
    for var S in ALibraryStore.FindSymbolsByExactName(AReference.NameText) do
    begin
      var UnitName: string:= TPath.GetFileNameWithoutExtension(ALibraryStore.GetFilePath(S.FileId));
      if not Graph.FileUses(ACaller.FileId, LowerCase(UnitName)) then Continue;
      if (AReference.ReceiverText <> '')
        and not EndsText('.' + AReference.ReceiverText + '.' + AReference.NameText, S.QualifiedName) then Continue;
      Inc(Hits);
      Result:= S.Id;
    end;
    if Hits <> 1 then Result:= 0;
    LibTarget.Add(Key, Result);
  end;

  procedure NoteLibrary(const ACaller: TSymbol; const AReference: TReference; const ABound: string;
    const AAt: TReference);
  begin
    var Target: Int64:= LibraryTarget(ACaller, AReference, ABound);
    if Target = 0 then Exit;
    var Found: TDictionary<string, string>;
    if not LibMemo.TryGetValue(Target, Found) then
    begin
      Found:= TDictionary<string, string>.Create;
      LibMemo.Add(Target, Found);
      LibraryHeavy(ALibraryStore, Target, Found, LibRefs);
    end;
    for var P in Found do
      if not Witness.ContainsKey(P.Key) then
      begin
        Witness.Add(P.Key, P.Value);
        if Anchor.StartLine = 0 then Anchor:= AAt;
      end;
  end;

  procedure NoteVia(const ACategory, AVia: string; const AAt: TReference);
  begin
    if Witness.ContainsKey(ACategory) then Exit;
    Witness.Add(ACategory, AVia);
    if Anchor.StartLine = 0 then Anchor:= AAt;
  end;

  procedure Note(const ACategory: string; const AVia: TSymbol; const AAt: TReference);
  begin
    NoteVia(ACategory, AVia.QualifiedName, AAt);
  end;

  { refs.id -> refs.external_target of the routine-bound calls ASymbolId makes that have no call edge. }
  procedure LoadBound(ASymbolId: Int64);
  begin
    Bound.Clear;
    for var B in AStore.GetUnresolvedCallsFromSymbol(ASymbolId) do
      if (B.ExternalTarget <> '') and (B.ExternalKind = '') then Bound.AddOrSetValue(B.Id, B.ExternalTarget);
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;
  Graph:= TInitGraph.Create(AStore);
  var Findings: TList<TLintFinding>:= TList<TLintFinding>.Create;
  Witness:= TDictionary<string, string>.Create;
  LibMemo:= TObjectDictionary<Int64, TDictionary<string, string>>.Create([doOwnsValues]);
  LibRefs:= TObjectDictionary<Int64, TList<TReference>>.Create([doOwnsValues]);
  LibTarget:= TDictionary<string, Int64>.Create;
  Bound:= TDictionary<Int64, string>.Create;
  try
    for var Pair in Graph.Units do
    begin
      if Pair.Value.InitId = 0 then Continue;
      Witness.Clear;
      Anchor:= Default(TReference);
      var IsSection: Boolean:= True;
      for var Item in Graph.Reach(Pair.Value.InitId) do
      begin
        if ALibraryStore <> nil then LoadBound(Item.Key.Id);
        for var R in Graph.RefsOf(Item.Key) do
        begin
          var Category: string:= HeavyCategoryOfRef(R);
          if Category = '' then
          begin
            if (ALibraryStore <> nil) and ((R.Kind = REF_CALL) or (R.Kind = REF_MEMBER)) and not Graph.HasEdge(Item.Key.Id, R.Id) then
            begin
              var Target: string;
              if not Bound.TryGetValue(R.Id, Target) then Target:= '';
              var At: TReference:= if IsSection then R else Item.Value;
              var TargetCategory: string:= HeavyCategoryOfQName(Target);
              if TargetCategory <> '' then NoteVia(TargetCategory, Target, At);
              NoteLibrary(Item.Key, R, Target, At);
            end;
            Continue;
          end;
          if IsSection then Note(Category, Item.Key, R) else Note(Category, Item.Key, Item.Value);
        end;
        if not IsSection then
        begin
          var Facts: TSymbolFacts:= AStore.GetSymbolFacts(Item.Key.Id);
          var Bar: Integer:= Pos(TOUCH_SEPARATOR, Facts.Touches);
          if (Facts.SqlReads <> '') or (Facts.SqlWrites <> '') or ((Bar > 0) and (Bar < Length(Facts.Touches))) then
            Note(CATEGORY_DATABASE, Item.Key, Item.Value);
          if ContainsText(Facts.Touches, CATEGORY_REGISTRY) then Note(CATEGORY_REGISTRY, Item.Key, Item.Value);
          if ContainsText(Facts.Touches, CATEGORY_NETWORK) then Note(CATEGORY_NETWORK, Item.Key, Item.Value);
        end;
        IsSection:= False;
      end;
      if Witness.Count = 0 then Continue;

      var Parts: TArray<string>:= nil;
      for var C in HEAVY_CATEGORY_ORDER do
      begin
        var Via: string;
        if Witness.TryGetValue(C, Via) then Parts:= Parts + [Format('%s (%s)', [C, Via])];
      end;
      var F: TLintFinding:= Default(TLintFinding);
      F.RuleId    := HEAVY_INITIALIZATION_RULE;
      F.Severity  := SEVERITY_HINT;
      F.FileId    := Pair.Value.FileId;
      F.FilePath  := AStore.GetFilePath(F.FileId);
      F.StartLine := Anchor.StartLine;
      F.StartCol  := Anchor.StartCol;
      F.EndLine   := Anchor.EndLine;
      F.EndCol    := Anchor.EndCol;
      F.SymbolName:= Pair.Value.Name;
      F.Message   := Format('The initialization of %s reaches %s: this runs before the application has an exception '
        + 'handler or a window, in every process that links the unit. Move it to an explicit start-up call.',
        [Pair.Value.Name, string.Join(', ', Parts)]);
      Findings.Add(F);
    end;
    Result:= Findings.ToArray;
  finally
    Bound.Free;
    LibTarget.Free;
    LibRefs.Free;
    LibMemo.Free;
    Witness.Free;
    Findings.Free;
    Graph.Free;
  end;
end;

{ Does anything prove this name is a class? A Create call proves nothing by itself: TRegEx.Create is a
  record's (12 false findings of 12 on the drag-lint index before this test). The stores answer for what
  they hold; KNOWN_RTL_CLASSES answers for the commonest classes when no library index is loaded. An
  unknown name is silent. }
function IsProvenClass(const AStore, ALibraryStore: ISymbolStore; const AType: string): Boolean;
begin
  if MatchText(AType, KNOWN_RTL_CLASSES) then Exit(True);
  for var S in AStore.FindSymbolsByExactName(AType) do
    if S.Kind = skClass then Exit(True);
  Result:= False;
  if ALibraryStore <> nil then
    for var S in ALibraryStore.FindSymbolsByExactName(AType) do
      if S.Kind = skClass then Exit(True);
end;

{ A declared type that holds a reference count, not an object reference. `IFoo` with no row in either store
  counts too: an unknown class is rarely spelled I + capital. }
function IsInterfaceTyped(const AStore, ALibraryStore: ISymbolStore; const ASignature: string): Boolean;
begin
  var T: string:= Trim(ASignature);
  if (Length(T) > 1) and (T[1] = 'I') and CharInSet(T[2], ['A'..'Z']) then Exit(True);
  for var S in AStore.FindSymbolsByExactName(T) do
    if S.Kind = skInterface then Exit(True);
  Result:= False;
  if ALibraryStore <> nil then
    for var S in ALibraryStore.FindSymbolsByExactName(T) do
      if S.Kind = skInterface then Exit(True);
end;

function TextFreesVariable(const AText, AVarName: string): Boolean;
begin
  var N: string:= TRegEx.Escape(AVarName);
  Result:= TRegEx.IsMatch(AText,
    '\b' + N + '\s*\.\s*(Free|Destroy|DisposeOf|Release|FreeOnTerminate)\b'    { a direct free }
    + '|\bFree\w*\s*\(\s*' + N + '\b'                                          { FreeAndNil(G), FreeObject(G) }
    + '|\b(Add|AddObject|Insert|Push|Enqueue|Register\w*)\s*\([^;]*\b' + N + '\b', { handed to an owner }
    [roIgnoreCase]);
end;

function CollectGlobalNeverFreed(const AStore, ALibraryStore: ISymbolStore): TArray<TLintFinding>;
begin
  Result:= nil;
  if AStore = nil then Exit;
  var Graph: TInitGraph:= TInitGraph.Create(AStore);
  var Findings: TList<TLintFinding>:= TList<TLintFinding>.Create;
  var AllFiles: TArray<Int64>:= AStore.GetAllFileIds;
  var Seen: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    for var Pair in Graph.Units do
    begin
      if Pair.Value.InitId = 0 then Continue;
      var Vars: TDictionary<string, TSymbol>:= TDictionary<string, TSymbol>.Create;
      try
        for var Ch in AStore.FindAllChildSymbols(Pair.Value.UnitId) do
          if Ch.Kind = skVarDecl then Vars.AddOrSetValue(LowerCase(Ch.Name), Ch);
        for var Item in Graph.Reach(Pair.Value.InitId) do
        begin
          if Item.Key.FileId <> Pair.Value.FileId then Continue;
          for var R in Graph.RefsOf(Item.Key) do
          begin
            var Key: string:= LowerCase(R.NameText);
            var V: TSymbol;
            if (R.Kind <> REF_WRITE) or (R.ReceiverText <> '') or not Vars.TryGetValue(Key, V) then Continue;
            if Seen.ContainsKey(Pair.Key + '|' + Key) then Continue;
            var Match: TMatch:= TRegEx.Match(Graph.LineText(Item.Key.FileId, R.StartLine, CREATE_STATEMENT_LINES),
              '\b' + TRegEx.Escape(R.NameText) + '\s*:=\s*([A-Za-z_][\w.]*(?:<[^>]*>)?)\s*\.\s*Create\b\s*(?:\(\s*([^,)]*))?',
              [roIgnoreCase]);
            if not Match.Success then Continue;
            var TypeName: string:= Match.Groups[1].Value;
            var Generic: Integer:= Pos('<', TypeName);
            if Generic > 0 then TypeName:= Copy(TypeName, 1, Generic - 1);
            var Arg: string:= if Match.Groups.Count > 2 then Trim(Match.Groups[2].Value) else '';
            if (not IsProvenClass(AStore, ALibraryStore, TypeName)) or IsInterfaceTyped(AStore, ALibraryStore, V.Signature) then Continue;
            { An owner argument: an identifier that is not a nil or a boolean. A literal is a plain parameter. }
            if TRegEx.IsMatch(Arg, '^[A-Za-z_]') and not MatchText(Arg, NOT_AN_OWNER) then Continue;
            Seen.Add(Pair.Key + '|' + Key, True);
            var Freed: Boolean:= False;
            var Named: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
            try
              Named.AddOrSetValue(Pair.Value.FileId, True);
              for var Other in AStore.FindRefsNamingInFiles(AllFiles, [Key]) do Named.AddOrSetValue(Other.FileId, True);
              for var Fid in Named.Keys do
                if TextFreesVariable(Graph.FileText(Fid), V.Name) then
                begin
                  Freed:= True;
                  Break;
                end;
            finally
              Named.Free;
            end;
            if Freed then Continue;
            var F: TLintFinding:= Default(TLintFinding);
            F.RuleId    := GLOBAL_NEVER_FREED_RULE;
            F.Severity  := SEVERITY_HINT;
            F.FileId    := Pair.Value.FileId;
            F.FilePath  := AStore.GetFilePath(F.FileId);
            F.StartLine := R.StartLine;
            F.StartCol  := R.StartCol;
            F.EndLine   := R.EndLine;
            F.EndCol    := R.EndCol;
            F.SymbolName:= V.Name;
            F.Message   := Format('%s is set to a new %s by the initialization of %s, and no source that names it frees it: '
              + 'the object lives to process exit and shows in every leak report. Free it in the unit''s finalization.',
              [V.Name, TypeName, Pair.Value.Name]);
            Findings.Add(F);
          end;
        end;
      finally
        Vars.Free;
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Seen.Free;
    Findings.Free;
    Graph.Free;
  end;
end;

function CollectInitOrderHazard(const AStore: ISymbolStore): TArray<TLintFinding>;
begin
  Result:= RunOrderWalk(AStore, skiInit);
end;

function CollectFinalizationAfterDependency(const AStore: ISymbolStore): TArray<TLintFinding>;
begin
  Result:= RunOrderWalk(AStore, skiFinal);
end;

{ Lane CYC3: 'file:line' of the first uses entry of AFileId that comes from an include or sits in a conditional
  region (a pp_regions branch overlapping a uses clause, from its `uses` keyword -- lane INITAPI; was its first
  entry -- to one line past its last, so an inactive branch before, between or after the entries counts too); ''
  when there is none. }
function OrderDependsOnConfig(const AStore: ISymbolStore; AFileId: Int64): string;
begin
  Result:= '';
  var Name:= ExtractFileName(AStore.GetFilePath(AFileId));
  var Rows:= AStore.GetUnitUsesForFile(AFileId);
  for var R in Rows do
    if R.FromInclude then Exit(Format('%s:%d', [Name, R.IncludeLine]));
  if Length(Rows) = 0 then Exit;
  if not AStore.HasFileFacts then Exit(Format('%s (the index has no conditional-region facts: reindex)', [Name]));
  var Regions:= AStore.GetPpRegions(AFileId);
  var Lines: TArray<string>:= nil;
  for var Sect:= Low(TUnitUseSection) to High(TUnitUseSection) do
  begin
    var Lo:= MaxInt;
    var Hi:= 0;
    for var R in Rows do
      if R.Section = Sect then
      begin
        Lo:= Min(Lo, R.StartLine);
        Hi:= Max(Hi, R.EndLine + 1);
      end;
    // Lane INITAPI: a branch BEFORE the first active entry (an inactive IFDEF entry on its own line, then W) belongs
    // to the clause too: widen Lo back to the line of the `uses` keyword.
    if (Hi > 0) and (Length(Regions) > 0) then
    begin
      if Lines = nil then
        try
          Lines:= TFile.ReadAllLines(AStore.GetFilePath(AFileId));
        except
          on EInOutError do Lines:= nil;  { EFileNotFoundException / EDirectoryNotFoundException too }
        end;
      var L:= Min(Lo, Length(Lines));
      while (L >= 1) and not TRegEx.IsMatch(Lines[L - 1], USES_KEYWORD_PATTERN, [roIgnoreCase]) do Dec(L);
      if L >= 1 then Lo:= L;
    end;
    for var G in Regions do
      if (Hi > 0) and (G.StartLine <= Hi) and (G.EndLine >= Lo) then Exit(Format('%s:%d', [Name, G.StartLine]));
  end;
end;

{ Lane CYC3: the units between AFrom and ATo on a shortest uses path with the entry AFrom -> ATo left out; False when
  AFrom no longer reaches ATo. }
function PathAfterCut(AGraph: TInitGraph; const AFrom, ATo: string; out APath: TArray<string>): Boolean;
var
  Parent: TDictionary<string, string>;
  Queue : TQueue<string>;
begin
  APath:= nil;
  Parent:= TDictionary<string, string>.Create;
  Queue:= TQueue<string>.Create;
  try
    Parent.Add(AFrom, '');
    Queue.Enqueue(AFrom);
    while Queue.Count > 0 do
    begin
      var K:= Queue.Dequeue;
      var Node: TUnitNode;
      if not AGraph.Units.TryGetValue(K, Node) then Continue;
      for var Dep in AGraph.UsesOfFile(Node.FileId) do
      begin
        if ((K = AFrom) and (Dep = ATo)) or Parent.ContainsKey(Dep) then Continue;
        Parent.Add(Dep, K);
        if Dep = ATo then
        begin
          var P:= K;
          while P <> AFrom do
          begin
            APath:= [AGraph.Units[P].Name] + APath;
            P:= Parent[P];
          end;
          Exit(True);
        end;
        Queue.Enqueue(Dep);
      end;
    end;
    Result:= False;
  finally
    Queue.Free;
    Parent.Free;
  end;
end;

function ProveInitOrderInversion(const AStore: ISymbolStore; const AConsumer, ADeclaring: string): TInitOrderProof;
var
  Graph: TInitGraph;
  A, B : TUnitNode;
  Path : TArray<string>;
begin
  Result:= Default(TInitOrderProof);
  if AStore = nil then Exit;
  var KA:= LowerCase(AConsumer);
  var KB:= LowerCase(ADeclaring);
  Graph:= TInitGraph.Create(AStore);
  try
    if not Graph.Units.TryGetValue(KA, A) or not Graph.Units.TryGetValue(KB, B) then
    begin
      Result.Text:= Format('`%s` or `%s` has no single place in the initialization order (the index holds that unit ' +
        'name twice, or not at all)', [AConsumer, ADeclaring]);
      Exit;
    end;
    if not PathAfterCut(Graph, KA, KB, Path) then
    begin
      Result.Text:= Format('after the cut `%s` still uses `%s` and `%s` no longer reaches `%s`, so `%s` initializes ' +
        'first whatever the .dpr order: the variable is nil there', [B.Name, A.Name, A.Name, B.Name, A.Name]);
      Exit;
    end;
    var Programs: TArray<Int64>:= nil;
    var First:= '';
    for var P in Graph.ProgramFiles do
    begin
      var Roots:= TDictionary<string, string>.Create;
      var Before:= Graph.ComputeOrder(P);
      var After:= Graph.ComputeOrder(P, KA, KB, Roots);
      try
        if not (Before.ContainsKey(KA) and Before.ContainsKey(KB)) then Continue;
        var Dpr:= ExtractFileName(AStore.GetFilePath(P));
        var Orders: TArray<TDictionary<string, Integer>>:= [Before, After];
        for var Order in Orders do
          if Order[KB] > Order[KA] then
          begin
            var Entry: string;
            if not Roots.TryGetValue(KA, Entry) then Entry:= KB;
            var EntryNode: TUnitNode;
            if Graph.Units.TryGetValue(Entry, EntryNode) then Entry:= EntryNode.Name;
            Result.Text:= Format('in `%s` `%s` (position %d) initializes before `%s` (position %d)%s: list `%s` ' +
              'before `%s` in the .dpr, or cut another edge', [Dpr, A.Name, Order[KA] + 1, B.Name, Order[KB] + 1,
              (if Order = After then ' once the cut is made' else ''), A.Name, Entry]);
            Exit;
          end;
        if First = '' then
          First:= Format('`%s` initializes before `%s` in `%s` (position %d before %d; `%s` reaches `%s` through `%s`)',
            [B.Name, A.Name, Dpr, After[KB] + 1, After[KA] + 1, A.Name, B.Name, string.Join('`, `', Path)]);
        Programs:= Programs + [P];
      finally
        After.Free;
        Before.Free;
        Roots.Free;
      end;
    end;
    if Length(Programs) = 0 then
    begin
      Result.Text:= 'no program in this index: a package has no initialization order to prove';
      Exit;
    end;
    var Files: TArray<Int64>:= Programs + [A.FileId, B.FileId];
    for var N in Path do Files:= Files + [Graph.Units[LowerCase(N)].FileId];
    var Site:= '';
    for var F in Files do
      if Site = '' then Site:= OrderDependsOnConfig(AStore, F);
    Result.Proved:= Site = '';
    Result.Text:= if Site <> '' then Format('the order depends on a conditional uses entry (`%s`)', [Site])
      else 'init order: ' + First + (if Length(Programs) > 1 then Format(', and so in %d other programs',
      [Length(Programs) - 1]) else '') + '. This holds for this uses order; the lint rule `init-order-hazard` ' +
      'reports it if a later uses change reverses it.';
  finally
    Graph.Free;
  end;
end;

{ Lane INITAPI: lower-case unit -> position, as a sorted unit list. }
function UnitsInOrder(AOrder: TDictionary<string, Integer>): TArray<string>;
begin
  SetLength(Result, AOrder.Count);
  for var Pair in AOrder do Result[Pair.Value]:= Pair.Key;
end;

{ Lane INITAPI: the program symbol of AFileId (its body is the main block), 0 when not indexed. }
function ProgramBlockOf(AGraph: TInitGraph; AFileId: Int64): Int64;
begin
  Result:= 0;
  for var S in AGraph.Store.FindSymbolsByKind(KIND_PROGRAM, False, MaxInt) do
    if S.FileId = AFileId then Exit(S.Id);
end;

function ProgramInitOrders(const AStore: ISymbolStore; const AStop: TFunc<Boolean>): TArray<TProgramInitOrder>;
begin
  Result:= nil;
  if AStore = nil then Exit;
  var Graph: TInitGraph:= TInitGraph.Create(AStore, AStop);
  try
    for var P in Graph.ProgramFiles do
    begin
      if Assigned(AStop) and AStop() then Exit;
      var Entry: TProgramInitOrder:= Default(TProgramInitOrder);
      Entry.ProgramFileId:= P;
      Entry.ProgramName:= ExtractFileName(AStore.GetFilePath(P));
      Entry.ProgramBlockId:= ProgramBlockOf(Graph, P);
      Entry.UnreliableReason:= OrderDependsOnConfig(AStore, P);
      var Order:= Graph.ComputeOrder(P);
      try
        for var Key in UnitsInOrder(Order) do
        begin
          if Assigned(AStop) and AStop() then Exit;  { the order's unit walk reads source per unit (OrderDependsOnConfig) }
          var Node:= Graph.Units[Key];
          var U: TProgramInitUnit:= Default(TProgramInitUnit);
          U.Name   := Node.Name;
          U.FileId := Node.FileId;
          U.UnitId := Node.UnitId;
          U.InitId := Node.InitId;
          U.FinalId:= Node.FinalId;
          Entry.Units:= Entry.Units + [U];
          if Entry.UnreliableReason = '' then Entry.UnreliableReason:= OrderDependsOnConfig(AStore, Node.FileId);
        end;
      finally
        Order.Free;
      end;
      Entry.Unreliable:= Entry.UnreliableReason <> '';
      Result:= Result + [Entry];
    end;
  finally
    Graph.Free;
  end;
end;

{ Lane INITAPI: the answer for one program whose order places both units. The deciding files: the program, every
  unit placed at or before the later of the two, and every unit whose uses reach either (a DFS ancestor of a unit
  placed after them; a unit placed after both that reaches neither was entered after both were placed). }
function AnswerInProgram(AGraph: TInitGraph; AProgram: Int64; AOrder: TDictionary<string, Integer>;
  const KA, KB: string): TInitOrderVerdict;
var
  Reaches: TDictionary<string, Boolean>;
begin
  var Dpr:= ExtractFileName(AGraph.Store.GetFilePath(AProgram));
  var PA:= AOrder[KA];
  var PB:= AOrder[KB];
  var Last:= Max(PA, PB);
  Reaches:= TDictionary<string, Boolean>.Create;
  try
    { reverse reach: a unit of the order whose uses name a unit already known to reach KA or KB }
    Reaches.Add(KA, True);
    Reaches.AddOrSetValue(KB, True);
    var Grew:= True;
    while Grew do
    begin
      Grew:= False;
      for var Pair in AOrder do
        if not Reaches.ContainsKey(Pair.Key) then
          for var Dep in AGraph.UsesOfFile(AGraph.Units[Pair.Key].FileId) do
            if Reaches.ContainsKey(Dep) then
            begin
              Reaches.Add(Pair.Key, True);
              Grew:= True;
              Break;
            end;
    end;
    var Site:= OrderDependsOnConfig(AGraph.Store, AProgram);
    for var Key in UnitsInOrder(AOrder) do
      if (Site = '') and ((AOrder[Key] <= Last) or Reaches.ContainsKey(Key)) then
        Site:= OrderDependsOnConfig(AGraph.Store, AGraph.Units[Key].FileId);
    var A:= AGraph.Units[KA].Name;
    var B:= AGraph.Units[KB].Name;
    if Site <> '' then
    begin
      Result.Answer:= ioaConfigDependent;
      Result.Text:= Format('in `%s` the order of `%s` and `%s` depends on a conditional uses entry (`%s`)', [Dpr, A, B, Site]);
      Exit;
    end;
    Result.Answer:= if PA < PB then ioaBefore else ioaNotBefore;
    Result.Text:= Format('in `%s` `%s` (position %d) initializes %s `%s` (position %d)', [Dpr, A, PA + 1,
      (if PA < PB then 'before' else if PA = PB then 'as' else 'after'), B, PB + 1]);
  finally
    Reaches.Free;
  end;
end;

function InitializesBefore(const AStore: ISymbolStore; const AProgram, AUnitA, AUnitB: string): TInitOrderVerdict;
begin
  Result:= Default(TInitOrderVerdict);
  Result.Text:= 'no store';
  if AStore = nil then Exit;
  var KA:= LowerCase(AUnitA);
  var KB:= LowerCase(AUnitB);
  var Graph: TInitGraph:= TInitGraph.Create(AStore);
  try
    if not Graph.Units.ContainsKey(KA) or not Graph.Units.ContainsKey(KB) then
    begin
      Result.Text:= Format('`%s` or `%s` has no single place in the initialization order (the index holds that unit ' +
        'name twice, or not at all)', [AUnitA, AUnitB]);
      Exit;
    end;
    var Answered:= False;
    var NotBefore: TInitOrderVerdict:= Default(TInitOrderVerdict);
    var Before: TInitOrderVerdict:= Default(TInitOrderVerdict);
    var Count:= 0;
    for var P in Graph.ProgramFiles do
    begin
      var FileName:= ExtractFileName(AStore.GetFilePath(P));
      if (AProgram <> '') and not SameText(AProgram, FileName) and not SameText(AProgram, ChangeFileExt(FileName, ''))
        then Continue;
      var Order:= Graph.ComputeOrder(P);
      try
        if not (Order.ContainsKey(KA) and Order.ContainsKey(KB)) then Continue;
        var V:= AnswerInProgram(Graph, P, Order, KA, KB);
        Answered:= True;
        Inc(Count);
        case V.Answer of
          ioaConfigDependent: Exit(V);
          ioaNotBefore: if NotBefore.Answer = ioaUnplaced then NotBefore:= V;
          ioaBefore: if Before.Answer = ioaUnplaced then Before:= V;
        end;
      finally
        Order.Free;
      end;
    end;
    if not Answered then
    begin
      Result.Text:= if AProgram = '' then Format('no program of the index initializes both `%s` and `%s`', [AUnitA, AUnitB])
        else Format('no program `%s` of the index initializes both `%s` and `%s`', [AProgram, AUnitA, AUnitB]);
      Exit;
    end;
    Result:= if NotBefore.Answer <> ioaUnplaced then NotBefore else Before;
    if (Result.Answer = ioaBefore) and (Count > 1) then
      Result.Text:= Result.Text + Format(', and so in %d other programs', [Count - 1]);
  finally
    Graph.Free;
  end;
end;

end.
