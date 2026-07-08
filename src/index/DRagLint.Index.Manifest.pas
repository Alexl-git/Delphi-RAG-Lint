unit DRagLint.Index.Manifest;

/// <summary>Manifest config types: load / merge (global + local) / validate / save
/// for the drag-lint named-database index manifest (.drag-lint.json).</summary>
/// <remarks>
/// Config discovery:
///   1. Global config: &lt;EngineDir&gt;\drag-lint.json (beside the EXE).
///   2. Local override: .drag-lint.json found by walking AStartDir up to the root.
/// Merge rules: local scalars override global ONLY when they are present in the
/// local file; local GlobalExclude is APPENDED to (not replacing) the global list;
/// a local section with the same Name replaces the matching global section; new
/// local sections are appended.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.
/// </remarks>

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , System.Generics.Collections
  ;

type
  /// <summary>Governs how projects are partitioned when building indexes.</summary>
  TProjectsIndexing = (piPerProject, piPerGroup, piSingle);

  /// <summary>Top-level settings block from the drag-lint manifest.</summary>
  TIndexSettings = record
    /// <summary>How project folders map to index DBs.</summary>
    CurrentProjectsIndexing: TProjectsIndexing;
    /// <summary>Default platform token used for {platform} expansion and DB selection.</summary>
    DefaultPlatform: string;
    /// <summary>Maximum DB file size (MB) before the 32-bit engine emits a warning.</summary>
    SizeGuardMB: Integer;
    /// <summary>Path to the drag-lint engine EXE, or 'auto' to locate beside the current EXE.</summary>
    EnginePath: string;
    /// <summary>Maximum parallel index jobs. 0 = auto (min(CpuCount, sectionCount)).</summary>
    MaxJobs: Integer;
    /// <summary>Maximum file size in KB that the indexer will hand to the
    /// tree-sitter parser. Files exceeding this threshold are skipped with a
    /// SKIP warning. 0 is normalised to 2048 (the safe default).
    /// Override via CLI: --max-file-kb N (0 = unlimited).</summary>
    MaxParseFileKB: Integer;
    /// <summary>Returns a record with all fields set to their documented defaults.</summary>
    class function Defaults: TIndexSettings; static;
  end; // record

  /// <summary>Doc-generation settings, parsed from the manifest 'docs' object.</summary>
  TDocSettings = record
    /// <summary>Max distinct return cases enumerated in a generated &lt;returns&gt;
    /// (the "Observed: ..." list). Default 20. 0 or negative disables enumeration
    /// (bare TODO only).</summary>
    MaxReturnCases: Integer;
    /// <summary>Record with all fields at documented defaults (MaxReturnCases=20).</summary>
    class function Defaults: TDocSettings; static;
  end; // record

  /// <summary>Which top-level settings keys were explicitly present in a parsed JSON block.
  /// Used by the merge logic to distinguish "absent" (keep global) from "present but default".</summary>
  TSettingsKeySet = set of ( skCurrentProjectsIndexing, skDefaultPlatform, skSizeGuardMB, skEnginePath, skMaxJobs, skMaxParseFileKB );

  /// <summary>Describes one named index section within the manifest.</summary>
  TIndexSection = record
    /// <summary>Unique human-readable name used to identify and reference this section.</summary>
    Name: string;
    /// <summary>Output SQLite file. May be empty (default: &lt;OutDir&gt;\&lt;Name&gt;.sqlite),
    /// a bare filename, or a template containing '{platform}'.</summary>
    Db: string;
    /// <summary>Data source: '' = include-list (folder tree); 'registry-libraries' = Delphi registry paths.</summary>
    Source: string;
    /// <summary>Platform tokens this section targets. ['*'] means all known platforms.</summary>
    Platforms: TArray<string>;
    /// <summary>Folder paths or .dpr/.dproj files to index. Relative to RootDir.</summary>
    Include: TArray<string>;
    /// <summary>Per-section glob patterns whose matches are excluded from the walk.</summary>
    Exclude: TArray<string>;
    /// <summary>If non-empty, only files matching one of these globs are indexed.</summary>
    IncludeOnly: TArray<string>;
    /// <summary>When True, .gitignore / .hgignore files found during the walk are honoured.</summary>
    UseIgnoreFiles: Boolean;
    /// <summary>Section names (or '*' for all) whose resolved roots are treated as
    /// already-indexed and excluded from this section's walk (deduplication).</summary>
    DedupAgainst: TArray<string>;
    /// <summary>When True and Source='', only MS*.SQL files pass the SQL file gate.</summary>
    /// <remarks>Applies to folder-tree (non-library) sections only; ignored when Source='registry-libraries'.</remarks>
    SqlOnlyMS: Boolean;
  end; // record

  /// <summary>Complete parsed and merged manifest for a drag-lint installation.</summary>
  TIndexManifest = record
    /// <summary>Absolute directory of the resolved config file (used to expand relative paths).</summary>
    RootDir: string;
    /// <summary>Directory where output SQLite DBs are written. Relative to RootDir.</summary>
    OutDir: string;
    /// <summary>Glob patterns applied to every section's walk before section-level excludes.
    /// During merge, local global-excludes are ADDITIVE to global ones (appended after).</summary>
    GlobalExclude: TArray<string>;
    /// <summary>Settings block parsed from the 'settings' key.</summary>
    Settings: TIndexSettings;
    /// <summary>Doc-generation settings parsed from the 'docs' key.</summary>
    Docs: TDocSettings;
    /// <summary>Ordered list of index sections.</summary>
    Sections: TArray<TIndexSection>;
    /// <summary>Returns True and populates ASection if a section named AName exists (case-insensitive).</summary>
    /// <param name="AName">Section name to look up.</param>
    /// <param name="ASection">Receives a copy of the matched section.</param>
    /// <returns>True if found; False otherwise.</returns>
    function FindSection(const AName: string; out ASection: TIndexSection): Boolean;
  end; // record

  /// <summary>Load, parse, validate and save drag-lint index manifests.</summary>
  TManifestIO = class
    public
      /// <summary>Load and merge: reads the global config beside AEngineDir, then
      /// walks AStartDir up to the root looking for .drag-lint.json and merges it
      /// (local scalars override global when present; local GlobalExclude appends to global;
      /// same-name sections replace; new sections append).</summary>
      /// <param name="AEngineDir">Directory containing the drag-lint EXE (global config source).</param>
      /// <param name="AStartDir">Directory to begin the upward local-config search.</param>
      /// <returns>Merged TIndexManifest. RootDir is set to the local config dir if found,
      /// else to AEngineDir.</returns>
      class function Load(const AEngineDir, AStartDir: string): TIndexManifest; static;

      /// <summary>Parse a manifest from JSON text and set RootDir to ARootDir.</summary>
      /// <param name="AJson">Raw JSON string (UTF-8 or ASCII).</param>
      /// <param name="ARootDir">Absolute directory associated with this JSON (used for relative paths).</param>
      /// <returns>Populated TIndexManifest.</returns>
      class function ParseText(const AJson, ARootDir: string): TIndexManifest; static;

      /// <summary>Parse a manifest from JSON text, also returning which top-level settings
      /// keys were explicitly present in the JSON. Used by the merge logic.</summary>
      /// <param name="AJson">Raw JSON string (UTF-8 or ASCII).</param>
      /// <param name="ARootDir">Absolute directory associated with this JSON (used for relative paths).</param>
      /// <param name="ASettingsKeys">Receives the set of settings keys that were present.</param>
      /// <returns>Populated TIndexManifest.</returns>
      class function ParseTextEx(const AJson, ARootDir: string; out ASettingsKeys: TSettingsKeySet): TIndexManifest; static;

      /// <summary>Serialise AManifest to a JSON object. Caller owns the returned object and
      /// must free it. Platforms ['*'] is emitted as the bare string "all";
      /// DedupAgainst ['*'] is emitted as the bare string "*".</summary>
      /// <param name="AManifest">Manifest to serialise.</param>
      /// <returns>New TJSONObject; caller must free.</returns>
      class function ToJson(const AManifest: TIndexManifest): TJSONObject; static;

      /// <summary>Serialise AManifest to a .drag-lint.json file at APath.</summary>
      /// <param name="AManifest">Manifest to write.</param>
      /// <param name="APath">Destination file path.</param>
      class procedure Save(const AManifest: TIndexManifest; const APath: string); static;

      /// <summary>Validate the manifest and return the first human-readable error,
      /// or '' if the manifest is valid.</summary>
      /// <param name="AManifest">Manifest to validate.</param>
      /// <returns>Empty string if valid; first error message otherwise.</returns>
      class function Validate(const AManifest: TIndexManifest): string; static;
  end;

