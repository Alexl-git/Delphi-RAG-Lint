program IndexJobTests;
{$APPTYPE CONSOLE}
{ What does a save actually ask the engine to do?

  WHAT THIS PINS. Tier 1 of PLAN-lint-tree: saving a unit refreshes its project
  index, so the fan-out in tiers 2 and 3 is answering from current data. The
  whole tier is one command line and one coalesce key, and each carries a
  failure that is silent if it is ever "simplified":

    --rebuild would re-parse the entire project on every Ctrl+S AND, on that
      path only, stop the resident LSP first to release the FTS trigger lock --
      taking the IDE's own diagnostics down every time anyone saved. Case 1b is
      a NEGATIVE assertion, so case 1a exists to prove the haystack is real.

    a FILE target instead of --project cannot see a newly added unit's closure,
      and a FOLDER target silently widens a project DB into a directory DB
      (measured 2026-09-02: DataCopy 39 -> 72 files, findings 393 -> 1123).

    a coalesce key per FILE rather than per DATABASE means Save All on 30 units
      queues 30 runs against one database. Keyed on the DB the queue keeps the
      newest and drops the rest, which is the reason this goes through the queue
      instead of CreateProcessW at all.

  WHY A CONSOLE TEST. DragLint.Plugin.IndexJob has no ToolsAPI -- it exists as a
  separate unit precisely so the string can be asserted without an IDE. The
  IDE-bound half is the AfterSave wiring in SaveNotifier, which is O-block work. }
uses
  System.SysUtils,
  System.StrUtils,
  DRagLint.Core.EngineHold in '..\src\core\DRagLint.Core.EngineHold.pas',
  DragLint.Plugin.ProcRun in '..\src\delphi-plugin\DragLint.Plugin.ProcRun.pas',
  DragLint.Plugin.JobQueue in '..\src\delphi-plugin\DragLint.Plugin.JobQueue.pas',
  DRagLint.Core.Model in '..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Core.JsonFile in '..\src\core\DRagLint.Core.JsonFile.pas',
  DRagLint.Index.Manifest in '..\src\index\DRagLint.Index.Manifest.pas',
  DragLint.Plugin.IndexJob in '..\src\delphi-plugin\DragLint.Plugin.IndexJob.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName);
    if ADetail <> '' then Writeln('      ', ADetail);
  end;
end;

const
  EXE  = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe';
  PROJ = 'C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj';
  DB   = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite';

procedure TestCmdLine;
var
  Cmd: string;
begin
  Cmd:= BuildProjectIndexCmdLine(EXE, PROJ, DB, 'Win32');

  { 1a POSITIVE CONTROL for 1b: without it, "no --rebuild" is equally true of
    an empty string, a misspelled verb, or a builder that returned nothing. }
  Check('1a it is an incremental project index',
        ContainsText(Cmd, ' index ') and ContainsText(Cmd, '--project') and
        ContainsText(Cmd, '--db'),
        Cmd);
  Check('1b and it is NOT a rebuild',
        not ContainsText(Cmd, '--rebuild'),
        'a save would re-parse the whole project AND stop the resident LSP: ' + Cmd);
  Check('1c the project file is the target, not the saved file',
        ContainsText(Cmd, '--project "' + PROJ + '"'), Cmd);
  Check('1d the db is passed explicitly',
        ContainsText(Cmd, '--db "' + DB + '"'), Cmd);
  Check('1e the platform is passed when known',
        ContainsText(Cmd, '--platform Win32'), Cmd);
end;

procedure TestPlatformOmitted;
var
  Cmd: string;
begin
  Cmd:= BuildProjectIndexCmdLine(EXE, PROJ, DB, '');
  Check('2a an unknown platform is left out entirely',
        not ContainsText(Cmd, '--platform'),
        'a bare --platform with nothing after it would swallow the next argument: ' + Cmd);
  Check('2b POSITIVE CONTROL: the rest of the command survives',
        ContainsText(Cmd, '--project') and ContainsText(Cmd, '--db'), Cmd);
end;

procedure TestQuoting;
var
  Cmd: string;
begin
  Cmd:= BuildProjectIndexCmdLine('C:\Program Files\dl\drag-lint.exe',
                                 'C:\My Projects\A B.dproj',
                                 'C:\My Projects\_D-RAG\A B.sqlite', 'Win64');
  Check('3 every path with a space is quoted',
        ContainsText(Cmd, '"C:\Program Files\dl\drag-lint.exe"') and
        ContainsText(Cmd, '"C:\My Projects\A B.dproj"') and
        ContainsText(Cmd, '"C:\My Projects\_D-RAG\A B.sqlite"'),
        Cmd);
end;

procedure TestCoalesceKey;
var
  A, B, C: string;
begin
  A:= ProjectIndexCoalesceKey(DB);
  B:= ProjectIndexCoalesceKey(UpperCase(DB));
  C:= ProjectIndexCoalesceKey('C:\other\_D-RAG\Other.sqlite');

  Check('4a the key names the database', ContainsText(A, LowerCase(DB)), A);
  { Save All fires AfterSave once per module; every one of them resolves to the
    same project DB, and Windows hands paths back in whatever case it likes. }
  Check('4b two saves in the same project collapse to ONE job', A = B,
        Format('[%s] vs [%s] -- a case difference would queue a second full reindex', [A, B]));
  Check('4c POSITIVE CONTROL: a different project does NOT collapse', A <> C,
        'every project would share one key and starve the others');
end;

