unit DRagLint.Lint.UnusedEnumValue;

{ The `unused-enum-value` project rule (INBOX-lint-rules-from-new-facts-2026-09-23.md
  rule 2, lane B-ENUM).

  An enum value that nothing in the project names. Possible only since enum
  reads bind (refs.symbol_id, 1.6.0-alpha); `unused-public-symbol` does not
  cover it (its kind set has no enum_value).

  The flood risk is the IMPLICIT use: a value is reached without being named by
  `for V := Low(T) to High(T)`, Succ / Pred / Inc / Dec, a cast `TEnum(N)`, an
  ordinal cast out (`Ord(V)` stored as an integer), RTTI (TypeInfo,
  GetEnumName, GetEnumValue) and DFM streaming of a property of the type. Any
  of those on the TYPE silences the whole type -- the decision is per type, the
  finding per value. A type none of whose values is named is left to
  `unused-public-symbol` / implicit use and never reported.

  ENUMRULES (2026-10-28, owner): ON by default. Two more silences, both for the
  owner's DB-ordinal enums -- a type padded with FILLER values so a legacy value
  lands on its stored ordinal (65 dummies put LotStatus_InspNotStarted at 65):
    * a value named for its OWN ordinal (Dummy0 at 0, None64 at 64; the index
      stores the computed ordinal as the enum_value signature) is padding and
      never reported;
    * every finding carries the type's declaration as its SCOPE (ScopeFile /
      ScopeLine), so ONE `// dl:ok unused-enum-value -- <reason>` on the type
      line reviews every value of it (DRagLint.CLI.ApplyLineMarkers). }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  UNUSED_ENUM_VALUE_RULE = 'unused-enum-value';

/// <summary>Runs the rule over a project index.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <returns>One 'unused-enum-value' hint per enum value no ref names, anchored
/// at the value's declaration, for every enum type that (1) has at least one
/// value some ref DOES name and (2) shows no implicit use: no line holding a ref
/// bound to the type, one of its values, or a symbol declared of the type also
/// names Low / High / Succ / Pred / Inc / Dec / an ordinal cast / TypeInfo /
/// GetEnumName / GetEnumValue; no cast bound to the type; no property declared
/// of the type. A filler value -- named for its own ordinal, Dummy0 at 0 -- is
/// never reported. Each finding's ScopeFile / ScopeLine is the enum type's
/// declaration, where one dl:ok reviews every value of the type.</returns>
/// <remarks>Reads refs file by file (one query per file) and symbols by kind;
/// never reads source text. A same-named enum pair makes typed symbols ambiguous:
/// they bind to neither, so an implicit use through such a variable is missed
/// and its type may be reported -- the documented false-positive shape.</remarks>
function CollectUnusedEnumValue(const AStore: ISymbolStore): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  ;

const
  { Names that, on a line holding a ref bound to an enum, use the enum's values
    without naming them. }
  IMPLICIT_USE: array[0..21] of string = (
    'low', 'high', 'succ', 'pred', 'inc', 'dec', 'typeinfo', 'getenumname',
    'getenumvalue', 'ord', 'integer', 'cardinal', 'byte', 'word', 'smallint',
    'shortint', 'longint', 'longword', 'int64', 'nativeint', 'getname', 'getvalue');
  { The symbol kinds whose declared type can be an enum. }
  TYPED_KINDS: array[0..4] of string = ('field', 'var', 'local_var', 'param', 'property');
  KIND_PROPERTY = 'property';
  REF_CALL      = 'call';
  NO_ORDINAL    = -1;

