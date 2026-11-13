unit IP3C;

// Plan fixture (lane CYC3): the third unit of the cycle. It takes the address of an IP3B routine, so the
// edge IP3C -> IP3B is never a routine-call inversion and stays after the cut.

interface

/// <summary>Takes the address of IP3BTick.</summary>
procedure IP3CPing;

implementation

uses
  IP3B;

var
  GTick: procedure;

procedure IP3CPing;
begin
  GTick:= @IP3BTick;
end;

initialization
  Writeln('init IP3C');

end.
