unit uCycA;

{ uCycA.interface is used by uCycB.interface, and uCycA.implementation uses
  uCycB -- the classic implementation-section cycle that `cycles --causes`
  exists to explain.

  UseIt declares a LOCAL named SharedName. Delphi resolves that name to the
  local, so it is NOT coupling to uCycB and must not be listed as a cause.
  RealThing IS coupling and must still be listed. }

interface

procedure TouchA;
procedure UseIt;

implementation

uses
  uCycB;

procedure TouchA;
begin
end;

procedure UseIt;
var
  SharedName: string;
begin
  SharedName := 'x';
  RealThing;
end;

end.
