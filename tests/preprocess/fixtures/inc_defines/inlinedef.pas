unit inlinedef;

{ POSITIVE CONTROL: identical shape, but the define is INLINE. This already
  worked before the fix, and proves nested conditional evaluation itself is
  fine -- so a failure of viainc.pas is about the include boundary and nothing
  else. If this ever fails, the preprocessor broke generally. }

{$DEFINE FEATURE_X}

interface

{$IFNDEF FEATURE_X}
  !! Error: FEATURE_X was defined inline
{$ENDIF}

procedure Beta;

implementation

procedure Beta; begin end;

end.
