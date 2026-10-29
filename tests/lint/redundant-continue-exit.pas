unit RedundantContinueExit;

interface

implementation

procedure Hit1(N: Integer);
var
  I: Integer;
begin
  for I := 0 to N do
  begin
    WriteLn(I);
    Continue; // HIT
  end;
end;

procedure Hit2;
begin
  WriteLn('x');
  Exit; // HIT
end;

function Hit3: Integer;
begin
  Result := 1;
  Exit; // HIT
end;

procedure NoHit1(N: Integer);
var
  I: Integer;
begin
  { FP shape: Continue guarded by a condition is not the last statement }
  for I := 0 to N do
  begin
    if I = 2 then Continue;
    WriteLn(I);
  end;
end;

procedure NoHit2(Flag: Boolean);
begin
  { FP shape: Exit before more code }
  if Flag then Exit;
  WriteLn('x');
end;

function NoHit3: Integer;
begin
  { FP shape: Exit(Value) carries the result }
  Exit(5);
end;

procedure NoHit4;
begin
  { FP shape: Exit as the last statement of a try block is not the routine tail (finally runs after it) }
  try
    WriteLn('x');
    Exit;
  finally
    WriteLn('y');
  end;
end;

end.
