unit unused_loop_variable;

{ Fixture for unused-loop-variable (OFF by default, hint).
  Hit: for I := a to/downto b do <body> where I is not referenced in the body.
  Silent: a body that uses I, a for-in loop. }

interface

procedure Demo;

implementation

procedure Demo;
var
  I, N: Integer;
  L: TArray<Integer>;
  V: Integer;
begin
  for I:= 1 to 3 do
    Writeln('x');
  for I:= 3 downto 1 do
  begin
    Inc(N);
  end;
  for I:= 1 to 3 do
    Writeln(I);
  for V in L do
    Inc(N);
end;

end.
