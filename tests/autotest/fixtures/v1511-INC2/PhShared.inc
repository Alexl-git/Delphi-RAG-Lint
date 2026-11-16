procedure SharedRun;
begin
  Emit;
  UProc;
  Clash;
end;

procedure TWork.Run;
begin
  Helper;
  FCount:= 1;
end;

procedure SharedTotal;
begin
  gTotal:= cLimit;
end;
