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

// Task 9b: both branches are literals -- a literal cannot have a side
// effect, so the rule's rationale is inapplicable (YADF.Options.pas:850,879).
procedure GoodBothLiteral;
var
  B: Boolean;
  S: string;
begin
  S := IfThen(B, 'true', 'false');
end;

end.
