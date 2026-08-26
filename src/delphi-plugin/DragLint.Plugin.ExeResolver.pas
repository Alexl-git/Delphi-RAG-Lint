unit DragLint.Plugin.ExeResolver;

{ v0.86 policy (user ruling 2026-07-05): the IDE BPL is the only 32-bit
  artifact; every process the plugin spawns defaults to the Win64 CLI.
  The Win32 sibling next to the BPL is the "just in case" fallback only.

  2026-08-25: that fallback was SILENT, and silence is what made it dangerous.
  build_draglint_win64.bat stages a new exe over the deployed one, and while the
  locked original is renamed out of the way the Win64 candidate does not exist.
  A spawn in that window falls through to the Win32 sibling -- which on this
  machine is drag-lint 1.3.0-alpha (2026-08-13) against a current 1.7.0-alpha,
  and until this same change had no rules\ beside it at all, so it answered
  "0 finding(s)" for every file. The live-diagnostics runner published that
  emptiness into the diagnostic cache and the gutter went blank, with nothing
  anywhere saying a different engine had answered.

  So the resolution is now logged -- once per DISTINCT outcome, not once per
  spawn, because this is called on every spawn site and a line per call would
  make the log useless. A fallback additionally logs at a level the reader
  cannot miss, because "the answers changed because a different binary produced
  them" is exactly the fact that was missing. }

interface

/// <summary>Resolves the drag-lint CLI exe for ALL plugin spawn sites.</summary>
/// <returns>Full path when a candidate exists; else the bare name
/// 'drag-lint.exe' (resolved via PATH by CreateProcess).</returns>
/// <remarks>
/// <para>Order: 1) Settings ExePath override (set + exists);
/// 2) &lt;bpl-dir&gt;\..\dll-win64\drag-lint.exe (DEFAULT);
/// 3) &lt;bpl-dir&gt;\drag-lint.exe (Win32 fallback); 4) bare name.</para>
/// <para>Thread-safe: pure function over the settings snapshot and the file
/// system, plus a guarded write to the telemetry log when the resolved path
/// differs from the previous call's.</para>
/// <para>Steps 3 and 4 are DEGRADED outcomes and say so in the telemetry log.
/// Step 4 in particular runs whatever 'drag-lint.exe' means on PATH, which on
/// this machine has resolved to a months-old build before.</para>
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
    if GLogLock = nil then GLogLock:= TCriticalSection.Create;
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

  Result:= BplDir + 'drag-lint.exe';
  if FileExists(Result) then
  begin
    { DEGRADED. Named loudly: findings produced by this binary may differ from
      the Win64 engine's, and a run that silently produces none is how the
      gutter went blank on 2026-08-24. }
    LogOnce('WIN32-FALLBACK (Win64 engine ABSENT -- results may differ)', Result);
    Exit;
  end;

  { DEGRADED FURTHER: no candidate on disk. CreateProcess will resolve this off
    PATH, which is not under our control and has picked up a stale build before. }
  Result:= 'drag-lint.exe';
  LogOnce('BARE-NAME (no engine found beside the BPL -- PATH decides)', Result);
end;

initialization

finalization
FreeAndNil(GLogLock);

end.
