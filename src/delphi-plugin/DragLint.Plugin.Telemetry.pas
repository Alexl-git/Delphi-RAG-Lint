unit DragLint.Plugin.Telemetry;

{ TEMPORARY debug telemetry (REMOVE before pushing to GitHub).

  A single thread-safe, timestamped log that every plugin flow writes to so the
  internal information flow can be traced end-to-end during debugging. The file
  lives with the other plugin logs (DragLint.Plugin.LogPaths, 2026-10-13):
      %LOCALAPPDATA%\drag-lint\logs\drag-lint-telemetry.log
  Each line: "hh:nn:ss.zzz [TAG] message". Call DLT('tag', 'msg') anywhere.
  Guarded end-to-end -- logging can never disturb the IDE. }

interface

/// <param name="ATag"><!-- drag-lint:auto type -->const string</param>
/// <param name="AMsg"><!-- drag-lint:auto type -->const string</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: initialization/finalization (DragLint.Plugin.AboutForm.pas), initialization/finalization (DragLint.Plugin.CliAsync.pas), initialization/finalization (DragLint.Plugin.DockForm.pas), initialization/finalization (DragLint.Plugin.EditViewNotifier.pas), initialization/finalization (DragLint.Plugin.LiveDiagnostics.pas) (+96 more)</para>
/// <para>Calls: DragLint.Plugin.Telemetry.EnsureLock, DragLint.Plugin.Telemetry.TelemetryLogPath, FormatDateTime</para>
/// <para>Catches: Exception (empty)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DragLint.Plugin.Telemetry.EnsureLock"/>
/// <seealso cref="DragLint.Plugin.Telemetry.TelemetryLogPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure DLT(const ATag, AMsg: string);
/// <returns><!-- drag-lint:auto -->string -- Observed: PluginLogPath(TELEMETRY_LOG_NAME).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Telemetry.DLT (DragLint.Plugin.Telemetry.pas), DragLint.Plugin.Telemetry.DLTReset (DragLint.Plugin.Telemetry.pas)</para>
/// <para>Calls: DragLint.Plugin.LogPaths.PluginLogPath</para>
/// <seealso cref="DragLint.Plugin.LogPaths.PluginLogPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TelemetryLogPath: string;
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.RegisterDragLintMenu (DragLint.Plugin.Editor.pas)</para>
/// <para>Calls: DragLint.Plugin.Telemetry.EnsureLock, DragLint.Plugin.Telemetry.TelemetryLogPath, FormatDateTime</para>
/// <para>Catches: Exception (empty)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DragLint.Plugin.Telemetry.EnsureLock"/>
/// <seealso cref="DragLint.Plugin.Telemetry.TelemetryLogPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure DLTReset; { truncate the log (called once at plugin startup) }

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.SyncObjs
  , Winapi.Windows
  , DragLint.Plugin.LogPaths
  ;

var
  GLock: TCriticalSection = nil;

function TelemetryLogPath: string;
const
  TELEMETRY_LOG_NAME = 'drag-lint-telemetry.log';
begin
  Result:= PluginLogPath(TELEMETRY_LOG_NAME);
end;

procedure EnsureLock;
begin
  if GLock = nil then GLock:= TCriticalSection.Create;
end;

procedure DLT(const ATag, AMsg: string);
begin
  try
    EnsureLock;
    GLock.Enter;
    try
      var LogPath: string:= TelemetryLogPath;
      if LogPath <> '' then { '' = no local-app-data folder: skip }
        TFile.AppendAllText(LogPath, FormatDateTime('hh:nn:ss.zzz', Now) + ' [' + ATag + '] ' + AMsg + sLineBreak);
    finally
      GLock.Leave;
    end;
  except
    { telemetry is best-effort -- never raise }
  end;
end;

procedure DLTReset;
begin
  try
    EnsureLock;
    GLock.Enter;
    try
      TFile.WriteAllText(TelemetryLogPath, '=== drag-lint telemetry started ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ===' + sLineBreak);
    finally
      GLock.Leave;
    end;
  except
  end;
end;

initialization

finalization
FreeAndNil(GLock);

end.
