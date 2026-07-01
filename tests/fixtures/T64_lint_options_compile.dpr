program T64_lint_options_compile;
{ Compile-only smoke test for LintOptionsFrame.
  Verifies that the unit compiles cleanly against VCL + ToolsAPI +
  ConfigWriter without a running IDE. No runtime is exercised. }
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.LintOptionsFrame;
begin
  { Nothing to instantiate at runtime without a real IDE host.
    Successful compilation is the test. }
  WriteLn('LintOptionsFrame: compiled OK');
  WriteLn('OK');
end.
