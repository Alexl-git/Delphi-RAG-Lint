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
  System.JSON, System.Hash, System.IOUtils, System.DateUtils, Winapi.Windows;

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
  lCommon: TArray<string>;
begin
  lCommon := Arr(['UNICODE', 'CONDITIONALEXPRESSIONS', 'VER370']);
  if SameText(pPlatform, 'Win32') then
    Result := Arr(['MSWINDOWS', 'WIN32', 'CPU386', 'CPUX86', 'CPU32BITS', 'ASSEMBLER'])
  else if SameText(pPlatform, 'Win64') then
    Result := Arr(['MSWINDOWS', 'WIN64', 'CPUX64', 'CPU64BITS', 'ASSEMBLER'])
  else if SameText(pPlatform, 'Win64x') then
    Result := Arr(['MSWINDOWS', 'WIN64', 'CPUARM64', 'CPUARM', 'CPU64BITS'])
  else if SameText(pPlatform, 'Linux64') then
    Result := Arr(['LINUX', 'LINUX64', 'UNIX', 'POSIX', 'POSIX64', 'ELF', 'CPUX64', 'CPU64BITS', 'ASSEMBLER'])
  else if SameText(pPlatform, 'OSX64') then
    Result := Arr(['MACOS', 'MACOS64', 'OSX', 'OSX64', 'DARWIN', 'UNIX', 'POSIX', 'POSIX64', 'CPUX64', 'CPU64BITS', 'ASSEMBLER'])
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
  Result := lCommon + Result;
end;

function DefaultDefines(const pPlatform, pConfig: string): TArray<string>;
begin
  Result := BuiltInDefines(pPlatform);
  if SameText(Trim(pConfig), 'Debug') then
    Result := Result + Arr(['DEBUG']);
end;

function DefaultNamespaces(const pPlatform: string): TArray<string>;
begin
  if SameText(Copy(pPlatform, 1, 3), 'Win') then
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
  lList: TStringList;
  i: Integer;
  lS: string;
begin
  Result := nil;
  lList := TStringList.Create;
  try
    lList.Text := pText;
    for i := 0 to lList.Count - 1 do
    begin
      lS := Trim(lList[i]);
      if lS <> '' then
        Result := Result + Arr([lS]);
    end;
  finally
    lList.Free;
  end;
end;

function ToJsonArray(const pItems: TArray<string>): TJSONArray;
var
  lS: string;
begin
  Result := TJSONArray.Create;
  for lS in pItems do
    Result.Add(lS);
end;

// Escapes every non-ASCII char as \uXXXX so the file is pure ASCII.
function AsciiOnly(const pText: string): string;
var
  lCh: Char;
  lSb: TStringBuilder;
begin
  lSb := TStringBuilder.Create;
  try
    for lCh in pText do
      if Ord(lCh) > 126 then
        lSb.Append('\u').Append(IntToHex(Ord(lCh), 4))
      else
        lSb.Append(lCh);
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

function ContextToJson(const pCtx: TSetupContext; const pNowUtc: string): string;
var
  lRoot, lSrc: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('schema', TJSONNumber.Create(1));
    lRoot.AddPair('generatedBy', CGeneratedBy);
    lRoot.AddPair('generatedAt', pNowUtc);
    lRoot.AddPair('project', pCtx.Project);
    lSrc := TJSONObject.Create;
    lSrc.AddPair('file', pCtx.SourceFile);
    lSrc.AddPair('mtime', pNowUtc);
    lSrc.AddPair('sha1', pCtx.SourceSha1);
    lRoot.AddPair('source', lSrc);
    lRoot.AddPair('platform', pCtx.PlatformName);
    lRoot.AddPair('config', pCtx.Config);
    lRoot.AddPair('targetCompiler', pCtx.TargetCompiler);
    lRoot.AddPair('defines', ToJsonArray(pCtx.Defines));
    lRoot.AddPair('searchPath', ToJsonArray(pCtx.SearchPath));
    lRoot.AddPair('namespaces', ToJsonArray(pCtx.Namespaces));
    lRoot.AddPair('unitAliases', TJSONObject.Create);
    lRoot.AddPair('libraryDb', pCtx.LibraryDb);
    lRoot.AddPair('libraryRoots', ToJsonArray(pCtx.LibraryRoots));
    lRoot.AddPair('projectDb', pCtx.ProjectDb);
    Result := AsciiOnly(lRoot.Format(2));
  finally
    lRoot.Free;
  end;
end;

function GetStr(pObj: TJSONObject; const pName: string): string;
begin
  if not pObj.TryGetValue<string>(pName, Result) then
    Result := '';
end;

function GetArr(pObj: TJSONObject; const pName: string): TArray<string>;
var
  lArr: TJSONArray;
  i: Integer;