implementation

{ ---------------------------------------------------------------------- }
{  Helpers                                                                 }
{ ---------------------------------------------------------------------- }

function JsonStrArr(const AArr: TJSONArray): TArray<string>;
var
  I: Integer;
begin
  if AArr = nil then
  begin
    Result:= nil;
    Exit;
  end;
  SetLength(Result, AArr.Count);
  for I:= 0 to AArr.Count - 1 do Result[I]:= AArr.Items[I].Value;
end;

{ Accept either a bare string or an array of strings.
  The string "all" or "*" maps to ['*']. }
function ParseStringOrArray(const AVal: TJSONValue): TArray<string>;
var
  S: string;
begin
  Result:= nil;
  if AVal = nil then Exit;
  if AVal is TJSONArray then
  begin
    Result:= JsonStrArr(TJSONArray(AVal));
    Exit;
  end;
  S:= AVal.Value;
  if (S = 'all') or (S = '*') then Result:= ['*']
  else Result:= [S];
end;

function ParseProjectsIndexing(const S: string): TProjectsIndexing;
begin
  if SameText(S, 'perGroup') then Result:= piPerGroup
  else if SameText(S, 'single') then Result:= piSingle
  else Result:= piPerProject;
end;

function ProjectsIndexingToStr(const V: TProjectsIndexing): string;
begin
  case V of
    piPerGroup: Result:= 'perGroup';
    piSingle  : Result:= 'single';
    else Result:= 'perProject';
  end;
