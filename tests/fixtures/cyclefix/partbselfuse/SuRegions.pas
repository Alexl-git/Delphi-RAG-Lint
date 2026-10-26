unit SuRegions;

// Task-17 F2092 repro (CYC-B): see SuFacts.

interface

/// <summary>Prints CSuMaxVia.</summary>
procedure SuRegionsRun;

implementation

uses
  SuFacts;

procedure SuRegionsRun;
begin
  Writeln(CSuMaxVia);
end;

end.
