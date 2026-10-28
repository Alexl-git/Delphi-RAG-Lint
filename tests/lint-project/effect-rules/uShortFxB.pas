unit uShortFxB;

{$B+}

{ Fixture for `side-effect-in-short-circuit`: complete Boolean evaluation is
  on for this unit, so `and` / `or` evaluate both operands and nothing is
  skipped. The rule must stay silent on the whole file. }

interface

procedure DriverB;

var
  GTick: Integer;

implementation

function Tick: Boolean;
begin
  GTick:= GTick + 1;
  Result:= GTick > 1;
end;

procedure DriverB;
var
  Ok: Boolean;
begin
  Ok:= GTick > 0;
  if Ok and Tick then GTick:= 0;               { SC-CONTROL-9: under B+ }
end;

end.
