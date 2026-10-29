unit basic;

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
    procedure Go;
  end;

implementation

end.
