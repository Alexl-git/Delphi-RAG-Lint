unit DivisionByZeroConst;
{ division-by-zero-literal, named-constant shape: a float division by a
  constant of this unit whose value is zero. }
interface
function Ratio(pA: Double): Double;
function RatioTyped(pA: Double): Double;
implementation
const
  NO_SCALE = 0;
  NO_WEIGHT: Double = 0.0;
function Ratio(pA: Double): Double;
begin
  Result := pA / NO_SCALE;
end;
function RatioTyped(pA: Double): Double;
const
  LOCAL_ZERO = 0.0;
begin
  Result := pA / NO_WEIGHT + pA / LOCAL_ZERO;
end;
end.
