unit LiCrossReader;

interface

function CrossValue: Integer;

implementation

uses
  LiHeavy, LiLight;

function CrossValue: Integer;
begin
  Result:= GShared + LightValue;
end;

initialization
  Writeln('LiCrossReader init ', GShared);
end.