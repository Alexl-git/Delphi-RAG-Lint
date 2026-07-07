program RoundTripOrdinalsDefault;
{$APPTYPE CONSOLE}

// Task 6b acceptance-gate proof: compiled and run against a temp copy of
// explicit_ordinals.pas AFTER create-enum-helper --apply has generated
// TSpecHelper into it WITH NO --tostring FLAG AT ALL (the CLI default,
// tsmRtti). TSpec = (sp_Undefined = 0, sp_Double = 1, sp_Upper = 2) -- every
// member has an explicit ordinal, so Delphi emits no automatic RTTI for it;
// before the Task 6b fallback, requesting the default here produced
// GetEnumName/GetEnumValue calls that failed to compile (E2134 "Type has no
// type info"). This program compiling and running at all is the proof the
// generator auto-fell-back to case-mode ToString/FromString under the
// default, exactly as it would for any real caller who runs
// `create-enum-helper --qname TSpec` with no --tostring override.

uses
  ExplicitOrdinals;

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
  Check('sp_Undefined.ToByte = 0'                        , sp_Undefined.ToByte = 0);
  Check('TSpec.FromByte(2) = sp_Upper'                   , TSpec.FromByte(2) = sp_Upper);
  Check('sp_Double.ToString = ''sp_Double'''             , sp_Double.ToString = 'sp_Double');
  Check('TSpec.FromString(''sp_Upper'') = sp_Upper'      , TSpec.FromString('sp_Upper') = sp_Upper);
  Check('TSpec.FromInteger(1) = sp_Double'               , TSpec.FromInteger(1) = sp_Double);
  if GFail > 0 then Halt(1) else Halt(0);
end.
