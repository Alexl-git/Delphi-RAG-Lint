unit assign;

interface

procedure P(C: Boolean; var X: Integer);

implementation

procedure P(C: Boolean; var X: Integer);
begin
  X := 1;
  X := 3;
  Writeln('end');
end;

end.
