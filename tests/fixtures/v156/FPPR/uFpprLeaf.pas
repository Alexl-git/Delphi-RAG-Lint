unit uFpprLeaf;
interface
type
  TStamp = record
    Ticks: Integer;
  end;
function LeafValue: Integer;
implementation
function LeafValue: Integer;
begin
  Result:= 7;
end;
end.
