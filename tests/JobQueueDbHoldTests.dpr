program JobQueueDbHoldTests;
{$APPTYPE CONSOLE}
{ C12 ask N6: while the conversion editor child lives, the plugin's queue HOLDS the
  jkReindex / jkLintAll jobs whose --db is the launched project's DB, and runs every
  other job as usual. Without it a save-triggered reindex collides with the editor's
  reindex-before-apply ("unit skipped: reindex before apply failed: ... used by another
  process"). Spec: docs\superpowers\specs\2026-10-06-c12-engine-asks.md, N6.

  A QUEUE-SIDE PREDICATE, NOT THE ENGINE HOLD. This program never writes the per-user
  engine-hold sentinel (ide-release), so it cannot defer anything else on the box.

  THE CONTROLS. "the X job did not run" is also true of a queue that runs nothing, so
  test 2b proves a job on another DB runs DURING the hold, 3 proves a generic job on the
  held DB is not held, and 4 proves the held job is DEFERRED, not dropped.

  RED, measured 2026-11-08 on lane/147-P1 base b036f2cb: compile error E2003 undeclared
  identifier 'JobDbArg' (and HoldDb / ReleaseDb) -- the hold did not exist. }
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  Winapi.Windows,
  DRagLint.Core.EngineHold in '..\src\core\DRagLint.Core.EngineHold.pas',
  DRagLint.Core.OutputEncoding in '..\src\core\DRagLint.Core.OutputEncoding.pas',
  DRagLint.Core.ControlChannel in '..\src\core\DRagLint.Core.ControlChannel.pas',
  DragLint.Plugin.ProcRun in '..\src\delphi-plugin\DragLint.Plugin.ProcRun.pas',
  DragLint.Plugin.JobQueue in '..\src\delphi-plugin\DragLint.Plugin.JobQueue.pas';

const
  DB_X = 'C:\NoSuch\P1Hold\ProjectX.sqlite';
  DB_Y = 'C:\NoSuch\P1Hold\ProjectY.sqlite';
  RUN_WAIT_MS = 9000;
  SETTLE_MS = 1500;

var
  GPass, GFail: Integer;
  GWork       : string ;
  GRan        : string ;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then
  begin
    Inc(GPass);
    Writeln('PASS  ', AName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName);
    if ADetail <> '' then Writeln('      ', ADetail);
  end;
end;

function MarkerText: string;
begin
  Result:= '';
  if not TFile.Exists(GRan) then Exit;
  try
    Result:= TFile.ReadAllText(GRan);
  except
    Result:= '';
  end;
end;

function Ran(const ATag: string): Boolean;
begin
  Result:= Pos(ATag, MarkerText) > 0;
end;

{ Appends ATag to the marker file. The trailing `rem` carries the --db argument the
  hold reads, exactly where a real engine command line has it. }
function MakeJob(AKind: TJobKind; const ATag, ADb: string): TDragLintJob;
begin
  Result:= TDragLintJob.Create;
  Result.Kind     := AKind;
  Result.Title    := 'marker ' + ATag;
  Result.CmdLine  := Format('cmd.exe /c echo %s>> "%s" & rem --db "%s"', [ATag, GRan, ADb]);
  Result.TimeoutMs:= 20000;
end;

function WaitFor(AMaxMs: Integer; ACond: TFunc<Boolean>): Boolean;
var
  SW: TStopwatch;
begin
  SW:= TStopwatch.StartNew;
  while SW.ElapsedMilliseconds < AMaxMs do
  begin
    if ACond() then Exit(True);
    Sleep(50);
  end;
  Result:= ACond();
end;

{ 1 -- the parser the predicate keys on. }
procedure TestJobDbArg;
begin
  Check('1a quoted --db', SameText(JobDbArg('"e.exe" index --project "a.dproj" --db "C:\a b\x.sqlite" --platform Win64'), 'C:\a b\x.sqlite'));
  Check('1b bare --db', SameText(JobDbArg('e.exe lint-all --db C:\x.sqlite --out r.txt'), 'C:\x.sqlite'));
  Check('1c the FIRST --db wins (lint-all passes the library second)', SameText(JobDbArg('e lint-all --db "C:\p.sqlite" --db "C:\lib.sqlite"'), 'C:\p.sqlite'));
  Check('1d no --db', JobDbArg('e.exe info --json') = '');
end;

{ 2 + 3 + 4 -- hold X, queue a reindex on X, then a reindex on Y and a generic job on X. }
procedure TestHoldThenRelease;
var
  St: TQueueState;
begin
  JobQueue.HoldDb(DB_X);
  JobQueue.Enqueue(MakeJob(jkReindex, 'xreindex', DB_X));
  JobQueue.Enqueue(MakeJob(jkLintAll, 'xlintall', LowerCase(DB_X)));
  JobQueue.Enqueue(MakeJob(jkReindex, 'yreindex', DB_Y));
  JobQueue.Enqueue(MakeJob(jkGeneric, 'xgeneric', DB_X));
  Check('2b positive control: a reindex on ANOTHER db runs during the hold',
        WaitFor(RUN_WAIT_MS, function: Boolean begin Result:= Ran('yreindex') end),
        'marker: ' + MarkerText);
  Check('3 a generic job on the held db is not held',
        WaitFor(RUN_WAIT_MS, function: Boolean begin Result:= Ran('xgeneric') end),
        'marker: ' + MarkerText);
  Sleep(SETTLE_MS);
  Check('2a the reindex on the held db did NOT run', not Ran('xreindex'), 'marker: ' + MarkerText);
  Check('2c the lint-all on the held db (other case) did NOT run', not Ran('xlintall'), 'marker: ' + MarkerText);
  St:= JobQueue.GetState;
  Check('2d both held jobs are still pending', St.QueueDepth = 2, Format('depth %d', [St.QueueDepth]));

  JobQueue.ReleaseDb(DB_X);
  Check('4a the held reindex runs once the hold is released',
        WaitFor(RUN_WAIT_MS, function: Boolean begin Result:= Ran('xreindex') end),
        'marker: ' + MarkerText);
  Check('4b and the held lint-all',
        WaitFor(RUN_WAIT_MS, function: Boolean begin Result:= Ran('xlintall') end),
        'marker: ' + MarkerText);
  Check('4c in FIFO order', Pos('xreindex', MarkerText) < Pos('xlintall', MarkerText), 'marker: ' + MarkerText);
end;

begin
  GPass:= 0;
  GFail:= 0;
  GWork:= TPath.Combine(TPath.GetTempPath, 'drag-lint-jobqueue-dbhold-' + IntToStr(GetCurrentProcessId));
  GRan := TPath.Combine(GWork, 'ran.txt');
  TDirectory.CreateDirectory(GWork);
  Writeln('JobQueueDbHoldTests -- work dir: ', GWork);
  try
    TestJobDbArg;
    TestHoldThenRelease;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL  unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;
  ShutdownJobQueue;
  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
