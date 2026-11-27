unit uFpprCallBody;
interface
function CallBody: Integer;
implementation
uses
  uFpprMid, uFpprLeaf;
function CallBody: Integer;
begin
  Result:= MidColl.Touch;
end;
end.
