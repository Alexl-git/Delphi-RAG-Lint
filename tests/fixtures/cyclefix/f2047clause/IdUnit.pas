unit IdUnit;

interface

const
  IdBase = 30;
  IdValue = 31;

implementation

uses
  IcUnit;

function IdPeek: Integer;
begin
  Result := IcValue;
end;

end.