end;

function ParseSection(const AObj: TJSONObject): TIndexSection;
var
  V: TJSONValue;
  B: TJSONBool ;
begin
  Result:= Default(TIndexSection);
  Result.UseIgnoreFiles:= True;
  Result.SqlOnlyMS     := True;

  V:= AObj.GetValue('name');
  if V <> nil then Result.Name:= V.Value;

  V:= AObj.GetValue('db');
  if V <> nil then Result.Db:= V.Value;

  V:= AObj.GetValue('source');
  if V <> nil then Result.Source:= V.Value;

  V:= AObj.GetValue('platforms');
  if V <> nil then Result.Platforms:= ParseStringOrArray(V);

  V:= AObj.GetValue('include');
  if V is TJSONArray then Result.Include:= JsonStrArr(TJSONArray(V))
  else if (V <> nil) then Result.Include:= [V.Value];

  V:= AObj.GetValue('exclude');
  if V is TJSONArray then Result.Exclude:= JsonStrArr(TJSONArray(V))
  else if (V <> nil) then Result.Exclude:= [V.Value];

  V:= AObj.GetValue('includeOnly');
  if V is TJSONArray then Result.IncludeOnly:= JsonStrArr(TJSONArray(V))
  else if (V <> nil) then Result.IncludeOnly:= [V.Value];

  { useIgnoreFiles: accept also legacy 'useGitignore' key (back-compat) }
  B:= AObj.GetValue('useIgnoreFiles') as TJSONBool;
  if B <> nil then Result.UseIgnoreFiles:= B.AsBoolean
  else
  begin
    B:= AObj.GetValue('useGitignore') as TJSONBool;
    if B <> nil then Result.UseIgnoreFiles:= B.AsBoolean;
  end;

  V:= AObj.GetValue('dedupAgainst');
  if V <> nil then Result.DedupAgainst:= ParseStringOrArray(V);

  B:= AObj.GetValue('sqlOnlyMS') as TJSONBool;
  if B <> nil then Result.SqlOnlyMS:= B.AsBoolean;
