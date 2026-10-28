unit UMain;

// INC3 lane fixture: $IF over true constants -- same file, a used project unit,
// a used library unit -- plus Declared(), a typed constant (not a true constant,
// dcc rejects it in $IF) and a constant declared only in an inactive branch.

interface

uses
  UConsts, LibConsts;

const
  DEBUG2 = 3;
  LOCAL_SUM = DEBUG2 * 2 + 1;
  TYPED_C: Integer = 3;

{$IFDEF NEVERDEFINED}
const
  GHOST = 1;
{$ENDIF}

{$IF DEBUG2 = 3}
{$I A.INC}
{$ELSE}
{$I B.INC}
{$IFEND}

{$IF LOCAL_SUM = 7}
{$I SUM_YES.INC}
{$ELSE}
{$I SUM_NO.INC}
{$IFEND}

{$IF PROJ_LEVEL = 5}
{$I PROJ_YES.INC}
{$ELSE}
{$I PROJ_NO.INC}
{$IFEND}

{$IF LIB_LEVEL = 9}
{$I LIB_YES.INC}
{$ELSE}
{$I LIB_NO.INC}
{$IFEND}

{$IF GHOST = 1}
{$I GHOST_YES.INC}
{$ELSE}
{$I GHOST_NO.INC}
{$IFEND}

{$IF TYPED_C = 3}
{$I TYPED_YES.INC}
{$ELSE}
{$I TYPED_NO.INC}
{$IFEND}

{$IF Declared(DEBUG2) and Declared(TLibThing) and not Declared(NOSUCHTHING)}
{$I DECL_YES.INC}
{$ELSE}
{$I DECL_NO.INC}
{$IFEND}

{$IF NOSUCHNAME = 1}
{$I NOSUCH_YES.INC}
{$ELSE}
{$I NOSUCH_NO.INC}
{$IFEND}

{$IF LIB_TYPED = 9}
{$I LTYPED_YES.INC}
{$ELSE}
{$I LTYPED_NO.INC}
{$IFEND}

implementation

end.