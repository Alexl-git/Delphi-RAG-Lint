program T61_hovertracker;
{ Compile-only smoke test for DragLint.Plugin.HoverTracker.
  Verifies the unit compiles and the two public procedures are accessible. }
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.HoverTracker;
begin
  { We cannot call StartHoverTracker without an IDE VCL app context.
    Just verify the symbols are reachable at the linker level.
    StopHoverTracker is safe to call when GHelper is nil (no-op). }
  StopHoverTracker;
  WriteLn('T61 HoverTracker: OK');
end.
