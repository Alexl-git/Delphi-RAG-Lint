unit DRagLint.Charts.Tools;

{ Where the chart emitters' external tool and database come from: the settings.json
  lookup, the shared "explicit -> set-by -> candidates" walk, the Graphviz dot.exe
  resolver and the clone-database guard. Each routine is a port of the named function
  in charts\src\Emit-Common.ps1 (line numbers of 2026-10-13); the PowerShell output is
  the reference (spec P3/P4), so every message is reproduced to the character.

  Not ported on purpose (triage 2026-10-13): Resolve-DragLintEngine -- an in-process
  emitter never starts drag-lint.exe (spec P5), so there is no engine to locate. }

interface

uses
  System.SysUtils;

const
  /// <summary>The environment variable that names dot.exe (step 1 of the dot walk).</summary>
  DOT_ENV_VAR = 'DRAGLINT_DOT';
  /// <summary>The dot.exe every machine of this repo falls back to (the last dot step).</summary>
  SHARED_DOT_DEFAULT = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe';  // dl:ok hardcoded-absolute-path@e72b -- REVIEWED 2026-10-13: the PS reference's own -SharedDefault (Resolve-GraphvizDot); only the LAST candidate of the walk and a parameter of ResolveGraphvizDot -- callers may pass another
  /// <summary>The environment variable that lets CloneDb accept a non-clone database.</summary>
  ALLOW_LIVE_DB_ENV_VAR = 'DRAGLINT_CHARTS_ALLOW_LIVE_DB';

type
  /// <summary>A tool or database the charts need could not be located, or was refused.</summary>
  EChartsTool = class(Exception);

  /// <summary>One candidate of a tool walk (an element of the PS $Steps array).</summary>
  TToolStep = record
    /// <summary>How the candidate is named in the "Looked, in order" message.</summary>
    Caption : string;
    /// <summary>The candidate path; '' when this step has no candidate.</summary>
    Path    : string;
    /// <summary>Why Path is empty (shown in the message instead of a path).</summary>
    WhyEmpty: string;
    /// <summary>Who SET Path; non-empty makes a missing Path an error, never a skip.</summary>
    SetBy   : string;
    /// <summary>Builds a step.</summary>
    /// <param name="pCaption">The step's name in the message.</param>
    /// <param name="pPath">The candidate path or ''.</param>
    /// <param name="pWhyEmpty">Why pPath is empty.</param>
    /// <param name="pSetBy">Who set pPath; '' for a plain candidate.</param>
    /// <returns>The step.</returns>
    class function Make(const pCaption, pPath, pWhyEmpty: string; const pSetBy: string = ''): TToolStep; static;
  end;

/// <summary>The settings.json the installer writes: %APPDATA%\drag-lint\settings.json.</summary>
/// <returns>The path, or '' when APPDATA is not set.</returns>
/// <remarks>Port of Get-DragLintSettingsPath (Emit-Common.ps1:98).</remarks>
function DragLintSettingsPath: string;  // dl:ok unused-public-symbol@c7ae -- REVIEWED 2026-10-13: step-2 port of Emit-Common for the in-process emitters (spec P1/P3); no production caller until an emitter is ported; pinned by ChartsTests and the ChartsCoreProbe parity harness, which sit outside this project index

/// <summary>One key of settings.json, or why it was skipped.</summary>
/// <param name="pSettingsPath">The settings file; '' means APPDATA was not set.</param>
/// <param name="pKey">The key; matched case-insensitively.</param>
/// <param name="pWhySkipped">'' when a value was found, else 'no %APPDATA%', 'file not found',
/// 'unreadable' or 'no "key" key'.</param>
/// <returns>The value as text, or '' when skipped.</returns>
/// <remarks>Port of Get-DragLintSetting (Emit-Common.ps1:102). PS traps closed:
/// PSObject.Properties[$Key] is case-insensitive, so the key is too; `"$($j.$Key)"` turns a
/// number or bool into text ('True'/'False' for a bool) and a null into '', and an empty
/// value is a skip; an empty file parses to $null, which is "no key", not "unreadable"; the file is
/// decoded like [IO.File]::ReadAllText (BOM, else UTF-8). Known limit: PS 7 ConvertFrom-Json
/// refuses keys that differ only in case ("unreadable"); this port takes the first match.
/// Never raises.</remarks>
function DragLintSetting(const pSettingsPath, pKey: string; out pWhySkipped: string): string;

