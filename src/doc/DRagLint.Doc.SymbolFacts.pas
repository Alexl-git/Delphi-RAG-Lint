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

type
  /// <summary>Index-time analyzer that derives a TSymbolFacts row for one
  /// routine symbol -- the single call site the indexer uses for every fact
  /// group Phase 2 will ever add (see the unit banner comment).</summary>
  TSymbolFactsAnalyzer = class
    public
      /// <summary>Analyzes ASym's body and returns the TSymbolFacts row to
      /// persist for it. Task 2 returned an EMPTY-but-Present record; Task 3
      /// (ADP2) filled in Cyclomatic/BodyLoc; Task 4 (ADP2) fills in
      /// ReadsFields/WritesFields (see below); Tasks 5-8 populate the
      /// remaining groups one at a time. Never returns Present=False (the
      /// indexer only calls this for a symbol it is about to write a row
      /// for).</summary>
      /// <param name="ASym">The routine symbol being analyzed. Result.SymbolId
      /// is seeded from ASym.Id, but the caller (the indexer) always
      /// overwrites it with the just-inserted DB id afterward -- ASym.Id may
      /// still be a pre-insert placeholder at the point Analyze runs.</param>
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
      /// + read/write classification rules.</remarks>
      class function Analyze(const ASym: TSymbol; const AFilePath: string; const ABody: TArray<string>; const AStore: ISymbolStore): TSymbolFacts; static;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Collections       { ADP2 T4: TDictionary/TList for the field-name set + ordered read/write lists }
  , TreeSitter                        { ADP2 T3: TTSNode for the AST-derived Cyclomatic fact }
  , DRagLint.Diagnostics.ParseCache    { ADP2 T3: TAstParseCache -- memoized per-file tree, owned by the cache }
  , DRagLint.Analysis.Cfg              { ADP2 T3: CfgFindProcs -- collect every defProc in the file's tree }
  , DRagLint.Analysis.Flow.Lattices    { ADP2 T4: TRoutineVarTable -- a same-named local/param/Result shadows a field, never misclassified as one }
  , DRagLint.Diagnostics.AstChecks     { ADP2 T3: TAstChecker.CyclomaticOf -- ONE shared formula with the lint rule }
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
// FINDING THE OWNING CLASS -- ASym.ParentId is NOT usable here. At the point
// Analyze runs, ASym is the caller's PRE-INSERT ParseRes.Symbols[I] (see this
// unit's Analyze <param name="ASym"> comment: "ASym.Id may still be a
// pre-insert placeholder"). The SAME caveat applies, less obviously, to
// ASym.ParentId: DRagLint.Core.Indexer.IndexFile's symbols loop stamps
// parent_id as an IN-ARRAY INDEX into ParseRes.Symbols at parse time and only
// TRANSLATES it to the real symbols.id via its local IdxToId map ("Translate
// in-array parent index to actual DB id") immediately before THAT loop's own
// FStore.UpsertSymbol call -- the facts loop (which calls Analyze) re-reads
// the SAME ParseRes.Symbols[I] afterwards, so the ASym it hands Analyze still
// carries the UNTRANSLATED, meaningless index. (Confirmed empirically: an
// earlier version of this function used ASym.ParentId directly and
// FindAllChildSymbols always came back empty/wrong -- ADP2 T4's own RED/GREEN
// cycle caught it.) Fix: re-resolve THIS SAME routine's ALREADY-INSERTED row
// via AStore.FindEnclosingRoutineByImpl(FileId, ASym.ImplStartLine) --
// symbols are fully committed by the time the facts loop runs (it is a
// separate, later pass over the same file), so this query returns the real
// row, correctly parent-linked. FileId itself is resolved fresh via
// AStore.FindFileIdByPath(AFilePath) rather than trusting ASym.FileId, for
// the same pre-insert-placeholder reason.
//
// Fields considered are the resolved owning class's DIRECT children
// (AStore.FindAllChildSymbols) filtered to Kind = skField: OWN-CLASS fields
// only. Inherited-field resolution (walking ancestor classes for a field
// declared higher up) is explicitly OUT OF SCOPE for T4 (the brief marks it
// OPTIONAL/bounded; own-class fields are the high-signal core) -- an
// identifier that does not resolve to a DIRECT field of the owning class is
// simply never reported (absence over noise), even if it happens to be an
// inherited field. A free routine (no enclosing type), an unresolvable
// file/routine lookup, or an owning type with no field children all yield ''
// for both -- the renderer then omits the whole Reads/Writes line.
procedure AnalyzeReadsWrites(const AProc, ABody: TTSNode; const ASrc: TBytes;
  const ASym: TSymbol; const AFilePath: string; const AStore: ISymbolStore; out AReadsCsv, AWritesCsv: string);
var
  FileId       : Int64;
  SelfSym      : TSymbol;
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

  FileId:= AStore.FindFileIdByPath(AFilePath);
  if FileId <= 0 then Exit;
  SelfSym:= AStore.FindEnclosingRoutineByImpl(FileId, ASym.ImplStartLine);
  if (SelfSym.Id <= 0) or (SelfSym.ParentId <= 0) then Exit; // free routine, or lookup failed

  Fields:= TDictionary<string, string>.Create;
  Reads := TList<string>.Create;
  Writes:= TList<string>.Create;
  Vars  := nil;
  try
    Kids:= AStore.FindAllChildSymbols(SelfSym.ParentId);
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

class function TSymbolFactsAnalyzer.Analyze(const ASym: TSymbol; const AFilePath: string; const ABody: TArray<string>; const AStore: ISymbolStore): TSymbolFacts;
var
  PF   : TParsedFile     ;
  Procs: TArray<TTSNode> ;
  Proc : TTSNode         ;
  Body : TTSNode         ;
begin
  // Every fact field starts at Default(TSymbolFacts)'s zero value; Task 3
  // (ADP2) fills in Cyclomatic/BodyLoc below. Tasks 4-8 populate
  // ReadsFields/WritesFields/ReturnsOwner/DfmEvent/SqlReads/SqlWrites/
  // CoveredBy in turn, each inside this same function body -- ABody/AStore
  // stay unused until then.
  Result:= Default(TSymbolFacts);
  Result.SymbolId:= ASym.Id;
  Result.Present := True;

  // BodyLoc: pure symbol-range arithmetic, no AST needed. Clamped to >= 0 as
  // a defensive guard (mirrors TIndexer.SliceBodyLines' Lo/Hi clip) though
  // ImplEndLine >= ImplStartLine always holds for a real routine body.
  Result.BodyLoc:= ASym.ImplEndLine - ASym.ImplStartLine;
  if Result.BodyLoc < 0 then Result.BodyLoc:= 0;

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

end.
