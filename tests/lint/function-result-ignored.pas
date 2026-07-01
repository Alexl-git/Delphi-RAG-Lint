unit fri;
interface
implementation

function Compute(X: Integer): Integer;
begin
  Result := X * 2;
end;

procedure DoStuff(X: Integer);
begin
end;

procedure P;
var Y: Integer;
begin
  Compute(5);
  Y := Compute(5);
  DoStuff(5);
  if Compute(5) > 0 then Y := 1;
end;
end.
