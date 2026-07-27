unit DRagLint.Doc.Drift;

interface

uses
  System.SysUtils, System.Classes, System.StrUtils,
  System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  /// <summary>The kinds of DETERMINISTIC doc-vs-code drift the engine detects.
  /// Each is a structural mismatch between a DocInsight comment and the code it
  /// documents -- NO natural-language understanding, NO LLM. See TDocDrift for
  /// the per-kind detection rule and which kinds are Fixable.</summary>
  // Per-kind detection rule (deterministic; see TDocDrift.Analyze):
  //   ddParamRenamedOrRemoved - a documented <param> whose name is not a sig param
  //   ddParamMissing          - a sig param with no <param> tag (report-only as of
  //                             v(ADP3 T3) -- see that field's own comment below)
  //   ddParamVolatileMode     - a var/out param whose <param> desc reads input-only (bounded)
  //   ddReturnsButNoValue     - a <returns> on a procedure (no return value)
  //   ddValueButNoReturns     - a function with no <returns> (FIXABLE only when a
  //                             return case is minable -- v(ADP3 T3d); see that
  //                             signal's own call site below for D2/D3)
  //   ddReturnTypeChanged     - a <c>type</c> token in <returns> != the sig return type (bounded)
  //   ddExceptionNotRaised    - an <exception cref> not in the body's actual Raises facts
  //   ddIdentifierGone        - a <c>/<paramref> code identifier no longer present (bounded)
  //   ddFactsBlockStale       - the managed facts block differs from a fresh render (FIXABLE)
  TDocDriftKind = (
    ddParamRenamedOrRemoved,
    ddParamMissing,
    ddParamVolatileMode,
    ddReturnsButNoValue,
    ddValueButNoReturns,
    ddReturnTypeChanged,
    ddExceptionNotRaised,
    ddIdentifierGone,
    ddFactsBlockStale
  );

  /// <summary>One drift finding: its kind, a human-readable detail string, the
  /// Fixable flag (True only for ddFactsBlockStale and for the
  /// ddValueButNoReturns instances a fix can actually satisfy -- a mechanical,
  /// prose-free fix; v(ADP3 T3) update: ddParamMissing is report-only, see
  /// MakeFinding's own call site for why), and the doc/decl line it anchors
  /// to.</summary>
  /// <remarks>v(ADP3 T3d): Fixable is a PER-FINDING answer, not a per-kind
  /// constant. ddValueButNoReturns reports it True only when the engine can
  /// actually satisfy that instance (a return case is minable and no
  /// hand-written blank &lt;returns&gt; slot is in the way); the same kind on a
  /// function with nothing minable is report-only. Consumers must read this
  /// field, never infer fixability from Kind.</remarks>
  TDocDriftFinding = record
    Kind   : TDocDriftKind;
    Detail : string       ;
    Fixable: Boolean      ;
    Line   : Integer      ;
  end;

  /// <summary>Pure, deterministic doc-vs-code staleness diff. Given a symbol, its
  /// signature/body facts (from the index) and a parsed DocInsight comment,
  /// reports every STRUCTURAL mismatch as a TDocDriftFinding. No LLM, no
  /// NL-understanding: every signal is an exact/token-level comparison. The three
  /// bounded heuristics (ddParamVolatileMode, ddReturnTypeChanged,
  /// ddIdentifierGone) fire ONLY on high-confidence exact matches -- a false
  /// drift finding is worse than a missed one, so when the signal is ambiguous
  /// the engine stays silent.</summary>
  TDocDrift = class
  public
    /// <summary>Analyzes ADoc against ASym's live signature and body facts,
    /// returning all drift findings (empty when the doc is structurally current).
    /// Deterministic and side-effect-free: reads the index (via AStore, for the
    /// Raises facts and the fresh facts block) but writes nothing.</summary>
    /// <param name="AStore">Open symbol store; not owned. Used for the exception
    /// Raises facts and the fresh facts-block render. Must not be nil.</param>
    /// <param name="ASym">The documented symbol (routine).</param>
    /// <param name="ADoc">The parsed DocInsight comment currently on the decl.</param>
    /// <returns>The drift findings, in a stable per-signal order.</returns>
    class function Analyze(const AStore: ISymbolStore; const ASym: TSymbol;
      const ADoc: TParsedDoc): TArray<TDocDriftFinding>;
  end;

