unit VarFix;

// variant-in-loop (G-30)

interface

implementation

procedure Sum(N: Integer);
var
  V: Variant;
  I: Integer;
begin
  V:= 0;
  for I:= 1 to N do
    V:= V + I;  // FIRE variant-in-loop
end;

procedure Param(Q: OleVariant; N: Integer);
var
  I: Integer;
begin
  I:= N;
  while I > 0 do
  begin
    Dec(I);
    Q:= Q * 2;  // FIRE variant-in-loop
  end;
end;

function Fn(N: Integer): Variant;
var
  I: Integer;
begin
  Result:= 0;
  I:= 0;
  repeat
    Inc(I);
    Result:= Result + I;  // FIRE variant-in-loop
  until I >= N;
end;

procedure Inline(const A: array of Integer);
begin
  var V: Variant:= 0;
  for var X in A do
    V:= V - X;  // FIRE variant-in-loop
end;

procedure IntegerLoop(N: Integer);
var
  S, I: Integer;
begin
  S:= 0;
  for I:= 1 to N do
    S:= S + I;
end;

procedure OutsideLoop(N: Integer);
var
  V: Variant;
begin
  V:= 1;
  V:= V + N;
end;

procedure NoArithmetic(N: Integer);
var
  V: Variant;
  I: Integer;
begin
  for I:= 1 to N do
    V:= I;
end;

procedure Unproven(N: Integer);
var
  I: Integer;
begin
  for I:= 1 to N do
    UnknownThing:= UnknownThing + I;
end;

procedure Shadowed(N: Integer);
var
  V: Variant;
  I: Integer;

  procedure Inner;
  var
    V: Integer;
    J: Integer;
  begin
    for J:= 1 to N do
      V:= V + J;
  end;

begin
  I:= N;
  V:= I;
end;

end.
