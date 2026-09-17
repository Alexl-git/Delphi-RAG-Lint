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
  System.SysUtils
  , System.Generics.Collections
  , ConvRules.BlockFile
  ;

type
  /// <summary>The outcome of examining a set of files.</summary>
  /// <remarks>
  /// Names are normalised and de-duplicated case-insensitively. Missing holds
  /// used names that match no leaf of the From property tree -- expected to be empty,
  /// and evidence of an indexer gap when it is not.
  /// Loose holds names seen in a .pas as '.Name' on a receiver that is NOT a known
  /// instance of the From class -- reported, never marked used. It exists so the
  /// receiver filter cannot silently DISCARD a real use: a property touched through a
  /// local alias or a loop variable lands here rather than vanishing. Empty whenever
  /// no receiver names are known, because the filter is then off and every hit is in
  /// Names (see ScanPasText's receiver-aware overload).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.MainForm.TConvRulesForm.LoadFormFiles (ConvRules.MainForm.pas), ConvRules.Usage.ComputeUsage (ConvRules.Usage.pas), declaration (ConvRules.Usage.pas)</para>
  /// <para>Used in units: ConvRules.MainForm, ConvRules.Usage</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TUsageSet = record
    Names   : TArray<string>;
    Loose   : TArray<string>;
    Missing : TArray<string>;
    DfmCount: Integer       ;
    PasCount: Integer       ;
  end;

  /// <summary>One entry of a unit's own `uses` clauses, with the clause it was
  /// written in.</summary>
  /// <remarks>A unit named in BOTH clauses appears ONCE, carrying the clause it
  /// appeared in FIRST -- the same first-wins rule the flat scan has always used,
  /// and the same answer the engine's `uses-report.first_section` gives. Do not
  /// read Section as "the only clause this unit appears in".</remarks>
  TUsedUnitRef = record
    UnitName: string;
    Section : string; // 'interface' | 'implementation'
  end;

  /// <summary>PURE: parses a DFM block header line into the class it declares.</summary>
  /// <param name="ALine">One .dfm line, e.g. 'object btnA: TabcToggleBtn'. Accepts the
  /// 'object', 'inherited' and 'inline' keywords real DFMs use for forms and frames.</param>
  /// <param name="AClass">Receives the bare class name, with any trailing collection
  /// index ('[0]') stripped; '' when the line is not a block header.</param>
  /// <returns>True when ALine is a block header declaring a class.</returns>
  /// <remarks>
  /// Exported so ConvRules.FormTypes can harvest the types on a form through
  /// the SAME parser this unit scans properties with. A second object-header parser
  /// would be free to disagree with this one about what a form contains.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Called from: ConvRules.FormTypes.ScanDfmTypes (ConvRules.FormTypes.pas), ConvRules.Usage.ScanDfmText (ConvRules.Usage.pas)</para>
  /// <para>Calls: ConvRules.BlockFile.FirstToken, Copy, Pos, SameText, Trim</para>
  /// <para>Returns: False; AClass &lt;&gt; ''</para>
  /// <para>Mutates: AClass (out)</para>
  /// <seealso cref="ConvRules.BlockFile.FirstToken"/>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
function ParseBlockHeader(const ALine: string; out AClass: string): Boolean; overload;

/// <summary>PURE: as ParseBlockHeader above, and additionally yields the INSTANCE name
/// the block declares ('object btnA: TabcToggleBtn' -> AClass 'TabcToggleBtn',
/// AInstance 'btnA').</summary>
/// <param name="ALine">One .dfm line.</param>
/// <param name="AClass">Receives the bare class name; '' when the line is not a header.</param>
/// <param name="AInstance">Receives the instance name, or '' for an anonymous block
/// ('object : TFoo', and the collection-item form where the name is an index). Never
/// carries the '[0]' suffix, which belongs to the class half of the line.</param>
/// <returns>True when ALine is a block header declaring a class.</returns>
/// <remarks>This is the ONE object-header parser; the two-argument overload above
/// delegates to it. Splitting them would let two parsers disagree about what a form
/// contains, which is the reason ParseBlockHeader was exported in the first place.</remarks>
function ParseBlockHeader(const ALine: string; out AClass, AInstance: string): Boolean; overload;

/// <summary>PURE: the INSTANCE names declared as AFromClass in a .dfm text --
/// ['btnEWAcAQL', 'btnEWAcQL', ...] for a form holding those TabcToggleBtn controls.</summary>
/// <param name="AText">The whole .dfm as text. A binary .dfm yields nothing.</param>
/// <param name="AFromClass">Bare class name, matched case-insensitively.</param>
/// <returns>Distinct instance names, in first-seen order.</returns>
/// <remarks>These are the receivers a .pas scan may trust: 'btnEWAcAQL.Popup' is a use
/// of TabcToggleBtn.Popup, while 'F7Actions.Popup' is a use of something else entirely.
/// Nested blocks are included -- a control is an instance of its class wherever on the
/// form it sits.</remarks>
function ScanDfmInstanceNames(const AText, AFromClass: string): TArray<string>;

