program ReportProgressTests;
{$APPTYPE CONSOLE}
{ DragLint.Plugin.ReportProgress (1.52 REPPROG): a Reports question runs with a
  progress window that can be cancelled. The IDE wiring (Reports.pas) needs the
  IDE; what makes the window safe does not, and it is all here:

    P  the run: Start never waits, progress fires at once and on every Tick, a
       normal run delivers once and then reports no more progress
    C  Cancel returns within 1 s, the child is gone (by pid), nothing is
       delivered, Tick is silent afterwards
    F  the window: marquee bar + elapsed seconds, Cancel button cancels and
       closes without an answer, a finished run closes it and delivers once,
       freeing it mid-run kills the child

  The child is this exe in a child mode: it writes its pid, sleeps, and writes
  a marker only if it lives to the end of its sleep. }
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.ComCtrls,
  DRagLint.Core.OutputEncoding in '..\src\core\DRagLint.Core.OutputEncoding.pas',
  DRagLint.Core.ControlChannel in '..\src\core\DRagLint.Core.ControlChannel.pas',
  DragLint.Plugin.ProcRun in '..\src\delphi-plugin\DragLint.Plugin.ProcRun.pas',
  DragLint.Plugin.LogPaths in '..\src\delphi-plugin\DragLint.Plugin.LogPaths.pas',
  DragLint.Plugin.Telemetry in '..\src\delphi-plugin\DragLint.Plugin.Telemetry.pas',
  DragLint.Plugin.CliAsync in '..\src\delphi-plugin\DragLint.Plugin.CliAsync.pas',
  DragLint.Plugin.ReportProgress in '..\src\delphi-plugin\DragLint.Plugin.ReportProgress.pas';

