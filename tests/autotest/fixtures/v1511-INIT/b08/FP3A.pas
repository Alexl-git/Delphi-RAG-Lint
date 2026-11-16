unit FP3A;

// Plan fixture (lane FINPROOF, finalization-order proof): FP3A's finalization calls FP3BReport. The cycle has
// three units (FP3A -> FP3C -> FP3B -> FP3A, plus FP3A -> FP3B), so after the cut FP3A still reaches FP3B
// through FP3C: whether FP3B is finalized after FP3A depends on the order the .dpr lists the units.

interface

/// <summary>Reports through FP3BReport.</summary>
procedure FP3AStop;

/// <summary>A fixed value, read by FP3B.</summary>
/// <returns>5.</returns>
function FP3AValue: Integer;

implementation

uses
  FP3C, FP3B.Untangle;

procedure FP3AStop;
begin
  FP3BReportPtr('a stopped');
end;

function FP3AValue: Integer;
begin
  Result:= 5;
end;

var
  GPing: procedure;

initialization
  GPing:= @FP3CPing;
  Writeln('init FP3A');

finalization
  Writeln('fin FP3A');
  FP3AStop;

end.
