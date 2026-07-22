unit coveredtest;

// Fixture for Auto-Document Phase 2 Task 5: the TEST caller of covered.
// Target, detected via rule (a) -- this unit's own NAME ends in 'test'
// (case-insensitive '*Test' convention) -- deliberately NOT deriving from
// TTestCase, so this fixture proves rule (a) works standalone, independent
// of rule (b) (TTestCase ancestry, see coveredfixture.pas).

interface

uses
  covered;

type
  TTargetTests = class
  public
    procedure TestTarget;
  end;

implementation

procedure TTargetTests.TestTarget;
begin
  Target(1);
end;

end.
