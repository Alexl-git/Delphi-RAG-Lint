unit TieB;

// E18 T7 fixture (R3 tie-break): TieB -> TieC carries TWO globals, read three
// times (members 0, refs 3, cost 2).

interface

var
  /// <summary>Read five times by TieA.</summary>
  GTieB1: Integer = 1;

/// <summary>Prints reads of GTieC1 and GTieC2.</summary>
procedure TieBRun;

implementation

uses
  TieC;

procedure TieBRun;
begin
  Writeln(GTieC1 + GTieC2 + GTieC2);
end;

end.