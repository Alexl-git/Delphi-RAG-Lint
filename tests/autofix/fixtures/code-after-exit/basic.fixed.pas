unit basic;

interface

procedure P(X: Integer);

implementation

procedure P(X: Integer);
begin
  if X > 0 then
  begin
    Writeln('a');
    Exit;
  end;
  Writeln('live');
end;

end.
