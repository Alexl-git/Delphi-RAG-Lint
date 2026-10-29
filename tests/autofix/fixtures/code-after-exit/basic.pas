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
    Writeln('dead1');
    { dead note }
    Writeln('dead2');
  end;
  Writeln('live');
end;

end.
