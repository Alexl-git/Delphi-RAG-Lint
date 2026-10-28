unit DRagLint.Fix.Store;

{ Lane A5 -- store-backed fixers of the autofix wave
  (docs\superpowers\plans\2026-10-27-autofix-wave-plan.md). The PROOF behind
  each edit is the finding itself: these rules fire only after the index
  proved the fact (zero references, an effect-free callee, an orphan managed
  block), so the fixer needs the source lines, not the store. What a fixer
  must still prove is that the text at the finding's position is STILL what
  the store described -- a second --fix run over a stale index must decline,
  never delete whatever moved onto that line. Every fixer below re-reads the
  declared name from the line and declines on any mismatch.

  Registered here: unused-private-member (fields and single-line private
  methods: declaration + implementation body), discarded-effect-free-result
  (the bare call line), doc-orphan-block (the orphan BEGIN..END block).
  Lane A5B adds: unused-public-symbol (own-unit tier: the interface prototype
  goes, its doc moves to the body), unused-unit-in-uses (the entry goes through
  the uses-movable core, RemoveUsesEntry; the initialization-section tier is
  declined), and two fixers that ASK the store (AutofixStore, nil without
  --db -> decline): empty-procedure-body (zero references, not virtual /
  override / message / published / exported) and classname-string-compare
  (`X.ClassName = 'TFoo'` -> `X.ClassType = TFoo` + the uses entry, RISKY).
  property-accessor-name is a rename, so it lives in DRagLint.Refactor.NamingFix.
  doc-param-no-description has no fix: the finding asks for prose only a human
  can write, and any stub text is still "no description" to the rule.

  The unit registers itself from its OWN initialization; DRagLint.Lint.Autofix
  never uses a fixer unit, so no unit cycle forms. }

interface

implementation

uses
  System.SysUtils, System.Classes, System.RegularExpressions, System.StrUtils,
  System.Generics.Collections, System.Math,
  DRagLint.Core.Model, DRagLint.Core.Interfaces, DRagLint.Refactor.TextEdit, DRagLint.Lint.Autofix,
  DRagLint.Lint.SharedUnit, DRagLint.Fix.ProjectWide;

const
  CRoutineKw = '(?:class\s+)?(?:procedure|function|constructor|destructor)';

