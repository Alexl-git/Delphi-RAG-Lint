program T52_options;
{ Compile-only smoke test for OptionsFrame + Options units.
  Verifies that both units compile cleanly. No runtime IDE is required;
  the INTAAddInOptions and TFrame types are available via ToolsAPI +
  VCL at compile time. }
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.OptionsFrame,
  DragLint.Plugin.Options;
begin
  { Nothing to instantiate at runtime without a real IDE host.
    Successful compilation is the test. }
  WriteLn('OptionsFrame: compiled OK');
  WriteLn('Options:      compiled OK');
  WriteLn('OK');
end.
