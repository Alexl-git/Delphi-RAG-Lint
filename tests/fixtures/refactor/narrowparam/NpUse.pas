unit NpUse;

// Each routine's header line says what narrow-param must decide for its parameter pP:
//   NARROW <type> / REFUSE <kind> / NONE (already as narrow as its uses).

interface

uses
  System.Classes, NpBase;

type
  THost = class
  public
    Slot: TLeaf;
    procedure ViaBase(pP: TLeaf); // NARROW TBase
    procedure ViaMid(pP: TLeaf); // NARROW TMid
    procedure ViaLeaf(pP: TLeaf); // NONE
    procedure ViaHidden(pP: TLeaf); // NARROW TMid
    procedure ViaRoot(pP: TLeaf); // NARROW TRoot
    procedure ViaNil(pP: TLeaf); // REFUSE no-member-use
    procedure ViaFree(pP: TLeaf); // REFUSE member-not-in-chain
    procedure ViaOver(pP: TLeaf); // REFUSE overloaded-member
    procedure ViaWrite(pP: TLeaf); // NARROW TBase
    procedure ViaPropWrite(pP: TLeaf); // NARROW TBase
    procedure ViaMidWrite(pP: TLeaf); // NARROW TMid
    procedure ViaGenBase(pP: TGenLeaf); // REFUSE generic-ancestor
    procedure ViaStore(pP: TLeaf); // REFUSE other-use
    procedure ViaArgWide(pP: TLeaf); // REFUSE other-use
    procedure ViaIs(pP: TLeaf); // REFUSE other-use
    procedure ViaAddr(pP: TLeaf); // REFUSE other-use
    procedure ViaWith(pP: TLeaf); // REFUSE with-body
    procedure ViaVarParam(var pP: TLeaf); // REFUSE by-reference
    procedure ViaOutParam(out pP: TLeaf); // REFUSE by-reference
    procedure ViaGrouped(pP, pQ: TLeaf); // REFUSE grouped-param
    procedure ViaVirtual(pP: TLeaf); virtual; // REFUSE virtual-routine
    procedure ViaOverloaded(pP: TLeaf); overload; // REFUSE overloaded-routine
    procedure ViaOverloaded(pP: TLeaf; pQ: Integer); overload; // REFUSE overloaded-routine
    procedure ViaPointed(pP: TLeaf); // REFUSE routine-as-value
    procedure ViaChain(pP: TLeaf); // REFUSE other-use
    procedure ViaAssigned(pP: TLeaf); // NARROW TBase
    procedure SetLeaf(pP: TLeaf); // REFUSE property-accessor
    property LeafProp: TLeaf write SetLeaf;
  published
    procedure ViaPublished(pP: TLeaf); // REFUSE published-routine
  end;

  TImpl = class(TInterfacedObject, ICounted)
  public
    procedure Consume(pP: TLeaf); // REFUSE implements-interface
  end;

  TOverride = class(THost)
  public
    procedure ViaVirtual(pP: TLeaf); override; // REFUSE virtual-routine
  end;

  TUnknownChainLeaf = class(TStringList)
  end;

  TPointedProc = procedure(pP: TLeaf) of object;

procedure FreeRoutine(pP: TLeaf); // NARROW TMid
procedure UnknownChain(pP: TUnknownChainLeaf); // REFUSE unresolved-ancestor
procedure RunAll;

implementation

procedure THost.ViaBase(pP: TLeaf);
begin
  pP.BaseOnly;
end;

procedure THost.ViaMid(pP: TLeaf);
begin
  pP.BaseOnly;
  pP.MidOnly;
end;

procedure THost.ViaLeaf(pP: TLeaf);
begin
  pP.LeafOnly;
end;

// Hidden binds to TMid.Hidden today; narrowing past TMid would rebind it, and dcc would not say a word.
procedure THost.ViaHidden(pP: TLeaf);
begin
  pP.Hidden;
end;

procedure THost.ViaRoot(pP: TLeaf);
begin
  pP.RootOnly;
end;

procedure THost.ViaNil(pP: TLeaf);
begin
  if pP = nil then Exit;
end;

procedure THost.ViaFree(pP: TLeaf);
begin
  pP.Free;
end;

procedure THost.ViaOver(pP: TLeaf);
begin
  pP.Over(1);
end;

procedure THost.ViaWrite(pP: TLeaf);
begin
  pP.BaseField:= 1;
end;

procedure THost.ViaPropWrite(pP: TLeaf);
begin
  pP.BaseProp:= pP.BaseField + 1;
end;

procedure THost.ViaMidWrite(pP: TLeaf);
begin
  pP.MidField:= 2;
end;

procedure THost.ViaGenBase(pP: TGenLeaf);
begin
  pP.GenField:= pP.GenField + 1;
end;

procedure THost.ViaStore(pP: TLeaf);
begin
  Slot:= pP;
end;

procedure THost.ViaArgWide(pP: TLeaf);
begin
  TakeBase(pP);
end;

procedure THost.ViaIs(pP: TLeaf);
begin
  if pP is TMid then Exit;
end;

procedure THost.ViaAddr(pP: TLeaf);
begin
  if @pP = nil then Exit;
end;

procedure THost.ViaWith(pP: TLeaf);
begin
  with pP do
    BaseOnly;
end;

procedure THost.ViaVarParam(var pP: TLeaf);
begin
  pP.BaseOnly;
end;

procedure THost.ViaOutParam(out pP: TLeaf);
begin
  pP:= nil;
end;

procedure THost.ViaGrouped(pP, pQ: TLeaf);
begin
  pP.BaseOnly;
  pQ.BaseOnly;
end;

procedure THost.ViaVirtual(pP: TLeaf);
begin
  pP.BaseOnly;
end;

procedure THost.ViaOverloaded(pP: TLeaf);
begin
  pP.BaseOnly;
end;

procedure THost.ViaOverloaded(pP: TLeaf; pQ: Integer);
begin
  pP.BaseOnly;
end;

procedure THost.ViaPointed(pP: TLeaf);
begin
  pP.BaseOnly;
end;

procedure THost.ViaChain(pP: TLeaf);
begin
  pP.GetSelf.BaseOnly;
  TakeLeaf(pP);
end;

procedure THost.SetLeaf(pP: TLeaf);
begin
  pP.BaseOnly;
end;

procedure THost.ViaAssigned(pP: TLeaf);
begin
  if Assigned(pP) then pP.BaseOnly;
end;

procedure THost.ViaPublished(pP: TLeaf);
begin
  pP.BaseOnly;
end;

procedure TImpl.Consume(pP: TLeaf);
begin
  pP.BaseOnly;
end;

procedure TOverride.ViaVirtual(pP: TLeaf);
begin
  pP.BaseOnly;
end;

procedure FreeRoutine(pP: TLeaf);
begin
  pP.VirtualM;
  pP.BaseOnly;
end;

procedure UnknownChain(pP: TUnknownChainLeaf);
begin
  pP.Clear;
end;

procedure RunAll;
var
  H: THost;
  P: TPointedProc;
begin
  H:= THost.Create;
  P:= H.ViaPointed;
  P(nil);
  H.Free;
end;

end.