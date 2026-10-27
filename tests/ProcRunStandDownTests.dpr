program ProcRunStandDownTests;

{ Lane X-BT (owner ruling 2026-10-26): an IDE cycle-fix run has no time limit, so Cancel is the only
  way to stop one -- and Cancel must not hard-kill the engine mid-apply. ProcRun's RunCaptureStdout
  grew AStandDownGraceMs: a cancel first sends the maintenance control channel's `shutdown` to the
  pipe named after the child's pid (DRagLint.Core.ControlChannel), keeps draining the child's output,
  and kills the tree only when the grace ends.

  THE CHILD IS THIS EXE. `--child honour` opens a real TControlChannel, prints `ready <pid>`, waits on
  RequestEvent, takes the request, prints the engine's line "cancelled -- rolled back", signals
  StandDownComplete and exits 1 -- the cycle-fix engine's contract in miniature. `--child ignore`
  opens the channel and never takes the request; `--child none` opens none.

  S1 honour, grace 10 s: the run returns the CHILD's exit code 1 and its output, well inside the grace,
     with no "killed" line.
  S2 ignore, grace 2 s: PROCRUN_CANCELLED_EXIT_CODE after the grace (not before), the "did not stand
     down" line, the child gone.
  S3 none, grace 2 s: the grace is waited out all the same (owner: kill only after the grace), then
     PROCRUN_CANCELLED_EXIT_CODE.
  S4 grace 0 (every other job): the old contract -- killed at once, CancelledText.

  Usage: tests\plugin\run_procrun_standdown.ps1 }

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
  CCancelAfterMs = 1500;  // the cancel lands this long after the child starts
  CChildLifeMs   = 30000; // a child that is never stopped ends by itself after this
  CExitRolledBack = 1;    // what the cycle-fix engine exits with after a stand-down

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
    Writeln('  [FAIL] ', AName);
    if ADetail <> '' then Writeln('      ', ADetail);
  end;
end;

{ ---- the child ---- }

procedure RunChild(const AMode: string);
var
  Ctl: TControlChannel;
  Err: string;
begin
  Ctl:= nil;
  if AMode <> 'none' then
  begin
    Ctl:= TControlChannel.Create([], 'test', 'test');
    if not Ctl.Start(Err) then
    begin
      Writeln('child: channel not started: ', Err);
      Halt(3);
    end;
  end;
  try
    Writeln('ready ', GetCurrentProcessId);
    Flush(Output);
    if AMode = 'honour' then
    begin
      if (WaitForSingleObject(Ctl.RequestEvent, CChildLifeMs) = WAIT_OBJECT_0) and Ctl.StandDownRequested then
      begin
        Writeln('cancelled -- rolled back');
        Flush(Output);
        Ctl.StandDownComplete;
        ExitCode:= CExitRolledBack;
        Exit;
      end;
    end
    else Sleep(CChildLifeMs);
    Writeln('child: never stopped');
  finally
    Ctl.Free;
  end;
end;

{ ---- the runner side ---- }

function ChildPid(const AOutput: string): DWORD;
var
  P: Integer;
