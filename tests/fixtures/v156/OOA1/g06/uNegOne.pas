unit uNegOne;

interface

uses uA;

function RunOne(const S: string): string;

implementation

function RunOne(const S: string): string;
begin
  Result := Normalize(S);
end;

end.