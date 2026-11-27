unit uOrdGame;

{ Fixture of run_v156_HB5.ps1 (program order): the one Random call of the program. }

interface

var
  GLast: Integer;

procedure RunGame;

implementation

procedure RunGame;
begin
  GLast:= Random(6);
end;

end.
