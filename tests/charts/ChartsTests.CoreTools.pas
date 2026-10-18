unit ChartsTests.CoreTools;

{ Cases for DRagLint.Charts.Tools (settings.json, the tool walk, the dot resolver and
  the clone guard), ported from charts\src\Emit-Common.ps1. Each expected message is
  what the PowerShell function says for the same input (spec P3/P4). Every case works
  in its own temp folder and restores any environment variable it touches. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreToolsTests = class
  private
    FDir: string;
    FOldDot: string;
    FOldLive: string;
    FOldCharts: string;
    function Touch(const pRelative: string; const pText: string = ''): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SettingSkipsAndReads;
    [Test] procedure ToolWalkExplicitMissingRaises;
    [Test] procedure ToolWalkSetByMissingRaises;
    [Test] procedure ToolWalkListsEveryPlaceLooked;
    [Test] procedure ToolWalkReturnsFirstExistingFullPath;
    [Test] procedure DotBadSettingNamesTheKey;
    [Test] procedure DotBesideTheScriptsWins;
    [Test] procedure CloneDbAcceptsCloneOnly;
    [Test] procedure CloneDbOverrideAddsNote;
    [Test] procedure ChartsHomeExplicitFileOrFolder;
    [Test] procedure ChartsHomeInsistedMissingRefuses;
    [Test] procedure ChartsHomeByLayoutAlwaysAnswers;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, DRagLint.Charts.Tools;

function MessageOf(const pProc: TProc): string;
begin
  Result:= '(no exception)';
  try
    pProc();
  except
    on E: EChartsTool do
      Result:= E.Message;
  end;
end;

procedure TCoreToolsTests.Setup;
begin
  FDir:= TPath.Combine(TPath.GetTempPath, 'charts-tools-' + TGUID.NewGuid.ToString);
  ForceDirectories(FDir);
  FOldDot:= GetEnvironmentVariable(DOT_ENV_VAR);
  FOldLive:= GetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR);
  FOldCharts:= GetEnvironmentVariable(CHARTS_DIR_ENV_VAR);
  SetEnvironmentVariable(DOT_ENV_VAR, nil);
  SetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR, nil);
  SetEnvironmentVariable(CHARTS_DIR_ENV_VAR, nil);
end;

procedure TCoreToolsTests.TearDown;
begin
  SetEnvironmentVariable(DOT_ENV_VAR, PChar(FOldDot));
  SetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR, PChar(FOldLive));
  if FOldDot = '' then
    SetEnvironmentVariable(DOT_ENV_VAR, nil);
  if FOldLive = '' then
    SetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR, nil);
  SetEnvironmentVariable(CHARTS_DIR_ENV_VAR, if FOldCharts = '' then nil else PChar(FOldCharts));
  TDirectory.Delete(FDir, True);
end;

function TCoreToolsTests.Touch(const pRelative, pText: string): string;
begin
  Result:= TPath.Combine(FDir, pRelative);
  ForceDirectories(ExtractFileDir(Result));
  TFile.WriteAllText(Result, pText, TEncoding.ASCII);
end;

procedure TCoreToolsTests.SettingSkipsAndReads;
var
  Why: string;
begin
  Assert.AreEqual('', DragLintSetting('', 'dot', Why));
  Assert.AreEqual('no %APPDATA%', Why);
  Assert.AreEqual('', DragLintSetting(TPath.Combine(FDir, 'absent.json'), 'dot', Why));
  Assert.AreEqual('file not found', Why);
  { PSObject.Properties[$Key] is case-insensitive }
  Assert.AreEqual('g\dot.exe', DragLintSetting(Touch('a.json', '{"DOT":"g\\dot.exe"}'), 'dot', Why));
  Assert.AreEqual('', Why);
  { an empty value is a skip, and so is an empty file ($null is not a pscustomobject) }
  Assert.AreEqual('', DragLintSetting(Touch('b.json', '{"dot":""}'), 'dot', Why));
  Assert.AreEqual('no "dot" key', Why);
  Assert.AreEqual('', DragLintSetting(Touch('c.json', '  '), 'dot', Why));
  Assert.AreEqual('no "dot" key', Why);
  Assert.AreEqual('', DragLintSetting(Touch('d.json', '{bad'), 'dot', Why));
  Assert.AreEqual('unreadable', Why);
  { "$($j.$Key)" on a bool is 'True' }
  Assert.AreEqual('True', DragLintSetting(Touch('e.json', '{"dot":true}'), 'dot', Why));
  Assert.AreEqual('', DragLintSetting(Touch('f.json', '[1]'), 'dot', Why));
  Assert.AreEqual('no "dot" key', Why);
