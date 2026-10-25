program EncodingHarness;
{ F8 (2026-10-25): drives the two shared write helpers that re-encode a whole
  file -- TTextEditApplier.Apply (lint --fix, cycles --fix, convert-apply) and
  PrependConvertComment (the convert-apply stamp) -- on a file the caller
  wrote, so run_textedit_encoding.ps1 can compare the bytes on disk.
    EncodingHarness edit  <file>   insert the 3 chars "(x)" with braces at L1:C1, insert one line
                                   holding U+00EF after line 2
    EncodingHarness stamp <file>   prepend the provenance comment }
{$APPTYPE CONSOLE}
uses System.SysUtils, DRagLint.Refactor.TextEdit, DRagLint.Convert.Backup;
var
  E1, E2: TTextEdit;
begin
  if ParamStr(1) = 'edit' then
  begin
    E1:= Default(TTextEdit); E1.FilePath:= ParamStr(2); E1.Kind:= tekInsertInLine; E1.Line:= 1; E1.Col:= 1; E1.Text:= '{x}';
    E2:= Default(TTextEdit); E2.FilePath:= ParamStr(2); E2.Kind:= tekInsertLines; E2.Line:= 2; E2.Text:= '// na' + #$00EF + 've';
    Writeln(TTextEditApplier.Apply([E1, E2], False));
  end
  else if ParamStr(1) = 'stamp' then
    PrependConvertComment(ParamStr(2), 'TS', 'r.rules', ['a.pas -> a.pas.BCK1'])
  else
    ExitCode:= 2;
end.
