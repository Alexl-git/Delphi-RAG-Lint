unit SqlConcat;

interface

implementation

procedure P(V: string);
var
  S: string;
begin
  S := 'SELECT * FROM T WHERE x=' + V;
  S := 'Hello ' + V;
end;

end.
