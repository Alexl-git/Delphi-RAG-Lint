unit DRagLint.Fix.Templates;

{ The GENERIC sidecar fixer (autofix wave A0, 2026-10-27). A .scm rule whose
  rules\<id>.json carries a "fix" key gets its fix with no Pascal at all: the
  loader (TQueryRule.AttachFix) expands the template onto the finding
  (TLintFinding.FixKind / FixText / FixUses) and this unit turns that into
  guarded text edits. Grammar of the key: TSidecarFix in
  DRagLint.Lint.QueryRules (the rules\README.md "Sidecar fixes" section is added at integration). }

interface

implementation

uses
  System.SysUtils
  , System.Classes
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  ;

{ ---- redundant parentheses around an atomic replacement ---- }

const
  { words after which a '(' opens a grouping, never a call's argument list }
  GROUPING_WORDS = '|if|while|until|not|and|or|xor|then|else|do|of|in|to|downto|case|with|';

{ True when AText is ONE call expression `Name(...)` whose first '(' closes at the very last
  character (so wrapping it in parentheses adds nothing). }
function IsAtomicCall(const AText: string): Boolean;
var
  I    : Integer;
  Depth: Integer;
  Open : Integer;
begin
  Result:= False;
  Open:= Pos('(', AText);
  if (Open < 2) or (AText[Length(AText)] <> ')') then Exit;
  for I:= 1 to Open - 1 do
    if not (CharInSet(AText[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.'])) then Exit;
  Depth:= 0;
  for I:= Open to Length(AText) do
  begin
    if AText[I] = '''' then Exit;   { a string literal: do not guess where its parentheses are }
    if AText[I] = '(' then Inc(Depth)
    else if AText[I] = ')' then
    begin
      Dec(Depth);
      if (Depth = 0) and (I < Length(AText)) then Exit;
    end;
  end;
  Result:= Depth = 0;
end;

{ True when the '(' at ALine[AOpen] groups an expression (so it may go) rather than opening a call's
  argument list, an indexer or a typecast (so it must stay). }
function OpensGrouping(const ALine: string; AOpen: Integer): Boolean;
var
  P, Q: Integer;
begin
  P:= AOpen - 1;
  while (P >= 1) and (ALine[P] = ' ') do Dec(P);
  if P < 1 then Exit(True);
  if CharInSet(ALine[P], [')', ']', '^', '@', '''']) then Exit(False);
  if not CharInSet(ALine[P], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit(True);
  Q:= P;
  while (Q > 1) and CharInSet(ALine[Q - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Dec(Q);
  Result:= GROUPING_WORDS.Contains('|' + LowerCase(Copy(ALine, Q, P - Q + 1)) + '|');
end;
{ True when the span [AStart, AEnd) of ALine sits exactly inside a grouping pair of its own. }
function IsGroupedSpan(const ALine: string; AStart, AEnd: Integer): Boolean;
begin
  Result:= (AStart > 1) and (AEnd <= Length(ALine)) and (ALine[AStart - 1] = '(') and (ALine[AEnd] = ')') and
    OpensGrouping(ALine, AStart - 1);
end;

{ The edits for one finding that carries a sidecar fix: one edit, or none when
  the span is not in the file (a stale finding) or the fix cannot be placed
  safely. A single-line span with single-line replacement text becomes a
  tekReplaceInLine guarded by the span's own text; anything that spans lines
  becomes a tekReplaceLines over StartLine..EndLine guarded by the first line.
  lfkDeleteStatement goes through Autofix.DeleteStatement. Pure. Lane A1 adds
  only rules\*.json "fix" keys -- never Pascal here. }
function BuildSidecarFixEdits(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  E      : TTextEdit;
  First  : string   ;
  Last   : string   ;
  NewText: string   ;
begin
  Result:= nil;
  if AFinding.FixKind = lfkNone then Exit;
  if AFinding.FixKind = lfkDeleteStatement then
  begin
    if DeleteStatement(AFinding, ALines, E) then Result:= [E];
    Exit;
  end;
  if (AFinding.StartLine < 1) or (AFinding.EndLine < AFinding.StartLine) or (AFinding.EndLine > ALines.Count) then Exit;
  First:= ALines[AFinding.StartLine - 1];
  Last := ALines[AFinding.EndLine - 1];
  if (AFinding.StartCol < 1) or (AFinding.StartCol > Length(First) + 1) or
     (AFinding.EndCol < 1) or (AFinding.EndCol > Length(Last) + 1) then Exit;
  NewText:= if AFinding.FixKind = lfkReplace then AFinding.FixText else '';
  NewText:= NewText.Replace(#13#10, #10).Replace(#10, sLineBreak);
  E:= Default(TTextEdit);
  E.FilePath:= AFinding.FilePath;
  if (AFinding.StartLine = AFinding.EndLine) and (not NewText.Contains(#10)) then
  begin
    if AFinding.EndCol <= AFinding.StartCol then Exit;   { zero-width span: nothing to guard }
    E.Kind      := tekReplaceInLine;
    E.Line      := AFinding.StartLine;
    E.Col       := AFinding.StartCol;
    E.EndCol    := AFinding.EndCol;
    E.Text      := NewText;
    E.ExpectText:= Copy(First, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
    { the replacement is one call and the span sat in a grouping pair of its own: the pair is now redundant }
    if (AFinding.FixKind = lfkReplace) and IsGroupedSpan(First, AFinding.StartCol, AFinding.EndCol) and IsAtomicCall(NewText) then
    begin
      E.Col       := AFinding.StartCol - 1;
      E.EndCol    := AFinding.EndCol + 1;
      E.ExpectText:= Copy(First, E.Col, E.EndCol - E.Col);
    end;
  end
  else
  begin
    E.Kind      := tekReplaceLines;
    E.Line      := AFinding.StartLine;
    E.EndLine   := AFinding.EndLine;
    E.Text      := Copy(First, 1, AFinding.StartCol - 1) + NewText + Copy(Last, AFinding.EndCol, MaxInt);
    E.ExpectText:= First;
  end;
  Result:= [E];
end;

initialization
  RegisterSidecarFixer(BuildSidecarFixEdits);

end.