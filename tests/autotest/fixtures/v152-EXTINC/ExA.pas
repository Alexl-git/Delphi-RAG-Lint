unit ExA;

interface

{$DEFINE COMPILE1}
{$I ExShared.inc}

procedure Work;

implementation

procedure PingA;
begin
end;

procedure PingB;
begin
end;

{$I ExBody.inc}

end.