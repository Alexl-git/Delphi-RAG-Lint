unit basic;

interface

implementation

function P(O: TObject): Boolean;
begin
  Result := not (O is TComponent);
  Result := Result and not (O is TStrings);
end;

end.
