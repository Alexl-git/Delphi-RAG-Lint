unit IsNotOp;

interface

implementation

uses Classes;

procedure Bad(O: TObject);
begin
  if not (O is TStrings) then
    Exit;
  if not (O is TComponent) and (O <> nil) then
    Exit;
end;

procedure Good(O: TObject; N: Integer);
begin
  if O is not TStrings then
    Exit;
  if not (N = 3) then
    Exit;
  if not Assigned(O) then
    Exit;
  if (O is TStrings) then
    Exit;
end;

end.
