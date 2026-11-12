unit IP3A;

// Plan fixture (lane CYC3, init-order proof): IP3A's initialization calls IP3BWrite. The cycle has three
// units (IP3A -> IP3C -> IP3B -> IP3A, plus IP3A -> IP3B), so after the cut IP3A still reaches IP3B through
// IP3C: whether IP3B initializes first depends on the order the .dpr lists the units.

interface

/// <summary>Writes a line through IP3BWrite.</summary>
procedure IP3AStart;

/// <summary>A fixed value, read by IP3B.</summary>
/// <returns>3.</returns>
function IP3AValue: Integer;

implementation

uses
  IP3C, IP3B;

procedure IP3AStart;
begin
  IP3BWrite('a started');
end;

function IP3AValue: Integer;
begin
  Result:= 3;
end;

var
  GPing: procedure;

initialization
  GPing:= @IP3CPing;
  Writeln('init IP3A');
  IP3AStart;

end.
