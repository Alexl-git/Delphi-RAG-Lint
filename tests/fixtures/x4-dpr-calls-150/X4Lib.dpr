library X4Lib;

uses
  uX4Unit in 'uX4Unit.pas';

{ X4 (wave 150) fixture: the library body calls a routine declared in the
  .dpr itself; the library root is an entry point, never dead.
  X4LibDead is the positive control: declared in the .dpr, never called. }

function X4LibAdd(A, B: Integer): Integer; stdcall;
begin
  Result:= A + B;
end;

procedure X4LibDead;
begin
end;

exports
  X4LibAdd name 'x4_lib_add';

begin
  X4LibAdd(1, 2);
end.