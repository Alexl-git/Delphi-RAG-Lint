unit uNegOwn;

interface

uses uA, uB;

function Normalize(const S: string): string;

implementation

function Normalize(const S: string): string;
begin
  Result := S;
end;

function Other(const S: string): string;
begin
  Result := Normalize(S);
end;

end.