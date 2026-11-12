unit IP3B;

// Plan fixture (lane CYC3): declares the routine IP3A's initialization calls. Its own use of IP3A takes
// the address of a routine, so that edge is never a routine-call inversion.

interface

/// <summary>Writes one line.</summary>
/// <param name="pText">The text.</param>
procedure IP3BWrite(const pText: string);

/// <summary>Takes no part in the order; keeps the uses entry needed.</summary>
procedure IP3BTick;

implementation

uses
  IP3A;

var
  GValue: function: Integer;

procedure IP3BWrite(const pText: string);
begin
  Writeln('[b] ', pText);
end;

procedure IP3BTick;
begin
  GValue:= @IP3AValue;
end;

initialization
  Writeln('init IP3B');

end.
