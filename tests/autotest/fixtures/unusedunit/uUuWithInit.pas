unit uUuWithInit;

{ Fixture: a unit with an export AND an initialization section.

  An import of this that references nothing may STILL be load-bearing -- the
  initialization is the work -- and removing it can build cleanly and fail at
  runtime. That is the one hazard the index cannot settle, so it must be
  reported at INFO rather than WARNING. }

interface

type
  TZzWithInitThing = class
  public
    procedure Idle;
  end;

var
  ZzRegistered: Boolean;

implementation

procedure TZzWithInitThing.Idle;
begin
end;

initialization
  ZzRegistered:= True;

end.
