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
        if Pos(SkipTo, Cur) > 0 then SkipTo := '';
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

      Val := Trim(Copy(Cur, ep + 1, MaxInt));
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

function CandidatesFor(const AFromPaths: TArray<string>): TArray<string>;
var
  List: TList<string>;
  P   : string;

  procedure Add(const S: string);
  begin
    if (S <> '') and not HasName(List.ToArray, S) then List.Add(S);
  end;

begin
  List := TList<string>.Create;
  try
    for P in AFromPaths do
    begin
      Add(P);
      Add(LastSegment(P));
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ScanPasText(const AText: string; const ACandidates: TArray<string>): TArray<string>;
var
  Low  : string;
  List : TList<string>;
  C, Nd: string;
  p, aft: Integer;
  Found: Boolean;
begin
  Low  := LowerCase(AText);
  List := TList<string>.Create;
  try
    for C in ACandidates do
    begin
      Nd := '.' + LowerCase(C);
      p  := Pos(Nd, Low);
      Found := False;
      while (p > 0) and not Found do
      begin
        aft := p + Length(Nd);
        if (aft > Length(Low))
           or not CharInSet(Low[aft], ['a'..'z', '0'..'9', '_']) then
          Found := True
        else
          p := Pos(Nd, Low, p + 1);
      end;
      if Found and not HasName(List.ToArray, C) then List.Add(C);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function MergeUsage(const AParts: TArray<TArray<string>>): TArray<string>;
var
  List: TList<string>;
  Part: TArray<string>;
  S   : string;
begin
  List := TList<string>.Create;
  try
    for Part in AParts do
      for S in Part do
        if not HasName(List.ToArray, S) then List.Add(S);
    Result := List.ToArray;
  finally
    List.Free;
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
