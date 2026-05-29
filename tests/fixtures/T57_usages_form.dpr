program T57_usages_form;
{ Compile-only smoke test for DragLint.Plugin.UsagesForm.
  Verifies the unit compiles and the two public procedures are accessible. }
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.UsagesForm;
begin
  { Just verify the public API symbols are reachable.
    We cannot call ShowFindUsages without an IDE; HideFindUsages is safe. }
  HideFindUsages;
  WriteLn('T57 UsagesForm: OK');
end.
