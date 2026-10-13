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
/// <returns>%LOCALAPPDATA%\drag-lint\logs\pFileName.</returns>
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

function PluginLogPath(const pFileName: string): string;
begin
  { TPath.GetCachePath is CSIDL_LOCAL_APPDATA on Windows. }
  Result:= PluginLogPathIn(TPath.GetCachePath, pFileName);
  ForceDirectories(ExtractFilePath(Result));
end;

end.