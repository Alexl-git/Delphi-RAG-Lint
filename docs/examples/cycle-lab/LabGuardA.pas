unit LabGuardA;

interface

uses
{$IFDEF LAB_EXTRA}
  LabGuardB,
{$ENDIF}
  System.SysUtils;

type
  TLabGuardA = class
  public
    function Name: string;
    function Peer: TLabGuardB;
  end;

implementation

function TLabGuardA.Peer: TLabGuardB;
begin
  Result := TLabGuardB.Create;
end;

function TLabGuardA.Name: string;
begin
  Result := 'guard-a';
end;

end.
