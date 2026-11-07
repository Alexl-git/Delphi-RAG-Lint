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

uses
  DragLint.Plugin.ProcRun
  ;

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
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.ExeResolver.ResolveEngine (DragLint.Plugin.ExeResolver.pas)</para>
/// <para>Calls: DragLint.Plugin.ExeResolver.LogOnce, DragLint.Plugin.Settings.LoadSettings, ExcludeTrailingPathDelimiter, ExtractFilePath, FileExists, GetModuleName</para>
/// <para>Returns: LoadSettings.ExePath; ExtractFilePath(ExcludeTrailingPathDelimiter(BplDir)) + 'dll-win64\drag-lint.exe'; 'drag-lint.exe'</para>
/// <seealso cref="DragLint.Plugin.ExeResolver.LogOnce"/>
/// <seealso cref="DragLint.Plugin.Settings.LoadSettings"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DragLintExe: string;

const
  /// <summary>The one user-facing message every plugin site shows when no usable
  /// engine exe resolves. Kept in one place so the wording cannot drift.</summary>
  ENGINE_NOT_FOUND_MSG = PROCRUN_ENGINE_NOT_FOUND_TEXT;

/// <summary>Diagnostic twin of <see cref="RequireEngine"/>: same usability test, but
/// pExe keeps the resolved path even when it is unusable so a message can name it
/// ("not found at X").</summary>
/// <param name="pExe">The resolved path (may be the degraded bare name).</param>
/// <returns>True when pExe exists on disk or is the bare name found on PATH.</returns>
/// <remarks>
/// Display/diagnostic sites only; a site that spawns must use RequireEngine.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.About.StartBackgroundSelfInfoFetch (DragLint.Plugin.About.pas), DragLint.Plugin.Diagnose.DescribeDiagFix (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.DiagConnections (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.EngineInfoCmd (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.EngineInfoJson (DragLint.Plugin.Diagnose.pas) (+3 more)</para>
/// <para>Calls: DragLint.Plugin.ExeResolver.DragLintExe, ExtractFilePath, FileExists, FileSearch, GetEnvironmentVariable</para>
/// <para>Mutates: pExe (out)</para>
/// <seealso cref="DragLint.Plugin.ExeResolver.DragLintExe"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveEngine(out pExe: string): Boolean;

/// <summary>Fail-closed twin of <see cref="DragLintExe"/>: resolves the engine and/// proves it is usable before a site spawns it.</summary>
/// <param name="pExe">The resolved exe on success; '' on failure.</param>
/// <returns>True when the resolved exe exists on disk or, for the degraded bare
/// name, is found on PATH. False when nothing usable resolves (the caller shows
/// <see cref="ENGINE_NOT_FOUND_MSG"/> or skips the spawn).</returns>
/// <remarks>
/// Same thread-safety as DragLintExe. Every plugin spawn site must use
/// this or <see cref="EngineExeOrEmpty"/>, never DragLintExe directly
/// (guard: tests\plugin\run_draglintexe_guarded.ps1).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.ExeResolver.EngineExeOrEmpty (DragLint.Plugin.ExeResolver.pas), DragLint.Plugin.Reports.OfferReindex (DragLint.Plugin.Reports.pas), DragLint.Plugin.UsagesForm.TUsagesEmbedCtl.RunFor (DragLint.Plugin.UsagesForm.pas)</para>
/// <para>Calls: DragLint.Plugin.ExeResolver.ResolveEngine</para>
/// <para>Returns: ResolveEngine(pExe)</para>
/// <para>Mutates: pExe (out)</para>
/// <seealso cref="DragLint.Plugin.ExeResolver.ResolveEngine"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RequireEngine(out pExe: string): Boolean;

/// <summary>Wrapper form of <see cref="RequireEngine"/> for sites that build a
/// command string.</summary>
/// <returns>The usable engine exe, or '' when none resolves; callers must treat ''
/// as "engine not found" and not spawn.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Diagnose.DiagVersions (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.RefreshEngineInfo (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Editor.DLExe (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.DLExe64 (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas) (+12 more)</para>
/// <para>Calls: DragLint.Plugin.ExeResolver.RequireEngine</para>
/// <seealso cref="DragLint.Plugin.ExeResolver.RequireEngine"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EngineExeOrEmpty: string;

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

function ResolveEngine(out pExe: string): Boolean;
begin
  pExe:= DragLintExe;
  Result:= (pExe <> '') and (FileExists(pExe)
    or ((ExtractFilePath(pExe) = '') and (FileSearch(pExe, GetEnvironmentVariable('PATH')) <> '')));
end;

function RequireEngine(out pExe: string): Boolean;
begin
  Result:= ResolveEngine(pExe);
  if not Result then pExe:= '';
end;
function EngineExeOrEmpty: string;
begin
  RequireEngine(Result);
end;

initialization

finalization
FreeAndNil(GLogLock);

end.
