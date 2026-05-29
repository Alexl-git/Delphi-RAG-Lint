program T47_regcolors;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  Vcl.Graphics,
  DragLint.Plugin.RegistryColors;
var
  C: TDragLintColors;
begin
  C := LoadEditorColors;
  { Colors are machine-dependent; just verify we get non-zero integers back
    (the defaults clRed etc. are all non-zero). }
  Assert(Integer(C.ErrorColor)   <> 0, 'ErrorColor non-zero');
  Assert(Integer(C.WarningColor) <> 0, 'WarningColor non-zero');
  Assert(Integer(C.HintColor)    <> 0, 'HintColor non-zero');
  Assert(Integer(C.InfoColor)    <> 0, 'InfoColor non-zero');
  WriteLn(Format('Error=%d Warning=%d Hint=%d Info=%d',
    [Integer(C.ErrorColor), Integer(C.WarningColor),
     Integer(C.HintColor),  Integer(C.InfoColor)]));
  WriteLn('OK');
end.