/// <summary>The shared tool walk: the explicit path, else the first existing candidate.</summary>
/// <param name="pWhat">The tool's name in messages ('Graphviz dot').</param>
/// <param name="pParamName">The PS parameter name in messages ('Dot').</param>
/// <param name="pExplicit">A path the caller passed; '' when none.</param>
/// <param name="pSteps">The candidates, in order.</param>
/// <param name="pHint">The sentence that ends the not-found message.</param>
/// <returns>The full path of the first candidate that exists as a file.</returns>
/// <exception cref="EChartsTool">pExplicit is given and missing; a step with SetBy names a
/// missing file; or nothing exists (the message lists every place looked at).</exception>
/// <remarks>Port of Resolve-ChartTool (Emit-Common.ps1:111). A path is made full (against
/// the process's current directory, as the PS makes it full against its location) before it
/// is tested, and the full path is returned.</remarks>
function ResolveChartTool(const pWhat, pParamName, pExplicit: string; const pSteps: TArray<TToolStep>;
  const pHint: string): string;

/// <summary>The Graphviz dot.exe the charts run.</summary>
/// <param name="pExplicit">The -Dot value; '' walks the chain.</param>
/// <param name="pSettingsPath">settings.json (usually DragLintSettingsPath).</param>
/// <param name="pChartsRoot">The charts folder (the PS default is the folder above charts\src).</param>
/// <param name="pScriptDir">The folder of the chart scripts (the PS default is charts\src).</param>
/// <param name="pSharedDefault">The last candidate (usually SHARED_DOT_DEFAULT).</param>
/// <returns>The full path of dot.exe.</returns>
/// <exception cref="EChartsTool">As ResolveChartTool.</exception>
/// <remarks>Port of Resolve-GraphvizDot (Emit-Common.ps1:150). Order: explicit, DRAGLINT_DOT,
/// settings "dot", beside the scripts, installed v2, installed, dot.exe on PATH, shared. PS
/// trap closed: Get-Command searches PATH only (never the current folder), so PATH is walked
/// entry by entry rather than through FileSearch, which looks in the current folder first.</remarks>
function ResolveGraphvizDot(const pExplicit, pSettingsPath, pChartsRoot, pScriptDir, pSharedDefault: string): string;  // dl:ok unused-public-symbol@a1c8 -- REVIEWED 2026-10-13: step-2 port of Emit-Common for the in-process emitters (spec P1/P3); no production caller until an emitter is ported; pinned by ChartsTests and the ChartsCoreProbe parity harness, which sit outside this project index

/// <summary>A database path made full, refusing anything but a live clone.</summary>
/// <param name="pPath">The database path.</param>
/// <param name="pCloneRoot">The clone folder (the PS uses charts\scratch\db).</param>
/// <param name="pNote">'' or the note the PS prints when DRAGLINT_CHARTS_ALLOW_LIVE_DB=1 let
/// a non-clone through.</param>
/// <returns>The full path.</returns>
/// <exception cref="EChartsTool">Blank or missing path; a name not ending in .sqlite (a history
/// copy); a path outside pCloneRoot without the override.</exception>
/// <remarks>Port of Get-CloneDb (Emit-Common.ps1:231). The suffix rule is checked BEFORE the
/// override, as in the PS. PS traps closed: Test-Path without -PathType accepts a folder too;
/// EndsWith/StartsWith are OrdinalIgnoreCase; `-eq '1'` on the variable.</remarks>
function CloneDb(const pPath, pCloneRoot: string; out pNote: string): string;  // dl:ok unused-public-symbol@370a -- REVIEWED 2026-10-13: step-2 port of Emit-Common for the in-process emitters (spec P1/P3); no production caller until an emitter is ported; pinned by ChartsTests and the ChartsCoreProbe parity harness, which sit outside this project index

implementation

uses
  System.IOUtils, System.JSON, System.Character;

const
  SETTINGS_SUBPATH = 'drag-lint\settings.json';
  DOT_SETTING_KEY = 'dot';
  DOT_EXE = 'dot.exe';
  GRAPHVIZ_DOT_SUBPATH = 'graphviz\bin\dot.exe';
  SQLITE_EXT = '.sqlite';
  ALLOW_LIVE_ON = '1';
  PATH_LIST_SEP = ';';

