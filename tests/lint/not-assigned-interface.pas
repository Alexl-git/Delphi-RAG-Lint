unit notassignedinterface;
interface
type
  IBar = interface
    procedure Baz;
  end;
  IFoo = interface
    procedure Bar;
    function IsReady: Boolean;
    function Child: IFoo;
  end;
function GetFoo: IFoo;
implementation
function GetFoo: IFoo;
begin
  Result := nil;
end;
{ declared then dereferenced with no assignment on any path -> warning }
procedure P1;
var
  V: IFoo;
begin
  V.Bar;
end;
{ assigned then dereferenced -> absent (must-assigned) }
procedure P2;
var
  V: IFoo;
begin
  V := GetFoo;
  V.Bar;
end;
{ assigned on one if-branch only, then dereferenced after -> info (may-assigned) }
procedure P3(b: Boolean);
var
  V: IFoo;
begin
  if b then V := GetFoo;
  V.Bar;
end;
{ plain copy of an unassigned interface, no deref -> absent (not a dereference) }
procedure P4;
var
  V, W: IFoo;
begin
  W := V;
end;
function Supports(const Instance: IInterface; const IID: TGUID; out Intf): Boolean;
begin
  Result := False;
end;
{ Supports(..,out V) and V.Method -> absent: short-circuit sequencing means
  the call-arg def of V is visible to the rhs deref within the same and-chain }
procedure P5(const Src: IInterface; const IID: TGUID);
var
  V: IFoo;
  OK: Boolean;
begin
  OK := Supports(Src, IID, V) and V.IsReady;
end;
{ declared then deref'd via `as` with no assignment on any path -> warning }
procedure P6;
var
  V: IFoo;
  B: IBar;
begin
  B := V as IBar;
end;
{ multi-hop chain V.Child.Bar with V unassigned -> warning (base of the chain) }
procedure P7;
var
  V: IFoo;
begin
  V.Child.Bar;
end;
end.
