unit InfiniteLoopNoExit;

interface

implementation

procedure Hit1;
begin
  while True do // HIT
  begin
    Poll;
  end;
end;

procedure Hit2;
begin
  repeat // HIT
    Poll;
  until False;
end;

procedure Hit3;
var
  I: Integer;
begin
  while True do // HIT: the Break leaves only the inner loop
  begin
    for I := 0 to 3 do
      if Check(I) then Break;
  end;
end;

procedure NoHitBreak;
begin
  while True do
  begin
    if Done then Break;
  end;
end;

procedure NoHitExit;
begin
  repeat
    if Done then Exit;
  until False;
end;

procedure NoHitRaise;
begin
  while True do
  begin
    if Bad then raise Exception.Create('x');
  end;
end;

procedure NoHitHalt;
begin
  while True do
  begin
    if Bad then Halt(1);
  end;
end;

procedure NoHitCondition(Flag: Boolean);
begin
  { FP shape: a real loop condition is not an infinite loop }
  while Flag do
    Poll;
end;

procedure NoHitUntil(Flag: Boolean);
begin
  repeat
    Poll;
  until Flag;
end;

end.
