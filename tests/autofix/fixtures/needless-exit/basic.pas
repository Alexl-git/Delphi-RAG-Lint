unit basic;

interface

procedure HitProc;
function HitResult: Integer;
procedure KeepBranch(A: Integer);

implementation

procedure HitProc;
begin
  Writeln('x');
  Exit;
end;

function HitResult: Integer;
begin
  Result:= 1;
  Exit(Result);
end;

procedure KeepBranch(A: Integer);
begin
  if A > 0 then
    Exit;
  Writeln('y');
end;

end.