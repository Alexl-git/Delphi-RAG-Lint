unit DRagLint.Index.RepoConfig;

/// <summary>The repository configuration: ONE &lt;repo root&gt;\_D-RAG\config.json,
/// found by walking UP from a path, the way git finds .git and CodeGraph finds
/// .codegraph.</summary>
/// <remarks>
/// WHY THIS EXISTS (owner ruling, 2026-10-06/07). The engine is a separate,
/// self-contained tool on its way to being an MCP server, and "all of the
/// configuration has to live inside the project". Before this unit the
/// configuration was spread over six files with six search rules -- a global
/// manifest beside the exe (and in every sibling folder of it), a dotted local
/// manifest walked up from the CWD, drag-lint-lint.json, drag-lint-layers.json,
/// drag-lint-project.json and .drag-lint-workspace.json -- so the same command
/// answered differently depending on the folder the shell stood in.
///
/// The layout, created by `drag-lint init`:
///   &lt;root&gt;\_D-RAG\config.json      -- this file, the only configuration
///   &lt;root&gt;\_D-RAG\&lt;Project&gt;.sqlite -- one index per configured project
///   &lt;root&gt;\_D-RAG\.gitignore       -- '*' except itself and config.json
///
/// config.json:
///   { "version": 1,
///     "projects": [ { "name": "App", "dproj": "App\\App.dproj",
///                     "platform": "Win32", "delphi": "20.0" } ],
///     "exclude": [], "settings": {}, "docs": {}, "lint": {}, "layers": {} }
/// "dproj" is relative to the root (absolute is accepted). "settings" and "docs"
/// are the manifest's own blocks; "lint" and "layers" are the bodies of what used
/// to be drag-lint-lint.json and drag-lint-layers.json.
///
/// THE ANCHOR. Discovery starts from a process-wide anchor that the CLI sets
/// ONCE per run from the verb's own path arguments (SetAnchor), so the ~25
/// places that load configuration do not each have to be taught where to look.
/// No anchor means the CWD, as for git.
///
/// This unit depends on nothing project-specific (no manifest types), so the
/// manifest unit can build on it without a unit cycle.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.
/// </remarks>

interface

uses
  System.SysUtils
  ;

const
  /// <summary>The config.json "version" this build writes and reads.</summary>
  REPO_CONFIG_VERSION = 1;

