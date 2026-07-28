unit ConvRules.Usage;

{ Pure "which properties does this conversion actually use" scanner.

  A conversion's From class exposes far more properties than any real form uses --
  Abcbtn.TabcToggleBtn has 3905 proptree leaves, while a real TabcToggleBtn in
  ORM3\CLIENT\VARINSP.dfm assigns nine. This unit answers, for a chosen set of .dfm and
  .pas texts, which of the From class's properties are genuinely touched, so the editor
  can mark those rows and the user can stop mapping the rest.

  Pure + headless: it takes TEXT and returns data. No file system, no VCL, no process
  spawn -- the form reads the files and passes their contents in, which is what makes
  every rule here unit-testable against inline fixtures. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  ConvRules.BlockFile;

type
  /// <summary>The outcome of examining a set of files.</summary>
  /// <remarks>Names are normalised and de-duplicated case-insensitively. Missing holds
  /// used names that match no leaf of the From property tree -- expected to be empty,
  /// and evidence of an indexer gap when it is not.</remarks>
  TUsageSet = record
    Names   : TArray<string>;
    Missing : TArray<string>;
    DfmCount: Integer;
    PasCount: Integer;
  end;

/// <summary>PURE: the property names assigned to instances of AFromClass in a .dfm text.</summary>
/// <param name="AText">The whole .dfm as text. A binary .dfm simply yields nothing.</param>
/// <param name="AFromClass">Bare class name, matched case-insensitively (e.g. 'TabcToggleBtn').</param>
/// <returns>Distinct names. A dotted assignment 'A.B' contributes BOTH 'A.B' and 'A',
/// because the root property is genuinely used and a grid row for 'A' should match.</returns>
/// <remarks>Depth-tracked line scan, not a parser. Assignments count only at the
/// immediate level of a matching block: a nested component belongs to itself, not to the
/// From class, though the scan still descends to find further instances. Values opening
/// a '{' blob, a '<' item list or a '(' list are skipped to their terminator so their
/// contents are never mistaken for assignments.</remarks>
function ScanDfmText(const AText, AFromClass: string): TArray<string>;

/// <summary>PURE: the names worth searching a .pas for, derived from the From tree:
/// every distinct full path plus every distinct last segment.</summary>
function CandidatesFor(const AFromPaths: TArray<string>): TArray<string>;

/// <summary>PURE: which candidates appear in a .pas text as '.Name' followed by a
/// non-identifier character.</summary>
/// <remarks>DELIBERATELY LOOSE (the user's ruling): it does not check which object the
/// member belongs to, and does not exclude comments or string literals. The cost is
/// over-reporting -- another component's '.Caption' marks Caption used; the gain is that
/// typed locals and any dotted access are caught. A 'with X do Caption := ...' has no
/// dot and is therefore NOT seen.</remarks>
function ScanPasText(const AText: string; const ACandidates: TArray<string>): TArray<string>;

/// <summary>PURE: union of several scans, de-duplicated case-insensitively.</summary>
function MergeUsage(const AParts: TArray<TArray<string>>): TArray<string>;

/// <summary>PURE: is a grid row's From path used? True when the path itself, or its last
/// dotted segment, is in AUsed (case-insensitive).</summary>
function IsRowUsed(const AFromPath: string; const AUsed: TArray<string>): Boolean;

/// <summary>PURE: examine a set of already-read file texts and report what the From class
/// actually uses.</summary>
/// <param name="ADfmTexts">Contents of the selected .dfm files.</param>
/// <param name="APasTexts">Contents of the selected .pas files.</param>
/// <param name="AFromClass">Bare From class name, e.g. 'TabcToggleBtn'.</param>
/// <param name="AFromPaths">Every leaf path of the From property tree, used both to derive
/// PAS candidates and to decide which used names have no row.</param>
function ComputeUsage(const ADfmTexts, APasTexts: TArray<string>;
  const AFromClass: string; const AFromPaths: TArray<string>): TUsageSet;

implementation

{ A valid (possibly dotted) DFM property name: identifier chars and dots only, starting
  with a letter or underscore. This is what keeps a continuation line of a quoted string
  -- which may well contain '=' -- from being read as an assignment. }
function IsPropName(const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if S = '' then Exit;
  if not (CharInSet(S[1], ['A'..'Z', 'a'..'z', '_'])) then Exit;
  for i := 2 to Length(S) do
    if not CharInSet(S[i], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then Exit;
  Result := True;
end;

{ 'object btnA: TabcToggleBtn' -> AName='btnA', AClass='TabcToggleBtn'. Also accepts the
  'inherited' and 'inline' block keywords real DFMs use for inherited forms and frames. }
function ParseBlockHeader(const ALine: string; out AClass: string): Boolean;
var
  S, Tok: string;
  p: Integer;
begin
  Result := False;
  AClass := '';
  S := Trim(ALine);
  Tok := FirstToken(S);
  if not (SameText(Tok, 'object') or SameText(Tok, 'inherited') or SameText(Tok, 'inline')) then
    Exit;
  p := Pos(':', S);
  if p = 0 then Exit;                      // 'inherited Frame1' with no type
  AClass := Trim(Copy(S, p + 1, MaxInt));
  // a trailing '[0]' index appears on inherited collection items
  p := Pos('[', AClass);
  if p > 0 then AClass := Trim(Copy(AClass, 1, p - 1));
  Result := AClass <> '';
end;

{ Removes the CONTENT of every single-quoted DFM string literal from ALine (the quotes
  too), collapsing the Pascal doubled-apostrophe escaped-quote convention correctly, so
  a literal's own '>', ')' or blob-closing brace can never be mistaken for a block
  terminator by a caller that then searches the result for one. A literal left open at
  end of line strips to the end of the line -- DFM values are never split mid-literal
  without a fresh opening quote on the continuation, so this is a safe simplification,
  not a real string-continuation parser. }
function StripQuoted(const ALine: string): string;
var
  i: Integer;
  InQuote: Boolean;
begin
  Result := '';
  InQuote := False;
  i := 1;
  while i <= Length(ALine) do
  begin
    if not InQuote then
    begin
      if ALine[i] = '''' then
        InQuote := True
      else
        Result := Result + ALine[i];
    end
    else
    begin
      if ALine[i] = '''' then
      begin
        if (i < Length(ALine)) and (ALine[i + 1] = '''') then
          Inc(i)                // '' inside a literal: an escaped quote, stay inside
        else
          InQuote := False;     // this quote closes the literal
      end;
    end;
    Inc(i);
  end;
end;

function ScanDfmText(const AText, AFromClass: string): TArray<string>;
var
  Lines : TArray<TRawLine>;
  Stack : TList<Boolean>;      // one entry per open block: is it a From-class block?
  Names : TList<string>;
  i, ep : Integer;
  Cur, Nm, Val, Cls: string;
  SkipTo: string;              // '' = not skipping; else the terminator to look for

  procedure AddName(const AName: string);
  var
    X: string;
    Root: string;
    DotPos: Integer;
  begin
    for X in Names do
      if SameText(X, AName) then Exit;
    Names.Add(AName);
    DotPos := Pos('.', AName);
    if DotPos > 1 then
    begin
      Root := Copy(AName, 1, DotPos - 1);
      for X in Names do
        if SameText(X, Root) then Exit;
      Names.Add(Root);
    end;
  end;

begin
  Lines  := SplitRawLines(AText);
  Stack  := TList<Boolean>.Create;
  Names  := TList<string>.Create;
  try
    SkipTo := '';
    for i := 0 to High(Lines) do
    begin
      Cur := Trim(Lines[i].Text);
      if Cur = '' then Continue;

      if SkipTo <> '' then
      begin
        // A terminator char sitting inside a quoted item value (e.g. Caption = 'Y > Z')
        // must not be mistaken for the container's own terminator -- search stripped.
        if Pos(SkipTo, StripQuoted(Cur)) > 0 then SkipTo := '';
        Continue;
      end;

      if ParseBlockHeader(Cur, Cls) then
      begin
        Stack.Add(SameText(Cls, AFromClass));
        Continue;
      end;

      if SameText(FirstToken(Cur), 'end') then
      begin
        if Stack.Count > 0 then Stack.Delete(Stack.Count - 1);
        Continue;
      end;

      if (Stack.Count = 0) or (not Stack[Stack.Count - 1]) then Continue;

      ep := Pos('=', Cur);
      if ep = 0 then Continue;
      Nm := Trim(Copy(Cur, 1, ep - 1));
      if not IsPropName(Nm) then Continue;
      AddName(Nm);

      // Stripped so a same-line value that merely CONTAINS a quoted opener character
      // (unlikely, but the same robustness rule applies here as to the terminator
      // search above) is judged on what is actually outside any quoted literal.
      Val := StripQuoted(Trim(Copy(Cur, ep + 1, MaxInt)));
      if      Val = '{' then SkipTo := '}'
      else if Val = '<' then SkipTo := '>'
      else if Val = '(' then SkipTo := ')';
    end;
    Result := Names.ToArray;
  finally
    Names.Free;
    Stack.Free;
  end;
end;

{ The last dotted segment of APath, or APath itself when it has none -- 'Font.Size' ->
  'Size', 'Caption' -> 'Caption'. }
function LastSegment(const APath: string): string;
var
  i: Integer;
begin
  Result := APath;
  for i := Length(APath) downto 1 do
    if APath[i] = '.' then Exit(Copy(APath, i + 1, MaxInt));
end;

{ Case-insensitive membership over a bare-name array. }
function HasName(const A: TArray<string>; const S: string): Boolean;
var
  X: string;
begin
  for X in A do
    if SameText(X, S) then Exit(True);
  Result := False;
end;

type
  { Case-insensitive, insertion-ordered set of names. Review fix (Important 3): the
    original CandidatesFor/MergeUsage/ScanPasText each deduplicated via
    HasName(List.ToArray, ...) -- a full array copy plus a linear scan per insertion,
    O(n^2) with n in the thousands at this feature's real scale (Abcbtn.TabcToggleBtn
    alone has 3905 proptree leaves). FSeen gives O(1) membership so repeated inserts
    stay linear overall; FOrder alongside preserves first-seen order for ToArray, which
    callers (and their tests) rely on. Implementation-only: nothing outside this unit
    needs a named set type. }
  TNameSet = class
  private
    FSeen : TDictionary<string, Byte>;
    FOrder: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AName: string);
    function Contains(const AName: string): Boolean;
    function ToArray: TArray<string>;
  end;

constructor TNameSet.Create;
begin
  inherited Create;
  FSeen  := TDictionary<string, Byte>.Create;
  FOrder := TList<string>.Create;
end;

destructor TNameSet.Destroy;
begin
  FOrder.Free;
  FSeen.Free;
  inherited;
end;

procedure TNameSet.Add(const AName: string);
var
  Key: string;
begin
  Key := LowerCase(AName);
  if not FSeen.ContainsKey(Key) then
  begin
    FSeen.Add(Key, 0);
    FOrder.Add(AName);
  end;
end;

function TNameSet.Contains(const AName: string): Boolean;
begin
  Result := FSeen.ContainsKey(LowerCase(AName));
end;

function TNameSet.ToArray: TArray<string>;
begin
  Result := FOrder.ToArray;
end;

function CandidatesFor(const AFromPaths: TArray<string>): TArray<string>;
var
  NameSet: TNameSet;
  P      : string;
  Seg    : string;
begin
  NameSet := TNameSet.Create;
  try
    for P in AFromPaths do
    begin
      if P <> '' then NameSet.Add(P);
      Seg := LastSegment(P);
      if Seg <> '' then NameSet.Add(Seg);
    end;
    Result := NameSet.ToArray;
  finally
    NameSet.Free;
  end;
end;

{ Review fix (Important 3): every distinct '.Identifier' token in AText, harvested in a
  SINGLE left-to-right pass -- each '.' is followed by the run of identifier characters
  after it, which becomes one token (an empty run, e.g. a '.' as the last character of
  the text, safely yields nothing). This replaces ScanPasText's old approach of one Pos
  scan of the WHOLE text per candidate (O(candidates x textlength), ~7810 candidates x a
  several-hundred-KB unit, per file) with one O(textlength) harvest plus an O(candidates)
  membership filter. It is exactly equivalent for the loose-match rule: a candidate is
  used iff it appears as a '.Identifier' token followed by a non-identifier character,
  which is precisely what this yields. Comments and string literals are still NOT
  excluded -- same loose semantics ScanPasText has always documented. }
function HarvestDotTokens(const AText: string): TNameSet;
var
  i, j: Integer;
begin
  Result := TNameSet.Create;
  i := 1;
  while i <= Length(AText) do
  begin
    if AText[i] = '.' then
    begin
      j := i + 1;
      while (j <= Length(AText)) and CharInSet(AText[j], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(j);
      if j > i + 1 then Result.Add(Copy(AText, i + 1, j - i - 1));
      i := j;
    end
    else
      Inc(i);
  end;
end;

function ScanPasText(const AText: string; const ACandidates: TArray<string>): TArray<string>;
var
  Tokens: TNameSet;
  Hits  : TNameSet;
  C     : string;
begin
  Tokens := HarvestDotTokens(AText);
  Hits   := TNameSet.Create;
  try
    for C in ACandidates do
      if Tokens.Contains(C) then Hits.Add(C);
    Result := Hits.ToArray;
  finally
    Hits.Free;
    Tokens.Free;
  end;
end;

function MergeUsage(const AParts: TArray<TArray<string>>): TArray<string>;
var
  NameSet: TNameSet;
  Part   : TArray<string>;
  S      : string;
begin
  NameSet := TNameSet.Create;
  try
    for Part in AParts do
      for S in Part do
        NameSet.Add(S);
    Result := NameSet.ToArray;
  finally
    NameSet.Free;
  end;
end;

function IsRowUsed(const AFromPath: string; const AUsed: TArray<string>): Boolean;
begin
  Result := HasName(AUsed, AFromPath) or HasName(AUsed, LastSegment(AFromPath));
end;

function ComputeUsage(const ADfmTexts, APasTexts: TArray<string>;
  const AFromClass: string; const AFromPaths: TArray<string>): TUsageSet;
var
  Parts: TList<TArray<string>>;
  Cand : TArray<string>;
  T, N : string;
  Miss : TList<string>;
begin
  Result := Default(TUsageSet);
  Cand   := CandidatesFor(AFromPaths);
  Parts  := TList<TArray<string>>.Create;
  Miss   := TList<string>.Create;
  try
    for T in ADfmTexts do
    begin
      Parts.Add(ScanDfmText(T, AFromClass));
      Inc(Result.DfmCount);
    end;
    for T in APasTexts do
    begin
      Parts.Add(ScanPasText(T, Cand));
      Inc(Result.PasCount);
    end;
    Result.Names := MergeUsage(Parts.ToArray);

    // A used name is Missing when no From-tree leaf matches it by either rule.
    for N in Result.Names do
    begin
      var Found: Boolean := False;
      for var P in AFromPaths do
        if SameText(P, N) or SameText(LastSegment(P), N) then
        begin
          Found := True;
          Break;
        end;
      if not Found then Miss.Add(N);
    end;
    Result.Missing := Miss.ToArray;
  finally
    Miss.Free;
    Parts.Free;
  end;
end;

end.
