unit basic;

interface

uses
  System.SyncObjs;

procedure P;
procedure Q;

implementation

procedure DoWork;
begin
end;

procedure P;
var
  Lock: TCriticalSection;
begin
  Lock := TCriticalSection.Create;
  Lock.Enter;
  try
    DoWork;
    Writeln('x');
  finally
    Lock.Leave;
  end;
  Lock.Free;
end;

procedure Q;
var
  LockA: TObject;
begin
  LockA := TObject.Create;
  TMonitor.Enter(LockA);
  try
    DoWork;
  finally
    TMonitor.Exit(LockA);
  end;
  LockA.Free;
end;

end.
