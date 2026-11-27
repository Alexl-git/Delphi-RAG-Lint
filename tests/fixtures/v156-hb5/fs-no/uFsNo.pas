unit uFsNo;

{ Fixture of run_v156_HB5.ps1, preset format-settings: nothing writes FormatSettings -> NO (a-never-happens). }

interface

uses
  System.SysUtils;

function Show(pValue: Double): string;

implementation

function Show(pValue: Double): string;
begin
  Result:= FloatToStr(pValue);
end;

end.
