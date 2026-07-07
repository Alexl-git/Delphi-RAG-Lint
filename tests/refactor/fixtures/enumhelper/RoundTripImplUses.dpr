program RoundTripImplUses;
{$APPTYPE CONSOLE}

// Mandatory Task-6 fixture (Task 4 review gap): compiled and run against a
// temp copy of has_impl_uses.pas AFTER create-enum-helper --apply has
// generated TShadeHelper (RTTI ToString/FromString) into it. HasImplUses.pas
// already has an implementation 'uses System.SysUtils;' clause BEFORE the
// apply -- proving System.TypInfo is appended to that EXISTING uses clause
// (not a second/duplicate uses clause) and the generated bodies land after
// it (no E2029), by virtue of this compiling and running at all.

uses
  HasImplUses;

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
  Check('shLight.ToByte = 0'                     , shLight.ToByte = 0);
  Check('TShade.FromByte(2) = shDark'            , TShade.FromByte(2) = shDark);
  Check('shMedium.ToString = ''shMedium'''       , shMedium.ToString = 'shMedium');
  Check('TShade.FromString(''shDark'') = shDark' , TShade.FromString('shDark') = shDark);
  Check('TShade.FromInteger(1) = shMedium'       , TShade.FromInteger(1) = shMedium);
  if GFail > 0 then Halt(1) else Halt(0);
end.
