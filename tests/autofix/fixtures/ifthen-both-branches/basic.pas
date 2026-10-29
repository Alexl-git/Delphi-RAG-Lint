unit basic;

interface

implementation

function P(C: Boolean; X: Integer; S: string): Integer;
begin
  Result := IfThen(C, Length(S), Length(S));
end;

end.
