unit MagicLiteralLabels;
{ magic-literal: a numeric label, a goto target and a string code page name
  a place, not a quantity -- none of them is a magic number. }
interface
type
  TLatinText = type AnsiString(1252);
function JumpAround(pN: Integer): Integer;
implementation
function JumpAround(pN: Integer): Integer;
label
  99;
begin
  Result := 0;
  if pN > 0 then
    goto 99;
  Result := pN;
  99:
  Result := Result + pN;
end;
end.
