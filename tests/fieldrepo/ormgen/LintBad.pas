unit LintBad;

{ Positive control of run_fieldrepo_ormgen_run.ps1: every rule the generated units must be clean of
  fires here. Never compiled into the test program. }

interface

uses
  System.Classes,
  System.Math;

type
  TmcBad = class(TPersistent)
  private
    fCODE: string;
    function GetZNAME: string;
    procedure SetZNAME(const Value: string);
  public
    procedure Assign(Source: TPersistent); override;
    /// <summary>
    /// Summary here
    /// </summary>
    property CODE: string read fCODE write fCODE;
    property NAME: string read GetZNAME write SetZNAME;
  end;

implementation

uses
  System.SysUtils;

procedure TmcBad.Assign(Source: TPersistent);
var
  ByteTemp: Byte;
begin
  if not (Source is TmcBad) then
    inherited
  else
    with Source as TmcBad do
    begin
      fCODE := CODE;
    end;
end;

function TmcBad.GetZNAME: string;
begin
  Result := fCODE;
end;

procedure TmcBad.SetZNAME(const Value: string);
begin
  if Value = '' then
    raise Exception.Create('empty');
  fCODE := Value;
end;

end.
