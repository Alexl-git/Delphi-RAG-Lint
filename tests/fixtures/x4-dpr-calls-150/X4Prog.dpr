program X4Prog;

uses
  uX4Unit in 'uX4Unit.pas';

{ X4 (wave 150) fixture: calls to routines DECLARED IN THE .dpr ITSELF must
  resolve, and the program root is an entry point, never dead.
  X4ProgDead is the positive control: declared in the .dpr, never called. }

procedure X4ProgLocal;
begin
end;

function X4ProgHelper(A: Integer): Integer;
begin
  X4ProgLocal;
  Result:= A + 1;
end;

procedure X4ProgDead;
begin
end;

begin
  X4ProgHelper(X4UnitTwice(1));
end.