procedure TestJob;
var
  Job: TDragLintJob;
begin
  Job:= BuildProjectIndexJob(EXE, PROJ, DB, 'Win32');
  try
    Check('5a the job carries the incremental command line',
          ContainsText(Job.CmdLine, '--project') and not ContainsText(Job.CmdLine, '--rebuild'),
          Job.CmdLine);
    Check('5b it coalesces on the database', Job.CoalesceKey = ProjectIndexCoalesceKey(DB),
          Job.CoalesceKey);
    Check('5c it has a bounded timeout', Job.TimeoutMs = INDEX_JOB_TIMEOUT_MS,
          Format('TimeoutMs=%d', [Job.TimeoutMs]));
    { A non-empty CoalesceKey is what the queue keys on; an empty one means
      every save is kept, which is the bug this whole unit exists to avoid. }
    Check('5d the key is non-empty', Job.CoalesceKey <> '', 'coalescing is off');
    Check('5e it is titled for the status bar', ContainsText(Job.Title, 'Micronite2027'),
          Job.Title);
    Check('5f it is not streaming -- no progress marquee on every save',
          not Job.Streaming);
  finally
    Job.Free;
  end;
end;

{ 2026-10-16: the save path paired the ACTIVE project with GLastProjectDb -- the
  last project OPENED -- and wrote Micronite2027's closure into
  Delphi13MigrationAssistant.sqlite for a whole session. The target DB is now
  the manifest's unique owner of the active project, or nothing at all. }
procedure TestReindexTarget;
const
  OTHER_DB = 'C:\Projects\Other\_D-RAG\Other.sqlite';
var
  Got, Why: string;
begin
  Got:= ReindexTargetDb(PROJ, pdmUnique, DB, Why);
  { the local is Got, not Db: Delphi is case-insensitive, so a local named Db
    shadows the DB constant and 6a would compare a variable with itself. }
  Check('6a POSITIVE CONTROL: a unique owner is the target', Got = DB,
        Format('got [%s] why [%s]', [Got, Why]));
  Check('6b ... with no refusal reason', Why = '', Why);

  Got:= ReindexTargetDb(PROJ, pdmNone, OTHER_DB, Why);
  Check('6c no owner -> nothing is written, whatever DB is to hand', Got = '',
        'a reindex would land in a DB no section gives this project: ' + Got);
  Check('6d ... and the reason names the project', ContainsText(Why, PROJ), Why);

  Got:= ReindexTargetDb(PROJ, pdmAmbiguous, OTHER_DB, Why);
  Check('6e two claimants -> refuse, never choose', Got = '', Got);
  Check('6f ... and the reason says so', ContainsText(Why, 'two or more'), Why);

  Got:= ReindexTargetDb('', pdmUnique, DB, Why);
  Check('6g no active project -> nothing is written', Got = '', Got);
  Check('6h ... and the reason says so', ContainsText(Why, 'no active project'), Why);

  Got:= ReindexTargetDb(PROJ, pdmUnique, '', Why);
  Check('6i a unique match with a blank DB is still a refusal', Got = '', Got);
end;

{ 2026-10-25: AfterSave posted "reindexing..." to the Messages pane even when the
  per-file fallback was skipped (no manifest section covers the file), i.e. when
  nothing was started. The message now follows the decision. }
procedure TestSaveReindexAction;
begin
  Check('7a POSITIVE CONTROL: a queued project job -> project action',
        ChooseSaveReindex(True, '') = sraProject);
  Check('7b a queued job wins over a fallback DB',
        ChooseSaveReindex(True, DB) = sraProject);
  Check('7c no job, a covering DB -> per-file fallback',
        ChooseSaveReindex(False, DB) = sraFile);
  Check('7d no job and no covering DB -> nothing started',
        ChooseSaveReindex(False, '') = sraNone,
        'the Messages pane would claim a reindex that never ran');
  Check('7e only sraNone suppresses the message',
        (ChooseSaveReindex(False, '') = sraNone) and (ChooseSaveReindex(True, '') <> sraNone) and
        (ChooseSaveReindex(False, DB) <> sraNone));
end;

{ 2026-10-25: JobQueue calls GReindexDoneHook (-> RequestRelint) after EVERY jkReindex
  job. A job that also carries its own OnDone re-lint makes one reindex re-lint twice.
  The save job must be a jkReindex (so the hook fires) with NO OnDone of its own. }
procedure TestOneRelintPerReindex;
var
  Job: TDragLintJob;
begin
  Job:= BuildProjectIndexJob(EXE, PROJ, DB, 'Win32');
  try
    Check('8a the save job is a jkReindex, so GReindexDoneHook re-lints it',
          Job.Kind = jkReindex);
    Check('8b ... and carries no OnDone of its own (the hook is the one re-lint path)',
          not Assigned(Job.OnDone));
  finally
    Job.Free;
  end;
  Job:= TDragLintJob.Create;
  try
    Job.OnDone:= procedure(AExit: Integer; AOutput: string) begin end;
    Check('8c POSITIVE CONTROL: Assigned(OnDone) can be true on a job', Assigned(Job.OnDone));
  finally
    Job.Free;
  end;
end;

begin  GPass:= 0;
  GFail:= 0;
  Writeln('IndexJobTests');

  try
    TestCmdLine;
    TestPlatformOmitted;
    TestQuoting;
    TestCoalesceKey;
    TestJob;
    TestReindexTarget;
    TestSaveReindexAction;
    TestOneRelintPerReindex;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL  unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;

  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
