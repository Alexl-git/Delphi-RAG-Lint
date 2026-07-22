unit coveredfixture;

// Fixture for Auto-Document Phase 2 Task 5: a LEGACY DUnit-style test caller
// of covered.Target, detected via rule (b) -- TTestCase ancestry -- rather
// than rule (a)'s unit-name convention (this unit's OWN name deliberately
// does NOT match '*Test'/'Test*', so a false hit here would prove rule (a)
// is over-matching). TTestCase itself is never declared anywhere in this
// fixture corpus (it lives in the real DUnit TestFramework.pas, outside this
// scratch index) -- an UNRESOLVED heritage edge still carries its NAME
// (ISymbolStore.GetTransitiveAncestors returns unresolved ancestors as
// name-only leaves), which is all rule (b) needs.

interface

uses
  covered;

type
  TLegacyCase = class(TTestCase)
  public
    procedure CheckTarget;
  end;

implementation

procedure TLegacyCase.CheckTarget;
begin
  Target(2);
end;

end.
