unit A_Owner;

{ Fixture for run_doc_returns_owner_order.ps1. A_Owner sorts BEFORE Z_Types, so
  on a fresh `index <dir>` this unit's facts pass runs while TZValue / TZThing
  are not yet in the store. Do not rename either unit. }

interface

uses
  Z_Types;

type
  TOwner = class
  private
    FValue: TZValue;
    FThing: TZThing;
  public
    function Value: TZValue;
    function Thing: TZThing;
  end;

implementation

function TOwner.Value: TZValue;
begin
  Result:= FValue;
end;

function TOwner.Thing: TZThing;
begin
  Result:= FThing;
end;

end.