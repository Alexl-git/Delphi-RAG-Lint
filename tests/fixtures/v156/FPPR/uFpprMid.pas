unit uFpprMid;
interface
uses
  uFpprBase, uFpprLeaf, uFpprOther;
type
  TMidColl = class(TBaseColl)
  private
    FStamp: TStamp;
    function GetItem(pIndex: Integer): Integer; inline;
    procedure SetAsStamp(const pValue: TStamp); inline;
  public
    function Touch: Integer; inline;
    function Plain: Integer;
    property Items[pIndex: Integer]: Integer read GetItem; default;
    property AsStamp: TStamp write SetAsStamp;
  end;
function MidColl: TMidColl;
implementation
var
  GMid: TMidColl;
function MidColl: TMidColl;
begin
  if GMid = nil then GMid:= TMidColl.Create;
  Result:= GMid;
end;
function TMidColl.GetItem(pIndex: Integer): Integer;
begin
  Result:= inherited Slots[pIndex];
end;
procedure TMidColl.SetAsStamp(const pValue: TStamp);
begin
  FStamp:= pValue;
end;
function TMidColl.Touch: Integer;
begin
  Result:= LeafValue;
end;
function TMidColl.Plain: Integer;
begin
  Result:= OtherValue;
end;
end.
