unit basic;

interface

implementation

uses
  System.Classes;

function P(O: TObject): Boolean;
begin
  Result := not (O is TComponent);
  Result := Result and not (O is TStrings);
end;

end.
