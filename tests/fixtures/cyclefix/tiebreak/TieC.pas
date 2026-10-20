unit TieC;

// E18 T7 fixture (R3 tie-break): TieC -> TieA reads ONE member of a record
// global (members 1, refs 2, cost 2).
// Members then refs pick TieB -> TieC; cost alone would pick TieA -> TieB,
// refs alone TieC -> TieA.

interface

var
  /// <summary>Read by TieB.</summary>
  GTieC1: Integer = 2;
  /// <summary>Read twice by TieB.</summary>
  GTieC2: Integer = 3;

/// <summary>Prints GTieA.F.</summary>
procedure TieCRun;

implementation

uses
  TieA;

procedure TieCRun;
begin
  Writeln(GTieA.F);
end;

end.