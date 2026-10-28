unit membership;

interface

implementation

type
  TByteSet = set of Byte;

function P(A: Integer; const S: TByteSet; C: Boolean): Boolean;
begin
  Result := not (A in S);
  Result := C and not (A in S);
end;

end.
