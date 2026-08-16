unit viainc;

{ RED: the define arrives through the include. Before the fix the indexer
  preprocessed with IncludeMode 'off', so FEATURE_X stayed undefined, the
  IFNDEF branch stayed LIVE, and the deliberate !! breaker below was parsed as
  code -- 0 symbols, 1 error, the whole unit lost. }

{$I guard.inc}

interface

{$IFNDEF FEATURE_X}
  !! Error: FEATURE_X must come from guard.inc
{$ENDIF}

procedure Alpha;

implementation

procedure Alpha; begin end;

end.
