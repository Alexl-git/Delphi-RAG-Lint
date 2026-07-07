program RoundTripSimple;
{$APPTYPE CONSOLE}

// Case 8 acceptance gate: compiled and run against a temp copy of
// simple.pas AFTER create-enum-helper --apply has generated TColorHelper
// into it. Exercises all 6 generated methods and exits nonzero on any
// failed round-trip assert (see spec Section 9, case 1/8). Copied
// alongside the applied Simple.pas by run_enum_helper.ps1 before the
// dcc64 -B compile, so 'uses Simple' resolves to the applied unit, not
// this repo copy of the fixture.

uses
  Simple;

var
  GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if not ACond then
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName);
  end
  else
    Writeln('PASS  ', AName);
end;

begin
  GFail:= 0;
  Check('clRed.ToByte = 0'                 , clRed.ToByte = 0);
  Check('TColor.FromByte(2) = clBlue'      , TColor.FromByte(2) = clBlue);
  Check('clGreen.ToString = ''clGreen'''   , clGreen.ToString = 'clGreen');
  Check('TColor.FromString(''clBlue'') = clBlue', TColor.FromString('clBlue') = clBlue);
  Check('TColor.FromInteger(1) = clGreen'  , TColor.FromInteger(1) = clGreen);
  if GFail > 0 then Halt(1) else Halt(0);
end.
