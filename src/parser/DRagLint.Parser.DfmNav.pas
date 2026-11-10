unit DRagLint.Parser.DfmNav;

/// <summary>150 Y2: the ONE line scanner that turns a text .dfm into its
/// navigation tree (blocks, collection items and the properties forms-csv /
/// menu-tree read). The indexer stores its rows (dfm_nav_nodes / dfm_nav_props)
/// through TDFMParser.Parse; TFormDfmTree builds its nodes from those rows, or
/// from this scanner run on the file when the index has none -- so the table path
/// and the text path are the same rows by construction.</summary>
/// <remarks>
/// Moved here from DRagLint.FormsMap.Dfm (TFormDfmTree.LoadFromLines /
/// ReadValue / DecodeDfmString), behaviour unchanged except the property filter
/// (IsDfmNavProp), which drops only properties no reader asks for. Pure
/// functions; thread-safe.
/// </remarks>

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  ;

/// <summary>Decodes raw .dfm bytes the way the indexer does (EnsureUtf8Bytes:
/// BOM stripped, UTF-16 transcoded, BOM-less non-UTF-8 read as Windows-1252)
/// and splits them with DfmNavTextLines.</summary>
/// <param name="ARaw">The file bytes as read from disk; a binary .dfm is the
/// caller's business (this does not test for one).</param>
/// <returns>The lines.</returns>
function DfmNavLinesFromBytes(const ARaw: TBytes): TArray<string>;

/// <summary>Scans the lines of a text .dfm into navigation-tree rows.</summary>
/// <param name="ALines">The .dfm lines (DfmNavTextLines / DfmNavLinesFromBytes).</param>
/// <param name="ANodes">Out: one row per `object` / `inherited` / `inline`
/// header and per collection `item`, in .dfm order; Ordinal = array index.</param>
/// <param name="AProps">Out: the IsDfmNavProp properties of those nodes, in
/// .dfm order. A '(...)' list, a '{...}' blob and an empty '&lt;&gt;' collection are
/// never values; '&lt;' opens a collection whose items carry its name.</param>
/// <remarks>A header's class is its first space-separated word after ':'
/// (`inherited X: TY [2]` gives TY); a header without ':' has the whole rest as
/// its class and an empty name. An `end` (or `end&gt;`) closes the innermost open
/// node. A property outside any node is dropped.</remarks>
procedure ScanDfmNav(const ALines: TArray<string>; out ANodes: TArray<TDfmNavNodeRow>;
  out AProps: TArray<TDfmNavPropRow>);

implementation

uses
  System.StrUtils
  , System.Generics.Collections
  , DRagLint.Core.Encoding
  ;

const
  NAV_PROPS: array[0..7] of string = ('Caption', 'Action', 'Item', 'ItemName', 'ToolbarName', 'BeginGroup',
    'IsMainMenu', 'OldName');
  EVENT_PREFIX = 'On';

/// <summary>Decodes a .dfm string value: quoted runs (doubled quotes inside),
/// #nnn character codes and '+' joins; e.g. 'a'#39'b' gives a'b.</summary>
/// <param name="S">The value text of one line, starting at a quote or '#'.</param>
/// <returns>The decoded text; a malformed #code gives '?'.</returns>
function DecodeDfmString(const S: string): string;
var
  Sb   : TStringBuilder;
  I    : Integer;
  Start: Integer;
