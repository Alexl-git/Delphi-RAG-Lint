unit InterfaceWithoutGuid;

interface

type
  IBare = interface
    procedure Run;
  end;

  IDerived = interface(IBare)
    procedure Stop;
  end;

  IGuided = interface
    ['{5B1C2F84-0C8E-4B6F-9C1B-3A8F2E7D6A10}']
    procedure Run;
  end;

  IGuidedChild = interface(IGuided)
    ['{9D3E7A10-4F21-4C55-8A6B-1E0C5B7F2D33}']
    procedure Stop;
  end;

  IDisp = dispinterface
    procedure Run;
  end;

implementation

end.
