program CliAsyncTests;
{$APPTYPE CONSOLE}
{ DragLint.Plugin.CliAsync: the plugin's short CLI runs off the main thread
  (IDE-MAINTHREAD-CLI). The forms themselves need the IDE; what makes them safe
  does not, and it is all here:

    A results arrive on the main thread and the call never waits
    B a superseded run is killed and its answer dropped (stale never overwrites)
    C cancelling or freeing the slot drops the answer, even one ALREADY QUEUED
    D a raising ADone does not escape into the message loop
    E StopAllCliRuns kills children, waits, withdraws queued answers

  The child is this exe in a child mode, so a kill is observed by a marker file the
  child writes only if it lives to the end of its sleep. }
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  DRagLint.Core.OutputEncoding in '..\src\core\DRagLint.Core.OutputEncoding.pas',
  DRagLint.Core.ControlChannel in '..\src\core\DRagLint.Core.ControlChannel.pas',
  DragLint.Plugin.ProcRun in '..\src\delphi-plugin\DragLint.Plugin.ProcRun.pas',
  DragLint.Plugin.LogPaths in '..\src\delphi-plugin\DragLint.Plugin.LogPaths.pas',
  DragLint.Plugin.Telemetry in '..\src\delphi-plugin\DragLint.Plugin.Telemetry.pas',
  DragLint.Plugin.CliAsync in '..\src\delphi-plugin\DragLint.Plugin.CliAsync.pas';

