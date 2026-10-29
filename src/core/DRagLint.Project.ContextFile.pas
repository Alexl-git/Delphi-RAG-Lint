unit DRagLint.Project.ContextFile;

// The project-context file: <ProjectBase>.dlcontext.json beside a .dproj / .dpr. It carries the
// active platform, config and the complete effective define set so a consumer (the LSP, the
// setup exe) need not guess them. Also the central defaults file
// %LOCALAPPDATA%\drag-lint\context-defaults.json (read only here; the plugin writes it).
// Schema 1; UTF-8 without BOM. Comments use // exclusively.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Core.ContextDefaults;

const
  /// <summary>The schema number this unit reads and writes.</summary>
  CONTEXT_SCHEMA = 1;
  /// <summary>File suffix appended to the project base name.</summary>
  CONTEXT_FILE_SUFFIX = '.dlcontext.json';
  /// <summary>Environment variable that overrides the central defaults file path (tests).</summary>
  CONTEXT_DEFAULTS_ENV = CORE_CONTEXT_DEFAULTS_ENV;

type
  /// <summary>One project context as stored in a .dlcontext.json file.</summary>
  /// <remarks>Plain value record. Defines are lowercased and deduped exactly as
  /// ResolveActiveBuild(...).Profile.Defines yields them.</remarks>
  TProjectContext = record
    Schema: Integer;
    Project, PlatformName, Config: string;
    Defines, SearchPath, Namespaces, LibraryRoots: TArray<string>;
    UnitAliases: TArray<TPair<string, string>>;
    LibraryDb, ProjectDb, SourceFile, SourceSha1: string;
    /// <summary>Optional compiler version ('37'); '' = default. Carried only, never evaluated here.</summary>
    TargetCompiler: string;
    /// <summary>Who wrote the file ('drag-lint project-context ...'); informational.</summary>
    GeneratedBy: string;
    /// <summary>Filled by Load: the .dproj named by SourceFile changed since the file was written.</summary>
    Stale: Boolean;
  end;

  /// <summary>Per-platform library override from the central defaults file.</summary>
  TLibraryDefault = record
    PlatformName, LibraryDb: string;
    LibraryRoots: TArray<string>;
  end;

  /// <summary>The central per-user defaults (context-defaults.json).</summary>
  TContextDefaults = record
    Schema: Integer;
    PlatformName, Config, TargetCompiler: string;
    Libraries: TArray<TLibraryDefault>;
  end;

/// <summary>The per-user settings folder %LOCALAPPDATA%\drag-lint (no trailing separator).</summary>
/// <returns>The folder path; '' when LOCALAPPDATA is not set. Does not create it.</returns>
/// <remarks>Shared helper: ENGINE code may call it instead of inlining the lookup. Forwards to
/// DRagLint.Core.ContextDefaults.DragLintLocalDataDir (the one definition, linkable by the plugin).</remarks>
function DragLintLocalDataDir: string;

/// <summary>Path of the central defaults file.</summary>
/// <returns>The env DRAGLINT_CONTEXT_DEFAULTS when set (explicit override, for tests),
/// else DragLintLocalDataDir\context-defaults.json; '' when neither resolves.</returns>
function ContextDefaultsFile: string;

/// <summary>Reads the central defaults file; %VAR% references in library paths are expanded.</summary>
/// <param name="ADefaults">Receives the defaults; empty when False.</param>
/// <returns>True when the file exists and parses. An absent or malformed file is False, never an error.</returns>
function TryLoadContextDefaults(out ADefaults: TContextDefaults): Boolean;

/// <summary>The context file that belongs to a project file.</summary>
/// <param name="AProjectFile">Path of the .dproj or .dpr.</param>
/// <returns>The same folder and base name with the .dlcontext.json suffix.</returns>
function ContextFileFor(const AProjectFile: string): string;

/// <summary>Loads a context file and fills Stale.</summary>
/// <param name="AFile">Path of the .dlcontext.json.</param>
/// <param name="ACtx">Receives the context.</param>
/// <returns>True when the file exists, parses and has schema 1. Never raises.</returns>
/// <remarks>Stale = SourceFile is a .dproj that exists and its SHA-1 differs from SourceSha1.
/// A .dpr source is never stale; a missing source is not stale.</remarks>
function TryLoadProjectContext(const AFile: string; out ACtx: TProjectContext): Boolean;

