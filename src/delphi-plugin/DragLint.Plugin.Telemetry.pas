unit DragLint.Plugin.Telemetry;

{ TEMPORARY debug telemetry (REMOVE before pushing to GitHub).

  A single thread-safe, timestamped log that every plugin flow writes to so the
  internal information flow can be traced end-to-end during debugging. The file
  lives with the other plugin logs (DragLint.Plugin.LogPaths, 2026-10-13):
      %LOCALAPPDATA%\drag-lint\logs\drag-lint-telemetry.log
  Each line: "hh:nn:ss.zzz [TAG] message". Call DLT('tag', 'msg') anywhere.
  Guarded end-to-end -- logging can never disturb the IDE. }

interface

procedure DLT(const ATag, AMsg: string);
function TelemetryLogPath: string;
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
