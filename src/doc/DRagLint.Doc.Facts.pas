unit DRagLint.Doc.Facts;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TDocFactRef = record
    Display : string;   { e.g. 'Unit1.DoThing' }
    Location: string;   { file name only, e.g. 'U1.pas' -- NO :line (volatile) }
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
  Refs   : TArray<TReference>;
  R      : TReference        ;
  Encl   : TSymbol           ;
  FR     : TDocFactRef       ;
  Distinct: TList<TDocFactRef>;
  Seen   : TDictionary<string, Boolean>;
  Key    : string            ;
  Shown  : Integer           ;
  I      : Integer           ;
begin
  Result:= Default(TDocFacts);

  // Called from: name-based caller refs -> display 'EnclosingQName (file)'.
  // IDEMPOTENCY: the Location is the caller FILE NAME ONLY -- deliberately NO
  // ':line'. A line number is VOLATILE: applying this managed comment inserts N
  // lines above every caller that sits below the insertion point, so on the next
  // index+run the caller's StartLine has shifted and the regenerated facts block
  // would differ from what is on disk -- 'document' would re-write the file every
  // run, breaking the managed-region idempotency promise. The file name is stable
  // across edits and the caller's qualified name already lets a reader navigate.
  //
  // DEDUPE: a caller routine that references the target 2+ times yields multiple
  // TReference rows that -- now that the volatile ':line' is dropped -- collapse
  // to IDENTICAL (Display, Location) pairs. Fold them to a single entry keyed on
  // 'Display|Location' (both line-free), preserving first-seen order, so a reader
  // sees each DISTINCT caller once. CalledFromTotal is the DISTINCT count, so the
  // '(+N more)' suffix reflects distinct callers, and the display cap applies to
  // the deduped list.
  Refs:= AStore.FindCallersByName(LastSeg(ASym.QualifiedName));
  Distinct:= TList<TDocFactRef>.Create;
  Seen    := TDictionary<string, Boolean>.Create;
  try
    for I:= 0 to High(Refs) do
    begin
      R:= Refs[I];
      FR:= Default(TDocFactRef);
      if R.EnclosingSymbolId > 0 then
      begin
        Encl:= AStore.GetSymbolById(R.EnclosingSymbolId);
        FR.Display:= Encl.QualifiedName;
      end;
      if FR.Display = '' then FR.Display:= LastSeg(ASym.QualifiedName) + ' caller';
      FR.Location:= ExtractFileName(AStore.GetFilePath(R.FileId));
      Key:= FR.Display + '|' + FR.Location;
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      Distinct.Add(FR);
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
