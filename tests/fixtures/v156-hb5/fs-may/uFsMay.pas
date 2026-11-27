unit uFsMay;

{ Fixture of run_v156_HB5.ps1, preset format-settings: FormatSettings is written in another routine nothing orders -> MAY. }

interface

uses
  System.SysUtils;

function Show(pValue: Double): string;

implementation

procedure Setup;
begin
  FormatSettings.DecimalSeparator:= '.';
end;

function Show(pValue: Double): string;
begin
  Result:= FloatToStr(pValue);
end;

end.
