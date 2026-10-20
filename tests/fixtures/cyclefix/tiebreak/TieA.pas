unit TieA;

// E18 T7 fixture (R3 tie-break): TieA -> TieB carries ONE global read five
// times (members 0, refs 5, cost 1).

interface

type
  /// <summary>A record whose field TieC reads.</summary>
  TTieARec = record
    F: Integer;
  end;

var
  /// <summary>Read by TieC through its field F.</summary>
  GTieA: TTieARec;

/// <summary>Prints five reads of GTieB1.</summary>
procedure TieARun;

implementation

uses
  TieB;

procedure TieARun;
begin
  Writeln(GTieB1 + GTieB1 + GTieB1 + GTieB1 + GTieB1);
end;

end.