const
  BLOCK_LIMIT_MS = 300;    { a call that "never waits" returns well inside this }
  CHILD_SLOW_MS  = 2500;   { longer than BLOCK_LIMIT_MS and every pump below }
  CHILD_FAST_MS  = 50;
  PUMP_DONE_MS   = 10000;  { upper bound; PumpUntil returns as soon as it is true }
  PUMP_QUIET_MS  = 400;    { long enough for a queued answer to arrive, if one exists }
  POST_QUEUE_MS  = 300;    { from the child's marker to its answer being queued }
  NOTHING_MS     = 1500;   { long enough for a run that should not exist to show }
  MARKER_POLL_MS = 20;
  CHILD_EXIT     = 7;

type
  { In the IDE an exception out of queued code reaches this hook and shows an error
    box. A console has no hook, so CheckSynchronize swallows it and D1 would pass on
    code that raises (measured): the test installs one. }
  TEscapeCounter = class
    class var Count: Integer;
    class procedure Hit(Sender: TObject);
  end;

class procedure TEscapeCounter.Hit(Sender: TObject);
begin
  Inc(Count);
end;

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
    CheckSynchronize(10);  // dl:ok magic-literal@0b14 -- REVIEWED 2026-11-04 int3: test data (pump slice, -99 unset sentinel, child argv position, slow-child factor)
    Result:= ACond();
  until Result or (GetTickCount64 - T0 >= AMs);
end;

procedure Pump(AMs: Cardinal);
begin
  PumpUntil(function: Boolean begin Result:= False; end, AMs);
end;

function ChildCmd(AMs: Integer; const AText, AMarker: string): string;
begin
  Result:= Format('"%s" child %d "%s" "%s"', [ParamStr(0), AMs, AText, AMarker]);
end;

function Marker(const AName: string): string;
begin
  Result:= TPath.Combine(GScratch, AName + '.done');
end;

{ Waits, NOT pumping, until the fast child has finished, so its answer is queued (or
  about to be) and nothing has delivered it. A fixed sleep failed here on a loaded
  machine (measured: eight lanes on nine cores). }
function WaitChildDone(const AMarker: string): Boolean;
var
  T0: UInt64;
begin
  T0:= GetTickCount64;
  while not FileExists(AMarker) and (GetTickCount64 - T0 < PUMP_DONE_MS) do Sleep(MARKER_POLL_MS);
  Result:= FileExists(AMarker);
  Sleep(POST_QUEUE_MS);
end;

procedure TestAsyncContract;
var
  Calls, Code: Integer; Text: string; Thread: Cardinal; T0: UInt64;
begin
  Calls:= 0;
  Code:= -99;  // dl:ok large-magic-number@d9e4, magic-literal@d9e4 -- REVIEWED 2026-11-04 int3: test data (pump slice, -99 unset sentinel, child argv position, slow-child factor)
  Thread:= 0;
  T0:= GetTickCount64;
  RunCliAsync(ChildCmd(CHILD_SLOW_MS, 'hello', Marker('a1')),
    procedure(AExit: Integer; const AOut: string)
    begin
      Inc(Calls);
      Code:= AExit;
      Text:= AOut;
      Thread:= GetCurrentThreadId;
    end);
  Check('A1 RunCliAsync returns before the child ends', GetTickCount64 - T0 < BLOCK_LIMIT_MS, UIntToStr(GetTickCount64 - T0));
  Check('A2 ADone not called synchronously', Calls = 0);
  Check('A3 delivered', PumpUntil(function: Boolean begin Result:= Calls > 0; end, PUMP_DONE_MS));
  Check('A4 on the main thread', Thread = MainThreadID, Format('%d vs %d', [Thread, MainThreadID]));
  Check('A5 exit code', Code = CHILD_EXIT, IntToStr(Code));
  Check('A6 output', Text.Contains('hello'), Text);
  Pump(PUMP_QUIET_MS);
  Check('A7 exactly once', Calls = 1, IntToStr(Calls));

  Calls:= 0;
  RunCliAsync('"C:\no\such\exe-cliasync.exe" x',
    procedure(AExit: Integer; const AOut: string)
    begin
      Inc(Calls);
      Code:= AExit;
    end);
  Check('A8 a spawn failure is delivered', PumpUntil(function: Boolean begin Result:= Calls > 0; end, PUMP_DONE_MS));
  Check('A9 with -1', Code = -1, IntToStr(Code));
end;

procedure TestSupersede;
var
  Slot: TCliRunSlot; OldCalls, NewCalls: Integer; Text: string;
begin
  OldCalls:= 0;
  NewCalls:= 0;
  Slot:= TCliRunSlot.Create;
  try
    Slot.Start(ChildCmd(CHILD_SLOW_MS, 'old', Marker('b1')), CLI_ASYNC_STALL_MS,
      procedure(AExit: Integer; const AOut: string) begin Inc(OldCalls); end);
    Check('B1 Running after Start', Slot.Running);
    Pump(PUMP_QUIET_MS);  { the old child must really exist before it is superseded }
    Slot.Start(ChildCmd(CHILD_FAST_MS, 'new', Marker('b2')), CLI_ASYNC_STALL_MS,
      procedure(AExit: Integer; const AOut: string)
      begin
        Inc(NewCalls);
        Text:= AOut;
      end);
    Check('B2 the new run delivered', PumpUntil(function: Boolean begin Result:= NewCalls > 0; end, PUMP_DONE_MS));
    Check('B3 with its own output', Text.Contains('new'), Text);
    Check('B4 not Running once delivered', not Slot.Running);
    Pump(CHILD_SLOW_MS + PUMP_QUIET_MS);  { past the old child's natural end }
    Check('B5 the old answer never arrived', OldCalls = 0, IntToStr(OldCalls));
    Check('B6 the old child was killed', not FileExists(Marker('b1')));
    Check('B7 positive control: the new child did finish', FileExists(Marker('b2')));
  finally
    Slot.Free;
  end;
end;

procedure TestCancel;
var
  Slot: TCliRunSlot; Calls: Integer;
begin
  Calls:= 0;
  Slot:= TCliRunSlot.Create;
  try
    { C1-3: cancelled while the child runs. }
    Slot.Start(ChildCmd(CHILD_SLOW_MS, 'x', Marker('c1')), CLI_ASYNC_STALL_MS,
      procedure(AExit: Integer; const AOut: string) begin Inc(Calls); end);
    Pump(PUMP_QUIET_MS);
    Slot.Cancel;
    Check('C1 not Running after Cancel', not Slot.Running);
    Pump(CHILD_SLOW_MS + PUMP_QUIET_MS);
    Check('C2 no answer after Cancel', Calls = 0, IntToStr(Calls));
    Check('C3 the child was killed', not FileExists(Marker('c1')));

    { C4: the answer is ALREADY QUEUED when the cancel comes; this is the stale race. }
    Slot.Start(ChildCmd(CHILD_FAST_MS, 'x', Marker('c4')), CLI_ASYNC_STALL_MS,
      procedure(AExit: Integer; const AOut: string) begin Inc(Calls); end);
    Check('C4a the child finished, so the answer is queued', WaitChildDone(Marker('c4')));
    Slot.Cancel;
    Pump(PUMP_QUIET_MS);
    Check('C4b a queued answer is dropped too', Calls = 0, IntToStr(Calls));

    { C5: Cancel with nothing running. }
    Slot.Cancel;
    Check('C5 Cancel is a no-op when idle', not Slot.Running);
  finally
    Slot.Free;
  end;

  { C6: the slot dies with the form while a run is in flight. }
  Calls:= 0;
  Slot:= TCliRunSlot.Create;
  Slot.Start(ChildCmd(CHILD_SLOW_MS, 'x', Marker('c6')), CLI_ASYNC_STALL_MS,
    procedure(AExit: Integer; const AOut: string) begin Inc(Calls); end);
  Pump(PUMP_QUIET_MS);
  Slot.Free;  // dl:ok unprotected-object-free@2824 -- REVIEWED 2026-11-04 int3: the test IS the mid-run Free of the slot; a try-finally would hide the Free it exercises
  Pump(CHILD_SLOW_MS + PUMP_QUIET_MS);
  Check('C6 no answer after the slot is freed', Calls = 0, IntToStr(Calls));
  Check('C7 the child was killed', not FileExists(Marker('c6')));

  { C8: a slot freed with its answer already queued: Deliver must not touch the slot. }
  Calls:= 0;
  Slot:= TCliRunSlot.Create;
  Slot.Start(ChildCmd(CHILD_FAST_MS, 'x', Marker('c8')), CLI_ASYNC_STALL_MS,
    procedure(AExit: Integer; const AOut: string) begin Inc(Calls); end);
  Check('C8a the child finished, so the answer is queued', WaitChildDone(Marker('c8')));
  Slot.Free;  // dl:ok unprotected-object-free@2824 -- REVIEWED 2026-11-04 int3: the test IS the mid-run Free of the slot; a try-finally would hide the Free it exercises
  Pump(PUMP_QUIET_MS);
  Check('C8 queued answer dropped after the slot is freed', Calls = 0, IntToStr(Calls));
end;

procedure TestDoneIsSafe;
var
  Slot: TCliRunSlot; Calls, Second: Integer;
begin
  Calls:= 0;
  Second:= 0;
  RunCliAsync(ChildCmd(CHILD_FAST_MS, 'x', Marker('d1')),
    procedure(AExit: Integer; const AOut: string)
    begin
      Inc(Calls);
      raise Exception.Create('from ADone');  // dl:ok raise-bare-exception@1f50 -- REVIEWED 2026-11-04 int3: a test: any exception from ADone must be swallowed by the runner, the class is irrelevant
    end);
  TEscapeCounter.Count:= 0;
  System.Classes.ApplicationHandleException:= TEscapeCounter.Hit;
  try
    Check('D1a the raising ADone ran', PumpUntil(function: Boolean begin Result:= Calls > 0; end, PUMP_DONE_MS));
    Check('D1b its exception stayed inside', TEscapeCounter.Count = 0, IntToStr(TEscapeCounter.Count));
  finally
    System.Classes.ApplicationHandleException:= nil;
  end;

  { D2: ADone starts the next run on the same slot (a retry; a Refresh). }
  Slot:= TCliRunSlot.Create;
  try
    Slot.Start(ChildCmd(CHILD_FAST_MS, 'first', Marker('d2')), CLI_ASYNC_STALL_MS,
      procedure(AExit: Integer; const AOut: string)
      begin
        Slot.Start(ChildCmd(CHILD_FAST_MS, 'second', Marker('d3')), CLI_ASYNC_STALL_MS,
          procedure(AExit2: Integer; const AOut2: string) begin Inc(Second); end);
      end);
    Check('D2 ADone can start the next run', PumpUntil(function: Boolean begin Result:= Second > 0; end, PUMP_DONE_MS));
  finally
    Slot.Free;
  end;
end;

{ Runs last: StopAllCliRuns is for good. }
procedure TestStopAll;
var
  Slot: TCliRunSlot; Calls: Integer; T0: UInt64; Ok: Boolean;
begin
  Calls:= 0;
  Slot:= TCliRunSlot.Create;
  try
    Slot.Start(ChildCmd(CHILD_SLOW_MS * 4, 'x', Marker('e1')), CLI_ASYNC_STALL_MS,  // dl:ok magic-literal@23fb -- REVIEWED 2026-11-04 int3: test data (pump slice, -99 unset sentinel, child argv position, slow-child factor)
      procedure(AExit: Integer; const AOut: string) begin Inc(Calls); end);
    RunCliAsync(ChildCmd(CHILD_FAST_MS, 'x', Marker('e2')),
      procedure(AExit: Integer; const AOut: string) begin Inc(Calls); end);
    Check('E0 the fast child finished, so its answer is queued; e1 is mid-run', WaitChildDone(Marker('e2')));
    T0:= GetTickCount64;
    Ok:= StopAllCliRuns;
    Check('E1 every worker came back', Ok);
    Check('E2 well before the long child would have ended', GetTickCount64 - T0 < CHILD_SLOW_MS * 2, UIntToStr(GetTickCount64 - T0));
    Check('E3 not Running', not Slot.Running);
    { CheckSynchronize says whether it ran anything: a Deliver left in the queue would
      run from an unloaded package. Observing it through E4 cannot work: it reads freed
      memory and, measured, passes. }
    Check('E3b nothing is left in the queue', not CheckSynchronize(0));
    Pump(PUMP_QUIET_MS);
    Check('E4 no answer delivered, queued or not', Calls = 0, IntToStr(Calls));
    Slot.Start(ChildCmd(CHILD_FAST_MS, 'x', Marker('e5')), CLI_ASYNC_STALL_MS,
      procedure(AExit: Integer; const AOut: string) begin Inc(Calls); end);
    Check('E5 a Start after the stop does nothing', not Slot.Running);
    Pump(NOTHING_MS);
    Check('E6 and spawns nothing', (Calls = 0) and not FileExists(Marker('e5')));
  finally
    Slot.Free;
  end;
end;

procedure RunChild;
begin
  { child <ms> <text> <marker> }
  Writeln(ParamStr(3));  // dl:ok magic-literal@50ed -- REVIEWED 2026-11-04 int3: test data (pump slice, -99 unset sentinel, child argv position, slow-child factor)
  Flush(Output);
  Sleep(StrToIntDef(ParamStr(2), 0));
  TFile.WriteAllText(ParamStr(4), 'done');  // dl:ok magic-literal@06e7 -- REVIEWED 2026-11-04 int3: test data (pump slice, -99 unset sentinel, child argv position, slow-child factor)
  Halt(CHILD_EXIT);
end;

begin
  if ParamStr(1) = 'child' then RunChild;
  GScratch:= TPath.Combine(TPath.GetTempPath, Format('cliasync-tests-%d', [GetCurrentProcessId]));
  TDirectory.CreateDirectory(GScratch);
  try
    TestAsyncContract;
    TestSupersede;
    TestCancel;
    TestDoneIsSafe;
    TestStopAll;
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
