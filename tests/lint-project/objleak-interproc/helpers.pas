unit helpers;

interface

uses System.Classes;

procedure UseButDontFree(o: TStringList);
procedure TakeAndFree(o: TStringList);

implementation

procedure UseButDontFree(o: TStringList);
begin
  o.Clear;
end;

procedure TakeAndFree(o: TStringList);
begin
  o.Free;
end;

end.
