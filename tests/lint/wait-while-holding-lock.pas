unit WaitWhileHoldingLock;

interface

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows;

var
  GLock: TObject;
  GOther: TObject;
  GCS: TRTLCriticalSection;
  FLock: TCriticalSection;

procedure HitSynchronize(T: TThread);
begin
  FLock.Enter;
  T.Synchronize(nil);
  FLock.Leave;
end;

procedure HitWaitForInFinally(T: TThread);
begin
  FLock.Acquire;
  try
    T.WaitFor;
  finally
    FLock.Release;
  end;
end;

procedure HitSleepMonitor;
begin
  TMonitor.Enter(GLock);
  try
    Sleep(10);
  finally
    TMonitor.Exit(GLock);
  end;
end;

procedure HitSleepCritSect;
begin
  EnterCriticalSection(GCS);
  Sleep(10);
  LeaveCriticalSection(GCS);
end;

procedure HitOtherLockLeft;
begin
  TMonitor.Enter(GLock);
  TMonitor.Exit(GOther);
  Sleep(10);
  TMonitor.Exit(GLock);
end;

procedure CleanAfterLeave;
begin
  FLock.Enter;
  try
    GLock := nil;
  finally
    FLock.Leave;
  end;
  Sleep(10);
end;

procedure CleanBeforeEnter;
begin
  Sleep(10);
  FLock.Enter;
  FLock.Leave;
end;

procedure CleanNestedRoutine;
  procedure Inner;
  begin
    Sleep(10);
  end;
begin
  FLock.Enter;
  GLock := nil;
  FLock.Leave;
  Inner;
end;

end.
