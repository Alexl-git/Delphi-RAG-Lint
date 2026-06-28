unit PCharArith;

interface

implementation

procedure Bad;
var
  PStr: PChar;
  N: Integer;
begin
  PStr := PStr + N;
  PStr := PStr + 1;
end;

procedure Good;
var
  S: string;
  N: Integer;
begin
  N := N + 1;
  S := S + 'x';
end;

end.
