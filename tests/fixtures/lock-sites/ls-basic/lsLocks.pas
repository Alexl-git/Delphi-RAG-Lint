unit lsLocks;

{ Fixture of tests\autotest\run_v156_THRS_lock_sites.ps1 (1.56 lane THR-S, S6 lock sites).
  Every lock call carries a marker comment `// SITE-<NAME>` on its own line; the runner finds the line
  by the marker, so the file can be edited without renumbering. }

interface

uses
  System.SysUtils
, System.Classes
, System.SyncObjs
, Winapi.Windows
  ;

type
  /// <summary>Has the method names of a lock and is none: its calls must not be lock sites.</summary>
  TFake = class
  public
    procedure Enter;
    procedure Leave;
    procedure Acquire;
    procedure Release;
  end;

  /// <summary>A lock by descent.</summary>
  TMyLock = class(TCriticalSection)
  end;

  TBank = class
  private
    FLockA: TCriticalSection;
    FLockB: TCriticalSection;
    FRtl: TRTLCriticalSection;
    FGuard: TObject;
    FRw: TMultiReadExclusiveWriteSynchronizer;
    FMutex: TMutex;
    FItems: TThreadList;
    FName: string;
    FFake: TFake;
    FMine: TMyLock;
    FSpin: TSpinLock;
    FGuards: TArray<TObject>;
  public
    procedure AThenB;
    procedure BThenA;
    procedure Unbalanced;
    procedure LocalLock;
    procedure ParamLock(pLock: TCriticalSection);
    procedure GlobalLock;
    procedure ViaSelf;
    procedure MonitorSite;
    procedure WinapiSite;
    procedure RwSite;
    procedure TrySite;
    procedure MutexSite;
    procedure ListSite;
    procedure OtherObject(pOther: TBank);
    procedure NoLocks;
    procedure NotLocks;
    procedure DescendantSite;
    procedure MonitorSelf;
    procedure MonitorTimeout;
    procedure MonitorIndexed;
    procedure MonitorOther(pOther: TBank);
    procedure SpinSite;
  end;

var
  GLock: TCriticalSection;

implementation

procedure TBank.AThenB;
begin
  FName:= ''; // HELD-NONE
  FLockA.Enter; // SITE-A1-ENTER
  try
    FLockB.Enter; // SITE-A1-B-ENTER
    try
      FName:= 'ab'; // HELD-AB
    finally
      FLockB.Leave; // SITE-A1-B-LEAVE
    end;
  finally
    FLockA.Leave; // SITE-A1-LEAVE
  end;
end;

procedure TBank.BThenA;
begin
  FLockB.Acquire; // SITE-B1-ACQUIRE
  try
    FLockA.Acquire; // SITE-B1-A-ACQUIRE
    try
      FName:= 'ba';
    finally
      FLockA.Release; // SITE-B1-A-RELEASE
    end;
  finally
    FLockB.Release; // SITE-B1-RELEASE
  end;
end;

procedure TBank.Unbalanced;
begin
  FLockA.Enter; // SITE-UNBAL-ENTER
  FName:= 'never left'; // HELD-UNBAL
end; // END-UNBAL

procedure TBank.LocalLock;
var
  L: TCriticalSection;
begin
  L:= TCriticalSection.Create;
  try
    L.Enter; // SITE-LOCAL-ENTER
    try
      FName:= 'local';
    finally
      L.Leave; // SITE-LOCAL-LEAVE
    end;
  finally
    L.Free;
  end;
end;

procedure TBank.ParamLock(pLock: TCriticalSection);
begin
  pLock.Enter; // SITE-PARAM-ENTER
  try
    FName:= 'param';
  finally
    pLock.Leave; // SITE-PARAM-LEAVE
  end;
end;

procedure TBank.GlobalLock;
begin
  GLock.Enter; // SITE-GLOBAL-ENTER
  try
    FName:= 'global';
  finally
    GLock.Leave; // SITE-GLOBAL-LEAVE
  end;
end;

procedure TBank.ViaSelf;
begin
  Self.FLockA.Enter; // SITE-SELF-ENTER
  try
    FName:= 'self';
  finally
    Self.FLockA.Leave; // SITE-SELF-LEAVE
  end;
end;

