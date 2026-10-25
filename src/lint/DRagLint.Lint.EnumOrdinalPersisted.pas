unit DRagLint.Lint.EnumOrdinalPersisted;

{ The `enum-ordinal-persisted` project rule (lane X6, spec
  docs\superpowers\specs\2026-10-25-three-lint-rules-design.md rule 2).

  An enum whose ORDINAL is written to (or read from) a stream, pipe, dataset or
  registry is a storage format: inserting or reordering a value silently changes
  what old data means. The rule flags such an enum when its ordinals are NOT
  pinned (`= N` on every value). It reads only indexed facts plus the enum's
  declaration text; no baseline. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  ENUM_ORDINAL_PERSISTED_RULE = 'enum-ordinal-persisted';
  /// <summary>The sink table's file name inside the engine's rules\ folder.</summary>
  ENUM_PERSIST_SINKS_FILE = 'enum-persist-sinks.txt';

/// <summary>The compiled-in sink list -- the same names as the shipped
/// rules\enum-persist-sinks.txt.</summary>
/// <returns>Stream / pipe, dataset / SQL and registry / ini routine names.</returns>
/// <remarks>Used only when the table file is missing, so a lost file never turns
/// the rule into a silent no-op.</remarks>
function DefaultEnumPersistSinks: TArray<string>;

/// <summary>Reads a sink table: one name per line, '#' comment lines and blank
/// lines skipped.</summary>
/// <param name="pPath">The table file. '' or a missing file selects
/// DefaultEnumPersistSinks.</param>
/// <returns>The sink names, trimmed, in file order.</returns>
/// <remarks>An existing file is authoritative, even when it lists nothing. A file that
/// exists but cannot be read propagates TFile.ReadAllLines' exception.</remarks>
function LoadEnumPersistSinks(const pPath: string): TArray<string>;

/// <summary>Counts the values of an enum declaration and how many of them carry
/// no explicit `= N`.</summary>
/// <param name="pDeclText">Source text starting at the enum's name, e.g.
/// `TKind = (kA = 0, kB { kB = 1 }, kC);` -- it may run past the declaration.</param>
/// <param name="pTotal">Out: the number of values; 0 when no value list is found.</param>
/// <returns>The number of values with an IMPLICIT ordinal.</returns>
/// <remarks>Comments ({ }, (* *), //) and string literals are ignored, so a
/// commented-out `= N` is not a pin. Parentheses nest, so `kA = Ord('a')` is one
/// value. The scan stops at the value list's closing parenthesis.</remarks>
function CountImplicitOrdinals(const pDeclText: string; out pTotal: Integer): Integer;

/// <summary>Runs the rule over a project index.</summary>
/// <param name="AStore">The project index; must not be nil.</param>
/// <param name="ASinksPath">The sink table file; '' selects
/// &lt;exe-dir&gt;\rules\enum-persist-sinks.txt.</param>
/// <returns>One warning per enum type that (1) has an ordinal cast -- cast-in
/// `TEnum(x)` bound to the type, or cast-out `Ord(v)` / `Integer(v)` / ... on a
/// line with exactly one enum-bound ref -- (2) in a routine that also names a
/// sink, and (3) has at least one value with an implicit ordinal. Anchored at the
/// enum's declaration; the message names one boundary site and its sink.</returns>
/// <remarks>Reads the source of each candidate enum's declaration from disk; an
/// unreadable file costs that enum's finding only. Cast-in relies on the G1
/// binding (resolver stream ResolveEnumCastRefs), so an index built before it
/// sees cast-out sites only.</remarks>
function CollectEnumOrdinalPersisted(const AStore: ISymbolStore;
  const ASinksPath: string = ''): TArray<TLintFinding>;

implementation

const
  { The built-in ordinal casts whose argument is an enum value on a cast-out line. }
  ORD_CASTS: array[0..19] of string = (
    'ord', 'integer', 'cardinal', 'byte', 'word', 'smallint', 'shortint', 'longint',
    'longword', 'dword', 'int8', 'int16', 'int32', 'int64', 'uint8', 'uint16',
    'uint32', 'uint64', 'nativeint', 'nativeuint');
  { The symbol kinds whose declared type can be an enum. }
  TYPED_KINDS: array[0..4] of string = ('field', 'var', 'local_var', 'param', 'property');
  { How far past the enum's start line the value list may run. }
  DECL_WINDOW_LINES = 400;
  REF_CALL = 'call';
  REF_WRITE = 'write';

function DefaultEnumPersistSinks: TArray<string>;
begin
  Result:= ['WriteBuffer', 'ReadBuffer', 'Write', 'Read', 'WriteFile', 'ReadFile',
    'WriteMessage', 'ReadMessage', 'SaveToStream', 'LoadFromStream',
    'FieldByName', 'ParamByName', 'AsInteger', 'AsLargeInt', 'Post', 'ExecSQL',
    'WriteInteger', 'ReadInteger'];
end;

function LoadEnumPersistSinks(const pPath: string): TArray<string>;
var
  Acc: TList<string>;
begin
  if (pPath = '') or not TFile.Exists(pPath) then Exit(DefaultEnumPersistSinks);
  Acc:= TList<string>.Create;
  try
    for var Line in TFile.ReadAllLines(pPath, TEncoding.ANSI) do
    begin
      var T: string:= Trim(Line);
      if (T <> '') and not T.StartsWith('#') then Acc.Add(T);
    end;
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

{ ADecl with every comment and string literal replaced by a space. }
function StripCommentsAndStrings(const ADecl: string): string;
var
  I       : Integer;
  InBrace : Boolean;
  InStar  : Boolean;
  InSlash  : Boolean;
  InString: Boolean;
begin
  Result  := ADecl;
  InBrace := False;
  InStar  := False;
  InSlash  := False;
  InString:= False;
  I:= 1;
  while I <= Length(Result) do
  begin
    var Ch: Char:= Result[I];
    var Nx: Char:= if I < Length(Result) then Result[I + 1] else #0;
    if InSlash then
    begin
      if CharInSet(Ch, [#10, #13]) then InSlash:= False else Result[I]:= ' ';
    end
    else if InBrace then
    begin
      InBrace:= Ch <> '}';
      Result[I]:= ' ';
    end
    else if InStar then
    begin
      Result[I]:= ' ';
      if (Ch = '*') and (Nx = ')') then
      begin
        Result[I + 1]:= ' ';
        Inc(I);
        InStar:= False;
      end;
    end
    else if InString then
    begin
      InString:= Ch <> '''';
      Result[I]:= ' ';
    end
    else if Ch = '{' then
    begin
      InBrace:= True;
      Result[I]:= ' ';
    end
    else if (Ch = '(') and (Nx = '*') then
    begin
      InStar:= True;
      Result[I]:= ' ';
      Result[I + 1]:= ' ';
      Inc(I);
    end
    else if (Ch = '/') and (Nx = '/') then
    begin
      InSlash:= True;
      Result[I]:= ' ';
    end
    else if Ch = '''' then
    begin
      InString:= True;
      Result[I]:= ' ';
    end;
    Inc(I);
  end;
end;

function CountImplicitOrdinals(const pDeclText: string; out pTotal: Integer): Integer;
var
  S      : string ;
  Depth  : Integer;
  ItemAt : Integer;
  Started: Boolean;

  { Counts the value S[ItemAt..AEnd - 1], if it is not blank. }
  procedure CloseItem(AEnd: Integer);
  begin
    var Item: string:= Copy(S, ItemAt, AEnd - ItemAt);
    if Trim(Item) <> '' then
    begin
      Inc(pTotal);
      if Pos('=', Item) = 0 then Inc(Result);
    end;
    ItemAt:= AEnd + 1;
  end;

begin
  Result := 0;
  pTotal := 0;
  S      := StripCommentsAndStrings(pDeclText);
  var Eq: Integer:= Pos('=', S);
  if Eq = 0 then Exit;
  Depth  := 0;
  ItemAt := 0;
  Started:= False;
  for var I:= Eq + 1 to Length(S) do
  begin
    var Ch: Char:= S[I];
    if not Started then
    begin
      if Ch = '(' then
      begin
        Started:= True;
        Depth  := 1;
        ItemAt := I + 1;
      end
      else if not CharInSet(Ch, [' ', #9, #10, #13]) then
        Exit;  { `= class`, `= set of`, ... -- not a value list }
      Continue;
    end;
    if Ch = '(' then Inc(Depth)
    else if Ch = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        CloseItem(I);
        Exit;
      end;
    end
    else if (Ch = ',') and (Depth = 1) then
      CloseItem(I);
  end;
  { no closing parenthesis inside the window: the list is unreadable }
  pTotal:= 0;
  Result:= 0;
end;

{ The bare type name a symbol's signature declares (`pK: TKind` -> `TKind`,
  `Unit.TKind` -> `TKind`), '' when there is none. }
function DeclaredTypeName(const ASignature: string): string;
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
end;

type
  { One boundary site of one enum: the cast, the sink and where they meet. }
  TEnumWitness = record
    Cast   : string;
    Sink   : string;
    Routine: Int64 ;
    Line   : Integer;
    CastIn : Boolean;
  end;

function CollectEnumOrdinalPersisted(const AStore: ISymbolStore;
  const ASinksPath: string): TArray<TLintFinding>;
var
  Sinks      : TDictionary<string, Boolean>;
  Casts      : TDictionary<string, Boolean>;
  Enums      : TDictionary<Int64, TSymbol>;
  EnumByName : TDictionary<string, Int64>;
  BoundToEnum: TDictionary<Int64, Int64>;
  Witness    : TDictionary<Int64, TEnumWitness>;
  Findings   : TList<TLintFinding>;

  procedure Offer(AEnumId: Int64; const ACast, ASink: string; ARoutine: Int64;
    ALine: Integer; ACastIn: Boolean);
  var
    W: TEnumWitness;
  begin
    if Witness.ContainsKey(AEnumId) then Exit;
    W.Cast   := ACast;
    W.Sink   := ASink;
    W.Routine:= ARoutine;
    W.Line   := ALine;
    W.CastIn := ACastIn;
    Witness.Add(AEnumId, W);
  end;

  procedure ScanFile(AFileId: Int64);
  var
    Refs     : TArray<TReference>;
    SinkOf   : TDictionary<Int64, string>;
    LineStart: Integer;
  begin
    Refs:= AStore.GetReferencesFromFile(AFileId);
    SinkOf:= TDictionary<Int64, string>.Create;
    try
      for var R in Refs do
        if (R.EnclosingSymbolId > 0) and not SameText(R.Kind, REF_WRITE)
           and Sinks.ContainsKey(LowerCase(R.NameText)) and not SinkOf.ContainsKey(R.EnclosingSymbolId) then
          SinkOf.Add(R.EnclosingSymbolId, R.NameText);
      if SinkOf.Count = 0 then Exit;
      { refs arrive ordered by line: walk one line at a time }
      LineStart:= 0;
      while LineStart < Length(Refs) do
      begin
        var LineEnd: Integer:= LineStart;
        while (LineEnd + 1 < Length(Refs)) and (Refs[LineEnd + 1].StartLine = Refs[LineStart].StartLine) do
          Inc(LineEnd);
        var Bound: Integer:= 0;
        var BoundEnum: Int64:= 0;
        for var I:= LineStart to LineEnd do
        begin
          var R: TReference:= Refs[I];
          var E: Int64;
          if (R.SymbolId > 0) and not SameText(R.Kind, REF_CALL) and BoundToEnum.TryGetValue(R.SymbolId, E) then
          begin
            Inc(Bound);
            BoundEnum:= E;
          end;
        end;
        for var I:= LineStart to LineEnd do
        begin
          var R: TReference:= Refs[I];
          var Sink: string;
          if not SameText(R.Kind, REF_CALL) or not SinkOf.TryGetValue(R.EnclosingSymbolId, Sink) then Continue;
          if (R.SymbolId > 0) and Enums.ContainsKey(R.SymbolId) then
            Offer(R.SymbolId, R.NameText, Sink, R.EnclosingSymbolId, R.StartLine, True)
          else if (R.SymbolId = 0) and (Bound = 1) and Casts.ContainsKey(LowerCase(R.NameText)) then
            Offer(BoundEnum, R.NameText, Sink, R.EnclosingSymbolId, R.StartLine, False);
        end;
        LineStart:= LineEnd + 1;
      end;
    finally
      SinkOf.Free;
    end;
  end;

  function DeclTextOf(const AEnum: TSymbol): string;
  var
    Lines: TArray<string>;
  begin
    Result:= '';
    try
      Lines:= TFile.ReadAllLines(AStore.GetFilePath(AEnum.FileId), TEncoding.ANSI);
    except  // dl:ok try-except-swallowed@57ce -- by design, as in CollectAssertWithSideEffect: an unreadable source file costs that enum's finding only, never the whole lint run
      on EInOutError do Exit;
      on EStreamError do Exit;
      on EEncodingError do Exit;
    end;
    var SB: TStringBuilder:= TStringBuilder.Create;
    try
      for var L:= AEnum.StartLine to AEnum.StartLine + DECL_WINDOW_LINES do
      begin
        if (L < 1) or (L > Length(Lines)) then Break;
        var Txt: string:= Lines[L - 1];
        if (L = AEnum.StartLine) and (AEnum.StartCol > 1) then Txt:= Copy(Txt, AEnum.StartCol, MaxInt);
        SB.Append(Txt).Append(sLineBreak);
      end;
      Result:= SB.ToString;
    finally
      SB.Free;
    end;
  end;

  procedure Report(const AEnum: TSymbol; const AW: TEnumWitness);
  var
    Total   : Integer;
    Implicit: Integer;
  begin
    Implicit:= CountImplicitOrdinals(DeclTextOf(AEnum), Total);
    if Implicit = 0 then Exit;
    var Site: string:= if AW.CastIn then AW.Sink + ' -> ' + AW.Cast + '()' else AW.Cast + ' -> ' + AW.Sink;
    var Fd: TLintFinding:= Default(TLintFinding);
    Fd.RuleId    := ENUM_ORDINAL_PERSISTED_RULE;
    Fd.FileId    := AEnum.FileId;
    Fd.FilePath  := AStore.GetFilePath(AEnum.FileId);
    Fd.StartLine := AEnum.StartLine;
    Fd.EndLine   := AEnum.StartLine;
    Fd.StartCol  := if AEnum.StartCol > 0 then AEnum.StartCol else 1;
    Fd.EndCol    := Fd.StartCol + Length(AEnum.Name);
    Fd.Severity  := 'warning';
    Fd.SymbolName:= AEnum.Name;
    Fd.Message   := Format(
      '%s crosses a persistence boundary (%s in %s:%d) but %d of %d values have implicit ordinals ' +
      '-- inserting or reordering a value silently changes stored data. Pin each value (= N).',
      [AEnum.Name, Site, AStore.GetSymbolById(AW.Routine).QualifiedName, AW.Line, Implicit, Total]);
    Findings.Add(Fd);
  end;

begin
  Sinks      := TDictionary<string, Boolean>.Create;
  Casts      := TDictionary<string, Boolean>.Create;
  Enums      := TDictionary<Int64, TSymbol>.Create;
  EnumByName := TDictionary<string, Int64>.Create;
  BoundToEnum:= TDictionary<Int64, Int64>.Create;
  Witness    := TDictionary<Int64, TEnumWitness>.Create;
  Findings   := TList<TLintFinding>.Create;
  try
    var Path: string:= ASinksPath;
    if Path = '' then
      Path:= TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'rules\' + ENUM_PERSIST_SINKS_FILE);
    for var S in LoadEnumPersistSinks(Path) do Sinks.AddOrSetValue(LowerCase(S), True);
    for var C in ORD_CASTS do Casts.AddOrSetValue(C, True);
    for var E in AStore.FindSymbolsByKind('enum', False, MaxInt) do
    begin
      Enums.AddOrSetValue(E.Id, E);
      var Lc: string:= LowerCase(E.Name);
      { a name two enums share types nothing by name }
      if EnumByName.ContainsKey(Lc) then EnumByName[Lc]:= 0 else EnumByName.Add(Lc, E.Id);
    end;
    if Enums.Count = 0 then Exit(nil);
    for var V in AStore.FindSymbolsByKind('enum_value', False, MaxInt) do
      if Enums.ContainsKey(V.ParentId) then BoundToEnum.AddOrSetValue(V.Id, V.ParentId);
    for var K in TYPED_KINDS do
      for var V in AStore.FindSymbolsByKind(K, False, MaxInt) do
      begin
        var E: Int64;
        if EnumByName.TryGetValue(LowerCase(DeclaredTypeName(V.Signature)), E) and (E > 0) then
          BoundToEnum.AddOrSetValue(V.Id, E);
      end;
    for var Fi in AStore.GetAllFileIds do ScanFile(Fi);
    for var Pair in Witness do Report(Enums[Pair.Key], Pair.Value);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
    Witness.Free;
    BoundToEnum.Free;
    EnumByName.Free;
    Enums.Free;
    Casts.Free;
    Sinks.Free;
  end;
end;

end.
