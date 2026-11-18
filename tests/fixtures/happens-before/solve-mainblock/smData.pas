unit smData;

interface

var
  GMain: Integer;
  GLate: Integer;

procedure UseMain;
procedure UseLate;

implementation

procedure UseMain;
begin
  Writeln(GMain); // USE-MAIN
end;

procedure UseLate;
begin
  Writeln(GLate); // USE-LATE
end;

end.
