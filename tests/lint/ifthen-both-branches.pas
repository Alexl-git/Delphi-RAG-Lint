unit IfThenBoth;

interface

implementation

uses SysUtils;

function Expensive: Integer;
begin
  Result := 42;
end;

procedure Bad;
var
  B: Boolean;
  N: Integer;
begin
  N := IfThen(B, Expensive, 0);
  N := IfThen(B, 1, Expensive);
end;

procedure Good;
var
  B: Boolean;
  N: Integer;
begin
  if B then
    N := Expensive
  else
    N := 0;
end;

end.