type
  /// <summary>Raised when a config.json exists and cannot be read or parsed:
  /// the run must stop rather than answer from another source.</summary>
  ERepoConfigError = class(Exception);

  /// <summary>One configured project.</summary>
  TRepoProject = record
    /// <summary>Name: the index file's base name and the --only selector.</summary>
    Name: string;
    /// <summary>The .dproj (or .dpr), ABSOLUTE.</summary>
    Dproj: string;
    /// <summary>'Win32' or 'Win64'; '' leaves the choice to the verb.</summary>
    Platform: string;
    /// <summary>BDS version ('20.0' = 10.3, '37.0' = 13); '' means the .dproj's
    /// ProjectVersion decides.</summary>
    Delphi: string;
    /// <summary>The project's index, ABSOLUTE: &lt;home&gt;\&lt;Name&gt;.sqlite.</summary>
    Db: string;
    /// <summary>True when the entry has an "ownRoots" list (even an empty one,
    /// which the reader refuses).</summary>
    HasOwnRoots: Boolean;
    /// <summary>The entry's "ownRoots", ABSOLUTE (relative entries are made
    /// absolute against the repository root).</summary>
    OwnRoots: TArray<string>;
  end;

  /// <summary>A parsed config.json.</summary>
  TRepoConfig = record
    /// <summary>The repository root: the folder that holds _D-RAG.</summary>
    Root: string;
    /// <summary>&lt;Root&gt;\_D-RAG.</summary>
    Home: string;
    /// <summary>&lt;Home&gt;\config.json.</summary>
    ConfigFile: string;
    /// <summary>The configured projects, in file order.</summary>
    Projects: TArray<TRepoProject>;
    /// <summary>Glob patterns excluded from every project walk.</summary>
    Exclude: TArray<string>;
    /// <summary>True when the file has a "lint" object.</summary>
    HasLint: Boolean;
    /// <summary>True when the file has a "layers" object.</summary>
    HasLayers: Boolean;
    /// <summary>True when the file has a top-level "ownRoots" list.</summary>
    HasOwnRoots: Boolean;
    /// <summary>The top-level "ownRoots", ABSOLUTE: the roots every project
    /// owns unless its own entry declares others.</summary>
    OwnRoots: TArray<string>;
    /// <summary>The raw file text, for the "settings" and "docs" blocks, which
    /// the manifest parser reads as it always has.</summary>
    Text: string;
    /// <summary>The project whose .dproj is AProjectFile (case-insensitive,
    /// full-path compare). A .dpr matches the .dproj beside it.</summary>
    function FindProject(const AProjectFile: string; out AProject: TRepoProject): Boolean;
    /// <summary>The project named AName (case-insensitive).</summary>
    function FindByName(const AName: string; out AProject: TRepoProject): Boolean;
  end;

  /// <summary>Discovery, parsing and writing of config.json.</summary>
  TRepoConfigIO = class
  strict private
    class var FAnchor: string;
  public
    /// <summary>Sets the process-wide discovery anchor (a file or a folder).
    /// '' resets it to the CWD.</summary>
    class procedure SetAnchor(const APath: string); static;
    /// <summary>The anchor in effect: the one set, else the CWD.</summary>
    class function Anchor: string; static;
    /// <summary>The anchor SetAnchor set, or '' when none was.</summary>
    class function ExplicitAnchor: string; static;
    /// <summary>Walks up from AStartPath (a file or a folder) to the drive root
    /// and returns the first &lt;dir&gt;\_D-RAG\config.json, or ''.</summary>
    class function FindConfigFile(const AStartPath: string): string; static;
    /// <summary>Finds and parses the config above AStartPath ('' = the anchor).
    /// False with AError = '' when there is none; False with AError set when one
    /// exists and cannot be read -- a broken config is an error, never a
    /// silent fall-back to another source.</summary>
    class function TryLoad(const AStartPath: string; out AConfig: TRepoConfig; out AError: string): Boolean; static;
    /// <summary>Parses config.json text for the repository at ARoot.</summary>
    class function Parse(const AText, ARoot: string; out AConfig: TRepoConfig; out AError: string): Boolean; static;
    /// <summary>True when APath is a repo config.json (the file inside a _D-RAG
    /// folder), whose "lint" / "layers" objects are the sections to read.</summary>
    class function IsRepoConfigFile(const APath: string): Boolean; static;
    /// <summary>Platform of a .dproj: the first Win32/Win64 &lt;Platform&gt;
    /// element, else 'Win32'.</summary>
    class function PlatformOfDproj(const ADproj: string): string; static;
  end;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.JSON
  , DRagLint.Core.Model   // dl:unit DRagLint.Core.Model accepted -- DRAG_HOME_DIR and REPO_CONFIG_FILE name what this unit looks for
  ;

function SameFile(const A, B: string): Boolean;
begin
  Result:= SameText(ExpandFileName(A), ExpandFileName(B));
end;

{ TRepoConfig }

function TRepoConfig.FindProject(const AProjectFile: string; out AProject: TRepoProject): Boolean;
var
  Want: string;
begin
  AProject:= Default(TRepoProject);
  if AProjectFile = '' then Exit(False);
  Want:= AProjectFile;
  if TPath.IsRelativePath(Want) then Want:= TPath.GetFullPath(Want);
  for var P in Projects do
    if SameFile(P.Dproj, Want) or SameFile(ChangeFileExt(P.Dproj, '.dpr'), Want)
       or SameFile(ChangeFileExt(P.Dproj, '.dproj'), Want) then
    begin
      AProject:= P;
      Exit(True);
    end;
  Result:= False;
end;

function TRepoConfig.FindByName(const AName: string; out AProject: TRepoProject): Boolean;
begin
  AProject:= Default(TRepoProject);
  for var P in Projects do
    if SameText(P.Name, AName) then
    begin
      AProject:= P;
      Exit(True);
    end;
  Result:= False;
end;

{ TRepoConfigIO }

class procedure TRepoConfigIO.SetAnchor(const APath: string);
begin
  FAnchor:= APath;
end;

class function TRepoConfigIO.Anchor: string;
begin
  Result:= FAnchor;
  if Result = '' then Result:= GetCurrentDir;
end;

class function TRepoConfigIO.ExplicitAnchor: string;
begin
  Result:= FAnchor;
end;

class function TRepoConfigIO.FindConfigFile(const AStartPath: string): string;
var
  Dir   : string;
  Parent: string;
  Start : string;
