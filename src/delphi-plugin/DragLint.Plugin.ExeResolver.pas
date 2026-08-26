unit DragLint.Plugin.ExeResolver;

{ v0.86 policy (user ruling 2026-07-05, reaffirmed 2026-08-26): the IDE BPL is
  the only 32-bit artifact -- it must be, because bds.exe is -- and every process
  the plugin spawns is the WIN64 CLI. There is no 32-bit engine any more.

  WHY THE WIN32 SIBLING WAS REMOVED. It was a "just in case" fallback, and the
  case it turned out to cover was making things silently worse. On 2026-08-25 the
  editor gutter was blank for a whole session because a spawn had fallen through
  to it: that binary was drag-lint 1.3.0-alpha of 2026-08-13 against a current
  1.7.0-alpha, and had no rules\ directory beside it, so it loaded 0 external
  rules and reported "0 finding(s)" for every file. The live-diagnostics runner
  published that emptiness over the real findings and PaintLine, finding no rows,
  drew nothing.

  The lesson is not "stage rules there too" (though 0fddcf2 did). It is that a
  fallback which ANSWERS WRONGLY is worse than one that fails: nothing
  distinguishes its zero from a clean file. Owner ruling 2026-08-26: "we need
  only the 64 bit exe because it can hold huge databases and indexes and we
  don't really need 32 bit."

  WHAT REPLACED IT is not a guarantee, it is VISIBILITY. Resolution is logged
  once per DISTINCT outcome -- not per spawn, since this is called at every spawn
  site and a line per call would drown the log it exists to make readable -- and
  the one remaining degraded outcome shouts. "Which binary produced these
  answers" was the fact missing on 2026-08-25, and no amount of fallback
  cleverness substitutes for stating it. }

interface

/// <summary>Resolves the drag-lint CLI exe for ALL plugin spawn sites.</summary>
/// <returns>Full path when a candidate exists; else the bare name
/// 'drag-lint.exe' (resolved via PATH by CreateProcess).</returns>
/// <remarks>
/// <para>Order: 1) Settings ExePath override (set + exists);
/// 2) &lt;bpl-dir&gt;\..\dll-win64\drag-lint.exe (DEFAULT); 3) bare name.</para>
/// <para>Thread-safe: pure function over the settings snapshot and the file
/// system, plus a guarded write to the telemetry log when the resolved path
/// differs from the previous call's.</para>
/// <para>Step 3 is a DEGRADED outcome and says so in the telemetry log: it runs
/// whatever 'drag-lint.exe' means on PATH, which on this machine has resolved
/// to a months-old build before. There is deliberately NO 32-bit fallback --
/// see the note at that step.</para>
/// </remarks>
function DragLintExe: string;

implementation

uses
  System.SysUtils
  , System.SyncObjs
  , Winapi.Windows
  , DragLint.Plugin.Settings
  , DragLint.Plugin.Telemetry
  ;

var
  { Last outcome reported, so a stable resolution is logged once rather than on
    every spawn. Guarded by GLogLock -- DragLintExe is called from the live
    diagnostics worker as well as the IDE thread. }
  GLastLogged: string           = '';
  GLogLock   : TCriticalSection = nil;

procedure LogOnce(const AHow, APath: string);
var
  Line: string;
begin
  try
    if not Assigned(GLogLock) then GLogLock:= TCriticalSection.Create;
    GLogLock.Enter;
    try
      Line:= AHow + '=' + APath;
      if Line = GLastLogged then Exit;
      GLastLogged:= Line;
    finally
      GLogLock.Leave;
    end;
    DLT('exe', 'resolved ' + Line);
  except
    { telemetry is best-effort -- never let it disturb a spawn }
  end;
end;

function DragLintExe: string;
var
  BplDir: string;
begin
  Result:= LoadSettings.ExePath;
  if (Result <> '') and FileExists(Result) then
  begin
    LogOnce('override', Result);
    Exit;
  end;

  BplDir:= ExtractFilePath(GetModuleName(HInstance));

  Result:= ExtractFilePath(ExcludeTrailingPathDelimiter(BplDir)) + 'dll-win64\drag-lint.exe';
  if FileExists(Result) then
  begin
    LogOnce('win64', Result);
    Exit;
  end;

  { THE WIN32 SIBLING STEP IS GONE (owner ruling, 2026-08-26): "we need only the
    64 bit exe because it can hold huge databases and indexes and we don't really
    need 32 bit". That confirms the v0.86 policy rather than changing it -- the
    BPL stays Win32 because bds.exe is, but the ENGINE is 64-bit only.

    It had to go on the merits too. That fallback was 1.3.0-alpha of 2026-08-13
    against a current 1.7.0-alpha, and until 0fddcf2 it had no rules\ beside it
    at all, so it answered "0 finding(s)" for every file -- which is how the
    editor gutter went blank for a whole session. A fallback that answers
    WRONGLY is worse than one that fails, because nothing distinguishes its zero
    from a clean file.

    Why the bare name below is still the last resort rather than an empty
    string: DragLintExe has 17 call sites across 13 units, and not all of them
    guard against ''. Returning '' would turn a rare degraded spawn into an
    assortment of untested failure paths in code that can only be exercised in a
    live IDE. The bare name at least reaches CreateProcess, and it is now LOUD.
    Auditing those 17 sites so this can fail closed is worth doing separately. }

  { DEGRADED: no engine beside the BPL. CreateProcess resolves this off PATH,
    which is not under our control and has picked up a stale build before -- it
    once answered 33,626 findings against a real 14,764 and read as a
    catastrophic regression. Hence the shouting. }
  Result:= 'drag-lint.exe';
  LogOnce('BARE-NAME -- NO Win64 ENGINE FOUND. PATH decides, and PATH has been '
        + 'wrong before. Expect implausible results', Result);
end;

initialization

finalization
FreeAndNil(GLogLock);

end.