end; // function

{ ---------------------------------------------------------------------- }
{  TIndexSettings                                                          }
{ ---------------------------------------------------------------------- }

class function TIndexSettings.Defaults: TIndexSettings;
begin
  Result:= Default(TIndexSettings);
  Result.CurrentProjectsIndexing:= piPerProject;
  Result.DefaultPlatform        := 'Win32';
  Result.SizeGuardMB            := 1500;
  Result.EnginePath             := 'auto';
  Result.MaxJobs                := 0;
  Result.MaxParseFileKB         := 2048;
end;

{ ---------------------------------------------------------------------- }
{  TDocSettings                                                            }
{ ---------------------------------------------------------------------- }

class function TDocSettings.Defaults: TDocSettings;
begin
  Result:= Default(TDocSettings);
  Result.MaxReturnCases:= 20;
end;

{ ---------------------------------------------------------------------- }
{  TIndexManifest                                                          }
{ ---------------------------------------------------------------------- }

function TIndexManifest.FindSection(const AName: string; out ASection: TIndexSection): Boolean;
var
  I: Integer;
begin
  for I:= 0 to High(Sections) do
    if SameText(Sections[I].Name, AName) then
    begin
      ASection:= Sections[I];
      Exit(True);
    end;
  Result:= False;
  ASection:= Default(TIndexSection);
end;

{ ---------------------------------------------------------------------- }
{  TManifestIO.ParseTextEx                                                 }
{ ---------------------------------------------------------------------- }

class function TManifestIO.ParseTextEx(const AJson, ARootDir: string; out ASettingsKeys: TSettingsKeySet): TIndexManifest;
var
  Root     : TJSONObject;
  JSettings: TJSONObject;
  JIndexes : TJSONObject;
  JSections: TJSONArray ;
  V        : TJSONValue ;
  N        : TJSONNumber;
  I        : Integer    ;