/// <summary>PURE: the property names assigned to instances of AFromClass in a .dfm text.</summary>
/// <param name="AText">The whole .dfm as text. A binary .dfm simply yields nothing.</param>
/// <param name="AFromClass">Bare class name, matched case-insensitively (e.g. 'TabcToggleBtn').</param>
/// <returns>Distinct names. A dotted assignment 'A.B' contributes BOTH 'A.B' and 'A',
/// because the root property is genuinely used and a grid row for 'A' should match.</returns>
/// <remarks>
/// Depth-tracked line scan, not a parser. Assignments count only at the
/// immediate level of a matching block: a nested component belongs to itself, not to the
/// From class, though the scan still descends to find further instances. Values opening
/// a '{' blob, a '<' item list or a '(' list are skipped to their terminator so their
/// contents are never mistaken for assignments.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Usage.ComputeUsage (ConvRules.Usage.pas)</para>
/// <para>Calls: ConvRules.BlockFile.FirstToken, ConvRules.BlockFile.SplitRawLines, ConvRules.Usage.IsPropName, ConvRules.Usage.ParseBlockHeader, ConvRules.Usage.ScanDfmText.AddName, ConvRules.Usage.StripQuoted, Copy, Pos, SameText, Trim</para>
/// <para>Returns: Names.ToArray</para>
/// <para>Complexity: 15 (cyclomatic, outer body), 80 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockFile.FirstToken"/>
/// <seealso cref="ConvRules.BlockFile.SplitRawLines"/>
/// <seealso cref="ConvRules.Usage.IsPropName"/>
/// <seealso cref="ConvRules.Usage.ParseBlockHeader"/>
/// <seealso cref="ConvRules.Usage.ScanDfmText.AddName"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ScanDfmText(const AText, AFromClass: string): TArray<string>;

/// <summary>PURE: the names worth searching a .pas for, derived from the From tree:
/// every distinct full path plus every distinct last segment.</summary>
/// <param name="AFromPaths"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
/// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: NameSet.ToArray.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Usage.ComputeUsage (ConvRules.Usage.pas)</para>
/// <para>Calls: ConvRules.Usage.LastSegment, ConvRules.Usage.TNameSet.Add, ConvRules.Usage.TNameSet.Create, ConvRules.Usage.TNameSet.ToArray</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Usage.LastSegment"/>
/// <seealso cref="ConvRules.Usage.TNameSet.Add"/>
/// <seealso cref="ConvRules.Usage.TNameSet.Create"/>
/// <seealso cref="ConvRules.Usage.TNameSet.ToArray"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CandidatesFor(const AFromPaths: TArray<string>): TArray<string>;

/// <summary>PURE: which candidates appear in a .pas text as '.Name' followed by a
/// non-identifier character.</summary>
/// <param name="AText"><!-- drag-lint:auto type -->const string</param>
/// <param name="ACandidates"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
/// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: Hits.ToArray.</returns>
/// <remarks>
/// DELIBERATELY LOOSE (the user's ruling): it does not check which object the
/// member belongs to. The cost is over-reporting -- another component's '.Caption' marks
/// Caption used; the gain is that typed locals and any dotted access are caught. A
/// 'with X do Caption := ...' has no dot and is therefore NOT seen.
/// Comments and string literals ARE excluded, which the ruling's wording also covered
/// until 2026-09-15: a commented-out line is not a use under any reading, and one was
/// measured contributing a green mark on VARINSP. Receiver-blindness -- the part of the
/// ruling that was a real trade-off -- survives here unchanged. Prefer the receiver-aware
/// overload below when the instance names are known; ComputeUsage now does.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Usage.ComputeUsage (ConvRules.Usage.pas)</para>
/// <para>Calls: ConvRules.Usage.HarvestDotTokens, ConvRules.Usage.TNameSet.Add, ConvRules.Usage.TNameSet.Contains, ConvRules.Usage.TNameSet.Create, ConvRules.Usage.TNameSet.ToArray</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Usage.HarvestDotTokens"/>
/// <seealso cref="ConvRules.Usage.TNameSet.Add"/>
/// <seealso cref="ConvRules.Usage.TNameSet.Contains"/>
/// <seealso cref="ConvRules.Usage.TNameSet.Create"/>
/// <seealso cref="ConvRules.Usage.TNameSet.ToArray"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ScanPasText(const AText: string; const ACandidates: TArray<string>): TArray<string>; overload;

/// <summary>PURE: as ScanPasText above, but a hit counts only when the RECEIVER of the
/// '.Name' is a known instance of the From class. Names rejected for their receiver are
/// returned in ALooseNames rather than discarded.</summary>
/// <param name="AText">The .pas text.</param>
/// <param name="ACandidates">Names worth looking for (see CandidatesFor).</param>
/// <param name="AReceivers">Instance names of the From class (see ScanDfmInstanceNames),
/// plus the From class name itself so a cast 'TabcToggleBtn(Sender).Popup' is credited.
/// EMPTY TURNS THE FILTER OFF: with no idea what the instances are called, every hit is
/// confirmed and the result is exactly the loose overload's. That is the honest
/// degradation -- examining .pas files with no .dfm cannot do better.</param>
/// <param name="ALooseNames">Receives candidates seen on an UNKNOWN receiver. Always
/// empty when AReceivers is empty.</param>
/// <returns>Candidates confirmed on a known receiver.</returns>
/// <remarks>
/// WHY THIS IS NOT THE OLD LOOSE RULE. Measured on ORM3\CLIENT\VARINSP: 'Popup' was
/// marked used on TabcToggleBtn although no TabcToggleBtn in that form sets it. The two
/// hits were 'F7Actions.Popup(400,300)' -- a TdxBarPopupMenu, a different class entirely
/// -- and a COMMENTED-OUT line. Both are now rejected: the first for its receiver, the
/// second because comments and string literals are skipped.
/// Recognised receiver forms are the identifier immediately before the dot ('btnA.X'),
/// the last link of a chain ('Self.btnA.X'), and the callee of a completed call or cast
/// ('TabcToggleBtn(Sender).X'). A 'with btnA do X' still has no dot and is still not
/// seen, unchanged and by design.
/// </remarks>
function ScanPasText(const AText: string; const ACandidates, AReceivers: TArray<string>; out ALooseNames: TArray<string>): TArray<string>; overload;