begin
  Result:= 0;
  P:= Pos('ready ', AOutput);
  if P = 0 then Exit;
  Result:= StrToIntDef(Trim(Copy(AOutput, P + Length('ready '), 12).Split([#13, #10])[0]), 0);
end;

function IsAlive(APid: DWORD): Boolean;
var
  H: THandle;
begin
  H:= OpenProcess(SYNCHRONIZE, False, APid);
  if H = 0 then Exit(False);
  try
    Result:= WaitForSingleObject(H, 0) = WAIT_TIMEOUT;
  finally
    CloseHandle(H);
  end;
end;

{ Runs `<self> --child <mode>`, sets the cancel CCancelAfterMs later; returns the exit code. }
function RunCancelled(const AMode: string; AGraceMs: Integer; out AOutput: string; out AMs: Int64): Integer;
var
  Ev   : THandle;
  Watch: TStopwatch;
begin
  Ev:= CreateEvent(nil, True, False, nil);
  try
    TThread.CreateAnonymousThread(
      procedure
      begin
        Sleep(CCancelAfterMs);
        SetEvent(Ev);
      end).Start;
    Watch:= TStopwatch.StartNew;
    Result:= RunCaptureStdout(Format('"%s" --child %s', [ParamStr(0), AMode]), AOutput, 0, Ev, AGraceMs);
    AMs:= Watch.ElapsedMilliseconds;
  finally
    Sleep(CCancelAfterMs); { the timer thread has set the event before the handle goes }
    CloseHandle(Ev);
  end;
end;

procedure Tests;
var
  Output: string;
  Ms    : Int64;
  Code  : Integer;
begin
  Writeln('S1 a child that honours the stand-down: its own result, inside the grace');
  Code:= RunCancelled('honour', 10000, Output, Ms);
  Check('S1a the child''s own exit code (1), not the cancelled code', Code = CExitRolledBack, Format('code=%d ms=%d out=%s', [Code, Ms, Output]));
  Check('S1b its "cancelled -- rolled back" line is in the output', Pos('cancelled -- rolled back', Output) > 0, Output);
  Check('S1c no kill line', Pos('killed', Output) = 0, Output);
  Check('S1d well inside the 10 s grace', Ms < 8000, Format('ms=%d', [Ms]));

  Writeln('S2 a child with a channel that never takes the request: killed after the grace');
  Code:= RunCancelled('ignore', 2000, Output, Ms);
  Check('S2a PROCRUN_CANCELLED_EXIT_CODE', Code = PROCRUN_CANCELLED_EXIT_CODE, Format('code=%d out=%s', [Code, Output]));
  Check('S2b not before the grace ended (cancel at 1.5 s + 2 s grace)', Ms >= CCancelAfterMs + 2000 - 250, Format('ms=%d', [Ms]));
  Check('S2c and not long after it', Ms < 12000, Format('ms=%d', [Ms]));
  Check('S2d the "did not stand down" line', Pos('did not stand down', Output) > 0, Output);
  Check('S2e the child is gone', (ChildPid(Output) <> 0) and not IsAlive(ChildPid(Output)), Format('pid=%d', [ChildPid(Output)]));

  Writeln('S3 a child with no channel: the grace is still waited out, then the kill');
  Code:= RunCancelled('none', 2000, Output, Ms);
  Check('S3a PROCRUN_CANCELLED_EXIT_CODE', Code = PROCRUN_CANCELLED_EXIT_CODE, Format('code=%d out=%s', [Code, Output]));
  Check('S3b after the grace', Ms >= CCancelAfterMs + 2000 - 250, Format('ms=%d', [Ms]));
  Check('S3c the child is gone', (ChildPid(Output) <> 0) and not IsAlive(ChildPid(Output)), Format('pid=%d', [ChildPid(Output)]));

  Writeln('S4 grace 0 (every other job): killed at once, as before');
  Code:= RunCancelled('honour', 0, Output, Ms);
  Check('S4a PROCRUN_CANCELLED_EXIT_CODE', Code = PROCRUN_CANCELLED_EXIT_CODE, Format('code=%d out=%s', [Code, Output]));
  Check('S4b at once (no grace)', Ms < CCancelAfterMs + 1500, Format('ms=%d', [Ms]));
  Check('S4c the plain cancelled line, no stand-down', (Pos('cancelled; the child process tree was killed', Output) > 0)
    and (Pos('cancelled -- rolled back', Output) = 0), Output);
end;

begin
  try
    if (ParamCount = 2) and (ParamStr(1) = '--child') then
    begin
      RunChild(ParamStr(2));
      Exit;
    end;
    Tests;
    Writeln(Format('%d passed, %d failed', [GPassed, GFailed]));
    if GFailed > 0 then ExitCode:= 1;
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode:= 2;
    end;
  end;
end.
