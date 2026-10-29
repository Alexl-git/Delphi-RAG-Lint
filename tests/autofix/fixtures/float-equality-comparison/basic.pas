unit basic;

interface

implementation

uses
  System.SysUtils;

procedure Run(A, B: Double);
begin
  if A = B then Exit;
  if (A <> 1.5) or (B = A) then Exit;
end;

end.