begin
  Result:= Default(TIndexManifest);
  Result.RootDir:= ARootDir;
  Result.Settings:= TIndexSettings.Defaults;
  Result.Docs:= TDocSettings.Defaults;
  ASettingsKeys:= [];

  Root:= TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if Root = nil then Exit;
  try
    { -- settings block -- }
    JSettings:= Root.GetValue('settings') as TJSONObject;
    if JSettings <> nil then
    begin
      V:= JSettings.GetValue('currentProjectsIndexing');
      if (V <> nil) and (V.Value <> '') then
      begin
        Result.Settings.CurrentProjectsIndexing:= ParseProjectsIndexing(V.Value);
        Include(ASettingsKeys, skCurrentProjectsIndexing);
      end;

      V:= JSettings.GetValue('defaultPlatform');
      if (V <> nil) and (V.Value <> '') then
      begin
        Result.Settings.DefaultPlatform:= V.Value;
        Include(ASettingsKeys, skDefaultPlatform);
      end;

      N:= JSettings.GetValue('sizeGuardMB') as TJSONNumber;
      if N <> nil then
      begin
        Result.Settings.SizeGuardMB:= N.AsInt;
        Include(ASettingsKeys, skSizeGuardMB);
      end;

      V:= JSettings.GetValue('enginePath');
      if (V <> nil) and (V.Value <> '') then
      begin
        Result.Settings.EnginePath:= V.Value;
        Include(ASettingsKeys, skEnginePath);
      end;

      N:= JSettings.GetValue('maxJobs') as TJSONNumber;
      if N <> nil then
      begin
        Result.Settings.MaxJobs:= N.AsInt;
        Include(ASettingsKeys, skMaxJobs);
      end;

      N:= JSettings.GetValue('maxParseFileKB') as TJSONNumber;
      if N <> nil then
      begin
        { 0 in JSON means "use default 2048"; a negative value disables the
          guard (unlimited). CLI --max-file-kb 0 overrides to unlimited after
          this is applied. }
        var KB:= N.AsInt;
        if KB = 0 then KB:= 2048;
        Result.Settings.MaxParseFileKB:= KB;
        Include(ASettingsKeys, skMaxParseFileKB);
      end;
    end; // if

    { -- docs block -- }
    var JDocs: TJSONObject:= Root.GetValue('docs') as TJSONObject;
    if JDocs <> nil then
    begin
      var ND: TJSONNumber:= JDocs.GetValue('max_return_cases') as TJSONNumber;
      if ND <> nil then Result.Docs.MaxReturnCases:= ND.AsInt;
    end;

    { -- indexes block -- }
    JIndexes:= Root.GetValue('indexes') as TJSONObject;
    if JIndexes <> nil then
    begin
      V:= JIndexes.GetValue('outDir');
      if (V <> nil) and (V.Value <> '') then Result.OutDir:= V.Value;

      V:= JIndexes.GetValue('exclude');
      if V is TJSONArray then Result.GlobalExclude:= JsonStrArr(TJSONArray(V));

      JSections:= JIndexes.GetValue('sections') as TJSONArray;
      if JSections <> nil then
      begin
        SetLength(Result.Sections, JSections.Count);
        for I:= 0 to JSections.Count - 1 do
          if JSections.Items[I] is TJSONObject then Result.Sections[I]:= ParseSection(TJSONObject(JSections.Items[I]));
      end;
    end; // if
  finally
    Root.Free;
  end; // try
end; // function

{ ---------------------------------------------------------------------- }
{  TManifestIO.ParseText                                                   }
{ ---------------------------------------------------------------------- }

class function TManifestIO.ParseText(const AJson, ARootDir: string): TIndexManifest;
var
  Keys: TSettingsKeySet;
begin
  Result:= ParseTextEx(AJson, ARootDir, Keys);
end;

{ ---------------------------------------------------------------------- }
{  TManifestIO.Load                                                        }
{ ---------------------------------------------------------------------- }

class function TManifestIO.Load(const AEngineDir, AStartDir: string): TIndexManifest;
var
  GlobalPath    : string         ;
  LocalPath     : string         ;
  GlobalManifest: TIndexManifest ;
  LocalManifest : TIndexManifest ;
  LocalKeys     : TSettingsKeySet;
  Content       : string         ;
  HaveGlobal    : Boolean        ;
  HaveLocal     : Boolean        ;
  Dir           : string         ;
  Parent        : string         ;

  procedure MergeSections(var ADest: TIndexManifest; const ASrc: TIndexManifest);
  var
    K       : Integer;
    L       : Integer;
    MatchIdx: Integer;
  begin
    for K:= 0 to High(ASrc.Sections) do
    begin
      MatchIdx:= -1;
      for L:= 0 to High(ADest.Sections) do
        if SameText(ADest.Sections[L].Name, ASrc.Sections[K].Name) then
        begin
          MatchIdx:= L;
          Break;
        end;
      if MatchIdx >= 0 then ADest.Sections[MatchIdx]:= ASrc.Sections[K]
      else
      begin
        SetLength(ADest.Sections, Length(ADest.Sections) + 1);
        ADest.Sections[High(ADest.Sections)]:= ASrc.Sections[K];
      end;
    end; // for
  end; // procedure

