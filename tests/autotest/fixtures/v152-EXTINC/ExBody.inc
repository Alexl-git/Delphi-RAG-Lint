procedure Work;
begin
{$IFDEF COMPILE1}
  PingA;
{$ELSE}
  PingB;
{$ENDIF}
end;