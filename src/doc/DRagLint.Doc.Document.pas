unit DRagLint.Doc.Document;

interface

uses
  System.SysUtils,
  DRagLint.Core.Model, DRagLint.Core.Interfaces,
  DRagLint.Refactor.TextEdit;

type
  TDocumentAction = (daCreated, daExtended, daUnchanged, daNotFound);

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
    /// comment changed), daUnchanged (identical -- no edits), or daNotFound
    /// (symbol/file missing). Edits are dry-run data; the caller applies them.</summary>
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

// v(ADP3 T3 review round 3, Regression 2): looks ahead from AOpenIx (which
// Lines[AOpenIx] trims to exactly '<remarks>') for a matching '</remarks>'
// line. Returns True (with ACloseIx set to that line's index) only when the
// span strictly between them contains nothing but blank lines plus exactly
// one well-formed AUTO_BEGIN..AUTO_END fence -- the EXACT shape
// TDocRegions.MergeComment emits for a facts-only remarks (no hand prose;
// see its own remarks-emission comment). Returns False (ACloseIx = -1) for
// anything else: no closing tag found in the region at all, no fence found,
// OR any other non-blank content alongside the fence -- a <remarks> that
// mixes hand-written prose in with the facts fence must NOT be swept up by
// this exemption (that prose line still has to earn ownership on its own
// merits via RegionFullyEngineOwned's ordinary per-line AUTO_MARK check). A
// bare hand-written empty '<remarks></remarks>' (no fence at all) also
// correctly returns False here: SawFence never becomes True, so there is
// nothing engine-authored to justify exempting the wrapper -- fail CLOSED
// when there is nothing to prove ownership, the same principle Regression 3
// applies to a malformed fence below.
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
// span encloses NOTHING but one well-formed fence is exempted (both wrapper
// lines skipped as a unit); a '<remarks>' sharing its span with hand-written
// prose is NOT exempted, and that prose line still fails the ordinary
// AUTO_MARK check on its own, so the overall verdict is unaffected there --
// this exemption only changes the answer for the fence-only case.
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
function FindDocRegionAbove(ADocRegions: System.Generics.Collections.TList<TDocCommentRegion>;
  ASymStartLine: Integer; AAllowGap: Integer; ACaptureLoose: Boolean;
  const ASymStartLines: TArray<Integer>): TDocCommentRegion;
var
  I      : Integer          ;
  Best   : TDocCommentRegion;
  HasBest: Boolean          ;
  L      : Integer          ;
begin
  HasBest:= False;
  // ADocRegions is sorted by StartLine ascending.
  for I:= 0 to ADocRegions.Count - 1 do
  begin
    if (not ACaptureLoose) and (ADocRegions[I].Kind in [dckLooseLine, dckLooseBlock]) then Continue;
    if (ADocRegions[I].EndLine >= ASymStartLine - 1 - AAllowGap) and (ADocRegions[I].EndLine <= ASymStartLine - 1) then
    begin
      Best:= ADocRegions[I];
      HasBest:= True;
    end;
    if ADocRegions[I].StartLine > ASymStartLine then Break;
  end;
  // Intervening-declaration check: reject Best when some OTHER symbol starts
  // strictly between Best.EndLine and ASymStartLine.
  if HasBest then
    for L in ASymStartLines do
    begin
      if L >= ASymStartLine then Break; // sorted ascending -- nothing further can qualify
      if L > Best.EndLine then
      begin
        HasBest:= False;
        Break;
      end;
    end;
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
    Region:= FindDocRegionAbove(Regions, ASym.StartLine, 1, False, SymStartLines);
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
  SrcLines     : TArray<string>                                    ;
  CurBlock     : string                                            ;
  LineIx       : Integer                                           ;
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
    Region:= FindDocRegionAbove(Regions, ASym.StartLine, 1, False, SymStartLines);
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

  Prefix:= '/// ';
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
  var ExistingHasAnyTag: Boolean:=
    Existing.HasSummaryTag or Existing.HasReturnsTag or (Length(Existing.Params) > 0)
    or Existing.HasContent;
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
      Result.Action:= daExtended;
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
    SrcLines:= Src.Replace(#13#10, #10, [rfReplaceAll]).Replace(#13, #10, [rfReplaceAll]).Split([#10]);
    // Extract the current comment's source lines [StartLine..EndLine] (1-based ->
    // 0-based), clamped so an EndLine past EOF cannot index out of range.
    CurBlock:= '';
    for LineIx:= Existing.StartLine to Existing.EndLine do
      if (LineIx >= 1) and (LineIx <= Length(SrcLines)) then
      begin
        if CurBlock <> '' then CurBlock:= CurBlock + #10;
        CurBlock:= CurBlock + SrcLines[LineIx - 1];
      end;
    if CommentLinesEqual(NormalizeCommentLines(CurBlock), NormalizeCommentLines(Merged)) then
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
    Result.Edits:= Result.Edits + [E];

    E:= Default(TTextEdit);
    E.FilePath:= Path;
    E.Kind    := tekInsertLines;
    E.Line    := Existing.StartLine - 1; // insert AFTER (StartLine-1) => at StartLine
    E.Text    := Merged;
    Result.Edits:= Result.Edits + [E];

    Result.Action:= daExtended;
  end
  else
  begin
    // No prior comment: one insert above the declaration.
    E:= Default(TTextEdit);
    E.FilePath:= Path;
    E.Kind    := tekInsertLines;
    E.Line    := ASym.StartLine - 1; // insert AFTER (StartLine-1) => at StartLine
    E.Text    := Merged;
    Result.Edits:= Result.Edits + [E];

    Result.Action:= daCreated;
  end;
end;

end.
