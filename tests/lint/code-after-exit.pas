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

end.
