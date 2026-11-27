unit uFpprCallPlain;
interface
function CallPlain: Integer;
implementation
uses
  uFpprMid, uFpprOther, uFpprDead;
function CallPlain: Integer;
begin
  Result:= MidColl.Plain;
end;
end.