begin
  Result := nil;
  if pObj.TryGetValue<TJSONArray>(pName, lArr) then
  begin
    SetLength(Result, lArr.Count);
    for i := 0 to lArr.Count - 1 do
      Result[i] := lArr.Items[i].Value;
  end;
end;

function TryParseContext(const pJson: string; out pCtx: TSetupContext): Boolean;
var
  lVal: TJSONValue;
  lRoot, lSrc: TJSONObject;
  lSchema: Integer;
begin
  Result := False;
  pCtx := Default(TSetupContext);
  lVal := TJSONObject.ParseJSONValue(pJson);
  if lVal = nil then
    Exit;
  try
    if not (lVal is TJSONObject) then
      Exit;
    lRoot := TJSONObject(lVal);
    if not lRoot.TryGetValue<Integer>('schema', lSchema) or (lSchema <> 1) then
      Exit;
    pCtx.Project := GetStr(lRoot, 'project');
    pCtx.PlatformName := GetStr(lRoot, 'platform');
    pCtx.Config := GetStr(lRoot, 'config');
    pCtx.Defines := GetArr(lRoot, 'defines');
    pCtx.SearchPath := GetArr(lRoot, 'searchPath');
    pCtx.Namespaces := GetArr(lRoot, 'namespaces');
    pCtx.LibraryDb := GetStr(lRoot, 'libraryDb');
    pCtx.LibraryRoots := GetArr(lRoot, 'libraryRoots');
    pCtx.ProjectDb := GetStr(lRoot, 'projectDb');
    pCtx.TargetCompiler := GetStr(lRoot, 'targetCompiler');
    if lRoot.TryGetValue<TJSONObject>('source', lSrc) then
    begin
      pCtx.SourceFile := GetStr(lSrc, 'file');
      pCtx.SourceSha1 := GetStr(lSrc, 'sha1');
    end;
    Result := True;
  finally
    lVal.Free;
  end;
end;

function SaveContext(const pCtx: TSetupContext): string;
var
  lJson: string;
begin
  Result := ContextFileFor(pCtx.Project);
  lJson := ContextToJson(pCtx, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(Now)));
  TFile.WriteAllText(Result, lJson, TUTF8Encoding.Create(False));
end;

function ContextDefaultsFile: string;
begin
  Result := GetEnvironmentVariable('DRAGLINT_CONTEXT_DEFAULTS');
  if Result = '' then
    Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'drag-lint'), 'context-defaults.json');
end;

function ExpandEnv(const pS: string): string;
var
  lBuf: array[0..1023] of Char;
begin
  if (Pos('%', pS) > 0) and (ExpandEnvironmentStrings(PChar(pS), lBuf, Length(lBuf)) > 0) then
    Result := lBuf
  else
    Result := pS;
end;

function TryLoadContextDefaults(const pPlatform: string; out pDefaults: TContextDefaults): Boolean;
var
  lFile, lPlat: string;
  lVal: TJSONValue;
  lRoot, lLibs, lLib: TJSONObject;
  i: Integer;
begin
  Result := False;
  pDefaults := Default(TContextDefaults);
  lFile := ContextDefaultsFile;
  if not TFile.Exists(lFile) then
    Exit;
  lVal := TJSONObject.ParseJSONValue(TFile.ReadAllText(lFile, TEncoding.UTF8));
  if lVal = nil then
    Exit;
  try
    if not (lVal is TJSONObject) then
      Exit;
    lRoot := TJSONObject(lVal);
    pDefaults.PlatformName := GetStr(lRoot, 'platform');
    pDefaults.Config := GetStr(lRoot, 'config');
    pDefaults.TargetCompiler := GetStr(lRoot, 'targetCompiler');
    lPlat := pPlatform;
    if lPlat = '' then
      lPlat := pDefaults.PlatformName;
    if lRoot.TryGetValue<TJSONObject>('libraries', lLibs) and lLibs.TryGetValue<TJSONObject>(lPlat, lLib) then
    begin
      pDefaults.LibraryDb := ExpandEnv(GetStr(lLib, 'libraryDb'));
      pDefaults.LibraryRoots := GetArr(lLib, 'libraryRoots');
      for i := 0 to High(pDefaults.LibraryRoots) do
        pDefaults.LibraryRoots[i] := ExpandEnv(pDefaults.LibraryRoots[i]);
    end;
    Result := True;
  finally
    lVal.Free;
  end;
end;

function TryLoadContext(const pProjectFile: string; out pCtx: TSetupContext): Boolean;
var
  lFile: string;
begin
  pCtx := Default(TSetupContext);
  lFile := ContextFileFor(pProjectFile);
  Result := TFile.Exists(lFile) and TryParseContext(TFile.ReadAllText(lFile, TEncoding.UTF8), pCtx);
end;

end.