/// <summary>PURE: every unit named in a .pas text's uses clauses -- BOTH the interface
/// and the implementation one, because a unit used only in the implementation still has
/// to be converted.</summary>
/// <param name="APasText">The whole .pas (or .dpr) as text.</param>
/// <returns>Unit names exactly as written, de-duplicated case-insensitively, in
/// first-seen order. A dotted name stays ONE name: 'Winapi.Windows' is a single unit,
/// never 'Winapi' plus 'Windows'.</returns>
/// <remarks>
/// A clause runs to its terminating ';', not to end of line, so a multi-line
/// clause is harvested whole; the .dpr "Foo in 'Foo.pas'" form contributes 'Foo'.
/// A 'uses' inside a '//', a brace or a '(* *)' comment, or inside a string literal, is
/// not a clause -- and neither is an identifier that merely contains it ('MyUses',
/// 'UsesFoo') nor a qualified member ('X.Uses').
/// KNOWN LIMITATIONS, both deliberate and both pinned by the test suite: (1) brace
/// comments are NOT treated as nesting -- the first closing brace ends the comment,
/// which is Delphi's own rule, so a 'uses' following an inner closing brace IS
/// harvested; (2) no conditional compilation is evaluated -- a $IFDEF arm the compiler
/// would discard still contributes its units. For a candidate work list, over-reporting
/// is the safe direction: nothing here creates a rule, and the user deletes rows.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.LoadFormFiles (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.Usage.IsIdentCh, ConvRules.Usage.IsIdentStartCh, ConvRules.Usage.ScanUsesClauses.HarvestClause, ConvRules.Usage.SkipNonCode, ConvRules.Usage.TNameSet.Create, ConvRules.Usage.TNameSet.ToArray, Copy, SameText, Trim</para>
/// <para>Returns: NameSet.ToArray</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Usage.IsIdentCh"/>
/// <seealso cref="ConvRules.Usage.IsIdentStartCh"/>
/// <seealso cref="ConvRules.Usage.ScanUsesClauses.HarvestClause"/>
/// <seealso cref="ConvRules.Usage.SkipNonCode"/>
/// <seealso cref="ConvRules.Usage.TNameSet.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ScanUsesClauses(const APasText: string): TArray<string>;

/// <summary>PURE: as ScanUsesClauses, but each unit carries the clause it was
/// written in -- 'interface' before the `implementation` keyword, 'implementation'
/// after it.</summary>
/// <param name="APasText">Whole .pas text. Comment and string runs are skipped by
/// the same SkipNonCode the flat scan uses, so a `uses` inside a comment is not a
/// clause and 'Foo in ''Foo.pas''' still reduces to 'Foo'.</param>
/// <returns>Source order, de-duplicated case-insensitively, FIRST occurrence
/// winning -- so a unit in both clauses is reported once, as 'interface'.</returns>
/// <remarks>This is the scanner; <see cref="ScanUsesClauses"/> is a flatten over
/// it. Deliberately NOT the engine's `uses-report`: that verb reads the INDEX, and
/// a unit the index does not cover (a browsed file, or a form like VARINSP that no
/// .dproj lists) comes back as zero rows with exit 0 -- an empty list that reads
/// as "uses nothing". Reading the text answers for any file the editor can open.
/// A `uses` inside an inactive {$IFDEF} branch IS reported: this is a text scan,
/// not a preprocessor.</remarks>
function ScanUsesClausesSectioned(const APasText: string): TArray<TUsedUnitRef>;

/// <summary>PURE: every class/interface/record/object declared at the top level of a
/// .pas file.</summary>
/// <param name="APasText">The whole .pas text.</param>
/// <returns>Type names exactly as written, de-duplicated case-insensitively, in
/// first-seen order. Only top-level declarations are harvested; nested types are
/// not descended.</returns>
/// <remarks>
/// Scans for the pattern: identifier followed by '=' followed by one of
/// (class, interface, record, object). Comments and strings are skipped, so a
/// 'class' inside a comment or string is not harvested. A generic class
/// 'TFoo&lt;T&gt; = class' contributes 'TFoo', not 'TFoo&lt;T&gt;'.
/// </remarks>
function ScanClassesDeclared(const APasText: string): TArray<string>;

/// <summary>PURE: union of several scans, de-duplicated case-insensitively.</summary>
/// <param name="AParts"><!-- drag-lint:auto type -->const TArray&lt;TArray&lt;string&gt;&gt;</param>
/// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: NameSet.ToArray.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.LoadFormFiles (ConvRules.MainForm.pas), ConvRules.Usage.ComputeUsage (ConvRules.Usage.pas)</para>
/// <para>Calls: ConvRules.Usage.TNameSet.Add, ConvRules.Usage.TNameSet.Create, ConvRules.Usage.TNameSet.ToArray</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Usage.TNameSet.Add"/>
/// <seealso cref="ConvRules.Usage.TNameSet.Create"/>
/// <seealso cref="ConvRules.Usage.TNameSet.ToArray"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MergeUsage(const AParts: TArray<TArray<string>>): TArray<string>;

/// <summary>PURE: is a grid row's From path used? True when the path itself, or its last
/// dotted segment, is in AUsed (case-insensitive).</summary>
/// <param name="AFromPath"><!-- drag-lint:auto type -->const string</param>
/// <param name="AUsed"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: HasName(AUsed, AFromPath) or
/// HasName(AUsed, LastSegment(AFromPath)).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.GridDrawCell (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.Usage.HasName, ConvRules.Usage.LastSegment</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Usage.HasName"/>
/// <seealso cref="ConvRules.Usage.LastSegment"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsRowUsed(const AFromPath: string; const AUsed: TArray<string>): Boolean;