{ The name the finding's message quotes ('Private member ''X'' has ...'), or ''. }
function QuotedName(const AMessage: string): string;
var
  M: TMatch;
begin
  M:= TRegEx.Match(AMessage, '''([A-Za-z_][A-Za-z0-9_]*)''');
  Result:= if M.Success then M.Groups[1].Value else '';
end;

function DeleteLines(const APath: string; AFirst, ALast: Integer): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath:= APath;
  Result.Kind    := tekDeleteLines;
  Result.Line    := AFirst;
  Result.EndLine := ALast;
end;

{ First line (1-based) of the run of '///' lines directly above ALine. }
function DocRunStart(ALines: TStrings; ALine: Integer): Integer;
begin
  Result:= ALine;
  while (Result > 1) and Trim(ALines[Result - 2]).StartsWith('///') do Dec(Result);
end;

{ The name of the class or record whose declaration encloses ALine (1-based),
  or '' when the nearest type header above it is not one. }
function EnclosingTypeName(ALines: TStrings; ALine: Integer): string;
var
  M: TMatch;
begin
  Result:= '';
  for var I:= ALine - 1 downto 1 do
  begin
    M:= TRegEx.Match(ALines[I - 1], '^\s*([A-Za-z_]\w*)\s*=\s*(?:packed\s+)?(class|record)\b(?<tail>.*)$', [roIgnoreCase]);
    if not M.Success then Continue;
    if TRegEx.IsMatch(M.Groups['tail'].Value, '^\s*(of\b|;)', [roIgnoreCase]) then Continue;   { class of / forward }
    Exit(M.Groups[1].Value);
  end;
end;

{ The implementation body of AType.AName: header line .. its column-1 `end;`.
  False when the header is missing or ambiguous (overloads), when a column-1
  routine header or a conditional directive sits inside the span, or when no
  column-1 `end;` closes it. }
function FindBody(ALines: TStrings; const AType, AName: string; out AFirst, ALast: Integer): Boolean;
var
  HeaderRx: string;
  Hits    : Integer;
begin
  Result:= False;
  AFirst:= 0;
  ALast := 0;
  { AType = '' asks for a unit-level routine: no qualifier at all }
  HeaderRx:= '^' + CRoutineKw + '\s+' + (if AType = '' then '' else '(?:[A-Za-z_]\w*\.)*' + AType + '\.') + AName + '\s*[(:;]';
  Hits:= 0;
  { bodies live below `implementation`; a unit routine's column-1 interface
    prototype above it must not count as a second header }
  var From: Integer:= 1;
  for var I:= 1 to ALines.Count do
    if SameText(Trim(ALines[I - 1]), 'implementation') then
    begin
      From:= I + 1;
      Break;
    end;
  for var I:= From to ALines.Count do
    if TRegEx.IsMatch(ALines[I - 1], HeaderRx, [roIgnoreCase]) then
    begin
      Inc(Hits);
      AFirst:= I;
    end;
  if Hits <> 1 then Exit;
  for var I:= AFirst + 1 to ALines.Count do
  begin
    var S: string:= ALines[I - 1];
    if TRegEx.IsMatch(S, '^(' + CRoutineKw + '|operator|initialization|finalization|end\.)\b', [roIgnoreCase]) then Break;
    if Trim(S).StartsWith('{$') then Exit;
    if TRegEx.IsMatch(S, '^end\s*;', [roIgnoreCase]) then ALast:= I;
  end;
  Result:= ALast > 0;
end;

{ unused-private-member: delete the declaration (with its '///' doc run) and,
  for a method, its implementation body. Declines on anything but a
  one-name field line or a one-line method declaration without overload. }
{ A one-line method declaration of AName that this fixer may delete: balanced
  parentheses, ends in ';', no overload / abstract / external / static / inline. }
function IsDeletableMethodDecl(const ALine, AName: string): Boolean;
var
  M   : TMatch;
  Tail: string;
begin
  M:= TRegEx.Match(ALine, '^\s*' + CRoutineKw + '\s+(?<name>[A-Za-z_]\w*)\b(?<tail>.*)$', [roIgnoreCase]);
  if not M.Success or not SameText(M.Groups['name'].Value, AName) then Exit(False);
  Tail:= M.Groups['tail'].Value;
  Result:= (Tail.CountChar('(') = Tail.CountChar(')'))
    and Trim(TRegEx.Replace(Tail, '//.*$', '')).EndsWith(';')
    and not TRegEx.IsMatch(Tail, '\b(overload|abstract|external|static|inline)\b', [roIgnoreCase]);
end;

function FixUnusedPrivateMember(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Name, Line, TypeName: string;
  M                   : TMatch;
  First, Last         : Integer;
begin
  Result:= nil;
  Name:= QuotedName(AFinding.Message);
  if (Name = '') or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  { a field: `Name: Type;` alone on its line (a trailing // comment allowed) }
  M:= TRegEx.Match(Line, '^\s*(?<name>[A-Za-z_]\w*)\s*:\s*[^;,=()]+;\s*(//.*)?$');
  if M.Success then
  begin
    if SameText(M.Groups['name'].Value, Name) then
      Result:= [DeleteLines(AFinding.FilePath, DocRunStart(ALines, AFinding.StartLine), AFinding.StartLine)];
    Exit;
  end;
  if not IsDeletableMethodDecl(Line, Name) then Exit;
  TypeName:= EnclosingTypeName(ALines, AFinding.StartLine);
  if (TypeName = '') or not FindBody(ALines, TypeName, Name, First, Last) then Exit;
  { one blank line after the body goes with it, so no double gap is left }
  if (Last < ALines.Count) and (Trim(ALines[Last]) = '') then Inc(Last);
  Result:= [DeleteLines(AFinding.FilePath, DocRunStart(ALines, AFinding.StartLine), AFinding.StartLine),
    DeleteLines(AFinding.FilePath, DocRunStart(ALines, First), Last)];
end;

{ discarded-effect-free-result: delete the call line. Declines when the line
  is not exactly the call, and when the previous code line ends in a word
  that makes this line a lone dependent statement (then / else / do / a case
  label) -- deleting it would hand that slot to the NEXT statement. }
function FixDiscardedEffectFree(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  M: TMatch;
begin
  Result:= nil;
  if (AFinding.SymbolName = '') or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  M:= TRegEx.Match(ALines[AFinding.StartLine - 1], '^\s*((?:[A-Za-z_]\w*\.)*)([A-Za-z_]\w*)\s*(\(.*\))?\s*;?\s*$');
  if not M.Success or not SameText(M.Groups[2].Value, AFinding.SymbolName) then Exit;
  for var I:= AFinding.StartLine - 1 downto 1 do
  begin
    var Prev: string:= Trim(TRegEx.Replace(ALines[I - 1], '//.*$', ''));
    if Prev = '' then Continue;
    if TRegEx.IsMatch(Prev, '(\b(then|else|do|of)|:)$', [roIgnoreCase]) then Exit;
    Break;
  end;
  Result:= [DeleteLines(AFinding.FilePath, AFinding.StartLine, AFinding.StartLine)];
end;

{ doc-orphan-block: delete the orphan BEGIN..END block the finding starts at,
  together with a <remarks> pair that held nothing else. }
function FixDocOrphanBlock(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  First, Last: Integer;
begin
  Result:= nil;
  First:= AFinding.StartLine;
  if (First < 1) or (First > ALines.Count) or not ALines[First - 1].Contains('drag-lint:auto BEGIN') then Exit;
  Last:= 0;
  for var I:= First + 1 to ALines.Count do
  begin
    if not Trim(ALines[I - 1]).StartsWith('///') then Exit;
    if ALines[I - 1].Contains('drag-lint:auto END') then
    begin
      Last:= I;
      Break;
    end;
  end;
  if Last = 0 then Exit;
  if (First > 1) and (Last < ALines.Count)
     and SameText(Trim(ALines[First - 2]), '/// <remarks>') and SameText(Trim(ALines[Last]), '/// </remarks>') then
  begin
    Dec(First);
    Inc(Last);
    { the stacked group's one-line <summary> goes too when the block that
      stays starts with its own <summary> right below }
    if (First > 1) and (Last < ALines.Count)
       and TRegEx.IsMatch(Trim(ALines[First - 2]), '^///\s*<summary>.*</summary>$')
       and Trim(ALines[Last]).StartsWith('/// <summary>') then Dec(First);
  end;
  Result:= [DeleteLines(AFinding.FilePath, First, Last)];
end;

{ ---------------------------------------------------------------- lane A5B }

{ ALine without a trailing // comment, blanks collapsed, lower-cased. }
function NormDecl(const ALine: string): string;
begin
  Result:= LowerCase(Trim(TRegEx.Replace(TRegEx.Replace(ALine, '//.*$', ''), '\s+', ' ')));
end;

{ 1-based line of the `implementation` keyword, 0 when none. }
function ImplementationLine(ALines: TStrings): Integer;
begin
  for var I:= 1 to ALines.Count do
    if SameText(Trim(ALines[I - 1]), 'implementation') then Exit(I);
  Result:= 0;
end;

{ Does \bAName\b occur on line I (1-based) outside a // comment? }
function LineMentions(ALines: TStrings; I: Integer; const AName: string): Boolean;
begin
  Result:= TRegEx.IsMatch(TRegEx.Replace(ALines[I - 1], '//.*$', ''), '\b' + TRegEx.Escape(AName) + '\b', [roIgnoreCase]);
end;

{ An edit inserting AText (lines joined by sLineBreak) after line ALine. }
function InsertAfter(const APath: string; ALine: Integer; const AText: string): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath:= APath;
  Result.Kind    := tekInsertLines;
  Result.Line    := ALine;
  Result.Text    := AText;
end;

{ unused-public-symbol, own-unit tier ("only referenced within its own unit"):
  delete the interface prototype; a '///' doc run above it moves onto the
  implementation header. Declines unless the prototype is one line without
  overload / inline / external, the implementation header repeats it exactly
  (a bare `procedure Foo;` body would lose its parameter list), the body ends
  in a column-1 `end;`, the header carries no doc of its own when one must
  move, and nothing between the unit start and the body names the routine --
  a use above the body needs the prototype. The finding is the proof of
  "own unit only"; the name re-read from the line is the stale-index guard. }
function FixUnusedPublicSymbol(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@3a0b -- REVIEWED 2026-10-27: one guard-clause Exit per condition under which this fixer must decline; a single exit would nest every guard
var
  M                         : TMatch;
  Name, Doc                 : string;
  ImplAt, First, Last, DocAt: Integer;
begin
  Result:= nil;
  M:= TRegEx.Match(AFinding.Message, '^Exported routine ([A-Za-z_]\w*) is only referenced within its own unit');
  if not M.Success or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Name:= M.Groups[1].Value;
  ImplAt:= ImplementationLine(ALines);
  if (ImplAt = 0) or (AFinding.StartLine > ImplAt) then Exit;
  if not IsDeletableMethodDecl(ALines[AFinding.StartLine - 1], Name) then Exit;
  if not FindBody(ALines, '', Name, First, Last) or (First <= ImplAt) then Exit;
  if NormDecl(ALines[First - 1]) <> NormDecl(ALines[AFinding.StartLine - 1]) then Exit;
  DocAt:= DocRunStart(ALines, AFinding.StartLine);
  for var I:= 1 to First - 1 do
    if ((I < DocAt) or (I > AFinding.StartLine)) and LineMentions(ALines, I, Name) then Exit;
  Result:= [DeleteLines(AFinding.FilePath, DocAt, AFinding.StartLine)];
  if DocAt < AFinding.StartLine then
  begin
    if DocRunStart(ALines, First) < First then Exit(nil);   { two docs: a human merges them }
    Doc:= '';
    for var I:= DocAt to AFinding.StartLine - 1 do
      Doc:= Doc + (if Doc = '' then '' else sLineBreak) + ALines[I - 1];
    Result:= Result + [InsertAfter(AFinding.FilePath, First - 1, Doc)];
  end;
end;

{ unused-unit-in-uses: per FILE, so two entries never get edits over the same
  line in one run (the next run, after a reindex, takes the neighbour). The
  span must still hold the unit the message names (stale-index guard), and a
  unit WITH an initialization section is declined: removing it can build
  clean and fail at runtime, which only a human (or uses-fix's compile check)
  can rule out. }
function FixUnusedUnits(const APath: string; const AFindings: TArray<TLintFinding>; out AFixed: Integer): TArray<TTextEdit>;
var
  Lines: TStringList;
  One  : TList<TTextEdit>;
  Taken: TDictionary<Integer, Boolean>;
  M    : TMatch;
  E    : TTextEdit;
  Clash: Boolean;
  Body : string;
begin
  Result:= nil;
  AFixed:= 0;
  if not FileExists(APath) then Exit;
  Lines:= TStringList.Create;
  One  := TList<TTextEdit>.Create;
  Taken:= TDictionary<Integer, Boolean>.Create;
  try
    TTextFileFormat.ReadFile(APath, Body);   { the applier's decoder: columns count the characters it will write (CLIFIX C3) }
    Lines.Text:= Body;
    for var F0: TLintFinding in AFindings do
    begin
      if not SameText(F0.RuleId, 'unused-unit-in-uses') or not SameText(F0.FilePath, APath) then Continue;
      if ContainsText(F0.Message, 'HAS an initialization section') then Continue;
      var F: TLintFinding:= WithCharColumns(F0, Lines);   { index columns are UTF-8 bytes (CLIFIX C3) }
      M:= TRegEx.Match(F.Message, '^Unit ''([A-Za-z_][\w.]*)''');
      if not M.Success or (F.StartLine < 1) or (F.StartLine > Lines.Count) then Continue;
      if not SameText(StringReplace(Copy(Lines[F.StartLine - 1], F.StartCol, F.EndCol - F.StartCol), ' ', '', [rfReplaceAll]), M.Groups[1].Value) then Continue;
      One.Clear;
      if not RemoveUsesEntry(F, Lines, One) then Continue;
      E:= One[0];
      Clash:= False;
      for var L:= E.Line to Max(E.Line, E.EndLine) do Clash:= Clash or Taken.ContainsKey(L);
      if Clash then Continue;
      for var L:= E.Line to Max(E.Line, E.EndLine) do Taken.AddOrSetValue(L, True);
      E.Owner:= FixOwnerKey(F0);   { lane IATOM: the applier writes a finding's edits all-or-nothing }
      Result:= Result + [E];
      Inc(AFixed);
    end;
  finally
    Taken.Free;
    One.Free;
    Lines.Free;
  end;
end;

{ The (last-segment) name of the routine header on ALine. }
function RoutineHeaderName(const ALine: string; out AName: string): Boolean;
var
  M: TMatch;
begin
  M:= TRegEx.Match(ALine, '^\s*' + CRoutineKw + '\s+(?:[A-Za-z_]\w*\.)*(?<name>[A-Za-z_]\w*)\s*[(:;]', [roIgnoreCase]);
  Result:= M.Success;
  AName:= if Result then M.Groups['name'].Value else '';
end;

{ May the store-proved-unreferenced routine ASym (in APath) be deleted?
  Not when anything could still reach it without a recorded reference:
  dispatch (virtual / dynamic / override / abstract / message / reintroduce),
  RTTI and the .dfm (published, or a member before any visibility keyword),
  `exports`, an interface its class implements, a sibling project of a
  shared unit, the interface section (public API), or ANY other mention of
  the name in the file (a property accessor is not a reference in the index). }
function IsDeletableRoutine(const AStore: ISymbolStore; const ASym: TSymbol; const APath: string; ALines: TStrings): Boolean;  // dl:ok too-many-exit-points@c1be -- REVIEWED 2026-10-27: one guard-clause Exit per condition under which this fixer must decline; a single exit would nest every guard
var
  Parent: TSymbol;
  DocAt : Integer;
begin
  Result:= False;
  if (ASym.Kind not in [skProcedure, skFunction, skMethod]) or ASym.IsVirtual then Exit;
  if TRegEx.IsMatch(ASym.Directives + ' ' + ASym.Modifiers,
       '\b(virtual|dynamic|override|abstract|message|reintroduce|export|external|overload|published)\b', [roIgnoreCase]) then Exit;
  if (ASym.Kind = skMethod) and not ASym.VisExplicit then Exit;
  if (ASym.Kind <> skMethod) and SameText(ASym.Section, 'interface') then Exit;
  if ASym.Kind = skMethod then
  begin
    Parent:= AStore.GetSymbolById(ASym.ParentId);
    if (Parent.Id <> ASym.ParentId) or (Parent.Kind <> skClass) or Parent.Heritage.Contains(',') then Exit;
  end;
  if Length(TSharedUnit.ProjectsOf(APath)) > 1 then Exit;
  if Length(AStore.FindReferencesTo(ASym.Id)) > 0 then Exit;
  if Length(AStore.FindCallersByName(ASym.Name)) > 0 then Exit;
  DocAt:= DocRunStart(ALines, ASym.StartLine);
  for var I:= 1 to ALines.Count do
  begin
    if TRegEx.IsMatch(ALines[I - 1], '^\s*exports\b', [roIgnoreCase]) then Exit;
    if InRange(I, ASym.ImplStartLine, ASym.ImplEndLine) or InRange(I, DocAt, ASym.StartLine) then Continue;
    if LineMentions(ALines, I, ASym.Name) then Exit;
  end;
  Result:= True;
end;

{ empty-procedure-body: delete the empty routine -- body, its doc run, and a
  separate one-line declaration -- when the store holds no reference to it.
  Needs --db (AutofixStore); the store row must have its body on the finding's
  line and bear the name read from that line, so a stale index declines. }
function FixEmptyProcedureBody(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@b5db -- REVIEWED 2026-10-27: one guard-clause Exit per condition under which this fixer must decline; a single exit would nest every guard
var
  Store: ISymbolStore;
  Name : string;
  Hit  : TSymbol;
  Hits : Integer;
  Last : Integer;
begin
  Result:= nil;
  Store:= AutofixStore;
  if (Store = nil) or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  if not RoutineHeaderName(ALines[AFinding.StartLine - 1], Name) then Exit;
  Hits:= 0;
  Hit:= Default(TSymbol);
  for var S: TSymbol in Store.FindSymbolsByFile(AFinding.FilePath) do
    if (S.ImplStartLine = AFinding.StartLine) and SameText(S.Name, Name) then
    begin
      Inc(Hits);
      Hit:= S;
    end;
  if (Hits <> 1) or (Hit.ImplEndLine < Hit.ImplStartLine) or (Hit.ImplEndLine > ALines.Count) then Exit;
  if not TRegEx.IsMatch(ALines[Hit.ImplEndLine - 1], '^\s*end\s*;', [roIgnoreCase]) then Exit;
  for var I:= Hit.ImplStartLine to Hit.ImplEndLine do
    if Trim(ALines[I - 1]).StartsWith('{$') then Exit;
  if not IsDeletableRoutine(Store, Hit, AFinding.FilePath, ALines) then Exit;
  Last:= Hit.ImplEndLine;
  if (Last < ALines.Count) and (Trim(ALines[Last]) = '') then Inc(Last);
  Result:= [DeleteLines(AFinding.FilePath, DocRunStart(ALines, AFinding.StartLine), Last)];
  if Hit.StartLine <> Hit.ImplStartLine then
  begin
    if (Hit.StartLine <> Hit.EndLine) or not IsDeletableMethodDecl(ALines[Hit.StartLine - 1], Name) then Exit(nil);
    Result:= Result + [DeleteLines(AFinding.FilePath, DocRunStart(ALines, Hit.StartLine), Hit.StartLine)];
  end;
end;

{ Is ALine (1-based) inside a CLASS method, where Self is a metaclass? True
  when no routine header is found above it (unknown counts as unsafe). }
function InClassRoutine(ALines: TStrings; ALine: Integer): Boolean;
begin
  for var I:= ALine downto 1 do
    if TRegEx.IsMatch(ALines[I - 1], '^' + CRoutineKw + '\b', [roIgnoreCase]) then
      Exit(TRegEx.IsMatch(ALines[I - 1], '^class\s', [roIgnoreCase]));
  Result:= True;
end;

{ Is ATypeName an instance class type, so that ClassType compiles on it?
  TObject, or exactly one class the store holds and no metaclass or alias of
  that name. }
function IsInstanceType(const AStore: ISymbolStore; const ATypeName: string): Boolean;
var
  Classes: Integer;
begin
  if ATypeName = '' then Exit(False);
  if SameText(ATypeName, 'TObject') then Exit(True);
  if SameText(ATypeName, 'TClass') or EndsText('Class', ATypeName) then Exit(False);
  Classes:= 0;
  for var S: TSymbol in AStore.FindSymbolsByExactName(ATypeName) do
    if S.Kind = skClass then Inc(Classes)
    else if S.Kind in [skClassRef, skTypeAlias] then Exit(False);
  Result:= Classes = 1;
end;

{ classname-string-compare, per FILE (one uses entry however many sites need
  it): `X.ClassName = 'TFoo'` -> `X.ClassType = TFoo` (`<>` likewise). The
  same exact-class test by identity instead of by name -- RISKY, because a
  second TFoo in some other unit no longer matches. Declines unless X is Self
  in an instance method or a local / parameter of an instance class type, and
  the literal names exactly one class the store holds, declared above the use
  when it is in this file; another unit's class adds that unit to the
  implementation uses clause. Needs --db (AutofixStore). }
function FixClassNameCompare(const APath: string; const AFindings: TArray<TLintFinding>; out AFixed: Integer): TArray<TTextEdit>;
var
  Store : ISymbolStore;
  Lines : TStringList;
  Units : TStringList;
  Body  : string;
  M     : TMatch;
  Span  : string;
  Target: TSymbol;
  Hits  : Integer;
  E     : TTextEdit;
  TPath : string;
  UnitNm: string;
begin
  Result:= nil;
  AFixed:= 0;
  Store:= AutofixStore;
  if (Store = nil) or not FileExists(APath) then Exit;
  Lines:= TStringList.Create;
  Units:= TStringList.Create(dupIgnore, True, False);
  try
    TTextFileFormat.ReadFile(APath, Body);   { the applier's decoder: columns count the characters it will write (CLIFIX C3) }
    Lines.Text:= Body;
    if ImplementationLine(Lines) = 0 then Exit;
    for var F0: TLintFinding in AFindings do
    begin
      if not SameText(F0.RuleId, 'classname-string-compare') or not SameText(F0.FilePath, APath) then Continue;
      var F: TLintFinding:= WithCharColumns(F0, Lines);   { index columns are UTF-8 bytes (CLIFIX C3) }
      if (F.StartLine < 1) or (F.StartLine > Lines.Count) or (F.EndLine <> F.StartLine) or (F.StartCol < 1) or (F.EndCol <= F.StartCol) then Continue;
      Span:= Copy(Lines[F.StartLine - 1], F.StartCol, F.EndCol - F.StartCol);
      M:= TRegEx.Match(Span, '^(?<recv>[A-Za-z_]\w*)\.ClassName\s*(?<op>=|<>)\s*''(?<cls>[A-Za-z_]\w*)''$');
      if not M.Success then Continue;
      if SameText(M.Groups['recv'].Value, 'Self') then
      begin
        if InClassRoutine(Lines, F.StartLine) then Continue;
      end
      else if not IsInstanceType(Store, DeclTypeOf(APath, F.StartLine, M.Groups['recv'].Value)) then Continue;
      Hits:= 0;
      Target:= Default(TSymbol);
      for var S: TSymbol in Store.FindSymbolsByExactName(M.Groups['cls'].Value) do
        if S.Kind = skClass then
        begin
          Inc(Hits);
          Target:= S;
        end;
      if Hits <> 1 then Continue;
      TPath:= Store.GetFilePath(Target.FileId);
      UnitNm:= '';
      if SameText(TPath, APath) then
      begin
        if Target.StartLine > F.StartLine then Continue;
      end
      else
      begin
        for var S: TSymbol in Store.FindSymbolsByFile(TPath) do
          if S.Kind = skUnit then UnitNm:= S.Name;
        if UnitNm = '' then Continue;
      end;
      E:= Default(TTextEdit);
      E.FilePath  := APath;
      E.Kind      := tekReplaceInLine;
      E.Line      := F.StartLine;
      E.Col       := F.StartCol;
      E.EndCol    := F.EndCol;
      E.Text      := M.Groups['recv'].Value + '.ClassType ' + M.Groups['op'].Value + ' ' + M.Groups['cls'].Value;
      E.ExpectText:= Span;
      Result:= Result + [E];
      Inc(AFixed);
      if UnitNm <> '' then Units.Add(UnitNm);
    end;
    for var U: string in Units do
      if EnsureImplUses(APath, Lines, U, E) then Result:= Result + [E];
  finally
    Units.Free;
    Lines.Free;
  end;
end;

initialization
  RegisterFixer('unused-private-member', FixUnusedPrivateMember);
  RegisterFixer('discarded-effect-free-result', FixDiscardedEffectFree);
  RegisterFixer('doc-orphan-block', FixDocOrphanBlock);
  RegisterFixer('unused-public-symbol', FixUnusedPublicSymbol);
  RegisterFileFixer('unused-unit-in-uses', FixUnusedUnits);
  RegisterFixer('empty-procedure-body', FixEmptyProcedureBody);
  RegisterFileFixer('classname-string-compare', FixClassNameCompare, True);

end.
