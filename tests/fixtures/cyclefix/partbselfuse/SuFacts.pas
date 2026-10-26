unit SuFacts;

// Task-17 F2092 repro (CYC-B): after Part A, SuFacts already uses its leaf
// SuFacts.Untangle in the interface. The implementation cycle SuFacts <-> SuRegions
// is cut in Part B by moving CSuMaxVia into that EXISTING leaf; the leaf must never
// get itself in its own uses clause (dcc F2092).

interface

uses
  SuFacts.Untangle;

const
  /// <summary>The largest via count SuRegions prints.</summary>
  CSuMaxVia = 3;

/// <summary>Prints the highest kind ordinal, then runs SuRegions.</summary>
procedure SuFactsShow;

implementation

uses
  SuRegions;

procedure SuFactsShow;
begin
  Writeln(Ord(High(TSuKind)));
  SuRegionsRun;
end;

end.
