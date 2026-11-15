procedure THost.Run;
var
  R: THidden;
begin
  Helper;
  HostProc;
  gHost:= cHost + HostFn + cUsed;
  R.V:= gHost;
  UProc;
end;

procedure IncLocal;
var
  T: THost;
begin
  T:= THost.Create;
  T.Run;
  T.Free;
end;
