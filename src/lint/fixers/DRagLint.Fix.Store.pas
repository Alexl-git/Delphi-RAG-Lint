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
  (the bare call line), doc-orphan-block (the orphan BEGIN..END block). The
  other A5 ids are not fixable yet (lane report).

  The unit registers itself from its OWN initialization; DRagLint.Lint.Autofix
  never uses a fixer unit, so no unit cycle forms. }

interface

implementation

uses
  System.SysUtils, System.Classes, System.RegularExpressions,
  DRagLint.Core.Model, DRagLint.Refactor.TextEdit, DRagLint.Lint.Autofix;

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

{ Delete AFirst..ALast as edits of which one STARTS on AAnchor (the finding's
  line): the --fix JSON reports a finding as applied only when an edit begins
  on its StartLine, so lines above the anchor go in a second edit. }
function DeleteAround(const APath: string; AFirst, AAnchor, ALast: Integer): TArray<TTextEdit>;
begin
  Result:= [DeleteLines(APath, AAnchor, ALast)];
  if AFirst < AAnchor then Result:= Result + [DeleteLines(APath, AFirst, AAnchor - 1)];
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
  HeaderRx:= '^' + CRoutineKw + '\s+(?:[A-Za-z_]\w*\.)*' + AType + '\.' + AName + '\s*[(:;]';
  Hits:= 0;
  for var I:= 1 to ALines.Count do
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
      Result:= DeleteAround(AFinding.FilePath, DocRunStart(ALines, AFinding.StartLine), AFinding.StartLine, AFinding.StartLine);
    Exit;
  end;
  if not IsDeletableMethodDecl(Line, Name) then Exit;
  TypeName:= EnclosingTypeName(ALines, AFinding.StartLine);
  if (TypeName = '') or not FindBody(ALines, TypeName, Name, First, Last) then Exit;
  { one blank line after the body goes with it, so no double gap is left }
  if (Last < ALines.Count) and (Trim(ALines[Last]) = '') then Inc(Last);
  Result:= DeleteAround(AFinding.FilePath, DocRunStart(ALines, AFinding.StartLine), AFinding.StartLine, AFinding.StartLine)
    + [DeleteLines(AFinding.FilePath, DocRunStart(ALines, First), Last)];
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
  Result:= DeleteAround(AFinding.FilePath, First, AFinding.StartLine, Last);
end;

initialization
  RegisterFixer('unused-private-member', FixUnusedPrivateMember);
  RegisterFixer('discarded-effect-free-result', FixDiscardedEffectFree);
  RegisterFixer('doc-orphan-block', FixDocOrphanBlock);

end.
