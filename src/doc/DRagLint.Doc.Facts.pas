unit DRagLint.Doc.Facts;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  System.Generics.Collections, System.RegularExpressions,
  DRagLint.Core.Model, DRagLint.Core.Interfaces, DRagLint.Doc.GitSince,
  DRagLint.Hover.Returns;

const
  // Display cap for the <seealso> related-symbol list (ADF T4). At most this many
  // <seealso cref> lines are emitted, keeping the managed block terse.
  SEEALSO_CAP = 5;
  // v(ADP1 T3): display cap for the 'Overridden by:' descendant-method list --
  // at most this many are shown; OverriddenByTotal carries the true count so the
  // renderer can add '(+N more)', mirroring CalledFrom's cap discipline.
  OVERRIDDENBY_CAP = 6;

type
  TDocFactRef = record
    Display   : string;   { e.g. 'Unit1.DoThing' }
    Location  : string;   { file name only, e.g. 'U1.pas' -- NO :line (volatile) }
    // v14 (D5): 'certain' | 'ambiguous' | 'unverified' | ''. The renderer marks
    // any value OTHER than 'certain'/'' with a trailing ' ?' (honest uncertainty):
    // 'ambiguous' = resolved to this symbol but >1 candidate on the type chain;
    // 'unverified' = a CALL SITE whose name matches but which has NO call_edges
    // row (receiver untypable). v(ADP3 T3i): "call site" is load-bearing -- a
    // usage ref (read/write/type_use/member-access) is not one, see
    // REF_KIND_CALL in DRagLint.Core.Model.
    Confidence: string;
  end;

  /// <summary>Index-grounded facts about one symbol, for the managed
  /// DocInsight remarks block. All lists are capped for display; the *Total
  /// fields carry the true count so the renderer can add '(+N more)'.</summary>
  TDocFacts = record
    CalledFrom     : TArray<TDocFactRef>;
    Calls          : TArray<string>     ;
    UsedInUnits    : TArray<string>     ;
    Raises         : TArray<string>     ;
    ReturnType     : string             ;
    // v(item1 T8): distinct return-expression RHS strings mined from the
    // function's body via the hover MineReturnExpressions miner (DRagLint.
    // Hover.Returns) -- the SAME pure miner the hover popup uses, so hover
    // and autodoc's <returns> agree. RAW (XML-unescaped); Task 9's emit
    // escapes at render time. Capped at Build's AMaxReturnCases (first-seen
    // order, truncated). Empty for procedures (ReturnType = '') and whenever
    // AMaxReturnCases <= 0 (enumeration disabled -> bare TODO at emit).
    ReturnCases    : TArray<string>     ;
    CalledFromTotal: Integer            ;
    CallsTotal     : Integer            ;
    UsedInTotal    : Integer            ;
    // v(ADF T3): ground-truth from the Pascal 'deprecated' DIRECTIVE on the decl
    // (NOT the <deprecated/> doc-comment TAG -- see DRagLint.Parser.DocComments'
    // TParsedDoc.Deprecated for that unrelated concept). Neither Signature nor
    // Modifiers captures the directive (Modifiers is visibility-only, Signature is
    // args+return-type only -- confirmed empirically), so Build falls back to a
    // source-line read at the declaration's StartLine. Deprecated=True whenever the
    // directive is present; DeprecatedMsg holds the optional message string
    // (quotes stripped), '' for a bare 'deprecated;'.
    Deprecated     : Boolean            ;
    DeprecatedMsg  : string             ;
    // v(ADF T4): OPT-IN <seealso> doc-source. The RELATED symbols for the decl,
    // each a REAL indexed qualified name (a resolved outgoing callee UNION a
    // sibling member of the same parent type), deduped, sorted, and capped at
    // SEEALSO_CAP. Populated ONLY when Build's AIncludeSeeAlso is True (the
    // --seealso opt-in); empty otherwise, so RenderFactsBlock emits no <seealso>
    // lines by default. NEVER holds a '?'-tagged/unverified/fabricated name --
    // "related" is a heuristic, but every entry is ground-truth.
    SeeAlso        : TArray<string>     ;
    // v(ADF T5): OPT-IN <since> doc-source. The git commit date (YYYY-MM-DD) of
    // the declaration line, derived via TGitSince.FirstCommitDate. Populated ONLY
    // when Build's AIncludeSince is True (the --since opt-in) AND git CONFIDENTLY
    // attributes the line; '' in every failure mode (no git, untracked file,
    // non-zero exit, unparseable output, exception). NEVER a guessed/stale date
    // -- absence over a wrong fact. Empty by default, so RenderFactsBlock emits no
    // <since> line unless --since was passed and git succeeded.
    Since          : string             ;
    // v(ADP1 T3): cheap fact group -- overrides / overridden-by / implements /
    // overload / virtual+abstract markers. Gathered UNCONDITIONALLY (no opt-in
    // flag, like Deprecated) whenever ASym is method-like (skMethod/
    // skConstructor/skDestructor) with a parent (ASym.ParentId > 0); empty/False
    // for everything else (free routines, types, fields, ...).
    //
    // Overrides: the QUALIFIED NAME of the same-named method on the NEAREST
    // resolved CLASS ancestor (via GetTransitiveAncestors + FindChildSymbolByName
    // -- the same helpers PropTree's ResolveInheritedType uses), or '' when ASym
    // does not override an ancestor method.
    Overrides        : string           ;
    // Overridden by: QUALIFIED NAMES of same-named methods on TRANSITIVE
    // DESCENDANT classes (via FindDescendantNames), capped at OVERRIDDENBY_CAP;
    // OverriddenByTotal carries the true distinct count for the renderer's
    // '(+N more)' suffix (mirrors CalledFrom/CalledFromTotal). Empty when no
    // descendant redeclares the method.
    OverriddenBy     : TArray<string>   ;
    OverriddenByTotal: Integer          ;
    // Implements: the QUALIFIED NAME of a same-named member on a resolved
    // INTERFACE ancestor (NAME-BASED ONLY -- no signature-match helper exists in
    // the index, so this is a heuristic, not a verified interface-method proof;
    // see DetectMethodDirectives'/the gather block's header comment). '' when
    // ASym's class implements no interface declaring the same member name.
    Implements       : string           ;
    // Overload k of n: ASym's 1-based position (by declaration StartLine order)
    // among its same-named siblings under the same parent (via
    // FindAllChildSymbols -- the same helper SeeAlso's sibling walk already
    // uses), and the sibling-set size. OverloadCount stays 0/1 (never rendered,
    // RenderFactsBlock requires > 1) when ASym has no same-named sibling.
    OverloadOrdinal  : Integer          ;
    OverloadCount    : Integer          ;
    // virtual / abstract directive markers: GROUND-TRUTH from a bounded SOURCE
    // PROBE (see DetectMethodDirectives) -- the index has NO abstract signal at
    // all, and TSymbol.IsVirtual (Model.pas) COLLAPSES virtual/dynamic/override
    // into one flag, so neither can be read back from stored symbol data. IsVirtual
    // here is True only for a ROOT virtual/dynamic declaration (the override
    // directive is ALSO present -> Overrides is populated instead, so the two
    // lines are never both emitted for the same decl). IsAbstract is True
    // whenever the 'abstract' directive is present, independent of override.
    IsAbstract       : Boolean          ;
    IsVirtual        : Boolean          ;
    // v(ADP2 T3): the routine's McCabe cyclomatic complexity and implementation
    // body line count, read back verbatim from the index-time symbol_facts row
    // (ISymbolStore.GetSymbolFacts -- see DRagLint.Doc.SymbolFacts.
    // TSymbolFactsAnalyzer.Analyze for how they were computed at index time).
    // RAW values, UNTHRESHOLDED here: Build never drops/zeroes Cyclomatic based
    // on docs.complexity_min -- RenderFactsBlock applies that threshold at
    // RENDER time (see its own comment), so changing complexity_min needs no
    // reindex. Cyclomatic = 0 when the symbol has no symbol_facts row (older
    // index, pre-Phase-2) or the analyzer found no matching defProc; either
    // way RenderFactsBlock's >= threshold naturally omits the line (0 is never
    // >= a positive complexity_min) -- absence over a wrong number.
    Cyclomatic       : Integer          ;
    BodyLoc          : Integer          ;
    // v(ADP2 T4): which of the owning class's OWN (non-inherited) instance
    // fields this routine reads vs. writes, read back verbatim from the
    // index-time symbol_facts row (ISymbolStore.GetSymbolFacts -- see
    // DRagLint.Doc.SymbolFacts.TSymbolFactsAnalyzer.Analyze /
    // AnalyzeReadsWrites for the classification rules). RAW PASSTHROUGH, like
    // Cyclomatic/BodyLoc above: the value is ALREADY display-ready (', '-
    // joined, capped at 8 entries, a ' (+N more)' suffix appended when
    // truncated -- see JoinCappedDisplay) because these two columns carry no
    // companion *Total field to defer the cap decision to render time. '' for
    // a free routine (no owning class), an owning class/record with no field
    // children, or an older index with no symbol_facts row -- RenderFactsBlock
    // omits the corresponding side (or the whole line) exactly as it does for
    // every other absent fact.
    ReadsFields      : string           ;
    WritesFields     : string           ;
    // v(ADP2 T5): Covered-by-tests -- CONTROLLER OVERRIDE, computed LAZILY
    // here in Build (NOT read back from symbol_facts.covered_by, which stays
    // unwritten/reserved -- see DRagLint.Doc.SymbolFacts' unit banner "TASK 5
    // OVERRIDE" comment for why a reverse test->target edge cannot be filled
    // deterministically at index time). Via DRagLint.Doc.SymbolFacts.
    // ComputeCoveredBy: a bounded reverse call-graph closure -- a hand-rolled
    // BFS over FindResolvedCallers+FindUnresolvedNameCallers, NOT DRagLint.
    // Report.RCallTree (see that unit's banner "IMPLEMENTATION NOTE" for the
    // empirically-confirmed reason a resolved-only reverse tree misses the
    // realistic DUnitX case) -- filtered to routines detected as TESTS (unit/
    // file '*Test' naming convention, or TTestCase ancestry -- see
    // ComputeCoveredBy/IsTestRoutine for the full ruleset and the confirmed
    // reason a [Test] attribute cannot be used as a third rule). Already
    // DISPLAY-READY (', '-joined, capped, a ' (+N more)' suffix when
    // truncated) -- the SAME raw-passthrough contract as ReadsFields/
    // WritesFields above. '' when ASym is not routine-like or no caller, at
    // any bounded hop, is detected as a test.
    CoveredBy        : string           ;
    // v(ADP2 T6): DFM event-wiring -- 'ObjectName.EventProp' (e.g.
    // 'Button1.OnClick') when ASym is a published method wired as an event
    // handler in its OWN .pas file's paired .dfm sibling, read back verbatim
    // from the index-time symbol_facts row (ISymbolStore.GetSymbolFacts --
    // see DRagLint.Doc.SymbolFacts.TSymbolFactsAnalyzer.Analyze /
    // AnalyzeDfmEvent for how it was computed at index time: a focused
    // extractor, DRagLint.Parser.DFM.ExtractDfmEventBindings, parses the
    // paired .dfm and matches ASym.Name against its (object, event-property,
    // handler) triples). RAW PASSTHROUGH, like Cyclomatic/BodyLoc/
    // ReadsFields/WritesFields above -- already the final display string, no
    // cap/threshold logic needed. '' when ASym has no owning class, has no
    // paired .dfm on disk, is not wired to any On*-property in it, or the
    // index predates Phase 2 Task 6 (no symbol_facts row / older column) --
    // absence over a guessed fact.
    DfmEvent         : string           ;
    // v(ADP2 T7): SQL tables touched -- which tables a routine that builds
    // SQL (string literals) reads (FROM/JOIN) vs. writes (INSERT INTO/
    // UPDATE/'UPDATE OR INSERT INTO'/DELETE FROM), read back verbatim from
    // the index-time symbol_facts row (ISymbolStore.GetSymbolFacts -- see
    // DRagLint.Doc.SymbolFacts.TSymbolFactsAnalyzer.Analyze/
    // AnalyzeSqlTables for the extraction pipeline: a NET-NEW, deliberately-
    // not-a-parser literal-concatenation + keyword-anchored table scan --
    // NOT DRagLint.Parser.Sql, which is Firebird DDL over *.sql schema-
    // migration files only and never parses a trigger/procedure body for
    // DML references). RAW PASSTHROUGH, like Cyclomatic/BodyLoc/
    // ReadsFields/WritesFields/DfmEvent above -- already the final display
    // CSVs (', '-joined, capped at 8, a ' (+N more)' suffix when
    // truncated), no cap/threshold logic needed here. '' for either/both
    // when the routine builds no recognizable SQL, its SQL is dynamically
    // assembled (a non-literal operand anywhere in a '+' concatenation), or
    // the index predates Phase 2 Task 7 -- absence over a guessed table.
    SqlReads         : string           ;
    SqlWrites        : string           ;
    // v(ADP2 T8): returned-object ownership -- 'new' (a freshly-constructed
    // object the caller must free), 'borrowed' (a reference the routine does
    // NOT own -- an own-class field or a parameter), 'self', or '' (ABSENCE
    // OVER A WRONG VERDICT: no return site, a disposed Result, ANY
    // unresolved/'unknown' site, a mix of categories across sites, or a
    // 'borrowed'/'self' verdict on a non-reference return type all yield '')
    // -- read back verbatim from the index-time symbol_facts row
    // (ISymbolStore.GetSymbolFacts -- see DRagLint.Doc.SymbolFacts.
    // TSymbolFactsAnalyzer.Analyze/AnalyzeReturnsOwner for the full
    // site-collection + unanimity + object-type-gate ruleset). RAW
    // PASSTHROUGH, like Cyclomatic/BodyLoc/ReadsFields/WritesFields/
    // DfmEvent/SqlReads/SqlWrites above -- already the final stored word, no
    // cap/threshold logic needed; RenderFactsBlock maps 'new' to the fuller
    // 'new (caller owns)' display text at render time.
    ReturnsOwner     : string           ;
    // v(ADP3 T3): the harvested summary text (Task 7 fills this in by mining
    // an adjacent hand-written // comment; until then it is ALWAYS ''). Added
    // in T3 so MergeComment's omit-when-empty guards are real and compile
    // against a genuine field rather than a placeholder -- a fresh/managed
    // <summary> is emitted ONLY when this is non-empty; '' means "nothing to
    // say", so the tag is omitted entirely rather than emitted blank.
    HarvestedSummary : string           ;
  end;

  TDocFactsBuilder = class
  public
    /// <summary>Builds the grounded facts for ASym from the index. When
    /// AIncludeSeeAlso is True (the --seealso opt-in), also populates
    /// Result.SeeAlso with the capped related-symbol crefs (resolved callees +
    /// siblings); when False, SeeAlso is left empty. When AIncludeSince is True
    /// (the --since opt-in), populates Result.Since with the git commit date of
    /// the declaration line (via TGitSince, using ABaseDir as the repo root);
    /// '' when git is absent / the line can't be attributed. NO git subprocess
    /// runs unless AIncludeSince is True. Also UNCONDITIONALLY populates the
    /// cheap Overrides/OverriddenBy/Implements/Overload/IsAbstract/IsVirtual
    /// fact group (v(ADP1 T3)) whenever ASym is method-like (skMethod/
    /// skConstructor/skDestructor) with a parent; see each TDocFacts field's own
    /// comment for how it is derived.</summary>
    /// <param name="AStore">Open symbol store to query; not owned. Must not be nil.</param>
    /// <param name="ASym">The symbol to document.</param>
    /// <param name="AIncludeSeeAlso">Opt-in: compute the &lt;seealso&gt; related set. Default False.</param>
    /// <param name="AIncludeSince">Opt-in: derive the git &lt;since&gt; date. Default False.</param>
    /// <param name="ABaseDir">Repo root for the git &lt;since&gt; lookup; '' -&gt; the file's own directory. Default ''.</param>
    /// <param name="AExtraStores">Additional index stores searched ONLY for name-based
    /// callers/used-in units, so cross-DB callers surface; nil/empty = single-store. Default nil.</param>
    /// <param name="AMaxReturnCases">Cap on Result.ReturnCases (v(item1 T8)): at most
    /// this many distinct mined return expressions are kept (first-seen order,
    /// truncated). 0 or negative disables enumeration entirely (ReturnCases stays
    /// empty). Default 20.</param>
    /// <param name="AMaxCallers">Cap on Result.CalledFrom (v(ADP1 T1)): at most
    /// this many distinct resolved/unverified callers are kept (same first-seen
    /// order as the underlying dedupe), truncated; Result.CalledFromTotal always
    /// carries the true distinct count so the renderer can add '(+N more)'. 0 or
    /// negative shows no callers (CalledFrom stays empty, total unaffected).
    /// Default 5.</param>
    class function Build(const AStore: ISymbolStore; const ASym: TSymbol;
      AIncludeSeeAlso: Boolean = False; AIncludeSince: Boolean = False;
      const ABaseDir: string = ''; const AExtraStores: TArray<ISymbolStore> = nil;
      AMaxReturnCases: Integer = 20; AMaxCallers: Integer = 5): TDocFacts;
  end;

  /// <summary>Applies the display cap: a list of ATotal items shows all of them
  /// UNLESS ATotal > 15, in which case only the first 10 are kept and the caller
  /// appends '(+N more)' with N = ATotal - 10. Returns how many to display.</summary>
  function DocDisplayCount(ATotal: Integer): Integer;