/// <summary>Nearest-wins lookup for a unit.</summary>
/// <param name="AUnitPath">Path of a source file.</param>
/// <param name="ACtx">Receives the context of the first loadable *.dlcontext.json found
/// walking up from the unit's folder.</param>
/// <returns>True when one was found and loaded.</returns>
function FindProjectContextForUnit(const AUnitPath: string; out ACtx: TProjectContext): Boolean;

/// <summary>Builds a context from a project file.</summary>
/// <param name="ADproj">A .dproj (defines via ResolveActiveBuild), or a .dpr / '' (platform built-ins).</param>
/// <param name="APlatform">Override; '' = the .dproj's active platform.</param>
/// <param name="AConfig">Override; '' = the .dproj's active config.</param>
/// <returns>The context with SourceSha1 of the project file, Stale False.</returns>
/// <remarks>ResolveActiveBuild knows only Win32 and Win64 define sets; any other platform name is
/// kept in Platform but its defines are the Win64 built-ins (a known limit).</remarks>
function BuildProjectContext(const ADproj, APlatform, AConfig: string): TProjectContext;

/// <summary>Writes a context atomically (pretty-printed, UTF-8 without BOM).</summary>
/// <param name="ACtx">The context.</param>
/// <param name="AFile">Destination path.</param>
/// <exception cref="Exception">I/O errors propagate.</exception>
procedure SaveProjectContext(const ACtx: TProjectContext; const AFile: string);

/// <summary>SHA-1 of a file as 40 lowercase hex.</summary>
/// <param name="AFile">Path.</param>
/// <returns>The hash, '' when the file is unreadable.</returns>
function FileSha1Hex(const AFile: string): string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Hash,
  System.DateUtils,
  System.JSON,
  DRagLint.Core.JsonFile,
  DRagLint.Project.DefineProfile;

function DragLintLocalDataDir: string;
begin
  Result := DRagLint.Core.ContextDefaults.DragLintLocalDataDir;
end;

function ContextDefaultsFile: string;
begin
  Result := DRagLint.Core.ContextDefaults.ContextDefaultsFile;
end;

function ExpandEnvVars(const AText: string): string;
var
  P, Q: Integer;
  VarName, VarValue: string;
begin
  Result := AText;
  P := Pos('%', Result);
  while P > 0 do
  begin
    Q := Pos('%', Result, P + 1);
    if Q = 0 then Break;
    VarName := Copy(Result, P + 1, Q - P - 1);
    VarValue := GetEnvironmentVariable(VarName);
    if VarValue <> '' then
    begin
      Result := Copy(Result, 1, P - 1) + VarValue + Copy(Result, Q + 1, MaxInt);
      P := Pos('%', Result, P + Length(VarValue));
    end
    else
      P := Pos('%', Result, Q + 1);
  end;
end;

function GetStr(AObj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if (V <> nil) and (V is TJSONString) then Result := V.Value else Result := '';
end;

function GetStrArray(AObj: TJSONObject; const AName: string; AExpand: Boolean): TArray<string>;
var
  V: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := nil;
  V := AObj.GetValue(AName);
  if not (V is TJSONArray) then Exit;
  Arr := TJSONArray(V);
  SetLength(Result, Arr.Count);
  for I := 0 to Arr.Count - 1 do
  begin
    Result[I] := Arr.Items[I].Value;
    if AExpand then Result[I] := ExpandEnvVars(Result[I]);
  end;
end;

function ParseObject(const AFile: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  if (AFile = '') or not TFile.Exists(AFile) then Exit;
  V := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFile, TEncoding.UTF8));
  if V is TJSONObject then Result := TJSONObject(V) else V.Free;
end;

function SafeParseObject(const AFile: string): TJSONObject;
begin
  try
    Result := ParseObject(AFile);
  except // dl:ok bare-except@8ac3 -- REVIEWED 2026-10-28 fail-open by contract: an unreadable or malformed file is "absent"
    Result := nil;
  end;
end;

function TryLoadContextDefaults(out ADefaults: TContextDefaults): Boolean;
var
  Obj, Libs, L: TJSONObject;
  I: Integer;
  Item: TLibraryDefault;
  Acc: TList<TLibraryDefault>;
