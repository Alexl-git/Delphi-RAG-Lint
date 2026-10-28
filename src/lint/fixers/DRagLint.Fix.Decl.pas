unit DRagLint.Fix.Decl;

{ Lane A4 -- declaration / directive fixers (8 ids) of the autofix wave
  (docs\superpowers\plans\2026-10-27-autofix-wave-plan.md):

    inherited-bare, inline-on-large-routine, missing-const-param, public-field
    and the risky destructor-without-override, missing-inherited-dtor,
    missing-inherited-ctor, method-could-be-static.

  Every fixer is a pure TEXT fixer over the finding's file lines: it reads the
  routine / class headers the way the source shows them, edits both the
  declaration and the implementation header where the rule needs both, and
  DECLINES (returns no edits) whenever the text is ambiguous -- an overloaded
  name, a header it cannot pair, a section it cannot classify. A declined
  finding stays a finding; it is never half-fixed.

  The unit registers itself from its OWN initialization; DRagLint.Lint.Autofix
  never uses a fixer unit, so no unit cycle forms. }

interface

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Math
  , System.StrUtils
  , System.RegularExpressions
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  ;

const
  DECL_INDENT_STEP  = 2;
  DECL_MAX_HEADER   = 40;
  DECL_MAX_BACK     = 6;
  DECL_ROUTINE_HEAD = '^\s*(?:class\s+)?(procedure|function|constructor|destructor)\b';
  DECL_DIRECTIVE    = '^\s*(?:inline|overload|register|stdcall|cdecl|pascal|safecall|static|virtual|override|' +
    'reintroduce|abstract|deprecated|platform|experimental|forward|external|dynamic|final|unsafe|message|' +
    'varargs|export)\b';
  DECL_CLASS_START  = '^\s*[A-Za-z_]\w*\s*(?:<[^>]*>)?\s*=\s*(?:packed\s+)?(?:class|object)\b(?!\s+of\b)(?!\s*;)';
  DECL_VISIBILITY   = '^\s*(strict\s+)?(private|protected|public|published|automated)\s*$';
  DECL_STMT_END     = ';\s*(//.*|\{[^}]*\})?\s*$';
  DECL_BAD_STATIC   = '\b(virtual|override|dynamic|message|abstract|reintroduce|static|class)\b';

type
  TDeclLookup = (dlNone, dlFound, dlAmbiguous);

function DcNewEdit(const AFinding: TLintFinding; AKind: TTextEditKind; ALine: Integer): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath:= AFinding.FilePath;
  Result.Kind    := AKind;
  Result.Line    := ALine;
end;

function DcIndentOf(const ALine: string): Integer;
begin
  Result:= Length(ALine) - Length(TrimLeft(ALine));
end;

{ The line (1-based) of the routine keyword that opens the header containing ALine, or 0. }
function DcHeaderKeywordLine(ALines: TStringList; ALine: Integer): Integer;
var
  I: Integer;
begin
  Result:= 0;
  for I:= Min(ALine, ALines.Count) downto Max(1, ALine - DECL_MAX_BACK) do
    if TRegEx.IsMatch(ALines[I - 1], DECL_ROUTINE_HEAD, [roIgnoreCase]) then Exit(I);
end;

