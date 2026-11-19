unit srRec;

interface

var
  GRec: Integer;
  GLoop: Integer;
  GBad: Integer;

procedure SetRec(N: Integer);
procedure UseRec;
procedure WalkLoop(N: Integer);
procedure WalkBad(N: Integer);
procedure UseBad;

implementation

procedure SetRec(N: Integer);
begin
  GRec:= N;
  if N > 0 then
    SetRec(N - 1);
end;

procedure UseRec;
begin
  Writeln(GRec); // USE-REC
end;

procedure WalkLoop(N: Integer);
begin
  Writeln(GLoop); // USE-LOOP
  if N > 0 then
    WalkLoop(N - 1);
end;

procedure WalkBad(N: Integer);
begin
  if N > 0 then
    WalkBad(N - 1)
  else
    GBad:= 1;
end;

procedure UseBad;
begin
  Writeln(GBad); // USE-BAD
end;

end.
