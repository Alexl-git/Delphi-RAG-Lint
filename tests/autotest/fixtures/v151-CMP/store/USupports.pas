unit USupports;

{ interface-holder-of-non-refcounted, CMP widening: Supports(X, IID, Intf) with
  X a TComponent descendant declared in another unit. (+) must fire, (-) must not. }

interface

uses
  SysUtils, UBaseComp;

procedure Probe(AComp: TBaseComp; AObj: TCountedObj; const AIntf: IInterface);

implementation

procedure Probe(AComp: TBaseComp; AObj: TCountedObj; const AIntf: IInterface);
var
  G: IGreeter;
begin
  if Supports(AComp, IGreeter, G) then { (+) }
    G.Greet;
  if Supports(AObj, IGreeter, G) then { (-) }
    G.Greet;
  if Supports(AIntf, IGreeter, G) then { (-) }
    G.Greet;
end;

end.
