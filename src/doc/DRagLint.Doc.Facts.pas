unit DRagLint.Doc.Facts;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  System.Generics.Collections, System.RegularExpressions,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

const
  // Display cap for the <seealso> related-symbol list (ADF T4). At most this many
  // <seealso cref> lines are emitted, keeping the managed block terse.
  SEEALSO_CAP = 5;

type
  TDocFactRef = record
    Display   : string;   { e.g. 'Unit1.DoThing' }
    Location  : string;   { file name only, e.g. 'U1.pas' -- NO :line (volatile) }
    // v14 (D5): 'certain' | 'ambiguous' | 'unverified' | ''. The renderer marks
    // any value OTHER than 'certain'/'' with a trailing ' ?' (honest uncertainty):
    // 'ambiguous' = resolved to this symbol but >1 candidate on the type chain;
    // 'unverified' = a name-match with NO call_edges row (receiver untypable).
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
  end;

  TDocFactsBuilder = class
  public
    /// <summary>Builds the grounded facts for ASym from the index. When
    /// AIncludeSeeAlso is True (the --seealso opt-in), also populates
    /// Result.SeeAlso with the capped related-symbol crefs (resolved callees +
    /// siblings); when False, SeeAlso is left empty.</summary>
    /// <param name="AStore">Open symbol store to query; not owned. Must not be nil.</param>
    /// <param name="ASym">The symbol to document.</param>
    /// <param name="AIncludeSeeAlso">Opt-in: compute the &lt;seealso&gt; related set. Default False.</param>
    class function Build(const AStore: ISymbolStore; const ASym: TSymbol;
      AIncludeSeeAlso: Boolean = False): TDocFacts;
  end;

  /// <summary>Applies the display cap: a list of ATotal items shows all of them
  /// UNLESS ATotal > 15, in which case only the first 10 are kept and the caller
  /// appends '(+N more)' with N = ATotal - 10. Returns how many to display.</summary>
  function DocDisplayCount(ATotal: Integer): Integer;

implementation

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

class function TDocFactsBuilder.Build(const AStore: ISymbolStore; const ASym: TSymbol;
  AIncludeSeeAlso: Boolean): TDocFacts;
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
    // Unverified name-match bucket: refs whose name matches but that have no
    // call_edges row (untypable receiver).
    ResCallers:= AStore.FindUnresolvedNameCallers(LastSeg(ASym.QualifiedName));
    for RC in ResCallers do
    begin
      FR:= ToFactRef(RC);
      FR.Confidence:= 'unverified'; // enforce the '?' marker regardless of store value
      AddDistinct(FR);
    end;

    Result.CalledFromTotal:= Distinct.Count;
    Shown:= DocDisplayCount(Distinct.Count);
    SetLength(Result.CalledFrom, Shown);
    for I:= 0 to Shown - 1 do Result.CalledFrom[I]:= Distinct[I];
  finally
    Seen.Free;
    Distinct.Free;
  end;

  // Returns: type from the signature, else '' (procedures).
  Result.ReturnType:= ParseReturnType(ASym.Signature);

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
        for var K:= 0 to CallSet.Count - 1 do
          if ResolvedLeaves.IndexOf(CallSet[K]) < 0 then
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
  // the type name (FindCallersByName over its last segment).
  // v14 (D5) NOTE -- DELIBERATELY still name-based (NOT call_edges resolved). This
  // counts distinct units that reference a TYPE NAME; those are TYPE references,
  // not method call sites, so they are NOT in call_edges at all (call_edges only
  // holds resolved METHOD calls). The Called-from name-collision bug that D5 fixes
  // does not exist here in the same form -- a type-name collision is far rarer and
  // out of this milestone's scope -- so resolving UsedIn via call_edges does not
  // apply and would break a working feature for zero bug-fix benefit. Left as-is.
  if ASym.Kind in [skClass, skInterface, skRecord] then
  begin
    var URefs: TArray<TReference>:= AStore.FindCallersByName(LastSeg(ASym.QualifiedName));
    var UnitSet: TStringList:= TStringList.Create;
    try
      UnitSet.Sorted:= True;
      UnitSet.Duplicates:= dupIgnore;
      UnitSet.CaseSensitive:= False;
      for var UR in URefs do
        UnitSet.Add(ChangeFileExt(ExtractFileName(AStore.GetFilePath(UR.FileId)), ''));
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
end;

end.
