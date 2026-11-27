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
  D:= Max(S, 1.5);  // FIRE math-single-overload
  D:= Power(S, 2.5);  // FIRE math-single-overload
  E:= Min(S, S2);  // FIRE math-single-overload
  D:= Math.Max(0.5, S);  // FIRE math-single-overload
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
end;

function ResultFire(S1, S2: Single): Double;
begin
  Result:= Max(S1, S2);  // FIRE math-single-overload
end;

function ResultSilent(D1, D2: Double): Double;
begin
  Result:= Max(D1, D2);
end;

end.
