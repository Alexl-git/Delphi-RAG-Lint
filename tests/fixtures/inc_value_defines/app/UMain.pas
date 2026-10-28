unit UMain;

// INC2 lane fixture. The .dproj Base group sets DEBUG2=3 and FEATX; the active
// config (Debug) turns range checking on.

interface

{$IF DEBUG2 = 3}
{$I A.INC}
{$ELSE}
{$I B.INC}
{$IFEND}

{$IF Defined(FEATX) and (DEBUG2 > 1)}
{$I C.INC}
{$IFEND}

{$IFDEF DEBUG2}
{$I D.INC}
{$ENDIF}

{$IFOPT R+}
{$I ROn.inc}
{$ELSE}
{$I ROff.inc}
{$ENDIF}

{$R-}
{$IFOPT R-}
{$I RLocal.inc}
{$ENDIF}

{$IF CompilerVersion >= 37}
{$I CV.inc}
{$IFEND}

implementation

end.