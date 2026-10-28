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
  DoWork;
  Writeln('x');
  Lock.Leave;
  Lock.Free;
end;

procedure Q;
var
  LockA: TObject;
begin
  LockA := TObject.Create;
  TMonitor.Enter(LockA);
  DoWork;
  TMonitor.Exit(LockA);
  LockA.Free;
end;

end.
