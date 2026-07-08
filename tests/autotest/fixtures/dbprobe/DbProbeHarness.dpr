program DbProbeHarness;
{$APPTYPE CONSOLE}
uses System.SysUtils, DRagLint.Plugin.Settings, DRagLint.Plugin.DbProbe;
var
  Settings: TDragLintSettings;
  Chosen  : string;
begin
  // args: <projPath> <dbPathTemplate>
  Settings := Default(TDragLintSettings);
  Settings.DbPathTemplate := ParamStr(2);
  Chosen := PickProjectDb(ParamStr(1), Settings);
  Writeln(Chosen);
end.