begin
  ADefaults := Default(TContextDefaults);
  Result := False;
  Obj := SafeParseObject(ContextDefaultsFile);
  if Obj = nil then Exit;
  try
    Obj.TryGetValue<Integer>('schema', ADefaults.Schema);
    ADefaults.PlatformName := GetStr(Obj, 'platform');
    ADefaults.Config := GetStr(Obj, 'config');
    ADefaults.TargetCompiler := GetStr(Obj, 'targetCompiler');
    if Obj.GetValue('libraries') is TJSONObject then
    begin
      Libs := TJSONObject(Obj.GetValue('libraries'));
      Acc := TList<TLibraryDefault>.Create;
      try
        for I := 0 to Libs.Count - 1 do
          if Libs.Pairs[I].JsonValue is TJSONObject then
          begin
            L := TJSONObject(Libs.Pairs[I].JsonValue);
            Item := Default(TLibraryDefault);
            Item.PlatformName := Libs.Pairs[I].JsonString.Value;
            Item.LibraryDb := ExpandEnvVars(GetStr(L, 'libraryDb'));
            Item.LibraryRoots := GetStrArray(L, 'libraryRoots', True);
            Acc.Add(Item);
          end;
        ADefaults.Libraries := Acc.ToArray;
      finally
        Acc.Free;
      end;
    end;
    Result := True;
  finally
    Obj.Free;
  end;
end;

function ContextFileFor(const AProjectFile: string): string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(AProjectFile),
    TPath.GetFileNameWithoutExtension(AProjectFile) + CONTEXT_FILE_SUFFIX);
end;

function FileSha1Hex(const AFile: string): string;
begin
  try
    Result := LowerCase(THashSHA1.GetHashStringFromFile(AFile));
  except // dl:ok bare-except@86a2 -- REVIEWED 2026-10-28 fail-open by contract: an unreadable file has no hash
    Result := '';
  end;
end;

function TryLoadProjectContext(const AFile: string; out ACtx: TProjectContext): Boolean;
var
  Obj, Src, Al: TJSONObject;
  I: Integer;
  Pairs: TList<TPair<string, string>>;
begin
  ACtx := Default(TProjectContext);
  Result := False;
  Obj := SafeParseObject(AFile);
  if Obj = nil then Exit;
  try
    Obj.TryGetValue<Integer>('schema', ACtx.Schema);
    if ACtx.Schema <> CONTEXT_SCHEMA then Exit;
    ACtx.GeneratedBy := GetStr(Obj, 'generatedBy');
    ACtx.Project := GetStr(Obj, 'project');
    ACtx.PlatformName := GetStr(Obj, 'platform');
    ACtx.Config := GetStr(Obj, 'config');
    ACtx.TargetCompiler := GetStr(Obj, 'targetCompiler');
    ACtx.Defines := GetStrArray(Obj, 'defines', False);
    ACtx.SearchPath := GetStrArray(Obj, 'searchPath', False);
    ACtx.Namespaces := GetStrArray(Obj, 'namespaces', False);
    ACtx.LibraryRoots := GetStrArray(Obj, 'libraryRoots', False);
    ACtx.LibraryDb := GetStr(Obj, 'libraryDb');
    ACtx.ProjectDb := GetStr(Obj, 'projectDb');
    if Obj.GetValue('source') is TJSONObject then
    begin
      Src := TJSONObject(Obj.GetValue('source'));
      ACtx.SourceFile := GetStr(Src, 'file');
      ACtx.SourceSha1 := GetStr(Src, 'sha1');
    end;
    if Obj.GetValue('unitAliases') is TJSONObject then
    begin
      Al := TJSONObject(Obj.GetValue('unitAliases'));
      Pairs := TList<TPair<string, string>>.Create;
      try
        for I := 0 to Al.Count - 1 do
          Pairs.Add(TPair<string, string>.Create(Al.Pairs[I].JsonString.Value, Al.Pairs[I].JsonValue.Value));
        ACtx.UnitAliases := Pairs.ToArray;
      finally
        Pairs.Free;
      end;
    end;
    ACtx.Stale := SameText(ExtractFileExt(ACtx.SourceFile), '.dproj') and TFile.Exists(ACtx.SourceFile)
      and (ACtx.SourceSha1 <> '') and not SameText(FileSha1Hex(ACtx.SourceFile), ACtx.SourceSha1);
    Result := True;
  finally
    Obj.Free;
  end;
end;

function FindProjectContextForUnit(const AUnitPath: string; out ACtx: TProjectContext): Boolean;
var
  Dir, Parent, F: string;
  Files: TArray<string>;
