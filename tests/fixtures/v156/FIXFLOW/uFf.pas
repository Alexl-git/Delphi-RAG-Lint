unit uFf;

{ Fixture of tests\autotest\run_v156_FIXFLOW.ps1. A line marked FIRE must report the rule named
  after it; every other line must stay silent. }

interface

function CrossUnitFail(AFlag: Boolean): Integer;
function RealMissing(AFlag: Boolean): Integer;
function HashIt(const AText: string; AEnc: TEncoding): string;

implementation

uses
  System.SysUtils, System.Hash, uFfOther;

function CrossUnitFail(AFlag: Boolean): Integer;
begin
  if AFlag then Exit(1);
  Fail('x');
end;

function RealMissing(AFlag: Boolean): Integer; // FIRE function-result-not-set
begin
  if AFlag then Exit(1);
end;

function HashIt(const AText: string; AEnc: TEncoding): string;
var
  VHash: THashSHA2;
begin
  VHash := THashSHA2.Create;
  VHash.Update(AEnc.GetBytes(AText));
  Result := VHash.HashAsString;
end;

end.
