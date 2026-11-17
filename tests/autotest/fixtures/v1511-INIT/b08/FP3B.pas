unit FP3B;

// Plan fixture (lane FINPROOF): declares the routine FP3A's finalization calls. Its state is a string that its
// own finalization clears, so a call that arrives after FP3B is finalized prints an empty name. Its own use of
// FP3A takes the address of a routine, so that edge is never a routine-call inversion.

interface

/// <summary>Writes one line with the unit's state.</summary>
/// <param name="pText">The text.</param>
procedure FP3BReport(const pText: string);

/// <summary>Takes no part in the order; keeps the uses entry needed.</summary>
procedure FP3BTick;

implementation

uses
  FP3A,
  FP3B.Untangle;

var
  GName : string;
  GValue: function: Integer;

procedure FP3BReport(const pText: string);
begin
  Writeln('[b] ', pText, ' name=', GName);
end;

procedure FP3BTick;
begin
  GValue:= @FP3AValue;
end;

initialization
  FP3BReportPtr := FP3BReport;
  GName:= 'alive';
  Writeln('init FP3B');

finalization
  Writeln('fin FP3B');
  GName:= '';

end.
