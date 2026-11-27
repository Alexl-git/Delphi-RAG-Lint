unit thrOrder;

{ Fixture of tests\autotest\run_v156_THR-R.ps1 (1.56 lane THR-R, G-05 lock-order-inversion).
  A line that must carry a finding ends with a marker comment `// HIT-<NAME>`; a line that looks
  like one and must stay silent ends with `// QUIET-<NAME>`. The runner finds lines by marker, so
  the file can be edited without renumbering. }

interface

uses
  System.SysUtils
, System.Classes
, System.SyncObjs
  ;

type
  /// <summary>Positive control: the two methods take the same two locks in opposite order.</summary>
  TBank = class
  private
    FLockA: TCriticalSection;
    FLockB: TCriticalSection;
  public
    procedure AThenB;
    procedure BThenA;
  end;

  /// <summary>Silent: both methods take the two locks in the SAME order.</summary>
  TSame = class
  private
    FLockC: TCriticalSection;
    FLockD: TCriticalSection;
  public
    procedure One;
    procedure Two;
  end;

  /// <summary>Silent: the locks are parameters and locals, their keys mean nothing across routines.</summary>
  TLoose = class
  public
    procedure XThenY(pX, pY: TCriticalSection);
    procedure YThenX(pX, pY: TCriticalSection);
    procedure LocalOne;
    procedure LocalTwo;
  end;

  /// <summary>The second lock is taken by a called routine, directly and two calls deep.</summary>
  TVia = class
  private
    FLockE: TCriticalSection;
    FLockF: TCriticalSection;
    FLockG: TCriticalSection;
    FLockH: TCriticalSection;
    procedure TakeF;
    procedure TakeH;
    procedure WrapH;
    procedure Harmless;
  public
    procedure Outer;
    procedure Reverse;
    procedure Outer2;
    procedure Reverse2;
  end;

  /// <summary>Silent: both orders run under one common gate lock, so they cannot interleave.</summary>
  TGate = class
  private
    FGate: TCriticalSection;
    FLockI: TCriticalSection;
    FLockJ: TCriticalSection;
  public
    procedure GateIJ;
    procedure GateJI;
  end;

  /// <summary>Silent: the second lock of one side is only TRIED, a failed try does not wait.</summary>
  TTry = class
  private
    FLockK: TCriticalSection;
    FLockL: TCriticalSection;
  public
    procedure KTryL;
    procedure LThenK;
  end;

  /// <summary>Silent: the read-write lock is taken for READING on both sides; readers do not block readers.</summary>
  TRwShared = class
  private
    FRw: TMultiReadExclusiveWriteSynchronizer;
    FCs: TCriticalSection;
  public
    procedure ReadThenCs;
    procedure CsThenRead;
  end;

  /// <summary>Fires: one side WRITES the read-write lock.</summary>
  TRwWrite = class
  private
    FRw: TMultiReadExclusiveWriteSynchronizer;
    FCs: TCriticalSection;
  public
    procedure WriteThenCs;
    procedure CsThenRead;
  end;

  /// <summary>Silent: the "second" lock is already held (re-entered), and a sequential pair is no nesting.</summary>
  TRe = class
  private
    FLockM: TCriticalSection;
    FLockN: TCriticalSection;
  public
    procedure MThenN;
    procedure MThenNThenM;
    procedure Sequential;
  end;

var
  GLockX: TCriticalSection;
  GLockY: TCriticalSection;

/// <summary>Takes the two unit-level locks X then Y; thrOrder2.GlobalYX takes them Y then X.</summary>
procedure GlobalXY;

implementation

{ TBank }

procedure TBank.AThenB;
begin
  FLockA.Enter;
  try
    FLockB.Enter; // HIT-AB
    try
    finally
      FLockB.Leave;
    end;
  finally
    FLockA.Leave;
  end;
end;

procedure TBank.BThenA;
begin
  FLockB.Acquire;
  try
    FLockA.Acquire; // HIT-BA
    try
    finally
      FLockA.Release;
    end;
  finally
    FLockB.Release;
  end;
end;

{ TSame }

procedure TSame.One;
begin
  FLockC.Enter;
  try
    FLockD.Enter; // QUIET-SAME1
    FLockD.Leave;
  finally
    FLockC.Leave;
  end;
end;

procedure TSame.Two;
begin
  FLockC.Enter;
  try
    FLockD.Enter; // QUIET-SAME2
    FLockD.Leave;
  finally
    FLockC.Leave;
  end;
end;

{ TLoose }

procedure TLoose.XThenY(pX, pY: TCriticalSection);
begin
  pX.Enter;
  pY.Enter; // QUIET-PARAM1
  pY.Leave;
  pX.Leave;
end;

procedure TLoose.YThenX(pX, pY: TCriticalSection);
begin
  pY.Enter;
  pX.Enter; // QUIET-PARAM2
  pX.Leave;
  pY.Leave;
