unit ModeHelperUnit;
interface
uses
  Mode;
type
  TModeHelper = record helper for TMode
    function ToByte: Byte;
  end;
implementation
function TModeHelper.ToByte: Byte;
begin
  Result := Ord(Self);
end;
end.
