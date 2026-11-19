unit mwData;

{ check-init fixture events-memberwrite (INT H-F1): a target written ONLY through a member access
  (`TCounter.Hits := ..`, `mwData.GUnitQ := ..`) has a writer, never NEVER-SET. Positions are
  asserted by tests\autotest\run_check_init_memberwrite.ps1 -- do not reflow. }

interface

type
  TCounter = class
  public
    class var Hits: Integer;
  end;

var
  GUnitQ: Integer;
  GNever: Integer;

procedure Setup;

implementation

procedure Setup;
begin
  TCounter.Hits := 3;
  mwData.GUnitQ := 4;
end;

end.
