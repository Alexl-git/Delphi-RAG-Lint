unit DefA;

// E18 T15b fixture incuses: the plain half of the DefA <-> DefB cycle.

interface

/// <summary>Calls into DefB.</summary>
procedure RunDefA;
/// <summary>Called back from DefB.</summary>
function ValueDefA: Integer;

implementation

uses
  DefB;

procedure RunDefA;
begin
  Writeln(ValueDefB);
end;

function ValueDefA: Integer;
begin
  Result:= 1;
end;

end.