unit basic;

interface

procedure P(X: Integer);

implementation

procedure P(X: Integer);
begin
  if X = 1 then
    Writeln('one');
  if (X + 1) = 2 then
    Writeln('two')
  else
  begin
    Writeln('other');
    Writeln('more');
  end;
  if X = 3 then Writeln('three');
end;

end.