/// <summary>PURE: examine a set of already-read file texts and report what the From class
/// actually uses.</summary>
/// <param name="ADfmTexts">Contents of the selected .dfm files.</param>
/// <param name="APasTexts">Contents of the selected .pas files.</param>
/// <param name="AFromClass">Bare From class name, e.g. 'TabcToggleBtn'.</param>
/// <param name="AFromPaths">Every leaf path of the From property tree, used both to derive
/// PAS candidates and to decide which used names have no row.</param>
/// <returns><!-- drag-lint:auto -->TUsageSet -- Observed: Default(TUsageSet).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.LoadFormFiles (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.Usage.CandidatesFor, ConvRules.Usage.LastSegment, ConvRules.Usage.MergeUsage, ConvRules.Usage.ScanDfmText, ConvRules.Usage.ScanPasText, Default, SameText</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Usage.CandidatesFor"/>
/// <seealso cref="ConvRules.Usage.LastSegment"/>
/// <seealso cref="ConvRules.Usage.MergeUsage"/>
/// <seealso cref="ConvRules.Usage.ScanDfmText"/>
/// <seealso cref="ConvRules.Usage.ScanPasText"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ComputeUsage(const ADfmTexts, APasTexts: TArray<string>; const AFromClass: string; const AFromPaths: TArray<string>): TUsageSet;

implementation

{ A valid (possibly dotted) DFM property name: identifier chars and dots only, starting
  with a letter or underscore. This is what keeps a continuation line of a quoted string
  -- which may well contain '=' -- from being read as an assignment. }
function IsPropName(const S: string): Boolean;
var
  i: Integer;
begin
  Result:= False;
  if S = '' then
    Exit;
  if not (CharInSet(S[1], ['A'..'Z', 'a'..'z', '_'])) then
    Exit;
  for i:= 2 to Length(S) do
    if not CharInSet(S[i], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
      Exit;
  Result:= True;
end; // function

{ 'object btnA: TabcToggleBtn' -> AName='btnA', AClass='TabcToggleBtn'. Also accepts the
  'inherited' and 'inline' block keywords real DFMs use for inherited forms and frames. }
function ParseBlockHeader(const ALine: string; out AClass: string): Boolean;
var
  Ignored: string;
begin
  Result:= ParseBlockHeader(ALine, AClass, Ignored);
end; // function

function ParseBlockHeader(const ALine: string; out AClass, AInstance: string): Boolean;
var
  S  : string ;
  Tok: string ;
  p  : Integer;
begin
  Result   := False;
  AClass   := '';
  AInstance:= '';
  S  := Trim      (ALine);
  Tok:= FirstToken(S    );
  if not (SameText(Tok, 'object') or SameText(Tok, 'inherited') or SameText(Tok, 'inline')) then
    Exit;
  p:= Pos(':', S);
  if p = 0 then Exit; // 'inherited Frame1' with no type
  // Between the keyword and the ':' is the instance name. It is absent on an
  // anonymous block ('object : TFoo'), which Trim then yields as ''.
  if p > Length(Tok) then
    AInstance:= Trim(Copy(S, Length(Tok) + 1, p - Length(Tok) - 1));
  AClass:= Trim(Copy(S, p + 1, MaxInt));
  // a trailing '[0]' index appears on inherited collection items
  p:= Pos('[', AClass);
  if p > 0 then
    AClass:= Trim(Copy(AClass, 1, p - 1));
  Result:= AClass <> '';
end; // function

{ Removes the CONTENT of every single-quoted DFM string literal from ALine (the quotes
  too), collapsing the Pascal doubled-apostrophe escaped-quote convention correctly, so
  a literal's own '>', ')' or blob-closing brace can never be mistaken for a block
  terminator by a caller that then searches the result for one. A literal left open at
  end of line strips to the end of the line -- DFM values are never split mid-literal
  without a fresh opening quote on the continuation, so this is a safe simplification,
  not a real string-continuation parser. }
function StripQuoted(const ALine: string): string;
var
  i      : Integer;
  InQuote: Boolean;
