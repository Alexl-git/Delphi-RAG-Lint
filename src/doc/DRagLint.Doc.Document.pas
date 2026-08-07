unit DRagLint.Doc.Document;

interface

uses
  System.SysUtils,
  DRagLint.Core.Model, DRagLint.Core.Interfaces,
  DRagLint.Refactor.TextEdit;

type
  /// <summary>How BuildFor/BuildForSymbol classified what it wants to do to the
  /// declaration's doc comment. daCreated = there was none, write one.
  /// daExtended = there was one and it needs repairing (delete + reinsert).
  /// daUnchanged = there is one and it is already correct (no edits).
  /// daNotFound = the symbol or its file could not be resolved.
  /// daRemoved = there was one, it was entirely engine-owned, and everything
  /// that fed it is now gone, so the right edit is a pure DELETE with nothing
  /// reinserted.</summary>
  /// <remarks>v(ADP3 T3k, register D1): daRemoved is new. A pure deletion used
  /// to report daExtended, so `document --apply` printed "extended -- 1 edit(s)"
  /// and --json said "action":"extended" for an operation that REMOVES a
  /// comment. A consumer could not tell a repair from a removal -- the two have
  /// opposite meanings for anyone deciding whether to review the diff.
  ///
  /// APPENDED, not inserted: every existing member keeps its ordinal, so
  /// nothing that persisted or compared an ordinal can shift underneath. This
  /// follows the convention T3d2 set for --strip's JSON -- additive, and stated
  /// in the contract note at the emitting site.
  ///
  /// CONTRACT CHANGE, and it is the sanctioned one for this task: the emitted
  /// action string for a deletion changes from "extended" to "removed" on both
  /// the --json and the text path. Exactly one runner pinned the old value for a
  /// genuine deletion (tests\autodoc\run_doc_p3_factsdecay.ps1, whose own header
  /// already called it "a single delete"); that expectation moved as part of
  /// this fix. Every other "extended" pin in the suite is a real repair and is
  /// untouched.
  ///
  /// EVERY consumer that tests for daExtended must decide about daRemoved
  /// explicitly. There are three, all updated: the two report sites in
  /// DRagLint.CLI.pas, and DRagLint.Doc.Batch.pas's Keep filter -- which had to
  /// admit daRemoved, because a deletion edit carries no text and therefore no
  /// managed fence, so HasManagedBlock is False for it and a batch run would
  /// otherwise have silently STOPPED removing decayed blocks.</remarks>
  TDocumentAction = (daCreated, daExtended, daUnchanged, daNotFound, daRemoved);

  TDocumentResult = record
    Action  : TDocumentAction   ;
    QName   : string            ;
    FilePath: string            ;
    Line    : Integer           ;
    Edits   : TArray<TTextEdit> ;
  end;

  TDocumenter = class
  public
    /// <summary>Resolves AQName in the index and computes the DocInsight
    /// comment edits for its declaration. Reads the source file (ANSI) and the
    /// existing doc-comment above the decl, derives params + return from the
    /// signature, builds index-grounded facts, and merges into a managed-region
    /// comment. Action is daCreated (no prior comment), daExtended (prior
    /// comment changed), daRemoved (prior comment was entirely engine-owned and
    /// has decayed to nothing -- a pure delete), daUnchanged (identical -- no
    /// edits), or daNotFound (symbol/file missing). Edits are dry-run data; the
    /// caller applies them.</summary>
    /// <param name="AStore">Open symbol store to query; not owned. Must not be nil.</param>
    /// <param name="AQName">Fully qualified symbol name, e.g. Unit.TType.Method.</param>
    /// <returns>The classified action plus file/line and the computed edits.</returns>
    /// <remarks>Does not write files; TTextEditApplier.Apply performs any I/O.
    /// AIncludeSeeAlso threads the --seealso opt-in into the facts builder; when
    /// False (the default overload) no &lt;seealso&gt; crefs are generated.
    /// AIncludeSince / ABaseDir thread the --since opt-in (git &lt;since&gt;
    /// date, ABaseDir = repo root); no git spawn when AIncludeSince is False.
    /// AExtraStores threads additional open index stores (e.g. other resolved
    /// --db's) into the facts builder so name-based Called-from/Used-in facts
    /// can span multiple DBs; nil/empty preserves single-store behavior.
    /// AMaxReturnCases caps the mined &lt;returns&gt; enumeration (forwarded to
    /// TDocFactsBuilder.Build as-is); default 20 matches the manifest default.
    /// AMaxCallers caps the "Called from:" list (forwarded to
    /// TDocFactsBuilder.Build as-is); default 5 matches the manifest
    /// default (v(ADP1 T1)). AComplexityMin (v(ADP2 T3)) gates the
    /// 'Complexity:' render line (forwarded to TDocRegions.MergeComment
    /// as-is, NOT to Build -- see RenderFactsBlock's remarks for why the
    /// threshold is applied at render, not compute); default 10 matches the
    /// manifest default (docs.complexity_min). Resolves AQName to Syms[0] and
    /// delegates to BuildForSymbol; when AQName is ambiguous (an overloaded
    /// method, all sharing one qualified_name) this still documents only the
    /// first-declared overload -- unchanged, existing behavior. Callers
    /// iterating actual resolved rows (e.g. one per overload) should call
    /// BuildForSymbol directly instead (see its remarks).</remarks>
    class function BuildFor(const AStore: ISymbolStore; const AQName: string;
      AIncludeSeeAlso: Boolean; AIncludeSince: Boolean = False;
      const ABaseDir: string = ''; const AExtraStores: TArray<ISymbolStore> = nil;
      AMaxReturnCases: Integer = 20; AMaxCallers: Integer = 5; AComplexityMin: Integer = 10): TDocumentResult; overload;
    /// <summary>Back-compat overload: BuildFor with no doc-source opt-ins
    /// (AIncludeSeeAlso = False, AIncludeSince = False).</summary>
    class function BuildFor(const AStore: ISymbolStore; const AQName: string): TDocumentResult; overload;
    /// <summary>Computes the DocInsight comment edits for an ALREADY-RESOLVED
    /// symbol ASym: builds index-grounded facts, scans the existing doc-comment
    /// above ASym's OWN declaration line, and merges into a managed-region
    /// comment -- the same logic BuildFor(AQName) runs after it resolves a
    /// qualified name to Syms[0]. Public so a caller iterating actual TSymbol
    /// ROWS (e.g. TDocBatch.DocumentUnit, once per overload) can document each
    /// row's own declaration; calling BuildFor(Sym.QualifiedName) instead would
    /// re-resolve every overload back onto the SAME first-declared symbol
    /// (they all share one qualified_name), stacking duplicate blocks above it
    /// and documenting the others never -- see adp1-bugA-brief.md.</summary>
    /// <param name="AStore">Open symbol store to query; not owned. Must not be nil.</param>
    /// <param name="ASym">The already-resolved symbol to document (its own file/line).</param>
    /// <returns>The classified action plus file/line and the computed edits.</returns>
    /// <remarks>Does not write files; TTextEditApplier.Apply performs any I/O.
    /// AIncludeSeeAlso / AIncludeSince / ABaseDir / AExtraStores /
    /// AMaxReturnCases / AMaxCallers / AComplexityMin have the same meaning as
    /// on BuildFor's full overload (see its remarks). Result.QName is
    /// ASym.QualifiedName.</remarks>
    class function BuildForSymbol(const AStore: ISymbolStore; const ASym: TSymbol;
      AIncludeSeeAlso: Boolean = False; AIncludeSince: Boolean = False;
      const ABaseDir: string = ''; const AExtraStores: TArray<ISymbolStore> = nil;
      AMaxReturnCases: Integer = 20; AMaxCallers: Integer = 5; AComplexityMin: Integer = 10): TDocumentResult;
    /// <summary>Resolves AQName and returns the DocInsight comment CURRENTLY on
    /// its declaration (scanned live from the source file, ANSI), plus the
    /// resolved symbol. AFound is False (and the outputs are Default) when the
    /// symbol is not in the index or its file is missing; AHasDoc is False when
    /// no comment sits above the decl. Used by the doc-drift diagnostic to feed
    /// TDocDrift.Analyze with the on-disk doc. Reads only; writes nothing.</summary>
    /// <param name="AStore">Open symbol store; not owned. Must not be nil.</param>
    /// <param name="AQName">Fully qualified symbol name.</param>
    /// <param name="ASym">OUT: the resolved symbol (Default when not found).</param>
    /// <param name="AFound">OUT: True when the symbol + its file were resolved.</param>
    /// <param name="AHasDoc">OUT: True when a doc-comment was found above the decl.</param>
    /// <returns>The parsed on-disk doc (Default/empty when AHasDoc is False).</returns>
    class function ExistingDocFor(const AStore: ISymbolStore; const AQName: string;
      out ASym: TSymbol; out AFound: Boolean; out AHasDoc: Boolean): TParsedDoc;
  end;

