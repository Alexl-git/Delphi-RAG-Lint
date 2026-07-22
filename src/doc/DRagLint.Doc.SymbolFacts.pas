unit DRagLint.Doc.SymbolFacts;

// Auto-Document Phase 2, Task 1: the analysis-facts layer. TSymbolFacts
// itself lives in DRagLint.Core.Model (so ISymbolStore.Get/PutSymbolFacts can
// reference it without a circular interface-uses -- see Core.Interfaces).
// This unit holds the record<->DB-column serialize helpers for symbol_facts'
// CSV TEXT columns (reads_fields, writes_fields, sql_reads, sql_writes,
// covered_by); Storage.SQLite stores/reads those columns verbatim as plain
// text, and callers (T2's analyzer, later renderers) use these helpers to
// move between a TArray<string> and that stored CSV form.
//
// Task 2 adds TSymbolFactsAnalyzer, the index-time entry point that produces
// one TSymbolFacts row per routine symbol. Its Analyze signature is final as
// of Task 2 -- Tasks 3-8 each fill in one group of fields inside the SAME
// function body (Cyclomatic/BodyLoc, ReadsFields/WritesFields, ReturnsOwner,
// DfmEvent, SqlReads/SqlWrites, CoveredBy respectively) without ever changing
// the signature, so the indexer's call site (DRagLint.Core.Indexer.IndexFile)
// is written once, here, and never touched again. This unit intentionally
// does NOT uses DRagLint.Core.Indexer: the Indexer uses THIS unit, so a
// back-reference would be a circular unit dependency.
//
// TASK 5 OVERRIDE (CoveredBy): unlike every other fact group listed above,
// CoveredBy is NOT filled by Analyze/the indexer -- Analyze never touches
// Result.CoveredBy, so symbol_facts.covered_by stays RESERVED/UNWRITTEN
// ('' as read back from storage, always). Covered-by is a REVERSE edge (a
// TEST calls the target), so index-time population would be ORDER-DEPENDENT/
// non-deterministic: if Foo.pas is indexed before FooTests.pas (the usual
// alphabetical order), the test->code call edge is not yet in call_edges
// when Foo's row is written, so CoveredBy comes out empty; index the other
// order and it is populated -- a real determinism violation the design's
// "same DB -> same facts" mandate cannot tolerate. Instead ComputeCoveredBy
// (below) computes it LAZILY at doc/hover RENDER time, exactly how Phase 1's
// 'Called from:' fact already works (DRagLint.Doc.Facts.TDocFactsBuilder.
// Build calls it directly, not through symbol_facts), which is always
// correct because it queries the full CURRENT call graph.
//
// IMPLEMENTATION NOTE -- NOT DRagLint.Report.RCallTree: the design brief
// suggested reusing TRCallTree's BuildReverseCallTree for the bounded reverse
// closure, but that walks ONLY AStore.FindResolvedCallers (certain call_edges
// rows). EMPIRICALLY CONFIRMED (a live RED/GREEN cycle against this Task's
// own fixtures) that this is NOT sufficient: DRagLint.Index.CallResolver's
// TCallResolver.TypeReceiver types every BARE (non-dotted) call site to the
// CALLING routine's OWN enclosing class/unit (kind 1: 'bare M / Self.M ->
// the enclosing routine's owning class') -- it never considers a target in a
// DIFFERENT unit. A DUnitX '[Test]'-style method calling a free-function (or
// another class's method) under test is exactly this bare-call shape, so
// that call NEVER gets a call_edges row, resolved or not -- it only ever
// surfaces via the NAME-based FindUnresolvedNameCallers bucket. A reverse
// walk built purely on FindResolvedCallers would therefore see the target's
// SAME-UNIT/SAME-CLASS callers only and silently miss essentially every real
// test caller. ComputeCoveredBy instead hand-rolls a bounded BFS that unions
// FindResolvedCallers + FindUnresolvedNameCallers at EVERY hop -- the exact
// two-bucket union DRagLint.Doc.Facts' own 'Called from:' gather already
// uses for the SAME reason -- per the task brief's own documented fallback
// ("if TRCallTree doesn't expose a bounded reverse walk cleanly, fall back
// to direct callers ... plus one or two manual reverse hops").
//
// Task 4 (ADP2) implements the ReadsFields/WritesFields group: a focused,
// single-pass AST walk (WalkFieldRW, implementation section) over the
// routine's OWN body -- deliberately NOT the shared TDataFlowSolver/
// IDataFlowAnalysis lattice machinery (DRagLint.Analysis.DataFlow/
// .Flow.Lattices) that Cyclomatic's neighboring CFG walk might suggest:
// field read/write is a bounded classification, not a fixpoint dataflow
// property. It DOES reuse DRagLint.Analysis.Flow.Lattices' TRoutineVarTable,
// purely to know which bare names are the routine's OWN locals/params/Result
// (so a same-named one SHADOWS an owning-class field, never misclassified as
// a read/write of it). See AnalyzeReadsWrites' header comment for the full
// field-set + classification ruleset (bare ':=' lhs / Inc-Dec first-arg =
// write; every other occurrence = read), and JoinCappedDisplay for the
// storage format -- already display-ready (', '-joined, capped at 8, a
// ' (+N more)' suffix when truncated), since these two columns have no
// companion *Total field to defer the cap decision to render time.
//
// Task 6 (ADP2) implements the DfmEvent group: which control/event a
// published method is wired to as a handler (e.g. 'Button1.OnClick'),
// mined from the .pas file's OWN paired .dfm sibling (ChangeFileExt(
// AFilePath, '.dfm')). Unlike ReturnsOwner/SqlReads/SqlWrites (still
// unimplemented placeholders as of this task) and UNLIKE Task 5's CoveredBy
// override above, DfmEvent IS filled by Analyze/stored in symbol_facts --
// the .dfm is a deterministic, same-file-pair sibling (no reverse-edge
// ordering problem the way a test->target call is), so index-time
// computation is safe and matches Cyclomatic/ReadsFields/WritesFields'
// discipline exactly (see the TASK 5 OVERRIDE comment above for the
// contrast). The existing 'event-binding' Reference DRagLint.Parser.DFM's
// WalkProperty already emits (consumed by DRagLint.Wiring's
// FindEventHandlersForForm) carries ONLY the handler's bare name -- it
// cannot answer "which object/property is THIS handler wired to" -- so this
// task adds a second, focused extractor (DRagLint.Parser.DFM.
// ExtractDfmEventBindings) that reuses the SAME WalkObject/WalkProperty tree
// walk but also threads the enclosing object's own name down to the
// property scan, yielding the full (ObjectName, EventProp, HandlerName)
// triple. See DfmEventMapFor's header comment (implementation section) for
// the per-.dfm memoization (mirrors TAstParseCache's per-file memoization,
// but deliberately a SINGLE-entry cache, not a growing dictionary -- see
// its own comment for why that is both sufficient and safe) and
// AnalyzeDfmEvent for how a routine's own Name is looked up against it.

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