{ The bare type name a symbol's signature declares (`pK: TKind` -> `tkind`). }
function DeclaredTypeLower(const ASignature: string): string;
var
  S: string;
  I: Integer;
begin
  S:= ASignature;
  I:= Pos(':', S);
  if I > 0 then S:= Copy(S, I + 1, MaxInt);
  S:= TrimLeft(S);
  I:= 1;
  while (I <= Length(S)) and CharInSet(S[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Inc(I);
  Result:= Copy(S, 1, I - 1);
  I:= LastDelimiter('.', Result);
  if I > 0 then Result:= Copy(Result, I + 1, MaxInt);
  Result:= LowerCase(Result);
end;

{ True for a FILLER value: its name ends in a decimal number equal to its own
  ordinal (Dummy0 at 0, None64 at 64). The index records the computed ordinal
  as the enum_value's signature. Padding of this shape exists so a later value
  lands on a stored ordinal (a DB byte, RTTI / streaming) and is never meant to
  be named. }
function IsOrdinalFiller(const AValue: TSymbol): Boolean;
var
  I: Integer;
begin
  I:= Length(AValue.Name);
  while (I >= 1) and CharInSet(AValue.Name[I], ['0'..'9']) do Dec(I);
  if (I = Length(AValue.Name)) or (I = 0) then Exit(False);
  var Ordinal: Integer:= StrToIntDef(Trim(AValue.Signature), NO_ORDINAL);
  Result:= (Ordinal <> NO_ORDINAL) and (StrToIntDef(Copy(AValue.Name, I + 1, MaxInt), NO_ORDINAL) = Ordinal);
end;

function CollectUnusedEnumValue(const AStore: ISymbolStore): TArray<TLintFinding>;
var
  Enums      : TDictionary<Int64, TSymbol>;   { enum type id -> type }
  EnumByName : TDictionary<string, Int64>;    { lower name -> type id; 0 when two share it }
  ValueOf    : TDictionary<Int64, TSymbol>;   { value id -> value }
  BoundToEnum: TDictionary<Int64, Int64>;     { value / typed symbol id -> type id }
  Named      : TDictionary<Int64, Boolean>;   { value ids some ref names }
  Implicit   : TDictionary<Int64, Boolean>;   { type ids with an implicit use }
  Implicits  : TDictionary<string, Boolean>;
  Findings   : TList<TLintFinding>;

  procedure ScanFile(AFileId: Int64);
  var
    Refs     : TArray<TReference>;
    LineStart: Integer;
  begin
    Refs:= AStore.GetReferencesFromFile(AFileId);
    { refs arrive ordered by line: walk one line at a time }
    LineStart:= 0;
    while LineStart < Length(Refs) do
    begin
      var LineEnd: Integer:= LineStart;
      while (LineEnd + 1 < Length(Refs)) and (Refs[LineEnd + 1].StartLine = Refs[LineStart].StartLine) do
        Inc(LineEnd);
      var HasImplicitName: Boolean:= False;
      for var I:= LineStart to LineEnd do
        if Implicits.ContainsKey(LowerCase(Refs[I].NameText)) then HasImplicitName:= True;
      for var I:= LineStart to LineEnd do
      begin
        var R: TReference:= Refs[I];
        { an UNBOUND ref spelled like a (unique) enum type on an implicit-use line:
          `Low(TFlag)` whose TFlag the resolver left unbound (measured on the engine tree) }
        var ByNm: Int64;
        if HasImplicitName and (R.SymbolId <= 0) and EnumByName.TryGetValue(LowerCase(R.NameText), ByNm) and (ByNm > 0) then
          Implicit.AddOrSetValue(ByNm, True);
        if R.SymbolId <= 0 then Continue;
        var V: TSymbol;
        if ValueOf.TryGetValue(R.SymbolId, V) then
        begin
          { a ref sitting on the value's own declaration is not a use }
          if not ((R.FileId = V.FileId) and (R.StartLine = V.StartLine) and (R.StartCol = V.StartCol)) then
            Named.AddOrSetValue(R.SymbolId, True);
        end
        else if Enums.ContainsKey(R.SymbolId) and SameText(R.Kind, REF_CALL) then
          Implicit.AddOrSetValue(R.SymbolId, True);              { cast-in TEnum(x) }
        var E: Int64;
        if HasImplicitName then
          if Enums.ContainsKey(R.SymbolId) then Implicit.AddOrSetValue(R.SymbolId, True)
          else if BoundToEnum.TryGetValue(R.SymbolId, E) then Implicit.AddOrSetValue(E, True);
      end;
      LineStart:= LineEnd + 1;
    end;
  end;

  procedure Report(const AEnum: TSymbol; const AValue: TSymbol);
  begin
    var Fd: TLintFinding:= Default(TLintFinding);
    Fd.RuleId    := UNUSED_ENUM_VALUE_RULE;
    Fd.FileId    := AValue.FileId;
    Fd.FilePath  := AStore.GetFilePath(AValue.FileId);
    Fd.StartLine := AValue.StartLine;
    Fd.EndLine   := AValue.StartLine;
    Fd.StartCol  := if AValue.StartCol > 0 then AValue.StartCol else 1;
    Fd.EndCol    := Fd.StartCol + Length(AValue.Name);
    Fd.Severity  := 'hint';
    Fd.SymbolName:= AValue.Name;
    { the TYPE scope: one dl:ok on the enum's declaration reviews every value }
    Fd.ScopeFile := AStore.GetFilePath(AEnum.FileId);
    Fd.ScopeLine := AEnum.StartLine;
    Fd.Message   := Format(
      'Enum value %s.%s is never named in the project, and %s shows no implicit use (Low/High, ' +
      'Succ/Pred, a cast, RTTI, a streamed property) -- remove it, or name it where it is meant.',
      [AEnum.Name, AValue.Name, AEnum.Name]);
    Findings.Add(Fd);
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;
  Enums      := TDictionary<Int64, TSymbol>.Create;
  EnumByName := TDictionary<string, Int64>.Create;
  ValueOf    := TDictionary<Int64, TSymbol>.Create;
  BoundToEnum:= TDictionary<Int64, Int64>.Create;
  Named      := TDictionary<Int64, Boolean>.Create;
  Implicit   := TDictionary<Int64, Boolean>.Create;
  Implicits  := TDictionary<string, Boolean>.Create;
  Findings   := TList<TLintFinding>.Create;
  try
    for var E in AStore.FindSymbolsByKind('enum', False, MaxInt) do
    begin
      Enums.AddOrSetValue(E.Id, E);
      var Lc: string:= LowerCase(E.Name);
      { a name two enums share types nothing by name }
      if EnumByName.ContainsKey(Lc) then EnumByName[Lc]:= 0 else EnumByName.Add(Lc, E.Id);
    end;
    if Enums.Count = 0 then Exit;
    for var V in AStore.FindSymbolsByKind('enum_value', False, MaxInt) do
      if Enums.ContainsKey(V.ParentId) then
      begin
        ValueOf.AddOrSetValue(V.Id, V);
        BoundToEnum.AddOrSetValue(V.Id, V.ParentId);
      end;
    for var K in TYPED_KINDS do
      for var S in AStore.FindSymbolsByKind(K, False, MaxInt) do
      begin
        var E: Int64;
        if not EnumByName.TryGetValue(DeclaredTypeLower(S.Signature), E) or (E <= 0) then Continue;
        BoundToEnum.AddOrSetValue(S.Id, E);
        { a property of the type may be streamed (DFM) by name }
        if K = KIND_PROPERTY then Implicit.AddOrSetValue(E, True);
      end;
    for var N in IMPLICIT_USE do Implicits.AddOrSetValue(N, True);
    for var Fi in AStore.GetAllFileIds do ScanFile(Fi);

    { per TYPE: values grouped by their enum, in declaration order }
    var ByEnum: TObjectDictionary<Int64, TList<TSymbol>>:= TObjectDictionary<Int64, TList<TSymbol>>.Create([doOwnsValues]);
    try
      for var V in ValueOf.Values do
      begin
        var L: TList<TSymbol>;
        if not ByEnum.TryGetValue(V.ParentId, L) then
        begin
          L:= TList<TSymbol>.Create;
          ByEnum.Add(V.ParentId, L);
        end;
        L.Add(V);
      end;
      for var Pair in ByEnum do
      begin
        if Implicit.ContainsKey(Pair.Key) then Continue;
        var AnyNamed: Boolean:= False;
        for var V in Pair.Value do
          if Named.ContainsKey(V.Id) then AnyNamed:= True;
        if not AnyNamed then Continue;
        for var V in Pair.Value do
          if not Named.ContainsKey(V.Id) and not IsOrdinalFiller(V) then Report(Enums[Pair.Key], V);
      end;
    finally
      ByEnum.Free;
    end;
    Findings.Sort(TComparer<TLintFinding>.Construct(
      function(const A, B: TLintFinding): Integer
      begin
        Result:= CompareText(A.FilePath, B.FilePath);
        if Result = 0 then Result:= A.StartLine - B.StartLine;
        if Result = 0 then Result:= A.StartCol - B.StartCol;
      end));
    Result:= Findings.ToArray;
  finally
    Findings.Free;
    Implicits.Free;
    Implicit.Free;
    Named.Free;
    BoundToEnum.Free;
    ValueOf.Free;
    EnumByName.Free;
    Enums.Free;
  end;
end;

end.
