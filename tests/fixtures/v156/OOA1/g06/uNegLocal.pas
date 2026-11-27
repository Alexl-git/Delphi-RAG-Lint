unit uNegLocal;

interface

uses uA, uB;

function RunLocal: Integer;

implementation

function RunLocal: Integer;
var
  Normalize: Integer;
begin
  Normalize := 3;
  Result := Normalize;
end;

end.