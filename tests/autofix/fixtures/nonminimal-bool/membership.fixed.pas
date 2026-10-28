unit membership;

interface

implementation

type
  TByteSet = set of Byte;

function P(A: Integer; const S: TByteSet; C: Boolean): Boolean;
begin
  Result := (A not in S);
  Result := C and (A not in S);
end;

end.
