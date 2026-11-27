unit uNegQualified;

interface

uses uA, uB;

function RunQ(const S: string): string;

implementation

function RunQ(const S: string): string;
begin
  Result := uA.Normalize(S);
end;

end.