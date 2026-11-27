unit thrGate2;

{ Fixture of tests\autotest\run_v156_FIX2A.ps1 (F8: lock-order-inversion behind a common gate that is
  not an exact blocking enter). `// HIT-<NAME>` = exactly one finding on the line; `// QUIET-<NAME>` =
  none. }

interface

uses
  System.SysUtils
, System.Classes
, System.SyncObjs
  ;

type
  TOwner = class
  public
    Gate: TCriticalSection;
  end;

  /// <summary>Positive control: opposite order, no gate at all.</summary>
  TPlain = class
  private
    FLockP: TCriticalSection;
    FLockQ: TCriticalSection;
  public
    procedure PThenQ;
    procedure QThenP;
  end;

  /// <summary>Silent: both orders run under a gate taken by TryEnter (the body runs only when it got it).</summary>
  TTryGate = class
  private
    FGate: TCriticalSection;
    FLockR: TCriticalSection;
    FLockS: TCriticalSection;
  public
    procedure GateRS;
    procedure GateSR;
  end;

  /// <summary>Silent: both orders run under a gate that is a field of another object (not an exact lock).</summary>
  TInexactGate = class
  private
    FOwner: TOwner;
    FLockT: TCriticalSection;
    FLockU: TCriticalSection;
  public
    procedure GateTU;
    procedure GateUT;
  end;

implementation

{ TPlain }

procedure TPlain.PThenQ;
begin
  FLockP.Enter;
  try
    FLockQ.Enter; // HIT-PLAIN
    FLockQ.Leave;
  finally
    FLockP.Leave;
  end;
end;

procedure TPlain.QThenP;
begin
  FLockQ.Enter;
  try
    FLockP.Enter; // HIT-PLAIN2
    FLockP.Leave;
  finally
    FLockQ.Leave;
  end;
end;

{ TTryGate }

procedure TTryGate.GateRS;
begin
  if FGate.TryEnter then
  try
    FLockR.Enter;
    FLockS.Enter; // QUIET-TRYGATE1
    FLockS.Leave;
    FLockR.Leave;
  finally
    FGate.Leave;
  end;
end;

procedure TTryGate.GateSR;
begin
  if FGate.TryEnter then
  try
    FLockS.Enter;
    FLockR.Enter; // QUIET-TRYGATE2
    FLockR.Leave;
    FLockS.Leave;
  finally
    FGate.Leave;
  end;
end;

{ TInexactGate }

procedure TInexactGate.GateTU;
begin
  FOwner.Gate.Enter;
  try
    FLockT.Enter;
    FLockU.Enter; // QUIET-INEXGATE1
    FLockU.Leave;
    FLockT.Leave;
  finally
    FOwner.Gate.Leave;
  end;
end;

procedure TInexactGate.GateUT;
begin
  FOwner.Gate.Enter;
  try
    FLockU.Enter;
    FLockT.Enter; // QUIET-INEXGATE2
    FLockT.Leave;
    FLockU.Leave;
  finally
    FOwner.Gate.Leave;
  end;
end;

end.
