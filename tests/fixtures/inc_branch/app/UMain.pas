unit UMain;

interface

{$DEFINE HOSTFEAT}
{$I Defs.inc}

{$IFDEF WIN32}{$I A.INC}{$ENDIF}
{$IFDEF WIN64}{$I C.INC}{$ENDIF}
{$IFDEF UNIX}{$I B.INC}{$ENDIF}
{$IFDEF NEVER_DEFINED_INC_X}{$I Dead.inc}{$ENDIF}
{$IFDEF LOCALFEAT}{$I LocalFeat.inc}{$ENDIF}
{$IFDEF PRO_FEATURES}{$I ..\addon\Pro.inc}{$ENDIF}
{$I SpFound.inc}
{$I Outer.inc}

type
  TWorker = class
  public
    procedure Run;
    function Twice(AValue: Integer): Integer;
  end;

procedure HostFeatOnCall;
procedure HostFeatOffCall;

implementation

procedure HostFeatOnCall;
begin
end;

procedure HostFeatOffCall;
begin
end;

{$I Frag.inc}

end.