implementation

uses
  System.IOUtils,
  DRagLint.Refactor.DocStub, DRagLint.Doc.Facts, DRagLint.Doc.Regions;

// ---------------------------------------------------------------------------
// Small deterministic helpers
// ---------------------------------------------------------------------------

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

// Collapses every run of whitespace (spaces, tabs, CR, LF) to a single space and
// trims the ends. Used to compare the current managed-block body against a fresh
// render APPLES-TO-APPLES: the doc parser flattens the stored remarks (newlines
// -> spaces via CollapseWhitespace) while RenderFactsBlock emits multi-line text,
// so a raw compare would always differ; normalizing both sides neutralizes that.
function CollapseAllWhitespace(const S: string): string;
var
  Sb  : TStringBuilder;
  I   : Integer       ;
  Prev: Boolean       ; // previous emitted char was a space
begin
  Sb:= TStringBuilder.Create;
  try
    Prev:= False;
    for I:= 1 to Length(S) do
      if CharInSet(S[I], [' ', #9, #13, #10]) then
      begin
        if not Prev then begin Sb.Append(' '); Prev:= True; end;
      end
      else begin Sb.Append(S[I]); Prev:= False; end;
    Result:= Trim(Sb.ToString);
  finally
    Sb.Free;
  end;
end;

// Extracts the managed facts-block BODY from a (post-parser) remarks string: the
// text strictly BETWEEN the AUTO_BEGIN and AUTO_END sentinels. '' when the block
// is absent or malformed (BEGIN with no following END).
function ExtractManagedBlockBody(const ARemarks: string; const ABegin, AEnd: string): string;
var
  B, E: Integer;
begin
  Result:= '';
  B:= Pos(ABegin, ARemarks);
  if B = 0 then Exit;
  B:= B + Length(ABegin);
  E:= PosEx(AEnd, ARemarks, B);
  if E = 0 then Exit;
  Result:= Copy(ARemarks, B, E - B);
end;

// Builds one drift finding.
function MakeFinding(AKind: TDocDriftKind; const ADetail: string;
  AFixable: Boolean; ALine: Integer): TDocDriftFinding;
begin
  Result.Kind   := AKind;
  Result.Detail := ADetail;
  Result.Fixable:= AFixable;
  Result.Line   := ALine;
end;

// Reads the 1-based ALine of AFilePath, trimmed. '' on any error (missing file,
// out-of-range line). Same tolerant ANSI-read idiom DocStub.ReadSourceLine and
// Facts.ReadDeclLine use (both implementation-only in their units, so this is a
// local copy rather than an added cross-unit export -- keeps the change within
// this task's file set).
function ReadDeclLine(const AFilePath: string; ALine: Integer): string;
var Lines: TArray<string>;
begin
  Result:= '';
  if (AFilePath = '') or (ALine <= 0) or (not TFile.Exists(AFilePath)) then Exit;
  try
    Lines:= TFile.ReadAllLines(AFilePath, TEncoding.ANSI);
  except
    Exit;
  end;
  if ALine <= Length(Lines) then Result:= Trim(Lines[ALine - 1]);
end;

// Returns the effective signature text for ASym: the indexed Signature, or a
// source-line read at the declaration when the index did not capture it (the
// same fallback DocStub / Documenter use).
function EffectiveSignature(const AStore: ISymbolStore; const ASym: TSymbol): string;
begin
  Result:= Trim(ASym.Signature);
  if Result = '' then
    Result:= ReadDeclLine(AStore.GetFilePath(ASym.FileId), ASym.StartLine);
end;

// Parses the return type from a signature: the text after the LAST ':' that is
// outside the parameter parentheses. '' when none (a procedure). Mirrors the
// private ParseReturnType in DRagLint.Doc.Facts (kept local so this unit does
// not depend on that unit's internals).
function ParseReturnType(const ASig: string): string;
var CloseP, Colon: Integer;
begin
  Result:= '';
  CloseP:= ASig.LastDelimiter(')');
  Colon := ASig.LastDelimiter(':');
  if (Colon > CloseP) and (Colon >= 0) then
    Result:= Trim(Copy(ASig, Colon + 2, MaxInt)).TrimRight([';']);
end;

// Splits a param-list string into its ';'-separated GROUPS, each Trimmed and
// non-empty. A group is e.g. 'const A, B: string' or 'var Buf: TBytes'. Used for
// per-group volatile-mode (var/out) detection, which ParseParamNames discards.
function SplitParamGroups(const AParamList: string): TArray<string>;
var
  Raw : TArray<string>;
  Acc : TStringList    ;
  G   : string         ;
begin
  if Trim(AParamList) = '' then Exit(nil);
  Raw:= AParamList.Split([';']);
  Acc:= TStringList.Create;
  try
    for G in Raw do
      if Trim(G) <> '' then Acc.Add(Trim(G));
    Result:= Acc.ToStringArray;
  finally
    Acc.Free;
  end;
end;

// True when the ';'-group AGroup is a var/out (volatile) parameter group -- it
// begins with a whole-word 'var' or 'out' qualifier. 'const'/'in'/plain groups
// are NOT volatile.
function GroupIsVolatile(const AGroup: string): Boolean;
var L: string;
begin
  L:= LowerCase(Trim(AGroup));
  Result:= L.StartsWith('var ') or L.StartsWith('out ');
end;

// Bare param names declared in ONE ';'-group (handles 'A, B: T' grouping and a
// leading const/var/out/in/array-of qualifier). Reuses ParseParamNames, which
// already strips those qualifiers, by feeding it the single group.
function GroupParamNames(const AGroup: string): TArray<string>;
begin
  Result:= ParseParamNames(AGroup);
end;

// Case-insensitive membership of AName in ANames.
function NameInArray(const AName: string; const ANames: TArray<string>): Boolean;
var N: string;
begin
  for N in ANames do
    if SameText(N, AName) then Exit(True);
  Result:= False;
end;

// BOUNDED heuristic support: True when ADesc reads as INPUT-ONLY -- i.e. the
// FIRST word of the description is exactly 'input' or 'in' (whole word,
// case-insensitive). This is deliberately narrow: it fires on descriptions that
// LEAD with an input claim (e.g. 'Input buffer ...', 'In value to ...') for a
// param the signature marks var/out (which are output/by-reference), and stays
// silent on ordinary prose that merely happens to contain the word 'in' later
// (e.g. 'the value in the record'), because only the LEADING word is inspected.
function DescReadsInputOnly(const ADesc: string): Boolean;
var
  S    : string ;
  I, J : Integer;
  First: string ;
begin
  Result:= False;
  S:= Trim(ADesc);
  if S = '' then Exit;
  // Take the first whitespace/punctuation-delimited word.
  I:= 1;
  while (I <= Length(S)) and not IsIdentStart(S[I]) do Inc(I);
  if I > Length(S) then Exit;
  J:= I;
  while (J <= Length(S)) and IsIdentPart(S[J]) do Inc(J);
  First:= Copy(S, I, J - I);
  Result:= SameText(First, 'input') or SameText(First, 'in');
end;

// BOUNDED heuristic support: extracts EXACT type tokens explicitly named in a
// <returns> description via the <c>Token</c> markup ONLY. Prose that does not
// wrap a token in <c>...</c> yields nothing, so the return-type check never
// guesses a type from free text. Each captured token is a bare identifier
// (letters/digits/underscore/dot for a qualified type).
function ExtractCTokens(const AText: string): TArray<string>;
var
  Acc  : TStringList;
  I, N : Integer    ;
  OpenT: Integer    ;
  CloseT: Integer   ;
  Tok  : string     ;
  Valid: Boolean    ;
  K    : Integer    ;
begin
  Acc:= TStringList.Create;
  try
    I:= 1;
    N:= Length(AText);
    while I <= N do
    begin
      // Find the next '<c>' (case-insensitive) open tag.
      OpenT:= PosEx('<c>', LowerCase(AText), I);
      if OpenT = 0 then Break;
      CloseT:= PosEx('</c>', LowerCase(AText), OpenT + 3);
      if CloseT = 0 then Break;
      Tok:= Trim(Copy(AText, OpenT + 3, CloseT - (OpenT + 3)));
      // Accept only a clean identifier (optionally dotted). Reject anything with
      // whitespace or non-identifier chars -- those are not a type token.
      Valid:= (Tok <> '') and (IsIdentStart(Tok[1]));
      if Valid then
        for K:= 2 to Length(Tok) do
          if not (IsIdentPart(Tok[K]) or (Tok[K] = '.')) then
          begin
            Valid:= False;
            Break;
          end;
      if Valid then Acc.Add(Tok);
      I:= CloseT + 4;
    end;
    Result:= Acc.ToStringArray;
  finally
    Acc.Free;
  end;
end;

// BOUNDED heuristic support: extracts identifiers explicitly marked as CODE in
// the summary/remarks prose -- either <c>Ident</c> or <paramref name="Ident"/>.
// These are the ONLY forms the ddIdentifierGone check inspects: an author who
// wrapped a word in code markup asserted it is a code identifier, so a
// deterministic exact match to a removed name is high-confidence. Ordinary prose
// words (no markup) are never considered, so the check cannot false-positive on
// natural language.
function ExtractCodeIdents(const AText: string): TArray<string>;
var
  Acc   : TStringList;
  LowerT: string     ;
  I, N  : Integer    ;
  OpenT : Integer    ;
  CloseT: Integer    ;
  QOpen : Integer    ;
  QClose: Integer    ;
  Tok   : string     ;

  procedure AddIfIdent(const S: string);
  var K: Integer; V: Boolean;
  begin
    if (S = '') or (not IsIdentStart(S[1])) then Exit;
    V:= True;
    for K:= 2 to Length(S) do
      if not IsIdentPart(S[K]) then begin V:= False; Break; end;
    if V then Acc.Add(S);
  end;

begin
  Acc:= TStringList.Create;
  try
    LowerT:= LowerCase(AText);
    N:= Length(AText);
    // <c>Ident</c>
    I:= 1;
    while I <= N do
    begin
      OpenT:= PosEx('<c>', LowerT, I);
      if OpenT = 0 then Break;
      CloseT:= PosEx('</c>', LowerT, OpenT + 3);
      if CloseT = 0 then Break;
      Tok:= Trim(Copy(AText, OpenT + 3, CloseT - (OpenT + 3)));
      AddIfIdent(Tok);
      I:= CloseT + 4;
    end;
    // <paramref name="Ident"/>
    I:= 1;
    while I <= N do
    begin
      OpenT:= PosEx('<paramref', LowerT, I);
      if OpenT = 0 then Break;
      QOpen:= PosEx('name="', LowerT, OpenT);
      if QOpen = 0 then Break;
      QOpen := QOpen + 6;
      QClose:= PosEx('"', AText, QOpen);
      if QClose = 0 then Break;
      Tok:= Trim(Copy(AText, QOpen, QClose - QOpen));
      AddIfIdent(Tok);
      I:= QClose + 1;
    end;
    Result:= Acc.ToStringArray;
  finally
    Acc.Free;
  end;
end;

// ---------------------------------------------------------------------------
// TDocDrift
// ---------------------------------------------------------------------------

class function TDocDrift.Analyze(const AStore: ISymbolStore; const ASym: TSymbol;
  const ADoc: TParsedDoc): TArray<TDocDriftFinding>;
var
  Findings  : TList<TDocDriftFinding>;
  Sig       : string                 ;
  ParamList : string                 ;
  SigNames  : TArray<string>         ;
  Groups    : TArray<string>         ;
  Facts     : TDocFacts              ;
  HasReturn : Boolean                ;
  RetType   : string                 ;
  DocLine   : Integer                ;
  DP        : TDocParam              ;
  DE        : TDocException          ;
  N         : string                 ;
begin
  Findings:= TList<TDocDriftFinding>.Create;
  try
    // The doc-comment anchor line (falls back to the decl line if the parsed doc
    // carries no position).
    if ADoc.StartLine > 0 then DocLine:= ADoc.StartLine else DocLine:= ASym.StartLine;

    // Body facts (for the exception-raised check and the fresh facts-block).
    Facts:= TDocFactsBuilder.Build(AStore, ASym);

    // Findings 1-6 are param/return drift and make sense ONLY for a routine.
    // On a class/interface/record/type-alias/const/var/property/field symbol,
    // EffectiveSignature returns the ancestor/interface heading (e.g. '(TFrame)'
    // or '(TInterfacedObject, ISomeIntf)'), which ExtractParamList/ParseParamNames
    // would otherwise mis-parse as a parameter list -- spuriously firing
    // ddParamMissing per ancestor/interface name. Gate the whole block (both the
    // sig/param/return computation and the finding emission) on routine kinds.
    if ASym.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor] then
    begin
      Sig       := EffectiveSignature(AStore, ASym);
      ParamList := ExtractParamList(Sig);
      SigNames  := ParseParamNames(ParamList);
      Groups    := SplitParamGroups(ParamList);
      RetType   := ParseReturnType(Sig);

      // HasReturn: index-grounded first (the indexed Signature has no leading
      // 'function' keyword, so SignatureHasReturn misses it and class functions
      // carry skMethod). Facts.ReturnType is the truth; keep the sig/kind checks
      // as a fallback. Same policy as TDocumenter.BuildFor.
      HasReturn:= (Facts.ReturnType <> '')
                  or (RetType <> '')
                  or SignatureHasReturn(Sig)
                  or (ASym.Kind in [skFunction, skConstructor]);

      // --- 1. ddParamRenamedOrRemoved: a documented <param> not in the sig. ----
      for DP in ADoc.Params do
        if (Trim(DP.Name) <> '') and (not NameInArray(DP.Name, SigNames)) then
          Findings.Add(MakeFinding(ddParamRenamedOrRemoved,
            Format('documented param "%s" not in signature', [DP.Name]), False, DocLine));

      // --- 2. ddParamMissing: a sig param with no <param> tag. ----------------
      // v(ADP3 T3): REPORT-ONLY, not Fixable, as of this task -- the auto-fix
      // used to add a marker-only <param> STUB (empty of prose); MergeComment's
      // omit-when-empty rule now forbids that categorically (Rule 2: a fresh or
      // missing <param> is NEVER given a skeleton, since no harvester for
      // param descriptions exists, or ever will -- see DRagLint.Doc.Regions'
      // own MergeComment comment). So this finding can no longer be
      // auto-satisfied by ANY fix pass: only a human typing a real
      // description resolves it. Fixable=True here would be a false promise
      // -- a person acting on it via `lint-all --fix` would see the finding
      // survive forever and reasonably conclude the tool is broken. The
      // finding itself stays useful (a real, permanent "this param has no
      // docs" signal for a human), just no longer claims a mechanical fix.
      for N in SigNames do
      begin
        var Documented: Boolean:= False;
        for DP in ADoc.Params do
          if SameText(DP.Name, N) then begin Documented:= True; Break; end;
        if not Documented then
          Findings.Add(MakeFinding(ddParamMissing,
            Format('signature param "%s" has no <param> tag', [N]), False, DocLine));
      end;

      // --- 3. ddParamVolatileMode: var/out param documented as input-only. ----
      // BOUNDED: fires ONLY when the param's ';'-group is var/out AND the <param>
      // desc's FIRST word is 'input'/'in'. Any other desc leaves it silent.
      for var GIdx:= 0 to High(Groups) do
        if GroupIsVolatile(Groups[GIdx]) then
          for var GN in GroupParamNames(Groups[GIdx]) do
            for DP in ADoc.Params do
              if SameText(DP.Name, GN) and DescReadsInputOnly(DP.Desc) then
                Findings.Add(MakeFinding(ddParamVolatileMode,
                  Format('var/out param "%s" documented as input-only', [GN]), False, DocLine));

      // --- 4. ddReturnsButNoValue: <returns> on a procedure. -------------------
      if (Trim(ADoc.ReturnsText) <> '') and (not HasReturn) then
        Findings.Add(MakeFinding(ddReturnsButNoValue,
          'documented <returns> but the routine returns no value', False, DocLine));

      // --- 5. ddValueButNoReturns: a function with no <returns>. -------------
      // v(ADP3 T3d, register D2 + D3): Fixable is now CONDITIONAL, not the
      // unconditional True it carried since the rule was written.
      //
      // D2 -- the false promise. `--fix` satisfies this finding through
      // TDocumenter.BuildFor -> MergeComment, whose engine-owned <returns>
      // arm emits the tag ONLY when there is a mined return case to put in
      // it (v(ADP3 T3)'s omit-when-empty rule: a <returns> with nothing to
      // say is never written). A function with no minable return site
      // therefore keeps this finding FOREVER, and Fixable=True told a person
      // running `lint-all --fix --apply` otherwise -- the same false promise
      // ddParamMissing was flipped for in v(ADP3 T3). Flipping this one to a
      // flat False was rejected: unlike <param> (which has no harvester and
      // never will), this finding IS mechanically satisfiable whenever a
      // return case is minable, and that path is proven end-to-end by
      // tests\autodoc\run_doc_drift_rule.ps1's 'Lookup: no fixable drift
      // remains' assertion. Deleting a working auto-fix to silence a
      // false promise would be the wrong trade; reporting the promise
      // ACCURATELY is the fix.
      //
      // The two conjuncts mirror the two things MergeComment needs, in the
      // narrow context where this finding fires at all (Trim(ReturnsText) is
      // '', so the tag is either absent or a literally-present empty one):
      //   * not ADoc.HasReturnsTag -- a literally-present, UNMARKED, empty
      //     '<returns></returns>' is a HUMAN's blank slot, which MergeComment
      //     preserves verbatim (ReturnsHandWritten). It re-emits the same
      //     empty tag forever, so no fix exists for that shape. (A MARKED
      //     empty one cannot reach here at all -- see D3 below.)
      //   * Length(Facts.ReturnCases) > 0 -- exactly the emptiness test
      //     MergeComment's own ObservedSuffix applies, which returns '' if
      //     and only if there are no cases.
      // A <returns> nested inside another tag makes HasReturnsTag True while
      // MergeComment's StandaloneReturns view says False, so this
      // under-promises there (reports not-fixable when a fix might exist).
      // Under-promising is the safe direction for a flag whose whole defect
      // was over-promising. That shape cannot reach this line with NON-EMPTY
      // nested text -- the text itself makes Trim(ReturnsText) non-empty -- but
      // an EMPTY nested tag ('<deprecated>dep <returns></returns> tail
      // </deprecated>') DOES reach it, and is exactly the under-promising
      // case: HasReturnsTag is True here, while MergeComment finds no
      // standalone <returns> and would emit one from the mined cases. Reported
      // report-only rather than fixable; a human still sees the finding.
      //
      // D3 -- the deliberate ruling on when this rule fires at all. Since
      // v(ADP3 T1) every engine-written <returns> carries AUTO_MARK
      // immediately after its opening tag, and the parser does NOT strip it
      // (ReturnsText keeps the marker text), so Trim(ADoc.ReturnsText) is
      // never '' for a managed tag and this rule silently stopped firing on
      // engine-written returns. That change was unintended but is CORRECT
      // and is hereby kept deliberately: the finding's own claim is "has no
      // <returns> tag", and for a marked tag that claim is factually false --
      // the tag is right there in the source. Firing on it would be a pure
      // false positive on a tag that demonstrably exists, and no fix could
      // clear it either (the marker keeps ReturnsText non-empty on every
      // subsequent run). Pinned by tests\autodoc\run_doc_p3_drift_fixable.ps1.
      if HasReturn and (Trim(ADoc.ReturnsText) = '') then
        Findings.Add(MakeFinding(ddValueButNoReturns,
          'function returns a value but has no <returns> tag',
          (not ADoc.HasReturnsTag) and (Length(Facts.ReturnCases) > 0), DocLine));

      // --- 6. ddReturnTypeChanged: a <c>Type</c> in <returns> != the sig type. -
      // BOUNDED: only an EXACT <c>...</c> token that is NOT the actual return
      // type fires. Free-text return prose (no <c> markup) never triggers this.
      if HasReturn and (RetType <> '') and (Trim(ADoc.ReturnsText) <> '') then
        for var CTok in ExtractCTokens(ADoc.ReturnsText) do
          if not SameText(CTok, RetType) then
            Findings.Add(MakeFinding(ddReturnTypeChanged,
              Format('<returns> names type "%s" but the signature returns "%s"', [CTok, RetType]),
              False, DocLine));
    end;

    // --- 7. ddExceptionNotRaised: <exception cref> not in the body's Raises. ---
    for DE in ADoc.Exceptions do
      if Trim(DE.TypeName) <> '' then
      begin
        var Raised: Boolean:= False;
        for var RC in Facts.Raises do
          if SameText(RC, DE.TypeName) then begin Raised:= True; Break; end;
        if not Raised then
          Findings.Add(MakeFinding(ddExceptionNotRaised,
            Format('documented <exception cref="%s"> but the body never raises it', [DE.TypeName]),
            False, DocLine));
      end;

    // --- 8. ddIdentifierGone: a code-marked identifier (in summary/remarks) ----
    // that is no longer a signature param. BOUNDED: only identifiers wrapped in
    // <c>...</c> or <paramref name="..."/> are considered (the author asserted
    // they are code), and only an EXACT match to a name that WAS documented as a
    // param but is no longer in the signature fires -- i.e. a removed param still
    // referenced by code markup in the prose. Plain prose words never trigger it.
    begin
      var GoneNames: TStringList:= TStringList.Create;
      try
        GoneNames.CaseSensitive:= False;
        // A "gone" identifier = a documented param name absent from the signature.
        for DP in ADoc.Params do
          if (Trim(DP.Name) <> '') and (not NameInArray(DP.Name, SigNames)) then
            GoneNames.Add(DP.Name);
        if GoneNames.Count > 0 then
        begin
          var CodeIdents: TArray<string>:=
            ExtractCodeIdents(ADoc.Summary) + ExtractCodeIdents(ADoc.Remarks);
          var Reported: TStringList:= TStringList.Create;
          try
            Reported.CaseSensitive:= False;
            for var CI in CodeIdents do
              if (GoneNames.IndexOf(CI) >= 0) and (Reported.IndexOf(CI) < 0) then
              begin
                Reported.Add(CI);
                Findings.Add(MakeFinding(ddIdentifierGone,
                  Format('prose references code identifier "%s" no longer in the signature', [CI]),
                  False, DocLine));
              end;
          finally
            Reported.Free;
          end;
        end;
      finally
        GoneNames.Free;
      end;
    end;

    // --- 9. ddFactsBlockStale: managed block text != a fresh render. FIXABLE. --
    // Only fires when the doc ACTUALLY carries a managed block (AUTO_BEGIN in the
    // remarks); a doc with no managed block is not "stale", it simply has none.
    if Pos(AUTO_BEGIN, ADoc.Remarks) > 0 then
    begin
      var CurBlock: string:= ExtractManagedBlockBody(ADoc.Remarks, AUTO_BEGIN, AUTO_END);
      // Match MergeComment's OWN IncludeReturns condition EXACTLY -- v(ADP3
      // T1) review fix (finding 2): this used to hand-expand IsManagedDesc's
      // three arms in-line (empty / the TODO sentinel / marker-keyed), which
      // is exactly the duplication that caused THIS unit to silently drift out
      // of sync with MergeComment the first time (the deleted content sniff
      // had a mirrored copy here too -- see this task's earlier fix commit).
      // Call the shared TDocRegions.IsManagedDesc instead of re-deriving the
      // same predicate a second time, so 'TODO: describe.' (and the marker
      // test) has exactly ONE executable home and the two conditions can never
      // diverge again. A symbol whose <returns> is HAND-WRITTEN (IsManagedDesc
      // False) AND that has mined return cases carries a 'Returns:' fact line
      // in its managed block; Render Fresh the same way, else the block would
      // read as perpetually stale.
      var IncludeRet: Boolean:= HasReturn
        and (not TDocRegions.IsManagedDesc(ADoc.ReturnsText))
        and (Length(Facts.ReturnCases) > 0);
      var Fresh   : string:= TDocRegions.RenderFactsBlock(Facts, '', IncludeRet);
      // Whitespace-normalized compare: the parser flattens the stored remarks to
      // single spaces, so both sides are collapsed the same way before diffing.
      if CollapseAllWhitespace(CurBlock) <> CollapseAllWhitespace(Fresh) then
        Findings.Add(MakeFinding(ddFactsBlockStale,
          'managed facts block is out of date', True, DocLine));
    end;

    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end;

end.
