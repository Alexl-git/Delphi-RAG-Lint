unit uEx3Local;

interface

uses
  uEx3Types;

function LocalSum: Integer;
function IsRunner(AObj: TObject): Boolean;

implementation

function LocalSum: Integer;
const
  CLocal: TEx3Rec = (Alpha: 3; Beta: 4);
  CLocalPlain = 5;
begin
  Result := CLocal.Alpha + CLocal.Beta + CLocalPlain;
end;

function IsRunner(AObj: TObject): Boolean;
begin
  Result := AObj is uEx3Types.TEx3Runner;
  if AObj is TEx3Base then
    Result := not Result;
end;

end.