begin
  Result:= Default(TIndexManifest);
  HaveGlobal:= False;
  HaveLocal := False;
  LocalKeys:= [];

  { Try global: <AEngineDir>\drag-lint.json (no leading dot -- the EXE-side config) }
  GlobalPath:= TPath.Combine(AEngineDir, 'drag-lint.json');
  if TFile.Exists(GlobalPath) then
  begin
    try
      Content:= TFile.ReadAllText(GlobalPath);
      GlobalManifest:= ParseText(Content, AEngineDir);
      HaveGlobal:= True;
    except
      on E: Exception do Writeln(ErrOutput, 'WARNING: could not parse config at ', GlobalPath, ': ', E.Message);
    end;
  end;

  { Try local: walk AStartDir .. root for .drag-lint.json }
  LocalPath:= '';
  Dir:= TPath.GetFullPath(AStartDir);
  while Dir <> '' do
  begin
    var Candidate:= TPath.Combine(Dir, '.drag-lint.json');
    if TFile.Exists(Candidate) then
    begin
      LocalPath:= Candidate;
      Break;
    end;
    Parent:= TPath.GetDirectoryName(Dir);
    if (Parent = '') or (Parent = Dir) then Break;
    Dir:= Parent;
  end;

  if LocalPath <> '' then
  begin
    try
      Content:= TFile.ReadAllText(LocalPath);
      LocalManifest:= ParseTextEx(Content, TPath.GetDirectoryName(LocalPath), LocalKeys);
      HaveLocal:= True;
    except
      on E: Exception do Writeln(ErrOutput, 'WARNING: could not parse config at ', LocalPath, ': ', E.Message);
    end;
  end;

  if HaveGlobal and HaveLocal then
  begin
    { Merge: start from global, override with local scalars only when present,
      append local GlobalExclude (additive), then sections }
    Result:= GlobalManifest;
    if LocalManifest.OutDir <> '' then Result.OutDir:= LocalManifest.OutDir;
    { GlobalExclude: APPEND local to global (additive -- local excludes do not
      replace global ones; both apply after merge) }
    if Length(LocalManifest.GlobalExclude) > 0 then
    begin
      var OldLen:= Length(Result.GlobalExclude);
      SetLength(Result.GlobalExclude, OldLen + Length(LocalManifest.GlobalExclude));
      for var K:= 0 to High(LocalManifest.GlobalExclude) do Result.GlobalExclude[OldLen + K]:= LocalManifest.GlobalExclude[K];
    end;
    { Settings: local scalars override ONLY when the key was present in the local file }
    if skDefaultPlatform         in LocalKeys then Result.Settings.DefaultPlatform        := LocalManifest.Settings.DefaultPlatform;
    if skEnginePath              in LocalKeys then Result.Settings.EnginePath             := LocalManifest.Settings.EnginePath;
    if skSizeGuardMB             in LocalKeys then Result.Settings.SizeGuardMB            := LocalManifest.Settings.SizeGuardMB;
    if skMaxJobs                 in LocalKeys then Result.Settings.MaxJobs                := LocalManifest.Settings.MaxJobs;
    if skCurrentProjectsIndexing in LocalKeys then Result.Settings.CurrentProjectsIndexing:= LocalManifest.Settings.CurrentProjectsIndexing;
    if skMaxParseFileKB          in LocalKeys then Result.Settings.MaxParseFileKB         := LocalManifest.Settings.MaxParseFileKB;
    Result.RootDir:= LocalManifest.RootDir;
    MergeSections(Result, LocalManifest);
  end // if
  else if HaveLocal  then Result:= LocalManifest
  else if HaveGlobal then Result:= GlobalManifest
  else
  begin
    { Neither found: return defaults. Docs must be defaulted explicitly here too
      (Task 10 bugfix) -- Result started as Default(TIndexManifest) above, which
      zero-fills Docs.MaxReturnCases to 0 (enumeration disabled); every OTHER
      branch (HaveLocal, HaveGlobal, both) gets Docs from a ParseText/ParseTextEx
      call that already sets Result.Docs:= TDocSettings.Defaults, so only this
      neither-found fallback was missing it. }
    Result.Settings:= TIndexSettings.Defaults;
    Result.Docs:= TDocSettings.Defaults;
    Result.RootDir:= AStartDir;
  end;
