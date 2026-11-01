program ProcRunHeartbeatTests;

{ 1.40 heartbeat (owner design 2026-11-01): the plugin kills an engine child only when it makes NO
  PROGRESS, and once the child answers a heartbeat, progress means its STATUS changing -- not CPU, not
  silence. A frozen status for the stall budget = stuck; an advancing one = slow, keep waiting.

  THE CHILD IS THIS EXE. `--child advance` opens the real heartbeat pipe (BeatChannelOpen) and, silent
  and idle (no output, no CPU), advances its status every 300 ms for CAdvanceMs. `--child frozen` opens
  it, reports once, then spins the CPU silently for CFrozenMs with the status frozen. `--child spin` and
  `--child sleep` open NO pipe (an older engine, a wrapper): the pre-1.40 rule must still hold for them.

  H1 advance, budget 2 s: NOT killed -- exit 0 with its own output. (Before 1.40: no output and no CPU
     for 2 s = killed.)
  H2 frozen, budget 2 s: KILLED as stuck within budget + 2 beat polls + slack, long before it would
     finish. (Before 1.40: the CPU spin counted as progress and it ran to its end.)
  H3 positive control, spin with no heartbeat: not killed (CPU is still progress without a beat).
  H4 positive control, sleep with no heartbeat: killed (the budget still bites).
  H5 while an advancing child runs, ProcRunBeatText names its action (the UI's progress text), and it
     is empty again once the run returned.

  Usage: tests\plugin\run_procrun_heartbeat.ps1 }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  DRagLint.Core.OutputEncoding in '..\src\core\DRagLint.Core.OutputEncoding.pas',
  DRagLint.Core.ControlChannel in '..\src\core\DRagLint.Core.ControlChannel.pas',
  DragLint.Plugin.ProcRun in '..\src\delphi-plugin\DragLint.Plugin.ProcRun.pas';

const
  CBudgetMs     = 2000;  { the stall budget every case runs under }
  CAdvanceMs    = 7000;  { an advancing child's whole silent life }
  CAdvanceStep  = 300;   { how often it reports }
  CFrozenMs     = 15000; { a frozen child's spin, far past any kill bound }
  CSpinMs       = 5000;
  CSleepMs      = 8000;
  CBeatPollMs   = 2000;  { PROCRUN_BEAT_POLL_MS }
  CSlackMs      = 2500;
  CTimedOut     = -2;    { PROCRUN_TIMED_OUT_EXIT_CODE }

var
  GPassed, GFailed: Integer;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then
  begin
    Inc(GPassed);
    Writeln('  [PASS] ', AName);
  end
  else
  begin
    Inc(GFailed);
    Writeln('  [FAIL] ', AName, ' ', ADetail);
  end;
end;

{ ---- the child ---- }

procedure Spin(AMs: Integer);
var
  Sw: TStopwatch;
  X : Int64;
begin
  Sw:= TStopwatch.StartNew;
  X:= 0;
  while Sw.ElapsedMilliseconds < AMs do Inc(X);
  if X < 0 then Writeln(X); { keeps the loop }
end;

procedure RunChild(const AMode: string);
var
  Sw: TStopwatch;
begin
  if (AMode = 'advance') or (AMode = 'frozen') then
    if not BeatChannelOpen('index', 'test', 'test') then
    begin
      Writeln('child: no heartbeat pipe');
      ExitCode:= 3;
      Exit;
    end;
  if AMode = 'advance' then
  begin
    BeatStep('work', CAdvanceMs div CAdvanceStep);
    Sw:= TStopwatch.StartNew;
    while Sw.ElapsedMilliseconds < CAdvanceMs do
    begin
      Sleep(CAdvanceStep);
      BeatProgress;
    end;
  end
  else if AMode = 'frozen' then
  begin
    BeatStep('stuck');
    Spin(CFrozenMs);
  end
  else if AMode = 'spin' then Spin(CSpinMs)
  else Sleep(CSleepMs);
  Writeln('child-done ', AMode);
end;

{ ---- the cases ---- }

function RunMode(const AMode: string; out AOutput: string; out AMs: Int64): Integer;
var
  Sw: TStopwatch;
begin
  Sw:= TStopwatch.StartNew;
  Result:= RunCaptureStdout(Format('"%s" --child %s', [ParamStr(0), AMode]), AOutput, CBudgetMs);
  AMs:= Sw.ElapsedMilliseconds;
end;

procedure Cases;
var
  Outp  : string ;
  Ms    : Int64  ;
  Rc    : Integer;
  Seen  : string ;
  Probe : TThread;
  Stop  : Boolean;
begin
  Writeln('H1 an advancing (silent, idle) child is slow, not stuck');
  Seen:= '';
  Stop:= False;
  Probe:= TThread.CreateAnonymousThread(
    procedure
    begin
      while not Stop do
      begin
        {$IFNDEF BASE_PROCRUN} if Seen = '' then Seen:= ProcRunBeatText; {$ENDIF}
        Sleep(100);
      end;
    end);
  Probe.FreeOnTerminate:= False;
  Probe.Start;
  Rc:= RunMode('advance', Outp, Ms);
  Stop:= True;
  Probe.WaitFor;
  Probe.Free;
  Check('H1a exit 0, not killed', Rc = 0, Format('rc=%d after %d ms', [Rc, Ms]));
  Check('H1b its own output arrived', Pos('child-done advance', Outp) > 0, Outp);
  {$IFNDEF BASE_PROCRUN} { BASE_PROCRUN: the behavioural RED build against the pre-1.40 ProcRun, which has no ProcRunBeatText }
  Writeln('H5 the UI progress text');
  Check('H5a ProcRunBeatText named the action while it ran', Pos('index', Seen) > 0, 'seen=' + Seen);
  Check('H5b and is empty once the run returned', ProcRunBeatText = '', 'now=' + ProcRunBeatText);
  {$ENDIF}

  Writeln('H2 a frozen status with a busy CPU is stuck');
  Rc:= RunMode('frozen', Outp, Ms);
  Check('H2a killed as timed out', Rc = CTimedOut, Format('rc=%d', [Rc]));
  Check('H2b within budget + 2 polls + slack', Ms < CBudgetMs + 2 * CBeatPollMs + CSlackMs, Format('%d ms', [Ms]));

  Writeln('H3 no heartbeat, CPU busy: the old rule (alive)');
  Rc:= RunMode('spin', Outp, Ms);
  Check('H3 exit 0', Rc = 0, Format('rc=%d after %d ms', [Rc, Ms]));

  Writeln('H4 no heartbeat, idle: the old rule (stuck)');
  Rc:= RunMode('sleep', Outp, Ms);
  Check('H4 killed as timed out', Rc = CTimedOut, Format('rc=%d after %d ms', [Rc, Ms]));
end;

begin
  try
    if (ParamCount >= 2) and (ParamStr(1) = '--child') then
    begin
      RunChild(ParamStr(2));
      Exit;
    end;
    Cases;
    Writeln(Format('%d passed, %d failed', [GPassed, GFailed]));
    if GFailed > 0 then ExitCode:= 1;
  except
    on E: Exception do
    begin
      Writeln('FATAL ', E.ClassName, ': ', E.Message);
      ExitCode:= 2;
    end;
  end;
end.
