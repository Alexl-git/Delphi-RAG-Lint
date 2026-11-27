unit uFpprCallInherited;
interface
function CallInherited: Integer;
implementation
uses
  uFpprMid, uFpprBase;
function CallInherited: Integer;
begin
  Result:= MidColl[1];
end;
end.
