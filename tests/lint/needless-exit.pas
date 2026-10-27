unit needless_exit;

{ Fixture for needless-exit (hint).
  Hit: Exit; as the last statement of a routine body, Exit(Result) as the
  last statement.
  Silent: Exit inside a branch or loop, Exit followed by more code, Exit(Value)
  whose argument is not Result. }

interface

procedure HitProc;
function HitFuncResult: Integer;
function HitFuncResultExit: Integer;
procedure NoHitBranch(A: Integer);
function NoHitValue: Integer;
procedure NoHitMiddle(A: Integer);

implementation

procedure HitProc;
begin
  Writeln('x');
  Exit;
end;

function HitFuncResult: Integer;
begin
  Result:= 1;
  Exit;
end;

function HitFuncResultExit: Integer;
begin
  Result:= 1;
  Exit(Result);
end;

procedure NoHitBranch(A: Integer);
begin
  if A > 0 then
    Exit;
  Writeln('x');
end;

function NoHitValue: Integer;
begin
  Exit(42);
end;

procedure NoHitMiddle(A: Integer);
begin
  Writeln('x');
  Exit;
  Writeln('y');
end;

end.