end;

procedure TCoreToolsTests.ToolWalkExplicitMissingRaises;
begin
  var Missing:= TPath.Combine(FDir, 'nope.exe');
  Assert.AreEqual(Format('Tool not found: -T %s does not exist (%s)', [Missing, Missing]),
    MessageOf(procedure begin ResolveChartTool('Tool', 'T', Missing, [], 'Hint.'); end));
end;

procedure TCoreToolsTests.ToolWalkSetByMissingRaises;
begin
  var Missing:= TPath.Combine(FDir, 'set.exe');
  Assert.AreEqual(Format('Tool not found: $env:X names %s, which does not exist (%s) -- fix or remove it', [Missing, Missing]),
    MessageOf(procedure begin
      ResolveChartTool('Tool', 'T', '', [TToolStep.Make('$env:X', Missing, 'not set', '$env:X'),
        TToolStep.Make('later', Touch('later.exe'), '')], 'Hint.');
    end));
end;

procedure TCoreToolsTests.ToolWalkListsEveryPlaceLooked;
begin
  var Missing:= TPath.Combine(FDir, 'c.exe');
  Assert.AreEqual(Format('Tool not found. Looked, in order: 1) -T (not given); 2) $env:X (not set); 3) cand %s (does not exist). Pass -T.', [Missing]),
    MessageOf(procedure begin
      ResolveChartTool('Tool', 'T', '', [TToolStep.Make('$env:X', '', 'not set', '$env:X'),
        TToolStep.Make('cand', Missing, '')], 'Pass -T.');
    end));
end;

procedure TCoreToolsTests.ToolWalkReturnsFirstExistingFullPath;
begin
  var Second:= Touch('two.exe');
  Touch('three.exe');
  { a folder is not a candidate: Test-Path -PathType Leaf }
  Assert.AreEqual(Second, ResolveChartTool('Tool', 'T', '', [TToolStep.Make('dir', FDir, ''),
    TToolStep.Make('two', TPath.Combine(FDir, 'sub\..\two.exe'), ''), TToolStep.Make('three', TPath.Combine(FDir, 'three.exe'), '')], ''));
end;

