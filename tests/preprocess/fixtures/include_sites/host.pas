unit Host;

// N-06 T1 fixture: one active {$I} (live.inc) and one in an inactive branch.

interface

  {$I live.inc}
{$IFDEF NEVER_DEFINED}
{$I dead.inc}
{$ENDIF}

implementation

end.