unit pipeline_fixture;

{ THIS FIXTURE MUST PRODUCE A WARNING, NOT AN ERROR.

  run_pipeline_tests.ps1 uses it to test the --fail-on GRADATION: that
  `--fail-on error` exits 0 while `--fail-on warning` exits 1, and that a
  --config severity bump then makes `--fail-on error` trip. All three assertions
  are vacuous unless the finding sits BELOW error.

  used-before-assignment has two levels. A local read on a path where it was
  definitely never written is an ERROR; one written on SOME path but not all is
  a WARNING ("may be used before it is assigned"). This fixture is deliberately
  the second: `n` is assigned only when AFlag is true.

  It used to be the first -- a bare `var n: Integer; Result := n + 1;`. That was
  correct while the rule was warning-severity throughout, and 9f78db3 raised the
  definite case to error, which turned "fail-on error => 0 (only warning)" red.
  The failure was NOT noticed for a session because the severity change was
  verified against the golden and flow suites rather than a full battery run.

  So: if you simplify this back to an unconditional read, three checks above go
  red and a fourth stops proving anything. Keep the branch. }

interface

function Compute(const AFlag: Boolean): Integer;

implementation

function Compute(const AFlag: Boolean): Integer;
var n: Integer;
begin
  if AFlag then n:= 7;
  Result:= n + 1;   // used-before-assignment (MAY): assigned on one path only
end;

end.
