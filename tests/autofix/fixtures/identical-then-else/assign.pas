unit assign;

interface

procedure P(C: Boolean; var X: Integer);

implementation

procedure P(C: Boolean; var X: Integer);
begin
  if C then X := 1 else X := 1;
  if C and (X > 0) then
    X := 3
  else
    X := 3;
  Writeln('end');
end;

end.
