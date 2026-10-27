unit SuboptimalMath;

interface

uses
  System.Math;

implementation

procedure P(X, A, B: Double);
var
  R: Double;
begin
  R := Power(X, 2);
  R := Power(X, 2.0);
  R := Power(X, 0.5);
  R := Sqrt(Sqr(A) + Sqr(B));
  R := Power(X, 3);
  R := Sqrt(A);
  R := Sqrt(Sqr(A) - Sqr(B));
  R := Sqrt(Sqr(A) + B);
  R := Hypot(A, B);
end;

end.
