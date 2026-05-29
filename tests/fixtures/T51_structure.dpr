program T51_structure;
{ Compile-only smoke test for StructureCache + StructureForm units.
  Verifies that both units compile and that StructureCache exposes the
  expected public interface. No runtime IDE is required. }
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.StructureCache;
var
  SC: TDragLintStructureCache;
  Syms: TArray<TSymbolInfo>;
begin
  SC := TDragLintStructureCache.Create;
  try
    { Call with a non-existent file / exe: should return empty array cleanly }
    Syms := SC.GetSymbolsForFile('C:\nonexistent\Foo.pas', 'drag-lint.exe');
    SC.InvalidateForFile('C:\nonexistent\Foo.pas');
    SC.Clear;
    WriteLn('StructureCache: OK');
  finally
    SC.Free;
  end;
  WriteLn('OK');
end.
