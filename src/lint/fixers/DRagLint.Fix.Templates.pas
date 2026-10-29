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