unit uT2Use;

{ Fixture for 1.46 t2 (criticalsection-not-released on the F1 receiver type).  Both routines acquire
  without a finally release.  TRIGGER = fires WITH the type fact; CONTROL = silent WITH the fact
  (the receiver is a TSemaphore, provably not a lock) but fires without it. }

interface

uses
  uLhBase;

procedure UseCs;
procedure UseSem;

implementation

procedure UseCs;
var
  CS: TCriticalSection;
begin
  CS.Enter; // TRIGGER-T2-LOCK
  CS.Leave;
end;

procedure UseSem;
var
  Sem: TSemaphore;
begin
  Sem.Acquire; // CONTROL-T2-LOCK
  Sem.Release;
end;

end.
