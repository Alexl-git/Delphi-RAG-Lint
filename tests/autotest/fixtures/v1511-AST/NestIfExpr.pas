unit NestIfExpr;

interface

procedure FiveAndExpr(A: Integer);
procedure SixIfs(A: Integer);

implementation

{ Y2: five control levels; the if-EXPRESSION on the innermost line is not a level. }
procedure FiveAndExpr(A: Integer);
var
  I, X: Integer;
begin
  if A > 0 then
    while A > 1 do
      for I:= 0 to A do
        if I > 2 then
          if I > 3 then
            X:= if I > 4 then 1 else if I > 5 then 2 else 3;
end;

{ Positive control: six statement ifs still nest 6 deep. }
procedure SixIfs(A: Integer);
begin
  if A > 1 then
    if A > 2 then
      if A > 3 then
        if A > 4 then
          if A > 5 then
            if A > 6 then
              A:= 0;
end;

end.