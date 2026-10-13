unit LogPathTests.Cases;

{ DragLint.Plugin.LogPaths: every plugin log lives in
  %LOCALAPPDATA%\drag-lint\logs (installer layout v2, owner ruling 2026-10-13). }

interface

uses
  DUnitX.TestFramework
  ;

type
  [TestFixture]
  TLogPathTests = class
  public
    [Test] procedure LogPathIsUnderLocalAppDataLogs;
    [Test] procedure LogPathToleratesTrailingBackslash;
    [Test] procedure LogPathCreatesTheLogsFolder;
  end;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , DragLint.Plugin.LogPaths
  ;

const
  LOG_NAME = 'drag-lint-plugin.log';
  LOCAL_ROOT = 'C:\Users\U\AppData\Local';  // dl:ok hardcoded-absolute-path@bf05 -- synthetic test input: names no real location and reaches no filesystem call
  EXPECTED_PATH = 'C:\Users\U\AppData\Local\drag-lint\logs\drag-lint-plugin.log';  // dl:ok hardcoded-absolute-path@f82b -- synthetic test input: names no real location and reaches no filesystem call

procedure TLogPathTests.LogPathIsUnderLocalAppDataLogs;
begin
  Assert.AreEqual(EXPECTED_PATH, PluginLogPathIn(LOCAL_ROOT, LOG_NAME));
end;

procedure TLogPathTests.LogPathToleratesTrailingBackslash;
begin
  Assert.AreEqual(EXPECTED_PATH, PluginLogPathIn(LOCAL_ROOT + '\', LOG_NAME));
end;

procedure TLogPathTests.LogPathCreatesTheLogsFolder;
var
  Path: string;
begin
  Path:= PluginLogPath(LOG_NAME);
  Assert.AreEqual(PluginLogPathIn(TPath.GetCachePath, LOG_NAME), Path, 'under %LOCALAPPDATA%');
  Assert.IsTrue(TDirectory.Exists(ExtractFilePath(Path)), 'logs folder created: ' + Path);
end;

initialization
  TDUnitX.RegisterTestFixture(TLogPathTests);

end.