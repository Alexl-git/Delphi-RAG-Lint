unit uFpprBase;
interface
type
  TBaseColl = class
  private
    FSlots: array [0..3] of Integer;
    function GetSlot(pIndex: Integer): Integer;
  public
    property Slots[pIndex: Integer]: Integer read GetSlot;
  end;
implementation
function TBaseColl.GetSlot(pIndex: Integer): Integer;
begin
  Result:= FSlots[pIndex];
end;
end.
