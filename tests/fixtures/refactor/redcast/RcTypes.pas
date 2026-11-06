unit RcTypes;

// Redundant-cast fixture: the types. Lane 144 refact1.

interface

type
  TBase = class
    procedure Foo;
  end;
  TDer = class(TBase)
  end;
  TRec = record
    V: Integer;
  end;
  PRecP = ^TRec;
  IFoo = interface
    procedure Bar;
  end;
  TEn = (eA, eB);
  TAlias = type TBase;
  TCnt = Cardinal;
  TProc1 = procedure(pX: Integer);
  TBox = class(TBase)
  end;
  TBox<T> = class(TBase)
  end;
  TDup = class(TBase)
  end;
  TNamed = class(TBase)
  end;

implementation

procedure TBase.Foo;
begin
end;

end.