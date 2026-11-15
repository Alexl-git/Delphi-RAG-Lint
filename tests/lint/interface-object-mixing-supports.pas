unit InterfaceObjectMixingSupports;
{ interface-object-mixing, v151 widening: the interface reference comes from a
  three-argument Supports, and the manual free is DisposeOf. }
interface

type
  IFoo = interface
    ['{00000000-0000-0000-0000-000000000002}']
    procedure DoIt;
  end;

  TFoo = class(TInterfacedObject, IFoo)
    procedure DoIt;
  end;

implementation

uses System.SysUtils;

procedure TFoo.DoIt;
begin
end;

procedure BadSupports;
var
  X: TFoo;
  I: IFoo;
begin
  X := TFoo.Create;
  if Supports(X, IFoo, I) then
    I.DoIt;
  X.Free;
end;

procedure BadDisposeOf;
var
  X: TFoo;
  I: IFoo;
begin
  X := TFoo.Create;
  I := X;
  I.DoIt;
  X.DisposeOf;
end;

end.
