program NameSynthHarness;
{$APPTYPE CONSOLE}
uses System.SysUtils, DRagLint.Refactor.NamingFix;
begin
  // args: <oldName> <configCaseText>
  Writeln(SynthesizeCasedName(ParamStr(1), StyleFromConfigText(ParamStr(2))));
end.
