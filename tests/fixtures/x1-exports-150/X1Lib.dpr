library X1Lib;

{ X1 (wave 150) fixture: every entry of the exports clause must emit a ref
  bound to the exported routine, so an exported routine is not "unused".
  X1Unused is the positive control: declared, never exported, never called. }

uses
  uX1LibUnit in 'uX1LibUnit.pas';

function X1LibAdd(A, B: Integer): Integer; stdcall;
begin
  Result:= A + B;
end;

exports
  X1LibAdd name 'x1_lib_add',
  X1Twice index 2;

begin
end.