/// <summary>Joins AItems into the CSV text form stored in one of
/// symbol_facts' TEXT columns (ReadsFields, WritesFields, SqlReads,
/// SqlWrites, CoveredBy). Returns '' for an empty array. No escaping is
/// applied: entries are Pascal identifiers / qualified names, which never
/// contain a comma.</summary>
/// <param name="AItems">Field/table/test qualified names, in display order.</param>
function SymbolFactsCsvJoin(const AItems: TArray<string>): string;

/// <summary>Splits a symbol_facts CSV TEXT column back into its entries.
/// Inverse of SymbolFactsCsvJoin. '' (or a blank/whitespace-only string)
/// yields an empty array (never a 1-element array holding '').</summary>
/// <param name="ACsv">A raw symbol_facts TEXT column value, e.g. as returned
/// by ISymbolStore.GetSymbolFacts.</param>
function SymbolFactsCsvSplit(const ACsv: string): TArray<string>;

/// <summary>LAZILY computes the 'Covered by:' fact for ASym at DOC/HOVER
/// RENDER time -- Phase 2 Task 5's CONTROLLER OVERRIDE to the index-time
/// brief (see this unit's banner comment, "TASK 5 OVERRIDE", for why a
/// reverse test-&gt;target edge cannot be filled deterministically at index
/// time). NEVER called from TSymbolFactsAnalyzer.Analyze; symbol_facts.
/// covered_by stays unwritten/reserved. Shared by DRagLint.Doc.Facts'
/// TDocFactsBuilder.Build and (Phase 2 Task 9) the hover renderer, so both
/// surfaces agree on the same fact.</summary>
/// <param name="AStore">Open symbol store to query; not owned.</param>
/// <param name="ASym">The routine whose test coverage is being reported.
/// Non-routine kinds (types/fields/consts/units/...) always yield ''.</param>
/// <returns>Already DISPLAY-READY (', '-joined, capped at COVERED_BY_CAP
/// entries, a ' (+N more)' suffix when truncated -- the SAME passthrough
/// contract as ReadsFields/WritesFields, see JoinCappedDisplay) CSV of
/// qualified TEST-method names that call ASym, directly or transitively
/// within COVERED_BY_DEPTH reverse call-graph hops. Walked via a bounded,
/// hand-rolled BFS over ISymbolStore.FindResolvedCallers +
/// FindUnresolvedNameCallers (NOT DRagLint.Report.RCallTree -- see this
/// unit's banner "IMPLEMENTATION NOTE" for the empirically-confirmed reason
/// a resolved-only reverse tree misses the realistic DUnitX case). '' when
/// ASym.Id &lt;= 0, ASym is not routine-like, or no caller (at any hop) is
/// detected as a test -- see IsTestRoutine for the two detection rules.</returns>
function ComputeCoveredBy(const AStore: ISymbolStore; const ASym: TSymbol): string;