procedure TCoreToolsTests.DotBadSettingNamesTheKey;
begin
  var Missing:= TPath.Combine(FDir, 'nope\dot.exe');
  var Settings:= Touch('settings.json', '{"dot":"' + Missing.Replace('\', '\\') + '"}');
  Assert.AreEqual(Format('Graphviz dot not found: settings.json %s key "dot" names %s, which does not exist (%s) -- fix or remove it',
    [Settings, Missing, Missing]),
    MessageOf(procedure begin
      ResolveGraphvizDot('', Settings, TPath.Combine(FDir, 'charts'), TPath.Combine(FDir, 'charts\src'), TPath.Combine(FDir, 'shared.exe'));
    end));
end;

procedure TCoreToolsTests.DotBesideTheScriptsWins;
begin
  var Beside:= Touch('charts\src\graphviz\bin\dot.exe');
  Touch('graphviz\bin\dot.exe');
  Assert.AreEqual(Beside, ResolveGraphvizDot('', TPath.Combine(FDir, 'absent.json'), TPath.Combine(FDir, 'charts'),
    TPath.Combine(FDir, 'charts\src'), ''));
  { without it, the installed one under <app> = the folder above charts }
  TFile.Delete(Beside);
  Assert.AreEqual(TPath.Combine(FDir, 'graphviz\bin\dot.exe'), ResolveGraphvizDot('', '', TPath.Combine(FDir, 'charts'),
    TPath.Combine(FDir, 'charts\src'), ''));
end;

procedure TCoreToolsTests.CloneDbAcceptsCloneOnly;
var
  Note: string;
begin
  var Root:= TPath.Combine(FDir, 'db');
  var Clone:= Touch('db\A.sqlite');
  var History:= Touch('db\A.sqlite.pre-1.9');
  var Live:= Touch('live\B.sqlite');
  Assert.AreEqual(Clone, CloneDb(Clone, Root, Note));
  Assert.AreEqual('', Note);
  Assert.AreEqual('Get-CloneDb: no database path given', MessageOf(procedure begin CloneDb(' ', Root, Note); end));
  var Missing:= TPath.Combine(Root, 'none.sqlite');
  Assert.AreEqual(Format('database not found: %s (clones live in %s)', [Missing, Root]),
    MessageOf(procedure begin CloneDb(Missing, Root, Note); end));
  Assert.StartsWith('refusing a database whose name does not end in .sqlite: ' + History + ' -- the clone root keeps',
    MessageOf(procedure begin CloneDb(History, Root, Note); end));
  Assert.StartsWith('refusing a non-clone database: ' + Live + ' -- charts run against the clones in ' + Root + '. ',
    MessageOf(procedure begin CloneDb(Live, Root, Note); end));
end;

procedure TCoreToolsTests.CloneDbOverrideAddsNote;
var
  Note: string;
begin
  var Root:= TPath.Combine(FDir, 'db');
  var History:= Touch('db\A.sqlite.pre-1.9');
  var Live:= Touch('live\B.sqlite');
  SetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR, '1');
  Assert.AreEqual(Live, CloneDb(Live, Root, Note));
  Assert.AreEqual('  NOTE: DRAGLINT_CHARTS_ALLOW_LIVE_DB=1 -- using a NON-CLONE database: ' + Live, Note);
  { the suffix rule is checked BEFORE the override: the override never reaches a history copy }
  Assert.StartsWith('refusing a database whose name does not end in .sqlite',
    MessageOf(procedure begin CloneDb(History, Root, Note); end));
end;

procedure TCoreToolsTests.ChartsHomeExplicitFileOrFolder;
var
  Root, Scripts, Why: string;
begin
  var Marker:= Touch('charts\src\any.txt');
  Assert.IsTrue(ResolveChartsHome(Marker, Root, Scripts, Why), Why);
  Assert.AreEqual(TPath.Combine(FDir, 'charts\src'), Scripts, 'a file names its folder');
  Assert.AreEqual(TPath.Combine(FDir, 'charts'), Root, 'the charts folder is the one above');
  Assert.AreEqual('', Why);
  Assert.IsTrue(ResolveChartsHome(TPath.Combine(FDir, 'charts\src'), Root, Scripts, Why), Why);
  Assert.AreEqual(TPath.Combine(FDir, 'charts\src'), Scripts, 'a folder names itself');
  { the environment variable is used when nothing explicit is given, and loses to it }
  SetEnvironmentVariable(CHARTS_DIR_ENV_VAR, PChar(FDir));
  Assert.IsTrue(ResolveChartsHome('', Root, Scripts, Why), Why);
  Assert.AreEqual(FDir, Scripts, 'DRAGLINT_CHARTS_DIR');
  Assert.IsTrue(ResolveChartsHome(Marker, Root, Scripts, Why), Why);
  Assert.AreEqual(TPath.Combine(FDir, 'charts\src'), Scripts, 'explicit wins over the variable');
end;

procedure TCoreToolsTests.ChartsHomeInsistedMissingRefuses;
var
  Root, Scripts, Why: string;
begin
  var Missing:= TPath.Combine(FDir, 'nowhere\Ask-Report.ps1');
  Assert.IsFalse(ResolveChartsHome(Missing, Root, Scripts, Why));
  Assert.AreEqual('explicit path: ' + Missing + ' (not found)', Why);
  Assert.AreEqual('', Scripts);
  SetEnvironmentVariable(CHARTS_DIR_ENV_VAR, PChar(Missing));
  Assert.IsFalse(ResolveChartsHome('', Root, Scripts, Why));
  Assert.AreEqual('environment variable ' + CHARTS_DIR_ENV_VAR + ': ' + Missing + ' (not found)', Why);
end;

procedure TCoreToolsTests.ChartsHomeByLayoutAlwaysAnswers;
var
  Root, Scripts, Why: string;
begin
  { no script is looked for: a layout folder, else the exe folder itself, so it never fails }
  Assert.IsTrue(ResolveChartsHome('', Root, Scripts, Why), Why);
  Assert.IsTrue(TDirectory.Exists(Scripts), Scripts);
  Assert.AreEqual(ExtractFileDir(Scripts), Root);
end;

end.