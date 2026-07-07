unit ProbeHelper;
interface
type
  TColor = (clRed, clGreen, clBlue);
  TColorHelper = record helper for TColor
    function ToByte: Byte;
  end;
  TPlain = record
    Field: TColor;
  end;
implementation
function TColorHelper.ToByte: Byte;
begin
  Result := Ord(Self);
end;
end.
