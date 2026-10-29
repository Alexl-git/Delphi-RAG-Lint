unit basic;

interface

type
  TByteSet = set of Byte;

implementation

function P(A: Integer; S: TByteSet): Boolean;
begin
  Result := not A in S;
end;

end.
