unit uPosType;

interface

uses uA, uB;

function MakeIt: TObject;

implementation

function MakeIt: TObject;
begin
  Result := TWidget.Create;
end;

end.