unit uUnusedGlobalUser;

interface

procedure UseOther;

implementation

uses
  uUnusedGlobal;

procedure UseOther;
var
  N: Integer;
begin
  N:= GIntfOtherUnit;
  RunGlobals;
  if N > 0 then Exit;
end;

end.
