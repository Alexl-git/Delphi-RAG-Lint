// A fragment: method bodies, no unit header. HOSTFEAT is defined by the host.
procedure TWorker.Run;
begin
{$IFDEF HOSTFEAT}
  HostFeatOnCall;
{$ELSE}
  HostFeatOffCall;
{$ENDIF}
end;

function TWorker.Twice(AValue: Integer): Integer;
begin
  Result := AValue * 2;
end;