end; // begin

{ ---------------------------------------------------------------------- }
{  TManifestIO.Validate                                                    }
{ ---------------------------------------------------------------------- }

class function TManifestIO.Validate(const AManifest: TIndexManifest): string;
var
  Names: TStringList  ;
  I    : Integer      ;
  Sec  : TIndexSection;
  DA   : string       ;
  Found: Boolean      ;
  DSec : TIndexSection;
begin
  Result:= '';
  if AManifest.Docs.MaxReturnCases < 0 then Exit('docs.max_return_cases must be >= 0');
  Names:= TStringList.Create;
  Names.CaseSensitive:= False;
  try
    { Each section must have a non-empty unique name }
    for I:= 0 to High(AManifest.Sections) do
    begin
      Sec:= AManifest.Sections[I];
      if Sec.Name = '' then
      begin
        Result:= Format('Section %d has an empty name', [I]);
        Exit;
      end;
      if Names.IndexOf(Sec.Name) >= 0 then
      begin
        Result:= Format('Duplicate section name: "%s"', [Sec.Name]);
        Exit;
      end;
      Names.Add(Sec.Name);
    end;

    { Each section must have either Include paths or Source='registry-libraries' }
    for I:= 0 to High(AManifest.Sections) do
    begin
      Sec:= AManifest.Sections[I];
      if (Sec.Source <> 'registry-libraries') and (Length(Sec.Include) = 0) then
      begin
        Result:= Format('Section "%s" has no include paths and source is not registry-libraries', [Sec.Name]);
        Exit;
      end;
    end;

    { Every dedupAgainst name (other than '*') must resolve to a known section }
    for I:= 0 to High(AManifest.Sections) do
    begin
      Sec:= AManifest.Sections[I];
      for DA in Sec.DedupAgainst do
      begin
        if DA = '*' then Continue;
        Found:= AManifest.FindSection(DA, DSec);
        if not Found then
        begin
          Result:= Format('Section "%s" dedupAgainst references unknown section "%s"', [Sec.Name, DA]);
          Exit;
        end;
      end;
    end;
  finally
    Names.Free;
  end; // try
end; // function

{ ---------------------------------------------------------------------- }
{  TManifestIO.ToJson                                                      }
{ ---------------------------------------------------------------------- }

class function TManifestIO.ToJson(const AManifest: TIndexManifest): TJSONObject;
var
  JSettings  : TJSONObject  ;
  JIndexes   : TJSONObject  ;
  JSections  : TJSONArray   ;
  JExclude   : TJSONArray   ;
  JInclude   : TJSONArray   ;
  JSecExclude: TJSONArray   ;
  JIncOnly   : TJSONArray   ;
  JPlats     : TJSONArray   ;
  JDedup     : TJSONArray   ;
  Sec        : TIndexSection;
  S          : string       ;
