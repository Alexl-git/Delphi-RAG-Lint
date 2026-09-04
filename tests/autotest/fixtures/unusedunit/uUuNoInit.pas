unit uUuNoInit;

{ Fixture: an ordinary unit with an export and NO initialization section.
  An import of this that references nothing is a plain dead import -- nothing
  invisible can be doing work here -- so it must be reported at WARNING. }

interface

type
  TZzNoInitThing = class
  public
    procedure Idle;
  end;

implementation

procedure TZzNoInitThing.Idle;
begin
end;

end.
