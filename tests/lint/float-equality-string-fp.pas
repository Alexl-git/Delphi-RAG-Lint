unit FloatEqualityStringFP;

// v0.65.1 regression: float-equality-comparison must NOT fire when an operand is a
// quoted string/char literal ('+', '-', '-.', '+.'). A quoted literal is never a
// float, even if the flat (no-scope) type map mis-resolves the variable to a float
// because another routine declares a same-named float AFTER this one. The rule MUST
// still fire on a genuine float = float-literal comparison (i = 0.0).

interface

implementation

uses
  System.SysUtils;

function StrToFloatA(const S: string): double;
var
  i : double;
  SS: string;
begin
  SS:= S;
  SS:= Trim(SS);
  i:= 0;
  if length(SS) = 0 then SS:= '0';
  if (SS = '-') or (SS = '+') or (SS = '-.') or (SS = '+.') then SS:= '0';
  i:= StrToFloat(SS, TFormatSettings.Invariant);
  if i = 0.0 then i:= 1.0;
  Result:= i;
end;

// Declared AFTER StrToFloatA: poisons the flat type map so 'ss' -> double wins.
function ScaleSS(SS: Double): Double;
begin
  Result:= SS * 2.0;
end;

end.
