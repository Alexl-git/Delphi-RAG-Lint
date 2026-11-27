unit uExtUse;

interface

uses uExtA, uExtB;

function Probe: Integer;

implementation

function Probe: Integer;
begin
  Result := ExtVersion;
end;

end.