begin
  Result := '';
  InQuote:= False;
  i      := 1;
  while i <= Length(ALine) do
  begin
    if not InQuote then
    begin
      if ALine[i] = '''' then
        InQuote:= True
      else
        Result:= Result + ALine[i];
    end
    else
    begin
      if ALine[i] = '''' then
      begin
        if (i < Length(ALine)) and (ALine[i + 1] = '''') then
          Inc(i) // '' inside a literal: an escaped quote, stay inside
        else
          InQuote:= False; // this quote closes the literal
      end;
    end;
    Inc(i);
  end; // while
end; // function

function ScanDfmText(const AText, AFromClass: string): TArray<string>;
var
  Lines : TArray<TRawLine>;
  Stack : TList<Boolean>  ; // one entry per open block: is it a From-class block?
  Names : TList<string>   ;
  i     : Integer         ;
  ep    : Integer         ;
  Cur   : string          ;
  Nm    : string          ;
  Val   : string          ;
  Cls   : string          ;
  SkipTo: string          ; // '' = not skipping; else the terminator to look for

  procedure AddName(const AName: string);
  var
    X     : string ;
    Root  : string ;
    DotPos: Integer;
  begin
    for X in Names do
      if SameText(X, AName) then
        Exit;
    Names.Add(AName);
    DotPos:= Pos('.', AName);
    if DotPos > 1 then
    begin
      Root:= Copy(AName, 1, DotPos - 1);
      for X in Names do
        if SameText(X, Root) then
          Exit;
      Names.Add(Root);
    end;
  end; // procedure

begin
  Lines:= SplitRawLines(AText);
  Stack:= TList<Boolean>.Create;
  Names:= TList<string>.Create;
  try
    SkipTo:= '';
    for i:= 0 to High(Lines) do
    begin
      Cur:= Trim(Lines[i].Text);
      if Cur = '' then
        Continue;

      if SkipTo <> '' then
      begin
        // A terminator char sitting inside a quoted item value (e.g. Caption = 'Y > Z')
        // must not be mistaken for the container's own terminator -- search stripped.
        if Pos(SkipTo, StripQuoted(Cur)) > 0 then
          SkipTo:= '';
        Continue;
      end;

      if ParseBlockHeader(Cur, Cls) then
      begin
        Stack.Add(SameText(Cls, AFromClass));
        Continue;
      end;

      if SameText(FirstToken(Cur), 'end') then
      begin
        if Stack.Count > 0 then
          Stack.Delete(Stack.Count - 1);
        Continue;
      end;

      if (Stack.Count = 0) or (not Stack[Stack.Count - 1]) then
        Continue;

      ep:= Pos('=', Cur);
      if ep = 0 then
        Continue;
      Nm:= Trim(Copy(Cur, 1, ep - 1));
      if not IsPropName(Nm) then
        Continue;
      AddName(Nm);

      // Stripped so a same-line value that merely CONTAINS a quoted opener character
      // (unlikely, but the same robustness rule applies here as to the terminator
      // search above) is judged on what is actually outside any quoted literal.
      Val:= StripQuoted(Trim(Copy(Cur, ep + 1, MaxInt)));
      if Val = '{' then
        SkipTo:= '}'
      else if Val = '<' then
        SkipTo:= '>'
      else if Val = '(' then
        SkipTo:= ')';
    end; // for
    Result:= Names.ToArray;
  finally
    Names.Free;
    Stack.Free;
  end; // try
end; // begin

{ The last dotted segment of APath, or APath itself when it has none -- 'Font.Size' ->
  'Size', 'Caption' -> 'Caption'. }
function LastSegment(const APath: string): string;
var
  i: Integer;
begin
  Result:= APath;
  for i:= Length(APath) downto 1 do
    if APath[i] = '.' then
      Exit(Copy(APath, i + 1, MaxInt));
end;

{ Case-insensitive membership over a bare-name array. }
function HasName(const A: TArray<string>; const S: string): Boolean;
var
  X: string;
begin
  for X in A do
    if SameText(X, S) then
      Exit(True);
  Result:= False;
end;

type { Case-insensitive, insertion-ordered set of names. Review fix (Important 3): the
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
      FOrder: TList<string>            ;
    public
      constructor Create;
      destructor Destroy; override;
      procedure Add(const AName: string);
      function Contains(const AName: string): Boolean;
      function ToArray: TArray<string>               ;
  end;

constructor TNameSet.Create;
begin
  inherited Create;
  FSeen:= TDictionary<string, Byte>.Create;
  FOrder:= TList<string>.Create;
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
  Key:= LowerCase(AName);
  if not FSeen.ContainsKey(Key) then
  begin
    FSeen.Add(Key, 0);
    FOrder.Add(AName);
  end;
end;

function TNameSet.Contains(const AName: string): Boolean;
begin
  Result:= FSeen.ContainsKey(LowerCase(AName));
end;

function TNameSet.ToArray: TArray<string>;
begin
  Result:= FOrder.ToArray;
end;

function IsIdentStartCh(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentCh(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

{ If a non-code run starts at AIdx -- a '//' line comment, a brace comment, a '(* *)'
  comment, or a single-quoted string literal -- advances AIdx past it and returns True;
  otherwise leaves AIdx alone and returns False. Brace comments do not nest (Delphi's
  own rule): the first closing brace ends the comment. An unterminated run consumes to
  end of text, which is the only sane thing to do with a truncated file. }
function SkipNonCode(const AText: string; var AIdx: Integer): Boolean;
var
  N: Integer;
begin
  Result:= True;
  N:= Length(AText);
  if (AIdx < N) and (AText[AIdx] = '/') and (AText[AIdx + 1] = '/') then
  begin
    while (AIdx <= N) and (AText[AIdx] <> #13) and (AText[AIdx] <> #10) do
      Inc(AIdx);
    Exit;
  end;
  if AText[AIdx] = '{' then
  begin
    Inc(AIdx);
    while (AIdx <= N) and (AText[AIdx] <> '}') do
      Inc(AIdx);
    if AIdx <= N then
      Inc(AIdx);
    Exit;
  end;
  if (AIdx < N) and (AText[AIdx] = '(') and (AText[AIdx + 1] = '*') then
  begin
    Inc(AIdx, 2);
    while (AIdx < N) and not ((AText[AIdx] = '*') and (AText[AIdx + 1] = ')')) do
      Inc(AIdx);
    if AIdx < N then
      Inc(AIdx, 2)
    else
      AIdx:= N + 1;
    Exit;
  end;
  if AText[AIdx] = '''' then
  begin
    Inc(AIdx);
    while AIdx <= N do
    begin
      if AText[AIdx] = '''' then
      begin
        if (AIdx < N) and (AText[AIdx + 1] = '''') then
          Inc(AIdx) // '' inside a literal: an escaped quote
        else
        begin
          Inc(AIdx); // this quote closes the literal
          Exit;
        end;
      end;
      Inc(AIdx);
    end; // while
    Exit;
  end; // if
  Result:= False;
end; // function

function ScanUsesClausesSectioned(const APasText: string): TArray<TUsedUnitRef>;
var
  NameSet: TNameSet           ;
  Refs   : TArray<TUsedUnitRef>;
  i      : Integer            ;
  j      : Integer            ;
  N      : Integer            ;
  Tok    : string             ;
  PrevSig: Char               ; // last significant code character; guards 'X.Uses'
  InImpl : Boolean            ; // past the `implementation` keyword

  { Reads the comma-separated clause starting at AIdx up to the terminating ';' (or end
    of text) and adds each entry's leading dotted identifier. Comment and string runs
    INSIDE the clause are skipped, which is what reduces "Foo in 'Foo.pas'" to 'Foo'. }
  procedure HarvestClause(var AIdx: Integer);
  var
    Entry: string;

    procedure FlushEntry;
    var
      k : Integer;
      Nm: string ;
    begin
      Entry:= Trim(Entry);
      Nm:= '';
      if (Entry <> '') and IsIdentStartCh(Entry[1]) then
      begin
        k:= 1;
        while (k <= Length(Entry)) and (IsIdentCh(Entry[k]) or (Entry[k] = '.')) do
          Inc(k);
        Nm:= Copy(Entry, 1, k - 1);
        while (Nm <> '') and (Nm[Length(Nm)] = '.') do
          SetLength(Nm, Length(Nm) - 1);
      end;
      { First occurrence wins, so a unit named in BOTH clauses keeps the clause it
        appeared in first. Contains-then-Add rather than Add alone: TNameSet.Add is
        silent on a duplicate, which would otherwise append a second Refs row
        carrying the LATER section. }
      if (Nm <> '') and not NameSet.Contains(Nm) then
      begin
        NameSet.Add(Nm);
        var R: TUsedUnitRef;
        R.UnitName:= Nm;
        if InImpl then
          R.Section:= 'implementation'
        else
          R.Section:= 'interface';
        Refs:= Refs + [R];
      end;
      Entry:= '';
    end; // procedure

  begin
    Entry:= '';
    while AIdx <= N do
    begin
      if SkipNonCode(APasText, AIdx) then
      begin
        Entry:= Entry + ' '; // a skipped run still separates tokens
        Continue;
      end;
      if APasText[AIdx] = ';' then
      begin
        Inc(AIdx);
        Break;
      end;
      if APasText[AIdx] = ',' then
      begin
        FlushEntry;
        Inc(AIdx);
        Continue;
      end;
      Entry:= Entry + APasText[AIdx];
      Inc(AIdx);
    end; // while
    FlushEntry; // the entry before ';' (or before end of text)
  end; // begin

begin
  NameSet:= TNameSet.Create;
  try
    Refs   := nil;
    N      := Length(APasText);
    PrevSig:= #0;
    InImpl := False;
    i      := 1;
    while i <= N do
    begin
      if SkipNonCode(APasText, i) then Continue; // PrevSig deliberately unchanged
      if IsIdentStartCh(APasText[i]) then
      begin
        j:= i;
        while (j <= N) and IsIdentCh(APasText[j]) do
          Inc(j);
        Tok:= Copy(APasText, i, j - i);
        i:= j;
        { The section switch. Guarded by PrevSig for the same reason `uses` is: an
          `X.Implementation` member access is not the keyword. A unit has exactly one
          `implementation`, so this latches and never flips back. }
        if SameText(Tok, 'implementation') and (PrevSig <> '.') then
          InImpl:= True;
        // Whole-token match, so 'MyUses'/'UsesFoo' never qualify; PrevSig rules out a
        // qualified member access like 'X.Uses'.
        if SameText(Tok, 'uses') and (PrevSig <> '.') then
          HarvestClause(i);
        PrevSig:= 'x'; // an identifier: significant, and definitely not a '.'
        Continue;
      end; // if
      if APasText[i] > ' ' then
        PrevSig:= APasText[i];
      Inc(i);
    end; // while
    Result:= Refs;
  finally
    NameSet.Free;
  end; // try
end; // begin

function ScanUsesClauses(const APasText: string): TArray<string>;
var
  R: TUsedUnitRef;
begin
  { A flatten over the sectioned scan -- one scanner, two consumers. TNameSet is
    insertion-ordered with first-wins dedup, so this reproduces the order and the
    contents this function returned before the section was tracked. }
  Result:= nil;
  for R in ScanUsesClausesSectioned(APasText) do
    Result:= Result + [R.UnitName];
end; // function

function ScanClassesDeclared(const APasText: string): TArray<string>;
var
  NameSet: TNameSet;
  i      : Integer ;
  j      : Integer ;
  N      : Integer ;
  Tok    : string  ;
  PrevSig: Char    ; // last significant code character; guards X.ClassName
  Ident  : string  ;
begin
  NameSet:= TNameSet.Create;
  try
    N      := Length(APasText);
    PrevSig:= #0;
    i      := 1;
    while i <= N do
    begin
      if SkipNonCode(APasText, i) then
      begin
        PrevSig:= #0; // a non-code run resets the significant char
        Continue;
      end;
      if IsIdentStartCh(APasText[i]) then
      begin
        j:= i;
        while (j <= N) and IsIdentCh(APasText[j]) do
          Inc(j);
        Tok:= Copy(APasText, i, j - i);
        i:= j;

        { Bare token 'class', 'interface', 'record', 'object' (not 'Foo.class').
          After an identifier (PrevSig='x') followed by '=', a type keyword means
          the identifier is a type declaration. }
        if (PrevSig = '=') and (SameText(Tok, 'class') or SameText(Tok, 'interface')
          or SameText(Tok, 'record') or SameText(Tok, 'object')) then
        begin
          { Backtrack: find the identifier before the '='. }
          j:= i - 1;
          while (j >= 1) and (APasText[j] <= ' ') do
            Dec(j);
          if (j >= 1) and (APasText[j] = '=') then
          begin
            Dec(j);
            while (j >= 1) and (APasText[j] <= ' ') do
              Dec(j);
            if (j >= 1) and IsIdentCh(APasText[j]) then
            begin
              { j now points at the last char of the identifier. Backtrack to start. }
              var k: Integer:= j;
              while (k >= 1) and IsIdentCh(APasText[k]) do
                Dec(k);
              Ident:= Copy(APasText, k + 1, j - k);
              { Strip generic parameters: 'TFoo<T>' -> 'TFoo' }
              j:= Pos('<', Ident);
              if j > 0 then
                SetLength(Ident, j - 1);
              if (Ident <> '') and IsIdentStartCh(Ident[1]) then
                NameSet.Add(Ident);
            end;
          end;
          PrevSig:= 'x'; // after processing a keyword
          Continue;
        end;

        PrevSig:= 'x'; // an identifier: significant, and definitely not a '.'
        Continue;
      end;
      if APasText[i] > ' ' then
        PrevSig:= APasText[i];
      Inc(i);
    end; // while
    Result:= NameSet.ToArray;
  finally
    NameSet.Free;
  end;
end; // function

function ScanDfmInstanceNames(const AText, AFromClass: string): TArray<string>;
var
  Lines  : TArray<TRawLine>;
  NameSet: TNameSet        ;
  i      : Integer         ;
  Cur    : string          ;
  Inst   : string          ;
begin
  Lines  := SplitRawLines(AText);
  NameSet:= TNameSet.Create;
  try
    for i:= 0 to High(Lines) do
      if ParseBlockHeader(Lines[i].Text, Cur, Inst) and SameText(Cur, AFromClass) and (Inst <> '') then
        NameSet.Add(Inst);
    Result:= NameSet.ToArray;
  finally
    NameSet.Free;
  end; // try
end; // function

function CandidatesFor(const AFromPaths: TArray<string>): TArray<string>;
var
  NameSet: TNameSet;
  p      : string  ;
  Seg    : string  ;
begin
  NameSet:= TNameSet.Create;
  try
    for p in AFromPaths do
    begin
      if p <> '' then
        NameSet.Add(p);
      Seg:= LastSegment(p);
      if Seg <> '' then
        NameSet.Add(Seg);
    end;
    Result:= NameSet.ToArray;
  finally
    NameSet.Free;
  end; // try
end; // function

{ Review fix (Important 3): every distinct '.Identifier' token in AText, harvested in a
  SINGLE left-to-right pass -- each '.' is followed by the run of identifier characters
  after it, which becomes one token (an empty run, e.g. a '.' as the last character of
  the text, safely yields nothing). This replaces ScanPasText's old approach of one Pos
  scan of the WHOLE text per candidate (O(candidates x textlength), ~7810 candidates x a
  several-hundred-KB unit, per file) with one O(textlength) harvest plus an O(candidates)
  membership filter. It is exactly equivalent for the loose-match rule: a candidate is
  used iff it appears as a '.Identifier' token followed by a non-identifier character,
  which is precisely what this yields.

  Comments and string literals ARE excluded (2026-09-15). They were not until the VARINSP
  measurement found 'Popup' marked used partly on the strength of a COMMENTED-OUT line.
  Nothing is lost: under no reading of "which properties does this conversion use" is a
  commented-out line or the inside of a string a use. Receiver-blindness -- the OTHER half
  of that defect, and the deliberate part -- is unchanged here and is addressed by
  ScanPasText's receiver-aware overload instead. }
function HarvestDotTokens(const AText: string): TNameSet;
var
  i: Integer;
  j: Integer;
begin
  Result:= TNameSet.Create;
  i:= 1;
  while i <= Length(AText) do
  begin
    if SkipNonCode(AText, i) then
      Continue;
    if AText[i] = '.' then
    begin
      j:= i + 1;
      while (j <= Length(AText)) and CharInSet(AText[j], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(j);
      if j > i + 1 then
        Result.Add(Copy(AText, i + 1, j - i - 1));
      i:= j;
    end
    else
      Inc(i);
  end; // while
end; // function

function ScanPasText(const AText: string; const ACandidates: TArray<string>): TArray<string>;
var
  Tokens: TNameSet;
  Hits  : TNameSet;
  C     : string  ;
begin
  Tokens:= HarvestDotTokens(AText);
  Hits:= TNameSet.Create;
  try
    for C in ACandidates do
      if Tokens.Contains(C) then
        Hits.Add(C);
    Result:= Hits.ToArray;
  finally
    Hits.Free;
    Tokens.Free;
  end;
end; // function

{ One left-to-right pass that, unlike HarvestDotTokens, is aware of two things the loose
  scan was blind to: NON-CODE (comments and string literals, skipped via the same
  SkipNonCode the uses-clause scanner uses) and the RECEIVER of each '.Name'.

  The receiver is tracked with two variables rather than a parser. PrevIdent is the last
  identifier token seen, which covers 'btnA.Popup' and -- because a matched member becomes
  the new PrevIdent -- the last link of a chain, 'Self.btnA.Popup'. A parenthesis stack
  carries the callee across a completed call or cast, so 'TabcToggleBtn(Sender).Popup'
  credits 'TabcToggleBtn'. Any other punctuation breaks the chain and leaves the receiver
  unknown; whitespace does not.

  A candidate seen on an unknown receiver goes to ALooseNames, never to the result -- but
  only if it was not ALSO seen on a known one, so a property touched both ways reads as
  used rather than as doubtful. }
function ScanPasText(const AText: string; const ACandidates, AReceivers: TArray<string>; out ALooseNames: TArray<string>): TArray<string>;
var
  Cand      : TNameSet      ;
  Recv      : TNameSet      ;
  Hits      : TNameSet      ;
  Loose     : TNameSet      ;
  Depth     : TStack<string>;
  i         : Integer       ;
  j         : Integer       ;
  N         : Integer       ;
  PrevIdent : string        ; // last identifier token seen; '' when the chain is broken
  LastCallee: string        ; // callee of the most recently CLOSED '( ... )'
  AfterClose: Boolean       ; // the last significant token was that ')'
  Member    : string        ;
  Receiver  : string        ;
  S         : string        ;
  FilterOn  : Boolean       ; // False when no receiver names are known: filter OFF
begin
  ALooseNames:= nil;
  Cand := TNameSet.Create;
  Recv := TNameSet.Create;
  Hits := TNameSet.Create;
  Loose:= TNameSet.Create;
  Depth:= TStack<string>.Create;
  try
    for S in ACandidates do
      if S <> '' then
        Cand.Add(S);
    FilterOn:= False;
    for S in AReceivers do
      if S <> '' then
      begin
        Recv.Add(S);
        FilterOn:= True;
      end;

    N         := Length(AText);
    i         := 1;
    PrevIdent := '';
    LastCallee:= '';
    AfterClose:= False;
    while i <= N do
    begin
      // A comment or a string literal is not code, and nothing inside one can name a
      // receiver either -- so the chain breaks across it.
      if SkipNonCode(AText, i) then
      begin
        PrevIdent := '';
        AfterClose:= False;
        Continue;
      end;

      if AText[i] = '.' then
      begin
        j:= i + 1;
        while (j <= N) and IsIdentCh(AText[j]) do
          Inc(j);
        if j > i + 1 then
        begin
          Member:= Copy(AText, i + 1, j - i - 1);
          if AfterClose then
            Receiver:= LastCallee
          else
            Receiver:= PrevIdent;
          if Cand.Contains(Member) then
            if (not FilterOn) or Recv.Contains(Receiver) then
              Hits.Add(Member)
            else
              Loose.Add(Member);
          // the member becomes the receiver of any further link in the chain
          PrevIdent := Member;
          AfterClose:= False;
          i         := j;
        end
        else
          Inc(i); // a '.' with no identifier after it (end of text, or '1.' )
        Continue;
      end;

      if IsIdentStartCh(AText[i]) then
      begin
        j:= i;
        while (j <= N) and IsIdentCh(AText[j]) do
          Inc(j);
        PrevIdent := Copy(AText, i, j - i);
        AfterClose:= False;
        i         := j;
        Continue;
      end;

      if AText[i] = '(' then
      begin
        Depth.Push(PrevIdent); // remember what was being called or cast
        PrevIdent := '';
        AfterClose:= False;
      end
      else if AText[i] = ')' then
      begin
        if Depth.Count > 0 then
          LastCallee:= Depth.Pop
        else
          LastCallee:= '';
        PrevIdent := '';
        AfterClose:= True;
      end
      else if not CharInSet(AText[i], [' ', #9, #13, #10]) then
      begin
        PrevIdent := ''; // any other punctuation breaks the receiver chain
        AfterClose:= False;
      end;
      Inc(i);
    end; // while

    Result:= Hits.ToArray;
    // A name confirmed somewhere is not doubtful anywhere.
    for S in Loose.ToArray do
      if not Hits.Contains(S) then
        ALooseNames:= ALooseNames + [S];
  finally
    Depth.Free;
    Loose.Free;
    Hits .Free;
    Recv .Free;
    Cand .Free;
  end; // try
end; // function

function MergeUsage(const AParts: TArray<TArray<string>>): TArray<string>;
var
  NameSet: TNameSet      ;
  Part   : TArray<string>;
  S      : string        ;
begin
  NameSet:= TNameSet.Create;
  try
    for Part in AParts do
    for S    in Part   do
        NameSet.Add(S);
    Result:= NameSet.ToArray;
  finally
    NameSet.Free;
  end;
end; // function

function IsRowUsed(const AFromPath: string; const AUsed: TArray<string>): Boolean;
begin
  Result:= HasName(AUsed, AFromPath) or HasName(AUsed, LastSegment(AFromPath));
end;

function ComputeUsage(const ADfmTexts, APasTexts: TArray<string>; const AFromClass: string; const AFromPaths: TArray<string>): TUsageSet;
var
  Parts    : TList<TArray<string>>;
  LooseAll : TList<TArray<string>>;
  Cand     : TArray<string>       ;
  Receivers: TArray<string>       ;
  LooseOne : TArray<string>       ;
  T        : string               ;
  N        : string               ;
  Miss     : TList<string>        ;
begin
  Result:= Default      (TUsageSet );
  Cand  := CandidatesFor(AFromPaths);
  Parts:= TList<TArray<string>>.Create;
  LooseAll:= TList<TArray<string>>.Create;
  Miss:= TList<string>.Create;
  try
    // The .dfm half is class-scoped and trustworthy; it also TELLS US the instance names
    // the .pas half needs in order to be. The From class name joins them so a cast
    // 'TabcToggleBtn(Sender).X' is credited as well.
    Receivers:= nil;
    for T in ADfmTexts do
    begin
      Parts.Add(ScanDfmText(T, AFromClass));
      Receivers:= Receivers + ScanDfmInstanceNames(T, AFromClass);
      Inc(Result.DfmCount);
    end;
    // With no .dfm there are no known instances, and ScanPasText then runs unfiltered --
    // the old loose behaviour, which is the best an examination of .pas files alone can
    // honestly do. Adding the class name in that case would NOT help: it would leave the
    // filter on with a single receiver and reject everything else.
    if Length(Receivers) > 0 then
      Receivers:= Receivers + [AFromClass];
    for T in APasTexts do
    begin
      Parts.Add(ScanPasText(T, Cand, Receivers, LooseOne));
      LooseAll.Add(LooseOne);
      Inc(Result.PasCount);
    end;
    Result.Names:= MergeUsage(Parts.ToArray);
    // Loose is what the receiver filter HELD BACK, so a name the .dfm half confirmed
    // independently must not appear there -- it is used, and by the trustworthy half.
    Result.Loose:= nil;
    for N in MergeUsage(LooseAll.ToArray) do
      if not HasName(Result.Names, N) then
        Result.Loose:= Result.Loose + [N];

    // A used name is Missing when no From-tree leaf matches it by either rule.
    for N in Result.Names do
    begin
      var Found: Boolean:= False;
      for var p in AFromPaths do
        if SameText(p, N) or SameText(LastSegment(p), N) then
        begin
          Found:= True;
          Break;
        end;
      if not Found then
        Miss.Add(N);
    end; // for
    Result.Missing:= Miss.ToArray;
  finally
    Miss.Free;
    LooseAll.Free;
    Parts.Free;
  end; // try
end; // function

end.
