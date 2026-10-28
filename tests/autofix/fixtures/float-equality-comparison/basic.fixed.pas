unit basic;

interface

implementation

uses
  System.Math,
  System.SysUtils;

procedure Run(A, B: Double);
begin
  if System.Math.SameValue(A, B) then Exit;
  if (not System.Math.SameValue(A, 1.5)) or (System.Math.SameValue(B, A)) then Exit;
end;

end.
