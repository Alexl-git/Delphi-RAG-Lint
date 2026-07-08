program SameLineHarness;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, DRagLint.Refactor.TextEdit;
var
  Edits: TArray<TTextEdit>;
  E1, E2: TTextEdit;
  Path: string;
begin
  // Build a one-line fixture: "  a := b;"  (cols 1-based)
  Path := TPath.Combine(TPath.GetTempPath, 'sameline_fixture.pas');
  TFile.WriteAllText(Path, '  aa := bb;' + sLineBreak, TEncoding.ANSI);
  // Two replaces on line 1, differing lengths: 'aa'->'FIRST' (col 3..5), 'bb'->'X' (col 9..11)
  E1 := Default(TTextEdit); E1.FilePath := Path; E1.Kind := tekReplaceInLine; E1.Line := 1; E1.Col := 3;  E1.EndCol := 5;  E1.Text := 'FIRST';
  E2 := Default(TTextEdit); E2.FilePath := Path; E2.Kind := tekReplaceInLine; E2.Line := 1; E2.Col := 9;  E2.EndCol := 11; E2.Text := 'X';
  Edits := [E1, E2];
  TTextEditApplier.Apply(Edits, False);
  Writeln(Trim(TFile.ReadAllText(Path)));  // expect: FIRST := X;
end.
