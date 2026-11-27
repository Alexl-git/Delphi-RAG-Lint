unit uFsYes;

{ Fixture of run_v156_HB5.ps1, preset format-settings: FormatSettings is written before the one FloatToStr, same routine -> YES. }

interface

uses
  System.SysUtils;

function Show(pValue: Double): string;

implementation

function Show(pValue: Double): string;
begin
  FormatSettings.DecimalSeparator:= '.';
  Result:= FloatToStr(pValue);
end;

end.
