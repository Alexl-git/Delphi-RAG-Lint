unit FP3C;

// Plan fixture (lane FINPROOF): the third unit of the cycle. It takes the address of an FP3B routine, so the
// edge FP3C -> FP3B is never a routine-call inversion and stays after the cut.

interface

/// <summary>Takes the address of FP3BTick.</summary>
procedure FP3CPing;

implementation

uses
  FP3B;

var
  GTick: procedure;

procedure FP3CPing;
begin
  GTick:= @FP3BTick;
end;

initialization
  Writeln('init FP3C');

finalization
  Writeln('fin FP3C');

end.
