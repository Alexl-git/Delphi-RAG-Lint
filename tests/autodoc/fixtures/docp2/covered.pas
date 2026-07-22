unit covered;

// Fixture for Auto-Document Phase 2 Task 5 (Covered-by-tests fact, LAZY
// reverse-closure path -- see DRagLint.Doc.SymbolFacts.ComputeCoveredBy).
// Target is called from THREE places, paired with coveredtest.pas and
// coveredfixture.pas (all three indexed into ONE db by the harness):
//   * coveredtest.pas'      TTargetTests.TestTarget  -- detected via rule (a),
//     the unit/file-NAME convention ('coveredtest' ends in 'test'); the class
//     does NOT derive TTestCase, proving rule (a) suffices alone.
//   * coveredfixture.pas'   TLegacyCase.CheckTarget  -- detected via rule (b),
//     TTestCase ANCESTRY (this unit's own name does NOT match '*Test'/
//     'Test*'), proving rule (b) fires independent of naming.
//   * UseTargetDirectly, below (SAME unit, plain non-test caller) -- must
//     NEVER appear in Target's 'Covered by:' fact.

interface

function Target(X: Integer): Integer;
procedure UseTargetDirectly;

implementation

function Target(X: Integer): Integer;
begin
  Result := X * 2;
end;

procedure UseTargetDirectly;
begin
  Target(1);
end;

end.
