unit IncHostH;

interface

uses
  IncHostU;

type
  THost = class
  public
    procedure Run;
    procedure Helper;
  end;

const
  cHost = 3;

var
  gHost: Integer;

procedure HostProc;
function HostFn: Integer;

implementation

type
  THidden = record
    V: Integer;
  end;

procedure THost.Helper;
begin
end;

procedure HostProc;
begin
end;

function HostFn: Integer;
begin
  Result:= cHost;
end;

{$I IncHostH_impl.inc}

end.
