unit InterfaceObjectMixingSupportsClean;
{ look-alike: the two-argument Supports only asks and keeps no reference, so a
  later X.Free is the only handle. }
interface

type
  IFoo = interface
    ['{00000000-0000-0000-0000-000000000003}']
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

procedure AskOnly;
var
  X: TFoo;
begin
  X := TFoo.Create;
  if Supports(X, IFoo) then
    X.DoIt;
  X.Free;
end;

end.
