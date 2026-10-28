unit ProjectSetup.ContextJson;

{ Reads and writes <ProjectBase>.dlcontext.json (schema 1). No VCL dependency. }

interface

uses
  System.SysUtils, System.Classes;

const
  /// <summary>Value written to the generatedBy field.</summary>
  CGeneratedBy = 'dl-project-setup 1.0';

type
  /// <summary>One project context, mirroring the schema-1 JSON fields.</summary>
  TSetupContext = record
    Project: string;
    PlatformName: string;
    Config: string;
    Defines: TArray<string>;
    SearchPath: TArray<string>;
    Namespaces: TArray<string>;
    LibraryDb: string;
    LibraryRoots: TArray<string>;
    ProjectDb: string;
    SourceFile: string;
    SourceSha1: string;
    TargetCompiler: string;
  end;

  /// <summary>Central defaults read from context-defaults.json (read only).</summary>
  TContextDefaults = record
    PlatformName: string;
    Config: string;
    TargetCompiler: string;
    LibraryDb: string;
    LibraryRoots: TArray<string>;
  end;

/// <summary>Delphi platform names the setup form offers.</summary>
function SetupPlatforms: TArray<string>;

/// <summary>Compiler built-in defines for a platform (empty for an unknown name).</summary>
function BuiltInDefines(const pPlatform: string): TArray<string>;

/// <summary>Built-ins for the platform, plus DEBUG when pConfig is Debug (case-insensitive).</summary>
function DefaultDefines(const pPlatform, pConfig: string): TArray<string>;

/// <summary>System;Vcl;Winapi for Windows platforms, System otherwise.</summary>
function DefaultNamespaces(const pPlatform: string): TArray<string>;

/// <summary>Path of the context file next to a project file: base + .dlcontext.json.</summary>
function ContextFileFor(const pProjectFile: string): string;

/// <summary>Lower-case hex SHA-1 of a file's bytes.</summary>
function FileSha1(const pFile: string): string;

/// <summary>Splits a memo text into trimmed, non-empty lines.</summary>
function SplitLines(const pText: string): TArray<string>;

/// <summary>Serialises a context to schema-1 JSON text (pure ASCII).</summary>
/// <param name="pCtx">Context to write.</param>
/// <param name="pNowUtc">Value for generatedAt (ISO-8601 Z).</param>
function ContextToJson(const pCtx: TSetupContext; const pNowUtc: string): string;

/// <summary>Parses schema-1 JSON text.</summary>
/// <returns>False when the text is not a JSON object with schema 1.</returns>
function TryParseContext(const pJson: string; out pCtx: TSetupContext): Boolean;

/// <summary>Writes the context file (UTF-8, no BOM) and returns its path.</summary>
function SaveContext(const pCtx: TSetupContext): string;

/// <summary>Path of the central defaults file under LOCALAPPDATA\drag-lint; env DRAGLINT_CONTEXT_DEFAULTS overrides it.</summary>
function ContextDefaultsFile: string;

/// <summary>Reads the central defaults file (platform, config, targetCompiler, libraries entry).</summary>
/// <param name="pPlatform">Platform whose libraries entry to use; empty = the file's own platform.</param>
/// <returns>False when the file is absent or invalid.</returns>
function TryLoadContextDefaults(const pPlatform: string; out pDefaults: TContextDefaults): Boolean;

/// <summary>Loads the context file next to pProjectFile, if present and valid.</summary>
function TryLoadContext(const pProjectFile: string; out pCtx: TSetupContext): Boolean;

implementation

uses
  System.JSON, System.Hash, System.IOUtils, System.DateUtils, Winapi.Windows,
  DRagLint.Preprocess.Profile;

const
  SCHEMA_VERSION = 1;
  LAST_ASCII = 126;
  UNICODE_HEX_DIGITS = 4;
  JSON_INDENT = 2;
  WIN_PREFIX_LEN = 3;
  ENV_BUF_LEN = 1024;

function Arr(const pItems: array of string): TArray<string>;
var
  i: Integer;
begin
  SetLength(Result, Length(pItems));
  for i := 0 to High(pItems) do
    Result[i] := pItems[i];
end;

function SetupPlatforms: TArray<string>;
begin
  Result := Arr(['Win32', 'Win64', 'Win64x', 'Linux64', 'OSX64', 'OSXARM64',
    'Android', 'Android64', 'iOSDevice64', 'iOSSimARM64']);
end;

function BuiltInDefines(const pPlatform: string): TArray<string>;
var
  Common: TArray<string>;
  i: Integer;
