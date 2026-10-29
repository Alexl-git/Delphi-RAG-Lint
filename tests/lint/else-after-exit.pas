unit ElseAfterExit;

interface

implementation

procedure Hit1(Flag: Boolean);
begin
  if Flag then
    Exit
  else // HIT
    WriteLn('x');
end;

procedure Hit2(N: Integer);
var
  I: Integer;
begin
  for I := 0 to N do
  begin
    if I = 3 then
    begin
      WriteLn('three');
      Continue;
    end
    else // HIT
      WriteLn(I);
  end;
end;

procedure Hit3(Flag: Boolean);
begin
  if Flag then
    raise Exception.Create('x')
  else // HIT
    WriteLn('ok');
end;

procedure NoHit1(Flag: Boolean);
begin
  { FP shape: no exit in the then branch }
  if Flag then
    WriteLn('a')
  else
    WriteLn('b');
end;

procedure NoHit2(Flag, Other: Boolean);
begin
  { FP shape: the exit is conditional inside the then branch }
  if Flag then
  begin
    if Other then Exit;
  end
  else
    WriteLn('b');
end;

procedure NoHit3(Flag: Boolean);
begin
  { FP shape: no else at all }
  if Flag then
    Exit;
  WriteLn('x');
end;

end.
