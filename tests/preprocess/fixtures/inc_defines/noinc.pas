unit noinc;

{ NEGATIVE CONTROL: this unit includes NOTHING, so FEATURE_X must stay
  undefined and the breaker must still fire (1 error, 0 symbols).

  This is the control that fails if the fix is implemented by seeding
  FEATURE_X globally, or if one file's include defines LEAK into the next
  file of the same index run. Without it, "viainc.pas parses" could be
  achieved by simply defining everything everywhere. }

interface

{$IFNDEF FEATURE_X}
  !! Error: FEATURE_X must NOT be defined here
{$ENDIF}

procedure Gamma;

implementation

procedure Gamma; begin end;

end.