begin
  Result:= '';
  Start:= StringReplace(AStartPath, '/', '\', [rfReplaceAll]);
  if Start = '' then Exit;
  { ExpandFileName, not TPath.GetFullPath: it does not raise on a malformed
    path, which simply names no repository. }
  Start:= ExpandFileName(Start);
  if TDirectory.Exists(Start) then Dir:= ExcludeTrailingPathDelimiter(Start)
  else Dir:= ExcludeTrailingPathDelimiter(ExtractFilePath(Start));
  while Dir <> '' do
  begin
    var Cand: string:= TPath.Combine(TPath.Combine(Dir, DRAG_HOME_DIR), REPO_CONFIG_FILE);
    if TFile.Exists(Cand) then Exit(Cand);
    Parent:= ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
    if (Parent = '') or SameText(Parent, Dir) then Break; { drive root reached }
    Dir:= Parent;
  end;
end;

class function TRepoConfigIO.TryLoad(const AStartPath: string; out AConfig: TRepoConfig; out AError: string): Boolean;
var
  Start: string;
  Cfg  : string;
  Text : string;
begin
  AConfig:= Default(TRepoConfig);
  AError := '';
  Start:= AStartPath;
  if Start = '' then Start:= Anchor;
  Cfg:= FindConfigFile(Start);
  if Cfg = '' then Exit(False);
  try
    Text:= TFile.ReadAllText(Cfg, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      AError:= Format('cannot read %s: %s', [Cfg, E.Message]);
      Exit(False);
    end;
  end;
  { <root>\_D-RAG\config.json -> <root> }
  Result:= Parse(Text, ExtractFilePath(ExcludeTrailingPathDelimiter(ExtractFilePath(Cfg))), AConfig, AError);
  if not Result then AError:= Format('%s: %s', [Cfg, AError]);
end;

{ An "ownRoots" value: an array of folder strings, each made absolute against
  ARoot. Returns '' or the error to report. An EMPTY array parses -- refusing it
  is the reader's call (TOwnRoots), which names the file in its error. }
function ParseOwnRoots(const AVal: TJSONValue; const ARoot: string; out ARoots: TArray<string>): string;
var
  Entry: string;
begin
  ARoots:= nil;
  if not (AVal is TJSONArray) then Exit('"ownRoots" must be an array of folders');
  for var JR in TJSONArray(AVal) do
  begin
    if not (JR is TJSONString) then Exit('every "ownRoots" entry must be a string');
    Entry:= StringReplace(Trim(JR.Value), '/', '\', [rfReplaceAll]);
    if Entry = '' then Continue;
    if TPath.IsRelativePath(Entry) then Entry:= TPath.Combine(ARoot, Entry);
    ARoots:= ARoots + [ExcludeTrailingPathDelimiter(ExpandFileName(Entry))];
  end;
  Result:= '';
end;

{ One "projects" entry, made absolute against AConfig.Root. Returns '' or the
  error to report; a valid entry is appended to AConfig.Projects. }
function ParseProjectEntry(const AEntry: TJSONValue; var AConfig: TRepoConfig): string;
var
  P  : TRepoProject;
  PO : TJSONObject ;
  Dup: TRepoProject;
begin
  if not (AEntry is TJSONObject) then Exit('every "projects" entry must be an object');
  P:= Default(TRepoProject);
  PO:= TJSONObject(AEntry);
  if PO.GetValue('dproj') <> nil then P.Dproj:= Trim(PO.GetValue('dproj').Value);
  if P.Dproj = '' then Exit('a "projects" entry has no "dproj"');
  P.Dproj:= StringReplace(P.Dproj, '/', '\', [rfReplaceAll]);
  if TPath.IsRelativePath(P.Dproj) then P.Dproj:= TPath.Combine(AConfig.Root, P.Dproj);
  P.Dproj:= ExpandFileName(P.Dproj);
  if PO.GetValue('name') <> nil then P.Name:= Trim(PO.GetValue('name').Value);
  if P.Name = '' then P.Name:= TPath.GetFileNameWithoutExtension(P.Dproj);
  if PO.GetValue('platform') <> nil then P.Platform:= Trim(PO.GetValue('platform').Value);
  if PO.GetValue('delphi') <> nil then P.Delphi:= Trim(PO.GetValue('delphi').Value);
  P.Db:= TPath.Combine(AConfig.Home, P.Name + '.sqlite');
  if PO.GetValue('ownRoots') <> nil then
  begin
    Result:= ParseOwnRoots(PO.GetValue('ownRoots'), AConfig.Root, P.OwnRoots);
    if Result <> '' then Exit(Format('project "%s": %s', [P.Name, Result]));
    P.HasOwnRoots:= True;
  end;
  if AConfig.FindByName(P.Name, Dup) then
    Exit(Format('two projects are named "%s" -- names are index file names and must be unique', [P.Name]));
  AConfig.Projects:= AConfig.Projects + [P];
  Result:= '';
end;

{ The checks and fields of a parsed config.json object. Returns '' or the
  error to report. }
function ParseConfigObject(const AObj: TJSONObject; var AConfig: TRepoConfig): string;
var
  V: TJSONValue;
begin
  V:= AObj.GetValue('version');
  if (V is TJSONNumber) and (TJSONNumber(V).AsInt > REPO_CONFIG_VERSION) then
    Exit(Format('"version" %d is newer than this build reads (%d)', [TJSONNumber(V).AsInt, REPO_CONFIG_VERSION]));
  V:= AObj.GetValue('projects');
  if (V <> nil) and not (V is TJSONArray) then Exit('"projects" must be an array');
  Result:= '';
  if V is TJSONArray then
    for var JP in TJSONArray(V) do
    begin
      Result:= ParseProjectEntry(JP, AConfig);
      if Result <> '' then Exit;
    end;
  V:= AObj.GetValue('exclude');
  if V is TJSONArray then
    for var JE in TJSONArray(V) do
      if Trim(JE.Value) <> '' then AConfig.Exclude:= AConfig.Exclude + [Trim(JE.Value)];
  V:= AObj.GetValue('ownRoots');
  if V <> nil then
  begin
    Result:= ParseOwnRoots(V, AConfig.Root, AConfig.OwnRoots);
    if Result <> '' then Exit;
    AConfig.HasOwnRoots:= True;
  end;
  AConfig.HasLint  := AObj.GetValue('lint')   is TJSONObject;
  AConfig.HasLayers:= AObj.GetValue('layers') is TJSONObject;
end;

class function TRepoConfigIO.Parse(const AText, ARoot: string; out AConfig: TRepoConfig; out AError: string): Boolean;
var
  RootVal: TJSONValue;
begin
  AConfig:= Default(TRepoConfig);
  AConfig.Root:= ExcludeTrailingPathDelimiter(ExpandFileName(ARoot));
  AConfig.Home:= TPath.Combine(AConfig.Root, DRAG_HOME_DIR);
  AConfig.ConfigFile:= TPath.Combine(AConfig.Home, REPO_CONFIG_FILE);
  AConfig.Text:= AText;
  RootVal:= TJSONObject.ParseJSONValue(AText);
  try
    if RootVal is TJSONObject then AError:= ParseConfigObject(TJSONObject(RootVal), AConfig)
    else AError:= 'not a JSON object';
  finally
    RootVal.Free;
  end;
  Result:= AError = '';
end;

class function TRepoConfigIO.IsRepoConfigFile(const APath: string): Boolean;
begin
  Result:= DRagLint.Core.Model.IsRepoConfigFile(APath);
end;

class function TRepoConfigIO.PlatformOfDproj(const ADproj: string): string;
var
  Xml: string;
  P1 : Integer;
  P2 : Integer;
begin
  Result:= 'Win32';
  if not SameText(ExtractFileExt(ADproj), '.dproj') or not TFile.Exists(ADproj) then Exit;
  Xml:= TFile.ReadAllText(ADproj);
  { <Platform Condition="'$(Platform)'==''">Win64</Platform> -- the IDE's
    active platform, the same element DetectPlatformFromDproj reads. }
  P1:= Pos('<platform condition=', LowerCase(Xml));
  while P1 > 0 do
  begin
    P1:= Pos('>', Xml, P1);
    if P1 = 0 then Break;
    P2:= Pos('<', Xml, P1 + 1);
    if P2 = 0 then Break;
    var Val: string:= Trim(Copy(Xml, P1 + 1, P2 - P1 - 1));
    if SameText(Val, 'Win32') or SameText(Val, 'Win64') then Exit(Val);
    P1:= Pos('<platform condition=', LowerCase(Xml), P2);
  end;
end;

end.
