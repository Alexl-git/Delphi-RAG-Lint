unit DivisionByZeroConstClean;
{ look-alikes that must stay quiet: a non-zero constant, a name that is a zero
  constant in one place and a variable in another, and integer div / mod by a
  zero constant (the compiler already rejects those, E2098). }
interface
function Scale(pA: Double; pStep: Double): Double;
function Halve(pA: Integer): Integer;
implementation
const
  HALF = 2;
  STEP = 0;
  GAP = 0;
function Scale(pA: Double; pStep: Double): Double;
var
  GAP: Double;
begin
  GAP := pStep + 1;
  Result := pA / HALF + pA / GAP;
end;
function Halve(pA: Integer): Integer;
begin
  Result := pA div HALF + pA div STEP + pA mod STEP;
end;
end.
