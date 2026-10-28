unit aliasmath;

interface

uses
  Math, SysUtils;

procedure Run(A, B: Double);

implementation

procedure Run(A, B: Double);
begin
  if SameValue(A, B) then Exit;
end;

end.