implementation

uses
  DRagLint.Doc.SymbolFacts; // v(ADP2 T5): ComputeCoveredBy -- see TDocFacts.CoveredBy's comment

function DocDisplayCount(ATotal: Integer): Integer;
begin
  if ATotal > 15 then Result:= 10 else Result:= ATotal;
end;

function LastSeg(const S: string): string;
var P: Integer;
begin
  P:= S.LastDelimiter('.');
  if P >= 0 then Result:= Copy(S, P + 2, MaxInt) else Result:= S;
end;

// v(ADP1 Bug D): True when ARef is a class's OWN self-reference -- a qualified
// implementation header (e.g. 'function TThing.Add: Integer;') emits a
// type_use ref of NameText='TThing' whose EnclosingSymbolId is the method
// itself (TThing.Add). Such a ref is not a genuine "TThing is used here"
// site; it is the class referencing its own name in its own member header.
// Only the "Used in units" gather (below) calls this -- it is a LOCAL
// post-filter, not a change to the shared FindCallersByName query (see that
// block's comment for why FindCallersByName itself must keep matching
// self-refs).
//
// CRITICAL (carried from the twin Bug C fix): a ref with EnclosingSymbolId
// <= 0 is OUTSIDE any routine body (e.g. a unit-scope 'var GThing: TThing;')
// and is NOT a self-reference -- it must be KEPT. Only a ref enclosed by a
// MEMBER of a type SAME-NAMED as ATypeName is a self-reference. AStore.
// GetSymbolById returns a zero/empty TSymbol (Id=0, ParentId=0) for a
// not-found id, so the ParentId<=0 guard also fails safe (keeps the ref)
// when a lookup can't find the enclosing symbol.
function RefIsOwnMemberSelfRef(const AStore: ISymbolStore; const ARef: TReference;
  const ATypeName: string): Boolean;
