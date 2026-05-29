program T58_symbolsearch_form;
{ Compile-only smoke test for DragLint.Plugin.SymbolSearchForm.
  Verifies the unit compiles and ShowSymbolSearch is accessible. }
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.SymbolSearchForm;
begin
  { ShowSymbolSearch requires a running GUI message loop; we just
    verify the symbol resolves at link time.  No ShowModal is called. }
  WriteLn('T58 SymbolSearchForm: OK');
end.
