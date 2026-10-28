unit ExtraUnit;

{ Fixture for tests\autotest\run_concept_search.ps1. The runner rewrites this
  unit to add and remove one documented routine (incremental checks). }

interface

type
  TExtra = class
  public
    procedure Placeholder;
  end;

implementation

procedure TExtra.Placeholder;
begin
end;

end.