begin
  // Win32 / Win64: the engine's own table, DRagLint.Preprocess.Profile.PlatformBuiltins
  // (src\preprocess), upper-cased for the context file.
  if SameText(pPlatform, 'Win32') or SameText(pPlatform, 'Win64') then
  begin
    Result := PlatformBuiltins(pPlatform);
    for i := 0 to High(Result) do
      Result[i] := UpperCase(Result[i]);
    Exit;
  end;
  // Every other platform: the engine has NO table (it maps unknown names to Win64),
  // so these lists are NOT from the engine; they are the documented Delphi
  // platform symbols and must be checked against the compiler.
  Common := Arr(['UNICODE', 'CONDITIONALEXPRESSIONS', 'COMPILER_VERSION_37', 'VER370']);
  if SameText(pPlatform, 'Win64x') then
    Result := Arr(['MSWINDOWS', 'WIN64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else if SameText(pPlatform, 'Linux64') then
    Result := Arr(['LINUX', 'LINUX64', 'UNIX', 'POSIX', 'POSIX64', 'ELF', 'CPUX64', 'CPU64BITS'])
  else if SameText(pPlatform, 'OSX64') then
    Result := Arr(['MACOS', 'MACOS64', 'OSX', 'OSX64', 'DARWIN', 'UNIX', 'POSIX', 'POSIX64', 'CPUX64', 'CPU64BITS'])
  else if SameText(pPlatform, 'OSXARM64') then
    Result := Arr(['MACOS', 'MACOS64', 'DARWIN', 'UNIX', 'POSIX', 'POSIX64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else if SameText(pPlatform, 'Android') then
    Result := Arr(['ANDROID', 'LINUX', 'UNIX', 'POSIX', 'POSIX32', 'CPUARM', 'CPUARM32', 'CPU32BITS'])
  else if SameText(pPlatform, 'Android64') then
    Result := Arr(['ANDROID', 'ANDROID64', 'LINUX', 'UNIX', 'POSIX', 'POSIX64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else if SameText(pPlatform, 'iOSDevice64') then
    Result := Arr(['IOS', 'IOS64', 'DARWIN', 'UNIX', 'POSIX', 'POSIX64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else if SameText(pPlatform, 'iOSSimARM64') then
    Result := Arr(['IOS', 'IOS64', 'IOSSIMULATOR', 'DARWIN', 'UNIX', 'POSIX', 'POSIX64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else
    Exit(nil);
  Result := Common + Result;
end;

function DefaultDefines(const pPlatform, pConfig: string): TArray<string>;
begin
  Result := BuiltInDefines(pPlatform);
  if SameText(Trim(pConfig), 'Debug') then
    Result := Result + Arr(['DEBUG']);
end;

function DefaultNamespaces(const pPlatform: string): TArray<string>;
begin
  if SameText(Copy(pPlatform, 1, WIN_PREFIX_LEN), 'Win') then
    Result := Arr(['System', 'Vcl', 'Winapi'])
  else
    Result := Arr(['System']);
end;

function ContextFileFor(const pProjectFile: string): string;
begin
  Result := TPath.ChangeExtension(pProjectFile, '.dlcontext.json');
end;

function FileSha1(const pFile: string): string;
begin
  Result := LowerCase(THashSHA1.GetHashStringFromFile(pFile));
end;

function SplitLines(const pText: string): TArray<string>;
var
  List: TStringList;
  i, N: Integer;
  S: string;
begin
  Result := nil;
  List := TStringList.Create;
  try
    List.Text := pText;
    SetLength(Result, List.Count);
    N := 0;
    for i := 0 to List.Count - 1 do
    begin
      S := Trim(List[i]);
      if S <> '' then
      begin
        Result[N] := S;
        Inc(N);
      end;
    end;
    SetLength(Result, N);
  finally
    List.Free;
  end;
end;

function ToJsonArray(const pItems: TArray<string>): TJSONArray;
var
  S: string;
begin
  Result := TJSONArray.Create;
  for S in pItems do
    Result.Add(S);
end;

// Escapes every non-ASCII char as \uXXXX so the file is pure ASCII.
function AsciiOnly(const pText: string): string;
var
  Ch: Char;
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create;
  try
    for Ch in pText do
      if Ord(Ch) > LAST_ASCII then
        Sb.Append('\u').Append(IntToHex(Ord(Ch), UNICODE_HEX_DIGITS))
      else
        Sb.Append(Ch);
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function ContextToJson(const pCtx: TSetupContext; const pNowUtc: string): string;
var
  Root, Src: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema', TJSONNumber.Create(SCHEMA_VERSION));
    Root.AddPair('generatedBy', CGeneratedBy);
    Root.AddPair('generatedAt', pNowUtc);
    Root.AddPair('project', pCtx.Project);
    Src := TJSONObject.Create;
    Src.AddPair('file', pCtx.SourceFile);
    Src.AddPair('mtime', pNowUtc);
    Src.AddPair('sha1', pCtx.SourceSha1);
    Root.AddPair('source', Src);
    Root.AddPair('platform', pCtx.PlatformName);
    Root.AddPair('config', pCtx.Config);
    Root.AddPair('targetCompiler', pCtx.TargetCompiler);
    Root.AddPair('defines', ToJsonArray(pCtx.Defines));
    Root.AddPair('searchPath', ToJsonArray(pCtx.SearchPath));
    Root.AddPair('namespaces', ToJsonArray(pCtx.Namespaces));
    Root.AddPair('unitAliases', TJSONObject.Create);
    Root.AddPair('libraryDb', pCtx.LibraryDb);
    Root.AddPair('libraryRoots', ToJsonArray(pCtx.LibraryRoots));
    Root.AddPair('projectDb', pCtx.ProjectDb);
    Result := AsciiOnly(Root.Format(JSON_INDENT));
  finally
    Root.Free;
  end;
end;

function GetStr(pObj: TJSONObject; const pName: string): string;
begin
  if not pObj.TryGetValue<string>(pName, Result) then
    Result := '';
end;

function GetArr(pObj: TJSONObject; const pName: string): TArray<string>;
var
  Arr: TJSONArray;
  i: Integer;
begin
  Result := nil;
  if pObj.TryGetValue<TJSONArray>(pName, Arr) then
  begin
    SetLength(Result, Arr.Count);
    for i := 0 to Arr.Count - 1 do
      Result[i] := Arr.Items[i].Value;
  end;
end;

function TryParseContext(const pJson: string; out pCtx: TSetupContext): Boolean;
var
  Val: TJSONValue;
  Root, Src: TJSONObject;
  Schema: Integer;
begin
  Result := False;
  pCtx := Default(TSetupContext);
  Val := TJSONObject.ParseJSONValue(pJson);
  if Val = nil then
    Exit;
  try
    if not (Val is TJSONObject) then
      Exit;
    Root := TJSONObject(Val);
    if not Root.TryGetValue<Integer>('schema', Schema) or (Schema <> SCHEMA_VERSION) then
      Exit;
    pCtx.Project := GetStr(Root, 'project');
    pCtx.PlatformName := GetStr(Root, 'platform');
    pCtx.Config := GetStr(Root, 'config');
    pCtx.Defines := GetArr(Root, 'defines');
    pCtx.SearchPath := GetArr(Root, 'searchPath');
    pCtx.Namespaces := GetArr(Root, 'namespaces');
    pCtx.LibraryDb := GetStr(Root, 'libraryDb');
    pCtx.LibraryRoots := GetArr(Root, 'libraryRoots');
    pCtx.ProjectDb := GetStr(Root, 'projectDb');
    pCtx.TargetCompiler := GetStr(Root, 'targetCompiler');
    if Root.TryGetValue<TJSONObject>('source', Src) then
    begin
      pCtx.SourceFile := GetStr(Src, 'file');
      pCtx.SourceSha1 := GetStr(Src, 'sha1');
    end;
    Result := True;
  finally
    Val.Free;
  end;
end;

function SaveContext(const pCtx: TSetupContext): string;
var
  Json: string;
begin
  Result := ContextFileFor(pCtx.Project);
  Json := ContextToJson(pCtx, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(Now)));
  TFile.WriteAllText(Result, Json, TUTF8Encoding.Create(False));
end;

function ContextDefaultsFile: string;
begin
  Result := GetEnvironmentVariable('DRAGLINT_CONTEXT_DEFAULTS');
  if Result = '' then
    Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'drag-lint'), 'context-defaults.json');
end;

function ExpandEnv(const pS: string): string;
var
  Buf: array[0..ENV_BUF_LEN - 1] of Char;
begin
  if (Pos('%', pS) > 0) and (ExpandEnvironmentStrings(PChar(pS), Buf, Length(Buf)) > 0) then
    Result := Buf
  else
    Result := pS;
end;

function TryLoadContextDefaults(const pPlatform: string; out pDefaults: TContextDefaults): Boolean;
var
  DefFile, Plat: string;
  Val: TJSONValue;
  Root, Libs, Lib: TJSONObject;
  i: Integer;
begin
  Result := False;
  pDefaults := Default(TContextDefaults);
  DefFile := ContextDefaultsFile;
  if not TFile.Exists(DefFile) then
    Exit;
  Val := TJSONObject.ParseJSONValue(TFile.ReadAllText(DefFile, TEncoding.UTF8));
  if Val = nil then
    Exit;
  try
    if not (Val is TJSONObject) then
      Exit;
    Root := TJSONObject(Val);
    pDefaults.PlatformName := GetStr(Root, 'platform');
    pDefaults.Config := GetStr(Root, 'config');
    pDefaults.TargetCompiler := GetStr(Root, 'targetCompiler');
    Plat := pPlatform;
    if Plat = '' then
      Plat := pDefaults.PlatformName;
    if Root.TryGetValue<TJSONObject>('libraries', Libs) and Libs.TryGetValue<TJSONObject>(Plat, Lib) then
    begin
      pDefaults.LibraryDb := ExpandEnv(GetStr(Lib, 'libraryDb'));
      pDefaults.LibraryRoots := GetArr(Lib, 'libraryRoots');
      for i := 0 to High(pDefaults.LibraryRoots) do
        pDefaults.LibraryRoots[i] := ExpandEnv(pDefaults.LibraryRoots[i]);
    end;
    Result := True;
  finally
    Val.Free;
  end;
end;

function TryLoadContext(const pProjectFile: string; out pCtx: TSetupContext): Boolean;
var
  DefFile: string;
begin
  pCtx := Default(TSetupContext);
  DefFile := ContextFileFor(pProjectFile);
  Result := TFile.Exists(DefFile) and TryParseContext(TFile.ReadAllText(DefFile, TEncoding.UTF8), pCtx);
end;

end.