const
  BLOCK_LIMIT_MS  = 300;    { a call that "never waits" returns well inside this }
  CANCEL_LIMIT_MS = 1000;   { the owner's ruling: Cancel answers within a second }
  CHILD_SLOW_MS   = 20000;  { far past GONE_LIMIT_MS: a natural exit cannot pass C4/F5/F11 }
  CHILD_FAST_MS   = 50;
  PUMP_DONE_MS    = 10000;
  PUMP_QUIET_MS   = 400;
  TICK_GAP_MS     = 1200;   { more than one second, so the elapsed count moves }
  GONE_LIMIT_MS   = 2000;   { a killed child is gone well inside this }
  PID_WAIT_MS     = 5000;
  POLL_MS         = 20;
  CHILD_EXIT      = 7;
  UNSET           = -1;

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GScratch: string;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then Inc(GPass)
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', AName, ' ', ADetail);
  end;
end;

function PumpUntil(const ACond: TFunc<Boolean>; AMs: Cardinal): Boolean;
var
  T0: UInt64;
begin
  T0:= GetTickCount64;
  repeat
    CheckSynchronize(POLL_MS);
    Result:= ACond();
  until Result or (GetTickCount64 - T0 >= AMs);
end;

procedure Pump(AMs: Cardinal);
begin
  PumpUntil(function: Boolean begin Result:= False; end, AMs);
end;

function FilePath(const AName: string): string;
begin
  Result:= TPath.Combine(GScratch, AName);
end;

function ChildCmd(AMs: Integer; const AName: string): string;
begin
  Result:= Format('"%s" child %d "%s" "%s"', [ParamStr(0), AMs, FilePath(AName + '.pid'), FilePath(AName + '.done')]);
end;

{ The child's pid, once it has written it; 0 when it never did. }
function ChildPid(const AName: string): DWORD;
var
  T0: UInt64;
begin
  Result:= 0;
  T0:= GetTickCount64;
  while (GetTickCount64 - T0 < PID_WAIT_MS) do
  begin
    if FileExists(FilePath(AName + '.pid')) then
      try
        Result:= StrToIntDef(Trim(TFile.ReadAllText(FilePath(AName + '.pid'))), 0);
        if Result <> 0 then Exit;
      except
        { the child is still writing it }
      end;
    Sleep(POLL_MS);
  end;
end;

{ True when no process with that pid runs within AMs. }
function ProcessGone(APid: DWORD; AMs: Cardinal): Boolean;
var
  H: THandle;
begin
  H:= OpenProcess(SYNCHRONIZE, False, APid);
  if H = 0 then Exit(True);
  try
    Result:= WaitForSingleObject(H, AMs) = WAIT_OBJECT_0;
  finally
    CloseHandle(H);
  end;
end;

procedure TestRunNormal;
var
  Run: TReportProgressRun;
  Ticks, Last, Calls, Code: Integer;
  Text: string;
  T0: UInt64;
begin
  Ticks:= 0;
  Last:= UNSET;
  Calls:= 0;
  Code:= UNSET;
  Run:= TReportProgressRun.Create(ChildCmd(TICK_GAP_MS * 2, 'p'), CLI_ASYNC_STALL_MS,
    procedure(ASec: Integer)
    begin
      Inc(Ticks);
      Last:= ASec;
    end,
    procedure(AExit: Integer; const AOut: string)
    begin
      Inc(Calls);
      Code:= AExit;
      Text:= AOut;
    end);
  try
    T0:= GetTickCount64;
    Run.Start;
    Check('P1 Start returns before the child ends', GetTickCount64 - T0 < BLOCK_LIMIT_MS, UIntToStr(GetTickCount64 - T0));
    Check('P2 progress fires at once, at 0 s', (Ticks = 1) and (Last = 0), Format('%d ticks, last %d', [Ticks, Last]));
    Check('P3 Running after Start', Run.Running);
    Pump(TICK_GAP_MS);
    Run.Tick;
    Check('P4 a Tick reports the elapsed seconds', (Ticks = 2) and (Last >= 1), Format('%d ticks, last %d', [Ticks, Last]));
    Check('P5 delivered', PumpUntil(function: Boolean begin Result:= Calls > 0; end, PUMP_DONE_MS));
    Check('P6 with the exit code and output', (Code = CHILD_EXIT) and Text.Contains('pid'), Format('%d %s', [Code, Text]));
    Check('P7 not Running once delivered', not Run.Running);
    Run.Tick;
    Check('P8 a Tick after the answer reports nothing', Ticks = 2, IntToStr(Ticks));
    Pump(PUMP_QUIET_MS);
    Check('P9 exactly once', Calls = 1, IntToStr(Calls));
    Check('P10 not Cancelled', not Run.Cancelled);
  finally
    Run.Free;
  end;
end;

procedure TestRunCancel;
var
  Run: TReportProgressRun;
  Ticks, Calls: Integer;
  Pid: DWORD;
  T0: UInt64;
begin
  Ticks:= 0;
  Calls:= 0;
  Run:= TReportProgressRun.Create(ChildCmd(CHILD_SLOW_MS, 'c'), CLI_ASYNC_STALL_MS,
    procedure(ASec: Integer) begin Inc(Ticks); end,
    procedure(AExit: Integer; const AOut: string) begin Inc(Calls); end);
  try
    Run.Start;
    Pid:= ChildPid('c');
    Check('C0 the child is running (positive control)', (Pid <> 0) and not ProcessGone(Pid, 0), UIntToStr(Pid));
    T0:= GetTickCount64;
    Run.Cancel;
    Check('C1 Cancel returns within 1 s', GetTickCount64 - T0 < CANCEL_LIMIT_MS, UIntToStr(GetTickCount64 - T0));
    Check('C2 not Running after Cancel', not Run.Running);
    Check('C3 Cancelled', Run.Cancelled);
    Check('C4 the child process is gone', (Pid <> 0) and ProcessGone(Pid, GONE_LIMIT_MS), UIntToStr(Pid));
    var TicksAtCancel: Integer:= Ticks;
    Run.Tick;
    Check('C5 a Tick after Cancel reports nothing', Ticks = TicksAtCancel, IntToStr(Ticks));
    Pump(PUMP_QUIET_MS);
    Check('C6 no answer after Cancel', Calls = 0, IntToStr(Calls));
    Check('C7 the child never reached its end', not FileExists(FilePath('c.done')));
    Run.Cancel;
    Check('C8 a second Cancel is a no-op', Run.Cancelled and not Run.Running);
  finally
    Run.Free;
  end;
end;

procedure TestForm;
var
  Form: TDragLintReportProgressForm;
  Done, Cancels: Integer;
  Text: string;
  Pid: DWORD;
begin
  { F1-F5: Cancel button }
  Done:= 0;
  Cancels:= 0;
  Form:= TDragLintReportProgressForm.CreateRun(nil, 'round-trip X', ChildCmd(CHILD_SLOW_MS, 'f1'), CLI_ASYNC_STALL_MS,
    procedure(AExit: Integer; const AOut: string) begin Inc(Done); end,
    procedure begin Inc(Cancels); end);
  try
    Check('F1 the bar is a marquee', Form.Bar.Style = pbstMarquee);
    Check('F2 the state names the report and 0 s', Form.StateText.Contains('round-trip X') and Form.StateText.Contains('0 s'), Form.StateText);
    Check('F3 Running after CreateRun', Form.Run.Running);
    Pid:= ChildPid('f1');
    Form.CancelRun;
    Check('F4 Cancel stops the run and calls back once', (not Form.Run.Running) and Form.Run.Cancelled and (Cancels = 1), IntToStr(Cancels));
    Check('F5 the child is gone', (Pid <> 0) and ProcessGone(Pid, GONE_LIMIT_MS), UIntToStr(Pid));
    Pump(PUMP_QUIET_MS);
    Check('F6 nothing is delivered', Done = 0, IntToStr(Done));
    Form.CancelRun;
    Check('F7 a second Cancel does not call back again', Cancels = 1, IntToStr(Cancels));
  finally
    Form.Free;
  end;

  { F8-F10: finished run }
  Done:= 0;
  Cancels:= 0;
  Form:= TDragLintReportProgressForm.CreateRun(nil, 'feeds-from Y', ChildCmd(CHILD_FAST_MS, 'f8'), CLI_ASYNC_STALL_MS,
    procedure(AExit: Integer; const AOut: string)
    begin
      Inc(Done);
      Text:= AOut;
    end,
    procedure begin Inc(Cancels); end);
  try
    Check('F8 a finished run delivers once', PumpUntil(function: Boolean begin Result:= Done > 0; end, PUMP_DONE_MS) and (Done = 1), IntToStr(Done));
    Check('F9 with its output, and the window hidden', Text.Contains('pid') and not Form.Visible, Text);
    Check('F10 no cancel callback', Cancels = 0, IntToStr(Cancels));
  finally
    Form.Free;
  end;

  { F11: freeing the window mid-run (IDE shutdown, package unload) kills the child }
  Done:= 0;
  Form:= TDragLintReportProgressForm.CreateRun(nil, 'z', ChildCmd(CHILD_SLOW_MS, 'f11'), CLI_ASYNC_STALL_MS,
    procedure(AExit: Integer; const AOut: string) begin Inc(Done); end, nil);
  Pid:= ChildPid('f11');
  Form.Free;
  Check('F11 freeing the window kills the child', (Pid <> 0) and ProcessGone(Pid, GONE_LIMIT_MS), UIntToStr(Pid));
  Pump(PUMP_QUIET_MS);
  Check('F12 and delivers nothing', Done = 0, IntToStr(Done));

  Check('F13 the elapsed caption', ReportProgressCaption('a -- b', 7) = 'a -- b' + sLineBreak + 'Computing... 7 s elapsed',
    ReportProgressCaption('a -- b', 7));
end;

procedure RunChild;
begin
  { child <ms> <pidfile> <marker> }
  TFile.WriteAllText(ParamStr(3), IntToStr(GetCurrentProcessId));  // dl:ok magic-literal -- test data: child argv position
  Writeln('pid ', GetCurrentProcessId);
  Flush(Output);
  Sleep(StrToIntDef(ParamStr(2), 0));
  TFile.WriteAllText(ParamStr(4), 'done');  // dl:ok magic-literal -- test data: child argv position
  Halt(CHILD_EXIT);
end;

begin
  if ParamStr(1) = 'child' then RunChild;
  GScratch:= TPath.Combine(TPath.GetTempPath, Format('reportprogress-tests-%d', [GetCurrentProcessId]));
  TDirectory.CreateDirectory(GScratch);
  try
    TestRunNormal;
    TestRunCancel;
    TestForm;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL unexpected ', E.ClassName, ': ', E.Message);
    end;
  end;
  try TDirectory.Delete(GScratch, True); except on E: Exception do Writeln('note: scratch not removed: ', E.Message); end;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
