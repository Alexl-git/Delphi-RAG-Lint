unit uMicXBase;

{ RB-A (wave 151) item 2: a generic class whose CONSTRAINT names the same
  interface as its heritage -- `TMicXBase<I: IMicX> = class(TComponent, IMicX)`,
  the last unbound IMicObject type_use on ORM3 CLIENT (uMicObjectBase.pas:32).
  A constraint is not a parameter name: the heritage IMicX must bind.
  Control: TItem below IS a parameter name of TBox, so `Get: TItem` stays a
  generic-parameter use although a class TItem exists. }

interface

uses
  System.Classes,
  IuMicX;

type
  TItem = class
  end;

  TMicXBase<I: IMicX> = class(TComponent, IMicX)
  end;

  TMicXPlain = class(TComponent, IMicX)
  end;

  TBox<TItem: IMicX> = class
    function Get: TItem;
  end;

implementation

function TBox<TItem>.Get: TItem;
begin
  Result:= nil;
end;

end.