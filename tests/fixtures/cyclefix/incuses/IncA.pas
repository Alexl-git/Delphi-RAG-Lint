unit IncA;

// E18 T15b fixture incuses: the plain half of the IncA <-> IncB cycle.

interface

/// <summary>Calls into IncB.</summary>
procedure RunA;
/// <summary>Called back from IncB.</summary>
function ValueA: Integer;

implementation

uses
  IncB;

procedure RunA;
begin
  Writeln(ValueB);
end;

function ValueA: Integer;
begin
  Result:= 1;
end;

end.