procedure TBank.MonitorSite;
begin
  TMonitor.Enter(FGuard); // SITE-MON-ENTER
  try
    FName:= 'monitor';
  finally
    TMonitor.Exit(FGuard); // SITE-MON-EXIT
  end;
end;

procedure TBank.WinapiSite;
begin
  EnterCriticalSection(FRtl); // SITE-WIN-ENTER
  try
    FName:= 'winapi';
  finally
    LeaveCriticalSection(FRtl); // SITE-WIN-LEAVE
  end;
end;

procedure TBank.RwSite;
begin
  FRw.BeginRead; // SITE-RW-BEGINREAD
  try
    FName:= FName + '';
  finally
    FRw.EndRead; // SITE-RW-ENDREAD
  end;
  FRw.BeginWrite; // SITE-RW-BEGINWRITE
  try
    FName:= 'rw';
  finally
    FRw.EndWrite; // SITE-RW-ENDWRITE
  end;
end;

procedure TBank.TrySite;
begin
  if FLockA.TryEnter then // SITE-TRY-ENTER
    try
      FName:= 'try';
    finally
      FLockA.Leave; // SITE-TRY-LEAVE
    end;
end;

procedure TBank.MutexSite;
begin
  FMutex.Acquire; // SITE-MUTEX-ACQUIRE
  try
    FName:= 'mutex';
  finally
    FMutex.Release; // SITE-MUTEX-RELEASE
  end;
end;

procedure TBank.ListSite;
var
  L: TList;
begin
  L:= FItems.LockList; // SITE-LIST-LOCK
  try
    FName:= IntToStr(L.Count);
  finally
    FItems.UnlockList; // SITE-LIST-UNLOCK
  end;
end;

procedure TBank.OtherObject(pOther: TBank);
begin
  pOther.FLockA.Enter; // SITE-OTHER-ENTER
  try
    FName:= 'other';
  finally
    pOther.FLockA.Leave; // SITE-OTHER-LEAVE
  end;
end;

procedure TBank.NoLocks;
var
  S: TStringList;
begin
  S:= TStringList.Create;
  try
    S.BeginUpdate;
    S.Add(FName);
    S.EndUpdate;
  finally
    S.Free;
  end;
end;

procedure TBank.DescendantSite;
begin
  FMine.Enter; // SITE-DESC-ENTER
  try
    FName:= 'mine';
  finally
    FMine.Leave; // SITE-DESC-LEAVE
  end;
end;

procedure TBank.MonitorSelf;
begin
  TMonitor.Enter(Self); // SITE-MONSELF-ENTER
  try
    FName:= 'monitor self';
  finally
    TMonitor.Exit(Self); // SITE-MONSELF-EXIT
  end;
end;

procedure TBank.MonitorTimeout;
begin
  if TMonitor.Enter(FGuard, 100) then // SITE-MONTIME-ENTER
    try
      FName:= 'monitor timeout';
    finally
      TMonitor.Exit(FGuard); // SITE-MONTIME-EXIT
    end;
end;

procedure TBank.MonitorIndexed;
begin
  TMonitor.Enter(FGuards[0]); // SITE-MONIDX-ENTER
  try
    FName:= 'monitor indexed';
  finally
    TMonitor.Exit(FGuards[0]); // SITE-MONIDX-EXIT
  end;
end;

procedure TBank.MonitorOther(pOther: TBank);
begin
  TMonitor.Enter(pOther.FGuard); // SITE-MONOTHER-ENTER
  try
    FName:= 'monitor other';
  finally
    TMonitor.Exit(pOther.FGuard); // SITE-MONOTHER-EXIT
  end;
end;

procedure TBank.SpinSite;
begin
  FSpin.Enter; // SITE-SPIN-ENTER
  try
    FName:= 'spin';
  finally
    FSpin.Exit; // SITE-SPIN-EXIT
  end;
end;

procedure TBank.NotLocks;
begin
  FFake.Enter;
  try
    FFake.Acquire;
    FFake.Release;
  finally
    FFake.Leave;
  end;
end;

{ TFake }

procedure TFake.Enter;
begin
end;

procedure TFake.Leave;
begin
end;

procedure TFake.Acquire;
begin
end;

procedure TFake.Release;
begin
end;

end.