begin
  ACtx := Default(TProjectContext);
  Result := False;
  if AUnitPath = '' then Exit;
  Dir := ExtractFilePath(ExpandFileName(AUnitPath));
  while Dir <> '' do
  begin
    Dir := ExcludeTrailingPathDelimiter(Dir);
    Files := nil;
    try
      if TDirectory.Exists(Dir) then Files := TDirectory.GetFiles(Dir, '*' + CONTEXT_FILE_SUFFIX);
    except // dl:ok bare-except@b9ec -- REVIEWED 2026-10-28 fail-open by contract: an unreadable folder is skipped
      Files := nil;
    end;
    for F in Files do
      if TryLoadProjectContext(F, ACtx) then Exit(True);
    Parent := ExtractFilePath(Dir);
    if (Parent = '') or SameText(ExcludeTrailingPathDelimiter(Parent), Dir) then Break;
    Dir := Parent;
  end;
end;

function IsoUtc(const AValue: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', AValue);
end;

function BuildProjectContext(const ADproj, APlatform, AConfig: string): TProjectContext;
var
  Build: TActiveBuild;
  I: Integer;
begin
  Result := Default(TProjectContext);
  Result.Schema := CONTEXT_SCHEMA;
  if SameText(ExtractFileExt(ADproj), '.dproj') and TFile.Exists(ADproj) then
    Build := ResolveActiveBuild(ADproj, APlatform, AConfig, True)
  else
    Build := ResolveActiveBuild('', APlatform, AConfig, False);
  Result.Project := ADproj;
  Result.PlatformName := Build.Platform;
  if APlatform <> '' then Result.PlatformName := APlatform;
  Result.Config := Build.Config;
  if (Result.Config = '') and (AConfig <> '') then Result.Config := AConfig;
  SetLength(Result.Defines, Length(Build.Profile.Defines));
  for I := 0 to High(Build.Profile.Defines) do Result.Defines[I] := Build.Profile.Defines[I];
  if (ADproj <> '') and TFile.Exists(ADproj) then
  begin
    Result.SourceFile := ADproj;
    Result.SourceSha1 := FileSha1Hex(ADproj);
  end;
end;

function StrArrayToJson(const AItems: TArray<string>): TJSONArray;
var
  S: string;
begin
  Result := TJSONArray.Create;
  for S in AItems do Result.Add(S);
end;

procedure SaveProjectContext(const ACtx: TProjectContext; const AFile: string);
var
  Root, Src, Al: TJSONObject;
  P: TPair<string, string>;
  Gen, Mtime: string;
begin
  Root := TJSONObject.Create;
  try
    Gen := ACtx.GeneratedBy;
    if Gen = '' then Gen := 'drag-lint project-context';
    Root.AddPair('schema', TJSONNumber.Create(CONTEXT_SCHEMA));
    Root.AddPair('generatedBy', Gen);
    Root.AddPair('generatedAt', IsoUtc(TTimeZone.Local.ToUniversalTime(Now)));
    Root.AddPair('project', ACtx.Project);
    Mtime := '';
    if (ACtx.SourceFile <> '') and TFile.Exists(ACtx.SourceFile) then
      Mtime := IsoUtc(TFile.GetLastWriteTimeUtc(ACtx.SourceFile));
    Src := TJSONObject.Create;
    Src.AddPair('file', ACtx.SourceFile);
    Src.AddPair('mtime', Mtime);
    Src.AddPair('sha1', ACtx.SourceSha1);
    Root.AddPair('source', Src);
    Root.AddPair('platform', ACtx.PlatformName);
    Root.AddPair('config', ACtx.Config);
    Root.AddPair('targetCompiler', ACtx.TargetCompiler);
    Root.AddPair('defines', StrArrayToJson(ACtx.Defines));
    Root.AddPair('searchPath', StrArrayToJson(ACtx.SearchPath));
    Root.AddPair('namespaces', StrArrayToJson(ACtx.Namespaces));
    Al := TJSONObject.Create;
    for P in ACtx.UnitAliases do Al.AddPair(P.Key, P.Value);
    Root.AddPair('unitAliases', Al);
    Root.AddPair('libraryDb', ACtx.LibraryDb);
    Root.AddPair('libraryRoots', StrArrayToJson(ACtx.LibraryRoots));
    Root.AddPair('projectDb', ACtx.ProjectDb);
    WriteJsonFileAtomic(AFile, Root);
  finally
    Root.Free;
  end;
end;

end.
