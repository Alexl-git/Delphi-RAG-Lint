unit IncRefB;

// Plan fixture (lane CYC3, item 2): uses IncRefA in its implementation.

interface

/// <summary>Writes one line.</summary>
/// <param name="pText">The text.</param>
procedure IncRefBWrite(const pText: string);

implementation

uses
  IncRefA;

procedure IncRefBWrite(const pText: string);
begin
  Writeln('[incref] ', pText, ' ', IncRefAValue);
end;

end.
