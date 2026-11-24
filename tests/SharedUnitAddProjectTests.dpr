program SharedUnitAddProjectTests;
{$APPTYPE CONSOLE}
{ v154 FLOW: TSharedUnit.AddProject read the unit into ANewText and then passed ANewText as both the const AText and the out ANewText of
  AddProjectToText, so the out parameter emptied the very text being edited. Run by tests\autotest\run_shared_unit_addproject.ps1. }
uses
  System.SysUtils,
  Winapi.Windows,
  System.IOUtils,
  DRagLint.Lint.SharedUnit;

var
  GFailed: Integer = 0;

procedure Check(const AName: string; AOk: Boolean);
begin
  if AOk then Writeln('  [PASS] ', AName)
  else
  begin
    Inc(GFailed);
    Writeln('  [FAIL] ', AName);
  end;
end;

var
  Path, NewText: string;
begin
  Path:= TPath.Combine(TPath.GetTempPath, 'SharedUnitAddProject-' + IntToStr(GetCurrentProcessId) + '.pas');
  TFile.WriteAllText(Path, 'unit U;' + #13#10 + 'interface' + #13#10 + 'implementation' + #13#10 + 'end.' + #13#10);
  try
    Check('AddProject marks the unit', TSharedUnit.AddProject(Path, 'YADF', NewText));
    Check('the new text keeps the unit', Pos('unit U;', NewText) = 1);
    Check('the new text carries the marker and project', (Pos('dl:shared', NewText) > 0) and (Pos('YADF', NewText) > 0));
  finally
    TFile.Delete(Path);
  end;
  if GFailed > 0 then
  begin
    Writeln('FAILED: ', GFailed);
    Halt(1);
  end;
  Writeln('ALL PASSED');
end.