{ Finds the ';' that ends the routine header opening on line AFirst: first ';' at paren depth 0,
  outside strings and // comments. }
function DcHeaderEnd(ALines: TStringList; AFirst: Integer; out ASemiLine, ASemiCol: Integer): Boolean;
var
  I, J, Depth: Integer;
  S          : string;
  InStr      : Boolean;
  Ch         : Char;
begin
  Result:= False;
  ASemiLine:= 0;
  ASemiCol:= 0;
  Depth:= 0;
  for I:= AFirst to Min(ALines.Count, AFirst + DECL_MAX_HEADER) do
  begin
    S:= ALines[I - 1];
    InStr:= False;
    J:= 1;
    while J <= Length(S) do
    begin
      Ch:= S[J];
      if InStr then
        InStr:= Ch <> ''''
      else if Ch = '''' then
        InStr:= True
      else if (Ch = '/') and (J < Length(S)) and (S[J + 1] = '/') then
        Break
      else if Ch = '(' then
        Inc(Depth)
      else if Ch = ')' then
        Dec(Depth)
      else if (Ch = ';') and (Depth <= 0) then
      begin
        ASemiLine:= I;
        ASemiCol := J;
        Exit(True);
      end;
      Inc(J);
    end;
  end;
end;

{ Last line of the header's directive tail: ASemiLine plus every following line that opens with a directive. }
function DcDirectivesLast(ALines: TStringList; ASemiLine: Integer): Integer;
begin
  Result:= ASemiLine;
  while (Result < ALines.Count) and TRegEx.IsMatch(ALines[Result], DECL_DIRECTIVE, [roIgnoreCase]) do
    Inc(Result);
end;

{ Kind keyword and qualified name of the header on ALine. }
function DcParseHead(const ALine: string; out AKind, AQName: string): Boolean;
var
  M: TMatch;
begin
  AKind:= '';
  AQName:= '';
  M:= TRegEx.Match(ALine, DECL_ROUTINE_HEAD + '\s+([^\s(;:]+)', [roIgnoreCase]);
  Result:= M.Success;
  if Result then
  begin
    AKind := LowerCase(M.Groups[1].Value);
    AQName:= M.Groups[2].Value;
  end;
end;

{ 1-based [AFirst, ALast] of the class / object declaration named AClass, ALast = its `end;` at the same indent. }
function DcClassRange(ALines: TStringList; const AClass: string; out AFirst, ALast: Integer): Boolean;
var
  I, J, Ind: Integer;
  Rx       : string;
begin
  Result:= False;
  AFirst:= 0;
  ALast:= 0;
  Rx:= '^\s*' + TRegEx.Escape(AClass) + '\s*(?:<[^>]*>)?\s*=\s*(?:packed\s+)?(?:class|object)\b(?!\s+of\b)(?!\s*;)';
  for I:= 1 to ALines.Count do
    if TRegEx.IsMatch(ALines[I - 1], Rx, [roIgnoreCase]) then
    begin
      Ind:= DcIndentOf(ALines[I - 1]);
      for J:= I + 1 to ALines.Count do
        if (DcIndentOf(ALines[J - 1]) = Ind) and TRegEx.IsMatch(ALines[J - 1], '^\s*end\s*;', [roIgnoreCase]) then
        begin
          AFirst:= I;
          ALast := J;
          Exit(True);
        end;
      Exit;
    end;
end;

{ Pairs the implementation header at AImplLine with its declaration in the same file.
  Method (AQName = Class.Method): the single header of that name inside the class body.
  Standalone routine: the single unindented header of that name elsewhere in the file. }
function DcLookupDecl(ALines: TStringList; AImplLine: Integer; const AQName: string; out ADeclLine: Integer): TDeclLookup;
var
  P, Q, I, Cnt, S, E: Integer;
  Cls, Meth, Rx     : string;
begin
  ADeclLine:= 0;
  Cnt:= 0;
  P:= LastDelimiter('.', AQName);
  if P > 0 then
  begin
    Cls := Copy(AQName, 1, P - 1);
    Meth:= Copy(AQName, P + 1, MaxInt);
    Q:= Pos('<', Cls);
    if Q > 0 then Cls:= Copy(Cls, 1, Q - 1);
    if not DcClassRange(ALines, Cls, S, E) then Exit(dlNone);
    Rx:= '^\s*(?:class\s+)?(?:procedure|function|constructor|destructor)\s+' + TRegEx.Escape(Meth) + '\s*(?:$|[(;:])';
  end
  else
  begin
    S:= 1;
    E:= ALines.Count;
    Rx:= '^(?:procedure|function)\s+' + TRegEx.Escape(AQName) + '\s*(?:$|[(;:])';
  end;
  for I:= S to E do
    if (I <> AImplLine) and TRegEx.IsMatch(ALines[I - 1], Rx, [roIgnoreCase]) then
    begin
      Inc(Cnt);
      ADeclLine:= I;
    end;
  if Cnt = 0 then Exit(dlNone);
  if Cnt > 1 then Exit(dlAmbiguous);
  Result:= dlFound;
end;

{ Splits AText at AChar outside (), [] and <>. }
function DcSplitTop(const AText: string; AChar: Char): TArray<string>;
var
  Parts: TList<string>;
  I, Depth, Start: Integer;
begin
  Parts:= TList<string>.Create;
  try
    Depth:= 0;
    Start:= 1;
    for I:= 1 to Length(AText) do
      if CharInSet(AText[I], ['(', '[', '<']) then
        Inc(Depth)
      else if CharInSet(AText[I], [')', ']', '>']) then
        Dec(Depth)
      else if (AText[I] = AChar) and (Depth <= 0) then
      begin
        Parts.Add(Copy(AText, Start, I - Start));
        Start:= I + 1;
      end;
    Parts.Add(Copy(AText, Start, MaxInt));
    Result:= Parts.ToArray;
  finally
    Parts.Free;
  end;
end;

{ Parameter names of the header whose text is AHeader (name, '(' params ')', ...). False on any shape it cannot read. }
function DcParamNames(const AHeader: string; ANames: TList<string>): Boolean;
var
  Open, I, Depth, Close: Integer;
  Inner, Group, Part   : string;
  Names                : TArray<string>;
  ColonP, EqP          : Integer;
  Nm                   : string;
begin
  Result:= False;
  Open:= Pos('(', AHeader);
  if (Open = 0) or ((AHeader.Contains(';')) and (Pos(';', AHeader) < Open)) then Exit(True);  { no parameter list }
  Depth:= 0;
  Close:= 0;
  for I:= Open to Length(AHeader) do
    if AHeader[I] = '(' then
      Inc(Depth)
    else if AHeader[I] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close:= I;
        Break;
      end;
    end;
  if Close = 0 then Exit;
  Inner:= Copy(AHeader, Open + 1, Close - Open - 1);
  for Part in DcSplitTop(Inner, ';') do
  begin
    Group:= Trim(TRegEx.Replace(Part, '^\s*\[[^\]]*\]\s*', ''));
    Group:= TRegEx.Replace(Group, '^(?:var|const|out)\s+', '', [roIgnoreCase]);
    ColonP:= Pos(':', Group);
    EqP   := Pos('=', Group);
    if ColonP > 0 then
      Group:= Copy(Group, 1, ColonP - 1)
    else if EqP > 0 then
      Group:= Copy(Group, 1, EqP - 1);
    Names:= Group.Split([',']);
    for Nm in Names do
    begin
      if not TRegEx.IsMatch(Trim(Nm), '^[A-Za-z_]\w*$') then Exit;
      ANames.Add(Trim(Nm));
    end;
  end;
  Result:= True;
end;

{ Text of the header from the keyword line to its terminating ';' (comments not stripped: ParamNames rejects them). }
function DcHeaderText(ALines: TStringList; AFirst, ALast: Integer): string;
var
  I: Integer;
begin
  Result:= '';
  for I:= AFirst to ALast do Result:= Result + ' ' + ALines[I - 1];
end;

{ The body of the routine whose keyword line is AKeyLine and whose header ends on AHeaderLast:
  `begin` and the closing `end;` at the header's own indent. }
function DcBodyRange(ALines: TStringList; AKeyLine, AHeaderLast: Integer; out ABegin, AEnd: Integer): Boolean;
var
  I, Ind: Integer;
begin
  Result:= False;
  ABegin:= 0;
  AEnd:= 0;
  Ind:= DcIndentOf(ALines[AKeyLine - 1]);
  for I:= AHeaderLast + 1 to ALines.Count do
    if DcIndentOf(ALines[I - 1]) = Ind then
    begin
      if ABegin = 0 then
      begin
        if TRegEx.IsMatch(ALines[I - 1], '^\s*begin\b', [roIgnoreCase]) then ABegin:= I
        else if TRegEx.IsMatch(ALines[I - 1], '^\s*(?:class\s+)?(?:procedure|function|constructor|destructor|implementation)\b', [roIgnoreCase]) then
          Exit;
      end
      else if TRegEx.IsMatch(ALines[I - 1], '^\s*end\s*;', [roIgnoreCase]) then
      begin
        AEnd:= I;
        Exit(True);
      end;
    end;
end;

{ ------------------------------------------------------------------ inherited-bare }

{ True when a class declaration line in the file declares procedure AMeth with the override directive. }
function DcDeclaredOverride(ALines: TStringList; const AMeth: string): Boolean;
begin
  Result:= TRegEx.IsMatch(ALines.Text, '^\s*procedure\s+' + TRegEx.Escape(AMeth) + '\b[^\r\n]*\boverride\s*;', [roIgnoreCase, roMultiLine]);
end;

{ inherited-bare: `inherited;` -> `inherited <Method>(<param names>);` from the enclosing implementation header.
  Declines for a function (the bare form forwards the result), for a constructor WITH parameters (a bare
  `inherited;` there legally reaches an ancestor constructor of a different signature, e.g. TObject.Create),
  and when the enclosing routine cannot be proven (nested routine, unreadable parameter list). }
function FixInheritedBare(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line, Span, Kind, QName, Meth, Text, Call: string;
  H, SemiLine, SemiCol, BodyBegin, BodyEnd : Integer;
  Names                                    : TList<string>;
  E                                        : TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine <> AFinding.EndLine) or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  if (AFinding.StartCol < 1) or (AFinding.EndCol > Length(Line) + 1) then Exit;
  Span:= Copy(Line, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
  if not SameText(Span, 'inherited') then Exit;
  H:= AFinding.StartLine;
  while (H >= 1) and not TRegEx.IsMatch(ALines[H - 1], DECL_ROUTINE_HEAD, [roIgnoreCase]) do Dec(H);
  if (H < 1) or not DcParseHead(ALines[H - 1], Kind, QName) then Exit;
  if (Kind = 'function') or not DcHeaderEnd(ALines, H, SemiLine, SemiCol) then Exit;
  if not DcBodyRange(ALines, H, SemiLine, BodyBegin, BodyEnd) then Exit;
  if (AFinding.StartLine <= BodyBegin) or (AFinding.StartLine >= BodyEnd) then Exit;
  Meth:= Copy(QName, LastDelimiter('.', QName) + 1, MaxInt);
  { a procedure that is not declared override may have no ancestor method of its name (an event handler): decline }
  if (Kind = 'procedure') and not DcDeclaredOverride(ALines, Meth) then Exit;
  Text:= DcHeaderText(ALines, H, SemiLine);
  Names:= TList<string>.Create;
  try
    if not DcParamNames(Text, Names) then Exit;
    if (Kind = 'constructor') and (Names.Count > 0) then Exit;
    Call:= 'inherited ' + Meth;
    if Names.Count > 0 then Call:= Call + '(' + string.Join(', ', Names.ToArray) + ')';
  finally
    Names.Free;
  end;
  E:= DcNewEdit(AFinding, tekReplaceInLine, AFinding.StartLine);
  E.Col       := AFinding.StartCol;
  E.EndCol    := AFinding.EndCol;
  E.ExpectText:= Span;
  E.Text      := Call;
  Result:= [E];
end;

{ ------------------------------------------------------------ inline-on-large-routine }

{ Edits deleting the `inline;` directive of the header opening on line AKeyLine (none when it has none). }
procedure DcRemoveInline(const AFinding: TLintFinding; ALines: TStringList; AKeyLine: Integer; AEdits: TList<TTextEdit>);
var
  SemiLine, SemiCol, Last, I: Integer;
  M                          : TMatch;
  E                          : TTextEdit;
begin
  if not DcHeaderEnd(ALines, AKeyLine, SemiLine, SemiCol) then Exit;
  Last:= DcDirectivesLast(ALines, SemiLine);
  for I:= AKeyLine to Last do
  begin
    if TRegEx.IsMatch(ALines[I - 1], '^\s*inline\s*;\s*$', [roIgnoreCase]) then
    begin
      E:= DcNewEdit(AFinding, tekDeleteLines, I);
      E.EndLine   := I;
      E.ExpectLine:= I;
      E.ExpectText:= 'inline';
      AEdits.Add(E);
      Continue;
    end;
    M:= TRegEx.Match(ALines[I - 1], ';\s*inline\s*;', [roIgnoreCase]);
    if M.Success then
    begin
      E:= DcNewEdit(AFinding, tekReplaceInLine, I);
      E.Col       := M.Index;
      E.EndCol    := M.Index + M.Length;
      E.ExpectText:= M.Value;
      E.Text      := ';';
      AEdits.Add(E);
    end;
  end;
end;

{ inline-on-large-routine: delete `inline;` on the declaration and on the implementation header (a hint, no
  semantics). A method needs its declaration found in its class; an overloaded name declines. }
function FixInlineOnLargeRoutine(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Kind, QName: string;
  K, DeclLine: Integer;
  Edits      : TList<TTextEdit>;
  Found      : TDeclLookup;
begin
  Result:= nil;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  K:= DcHeaderKeywordLine(ALines, AFinding.StartLine);
  if (K = 0) or not DcParseHead(ALines[K - 1], Kind, QName) then Exit;
  if (not QName.Contains('.')) and (DcIndentOf(ALines[K - 1]) <> 0) then Exit;
  Found:= DcLookupDecl(ALines, K, QName, DeclLine);
  if (Found = dlAmbiguous) or ((Found = dlNone) and (QName.Contains('.'))) then Exit;
  Edits:= TList<TTextEdit>.Create;
  try
    DcRemoveInline(AFinding, ALines, K, Edits);
    if Found = dlFound then DcRemoveInline(AFinding, ALines, DeclLine, Edits);
    Result:= Edits.ToArray;
  finally
    Edits.Free;
  end;
end;

{ ------------------------------------------------------------------ missing-const-param }

{ True when the identifier at (ALine, ACol) of length ALen opens a lone by-value parameter: the previous code
  character is '(' or ';' (no modifier, no group comma) and a ':' follows. }
function DcLoneParamAt(ALines: TStringList; ALine, ACol, ALen: Integer): Boolean;
var
  I, J: Integer;
  S   : string;
  Prev: Char;
begin
  Result:= False;
  S:= ALines[ALine - 1];
  if not TRegEx.IsMatch(Copy(S, ACol + ALen, MaxInt), '^\s*:') then Exit;
  Prev:= #0;
  I:= ALine;
  J:= ACol - 1;
  while I >= 1 do
  begin
    S:= ALines[I - 1];
    while (J >= 1) and CharInSet(S[J], [' ', #9]) do Dec(J);
    if J >= 1 then
    begin
      Prev:= S[J];
      Break;
    end;
    Dec(I);
    if I >= 1 then J:= Length(ALines[I - 1]);
  end;
  Result:= CharInSet(Prev, ['(', ';']);
end;

{ missing-const-param: insert `const ` before the lone by-value parameter on the implementation header AND on the
  declaration. Declines for a grouped name list, an overloaded or unpaired method, or a parameter the declaration
  spells differently. }
function FixMissingConstParam(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line, Name, Kind, QName: string;
  K, DeclLine, SemiLine, SemiCol, I, Col: Integer;
  Found      : TDeclLookup;
  M          : TMatch;
  E, E2      : TTextEdit;
  Hits       : Integer;
  HitLine    : Integer;
  HitCol     : Integer;
begin
  Result:= nil;
  if (AFinding.StartLine <> AFinding.EndLine) or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  if (AFinding.StartCol < 1) or (AFinding.EndCol > Length(Line) + 1) then Exit;
  Name:= Copy(Line, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
  if not DcLoneParamAt(ALines, AFinding.StartLine, AFinding.StartCol, Length(Name)) then Exit;
  K:= DcHeaderKeywordLine(ALines, AFinding.StartLine);
  if (K = 0) or not DcParseHead(ALines[K - 1], Kind, QName) then Exit;
  if not DcHeaderEnd(ALines, K, SemiLine, SemiCol) or (SemiLine < AFinding.StartLine) then Exit;
  if (not QName.Contains('.')) and (DcIndentOf(ALines[K - 1]) <> 0) then Exit;
  Found:= DcLookupDecl(ALines, K, QName, DeclLine);
  if (Found = dlAmbiguous) or ((Found = dlNone) and (QName.Contains('.'))) then Exit;
  E:= DcNewEdit(AFinding, tekReplaceInLine, AFinding.StartLine);
  E.Col       := AFinding.StartCol;
  E.EndCol    := AFinding.EndCol;
  E.ExpectText:= Name;
  E.Text      := 'const ' + Name;
  if Found = dlNone then
  begin
    Result:= [E];
    Exit;
  end;
  if not DcHeaderEnd(ALines, DeclLine, SemiLine, SemiCol) then Exit;
  Hits:= 0;
  HitLine:= 0;
  HitCol := 0;
  for I:= DeclLine to SemiLine do
    for M in TRegEx.Matches(ALines[I - 1], '(?<![\w.])' + TRegEx.Escape(Name) + '(?=\s*:)', [roIgnoreCase]) do
    begin
      Col:= M.Index;
      if DcLoneParamAt(ALines, I, Col, Length(Name)) then
      begin
        Inc(Hits);
        HitLine:= I;
        HitCol := Col;
      end;
    end;
  if Hits <> 1 then Exit;
  E2:= DcNewEdit(AFinding, tekReplaceInLine, HitLine);
  E2.Col       := HitCol;
  E2.EndCol    := HitCol + Length(Name);
  E2.ExpectText:= Name;
  E2.Text      := 'const ' + Name;
  Result:= [E, E2];
end;

{ ------------------------------------------------------------------------ public-field }

const
  DECL_HEADER_RE = '\b(?:procedure|function|constructor|destructor)\s+(?:\w+\.)*(\w+)\s*(?:\(((?:[^()]|\([^()]*\))*)\))?';
  DECL_CALL_RE   = '\b(\w+)\s*\(';

{ Per routine name declared in the file: one char per parameter position, '1' = var/out, '0' = other (overloads
  OR-ed together). AHeaderSpans receives the [start, end) 1-based text range of every header so calls scanning skips them. }
procedure DcVarParamMasks(const AText: string; AMasks: TDictionary<string, string>; AHeaderSpans: TList<TPair<Integer, Integer>>);
var
  M: TMatch;
  Part, Mod1, NamePart, Old, Mask, Merged: string;
  Colon, I, N: Integer;
begin
  for M in TRegEx.Matches(AText, DECL_HEADER_RE, [roIgnoreCase, roSingleLine]) do
  begin
    AHeaderSpans.Add(TPair<Integer, Integer>.Create(M.Index, M.Index + M.Length));
    Mask:= '';
    { Groups holds only up to the last group that PARTICIPATED: a header without a
      parameter list has no Groups[2], and indexing it raises. }
    if (M.Groups.Count > 2) and M.Groups[2].Success then
      for Part in DcSplitTop(M.Groups[2].Value, ';') do
      begin
        Colon:= Pos(':', Part);
        NamePart:= if Colon > 0 then Trim(Copy(Part, 1, Colon - 1)) else Trim(Part);
        Mod1:= if TRegEx.IsMatch(NamePart, '^(?:var|out)\b', [roIgnoreCase]) then '1' else '0';
        NamePart:= TRegEx.Replace(NamePart, '^(?:var|out|const)\s+', '', [roIgnoreCase]);
        N:= Length(DcSplitTop(NamePart, ','));
        Mask:= Mask + StringOfChar(Mod1[1], N);   // dl:ok concat-in-loop@e14b -- REVIEWED 2026-10-27: one char per parameter, a handful per header
      end;
    if AMasks.TryGetValue(LowerCase(M.Groups[1].Value), Old) then
    begin
      Merged:= StringOfChar('0', Max(Length(Old), Length(Mask)));
      for I:= 1 to Length(Merged) do
        if ((I <= Length(Old)) and (Old[I] = '1')) or ((I <= Length(Mask)) and (Mask[I] = '1')) then Merged[I]:= '1';
      Mask:= Merged;
    end;
    AMasks.AddOrSetValue(LowerCase(M.Groups[1].Value), Mask);
  end;
end;

{ True when the argument list starting at the '(' at AOpen (1-based) of AText has, at a var/out position of AMask,
  an argument that is AName or a dotted path ending in AName. }
function DcArgHitsField(const AText: string; AOpen: Integer; const AMask, AName: string): Boolean;
var
  I, Depth, Pos1: Integer;
  Args: TArray<string>;
begin
  Result:= False;
  Depth:= 0;
  for I:= AOpen to Length(AText) do
  begin
    if AText[I] = '(' then Inc(Depth)
    else if AText[I] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Args:= DcSplitTop(Copy(AText, AOpen + 1, I - AOpen - 1), ',');
        for Pos1:= 0 to High(Args) do
          if (Pos1 < Length(AMask)) and (AMask[Pos1 + 1] = '1') and
             TRegEx.IsMatch(Trim(Args[Pos1]), '^(?:\w+\.)*' + TRegEx.Escape(AName) + '$', [roIgnoreCase]) then Exit(True);
        Exit;
      end;
    end;
  end;
end;

{ True when the file passes AName (bare or as the last segment of a dotted path) to a routine declared in the SAME
  file at a position where that routine's parameter is var/out -- a property cannot be passed there. }
function DcFieldPassedAsVarArg(ALines: TStringList; const AName: string): Boolean;
var
  Masks    : TDictionary<string, string>;
  Spans    : TList<TPair<Integer, Integer>>;
  Text     : string;
  M        : TMatch;
  Mask     : string;
  Span     : TPair<Integer, Integer>;
  InHeader : Boolean;
begin
  Result:= False;
  Text:= ALines.Text;
  Masks:= TDictionary<string, string>.Create;
  Spans:= TList<TPair<Integer, Integer>>.Create;
  try
    DcVarParamMasks(Text, Masks, Spans);
    for M in TRegEx.Matches(Text, DECL_CALL_RE, [roIgnoreCase]) do
    begin
      if not Masks.TryGetValue(LowerCase(M.Groups[1].Value), Mask) then Continue;
      InHeader:= False;
      for Span in Spans do
        if (M.Index >= Span.Key) and (M.Index < Span.Value) then InHeader:= True;
      if InHeader then Continue;
      if DcArgHitsField(Text, M.Index + M.Length - 1, Mask, AName) then Exit(True);
    end;
  finally
    Spans.Free;
    Masks.Free;
  end;
end;
{ True when the file uses AName (bare or as the last segment of a dotted path) where a variable is required:
  the first argument of Inc / Dec / Include / Exclude, or the operand of @ -- a property cannot stand there. }
function DcFieldUsedAsVariable(ALines: TStringList; const AName: string): Boolean;
var
  Esc: string;
begin
  Esc:= TRegEx.Escape(AName);
  Result:= TRegEx.IsMatch(ALines.Text, '\b(?:Inc|Dec|Include|Exclude)\s*\(\s*(?:\w+\.)*' + Esc + '\b', [roIgnoreCase]) or
    TRegEx.IsMatch(ALines.Text, '@\s*(?:\w+\.)*' + Esc + '\b', [roIgnoreCase]);
end;
{ True when a later plain field line in the class (before ALast) names a field that the fixer will decline
  (var/out argument or Inc / Dec / @ target): it would stay a field AFTER the earlier converted properties, which
  Delphi rejects (E2169). }
function DcLaterSiblingStaysField(ALines: TStringList; AFrom, ALast: Integer): Boolean;
var
  I: Integer;
  M: TMatch;
begin
  Result:= False;
  for I:= AFrom to ALast - 1 do
  begin
    M:= TRegEx.Match(ALines[I - 1], '^\s*(\w+)\s*:\s*[^\s;=\[\(]+\s*;\s*$');
    if M.Success and (DcFieldPassedAsVarArg(ALines, M.Groups[1].Value) or DcFieldUsedAsVariable(ALines, M.Groups[1].Value)) then Exit(True);
  end;
end;

{ public-field: `X: T;` in a public section -> a same-named property `property X: T read FX write FX;` plus a
  private `FX: T;` (in the class's first `private` section, else in a new `private` section opened just above the
  `public` line). Same name, so no call site changes. Declines for anything but a lone, comment-free `X: T;` with a
  whitespace-free type, when `FX` already exists in the class, when the section is not a plain `public`, or (decline
  reason "passed as var/out") when the same file passes the field -- bare or as `Obj.X` -- as an argument at a var/out
  parameter position of a routine declared in that file: a property cannot be a var/out argument, so the fix would stop
  that call compiling. Registered RISKY: a var/out use in another unit is invisible to this per-file fixer. }
function FixPublicField(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line, Name, TypeText, Ind: string;
  M                        : TMatch;
  I, ClassFirst, ClassLast, PubLine, PrivLine, ClassInd: Integer;
  E, EProp                 : TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine <> AFinding.EndLine) or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  if (AFinding.StartCol < 1) or (AFinding.EndCol > Length(Line) + 1) then Exit;
  Name:= Copy(Line, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
  if DcFieldPassedAsVarArg(ALines, Name) then Exit;   { decline: passed as var/out }
  if DcFieldUsedAsVariable(ALines, Name) then Exit;   { decline: Inc / Dec / @ target }
  M:= TRegEx.Match(Line, '^(\s*)' + TRegEx.Escape(Name) + '\s*:\s*([^\s;=\[\(]+)\s*;\s*$', [roIgnoreCase]);
  if not M.Success or (Length(M.Groups[1].Value) <> AFinding.StartCol - 1) then Exit;
  Ind:= M.Groups[1].Value;
  TypeText:= M.Groups[2].Value;
  ClassFirst:= 0;
  PubLine:= 0;
  for I:= AFinding.StartLine - 1 downto 1 do
  begin
    if (PubLine = 0) and TRegEx.IsMatch(ALines[I - 1], DECL_VISIBILITY, [roIgnoreCase]) then
    begin
      M:= TRegEx.Match(ALines[I - 1], DECL_VISIBILITY, [roIgnoreCase]);
      if (M.Groups[1].Value <> '') or not SameText(M.Groups[2].Value, 'public') then Exit;
      PubLine:= I;
    end;
    if TRegEx.IsMatch(ALines[I - 1], DECL_CLASS_START, [roIgnoreCase]) then
    begin
      ClassFirst:= I;
      Break;
    end;
  end;
  if (ClassFirst = 0) or (PubLine = 0) then Exit;
  ClassInd:= DcIndentOf(ALines[ClassFirst - 1]);
  ClassLast:= 0;
  for I:= AFinding.StartLine + 1 to ALines.Count do
    if (DcIndentOf(ALines[I - 1]) = ClassInd) and TRegEx.IsMatch(ALines[I - 1], '^\s*end\s*;', [roIgnoreCase]) then
    begin
      ClassLast:= I;
      Break;
    end;
  if ClassLast = 0 then Exit;
  if DcLaterSiblingStaysField(ALines, AFinding.StartLine + 1, ClassLast) then Exit;   { decline: a sibling stays a field }
  PrivLine:= 0;
  for I:= ClassFirst to ClassLast do
  begin
    if TRegEx.IsMatch(ALines[I - 1], '\bF' + TRegEx.Escape(Name) + '\b', [roIgnoreCase]) then Exit;
    { only a private section ABOVE the public one: a property may not read a field declared after it }
    if (PrivLine = 0) and (I < PubLine) and TRegEx.IsMatch(ALines[I - 1], '^\s*(?:strict\s+)?private\s*$', [roIgnoreCase]) then PrivLine:= I;
  end;
  EProp:= DcNewEdit(AFinding, tekReplaceLines, AFinding.StartLine);
  EProp.EndLine   := AFinding.StartLine;
  EProp.ExpectText:= Line;
  EProp.Text      := Ind + 'property ' + Name + ': ' + TypeText + ' read F' + Name + ' write F' + Name + ';';
  if PrivLine > 0 then
  begin
    E:= DcNewEdit(AFinding, tekInsertLines, PrivLine);
    E.ExpectLine:= PrivLine;
    E.ExpectText:= 'private';
    E.Text      := Copy(ALines[PrivLine - 1], 1, DcIndentOf(ALines[PrivLine - 1])) + StringOfChar(' ', DECL_INDENT_STEP) +
      'F' + Name + ': ' + TypeText + ';';
  end
  else
  begin
    E:= DcNewEdit(AFinding, tekInsertLines, PubLine - 1);
    E.ExpectLine:= PubLine;
    E.ExpectText:= 'public';
    E.Text      := Copy(ALines[PubLine - 1], 1, DcIndentOf(ALines[PubLine - 1])) + 'private' + sLineBreak +
      Copy(ALines[PubLine - 1], 1, DcIndentOf(ALines[PubLine - 1])) + StringOfChar(' ', DECL_INDENT_STEP) +
      'F' + Name + ': ' + TypeText + ';';
  end;
  Result:= [EProp, E];
end;

{ ------------------------------------------------------------ destructor-without-override }

{ destructor-without-override: `destructor Destroy;` -> `destructor Destroy; override;`. Declines when the
  declaration carries any other directive or is not the plain one-line Destroy. }
function FixDestructorWithoutOverride(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line, Span: string;
  E         : TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine <> AFinding.EndLine) or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  if (AFinding.StartCol < 1) or (AFinding.EndCol > Length(Line) + 1) then Exit;
  Span:= Copy(Line, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
  if not TRegEx.IsMatch(Span, '^destructor\s+Destroy\s*;$', [roIgnoreCase]) then Exit;
  E:= DcNewEdit(AFinding, tekReplaceInLine, AFinding.StartLine);
  E.Col       := AFinding.StartCol;
  E.EndCol    := AFinding.EndCol;
  E.ExpectText:= Span;
  E.Text      := Span + ' override;';
  Result:= [E];
end;

{ ------------------------------------------------------- missing-inherited-dtor / ctor }

{ Common lookup: the routine opening at the finding, its header end and its body range, when the keyword on the
  finding's line is AKeyword. }
function DcLocateBody(const AFinding: TLintFinding; ALines: TStringList; const AKeyword: string;
  out AQName: string; out AHeader: string; out ABegin, AEnd: Integer): Boolean;
var
  Kind, Head       : string;
  SemiLine, SemiCol: Integer;
begin
  Result:= False;
  AQName:= '';
  AHeader:= '';
  ABegin:= 0;
  AEnd:= 0;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  if not DcParseHead(ALines[AFinding.StartLine - 1], Kind, AQName) or (Kind <> AKeyword) then Exit;
  if not DcHeaderEnd(ALines, AFinding.StartLine, SemiLine, SemiCol) then Exit;
  if not DcBodyRange(ALines, AFinding.StartLine, SemiLine, ABegin, AEnd) then Exit;
  Head:= DcHeaderText(ALines, AFinding.StartLine, SemiLine);
  AHeader:= Head;
  Result:= TRegEx.IsMatch(ALines[ABegin - 1], '^\s*begin\s*(//.*|\{[^}]*\})?\s*$', [roIgnoreCase]);
end;

{ missing-inherited-dtor: insert `inherited;` as the last statement of `destructor ...Destroy`. Declines when the
  previous statement is not ';'-terminated (the insert would not parse). }
function FixMissingInheritedDtor(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  QName, Header: string;
  BodyBegin, BodyEnd, Prev: Integer;
  E            : TTextEdit;
begin
  Result:= nil;
  if not DcLocateBody(AFinding, ALines, 'destructor', QName, Header, BodyBegin, BodyEnd) then Exit;
  if not SameText(Copy(QName, LastDelimiter('.', QName) + 1, MaxInt), 'Destroy') then Exit;
  Prev:= BodyEnd - 1;
  while (Prev > BodyBegin) and (Trim(ALines[Prev - 1]) = '') do Dec(Prev);
  if (Prev > BodyBegin) and not TRegEx.IsMatch(ALines[Prev - 1], DECL_STMT_END) then Exit;
  E:= DcNewEdit(AFinding, tekInsertLines, Prev);
  E.ExpectLine:= BodyEnd;
  E.ExpectText:= 'end';
  E.Text      := StringOfChar(' ', DcIndentOf(ALines[BodyEnd - 1]) + DECL_INDENT_STEP) + 'inherited;';
  Result:= [E];
end;

{ missing-inherited-ctor: insert `inherited;` as the first statement of a PARAMETERLESS constructor (a guess at
  an ancestor signature is never made). Declines for any parameter list. }
function FixMissingInheritedCtor(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  QName, Header: string;
  BodyBegin, BodyEnd: Integer;
  E            : TTextEdit;
begin
  Result:= nil;
  if not DcLocateBody(AFinding, ALines, 'constructor', QName, Header, BodyBegin, BodyEnd) then Exit;
  if Header.Contains('(') then Exit;
  E:= DcNewEdit(AFinding, tekInsertLines, BodyBegin);
  E.ExpectLine:= BodyBegin;
  E.ExpectText:= 'begin';
  E.Text      := StringOfChar(' ', DcIndentOf(ALines[BodyBegin - 1]) + DECL_INDENT_STEP) + 'inherited;';
  Result:= [E];
end;

{ ------------------------------------------------------------- method-could-be-static }

{ Edit that turns the routine keyword on ALine into `class <keyword>`. }
function DcClassPrefixEdit(const AFinding: TLintFinding; ALines: TStringList; ALine: Integer; out AEdit: TTextEdit): Boolean;
var
  M: TMatch;
begin
  AEdit:= Default(TTextEdit);
  M:= TRegEx.Match(ALines[ALine - 1], DECL_ROUTINE_HEAD, [roIgnoreCase]);
  Result:= M.Success and not StartsText('class', Trim(ALines[ALine - 1]));
  if not Result then Exit;
  AEdit:= DcNewEdit(AFinding, tekReplaceInLine, ALine);
  AEdit.Col       := M.Groups[1].Index;
  AEdit.EndCol    := M.Groups[1].Index + M.Groups[1].Length;
  AEdit.ExpectText:= M.Groups[1].Value;
  AEdit.Text      := 'class ' + M.Groups[1].Value;
end;

{ True when the declaration at ADeclLine sits in a section that is not published / automated (a published method
  is reachable through RTTI, so a static one could break a streamed reference). }
function DcSectionIsSafe(ALines: TStringList; ADeclLine: Integer): Boolean;
var
  I: Integer;
  M: TMatch;
begin
  Result:= False;
  for I:= ADeclLine - 1 downto 1 do
  begin
    M:= TRegEx.Match(ALines[I - 1], DECL_VISIBILITY, [roIgnoreCase]);
    if M.Success then Exit(not MatchText(M.Groups[2].Value, ['published', 'automated']));
    if TRegEx.IsMatch(ALines[I - 1], DECL_CLASS_START, [roIgnoreCase]) then Exit;
  end;
end;

{ method-could-be-static: `class <kw>` on the implementation header and on the declaration, plus `static;` after
  the declaration's header. Declines for an overloaded or unpaired method, a declaration with virtual / override /
  dynamic / message / abstract / reintroduce, and a published or unclassified section. A method reference to the
  result breaks visibly at compile time -- hence the risky tag. }
function FixMethodCouldBeStatic(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Kind, QName, Tail: string;
  K, DeclLine, SemiLine, SemiCol, I: Integer;
  EImpl, EDecl, ESemi               : TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  K:= DcHeaderKeywordLine(ALines, AFinding.StartLine);
  if (K = 0) or not DcParseHead(ALines[K - 1], Kind, QName) or (not QName.Contains('.')) then Exit;
  if (Kind <> 'function') and (Kind <> 'procedure') then Exit;
  if DcLookupDecl(ALines, K, QName, DeclLine) <> dlFound then Exit;
  if not DcSectionIsSafe(ALines, DeclLine) then Exit;
  if not DcHeaderEnd(ALines, DeclLine, SemiLine, SemiCol) then Exit;
  Tail:= '';
  for I:= DeclLine to DcDirectivesLast(ALines, SemiLine) do Tail:= Tail + ' ' + ALines[I - 1];
  if TRegEx.IsMatch(Tail, DECL_BAD_STATIC, [roIgnoreCase]) then Exit;
  if not DcClassPrefixEdit(AFinding, ALines, K, EImpl) then Exit;
  if not DcClassPrefixEdit(AFinding, ALines, DeclLine, EDecl) then Exit;
  ESemi:= DcNewEdit(AFinding, tekReplaceInLine, SemiLine);
  ESemi.Col       := SemiCol;
  ESemi.EndCol    := SemiCol + 1;
  ESemi.ExpectText:= ';';
  ESemi.Text      := '; static;';
  Result:= [EImpl, EDecl, ESemi];
end;

initialization
  RegisterFixer('inherited-bare', FixInheritedBare);
  RegisterFixer('inline-on-large-routine', FixInlineOnLargeRoutine);
  RegisterFixer('missing-const-param', FixMissingConstParam);
  RegisterFixer('public-field', FixPublicField, True);
  RegisterFixer('destructor-without-override', FixDestructorWithoutOverride, True);
  RegisterFixer('missing-inherited-dtor', FixMissingInheritedDtor, True);
  RegisterFixer('missing-inherited-ctor', FixMissingInheritedCtor, True);
  RegisterFixer('method-could-be-static', FixMethodCouldBeStatic, True);

end.
