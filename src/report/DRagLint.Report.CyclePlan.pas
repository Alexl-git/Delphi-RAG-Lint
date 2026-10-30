unit DRagLint.Report.CyclePlan;  // dl:ok unit-too-large@252c -- one self-contained pipeline (plan, materialise, predict, render) whose ~15 record types are private to it; a split would publish them all for no second caller

// ---------------------------------------------------------------------------
// `drag-lint cycles --plan` -- the circular-dependency refactoring playbook.
//
// Written for the CHEAPEST reader: a model with no project context and no
// index access must be able to follow it to a compiling tree whose `cycles`
// report matches the playbook's own prediction
// (docs\INBOX-test-cycle-playbook-followability-haiku-flash.md). The old
// playbook said "extract the shared contract into a leaf unit"; Haiku moved a
// CLASS declaration without its method bodies (E2065 x5) and was then told the
// cycle "should be gone" when a legal implementation-only cycle remained.
//
// So every step here is concrete: the kind of each symbol and the recipe for
// that kind, exact line ranges, the full text of every new unit, the current
// and the replacement text of every edited line, a per-unit decision on the
// old uses entry, a DONE definition, and a checklist that ends in the exact
// output `cycles` must print afterwards -- computed by replaying the plan on
// the unit graph, not promised.
// ---------------------------------------------------------------------------

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, System.JSON,
  DRagLint.Core.Interfaces;

const
  /// <summary>Tag `cycles` prints after a group that has interface coupling.
  /// Shared with DoCycles so the playbook's predicted output cannot drift
  /// from what the report really prints.</summary>
  CCycleTagInterface = '(has interface coupling -- widest recompile blast radius)';
  /// <summary>Tag `cycles` prints after an implementation-only group.</summary>
  CCycleTagImplOnly = '(implementation-only -- legal, lower impact)';
  /// <summary>Hint line `cycles` prints after the groups when neither
  /// --edges nor --causes was given.</summary>
  CCycleEdgesHint = '  (add --edges for the uses lines, --causes for the symbols to refactor)';
  /// <summary>What `cycles` prints for an acyclic unit graph.</summary>
  CCycleNone = 'No circular unit dependencies found.';
  /// <summary>First line of a non-empty report; the argument is the group count.</summary>
  CCycleCountFmt = '%d circular unit group(s) found:';
  /// <summary>One group line: size, members joined by ' &lt;-&gt; ', tag.</summary>
  CCycleGroupFmt = '  [%d units] %s   %s';

type
  /// <summary>The unit-uses graph DoCycles already built, handed to the
  /// playbook renderer.</summary>
  /// <remarks>Every dictionary is keyed by the LOWER-CASE unit stem (file name
  /// without extension) and is owned by the caller; the renderer only reads
  /// them.</remarks>
  TCycleGraph = record
    /// <summary>Unit stem -> stems it uses, from either uses clause.</summary>
    Adj: TDictionary<string, TList<string>>;
    /// <summary>Holds the key 'a-&gt;b' when a names b in its INTERFACE uses.</summary>
    IntfEdges: TDictionary<string, Boolean>;
    /// <summary>Unit stem -> source path.</summary>
    UnitFile: TDictionary<string, string>;
    /// <summary>Unit stem -> file id in the index.</summary>
    UnitFid: TDictionary<string, Int64>;
  end;

  /// <summary>One reason a cycle's plan cannot be applied mechanically.</summary>
  /// <remarks>Kind is one of the strings of the 2026-10-10 contract 4.4:
  /// manual-edit, blocked-symbol, unresolved-edge, directive, leaf-uses-cycle,
  /// qualified-ref, class-ctor, base-class, outside-roots; R1 (E18 T5) adds
  /// signature-in-cycle, signature-unknown, routine-not-called, init-order,
  /// duplicate-identifier, edge-still-used, overloaded-routine, unsupported-directive; R2 (E18 T6) adds
  /// member-write, construction, class-method, class-ref, type-decl, type-cast, other-ref,
  /// multiple-classes, member-unsupported, no-iinterface, ref-counted, receiver-unknown,
  /// cast-unseen, with-member, ancestry-unknown, type-unresolved, unresolved-qualified-type, exception-semantics (and reuses leaf-uses-cycle,
  /// qualified-ref, duplicate-identifier, edge-still-used, manual-edit). Line is 0 when the
  /// refusal has no single line (an edge, a unit).</remarks>
  TRefusal = record
    Kind    : string;
    Symbol  : string;
    FilePath: string;
    Reason  : string;
    Line    : Integer;
  end;

  /// <summary>One symbol a plan moves into a leaf unit.</summary>
  TPlanMove = record
    /// <summary>Declared name.</summary>
    Symbol: string;
    /// <summary>Declaration keyword (record, class, type, ...) or the symbol kind.</summary>
    Kind: string;
    /// <summary>decl, with-bodies, base or blocked.</summary>
    Recipe: string;
    /// <summary>Source file as indexed.</summary>
    FromFile: string;
    /// <summary>Receiving leaf unit; '' when none is named.</summary>
    ToUnit: string;
    /// <summary>First declaration line, as indexed.</summary>
    First: Integer;
    /// <summary>Last declaration line, as indexed.</summary>
    Last: Integer;
  end;

  /// <summary>One decision on a uses entry.</summary>
  TPlanUse = record
    /// <summary>File whose uses clause is judged.</summary>
    FilePath: string;
    /// <summary>The entry's unit name.</summary>
    UnitName: string;
    /// <summary>interface or implementation.</summary>
    Section: string;
    /// <summary>move, remove or keep.</summary>
    Action: string;
  end;

  /// <summary>A unit file the plan creates.</summary>
  TPlanNewUnit = record
    /// <summary>Unit name.</summary>
    UnitName: string;
    /// <summary>Target file path.</summary>
    Path: string;
    /// <summary>The unit's full text, one string per line (no line terminators).</summary>
    Text: TArray<string>;
  end;

  /// <summary>One edit of an existing file.</summary>
  TPlanEdit = record
    /// <summary>The edited file.</summary>
    FilePath: string;
    /// <summary>delete, insert, replace or manual.</summary>
    Kind: string;
    /// <summary>First line, as indexed.</summary>
    First: Integer;
    /// <summary>Last line, as indexed.</summary>
    Last: Integer;
    /// <summary>delete/replace: the lines First..Last as the planner read them (the playbook's "Current text"); else empty.</summary>
    CurrentLines: TArray<string>;
    /// <summary>replace/insert: the lines that go in; else empty.</summary>
    NewLines: TArray<string>;
    /// <summary>insert: the full text of line First, the line the lines go after; else ''.</summary>
    AnchorText: string;
  end;

  /// <summary>A plan for one circular group as plain data, for the `cycles --fix` front end.</summary>
  /// <remarks>Built by VisitCyclePlans from the planner's TCycleFixPlan; it owns nothing.</remarks>
  TCyclePlanView = record
    /// <summary>1-based group index (DoCycles order).</summary>
    CycleIndex: Integer;
    /// <summary>The group's unit stems.</summary>
    Units: TArray<string>;
    /// <summary>True when an interface uses edge is part of the group.</summary>
    HasIntf: Boolean;
    /// <summary>'A' for an interface-coupled group, 'B' for an implementation-only one.</summary>
    Part: Char;
    /// <summary>True when the planner found no refusal.</summary>
    Mechanical: Boolean;
    /// <summary>The planner's refusals.</summary>
    Refusals: TArray<TRefusal>;
    /// <summary>Symbols moved.</summary>
    Moves: TArray<TPlanMove>;
    /// <summary>Uses-entry decisions.</summary>
    UseDecisions: TArray<TPlanUse>;
    /// <summary>Units created.</summary>
    NewUnits: TArray<TPlanNewUnit>;
    /// <summary>Every edit of an existing file, the .dpr and .dproj included.</summary>
    Edits: TArray<TPlanEdit>;
    /// <summary>Paths of every file the plan edits (the .dproj when it is edited).</summary>
    TouchedPaths: TArray<string>;
    /// <summary>move-globals, routine-inversion, member-interface or ''.</summary>
    Recipe: string;
    /// <summary>The cut edge as 'from->to' (Part B), else ''.</summary>
    Edge: string;
    /// <summary>The expected `cycles` output after the plan, one line per #10.</summary>
    Predicted: string;
    /// <summary>member-interface / routine-inversion: the unit that receives the interface or the
    /// pointer declarations (a new `*.Untangle` leaf or an existing unit); else ''.</summary>
    InversionUnit: string;
    /// <summary>member-interface: the extracted interface's name; else ''.</summary>
    IfaceName: string;
    /// <summary>member-interface: the ancestor a receiver that does not implement IInterface is
    /// cast through ('' when no line needs a cast); else ''.</summary>
    CastAncestor: string;
    /// <summary>routine-inversion: the procedural type `T&lt;Routine&gt;Ptr`; else ''.</summary>
    PtrType: string;
    /// <summary>routine-inversion: the variable `&lt;Routine&gt;Ptr`; else ''.</summary>
    PtrVar: string;
    /// <summary>routine-inversion: the type declaration as the plan emits it (no indent), built
    /// from the routine's signature verbatim; else ''.</summary>
    PtrTypeDecl: string;
  end;

  /// <summary>One edge a `Fix it` block names, as the planner weighed it.</summary>
  TFixEdge = record
    /// <summary>The using unit's stem.</summary>
    FromUnit: string;
    /// <summary>The used unit's stem.</summary>
    ToUnit: string;
    /// <summary>move-globals, routine-inversion or member-interface.</summary>
    Recipe: string;
    /// <summary>True for the edge `cycles --fix` cuts (the planner's CutEdge).</summary>
    Chosen: Boolean;
  end;

  /// <summary>What a `Fix it` block (text) or `fix` object (JSON) says about one circular group.</summary>
  /// <remarks>Taken only from the planner's plan of the group; nothing is re-derived.</remarks>
  TCycleFixHint = record
    /// <summary>1-based group index (DoCycles order).</summary>
    CycleIndex: Integer;
    /// <summary>'A' for an interface-coupled group, 'B' for an implementation-only one.</summary>
    Part: Char;
    /// <summary>True when the planner found a mechanical cut with no refusal.</summary>
    Available: Boolean;
    /// <summary>The `cycles --fix` dry-run command.</summary>
    DryRun: string;
    /// <summary>The `cycles --fix --apply` command.</summary>
    Apply: string;
    /// <summary>The first refusal as 'kind: reason', or '' when Available.</summary>
    Reason: string;
    /// <summary>Part B groups: every edge with a recipe, the chosen one first; Part A: empty.</summary>
    Edges: TArray<TFixEdge>;
    /// <summary>Part A groups: True when Part B would cut an edge afterwards (see Followup).</summary>
    HasFollowup: Boolean;
    /// <summary>Part A groups: the edge Part B cuts after Part A (Chosen = True); else empty.</summary>
    Followup: TFixEdge;
  end;

  /// <summary>Called once per planned group by VisitCyclePlans.</summary>
  /// <param name="pView">The group's plan as data; valid during the call only.</param>
  /// <param name="pRender">Returns the playbook of this group, one string per line; call at most once.</param>
  /// <returns>True to continue with the next group, False to stop.</returns>
  TCyclePlanVisit = reference to function(const pView: TCyclePlanView; const pRender: TFunc<TArray<string>>): Boolean;

/// <summary>The encoding a source file is read and written in: UTF-8 when it starts with the
/// UTF-8 BOM, else the system ANSI code page (the indexer's basis).</summary>
/// <param name="pBytes">The file's raw bytes.</param>
/// <returns>TEncoding.UTF8 or TEncoding.ANSI; not owned by the caller.</returns>
function SourceEncodingOf(const pBytes: TBytes): TEncoding;

/// <summary>Decodes a source file's bytes in its own encoding.</summary>
/// <param name="pBytes">The file's raw bytes.</param>
/// <param name="pEncoding">Receives the encoding used (SourceEncodingOf).</param>
/// <returns>The text without the BOM.</returns>
function DecodeSource(const pBytes: TBytes; out pEncoding: TEncoding): string;

/// <summary>Encodes text for a source file; the inverse of DecodeSource.</summary>
/// <param name="pText">The text.</param>
/// <param name="pEncoding">The file's encoding from DecodeSource.</param>
/// <returns>The bytes, with the UTF-8 BOM first when the encoding is UTF-8.</returns>
function EncodeSource(const pText: string; pEncoding: TEncoding): TBytes;

/// <summary>Reads a source file as lines in its own encoding (DecodeSource), the one routine both
/// the planner and the cycle-fix staging use so they agree on every character.</summary>
/// <param name="pPath">The file.</param>
/// <returns>The lines without terminators.</returns>
function ReadSourceLines(const pPath: string): TArray<string>;
/// <summary>Plans each circular group (or one) and hands every plan to pVisit as data.</summary>
/// <param name="pStore">Open index the graph was built from; read only.</param>
/// <param name="pDbPath">Path of that index.</param>
/// <param name="pSccs">The circular groups, lower-case stems.</param>
/// <param name="pGraph">The uses graph the groups were computed from.</param>
/// <param name="pLibStore">Platform library index (read only) or nil.</param>
/// <param name="pVisit">The consumer.</param>
/// <param name="pOnly">1-based group to plan, or 0 for every group in order.</param>
/// <remarks>Writes nothing. Groups after the one that made pVisit return False are not planned.</remarks>
procedure VisitCyclePlans(const pStore: ISymbolStore; const pDbPath: string;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph;
  const pLibStore: ISymbolStore; const pVisit: TCyclePlanVisit; pOnly: Integer = 0);

/// <summary>Renders the `cycles --plan` markdown playbook for every circular
/// unit group into <paramref name="pOut"/>, one output line per item.</summary>
/// <param name="pStore">Open index the graph was built from; read only.</param>
/// <param name="pDbPath">Path of that index, quoted in the re-check commands.</param>
/// <param name="pSccs">The circular groups (strongly-connected components of
/// more than one unit), as lower-case unit stems.</param>
/// <param name="pGraph">The uses graph the groups were computed from.</param>
/// <param name="pOut">Receives the markdown; lines are appended.</param>
/// <param name="pLibStore">The platform library index, opened read-only by the caller, or nil.
/// Recipe R2 reads class ancestry, inherited members and the units of library types from it;
/// without it R2 refuses wherever the answer needs the library.</param>
/// <param name="pFixProject">The project file named in each cycle's `Fix it` commands, or '' to print
/// the placeholder `&lt;your.dproj&gt;`.</param>
/// <remarks>
/// <para>An INTERFACE-coupled group gets Part A: every symbol that one member's
/// interface takes from another moves into a new leaf unit
/// `&lt;Declaring&gt;.Untangle` (an existing one is extended while it is still a
/// leaf for the group, DRagLint.Report.UntangleCatalog) -- a class whose method bodies use the cycle is
/// NOT moved; a base class carrying the members its consumers use is
/// extracted instead. An implementation-only group gets the cheapest edge
/// that can be cut the same way; else an edge that is one routine call (R1,
/// routine-call inversion); else an edge that is `is` / `as` plus member reads
/// of one class (R2, member hand-over through an extracted interface); or a
/// statement that none can.</para>
/// <para>Line numbers are those of the files as indexed. Each file's edits are
/// listed bottom-up so they can be applied in order without renumbering.</para>
/// <para>The expected `cycles` output is predicted by replaying the planned
/// uses changes on the graph; it assumes the other groups are left alone.</para>
/// </remarks>
procedure RenderCyclePlaybook(const pStore: ISymbolStore; const pDbPath: string;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pOut: TStrings;
  const pLibStore: ISymbolStore = nil; const pFixProject: string = '');

type
/// <summary>The inputs of AddCycleFixHints bundled in one record (keeps the routine under the parameter limit).</summary>
/// <remarks>Plain value record; every reference is borrowed, none is owned or freed by the record.</remarks>
TCycleFixHintInput = record
  /// <summary>Open index the graph was built from; read only.</summary>
  Store: ISymbolStore;
  /// <summary>Path of that index, quoted in the commands.</summary>
  DbPath: string;
  /// <summary>The circular groups, as lower-case unit stems.</summary>
  Sccs: TList<TArray<string>>;
  /// <summary>The uses graph the groups were computed from.</summary>
  Graph: TCycleGraph;
  /// <summary>Platform library index (read only) or nil.</summary>
  LibStore: ISymbolStore;
  /// <summary>The project file to name in the commands, or '' for the placeholder.</summary>
  FixProject: string;
  /// <summary>When not empty, no planner runs: every fix object is available=false with this text as its reason (the platform library could not be opened).</summary>
  Unavailable: string;
end;

/// <summary>Adds a `fix` object (TCycleFixHint) to every group object of a `cycles --format json` report.</summary>
/// <param name="pIn">The index, graph, groups and project (see TCycleFixHintInput).</param>
/// <param name="pGroups">The report's group objects, index-aligned with pIn.Sccs; each must be a
/// TJSONObject. The new objects become owned by those objects.</param>
/// <remarks>Runs the planner once per group, so it is only for `--causes`. Writes nothing.
/// Fields: available, part, dry_run, apply, edges[{from,to,recipe,chosen}], reason, and for a
/// Part A group `followup` {from,to,recipe} when Part B cuts an edge afterwards.</remarks>
procedure AddCycleFixHints(const pIn: TCycleFixHintInput; const pGroups: TJSONArray);

/// <summary>Adds an `edges` array to every group object of a `cycles --format json`
/// report: one entry per uses edge inside the group, with that edge's surface
/// (DRagLint.Report.CycleEdge.EdgeSurfaceToJson).</summary>
/// <param name="pStore">Open index the graph was built from; read only.</param>
/// <param name="pSccs">The circular groups, as lower-case unit stems.</param>
/// <param name="pGraph">The uses graph the groups were computed from.</param>
/// <param name="pGroups">The report's group objects, index-aligned with pSccs; each
/// must be a TJSONObject. The new arrays become owned by those objects.</param>
/// <remarks>Edges are listed member by member in group order (from, then to), the
/// order the impl-cycle planner weighs them. Reads every member_accesses row once.</remarks>
procedure AddCycleEdgeSurfaces(const pStore: ISymbolStore; const pSccs: TList<TArray<string>>;
  const pGraph: TCycleGraph; const pGroups: TJSONArray);

/// <summary>Builds the unit-uses graph `cycles` works on from every indexed `.pas` file's
/// unit_uses rows.</summary>
/// <param name="pStore">Open index; read only.</param>
/// <returns>A graph whose four dictionaries are NEW and owned by the caller: release them with
/// FreeCycleGraph.</returns>
/// <remarks>Keys are lower-case file stems; an edge's target is the lower-case unit name as
/// written in the uses clause, so a library unit is a node with no outgoing list; a bare name
/// binds to a project unit only as dcc binds it (BareUsesBinding, A3-b). E18 T15b:
/// hoisted out of DoCycles so `lint &lt;file&gt;` builds the same graph.</remarks>
function BuildCycleGraph(const pStore: ISymbolStore): TCycleGraph;

/// <summary>Frees the four dictionaries (and the adjacency lists) of a graph from BuildCycleGraph
/// and sets them to nil.</summary>
/// <param name="pGraph">The graph; safe to call twice.</param>
procedure FreeCycleGraph(var pGraph: TCycleGraph);

/// <summary>The circular unit groups of a graph: Tarjan's strongly-connected components of more
/// than one unit.</summary>
/// <param name="pGraph">A graph from BuildCycleGraph; read only.</param>
/// <returns>A NEW list owned by the caller, one array of lower-case stems per group, in the order
/// `cycles` prints them.</returns>
/// <remarks>The one SCC pass behind `cycles` (DoCycles) and the per-file circular-uses finding of
/// `lint &lt;file&gt;` (E18 T15b), so the two cannot disagree on which units cycle.</remarks>
function ComputeSccs(const pGraph: TCycleGraph): TList<TArray<string>>; overload;

/// <summary>The circular unit groups of an index (BuildCycleGraph, then ComputeSccs).</summary>
/// <param name="pStore">Open index; read only.</param>
/// <returns>A NEW list owned by the caller, one array of lower-case stems per group.</returns>
function ComputeSccs(const pStore: ISymbolStore): TList<TArray<string>>; overload;

/// <summary>The cycles dcc rejects with F2047: Tarjan's strongly-connected components
/// (of more than one unit) of the INTERFACE-uses edges alone.</summary>
/// <param name="pGraph">A graph from BuildCycleGraph; read only.</param>
/// <returns>A NEW list owned by the caller, one array of lower-case stems per group.</returns>
/// <remarks>`cycles --f2047` (N-09). Every group here is also inside one group of
/// ComputeSccs(pGraph); a group there with an implementation edge on every loop is not
/// here, because the compiler accepts it.</remarks>
function ComputeInterfaceSccs(const pGraph: TCycleGraph): TList<TArray<string>>;

implementation

uses
  System.IOUtils, System.StrUtils, System.RegularExpressions, System.Math, System.TypInfo,
  System.Generics.Defaults,
  DRagLint.Core.Model, DRagLint.Convert.UnitRules, DRagLint.Report.CycleEdge,
  DRagLint.Report.UntangleCatalog;

const
  CLeafSuffix    = CUntangleSuffix;
  CBaseSuffix    = 'Base';
  CCodeFence     = '```';
  CPascalFence   = '```pascal';
  CTextFence     = '```text';
  CXmlFence      = '```xml';
  CEntryIndent   = '  ';
  CNotFound      = -1;
  CKeyFmt        = '%d:%d';
  COverrideTail  = ' override;';
  CAbstractTail  = ' virtual; abstract;';
  CMaxNamesShown = 6;
  CIntfMark      = '!';
  CKindPrefix    = 'sk';
  CStepMoves     = 1;
  CStepUses      = 2;
  CStepCreate    = 3;
  CStepEdit      = 4;
  CBlockWords: TArray<string> = ['type', 'var', 'const', 'threadvar', 'resourcestring'];

type
  TSect = (scIntf, scImpl, scProg);

  TLineRange = record
    First: Integer;
    Last : Integer;
  end;

  TPlanFile = record
    Fid      : Int64;
    Path     : string;
    UnitName : string;
    Stem     : string;
    IsProgram: Boolean;
    Lines    : TArray<string>;
    IntfLine : Integer;
    ImplLine : Integer;
    Syms     : TArray<TSymbol>;
    Refs     : TArray<TReference>;
    UsesList : TArray<TUnitUse>;
  end;

  TNeed = record
    Owner    : TSymbol;
    OwnerStem: string;
    Sect     : TSect;
    Line     : Integer;
    RefName  : string;
    RefKind  : TSymbolKind;
  end;

  TCandidate = record
    Actual: TSymbol;
    Owner : TSymbol;
    Stem  : string;
  end;

  TMoveKind = (mvDecl, mvWithBodies, mvBase, mvBlocked);

  TBaseMember = record
    Sym  : TSymbol;
    Range: TLineRange;
  end;

  TSwitchLine = record
    Fid    : Int64;
    Line   : Integer;
    NewText: string;
  end;

  { B4: a plain field `F: TX;` (B4-b), a local `L: TX` (B4-a) or a parameter of type TX that the F5
    base class may stand in for; RoutineId 0 = a field (its scope is the unit). }
  TObjSlot = record
    Name     : string;
    IsField  : Boolean;
    Fid      : Int64;
    Line     : Integer;
    RoutineId: Int64;
  end;

  TMoveItem = record
    Sym        : TSymbol;
    Stem       : string;
    Kind       : TMoveKind;
    Keyword    : string;
    Header     : Integer;
    Decl       : TLineRange;
    Bodies     : TArray<TLineRange>;
    Drags      : TArray<string>;
    Reason     : string;
    BaseName   : string;
    BaseIndent : string;
    BaseMembers: TArray<TBaseMember>;
    CutFids    : TArray<Int64>;
    HeaderNew  : string;
    Switches   : TArray<TSwitchLine>;
    Refusal    : string;  // mvBlocked by a recipe gate: its refusal kind (F5: 'base-class'); '' otherwise
    SameLine   : Boolean; // W6 C6: the keyword opens the declaration's own line (`var X: T;`); Header = Sym.StartLine
    BaseAncestor: string; // B4-d: the ancestor the base class inherits, as the header writes it; '' = TObject
  end;

  TConsumer = record
    Fid : Int64;
    Sect: TSect;
    Line: Integer;
  end;

  TUsesVerdict = (uvKeep, uvKeepUnseen, uvMove, uvRemove);

  TUsesDecision = record
    Fid        : Int64;
    PartnerStem: string;
    Sect       : TSect;
    Verdict    : TUsesVerdict;
    Still      : string;
  end;

  TEditKind = (ekDelete, ekReplace, ekInsertAfter, ekManual);

  TFileEdit = record
    Kind    : TEditKind;
    First   : Integer;
    Last    : Integer;
    NewLines: TArray<string>;
    Note    : string;
    Refusal : string;  // ekManual only: the refusal kind ('' = manual-edit)
  end;

  TEdgeEval = record
    FromStem: string;
    ToStem  : string;
    Needs   : TArray<TNeed>;
    Movable : Boolean;
    Why     : string;
    Cost    : Integer;
    Surface : TEdgeSurface;  // what FromStem takes from ToStem (E18 T4)
    Recipe  : TCutRecipe;    // the recipe that applies to this edge (E18 T7 R3); crNone = none applies
    Refusal : string;        // the refusal kind when a recipe was tried and refused
    Steps   : TRecipeSteps;  // crRoutineInversion: the R1 steps
    ViaBase : Boolean;       // B4-f: crMoveGlobals through a base class of a class need (the consumer's fid is its cut)
  end;

  TPredGroup = record
    Members: TArray<string>;
    HasIntf: Boolean;
  end;

  /// <summary>Whether a cycle's plan can be applied without a human.</summary>
  TCycleVerdict = (cvMechanical, cvRefused);

  /// <summary>A unit the plan creates: its name, its file and its full text.</summary>
  TNewUnit = record
    UnitName: string;
    Path    : string;
    Text    : TArray<string>;
  end;

  /// <summary>Everything BuildPlan computed for one circular group, as data,
  /// so a caller can render it (RenderPlan) or apply it.</summary>
  /// <remarks>
  /// <para>Ownership: the record owns Edits (created by BuildPlan, owning its
  /// lists). Do not copy the record -- a copy shares the same Edits object --
  /// and call Release exactly once, on the one copy you keep. It holds the edits of every touched unit EXCEPT the project's .dpr,
  /// each list ordered bottom-up (the order the playbook prints them); the .dpr
  /// edits are in DprEdits, the .dproj edits in DprojEdits (index order).
  /// Touched is the file order the playbook prints (cycle members first, the
  /// .dpr last).</para>
  /// <para>A plan with any refusal has Verdict = cvRefused but still carries
  /// every step the playbook prints.</para>
  /// </remarks>
  TCycleFixPlan = record
    CycleIndex: Integer;                          // 1-based, DoCycles order
    Units     : TArray<string>;                   // stems
    HasIntf   : Boolean;
    Part      : Char;                             // 'A' or 'B'
    Verdict   : TCycleVerdict;
    Refusals  : TArray<TRefusal>;
    Items     : TArray<TMoveItem>;
    Decisions : TArray<TUsesDecision>;
    NewUnits  : TArray<TNewUnit>;
    Edits     : TDictionary<Int64, TList<TFileEdit>>;  // fid -> edits, EditOrder applied
    DprojEdits: TArray<TFileEdit>;
    DprEdits  : TArray<TFileEdit>;
    Touched   : TArray<Int64>;                    // fids
    Predicted : TArray<TPredGroup>;
    ExpectedOutput: TArray<string>;
    CutEdge   : TEdgeEval;                        // Part B
    Evals     : TArray<TEdgeEval>;                // Part B: every edge weighed
    /// <summary>Frees Edits (and its lists); safe to call twice.</summary>
    procedure Release;
  end;

  TCyclePlanner = class(TNoRefCountObject, IEdgeSurfaceSource)  // dl:ok god-class@ac0b, high-response@ac0b -- implementation-private; one per cycles --plan run, holding the shared per-cycle state that every small step reads; its many methods are the steps, each short
  private
    FAccess     : TDictionary<Int64, TCallEdge>;  // ref id -> member_accesses row, loaded on first use
    FStore      : ISymbolStore;
    FLibStore   : ISymbolStore;  // platform library (R2 ancestry), read-only; nil when none
    FDbPath     : string;
    FSccs       : TList<TArray<string>>;
    FGraph      : TCycleGraph;
    FOut        : TStrings;
    FProjectFid : Int64;
    FProjectFile: string;
    FFiles      : TDictionary<Int64, TPlanFile>;
    FPaths      : TDictionary<Int64, string>;
    FStemFid    : TDictionary<string, Int64>;
    FUsersOf    : TObjectDictionary<string, TList<Int64>>;
    FCands      : TDictionary<string, TArray<TCandidate>>;
    FSyms       : TDictionary<Int64, TSymbol>;
    FNeeds      : TDictionary<Int64, TArray<TNeed>>;
    // per-cycle state, cleared by ResetCycle
    FComp       : TArray<string>;
    FMembers    : TDictionary<string, Boolean>;
    FItems      : TDictionary<Int64, TMoveItem>;
    FOrder      : TList<Int64>;
    FManual     : TList<TMoveItem>;
    FDeleted    : TDictionary<string, Boolean>;
    FReplaced   : TDictionary<string, string>;
    FExtraEdits : TObjectDictionary<Int64, TList<TFileEdit>>;
    FLeafName   : TDictionary<string, string>;
    FLeafPath   : TDictionary<string, string>;
    FLeafInfo   : TDictionary<string, TUntangleLeaf>;  // source stem -> the catalog's answer
    FLeafDeps   : TObjectDictionary<string, TList<string>>;
    FConsumers  : TObjectDictionary<Int64, TList<TConsumer>>;
    FPulledBy   : TDictionary<Int64, string>;
    FDecisions  : TList<TUsesDecision>;
    FUsesAdd    : TObjectDictionary<string, TList<string>>;
    FUsesDel    : TObjectDictionary<string, TList<string>>;
    FDprojEdits : TList<TFileEdit>;
    FTouched    : TList<Int64>;
    FPredicted  : TList<TPredGroup>;
    FCutEdge    : TEdgeEval;
    FInversion  : TRecipeSteps;  // R1 / R2 steps of FCutEdge; Recipe = crNone otherwise
    FPartBBest  : TEdgeEval;     // Part A groups: the edge Part B cuts after Part A (FromStem = '' when none)
    FPartBDone  : Boolean;       // FPartBBest has been computed for the current group
    FFixProject : string;        // the project named in the Fix it commands; '' = placeholder
    // loading + resolution
    procedure IndexAllFiles;
    function GetFile(pFid: Int64): TPlanFile;
    function PathOf(pFid: Int64): string;
    function StemOfFid(pFid: Int64): string;
    function GetSym(pId: Int64): TSymbol;
    function OwnerOf(const pSym: TSymbol; out pOwner: TSymbol): Boolean;
    function CandidatesFor(const pName: string): TArray<TCandidate>;
    function VisibleStems(const pF: TPlanFile; pSect: TSect): TArray<string>;
    function PickCandidate(const pF: TPlanFile; pSect: TSect; const pCands: TArray<TCandidate>): Integer;
    function IsLocalName(const pR: TReference): Boolean;
    function Resolve(const pF: TPlanFile; const pR: TReference; out pNeed: TNeed): Boolean;
    function NeedsOf(pFid: Int64): TArray<TNeed>;
    function FidOfStem(const pStem: string): Int64;
    function UnitNameOfStem(const pStem: string): string;
    // closure
    procedure ResetCycle(const pComp: TArray<string>);
    function IsDeclOnly(const pSym: TSymbol): Boolean;
    function BodyRanges(const pSym: TSymbol): TArray<TLineRange>;
    function NeedsInRanges(const pF: TPlanFile; const pRanges: TArray<TLineRange>): TArray<TNeed>;
    function MovedRanges(const pItem: TMoveItem): TArray<TLineRange>;
    function Classify(const pSym: TSymbol; const pCut: TArray<Int64>): TMoveItem;
    procedure ClassifyStructured(const pF: TPlanFile; var pItem: TMoveItem);
    procedure SetHeader(const pF: TPlanFile; var pItem: TMoveItem);
    procedure BuildBase(const pF: TPlanFile; var pItem: TMoveItem);
    function UsedMemberNames(const pChildren: TArray<TSymbol>; const pCut: TArray<Int64>; const pClassName: string = ''): TDictionary<string, Boolean>;
    function PullMembers(const pF: TPlanFile; var pItem: TMoveItem; const pChildren: TArray<TSymbol>;
      pUsed: TDictionary<string, Boolean>): Boolean;
    function BuildSwitches(var pItem: TMoveItem): Boolean;
    function BaseSiteRefusal(const pItem: TMoveItem): string;
    function AncestorRefusal(const pF: TPlanFile; const pItem: TMoveItem; const pAnc: string): string;
    function StreamedMemberRefusal(const pF: TPlanFile; const pItem: TMoveItem): string;
    function ClassParentRefusal(const pItem: TMoveItem): string;
    function ClassTestSiteOk(const pCode: string; pIndex, pLen: Integer; const pItem: TMoveItem): Boolean;
    function FieldSiteRefusal(const pItem: TMoveItem; pFid: Int64; pLine: Integer; out pField: string;
      const pSlots: TArray<string> = nil): string;
    function ParamBodyRefusal(pFid: Int64; pLine: Integer; const pParam: string;
      const pFields: TArray<string>; const pSlots: TArray<string> = nil): string;
    function ObjSlotAt(const pItem: TMoveItem; pFid: Int64; pLine, pCol: Integer; out pSlot: TObjSlot): Boolean;
    function ObjSlotRefusal(const pItem: TMoveItem; const pSlot: TObjSlot; const pFields: TArray<string>;
      const pSlots: TArray<TObjSlot>): string;
    function TryAdd(const pSym: TSymbol; const pCut: TArray<Int64>; out pWhy: string): Boolean;
    function AddDependencies(const pItem: TMoveItem; out pWhy: string): Boolean;
    function AddCompanions(const pItem: TMoveItem; out pWhy: string): Boolean;
    procedure NotePulledBy(const pSym, pBy: TSymbol);
    procedure Rollback(pSnap: Integer);
    function IsMovedFor(const pOwner: TSymbol; pFid: Int64): Boolean;
    // materialise
    procedure Materialize;
    procedure AssignLeafNames;
    function LeafStems(pDecision: TUntangleDecision): TArray<string>;
    procedure MarkDeleted(pFid: Int64; const pRange: TLineRange);
    function IsDeleted(pFid: Int64; pLine: Integer): Boolean;
    procedure MarkReplaced(pFid: Int64; pLine: Integer; const pText: string);
    procedure MarkItemLines;
    procedure DeleteEmptyHeaders;
    procedure CollectConsumers;
    procedure AddConsumer(const pItem: TMoveItem; pFid: Int64; pSect: TSect; pLine: Integer);
    procedure CollectLeafDeps;
    procedure DecideUses;
    procedure DecideOne(const pA: TPlanFile; const pU: TUnitUse);
    procedure DecideUnseenIntfEntries;
    procedure DecideUnseenIntfEntry(const pFrom, pTo: string);
    function IntfEntryDecided(const pFrom, pTo: string): Boolean;
    function LexicalUseOf(const pFrom, pTo: string; pSect: TSect; out pLine: Integer): string;
    procedure RegisterLeaves;
    procedure ExtendLeaves;
    function MergeLeafUses(const pF: TPlanFile; pSect: TSect; pAnchor: Integer;
      const pEntries: TArray<string>): TArray<string>;
    procedure AddUses(pFid: Int64; pSect: TSect; const pEntry: string);
    procedure DelUses(pFid: Int64; pSect: TSect; const pStem: string);
    procedure Touch(pFid: Int64);
    function EntryText(const pF: TPlanFile; const pU: TUnitUse): string;
    function UsesEntryFor(const pF: TPlanFile; const pLeafStem: string): string;
    procedure DedupeAdds;
    procedure BuildUsesEdits;
    procedure BuildClauseEdit(const pF: TPlanFile; pSect: TSect);
    function SectionEntries(const pF: TPlanFile; pSect: TSect): TArray<TUnitUse>;
    function ListOf(pDict: TObjectDictionary<string, TList<string>>; pFid: Int64; pSect: TSect): TList<string>;
    function EditList(pFid: Int64): TList<TFileEdit>;
    function EditsOf(pFid: Int64): TArray<TFileEdit>;
    function EditOrder: TArray<Int64>;
    // prediction
    procedure Predict;
    function PredictedEdges: TObjectDictionary<string, TList<string>>;
    function Targets(pEdges: TObjectDictionary<string, TList<string>>; const pFrom: string): TArray<string>;
    function ExpectedOutput(pSelf: Integer): TArray<string>;
    function GroupHasIntf(const pComp: TArray<string>): Boolean;
    function EvaluateEdge(const pFrom, pTo: string; const pNeeds: TArray<TNeed>; pViaBase: Boolean = False): TEdgeEval;
    procedure PlanBaseHandOver(pEvals: TList<TEdgeEval>);
    function BaseCut(const pSym: TSymbol; const pFrom: string; pViaBase: Boolean): TArray<Int64>;
    procedure RenderEdgeChoices(const pEvals: TArray<TEdgeEval>);
    function RemainingNeeds(const pFrom, pTo: string; pAll: Boolean): TArray<TNeed>;
    // rendering
    procedure Emit(const pText: string);
    procedure EmitFmt(const pFmt: string; const pArgs: array of const);
    procedure EmitBlock(const pFence: string; const pLines: TArray<string>);
    procedure RenderHeader;
    procedure RenderFiles;
    procedure RenderIntfWhy;
    procedure RenderImplWhy;
    procedure RenderMoves(pStep: Integer);
    procedure RenderOneMove(pNo: Integer; const pItem: TMoveItem);
    procedure RenderBaseRecipe(const pItem: TMoveItem);
    procedure RenderConsumers(const pItem: TMoveItem);
    procedure RenderManual;
    procedure RenderDecisions(pStep: Integer);
    procedure RenderLeafUnits(pStep: Integer);
    function LeafUnitText(const pStem: string): TArray<string>;
    function LeafEntries(const pStem: string; pSect: TSect): TArray<string>;
    function LeafDeclLines(const pStem: string; pBodies: TList<TLineRange>): TArray<string>;
    function BaseClassText(const pItem: TMoveItem): TArray<string>;
    procedure RenderEdits(pStep: Integer);
    procedure RenderFileEdits(const pTitle: string; const pLines: TArray<string>;
      const pEdits: TArray<TFileEdit>; const pFence: string);
    procedure RenderChecklist(pSelf: Integer);
    procedure RenderCompileHelp;
    procedure RenderDone(pIntf: Boolean);
    procedure RenderPartB;
    procedure CollectPartB(const pEvals: TList<TEdgeEval>; const pTexts: TList<string>);
    function PartBBest: TEdgeEval;
    procedure RenderFixIt(const pPlan: TCycleFixPlan);
    function FixCommand(pCycle: Integer; pApply: Boolean): string;
    function IntfStatusLine: string;
    procedure RenderIntfCycle(const pPlan: TCycleFixPlan);
    procedure RenderImplCycle(const pPlan: TCycleFixPlan);
    // planning (no output)
    procedure PlanIntfCycle;
    function PlanImplCycle: TArray<TEdgeEval>;
    procedure PlanInversion(pEvals: TList<TEdgeEval>);
    function ProbeInversionMoves(const pEv: TEdgeEval; out pMoved: TArray<string>; out pMoveIds: TArray<Int64>;
      out pCount: Integer): Boolean;
    procedure PlanMemberHandOver(pEvals: TList<TEdgeEval>);
    procedure SettleIfaceName(const pSurface: TEdgeSurface; const pLeaf: TUntangleLeaf; const pUnitScopes: TArray<string>;
      var pSteps: TRecipeSteps; var pRefusal: TRecipeRefusal);
    procedure RenderMemberHandOver(pStep: Integer);
    procedure EmitMemberWrites;
    function InversionLeaf(const pSteps: TRecipeSteps): TUntangleLeaf;
    function LeavesProgramReason(const pSteps: TRecipeSteps): string;
    procedure RegisterDeclUnit;
    procedure MaterializeInversion;
    function IsInversionStem(const pStem: string): Boolean;
    function InversionDeclLines(const pStem: string): TArray<string>;
    procedure SettleInversionNames(const pEv: TEdgeEval; const pLeaf: TUntangleLeaf; var pSteps: TRecipeSteps;
      var pRefusal: TRecipeRefusal);
    procedure RenderInversion(pStep: Integer);
    function InversionStillUsed: string;
    function InversionNames: string;
    procedure CapturePlan(var pPlan: TCycleFixPlan);
    function BuildView(const pPlan: TCycleFixPlan): TCyclePlanView;
    procedure CaptureRefusals(var pPlan: TCycleFixPlan);
    procedure DumpPlanForTests(const pPlan: TCycleFixPlan);
    procedure RenderNoMechanicalCut(const pEvals: TArray<TEdgeEval>);
    procedure RenderRemedy;
    function ReindexCommand: string;
    function CyclesCommand(pPlan: Boolean): string;
    function KindLabel(const pItem: TMoveItem): string;
    function MemberNames: string;
    // IEdgeSurfaceSource (DRagLint.Report.CycleEdge); FidOfStem above is the fourth
    function Store: ISymbolStore;
    function FileLines(pFid: Int64): TArray<string>;
    function BindName(pFid: Int64; pLine: Integer; const pName: string; out pOwner: TSymbol;
      out pStem: string): Boolean;
    function IsSccStem(const pStem: string): Boolean;
    function MemberAccessOf(pRefId: Int64; out pAccess: TCallEdge): Boolean;
  public
    constructor Create(const pStore: ISymbolStore; const pDbPath: string;
      const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pOut: TStrings;
      const pLibStore: ISymbolStore = nil);
    destructor Destroy; override;
    /// <summary>Computes the plan for one SCC without rendering.</summary>
    /// <param name="pCycleIndex">1-based index into the circular groups
    /// (DoCycles order).</param>
    /// <returns>The plan; the caller must call its Release.</returns>
    /// <remarks>Resets and refills the planner's per-cycle state, which then
    /// stays that of the returned plan until the next BuildPlan.</remarks>
    function BuildPlan(pCycleIndex: Integer): TCycleFixPlan;
    /// <summary>Renders the playbook for one SCC from a plan built by BuildPlan.</summary>
    /// <param name="pPlan">The plan the LAST BuildPlan call returned.</param>
    /// <exception cref="EInvalidOpException">Raised when pPlan is not the plan of the
    /// planner's current per-cycle state (another BuildPlan ran since).</exception>
    /// <remarks>The detail sections still read the planner's per-cycle state,
    /// which BuildPlan left in place; hence the guard.</remarks>
    procedure RenderPlan(const pPlan: TCycleFixPlan);
    procedure Run;
    /// <summary>What the Fix it block (text) and fix object (JSON) say about one group.</summary>
    /// <param name="pPlan">The plan the LAST BuildPlan call returned.</param>
    /// <returns>Availability, commands, cuttable edges and the first refusal, all taken from pPlan.</returns>
    /// <remarks>Availability is the planner's verdict: a mechanical cut with no refusal. It does not
    /// build; the dry run checks the baseline. Part A groups run the Part B weighing once, only to
    /// name the follow-up edge.</remarks>
    function FixHintOf(const pPlan: TCycleFixPlan): TCycleFixHint;
    /// <summary>The project named in the Fix it commands; '' prints the placeholder `&lt;your.dproj&gt;`.</summary>
    property FixProject: string read FFixProject write FFixProject;
    /// <summary>The surface of every uses edge inside one SCC.</summary>
    /// <param name="pCycleIndex">1-based index into the circular groups.</param>
    /// <returns>One surface per edge A -&gt; B with A, B in the group and B in A's
    /// uses, in group order.</returns>
    /// <remarks>Resets the planner's per-cycle state to that group.</remarks>
    function EdgeSurfacesOf(pCycleIndex: Integer): TArray<TEdgeSurface>;
  end;

