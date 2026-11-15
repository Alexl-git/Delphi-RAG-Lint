unit uMain;

interface

procedure Run;

implementation

uses
  uDice;

procedure Run;
begin
  Writeln(RollDie);
  // Randomize in a comment must not count
end;

end.
