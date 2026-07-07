program RoundTripMultiLine;
{$APPTYPE CONSOLE}

// Task 6b review-fix acceptance-gate proof: compiled and run against a temp
// copy of MultiLineOrdinals.pas AFTER create-enum-helper --apply has
// generated TStageHelper into it WITH NO --tostring FLAG AT ALL (the CLI
// default, tsmRtti). TStage = (stInit = 1, stMid = 5, stEnd = 9) is declared
// across MULTIPLE source lines, with every member on an explicit ordinal on
// a line AFTER the enum's own 'type'/'TStage = (' line -- the real-world
// MSCTYPES.PAS shape ReadDeclSpan's multi-line span read exists for. This
// program compiling and running at all is the proof the generator both (a)
// DETECTED the explicit ordinals via the multi-line span read and (b)
// auto-fell-back to case-mode ToString/FromString under the default, exactly
// as it would for any real caller who runs `create-enum-helper --qname
// TStage` with no --tostring override.

uses
  MultiLineOrdinals;

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
  Check('stInit.ToByte = 1'                         , stInit.ToByte = 1);
  Check('TStage.FromByte(9) = stEnd'                , TStage.FromByte(9) = stEnd);
  Check('stMid.ToString = ''stMid'''                , stMid.ToString = 'stMid');
  Check('TStage.FromString(''stEnd'') = stEnd'      , TStage.FromString('stEnd') = stEnd);
  Check('TStage.FromInteger(5) = stMid'              , TStage.FromInteger(5) = stMid);
  if GFail > 0 then Halt(1) else Halt(0);
end.
