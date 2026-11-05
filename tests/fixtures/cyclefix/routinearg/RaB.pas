unit RaB;

interface

/// <summary>Prints a text.</summary>
/// <param name="pText">The text.</param>
procedure RaBSay(const pText: string);

/// <summary>A fixed value.</summary>
/// <returns>5.</returns>
function RaBFive: Integer;

implementation

uses
  RaA;

procedure RaBSay(const pText: string);
begin
  Writeln(pText, RaAFive);
end;

function RaBFive: Integer;
begin
  Result:= 5;
end;

end.