var Encl, Parent: TSymbol;
begin
  Result:= False;
  if ARef.EnclosingSymbolId <= 0 then Exit;
  Encl:= AStore.GetSymbolById(ARef.EnclosingSymbolId);
  if Encl.ParentId <= 0 then Exit;
  Parent:= AStore.GetSymbolById(Encl.ParentId);
  Result:= SameText(Parent.Name, ATypeName) and (Parent.Kind in [skClass, skInterface, skRecord]);
end;

// v(ADP3 T3i review round 2): can a symbol of this kind ever BE a call target?
// Only a routine can: TCallResolver resolves a call ref to a routine symbol, so
// call_edges.target_symbol_id is always a routine and FindResolvedCallers can
// never return a row for anything else.
//
// v(ADP3 T3i review round 4): THIS HEADER IS THE SINGLE SOURCE for "which kinds
// are exempt from the call-site restriction, and why". The two CalledFrom call
// sites below, the ISymbolStore declaration in DRagLint.Core.Interfaces and the
// store implementation in DRagLint.Storage.SQLite all POINT HERE and write no
// kind list of their own -- because every hand-written enumeration of this set
// has so far been WRONG: once as a code literal (round 1, below) and twice as a
// five-kind paraphrase in comments, retired by round 4.
//
// THE EXEMPT SET IS THE WHOLE COMPLEMENT, NOT A SHORTLIST OF TYPE KINDS. Do not
// write the complement out. Build (this unit) has four callers -- the `document`
// path, doc drift, the CLI `hover` verb and the LSP hover -- and the CalledFrom
// gather has no kind gate of its own, so the two hover callers reach the exempt
// branch with whatever kind the cursor resolved to: skProperty, skField,
// skVarDecl, skConstDecl, skEnumValue, skForm, skUnit, the skSql* kinds and even
// skLocalVar / skParam, not merely the five documentable type kinds
// Doc.Batch.IsDocumentableKind admits.
//
// This -- not a list of "type-like" kinds -- is the correct gate for the
// CalledFrom gather's call-sites-only restriction. For a NON-routine symbol the
// unresolved bucket has never held call sites at all: it holds plain references
// to the symbol's NAME, which the renderer then labels "Called from:". The label
// is the defect; relabelling it (the planned "Used by:" for types) is owned by
// the render workstream. Restricting a non-routine to call sites therefore does
// not correct a caller list, it DELETES a reference list -- so we restrict
// exactly when the symbol could genuinely have callers, and the non-routine path
// stays byte-identical to pre-T3i for EVERY kind.
//
// ROUND 1 GOT THIS WRONG, and the way it was wrong is the lesson: the gate was a
// literal [skClass, skInterface, skRecord], which is the set
// run_doc_no_self_caller.ps1 happens to pin -- the boundary was drawn by what a
// test covered rather than by the semantics. skEnum and skTypeAlias are equally
// documentable (see Doc.Batch.IsDocumentableKind) and silently lost their line.
// PINNED BY tests/autotest/run_doc_no_self_caller.ps1 (a class, including the
// NULL-enclosing unit-scope reference a Bug C regression once dropped) and
// tests/callresolve/run_callsite_kind_universe.ps1 (a class AND an enum).
//
// NOT EXPORTED -- it lives in this unit's implementation section, so a
// cross-unit reader is pointed at it by name rather than calling it. Noted
// because DRagLint.Doc.SymbolFacts' ComputeCoveredBy asks this exact question
// with its own literal copy of the same five kinds at the routine's tail;
// collapsing that duplicate would mean exporting this function, which is a CODE
// change and out of scope for a comments-only round (recorded in
// task-3i-report.md round 4 rather than done).
function CanBeCallTarget(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor];
end;

// Parses the return type from a signature: the text after the LAST ':' that is
// outside the parameter parentheses. '' when none (a procedure).
function ParseReturnType(const ASig: string): string;
var CloseP, Colon: Integer;
begin
  Result:= '';
  CloseP:= ASig.LastDelimiter(')');
  Colon := ASig.LastDelimiter(':');
  if (Colon > CloseP) and (Colon >= 0) then
    Result:= Trim(Copy(ASig, Colon + 2, MaxInt)).TrimRight([';']);
end;

// True for identifiers that appear as 'Word(' but are Pascal reserved words /
// control-flow / typecasts, not real call targets. Kept out of the Calls list.
function IsCallSkipWord(const AWord: string): Boolean;
const
  SKIP: array[0..13] of string = (
    'if', 'while', 'for', 'case', 'with', 'and', 'or', 'not', 'in',
    'array', 'set', 'string', 'to', 'downto');
var W: string;
begin
  W:= LowerCase(AWord);
  for var S in SKIP do
    if W = S then Exit(True);
  Result:= False;
end;

// True when C can start a Pascal identifier: letter or underscore.
function IsIdentStart(C: Char): Boolean;
begin
  Result:= (C = '_') or ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

// True when C can continue a Pascal identifier: letter, digit, or underscore.
function IsIdentPart(C: Char): Boolean;
begin
  Result:= IsIdentStart(C) or ((C >= '0') and (C <= '9'));
end;

// Scans ONE source line for call sites: an identifier immediately followed by
// '(' (allowing spaces before the paren). Adds each captured name to AAcc.
// Lexer-aware within the single line: skips '...' string literals (Pascal
// doubles '' for an embedded quote), stops at a // line comment, and tracks
// { } brace-comment depth. LIMITATION: a { } comment that OPENS on an earlier
// line is not seen here (we scan one line at a time) -- accepted best-effort
// for Chunk 1. Reserved words (if/while/etc.) are dropped via IsCallSkipWord.
procedure CollectCallIdents(const ALine: string; AAcc: TStringList);
var
  I, N, J, K   : Integer;
  InBrace      : Integer; // { } comment nesting depth on this line
  Ident        : string ;