{ TCycleFixPlan }

procedure TCycleFixPlan.Release;
begin
  FreeAndNil(Edits);
end;

{ ---------------------------------------------------------------------------
  small text helpers
  --------------------------------------------------------------------------- }

function StemOfPath(const pPath: string): string;
begin
  Result:= LowerCase(ChangeFileExt(ExtractFileName(StringReplace(pPath, '/', '\', [rfReplaceAll])), ''));
end;

function UnitNameOfPath(const pPath: string): string;
begin
  Result:= ChangeFileExt(ExtractFileName(StringReplace(pPath, '/', '\', [rfReplaceAll])), '');
end;

function LineKey(pFid: Int64; pLine: Integer): string;
begin
  Result:= Format(CKeyFmt, [pFid, pLine]);
end;

function SectKey(pFid: Int64; pSect: TSect): string;
begin
  Result:= Format(CKeyFmt, [pFid, Ord(pSect)]);
end;

function IsIndented(const pLine: string): Boolean;
begin
  Result:= (pLine <> '') and CharInSet(pLine[1], [' ', #9]);
end;

function IsCommentOnly(const pLine: string): Boolean;
var
  T: string;
begin
  T:= Trim(pLine);
  if T = '' then Exit(True);
  if StartsStr('//', T) then Exit(True);
  if StartsStr('{', T) and EndsStr('}', T) then Exit(True);
  Result:= StartsStr('(*', T) and EndsStr('*)', T);
end;

/// Text of a line before its first comment (`//`, `{`, `(*`); quotes are honoured.
function CodePart(const pLine: string): string;
var
  InStr: Boolean;
  Pair : string;
begin
  InStr:= False;
  for var I:= 1 to Length(pLine) do
  begin
    if pLine[I] = '''' then InStr:= not InStr;
    if InStr then Continue;
    Pair:= Copy(pLine, I, 2);
    if (pLine[I] = '{') or (Pair = '//') or (Pair = '(*') then Exit(Copy(pLine, 1, I - 1));
  end;
  Result:= pLine;
end;

function SourceEncodingOf(const pBytes: TBytes): TEncoding;
const
  CBomLen = 3;  // the UTF-8 BOM EF BB BF
  CBomEF  = $EF;
  CBomBB  = $BB;
  CBomBF  = $BF;
begin
  if (Length(pBytes) >= CBomLen) and (pBytes[0] = CBomEF) and (pBytes[1] = CBomBB) and (pBytes[2] = CBomBF) then
    Result:= TEncoding.UTF8
  else Result:= TEncoding.ANSI;
end;

function DecodeSource(const pBytes: TBytes; out pEncoding: TEncoding): string;
begin
  pEncoding:= SourceEncodingOf(pBytes);
  if pEncoding = TEncoding.UTF8 then
    Result:= TEncoding.UTF8.GetString(pBytes, Length(TEncoding.UTF8.GetPreamble), Length(pBytes) - Length(TEncoding.UTF8.GetPreamble))
  else Result:= TEncoding.ANSI.GetString(pBytes);
end;

function EncodeSource(const pText: string; pEncoding: TEncoding): TBytes;
begin
  Result:= pEncoding.GetBytes(pText);
  if pEncoding = TEncoding.UTF8 then Result:= TEncoding.UTF8.GetPreamble + Result;
end;

function ReadSourceLines(const pPath: string): TArray<string>;
var
  Enc: TEncoding;
begin
  var Lines:= TStringList.Create;
  try
    Lines.Text:= DecodeSource(TFile.ReadAllBytes(pPath), Enc);
    Result:= Lines.ToStringArray;
  finally
    Lines.Free;
  end;
end;

function LineAt(const pLines: TArray<string>; pLine: Integer): string;
begin
  if (pLine >= 1) and (pLine <= Length(pLines)) then Result:= pLines[pLine - 1]
  else Result:= '';
end;

function SliceLines(const pLines: TArray<string>; const pRange: TLineRange): TArray<string>;
begin
  SetLength(Result, pRange.Last - pRange.First + 1);
  for var I:= pRange.First to pRange.Last do Result[I - pRange.First]:= LineAt(pLines, I);
end;

function DocStart(const pLines: TArray<string>; pLine: Integer): Integer;
begin
  Result:= pLine;
  while (Result > 1) and StartsStr('///', Trim(LineAt(pLines, Result - 1))) do Dec(Result);
end;

function FindKeywordLine(const pLines: TArray<string>; const pWord: string): Integer;
begin
  for var I:= 0 to High(pLines) do
    if SameText(Trim(CodePart(pLines[I])), pWord) then Exit(I + 1);
  Result:= 0;
end;

function IsBlockWord(const pText: string): Boolean;
begin
  Result:= MatchText(Trim(CodePart(pText)), CBlockWords);
end;

/// Count of leading blanks / tabs of pLine.
function IndentOf(const pLine: string): Integer;
begin
  Result:= 0;
  while (Result < Length(pLine)) and CharInSet(pLine[Result + 1], [' ', #9]) do Inc(Result);
end;

/// The `type` / `var` / `const` line that opens the block holding pFirst, or 0: the nearest
/// column-1 block word above, or (W6 C6) an indented one indented LESS than pFirst -- a nested
/// class section (`  var` inside a class body) sits at or beyond the declaration's indent.
function HeaderOf(const pLines: TArray<string>; pFirst: Integer): Integer;
var
  L: Integer;
begin
  var Depth:= IndentOf(LineAt(pLines, pFirst));
  L:= pFirst - 1;
  while L >= 1 do
  begin
    var S:= LineAt(pLines, L);
    if not IsCommentOnly(S) then
    begin
      if not IsIndented(S) then Break;
      if (IndentOf(S) < Depth) and IsBlockWord(S) then Exit(L);
    end;
    Dec(L);
  end;
  if (L >= 1) and IsBlockWord(LineAt(pLines, L)) then Result:= L
  else Result:= 0;
end;

/// First line after pHeader that is indented no deeper than pHeader (a column-1 header: the
/// first column-1 construct).
function BlockEnd(const pLines: TArray<string>; pHeader: Integer): Integer;
var
  L: Integer;
begin
  var Depth:= IndentOf(LineAt(pLines, pHeader));
  L:= pHeader + 1;
  while (L <= Length(pLines)) and (IsCommentOnly(LineAt(pLines, L)) or
    (IsIndented(LineAt(pLines, L)) and (IndentOf(LineAt(pLines, L)) > Depth))) do Inc(L);
  Result:= L;
end;

/// W6 C6: the keyword of a declaration that opens its own line (`var GX: Integer = 2;`,
/// `type TR = record`), or ''. A one-line declaration must end the line: `var A: T; B: T;`
/// would carry B along, so it answers ''.
function SameLineKeyword(const pLine, pName: string; pOneLine: Boolean): string;
begin
  var Code:= Trim(CodePart(pLine));
  var M   := TRegEx.Match(Code, '^(type|var|const)\s+' + pName + '\b', [roIgnoreCase]);
  if not M.Success then Exit('');
  if pOneLine then
  begin
    var Bare:= TRegEx.Replace(Code, '''[^'']*''', '');
    if Pos(';', Bare) <> Length(Bare) then Exit('');
  end;
  Result:= LowerCase(M.Groups[1].Value);
end;

function RangeText(const pRanges: TArray<TLineRange>): string;
var
  S: TStringBuilder;
begin
  S:= TStringBuilder.Create;
  try
    for var R in pRanges do
    begin
      if S.Length > 0 then S.Append(', ');
      if R.First = R.Last then S.Append(R.First)
      else S.Append(R.First).Append('-').Append(R.Last);
    end;
    Result:= S.ToString;
  finally
    S.Free;
  end;
end;

function OneRange(pFirst, pLast: Integer): TLineRange;
begin
  Result.First:= pFirst;
  Result.Last := pLast;
end;

function WithRange(const pFirst: TLineRange; const pRest: TArray<TLineRange>): TArray<TLineRange>;
begin
  SetLength(Result, Length(pRest) + 1);
  Result[0]:= pFirst;
  for var I:= 0 to High(pRest) do Result[I + 1]:= pRest[I];
end;

function PrependBlank(const pLines: TArray<string>): TArray<string>;
begin
  SetLength(Result, Length(pLines) + 1);
  Result[0]:= '';
  for var I:= 0 to High(pLines) do Result[I + 1]:= pLines[I];
end;

function InRanges(pLine: Integer; const pRanges: TArray<TLineRange>): Boolean;
begin
  for var R in pRanges do
    if (pLine >= R.First) and (pLine <= R.Last) then Exit(True);
  Result:= False;
end;

function QuoteList(const pNames: TArray<string>): string;
var
  Shown: TList<string>;
begin
  Shown:= TList<string>.Create;
  try
    for var I:= 0 to Min(High(pNames), CMaxNamesShown - 1) do Shown.Add('`' + pNames[I] + '`');
    Result:= string.Join(', ', Shown.ToArray);
  finally
    Shown.Free;
  end;
  if Length(pNames) > CMaxNamesShown then Result:= Result + Format(' and %d more', [Length(pNames) - CMaxNamesShown]);
end;

function AddUnique(pList: TList<string>; const pText: string): Boolean;
begin
  for var S in pList do
    if SameText(S, pText) then Exit(False);
  pList.Add(pText);
  Result:= True;
end;

function StemOfEntry(const pEntry: string): string;
var
  P: Integer;
begin
  P:= Pos(' in ', LowerCase(pEntry));
  if P > 0 then Result:= LowerCase(Trim(Copy(pEntry, 1, P - 1)))
  else Result:= LowerCase(Trim(pEntry));
end;

function SectLabel(pSect: TSect): string;
begin
  case pSect of
    scIntf: Result:= 'interface';
    scImpl: Result:= 'implementation';
  else
    Result:= 'program uses';
  end;
end;

function FormatUses(const pIndent: string; const pEntries, pComments: TArray<string>): TArray<string>;
var
  Row: string;
begin
  SetLength(Result, Length(pEntries) + 1);
  Result[0]:= pIndent + 'uses';
  for var I:= 0 to High(pEntries) do
  begin
    Row:= CEntryIndent + pIndent + pEntries[I] + (if I = High(pEntries) then ';' else ',');
    if (I <= High(pComments)) and (pComments[I] <> '') then Row:= Row + ' ' + pComments[I];
    Result[I + 1]:= Row;
  end;
end;

{ ---------------------------------------------------------------------------
  E18 T3a: minimal edits to an EXISTING uses clause, computed over TUsesLexer
  tokens. The lexer treats comments as trivia, and only tokens -- plus a BLANK
  gap between two deleted tokens -- are ever deleted, so every comment
  survives. Add = `, <Unit>` after the last entry (before the `;` when a
  directive sits between the two). Remove = the entry and ONE separator: the
  following one (its line then goes away whole), or the preceding one when the
  following side holds a directive or a comment parts the entry from it while the
  preceding one is adjacent; the LAST entry takes the preceding separator and the
  `;`, which moves to the entry before (T17b D3). An entry in a
  conditional region, or a directive inside the span a removal deletes,
  refuses with `directive`; a directive elsewhere in the clause does not.
  --------------------------------------------------------------------------- }
type
  TOfsSpan = record
    Start: Integer;
    Stop : Integer;
  end;

const
  CClauseBreak = #13#10;
  CRefDirective = 'directive';
  CRefManual    = 'manual-edit';

function OfsSpan(pStart, pStop: Integer): TOfsSpan;
begin
  Result.Start:= pStart;
  Result.Stop := pStop;
end;

{ The first `uses` clause of the lexer's text, read by UnitRules' ParseClause
  (one uses grammar); Present = False when there is none or it does not parse. }
function ScanClause(pLex: TUsesLexer): TUsesClause;
var
  T: TTok;
begin
  Result:= Default(TUsesClause);
  repeat
    T:= pLex.Next;
  until (T.Kind = tkEof) or ((T.Kind = tkIdent) and not T.Escaped and SameText(T.Text, 'uses'));
  if (T.Kind = tkEof) or not ParseClause(pLex, T, Result) then Result.Present:= False;
end;

{ True when the entry span holds anything but its own tokens -- a comment or a
  directive -- asked of the lexer, so an `in 'path'` literal holding `{` or
  `//` is just a string. }
function EntryHasTrivia(const pText: string; const pE: TUsesEntry): Boolean;
var
  Lex : TUsesLexer;
  T   : TTok;
  Body: string;
  At  : Integer;
begin
  Body:= Copy(pText, pE.Start, pE.Stop - pE.Start);
  Lex := TUsesLexer.Create(Body);
  try
    At:= 1;
    Result:= False;
    repeat
      T:= Lex.Next;
      if Trim(Copy(Body, At, T.Start - At)) <> '' then Result:= True;
      At:= T.Stop;
    until Result or (T.Kind = tkEof);
  finally
    Lex.Free;
  end;
end;

{ Deletes the token spans pSpans (ascending) from pText, and every gap between
  two of them that is blank -- a gap holding a comment stays. pEatBlanks also
  deletes the spaces / tabs right after the last span. }
procedure DeleteSpans(var pText: string; const pSpans: array of TOfsSpan; pEatBlanks: Boolean);
var
  Runs: TList<TOfsSpan>;
  Cur : TOfsSpan;
begin
  Runs:= TList<TOfsSpan>.Create;
  try
    Cur:= pSpans[0];
    for var I:= 1 to High(pSpans) do
      if Trim(Copy(pText, Cur.Stop, pSpans[I].Start - Cur.Stop)) = '' then Cur.Stop:= pSpans[I].Stop
      else
      begin
        Runs.Add(Cur);
        Cur:= pSpans[I];
      end;
    if pEatBlanks then
      while (Cur.Stop <= Length(pText)) and CharInSet(pText[Cur.Stop], [' ', #9]) do Inc(Cur.Stop);
    Runs.Add(Cur);
    for var I:= Runs.Count - 1 downto 0 do Delete(pText, Runs[I].Start, Runs[I].Stop - Runs[I].Start);
  finally
    Runs.Free;
  end;
end;

{ Adds pEntry after the last entry; returns the refusal kind or ''. }
function AddClauseEntry(var pText: string; pLex: TUsesLexer; const pScan: TUsesClause; const pEntry: string): string;
var
  L        : TUsesEntry;
  At       : Integer;
  LineStart: Integer;
  Indent   : string;
begin
  if pScan.Semi.Depth > 0 then Exit(CRefDirective);
  L := pScan.Entries[High(pScan.Entries)];
  L.Start:= L.Start - Ord(L.Escaped);
  At:= if pLex.DirectiveIn(L.Stop, pScan.Semi.Start) then pScan.Semi.Start else L.Stop;
  LineStart:= L.Start;
  while (LineStart > 1) and not CharInSet(pText[LineStart - 1], [#10, #13]) do Dec(LineStart);
  Indent:= Copy(pText, LineStart, L.Start - LineStart);
  { one entry per line stays one entry per line; an inline clause stays inline }
  if (Trim(Indent) = '') and (LineStart > pScan.UsesTok.Stop) then Insert(',' + CClauseBreak + Indent + pEntry, pText, At)
  else Insert(', ' + pEntry, pText, At);
  Result:= '';
end;

{ True when entry pIdx has a preceding separator that a removal may take (outside a
  conditional, no directive up to the entry's end) with only blanks between the two. }
function PrevAdjacent(const pText: string; pLex: TUsesLexer; const pScan: TUsesClause; pIdx: Integer): Boolean;
begin
  if pIdx = 0 then Exit(False);
  var S:= pScan.Commas[pIdx - 1];
  var E:= pScan.Entries[pIdx];
  E.Start:= E.Start - Ord(E.Escaped);
  Result:= (S.Depth = 0) and not pLex.DirectiveIn(S.Start, E.Stop) and (Trim(Copy(pText, S.Stop, E.Start - S.Stop)) = '');
end;

{ Removes entry pIdx with one separator; returns the refusal kind or ''. }
function RemoveClauseEntry(var pText: string; pLex: TUsesLexer; const pScan: TUsesClause; pIdx: Integer): string;
var
  E: TUsesEntry;
  S: TTok;
begin
  E:= pScan.Entries[pIdx];
  if E.Depth > 0 then Exit(CRefDirective);
  if EntryHasTrivia(pText, E) then Exit(CRefManual);
  E.Start:= E.Start - Ord(E.Escaped);  { an '&ident' entry's span starts at its '&' }
  Result:= CRefDirective;
  if Length(pScan.Entries) = 1 then
  begin
    { the last entry goes: so does the clause }
    if not pLex.DirectiveIn(pScan.UsesTok.Start, pScan.Semi.Stop) then
    begin
      DeleteSpans(pText, [OfsSpan(pScan.UsesTok.Start, pScan.UsesTok.Stop), OfsSpan(E.Start, E.Stop),
        OfsSpan(pScan.Semi.Start, pScan.Semi.Stop)], True);
      Result:= '';
    end;
  end
  else if (pIdx = High(pScan.Entries)) and (pScan.Commas[pIdx - 1].Depth = 0) and (pScan.Semi.Depth = 0) and
    not pLex.DirectiveIn(pScan.Entries[pIdx - 1].Stop, pScan.Semi.Stop) then
  begin
    { T17b D3: the last entry goes with its separator AND the `;`, which moves to the
      entry before -- so neither a leading-comma clause (`  , X` / `  , Y;`) nor a
      comment line before the entry leaves a line holding only `;` }
    S:= pScan.Commas[pIdx - 1];
    DeleteSpans(pText, [OfsSpan(S.Start, S.Stop), OfsSpan(E.Start, E.Stop),
      OfsSpan(pScan.Semi.Start, pScan.Semi.Stop)], False);
    Insert(';', pText, pScan.Entries[pIdx - 1].Stop);
    Result:= '';
  end
  else if (pIdx < High(pScan.Entries)) and (pScan.Commas[pIdx].Depth = 0) and
    not pLex.DirectiveIn(E.Start, pScan.Commas[pIdx].Stop) and
    ((Trim(Copy(pText, E.Stop, pScan.Commas[pIdx].Start - E.Stop)) = '') or not PrevAdjacent(pText, pLex, pScan, pIdx)) then
  begin
    { the following separator -- unless a comment parts the entry from it while the
      preceding one is adjacent (T17b D3: `  , X` then `  // why` then `  , Y` lost
      X and the comma before Y, leaving a line `  , `) }
    S:= pScan.Commas[pIdx];
    DeleteSpans(pText, [OfsSpan(E.Start, E.Stop), OfsSpan(S.Start, S.Stop)], True);
    Result:= '';
  end
  else if (pIdx > 0) and (pScan.Commas[pIdx - 1].Depth = 0) and not pLex.DirectiveIn(pScan.Commas[pIdx - 1].Start, E.Stop) then
  begin
    S:= pScan.Commas[pIdx - 1];
    DeleteSpans(pText, [OfsSpan(S.Start, S.Stop), OfsSpan(E.Start, E.Stop)], False);
    Result:= '';
  end;
end;

function IndexOfEntry(const pScan: TUsesClause; const pStem: string): Integer;
begin
  for var I:= 0 to High(pScan.Entries) do
    if SameText(pScan.Entries[I].Name, pStem) then Exit(I);
  Result:= -1;
end;

{ The ONE minimal edit applying pAdds (entry texts) and pDels (stems) to the
  existing uses clause whose `uses` keyword is on line pUsesLine. Adds go
  first, so a removal never empties a clause that gains an entry. First = 0
  when nothing changes; a refusal is an ekManual edit on the line it names,
  its Refusal the kind. }
function ClauseEdit(const pLines: TArray<string>; pUsesLine: Integer; const pSectLabel: string;
  const pAdds, pDels: TArray<string>): TFileEdit;
var
  Old   : TArray<string>;
  Src   : string;           // the clause onward, unedited
  Text  : string;           // the same, as the ops edit it
  Orig  : TUsesClause;
  Cur   : TUsesClause;
  Lex   : TUsesLexer;
  Ops   : TList<string>;  // '+entry' / '-stem', in order
  Kind  : string;
  BadOfs: Integer;
  Pre   : Integer;
  Suf   : Integer;
  Mid   : TList<string>;
begin
  Result:= Default(TFileEdit);
  Old   := Copy(pLines, pUsesLine - 1, MaxInt);
  Src   := string.Join(CClauseBreak, Old);
  Text  := Src;
  Kind  := '';
  Lex   := TUsesLexer.Create(Src);
  try
    Orig:= ScanClause(Lex);
  finally
    Lex.Free;
  end;
  BadOfs:= if Orig.Present then Orig.UsesTok.Start else 1;
  if not Orig.Present then Kind:= CRefManual;
  Ops:= TList<string>.Create;
  try
    if Kind = '' then
    begin
      for var S in pAdds do
      begin
        var I:= IndexOfEntry(Orig, StemOfEntry(S));
        if I < 0 then Ops.Add('+' + S);
      end;
      { a stem both removed and added again stays where it is }
      for var S in pDels do
        if IndexOfEntry(Orig, S) >= 0 then
        begin
          var Readded:= False;
          for var A in pAdds do Readded:= Readded or SameText(StemOfEntry(A), S);
          if not Readded then Ops.Add('-' + S);
        end;
    end;
    for var Op in Ops do
    begin
      Lex:= TUsesLexer.Create(Text);
      try
        Cur:= ScanClause(Lex);
        if not Cur.Present then Kind:= CRefManual
        else if Op[1] = '+' then
        begin
          Kind:= AddClauseEntry(Text, Lex, Cur, Copy(Op, 2, MaxInt));
          BadOfs:= Orig.Semi.Start;
        end
        else
        begin
          { both indexes exist by construction (a removal is queued only for an
            entry of Orig, and adds never remove one) -- refuse, never index -1 }
          var InCur := IndexOfEntry(Cur, Copy(Op, 2, MaxInt));
          var InOrig:= IndexOfEntry(Orig, Copy(Op, 2, MaxInt));
          if (InCur < 0) or (InOrig < 0) then Kind:= CRefManual
          else
          begin
            Kind  := RemoveClauseEntry(Text, Lex, Cur, InCur);
            BadOfs:= Orig.Entries[InOrig].Start;
          end;
        end;
      finally
        Lex.Free;
      end;
      if Kind <> '' then Break;
    end;
  finally
    Ops.Free;
  end;
  if Kind <> '' then
  begin
    { the line the refusal names, counted in the UNEDITED clause }
    Result.Kind   := ekManual;
    Result.Refusal:= Kind;
    Result.First  := pUsesLine;
    for var I:= 1 to BadOfs - 1 do
      if Src[I] = #10 then Inc(Result.First);
    Result.Last   := Result.First;
    Result.Note   := Format('refused: %s -- the %s uses clause, line %d, cannot be edited token by token (%s). ' +
      'Edit it by hand: remove %s; add %s.', [Kind, pSectLabel, Result.First,
      (if Kind = CRefDirective then 'the edit would touch a compiler directive or a conditional entry'
       else 'a comment inside an entry, or a clause shape the lexer does not read'),
      (if Length(pDels) > 0 then QuoteList(pDels) else 'nothing'), (if Length(pAdds) > 0 then QuoteList(pAdds) else 'nothing')]);
    Exit;
  end;
  var Fresh:= Text.Split([CClauseBreak]);
  Pre:= 0;
  while (Pre < Length(Old)) and (Pre < Length(Fresh)) and (Old[Pre] = Fresh[Pre]) do Inc(Pre);
  Suf:= 0;
  while (Suf < Length(Old) - Pre) and (Suf < Length(Fresh) - Pre) and (Old[High(Old) - Suf] = Fresh[High(Fresh) - Suf]) do
    Inc(Suf);
  Mid:= TList<string>.Create;
  try
    { a line an edit left blank goes away with it }
    for var I:= Pre to High(Fresh) - Suf do
      if Trim(Fresh[I]) <> '' then Mid.Add(Fresh[I]);
    if (Length(Old) - Pre - Suf = 0) and (Mid.Count = 0) then Exit;
    Result.NewLines:= Mid.ToArray;
  finally
    Mid.Free;
  end;
  if Length(Old) - Pre - Suf = 0 then
  begin
    Result.Kind := ekInsertAfter;
    Result.First:= pUsesLine + Pre - 1;
    Result.Last := Result.First;
  end
  else
  begin
    Result.Kind := if Length(Result.NewLines) = 0 then ekDelete else ekReplace;
    Result.First:= pUsesLine + Pre;
    Result.Last := pUsesLine + Length(Old) - Suf - 1;
  end;
end;

function SortedInts(pList: TList<Integer>): TArray<Integer>;
begin
  pList.Sort;
  Result:= pList.ToArray;
end;

/// Coarse layer of a path, to flag an inverted dependency (COMMON -> CLIENT/SERVER).
function LayerOfPath(const pPath: string): string;
begin
  if ContainsText(pPath, '\common\') then Exit('COMMON');
  if ContainsText(pPath, '\client\') then Exit('CLIENT');
  if ContainsText(pPath, '\server\') then Exit('SERVER');
  Result:= '';
end;

function SectOf(const pF: TPlanFile; pLine: Integer): TSect;
begin
  if pF.IsProgram then Exit(scProg);
  if (pF.ImplLine > 0) and (pLine >= pF.ImplLine) then Exit(scImpl);
  Result:= scIntf;
end;

type
  TTypeSite = (tsParam, tsResult, tsOther);

{ E18 T7 F5: where the type name at column pCol of line pLine sits. tsParam: a
  parameter of a routine header (pParam = the group before the colon, e.g.
  `const a, b`); tsResult: a function result; tsOther: anything else (a field, a
  variable, a cast, a generic argument, a procedural type's parameter). The header
  is read backwards up to CMaxHeaderLines lines for the unmatched `(`. }
function TypeSiteAt(const pLines: TArray<string>; pLine, pCol: Integer; out pParam: string): TTypeSite;
const
  CMaxHeaderLines = 30;
var
  S, Tail, Head: string;
  Depth, L, Open: Integer;
begin
  pParam:= '';
  S:= TrimRight(Copy(CodePart(LineAt(pLines, pLine)), 1, pCol - 1));
  if not EndsStr(':', S) then Exit(tsOther);
  S:= TrimRight(Copy(S, 1, Length(S) - 1));
  if EndsStr(')', S) or TRegEx.IsMatch(S, '\bfunction\s+[\w.<>]+$', [roIgnoreCase]) then Exit(tsResult);
  Tail := '';
  Depth:= 0;
  L    := pLine;
  Open := 0;
  while Open = 0 do
  begin
    for var I:= Length(S) downto 1 do
    begin
      if S[I] = ')' then Inc(Depth)
      else if (S[I] = '(') and (Depth > 0) then Dec(Depth)
      else if S[I] = '(' then
      begin
        Open:= I;
        Break;
      end;
    end;
    if Open > 0 then Break;
    Tail:= S + ' ' + Tail;
    Dec(L);
    if (L < 1) or (pLine - L > CMaxHeaderLines) then Exit(tsOther);
    S:= CodePart(LineAt(pLines, L));
    if IsBlockWord(S) or SameText(Trim(S), 'begin') then Exit(tsOther);
  end;
  Head:= TrimRight(Copy(S, 1, Open - 1));
  if not TRegEx.IsMatch(Head, '\b(procedure|function|constructor|destructor|operator)\s+[\w.<>, ]+$', [roIgnoreCase]) then
    Exit(tsOther);
  Tail:= Copy(S, Open + 1, MaxInt) + ' ' + Tail;
  pParam:= Trim(Copy(Tail, LastDelimiter(';', Tail) + 1, MaxInt));
  Result:= tsParam;
end;

{ E18 T7 F5: the end of a routine's implementation header in lines pFirst..pLast:
  the first `;` outside the parameter list (pLine, pCol). False when none. }
function HeaderEnd(const pLines: TArray<string>; pFirst, pLast: Integer; out pLine, pCol: Integer): Boolean;
var
  Depth: Integer;
begin
  Depth:= 0;
  for var L:= pFirst to pLast do
  begin
    var Code:= CodePart(LineAt(pLines, L));
    for var I:= 1 to Length(Code) do
      if Code[I] = '(' then Inc(Depth)
      else if Code[I] = ')' then Dec(Depth)
      else if (Code[I] = ';') and (Depth = 0) then
      begin
        pLine:= L;
        pCol := I;
        Exit(True);
      end;
  end;
  pLine := 0;
  pCol  := 0;
  Result:= False;
end;

{ E18 T7 F5: the occurrence of a name at pIndex (length pLen) in pCode is a
  receiver (`p.`) or one side of a nil test (`p = nil`, `p <> nil`, `nil = p`). }
function IsReceiverOrNilTest(const pCode: string; pIndex, pLen: Integer): Boolean;
begin
  var Rest  := Copy(pCode, pIndex + pLen, MaxInt);
  var Before:= Copy(pCode, 1, pIndex - 1);
  Result:= TRegEx.IsMatch(Rest, '^\s*\.') or TRegEx.IsMatch(Rest, '^\s*(=|<>)\s*nil\b', [roIgnoreCase]) or
    TRegEx.IsMatch(Before, '\bnil\s*(=|<>)\s*$', [roIgnoreCase]);
end;

{ Whether pIds holds pId. }
function HasId(pId: Int64; const pIds: TArray<Int64>): Boolean;
begin
  for var Id in pIds do
    if Id = pId then Exit(True);
  Result:= False;
end;

{ E18 T7 R3: the order the recipes are preferred in (lower first). }
function RecipeRank(pRecipe: TCutRecipe): Integer;
begin
  case pRecipe of
    crMoveGlobals     : Result:= 0;
    crRoutineInversion: Result:= 1;
    crMemberInterface : Result:= 2;
  else
    Result:= MaxInt;
  end;
end;

{ B4-f: a base-class move ranks after R2 (it moves fields out of the class; an interface moves nothing). }
function EvalRank(const pEv: TEdgeEval): Integer;
begin
  Result:= if pEv.ViaBase then RecipeRank(crMemberInterface) + 1 else RecipeRank(pEv.Recipe);
end;

{ E18 T7 R3: pEv is a better cut than pBest -- the preferred recipe, then the
  fewest surface members, then the fewest surface refs, then the lower recipe
  cost; an empty pBest loses to any edge a recipe applies to. }
function BetterCut(const pEv, pBest: TEdgeEval): Boolean;
begin
  if pEv.Recipe = crNone then Exit(False);
  if pBest.FromStem = '' then Exit(True);
  if EvalRank(pEv) <> EvalRank(pBest) then Exit(EvalRank(pEv) < EvalRank(pBest));
  if Length(pEv.Surface.Members) <> Length(pBest.Surface.Members) then
    Exit(Length(pEv.Surface.Members) < Length(pBest.Surface.Members));
  if Length(pEv.Surface.Refs) <> Length(pBest.Surface.Refs) then
    Exit(Length(pEv.Surface.Refs) < Length(pBest.Surface.Refs));
  Result:= pEv.Cost < pBest.Cost;
end;

function RecipeLabel(pRecipe: TCutRecipe): string;
begin
  case pRecipe of
    crMoveGlobals     : Result:= 'move globals';
    crRoutineInversion: Result:= 'routine-call inversion';
    crMemberInterface : Result:= 'member hand-over';
  else
    Result:= 'none';
  end;
end;

{ ---------------------------------------------------------------------------
  TCyclePlanner -- construction and loading
  --------------------------------------------------------------------------- }

constructor TCyclePlanner.Create(const pStore: ISymbolStore; const pDbPath: string;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pOut: TStrings;
  const pLibStore: ISymbolStore);
begin
  inherited Create;
  FStore     := pStore;
  FLibStore  := pLibStore;
  FDbPath    := pDbPath;
  FSccs      := pSccs;
  FGraph     := pGraph;
  FOut       := pOut;
  FFiles     := TDictionary<Int64, TPlanFile>.Create;
  FPaths     := TDictionary<Int64, string>.Create;
  FStemFid   := TDictionary<string, Int64>.Create;
  FUsersOf   := TObjectDictionary<string, TList<Int64>>.Create([doOwnsValues]);
  FCands     := TDictionary<string, TArray<TCandidate>>.Create;
  FSyms      := TDictionary<Int64, TSymbol>.Create;
  FNeeds     := TDictionary<Int64, TArray<TNeed>>.Create;
  FMembers   := TDictionary<string, Boolean>.Create;
  FItems     := TDictionary<Int64, TMoveItem>.Create;
  FOrder     := TList<Int64>.Create;
  FManual    := TList<TMoveItem>.Create;
  FDeleted   := TDictionary<string, Boolean>.Create;
  FReplaced  := TDictionary<string, string>.Create;
  FExtraEdits:= TObjectDictionary<Int64, TList<TFileEdit>>.Create([doOwnsValues]);
  FLeafName  := TDictionary<string, string>.Create;
  FLeafPath  := TDictionary<string, string>.Create;
  FLeafInfo  := TDictionary<string, TUntangleLeaf>.Create;
  FLeafDeps  := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FConsumers := TObjectDictionary<Int64, TList<TConsumer>>.Create([doOwnsValues]);
  FPulledBy  := TDictionary<Int64, string>.Create;
  FDecisions := TList<TUsesDecision>.Create;
  FUsesAdd   := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FUsesDel   := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FDprojEdits:= TList<TFileEdit>.Create;
  FTouched   := TList<Int64>.Create;
  FPredicted := TList<TPredGroup>.Create;
  IndexAllFiles;
end;

destructor TCyclePlanner.Destroy;
begin
  FPredicted.Free;
  FTouched.Free;
  FDprojEdits.Free;
  FUsesDel.Free;
  FUsesAdd.Free;
  FDecisions.Free;
  FPulledBy.Free;
  FConsumers.Free;
  FLeafDeps.Free;
  FLeafInfo.Free;
  FLeafPath.Free;
  FLeafName.Free;
  FExtraEdits.Free;
  FReplaced.Free;
  FDeleted.Free;
  FManual.Free;
  FOrder.Free;
  FItems.Free;
  FMembers.Free;
  FNeeds.Free;
  FSyms.Free;
  FCands.Free;
  FUsersOf.Free;
  FStemFid.Free;
  FPaths.Free;
  FFiles.Free;
  FAccess.Free;
  inherited Destroy;
end;

procedure TCyclePlanner.IndexAllFiles;
var
  Users: TList<Int64>;
begin
  for var Fid in FStore.GetAllFileIds do
  begin
    var Path:= PathOf(Fid);
    var Ext := LowerCase(ExtractFileExt(Path));
    if not MatchText(Ext, ['.pas', '.dpr', '.dpk']) then Continue;
    FStemFid.AddOrSetValue(StemOfPath(Path), Fid);
    if SameText(Ext, '.dpr') and (FProjectFid = 0) then FProjectFid:= Fid;
    for var U in FStore.GetUnitUsesForFile(Fid) do
    begin
      if not FUsersOf.TryGetValue(LowerCase(U.UnitName), Users) then
      begin
        Users:= TList<Int64>.Create;
        FUsersOf.Add(LowerCase(U.UnitName), Users);
      end;
      if not Users.Contains(Fid) then Users.Add(Fid);
    end;
  end;
  if FProjectFid = 0 then Exit;
  FProjectFile:= ChangeFileExt(PathOf(FProjectFid), '.dproj');
  if not TFile.Exists(FProjectFile) then FProjectFile:= PathOf(FProjectFid);
end;

function TCyclePlanner.PathOf(pFid: Int64): string;
begin
  if FPaths.TryGetValue(pFid, Result) then Exit;
  Result:= FStore.GetFilePath(pFid);
  FPaths.Add(pFid, Result);
end;

function TCyclePlanner.StemOfFid(pFid: Int64): string;
begin
  Result:= StemOfPath(PathOf(pFid));
end;

function TCyclePlanner.FidOfStem(const pStem: string): Int64;
begin
  if not FStemFid.TryGetValue(pStem, Result) then Result:= 0;
end;

function TCyclePlanner.UnitNameOfStem(const pStem: string): string;
var
  Fid: Int64;
begin
  Fid:= FidOfStem(pStem);
  if Fid > 0 then Result:= UnitNameOfPath(PathOf(Fid))
  else Result:= pStem;
end;

function TCyclePlanner.GetFile(pFid: Int64): TPlanFile;
begin
  if FFiles.TryGetValue(pFid, Result) then Exit;
  Result:= Default(TPlanFile);
  Result.Fid      := pFid;
  Result.Path     := PathOf(pFid);
  Result.UnitName := UnitNameOfPath(Result.Path);
  Result.Stem     := LowerCase(Result.UnitName);
  Result.IsProgram:= MatchText(ExtractFileExt(Result.Path), ['.dpr', '.dpk']);
  if TFile.Exists(Result.Path) then Result.Lines:= ReadSourceLines(Result.Path);
  Result.IntfLine:= FindKeywordLine(Result.Lines, 'interface');
  Result.ImplLine:= FindKeywordLine(Result.Lines, 'implementation');
  Result.Syms    := FStore.FindSymbolsByFile(Result.Path);
  Result.Refs    := FStore.GetReferencesFromFile(pFid);
  Result.UsesList:= FStore.GetUnitUsesForFile(pFid);
  FFiles.Add(pFid, Result);
end;

function TCyclePlanner.GetSym(pId: Int64): TSymbol;
begin
  if FSyms.TryGetValue(pId, Result) then Exit;
  Result:= FStore.GetSymbolById(pId);
  FSyms.Add(pId, Result);
end;

function TCyclePlanner.OwnerOf(const pSym: TSymbol; out pOwner: TSymbol): Boolean;
begin
  pOwner:= pSym;
  if pSym.Kind in [skLocalVar, skParam, skUnit, skProgram, skPackage] then Exit(False);
  if pSym.Kind = skEnumValue then
  begin
    if pSym.ParentId <= 0 then Exit(False);
    pOwner:= GetSym(pSym.ParentId);
  end;
  Result:= (pOwner.ParentId > 0) and (GetSym(pOwner.ParentId).Kind in [skUnit, skProgram, skPackage]);
end;

function TCyclePlanner.CandidatesFor(const pName: string): TArray<TCandidate>;
var
  L: TList<TCandidate>;
  C: TCandidate;
begin
  if FCands.TryGetValue(LowerCase(pName), Result) then Exit;
  C:= Default(TCandidate);
  L:= TList<TCandidate>.Create;
  try
    for var S in FStore.FindSymbolsByExactName(pName) do
    begin
      if not OwnerOf(S, C.Owner) then Continue;
      C.Actual:= S;
      C.Stem  := StemOfFid(C.Owner.FileId);
      L.Add(C);
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
  FCands.Add(LowerCase(pName), Result);
end;

function TCyclePlanner.VisibleStems(const pF: TPlanFile; pSect: TSect): TArray<string>;
var
  L   : TList<string>;
  Take: Boolean;
begin
  L:= TList<string>.Create;
  try
    for var U in pF.UsesList do
    begin
      case U.Section of
        uusInterface     : Take:= pSect in [scIntf, scImpl];
        uusImplementation: Take:= pSect = scImpl;
      else
        Take:= pSect = scProg;
      end;
      if Take then L.Add(LowerCase(U.UnitName));
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TCyclePlanner.PickCandidate(const pF: TPlanFile; pSect: TSect; const pCands: TArray<TCandidate>): Integer;
var
  Vis    : TArray<string>;
  BestPos: Integer;
begin
  for var I:= 0 to High(pCands) do
    if pCands[I].Owner.FileId = pF.Fid then Exit(I);   { own declaration wins }
  Result := CNotFound;
  BestPos:= CNotFound;
  Vis    := VisibleStems(pF, pSect);
  for var I:= 0 to High(pCands) do
  begin
    if SameText(pCands[I].Owner.Section, 'implementation') then Continue;
    for var P:= 0 to High(Vis) do
      if (Vis[P] = pCands[I].Stem) and (P > BestPos) then
      begin
        BestPos:= P;   { Delphi: the LAST unit in the uses list wins }
        Result := I;
      end;
  end;
end;

function TCyclePlanner.IsLocalName(const pR: TReference): Boolean;
var
  Local: TSymbol;
begin
  if pR.EnclosingSymbolId <= 0 then Exit(False);
  Local:= FStore.FindChildSymbolByName(pR.EnclosingSymbolId, pR.NameText);
  Result:= (Local.Id > 0) and (Local.Kind in [skLocalVar, skParam]);
end;

function TCyclePlanner.Resolve(const pF: TPlanFile; const pR: TReference; out pNeed: TNeed): Boolean;
var
  Cands: TArray<TCandidate>;
  Best : Integer;
begin
  pNeed:= Default(TNeed);
  if (pR.ReceiverText <> '') or SameText(pR.Kind, 'member-access') then Exit(False);
  Cands:= CandidatesFor(pR.NameText);
  if Length(Cands) = 0 then Exit(False);
  Best:= PickCandidate(pF, SectOf(pF, pR.StartLine), Cands);
  if (Best = CNotFound) or IsLocalName(pR) or
    IsClassChainMember(FStore, FLibStore, pR.EnclosingSymbolId, pR.NameText) then Exit(False);
  pNeed.Owner    := Cands[Best].Owner;
  pNeed.OwnerStem:= Cands[Best].Stem;
  pNeed.Sect     := SectOf(pF, pR.StartLine);
  pNeed.Line     := pR.StartLine;
  pNeed.RefName  := pR.NameText;
  pNeed.RefKind  := Cands[Best].Actual.Kind;
  Result:= True;
end;

function TCyclePlanner.NeedsOf(pFid: Int64): TArray<TNeed>;
var
  F: TPlanFile;
  L: TList<TNeed>;
  N: TNeed;
begin
  if FNeeds.TryGetValue(pFid, Result) then Exit;
  F:= GetFile(pFid);
  L:= TList<TNeed>.Create;
  try
    for var R in F.Refs do
      if Resolve(F, R, N) then L.Add(N);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
  FNeeds.Add(pFid, Result);
end;

{ ---------------------------------------------------------------------------
  closure: which declarations move, and how
  --------------------------------------------------------------------------- }

procedure TCyclePlanner.ResetCycle(const pComp: TArray<string>);
begin
  FComp:= pComp;
  FMembers.Clear;
  for var S in pComp do FMembers.AddOrSetValue(S, True);
  FItems.Clear;
  FOrder.Clear;
  FManual.Clear;
  FDeleted.Clear;
  FReplaced.Clear;
  FExtraEdits.Clear;
  FLeafName.Clear;
  FLeafPath.Clear;
  FLeafInfo.Clear;
  FLeafDeps.Clear;
  FConsumers.Clear;
  FPulledBy.Clear;
  FDecisions.Clear;
  FUsesAdd.Clear;
  FUsesDel.Clear;
  FDprojEdits.Clear;
  FTouched.Clear;
  FPredicted.Clear;
  FCutEdge  := Default(TEdgeEval);
  FInversion:= Default(TRecipeSteps);
  FPartBBest:= Default(TEdgeEval);
  FPartBDone:= False;
end;

function TCyclePlanner.BodyRanges(const pSym: TSymbol): TArray<TLineRange>;
var
  L: TList<TLineRange>;
begin
  L:= TList<TLineRange>.Create;
  try
    for var C in FStore.FindAllChildSymbols(pSym.Id) do
      if (C.ImplStartLine > 0) and (C.ImplEndLine >= C.ImplStartLine) then L.Add(OneRange(C.ImplStartLine, C.ImplEndLine));
    L.Sort(TComparer<TLineRange>.Construct(
      function(const pLeft, pRight: TLineRange): Integer
      begin
        Result:= pLeft.First - pRight.First;
      end));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TCyclePlanner.IsDeclOnly(const pSym: TSymbol): Boolean;
begin
  if pSym.Kind in [skEnum, skTypeAlias, skInterface, skConstDecl] then Exit(True);
  Result:= (pSym.Kind in [skRecord, skClass]) and (Length(BodyRanges(pSym)) = 0);
end;

function TCyclePlanner.NeedsInRanges(const pF: TPlanFile; const pRanges: TArray<TLineRange>): TArray<TNeed>;
var
  L: TList<TNeed>;
begin
  L:= TList<TNeed>.Create;
  try
    for var N in NeedsOf(pF.Fid) do
      if InRanges(N.Line, pRanges) then L.Add(N);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TCyclePlanner.MovedRanges(const pItem: TMoveItem): TArray<TLineRange>;
begin
  if pItem.Kind = mvBase then
  begin
    SetLength(Result, Length(pItem.BaseMembers));
    for var I:= 0 to High(pItem.BaseMembers) do Result[I]:= pItem.BaseMembers[I].Range;
  end
  else if pItem.Kind = mvWithBodies then Result:= WithRange(pItem.Decl, pItem.Bodies)
  else Result:= WithRange(pItem.Decl, nil);
end;

procedure TCyclePlanner.SetHeader(const pF: TPlanFile; var pItem: TMoveItem);
begin
  var KW:= SameLineKeyword(LineAt(pF.Lines, pItem.Sym.StartLine), pItem.Sym.Name, pItem.Sym.StartLine = pItem.Sym.EndLine);
  if KW <> '' then
  begin
    { W6 C6: `var GX: T;` -- the keyword stays on the line, the declaration moves }
    pItem.Header  := pItem.Sym.StartLine;
    pItem.Keyword := KW;
    pItem.SameLine:= True;
    Exit;
  end;
  pItem.Header:= HeaderOf(pF.Lines, pItem.Decl.First);
  if pItem.Header = 0 then
  begin
    pItem.Kind  := mvBlocked;
    pItem.Reason:= Format('the declaration block around line %d was not recognised (expected a ' +
      '`type` / `var` / `const` line at column 1 above it)', [pItem.Decl.First]);
    Exit;
  end;
  pItem.Keyword:= LowerCase(Trim(CodePart(LineAt(pF.Lines, pItem.Header))));
end;

function TCyclePlanner.Classify(const pSym: TSymbol; const pCut: TArray<Int64>): TMoveItem;
var
  F: TPlanFile;
begin
  Result:= Default(TMoveItem);
  Result.Sym    := pSym;
  Result.Stem   := StemOfFid(pSym.FileId);
  Result.CutFids:= pCut;
  F:= GetFile(pSym.FileId);
  Result.Decl:= OneRange(DocStart(F.Lines, pSym.StartLine), pSym.EndLine);
  case pSym.Kind of
    skEnum, skTypeAlias, skInterface, skConstDecl, skVarDecl: Result.Kind:= mvDecl;
    skRecord, skClass: ClassifyStructured(F, Result);
    skProcedure, skFunction:
      begin
        Result.Kind  := mvBlocked;
        Result.Reason:= 'it is a routine: its body would have to move together with everything it ' +
          'uses, or be handed over as a parameter / event instead of being called by name';
      end;
  else
    Result.Kind  := mvBlocked;
    Result.Reason:= Format('a %s cannot be moved mechanically', [pSym.Kind.ToText]);
  end;
  if Result.Kind in [mvDecl, mvWithBodies] then SetHeader(F, Result);
end;

procedure TCyclePlanner.ClassifyStructured(const pF: TPlanFile; var pItem: TMoveItem);
var
  Drags: TList<string>;
begin
  pItem.Bodies:= BodyRanges(pItem.Sym);
  if Length(pItem.Bodies) = 0 then
  begin
    pItem.Kind:= mvDecl;
    Exit;
  end;
  Drags:= TList<string>.Create;
  try
    { a body DRAGS a symbol of the cycle that is not a plain declaration --
      a global variable, a routine, a class with code -- because moving the
      body would mean moving that too }
    for var N in NeedsInRanges(pF, WithRange(pItem.Decl, pItem.Bodies)) do
    begin
      if (N.Owner.Id = pItem.Sym.Id) or not FMembers.ContainsKey(N.OwnerStem) then Continue;
      if IsMovedFor(N.Owner, 0) or IsDeclOnly(N.Owner) then Continue;
      AddUnique(Drags, N.Owner.Name);
    end;
    pItem.Drags:= Drags.ToArray;
  finally
    Drags.Free;
  end;
  if Length(pItem.Drags) = 0 then pItem.Kind:= mvWithBodies
  else if (pItem.Sym.Kind = skClass) and (Length(pItem.CutFids) > 0) then BuildBase(pF, pItem)
  else
  begin
    pItem.Kind  := mvBlocked;
    pItem.Reason:= Format('its method bodies use %s, which live in units of this cycle -- they ' +
      'would have to move with it', [QuoteList(pItem.Drags)]);
  end;
end;

{ The F5 base-class plan of a class: `TX = class` or, since B4-d, `TX = class(TAnc[, I1, ...])`
  with TAnc declared outside the cycle -- the leaf gets `TXBase = class(TAnc)`, the class becomes
  `TX = class(TXBase[, I1, ...])` (the interfaces stay on TX: their methods are implemented there). }
procedure TCyclePlanner.BuildBase(const pF: TPlanFile; var pItem: TMoveItem);
const
  CHeritageGroup = 3;  // the header regex's group for the text inside `class(...)`; 1 = indent, 2 = the parentheses
var
  M       : TMatch;
  Children: TArray<TSymbol>;
  Used    : TDictionary<string, Boolean>;
  Comment : string;
  Rest    : string;
  Site    : string;

  procedure RefuseSite(const pSite: string);
  begin
    pItem.Refusal:= 'base-class';
    pItem.Reason := 'refused: base-class -- ' + pSite;
  end;

begin
  pItem.Kind:= mvBlocked;
  if pItem.Sym.IsHelper or (pItem.Sym.GenericParams <> '') then
  begin
    pItem.Reason:= 'it is generic or is a helper, so a base class cannot be slotted in mechanically';
    Exit;
  end;
  var Line:= LineAt(pF.Lines, pItem.Sym.StartLine);
  var Code:= CodePart(Line);
  M:= TRegEx.Match(Code, '^(\s*)' + pItem.Sym.Name + '\s*=\s*class\s*(\(([^()]*)\))?\s*$', [roIgnoreCase]);
  if not M.Success then
  begin
    pItem.Reason:= Format('its header (line %d) is not a plain `%s = class` or `%s = class(...)` line ' +
      '(the heritage must close on it)', [pItem.Sym.StartLine, pItem.Sym.Name, pItem.Sym.Name]);
    Exit;
  end;
  pItem.BaseName  := pItem.Sym.Name + CBaseSuffix;
  pItem.BaseIndent:= M.Groups[1].Value;
  Comment:= Trim(Copy(Line, Length(Code) + 1, MaxInt));
  { B4-d: the direct ancestor goes to the base class; the interfaces stay on the class }
  Rest:= '';
  { an unmatched optional group is not in Groups (Count stops at the last group that took part) }
  if (M.Groups.Count > CHeritageGroup) and (Trim(M.Groups[CHeritageGroup].Value) <> '') then
  begin
    var Parts:= SplitHeritage(M.Groups[CHeritageGroup].Value);
    Site:= AncestorRefusal(pF, pItem, Parts[0]);
    if Site <> '' then
    begin
      RefuseSite(Site);
      Exit;
    end;
    pItem.BaseAncestor:= Parts[0];
    for var I:= 1 to High(Parts) do Rest:= Rest + ', ' + Parts[I];
  end;
  pItem.HeaderNew:= pItem.BaseIndent + pItem.Sym.Name + ' = class(' + pItem.BaseName + Rest + ')' +
    (if Comment <> '' then ' ' + Comment else '');
  Children:= FStore.FindAllChildSymbols(pItem.Sym.Id);
  Used:= UsedMemberNames(Children, pItem.CutFids, pItem.Sym.Name);
  try
    if not PullMembers(pF, pItem, Children, Used) then Exit;
  finally
    Used.Free;
  end;
  if not BuildSwitches(pItem) then Exit;
  { E18 T7 F5: the base class stands in for the class only where nothing but a
    member read or a nil test happens to it }
  Site:= BaseSiteRefusal(pItem);
  { B4-d: a form / data module keeps its streamed members; the RTTI parent must not be observed }
  if Site = '' then Site:= StreamedMemberRefusal(pF, pItem);
  if Site = '' then Site:= ClassParentRefusal(pItem);
  if Site <> '' then
  begin
    RefuseSite(Site);
    Exit;
  end;
  pItem.Kind:= mvBase;
end;

{ B4-d: '' when the ancestor pAnc of the class is declared outside the cycle -- in a project unit
  that is no member of the group, or (no project row) in the platform library; else the site. }
function TCyclePlanner.AncestorRefusal(const pF: TPlanFile; const pItem: TMoveItem; const pAnc: string): string;
var
  Owner: TSymbol;
  Stem : string;
begin
  var Site:= Format('`%s:%d`', [ExtractFileName(pF.Path), pItem.Sym.StartLine]);
  var Bare:= pAnc.Substring(pAnc.LastIndexOf('.') + 1);
  if BindName(pF.Fid, pItem.Sym.StartLine, Bare, Owner, Stem) then
  begin
    if FMembers.ContainsKey(Stem) then
      Exit(Format('%s: its ancestor `%s` is declared in `%s`, a unit of this cycle -- a base class inheriting ' +
        'it would carry the cycle into the leaf', [Site, pAnc, ExtractFileName(PathOf(Owner.FileId))]));
    Exit('');
  end;
  if FLibStore <> nil then
    for var S in FLibStore.FindSymbolsByExactName(Bare) do
      if S.Kind = skClass then Exit('');
  Result:= Format('%s: its ancestor `%s` is declared in no index given (the project index has no row for it%s), ' +
    'so the leaf that would inherit it cannot be checked', [Site, pAnc,
    (if FLibStore = nil then ' and no platform library was read: pass --library-db' else ', nor has the platform library')]);
end;

{ B4-d: a unit with a form resource keeps every published (or unlabelled-section) member in the
  form class -- the designer re-creates component fields there, which would shadow the base's
  field, and streaming would fill the wrong one. '' when nothing streamed is pulled. }
function TCyclePlanner.StreamedMemberRefusal(const pF: TPlanFile; const pItem: TMoveItem): string;
begin
  Result:= '';
  var HasRes:= False;
  for var L in pF.Lines do
    if TRegEx.IsMatch(L, '\{\$R\s+\*\.(dfm|fmx)\}', [roIgnoreCase]) then HasRes:= True;
  if not HasRes then Exit;
  for var B in pItem.BaseMembers do
    if SameText(Trim(B.Sym.Modifiers), 'published') or not B.Sym.VisExplicit then
      Exit(Format('`%s:%d`: `%s.%s` is published (or in the unlabelled section) of a unit with a form resource ' +
        '(`{$R *.dfm}` / `{$R *.fmx}`): the designer re-creates published fields in the form class, which would ' +
        'shadow the base''s copy, and streaming would fill the wrong one', [ExtractFileName(pF.Path),
        B.Sym.StartLine, pItem.Sym.Name, B.Sym.Name]));
end;

{ B4-d: `ClassParent` named in the class's unit or in a unit that uses it -- `TX.ClassParent`
  would turn into `TXBase`, an observable change. '' when nothing names it. }
function TCyclePlanner.ClassParentRefusal(const pItem: TMoveItem): string;
var
  Fids : TList<Int64>;
  Users: TList<Int64>;
begin
  Result:= '';
  Fids:= TList<Int64>.Create;
  try
    Fids.Add(pItem.Sym.FileId);
    if FUsersOf.TryGetValue(pItem.Stem, Users) then
      for var Fid in Users do
        if not Fids.Contains(Fid) then Fids.Add(Fid);
    for var Fid in Fids do
    begin
      var F:= GetFile(Fid);
      for var I:= 0 to High(F.Lines) do
        if TRegEx.IsMatch(CodePart(F.Lines[I]), '\bClassParent\b', [roIgnoreCase]) then
          Exit(Format('`%s:%d`: `ClassParent` is named here; `%s.ClassParent` would turn from `%s` into `%s`, ' +
            'an observable change', [ExtractFileName(F.Path), I + 1, pItem.Sym.Name,
            (if pItem.BaseAncestor <> '' then pItem.BaseAncestor else 'TObject'), pItem.BaseName]));
    end;
  finally
    Fids.Free;
  end;
end;

function TCyclePlanner.UsedMemberNames(const pChildren: TArray<TSymbol>; const pCut: TArray<Int64>; const pClassName: string): TDictionary<string, Boolean>;
var
  Ids  : TDictionary<Int64, Boolean>;
  Names: TDictionary<string, Boolean>;
begin
  Result:= TDictionary<string, Boolean>.Create;
  Ids   := TDictionary<Int64, Boolean>.Create;
  Names := TDictionary<string, Boolean>.Create;
  try
    for var C in pChildren do
    begin
      if C.Kind in [skConstructor, skDestructor] then Continue;
      Ids.AddOrSetValue(C.Id, True);
      Names.AddOrSetValue(LowerCase(C.Name), True);
    end;
    for var Fid in pCut do
      for var R in GetFile(Fid).Refs do
      begin
        if (R.ReceiverText = '') and not SameText(R.Kind, 'member-access') then Continue;
        if (R.SymbolId > 0) and not Ids.ContainsKey(R.SymbolId) then Continue;
        if Names.ContainsKey(LowerCase(R.NameText)) then Result.AddOrSetValue(LowerCase(R.NameText), True);
      end;
    { B4-f: `(X as TX).M` -- the index records no member access after a parenthesised cast }
    if pClassName <> '' then
      for var Fid in pCut do
        for var Line in GetFile(Fid).Lines do
          for var M in TRegEx.Matches(CodePart(Line), '\(\s*[A-Za-z_][\w.]*\s+as\s+' + pClassName + '\s*\)\s*\.\s*([A-Za-z_]\w*)', [roIgnoreCase]) do
            if Names.ContainsKey(LowerCase(M.Groups[1].Value)) then Result.AddOrSetValue(LowerCase(M.Groups[1].Value), True);
  finally
    Names.Free;
    Ids.Free;
  end;
end;

function TCyclePlanner.PullMembers(const pF: TPlanFile; var pItem: TMoveItem;
  const pChildren: TArray<TSymbol>; pUsed: TDictionary<string, Boolean>): Boolean;
var
  L     : TList<TBaseMember>;
  Pulled: TDictionary<Int64, Boolean>;
  Why   : string;

  procedure Pull(const pSym: TSymbol);
  var
    B: TBaseMember;
  begin
    if Pulled.ContainsKey(pSym.Id) then Exit;
    Pulled.Add(pSym.Id, True);
    B.Sym  := pSym;
    B.Range:= OneRange(DocStart(pF.Lines, pSym.StartLine), pSym.EndLine);
    L.Add(B);
  end;

  function FieldNamed(const pName: string; out pField: TSymbol): Boolean;
  begin
    for var C in pChildren do
      if SameText(C.Name, pName) then
      begin
        pField:= C;
        Exit(C.Kind = skField);
      end;
    pField:= Default(TSymbol);
    Result:= False;
  end;

  function PullAccessors(const pProp: TSymbol): Boolean;
  var
    Fld: TSymbol;
  begin
    var Text:= string.Join(' ', SliceLines(pF.Lines, OneRange(pProp.StartLine, pProp.EndLine)));
    for var M in TRegEx.Matches(CodePart(Text), '\b(read|write)\s+([A-Za-z_]\w*)', [roIgnoreCase]) do
    begin
      if not FieldNamed(M.Groups[2].Value, Fld) and (Fld.Kind in [skMethod, skFunction, skProcedure]) then
      begin
        { B4-e: a method accessor is pulled too -- the base class declares it `virtual; abstract;` and the
          class overrides it, so its body, and every member that body names, stays in the class }
        if Fld.Directives <> '' then
        begin
          Why:= Format('property `%s` is read or written through method `%s`, which already carries directives (%s)',
            [pProp.Name, Fld.Name, Fld.Directives]);
          Exit(False);
        end;
        Pull(Fld);
        Continue;
      end;
      if Fld.Kind <> skField then
      begin
        Why:= Format('property `%s` is read or written through `%s`, which is not a field',
          [pProp.Name, M.Groups[2].Value]);
        Exit(False);
      end;
      Pull(Fld);
    end;
    Result:= True;
  end;

begin
  Result:= False;
  Why   := '';
  L     := TList<TBaseMember>.Create;
  Pulled:= TDictionary<Int64, Boolean>.Create;
  try
    for var C in pChildren do
    begin
      if not pUsed.ContainsKey(LowerCase(C.Name)) then Continue;
      if (C.Kind = skProperty) and not PullAccessors(C) then Break;
      if (C.Kind in [skMethod, skFunction, skProcedure]) and (C.Directives <> '') then
      begin
        Why:= Format('method `%s` already carries directives (%s)', [C.Name, C.Directives]);
        Break;
      end;
      if C.Kind in [skField, skProperty, skMethod, skFunction, skProcedure] then Pull(C);
    end;
    if Why <> '' then
    begin
      pItem.Reason:= Why;
      Exit;
    end;
    L.Sort(TComparer<TBaseMember>.Construct(
      function(const pLeft, pRight: TBaseMember): Integer
      begin
        Result:= pLeft.Range.First - pRight.Range.First;
      end));
    pItem.BaseMembers:= L.ToArray;
    Result:= True;
  finally
    Pulled.Free;
    L.Free;
  end;
end;

function TCyclePlanner.BuildSwitches(var pItem: TMoveItem): Boolean;
var
  L : TList<TSwitchLine>;
  SL: TSwitchLine;
begin
  Result:= False;
  L:= TList<TSwitchLine>.Create;
  try
    for var Fid in pItem.CutFids do
    begin
      var F:= GetFile(Fid);
      for var I:= 1 to Length(F.Lines) do
      begin
        var Line:= F.Lines[I - 1];
        if IsCommentOnly(Line) then Continue;
        var Code:= CodePart(Line);
        if not TRegEx.IsMatch(Code, '\b' + pItem.Sym.Name + '\b', [roIgnoreCase]) then Continue;
        if TRegEx.IsMatch(Code, '\b' + pItem.Sym.Name + '\s*\.', [roIgnoreCase]) then
        begin
          pItem.Reason:= Format('`%s` line %d uses `%s.` (the class itself, not an instance)',
            [ExtractFileName(F.Path), I, pItem.Sym.Name]);
          Exit;
        end;
        SL.Fid    := Fid;
        SL.Line   := I;
        SL.NewText:= TRegEx.Replace(Code, '\b' + pItem.Sym.Name + '\b', pItem.BaseName, [roIgnoreCase]) +
          Copy(Line, Length(Code) + 1, MaxInt);
        L.Add(SL);
      end;
    end;
    pItem.Switches:= L.ToArray;
    Result:= True;
  finally
    L.Free;
  end;
end;

{ B4: the routine whose implementation (header to `end`) holds line pLine of pF, else the routine whose
  declaration holds it (a parameter in a class or interface section); Id 0 for none. }
function RoutineAt(const pF: TPlanFile; pLine: Integer): TSymbol;
begin
  Result:= Default(TSymbol);
  for var S in pF.Syms do
    if (S.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor]) and
      (S.ImplStartLine > 0) and (S.ImplStartLine <= pLine) and (pLine <= S.ImplEndLine) and
      (S.ImplStartLine > Result.ImplStartLine) then Result:= S;
  if Result.Id = 0 then
    for var S in pF.Syms do
      if (S.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor]) and
        (S.StartLine <= pLine) and (pLine <= S.EndLine) then Result:= S;
end;

{ B4: the names of the slots visible in routine pRoutineId -- the fields and that routine's
  locals and parameters; pRoutineId -1 = every slot. }
function SlotNames(const pSlots: TArray<TObjSlot>; pRoutineId: Int64): TArray<string>;
begin
  Result:= nil;
  for var S in pSlots do
    if (pRoutineId = -1) or S.IsField or (S.RoutineId = pRoutineId) then Result:= Result + [S.Name];
end;

{ B4-c: the occurrence (pIndex, pLen) in pCode is the whole last argument of Add / Insert / Remove /
  IndexOf / Contains called on one of the fields pFields (a list that switches): `F.Add(p)`,
  `F.Insert(i, p)`. }
function IsListArg(const pCode: string; pIndex, pLen: Integer; const pFields: TArray<string>): Boolean;
begin
  Result:= (Length(pFields) > 0) and TRegEx.IsMatch(Copy(pCode, 1, pIndex - 1), '\b(Self\s*\.\s*)?(' +
    string.Join('|', pFields) + ')\s*\.\s*(Add|Insert|Remove|IndexOf|Contains)\s*\(([^()]*,)?\s*$', [roIgnoreCase]) and
    TRegEx.IsMatch(Copy(pCode, pIndex + pLen, MaxInt), '^\s*\)');
end;
{ B4: one occurrence (pIndex, pLen) of a slot's name in pCode that survives the switch of the
  slot's type to the base class, the names in pSlots / pArrays switching too: a receiver or a nil
  test; `Assigned(X)` / `FreeAndNil(X)`; `X := nil | S | A[..]`; `S := X` / `A[..] := X` as a whole
  statement; `for [var] X [: T] in A do`; the argument of `A.Add(X)` and its kin (IsListArg) -- S a slot,
  A a switching array or list field. }
function IsSlotUse(const pCode: string; pIndex, pLen: Integer; const pSlots, pArrays: TArray<string>): Boolean;
begin
  if IsReceiverOrNilTest(pCode, pIndex, pLen) or IsListArg(pCode, pIndex, pLen, pArrays) then Exit(True);
  var Before:= Copy(pCode, 1, pIndex - 1);
  var Rest  := Copy(pCode, pIndex + pLen, MaxInt);
  var SlotRx := if Length(pSlots) > 0 then '(' + string.Join('|', pSlots) + ')' else '(?!)';
  var ArrayRx:= if Length(pArrays) > 0 then '(' + string.Join('|', pArrays) + ')' else '(?!)';
  var StmtEnd:= '\s*(;|$|end\b|else\b)';
  if TRegEx.IsMatch(Before, '\b(Assigned|FreeAndNil)\s*\(\s*$', [roIgnoreCase]) and TRegEx.IsMatch(Rest, '^\s*\)') then
    Exit(True);
  if TRegEx.IsMatch(Before, '(^|[;\s])(Self\s*\.\s*)?$', [roIgnoreCase]) and
    TRegEx.IsMatch(Rest, '^\s*:=\s*(nil|(Self\s*\.\s*)?' + SlotRx + '|(Self\s*\.\s*)?' + ArrayRx + '\s*\[[^;]*\])' + StmtEnd,
    [roIgnoreCase]) then Exit(True);
  if TRegEx.IsMatch(Before, '(^|[;\s])(Self\s*\.\s*)?(' + SlotRx + '|' + ArrayRx + '\s*\[[^;]*\])\s*:=\s*$', [roIgnoreCase]) and
    TRegEx.IsMatch(Rest, '^' + StmtEnd, [roIgnoreCase]) then Exit(True);
  Result:= TRegEx.IsMatch(Before, '\bfor\s+(var\s+)?$', [roIgnoreCase]) and
    TRegEx.IsMatch(Rest, '^\s*(:\s*[\w.<>]+\s*)?in\s+(Self\s*\.\s*)?' + ArrayRx + '\s+do\b', [roIgnoreCase]);
end;

{ B4-c: pCode is `F := TList<TX>.Create...` (TObjectList too) with F one of the list fields pFields that
  switch (its uses, this one included, are judged by IsListFieldUse). }
function IsListCreation(const pCode, pTypeName: string; const pFields: TArray<string>): Boolean;
begin
  Result:= (Length(pFields) > 0) and TRegEx.IsMatch(pCode, '^\s*(Self\s*\.\s*)?(' + string.Join('|', pFields) +
    ')\s*:=\s*T(Object)?List\s*<\s*' + pTypeName + '\s*>\s*\.\s*Create\b', [roIgnoreCase]);
end;
{ B4-f: a class test the base class answers the same: `X is TX` (only TX derives from the new TXBase, so
  `is TXBase` holds exactly when `is TX` did), and `(X as TX).M` with M a member pulled into the base,
  read or called, never assigned (`(X as TX).M :=`). }
function TCyclePlanner.ClassTestSiteOk(const pCode: string; pIndex, pLen: Integer; const pItem: TMoveItem): Boolean;
begin
  var Before:= Copy(pCode, 1, pIndex - 1);
  var Rest  := Copy(pCode, pIndex + pLen, MaxInt);
  if TRegEx.IsMatch(Before, '[\w)\]]\s+is\s+$', [roIgnoreCase]) then Exit(True);
  if not TRegEx.IsMatch(Before, '\(\s*[A-Za-z_][\w.]*\s+as\s+$', [roIgnoreCase]) then Exit(False);
  var R:= TRegEx.Match(Rest, '^\s*\)\s*\.\s*([A-Za-z_]\w*)\b(?!\s*:=)', [roIgnoreCase]);
  if not R.Success then Exit(False);
  for var BM in pItem.BaseMembers do
    if SameText(BM.Sym.Name, R.Groups[1].Value) then Exit(True);
  Result:= False;
end;
{ E18 T7 F5: '' when every switched site of pItem is a const or value parameter
  whose routine body only reads members of it, compares it with nil or stores it
  into a switchable field (`F[..] := p`), or is such a field (FieldSiteRefusal);
  otherwise the first offending site, as "`<file>:<line>` <what>". }
function TCyclePlanner.BaseSiteRefusal(const pItem: TMoveItem): string;
var
  Param : string;
  Field : string;
  Fields: TArray<string>;
  Slots : TArray<TObjSlot>;
  Slot  : TObjSlot;
begin
  { D1: the array fields that switch; B4: the plain fields, locals and parameters -- all
    named first, so a store into one is judged against every slot whatever its order }
  Fields:= nil;
  Slots := nil;
  for var S in pItem.Switches do
  begin
    var F:= GetFile(S.Fid);
    FieldSiteRefusal(pItem, S.Fid, S.Line, Field);
    if Field <> '' then
    begin
      Fields:= Fields + [Field];
      Continue;
    end;
    for var M in TRegEx.Matches(CodePart(LineAt(F.Lines, S.Line)), '\b' + pItem.Sym.Name + '\b', [roIgnoreCase]) do
      case TypeSiteAt(F.Lines, S.Line, M.Index, Param) of
        tsOther: if ObjSlotAt(pItem, S.Fid, S.Line, M.Index, Slot) then Slots:= Slots + [Slot];
        tsParam:
          begin
            var Group:= Trim(TRegEx.Replace(Param, '^\[\s*ref\s*\]', '', [roIgnoreCase]));
            var Modifier:= LowerCase(Copy(Group, 1, Pos(' ', Group + ' ') - 1));
            if MatchText(Modifier, ['const', 'constref']) then Group:= Trim(Copy(Group, Length(Modifier) + 1, MaxInt));
            for var Name in Group.Split([',']) do
            begin
              Slot          := Default(TObjSlot);
              Slot.Name     := Trim(Name);
              Slot.Fid      := S.Fid;
              Slot.Line     := S.Line;
              Slot.RoutineId:= RoutineAt(F, S.Line).Id;
              Slots:= Slots + [Slot];
            end;
          end;
      end;
  end;
  for var S in pItem.Switches do
  begin
    var F   := GetFile(S.Fid);
    var Site:= Format('`%s:%d`', [ExtractFileName(F.Path), S.Line]);
    for var M in TRegEx.Matches(CodePart(LineAt(F.Lines, S.Line)), '\b' + pItem.Sym.Name + '\b', [roIgnoreCase]) do
    begin
      case TypeSiteAt(F.Lines, S.Line, M.Index, Param) of
        tsResult: Exit(Format('%s: a function result of type `%s`', [Site, pItem.Sym.Name]));
        tsOther :
          begin
            var Why:= FieldSiteRefusal(pItem, S.Fid, S.Line, Field, SlotNames(Slots, -1));
            if (Field = '') and ObjSlotAt(pItem, S.Fid, S.Line, M.Index, Slot) then Why:= ObjSlotRefusal(pItem, Slot, Fields, Slots)
            else if (Field = '') and IsListCreation(CodePart(LineAt(F.Lines, S.Line)), pItem.Sym.Name, Fields) then Continue
            else if (Field = '') and ClassTestSiteOk(CodePart(LineAt(F.Lines, S.Line)), M.Index, M.Length, pItem) then Continue
            else if Field = '' then
              Exit(Format('%s: `%s` is used here as something other than a parameter type (a field, ' +
                'variable, cast or type argument)', [Site, pItem.Sym.Name]));
            if Why <> '' then Exit(Why);
            Continue;
          end;
      end;
      var Group:= Trim(TRegEx.Replace(Param, '^\[\s*ref\s*\]', '', [roIgnoreCase]));
      var Modifier:= LowerCase(Copy(Group, 1, Pos(' ', Group + ' ') - 1));
      if MatchText(Modifier, ['var', 'out']) then
        Exit(Format('%s: `%s` is a `%s` parameter of type `%s`; a base class cannot stand in for it',
          [Site, Group, Modifier, pItem.Sym.Name]));
      if MatchText(Modifier, ['const', 'constref']) then Group:= Trim(Copy(Group, Length(Modifier) + 1, MaxInt));
      for var Name in Group.Split([',']) do
      begin
        var Why:= ParamBodyRefusal(S.Fid, S.Line, Trim(Name), Fields, SlotNames(Slots, RoutineAt(F, S.Line).Id));
        if Why <> '' then Exit(Format('%s: parameter `%s` -- %s', [Site, Trim(Name), Why]));
      end;
    end;
  end;
  Result:= '';
end;

{ B4: whether the switch site at (pLine, pCol) of pFid declares a plain field `F: TX;` (B4-b) or a
  local `L: TX` -- in a routine's `var` section, an inline `var L: TX`, or `for var L: TX in` (B4-a). }
function TCyclePlanner.ObjSlotAt(const pItem: TMoveItem; pFid: Int64; pLine, pCol: Integer; out pSlot: TObjSlot): Boolean;
begin
  pSlot:= Default(TObjSlot);
  var F   := GetFile(pFid);
  var Code:= CodePart(LineAt(F.Lines, pLine));
  var Head:= TRegEx.Match(Copy(Code, 1, pCol - 1), '(^|\bvar\s+|\bfor\s+var\s+)\s*([A-Za-z_]\w*)\s*:\s*$', [roIgnoreCase]);
  if not Head.Success or not TRegEx.IsMatch(Copy(Code, pCol + Length(pItem.Sym.Name), MaxInt), '^\s*(;|:=|in\b)',
    [roIgnoreCase]) then Exit(False);
  pSlot.Name:= Head.Groups[2].Value;
  pSlot.Fid := pFid;
  pSlot.Line:= pLine;
  var R:= RoutineAt(F, pLine);
  if R.Id > 0 then
  begin
    pSlot.RoutineId:= R.Id;
    Exit(True);
  end;
  for var S in F.Syms do
    if (S.Kind = skField) and (S.StartLine = pLine) and SameText(S.Name, pSlot.Name) then
    begin
      pSlot.IsField:= True;
      Exit(True);
    end;
  Result:= False;
end;

{ B4: '' when the slot pSlot switches -- a field is not published (nor unlabelled, $M+), has no
  ref outside its unit; every use of its name in its scope (the unit for a field, the routine
  body for a local) passes IsSlotUse; a member reached through it is read, or is `Free` called;
  otherwise the first offending site, as "`<file>:<line>`: <what>". }
function TCyclePlanner.ObjSlotRefusal(const pItem: TMoveItem; const pSlot: TObjSlot; const pFields: TArray<string>;
  const pSlots: TArray<TObjSlot>): string;
var
  MA     : TCallEdge;
  Fld    : TSymbol;
  BodyAt : Integer;
  BodyCol: Integer;
begin
  Result:= '';
  var F   := GetFile(pSlot.Fid);
  var What:= Format('%s `%s` (type `%s`) can switch to the base class only when it is read through, compared ' +
    'with nil, freed, or assigned to / from another slot that switches', [(if pSlot.IsField then 'field' else 'local'),
    pSlot.Name, pItem.Sym.Name]);
  var First:= 1;
  var Last := Length(F.Lines);
  if pSlot.IsField then
  begin
    Fld:= Default(TSymbol);
    for var S in F.Syms do
      if (S.Kind = skField) and (S.StartLine = pSlot.Line) and SameText(S.Name, pSlot.Name) then Fld:= S;
    if ContainsText(Fld.Modifiers, 'published') or not Fld.VisExplicit then
      Exit(Format('`%s:%d`: %s; it is published (or in an unlabelled section, published under {$M+}), so RTTI ' +
        'and streaming see its declared type', [ExtractFileName(F.Path), pSlot.Line, What]));
    for var R in FStore.FindReferencesTo(Fld.Id) do
      if R.FileId <> pSlot.Fid then
        Exit(Format('`%s:%d`: %s; it is referred to here, outside its unit', [ExtractFileName(PathOf(R.FileId)),
          R.StartLine, What]));
  end
  else
  begin
    var R:= Default(TSymbol);
    for var S in F.Syms do
      if S.Id = pSlot.RoutineId then R:= S;
    if not HeaderEnd(F.Lines, R.ImplStartLine, R.ImplEndLine, BodyAt, BodyCol) then
      Exit(Format('`%s:%d`: the header of `%s` could not be read', [ExtractFileName(F.Path), R.ImplStartLine, R.Name]));
    First:= BodyAt;
    Last := R.ImplEndLine;
  end;
  for var L:= First to Last do
  begin
    if L = pSlot.Line then Continue;
    var Code:= CodePart(LineAt(F.Lines, L));
    var Names:= SlotNames(pSlots, if pSlot.IsField then RoutineAt(F, L).Id else pSlot.RoutineId);
    for var U in TRegEx.Matches(Code, '\b' + pSlot.Name + '\b', [roIgnoreCase]) do
      if not IsSlotUse(Code, U.Index, U.Length, Names, pFields) then
        Exit(Format('`%s:%d`: %s', [ExtractFileName(F.Path), L, What]));
  end;
  for var R in F.Refs do
  begin
    if (R.StartLine < First) or (R.StartLine > Last) or not SameText(R.ReceiverText, pSlot.Name) then Continue;
    var IsRead:= SameText(R.Kind, 'member-access') and MemberAccessOf(R.Id, MA) and SameText(MA.MemberMode, 'read');
    if not IsRead and not SameText(R.NameText, 'Free') then
      Exit(Format('`%s:%d`: %s; `%s.%s` is not a read of a member', [ExtractFileName(F.Path), R.StartLine, What,
        pSlot.Name, R.NameText]));
  end;
end;

{ D1 (owner ruling 2026-10-25, option a+): one use of the field pName at pIndex in
  pCode that survives the switch of its element type to the base class:
  `SetLength(F, ..)`, `Length(F)` / `High(F)` / `Low(F)`, a store `F[..] := x`, or
  a read `F[..].M` of a member in pPulled (not followed by `:=`). The brackets
  must close on the same line. }
function IsSwitchableFieldUse(const pCode: string; pIndex, pLen: Integer; const pPulled: TArray<string>;
  const pSlots: TArray<string> = nil): Boolean;
var
  Depth: Integer;
  Close: Integer;
begin
  var Before:= Copy(pCode, 1, pIndex - 1);
  var Rest  := Copy(pCode, pIndex + pLen, MaxInt);
  var SetLen:= TRegEx.IsMatch(Before, '\bSetLength\s*\(\s*$', [roIgnoreCase]) and TRegEx.IsMatch(Rest, '^\s*,');
  if SetLen or (TRegEx.IsMatch(Before, '\b(Length|High|Low)\s*\(\s*$', [roIgnoreCase]) and TRegEx.IsMatch(Rest, '^\s*\)')) then
    Exit(True);
  { B4: `for [var] S in F do` with S a slot that switches }
  if (Length(pSlots) > 0) and TRegEx.IsMatch(Before, '\bfor\s+(var\s+)?(' + string.Join('|', pSlots) +
    ')\s*(:\s*[\w.<>]+\s*)?in\s+(Self\s*\.\s*)?$', [roIgnoreCase]) and TRegEx.IsMatch(Rest, '^\s+do\b', [roIgnoreCase]) then
    Exit(True);
  var Open:= TRegEx.Match(Rest, '^\s*\[');
  if not Open.Success then Exit(False);
  Depth:= 0;
  Close:= 0;
  for var I:= Open.Length to Length(Rest) do
  begin
    if Rest[I] = '[' then Inc(Depth)
    else if Rest[I] = ']' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close:= I;
        Break;
      end;
    end;
  end;
  if Close = 0 then Exit(False);
  var After:= Copy(Rest, Close + 1, MaxInt);
  { B4: `S := F[..]` as a whole statement, S a slot that switches }
  var IntoSlot:= (Length(pSlots) > 0) and TRegEx.IsMatch(After, '^\s*(;|$|end\b|else\b)', [roIgnoreCase]) and
    TRegEx.IsMatch(Before, '(^|[;\s])(Self\s*\.\s*)?(' + string.Join('|', pSlots) + ')\s*:=\s*(Self\s*\.\s*)?$', [roIgnoreCase]);
  if IntoSlot or TRegEx.IsMatch(After, '^\s*:=') then Exit(True);
  var Member:= TRegEx.Match(After, '^\s*\.\s*([A-Za-z_]\w*)');
  Result:= Member.Success and MatchText(Member.Groups[1].Value, pPulled) and
    not TRegEx.IsMatch(Copy(After, Member.Length + 1, MaxInt), '^\s*:=');
end;

{ B4-c: one use of the TList<TX> / TObjectList<TX> field named at pIndex in pCode that survives the
  switch of its element type to the base class (pTypeName = TX): a use IsSwitchableFieldUse admits
  (`F[..] := x`, `F[..].M`, `S := F[..]`, `for S in F do`), the same through `.Items[..]`, a call or read
  of Add / Insert / Remove / IndexOf / Contains / Delete / Clear / Count / Free, a nil test,
  `Assigned(F)` / `FreeAndNil(F)`, or `F := TList<TX>.Create` (TObjectList too) -- the creation is
  switched with the field. Extract, First, Last, ToArray and every other use refuse. }
function IsListFieldUse(const pCode: string; pIndex, pLen: Integer; const pTypeName: string; const pPulled,
  pSlots: TArray<string>): Boolean;
begin
  if IsSwitchableFieldUse(pCode, pIndex, pLen, pPulled, pSlots) then Exit(True);
  var Rest:= Copy(pCode, pIndex + pLen, MaxInt);
  var Items:= TRegEx.Match(Rest, '^\s*\.\s*Items\b', [roIgnoreCase]);
  if Items.Success and IsSwitchableFieldUse(Copy(pCode, 1, pIndex + pLen - 1) + Copy(Rest, Items.Length + 1, MaxInt),
    pIndex, pLen, pPulled, pSlots) then Exit(True);
  if TRegEx.IsMatch(Rest, '^\s*\.\s*(Add|Insert|Remove|IndexOf|Contains|Delete|Clear|Count|Free)\b', [roIgnoreCase]) then
    Exit(True);
  if TRegEx.IsMatch(Rest, '^\s*(=|<>)\s*nil\b', [roIgnoreCase]) then Exit(True);
  var Before:= Copy(pCode, 1, pIndex - 1);
  if TRegEx.IsMatch(Before, '\b(Assigned|FreeAndNil)\s*\(\s*$', [roIgnoreCase]) and TRegEx.IsMatch(Rest, '^\s*\)') then
    Exit(True);
  Result:= TRegEx.IsMatch(Rest, '^\s*:=\s*T(Object)?List\s*<\s*' + pTypeName + '\s*>\s*\.\s*Create\b', [roIgnoreCase]);
end;
{ D1 (owner ruling 2026-10-25, option a+): whether the switched line pLine of
  pFid declares a FIELD `F: TArray<TX>` / `F: array of TX` (TX = pItem's class)
  that may become `TArray<TXBase>` -- B4-c: or `TList<TX>` / `TObjectList<TX>`, judged by IsListFieldUse. pField is '' when the line is not such a
  field declaration (the caller keeps its general refusal), else the field's
  name. Returns '' when the field switches: it is not published (nor in an
  unlabelled section, which $M+ publishes), the index shows no reference to it
  outside its unit, and every use of its name in its unit passes
  IsSwitchableFieldUse; otherwise the first offending site, as
  "`<file>:<line>`: <what>". }
function TCyclePlanner.FieldSiteRefusal(const pItem: TMoveItem; pFid: Int64; pLine: Integer; out pField: string;
  const pSlots: TArray<string>): string;
var
  Fld   : TSymbol;
  Pulled: TArray<string>;
begin
  pField:= '';
  Result:= '';
  var F:= GetFile(pFid);
  var M:= TRegEx.Match(CodePart(LineAt(F.Lines, pLine)), '^\s*([A-Za-z_]\w*)\s*:\s*(TArray\s*<\s*' + pItem.Sym.Name +
    '\s*>|array\s+of\s+' + pItem.Sym.Name + '|(?:TList|TObjectList)\s*<\s*' + pItem.Sym.Name + '\s*>)\s*;\s*$', [roIgnoreCase]);
  if not M.Success then Exit;
  var IsList:= StartsText('TList', Trim(M.Groups[2].Value)) or StartsText('TObjectList', Trim(M.Groups[2].Value));
  Fld:= Default(TSymbol);
  for var S in F.Syms do
    if (S.Kind = skField) and (S.StartLine = pLine) and SameText(S.Name, M.Groups[1].Value) then Fld:= S;
  if Fld.Id = 0 then Exit;
  pField:= Fld.Name;
  var Site:= Format('`%s:%d`', [ExtractFileName(F.Path), pLine]);
  var Head:= if IsList then Format('field `%s` (`%s`) can switch to the base class only when every use is on the ' +
    'list whitelist (Create, Add, Insert, Remove, IndexOf, Contains, Delete, Clear, Count, Free, a store `%s[..] := x`, ' +
    'a read `%s[..].M` of a member the base class gets, `for S in %s`)', [Fld.Name, Trim(M.Groups[2].Value), Fld.Name,
    Fld.Name, Fld.Name])
  else Format('field `%s` (`%s`) can switch to the base class only when every use is SetLength, ' +
    'Length, High, Low, a store `%s[..] := x` or a read `%s[..].M` of a member the base class gets',
    [Fld.Name, Trim(M.Groups[2].Value), Fld.Name, Fld.Name]);
  if ContainsText(Fld.Modifiers, 'published') or not Fld.VisExplicit then
    Exit(Format('%s: %s; it is published (or in an unlabelled section, published under {$M+}), so RTTI ' +
      'and streaming see its declared type', [Site, Head]));
  for var R in FStore.FindReferencesTo(Fld.Id) do
    if R.FileId <> pFid then
      Exit(Format('`%s:%d`: %s; it is referred to here, outside its unit', [ExtractFileName(PathOf(R.FileId)),
        R.StartLine, Head]));
  Pulled:= nil;
  for var B in pItem.BaseMembers do Pulled:= Pulled + [B.Sym.Name];
  for var L:= 1 to Length(F.Lines) do
  begin
    if L = pLine then Continue;
    var Code:= CodePart(LineAt(F.Lines, L));
    for var U in TRegEx.Matches(Code, '\b' + Fld.Name + '\b', [roIgnoreCase]) do
      if not (if IsList then IsListFieldUse(Code, U.Index, U.Length, pItem.Sym.Name, Pulled, pSlots)
        else IsSwitchableFieldUse(Code, U.Index, U.Length, Pulled, pSlots)) then
        Exit(Format('`%s:%d`: %s', [ExtractFileName(F.Path), L, Head]));
  end;
end;

{ E18 T7 F5: '' when the routine pLine belongs to uses pParam only to read one
  of its members (member_accesses mode read, receiver = the parameter) or to
  compare it with nil; otherwise what it does, with the line. pLine is in the
  routine's implementation header, or in its declaration (interface or class),
  whose body is then checked through the declaration's implementation range.
  No body at all (abstract, external, a forward never implemented here) is a
  refusal: nothing shows the base class is enough for the overrides or callees.
  Every occurrence of the name in the body is classified by its own column:
  followed by `.` (a receiver: the member ref must be a read) or by `= nil` /
  `<> nil` (or preceded by `nil =` / `nil <>`), or -- D1 -- as the whole right
  side of a store `F[..] := p` into one of pFields (fields that switch to
  the base class too); B4: the argument of `F.Add(p)` and its kin (IsListArg), or the whole
  right side of `S := p` into one of pSlots (plain fields / locals that switch); anything else refuses. }
function TCyclePlanner.ParamBodyRefusal(pFid: Int64; pLine: Integer; const pParam: string;
  const pFields: TArray<string>; const pSlots: TArray<string>): string;
var
  Routine: TSymbol;
  MA     : TCallEdge;
  BodyAt : Integer;
  BodyCol: Integer;
begin
  var F:= GetFile(pFid);
  Routine:= RoutineAt(F, pLine);
  if (Routine.Id = 0) or (Routine.ImplStartLine <= 0) or (Routine.ImplEndLine < Routine.ImplStartLine) then
    Exit(Format('it belongs to no routine body in this file (abstract, external or not ' +
      'implemented here), so nothing shows a base class is enough for `%s`', [pParam]));
  if not HeaderEnd(F.Lines, Routine.ImplStartLine, Routine.ImplEndLine, BodyAt, BodyCol) then Exit(Format('the header of `%s` (line %d) could not be read', [Routine.Name, Routine.ImplStartLine]));
  for var L:= BodyAt to Routine.ImplEndLine do
  begin
    var Code:= CodePart(LineAt(F.Lines, L));
    for var M in TRegEx.Matches(Code, '\b' + pParam + '\b', [roIgnoreCase]) do
    begin
      if (L = BodyAt) and (M.Index <= BodyCol) then Continue;
      if IsReceiverOrNilTest(Code, M.Index, M.Length) then Continue;
      if IsListArg(Code, M.Index, M.Length, pFields) then Continue;
      { B4: stored whole into a plain field or local that switches (`S := p`) }
      if (Length(pSlots) > 0) and
        TRegEx.IsMatch(Copy(Code, 1, M.Index - 1), '(^|[;\s])(Self\s*\.\s*)?(' + string.Join('|', pSlots) + ')\s*:=\s*$',
          [roIgnoreCase]) and
        TRegEx.IsMatch(Copy(Code, M.Index + M.Length, MaxInt), '^\s*(;|$|end\b|else\b)', [roIgnoreCase]) then
        Continue;
      if (Length(pFields) > 0) and
        TRegEx.IsMatch(Copy(Code, 1, M.Index - 1), '(^|[;\s])(Self\s*\.\s*)?(' + string.Join('|', pFields) +
          ')\s*\[[^;]*\]\s*:=\s*$', [roIgnoreCase]) and
        TRegEx.IsMatch(Copy(Code, M.Index + M.Length, MaxInt), '^\s*(;|$|end\b|else\b)', [roIgnoreCase]) then
        Continue;
      Exit(Format('line %d (column %d) uses `%s` other than to read a member or compare it with nil',
        [L, M.Index, pParam]));
    end;
  end;
  Result:= '';
  for var R in F.Refs do
  begin
    if (R.StartLine < Routine.ImplStartLine) or (R.StartLine > Routine.ImplEndLine) then Continue;
    if SameText(R.ReceiverText, pParam) and
      not (SameText(R.Kind, 'member-access') and MemberAccessOf(R.Id, MA) and SameText(MA.MemberMode, 'read')) then
      Exit(Format('line %d: `%s.%s` is not a read of a member', [R.StartLine, pParam, R.NameText]));
  end;
end;
function TCyclePlanner.TryAdd(const pSym: TSymbol; const pCut: TArray<Int64>; out pWhy: string): Boolean;
var
  Item: TMoveItem;
begin
  pWhy:= '';
  if FItems.TryGetValue(pSym.Id, Item) then
  begin
    { a class that only got a base class extracted has NOT moved }
    if Item.Kind <> mvBase then Exit(True);
    pWhy:= Format('`%s` itself stays in its unit -- only its base class moves', [pSym.Name]);
    Exit(False);
  end;
  if not FMembers.ContainsKey(StemOfFid(pSym.FileId)) then Exit(True);
  Item:= Classify(pSym, pCut);
  if Item.Kind = mvBlocked then
  begin
    pWhy:= Item.Reason;
    Exit(False);
  end;
  FItems.Add(pSym.Id, Item);
  FOrder.Add(pSym.Id);
  Result:= AddDependencies(Item, pWhy) and AddCompanions(Item, pWhy);
end;

function TCyclePlanner.AddDependencies(const pItem: TMoveItem; out pWhy: string): Boolean;
var
  Why: string;
begin
  pWhy:= '';
  for var N in NeedsInRanges(GetFile(pItem.Sym.FileId), MovedRanges(pItem)) do
  begin
    if (N.Owner.Id = pItem.Sym.Id) or not FMembers.ContainsKey(N.OwnerStem) then Continue;
    NotePulledBy(N.Owner, pItem.Sym);
    if not TryAdd(N.Owner, nil, Why) then
    begin
      pWhy:= Format('it needs `%s` (%s), which cannot move: %s', [N.Owner.Name, N.Owner.Kind.ToText, Why]);
      Exit(False);
    end;
  end;
  Result:= True;
end;

function TCyclePlanner.AddCompanions(const pItem: TMoveItem; out pWhy: string): Boolean;
var
  Owner: TSymbol;
  Why  : string;
begin
  pWhy:= '';
  if pItem.Kind = mvBase then Exit(True);
  { every other unit-level declaration on the moved lines moves too }
  for var S in GetFile(pItem.Sym.FileId).Syms do
  begin
    if (S.Id = pItem.Sym.Id) or not InRanges(S.StartLine, WithRange(pItem.Decl, nil)) then Continue;
    if (S.Kind = skEnumValue) or not OwnerOf(S, Owner) or (Owner.Id <> S.Id) then Continue;
    NotePulledBy(S, pItem.Sym);
    if not TryAdd(S, nil, Why) then
    begin
      pWhy:= Format('`%s` is declared on the same lines and cannot move: %s', [S.Name, Why]);
      Exit(False);
    end;
  end;
  Result:= True;
end;

procedure TCyclePlanner.NotePulledBy(const pSym, pBy: TSymbol);
begin
  { overwrites a stale entry of a probe that Rollback undid; an item already planned keeps none }
  if FItems.ContainsKey(pSym.Id) then Exit;
  FPulledBy.AddOrSetValue(pSym.Id, Format('%s `%s`', [(if pBy.Kind = skVarDecl then 'var' else 'declaration'), pBy.Name]));
end;

procedure TCyclePlanner.Rollback(pSnap: Integer);
begin
  while FOrder.Count > pSnap do
  begin
    FItems.Remove(FOrder.Last);
    FOrder.Delete(FOrder.Count - 1);
  end;
end;

function TCyclePlanner.IsMovedFor(const pOwner: TSymbol; pFid: Int64): Boolean;
var
  Item: TMoveItem;
begin
  { R1: the consumer's calls of the inverted routine go through the pointer }
  if (FInversion.Recipe = crRoutineInversion) and (pFid = FInversion.ConsumerFid) then
    for var R in FInversion.Routines do
      if pOwner.Id = R.Id then Exit(True);
  { R2: the consumer names the interface instead of the class }
  if (FInversion.Recipe = crMemberInterface) and (pOwner.Id = FInversion.ClassId) and
    (pFid = FInversion.ConsumerFid) then Exit(True);
  if not FItems.TryGetValue(pOwner.Id, Item) then Exit(False);
  if Item.Kind in [mvDecl, mvWithBodies] then Exit(True);
  for var Fid in Item.CutFids do
    if Fid = pFid then Exit(True);
  Result:= False;
end;

{ ---------------------------------------------------------------------------
  materialise: leaf names, line edits, consumers, uses decisions
  --------------------------------------------------------------------------- }

procedure TCyclePlanner.Materialize;
begin
  AssignLeafNames;
  MarkItemLines;
  DeleteEmptyHeaders;
  CollectConsumers;
  CollectLeafDeps;
  DecideUses;
  DecideUnseenIntfEntries;
  RegisterLeaves;
  ExtendLeaves;
  BuildUsesEdits;
  Predict;
end;

procedure TCyclePlanner.AssignLeafNames;
begin
  { E18 T4b: the catalog names the leaf `<Source>.Untangle` and finds an existing
    one that is still a leaf for this group (udExtend) }
  var Root:= if FProjectFid > 0 then ExtractFilePath(PathOf(FProjectFid)) else '';
  for var Id in FOrder do
  begin
    var Stem:= FItems[Id].Stem;
    if FLeafName.ContainsKey(Stem) then Continue;
    var Leaf:= ResolveUntangleLeaf(FStore, Stem, FComp, Root);
    FLeafInfo.Add(Stem, Leaf);
    FLeafName.Add(Stem, Leaf.UnitName);
    FLeafPath.Add(Stem, Leaf.Path);
  end;
end;

function TCyclePlanner.LeafStems(pDecision: TUntangleDecision): TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var Id in FOrder do
      if FLeafInfo.ContainsKey(FItems[Id].Stem) and (FLeafInfo[FItems[Id].Stem].Decision = pDecision) then
        AddUnique(L, FItems[Id].Stem);
    if IsInversionStem(FInversion.DeclStem) and (FLeafInfo[FInversion.DeclStem].Decision = pDecision) then
      AddUnique(L, FInversion.DeclStem);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TCyclePlanner.Touch(pFid: Int64);
begin
  if not FTouched.Contains(pFid) then FTouched.Add(pFid);
end;

procedure TCyclePlanner.MarkDeleted(pFid: Int64; const pRange: TLineRange);
begin
  Touch(pFid);
  for var I:= pRange.First to pRange.Last do FDeleted.AddOrSetValue(LineKey(pFid, I), True);
end;

function TCyclePlanner.IsDeleted(pFid: Int64; pLine: Integer): Boolean;
begin
  Result:= FDeleted.ContainsKey(LineKey(pFid, pLine));
end;

procedure TCyclePlanner.MarkReplaced(pFid: Int64; pLine: Integer; const pText: string);
begin
  Touch(pFid);
  FReplaced.AddOrSetValue(LineKey(pFid, pLine), pText);
end;

procedure TCyclePlanner.MarkItemLines;
begin
  for var Id in FOrder do
  begin
    var Item:= FItems[Id];
    var Fid := Item.Sym.FileId;
    if Item.Kind <> mvBase then
    begin
      for var R in MovedRanges(Item) do MarkDeleted(Fid, R);
      if Item.SameLine then
      begin
        { W6 C6: the keyword line stays (DeleteEmptyHeaders drops it with an emptied block) }
        var Line:= LineAt(GetFile(Fid).Lines, Item.Header);
        FDeleted.Remove(LineKey(Fid, Item.Header));
        MarkReplaced(Fid, Item.Header, Copy(Line, 1, IndentOf(Line)) + Item.Keyword);
      end;
      Continue;
    end;
    var F:= GetFile(Fid);
    MarkReplaced(Fid, Item.Sym.StartLine, Item.HeaderNew);
    for var M in Item.BaseMembers do
      if M.Sym.Kind in [skMethod, skFunction, skProcedure] then
      begin
        var Last:= LineAt(F.Lines, M.Sym.EndLine);
        var Code:= CodePart(Last);
        MarkReplaced(Fid, M.Sym.EndLine, TrimRight(Code) + COverrideTail + Copy(Last, Length(Code) + 1, MaxInt));
      end
      else MarkDeleted(Fid, M.Range);
    for var S in Item.Switches do MarkReplaced(S.Fid, S.Line, S.NewText);
  end;
end;

procedure TCyclePlanner.DeleteEmptyHeaders;
begin
  { a `type` / `var` block whose every declaration moved loses its keyword too }
  for var Id in FOrder do
  begin
    var Item:= FItems[Id];
    if Item.Kind = mvBase then Continue;
    var F    := GetFile(Item.Sym.FileId);
    var Empty:= True;
    for var L:= Item.Header + 1 to BlockEnd(F.Lines, Item.Header) - 1 do
      if not (IsDeleted(F.Fid, L) or IsCommentOnly(LineAt(F.Lines, L))) then Empty:= False;
    if Empty then
    begin
      FReplaced.Remove(LineKey(F.Fid, Item.Header));
      MarkDeleted(F.Fid, OneRange(Item.Header, Item.Header));
    end;
  end;
end;

procedure TCyclePlanner.AddConsumer(const pItem: TMoveItem; pFid: Int64; pSect: TSect; pLine: Integer);
var
  L: TList<TConsumer>;
  C: TConsumer;
begin
  if not FConsumers.TryGetValue(pItem.Sym.Id, L) then
  begin
    L:= TList<TConsumer>.Create;
    FConsumers.Add(pItem.Sym.Id, L);
  end;
  for var I:= 0 to L.Count - 1 do
    if (L[I].Fid = pFid) and (L[I].Sect = pSect) then
    begin
      C:= L[I];
      if pLine < C.Line then C.Line:= pLine;
      L[I]:= C;
      Exit;
    end;
  C.Fid := pFid;
  C.Sect:= pSect;
  C.Line:= pLine;
  L.Add(C);
  AddUses(pFid, pSect, UsesEntryFor(GetFile(pFid), pItem.Stem));
end;

procedure TCyclePlanner.CollectConsumers;
var
  Users: TList<Int64>;
  Files: TList<Int64>;
begin
  Files:= TList<Int64>.Create;
  try
    for var Id in FOrder do
    begin
      var Item:= FItems[Id];
      if Item.Kind = mvBase then
      begin
        AddConsumer(Item, Item.Sym.FileId, scIntf, Item.Sym.StartLine);
        for var S in Item.Switches do AddConsumer(Item, S.Fid, SectOf(GetFile(S.Fid), S.Line), S.Line);
        Continue;
      end;
      Files.Clear;
      Files.Add(Item.Sym.FileId);
      if FUsersOf.TryGetValue(Item.Stem, Users) then
        for var U in Users do
          if not Files.Contains(U) then Files.Add(U);
      for var Fid in Files do
        for var N in NeedsOf(Fid) do
          if (N.Owner.Id = Item.Sym.Id) and not IsDeleted(Fid, N.Line) then AddConsumer(Item, Fid, N.Sect, N.Line);
    end;
  finally
    Files.Free;
  end;
end;

procedure TCyclePlanner.CollectLeafDeps;
var
  Deps : TList<string>;
  Other: TMoveItem;
begin
  for var Id in FOrder do
  begin
    var Item:= FItems[Id];
    if not FLeafDeps.TryGetValue(Item.Stem, Deps) then
    begin
      Deps:= TList<string>.Create;
      FLeafDeps.Add(Item.Stem, Deps);
    end;
    for var N in NeedsInRanges(GetFile(Item.Sym.FileId), MovedRanges(Item)) do
    begin
      if N.OwnerStem = Item.Stem then Continue;
      if FItems.TryGetValue(N.Owner.Id, Other) then AddUnique(Deps, FLeafName[Other.Stem])
      else if not FMembers.ContainsKey(N.OwnerStem) then AddUnique(Deps, UnitNameOfStem(N.OwnerStem));
    end;
  end;
end;

procedure TCyclePlanner.DecideUses;
begin
  for var Stem in FComp do
  begin
    var F:= GetFile(FidOfStem(Stem));
    for var U in F.UsesList do
    begin
      var B:= LowerCase(U.UnitName);
      if (B = Stem) or not FMembers.ContainsKey(B) or not FLeafName.ContainsKey(B) then Continue;
      if U.Section in [uusInterface, uusImplementation] then DecideOne(F, U);
    end;
  end;
end;

procedure TCyclePlanner.DecideOne(const pA: TPlanFile; const pU: TUnitUse);
var
  D      : TUsesDecision;
  Had    : array [Boolean] of Boolean;
  Still  : array [Boolean] of TList<string>;
  InImpl : Boolean;
  Partner: string;
begin
  Partner    := LowerCase(pU.UnitName);
  InImpl     := pU.Section = uusImplementation;
  Had[False] := False;
  Had[True]  := False;
  Still[False]:= TList<string>.Create;
  Still[True] := TList<string>.Create;
  try
    for var N in NeedsOf(pA.Fid) do
    begin
      if (N.OwnerStem <> Partner) or IsDeleted(pA.Fid, N.Line) then Continue;
      Had[N.Sect = scImpl]:= True;
      if IsMovedFor(N.Owner, pA.Fid) then Continue;
      var Shown:= False;
      for var S in Still[N.Sect = scImpl] do
        if StartsText('`' + N.RefName + '`', S) then Shown:= True;
      if not Shown then Still[N.Sect = scImpl].Add(Format('`%s` line %d', [N.RefName, N.Line]));
    end;
    D.Fid        := pA.Fid;
    D.PartnerStem:= Partner;
    D.Sect       := if InImpl then scImpl else scIntf;
    if not Had[InImpl] then D.Verdict:= uvKeepUnseen
    else if Still[InImpl].Count > 0 then D.Verdict:= uvKeep
    else if (not InImpl) and (Still[True].Count > 0) then D.Verdict:= uvMove
    else D.Verdict:= uvRemove;
    D.Still:= string.Join(', ', Still[InImpl or (D.Verdict = uvMove)].ToArray);
  finally
    Still[True].Free;
    Still[False].Free;
  end;
  FDecisions.Add(D);
  if D.Verdict in [uvMove, uvRemove] then DelUses(pA.Fid, D.Sect, Partner);
  if D.Verdict = uvMove then AddUses(pA.Fid, scImpl, EntryText(pA, pU));
end;

type
  { A3-a: one identifier CodeIdentsIn found, at its 1-based line }
  TLexIdent = record
    Name: string;
    Line: Integer;
  end;

{ A3-a: pLine with every comment (brace and paren-star comments, which may span lines -- the open
  state is carried in pInBrace / pInParen -- and `//`), compiler directive and string literal blanked
  to spaces, so only code is left. }
function CodeOnly(const pLine: string; var pInBrace, pInParen: Boolean): string;
const
  CPairLen = 2;
var
  I: Integer;
begin
  Result:= pLine;
  I:= 1;
  while I <= Length(Result) do
  begin
    var Pair:= Copy(Result, I, CPairLen);
    var Opens:= (not pInBrace) and (not pInParen) and ((Result[I] = '{') or (Pair = '(*'));
    if Opens then
    begin
      pInBrace:= Result[I] = '{';
      pInParen:= not pInBrace;
    end;
    if (not pInBrace) and (not pInParen) and (Pair = '//') then
      Exit(Copy(Result, 1, I - 1));
    if (not pInBrace) and (not pInParen) and (Result[I] = '''') then
    begin
      var J:= PosEx('''', Result, I + 1);
      if J = 0 then J:= Length(Result);
      for var K:= I to J do Result[K]:= ' ';
      I:= J + 1;
      Continue;
    end;
    if pInBrace or pInParen then
    begin
      var Closes:= (pInBrace and (Result[I] = '}')) or (pInParen and (Pair = '*)') and not Opens);
      if pInParen and Closes then Result[I + 1]:= ' ';
      if Closes then
      begin
        pInBrace:= False;
        pInParen:= False;
      end;
      Result[I]:= ' ';
    end;
    Inc(I);
  end;
end;

{ A3-a: every identifier of lines pFirst..pLast (1-based) in code (CodeOnly); a dotted name gives
  each of its segments; the unit names of a `uses ... ;` clause are skipped (they name units, not
  exports); numeric literals (`1e5`, `$FF`, `#13`) are not identifiers. }
function CodeIdentsIn(const pLines: TArray<string>; pFirst, pLast: Integer): TArray<TLexIdent>;
var
  L      : TList<TLexIdent>;
  InBrace: Boolean;
  InParen: Boolean;
  InUses : Boolean;
  X      : TLexIdent;
begin
  L:= TList<TLexIdent>.Create;
  try
    InBrace:= False;
    InParen:= False;
    InUses := False;
    for var Ln:= pFirst to pLast do
      for var M in TRegEx.Matches(CodeOnly(LineAt(pLines, Ln), InBrace, InParen), '[0-9$#]\w*|[A-Za-z_]\w*|;') do
      begin
        if M.Value = ';' then InUses:= False
        else if SameText(M.Value, 'uses') then InUses:= True
        else if (not InUses) and not CharInSet(M.Value[1], ['0'..'9', '$', '#']) then
        begin
          X.Name:= M.Value;
          X.Line:= Ln;
          L.Add(X);
        end;
      end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;
{ A3-a: the first identifier in section pSect of pFrom's text that names a top-level interface
  export of pTo (an enum value counts) and is not a top-level declaration of pFrom itself; ''
  when none. The cross-check that tells "the interface uses nothing of pTo" from "the index
  missed a use" before an interface entry the index saw no use for is moved or removed. }
function TCyclePlanner.LexicalUseOf(const pFrom, pTo: string; pSect: TSect; out pLine: Integer): string;
var
  Exported: TDictionary<string, Boolean>;
  Owner   : TSymbol;
begin
  Result:= '';
  pLine := 0;
  Owner := Default(TSymbol);
  var FA:= GetFile(FidOfStem(pFrom));
  var FB:= GetFile(FidOfStem(pTo));
  Exported:= TDictionary<string, Boolean>.Create;
  try
    for var S in FB.Syms do
      if OwnerOf(S, Owner) and ((FB.ImplLine = 0) or (Owner.StartLine < FB.ImplLine)) then
        Exported.AddOrSetValue(LowerCase(S.Name), True);
    for var S in FA.Syms do
      if OwnerOf(S, Owner) then Exported.Remove(LowerCase(S.Name));
    var First:= if pSect = scIntf then FA.IntfLine + 1 else FA.ImplLine + 1;
    var Last := if (pSect = scIntf) and (FA.ImplLine > 0) then FA.ImplLine - 1 else Length(FA.Lines);
    if (pSect = scImpl) and (FA.ImplLine = 0) then Exit;
    for var X in CodeIdentsIn(FA.Lines, First, Last) do
      if Exported.ContainsKey(LowerCase(X.Name)) then
      begin
        pLine:= X.Line;
        Exit(X.Name);
      end;
  finally
    Exported.Free;
  end;
end;

{ A3-a: whether DecideUnseenIntfEntries moved or removed pFrom's interface entry for pTo. }
function TCyclePlanner.IntfEntryDecided(const pFrom, pTo: string): Boolean;
begin
  for var D in FDecisions do
    if (D.Fid = FidOfStem(pFrom)) and (D.PartnerStem = pTo) and (D.Sect = scIntf) and
      (D.Verdict in [uvMove, uvRemove]) then Exit(True);
  Result:= False;
end;

{ A3-a (plan 2026-10-25-cycles-fix-refusal-recipes.md): an interface uses entry A -> B between
  units of the cycle for which the index records NO interface need is decided from what the
  implementation needs, as DecideOne decides a partner whose declarations move -- unless the text
  of A's interface names an export of B (LexicalUseOf), which keeps the `unresolved-edge`
  refusal. The implementation uses B (an index need or a lexical use) -> move the entry down;
  nothing does -> remove it. A uvKeepUnseen decision DecideOne made for the same entry is
  replaced. An entry that comes from an include is left alone (BuildClauseEdit refuses it). The
  compile gate rolls back a use both the index and the scan missed (E2003). }
procedure TCyclePlanner.DecideUnseenIntfEntries;
begin
  for var A in FComp do
    for var B in FComp do
      if (A <> B) and FGraph.IntfEdges.ContainsKey(A + '->' + B) and not IntfEntryDecided(A, B) then
        DecideUnseenIntfEntry(A, B);
end;

{ A3-a: DecideUnseenIntfEntries for the one interface edge pFrom -> pTo. }
procedure TCyclePlanner.DecideUnseenIntfEntry(const pFrom, pTo: string);
var
  F       : TPlanFile;
  U       : TUnitUse;
  D       : TUsesDecision;
  Still   : TList<string>;
  Idx     : Integer;
  HitLine : Integer;
  Lex     : string;
  Replaced: Boolean;
begin
  for var N in NeedsOf(FidOfStem(pFrom)) do
    if (N.Sect = scIntf) and (N.OwnerStem = pTo) then Exit;
  if LexicalUseOf(pFrom, pTo, scIntf, HitLine) <> '' then Exit;
  F:= GetFile(FidOfStem(pFrom));
  Idx:= -1;
  for var K:= 0 to High(F.UsesList) do
    if (F.UsesList[K].Section = uusInterface) and not F.UsesList[K].FromInclude and
      ((LowerCase(F.UsesList[K].UnitName) = pTo) or EndsText('.' + LowerCase(F.UsesList[K].UnitName), pTo)) then
      Idx:= K;
  if Idx < 0 then Exit;
  U:= F.UsesList[Idx];
  Still:= TList<string>.Create;
  try
    for var N in NeedsOf(F.Fid) do
      if (N.Sect = scImpl) and (N.OwnerStem = pTo) and not IsDeleted(F.Fid, N.Line) then
        AddUnique(Still, Format('`%s` line %d', [N.RefName, N.Line]));
    Lex:= LexicalUseOf(pFrom, pTo, scImpl, HitLine);
    if (Still.Count = 0) and (Lex <> '') then Still.Add(Format('`%s` line %d', [Lex, HitLine]));
    D:= Default(TUsesDecision);
    D.Fid        := F.Fid;
    D.PartnerStem:= pTo;
    D.Sect       := scIntf;
    D.Verdict    := if Still.Count > 0 then uvMove else uvRemove;
    D.Still      := string.Join(', ', Still.ToArray);
  finally
    Still.Free;
  end;
  Replaced:= False;
  for var K:= 0 to FDecisions.Count - 1 do
    if (FDecisions[K].Fid = F.Fid) and (FDecisions[K].Sect = scIntf) and (FDecisions[K].Verdict = uvKeepUnseen) and
      (FDecisions[K].PartnerStem = LowerCase(U.UnitName)) then
    begin
      FDecisions[K]:= D;
      Replaced:= True;
    end;
  if not Replaced then FDecisions.Add(D);
  DelUses(F.Fid, scIntf, LowerCase(U.UnitName));
  if D.Verdict = uvMove then AddUses(F.Fid, scImpl, EntryText(F, U));
end;

procedure TCyclePlanner.RegisterLeaves;
var
  Dproj: TArray<string>;
  E    : TFileEdit;
begin
  if FProjectFid = 0 then Exit;
  var Prj:= GetFile(FProjectFid);
  { only a CREATED leaf is registered; an extended one is in the project already }
  var Created:= LeafStems(udCreate);
  for var Stem in Created do AddUses(FProjectFid, scProg, UsesEntryFor(Prj, Stem));
  if not (SameText(ExtractFileExt(FProjectFile), '.dproj') and TFile.Exists(FProjectFile)) then Exit;
  Dproj:= ReadSourceLines(FProjectFile);
  for var U in Prj.UsesList do
  begin
    var Stem:= LowerCase(U.UnitName);
    if (U.InPath = '') or not MatchText(Stem, Created) then Continue;
    for var I:= 0 to High(Dproj) do
      if ContainsText(Dproj[I], 'Include="' + U.InPath + '"') then
      begin
        E:= Default(TFileEdit);
        E.Kind    := ekInsertAfter;
        E.First   := I + 1;
        E.Last    := I + 1;
        E.NewLines:= [StringReplace(Dproj[I], U.InPath, ExtractFilePath(U.InPath) + FLeafName[Stem] + '.pas', [rfIgnoreCase])];
        FDprojEdits.Add(E);
        Break;
      end;
  end;
end;

{ The uses entries pEntries for section pSect of the existing leaf pF. A section
  that has a clause gets them through AddUses (the T3a lexer add, which skips an
  entry already there); one without a clause gets a new clause after its keyword
  -- also through AddUses, unless the insert at pAnchor sits on that keyword
  line too: two inserts after one line have no order, so the clause is then
  returned to lead the insert's own text. }
function TCyclePlanner.MergeLeafUses(const pF: TPlanFile; pSect: TSect; pAnchor: Integer;
  const pEntries: TArray<string>): TArray<string>;
begin
  Result:= nil;
  if Length(pEntries) = 0 then Exit;
  var KeyLine:= if pSect = scIntf then pF.IntfLine else pF.ImplLine;
  if (Length(SectionEntries(pF, pSect)) = 0) and (pAnchor = KeyLine) then
    Exit(PrependBlank(FormatUses('', pEntries, nil)));
  for var S in pEntries do AddUses(pF.Fid, pSect, S);
end;

procedure TCyclePlanner.ExtendLeaves;
var
  Bodies: TList<TLineRange>;
  E     : TFileEdit;
  Lines : TList<string>;
begin
  { E18 T4b: a leaf the catalog found (udExtend) gets the moved declarations
    inserted after its last interface declaration, the bodies before the end of
    its implementation section, and the uses entries they need merged in }
  Bodies:= TList<TLineRange>.Create;
  Lines := TList<string>.Create;
  try
    for var Stem in LeafStems(udExtend) do
    begin
      var Leaf:= FLeafInfo[Stem];
      var F   := GetFile(Leaf.Fid);
      Bodies.Clear;
      var Decls:= LeafDeclLines(Stem, Bodies);
      var At:= Leaf.InsertAfterLine;
      if At = 0 then
      begin
        { no interface declaration: after the interface uses clause, else the keyword }
        At:= F.IntfLine;
        for var U in SectionEntries(F, scIntf) do
          if U.EndLine > At then At:= U.EndLine;
        while (At > F.IntfLine) and (At < Length(F.Lines)) and not ContainsStr(CodePart(LineAt(F.Lines, At)), ';') do Inc(At);
      end;
      Lines.Clear;
      Lines.AddRange(MergeLeafUses(F, scIntf, At, LeafEntries(Stem, scIntf)));
      Lines.AddRange(Decls);
      if Lines.Count = 0 then Continue;  { W6 C2: a reused pointer declaration inserts nothing }
      E:= Default(TFileEdit);
      E.Kind    := ekInsertAfter;
      E.First   := At;
      E.Last    := At;
      E.NewLines:= Lines.ToArray;
      EditList(F.Fid).Add(E);
      if Bodies.Count = 0 then Continue;
      { the bodies go before `initialization` / `finalization` / `end.` }
      At:= Length(F.Lines);
      for var L:= F.ImplLine + 1 to Length(F.Lines) do
        if MatchText(Trim(CodePart(LineAt(F.Lines, L))), ['initialization', 'finalization', 'end.']) then
        begin
          At:= L;
          Break;
        end;
      Dec(At);
      Lines.Clear;
      Lines.AddRange(MergeLeafUses(F, scImpl, At, LeafEntries(Stem, scImpl)));
      for var R in Bodies do
      begin
        Lines.Add('');
        Lines.AddRange(SliceLines(GetFile(FidOfStem(Stem)).Lines, R));
      end;
      E:= Default(TFileEdit);
      E.Kind    := ekInsertAfter;
      E.First   := At;
      E.Last    := At;
      E.NewLines:= Lines.ToArray;
      EditList(F.Fid).Add(E);
    end;
  finally
    Lines.Free;
    Bodies.Free;
  end;
end;

function TCyclePlanner.ListOf(pDict: TObjectDictionary<string, TList<string>>; pFid: Int64; pSect: TSect): TList<string>;
begin
  if not pDict.TryGetValue(SectKey(pFid, pSect), Result) then
  begin
    Result:= TList<string>.Create;
    pDict.Add(SectKey(pFid, pSect), Result);
  end;
end;

procedure TCyclePlanner.AddUses(pFid: Int64; pSect: TSect; const pEntry: string);
begin
  Touch(pFid);
  AddUnique(ListOf(FUsesAdd, pFid, pSect), pEntry);
end;

procedure TCyclePlanner.DelUses(pFid: Int64; pSect: TSect; const pStem: string);
begin
  Touch(pFid);
  AddUnique(ListOf(FUsesDel, pFid, pSect), pStem);
end;

function TCyclePlanner.EntryText(const pF: TPlanFile; const pU: TUnitUse): string;
var
  S: TStringBuilder;
begin
  { N-06: an include row's coordinates are inside the .inc, not pF.Lines --
    name the unit (with its in-path) rather than copy host text. }
  if pU.FromInclude then
    Exit(if pU.InPath <> '' then Format('%s in ''%s''', [pU.UnitName, pU.InPath]) else pU.UnitName);
  if pU.StartLine = pU.EndLine then
    Exit(Copy(LineAt(pF.Lines, pU.StartLine), pU.StartCol, pU.EndCol - pU.StartCol));
  S:= TStringBuilder.Create;
  try
    S.Append(Copy(LineAt(pF.Lines, pU.StartLine), pU.StartCol, MaxInt));
    for var I:= pU.StartLine + 1 to pU.EndLine - 1 do S.Append(' ').Append(Trim(LineAt(pF.Lines, I)));
    S.Append(' ').Append(TrimLeft(Copy(LineAt(pF.Lines, pU.EndLine), 1, pU.EndCol - 1)));
    Result:= S.ToString;
  finally
    S.Free;
  end;
end;

function TCyclePlanner.UsesEntryFor(const pF: TPlanFile; const pLeafStem: string): string;
begin
  Result:= FLeafName[pLeafStem];
  if not pF.IsProgram then Exit;
  for var U in pF.UsesList do
    if (LowerCase(U.UnitName) = pLeafStem) and (U.InPath <> '') then
      Exit(Format('%s in ''%s''', [Result, ExtractFilePath(U.InPath) + Result + '.pas']));
end;

function TCyclePlanner.SectionEntries(const pF: TPlanFile; pSect: TSect): TArray<TUnitUse>;
var
  L: TList<TUnitUse>;
begin
  L:= TList<TUnitUse>.Create;
  try
    for var U in pF.UsesList do
      case pSect of
        scIntf: if U.Section = uusInterface then L.Add(U);
        scImpl: if U.Section = uusImplementation then L.Add(U);
      else
        if U.Section in [uusProgram, uusPackage] then L.Add(U);
      end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TCyclePlanner.DedupeAdds;
var
  Impl: TList<string>;
  Seen: TList<string>;
begin
  { a unit the interface section already sees must not be named again in the
    implementation uses -- that is E2004 "Identifier redeclared" }
  Seen:= TList<string>.Create;
  try
    for var Fid in FTouched.ToArray do
    begin
      if not FUsesAdd.TryGetValue(SectKey(Fid, scImpl), Impl) then Continue;
      Seen.Clear;
      for var U in SectionEntries(GetFile(Fid), scIntf) do
        if not ListOf(FUsesDel, Fid, scIntf).Contains(LowerCase(U.UnitName)) then Seen.Add(LowerCase(U.UnitName));
      for var S in ListOf(FUsesAdd, Fid, scIntf) do Seen.Add(StemOfEntry(S));
      for var I:= Impl.Count - 1 downto 0 do
        if Seen.Contains(StemOfEntry(Impl[I])) then Impl.Delete(I);
    end;
  finally
    Seen.Free;
  end;
end;

procedure TCyclePlanner.BuildUsesEdits;
begin
  DedupeAdds;
  for var Fid in FTouched.ToArray do
    for var Sect:= Low(TSect) to High(TSect) do
      if (ListOf(FUsesAdd, Fid, Sect).Count > 0) or (ListOf(FUsesDel, Fid, Sect).Count > 0) then
        BuildClauseEdit(GetFile(Fid), Sect);
end;

procedure TCyclePlanner.BuildClauseEdit(const pF: TPlanFile; pSect: TSect);
var
  Entries : TArray<TUnitUse>;
  Adds    : TList<string>;
  Dels    : TList<string>;
  E       : TFileEdit;
  UsesLine: Integer;
begin
  Entries:= SectionEntries(pF, pSect);
  Adds   := ListOf(FUsesAdd, pF.Fid, pSect);
  Dels   := ListOf(FUsesDel, pF.Fid, pSect);
  E      := Default(TFileEdit);
  { N-06: a section whose uses entries come (partly) from an include is never
    edited -- the .inc may be shared, and its coordinates are not this file's.
    ONE manual edit at the include line names the refusal. }
  { name the include entry the plan would remove when there is one, else the first }
  var IncIdx: Integer:= -1;
  for var I:= 0 to High(Entries) do
    if Entries[I].FromInclude and ((IncIdx < 0) or Dels.Contains(LowerCase(Entries[I].UnitName))) then
      if (IncIdx < 0) or not Dels.Contains(LowerCase(Entries[IncIdx].UnitName)) then IncIdx:= I;
  if IncIdx >= 0 then
  begin
    E.Kind   := ekManual;
    E.Refusal:= REFUSAL_USES_IN_INCLUDE;
    E.First  := Entries[IncIdx].IncludeLine;
    E.Last   := E.First;
    E.Note   := IncludeUsesRefusal('cycles --fix', Entries[IncIdx], pF.Path);
    EditList(pF.Fid).Add(E);
    Exit;
  end;
  if Length(Entries) = 0 then
  begin
    if Adds.Count = 0 then Exit;
    E.Kind := ekInsertAfter;
    E.First:= if pSect = scIntf then pF.IntfLine else pF.ImplLine;
    E.Last := E.First;
    if (pSect = scProg) or (E.First = 0) then
    begin
      E.Kind:= ekManual;
      E.Note:= Format('Add a `uses` clause naming %s to the %s section.', [QuoteList(Adds.ToArray), SectLabel(pSect)]);
    end
    else E.NewLines:= PrependBlank(FormatUses('', Adds.ToArray, nil));
    EditList(pF.Fid).Add(E);
    Exit;
  end;
  { E18 T3a: an existing clause gets ONE minimal edit computed over its
    TUsesLexer tokens (ClauseEdit), never a whole-clause rewrite: comments
    survive, a directive the edit would touch refuses the cycle }
  UsesLine:= Entries[0].StartLine;
  while (UsesLine > 1) and not TRegEx.IsMatch(CodePart(LineAt(pF.Lines, UsesLine)), '\buses\b', [roIgnoreCase]) do
    Dec(UsesLine);
  E:= ClauseEdit(pF.Lines, UsesLine, SectLabel(pSect), Adds.ToArray, Dels.ToArray);
  if E.First > 0 then EditList(pF.Fid).Add(E);
end;

function TCyclePlanner.EditList(pFid: Int64): TList<TFileEdit>;
begin
  Touch(pFid);
  if not FExtraEdits.TryGetValue(pFid, Result) then
  begin
    Result:= TList<TFileEdit>.Create;
    FExtraEdits.Add(pFid, Result);
  end;
end;

function TCyclePlanner.EditsOf(pFid: Int64): TArray<TFileEdit>;
var
  L   : TList<TFileEdit>;
  Dels: TList<Integer>;
  E   : TFileEdit;
  F   : TPlanFile;
  I   : Integer;
  J   : Integer;
begin
  F   := GetFile(pFid);
  L   := TList<TFileEdit>.Create;
  Dels:= TList<Integer>.Create;
  try
    for var K:= 1 to Length(F.Lines) do
      if IsDeleted(pFid, K) then Dels.Add(K);
    var Sorted:= SortedInts(Dels);
    I:= 0;
    while I <= High(Sorted) do
    begin
      J:= I;
      while (J < High(Sorted)) and (Sorted[J + 1] = Sorted[J] + 1) do Inc(J);
      E:= Default(TFileEdit);
      E.Kind := ekDelete;
      E.First:= Sorted[I];
      E.Last := Sorted[J];
      L.Add(E);
      I:= J + 1;
    end;
    for var K:= 1 to Length(F.Lines) do
      if FReplaced.ContainsKey(LineKey(pFid, K)) then
      begin
        E:= Default(TFileEdit);
        E.Kind    := ekReplace;
        E.First   := K;
        E.Last    := K;
        E.NewLines:= [FReplaced[LineKey(pFid, K)]];
        L.Add(E);
      end;
    if FExtraEdits.ContainsKey(pFid) then L.AddRange(FExtraEdits[pFid]);
    { bottom-up; an insert AFTER line N runs before an edit starting AT line N }
    L.Sort(TComparer<TFileEdit>.Construct(
      function(const pLeft, pRight: TFileEdit): Integer
      begin
        Result:= (pRight.First * 2 + Ord(pRight.Kind = ekInsertAfter)) - (pLeft.First * 2 + Ord(pLeft.Kind = ekInsertAfter));
      end));
    Result:= L.ToArray;
  finally
    Dels.Free;
    L.Free;
  end;
end;

function TCyclePlanner.EditOrder: TArray<Int64>;
var
  L: TList<Int64>;
begin
  L:= TList<Int64>.Create;
  try
    for var S in FComp do
      if FTouched.Contains(FidOfStem(S)) then L.Add(FidOfStem(S));
    for var Fid in FTouched do
      if (not L.Contains(Fid)) and (Fid <> FProjectFid) then L.Add(Fid);
    if FTouched.Contains(FProjectFid) then L.Add(FProjectFid);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  prediction: replay the uses changes on the graph
  --------------------------------------------------------------------------- }

function TCyclePlanner.PredictedEdges: TObjectDictionary<string, TList<string>>;
var
  L: TList<string>;
begin
  { edge list per member: 'b' for an implementation edge, 'b!' for an interface one }
  Result:= TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  for var A in FComp do
  begin
    L:= TList<string>.Create;
    Result.Add(A, L);
    var F:= GetFile(FidOfStem(A));
    for var U in F.UsesList do
    begin
      var B:= LowerCase(U.UnitName);
      if (B = A) or not FMembers.ContainsKey(B) then Continue;
      var Sect:= if U.Section = uusInterface then scIntf else scImpl;
      if ListOf(FUsesDel, F.Fid, Sect).Contains(B) then Continue;
      AddUnique(L, B + (if Sect = scIntf then CIntfMark else ''));
    end;
    for var S in ListOf(FUsesAdd, F.Fid, scImpl) do
      if FMembers.ContainsKey(StemOfEntry(S)) then AddUnique(L, StemOfEntry(S));
  end;
end;

function TCyclePlanner.Targets(pEdges: TObjectDictionary<string, TList<string>>; const pFrom: string): TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var S in pEdges[pFrom] do AddUnique(L, S.Replace(CIntfMark, ''));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TCyclePlanner.Predict;
var
  Edges: TObjectDictionary<string, TList<string>>;
  Reach: TDictionary<string, Boolean>;
  Done : TDictionary<string, Boolean>;
  Queue: TList<string>;
  M    : TList<string>;
  G    : TPredGroup;
begin
  Edges:= PredictedEdges;
  Reach:= TDictionary<string, Boolean>.Create;
  Done := TDictionary<string, Boolean>.Create;
  Queue:= TList<string>.Create;
  M    := TList<string>.Create;
  try
    { breadth-first reachability from every member -- the groups are small }
    for var A in FComp do
    begin
      Queue.Clear;
      Queue.Add(A);
      while Queue.Count > 0 do
      begin
        var X:= Queue[0];
        Queue.Delete(0);
        for var Y in Targets(Edges, X) do
          if not Reach.ContainsKey(A + '>' + Y) then
          begin
            Reach.Add(A + '>' + Y, True);
            Queue.Add(Y);
          end;
      end;
    end;
    for var A in FComp do
    begin
      if Done.ContainsKey(A) then Continue;
      M.Clear;
      M.Add(A);
      for var B in FComp do
        if (B <> A) and Reach.ContainsKey(A + '>' + B) and Reach.ContainsKey(B + '>' + A) then M.Add(B);
      for var S in M do Done.AddOrSetValue(S, True);
      if M.Count < 2 then Continue;
      G.Members:= M.ToArray;
      G.HasIntf:= False;
      for var X in G.Members do
        for var Y in G.Members do
          if (X <> Y) and Edges[X].Contains(Y + CIntfMark) then G.HasIntf:= True;
      FPredicted.Add(G);
    end;
  finally
    M.Free;
    Queue.Free;
    Done.Free;
    Reach.Free;
    Edges.Free;
  end;
end;

function TCyclePlanner.GroupHasIntf(const pComp: TArray<string>): Boolean;
begin
  for var A in pComp do
    for var B in pComp do
      if (A <> B) and FGraph.IntfEdges.ContainsKey(A + '->' + B) then Exit(True);
  Result:= False;
end;

function TCyclePlanner.ExpectedOutput(pSelf: Integer): TArray<string>;
var
  L: TList<string>;
  N: Integer;
begin
  L:= TList<string>.Create;
  try
    N:= FSccs.Count - 1 + FPredicted.Count;
    if N = 0 then L.Add(CCycleNone)
    else
    begin
      L.Add(Format(CCycleCountFmt, [N]));
      // Prediction order = SCC discovery order (the order DoCycles prints): a
      // group never moves. Untouched SCCs keep their FSccs index; the groups the
      // edited SCC splits into take that SCC's place.
      for var I:= 0 to FSccs.Count - 1 do
        if I <> pSelf then
          L.Add(Format(CCycleGroupFmt, [Length(FSccs[I]), string.Join(' <-> ', FSccs[I]),
            (if GroupHasIntf(FSccs[I]) then CCycleTagInterface else CCycleTagImplOnly)]))
        else
          for var G in FPredicted do
            L.Add(Format(CCycleGroupFmt, [Length(G.Members), string.Join(' <-> ', G.Members),
              (if G.HasIntf then CCycleTagInterface else CCycleTagImplOnly)]));
      L.Add(CCycleEdgesHint);
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TCyclePlanner.RemainingNeeds(const pFrom, pTo: string; pAll: Boolean): TArray<TNeed>;
var
  L   : TList<TNeed>;
  Seen: TDictionary<Int64, Boolean>;
  Fid : Int64;
begin
  L   := TList<TNeed>.Create;
  Seen:= TDictionary<Int64, Boolean>.Create;
  try
    Fid:= FidOfStem(pFrom);
    for var N in NeedsOf(Fid) do
    begin
      if (N.OwnerStem <> pTo) or Seen.ContainsKey(N.Owner.Id) then Continue;
      if (not pAll) and (IsMovedFor(N.Owner, Fid) or IsDeleted(Fid, N.Line)) then Continue;
      Seen.Add(N.Owner.Id, True);
      L.Add(N);
    end;
    Result:= L.ToArray;
  finally
    Seen.Free;
    L.Free;
  end;
end;

function TCyclePlanner.EvaluateEdge(const pFrom, pTo: string; const pNeeds: TArray<TNeed>; pViaBase: Boolean): TEdgeEval;
var
  Snap : Integer;
  Why  : string;
  Stems: TArray<string>;
begin
  Result:= Default(TEdgeEval);
  Result.FromStem:= pFrom;
  Result.ToStem  := pTo;
  Result.Needs   := pNeeds;
  Result.Surface := BuildEdgeSurface(Self, FidOfStem(pFrom), pTo);
  Result.ViaBase := pViaBase;
  Result.Movable := Length(pNeeds) > 0;
  if not Result.Movable then Result.Why:= 'the index resolved no symbol for this edge';
  Snap:= FOrder.Count;
  for var N in pNeeds do
    if not TryAdd(N.Owner, BaseCut(N.Owner, pFrom, pViaBase), Why) then
    begin
      Result.Movable:= False;
      Result.Why    := Format('`%s` (%s): %s', [N.Owner.Name, N.Owner.Kind.ToText, Why]);
      if (N.Owner.Kind in [skProcedure, skFunction]) and SigTypesOutsideScc(
        SignatureTypes(Self, N.Owner.FileId, N.Owner.StartLine, N.Owner.Signature), Stems) then
      begin
        for var I:= 0 to High(Stems) do Stems[I]:= UnitNameOfStem(Stems[I]);
        Result.Why:= Format('`%s` (%s) -- a routine; could be called through a pointer declared in %s (not automated)',
          [N.Owner.Name, N.Owner.Kind.ToText, QuoteList(Stems)]);
      end;
      Break;
    end;
  Result.Cost:= FOrder.Count - Snap;
  Rollback(Snap);
end;

{ B4-f: the cut a class need of an implementation edge is judged against -- the consumer's file, so
  BuildBase runs (F5 / B4 site rules over that unit); nil for any other need, or without pViaBase. }
function TCyclePlanner.BaseCut(const pSym: TSymbol; const pFrom: string; pViaBase: Boolean): TArray<Int64>;
begin
  Result:= nil;
  if pViaBase and (pSym.Kind = skClass) then Result:= [FidOfStem(pFrom)];
end;

{ B4-f: every implementation edge no recipe cut, whose needs include a class, is evaluated again with the
  class handed over through a base class (BuildBase, cut = the consumer). Movable -> crMoveGlobals,
  ViaBase (ranked after R2 by EvalRank); else the edge keeps its earlier reason, and the base-class
  refusal is appended when it names a site. }
procedure TCyclePlanner.PlanBaseHandOver(pEvals: TList<TEdgeEval>);
begin
  for var I:= 0 to pEvals.Count - 1 do
  begin
    var Ev:= pEvals[I];
    if Ev.Recipe <> crNone then Continue;
    var HasClass:= False;
    for var N in Ev.Needs do
      if N.Owner.Kind = skClass then HasClass:= True;
    if not HasClass then Continue;
    var Base:= EvaluateEdge(Ev.FromStem, Ev.ToStem, Ev.Needs, True);
    if Base.Movable then
    begin
      Base.Recipe:= crMoveGlobals;
      pEvals[I]  := Base;
    end
    else if ContainsStr(Base.Why, 'base-class') then
    begin
      Ev.Why:= Ev.Why + '; through a base class: ' + Base.Why;
      pEvals[I]:= Ev;
    end;
  end;
end;
{ ---------------------------------------------------------------------------
  rendering
  --------------------------------------------------------------------------- }

procedure TCyclePlanner.Emit(const pText: string);
begin
  FOut.Add(pText);
end;

procedure TCyclePlanner.EmitFmt(const pFmt: string; const pArgs: array of const);
begin
  FOut.Add(Format(pFmt, pArgs));
end;

procedure TCyclePlanner.EmitBlock(const pFence: string; const pLines: TArray<string>);
begin
  Emit(pFence);
  for var S in pLines do Emit(S);
  Emit(CCodeFence);
end;

function TCyclePlanner.MemberNames: string;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var S in FComp do L.Add(UnitNameOfStem(S));
    L.Sort;
    Result:= QuoteList(L.ToArray);
  finally
    L.Free;
  end;
end;

function TCyclePlanner.ReindexCommand: string;
begin
  if FProjectFile <> '' then
    Result:= Format('drag-lint index --project "%s" --db "%s"', [FProjectFile, FDbPath])
  else
    Result:= Format('drag-lint index "%s" --db "%s"',
      [ExcludeTrailingPathDelimiter(ExtractFilePath(PathOf(FidOfStem(FComp[0])))), FDbPath]);
end;

function TCyclePlanner.CyclesCommand(pPlan: Boolean): string;
begin
  Result:= Format('drag-lint cycles --db "%s"', [FDbPath]) + (if pPlan then ' --plan' else '');
end;

procedure TCyclePlanner.RenderHeader;
begin
  Emit('# Cycle refactoring playbook');
  Emit('');
  Emit('Generated by `drag-lint cycles --plan`. Each cycle below is a mechanical');
  Emit('procedure: which declarations move, into which new unit, which uses clauses');
  Emit('change, and the exact text of every edit. Line numbers are those of the files');
  Emit('AS THEY ARE NOW, before any edit. The index can miss a reference (e.g. a `set`');
  Emit('type), so each procedure ends with a compile, a re-check, and what to do about');
  Emit('each error the compile can report. Fix ONE cycle, then re-run');
  Emit('`drag-lint cycles --plan`: after the first edit, the line numbers given for the');
  Emit('other cycles are stale.');
  Emit('');
end;

procedure TCyclePlanner.RenderFiles;
begin
  Emit('Files:');
  for var A in FComp do
  begin
    var P: string:= '';
    FGraph.UnitFile.TryGetValue(A, P);
    EmitFmt('- `%s` -> `%s`', [A, P]);
  end;
  for var A in FComp do
    for var B in FComp do
      if (A <> B) and FGraph.Adj[A].Contains(B) and (LayerOfPath(PathOf(FidOfStem(A))) = 'COMMON') and
        MatchText(LayerOfPath(PathOf(FidOfStem(B))), ['CLIENT', 'SERVER']) then
        EmitFmt('- Note: `%s` (COMMON) uses `%s` (%s) -- a layering inversion. The steps below cut the ' +
          'cycle; that edge should also go, by declaring in COMMON an interface that `%s` implements.',
          [A, B, LayerOfPath(PathOf(FidOfStem(B))), B]);
  Emit('');
end;

procedure TCyclePlanner.RenderIntfWhy;
var
  Seen: TDictionary<Int64, Boolean>;
begin
  Emit('### Why it cycles');
  Seen:= TDictionary<Int64, Boolean>.Create;
  try
    for var A in FComp do
      for var B in FComp do
      begin
        if (A = B) or not FGraph.IntfEdges.ContainsKey(A + '->' + B) then Continue;
        var F:= GetFile(FidOfStem(A));
        Seen.Clear;
        for var N in NeedsOf(F.Fid) do
        begin
          if (N.Sect <> scIntf) or (N.OwnerStem <> B) or Seen.ContainsKey(N.Owner.Id) then Continue;
          Seen.Add(N.Owner.Id, True);
          EmitFmt('- `%s` interface uses `%s` (%s) at `%s:%d`; declared in `%s:%d`.',
            [A, N.Owner.Name, N.Owner.Kind.ToText, ExtractFileName(F.Path), N.Line,
             ExtractFileName(PathOf(N.Owner.FileId)), N.Owner.StartLine]);
        end;
        if Seen.Count = 0 then
          EmitFmt('- `%s` interface uses `%s` but the index could not resolve the symbol (likely a ' +
            '`set` type). **Open `%s` and find what its interface uses from `%s` by hand.**',
            [A, B, ExtractFileName(F.Path), B]);
      end;
  finally
    Seen.Free;
  end;
  Emit('');
end;

procedure TCyclePlanner.RenderImplWhy;
var
  Seen: TDictionary<string, Boolean>;
begin
  Emit('### Why it cycles (implementation-section edges)');
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for var A in FComp do
      for var B in FComp do
      begin
        if (A = B) or not FGraph.Adj[A].Contains(B) then Continue;
        var F:= GetFile(FidOfStem(A));
        EmitFmt('- `%s` uses `%s` in its **implementation** section (`%s`) via:', [A, B, ExtractFileName(F.Path)]);
        Seen.Clear;
        for var N in NeedsOf(F.Fid) do
        begin
          if (N.Sect <> scImpl) or (N.OwnerStem <> B) or Seen.ContainsKey(LowerCase(N.RefName)) then Continue;
          Seen.Add(LowerCase(N.RefName), True);
          EmitFmt('    - line %d: `%s`  [%s]  -> declared in `%s`', [N.Line, N.RefName, N.RefKind.ToText, B]);
        end;
        if Seen.Count = 0 then
          EmitFmt('    - (no specific symbol resolved -- index gap, e.g. a `set` type; open `%s` and ' +
            'scan its implementation uses of `%s` by hand)', [ExtractFileName(F.Path), B]);
      end;
  finally
    Seen.Free;
  end;
  Emit('');
end;

function TCyclePlanner.KindLabel(const pItem: TMoveItem): string;
begin
  case pItem.Sym.Kind of
    skEnum     : Result:= 'enum';
    skTypeAlias: Result:= 'type';
    skInterface: Result:= 'interface type';
    skConstDecl: Result:= 'constant';
    skVarDecl  : Result:= 'global variable';
    skRecord   : Result:= if Length(pItem.Bodies) > 0 then 'record with methods' else 'record';
    skClass    : Result:= if Length(pItem.Bodies) > 0 then 'class with methods' else 'class';
  else
    Result:= pItem.Sym.Kind.ToText;
  end;
end;

procedure TCyclePlanner.RenderConsumers(const pItem: TMoveItem);
var
  L: TList<TConsumer>;
begin
  if not FConsumers.TryGetValue(pItem.Sym.Id, L) then
  begin
    { a companion pulled in only by another moved declaration has no consumer of its own }
    var By: string;
    if FPulledBy.TryGetValue(pItem.Sym.Id, By) then EmitFmt('   - Used by: only the moved %s', [By]);
    Exit;
  end;
  EmitFmt('   - Used by (each needs `%s` in the uses clause of that section; the edit step does it):',
    [FLeafName[pItem.Stem]]);
  for var C in L do
    EmitFmt('     - `%s` %s (first use: line %d)', [ExtractFileName(PathOf(C.Fid)), SectLabel(C.Sect), C.Line]);
end;

procedure TCyclePlanner.RenderBaseRecipe(const pItem: TMoveItem);
var
  Names: TList<string>;
  Lines: TList<Integer>;
begin
  EmitFmt('   - Recipe: **extract a base class** and keep `%s` where it is. Why: its method bodies use %s, ' +
    'which live in units of this cycle; moving the class would mean moving those bodies (lines %s) ' +
    'AND everything they use.', [pItem.Sym.Name, QuoteList(pItem.Drags), RangeText(pItem.Bodies)]);
  Names:= TList<string>.Create;
  Lines:= TList<Integer>.Create;
  try
    for var M in pItem.BaseMembers do Names.Add(M.Sym.Name);
    EmitFmt('   - New class `%s` in `%s`%s carries exactly what the units below use: %s.',
      [pItem.BaseName, FLeafName[pItem.Stem],
       (if pItem.BaseAncestor <> '' then Format(' (inheriting `%s`, which is declared outside this cycle)', [pItem.BaseAncestor]) else ''),
       (if Names.Count > 0 then QuoteList(Names.ToArray) else 'nothing (an empty base)')]);
    EmitFmt('   - `%s` stays in `%s` and becomes `%s`; the members above are deleted from it.',
      [pItem.Sym.Name, ExtractFileName(PathOf(pItem.Sym.FileId)), Trim(CodePart(pItem.HeaderNew))]);
    for var Fid in pItem.CutFids do
    begin
      Lines.Clear;
      for var S in pItem.Switches do
        if S.Fid = Fid then Lines.Add(S.Line);
      var Nums:= TList<string>.Create;
      try
        for var N in SortedInts(Lines) do Nums.Add(IntToStr(N));
        EmitFmt('   - Units that switch to `%s` (the name is replaced on these lines): `%s` lines %s.',
          [pItem.BaseName, ExtractFileName(PathOf(Fid)), string.Join(', ', Nums.ToArray)]);
      finally
        Nums.Free;
      end;
    end;
  finally
    Lines.Free;
    Names.Free;
  end;
end;

procedure TCyclePlanner.RenderOneMove(pNo: Integer; const pItem: TMoveItem);
var
  FileName: string;
begin
  FileName:= ExtractFileName(PathOf(pItem.Sym.FileId));
  EmitFmt('%d. `%s` -- **%s**, declared at `%s` lines %d-%d%s.', [pNo, pItem.Sym.Name, KindLabel(pItem),
    FileName, pItem.Decl.First, pItem.Decl.Last,
    (if Length(pItem.Bodies) > 0 then Format('; method bodies at `%s` lines %s', [FileName, RangeText(pItem.Bodies)]) else '')]);
  case pItem.Kind of
    mvDecl:
      EmitFmt('   - Recipe: %s %s has no code of its own -- move the declaration, unchanged, into `%s`.',
        [(if CharInSet(KindLabel(pItem)[1], ['a', 'e', 'i', 'o', 'u']) then 'an' else 'a'), KindLabel(pItem), FLeafName[pItem.Stem]]);
    mvWithBodies:
      EmitFmt('   - Recipe: **move the whole %s**: its declaration AND its method bodies (lines %s) go ' +
        'into `%s` (the bodies into its implementation section). Why: the bodies use nothing else from ' +
        'this cycle, so they can travel with it.', [KindLabel(pItem), RangeText(pItem.Bodies), FLeafName[pItem.Stem]]);
    mvBase:
      RenderBaseRecipe(pItem);
  end;
  RenderConsumers(pItem);
end;

procedure TCyclePlanner.RenderManual;
begin
  if FManual.Count = 0 then Exit;
  Emit('');
  Emit('**MANUAL -- not mechanical.** These symbols cannot be moved by the recipes above; their ' +
    'edge stays until you cut it by hand:');
  for var M in FManual do
    EmitFmt('- `%s` (%s, `%s` line %d): %s.', [M.Sym.Name, M.Sym.Kind.ToText,
      ExtractFileName(PathOf(M.Sym.FileId)), M.Sym.StartLine, M.Reason]);
end;

procedure TCyclePlanner.RenderMoves(pStep: Integer);
var
  No: Integer;
begin
  EmitFmt('### Step %d: what moves where', [pStep]);
  No:= 0;
  for var Id in FOrder do
  begin
    Inc(No);
    RenderOneMove(No, FItems[Id]);
  end;
  if FOrder.Count = 0 then Emit('Nothing can be moved mechanically.');
  RenderManual;
  Emit('');
end;

procedure TCyclePlanner.RenderDecisions(pStep: Integer);
begin
  EmitFmt('### Step %d: uses clauses -- keep, move or remove the old unit', [pStep]);
  Emit('For each unit of the cycle that uses a unit whose declarations move. A unit can be removed ' +
    'from a section only when nothing else from it is used there.');
  for var D in FDecisions do
  begin
    var Who:= Format('- `%s` / `%s`: ', [ExtractFileName(PathOf(D.Fid)), UnitNameOfStem(D.PartnerStem)]);
    case D.Verdict of
      uvKeep:
        EmitFmt('%s**keep** it in the %s uses; that section still uses %s.', [Who, SectLabel(D.Sect), D.Still]);
      uvKeepUnseen:
        EmitFmt('%s**keep** it in the %s uses (the index saw no symbol from it there -- do not touch it).',
          [Who, SectLabel(D.Sect)]);
      uvMove:
        EmitFmt('%sthe interface no longer needs it; the implementation still does (%s) -> **move** it ' +
          'from the interface uses to the implementation uses.', [Who, D.Still]);
      uvRemove:
        EmitFmt('%snothing from it is used there any more -> **remove** it from the %s uses.',
          [Who, SectLabel(D.Sect)]);
    end;
  end;
  if FDecisions.Count = 0 then Emit('- (no uses entry between units of this cycle changes)');
  Emit('');
end;

function TCyclePlanner.BaseClassText(const pItem: TMoveItem): TArray<string>;
var
  L     : TList<string>;
  F     : TPlanFile;
  Ind   : string;
  Header: Boolean;
begin
  F  := GetFile(pItem.Sym.FileId);
  Ind:= pItem.BaseIndent;
  L  := TList<string>.Create;
  try
    L.Add(Ind + '/// <summary>Base class of <c>' + pItem.Sym.Name + '</c>: the members that units');
    L.Add(Ind + '/// outside <c>' + F.UnitName + '</c> use, extracted by drag-lint cycles --plan');
    L.Add(Ind + '/// so those units can depend on this leaf unit instead.</summary>');
    L.Add(Ind + pItem.BaseName + ' = class' + (if pItem.BaseAncestor <> '' then '(' + pItem.BaseAncestor + ')' else ''));
    for var Vis in TArray<string>.Create('protected', 'public', 'published') do
    begin
      Header:= False;
      for var M in pItem.BaseMembers do
      begin
        var MVis:= if M.Sym.Kind = skField then 'protected' else LowerCase(Trim(M.Sym.Modifiers));
        if not MatchText(MVis, ['public', 'published']) then MVis:= 'protected';
        if MVis <> Vis then Continue;
        if not Header then L.Add(Ind + Vis);
        Header:= True;
        var Body:= SliceLines(F.Lines, M.Range);
        if M.Sym.Kind in [skMethod, skFunction, skProcedure] then
        begin
          var Code:= CodePart(Body[High(Body)]);
          Body[High(Body)]:= TrimRight(Code) + CAbstractTail + Copy(Body[High(Body)], Length(Code) + 1, MaxInt);
        end;
        L.AddRange(Body);
      end;
    end;
    L.Add(Ind + 'end;');
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ The uses entries a leaf of pStem needs in section pSect: the source unit's own
  entries of that section that are not members of the cycle, plus (interface)
  the units the moved declarations use. }
function TCyclePlanner.LeafEntries(const pStem: string; pSect: TSect): TArray<string>;
var
  Entries: TList<string>;
begin
  var P:= GetFile(FidOfStem(pStem));
  { R1 into an existing unit (J2): its signature types are declared there or are
    System built-ins -- it needs no new uses entry }
  if IsInversionStem(pStem) and (FInversion.LeafStem <> '') then Exit(nil);
  { R2: the units that declare the member types (PlanMemberInterface), nothing else }
  if IsInversionStem(pStem) and (FInversion.Recipe = crMemberInterface) then
  begin
    Result:= nil;
    if pSect = scIntf then Result:= FInversion.LeafUses;
    Exit;
  end;
  { T17b D2: the source may already use its leaf (a pass after Part A) -- a unit never
    goes into its own uses clause (F2092) }
  var Own: string;
  if not FLeafName.TryGetValue(pStem, Own) then Own:= '';
  Entries:= TList<string>.Create;
  try
    for var U in SectionEntries(P, pSect) do
      if not FMembers.ContainsKey(LowerCase(U.UnitName)) and not SameText(U.UnitName, Own) then
        Entries.Add(EntryText(P, U));
    if (pSect = scIntf) and FLeafDeps.ContainsKey(pStem) then
      for var S in FLeafDeps[pStem] do
        if not SameText(S, Own) then AddUnique(Entries, S);
    Result:= Entries.ToArray;
  finally
    Entries.Free;
  end;
end;

{ The interface text of everything that moves out of pStem, each item led by a
  blank line and, when it changes, its block keyword; pBodies receives the
  method-body ranges of the items that move with their bodies. }
function TCyclePlanner.LeafDeclLines(const pStem: string; pBodies: TList<TLineRange>): TArray<string>;
var
  L      : TList<string>;
  Items  : TList<TMoveItem>;
  Keyword: string;
begin
  var P:= GetFile(FidOfStem(pStem));
  L    := TList<string>.Create;
  Items:= TList<TMoveItem>.Create;
  try
    { SOURCE order, not closure order: a variable is added before the type it
      needs, and Delphi requires the type to be declared first }
    for var Id in FOrder do
      if FItems[Id].Stem = pStem then Items.Add(FItems[Id]);
    Items.Sort(TComparer<TMoveItem>.Construct(
      function(const pLeft, pRight: TMoveItem): Integer
      begin
        Result:= pLeft.Decl.First - pRight.Decl.First;
      end));
    Keyword:= '';
    for var Item in Items do
    begin
      var KW:= if Item.Kind = mvBase then 'type' else Item.Keyword;
      L.Add('');
      if KW <> Keyword then L.Add(KW);
      Keyword:= KW;
      if Item.Kind = mvBase then L.AddRange(BaseClassText(Item))
      else if Item.SameLine then
      begin
        { W6 C6: the leaf's own keyword line opens the block; the declaration loses the keyword }
        var Slice:= SliceLines(P.Lines, Item.Decl);
        var K    := Item.Sym.StartLine - Item.Decl.First;
        Slice[K]:= '  ' + TrimLeft(Copy(TrimLeft(Slice[K]), Length(Item.Keyword) + 1, MaxInt));
        L.AddRange(Slice);
      end
      else L.AddRange(SliceLines(P.Lines, Item.Decl));
      if Item.Kind = mvWithBodies then pBodies.AddRange(Item.Bodies);
    end;
    if IsInversionStem(pStem) then L.AddRange(InversionDeclLines(pStem));
    Result:= L.ToArray;
  finally
    Items.Free;
    L.Free;
  end;
end;

function TCyclePlanner.LeafUnitText(const pStem: string): TArray<string>;
var
  L      : TList<string>;
  P      : TPlanFile;
  Entries: TArray<string>;
  Bodies : TList<TLineRange>;
begin
  P     := GetFile(FidOfStem(pStem));
  L     := TList<string>.Create;
  Bodies:= TList<TLineRange>.Create;
  try
    L.Add('unit ' + FLeafName[pStem] + ';');
    L.Add('');
    if IsInversionStem(pStem) and (FInversion.Recipe = crMemberInterface) then
      L.Add(Format('// Created by `drag-lint cycles --plan`: the interface %s (%s) implements, extracted',
        [FInversion.ClassTypeName, P.UnitName]))
    else
      L.Add('// Created by `drag-lint cycles --plan`: declarations moved here from ' + P.UnitName);
    L.Add('// to break a circular unit dependency. This unit may use only units OUTSIDE');
    L.Add('// that cycle -- never ' + MemberNames.Replace('`', '') + '.');
    L.Add('');
    L.Add('interface');
    Entries:= LeafEntries(pStem, scIntf);
    if Length(Entries) > 0 then
    begin
      L.Add('');
      L.AddRange(FormatUses('', Entries, nil));
    end;
    L.AddRange(LeafDeclLines(pStem, Bodies));
    L.Add('');
    L.Add('implementation');
    if Bodies.Count > 0 then
    begin
      Entries:= LeafEntries(pStem, scImpl);
      if Length(Entries) > 0 then
      begin
        L.Add('');
        L.AddRange(FormatUses('', Entries, nil));
      end;
      for var R in Bodies do
      begin
        L.Add('');
        L.AddRange(SliceLines(P.Lines, R));
      end;
    end;
    L.Add('');
    L.Add('end.');
    Result:= L.ToArray;
  finally
    Bodies.Free;
    L.Free;
  end;
end;

procedure TCyclePlanner.RenderLeafUnits(pStep: Integer);
begin
  EmitFmt('### Step %d: create the new units', [pStep]);
  { E18 T4b: why a `<Source>.Untangle` that exists was passed over, and which
    existing leaves receive declarations instead of a new unit }
  for var D:= Low(TUntangleDecision) to High(TUntangleDecision) do
    for var Stem in LeafStems(D) do
      if FLeafInfo[Stem].Reason <> '' then EmitFmt('- Note: %s.', [FLeafInfo[Stem].Reason]);
  for var Stem in LeafStems(udExtend) do
    if IsInversionStem(Stem) and (FInversion.Recipe = crMemberInterface) then
      EmitFmt('- `%s` already exists (`%s`) and uses no unit of this cycle: it receives the interface `%s`. ' +
        'Do not create it again; the edit step lists the insert.', [FLeafName[Stem], FLeafPath[Stem],
        FInversion.IfaceName])
    else if IsInversionStem(Stem) then
      EmitFmt('- `%s` already exists (`%s`) and uses no unit of this cycle: it receives the procedural ' +
        'type and variable of `%s`. Do not create it again; the edit step lists the insert.',
        [FLeafName[Stem], FLeafPath[Stem], InversionNames])
    else
    EmitFmt('- `%s` already exists (`%s`) and uses no unit of this cycle: what moves out of `%s` goes ' +
      'into it. Do not create it again; the edit step lists the insert.', [FLeafName[Stem], FLeafPath[Stem],
      UnitNameOfStem(Stem)]);
  if Length(LeafStems(udCreate)) = 0 then
  begin
    Emit('No new unit is needed.');
    Emit('');
    Exit;
  end;
  EmitFmt('Each new unit may use only RTL / library units and other new `*%s` units -- never a ' +
    'unit of this cycle (%s). Create each file with EXACTLY this text:', [CLeafSuffix, MemberNames]);
  Emit('');
  for var Stem in LeafStems(udCreate) do
  begin
    EmitFmt('#### `%s` -> `%s`', [FLeafName[Stem], FLeafPath[Stem]]);
    EmitBlock(CPascalFence, LeafUnitText(Stem));
    if FProjectFid > 0 then
      EmitFmt('Register it in the project (the edit step spells out both edits): the .dpr uses clause ' +
        'gets `%s`; the .dproj lists it as `<DCCReference Include="%s"/>`.',
        [UsesEntryFor(GetFile(FProjectFid), Stem), ExtractFileName(FLeafPath[Stem])]);
    Emit('');
  end;
end;

procedure TCyclePlanner.RenderFileEdits(const pTitle: string; const pLines: TArray<string>;
  const pEdits: TArray<TFileEdit>; const pFence: string);
var
  No: Integer;
begin
  if Length(pEdits) = 0 then Exit;
  Emit(pTitle);
  No:= 0;
  for var E in pEdits do
  begin
    Inc(No);
    var Span:= if E.First = E.Last then Format('line %d', [E.First]) else Format('lines %d-%d', [E.First, E.Last]);
    case E.Kind of
      ekDelete:
        begin
          EmitFmt('E%d. Delete %s. Current text:', [No, Span]);
          EmitBlock(pFence, SliceLines(pLines, OneRange(E.First, E.Last)));
        end;
      ekReplace:
        begin
          EmitFmt('E%d. Replace %s. Current text:', [No, Span]);
          EmitBlock(pFence, SliceLines(pLines, OneRange(E.First, E.Last)));
          Emit('New text:');
          EmitBlock(pFence, E.NewLines);
        end;
      ekInsertAfter:
        begin
          EmitFmt('E%d. After line %d (`%s`), insert:', [No, E.First, Trim(LineAt(pLines, E.First))]);
          EmitBlock(pFence, E.NewLines);
        end;
      ekManual:
        EmitFmt('E%d. %s', [No, E.Note]);
    end;
  end;
  Emit('');
end;

procedure TCyclePlanner.RenderEdits(pStep: Integer);
begin
  EmitFmt('### Step %d: edit the existing files', [pStep]);
  Emit('Apply each file''s edits in the order listed. They run from the bottom of the file to the ' +
    'top, so the line numbers of the edits still to do do not move. "Current text" is what the lines ' +
    'say before the edit -- if it does not match, stop: the file changed since it was indexed.');
  Emit('');
  for var Fid in EditOrder do
  begin
    var F:= GetFile(Fid);
    RenderFileEdits(Format('#### `%s`  (`%s`)', [ExtractFileName(F.Path), F.Path]), F.Lines, EditsOf(Fid), CPascalFence);
  end;
  if FDprojEdits.Count = 0 then Exit;
  var Arr:= FDprojEdits.ToArray;
  TArray.Sort<TFileEdit>(Arr, TComparer<TFileEdit>.Construct(
    function(const pLeft, pRight: TFileEdit): Integer
    begin
      Result:= pRight.First - pLeft.First;
    end));
  RenderFileEdits(Format('#### `%s`  (`%s`)', [ExtractFileName(FProjectFile), FProjectFile]),
    ReadSourceLines(FProjectFile), Arr, CXmlFence);
end;

procedure TCyclePlanner.RenderCompileHelp;
begin
  Emit('#### If the compile fails');
  Emit('- `E2003 Undeclared identifier: ''X''` in file F at line N: the index missed a use of X. ' +
    'If X is listed in the "what moves where" step, add that step''s new unit to F''s uses clause ' +
    'of the section holding line N (interface above `implementation`, implementation below it). ' +
    'Otherwise X still lives in a unit you moved or removed in the uses step: add that unit back ' +
    'to the same section.');
  Emit('- `E2065 Unsatisfied forward or external declaration`: a class moved without its method ' +
    'bodies. Move the bodies listed for it as well.');
  Emit('- `E2010 Incompatible types: ''TX'' and ''TXBase''` or `E2033 Types of actual and formal ' +
    'var parameters must be identical`: a routine now takes or returns the base class. Cast at that ' +
    'line: `TX(value)`.');
  Emit('- `F2047 Circular unit reference`: a new unit names a unit of this cycle in its uses. ' +
    'Remove that entry -- the new units may use only what the "create the new units" step lists.');
  Emit('- `F1026 File not found`: a new unit''s file name must equal its unit name plus `.pas`.');
  Emit('');
end;

procedure TCyclePlanner.RenderChecklist(pSelf: Integer);
var
  No: Integer;

  procedure Item(const pText: string);
  begin
    Inc(No);
    EmitFmt('%d. [ ] %s', [No, pText]);
  end;

begin
  Emit('### Checklist');
  Emit('Tick each box in order. Do not skip the compile.');
  No:= 0;
  { IDE-9 run 2 (2026-09-23): a cheap model followed the plan 4/4 but saved the
    NEW units with LF endings -- the plan never said how to save them. Say it. }
  for var Stem in LeafStems(udCreate) do
    Item(Format('Create `%s` with the exact text given for `%s`. Save it as plain ASCII with ' +
      'Windows CRLF line endings, like the existing units.', [FLeafPath[Stem], FLeafName[Stem]]));
  for var Fid in EditOrder do
    if Length(EditsOf(Fid)) > 0 then
      Item(Format('Apply every edit listed for `%s`, in the order listed.', [ExtractFileName(PathOf(Fid))]));
  if FDprojEdits.Count > 0 then
    Item(Format('Apply every edit listed for `%s`.', [ExtractFileName(FProjectFile)]));
  if FProjectFile <> '' then
    Item(Format('Compile `%s` (RAD Studio: Project > Build; or `msbuild "%s" /t:Build` from a RAD ' +
      'Studio Command Prompt). Expect 0 errors; on an error see "If the compile fails" below, fix, ' +
      'and compile again.', [ExtractFileName(FProjectFile), FProjectFile]))
  else
    Item('Compile the project. Expect 0 errors; on an error see "If the compile fails" below.');
  Item(Format('Re-index: `%s`', [ReindexCommand]));
  Item(Format('Run `%s`. It must print exactly:', [CyclesCommand(False)]));
  EmitBlock(CTextFence, ExpectedOutput(pSelf));
  Emit('   The units inside a group may be listed in a different order. Lines starting with ' +
    '`(loaded`, `drag-lint: note:` or `  resolver:` are informational -- ignore them.');
  Emit('');
  RenderCompileHelp;
end;

procedure TCyclePlanner.RenderDone(pIntf: Boolean);
var
  Still: Boolean;
begin
  Still:= False;
  for var G in FPredicted do
    if G.HasIntf then Still:= True;
  Emit('### DONE');
  if pIntf then
    Emit('This plan (Part A) removes the INTERFACE-section coupling of this cycle. It is DONE when ' +
      'both hold: (1) the project compiles with 0 errors, and (2) `drag-lint cycles` prints exactly ' +
      'the output given in the last checklist item.')
  else
    EmitFmt('This plan cuts the edge `%s -> %s`, the cheapest edge of this cycle that can be cut ' +
      'mechanically. It is DONE when both hold: (1) the project compiles with 0 errors, and (2) ' +
      '`drag-lint cycles` prints exactly the output given in the last checklist item.',
      [FCutEdge.FromStem, FCutEdge.ToStem]);
  if FPredicted.Count = 0 then
    Emit('After it, these units form no cycle at all.')
  else if Still then
    Emit('After it, some of these units still use each other in their interfaces: the MANUAL ' +
      'items were not cut. Cut them by hand, or leave them.')
  else
    Emit('After it, these units still form a cycle, but only through IMPLEMENTATION uses. That is ' +
      'LEGAL Delphi: it compiles, and a change to one unit no longer forces the others'' ' +
      'interfaces to recompile. Removing it as well is optional (Part B).');
  Emit('');
end;

procedure TCyclePlanner.RenderRemedy;
begin
  Emit('The standard remedy: move the shared GLOBAL variables (and the plain types they need) into a ' +
    'leaf unit that both sides use; a routine can move only together with everything its body uses, ' +
    'or be handed over as a parameter / event instead of being called by name.');
end;

{ E18 T13: Part B's weighing of every remaining edge, shared by the Part B text and the Fix it
  block, so the edge the block names is the edge Part B prints. }
procedure TCyclePlanner.CollectPartB(const pEvals: TList<TEdgeEval>; const pTexts: TList<string>);
var
  Names: TList<string>;
begin
  Names:= TList<string>.Create;
  try
    for var G in FPredicted do
      for var A in G.Members do
        for var B in G.Members do
        begin
          if A = B then Continue;
          var Needs:= RemainingNeeds(A, B, False);
          if Length(Needs) = 0 then Continue;
          var Ev:= EvaluateEdge(A, B, Needs);
          if Ev.Movable then Ev.Recipe:= crMoveGlobals;
          Names.Clear;
          for var N in Needs do Names.Add(Format('%s (%s)', [N.Owner.Name, N.Owner.Kind.ToText]));
          pEvals.Add(Ev);
          pTexts.Add(QuoteList(Names.ToArray));
        end;
    { E18 T7 R3: the same recipes and order the re-run after Part A uses }
    PlanInversion(pEvals);
    PlanMemberHandOver(pEvals);
  finally
    Names.Free;
  end;
  FPartBBest:= Default(TEdgeEval);
  for var Ev in pEvals do
    if BetterCut(Ev, FPartBBest) then FPartBBest:= Ev;
  FPartBDone:= True;
end;

function TCyclePlanner.PartBBest: TEdgeEval;
var
  Evals: TList<TEdgeEval>;
  Texts: TList<string>;
begin
  if not FPartBDone then
  begin
    Evals:= TList<TEdgeEval>.Create;
    Texts:= TList<string>.Create;
    try
      CollectPartB(Evals, Texts);
    finally
      Texts.Free;
      Evals.Free;
    end;
  end;
  Result:= FPartBBest;
end;

procedure TCyclePlanner.RenderPartB;
var
  Evals: TList<TEdgeEval>;
  Texts: TList<string>;
begin
  Emit('### Part B (optional): remove the implementation-only cycle too');
  if FPredicted.Count = 0 then
  begin
    Emit('Nothing to do: after Part A no cycle remains among these units.');
    Emit('');
    Exit;
  end;
  Emit('After Part A these units still use each other through these edges (predicted):');
  Evals:= TList<TEdgeEval>.Create;
  Texts:= TList<string>.Create;
  try
    CollectPartB(Evals, Texts);
    for var I:= 0 to Evals.Count - 1 do
    begin
      var Ev:= Evals[I];
      EmitFmt('- `%s -> %s`: %s -- %s', [Ev.FromStem, Ev.ToStem, Texts[I],
        (if Ev.Recipe = crMoveGlobals then 'mechanical: these can move into a new leaf unit'
         else if Ev.Recipe <> crNone then 'mechanical: recipe: ' + RecipeLabel(Ev.Recipe)
         else 'not mechanical: ' + Ev.Why)]);
    end;
  finally
    Texts.Free;
    Evals.Free;
  end;
  var Best:= FPartBBest;
  Emit('');
  RenderRemedy;
  if Best.FromStem <> '' then
    EmitFmt('To do it: finish Part A (every checklist item), then run `%s` again. It prints Part B as ' +
      'the same kind of numbered, mechanical steps, with line numbers for the edited files. The edge ' +
      'it will cut is `%s -> %s`. Recipe: %s.', [CyclesCommand(True), Best.FromStem, Best.ToStem,
      RecipeLabel(Best.Recipe)])
  else
    EmitFmt('No edge above can be cut mechanically as the units stand before Part A. Part A changes what ' +
      'these edges carry, so after it run `%s` again: it weighs move globals, routine-call inversion and ' +
      'member hand-over against the edited units. Leaving the implementation-only cycle is acceptable.',
      [CyclesCommand(True)]);
  Emit('');
end;

function FixCommandText(const pProject, pDbPath: string; pCycle: Integer; pApply: Boolean): string;
begin
  Result:= Format('drag-lint cycles --fix --project %s --db "%s" --cycle %d',
    [(if pProject <> '' then '"' + pProject + '"' else '<your.dproj>'), pDbPath, pCycle]) +
    (if pApply then ' --apply' else '');
end;

function TCyclePlanner.FixCommand(pCycle: Integer; pApply: Boolean): string;
begin
  Result:= FixCommandText(FFixProject, FDbPath, pCycle, pApply);
end;

function TCyclePlanner.FixHintOf(const pPlan: TCycleFixPlan): TCycleFixHint;
const
  CRecipeId: array[TCutRecipe] of string = ('', 'move-globals', 'routine-inversion', 'member-interface');

  function EdgeOf(const pEv: TEdgeEval; pChosen: Boolean): TFixEdge;
  begin
    Result.FromUnit:= pEv.FromStem;
    Result.ToUnit  := pEv.ToStem;
    Result.Recipe  := CRecipeId[pEv.Recipe];
    Result.Chosen  := pChosen;
  end;

begin
  Result:= Default(TCycleFixHint);
  Result.CycleIndex:= pPlan.CycleIndex;
  Result.Part      := pPlan.Part;
  Result.Available := pPlan.Verdict = cvMechanical;
  Result.DryRun    := FixCommand(pPlan.CycleIndex, False);
  Result.Apply     := FixCommand(pPlan.CycleIndex, True);
  if Length(pPlan.Refusals) > 0 then
    Result.Reason:= pPlan.Refusals[0].Kind + ': ' + pPlan.Refusals[0].Reason;
  if pPlan.HasIntf then
  begin
    var Best:= PartBBest;
    Result.HasFollowup:= Best.FromStem <> '';
    if Result.HasFollowup then Result.Followup:= EdgeOf(Best, True);
    Exit;
  end;
  { the chosen edge first, then every other edge that has a recipe, in the planner's order }
  var L:= TList<TFixEdge>.Create;
  try
    if pPlan.CutEdge.FromStem <> '' then L.Add(EdgeOf(pPlan.CutEdge, True));
    for var Ev in pPlan.Evals do
      if (Ev.Recipe <> crNone) and not ((Ev.FromStem = pPlan.CutEdge.FromStem) and (Ev.ToStem = pPlan.CutEdge.ToStem)) then
        L.Add(EdgeOf(Ev, False));
    Result.Edges:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TCyclePlanner.RenderFixIt(const pPlan: TCycleFixPlan);
const
  CRecipeText: array[TCutRecipe] of string = ('', 'move globals', 'routine-call inversion',
    'member hand-over through an extracted interface');

  function EdgeText(const pEdge: TFixEdge): string;
  begin
    Result:= Format('%s -> %s (%s)', [pEdge.FromUnit, pEdge.ToUnit,
      (if pEdge.Recipe = 'routine-inversion' then CRecipeText[crRoutineInversion]
       else if pEdge.Recipe = 'member-interface' then CRecipeText[crMemberInterface]
       else CRecipeText[crMoveGlobals])]);
  end;

begin
  var H:= FixHintOf(pPlan);
  if not H.Available then
  begin
    { the kind only: the full reason is already printed in the refusing step above, and is in the JSON }
    EmitFmt('Fix it: not available -- %s', [(if Length(pPlan.Refusals) > 0 then pPlan.Refusals[0].Kind else 'refused')]);
    Emit('');
    Exit;
  end;
  Emit('Fix it (mechanical, compile-gated):');
  EmitFmt('  dry run : %s', [H.DryRun]);
  EmitFmt('  apply   : %s', [H.Apply]);
  if H.Part = 'A' then
  begin
    { C9: name the Part A recipes the plan really uses -- a base-class cut moves no global }
    var Moves:= False;
    var Bases:= False;
    for var It in pPlan.Items do
      if It.Kind = mvBase then Bases:= True
      else if It.Kind in [mvDecl, mvWithBodies] then Moves:= True;
    EmitFmt('  cuts    : the INTERFACE coupling of this cycle (Part A: %s)',
      [(if Bases and Moves then 'move globals into new leaf units and extract base classes there'
        else if Bases then 'extract base classes into new leaf units'
        else 'move globals into new leaf units')]);
    if H.HasFollowup then
      EmitFmt('  then    : Part B, optional, after Part A: %s', [EdgeText(H.Followup)]);
  end
  else
    for var E in H.Edges do
      EmitFmt('  cuts    : %s%s', [EdgeText(E), (if E.Chosen then ' (chosen)' else '')]);
  Emit('  requires: the project builds with 0 errors before the fix (the dry run checks this)');
  Emit('');
end;
procedure TCyclePlanner.PlanIntfCycle;
var
  Seeds: TList<TNeed>;
  Cut  : TObjectDictionary<Int64, TList<Int64>>;
  Why  : string;
begin
  Seeds:= TList<TNeed>.Create;
  Cut  := TObjectDictionary<Int64, TList<Int64>>.Create([doOwnsValues]);
  try
    { every interface edge of the cycle is cut: its symbols are the seeds, and
      the units whose interface names a class are its base-class consumers }
    for var A in FComp do
      for var B in FComp do
      begin
        if (A = B) or not FGraph.IntfEdges.ContainsKey(A + '->' + B) then Continue;
        for var N in NeedsOf(FidOfStem(A)) do
        begin
          if (N.Sect <> scIntf) or (N.OwnerStem <> B) then Continue;
          if not Cut.ContainsKey(N.Owner.Id) then
          begin
            Cut.Add(N.Owner.Id, TList<Int64>.Create);
            Seeds.Add(N);
          end;
          if not Cut[N.Owner.Id].Contains(FidOfStem(A)) then Cut[N.Owner.Id].Add(FidOfStem(A));
        end;
      end;
    for var N in Seeds do
    begin
      var Snap:= FOrder.Count;
      if TryAdd(N.Owner, Cut[N.Owner.Id].ToArray, Why) then Continue;
      Rollback(Snap);
      var M:= Classify(N.Owner, Cut[N.Owner.Id].ToArray);
      M.Reason:= Why;
      FManual.Add(M);
    end;
  finally
    Cut.Free;
    Seeds.Free;
  end;
  Materialize;
end;

{ E14: the Status line counts the uses between the cycle's units instead of echoing "interface":
  every use in an INTERFACE clause = an all-interface loop the compiler refuses; otherwise N of M. }
function TCyclePlanner.IntfStatusLine: string;
var
  NIntf, NAll: Integer;
begin
  NIntf:= 0;
  NAll:= 0;
  for var A in FComp do
    for var B in FComp do
    begin
      if (A = B) or not FGraph.Adj.ContainsKey(A) or not FGraph.Adj[A].Contains(B) then Continue;
      Inc(NAll);
      if FGraph.IntfEdges.ContainsKey(A + '->' + B) then Inc(NIntf);
    end;
  if (NAll > 0) and (NIntf = NAll) then
    Result:= Format('Status: **interface cycle** -- all %d uses between the units of this cycle are in INTERFACE ' +
      'uses clauses (the compiler refuses this loop).', [NAll])
  else
    Result:= Format('Status: **interface coupling** -- %d of %d uses between the units of this cycle are in ' +
      'INTERFACE uses clauses.', [NIntf, NAll]);
end;
procedure TCyclePlanner.RenderIntfCycle(const pPlan: TCycleFixPlan);
begin
  Emit(IntfStatusLine);
  Emit('');
  RenderFiles;
  RenderIntfWhy;
  Emit('### Goal');
  Emit('Part A (steps 1-4, required) removes the INTERFACE coupling: each symbol above -- and ' +
    'whatever it needs -- moves into a new leaf unit, or its class gets a base class there, so no ' +
    'unit of the cycle needs another one in its interface any more. Part B (optional) removes the ' +
    'implementation-only cycle that may remain.');
  Emit('');
  RenderDone(True);
  RenderMoves(CStepMoves);
  RenderDecisions(CStepUses);
  RenderLeafUnits(CStepCreate);
  RenderEdits(CStepEdit);
  RenderChecklist(pPlan.CycleIndex - 1);
  RenderPartB;
end;

{ E18 T7 R3: every edge of the cycle with the recipe that applies to it, or the
  reason none does; the cut edge is marked. }
procedure TCyclePlanner.RenderEdgeChoices(const pEvals: TArray<TEdgeEval>);
begin
  Emit('');
  Emit('Every edge of this cycle, weighed in this order: move globals, routine-call inversion, member ' +
    'hand-over; within one recipe the edge whose surface has the fewest members, then the fewest references, ' +
    'wins. One edge is cut per run:');
  for var Ev in pEvals do
    if Ev.Recipe = crNone then
      EmitFmt('- `%s -> %s`: not mechanical: %s', [Ev.FromStem, Ev.ToStem, Ev.Why])
    else
      EmitFmt('- `%s -> %s`: recipe: %s%s', [Ev.FromStem, Ev.ToStem, RecipeLabel(Ev.Recipe),
        (if (Ev.FromStem = FCutEdge.FromStem) and (Ev.ToStem = FCutEdge.ToStem) then ' -- **cut by this plan**'
         else ' -- also possible, not cut by this plan')]);
end;

procedure TCyclePlanner.RenderNoMechanicalCut(const pEvals: TArray<TEdgeEval>);
begin
  Emit('No edge of this cycle can be cut mechanically:');
  for var Ev in pEvals do
    EmitFmt('- `%s -> %s`: %s', [Ev.FromStem, Ev.ToStem, Ev.Why]);
  Emit('');
  RenderRemedy;
  Emit('This cycle is legal Delphi and compiles; leaving it is acceptable.');
  Emit('');
end;

function TCyclePlanner.PlanImplCycle: TArray<TEdgeEval>;
var
  Evals: TList<TEdgeEval>;
  Why  : string;
begin
  Evals:= TList<TEdgeEval>.Create;
  try
    for var A in FComp do
      for var B in FComp do
        if (A <> B) and FGraph.Adj[A].Contains(B) then
        begin
          var Ev:= EvaluateEdge(A, B, RemainingNeeds(A, B, True));
          if Ev.Movable then Ev.Recipe:= crMoveGlobals;
          Evals.Add(Ev);
        end;
    { E18 T7 R3: every edge that cannot MOVE is tried with R1 (one routine), then
      R2 (`is` / `as` + member reads); each edge keeps its recipe or its reason,
      and the best by BetterCut is the one cut of this run }
    PlanInversion(Evals);
    PlanMemberHandOver(Evals);
    PlanBaseHandOver(Evals);
    for var Ev in Evals do
      if BetterCut(Ev, FCutEdge) then FCutEdge:= Ev;
    if FCutEdge.Recipe in [crRoutineInversion, crMemberInterface] then FInversion:= FCutEdge.Steps;
    Result:= Evals.ToArray;
  finally
    Evals.Free;
  end;
  if FCutEdge.FromStem = '' then Exit;
  if FCutEdge.Recipe in [crRoutineInversion, crMemberInterface] then
  begin
    { B3: what moves with the routines goes into the same leaf (ProbeInversionMoves proved it can) }
    for var Id in FInversion.MoveIds do TryAdd(FStore.GetSymbolById(Id), nil, Why);
    MaterializeInversion;
    Exit;
  end;
  for var N in FCutEdge.Needs do TryAdd(N.Owner, BaseCut(N.Owner, FCutEdge.FromStem, FCutEdge.ViaBase), Why);
  Materialize;
end;

const
  CMaxPtrSuffix = 99;  { W6 C2: the highest `FooPtr<N>` suffix tried }

{ The declaration at pSym as comparable text: comments dropped, white space collapsed, a leading
  `type` / `var` keyword dropped. }
function DeclarationText(const pLines: TArray<string>; const pSym: TSymbol): string;
begin
  Result:= '';
  for var L:= pSym.StartLine to Max(pSym.StartLine, pSym.EndLine) do Result:= Result + ' ' + CodePart(LineAt(pLines, L));
  Result:= Trim(TRegEx.Replace(Trim(TRegEx.Replace(Result, '\s+', ' ')), '^(type|var)\s+', '', [roIgnoreCase]));
end;

{ W6 C2: R2 into an existing leaf that already declares I<Class>Surface. The same code text (comments
  aside; the GUID is derived from leaf + name, so a repeated plan matches) is reused: nothing is
  inserted. A different declaration: the lowest free suffix (`I<Class>Surface2` ...) names the
  interface and the steps are planned again with it. No free suffix below 100: `duplicate-identifier`. }
procedure TCyclePlanner.SettleIfaceName(const pSurface: TEdgeSurface; const pLeaf: TUntangleLeaf;
  const pUnitScopes: TArray<string>; var pSteps: TRecipeSteps; var pRefusal: TRecipeRefusal);
var
  Clash: TSymbol;
begin
  var F:= GetFile(pLeaf.Fid);
  Clash:= Default(TSymbol);
  for var S in F.Syms do
    if SameText(S.Name, pSteps.IfaceName) then Clash:= S;
  if Clash.Id = 0 then Exit;
  var Mine:= '';
  for var T in pSteps.IfaceDecl do Mine:= Mine + ' ' + CodePart(T);
  if SameText(DeclarationText(F.Lines, Clash), Trim(TRegEx.Replace(Mine, '\s+', ' '))) then
  begin
    pSteps.ReuseDecl:= True;
    Exit;
  end;
  for var N:= 2 to CMaxPtrSuffix do
  begin
    var Name := Clash.Name + IntToStr(N);
    var Taken:= False;
    for var S in F.Syms do
      if SameText(S.Name, Name) then Taken:= True;
    if Taken then Continue;
    pSteps:= PlanMemberInterface(Self, FLibStore, pSurface, pLeaf.UnitName, pUnitScopes, pRefusal, Name);
    Exit;
  end;
  pRefusal.Kind  := 'duplicate-identifier';
  pRefusal.Reason:= Format('`%s` already declares `%s` (line %d) differently, and every suffix up to %d is taken',
    [pLeaf.UnitName, Clash.Name, Clash.StartLine, CMaxPtrSuffix]);
end;
{ W6 C2: R1 into an existing leaf that already declares the pointer's names. The same type and variable
  declarations (text equal) are reused: nothing is inserted, and the assignment is added only when the
  declaring unit does not make it already. Different declarations: the lowest free suffix (`FooPtr2`,
  `FooPtr3` ...) names the pointer, and the steps are planned again with it. No free suffix below 100:
  `duplicate-identifier`. }
procedure TCyclePlanner.SettleInversionNames(const pEv: TEdgeEval; const pLeaf: TUntangleLeaf; var pSteps: TRecipeSteps;
  var pRefusal: TRecipeRefusal);
var
  TypeSym, VarSym, Clash: TSymbol;
  HasType, HasVar       : Boolean;
begin
  var F:= GetFile(pLeaf.Fid);
  HasType:= False;
  HasVar := False;
  TypeSym:= Default(TSymbol);
  VarSym := Default(TSymbol);
  for var S in F.Syms do
    if SameText(S.Name, pSteps.PtrType) then
    begin
      TypeSym:= S;
      HasType:= True;
    end
    else if SameText(S.Name, pSteps.PtrVar) then
    begin
      VarSym:= S;
      HasVar:= True;
    end;
  if not (HasType or HasVar) then Exit;
  if HasType and HasVar and SameText(DeclarationText(F.Lines, TypeSym), Trim(TRegEx.Replace(pSteps.TypeDecl, '\s+', ' '))) and
    SameText(DeclarationText(F.Lines, VarSym), Trim(TRegEx.Replace(pSteps.VarDecl, '\s+', ' '))) then
  begin
    pSteps.ReuseDecl   := True;
    pSteps.AssignExists:= TRegEx.IsMatch(string.Join(#10, GetFile(FidOfStem(pSteps.DeclStem)).Lines),
      '(?im)^\s*' + TRegEx.Escape(pSteps.PtrVar) + '\s*:=\s*' + TRegEx.Escape(pSteps.RoutineName) + '\s*;');
    if pSteps.AssignExists then SetLength(pSteps.Edits, Length(pSteps.Edits) - 1);  { the assignment edit is the last one }
    Exit;
  end;
  Clash:= if HasType then TypeSym else VarSym;
  for var N:= 2 to CMaxPtrSuffix do
  begin
    var NewVar := pSteps.RoutineName + 'Ptr' + IntToStr(N);
    var NewType:= 'T' + NewVar;
    var Taken  := False;
    for var S in F.Syms do
      if SameText(S.Name, NewVar) or SameText(S.Name, NewType) then Taken:= True;
    if Taken then Continue;
    var Again: TRecipeRefusal;
    var Steps2:= PlanRoutineInversion(Self, pEv.Surface, Again, N);
    if Again.Kind <> '' then pRefusal:= Again
    else pSteps:= Steps2;
    Exit;
  end;
  pRefusal.Kind  := 'duplicate-identifier';
  pRefusal.Reason:= Format('`%s` already declares `%s` (line %d) and every suffix up to 99 of it', [pLeaf.UnitName,
    Clash.Name, Clash.StartLine]);
end;

{ R1 on every edge that cannot move and whose surface binds at least one routine (B3: N
  routines, mixed with movable globals): a refusal is recorded on the edge (its Why is
  what the playbook prints), an applicable edge gets Recipe crRoutineInversion, its Steps
  and Cost = its calls + the declarations that move. PlanImplCycle picks the cut (R3). }
procedure TCyclePlanner.PlanInversion(pEvals: TList<TEdgeEval>);
var
  Refusal: TRecipeRefusal;
  Moved  : TArray<string>;
  MoveIds: TArray<Int64>;
begin
  for var I:= 0 to pEvals.Count - 1 do
  begin
    var Ev:= pEvals[I];
    if (Ev.Recipe <> crNone) or (Length(Ev.Surface.RoutineIds) = 0) then Continue;
    { B3: a non-routine on the edge must move; an edge with something that cannot keeps its Why }
    var MoveCount:= 0;
    if not ProbeInversionMoves(Ev, Moved, MoveIds, MoveCount) then Continue;
    var Steps:= PlanRoutinesInversion(Self, Ev.Surface, Moved, Refusal);
    Steps.MoveIds:= MoveIds;
    if Refusal.Kind = '' then
    begin
      { W6 C2 (one routine, nothing moved): the leaf may declare the pointer's names already -- reuse an
        identical declaration, else a free suffix. B3 (several routines or moves): any such name refuses. }
      var Leaf:= InversionLeaf(Steps);
      if (Leaf.Decision = udExtend) and (Length(Steps.Routines) <= 1) and (Length(MoveIds) = 0) then
        SettleInversionNames(Ev, Leaf, Steps, Refusal)
      else if Leaf.Decision = udExtend then
        for var S in GetFile(Leaf.Fid).Syms do
          for var R in Steps.Routines do
            if SameText(S.Name, R.PtrType) or SameText(S.Name, R.PtrVar) then
            begin
              Refusal.Kind  := 'duplicate-identifier';
              Refusal.Reason:= Format('`%s` already declares `%s` (line %d)', [Leaf.UnitName, S.Name, S.StartLine]);
            end;    end;
    { A2: the old refusal unit-leaves-program named its own fix -- the declaring unit joins the program's uses }
    if Refusal.Kind = '' then Steps.RegisterDecl:= LeavesProgramReason(Steps) <> '';
    if Refusal.Kind <> '' then
    begin
      Ev.Refusal:= Refusal.Kind;
      { the label is the kind of the symbol named, never of the edge's first need (a var read before the call) }
      var Shown:= if Ev.Surface.RoutineName <> '' then Ev.Surface.RoutineName else Refusal.Symbol;
      var Kind := 'routine';
      for var N in Ev.Needs do
        if SameText(N.Owner.Name, Shown) then Kind:= N.Owner.Kind.ToText;
      if (Kind = 'routine') and (Ev.Surface.RoutineName = '') then
        for var S in GetFile(FidOfStem(Ev.Surface.ToStem)).Syms do
          if SameText(S.Name, Shown) and not (S.Kind in [skParam, skLocalVar]) and (Kind = 'routine') then Kind:= S.Kind.ToText;
      Ev.Why    := Format('`%s` (%s): refused: %s -- %s', [Shown, Kind, Refusal.Kind, Refusal.Reason]);
      pEvals[I]:= Ev;
      Continue;
    end;
    Ev.Recipe:= crRoutineInversion;
    Ev.Steps := Steps;
    Ev.Cost  := Ev.Surface.CallCount + MoveCount;
    pEvals[I]:= Ev;
  end;
end;

{ B3: probes what moves with the routines of one edge -- every need that is not one of
  them (TryAdd must succeed), and every signature type of the declaring unit that is a
  plain declaration (mvDecl: an enum, a record or alias without bodies). A type that
  cannot move stays a signature-in-cycle refusal; a need that cannot move, or a routine a
  move would pull along, leaves the edge as EvaluateEdge judged it (False). pMoved gets
  the names of the moved declarations of the declaring unit (with every signature type an
  earlier step already moved -- Part A, when Part B is predicted), pMoveIds the ids to TryAdd
  again at materialisation, pCount the number of declarations moved. Nothing stays added. }
function TCyclePlanner.ProbeInversionMoves(const pEv: TEdgeEval; out pMoved: TArray<string>;
  out pMoveIds: TArray<Int64>; out pCount: Integer): Boolean;
var
  Why    : string;
  Roots  : TList<Int64>;
  Already: TList<string>;
  Owner  : TSymbol;
  Stem   : string;
begin
  pMoved  := nil;
  pMoveIds:= nil;
  pCount  := 0;
  var Snap:= FOrder.Count;
  Roots  := TList<Int64>.Create;
  Already:= TList<string>.Create;
  try
    Result:= True;
    for var N in pEv.Needs do
      if not HasId(N.Owner.Id, pEv.Surface.RoutineIds) then
      begin
        if (N.Owner.Kind in [skProcedure, skFunction]) or not TryAdd(N.Owner, nil, Why) then Exit(False);
        Roots.Add(N.Owner.Id);
      end;
    var DeclFid:= FidOfStem(pEv.ToStem);
    for var Id in pEv.Surface.RoutineIds do
    begin
      var R:= FStore.GetSymbolById(Id);
      for var T in SignatureTypes(Self, DeclFid, R.StartLine, R.Signature) do
      begin
        if not T.InScc or (T.DeclStem <> pEv.ToStem) or
          not BindName(DeclFid, R.StartLine, T.Name.Substring(T.Name.LastIndexOf('.') + 1), Owner, Stem) then Continue;
        var Item: TMoveItem;
        var Before:= FOrder.Count;
        if not TryAdd(Owner, nil, Why) or not FItems.TryGetValue(Owner.Id, Item) or (Item.Kind <> mvDecl) then
        begin
          Rollback(Before);
          Continue;
        end;
        if not Roots.Contains(Owner.Id) then Roots.Add(Owner.Id);
        { CYCDEMO: a type an earlier step already moved (Part A, before Part B's prediction) adds
          nothing to FOrder, yet it is out of the cycle all the same -- name it, or the signature
          still reads as naming a type of the cycle }
        if (FOrder.Count = Before) and not Already.Contains(Owner.Name) then Already.Add(Owner.Name);
      end;
    end;
    for var Id in pEv.Surface.RoutineIds do
      if FItems.ContainsKey(Id) then Exit(False);
    pCount:= FOrder.Count - Snap;
    var Names:= TList<string>.Create;
    try
      for var K:= Snap to FOrder.Count - 1 do
        if FItems[FOrder[K]].Stem = pEv.ToStem then Names.Add(FItems[FOrder[K]].Sym.Name);
      pMoved:= Names.ToArray + Already.ToArray;
    finally
      Names.Free;
    end;
    pMoveIds:= Roots.ToArray;
  finally
    Rollback(Snap);
    Already.Free;
    Roots.Free;
  end;
end;

{ R2 on every edge that neither moves nor is one routine, and whose surface tests or
  casts against a class with `is` / `as`: as PlanInversion, a refusal is recorded on
  the edge, an applicable edge gets Recipe crMemberInterface, its Steps and Cost = its
  edits. The interface goes into the class unit's Untangle leaf, which must not declare
  its name already. }
procedure TCyclePlanner.PlanMemberHandOver(pEvals: TList<TEdgeEval>);
var
  Refusal: TRecipeRefusal;
begin
  var Root:= if FProjectFid > 0 then ExtractFilePath(PathOf(FProjectFid)) else '';
  var UnitScopes:= EffectiveUnitScopes(if TFile.Exists(FProjectFile) and SameText(ExtractFileExt(FProjectFile), '.dproj')
    then TFile.ReadAllText(FProjectFile) else '');
  for var I:= 0 to pEvals.Count - 1 do
  begin
    var Ev:= pEvals[I];
    var Tested:= False;
    for var R in Ev.Surface.Refs do
      if R.Kind in [erTypeIs, erTypeAs] then Tested:= True;
    if (Ev.Recipe <> crNone) or (Ev.Surface.RoutineName <> '') or not Tested then Continue;
    var Leaf := ResolveUntangleLeaf(FStore, Ev.Surface.ToStem, FComp, Root);
    var Steps:= PlanMemberInterface(Self, FLibStore, Ev.Surface, Leaf.UnitName, UnitScopes, Refusal);
    if (Refusal.Kind = '') and (Leaf.Decision = udExtend) then SettleIfaceName(Ev.Surface, Leaf, UnitScopes, Steps, Refusal);
    if Refusal.Kind <> '' then
    begin
      Ev.Refusal:= Refusal.Kind;
      Ev.Why    := Format('`%s` (class): refused: %s -- %s', [string.Join(', ', Ev.Surface.ClassNames), Refusal.Kind,
        Refusal.Reason]);
      pEvals[I]:= Ev;
      Continue;
    end;
    Ev.Recipe:= crMemberInterface;
    Ev.Steps := Steps;
    Ev.Cost  := Length(Steps.Edits);
    pEvals[I]:= Ev;
  end;
end;

{ The unit that receives R1's procedural type and variable: the existing unit J2
  chose, else the catalog's `<Declaring>.Untangle` (created or extended). }
function TCyclePlanner.InversionLeaf(const pSteps: TRecipeSteps): TUntangleLeaf;
begin
  if pSteps.LeafStem = '' then
    Exit(ResolveUntangleLeaf(FStore, pSteps.DeclStem, FComp,
      (if FProjectFid > 0 then ExtractFilePath(PathOf(FProjectFid)) else '')));
  Result:= Default(TUntangleLeaf);
  var F:= GetFile(FidOfStem(pSteps.LeafStem));
  Result.UnitName  := F.UnitName;
  Result.Path      := F.Path;
  Result.SourceStem:= pSteps.DeclStem;
  Result.Decision  := udExtend;
  Result.Fid       := F.Fid;
  for var S in F.Syms do
    if SameText(S.Section, 'interface') and not (S.Kind in [skUnit, skProgram, skPackage]) and
      (S.EndLine > Result.InsertAfterLine) then Result.InsertAfterLine:= S.EndLine;
end;

{ Unit-leaves-program (E18 final review F2; since A2 the plan registers the unit instead of
  refusing, see RegisterDeclUnit): R1 assigns the pointer in the
  declaring unit's initialization section, so that unit must stay in the program
  once the consumer stops naming it. It stays when the program file (.dpr) lists it
  or any unit other than the consumer uses it -- both are unit_uses rows (FUsersOf).
  Otherwise the consumer was its only way in: the linker drops it, its initialization
  never runs and the first call through the pointer is a nil call at run time,
  although the project compiles. A DCCReference alone does not link a unit (dcc
  compiles from the .dpr), so the .dproj is not consulted. With no indexed .dpr
  (a package, a directory index) nothing is decided here. Returns the reason, or ''. }
function TCyclePlanner.LeavesProgramReason(const pSteps: TRecipeSteps): string;
var
  Users: TList<Int64>;
begin
  Result:= '';
  if FProjectFid = 0 then Exit;
  if FUsersOf.TryGetValue(pSteps.DeclStem, Users) then
    for var Fid in Users do
      if Fid <> pSteps.ConsumerFid then Exit;
  Result:= Format('`%s` is used only by `%s` and `%s` does not list it: after the cut it leaves the program, ' +
    'its initialization never assigns `%s` and the call is a nil call at run time -- add it to the program''s uses',
    [UnitNameOfStem(pSteps.DeclStem), ExtractFileName(PathOf(pSteps.ConsumerFid)), ExtractFileName(PathOf(FProjectFid)),
     pSteps.PtrVar]);
end;

{ A2: the declaring unit joins the program's uses (`Name in 'path'`, the path relative to the .dpr) and,
  when the .dproj has no DCCReference for it, gains one after the last DCCReference. }
procedure TCyclePlanner.RegisterDeclUnit;
var
  E: TFileEdit;
begin
  if (FProjectFid = 0) or not FInversion.RegisterDecl then Exit;
  var Rel:= ExtractRelativePath(PathOf(FProjectFid), PathOf(FidOfStem(FInversion.DeclStem)));
  AddUses(FProjectFid, scProg, Format('%s in ''%s''', [UnitNameOfStem(FInversion.DeclStem), Rel]));
  if not (SameText(ExtractFileExt(FProjectFile), '.dproj') and TFile.Exists(FProjectFile)) then Exit;
  var Dproj:= ReadSourceLines(FProjectFile);
  var Last := -1;
  for var I:= 0 to High(Dproj) do
    if ContainsText(Dproj[I], 'Include="' + Rel + '"') then Exit
    else if ContainsText(Dproj[I], '<DCCReference') then Last:= I;
  if Last < 0 then Exit;
  E:= Default(TFileEdit);
  E.Kind    := ekInsertAfter;
  E.First   := Last + 1;
  E.Last    := Last + 1;
  E.NewLines:= [StringReplace(Dproj[Last], TRegEx.Match(Dproj[Last], 'Include="([^"]*)"').Groups[1].Value, Rel, [rfIgnoreCase])];
  FDprojEdits.Add(E);
end;

function TCyclePlanner.IsInversionStem(const pStem: string): Boolean;
begin
  Result:= (FInversion.Recipe in [crRoutineInversion, crMemberInterface]) and (pStem <> '') and
    (pStem = FInversion.DeclStem) and FLeafInfo.ContainsKey(pStem);
end;

{ R1's file edits and leaf, through the same leaf machinery as a move: the
  leaf is registered under the declaring unit's stem, the consumer's uses entry
  of the declaring unit is decided by DecideOne (IsMovedFor answers for the
  inverted calls), and the rest of Materialize runs unchanged. }
procedure TCyclePlanner.MaterializeInversion;
var
  E: TFileEdit;
begin
  var Stem:= FInversion.DeclStem;
  var Leaf:= InversionLeaf(FInversion);
  FLeafInfo.AddOrSetValue(Stem, Leaf);
  FLeafName.AddOrSetValue(Stem, Leaf.UnitName);
  FLeafPath.AddOrSetValue(Stem, Leaf.Path);
  for var R in FInversion.Edits do
  begin
    E:= Default(TFileEdit);
    E.Kind    := if R.Replace then ekReplace else ekInsertAfter;
    E.First   := R.Line;
    E.Last    := R.Line;
    E.NewLines:= R.NewLines;
    EditList(R.Fid).Add(E);
  end;
  var Consumer:= GetFile(FInversion.ConsumerFid);
  for var R in FInversion.Edits do
    if R.Fid = Consumer.Fid then AddUses(Consumer.Fid, SectOf(Consumer, R.Line), UsesEntryFor(Consumer, Stem));
  var Decl:= GetFile(FidOfStem(Stem));
  if FInversion.Recipe = crMemberInterface then
  begin
    { R2: the heritage names the interface, so the class unit's INTERFACE uses the leaf;
      the consumer gains Supports' unit / a cast ancestor's unit when it does not see them }
    AddUses(Decl.Fid, scIntf, UsesEntryFor(Decl, Stem));
    for var U in FInversion.ConsumerUses do AddUses(Consumer.Fid, scImpl, U);
  end
  else AddUses(Decl.Fid, scImpl, UsesEntryFor(Decl, Stem));
  RegisterDeclUnit;
  Materialize;
end;

{ The leaf text of R1: the procedural type (the routine's signature verbatim,
  J3) and the variable. Inside an existing unit's `type` block the keyword is
  not repeated. }
function TCyclePlanner.InversionDeclLines(const pStem: string): TArray<string>;
var
  L: TList<string>;
begin
  if FInversion.ReuseDecl then Exit(nil);  { W6 C2: the leaf declares the pointer identically already }
  var Leaf  := FLeafInfo[pStem];
  var InType:= False;
  if (Leaf.Decision = udExtend) and (Leaf.InsertAfterLine > 0) then
  begin
    var Lines:= GetFile(Leaf.Fid).Lines;
    var H    := HeaderOf(Lines, Leaf.InsertAfterLine + 1);
    InType:= (H > 0) and SameText(Trim(CodePart(LineAt(Lines, H))), 'type');
  end;
  L:= TList<string>.Create;
  try
    L.Add('');
    if not InType then L.Add('type');
    if FInversion.Recipe = crMemberInterface then
    begin
      { R2: the extracted interface }
      L.AddRange(FInversion.IfaceDecl);
      Exit(L.ToArray);
    end;
    for var R in FInversion.Routines do
    begin
      L.Add(Format('  /// <summary>Signature of %s (%s), copied verbatim.</summary>', [R.Name, UnitNameOfStem(pStem)]));
      L.Add('  ' + R.TypeDecl);
    end;
    L.Add('');
    L.Add('var');
    for var R in FInversion.Routines do
    begin
      L.Add(Format('  /// <summary>Holds %s, assigned by %s in its initialization section; the units of ' +
        'its former cycle call it instead of naming the routine.</summary>', [R.Name, UnitNameOfStem(pStem)]));
      L.Add('  ' + R.VarDecl);
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ The names of the routines R1 inverts, joined as `a`, `b` (the caller supplies the outer backticks). }
function TCyclePlanner.InversionNames: string;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var R in FInversion.Routines do L.Add(R.Name);
    if L.Count = 0 then L.Add(FInversion.RoutineName);
    Result:= string.Join('`, `', L.ToArray);
  finally
    L.Free;
  end;
end;
{ Why the R1 consumer keeps the declaring unit's uses entry (its section still
  uses another name the planner binds to that unit), or '' when it drops it. }
function TCyclePlanner.InversionStillUsed: string;
begin
  Result:= '';
  for var D in FDecisions do
    if (D.Fid = FInversion.ConsumerFid) and (D.PartnerStem = FInversion.DeclStem) and
      (D.Verdict in [uvKeep, uvKeepUnseen]) then
      Exit(Format('the %s section of `%s` still uses `%s`%s', [SectLabel(D.Sect), ExtractFileName(PathOf(D.Fid)),
        UnitNameOfStem(D.PartnerStem), (if D.Still <> '' then ': ' + D.Still else '')]));
end;

procedure TCyclePlanner.RenderInversion(pStep: Integer);
var
  Calls: TList<string>;
begin
  EmitFmt('### Step %d: what moves where', [pStep]);
  Calls:= TList<string>.Create;
  try
    var Decl:= UnitNameOfStem(FInversion.DeclStem);
    if Length(FInversion.MoveIds) = 0 then
      EmitFmt('Nothing moves. Recipe: **routine-call inversion** -- `%s` stays in `%s`; callers outside ' +
        'this cycle keep calling it by name.', [InversionNames, Decl])
    else
    begin
      { B3: the declarations that move with the routines, then the pointers }
      EmitFmt('Recipe: **routine-call inversion** -- `%s` stays in `%s`; callers outside this cycle keep calling ' +
        'it by name. These declarations move into `%s` first:', [InversionNames, Decl, FLeafName[FInversion.DeclStem]]);
      var No:= 0;
      for var Id in FOrder do
      begin
        Inc(No);
        RenderOneMove(No, FItems[Id]);
      end;
    end;
    for var R in FInversion.Routines do
    begin
      Calls.Clear;
      for var E in FInversion.Edits do
        if (E.Fid = FInversion.ConsumerFid) and (Length(E.NewLines) > 0) and
          TRegEx.IsMatch(E.NewLines[0], '(?<![\w.])' + TRegEx.Escape(R.PtrVar) + '\b', [roIgnoreCase]) then
          Calls.Add(IntToStr(E.Line));
      if FInversion.ReuseDecl then
        EmitFmt('- `%s` already declares the procedural type `%s` and the variable `%s` with exactly this text: they ' +
          'are reused, nothing is inserted there.', [FLeafName[FInversion.DeclStem], R.PtrType, R.PtrVar])
      else
        EmitFmt('- `%s` gets the procedural type `%s` -- the routine''s own signature, copied verbatim (keep ' +
          'every `const` and parameter name) -- and the variable `%s`.', [FLeafName[FInversion.DeclStem],
          R.PtrType, R.PtrVar]);
      if FInversion.AssignExists then
        EmitFmt('- `%s` already assigns `%s := %s;` in its initialization section: no second assignment is added.',
          [Decl, R.PtrVar, R.Name])
      else
        EmitFmt('- `%s` assigns `%s := %s;` as the first statement of its initialization section.',
          [Decl, R.PtrVar, R.Name]);
      EmitFmt('- `%s` calls `%s` instead of `%s` (line %s). Checked: its own initialization section ' +
        'makes none of these calls and does not name the routine that makes them. NOT checked: an ' +
        'initialization section of another unit that reaches them through a call chain.',
        [ExtractFileName(PathOf(FInversion.ConsumerFid)), R.PtrVar, R.Name, string.Join(', ', Calls.ToArray)]);
    end;
    if FInversion.RegisterDecl then
      EmitFmt('- `%s` joins the program''s uses (`%s`) so it stays linked and its initialization assigns `%s`: ' +
        'after the cut only `%s` used it, and the program did not list it.', [Decl, ExtractFileName(PathOf(FProjectFid)),
        FInversion.PtrVar, ExtractFileName(PathOf(FInversion.ConsumerFid))]);
  finally
    Calls.Free;
  end;
  Emit('');
end;

{ B1: the members the consumer of an R2 cut WRITES -- read/write properties with a one-line
  setter each; nothing when it only reads. }
procedure TCyclePlanner.EmitMemberWrites;
begin
  if Length(FInversion.Setters) = 0 then Exit;
  EmitFmt('- The members `%s` writes are read/write properties instead, each with a one-line setter that ' +
    'assigns the member itself (%s); a property with its own setter still runs it.',
    [ExtractFileName(PathOf(FInversion.ConsumerFid)), string.Join(', ', FInversion.Setters)]);
end;

procedure TCyclePlanner.RenderMemberHandOver(pStep: Integer);
var
  IsLines, AsLines, CastLines: TList<string>;
begin
  EmitFmt('### Step %d: what moves where', [pStep]);
  IsLines  := TList<string>.Create;
  AsLines  := TList<string>.Create;
  CastLines:= TList<string>.Create;
  try
    for var R in FCutEdge.Surface.Refs do
      if (R.Kind = erTypeIs) and not IsLines.Contains(IntToStr(R.Line)) then IsLines.Add(IntToStr(R.Line))
      else if (R.Kind = erTypeAs) and not AsLines.Contains(IntToStr(R.Line)) then AsLines.Add(IntToStr(R.Line))
      else if (R.Kind = erTypeCast) and not CastLines.Contains(IntToStr(R.Line)) then CastLines.Add(IntToStr(R.Line));
    var Decl    := UnitNameOfStem(FInversion.DeclStem);
    var Consumer:= ExtractFileName(PathOf(FInversion.ConsumerFid));
    EmitFmt('Nothing moves. Recipe: **member hand-over through an extracted interface** -- `%s` stays in `%s`; ' +
      'units outside this cycle keep using it as before.', [FInversion.ClassTypeName, Decl]);
    if FInversion.ReuseDecl then
      EmitFmt('- `%s` already declares the interface `%s` (GUID `%s`) with exactly this text: it is reused, nothing ' +
        'is inserted there. Its properties are the members `%s` reads: %s.', [FLeafName[FInversion.DeclStem],
        FInversion.IfaceName, FInversion.IfaceGuid, Consumer, string.Join(', ', FInversion.MemberSigs)])
    else
      EmitFmt('- `%s` gets the interface `%s` (GUID `%s`), with a read-only property for each member `%s` reads: %s.',
        [FLeafName[FInversion.DeclStem], FInversion.IfaceName, FInversion.IfaceGuid, Consumer,
         string.Join(', ', FInversion.MemberSigs)]);
    EmitMemberWrites;
    if Length(FInversion.MethodSigs) > 0 then
      EmitFmt('- The interface also declares each method `%s` calls on it, the signature copied verbatim: %s. `%s` ' +
        'needs no edit for them: its own methods implement them, and a virtual one still dispatches to the override.',
        [Consumer, string.Join(', ', FInversion.MethodSigs), FInversion.ClassTypeName]);
    EmitFmt('- `%s` implements it: `%s` is appended to its heritage, and a getter per member is declared before ' +
      'the class''s `end;` and implemented in its implementation section%s.', [FInversion.ClassTypeName,
      FInversion.IfaceName,
      (if Length(FInversion.KeptGetters) > 0 then Format(' -- except %s, which the class already declares and the ' +
        'interface reuses as is', [QuoteList(FInversion.KeptGetters)]) else '')]);
    if IsLines.Count > 0 then
      EmitFmt('- `%s`: `X is %s` becomes `Supports(X, %s)` (line %s).', [Consumer, FInversion.ClassTypeName,
        FInversion.IfaceName, string.Join(', ', IsLines.ToArray)]);
    if AsLines.Count > 0 then
      EmitFmt('- `%s`: `X as %s` becomes `X as %s` (line %s)%s.', [Consumer, FInversion.ClassTypeName,
        FInversion.IfaceName, string.Join(', ', AsLines.ToArray),
        (if FInversion.CastAncestor <> '' then Format('; a receiver whose type does not implement IInterface ' +
          'is cast through `%s` first', [FInversion.CastAncestor]) else '')]);
    if CastLines.Count > 0 then
      EmitFmt('- `%s`: the hard cast `%s(X).M` becomes `(X as %s).M` (line %s)%s. Behaviour change, stated: a ' +
        'cast of an object that is no `%s` used to read through the wrong object; it now raises EIntfCastError.',
        [Consumer, FInversion.ClassTypeName, FInversion.IfaceName, string.Join(', ', CastLines.ToArray),
         (if FInversion.CastAncestor <> '' then Format(' -- through `%s` when X''s type does not implement IInterface',
           [FInversion.CastAncestor]) else ''), FInversion.ClassTypeName]);
    Emit('- Checked: no name inside a `with` body changes what it binds to; the members carried are fields and ' +
      'properties of the class itself, read only.');
    EmitFmt('- Exceptions: a failed `as %s` raises EIntfCastError, not EInvalidCast as `as %s` did -- a handler ' +
      'for EInvalidCast no longer catches it. Checked: `%s` handles no EInvalidCast, or each `as` follows its ' +
      '`is` guard.', [FInversion.IfaceName, FInversion.ClassTypeName, Consumer]);
  finally
    CastLines.Free;
    AsLines.Free;
    IsLines.Free;
  end;
  Emit('');
end;

procedure TCyclePlanner.RenderImplCycle(const pPlan: TCycleFixPlan);
begin
  Emit('Status: **implementation-only** (legal in Delphi, low impact -- no interface-recompile ' +
    'blast radius). Optional to fix; the steps below are for when you want a fully acyclic uses-graph.');
  Emit('');
  RenderFiles;
  RenderImplWhy;
  Emit('### Recommended fix (optional)');
  if pPlan.CutEdge.FromStem = '' then
  begin
    RenderNoMechanicalCut(pPlan.Evals);
    Exit;
  end;
  if pPlan.CutEdge.Recipe = crRoutineInversion then
  begin
    if (Length(FInversion.Routines) > 1) or (Length(FInversion.MoveIds) > 0) then
      { B3: several routines, or routines and declarations that move }
      EmitFmt('Cut the edge `%s -> %s` by **routine-call inversion**: `%s` takes from `%s` the routines `%s`%s; every ' +
      'type of their signatures is declared outside this cycle or moves too. `%s` calls them through procedural ' +
      'variables declared in `%s` instead. No edge of this cycle can be cut by moving declarations alone.',
      [pPlan.CutEdge.FromStem, pPlan.CutEdge.ToStem, pPlan.CutEdge.FromStem, pPlan.CutEdge.ToStem, InversionNames,
      (if Length(FInversion.MoveIds) > 0 then Format(' and declarations that move into `%s`',
      [FLeafName[FInversion.DeclStem]]) else ''), pPlan.CutEdge.FromStem, FLeafName[FInversion.DeclStem]])
    else
    EmitFmt('Cut the edge `%s -> %s` by **routine-call inversion**: `%s` takes only the routine `%s` from ' +
      '`%s`, and every type of its signature is declared outside this cycle. `%s` calls it through a ' +
      'procedural variable declared in `%s` instead. No edge of this cycle can be cut by moving ' +
      'declarations.', [pPlan.CutEdge.FromStem, pPlan.CutEdge.ToStem, pPlan.CutEdge.FromStem,
      FInversion.RoutineName, pPlan.CutEdge.ToStem, pPlan.CutEdge.FromStem, FLeafName[FInversion.DeclStem]]);
    var Still:= InversionStillUsed;
    if Still <> '' then
      EmitFmt('refused: edge-still-used -- %s. The steps below keep that uses entry, so the edge stays: ' +
        'do not follow them.', [Still]);
    RenderEdgeChoices(pPlan.Evals);
    Emit('');
    RenderDone(False);
    RenderInversion(CStepMoves);
    RenderDecisions(CStepUses);
    RenderLeafUnits(CStepCreate);
    RenderEdits(CStepEdit);
    RenderChecklist(pPlan.CycleIndex - 1);
    Exit;
  end;
  if pPlan.CutEdge.Recipe = crMemberInterface then
  begin
    EmitFmt('Cut the edge `%s -> %s` by **member hand-over through an extracted interface**: `%s` takes from ' +
      '`%s` only `is` / `as` tests against `%s` and reads of its members. `%s` implements a new interface `%s`, ' +
      'declared in `%s`, and `%s` tests and casts against that instead. No edge of this cycle can be cut by ' +
      'moving declarations or by routine-call inversion.', [pPlan.CutEdge.FromStem, pPlan.CutEdge.ToStem,
      pPlan.CutEdge.FromStem, pPlan.CutEdge.ToStem, FInversion.ClassTypeName, FInversion.ClassTypeName,
      FInversion.IfaceName, FLeafName[FInversion.DeclStem], pPlan.CutEdge.FromStem]);
    var Still:= InversionStillUsed;
    if Still <> '' then
      EmitFmt('refused: edge-still-used -- %s. The steps below keep that uses entry, so the edge stays: ' +
        'do not follow them.', [Still]);
    RenderEdgeChoices(pPlan.Evals);
    Emit('');
    RenderDone(False);
    RenderMemberHandOver(CStepMoves);
    RenderDecisions(CStepUses);
    RenderLeafUnits(CStepCreate);
    RenderEdits(CStepEdit);
    RenderChecklist(pPlan.CycleIndex - 1);
    Exit;
  end;
  EmitFmt('Cut the edge `%s -> %s`: everything `%s` uses from `%s` can move into a new leaf unit, ' +
    'the smallest mechanical cut in this cycle.', [pPlan.CutEdge.FromStem, pPlan.CutEdge.ToStem,
    pPlan.CutEdge.FromStem, pPlan.CutEdge.ToStem]);
  RenderEdgeChoices(pPlan.Evals);
  Emit('');
  RenderDone(False);
  RenderMoves(CStepMoves);
  RenderDecisions(CStepUses);
  RenderLeafUnits(CStepCreate);
  RenderEdits(CStepEdit);
  RenderChecklist(pPlan.CycleIndex - 1);
end;

procedure TCyclePlanner.CaptureRefusals(var pPlan: TCycleFixPlan);
var
  L: TList<TRefusal>;

  procedure Add(const pKind, pSymbol, pFilePath, pReason: string; pLine: Integer);
  var
    R: TRefusal;
  begin
    R.Kind    := pKind;
    R.Symbol  := pSymbol;
    R.FilePath:= pFilePath;
    R.Reason  := pReason;
    R.Line    := pLine;
    L.Add(R);
  end;

begin
  L:= TList<TRefusal>.Create;
  try
    { the facts the playbook already prints: MANUAL items (a base class the F5
      gate refused is one, kind base-class; an allowed extraction is mechanical
      since E18 T7), interface edges the index could not resolve, and the
      per-file steps it can only describe. A symbol is named at its declaration
      line (Sym.StartLine), as the plan, outline and query name it -- not at
      Decl.First, the start of the move range, which includes its doc-comment }
    for var M in FManual do
      Add((if M.Refusal <> '' then M.Refusal else if M.Kind = mvBlocked then 'blocked-symbol' else 'manual-edit'),
        M.Sym.Name, PathOf(M.Sym.FileId), M.Reason, M.Sym.StartLine);
    if pPlan.HasIntf then
    begin
      for var A in FComp do
        for var B in FComp do
        begin
          if (A = B) or not FGraph.IntfEdges.ContainsKey(A + '->' + B) then Continue;
          var Resolved:= False;
          for var N in NeedsOf(FidOfStem(A)) do
            if (N.Sect = scIntf) and (N.OwnerStem = B) then Resolved:= True;
          if Resolved or IntfEntryDecided(A, B) then Continue;
          var HitLine: Integer;
          var Hit:= LexicalUseOf(A, B, scIntf, HitLine);
          Add('unresolved-edge', A + ' -> ' + B, PathOf(FidOfStem(A)),
            (if Hit = '' then 'the index could not resolve what the interface uses'
             else Format('`%s` at line %d names an interface export of %s that the index did not record: ' +
               'extractor gap', [Hit, HitLine, UnitNameOfStem(B)])), HitLine);
        end;
    end
    else if pPlan.CutEdge.FromStem = '' then
    begin
      for var Ev in pPlan.Evals do
        Add((if Ev.Refusal <> '' then Ev.Refusal else if Length(Ev.Needs) = 0 then 'unresolved-edge' else 'manual-edit'),
          Ev.FromStem + ' -> ' + Ev.ToStem, PathOf(FidOfStem(Ev.FromStem)), Ev.Why, 0);
    end
    else if pPlan.CutEdge.Recipe in [crRoutineInversion, crMemberInterface] then
    begin
      { R1 / R2 cut the edge only when the consumer drops the uses entry }
      var Still:= InversionStillUsed;
      if Still <> '' then
        Add('edge-still-used', (if FInversion.Recipe = crMemberInterface then FInversion.ClassTypeName
          else FInversion.RoutineName), PathOf(FInversion.ConsumerFid), Still, 0);
    end;
    for var Fid in pPlan.Touched do
      for var E in EditsOf(Fid) do
        if E.Kind = ekManual then
          Add((if E.Refusal <> '' then E.Refusal else 'manual-edit'), '', PathOf(Fid), E.Note, E.First);
    for var E in pPlan.DprojEdits do
      if E.Kind = ekManual then Add('manual-edit', '', FProjectFile, E.Note, E.First);
    pPlan.Refusals:= L.ToArray;
  finally
    L.Free;
  end;
  pPlan.Verdict:= if Length(pPlan.Refusals) > 0 then cvRefused else cvMechanical;
end;

procedure TCyclePlanner.CapturePlan(var pPlan: TCycleFixPlan);
var
  Items : TList<TMoveItem>;
  Leaves: TList<TNewUnit>;
begin
  Items := TList<TMoveItem>.Create;
  Leaves:= TList<TNewUnit>.Create;
  try
    for var Id in FOrder do Items.Add(FItems[Id]);
    pPlan.Items:= Items.ToArray;
    for var Stem in LeafStems(udCreate) do
    begin
      var U:= Default(TNewUnit);
      U.UnitName:= FLeafName[Stem];
      U.Path    := FLeafPath[Stem];
      U.Text    := LeafUnitText(Stem);
      Leaves.Add(U);
    end;
    pPlan.NewUnits:= Leaves.ToArray;
  finally
    Leaves.Free;
    Items.Free;
  end;
  pPlan.Decisions:= FDecisions.ToArray;
  pPlan.Touched  := EditOrder;
  pPlan.Edits    := TObjectDictionary<Int64, TList<TFileEdit>>.Create([doOwnsValues]);
  for var Fid in pPlan.Touched do
    if (FProjectFid > 0) and (Fid = FProjectFid) then pPlan.DprEdits:= EditsOf(Fid)
    else
    begin
      var L:= TList<TFileEdit>.Create;
      pPlan.Edits.Add(Fid, L);
      L.AddRange(EditsOf(Fid));
    end;
  pPlan.DprojEdits    := FDprojEdits.ToArray;
  pPlan.Predicted     := FPredicted.ToArray;
  pPlan.ExpectedOutput:= ExpectedOutput(pPlan.CycleIndex - 1);
  pPlan.CutEdge       := FCutEdge;
  CaptureRefusals(pPlan);
end;

function TCyclePlanner.BuildPlan(pCycleIndex: Integer): TCycleFixPlan;
begin
  ResetCycle(FSccs[pCycleIndex - 1]);
  Result:= Default(TCycleFixPlan);
  Result.CycleIndex:= pCycleIndex;
  Result.Units     := FComp;
  Result.HasIntf   := GroupHasIntf(FComp);
  Result.Part      := if Result.HasIntf then 'A' else 'B';
  if Result.HasIntf then PlanIntfCycle
  else Result.Evals:= PlanImplCycle;
  try
    CapturePlan(Result);
  except  // dl:ok bare-except@9273 -- releases the half-built plan result and re-raises; nothing is swallowed
    Result.Release;
    raise;
  end;
end;

function TCyclePlanner.BuildView(const pPlan: TCycleFixPlan): TCyclePlanView;
const
  CMoveRecipe: array[TMoveKind] of string = ('decl', 'with-bodies', 'base', 'blocked');
  CEditKind  : array[TEditKind] of string = ('delete', 'replace', 'insert', 'manual');
  CSection   : array[TSect] of string = ('interface', 'implementation', 'implementation');
  CUseAction : array[TUsesVerdict] of string = ('keep', 'keep', 'move', 'remove');
var
  Edits  : TList<TPlanEdit>;
  Paths  : TList<string>;
  Moves  : TList<TPlanMove>;
  UseList: TList<TPlanUse>;
  Created: TList<TPlanNewUnit>;

  procedure AddEdits(const pPath: string; const pList: TArray<TFileEdit>; const pLines: TArray<string>);
  begin
    for var E in pList do
    begin
      var V:= Default(TPlanEdit);
      V.FilePath:= pPath;
      V.Kind    := CEditKind[E.Kind];
      V.First   := E.First;
      V.Last    := E.Last;
      V.NewLines:= E.NewLines;
      case E.Kind of
        ekDelete, ekReplace: V.CurrentLines:= SliceLines(pLines, OneRange(E.First, E.Last));
        ekInsertAfter      : V.AnchorText  := LineAt(pLines, E.First);
      end;
      Edits.Add(V);
    end;
  end;

begin
  Result:= Default(TCyclePlanView);
  Result.CycleIndex:= pPlan.CycleIndex;
  Result.Units     := pPlan.Units;
  Result.HasIntf   := pPlan.HasIntf;
  Result.Part      := pPlan.Part;
  Result.Mechanical:= pPlan.Verdict = cvMechanical;
  Result.Refusals  := pPlan.Refusals;
  Edits  := TList<TPlanEdit>.Create;
  Paths  := TList<string>.Create;
  Moves  := TList<TPlanMove>.Create;
  UseList:= TList<TPlanUse>.Create;
  Created:= TList<TPlanNewUnit>.Create;
  try
    for var Fid in pPlan.Touched do
    begin
      Paths.Add(PathOf(Fid));
      if pPlan.Edits.ContainsKey(Fid) then AddEdits(PathOf(Fid), pPlan.Edits[Fid].ToArray, GetFile(Fid).Lines)
      else if Fid = FProjectFid then AddEdits(PathOf(Fid), pPlan.DprEdits, GetFile(Fid).Lines);
    end;
    if Length(pPlan.DprojEdits) > 0 then
    begin
      Paths.Add(FProjectFile);
      { the playbook's order (RenderEdits), so a consumer applying them in list order does what a follower of the text does }
      var Sorted:= Copy(pPlan.DprojEdits);
      TArray.Sort<TFileEdit>(Sorted, TComparer<TFileEdit>.Construct(
        function(const pLeft, pRight: TFileEdit): Integer
        begin
          Result:= pRight.First - pLeft.First;
        end));
      AddEdits(FProjectFile, Sorted, ReadSourceLines(FProjectFile));
    end;
    for var It in pPlan.Items do
    begin
      var M:= Default(TPlanMove);
      M.Symbol  := It.Sym.Name;
      M.Kind    := if It.Keyword <> '' then It.Keyword else LowerCase(Copy(GetEnumName(TypeInfo(TSymbolKind), Ord(It.Sym.Kind)), Succ(Length(CKindPrefix))));
      M.Recipe  := CMoveRecipe[It.Kind];
      M.FromFile:= PathOf(It.Sym.FileId);
      M.First   := It.Decl.First;
      M.Last    := It.Decl.Last;
      if FLeafName.ContainsKey(It.Stem) then M.ToUnit:= FLeafName[It.Stem];
      Moves.Add(M);
    end;
    for var D in pPlan.Decisions do
    begin
      var U:= Default(TPlanUse);
      U.FilePath:= PathOf(D.Fid);
      U.UnitName:= UnitNameOfStem(D.PartnerStem);
      U.Section := CSection[D.Sect];
      U.Action  := CUseAction[D.Verdict];
      UseList.Add(U);
    end;
    for var N in pPlan.NewUnits do
    begin
      var V:= Default(TPlanNewUnit);
      V.UnitName:= N.UnitName;
      V.Path    := N.Path;
      V.Text    := N.Text;
      Created.Add(V);
    end;
    Result.Edits       := Edits.ToArray;
    Result.TouchedPaths:= Paths.ToArray;
    Result.Moves       := Moves.ToArray;
    Result.UseDecisions:= UseList.ToArray;
    Result.NewUnits    := Created.ToArray;
  finally
    Created.Free;
    UseList.Free;
    Moves.Free;
    Paths.Free;
    Edits.Free;
  end;
  if pPlan.HasIntf then Result.Recipe:= 'move-globals'
  else if pPlan.CutEdge.FromStem <> '' then
  begin
    Result.Edge:= pPlan.CutEdge.FromStem + '->' + pPlan.CutEdge.ToStem;
    case pPlan.CutEdge.Recipe of
      crRoutineInversion: Result.Recipe:= 'routine-inversion';
      crMemberInterface : Result.Recipe:= 'member-interface';
    else Result.Recipe:= 'move-globals';
    end;
    var Steps:= pPlan.CutEdge.Steps;
    if Steps.Recipe in [crRoutineInversion, crMemberInterface] then
    begin
      Result.InversionUnit:= InversionLeaf(Steps).UnitName;
      Result.IfaceName    := Steps.IfaceName;
      Result.CastAncestor := Steps.CastAncestor;
      Result.PtrType      := Steps.PtrType;
      Result.PtrVar       := Steps.PtrVar;
      Result.PtrTypeDecl  := Steps.TypeDecl;
    end;
  end;
  Result.Predicted:= string.Join(#10, pPlan.ExpectedOutput);
end;

procedure TCyclePlanner.RenderPlan(const pPlan: TCycleFixPlan);
begin
  if (pPlan.CycleIndex < 1) or (pPlan.CycleIndex > FSccs.Count) or
    (string.Join(',', pPlan.Units) <> string.Join(',', FComp)) then
    raise EInvalidOpException.CreateFmt('RenderPlan: plan of cycle %d is not the planner''s current cycle',
      [pPlan.CycleIndex]);
  EmitFmt('## Cycle %d: %s', [pPlan.CycleIndex, string.Join(' <-> ', pPlan.Units)]);
  Emit('');
  if pPlan.HasIntf then RenderIntfCycle(pPlan)
  else RenderImplCycle(pPlan);
  RenderFixIt(pPlan);
end;

{ E18 T1 fix round 1: TEST SEAM, inert unless the environment variable names a
  file. With DRAGLINT_TEST_DUMP_PLAN=<path>, every plan Run builds appends one
  tab-separated line of its counts and names to <path>, so
  run_cycle_plan_split_identity.ps1 can check the plan DATA against the playbook
  TEXT rendered in the same run -- RenderPlan still prints the details from the
  planner's live state, and later tasks APPLY the plan's arrays. }
procedure TCyclePlanner.DumpPlanForTests(const pPlan: TCycleFixPlan);
const
  CDumpPlanVar = 'DRAGLINT_TEST_DUMP_PLAN';
  CVerdictText: array[TCycleVerdict] of string = ('mechanical', 'refused');
var
  Path : string;
  Kinds: TList<string>;
  Names: TList<string>;
  Files: TList<string>;
begin
  Path:= GetEnvironmentVariable(CDumpPlanVar);
  if Path = '' then Exit;
  Kinds:= TList<string>.Create;
  Names:= TList<string>.Create;
  Files:= TList<string>.Create;
  try
    for var R in pPlan.Refusals do
      if not Kinds.Contains(R.Kind) then Kinds.Add(R.Kind);
    for var U in pPlan.NewUnits do Names.Add(U.UnitName);
    for var Fid in pPlan.Touched do
      if pPlan.Edits.ContainsKey(Fid) then
        Files.Add(Format('%s:%d', [ExtractFileName(PathOf(Fid)), pPlan.Edits[Fid].Count]));
    TFile.AppendAllText(Path, Format('cycle=%d'#9'verdict=%s'#9'refusals=%s'#9'items=%d'#9'decisions=%d'#9 +
      'newunits=%s'#9'edits=%s'#9'dpr=%d'#9'dproj=%d'#9'predicted=%d',
      [pPlan.CycleIndex, CVerdictText[pPlan.Verdict], string.Join(',', Kinds.ToArray), Length(pPlan.Items),
       Length(pPlan.Decisions), string.Join('|', Names.ToArray), string.Join('|', Files.ToArray),
       Length(pPlan.DprEdits), Length(pPlan.DprojEdits), Length(pPlan.Predicted)]) + sLineBreak, TEncoding.ASCII);
  finally
    Files.Free;
    Names.Free;
    Kinds.Free;
  end;
end;

procedure TCyclePlanner.Run;
begin
  RenderHeader;
  if FSccs.Count = 0 then
  begin
    Emit('No circular unit dependencies. Nothing to do.');
    Exit;
  end;
  for var I:= 1 to FSccs.Count do
  begin
    var Plan:= BuildPlan(I);
    try
      DumpPlanForTests(Plan);
      RenderPlan(Plan);
    finally
      Plan.Release;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  IEdgeSurfaceSource -- the index access DRagLint.Report.CycleEdge reads
  --------------------------------------------------------------------------- }

function TCyclePlanner.Store: ISymbolStore;
begin
  Result:= FStore;
end;

function TCyclePlanner.FileLines(pFid: Int64): TArray<string>;
begin
  Result:= GetFile(pFid).Lines;
end;

function TCyclePlanner.BindName(pFid: Int64; pLine: Integer; const pName: string; out pOwner: TSymbol;
  out pStem: string): Boolean;
var
  Cands: TArray<TCandidate>;
  Best : Integer;
  F    : TPlanFile;
begin
  pOwner:= Default(TSymbol);
  pStem := '';
  Cands := CandidatesFor(pName);
  if Length(Cands) = 0 then Exit(False);
  F   := GetFile(pFid);
  Best:= PickCandidate(F, SectOf(F, pLine), Cands);
  if Best = CNotFound then Exit(False);
  pOwner:= Cands[Best].Owner;
  pStem := Cands[Best].Stem;
  Result:= True;
end;

function TCyclePlanner.IsSccStem(const pStem: string): Boolean;
begin
  Result:= FMembers.ContainsKey(pStem);
end;

function TCyclePlanner.MemberAccessOf(pRefId: Int64; out pAccess: TCallEdge): Boolean;
begin
  if FAccess = nil then
  begin
    FAccess:= TDictionary<Int64, TCallEdge>.Create;
    for var E in FStore.DumpAllMemberAccesses do FAccess.AddOrSetValue(E.RefId, E);
  end;
  Result:= FAccess.TryGetValue(pRefId, pAccess);
end;

function TCyclePlanner.EdgeSurfacesOf(pCycleIndex: Integer): TArray<TEdgeSurface>;
var
  L   : TList<TEdgeSurface>;
  Used: TList<string>;
begin
  ResetCycle(FSccs[pCycleIndex - 1]);
  L:= TList<TEdgeSurface>.Create;
  try
    for var A in FComp do
      if FGraph.Adj.TryGetValue(A, Used) then
        for var B in FComp do
          if (A <> B) and Used.Contains(B) then L.Add(BuildEdgeSurface(Self, FidOfStem(A), B));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure RenderCyclePlaybook(const pStore: ISymbolStore; const pDbPath: string;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pOut: TStrings;
  const pLibStore: ISymbolStore; const pFixProject: string);
var
  Planner: TCyclePlanner;
begin
  Planner:= TCyclePlanner.Create(pStore, pDbPath, pSccs, pGraph, pOut, pLibStore);
  try
    Planner.FixProject:= pFixProject;
    Planner.Run;
  finally
    Planner.Free;
  end;
end;

procedure VisitCyclePlans(const pStore: ISymbolStore; const pDbPath: string;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph;
  const pLibStore: ISymbolStore; const pVisit: TCyclePlanVisit; pOnly: Integer);
var
  Planner: TCyclePlanner;
  Lines  : TStringList;
begin
  Lines  := TStringList.Create;
  Planner:= TCyclePlanner.Create(pStore, pDbPath, pSccs, pGraph, Lines, pLibStore);
  try
    for var I:= 1 to pSccs.Count do
    begin
      if (pOnly > 0) and (I <> pOnly) then Continue;
      var Plan:= Planner.BuildPlan(I);
      try
        if not pVisit(Planner.BuildView(Plan),
          function: TArray<string>
          begin
            Lines.Clear;
            Planner.RenderPlan(Plan);
            Result:= Lines.ToStringArray;
          end) then Break;
      finally
        Plan.Release;
      end;
    end;
  finally
    Planner.Free;
    Lines.Free;
  end;
end;

procedure AddCycleFixHints(const pIn: TCycleFixHintInput; const pGroups: TJSONArray);

  function EdgeJson(const pEdge: TFixEdge; pWithChosen: Boolean): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('from', pEdge.FromUnit);
    Result.AddPair('to', pEdge.ToUnit);
    Result.AddPair('recipe', pEdge.Recipe);
    if pWithChosen then Result.AddPair('chosen', TJSONBool.Create(pEdge.Chosen));
  end;

var
  Planner: TCyclePlanner;
begin
  if pIn.Unavailable <> '' then
  begin
    for var I:= 1 to pIn.Sccs.Count do
    begin
      var Fix:= TJSONObject.Create;
      Fix.AddPair('available', TJSONBool.Create(False));
      Fix.AddPair('part', '');
      Fix.AddPair('dry_run', FixCommandText(pIn.FixProject, pIn.DbPath, I, False));
      Fix.AddPair('apply', FixCommandText(pIn.FixProject, pIn.DbPath, I, True));
      Fix.AddPair('edges', TJSONArray.Create);
      Fix.AddPair('reason', pIn.Unavailable);
      (pGroups.Items[I - 1] as TJSONObject).AddPair('fix', Fix);
    end;
    Exit;
  end;
  Planner:= TCyclePlanner.Create(pIn.Store, pIn.DbPath, pIn.Sccs, pIn.Graph, nil, pIn.LibStore);
  try
    Planner.FixProject:= pIn.FixProject;
    for var I:= 1 to pIn.Sccs.Count do
    begin
      var Plan:= Planner.BuildPlan(I);
      try
        var H:= Planner.FixHintOf(Plan);
        var Fix:= TJSONObject.Create;
        Fix.AddPair('available', TJSONBool.Create(H.Available));
        Fix.AddPair('part', LowerCase(H.Part));
        Fix.AddPair('dry_run', H.DryRun);
        Fix.AddPair('apply', H.Apply);
        var Edges:= TJSONArray.Create;
        for var E in H.Edges do Edges.AddElement(EdgeJson(E, True));
        Fix.AddPair('edges', Edges);
        if H.HasFollowup then Fix.AddPair('followup', EdgeJson(H.Followup, False));
        Fix.AddPair('reason', H.Reason);
        (pGroups.Items[I - 1] as TJSONObject).AddPair('fix', Fix);
      finally
        Plan.Release;
      end;
    end;
  finally
    Planner.Free;
  end;
end;

procedure AddCycleEdgeSurfaces(const pStore: ISymbolStore; const pSccs: TList<TArray<string>>;
  const pGraph: TCycleGraph; const pGroups: TJSONArray);
var
  Planner: TCyclePlanner;
begin
  Planner:= TCyclePlanner.Create(pStore, '', pSccs, pGraph, nil);
  try
    for var I:= 1 to pSccs.Count do
    begin
      var Edges:= TJSONArray.Create;
      (pGroups.Items[I - 1] as TJSONObject).AddPair('edges', Edges);
      for var S in Planner.EdgeSurfacesOf(I) do Edges.AddElement(EdgeSurfaceToJson(S));
    end;
  finally
    Planner.Free;
  end;
end;

function BuildCycleGraph(const pStore: ISymbolStore): TCycleGraph;
var
  Fid  : Int64        ;
  Path : string       ;
  UFrom: string       ;
  UTo  : string       ;
  L    : TList<string>;
  Uo   : TUnitUse     ;
  Units: TDictionary<string, string>; { = Result.UnitFile, for the BareUsesBinding test }
begin
  Result.Adj      := TDictionary<string, TList<string>>.Create;
  Result.IntfEdges:= TDictionary<string, Boolean>.Create;
  Result.UnitFile := TDictionary<string, string>.Create;
  Result.UnitFid  := TDictionary<string, Int64>.Create;
  Units:= Result.UnitFile;
  try
    var Scopes:= ProjectUnitScopes(pStore);
    var IsUnit: TProjectUnitTest:=
      function(const pUnitLower: string): Boolean
      begin
        Result:= Units.ContainsKey(pUnitLower);
      end;
    for Fid in pStore.GetAllFileIds do
    begin
      Path:= pStore.GetFilePath(Fid);
      if not SameText(ExtractFileExt(Path), '.pas') then Continue;
      { indexed paths may use '/' -- normalise so ExtractFileName strips the dir }
      UFrom:= LowerCase(ChangeFileExt(ExtractFileName(StringReplace(Path, '/', '\', [rfReplaceAll])), ''));
      if UFrom = '' then Continue;
      Result.UnitFile.AddOrSetValue(UFrom, Path);
      Result.UnitFid .AddOrSetValue(UFrom, Fid );
    end;
    for Fid in pStore.GetAllFileIds do
    begin
      Path:= pStore.GetFilePath(Fid);
      if not SameText(ExtractFileExt(Path), '.pas') then Continue;
      UFrom:= LowerCase(ChangeFileExt(ExtractFileName(StringReplace(Path, '/', '\', [rfReplaceAll])), ''));
      if UFrom = '' then Continue;
      if not Result.Adj.TryGetValue(UFrom, L) then
      begin
        L:= TList<string>.Create;
        Result.Adj.AddOrSetValue(UFrom, L);
      end;
      for Uo in pStore.GetUnitUsesForFile(Fid) do
      begin
        UTo:= LowerCase(Uo.UnitName);
        if UTo = '' then Continue;
        { A3-b: a bare name binds as dcc binds it -- the exact project unit, else the first
          unit scope of the project (DCC_Namespace) that makes one; otherwise it is an
          external unit, taken as written (a node with no outgoing list). Dotted: as written. }
        var Mapped:= BareUsesBinding(UTo, Scopes, IsUnit);
        if (Mapped <> '') and (Mapped <> UFrom) then UTo:= Mapped;
        if not L.Contains(UTo) then L.Add(UTo);
        if Uo.Section = uusInterface then Result.IntfEdges.AddOrSetValue(UFrom + '->' + UTo, True);
      end;
    end;
  except
    on Exception do
    begin
      FreeCycleGraph(Result); { fix round 1: a raise midway must not leak the partial graph }
      raise;
    end;
  end;
end;

procedure FreeCycleGraph(var pGraph: TCycleGraph);
begin
  if pGraph.Adj <> nil then
    for var L in pGraph.Adj.Values do L.Free;
  FreeAndNil(pGraph.Adj);
  FreeAndNil(pGraph.IntfEdges);
  FreeAndNil(pGraph.UnitFile);
  FreeAndNil(pGraph.UnitFid);
end;

function ComputeSccs(const pGraph: TCycleGraph): TList<TArray<string>>;
var
  Index  : TDictionary<string, Integer>;
  Lowlink: TDictionary<string, Integer>;
  OnStack: TDictionary<string, Boolean>;
  Stack  : TList<string>               ;
  Counter: Integer                     ;
  Sccs   : TList<TArray<string>>       ;
  Done   : Boolean                     ;

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
    if pGraph.Adj.TryGetValue(AV, Neighbors) then
      for W in Neighbors do
      begin
        if not Index.ContainsKey(W) then
        begin
          { external/library unit -- a leaf, cannot be part of a cycle }
          if not pGraph.Adj.ContainsKey(W) then Continue;
          StrongConnect(W);  // dl:ok duplicate-code@6627 -- the Tarjan pass DRagLint.Charts.Q.Cycles also runs; merging the charts query onto ComputeSccs is outside E18 T15b
          if Lowlink[W] < Lowlink[AV] then Lowlink[AV]:= Lowlink[W];
        end
        else if OnStack.ContainsKey(W) and OnStack[W] then
          if Index[W] < Lowlink[AV] then Lowlink[AV]:= Index[W];
      end;
    if Lowlink[AV] = Index[AV] then
    begin
      Comp:= TList<string>.Create;
      try
        repeat
          Top:= Stack[Stack.Count - 1];
          Stack.Delete(Stack.Count - 1);
          OnStack.AddOrSetValue(Top, False);
          Comp.Add(Top);
        until Top = AV;
        if Comp.Count > 1 then Sccs.Add(Comp.ToArray);
      finally
        Comp.Free;
      end;
    end;
  end;

begin
  Sccs   := TList<TArray<string>>.Create;
  Index  := TDictionary<string, Integer>.Create;
  Lowlink:= TDictionary<string, Integer>.Create;
  OnStack:= TDictionary<string, Boolean>.Create;
  Stack  := TList<string>.Create;
  Done   := False;
  try
    Counter:= 0;
    for var K in pGraph.Adj.Keys do
      if not Index.ContainsKey(K) then StrongConnect(K);
    Done:= True;
  finally
    Stack.Free;
    OnStack.Free;
    Lowlink.Free;
    Index.Free;
    if not Done then FreeAndNil(Sccs); { a raise must not leak the caller's list }
  end;
  Result:= Sccs;
end;

function ComputeSccs(const pStore: ISymbolStore): TList<TArray<string>>;
var
  Graph: TCycleGraph;
begin
  Graph:= BuildCycleGraph(pStore);
  try
    Result:= ComputeSccs(Graph);
  finally
    FreeCycleGraph(Graph);
  end;
end;

function ComputeInterfaceSccs(const pGraph: TCycleGraph): TList<TArray<string>>;
var
  IntfOnly: TCycleGraph;
begin
  IntfOnly          := pGraph; { IntfEdges / UnitFile / UnitFid aliased, read only }
  IntfOnly.Adj      := TDictionary<string, TList<string>>.Create;
  try
    for var Pair in pGraph.Adj do
    begin
      { every unit stays a node (ComputeSccs treats a stem with no Adj key as a library leaf) }
      var Kept:= TList<string>.Create;
      IntfOnly.Adj.Add(Pair.Key, Kept);
      for var Used in Pair.Value do
        if pGraph.IntfEdges.ContainsKey(Pair.Key + '->' + Used) then Kept.Add(Used);
    end;
    Result:= ComputeSccs(IntfOnly);
  finally
    for var L in IntfOnly.Adj.Values do L.Free;
    IntfOnly.Adj.Free;
  end;
end;

end.