begin
  Sb:= TStringBuilder.Create;
  try
    I:= 1;
    while I <= Length(S) do
    begin
      if S[I] = '''' then
      begin
        Inc(I);
        while I <= Length(S) do
        begin
          if S[I] <> '''' then Sb.Append(S[I])
          else if (I < Length(S)) and (S[I + 1] = '''') then
          begin
            Sb.Append('''');
            Inc(I);
          end
          else
            Break;
          Inc(I);
        end;
        Inc(I); // past the closing quote
      end
      else if S[I] = '#' then
      begin
        Inc(I);
        Start:= I;
        while (I <= Length(S)) and CharInSet(S[I], ['0'..'9']) do Inc(I);
        if I > Start then Sb.Append(Char(StrToIntDef(Copy(S, Start, I - Start), Ord('?'))));
      end
      else
        Inc(I); // '+', blanks between joined runs
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

/// <summary>True for a property a navigation reader asks for: Caption, Action,
/// Item, ItemName, ToolbarName, BeginGroup, IsMainMenu, OldName (any case), or an
/// event -- a name whose last dotted segment starts with "On" (any case).</summary>
/// <param name="AName">The property name as written, e.g. Properties.OnChange.</param>
/// <returns>True when ScanDfmNav keeps the property.</returns>
function IsDfmNavProp(const AName: string): Boolean;
begin
  Result:= MatchText(AName, NAV_PROPS) or StartsText(EVENT_PREFIX, Copy(AName, LastDelimiter('.', AName) + 1, MaxInt));
end;

/// <summary>Splits decoded .dfm text into lines exactly as TFile.ReadAllLines
/// does (CR LF, LF or CR end a line; a final line break adds no empty line).</summary>
/// <param name="AText">The decoded text (no BOM).</param>
/// <returns>The lines, without their breaks.</returns>
function DfmNavTextLines(const AText: string): TArray<string>;
var
  L    : TList<string>;
  I    : Integer;
  Start: Integer;
begin
  L:= TList<string>.Create;
  try
    Start:= 1;
    I:= 1;
    while I <= Length(AText) do
    begin
      if CharInSet(AText[I], [#10, #13]) then
      begin
        L.Add(Copy(AText, Start, I - Start));
        if (AText[I] = #13) and (I < Length(AText)) and (AText[I + 1] = #10) then Inc(I);
        Start:= I + 1;
      end;
      Inc(I);
    end;
    if Start <= Length(AText) then L.Add(Copy(AText, Start, MaxInt));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function DfmNavLinesFromBytes(const ARaw: TBytes): TArray<string>;
begin
  Result:= DfmNavTextLines(TEncoding.UTF8.GetString(EnsureUtf8Bytes(ARaw)));
end;

/// Reads one property value starting at ARaw (the text after '='), consuming
/// continuation lines from ALines[AIndex..]. False for a value the tree does not
/// keep: a '(...)' list or a '{...}' binary blob.
function ReadNavValue(const ALines: TArray<string>; var AIndex: Integer; const ARaw: string; out AValue: string): Boolean;
var
  T : string;
  Sb: TStringBuilder;
begin
  AValue:= ARaw;
  if (ARaw <> '') and CharInSet(ARaw[1], ['(', '{']) then
  begin
    // Skip to the closing bracket; the list or blob is never a caption or event.
    T:= ARaw;
    while not (T.EndsWith(')') or T.EndsWith('}')) and (AIndex < Length(ALines)) do
    begin
      T:= Trim(ALines[AIndex]);
      Inc(AIndex);
    end;
    Exit(False);
  end;
  if (ARaw <> '') and not CharInSet(ARaw[1], ['''', '#']) then Exit(True); // identifier, number, set
  // A string: on this line ('abc' + ...) or, when ARaw is empty, on the next ones.
  Sb:= TStringBuilder.Create;
  try
    T:= ARaw;
    if T <> '' then Sb.Append(DecodeDfmString(T));
    while ((T = '') or T.EndsWith('+')) and (AIndex < Length(ALines)) do
    begin
      T:= Trim(ALines[AIndex]);
      if (T = '') or not CharInSet(T[1], ['''', '#']) then Break;
      Inc(AIndex);
      Sb.Append(DecodeDfmString(T));
    end;
    AValue:= Sb.ToString;
  finally
    Sb.Free;
  end;
  Result:= True;
end;

procedure ScanDfmNav(const ALines: TArray<string>; out ANodes: TArray<TDfmNavNodeRow>;
  out AProps: TArray<TDfmNavPropRow>);
var
  Nodes    : TList<TDfmNavNodeRow>;
  Props    : TList<TDfmNavPropRow>;
  Stack    : TStack<Integer>;
  CollStack: TStack<string>;
  I        : Integer;
  T        : string;
  N        : TDfmNavNodeRow;
  Pr       : TDfmNavPropRow;
  P        : Integer;
  PName    : string;
  PVal     : string;
  Value    : string;
  Top      : Integer;
begin
  Nodes    := TList<TDfmNavNodeRow>.Create;
  Props    := TList<TDfmNavPropRow>.Create;
  Stack    := TStack<Integer>.Create;
  CollStack:= TStack<string>.Create;
  try
    I:= 0;
    while I < Length(ALines) do
    begin
      T:= Trim(ALines[I]);
      Inc(I);
      Top:= if Stack.Count > 0 then Stack.Peek else -1;
      if StartsText('object ', T) or StartsText('inherited ', T) or StartsText('inline ', T) then
      begin
        // "object Name: TClass" / "inherited Name: TClass [2]"
        N:= Default(TDfmNavNodeRow);
        N.Ordinal:= Nodes.Count;
        N.Parent := Top;
        N.Line   := I; // I is already past this line: the 1-based line number
        T:= Trim(Copy(T, Pos(' ', T) + 1, MaxInt));
        P:= Pos(':', T);
        if P > 0 then
        begin
          N.Name     := Trim(Copy(T, 1, P - 1));
          N.CompClass:= Trim(Copy(T, P + 1, MaxInt)).Split([' '])[0];
        end
        else
          N.CompClass:= T;
        Nodes.Add(N);
        Stack.Push(N.Ordinal);
      end
      else if SameText(T, 'item') then
      begin
        N:= Default(TDfmNavNodeRow);
        N.Ordinal:= Nodes.Count;
        N.Parent := Top;
        N.Line   := I;
        N.IsItem := True;
        if CollStack.Count > 0 then N.CollProp:= CollStack.Peek;
        Nodes.Add(N);
        Stack.Push(N.Ordinal);
      end
      else if SameText(T, 'end') or StartsText('end>', T) then
      begin
        if Stack.Count > 0 then Stack.Pop;
        if StartsText('end>', T) and (CollStack.Count > 0) then CollStack.Pop;
      end
      else
      begin
        P:= Pos('=', T);
        if P = 0 then Continue;
        PName:= Trim(Copy(T, 1, P - 1));
        PVal := Trim(Copy(T, P + 1, MaxInt));
        if PVal = '<' then CollStack.Push(PName)
        // Distinct out variable: an out string is cleared on entry, and ARaw is a
        // const reference -- passing PVal twice reads back ''.
        else if (PVal <> '<>') and ReadNavValue(ALines, I, PVal, Value) and (Top >= 0) and IsDfmNavProp(PName) then
        begin
          Pr.Node := Top;
          Pr.Name := PName;
          Pr.Value:= Value;
          Props.Add(Pr);
        end;
      end;
    end; // while
    ANodes:= Nodes.ToArray;
    AProps:= Props.ToArray;
  finally
    CollStack.Free;
    Stack.Free;
    Props.Free;
    Nodes.Free;
  end;
end;

end.
