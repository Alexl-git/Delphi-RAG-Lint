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

// v(B10): a NON-test HELPER declared inside a '*Test'-named unit. This is the
// exact shape of YADF's `CodeChars` (Test\GuardTest.dpr:143), which rule (a)
// counted as a test purely because of the FILE it lives in. It genuinely CALLS
// Target, so it is a real caller and shows up in the reverse walk -- it must
// still NEVER appear in Target's 'Covered by:' set, because it is not a test.
function ScanHelper(const S: string): Integer;

implementation

procedure TTargetTests.TestTarget;
begin
  Target(1);
end;

function ScanHelper(const S: string): Integer;
begin
  Result:= Target(Length(S));
end;

end.
