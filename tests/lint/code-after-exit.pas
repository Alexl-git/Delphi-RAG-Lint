unit CodeAfterExit;

interface

implementation

procedure P;
begin
  Exit;
  WriteLn('dead');
end;

procedure Q(X: Integer);
begin
  if X > 0 then
    Exit;
  WriteLn('not dead');
end;

procedure R;
begin
  Exit;  { trailing comment is not code }
end;

procedure S(X: Integer);
begin
  if X = 0 then Exit;
  Exit; // unconditional exit with a trailing comment -- the comment is not code
end;

end.
