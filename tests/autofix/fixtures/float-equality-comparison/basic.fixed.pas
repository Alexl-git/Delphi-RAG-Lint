unit basic;

interface

implementation

uses
  System.Math,
  System.SysUtils;

procedure Run(A, B: Double);
begin
  if SameValue(A, B) then Exit;
  if (not SameValue(A, 1.5)) or (SameValue(B, A)) then Exit;
end;

end.
