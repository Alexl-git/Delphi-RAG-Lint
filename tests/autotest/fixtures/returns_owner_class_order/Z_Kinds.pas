unit Z_Kinds;

{ Fixture for run_returns_owner_order.ps1 (151 X2R): a class whose name does
  NOT follow the T/I convention, and one that does. }

interface

type
  Widget = class
  public
    N: Integer;
  end;

  TZThing = class
  public
    N: Integer;
  end;

implementation

end.