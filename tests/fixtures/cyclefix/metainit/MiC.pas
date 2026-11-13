unit MiC;

// Plan fixture (lane CYC3 finisher): the third unit of the cycle. It takes the address of an MiB routine, so
// the edge MiC -> MiB is never an inversion and stays after the cut.

interface

/// <summary>Takes the address of MiBTick.</summary>
procedure MiCPing;

implementation

uses
  MiB;

var
  GTick: procedure;

procedure MiCPing;
begin
  GTick:= @MiBTick;
end;

initialization
  Writeln('init MiC');

end.