implementation

uses
  System.IOUtils, System.Generics.Collections,
  DRagLint.Doc.Facts, DRagLint.Doc.Regions,
  DRagLint.Parser.DocComments, DRagLint.Refactor.DocStub;

// Splits S into lines (normalizing CRLF/CR -> LF first), Trims each line, and
// drops trailing empty lines. Used to compare the current source-comment span
// against the merged comment apples-to-apples: BOTH sides are /// -prefixed
// source lines, so a per-line Trim neutralizes source indentation vs the
// prefix's trailing space and leaves the identical /// bodies aligned. Interior
// blank lines are preserved (only TRAILING empties are dropped) so a genuine
// structural difference is not masked.
function NormalizeCommentLines(const S: string): TArray<string>;
var
  Norm : string        ;
  Parts: TArray<string>;
  Last : Integer       ;
  I    : Integer       ;
begin
  Norm := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  Norm := StringReplace(Norm, #13, #10, [rfReplaceAll]);
  Parts:= Norm.Split([#10]);
  for I:= 0 to High(Parts) do
    Parts[I]:= Trim(Parts[I]);
  // Drop trailing empty lines (do NOT drop interior blanks).
  Last:= High(Parts);
  while (Last >= 0) and (Parts[Last] = '') do Dec(Last);
  SetLength(Result, Last + 1);
  for I:= 0 to Last do Result[I]:= Parts[I];
end;

// v(ADP3 T3g): the SAME line splitting and trailing-blank drop as
// NormalizeCommentLines, but every retained line is returned RAW (untrimmed),
// so leading whitespace is readable. Pairs with NormalizeCommentLines INDEX
// FOR INDEX -- same input gives the same count, because the drop rule is
// character-identical (a whitespace-only trailing line is dropped by BOTH; it
// is Trim(...) = '' either way). That pairing is what lets the indentation
// compare below be read as a refinement of the body compare rather than as a
// second, differently-shaped notion of "the lines" that could disagree about
// which line is which.
//
// v(ADP3 T3d2, item 6 -- EVALUATED, DECLINED): this body provably equals
// NormalizeCommentLines(S) = Map(Trim, RawCommentLines(S)) -- same #13#10/#13
// normalization, same Split, same Trim(line)='' trailing-blank predicate,
// differing only in whether the KEPT lines come back trimmed or raw. A
// collapse is intentionally NOT done here: the only way to share the split +
// trailing-blank-index logic is to change NormalizeCommentLines's own body
// (e.g. split it into "compute Parts/Last" + "trim and return"), and this
// file regressed three consecutive review rounds on exactly this kind of
// shared-helper change. The T3g reviewer who first flagged the duplication
// called touching NormalizeCommentLines here "a defensible thing to
// decline" -- the blast radius of leaving it duplicated is bounded, because
// every comparator call site below feeds BOTH its arguments through the SAME
// one of these two functions, never a mix: CommentLinesEqual and
// CommentLinesContain always get a NormalizeCommentLines(...) pair,
// CommentLinesIndentEqual always gets a RawCommentLines(...) pair. A drift
// between the two helpers would show an equality check silently agreeing
// with itself on both sides, never a cross-function mismatch that could
// point a repair or fresh-insert guard at the wrong verdict. If a future
// change needs to touch NormalizeCommentLines anyway, collapsing this one
// into it then is fine -- just don't do it FOR this reason alone.
function RawCommentLines(const S: string): TArray<string>;
var
  Norm : string        ;
  Parts: TArray<string>;
  Last : Integer       ;
  I    : Integer       ;
begin
  Norm := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  Norm := StringReplace(Norm, #13, #10, [rfReplaceAll]);
  Parts:= Norm.Split([#10]);
  Last := High(Parts);
  while (Last >= 0) and (Trim(Parts[Last]) = '') do Dec(Last);
  SetLength(Result, Last + 1);
  for I:= 0 to Last do Result[I]:= Parts[I];
end;

// v(ADP3 T3g): the leading whitespace run of S -- spaces and TABS only, in
// the order they appear, copied verbatim. Not Length(S) - Length(TrimLeft(S)):
// that would count any whitespace character, and it answers with a LENGTH,
// which cannot tell one tab from one space. A project indented with tabs must
// still be indented with tabs after `document --apply` touches it, so the
// characters themselves are the answer, never a width.
function LeadingWhitespace(const S: string): string;
var
  I: Integer;
begin
  I:= 1;
  while (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) do Inc(I);
  Result:= Copy(S, 1, I - 1);
end;

// True when the normalized line sequences are identical (same count, each line
// exactly equal). Exact '=' (not SameText): Merged is deterministic and both
// sides come from /// -prefixed source, so casing never varies -- exact compare
// gives the tighter idempotency guarantee.
function CommentLinesEqual(const A, B: TArray<string>): Boolean;
var
  I: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  for I:= 0 to High(A) do
    if A[I] <> B[I] then Exit(False);
  Result:= True;
end;

// v(ADP3 T3g): True when A and B agree, line for line, on the LEADING
// WHITESPACE run alone -- the exact characters, so one tab and one space are
// DIFFERENT indentation, never interchangeable. Deliberately narrower than a
// raw string compare: it is called only once CommentLinesEqual has already
// established that the trimmed bodies match, and at that point the only
// difference a raw compare could still find is per-line leading OR TRAILING
// whitespace. Trailing whitespace is not this task's business -- rewriting a
// file to strip a stray trailing space is churn `document --strip` can never
// undo (there is no marker saying the engine did it), and the same argument
// the single-line-remarks fix already makes applies here. So the compare is
// scoped to exactly the thing that is wrong: the indentation.
//
// A length mismatch answers False, which routes the caller to the replace.
// Unreachable in practice -- CommentLinesEqual has already matched the counts
// and RawCommentLines drops the same trailing lines NormalizeCommentLines does
// -- but the safe direction for an impossible input is to re-emit the block
// the engine can prove correct, not to declare an unexamined one already fine.
function CommentLinesIndentEqual(const A, B: TArray<string>): Boolean;
var
  I: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  for I:= 0 to High(A) do
    if LeadingWhitespace(A[I]) <> LeadingWhitespace(B[I]) then Exit(False);
  Result:= True;
end;

// v(ADP3 T3b review round 4, CRITICAL): True when AInner's line sequence
// occurs as a CONTIGUOUS run anywhere inside AOuter's. Deliberately
// CONTAINMENT rather than CommentLinesEqual's whole-sequence equality -- the
// shape this answers for is a comment region that holds the author's OWN
// line(s) PLUS an already-written, verbatim copy of exactly what the engine is
// about to insert below them, so the two sequences can NEVER be equal, only
// nested. Both sides come from NormalizeCommentLines, so both are per-line
// Trimmed /// source lines and the compare is exact (never SameText -- see
// CommentLinesEqual's own comment for why). An empty AInner answers False
// (fail OPEN: "not already present", so the caller inserts) -- unreachable in
// practice, since an empty Merged exits BuildForSymbol long before either
// branch, but the safe default is to preserve the pre-guard behaviour rather
// than to suppress an edit on a degenerate input.
function CommentLinesContain(const AOuter, AInner: TArray<string>): Boolean;
var
  I: Integer;
  J: Integer;
begin
  if Length(AInner) = 0 then Exit(False);
  if Length(AInner) > Length(AOuter) then Exit(False);
  for I:= 0 to Length(AOuter) - Length(AInner) do
  begin
    Result:= True;
    for J:= 0 to High(AInner) do
      if AOuter[I + J] <> AInner[J] then
      begin
        Result:= False;
        Break;
      end;
    if Result then Exit;
  end;
  Result:= False;
end;

// v(ADP3 T3b review round 4, CRITICAL): the source lines of the 1-based,
// inclusive span [AStartLine..AEndLine] of ASrc, joined with #10, clamped so
// an EndLine past EOF cannot index out of range. Lifted verbatim out of the
// repair branch's own inline loop so BOTH idempotency guards -- the repair
// path's long-standing CommentLinesEqual compare and round 4's new
// fresh-path CommentLinesContain compare -- read the current on-disk comment
// through the SAME extraction. Two independent copies of this could drift and
// leave one of the two guards silently wrong about what is already on disk,
// which is precisely the "agrees only by convention" class of defect this
// task's earlier rounds were pulled up on. Semantics preserved exactly,
// including the leading-blank-line quirk: the #10 separator is only prepended
// once Result is non-empty, so a span whose FIRST line is blank drops that
// blank rather than emitting a leading separator.
function ExtractSourceSpan(const ASrc: string; AStartLine, AEndLine: Integer): string;
var
  Lines: TArray<string>;
  Ix   : Integer       ;
begin
  Result:= '';
  Lines := ASrc.Replace(#13#10, #10, [rfReplaceAll]).Replace(#13, #10, [rfReplaceAll]).Split([#10]);
  for Ix:= AStartLine to AEndLine do
    if (Ix >= 1) and (Ix <= Length(Lines)) then
    begin
      if Result <> '' then Result:= Result + #10;
      Result:= Result + Lines[Ix - 1];
    end;
end;

// v(ADP3 T3g): the leading whitespace of the 1-based line ALine of ASrc --
// the indentation every emitted /// line for that declaration is built from.
// Reads the line through ExtractSourceSpan rather than splitting ASrc a second
// time, so this unit keeps ONE line extraction (the same argument
// ExtractSourceSpan's own comment makes for the two idempotency guards) and
// inherits its EOF clamp for free.
//
// A missing or whitespace-only line answers '' -- a degenerate input can then
// only ever reproduce the pre-v(ADP3 T3g) behaviour (a comment at column 0),
// never a comment made of nothing but indentation. Note ExtractSourceSpan's
// own leading-blank quirk collapses a blank line to '' before Trim even sees
// it, which lands on the same answer by a second route.
function DeclIndent(const ASrc: string; ALine: Integer): string;
var
  L: string;
begin
  L:= ExtractSourceSpan(ASrc, ALine, ALine);
  if Trim(L) = '' then Exit('');
  Result:= LeadingWhitespace(L);
end;

// v(PHASE A2): arms TTextEditApplier's stale-anchor guard on one doc edit.
//
// EVERY coordinate in a doc edit is derived from ASym.StartLine, and that number
// comes from the STORE -- a snapshot that goes stale the moment anything writes
// to the file. Two `document --qname --apply` runs against two members of one
// class is enough: the first insert pushes the second declaration down, the
// store still says where it USED to be, and that coordinate now points into the
// middle of the block just written. Filed as
// docs\INBOX-document-qname-second-apply-nests-block-on-stale-anchor.md; the
// result was two <remarks> opens, one member's facts inside the other's block,
// the second member left undocumented, and exit 0.
//
// The anchor is the DECLARATION line, and the name is what must still be on it.
// Both edits of the repair pair (the delete of the old span and the insert of
// the merged one) get the SAME anchor deliberately: the applier validates the
// whole file's edits against one pre-mutation snapshot, so a stale pair is
// dropped together and can never half-apply into a delete with no replacement.
//
// NOT a second verification path -- the check itself lives in
// TTextEditApplier.AnchorIsValid, beside the tekReplaceInLine guard that already
// fixed this same root cause for the `unused-local` and naming fixers. This
// function only supplies what to verify.
procedure StampAnchor(var AEdit: TTextEdit; const ASym: TSymbol);
begin
  AEdit.ExpectLine:= ASym.StartLine;
  AEdit.ExpectText:= ASym.Name;
  // A symbol with no short name (never observed, but the store is external
  // input) would arm a guard that can never pass and would silently stop the
  // verb writing anything. Leave it unguarded instead -- exactly the historic
  // behaviour -- rather than fail closed on a case that is not the defect.
  if Trim(AEdit.ExpectText) = '' then AEdit.ExpectLine:= 0;
end;

// v(ADP3 T3 review round 3, Regression 2): looks ahead from AOpenIx (which
// Lines[AOpenIx] trims to exactly '<remarks>') for a matching '</remarks>'
// line. Returns True (with ACloseIx set to that line's index) only when the
// span strictly between them contains nothing but blank lines plus one or
// more well-formed, SEQUENTIAL AUTO_BEGIN..AUTO_END fences (each fully
// closed before the next opens) -- the shape(s) TDocRegions.MergeComment
// emits for a facts-only remarks (no hand prose; see its own remarks-
// emission comment). Returns False (ACloseIx = -1) for anything else: no
// closing tag found in the region at all, no fence found, a nested or
// overlapping BEGIN (a second BEGIN before the first's END), OR any other
// non-blank content alongside the fence -- a <remarks> that mixes
// hand-written prose in with the facts fence must NOT be swept up by this
// exemption (that prose line still has to earn ownership on its own merits
// via RegionFullyEngineOwned's ordinary per-line AUTO_MARK check). A bare
// hand-written empty '<remarks></remarks>' (no fence at all) also correctly
// returns False here: SawFence never becomes True, so there is nothing
// engine-authored to justify exempting the wrapper -- fail CLOSED when
// there is nothing to prove ownership, the same principle Regression 3
// applies to a malformed fence below.
//
// v(ADP3 T3d2 D10): this header used to say the span must hold "exactly
// one" fence, which underclaimed what the loop below actually accepts; the
// code was already correct; only the header was not.
function IsFenceOnlyRemarksSpan(const Lines: TArray<string>; AOpenIx: Integer;
  out ACloseIx: Integer): Boolean;
var
  J       : Integer;
  SawFence: Boolean;
  SawOther: Boolean;
  InFence : Boolean;
begin
  SawFence:= False;
  SawOther:= False;
  InFence := False;
  J:= AOpenIx + 1;
  while J <= High(Lines) do
  begin
    if Trim(Lines[J]) = '</remarks>' then
    begin
      ACloseIx:= J;
      Exit((not InFence) and SawFence and (not SawOther));
    end;
    if Trim(Lines[J]) = '' then begin Inc(J); Continue; end;
    if Pos(AUTO_BEGIN, Lines[J]) > 0 then
    begin
      if InFence then SawOther:= True; // nested/duplicate BEGIN -- ambiguous, do not exempt
      InFence := True;
      SawFence:= True;
      Inc(J);
      Continue;
    end;
    if Pos(AUTO_END, Lines[J]) > 0 then begin InFence:= False; Inc(J); Continue; end;
    if not InFence then SawOther:= True; // hand-written prose alongside the fence
    Inc(J);
  end;
  ACloseIx:= -1;
  Result:= False; // no closing '</remarks>' found anywhere in the region
end;

// v(ADP3 T3 review round 2, Finding 3; round 3, Regressions 2 and 3): true
// when EVERY line of ARawText (the EXISTING doc region's raw content -- one
// entry per source /// line, /// prefix already stripped by
// TDocCommentScanner) is engine-owned: it carries AUTO_MARK, it lies within a
// well-formed AUTO_BEGIN..AUTO_END fence (inclusive of the fence lines
// themselves), or it is one half of a fence-only '<remarks>'/'</remarks>'
// wrapper (IsFenceOnlyRemarksSpan); a blank interior line carries no content
// either way and is skipped. Gates BuildForSymbol's empty-merge delete branch
// over the RAW region instead of a field-by-field TParsedDoc whitelist
// (Exceptions/ExampleText/SeeAlso/SinceText/Deprecated): a whitelist is
// correct only by ENUMERATION -- any tag type the PARSER does not even model
// (<value>, <typeparam>, <para>, <code>, <list>, <permission>,
// <inheritdoc/>, ...) would still be silently destroyed. Testing the raw
// text directly needs no such list and no future maintenance as new tag
// types appear: an unrecognized, unmarked, non-fence line is by definition
// NOT engine-owned, so it correctly blocks the delete, regardless of whether
// the parser has ever heard of the tag it came from.
//
// Round 3, Regression 2: the engine's own '<remarks>'/'</remarks>' wrapper
// line (TDocRegions.MergeComment's remarks emission -- see its comment)
// carries no AUTO_MARK of its own and is NOT inside the fence it encloses
// (the fence starts on the line AFTER '<remarks>' and ends on the line
// BEFORE '</remarks>'), so the pre-round-3 per-line loop below always
// rejected a WHOLLY engine-authored, facts-only remarks region on its own
// wrapper tags -- meaning such a region could never satisfy this guard, so a
// DECAYED one (source changed, the fact it asserts is now false) was never
// refreshed or deleted and sat on disk asserting a stale fact permanently.
// IsFenceOnlyRemarksSpan resolves this narrowly: only a '<remarks>' whose
// span encloses NOTHING but one or more well-formed, sequential fences is
// exempted (both wrapper lines skipped as a unit); a '<remarks>' sharing its
// span with hand-written prose is NOT exempted, and that prose line still
// fails the ordinary AUTO_MARK check on its own, so the overall verdict is
// unaffected there -- this exemption only changes the answer for the
// fence-only case. (v(ADP3 T3d2 D10): "one" corrected to "one or more,
// sequential" here to match the same fix at IsFenceOnlyRemarksSpan's own
// header above -- see that comment for the full trace of why.)
//
// Round 3, Regression 3: an AUTO_BEGIN that never reaches a matching
// AUTO_END within the region now FAILS CLOSED (Exit(False) immediately)
// instead of the old fail-OPEN behaviour, where a bare InFence flag was set
// and never reset, silently treating every remaining line through EOF --
// including real hand-written prose -- as "fenced" and therefore engine-
// owned. Mirrors DRagLint.Doc.Strip.pas's StripRegion, which already treats
// this exact malformed shape (BEGIN with no END in the searched range) as
// "leave alone" rather than guessing; a stray AUTO_END with no opening
// AUTO_BEGIN is symmetrically ambiguous and also fails closed. A guard whose
// entire purpose is protecting hand-written source must fail closed on
// anything ambiguous, not open.
function RegionFullyEngineOwned(const ARawText: string): Boolean;
var
  Lines  : TArray<string>;
  L      : string        ;
  I, J   : Integer        ;
  CloseIx: Integer        ;
begin
  Lines:= ARawText.Split([sLineBreak, #10, #13]);
  I:= 0;
  while I <= High(Lines) do
  begin
    L:= Lines[I];
    if Trim(L) = '' then begin Inc(I); Continue; end;
    if (Trim(L) = '<remarks>') and IsFenceOnlyRemarksSpan(Lines, I, CloseIx) then
    begin
      I:= CloseIx + 1; // fence-only remarks wrapper, consumed as a unit
      Continue;
    end;
    if Pos(AUTO_BEGIN, L) > 0 then
    begin
      J:= I;
      while (J <= High(Lines)) and (Pos(AUTO_END, Lines[J]) = 0) do Inc(J);
      if J > High(Lines) then Exit(False); // unterminated fence -- fail closed, see header comment
      I:= J + 1; // whole fence, inclusive
      Continue;
    end;
    if Pos(AUTO_END, L) > 0 then Exit(False); // stray END with no opening BEGIN -- ambiguous, fail closed
    if Pos(AUTO_MARK, L) = 0 then Exit(False);
    Inc(I);
  end;
  Result:= True;
end;

// Returns the TDocCommentRegion immediately preceding ASymStartLine (EndLine in
// [SymStartLine - 1 - AllowGap, SymStartLine - 1]), REJECTING that candidate
// when another declaration's StartLine sits strictly BETWEEN the region and
// ASymStartLine (Best.EndLine < L < ASymStartLine for some L in
// ASymStartLines) -- such a region belongs to the INTERVENING declaration,
// not this one. Without this check, two back-to-back declarations with no
// blank line between them (A documented, B immediately after) both matched
// A's doc-comment against the line-distance window alone, so `document
// --apply` treated A's block as B's *existing* doc and rewrote/duplicated it
// -- corrupting A's comment and stamping A's prose onto B (see
// adp2-docregion-fix-report.md). ASymStartLines must be sorted ascending
// (every symbol's StartLine in the file, including ASymStartLine's own); the
// scan below early-exits once L >= ASymStartLine, keeping the cost bounded
// even on files with many symbols. A region separated from ASymStartLine by
// only blank lines (no intervening declaration) is unaffected -- blank lines
// are never symbol start-lines. When ACaptureLoose is False, loose regions
// are skipped. Sentinel: Result.Kind = TDocCommentKind(-1) means none found.
// Mirrors DRagLint.Core.Indexer.FindDocRegionAbove (which is implementation-
// only there); kept local so this unit does not pull in Indexer.
// v(ADP3 T3j review round 1): the two copies are no longer independent
// reimplementations -- both now delegate the actual decision to
// DRagLint.Core.Model's DocRegionInGapWindow + NoDeclarationInGap, which
// DRagLint.Doc.Strip's `--strip` path reads as well. Only the region-selection
// loop is duplicated; the PREDICATE has a single declaration. That is the point:
// the T3j defect (register S1) was a third copy of this window that omitted the
// guard while a comment claimed it matched.
function FindDocRegionAbove(ADocRegions: System.Generics.Collections.TList<TDocCommentRegion>;
  ASymStartLine: Integer; AAllowGap: Integer; ACaptureLoose: Boolean;
  const ASymStartLines: TArray<Integer>): TDocCommentRegion;
var
  I      : Integer          ;
  Best   : TDocCommentRegion;
  HasBest: Boolean          ;
begin
  HasBest:= False;
  // ADocRegions is sorted by StartLine ascending.
  for I:= 0 to ADocRegions.Count - 1 do
  begin
    if (not ACaptureLoose) and (ADocRegions[I].Kind in [dckLooseLine, dckLooseBlock]) then Continue;
    // v(ADP3 T3j review round 1): the window is now the SHARED
    // DocRegionInGapWindow (DRagLint.Core.Model) -- same arithmetic, one
    // declaration. Control flow deliberately unchanged: pick the last region
    // satisfying the window, THEN apply the declaration guard to it below.
    if DocRegionInGapWindow(ADocRegions[I].EndLine, ASymStartLine, AAllowGap) then
    begin
      Best:= ADocRegions[I];
      HasBest:= True;
    end;
    if ADocRegions[I].StartLine > ASymStartLine then Break;
  end;
  // Intervening-declaration check: reject Best when some OTHER symbol starts
  // strictly between Best.EndLine and ASymStartLine. v(ADP3 T3j review round 1):
  // now the SHARED NoDeclarationInGap, which `document --strip` reads too, so
  // the apply and strip paths can no longer drift apart -- the T3j defect was
  // Doc.Strip copying the window above WITHOUT this guard.
  if HasBest and (not NoDeclarationInGap(Best.EndLine, ASymStartLine, ASymStartLines)) then
    HasBest:= False;
  if HasBest then Result:= Best
  else
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.Kind:= TDocCommentKind(-1);
  end;
end;

class function TDocumenter.BuildFor(const AStore: ISymbolStore; const AQName: string): TDocumentResult;
begin
  // Back-compat: no doc-source opt-ins.
  Result:= BuildFor(AStore, AQName, False);
end;

class function TDocumenter.ExistingDocFor(const AStore: ISymbolStore; const AQName: string;
  out ASym: TSymbol; out AFound: Boolean; out AHasDoc: Boolean): TParsedDoc;
var
  Syms         : TArray<TSymbol>                                       ;
  Path         : string                                               ;
  Src          : string                                               ;
  Regions      : System.Generics.Collections.TList<TDocCommentRegion> ;
  Region       : TDocCommentRegion                                    ;
  FileSyms     : TArray<TSymbol>                                      ;
  SymStartLines: TArray<Integer>                                      ;
  I            : Integer                                              ;
begin
  Result := Default(TParsedDoc);
  ASym   := Default(TSymbol);
  AFound := False;
  AHasDoc:= False;

  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  ASym:= Syms[0];

  Path:= AStore.GetFilePath(ASym.FileId);
  if (Path = '') or (not TFile.Exists(Path)) then Exit;
  AFound:= True;

  Src:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(Path));

  // adp2-docregion-fix: every symbol's StartLine in this file, sorted
  // ascending, so FindDocRegionAbove can reject a region separated from ASym
  // by an intervening declaration (see its header comment).
  FileSyms:= AStore.FindSymbolsByFile(Path);
  SetLength(SymStartLines, Length(FileSyms));
  for I:= 0 to High(FileSyms) do SymStartLines[I]:= FileSyms[I].StartLine;
  TArray.Sort<Integer>(SymStartLines);

  // Same live-scan the Documenter uses: nearest doc-comment above the decl,
  // allow a 1-line gap, skip loose regions. Kind = TDocCommentKind(-1) = none.
  Regions:= TDocCommentScanner.Scan(Src);
  try
    // v(ADP3 T3j review round 2, Important 2): DOC_ALLOW_GAP, not a literal 1.
    // The constant existed to close the literal-drift channel between the apply
    // and strip paths, but only Doc.Strip actually read it -- so setting it to 2
    // would have widened `--strip` alone, silently recreating the very
    // apply/strip asymmetry this task exists to prevent.
    Region:= FindDocRegionAbove(Regions, ASym.StartLine, DOC_ALLOW_GAP, False, SymStartLines);
    if Region.Kind <> TDocCommentKind(-1) then
    begin
      Result := TDocCommentParser.Dispatch(Region);
      AHasDoc:= True;
    end;
  finally
    Regions.Free;
  end;
end;

class function TDocumenter.BuildFor(const AStore: ISymbolStore; const AQName: string;
  AIncludeSeeAlso: Boolean; AIncludeSince: Boolean; const ABaseDir: string;
  const AExtraStores: TArray<ISymbolStore>; AMaxReturnCases: Integer; AMaxCallers: Integer;
  AComplexityMin: Integer): TDocumentResult;
var
  Syms: TArray<TSymbol>;
begin
  Result:= Default(TDocumentResult);
  Result.QName := AQName;
  Result.Action:= daNotFound;

  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;

  Result:= BuildForSymbol(AStore, Syms[0], AIncludeSeeAlso, AIncludeSince, ABaseDir,
    AExtraStores, AMaxReturnCases, AMaxCallers, AComplexityMin);
end;

class function TDocumenter.BuildForSymbol(const AStore: ISymbolStore; const ASym: TSymbol;
  AIncludeSeeAlso: Boolean; AIncludeSince: Boolean; const ABaseDir: string;
  const AExtraStores: TArray<ISymbolStore>; AMaxReturnCases: Integer; AMaxCallers: Integer;
  AComplexityMin: Integer): TDocumentResult;
var
  Path         : string                                            ;
  Src          : string                                            ;
  Regions      : System.Generics.Collections.TList<TDocCommentRegion>;
  Region       : TDocCommentRegion                                 ;
  Existing     : TParsedDoc                                        ;
  SigParams    : TArray<string>                                    ;
  HasRet       : Boolean                                           ;
  Facts        : TDocFacts                                         ;
  Merged       : string                                            ;
  Prefix       : string                                            ;
  Sig          : string                                            ;
  CurBlock     : string                                            ;
  E            : TTextEdit                                         ;
  FileSyms     : TArray<TSymbol>                                   ;
  SymStartLines: TArray<Integer>                                   ;
  I            : Integer                                           ;
begin
  Result:= Default(TDocumentResult);
  Result.QName := ASym.QualifiedName;
  Result.Action:= daNotFound;

  Path:= AStore.GetFilePath(ASym.FileId);
  Result.FilePath:= Path;
  Result.Line    := ASym.StartLine;
  if (Path = '') or (not TFile.Exists(Path)) then Exit;

  Src:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(Path));

  // adp2-docregion-fix: every symbol's StartLine in this file, sorted
  // ascending, so FindDocRegionAbove can reject a region separated from ASym
  // by an intervening declaration (see its header comment) -- prevents
  // stacking/duplicating a doc block onto the very next back-to-back
  // declaration when there is no blank line between them.
  FileSyms:= AStore.FindSymbolsByFile(Path);
  SetLength(SymStartLines, Length(FileSyms));
  for I:= 0 to High(FileSyms) do SymStartLines[I]:= FileSyms[I].StartLine;
  TArray.Sort<Integer>(SymStartLines);

  // Existing doc-comment above the declaration (allow a 1-line gap; skip loose).
  // FindDocRegionAbove signals "not found" with Kind = TDocCommentKind(-1).
  Existing:= Default(TParsedDoc);
  Regions := TDocCommentScanner.Scan(Src);
  try
    // v(ADP3 T3j review round 2, Important 2): DOC_ALLOW_GAP, not a literal 1.
    // The constant existed to close the literal-drift channel between the apply
    // and strip paths, but only Doc.Strip actually read it -- so setting it to 2
    // would have widened `--strip` alone, silently recreating the very
    // apply/strip asymmetry this task exists to prevent.
    Region:= FindDocRegionAbove(Regions, ASym.StartLine, DOC_ALLOW_GAP, False, SymStartLines);
    if Region.Kind <> TDocCommentKind(-1) then
      Existing:= TDocCommentParser.Dispatch(Region);
  finally
    Regions.Free;
  end;

  // Signature-derived params.
  Sig      := Trim(ASym.Signature);
  SigParams:= ParseParamNames(ExtractParamList(Sig));

  Facts := TDocFactsBuilder.Build(AStore, ASym, AIncludeSeeAlso, AIncludeSince, ABaseDir, AExtraStores, AMaxReturnCases, AMaxCallers);

  // Has a return value? The indexed Signature holds only '(params): RetType'
  // (no leading 'function' keyword), so SignatureHasReturn misses it, and class
  // functions carry kind skMethod (not skFunction). Facts.ReturnType is the
  // index-grounded truth -- the type text after the trailing ':', '' for a
  // procedure -- so use it first; keep the signature/kind checks as a fallback.
  HasRet := (Facts.ReturnType <> '')
            or SignatureHasReturn(Sig)
            or (ASym.Kind in [skFunction, skConstructor]);

  // v(ADP3 T3g): the prefix carries the DECLARATION's own indentation, copied
  // verbatim. It was the hardcoded literal '/// ' from 26b986c (one of the
  // first commits of the whole `document` feature) until now, so every emitted
  // line landed at column 0 -- invisible for a unit-level routine, but for a
  // class member it silently de-indented the author's documentation on the
  // first --apply, and BOTH idempotency compares run through
  // NormalizeCommentLines, which Trims per line, so nothing could see it.
  //
  // The DECLARATION's indentation, not the existing comment's: the comment
  // documents the declaration, so the declaration is the anchor, and that is
  // the only choice that answers the gapped shape (a doc region separated from
  // its decl by a blank line, which FindDocRegionAbove tolerates via
  // AAllowGap = 1) without asking which of two lines wins.
  //
  // TDocRegions.MergeComment derives its residual LinePrefix as
  // TrimRight(APrefix) (see its own comment), so the v(ADP3 T3f) verbatim
  // carry-through picks the indentation up from here too, with no second
  // notion of "the indent" to keep in sync: an author line comes back as
  // <indent> + '///' + <everything the scanner left after the slashes>, so its
  // INTERIOR whitespace is still byte-exact while the line as a whole sits
  // where its indented siblings do.
  Prefix:= DeclIndent(Src, ASym.StartLine) + '/// ';
  // v(ADP3 T3 review round 2, Finding 4): a SEPARATE, LOCAL signal for the
  // repair-vs-fresh decision only -- NOT a widening of TParsedDoc.HasContent
  // itself (that stays narrower, exactly as before v(ADP3 T3): the indexer's
  // symbol_docs write, context bundling, TypeAt, MCP, and LSP hover all read
  // HasContent directly and correctly treat a blank-slot-only comment as
  // "not documented"). A comment consisting ONLY of a human's blank
  // <summary></summary>/<returns></returns> slot (no <param>, so
  // Existing.HasContent itself stays False) must still route MergeComment
  // through its REPAIR path, not the fresh-insert path, or it stacks a
  // second, separate comment block below the human's untouched line.
  //
  // v(ADP3 T3 review round 3, Regression 1): the OR-term this round-2 comment
  // originally added here -- (Trim(Region.RawText) <> '') -- is DELETED. It
  // routed ANY existing region with non-blank raw text into the repair
  // branch below, which deletes [Existing.StartLine..EndLine] and inserts
  // Merged -- but Merged, by construction, can only carry Summary/Params/
  // Returns/Remarks-prose (see MergeComment). A region holding a tag type
  // Merged cannot represent at all (<value>, <example>, ...) was therefore
  // deleted outright with NO gate protecting it (RegionFullyEngineOwned only
  // guards the Merged='' branch above, not this one). No committed test
  // requires the term: run_doc_p3_summaryonly is covered by HasSummaryTag,
  // the HasValueTag case by HasReturnsTag (its <returns> tag is marked and
  // empty), the other two unhandledtags cases by HasContent. Dropping it
  // restores the additive (non-destructive) behaviour those untracked tags
  // relied on before this round: when none of the OTHER disjuncts fire, the
  // region is treated as "no prior comment" and Merged is inserted as a
  // PLAIN ADDITIONAL block above the declaration (fresh-insert branch,
  // below) -- the existing lines are left completely alone, merely
  // shadowed by a second block, rather than being destroyed. Gating the
  // repair-branch delete itself the way the Merged='' branch is gated
  // (RegionFullyEngineOwned) was considered and rejected: a region with a
  // genuine hand-written <summary> PLUS facts is legitimately not fully
  // engine-owned yet still must be repairable, so that gate would block real
  // repairs, not just unsafe ones. Additive-insert stacking is the correct
  // INTERIM behaviour for a region Merged cannot model; Task 3b (tag round-
  // tripping) is where Merged learns to carry these tags, at which point the
  // repair path can handle them precisely instead of stacking.
  // v(ADP3 T9): HasRemarksTag JOINS the chain, and this is the fix the user's
  // 2026-08-02 ruling asked for (docs/lint/TRIAGE-the-22-harvest-repair.md,
  // "THE RULING"). It is NOT the round-3 widening the comment above records as
  // deleted -- that one was (Trim(Region.RawText) <> ''), which swept in ANY
  // non-blank region including ones holding tags Merged could not represent.
  // This term adds exactly one thing: a <remarks> TAG being literally present.
  // The parameter is documented as "True when the EXISTING doc region carries
  // any tag at all", so its absence was a plain omission in the enumeration,
  // not a policy.
  //
  // WHY IT IS THE NON-DESTRUCTIVE FIX, measured rather than argued. A comment
  // whose only tag is an empty <remarks></remarks> has HasContent False and no
  // summary/returns/param, so it took the FRESH-INSERT branch, which leaves the
  // author's line alone and stacks a second block below it. Cycle 2 then sees
  // one region holding both, takes the REPAIR branch, and re-emits a single
  // <remarks> -- silently dropping the author's now-surplus empty one. Measured
  // on fixtures/docp3/idempotency_shapes.EmptyRemarksOnly:
  //   7502 -> 9481 -> 9456 -> 9456 bytes, actions created/1 extended/2
  // The 25-byte cycle-2 SHRINK is exactly '/// <remarks></remarks>' + CRLF.
  //
  // Routing it to repair on cycle 1 does not MOVE that deletion earlier (the
  // trap the triage warned about); it removes the deletion entirely, because
  // repair ADOPTS the author's <remarks> as the container for its own facts
  // instead of stacking a rival one for a later cycle to reconcile. The proof
  // was already in the fixture: the six *PlusEmptyRemarks symbols each carry an
  // empty <remarks> beside a tag that DOES set this flag, so they already took
  // repair on cycle 1 -- and every one of them converges at cycle 1 with its
  // empty <remarks> intact. The only three symbols that lost content were the
  // only three that took fresh-insert.
  //
  // The round-3 comment above defers this to "Task 3b ... at which point the
  // repair path can handle them precisely instead of stacking". That
  // precondition is MET: T3f's verbatim carry-through (SplitResidualLines)
  // ships, and run_doc_p3_idempotency_sweep's own NON-DESTRUCTIVE checks prove
  // an unmodeled hand-written <value> now survives all three cycles THROUGH the
  // repair path. Stacking was the interim; it is now the thing doing the damage.
  var ExistingHasAnyTag: Boolean:=
    Existing.HasSummaryTag or Existing.HasReturnsTag or (Length(Existing.Params) > 0)
    or Existing.HasRemarksTag or Existing.HasContent;
  Merged:= TDocRegions.MergeComment(Existing, SigParams, Facts, HasRet, Prefix, AComplexityMin, ExistingHasAnyTag);

  // v(ADP3 T3): MergeComment returns '' when omit-when-empty suppression
  // leaves NOTHING to say (no summary/param/returns content and no facts to
  // render) -- see its own comment. A fresh symbol then gets NO edit at all
  // (never an insert of an empty comment); an existing comment that has
  // decayed to nothing (every tag was engine-owned and the harvest/facts that
  // fed it are now empty too) is deleted outright rather than left as -- or
  // replaced by -- a blank stub, so the file ends up with no comment there
  // either way. A second run then sees the same absence and Merged is still
  // '', so this is a stable fixed point (daUnchanged), not a re-triggering edit.
  if Trim(Merged) = '' then
  begin
    // v(ADP3 T3 review round 2, Finding 3): CONSERVATIVE guard over the RAW
    // existing region, not a field-by-field TParsedDoc whitelist -- see
    // RegionFullyEngineOwned's own comment for why a whitelist is only
    // correct by enumeration (an unmodeled tag type like <value> would still
    // be silently destroyed) where the raw-region check needs no future
    // maintenance as new tag types appear.
    if Existing.HasContent and RegionFullyEngineOwned(Region.RawText) then
    begin
      E:= Default(TTextEdit);
      E.FilePath:= Path;
      E.Kind    := tekDeleteLines;
      E.Line    := Existing.StartLine;
      E.EndLine := Existing.EndLine;
      Result.Edits:= Result.Edits + [E];
      // v(ADP3 T3k, register D1): this is the ONE place the engine emits a pure
      // deletion -- a tekDeleteLines with no matching insert. It reported
      // daExtended, which made a removal indistinguishable from a repair in both
      // the CLI text output and --json. See TDocumentAction's own remarks.
      Result.Action:= daRemoved;
    end
    else
      Result.Action:= daUnchanged;
    Exit;
  end;

  // v(ADP3 T3 review round 2, Finding 4): ExistingHasAnyTag (not just
  // Existing.HasContent) decides repair-vs-fresh here too -- a comment
  // consisting ONLY of a human's blank <summary></summary> slot must be
  // REPLACED (delete old span + insert the new Merged text that preserves
  // it) via the repair branch below, not left untouched while a SECOND,
  // separate block is inserted above the declaration by the fresh branch's
  // plain insert (which does not touch the existing lines at all).
  // ExistingHasAnyTag already subsumes Existing.HasContent (see its own
  // computation above), so testing it alone suffices.
  if ExistingHasAnyTag then
  begin
    // Idempotency: a re-run on an already-current comment makes no edit.
    // Compare the MERGED comment (the /// -prefixed lines drag-lint WOULD write)
    // against the ACTUAL current comment lines in the source file -- both are
    // /// -prefixed, so per-line-Trim aligns them. This round-trips: on apply we
    // write Merged into the file; on the next run the scanner reads those exact
    // lines back, MergeComment is idempotent (StripManagedBlock re-emits an
    // identical fence, prose preserved per-line), so run 2's Merged equals what
    // is on disk -> the normalized line sequences match -> daUnchanged, 0 edits.
    // (The old SameText(Trim(RawBlock), Trim(Merged)) could NEVER match: RawBlock
    // has the /// stripped and Merged does not, and outer Trim never aligns
    // per-line indentation -- so document always re-wrote the file.)
    // The current comment's source lines [StartLine..EndLine] (1-based ->
    // 0-based), clamped so an EndLine past EOF cannot index out of range.
    // v(ADP3 T3b review round 4): the inline loop that used to live here is
    // now ExtractSourceSpan, shared with the fresh path's own guard below --
    // see its comment for why both guards must read the on-disk comment
    // through one extraction. Behaviour identical.
    //
    // v(ADP3 T3g): the compare above is indentation-BLIND (NormalizeCommentLines
    // Trims every line -- deliberately, see its own comment), so on its own it
    // would answer daUnchanged for a block whose body is already right but
    // whose lines sit at column 0 because an earlier build put them there. That
    // is every class member in every file any pre-v(ADP3 T3g) `--apply` ever
    // touched, the 2026-07-24 YADF run included: indenting on write alone
    // repairs nothing already damaged, because nothing ever reaches the replace.
    //
    // So the guard is now BODY-equal AND INDENT-equal. When the bodies agree
    // and the indentation does not, the replace below is emitted deliberately:
    // a one-time re-indent that leaves the file's doc content byte-identical.
    // It still CONVERGES, and provably so rather than by hope -- the replace
    // writes exactly Merged's lines, so the next run's CurBlock IS Merged, both
    // compares hold, and the run after that makes no edit. The 3-cycle sweep in
    // tests\autodoc\run_doc_p3_indent.ps1 pins that, including for a block the
    // runner flattens by hand between cycles.
    //
    // Scope note: this touches ONLY the repair branch's own guard. The
    // fresh-insert branch's CommentLinesContain guard below stays exactly as it
    // is -- indentation-blind, which is CORRECT there: it exists to stop an
    // already-present block being inserted a second time, and an indentation
    // difference is no reason at all to let that unbounded growth back in.
    CurBlock:= ExtractSourceSpan(Src, Existing.StartLine, Existing.EndLine);
    if CommentLinesEqual(NormalizeCommentLines(CurBlock), NormalizeCommentLines(Merged))
       and CommentLinesIndentEqual(RawCommentLines(CurBlock), RawCommentLines(Merged)) then
    begin
      Result.Action:= daUnchanged;
      Exit;
    end;
    // Replace the old comment span. Emit the delete over [StartLine, EndLine],
    // then an insert of the merged comment AFTER (StartLine - 1) so it lands at
    // the same spot. The applier sorts back-to-front by top-line, so the delete
    // (key = its EndLine, the larger) is processed before the insert (key =
    // StartLine - 1), keeping both line ranges valid against the original text.
    E:= Default(TTextEdit);
    E.FilePath:= Path;
    E.Kind    := tekDeleteLines;
    E.Line    := Existing.StartLine;
    E.EndLine := Existing.EndLine;
    StampAnchor(E, ASym);
    Result.Edits:= Result.Edits + [E];

    E:= Default(TTextEdit);
    E.FilePath:= Path;
    E.Kind    := tekInsertLines;
    E.Line    := Existing.StartLine - 1; // insert AFTER (StartLine-1) => at StartLine
    E.Text    := Merged;
    StampAnchor(E, ASym);
    Result.Edits:= Result.Edits + [E];

    Result.Action:= daExtended;
  end
  else
  begin
    // v(ADP3 T3b review round 4, CRITICAL -- unbounded per-run growth): this
    // branch is reached when ExistingHasAnyTag is False, which is NOT the same
    // thing as "there is no comment here". A comment CAN exist above the
    // declaration and still leave every disjunct of ExistingHasAnyTag False --
    // the measured case is one whose only HasContent-bearing tag is an EMPTY or
    // WHITESPACE-ONLY <remarks>: HasSummaryTag/HasReturnsTag/Params are all
    // empty, and HasContent tests Remarks <> '' while RxRemarks.Match is
    // SINGULAR and takes the FIRST match -- which is the author's own empty tag,
    // forever, however many facts blocks accumulate below it. So control landed
    // here and inserted UNCONDITIONALLY: `document --apply` appended another
    // identical facts block on EVERY run, never reaching a fixed point
    // (measured over four applies with a reindex before each: 364 -> 517 -> 670
    // -> 823 bytes, "action":"created","edits":1 every cycle). Three
    // pre-existing siblings grew the same way for the same reason -- a
    // hand-written <since>/<example>/<seealso> (none of them in
    // ExistingHasAnyTag's OR-chain) alongside an empty <remarks> -- as does an
    // UNMODELED tag such as <value> in that company. This violates the binding
    // acceptance criterion (a second --apply must be a zero-byte diff) and
    // silently corrupts files under `document --project` or the IDE's
    // whole-project action.
    //
    // The guard: never insert a block whose lines are ALREADY sitting above
    // this declaration, verbatim. The repair branch above has had a
    // CommentLinesEqual idempotency compare since it was written; this branch
    // had none at all. Equality is the wrong test HERE, though -- the existing
    // region holds the author's own line(s) PLUS the previously-inserted copy,
    // so the two sequences are never equal, only nested (verified: a plain
    // equality guard leaves the growth completely unfixed). Hence
    // CommentLinesContain.
    //
    // Why a guard and NOT the other candidate fix (widening ExistingHasAnyTag
    // so these shapes route to the repair branch instead): the repair branch
    // DELETES [StartLine..EndLine] and re-inserts Merged, and Merged cannot
    // represent a tag type it has no field for. Widening the routing term would
    // therefore have "converged" the <value> + empty-<remarks> shape by
    // DESTROYING the author's <value> -- exactly the regression the comment on
    // ExistingHasAnyTag's own computation records being reverted once already.
    // Suppressing a duplicate INSERT deletes nothing, so every shape above
    // converges non-destructively and the hand-written tag survives intact.
    //
    // Existing.StartLine is 0 when FindDocRegionAbove found nothing at all
    // (Existing stays Default(TParsedDoc)), so the genuinely-fresh symbol skips
    // the compare entirely and inserts exactly as before.
    if (Existing.StartLine >= 1) and (Existing.EndLine >= Existing.StartLine)
       and CommentLinesContain(
             NormalizeCommentLines(ExtractSourceSpan(Src, Existing.StartLine, Existing.EndLine)),
             NormalizeCommentLines(Merged)) then
    begin
      Result.Action:= daUnchanged;
      Exit;
    end;

    // No prior comment: one insert above the declaration.
    E:= Default(TTextEdit);
    E.FilePath:= Path;
    E.Kind    := tekInsertLines;
    E.Line    := ASym.StartLine - 1; // insert AFTER (StartLine-1) => at StartLine
    E.Text    := Merged;
    StampAnchor(E, ASym);
    Result.Edits:= Result.Edits + [E];

    Result.Action:= daCreated;
  end;
end;

end.
