unit Z_Types;

{ Fixture for run_doc_returns_owner_order.ps1: one value type, one class. }

interface

type
  TZValue = record
    N: Integer;
  end;

  TZThing = class
  public
    N: Integer;
  end;

implementation

end.