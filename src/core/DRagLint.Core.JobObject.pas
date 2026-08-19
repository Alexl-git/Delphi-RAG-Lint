unit DRagLint.Core.JobObject;

{ v0.47: child-process lifecycle guard.
  v1.7 Task 2: MOVED here from DragLint.Plugin.JobObject so the CLI can use it
  too. It was never plugin-specific -- only its first caller was -- and the LSP
  merge proxy needs exactly the same guarantee for the DelphiLSP child it
  spawns. One copy, two callers; a forked second copy would drift.

  The plugin spawns two long-running helper processes -- the engine LSP server
  (drag-lint.exe lsp) and the standalone Graph viewer (drag_lint_graph.exe).
  Both self-terminate on a CLEAN IDE shutdown (the spawn sites TerminateProcess
  them in finalization), but a crash or a Task-Manager kill of the IDE skips
  that finalization and ORPHANS them -- and an orphaned child keeps the project
  index DB open, so a later reindex fails with "used by another process".

  This unit assigns every spawned child to a single Windows Job Object created
  with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE. The spawning process holds the only
  handle to that job; when it dies for ANY reason -- clean exit, crash, or kill
  -- the OS closes the handle and force-terminates every process still in the
  job. No cooperation from the children is required, which is the entire point:
  cleanup code cannot run in a process that was killed with TerminateProcess,
  and that is precisely the case that orphans children. The children also carry
  a --parent-pid self-exit watcher as belt-and-suspenders.

  ASSIGN BEFORE THE CHILD RUNS. A child assigned after it has already started
  may have spawned grandchildren of its own (DelphiLSP starts Agent0/Agent1),
  and those are outside the job. Callers that care should create the child
  suspended, assign, and only then resume. }

interface

uses
  Winapi.Windows
  ;

/// <summary>Assigns AProcess to the drag-lint kill-on-close job object so the
/// OS force-terminates it when the IDE process exits, crashes, or is killed.
/// Lazily creates the job on first call. No-op for a 0/invalid handle, and
/// best-effort (a failed assignment is swallowed, e.g. a child already in an
/// incompatible job on pre-Win8 -- the --parent-pid watcher still covers it).</summary>
/// <remarks>Thread-safety: call from the main (IDE) thread, like the spawn sites.</remarks>
procedure AssignToDragLintJob(AProcess: THandle);

implementation

var
  GJob: THandle = 0;

function EnsureJob: THandle;
var
  Info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION;
begin
  if GJob = 0 then
  begin
    GJob:= CreateJobObject(nil, nil);
    if GJob <> 0 then
    begin
      FillChar(Info, SizeOf(Info), 0);
      Info.BasicLimitInformation.LimitFlags:= JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
      SetInformationJobObject(GJob, JobObjectExtendedLimitInformation, @Info, SizeOf(Info));
    end;
  end;
  Result:= GJob;
end;

procedure AssignToDragLintJob(AProcess: THandle);
var
  Job: THandle;
begin
  if (AProcess = 0) or (AProcess = INVALID_HANDLE_VALUE) then Exit;
  Job:= EnsureJob;
  if Job = 0 then Exit;
  AssignProcessToJobObject(Job, AProcess); { best-effort }
end;

{ Intentionally NO finalization that closes GJob: closing it would kill the
  children, but on a clean unload the spawn sites already TerminateProcess them.
  When the IDE process truly exits, the OS closes GJob for us and kill-on-close
  fires -- which is exactly the crash/kill case we are guarding. }

end.
