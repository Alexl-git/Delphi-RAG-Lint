unit ownsame;

{ The unit declares its own SameValue(V1, V2, DIGITS) which hides System.Math.SameValue; the
  rewrite `A = B` -> `SameValue(A, B)` would call the 3-parameter one: E2035 "Not enough actual
  parameters". The fixer must decline the whole file. Found by the ORM3 --fix --apply build
  proof (BASICSF.pas). }

interface

function SameValue(const V1, V2: Double; const DIGITS: Integer): Boolean;

implementation

uses
  System.SysUtils;

function SameValue(const V1, V2: Double; const DIGITS: Integer): Boolean;
begin
  Result:= Abs(V1 - V2) < 1;
end;

procedure Run(A, B: Double);
begin
  if A = B then Exit;
end;

end.
