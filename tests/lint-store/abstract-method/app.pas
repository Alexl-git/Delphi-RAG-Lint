unit app;

interface

implementation

uses shapes;

procedure MakeThem;
var
  s: TShape;
  c: TCircle;
begin
  s := TShape.Create;
  c := TCircle.Create;
  s.Free;
  c.Free;
end;

end.
