unit uEnumUse;

{ enum-type-marker fixture: the casts, in a unit that is NOT the declaring one. }

interface

uses
  uEnumDecl;

procedure Run(pN: Integer);

implementation

procedure Run(pN: Integer);
var
  M: TMarkedCmd;
  F: TFreeCmd;
begin
  M:= TMarkedCmd(1);      // CONTROL-MARKED-CAST
  if Ord(M) = 2 then Exit; // CONTROL-MARKED-ORD
  F:= TFreeCmd(1);        // TRIGGER-FREE-CAST
  if (F = fcA) and (M = mcA) and (pN > 0) then Exit;
end;

end.