function IsBlank(const pS: string): Boolean;
begin
  { [string]::IsNullOrWhiteSpace: Char.IsWhiteSpace, not Delphi Trim's <= #32 }
  for var C in pS do
    if not C.IsWhiteSpace then
      Exit(False);
  Result:= True;
end;

function JoinPath(const pDir, pChild: string): string;
begin
  { Join-Path: one separator between the two, whatever the folder ends in }
  if pDir = '' then
    Exit(pChild);
  Result:= IncludeTrailingPathDelimiter(pDir) + pChild;
end;

function IsLeaf(const pPath: string): Boolean;
begin
  Result:= (pPath <> '') and FileExists(pPath) and not DirectoryExists(pPath);
end;

class function TToolStep.Make(const pCaption, pPath, pWhyEmpty, pSetBy: string): TToolStep;
begin
  Result.Caption:= pCaption;
  Result.Path:= pPath;
  Result.WhyEmpty:= pWhyEmpty;
  Result.SetBy:= pSetBy;
end;

function DragLintSettingsPath: string;
begin
  var AppData:= GetEnvironmentVariable('APPDATA');
  Result:= if AppData <> '' then JoinPath(AppData, SETTINGS_SUBPATH) else '';
end;

function JsonValueText(pValue: TJSONValue): string;
begin
  if (pValue = nil) or (pValue is TJSONNull) then
    Exit('');
  if pValue is TJSONBool then
    Exit(if TJSONBool(pValue).AsBoolean then 'True' else 'False');
  if pValue is TJSONString then
    Exit(TJSONString(pValue).Value);
  Result:= pValue.ToJSON;
end;

function DragLintSetting(const pSettingsPath, pKey: string; out pWhySkipped: string): string;
begin
  Result:= '';
  if pSettingsPath = '' then
  begin
    pWhySkipped:= 'no %APPDATA%';
    Exit;
  end;
  if not IsLeaf(pSettingsPath) then
  begin
    pWhySkipped:= 'file not found';
    Exit;
  end;
  var Text: string;
  var Json: TJSONValue:= nil;
  try
    var Bytes:= TFile.ReadAllBytes(pSettingsPath);
    var Enc: TEncoding:= nil;
    var Skip:= TEncoding.GetBufferEncoding(Bytes, Enc, TEncoding.UTF8);
    Text:= Enc.GetString(Bytes, Skip, Length(Bytes) - Skip);
    if not IsBlank(Text) then
      Json:= TJSONValue.ParseJSONValue(Text, False, True);
  except
    { the PS catch is untyped: a read, decode or parse failure all read as 'unreadable' }
    on E: Exception do
    begin
      pWhySkipped:= 'unreadable';
      Exit;
    end;
  end;
  try
    pWhySkipped:= Format('no "%s" key', [pKey]);
    if not (Json is TJSONObject) then
      Exit;
    for var Pair in TJSONObject(Json) do
      if SameText(Pair.JsonString.Value, pKey) then
      begin
        Result:= JsonValueText(Pair.JsonValue);
        Break;
      end;
    if Result <> '' then
      pWhySkipped:= '';
  finally
    Json.Free;
  end;
end;

function ResolveChartTool(const pWhat, pParamName, pExplicit: string; const pSteps: TArray<TToolStep>;
  const pHint: string): string;
begin
  if pExplicit <> '' then
  begin
    var X:= ExpandFileName(pExplicit);
    if IsLeaf(X) then
      Exit(X);
    raise EChartsTool.CreateFmt('%s not found: -%s %s does not exist (%s)', [pWhat, pParamName, pExplicit, X]);
  end;
  var Looked: TArray<string>:= [Format('-%s (not given)', [pParamName])];
  for var S in pSteps do
  begin
    if S.Path <> '' then
    begin
      var X:= ExpandFileName(S.Path);
      if IsLeaf(X) then
        Exit(X);
      if S.SetBy <> '' then
        raise EChartsTool.CreateFmt('%s not found: %s names %s, which does not exist (%s) -- fix or remove it',
          [pWhat, S.SetBy, S.Path, X]);
      Looked:= Looked + [Format('%s %s (does not exist)', [S.Caption, S.Path])];
    end
    else
      Looked:= Looked + [Format('%s (%s)', [S.Caption, S.WhyEmpty])];
  end;
  for var K:= 0 to Length(Looked) - 1 do
    Looked[K]:= Format('%d) %s', [K + 1, Looked[K]]);
  raise EChartsTool.CreateFmt('%s not found. Looked, in order: %s. %s', [pWhat, string.Join('; ', Looked), pHint]);
end;

function DotOnPath: string;
begin
  for var Dir in GetEnvironmentVariable('PATH').Split([PATH_LIST_SEP]) do
  begin
    if Trim(Dir) = '' then
      Continue;
    var Candidate:= JoinPath(Dir, DOT_EXE);
    if IsLeaf(Candidate) then
      Exit(Candidate);
  end;
  Result:= '';
end;

function ResolveGraphvizDot(const pExplicit, pSettingsPath, pChartsRoot, pScriptDir, pSharedDefault: string): string;
begin
  var Why: string;
  var SetValue:= DragLintSetting(pSettingsPath, DOT_SETTING_KEY, Why);
  var App:= ExpandFileName(JoinPath(pChartsRoot, '..'));
  var OnPath:= DotOnPath;
  var SettingsName:= if pSettingsPath <> '' then 'settings ' + pSettingsPath else 'settings.json';
  var HintFile:= if pSettingsPath <> '' then pSettingsPath else 'settings.json';
  Result:= ResolveChartTool('Graphviz dot', 'Dot', pExplicit, [
    TToolStep.Make('$env:' + DOT_ENV_VAR, GetEnvironmentVariable(DOT_ENV_VAR), 'not set', '$env:' + DOT_ENV_VAR),
    TToolStep.Make(SettingsName + ' "dot"', SetValue, Why, Format('settings.json %s key "dot"', [pSettingsPath])),
    TToolStep.Make('beside the scripts', JoinPath(pScriptDir, GRAPHVIZ_DOT_SUBPATH), ''),
    TToolStep.Make('installed v2', ExpandFileName(JoinPath(pScriptDir, '..\' + GRAPHVIZ_DOT_SUBPATH)), ''),
    TToolStep.Make('installed', JoinPath(App, GRAPHVIZ_DOT_SUBPATH), ''),
    TToolStep.Make('dot.exe on PATH', OnPath, 'not on PATH'),
    TToolStep.Make('shared', pSharedDefault, '')],
    Format('Pass -Dot, set %s, or add "dot" to %s.', [DOT_ENV_VAR, HintFile]));
end;

function CloneDb(const pPath, pCloneRoot: string; out pNote: string): string;
begin
  pNote:= '';
  if IsBlank(pPath) then
    raise EChartsTool.Create('Get-CloneDb: no database path given');
  var Root:= ExpandFileName(pCloneRoot);
  if not (FileExists(pPath) or DirectoryExists(pPath)) then
    raise EChartsTool.CreateFmt('database not found: %s (clones live in %s)', [pPath, Root]);
  var Full:= ExpandFileName(pPath);
  if not Full.EndsWith(SQLITE_EXT, True) then
    raise EChartsTool.Create('refusing a database whose name does not end in .sqlite: ' + Full + ' -- the clone root keeps ' +
      'history copies (*.sqlite.pre-1.10, *.sqlite.pre-1.9, *.sqlite.pre-1.19, *.sqlite.pre-1.18, *.sqlite.pre-reindex-0530) beside the live clones, and ' +
      'they answer with an OLDER parse. Point at the *.sqlite clone itself.');
  if Full.StartsWith(Root + PathDelim, True) then
    Exit(Full);
  if GetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR) = ALLOW_LIVE_ON then
  begin
    pNote:= Format('  NOTE: %s=1 -- using a NON-CLONE database: %s', [ALLOW_LIVE_DB_ENV_VAR, Full]);
    Exit(Full);
  end;
  raise EChartsTool.Create('refusing a non-clone database: ' + Full + ' -- charts run against the clones in ' + Root + '. ' +
    'A live DB can be re-indexed mid-run, so an asserted count would not be reproducible; ' +
    'the clones (v=1.20.0-alpha / r=1.11.0-alpha) freeze it. Set ' + ALLOW_LIVE_DB_ENV_VAR + '=1 ' +
    'to override deliberately.');
end;

end.
