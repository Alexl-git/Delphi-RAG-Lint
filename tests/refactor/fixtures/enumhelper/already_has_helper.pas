unit AlreadyHasHelper;
interface
type
  TStatus = (stNew, stActive, stDone);
  TStatusHelper = record helper for TStatus
    function ToByte: Byte;
  end;
const
  TStatusDescriptions: array[TStatus] of string = (
    'New', 'Active', 'Done');
implementation
function TStatusHelper.ToByte: Byte;
begin
  Result := Ord(Self);
end;
end.
