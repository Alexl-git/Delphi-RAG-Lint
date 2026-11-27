unit uPosCall;

interface

uses uA, uB;

function RunPos(const S: string): string;

implementation

function RunPos(const S: string): string;
begin
  Result := Normalize(S);
end;

end.