unit keep;
interface
uses
  System.SyncObjs;
implementation
procedure DoWork;
begin
end;
procedure P(Lock: TCriticalSection);
begin
  Lock.Enter;
  DoWork;
end;
end.