begin
  Result:= TJSONObject.Create;

  { settings }
  JSettings:= TJSONObject.Create;
  Result.AddPair('settings', JSettings);
  JSettings.AddPair('currentProjectsIndexing', ProjectsIndexingToStr(AManifest.Settings.CurrentProjectsIndexing));
  JSettings.AddPair('defaultPlatform', AManifest.Settings.DefaultPlatform);
  JSettings.AddPair('sizeGuardMB', TJSONNumber.Create(AManifest.Settings.SizeGuardMB));
  JSettings.AddPair('enginePath', AManifest.Settings.EnginePath);
  JSettings.AddPair('maxJobs'       , TJSONNumber.Create(AManifest.Settings.MaxJobs       ));
  JSettings.AddPair('maxParseFileKB', TJSONNumber.Create(AManifest.Settings.MaxParseFileKB));

  { docs }
  var JDocs:= TJSONObject.Create;
  Result.AddPair('docs', JDocs);
  JDocs.AddPair('max_return_cases', TJSONNumber.Create(AManifest.Docs.MaxReturnCases));

  { indexes }
  JIndexes:= TJSONObject.Create;
  Result.AddPair('indexes', JIndexes);
  JIndexes.AddPair('outDir', AManifest.OutDir);

  JExclude:= TJSONArray.Create;
  JIndexes.AddPair('exclude', JExclude);
  for S in AManifest.GlobalExclude do JExclude.AddElement(TJSONString.Create(S));

  JSections:= TJSONArray.Create;
  JIndexes.AddPair('sections', JSections);
  for Sec in AManifest.Sections do
  begin
    var JSecObj:= TJSONObject.Create;
    JSections.AddElement(JSecObj);
    JSecObj.AddPair('name', Sec.Name);
    if Sec.Db     <> '' then JSecObj.AddPair('db'    , Sec.Db    );
    if Sec.Source <> '' then JSecObj.AddPair('source', Sec.Source);

    if Length(Sec.Platforms) > 0 then
    begin
      if (Length(Sec.Platforms) = 1) and (Sec.Platforms[0] = '*') then JSecObj.AddPair('platforms', 'all')
      else
      begin
        JPlats:= TJSONArray.Create;
        JSecObj.AddPair('platforms', JPlats);
        for S in Sec.Platforms do JPlats.AddElement(TJSONString.Create(S));
      end;
    end;

    if Length(Sec.Include) > 0 then
    begin
      JInclude:= TJSONArray.Create;
      JSecObj.AddPair('include', JInclude);
      for S in Sec.Include do JInclude.AddElement(TJSONString.Create(S));
    end;

    if Length(Sec.Exclude) > 0 then
    begin
      JSecExclude:= TJSONArray.Create;
      JSecObj.AddPair('exclude', JSecExclude);
      for S in Sec.Exclude do JSecExclude.AddElement(TJSONString.Create(S));
    end;

    if Length(Sec.IncludeOnly) > 0 then
    begin
      JIncOnly:= TJSONArray.Create;
      JSecObj.AddPair('includeOnly', JIncOnly);
      for S in Sec.IncludeOnly do JIncOnly.AddElement(TJSONString.Create(S));
    end;

    JSecObj.AddPair('useIgnoreFiles', TJSONBool.Create(Sec.UseIgnoreFiles));

    if Length(Sec.DedupAgainst) > 0 then
    begin
      if (Length(Sec.DedupAgainst) = 1) and (Sec.DedupAgainst[0] = '*') then JSecObj.AddPair('dedupAgainst', '*')
      else
      begin
        JDedup:= TJSONArray.Create;
        JSecObj.AddPair('dedupAgainst', JDedup);
        for S in Sec.DedupAgainst do JDedup.AddElement(TJSONString.Create(S));
      end;
    end;

    JSecObj.AddPair('sqlOnlyMS', TJSONBool.Create(Sec.SqlOnlyMS));
  end; // for
end; // function

{ ---------------------------------------------------------------------- }
{  TManifestIO.Save                                                        }
{ ---------------------------------------------------------------------- }

class procedure TManifestIO.Save(const AManifest: TIndexManifest; const APath: string);
var
  Root    : TJSONObject;
  JsonText: string     ;
begin
  Root:= ToJson(AManifest);
  try
    JsonText:= Root.Format(2);
  finally
    Root.Free;
  end;
  TFile.WriteAllText(APath, JsonText, TEncoding.UTF8);
end;

end.