begin
  I:= 1;
  N:= Length(ALine);
  InBrace:= 0;
  while I <= N do
  begin
    if InBrace > 0 then
    begin
      if ALine[I] = '}' then Dec(InBrace);
      Inc(I);
      Continue;
    end;
    if ALine[I] = '{' then begin Inc(InBrace); Inc(I); Continue; end;
    if (ALine[I] = '/') and (I < N) and (ALine[I + 1] = '/') then Break; // line comment
    if ALine[I] = '''' then
    begin
      // Skip a single-quoted string; '' inside stays in-string.
      Inc(I);
      while I <= N do
      begin
        if ALine[I] = '''' then
        begin
          if (I < N) and (ALine[I + 1] = '''') then Inc(I, 2) // escaped quote
          else begin Inc(I); Break; end;
        end
        else Inc(I);
      end;
      Continue;
    end;
    if IsIdentStart(ALine[I]) then
    begin
      J:= I;
      while (J <= N) and IsIdentPart(ALine[J]) do Inc(J);
      Ident:= Copy(ALine, I, J - I);
      // Peek past spaces for a '(' -> this is a call site.
      K:= J;
      while (K <= N) and (ALine[K] = ' ') do Inc(K);
      if (K <= N) and (ALine[K] = '(') and not IsCallSkipWord(Ident) then
        AAcc.Add(Ident);
      I:= J;
      Continue;
    end;
    Inc(I);
  end;
end;

// Scans ONE source line for 'raise <Ident>' -- the whole-word keyword 'raise'
// followed by an identifier (the exception class). Adds the class name to AAcc.
// Same string/comment skipping and single-line limitation as CollectCallIdents.
procedure CollectRaiseClass(const ALine: string; AAcc: TStringList);
var
  I, N, J, K : Integer;
  InBrace    : Integer;
  Ident      : string ;
begin
  I:= 1;
  N:= Length(ALine);
  InBrace:= 0;
  while I <= N do
  begin
    if InBrace > 0 then
    begin
      if ALine[I] = '}' then Dec(InBrace);
      Inc(I);
      Continue;
    end;
    if ALine[I] = '{' then begin Inc(InBrace); Inc(I); Continue; end;
    if (ALine[I] = '/') and (I < N) and (ALine[I + 1] = '/') then Break;
    if ALine[I] = '''' then
    begin
      Inc(I);
      while I <= N do
      begin
        if ALine[I] = '''' then
        begin
          if (I < N) and (ALine[I + 1] = '''') then Inc(I, 2)
          else begin Inc(I); Break; end;
        end
        else Inc(I);
      end;
      Continue;
    end;
    if IsIdentStart(ALine[I]) then
    begin
      J:= I;
      while (J <= N) and IsIdentPart(ALine[J]) do Inc(J);
      Ident:= Copy(ALine, I, J - I);
      if SameText(Ident, 'raise') then
      begin
        // Skip spaces, then capture the next identifier = exception class.
        K := J;
        while (K <= N) and (ALine[K] = ' ') do Inc(K);
        if (K <= N) and IsIdentStart(ALine[K]) then
        begin
          var E: Integer:= K;
          while (E <= N) and IsIdentPart(ALine[E]) do Inc(E);
          AAcc.Add(Copy(ALine, K, E - K));
          I:= E;
          Continue;
        end;
      end;
      I:= J;
      Continue;
    end;
    Inc(I);
  end;
end;

// Reads the 1-based ALine of AFilePath, trimmed. '' on any error (missing
// file, out-of-range line) -- same tolerant pattern the Calls/Raises sections
// above use for their own TFile.ReadAllLines(..., TEncoding.ANSI) reads (source
// is strict ANSI/CRLF per repo convention).
function ReadDeclLine(const AFilePath: string; ALine: Integer): string;
var Lines: TArray<string>;
begin
  Result:= '';
  if (AFilePath = '') or (ALine <= 0) then Exit;
  try
    Lines:= System.IOUtils.TFile.ReadAllLines(AFilePath, TEncoding.ANSI);
  except
    Exit;
  end;
  if ALine <= Length(Lines) then Result:= Trim(Lines[ALine - 1]);
end;

// Detects a Pascal 'deprecated' DIRECTIVE on ASym's declaration and, when
// present, extracts its optional trailing message string literal. This is
// GROUND-TRUTH ONLY: called just once per Build and the caller sets
// Result.Deprecated/DeprecatedMsg strictly from what this function finds --
// no fabrication when the directive is absent.
//
// SOURCE: empirically confirmed (probe fixture, 'query --name X --json' on a
// scratch DB) that NEITHER TSymbol.Signature (args+return-type only) NOR
// TSymbol.Modifiers (visibility only, e.g. 'public') captures the directive --
// both are '' for a routine regardless of a trailing 'deprecated' clause. The
// parser (DRagLint.Parser.Delphi13.EmitProc et al.) never inspects the
// procAttribute directive nodes for 'deprecated' at all. Fallback: read the
// raw declaration line at ASym.StartLine (ReadDeclLine, above -- the same
// tolerant ANSI-read idiom this unit already uses for Calls/Raises) and
// regex-match the directive there.
//
// Matches (case-insensitive, whole-word 'deprecated'):
//   procedure OldWay; deprecated 'use NewWay';   -> Deprecated=True,  Msg='use NewWay'
//   procedure OldBare; deprecated;               -> Deprecated=True,  Msg=''
//   procedure Fine;                              -> Deprecated=False, Msg=''
function DetectDeprecated(const AStore: ISymbolStore; const ASym: TSymbol; out AMsg: string): Boolean;
var
  Line : string;
  M    : TMatch;
begin
  Result:= False;
  AMsg  := '';
  if ASym.StartLine <= 0 then Exit;
  Line:= ReadDeclLine(AStore.GetFilePath(ASym.FileId), ASym.StartLine);
  if Line = '' then Exit;
  // 'deprecated' as a whole word, optionally followed by a single-quoted
  // message string, up to the terminating ';'. The message capture tolerates
  // a Pascal-escaped '' (embedded quote) via the non-greedy .*? + literal ''.
  M:= TRegEx.Match(Line, '\bdeprecated\b\s*(?:''(.*?)'')?\s*;', [roIgnoreCase]);
  if not M.Success then Exit;
  Result:= True;
  if M.Groups.Count > 1 then
    if M.Groups[1].Success then
      AMsg:= StringReplace(M.Groups[1].Value, '''''', '''', [rfReplaceAll]);
end;

// v(ADP1 T3): detects the virtual / abstract / override / dynamic DIRECTIVES on
// ASym's declaration line. SOURCE PROBE, mirroring DetectDeprecated above --
// the index has NO abstract signal at all (never persisted anywhere), and
// TSymbol.IsVirtual (Model.pas) COLLAPSES virtual/dynamic/override into a
// single flag (cannot tell WHICH directive is present), so the declaration
// TEXT is the only ground truth for these three. Reuses ReadDeclLine (the same
// tolerant ANSI-read idiom DetectDeprecated already uses).
//
// KNOWN BOUND (same as DetectDeprecated): reads ONLY ASym.StartLine. A
// directive written on a LATER line of a WRAPPED multi-line signature (e.g. a
// long param list with 'virtual;' on the line after the closing paren) is
// MISSED -- Phase 1 does not expand to multi-line scanning; single-line
// declarations (as produced by this repo's formatting conventions and the
// task's test fixtures) are the supported case.
//
// Matches whole-word, case-insensitive; a bare declaration with none of these
// words yields all three False (never fabricated).
procedure DetectMethodDirectives(const AStore: ISymbolStore; const ASym: TSymbol;
  out AVirtual, AAbstract, AOverride: Boolean);
var
  Line: string;
begin
  AVirtual := False;
  AAbstract:= False;
  AOverride:= False;
  if ASym.StartLine <= 0 then Exit;
  Line:= ReadDeclLine(AStore.GetFilePath(ASym.FileId), ASym.StartLine);
  if Line = '' then Exit;
  AVirtual := TRegEx.IsMatch(Line, '\b(virtual|dynamic)\b', [roIgnoreCase]);
  AAbstract:= TRegEx.IsMatch(Line, '\babstract\b', [roIgnoreCase]);
  AOverride:= TRegEx.IsMatch(Line, '\boverride\b', [roIgnoreCase]);
end;

class function TDocFactsBuilder.Build(const AStore: ISymbolStore; const ASym: TSymbol;
  AIncludeSeeAlso: Boolean; AIncludeSince: Boolean; const ABaseDir: string;
  const AExtraStores: TArray<ISymbolStore>; AMaxReturnCases: Integer; AMaxCallers: Integer): TDocFacts;
var
  ResCallers: TArray<TResolvedCaller>;
  RC        : TResolvedCaller        ;
  FR        : TDocFactRef            ;
  Distinct  : TList<TDocFactRef>     ;
  Seen      : TDictionary<string, Boolean>;
  Key       : string                 ;
  Shown     : Integer                ;
  I         : Integer                ;

  // Map one resolved-caller row to a display ref. Display is the enclosing
  // routine's qualified name (or the same fallback the name-based path used when
  // the ref has no enclosing symbol); Location is already file-name-only.
  function ToFactRef(const ARC: TResolvedCaller): TDocFactRef;
  begin
    Result:= Default(TDocFactRef);
    Result.Display:= ARC.EnclosingQName;
    if Result.Display = '' then Result.Display:= LastSeg(ASym.QualifiedName) + ' caller';
    Result.Location  := ARC.Location;
    Result.Confidence:= ARC.Confidence;
  end;

  // Add FR to Distinct unless a caller with the SAME 'Display|Location' key has
  // already been added. First-seen wins -> resolved bucket (added first) beats a
  // later unverified name-match for the same caller, so a caller that DID resolve
  // to this symbol is never re-marked '?'.
  procedure AddDistinct(const AFR: TDocFactRef);
  begin
    Key:= AFR.Display + '|' + AFR.Location;
    if Seen.ContainsKey(Key) then Exit;
    Seen.Add(Key, True);
    Distinct.Add(AFR);
  end;

begin
  Result:= Default(TDocFacts);

  // Called from: RESOLVED caller refs -> display 'EnclosingQName (file)'.
  // v14 (D5) -- THE BUG FIX. Previously this was name-based
  // (FindCallersByName(LastSeg)), so it listed callers of EVERY same-named method
  // in the codebase. It is now grounded in call_edges (per-site resolved targets):
  //   1. FindResolvedCallers(ASym.Id) -- callers whose resolved call target IS
  //      this symbol. Confidence 'certain' -> plain; 'ambiguous' (>1 candidate on
  //      the type chain) -> ' ?'. A caller resolved CERTAIN to a DIFFERENT symbol
  //      is simply absent here -- that is the exclusion, automatic.
  //   2. FindUnresolvedNameCallers(LastSeg) -- name-matching refs with NO
  //      call_edges row (receiver untypable). These are 'unverified' -> ' ?'
  //      (honest: might or might not be this symbol).
  // The renderer (JoinRefs) appends ' ?' to any Confidence not 'certain'/''.
  //
  // IDEMPOTENCY: the Location is the caller FILE NAME ONLY -- deliberately NO
  // ':line'. A line number is VOLATILE: applying this managed comment inserts N
  // lines above every caller that sits below the insertion point, so on the next
  // index+run the caller's StartLine has shifted and the regenerated facts block
  // would differ from what is on disk -- 'document' would re-write the file every
  // run, breaking the managed-region idempotency promise. TResolvedCaller.Location
  // is already ExtractFileName'd, preserving this invariant on the resolved path.
  //
  // DEDUPE: a caller routine that references the target 2+ times yields multiple
  // rows that -- now that the volatile ':line' is dropped -- collapse to IDENTICAL
  // (Display, Location) pairs. AddDistinct folds them to a single entry keyed on
  // 'Display|Location' (both line-free). Resolved rows are added BEFORE unverified
  // rows, so first-seen dedupe also keeps a caller in the STRONGER bucket (a
  // resolved caller never re-appears as an unverified '?' for the same site).
  // CalledFromTotal is the DISTINCT count and the display cap applies to it.
  //
  // ORDER: FindResolvedCallers orders 'certain' before 'ambiguous', so plain
  // entries precede ' ?' entries within the resolved bucket; the unverified '?'
  // bucket follows -- overall plain-before-'?' as the spec requires.
  Distinct:= TList<TDocFactRef>.Create;
  Seen    := TDictionary<string, Boolean>.Create;
  try
    ResCallers:= AStore.FindResolvedCallers(ASym.Id);
    for RC in ResCallers do
    begin
      FR:= ToFactRef(RC);
      AddDistinct(FR);
    end;
    // Unverified name-match bucket: CALL-SITE refs whose name matches but that
    // have no call_edges row (untypable receiver). v(ADP3 T3i, register E1):
    // until this bucket was restricted to call-site refs it also collected the
    // co-located 'member-access' ref every dotted call emits since 9d7e641 --
    // so a caller that resolved CERTAIN to a DIFFERENT same-named method still
    // appeared here with a ' ?'.
    //
    // NON-ROUTINE KINDS ARE DELIBERATELY EXEMPT, and this is a scope boundary,
    // not an oversight. WHICH kinds and WHY are stated once, on
    // CanBeCallTarget's own header above; the parameter's contract is stated
    // once, on the ISymbolStore declaration in DRagLint.Core.Interfaces.
    // v(ADP3 T3i review round 4): neither is paraphrased here, and no kind list
    // is written here -- the paraphrase that used to sit at this spot named five
    // type kinds and was narrower than the predicate it described.
    ResCallers:= AStore.FindUnresolvedNameCallers(LastSeg(ASym.QualifiedName),
                                                 CanBeCallTarget(ASym.Kind));
    for RC in ResCallers do
    begin
      FR:= ToFactRef(RC);
      FR.Confidence:= 'unverified'; // enforce the '?' marker regardless of store value
      AddDistinct(FR);
    end;

    // Extra stores (multi-DB fan-out): NAME-BASED bucket only. ASym.Id is a
    // PRIMARY-store-only key -- in an extra store the same symbol has a
    // different Id (or isn't defined there at all), so FindResolvedCallers
    // would be meaningless there. FindUnresolvedNameCallers is Id-independent
    // (keys on the qualified name's last segment), so it is exactly how a
    // cross-DB caller (e.g. a COMMON reference) surfaces. Every extra-store hit
    // is marked 'unverified' -- AddDistinct's Display|Location dedupe folds a
    // caller seen in both the primary and an extra store into one entry.
    for var ExStore in AExtraStores do
    begin
      if ExStore = nil then Continue;
      // Same kind gate as the primary store above -- the two must agree, or a
      // symbol's fact would depend on which DB a reference happened to live in.
      // The expression is repeated because it is CODE; the reasoning is not, and
      // lives on CanBeCallTarget's header.
      ResCallers:= ExStore.FindUnresolvedNameCallers(LastSeg(ASym.QualifiedName),
                                                    CanBeCallTarget(ASym.Kind));
      for RC in ResCallers do
      begin
        FR:= ToFactRef(RC);
        FR.Confidence:= 'unverified';
        AddDistinct(FR);
      end;
    end;

    // v(ADP1 T1): CalledFrom's display cap is the CONFIG-DRIVEN AMaxCallers
    // (manifest docs.max_callers, default 5 -- see LoadDocMaxCallers), NOT the
    // shared DocDisplayCount helper (that >15-total-\>10-shown rule still
    // governs Calls:/Used in units: below, unchanged). Simple threshold: show
    // AMaxCallers when the distinct count exceeds it, else show all; the
    // renderer's MoreSuffix appends '(+N more)' from CalledFromTotal.
    Result.CalledFromTotal:= Distinct.Count;
    if Distinct.Count > AMaxCallers then Shown:= AMaxCallers else Shown:= Distinct.Count;
    if Shown < 0 then Shown:= 0;
    SetLength(Result.CalledFrom, Shown);
    for I:= 0 to Shown - 1 do Result.CalledFrom[I]:= Distinct[I];
  finally
    Seen.Free;
    Distinct.Free;
  end;

  // Returns: type from the signature, else '' (procedures).
  Result.ReturnType:= ParseReturnType(ASym.Signature);

  // ReturnCases: v(item1 T8) -- enumerate distinct return cases for a function's
  // <returns> doc (Task 9 emits them). Reuses MineReturnExpressions (DRagLint.
  // Hover.Returns) -- the SAME pure miner the hover popup already uses, so hover
  // and autodoc agree on what a routine returns. Guarded so PROCEDURES (no
  // return type) never get ReturnCases, AMaxReturnCases <= 0 disables mining
  // entirely (bare TODO at emit), and only a valid impl-line span is scanned.
  // The body is re-read here (tolerant ANSI read, same idiom as Calls/Raises
  // below) rather than reusing their Src arrays, since this block runs before
  // either of those reads and keeping it self-contained avoids coupling three
  // unrelated Result fields to one shared local.
  if (Result.ReturnType <> '') and (AMaxReturnCases > 0)
     and (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
  begin
    var RSrc: TArray<string>;
    try RSrc:= System.IOUtils.TFile.ReadAllLines(AStore.GetFilePath(ASym.FileId), TEncoding.ANSI);
    except RSrc:= nil; end;
    if Length(RSrc) > 0 then
    begin
      var BodyLines: TArray<string>; SetLength(BodyLines, 0);
      for var Ln:= ASym.ImplStartLine to Min(ASym.ImplEndLine, Length(RSrc)) do
        BodyLines:= BodyLines + [RSrc[Ln - 1]];
      var Mined: TArray<string>:= MineReturnExpressions(BodyLines);
      if Length(Mined) > AMaxReturnCases then SetLength(Mined, AMaxReturnCases);
      Result.ReturnCases:= Mined;
    end;
  end;

  // Calls (outgoing): v14 (D5 T10) -- PREFER RESOLVED callees, body-scan FALLBACK.
  // T3's original decision (t3-calls-spike-decision.md) still holds for sites
  // call_edges cannot resolve: there is no store method filtering refs by
  // enclosing_symbol_id, and GetReferencesFromFile emits EVERY identifier ref
  // (locals, params, Result, Exit) with ref.Kind not discriminating calls, so a
  // bounded body TEXT-SCAN ('Identifier(' call sites, lexer-skipping strings/
  // comments) is still how UNRESOLVED sites are found. But now that
  // ResolveCallTargets (T5/T6) populates call_edges, resolved sites can show the
  // QUALIFIED callee (e.g. 'receivers.TAlpha.Run') instead of the bare, possibly
  // ambiguous identifier ('Run').
  //
  // UNION WITHOUT DOUBLE-LISTING: a naive union of (resolved qualified names) +
  // (body-scan bare names) would list the SAME call twice (once qualified, once
  // bare) whenever a site resolved. Instead:
  //   1. Pull GetCallEdgesFromSymbol(ASym.Id); for each edge with a resolved
  //      target, add the target's QualifiedName to the final set AND record its
  //      LAST SEGMENT (leaf, e.g. 'Run') in ResolvedLeaves (case-insensitive).
  //   2. Run the existing body-scan into a bare-name set, as before.
  //   3. Add each bare name to the final set UNLESS its leaf is already covered
  //      by ResolvedLeaves -- that bare mention is the SAME call site already
  //      shown qualified, so it is suppressed (not lost: still counted via the
  //      qualified entry). A bare name whose leaf was never resolved (SetLength,
  //      a typecast, an unresolved receiver) still appears -- nothing is lost.
  // Example: TCaller calls TAlpha.Run (resolves) and TBeta.Run (resolves) and a
  // bare 'B.Free' (does not resolve) in the same body -> final set shows BOTH
  // qualified Run callees plus bare 'Free'; the bare 'Run' text is suppressed.
  //
  // IDEMPOTENCY: the final set is built into a Sorted/CaseInsensitive/dupIgnore
  // TStringList (same discipline as the old CallSet), so the displayed order is
  // deterministic regardless of GetCallEdgesFromSymbol's row order or body-scan
  // encounter order. Qualified names carry no line numbers, so re-running
  // document --apply after a reindex reproduces the identical list.
  if (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
  begin
    var FinalSet: TStringList:= TStringList.Create;
    var ResolvedLeaves: TStringList:= TStringList.Create;
    try
      FinalSet.Sorted:= True;
      FinalSet.Duplicates:= dupIgnore;
      FinalSet.CaseSensitive:= False;
      ResolvedLeaves.Sorted:= True;
      ResolvedLeaves.Duplicates:= dupIgnore;
      ResolvedLeaves.CaseSensitive:= False;

      // 1. Resolved callees (qualified), via call_edges.
      var Edges: TArray<TCallEdge>:= AStore.GetCallEdgesFromSymbol(ASym.Id);
      for var Edge in Edges do
        if Edge.TargetSymbolId > 0 then
        begin
          var TargetQName: string:= AStore.GetSymbolById(Edge.TargetSymbolId).QualifiedName;
          if TargetQName <> '' then
          begin
            FinalSet.Add(TargetQName);
            ResolvedLeaves.Add(LastSeg(TargetQName));
          end;
        end;

      // 2. Body-scan fallback (bare names), unchanged mechanism.
      var CallSet: TStringList:= TStringList.Create;
      try
        CallSet.Sorted:= True;
        CallSet.Duplicates:= dupIgnore;
        CallSet.CaseSensitive:= False;
        var Src: TArray<string>;
        try
          Src:= System.IOUtils.TFile.ReadAllLines(AStore.GetFilePath(ASym.FileId), TEncoding.ANSI);
        except
          Src:= nil;
        end;
        for var Ln:= ASym.ImplStartLine to Min(ASym.ImplEndLine, Length(Src)) do
          CollectCallIdents(Src[Ln - 1], CallSet);

        // 3. Add a bare name only when its leaf is NOT already covered by a
        // resolved qualified callee (suppress the duplicate, keep the unresolved).
        // Also drop the symbol's OWN name: the impl span includes the routine
        // header line (`Name(...)`), whose `Name(` reads as a call to itself --
        // a spurious self-`Calls:` (seen on free-function overloads). Genuine
        // self-recursion renders nothing useful as "Calls: self" either.
        for var K:= 0 to CallSet.Count - 1 do
          if (ResolvedLeaves.IndexOf(CallSet[K]) < 0) and (not SameText(CallSet[K], ASym.Name)) then
            FinalSet.Add(CallSet[K]);
      finally
        CallSet.Free;
      end;

      Result.CallsTotal:= FinalSet.Count;
      var ShownC: Integer:= DocDisplayCount(FinalSet.Count);
      SetLength(Result.Calls, ShownC);
      for var J:= 0 to ShownC - 1 do Result.Calls[J]:= FinalSet[J];
    finally
      ResolvedLeaves.Free;
      FinalSet.Free;
    end;
  end;

  // Used in units: only for type-like kinds. Distinct owning units of refs to
  // the type name (FindCallersByName over its last segment), EXCLUDING each
  // type's own self-references (see RefIsOwnMemberSelfRef, below the fix note).
  // v14 (D5) NOTE -- DELIBERATELY still name-based (NOT call_edges resolved). This
  // counts distinct units that reference a TYPE NAME; those are TYPE references,
  // not method call sites, so they are NOT in call_edges at all (call_edges only
  // holds resolved METHOD calls). The Called-from name-collision bug that D5 fixes
  // does not exist here in the same form -- a type-name collision is far rarer and
  // out of this milestone's scope -- so resolving UsedIn via call_edges does not
  // apply and would break a working feature for zero bug-fix benefit.
  // v(ADP1 Bug D) NOTE -- SELF-REFERENCE FIX (twin of Bug C's Called-from fix,
  // different fact + different function): FindCallersByName is SHARED by
  // rename/refactor, dead-code/unused lint, the context bundler, LSP/MCP
  // references, and `query find-callers` -- all of them STRUCTURALLY need it
  // to keep matching a class's own qualified impl-header refs (e.g.
  // 'function TThing.Add' must resolve as a TThing self-reference for rename
  // to rewrite it to 'TRenamed.Add'), so self-refs must stay in
  // FindCallersByName itself. Excluding them there would break those callers.
  // Instead each ref returned here is screened LOCALLY via
  // RefIsOwnMemberSelfRef before being added to UnitSet: previously every
  // class with an implemented method acquired a spurious "Used in units:
  // <own unit>" fact purely from its own method headers (the class always
  // "uses itself"), so EVERY such class was wrongly "documented" under the
  // facts-only gate. A ref with no enclosing symbol (a unit-scope 'var G: T;')
  // is NOT a self-reference and is always kept -- see RefIsOwnMemberSelfRef's
  // header comment for the NULL-enclosing lesson carried from Bug C.
  // v(ADP3 T3i review round 2): DELIBERATELY ITS OWN SET, NOT CanBeCallTarget's
  // complement, and round 1's attempt to share one declaration between this gate
  // and the CalledFrom gate was the error that hid the skEnum/skTypeAlias bug.
  // The two decisions look alike but their correct sets DIFFER: "which kinds are
  // exempt from the call-site restriction" is every non-routine kind, whereas
  // "which kinds get a Used in units: fact" is these three and always has been.
  // Widening this one to match would ADD a brand-new fact line to every enum and
  // alias -- a behaviour change nobody asked for, in the opposite direction to
  // the one being fixed. Sharing is only safe when two sites answer the SAME
  // question; here they do not, so they get one declaration each.
  //
  // The identical set also appears in RefIsOwnMemberSelfRef above, and is
  // deliberately NOT folded in with this one either: that one asks "is the
  // ENCLOSING symbol's parent a named type, so this ref is a self-reference",
  // which is a property of the ref's neighbourhood rather than of the symbol
  // being documented. Three coincident literals would be worth collapsing; two
  // sites answering two different questions is the same trap in miniature.
  if ASym.Kind in [skClass, skInterface, skRecord] then
  begin
    var URefs: TArray<TReference>:= AStore.FindCallersByName(LastSeg(ASym.QualifiedName));
    var UnitSet: TStringList:= TStringList.Create;
    try
      UnitSet.Sorted:= True;
      UnitSet.Duplicates:= dupIgnore;
      UnitSet.CaseSensitive:= False;
      for var UR in URefs do
        if not RefIsOwnMemberSelfRef(AStore, UR, LastSeg(ASym.QualifiedName)) then
          UnitSet.Add(ChangeFileExt(ExtractFileName(AStore.GetFilePath(UR.FileId)), ''));
      // Extra stores (multi-DB fan-out): same name-based query, but resolve
      // each ref's file path -- and screen self-refs -- via the EXTRA store's
      // OWN FileId/symbol-id maps (ExStore.GetFilePath / ExStore passed into
      // RefIsOwnMemberSelfRef) -- FileIds AND symbol ids are per-DB, so using
      // AStore for an extra store's ref would read the wrong (or a
      // coincidentally valid but wrong) path/symbol. UnitSet is
      // case-insensitive dupIgnore, so a unit name seen in both stores
      // collapses to one entry.
      for var ExStore in AExtraStores do
      begin
        if ExStore = nil then Continue;
        var ExURefs: TArray<TReference>:= ExStore.FindCallersByName(LastSeg(ASym.QualifiedName));
        for var EUR in ExURefs do
          if not RefIsOwnMemberSelfRef(ExStore, EUR, LastSeg(ASym.QualifiedName)) then
            UnitSet.Add(ChangeFileExt(ExtractFileName(ExStore.GetFilePath(EUR.FileId)), ''));
      end;
      Result.UsedInTotal:= UnitSet.Count;
      var ShownU: Integer:= DocDisplayCount(UnitSet.Count);
      SetLength(Result.UsedInUnits, ShownU);
      for var K:= 0 to ShownU - 1 do Result.UsedInUnits[K]:= UnitSet[K];
    finally
      UnitSet.Free;
    end;
  end;

  // Raises: 'raise <Ident>' exception class names in the body, deduped.
  if (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
  begin
    var RaiseSet: TStringList:= TStringList.Create;
    try
      RaiseSet.Sorted:= True;
      RaiseSet.Duplicates:= dupIgnore;
      RaiseSet.CaseSensitive:= False;
      var Src2: TArray<string>;
      try
        Src2:= System.IOUtils.TFile.ReadAllLines(AStore.GetFilePath(ASym.FileId), TEncoding.ANSI);
      except
        Src2:= nil;
      end;
      for var Ln2:= ASym.ImplStartLine to Min(ASym.ImplEndLine, Length(Src2)) do
        CollectRaiseClass(Src2[Ln2 - 1], RaiseSet);
      Result.Raises:= RaiseSet.ToStringArray;
    finally
      RaiseSet.Free;
    end;
  end;

  // Deprecated: ground-truth 'deprecated' directive detection (see
  // DetectDeprecated's header comment for the source/probe rationale).
  var DepMsg: string;
  Result.Deprecated:= DetectDeprecated(AStore, ASym, DepMsg);
  Result.DeprecatedMsg:= DepMsg;

  // v(ADP1 T3): cheap fact group -- overrides / overridden-by / implements /
  // overload / virtual+abstract markers. GROUND-TRUTH via the SAME mapped
  // ancestry/descendant/sibling helpers already used elsewhere in this unit and
  // in PropTree (GetTransitiveAncestors, FindDescendantNames,
  // FindChildSymbolByName, FindAllChildSymbols) -- not reinvented. virtual/
  // abstract have no index signal at all, so they come from the bounded source
  // probe DetectMethodDirectives (see its header comment for the rationale and
  // the known StartLine-only bound).
  //
  // CHEAP EARLY-OUT: only routine-like symbols with a parent (ASym.ParentId > 0)
  // can carry any of these facts -- a type, a field, a const, etc. has none, so
  // the whole block is skipped for every other kind/parentless symbol. Free
  // (unit-level) functions/procedures ARE included because they can be OVERLOADED
  // (the Overload k of n line below); the method-only facts (Overrides /
  // Implements / Overridden by / virtual+abstract) naturally resolve to EMPTY for
  // them -- a unit parent has no class ancestry/descendants and a free routine
  // carries no virtual/abstract directive -- so including them is correct, not
  // just harmless.
  if (ASym.Kind in [skMethod, skConstructor, skDestructor, skFunction, skProcedure]) and (ASym.ParentId > 0) then
  begin
    var ParentSym: TSymbol:= AStore.GetSymbolById(ASym.ParentId);
    if ParentSym.Id > 0 then
    begin
      // Overrides / Implements: walk the parent's TRANSITIVE ancestor closure
      // (GetTransitiveAncestors -- BFS, nearest-first, resolved edges only).
      // A 'class' ancestor declaring the SAME method name -> Overrides (first/
      // nearest match wins, mirrors PropTree's ResolveInheritedType). An
      // 'interface' ancestor declaring the same member name -> Implements
      // (NAME-BASED ONLY: no signature-match helper exists in the index, so an
      // unrelated same-named method that happens to sit under an implemented
      // interface would also match here -- accepted as a documented heuristic
      // for this cheap fact group, not a verified interface-implementation
      // proof).
      var Ancestors: TArray<TTypeAncestor>:= AStore.GetTransitiveAncestors(ParentSym.Id);
      for var Anc in Ancestors do
      begin
        if not (Anc.Resolved and (Anc.SymbolId > 0)) then Continue;
        if SameText(Anc.Kind, 'class') and (Result.Overrides = '') then
        begin
          var BaseMethod: TSymbol:= AStore.FindChildSymbolByName(Anc.SymbolId, ASym.Name);
          if (BaseMethod.Id > 0) and (BaseMethod.Kind in [skMethod, skConstructor, skDestructor]) then
            Result.Overrides:= BaseMethod.QualifiedName;
        end
        else if SameText(Anc.Kind, 'interface') and (Result.Implements = '') then
        begin
          var IfaceMember: TSymbol:= AStore.FindChildSymbolByName(Anc.SymbolId, ASym.Name);
          if IfaceMember.Id > 0 then
            Result.Implements:= IfaceMember.QualifiedName;
        end;
      end;

      // Overridden by: every TRANSITIVE DESCENDANT class of the parent
      // (FindDescendantNames -- distinct, sorted class NAMES only) that
      // redeclares the same method name. Each name is re-resolved to a symbol
      // via FindSymbolsByExactName, trying candidates in order and keeping the
      // FIRST one that actually owns a same-named method-like child -- guards
      // against an unrelated same-named class in a different unit shadowing the
      // real descendant. Capped at OVERRIDDENBY_CAP; OverriddenByTotal carries
      // the true distinct count (mirrors CalledFrom's cap discipline).
      if ParentSym.Kind = skClass then
      begin
        var DescNames: TArray<string>:= AStore.FindDescendantNames(ParentSym.Name);
        var OB: TStringList:= TStringList.Create;
        try
          for var DName in DescNames do
          begin
            var Cands: TArray<TSymbol>:= AStore.FindSymbolsByExactName(DName);
            for var Cand in Cands do
            begin
              if Cand.Kind <> skClass then Continue;
              var DescMethod: TSymbol:= AStore.FindChildSymbolByName(Cand.Id, ASym.Name);
              if (DescMethod.Id > 0) and (DescMethod.Kind in [skMethod, skConstructor, skDestructor]) then
              begin
                OB.Add(DescMethod.QualifiedName);
                Break; // first candidate that owns the method wins; stop scanning this name
              end;
            end;
          end;
          Result.OverriddenByTotal:= OB.Count;
          var ShownOB: Integer:= OB.Count;
          if ShownOB > OVERRIDDENBY_CAP then ShownOB:= OVERRIDDENBY_CAP;
          SetLength(Result.OverriddenBy, ShownOB);
          for var K:= 0 to ShownOB - 1 do Result.OverriddenBy[K]:= OB[K];
        finally
          OB.Free;
        end;
      end;
    end;

    // Overload k of n: siblings under the SAME parent (FindAllChildSymbols --
    // the same helper SeeAlso's sibling walk above already uses) sharing
    // ASym's Name, in the query's start_line order. ASym's own 1-based
    // position within that same-named subset is its ordinal; the subset size
    // is the count. A lone (non-overloaded) method yields Count <= 1 (never
    // rendered -- RenderFactsBlock requires > 1).
    var Siblings: TArray<TSymbol>:= AStore.FindAllChildSymbols(ASym.ParentId);
    var SameName: TList<TSymbol>:= TList<TSymbol>.Create;
    try
      for var Sib in Siblings do
        // Include free (unit-level) functions/procedures, not just methods:
        // FindAllChildSymbols(ParentId) already scopes to the right container
        // (a class for methods, the unit symbol for free routines), so an
        // overloaded free function -- e.g. two `Combine`s at unit scope -- gets
        // its "Overload k of n" line too.
        if (Sib.Kind in [skMethod, skConstructor, skDestructor, skFunction, skProcedure]) and SameText(Sib.Name, ASym.Name) then
          SameName.Add(Sib);
      if SameName.Count > 1 then
      begin
        Result.OverloadCount:= SameName.Count;
        for var OI:= 0 to SameName.Count - 1 do
          if SameName[OI].Id = ASym.Id then
          begin
            Result.OverloadOrdinal:= OI + 1;
            Break;
          end;
      end;
    finally
      SameName.Free;
    end;

    // virtual / abstract / override directive markers (source probe). IsVirtual
    // is suppressed when AOverride is also present -- an override is already
    // (implicitly) virtual, and Overrides is the more informative line, so the
    // two are never both rendered for the same decl (per the task's design
    // decision).
    var DVirtual, DAbstract, DOverride: Boolean;
    DetectMethodDirectives(AStore, ASym, DVirtual, DAbstract, DOverride);
    Result.IsAbstract:= DAbstract;
    Result.IsVirtual := DVirtual and not DOverride;
  end;

  // SeeAlso (opt-in): related-symbol crefs for the <seealso> doc-source. Only
  // computed when AIncludeSeeAlso (the --seealso flag) -- otherwise SeeAlso stays
  // empty and RenderFactsBlock emits nothing, so the default (no --seealso) facts
  // block is byte-for-byte what it was before this doc-source existed.
  //
  // "Related" = RESOLVED outgoing callees UNION sibling members of the same parent
  // type. GROUND-TRUTH: every entry is a REAL indexed qualified name --
  //   1. Resolved callees: GetCallEdgesFromSymbol -> each edge's target
  //      QualifiedName. This is the call_edges truth (D5), so it is NEVER a
  //      '?'-tagged/unverified guess and NEVER a bare body-scan name -- an
  //      UNRESOLVED site (TargetSymbolId <= 0) is simply skipped, so no unverified
  //      name can leak in. (Result.Calls deliberately mixes in body-scan bare
  //      names for the human 'Calls:' line; SeeAlso must not, hence we re-read the
  //      edges here rather than reuse Result.Calls.)
  //   2. Siblings: FindAllChildSymbols(ASym.ParentId) -- other members of the same
  //      parent type -- EXCLUDING ASym itself (by Id). Each contributes its own
  //      QualifiedName. ParentId <= 0 (a unit-level routine, no parent) yields no
  //      siblings; that is fine, the callees still stand.
  // DEDUPE + SORT + CAP: fold into a Sorted/CaseInsensitive/dupIgnore TStringList
  // (deterministic order regardless of edge/sibling encounter order), then take
  // the first SEEALSO_CAP entries. Qualified names carry no line numbers, so a
  // re-run after reindex reproduces the identical list (idempotent).
  if AIncludeSeeAlso then
  begin
    var SeeSet: TStringList:= TStringList.Create;
    try
      SeeSet.Sorted:= True;
      SeeSet.Duplicates:= dupIgnore;
      SeeSet.CaseSensitive:= False;

      // 1. Resolved callees (qualified, ground-truth via call_edges).
      var SeeEdges: TArray<TCallEdge>:= AStore.GetCallEdgesFromSymbol(ASym.Id);
      for var SE in SeeEdges do
        if SE.TargetSymbolId > 0 then
        begin
          var CalleeQName: string:= AStore.GetSymbolById(SE.TargetSymbolId).QualifiedName;
          if CalleeQName <> '' then SeeSet.Add(CalleeQName);
        end;

      // 2. Sibling members of the same parent type (excluding ASym itself).
      if ASym.ParentId > 0 then
      begin
        var Siblings: TArray<TSymbol>:= AStore.FindAllChildSymbols(ASym.ParentId);
        for var Sib in Siblings do
          if (Sib.Id <> ASym.Id) and (Sib.QualifiedName <> '') then
            SeeSet.Add(Sib.QualifiedName);
      end;

      // CAP at SEEALSO_CAP (deduped, already sorted).
      var ShownS: Integer:= Min(SeeSet.Count, SEEALSO_CAP);
      SetLength(Result.SeeAlso, ShownS);
      for var S:= 0 to ShownS - 1 do Result.SeeAlso[S]:= SeeSet[S];
    finally
      SeeSet.Free;
    end;
  end;

  // Since (opt-in): git commit date of the declaration line. Computed ONLY when
  // AIncludeSince (the --since flag) -- so a batch run WITHOUT --since never
  // spawns git per decl (TGitSince.FirstCommitDate is the only git subprocess and
  // it is behind this guard). GROUND-TRUTH: TGitSince returns 'YYYY-MM-DD' only on
  // a confident git attribution and '' in every failure mode (no git, untracked,
  // non-zero exit, unparseable, exception), so Result.Since is either a real
  // commit date or '' -- never a guessed/stale date. Set only when non-empty, so
  // RenderFactsBlock emits a <since> line only for a real date. ABaseDir is the
  // repo root (TDocBatchOptions.BaseDir); '' -> the file's own directory.
  if AIncludeSince then
  begin
    var SinceDate: string:= TGitSince.FirstCommitDate(
      ABaseDir, AStore.GetFilePath(ASym.FileId), ASym.StartLine);
    if SinceDate <> '' then Result.Since:= SinceDate;
  end;

  // v(ADP2 T3): Complexity fact -- the RAW index-time symbol_facts values,
  // read back verbatim (no threshold applied here: RenderFactsBlock gates the
  // 'Complexity:' line on docs.complexity_min at RENDER time -- see
  // TDocFacts.Cyclomatic's field comment for why). Unconditional, like
  // Deprecated above: a symbol with no symbol_facts row (a non-routine kind,
  // or an index built before Phase 2) reads back Present=False with both
  // fields already zeroed by Default(TSymbolFacts) -- exactly the "no fact"
  // state, never fabricated.
  var SFacts: TSymbolFacts:= AStore.GetSymbolFacts(ASym.Id);
  Result.Cyclomatic:= SFacts.Cyclomatic;
  Result.BodyLoc   := SFacts.BodyLoc;
  // v(ADP2 T4): Reads/Writes fields -- same raw-passthrough contract as
  // Cyclomatic/BodyLoc above (already capped/formatted at analysis time).
  Result.ReadsFields := SFacts.ReadsFields;
  Result.WritesFields:= SFacts.WritesFields;
  // v(ADP2 T6): DFM event-wiring -- same raw-passthrough contract as
  // Cyclomatic/BodyLoc/ReadsFields/WritesFields above (already the final
  // display string, computed at index time by DRagLint.Doc.SymbolFacts.
  // TSymbolFactsAnalyzer.Analyze/AnalyzeDfmEvent -- see TDocFacts.DfmEvent's
  // own field comment).
  Result.DfmEvent:= SFacts.DfmEvent;
  // v(ADP2 T7): SQL tables touched -- same raw-passthrough contract as
  // Cyclomatic/BodyLoc/ReadsFields/WritesFields/DfmEvent above (already the
  // final display CSVs, computed at index time by DRagLint.Doc.SymbolFacts.
  // TSymbolFactsAnalyzer.Analyze/AnalyzeSqlTables).
  Result.SqlReads := SFacts.SqlReads;
  Result.SqlWrites:= SFacts.SqlWrites;
  // v(ADP2 T8): returned-object ownership -- same raw-passthrough contract
  // as Cyclomatic/BodyLoc/ReadsFields/WritesFields/DfmEvent/SqlReads/
  // SqlWrites above (already the final stored word, computed at index time
  // by DRagLint.Doc.SymbolFacts.TSymbolFactsAnalyzer.Analyze/
  // AnalyzeReturnsOwner).
  Result.ReturnsOwner:= SFacts.ReturnsOwner;

  // v(ADP2 T5): Covered-by-tests -- CONTROLLER OVERRIDE: computed LAZILY
  // here (NOT read back from SFacts.CoveredBy, which stays unwritten/
  // reserved) via a bounded reverse call-graph closure -- see TDocFacts.
  // CoveredBy's own field comment and DRagLint.Doc.SymbolFacts'
  // ComputeCoveredBy for the full rationale/ruleset. Unconditional call,
  // like Cyclomatic/ReadsFields above: ComputeCoveredBy itself early-outs
  // to '' for a non-routine ASym, so no kind-guard is duplicated here.
  Result.CoveredBy:= ComputeCoveredBy(AStore, ASym);
end;

end.
