unit uDice;

interface

function RollDie: Integer;

implementation

function RollDie: Integer;
begin
  Result := Random(6) + 1; // fires: nothing in the project seeds Random
end;

end.
