unit basic;

interface

implementation

uses
  System.Classes;

function P(O: TObject): Boolean;
begin
  Result := (O is not TComponent);
  Result := Result and (O is not TStrings);
end;

end.
