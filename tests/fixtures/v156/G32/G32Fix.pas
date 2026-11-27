unit G32Fix;

interface

function UserMax(const A, B: Single): Single;

procedure FireCases(S, S2: Single; var D: Double; var E: Extended);
procedure SilentCases(S: Single; Dbl: Double; var D: Double; var Sg: Single);
function ResultFire(S1, S2: Single): Double;
function ResultSilent(D1, D2: Double): Double;

implementation

uses
  System.Math;

function UserMax(const A, B: Single): Single;
begin
  Result:= A;
  if B > A then Result:= B;
end;

procedure FireCases(S, S2: Single; var D: Double; var E: Extended);
begin
  D:= Power(S, S2);  // FIRE math-single-overload
  E:= Math.Power(S2, S);  // FIRE math-single-overload
end;

procedure SilentCases(S: Single; Dbl: Double; var D: Double; var Sg: Single);
begin
  D:= Max(Dbl, 1.5);
  Sg:= Max(S, 1.5);
  D:= Max(S, Dbl);
  D:= Max(S, Unknown1);
  D:= Max(Double(S), 1.5);
  D:= Max(S, 1);
  D:= UserMax(S, 1.5);
  D:= Max(Dbl, Dbl);
  D:= Round(S);
  D:= Max(S, 1.5);
  D:= Power(S, 2.5);
  D:= Math.Max(0.5, S);
  D:= Max(S, S);
  D:= Min(S, S);
  D:= Power(S, Dbl);
  Sg:= Power(S, S);
end;

function ResultFire(S1, S2: Single): Double;
begin
  Result:= Power(S1, S2);  // FIRE math-single-overload
end;

function ResultSilent(D1, D2: Double): Double;
begin
  Result:= Max(D1, D2);
end;

end.
