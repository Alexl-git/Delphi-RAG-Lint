unit basic;

interface

type
  IBare = interface
    ['{DD3A3918-6EBE-318D-8336-A00707AAEA98}']
    procedure Run;
  end;

  IDerived = interface(IBare)
    ['{B605B0D9-4ED8-3EB0-9F2E-9DBEFD9F885D}']
    procedure Stop;
  end;

  IGuided = interface
    ['{5B1C2F84-0C8E-4B6F-9C1B-3A8F2E7D6A10}']
    procedure Go;
  end;

implementation

end.
