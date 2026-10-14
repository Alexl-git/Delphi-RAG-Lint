unit DragLint.Plugin.LogPaths;

{ Where the plugin's log files live. Owner ruling 2026-10-13 (installer layout
  v2): ALWAYS %LOCALAPPDATA%\drag-lint\logs, dev box included -- never beside
  the BPL (not writable under Program Files) and never %TEMP%. Every writer and
  every reader of a plugin log goes through PluginLogPath, so a log is always
  looked for where it was written. }

interface

/// <summary>The log path for pFileName under a given local-app-data root.</summary>
/// <param name="pLocalAppData">The %LOCALAPPDATA% folder, with or without a trailing backslash.</param>
/// <param name="pFileName">Bare log file name, e.g. drag-lint-plugin.log.</param>
/// <returns>pLocalAppData\drag-lint\logs\pFileName.</returns>
/// <remarks>Pure: touches no file and reads no environment.</remarks>
function PluginLogPathIn(const pLocalAppData, pFileName: string): string;

/// <summary>The full path of a plugin log file, its folder created on demand.</summary>
/// <param name="pFileName">Bare log file name, e.g. drag-lint-plugin.log.</param>
/// <returns>%LOCALAPPDATA%\drag-lint\logs\pFileName, or '' when no local-app-data
/// folder can be found at all -- callers skip the write then, rather than log to
/// '\drag-lint\logs' on the current drive root.</returns>
/// <remarks>Creates the logs folder when missing; a failure to create it is
/// not raised -- the caller's own write then fails, and every log writer in
/// the plugin is already best-effort.</remarks>
function PluginLogPath(const pFileName: string): string;

implementation

uses
  System.SysUtils
  , System.IOUtils
  ;

function PluginLogPathIn(const pLocalAppData, pFileName: string): string;
const
  LOGS_REL = 'drag-lint\logs\';
begin
  Result:= IncludeTrailingPathDelimiter(pLocalAppData) + LOGS_REL + pFileName;
end;

var
  { %LOCALAPPDATA%, resolved ONCE at unit initialization (single-threaded, BPL
    load) -- PluginLogPath sits on the hot path of every log write, from the IDE
    thread and the live-diagnostics worker alike, so it must not re-query the
    shell folder or the disk each time. GLogDirReady is a benign race: two
    threads may both call ForceDirectories once. }
  GLocalAppData: string  = '';
  GLogDirReady : Boolean = False;

function ResolveLocalAppData: string;
begin
  { TPath.GetCachePath is CSIDL_LOCAL_APPDATA on Windows; the environment
    variable is the fallback if the shell call fails or returns nothing. }
  { Runs in the unit's initialization, i.e. while the IDE loads the BPL: ANY
    failure here would stop the plugin loading, so every exception class is
    deliberately caught and turned into the fallback below. }
  try
    Result:= TPath.GetCachePath;
  except
    on E: Exception do Result:= '';
  end;
  if Result = '' then Result:= GetEnvironmentVariable('LOCALAPPDATA');
end;

function PluginLogPath(const pFileName: string): string;
begin
  if GLocalAppData = '' then Exit('');
  Result:= PluginLogPathIn(GLocalAppData, pFileName);
  if not GLogDirReady then GLogDirReady:= ForceDirectories(ExtractFilePath(Result));
end;

initialization
  GLocalAppData:= ResolveLocalAppData;

end.