unit aliasmath;

interface

uses
  Math, SysUtils;

procedure Run(A, B: Double);

implementation

procedure Run(A, B: Double);
begin
  if System.Math.SameValue(A, B) then Exit;
end;

end.
