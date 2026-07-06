unit DRagLint.Doc.Facts;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

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
  end;

  TDocFactsBuilder = class
  public
    /// <summary>Builds the grounded facts for ASym from the index.</summary>
    class function Build(const AStore: ISymbolStore; const ASym: TSymbol): TDocFacts;
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

class function TDocFactsBuilder.Build(const AStore: ISymbolStore; const ASym: TSymbol): TDocFacts;
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

  // Calls (outgoing): DECISION (t3-calls-spike-decision.md, verified via a live
  // dump-refs spike) -- there is NO store method filtering refs by
  // enclosing_symbol_id, and GetReferencesFromFile emits EVERY identifier ref
  // (locals, params, Result, Exit) with ref.Kind not discriminating calls, so an
  // enclosing-ref filter over-captures. We use a bounded body TEXT-SCAN instead:
  // scan the impl body (ImplStartLine..ImplEndLine) for 'Identifier(' call sites,
  // lexer-skipping strings/comments, deduped. Minor over-capture (Create,
  // SetLength, typecasts) is accepted for Chunk 1; the section is OMITTABLE.
  if (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
  begin
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
      Result.CallsTotal:= CallSet.Count;
      var ShownC: Integer:= DocDisplayCount(CallSet.Count);
      SetLength(Result.Calls, ShownC);
      for var J:= 0 to ShownC - 1 do Result.Calls[J]:= CallSet[J];
    finally
      CallSet.Free;
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
end;

end.
