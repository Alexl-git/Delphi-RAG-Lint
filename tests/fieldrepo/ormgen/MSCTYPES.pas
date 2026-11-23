unit MSCTYPES;

{ Stub of the ORM3 unit of the same name: the enumeration the fixture table uses. }

interface

type
  TOrderStatus = (osNew, osOpen, osDone);

  TOrderStatusHelper = record helper for TOrderStatus
    function ToByte: Byte;
    class function FromByte(const pValue: Byte): TOrderStatus; static;
  end;

implementation

class function TOrderStatusHelper.FromByte(const pValue: Byte): TOrderStatus;
begin
  Result := TOrderStatus(pValue);
end;

function TOrderStatusHelper.ToByte: Byte;
begin
  Result := Ord(Self);
end;

end.
