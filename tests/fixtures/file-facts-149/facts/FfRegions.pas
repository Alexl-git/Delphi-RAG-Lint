unit FfRegions;

interface

{$DEFINE FF_ON}
{$IFDEF FF_ON}
const CA = 1;
  {$IFDEF FF_OFF}
  const CB = 2;
  {$ELSE}
  const CC = 3;
  {$ENDIF}
{$ELSE}
const CD = 4;
{$ENDIF}
{$IF FF_UNDEFINED_NAME}
const CE = 5;
{$ELSEIF Defined(FF_ON)}
const CF = 6;
{$IFEND}

implementation

end.