end;

procedure TLoose.LocalOne;
var
  P, Q: TCriticalSection;
begin
  P:= TCriticalSection.Create;
  Q:= TCriticalSection.Create;
  P.Enter;
  Q.Enter; // QUIET-LOCAL1
  Q.Leave;
  P.Leave;
end;

procedure TLoose.LocalTwo;
var
  P, Q: TCriticalSection;
begin
  P:= TCriticalSection.Create;
  Q:= TCriticalSection.Create;
  Q.Enter;
  P.Enter; // QUIET-LOCAL2
  P.Leave;
  Q.Leave;
end;

{ TVia }

procedure TVia.TakeF;
begin
  FLockF.Enter;
  FLockF.Leave;
end;

procedure TVia.TakeH;
begin
  FLockH.Enter;
  FLockH.Leave;
end;

procedure TVia.WrapH;
begin
  TakeH;
end;

procedure TVia.Harmless;
begin
end;

procedure TVia.Outer;
begin
  FLockE.Enter;
  try
    Harmless; // QUIET-CALL-NOLOCK
    TakeF; // HIT-CALL
  finally
    FLockE.Leave;
  end;
  TakeF; // QUIET-CALL-AFTER
end;

procedure TVia.Reverse;
begin
  FLockF.Enter;
  try
    FLockE.Enter; // HIT-CALL-REV
    FLockE.Leave;
  finally
    FLockF.Leave;
  end;
end;

procedure TVia.Outer2;
begin
  FLockG.Enter;
  try
    WrapH; // HIT-CALL2
  finally
    FLockG.Leave;
  end;
end;

procedure TVia.Reverse2;
begin
  FLockH.Enter;
  try
    FLockG.Enter; // HIT-CALL2-REV
    FLockG.Leave;
  finally
    FLockH.Leave;
  end;
end;

{ TGate }

procedure TGate.GateIJ;
begin
  FGate.Enter;
  try
    FLockI.Enter;
    FLockJ.Enter; // QUIET-GATE1
    FLockJ.Leave;
    FLockI.Leave;
  finally
    FGate.Leave;
  end;
end;

procedure TGate.GateJI;
begin
  FGate.Enter;
  try
    FLockJ.Enter;
    FLockI.Enter; // QUIET-GATE2
    FLockI.Leave;
    FLockJ.Leave;
  finally
    FGate.Leave;
  end;
end;

{ TTry }

procedure TTry.KTryL;
begin
  FLockK.Enter;
  try
    if FLockL.TryEnter then // QUIET-TRY1
      FLockL.Leave;
  finally
    FLockK.Leave;
  end;
end;

procedure TTry.LThenK;
begin
  FLockL.Enter;
  try
    FLockK.Enter; // QUIET-TRY2
    FLockK.Leave;
  finally
    FLockL.Leave;
  end;
end;

{ TRwShared }

procedure TRwShared.ReadThenCs;
begin
  FRw.BeginRead;
  try
    FCs.Enter; // QUIET-RW1
    FCs.Leave;
  finally
    FRw.EndRead;
  end;
end;

procedure TRwShared.CsThenRead;
begin
  FCs.Enter;
  try
    FRw.BeginRead; // QUIET-RW2
    FRw.EndRead;
  finally
    FCs.Leave;
  end;
end;

{ TRwWrite }

procedure TRwWrite.WriteThenCs;
begin
  FRw.BeginWrite;
  try
    FCs.Enter; // HIT-RW-WRITE
    FCs.Leave;
  finally
    FRw.EndWrite;
  end;
end;

procedure TRwWrite.CsThenRead;
begin
  FCs.Enter;
  try
    FRw.BeginRead; // HIT-RW-READ
    FRw.EndRead;
  finally
    FCs.Leave;
  end;
end;

{ TRe }

procedure TRe.MThenN;
begin
  FLockM.Enter;
  try
    FLockN.Enter; // QUIET-RE1
    FLockN.Leave;
  finally
    FLockM.Leave;
  end;
end;

procedure TRe.MThenNThenM;
begin
  FLockM.Enter;
  try
    FLockN.Enter; // QUIET-RE2
    try
      FLockM.Enter; // QUIET-REENTER
      FLockM.Leave;
    finally
      FLockN.Leave;
    end;
  finally
    FLockM.Leave;
  end;
end;

procedure TRe.Sequential;
begin
  FLockN.Enter;
  FLockN.Leave;
  FLockM.Enter; // QUIET-SEQ
  FLockM.Leave;
end;

procedure GlobalXY;
begin
  GLockX.Enter;
  try
    GLockY.Enter; // HIT-GLOBAL-XY
    GLockY.Leave;
  finally
    GLockX.Leave;
  end;
end;

end.
