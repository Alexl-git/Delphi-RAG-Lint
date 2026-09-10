unit CriticalSectionNotReleased;

interface

implementation

procedure Bad;
var
  Lock: TCriticalSection;
begin
  Lock.Enter;
  DoWork;
end;

procedure Good;
var
  Lock: TCriticalSection;
begin
  Lock.Enter;
  try
    DoWork;
  finally
    Lock.Leave;
  end;
end;

procedure GoodMonitor;
var
  LockA: TObject;
begin
  TMonitor.Enter(LockA);
  try
    DoWork;
  finally
    TMonitor.Exit(LockA);
  end;
end;

procedure BadMonitorNoExit;
var
  LockA: TObject;
begin
  TMonitor.Enter(LockA);
  DoWork;
end;

procedure BadMonitorExitOutsideFinally;
var
  LockA: TObject;
begin
  TMonitor.Enter(LockA);
  DoWork;
  TMonitor.Exit(LockA);
end;

procedure BadMonitorMixed;
var
  LockA: TObject;
  LockB: TObject;
begin
  TMonitor.Enter(LockA);
  try
    DoWork;
  finally
    TMonitor.Exit(LockA);
  end;
  TMonitor.Enter(LockB);
  DoWork;
end;

end.
