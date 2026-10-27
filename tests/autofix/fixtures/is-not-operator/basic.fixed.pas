unit basic;

interface

implementation

function P(O: TObject): Boolean;
begin
  Result := (O is not TComponent);
  Result := Result and (O is not TStrings);
end;

end.
