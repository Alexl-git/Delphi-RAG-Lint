unit FoUnit;

interface

procedure RunAll;

implementation

var
  GCalls: Integer;

{ the repeat in the middle of a chain: the rest of the chain becomes the else }
function Classify(A: Integer): Integer;
var
  X: Integer;
begin
  X:= A * 2;
  if X = 2 then Result:= 1
  else if A > 5 then Result:= 2
  else Result:= 4;
end;

{ the repeat ends the chain: the chain loses its last else }
function Tail(const S: string): Integer;
begin
  Result:= 0;
  if S = 'a' then Result:= 1;
end;

function Next: Boolean;
begin
  Inc(GCalls);
  Result:= Odd(GCalls);
end;

{ declined: Next runs code, so its second answer may differ }
function Declined: Integer;
begin
  Result:= 0;
  if Next then Result:= 1
  else if Next then Result:= 2;
end;

procedure RunAll;
begin
  WriteLn(Classify(1), Tail('a'), Declined);
end;

end.
