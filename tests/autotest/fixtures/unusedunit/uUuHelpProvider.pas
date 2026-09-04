unit uUuHelpProvider;

{ Fixture for run_unused_unit_helpers.ps1.

  Declares a TYPE HELPER and nothing else worth naming. A consumer that calls
  ZzShout on a string names this unit's helper MEMBER without naming the unit's
  own type -- the exact shape unused-unit-in-uses could not see. }

interface

type
  TZzStringHelper = record helper for string
    function ZzShout: string;
  end;

implementation

uses
  System.SysUtils;

function TZzStringHelper.ZzShout: string;
begin
  Result:= UpperCase(Self);
end;

end.