type
  /// <summary>Index-time analyzer that derives a TSymbolFacts row for one
  /// routine symbol -- the single call site the indexer uses for every fact
  /// group Phase 2 will ever add (see the unit banner comment).</summary>
  TSymbolFactsAnalyzer = class
    public
      /// <summary>Analyzes ASym's body and returns the TSymbolFacts row to
      /// persist for it. Task 2 returned an EMPTY-but-Present record; Task 3
      /// (ADP2) filled in Cyclomatic/BodyLoc; Task 4 (ADP2) fills in
      /// ReadsFields/WritesFields (see below); Task 6 (ADP2) fills in
      /// DfmEvent (see below); Tasks 7-8 populate the remaining groups one
      /// at a time. Never returns Present=False (the indexer only calls
      /// this for a symbol it is about to write a row for).</summary>
      /// <param name="ASym">The routine symbol being analyzed. ADP2 T4 fix
      /// wave: the caller (the indexer's facts loop) now resolves ASym's real
      /// identity BEFORE calling Analyze -- Id/FileId are the just-inserted DB
      /// values and ParentId is already translated to the real owning
      /// symbol's id (or -1 for a free routine / unresolved parent), never a
      /// pre-insert in-array index or placeholder. Result.SymbolId is seeded
      /// from ASym.Id and the caller still overwrites it with the same
      /// just-inserted DB id afterward, defensively.</param>
      /// <param name="AFilePath">Path to ASym's source file (ADP2 T3) -- the
      /// indexer's own IndexFile parameter, passed through unchanged. Needed
      /// because the indexer's TParseResult carries no tree-sitter tree (only
      /// extracted symbols/refs); this is how Analyze reaches the AST (via
      /// TAstParseCache.Get, memoized per file) for Cyclomatic.</param>
      /// <param name="ABody">The routine's implementation body, one source
      /// line per array entry (ASym.ImplStartLine..ImplEndLine, 1-based),
      /// already bounds-clipped by the caller. Unused by Task 3 (BodyLoc is
      /// pure symbol-range arithmetic, not a text scan); a later fact group
      /// may use it.</param>
      /// <param name="AStore">Read-only access to the rest of the index, for
      /// facts that need a cross-symbol lookup (e.g. DFM event bindings, SQL
      /// table references). Unused by Task 3.</param>
      /// <returns>A TSymbolFacts record with Present=True.</returns>
      /// <remarks>ADP2 T3: Cyclomatic is 0 when no defProc in AFilePath's tree
      /// starts at ASym.ImplStartLine (e.g. AFilePath unreadable/unparseable) --
      /// absence over a wrong number, never fabricated. BodyLoc is always
      /// ImplEndLine - ImplStartLine (clamped to >= 0), independent of the AST.
      /// ADP2 T4: ReadsFields/WritesFields are '' under the SAME no-defProc
      /// condition, plus whenever ASym has no owning class or that owning
      /// class has no field children -- see AnalyzeReadsWrites' header
      /// comment (this unit's implementation section) for the full field-set
      /// + read/write classification rules. ADP2 T6: DfmEvent is '' whenever
      /// ASym has no owning class (a free routine can never be a DFM event
      /// handler), the paired .dfm (ChangeFileExt(AFilePath, '.dfm')) does
      /// not exist on disk (most units are not forms), or no On*-property in
      /// that .dfm is wired to ASym.Name -- see AnalyzeDfmEvent/
      /// DfmEventMapFor (this unit's implementation section) for the
      /// memoized per-.dfm parse and the first-wiring-wins tie-break
      /// rule.</remarks>
      class function Analyze(const ASym: TSymbol; const AFilePath: string; const ABody: TArray<string>; const AStore: ISymbolStore): TSymbolFacts; static;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils                    { ADP2 T6: TFile.Exists/ReadAllBytes -- the paired .dfm sibling read }
  , System.Classes                    { ADP2 T5: TStringList for the sorted/deduped test-name set }
  , System.Generics.Collections       { ADP2 T4: TDictionary/TList for the field-name set + ordered read/write lists }
  , TreeSitter                        { ADP2 T3: TTSNode for the AST-derived Cyclomatic fact }
  , DRagLint.Diagnostics.ParseCache    { ADP2 T3: TAstParseCache -- memoized per-file tree, owned by the cache }
  , DRagLint.Analysis.Cfg              { ADP2 T3: CfgFindProcs -- collect every defProc in the file's tree }
  , DRagLint.Analysis.Flow.Lattices    { ADP2 T4: TRoutineVarTable -- a same-named local/param/Result shadows a field, never misclassified as one }
  , DRagLint.Diagnostics.AstChecks     { ADP2 T3: TAstChecker.CyclomaticOf -- ONE shared formula with the lint rule }
  , DRagLint.Parser.DFM                { ADP2 T6: TDfmEventBinding/ExtractDfmEventBindings -- the paired-.dfm event-wiring extractor }
  ;

function SymbolFactsCsvJoin(const AItems: TArray<string>): string;
begin
  if Length(AItems) = 0 then Exit('');
  Result:= string.Join(',', AItems);
end;

function SymbolFactsCsvSplit(const ACsv: string): TArray<string>;
begin
  if Trim(ACsv) = '' then Exit(nil);
  Result:= SplitString(ACsv, ',');
end;

// ADP2 T4: display cap for the Reads:/Writes: fields fact -- 8 names shown,
// then a ' (+N more)' suffix (the Phase 1 cap convention DRagLint.Doc.Regions'
// MoreSuffix already uses for Calls/CalledFrom/etc.). Unlike those fields,
// ReadsFields/WritesFields have no companion *Total column (see TSymbolFacts,
// DRagLint.Core.Model), so the cap decision is made ONCE here, at analysis
// time, and the resulting string is stored -- and later rendered -- verbatim.
const
  FIELD_RW_CAP = 8;

// Byte-slice text of N out of ASrc (UTF-8), mirroring the private NodeStr
// helper every AST-walking unit (DRagLint.Analysis.Cfg, .Flow.Lattices,
// DRagLint.Diagnostics.AstChecks) keeps its own copy of: none of them export
// it, so it is duplicated here rather than reaching across units for a
// three-line helper.
function FieldNodeStr(const N: TTSNode; const ASrc: TBytes): string;
var S, E, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
  if (L <= 0) or (S < 0) or (E > Length(ASrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASrc, S, L);
end;

// True when AEnt is the bare identifier 'Inc' or 'Dec' (case-insensitive) --
// the two mutating RTL intrinsics whose FIRST argument is a WRITE target
// (see WalkFieldRW's header comment for the full classification ruleset).
function IsIncOrDecEntity(const AEnt: TTSNode; const ASrc: TBytes): Boolean;
var T: string;
begin
  Result:= False;
  if AEnt.IsNull or (AEnt.NodeType <> 'identifier') then Exit;
  T:= LowerCase(Trim(FieldNodeStr(AEnt, ASrc)));
  Result:= (T = 'inc') or (T = 'dec');
end;

// Single-pass classification walk over one routine body (or any subtree of
// it) for the Reads/Writes fields fact. Every bare identifier that resolves
// (case-insensitively) to a key of AFields -- and is NOT shadowed by a
// same-named local/param/Result in AVars (a local declaration shadows a
// field of the same name in Pascal scoping -- AVars is the routine's OWN
// TRoutineVarTable, built once by the caller via DRagLint.Analysis.
// Flow.Lattices' TRoutineVarTable.Build, the exact same var table the
// dataflow lattices themselves use) -- is recorded into AReads/AWrites
// (TList<string>, ORIGINAL-CASE display spelling, first-occurrence order,
// each deduped independently so a field re-read/re-written many times
// appears once per list).
//
// Node-shape rules reuse the SAME grammar knowledge DRagLint.Analysis.
// Flow.Lattices' CollectReadsAndCallDefs / TLiveness.Transfer already encode
// (an 'assignment' node's lhs/rhs fields; 'exprDot' splitting a receiver from
// its member name; 'exprCall' splitting a callee entity from its args) -- see
// this unit's Analyze remarks for the pointer to that reference reading.
// This walk is deliberately NOT the shared TDataFlowSolver/IDataFlowAnalysis
// lattice machinery (field read/write is a focused AST classification here,
// not a fixpoint dataflow property):
//   - 'assignment': a BARE-IDENTIFIER lhs is a WRITE. Any other lhs shape (an
//     indexed/qualified write, e.g. `a[i] :=` / `x.f :=`) is walked as a READ
//     of its own subtree instead -- absence over guessing a field write for
//     a shape this fact does not attempt to resolve.
//   - 'exprCall' whose entity is 'Inc'/'Dec': the first argument, if a bare
//     identifier, is a WRITE (the mutating-intrinsic rule); any further
//     argument (Inc/Dec's optional step N) and the callee identifier itself
//     are reads.
//   - any OTHER 'exprCall': the entity and every argument are reads -- the
//     brief's documented choice. Resolving whether an ordinary callee's
//     parameter is var/out (so a field passed to it might be written) is
//     cross-referenced/expensive and explicitly OPTIONAL/not attempted here;
//     an unresolved possible write is never guessed, so such a field is
//     simply counted as read (absence of a write fact, never a wrong one).
//   - 'exprDot': only the lhs (receiver) is walked. The rhs is the MEMBER
//     NAME, never itself a var/field reference (e.g. in `FLogger.Log(...)`,
//     'Log' must never be checked against the field-name set).
//   - anything else (if/while/for/case/block/binary-expr/statement
//     wrappers/...): recurse into every named child.
//
// KNOWN GRAMMAR GOTCHA (found empirically during T4's own RED/GREEN cycle,
// NOT a bug in this walk): a BARE (no begin/end) `if C then Inc(X) else
// Y := Z;` -- an Inc/Dec call as the un-braced 'then' arm, immediately
// followed by an un-braced assignment 'else' arm -- is misparsed by
// tree-sitter-delphi13: the WHOLE construct comes back as one 'assignment'
// node whose lhs is an 'exprIf' (covering "if C then Inc(X)") and whose rhs
// is the bare identifier Y (with the ':= Z' part orphaned) -- so Y reads
// back as a READ, not a WRITE. Confirmed via temporary AST tracing; wrapping
// EITHER arm in begin/end avoids it entirely (the fixture and this repo's
// own style always brace multi-branch bodies, so it is not expected to bite
// real code, but it is a real, pre-existing parser gap -- out of scope for
// this fact to fix -- worth a grammar-side ticket).
procedure WalkFieldRW(const N: TTSNode; const ASrc: TBytes; AFields: TDictionary<string, string>;
  AVars: TRoutineVarTable; AReads, AWrites: TList<string>);

  function ResolveField(const AIdent: TTSNode; out ADisplay: string): Boolean;
  var Key: string;
  begin
    Result:= False;
    if AIdent.IsNull or (AIdent.NodeType <> 'identifier') then Exit;
    Key:= LowerCase(Trim(FieldNodeStr(AIdent, ASrc)));
    if (AVars <> nil) and (AVars.IndexOf(Key) >= 0) then Exit; // shadowed by a local/param/Result
    Result:= AFields.TryGetValue(Key, ADisplay);
  end;

  procedure MarkRead(const AIdent: TTSNode);
  var Disp: string;
  begin
    if ResolveField(AIdent, Disp) and (AReads.IndexOf(Disp) < 0) then AReads.Add(Disp);
  end;

  procedure MarkWrite(const AIdent: TTSNode);
  var Disp: string;
  begin
    if ResolveField(AIdent, Disp) and (AWrites.IndexOf(Disp) < 0) then AWrites.Add(Disp);
  end;

var
  I         : Integer;
  Lhs, Rhs  : TTSNode ;
  Ent, ArgsN: TTSNode ;
begin
  if N.IsNull then Exit;

  if N.NodeType = 'assignment' then
  begin
    Lhs:= N.ChildByField('lhs');
    Rhs:= N.ChildByField('rhs');
    if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') then
      MarkWrite(Lhs)
    else
      WalkFieldRW(Lhs, ASrc, AFields, AVars, AReads, AWrites);
    WalkFieldRW(Rhs, ASrc, AFields, AVars, AReads, AWrites);
    Exit;
  end;

  if N.NodeType = 'identifier' then begin MarkRead(N); Exit; end;

  if N.NodeType = 'exprDot' then
  begin
    WalkFieldRW(N.ChildByField('lhs'), ASrc, AFields, AVars, AReads, AWrites);
    Exit; // rhs = member name, never itself a field reference
  end;

  if N.NodeType = 'exprCall' then
  begin
    Ent  := N.ChildByField('entity');
    ArgsN:= N.ChildByField('args');
    if IsIncOrDecEntity(Ent, ASrc) and (not ArgsN.IsNull) and (ArgsN.NamedChildCount > 0) then
    begin
      if ArgsN.NamedChild(0).NodeType = 'identifier' then MarkWrite(ArgsN.NamedChild(0))
      else WalkFieldRW(ArgsN.NamedChild(0), ASrc, AFields, AVars, AReads, AWrites);
      for I:= 1 to ArgsN.NamedChildCount - 1 do
        WalkFieldRW(ArgsN.NamedChild(I), ASrc, AFields, AVars, AReads, AWrites);
    end
    else if not ArgsN.IsNull then
      for I:= 0 to ArgsN.NamedChildCount - 1 do
        WalkFieldRW(ArgsN.NamedChild(I), ASrc, AFields, AVars, AReads, AWrites);
    WalkFieldRW(Ent, ASrc, AFields, AVars, AReads, AWrites); // a field holding a callback (FOnChange()) reads FOnChange
    Exit;
  end;

  for I:= 0 to N.NamedChildCount - 1 do
    WalkFieldRW(N.NamedChild(I), ASrc, AFields, AVars, AReads, AWrites);
end;

// Joins up to ACap entries of AItems with ', ', appending the Phase 1
// ' (+N more)' suffix when AItems holds more than ACap. '' for an empty
// AItems. This IS the final, display-ready string stored verbatim in
// symbol_facts.reads_fields/writes_fields (see FIELD_RW_CAP's comment for
// why the cap can't be deferred to render time for these two columns).
function JoinCappedDisplay(AItems: TList<string>; ACap: Integer): string;
var Shown, I: Integer;
begin
  Result:= '';
  if (AItems = nil) or (AItems.Count = 0) then Exit;
  if AItems.Count > ACap then Shown:= ACap else Shown:= AItems.Count;
  for I:= 0 to Shown - 1 do
  begin
    if I > 0 then Result:= Result + ', ';
    Result:= Result + AItems[I];
  end;
  if AItems.Count > ACap then
    Result:= Result + Format(' (+%d more)', [AItems.Count - ACap]);
end;

// ADP2 T4: fills AReadsCsv/AWritesCsv (capped, display-ready strings) for one
// routine. AProc/ABody are the SAME defProc/body nodes Analyze already
// matched for Cyclomatic -- no second AST scan.
//
// FINDING THE OWNING CLASS -- ASym.ParentId IS usable here (ADP2 T4 fix wave:
// root-cause identity resolution). It used to NOT be: ASym was the caller's
// PRE-INSERT ParseRes.Symbols[I], so ASym.Id/.FileId were not yet assigned and
// ASym.ParentId was still an untranslated IN-ARRAY INDEX (DRagLint.Core.
// Indexer.IndexFile's symbols loop only translated parent_id to the real
// symbols.id on its OWN local copy, immediately before that loop's own
// FStore.UpsertSymbol call -- the facts loop, which calls Analyze, used to
// re-read the SAME untranslated ParseRes.Symbols[I] afterwards). This
// function used to work around that by re-resolving the routine's ALREADY-
// INSERTED row via AStore.FindFileIdByPath(AFilePath) + AStore.
// FindEnclosingRoutineByImpl(FileId, ASym.ImplStartLine) -- three SQL
// round-trips per routine, always-on, corpus-wide. The indexer's facts loop
// now resolves identity BEFORE calling Analyze instead (Id := the
// just-inserted DB id, FileId := the open file-tx's FileId, ParentId :=
// translated from its in-array index via the same IdxToId map the symbols
// loop uses) -- a pure in-memory fixup, no DB round-trip -- so ASym.ParentId
// (and .Id/.FileId) can be trusted directly here, and by every later fact
// group (T5-T8) that needs the owning symbol's identity: just read
// ASym.ParentId, do not re-resolve it via FindFileIdByPath/
// FindEnclosingRoutineByImpl.
//
// Fields considered are the resolved owning class's DIRECT children
// (AStore.FindAllChildSymbols) filtered to Kind = skField: OWN-CLASS fields
// only. Inherited-field resolution (walking ancestor classes for a field
// declared higher up) is explicitly OUT OF SCOPE for T4 (the brief marks it
// OPTIONAL/bounded; own-class fields are the high-signal core) -- an
// identifier that does not resolve to a DIRECT field of the owning class is
// simply never reported (absence over noise), even if it happens to be an
// inherited field. A free routine (ASym.ParentId <= 0) or an owning class
// with no field children both yield '' for both -- the renderer then omits
// the whole Reads/Writes line.
procedure AnalyzeReadsWrites(const AProc, ABody: TTSNode; const ASrc: TBytes;
  const ASym: TSymbol; const AFilePath: string; const AStore: ISymbolStore; out AReadsCsv, AWritesCsv: string);
var
  Fields       : TDictionary<string, string>;
  Kids         : TArray<TSymbol>;
  Kid          : TSymbol;
  LKey         : string;
  Vars         : TRoutineVarTable;
  Reads, Writes: TList<string>;
begin
  AReadsCsv := '';
  AWritesCsv:= '';
  if ABody.IsNull then Exit;
  // ADP2 T4 fix wave: ASym's identity is resolved by the caller (the
  // indexer's facts loop) before Analyze is called -- see this function's
  // header comment above -- so ASym.ParentId is read directly here, no
  // FindFileIdByPath/FindEnclosingRoutineByImpl re-resolution needed.
  // AFilePath is now unused by this function; left in the signature
  // unchanged (mechanical plumbing fix, not a signature change).
  if ASym.ParentId <= 0 then Exit; // free routine (no owning class) -- nothing to classify

  Fields:= TDictionary<string, string>.Create;
  Reads := TList<string>.Create;
  Writes:= TList<string>.Create;
  Vars  := nil;
  try
    Kids:= AStore.FindAllChildSymbols(ASym.ParentId);
    for Kid in Kids do
      if Kid.Kind = skField then
      begin
        LKey:= LowerCase(Kid.Name);
        if not Fields.ContainsKey(LKey) then Fields.Add(LKey, Kid.Name);
      end;
    if Fields.Count = 0 then Exit; // no owning-class fields -> nothing to classify

    Vars:= TRoutineVarTable.Build(AProc, ASrc); // params/locals/Result shadow same-named fields
    WalkFieldRW(ABody, ASrc, Fields, Vars, Reads, Writes);

    AReadsCsv := JoinCappedDisplay(Reads, FIELD_RW_CAP);
    AWritesCsv:= JoinCappedDisplay(Writes, FIELD_RW_CAP);
  finally
    Vars.Free;
    Writes.Free;
    Reads.Free;
    Fields.Free;
  end;
end;

// ADP2 T6: process-wide, SINGLE-ENTRY memoized cache of one .dfm's parsed
// event-binding map: HandlerName (lowercased key) -> display 'ObjectName.
// EventProp'. Re-parses ONLY when GDfmCachePath differs from the requested
// ADfmPath -- deliberately NOT a per-path TDictionary (unlike TAstParseCache,
// DRagLint.Diagnostics.ParseCache, which keeps one entry PER FILE until its
// own Clear is called): a routine's own .dfm sibling never changes mid-file,
// and the indexer's facts loop (DRagLint.Core.Indexer.IndexFile) processes
// one file's routines CONSECUTIVELY before moving to the next file's ('--jobs'
// parallelizes across whole SECTIONS/DBs, never within one file's own
// sequential symbol loop -- the SAME sequential-processing assumption
// TAstParseCache's per-process cache already relies on, see its own header
// comment), so in practice this parses each distinct .dfm exactly ONCE per
// index run: every OTHER routine in the SAME unit reuses the cached map: the
// analyzer moves on to a DIFFERENT file's .dfm only after the current file's
// last routine, at which point the single entry is simply overwritten (never
// grows, so no per-file Clear is needed to bound memory -- unlike
// TAstParseCache, which DOES accumulate one tree per file until the indexer
// calls Clear after each file's facts pass).
//
// Reads the .dfm's bytes directly (TFile.ReadAllBytes, UNTRANSCODED) rather
// than via EnsureUtf8Bytes (DRagLint.Core.Encoding, what the indexer's OWN
// generic IndexFile pipeline applies before handing bytes to ANY IParser,
// including TDFMParser): EnsureUtf8Bytes' UTF-16-BOM sniff treats a leading
// $FF as a (possible) UTF-16LE BOM marker, which would risk mis-transcoding
// -- and so defeating -- a REAL binary DFM's own leading-$FF signature before
// ExtractDfmEventBindings ever gets to check it. This analyzer's .dfm read is
// independent of that pipeline (the .dfm may not even be a walked/indexed
// file in this run at all -- it is read purely as ASym's sibling), so
// reading raw bytes and letting ExtractDfmEventBindings apply its own
// binary-DFM guard on the UNMODIFIED first byte is the safer choice; event-
// binding identifiers are always plain ASCII regardless, so no real-world
// text DFM loses fidelity here.
var
  GDfmCachePath: string                    ;
  GDfmCacheMap : TDictionary<string,string>;

function DfmEventMapFor(const ADfmPath: string): TDictionary<string,string>;
var
  Bindings: TArray<TDfmEventBinding>;
  EB      : TDfmEventBinding        ;
  Key     : string                  ;
begin
  if (GDfmCacheMap <> nil) and SameText(GDfmCachePath, ADfmPath) then Exit(GDfmCacheMap);

  FreeAndNil(GDfmCacheMap);
  GDfmCachePath:= ADfmPath;
  GDfmCacheMap := TDictionary<string,string>.Create;

  Bindings:= nil;
  try
    Bindings:= ExtractDfmEventBindings(TFile.ReadAllBytes(ADfmPath));
  except
    Bindings:= nil; // unreadable/unparseable .dfm -- absence over a wrong fact
  end;
  for EB in Bindings do
  begin
    Key:= LowerCase(EB.HandlerName);
    // First wiring wins: deterministic (ExtractDfmEventBindings returns
    // bindings in DOCUMENT order), matches this task's documented tie-break
    // for the rare case of one handler shared by multiple controls/events.
    if not GDfmCacheMap.ContainsKey(Key) then
      GDfmCacheMap.Add(Key, EB.ObjectName + '.' + EB.EventProp);
  end;
  Result:= GDfmCacheMap;
end;

// ADP2 T6: the DfmEvent fact for ASym -- '' when ASym has no owning class (a
// free routine can never be a DFM event handler: the .dfm always wires a
// handler to a METHOD of the form/frame class), the paired .dfm does not
// exist on disk (most units are not forms), or no On*-property in that .dfm
// happens to be wired to a method named ASym.Name. NAME-BASED (like
// DRagLint.Wiring's FindEventHandlersForForm/the underlying 'event-binding'
// reference): the owning class is not cross-checked against the .dfm's own
// root object's declared type, so two DIFFERENT classes in the same unit
// sharing a same-named method would both read back the same wiring -- an
// accepted, documented heuristic limitation (real forms declare each event
// handler once; this mirrors the existing event-binding mechanism's own
// scope, not a NEW gap this task introduces).
function AnalyzeDfmEvent(const ASym: TSymbol; const AFilePath: string): string;
var
  DfmPath: string;
  Map    : TDictionary<string,string>;
begin
  Result:= '';
  if ASym.ParentId <= 0 then Exit;
  DfmPath:= ChangeFileExt(AFilePath, '.dfm');
  if not TFile.Exists(DfmPath) then Exit;
  Map:= DfmEventMapFor(DfmPath);
  if Map = nil then Exit;
  Map.TryGetValue(LowerCase(ASym.Name), Result);
end;

class function TSymbolFactsAnalyzer.Analyze(const ASym: TSymbol; const AFilePath: string; const ABody: TArray<string>; const AStore: ISymbolStore): TSymbolFacts;
var
  PF   : TParsedFile     ;
  Procs: TArray<TTSNode> ;
  Proc : TTSNode         ;
  Body : TTSNode         ;
begin
  // Every fact field starts at Default(TSymbolFacts)'s zero value; Task 3
  // (ADP2) fills in Cyclomatic/BodyLoc below. Tasks 4/6 (ADP2) fill in
  // ReadsFields/WritesFields/DfmEvent (see below); Tasks 7-8 populate the
  // remaining groups -- ABody stays unused until then.
  Result:= Default(TSymbolFacts);
  Result.SymbolId:= ASym.Id;
  Result.Present := True;

  // BodyLoc: pure symbol-range arithmetic, no AST needed. Clamped to >= 0 as
  // a defensive guard (mirrors TIndexer.SliceBodyLines' Lo/Hi clip) though
  // ImplEndLine >= ImplStartLine always holds for a real routine body.
  Result.BodyLoc:= ASym.ImplEndLine - ASym.ImplStartLine;
  if Result.BodyLoc < 0 then Result.BodyLoc:= 0;

  // ADP2 T6: DfmEvent -- deliberately computed HERE, independent of the
  // Cyclomatic/ReadsWrites block below: unlike those two, this fact does not
  // need ASym's OWN .pas file AST at all (it needs the SIBLING .dfm's own
  // tree, via AnalyzeDfmEvent/DfmEventMapFor), so it must not be skipped
  // just because AFilePath's OWN parse happens to fail (PF.Tree = nil).
  Result.DfmEvent:= AnalyzeDfmEvent(ASym, AFilePath);

  // Cyclomatic: find the defProc node whose OWN StartPoint matches
  // ASym.ImplStartLine -- the EXACT provenance the parser used to stamp
  // ImplStartLine in the first place (DRagLint.Parser.Delphi13's defProc walk
  // calls SetRoutineImplRange(..., Integer(ANode.StartPoint.row) + 1, ...)
  // where ANode IS the defProc), so this lookup is guaranteed to find the
  // right routine whenever the same source parses the same way twice.
  // TAstParseCache.Get is memoized per file (see this unit's banner comment
  // and the indexer's facts-pass comment): the FIRST Analyze call for a file
  // parses it; every other routine in the SAME file reuses the cached tree --
  // one extra parse PER FILE (on top of the indexer's own parse), not per
  // routine. CfgFindProcs (DRagLint.Analysis.Cfg) collects every defProc in
  // the tree; an O(routines-in-file) linear scan then matches by line -- no
  // positional (point-based) node lookup is exposed by the TTSNode API, and
  // this walk is accepted as index-time cost (see the Phase 2 design).
  PF:= TAstParseCache.Get(AFilePath);
  if PF.Tree <> nil then
  begin
    Procs:= CfgFindProcs(PF.Tree.RootNode);
    for Proc in Procs do
      if Integer(Proc.StartPoint.Row) + 1 = ASym.ImplStartLine then
      begin
        Body:= Proc.ChildByField('body');
        Result.Cyclomatic:= TAstChecker.CyclomaticOf(Body);
        // ADP2 T4: Reads/Writes fields -- the SAME matched Proc/Body, no 2nd
        // AST scan. See AnalyzeReadsWrites' header comment (above, this
        // unit's implementation section) for the field-set + classification
        // rules.
        AnalyzeReadsWrites(Proc, Body, PF.Src, ASym, AFilePath, AStore, Result.ReadsFields, Result.WritesFields);
        Break;
      end;
    // No matching defProc: Cyclomatic stays 0 and Reads/WritesFields stay ''
    // (absence over a wrong number/fact -- e.g. a stale/mismatched parse, or
    // ASym's file changed between the indexer's own parse and this cache
    // lookup).
  end;
end;

// ADP2 T5: display cap + bounded reverse-hop depth/walk-size for the
// Covered-by-tests fact -- see ComputeCoveredBy's own header comment
// (interface section) and this unit's banner "TASK 5 OVERRIDE" +
// "IMPLEMENTATION NOTE" for the full rationale. COVERED_BY_CAP mirrors
// FIELD_RW_CAP's convention (a dedicated const per fact, not shared) but is
// deliberately smaller (5, not 8): CalledFrom's own display cap (DRagLint.
// Doc.Facts, docs.max_callers) already defaults to 5, and Covered-by is
// conceptually a FILTERED view of the same caller set, so matching that
// default keeps the two lines visually consistent.
const
  COVERED_BY_CAP     = 5;   // display cap + '(+N more)' threshold
  COVERED_BY_DEPTH   = 3;   // reverse hops walked (brief's suggested "<= 3")
  COVERED_BY_MAXWALK = 200; // hard cap on distinct caller routines expanded per render (see ComputeCoveredBy's remarks)

// LastSegment: "Unit.TClass.Method" -> "Method"; "Unit.Method" -> "Method";
// a bare name -> itself. Duplicated locally (mirrors DRagLint.Refactor.
// TestStub's own TSG_LastSegment, whose header comment states the same
// "keep this unit standalone" reasoning) rather than reaching into
// DRagLint.Doc.Facts' private, non-exported LastSeg -- which would also
// require Doc.Facts to export it, and Doc.Facts already `uses` THIS unit
// (for ComputeCoveredBy), so pulling the other way would be a real circular
// unit dependency.
function LastSegment(const S: string): string;
var P: Integer;
begin
  P:= S.LastDelimiter('.');
  if P >= 0 then Result:= Copy(S, P + 2, MaxInt) else Result:= S;
end;

// True when the caller routine identified by (ASymbolId, AQName, ALocation)
// -- one row of a FindResolvedCallers/FindUnresolvedNameCallers result -- is
// a TEST routine, by either of two GROUND-TRUTH rules (checked in this
// order, (a) first since it is a plain string comparison with NO extra store
// query, while (b) costs one):
//   (a) its DECLARING FILE's basename matches the '*Test'/'Test*' naming
//       convention, case-insensitive (the DUnitX corpus-wide convention --
//       e.g. 'UWidgetTests.pas' or 'TestWidget.pas'). ALocation is already
//       the bare caller filename (TResolvedCaller.Location's own contract:
//       "filename only"), so this is a query-free string check.
//   (b) ONLY when (a) does not match: its ENCLOSING CLASS transitively
//       descends from a class literally named 'TTestCase' (a legacy-DUnit-
//       style fixture) -- AStore.GetTransitiveAncestors, the SAME ancestry
//       walk DRagLint.Doc.Facts' Overrides/Implements gather already uses.
//       ASymbolId is the caller ROUTINE's own id (TResolvedCaller.
//       EnclosingSymbolId, already resolved by the caller), so no further
//       name-based re-resolution is needed here. GetTransitiveAncestors
//       returns UNRESOLVED heritage edges too (name-only leaves -- see its
//       own header comment), so this fires even when TTestCase itself (e.g.
//       DUnit's TestFramework.pas) is outside the indexed corpus, which is
//       the realistic case.
//
// A [Test]/[TestCase] CUSTOM ATTRIBUTE is deliberately NOT checked as a
// third rule (route (c) in the task brief): CONFIRMED by reading
// TIndexer.ResolveEnclosingSymbolId (DRagLint.Core.Indexer) that a
// reference's EnclosingSymbolId is resolved ONLY by testing the reference's
// line against a ROUTINE'S IMPLEMENTATION range (ImplStartLine..
// ImplEndLine). A custom attribute like '[Test]' decorates the BARE
// INTERFACE-SECTION declaration one or more lines above the routine's own
// body -- outside any routine's impl range -- so the 'attribute' reference
// the parser DOES emit (DRagLint.Parser.Delphi13's Walk, NodeType =
// 'attribute') always comes back with EnclosingSymbolId = 0 (unenclosed).
// No store primitive answers "does method M carry attribute X" any other
// way, so route (c) is skipped per the task's own documented contingency
// (route (a)/(b) are the "high-signal core"; attributes would be a bonus
// this index cannot currently support).
function IsTestRoutine(const AStore: ISymbolStore; ASymbolId: Int64; const ALocation: string): Boolean;
var
  BaseName : string;
  Sym      : TSymbol;
  ParentSym: TSymbol;
  Anc      : TTypeAncestor;
begin
  Result:= False;

  // (a) file-name convention -- query-free.
  BaseName:= ChangeFileExt(ALocation, '');
  if StartsText('Test', BaseName) or EndsText('Test', BaseName) then Exit(True);

  // (b) TTestCase ancestry -- only reached when (a) did not already match.
  if ASymbolId <= 0 then Exit;
  Sym:= AStore.GetSymbolById(ASymbolId);
  if Sym.ParentId <= 0 then Exit;
  ParentSym:= AStore.GetSymbolById(Sym.ParentId);
  if ParentSym.Kind <> skClass then Exit;
  for Anc in AStore.GetTransitiveAncestors(ParentSym.Id) do
    if SameText(Anc.Name, 'TTestCase') then Exit(True);
end;

function ComputeCoveredBy(const AStore: ISymbolStore; const ASym: TSymbol): string;
var
  Names  : TStringList;
  Visited: TDictionary<Int64, Boolean>; // caller-routine ids already expanded, across the WHOLE walk (cycle guard + the render-size cap)

  // Finds every caller of (ASymbolId as a resolved call_edges target) UNION
  // (AQName's last segment as a NAME match with no call_edges row) -- the
  // SAME two-bucket union DRagLint.Doc.Facts' 'Called from:' gather uses,
  // required here for the identical reason (see this unit's banner
  // "IMPLEMENTATION NOTE"): TCallResolver never resolves a bare call from a
  // method to a DIFFERENT unit's routine, so the DUnitX test->target edge
  // only ever shows up in the unresolved/name-based bucket. Recurses one
  // hop per call, up to ADepth, expanding EVERY newly-discovered caller
  // exactly once (Visited, shared across the whole walk) and stopping once
  // COVERED_BY_MAXWALK distinct callers have been expanded (a render-time
  // safety net against a pathologically hot symbol).
  procedure Walk(ASymbolId: Int64; const AQName: string; ADepth: Integer);
  var
    RC       : TResolvedCaller;
    Combined : TArray<TResolvedCaller>;
    HopSeen  : TDictionary<Int64, Boolean>; // dedupes a caller seen in BOTH buckets at THIS hop
  begin
    if ADepth <= 0 then Exit;
    Combined:= nil;
    if ASymbolId > 0 then
      Combined:= Combined + AStore.FindResolvedCallers(ASymbolId);
    if AQName <> '' then
      Combined:= Combined + AStore.FindUnresolvedNameCallers(LastSegment(AQName));
    if Length(Combined) = 0 then Exit;

    HopSeen:= TDictionary<Int64, Boolean>.Create;
    try
      for RC in Combined do
      begin
        if RC.EnclosingSymbolId <= 0 then Continue; // no enclosing routine -- nothing to attribute the call to
        if HopSeen.ContainsKey(RC.EnclosingSymbolId) then Continue;
        HopSeen.Add(RC.EnclosingSymbolId, True);
        if Visited.ContainsKey(RC.EnclosingSymbolId) then Continue; // already expanded (earlier hop, or another branch) -- cycle guard
        if Visited.Count >= COVERED_BY_MAXWALK then Exit; // hard walk-size cap reached
        Visited.Add(RC.EnclosingSymbolId, True);
        if IsTestRoutine(AStore, RC.EnclosingSymbolId, RC.Location) then
          Names.Add(RC.EnclosingQName);
        Walk(RC.EnclosingSymbolId, RC.EnclosingQName, ADepth - 1);
      end;
    finally
      HopSeen.Free;
    end;
  end;

begin
  Result:= '';
  if ASym.Id <= 0 then Exit;
  // Only routine-like symbols can be "covered by tests" -- a type/field/
  // const/unit can never be a call target, so FindResolvedCallers et al.
  // would trivially return nothing for them anyway; this early-out just
  // skips the (otherwise harmless but wasted) walk for `document --project`'s
  // many non-routine symbols. Mirrors DRagLint.Doc.Facts' "cheap fact group"
  // kind-gate.
  if not (ASym.Kind in [skMethod, skConstructor, skDestructor, skFunction, skProcedure]) then Exit;

  Names  := TStringList.Create;
  Visited:= TDictionary<Int64, Boolean>.Create;
  try
    Names.Sorted      := True;      // DETERMINISTIC order regardless of walk/encounter order
    Names.Duplicates  := dupIgnore; // the SAME test can be reached via >1 reverse path/hop
    Names.CaseSensitive:= False;
    Visited.Add(ASym.Id, True); // seed with the root itself -- a (mutually) recursive target must never be re-attributed as its own "covered by" caller
    Walk(ASym.Id, ASym.QualifiedName, COVERED_BY_DEPTH);

    if Names.Count = 0 then Exit;

    // JoinCappedDisplay (above, this unit) applies the SAME cap+'(+N more)'
    // convention ReadsFields/WritesFields already use -- reused rather than
    // re-implemented. It wants a TList<string>; Names is a sorted/deduped
    // TStringList, so its (already-ordered) contents are copied across.
    var Capped: TList<string>:= TList<string>.Create;
    try
      Capped.AddRange(Names.ToStringArray);
      Result:= JoinCappedDisplay(Capped, COVERED_BY_CAP);
    finally
      Capped.Free;
    end;
  finally
    Visited.Free;
    Names.Free;
  end;
end;

end.
