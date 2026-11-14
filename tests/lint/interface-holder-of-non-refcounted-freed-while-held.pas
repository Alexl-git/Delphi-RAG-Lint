unit interface_holder_freed_while_held;

{ Fixture for the CMP widening of interface-holder-of-non-refcounted (warning):
  a component freed while a local interface variable still refers to it fires at
  the free -- the variable is released at the end of the routine, on the freed
  object. Silent: the interface cleared before the free, an object that is not a
  component, a free before the binding. (+) must fire, (-) must not. }

interface

uses
  Classes, StdCtrls;

type
  IGreeter = interface
    ['{0B9C4E61-2D7A-4F3B-9E10-5A6C7D8E9F01}']
    procedure Greet;
  end;

  TGreeterComp = class(TComponent, IGreeter)
  public
    procedure Greet;
  end;

  TGreeterObj = class(TInterfacedObject, IGreeter)
  public
    procedure Greet;
  end;

procedure UseAndFree;
procedure ClearFirst;
procedure ViaSupports;
procedure NotAComponent;
procedure FreedBefore;

implementation

procedure TGreeterComp.Greet;
begin
end;

procedure TGreeterObj.Greet;
begin
end;

procedure UseAndFree;
var
  Comp: TGreeterComp;
  G: IGreeter;
begin
  Comp := TGreeterComp.Create(nil);
  try
    G := Comp as IGreeter;
    G.Greet;
  finally
    Comp.Free; { (+) }
  end;
end;

procedure ClearFirst;
var
  Comp: TGreeterComp;
  G: IGreeter;
begin
  Comp := TGreeterComp.Create(nil);
  G := Comp;
  G.Greet;
  G := nil;
  Comp.Free; { (-) }
end;

procedure ViaSupports;
var
  Btn: TButton;
  G: IGreeter;
begin
  Btn := TButton.Create(nil);
  if Supports(Btn, IGreeter, G) then
    G.Greet;
  FreeAndNil(Btn); { (+) }
end;

procedure NotAComponent;
var
  Obj: TGreeterObj;
  G: IGreeter;
begin
  Obj := TGreeterObj.Create;
  G := Obj;
  G.Greet;
  Obj.Free; { (-) }
end;

procedure FreedBefore;
var
  Comp: TGreeterComp;
  G: IGreeter;
begin
  Comp := TGreeterComp.Create(nil);
  Comp.Free; { (-) }
  Comp := TGreeterComp.Create(nil);
  G := Comp;
  G := nil;
end;

end.
