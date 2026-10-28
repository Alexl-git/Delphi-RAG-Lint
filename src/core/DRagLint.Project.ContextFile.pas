unit DRagLint.Project.ContextFile;

{ The project-context file `<ProjectBase>.dlcontext.json` and the central
  context defaults `%LOCALAPPDATA%\drag-lint\context-defaults.json`.
  Contract: C:\TEMP\claude\lanes\lsp-context\SPEC.md sections 1 and 1b.

  MINIMAL READER written by lane CORE (fix/lsp-context) because the owning
  lane CTXFILE (feat/project-context-file) had not landed the unit when the
  LSP needed it. Same path, same API for the readers; BuildProjectContext and
  SaveProjectContext are NOT here -- CTXFILE owns them and reconciles this
  file when it merges. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  ;

type
  /// <summary>One project's build context as read from a .dlcontext.json.</summary>
  /// <remarks>Plain value record; Stale is computed by TryLoadProjectContext.</remarks>
  TProjectContext = record
    Schema      : Integer;
    Project     : string;
    Platform    : string;
    Config      : string;
    Defines     : TArray<string>;
    SearchPath  : TArray<string>;
    Namespaces  : TArray<string>;
    LibraryRoots: TArray<string>;
    UnitAliases : TArray<TPair<string,string>>;
    LibraryDb   : string;
    ProjectDb   : string;
    SourceFile  : string;
    SourceSha1  : string;
    /// <summary>Compiler version the code targets ('' = default); carried, not evaluated.</summary>
    TargetCompiler: string;
    /// <summary>The .dlcontext.json this was read from.</summary>
    ContextFile: string;
    /// <summary>True when source.file is a .dproj whose SHA-1 no longer matches source.sha1.</summary>
    Stale: Boolean;
  end;

  /// <summary>One `libraries.&lt;Platform&gt;` entry of the central defaults.</summary>
  TContextLibrary = record
    LibraryDb   : string;
    Platform    : string;  { not first: the drag-lint grammar fails on a record whose first field is Platform (gap logged) }
    LibraryRoots: TArray<string>;
  end;

  /// <summary>The central context defaults (spec 1b).</summary>
  TContextDefaults = record
    Schema        : Integer;
    Platform      : string;
    Config        : string;
    TargetCompiler: string;
    Libraries     : TArray<TContextLibrary>;
  end;

/// <summary>The context file that belongs to a project file.</summary>
/// <param name="AProjectFile">A .dproj or .dpr path.</param>
/// <returns>`&lt;dir&gt;\&lt;base&gt;.dlcontext.json`.</returns>
function  ContextFileFor(const AProjectFile: string): string;

/// <summary>Reads one .dlcontext.json.</summary>
/// <param name="AFile">The context file.</param>
/// <param name="ACtx">Receives the context; Default() on failure.</param>
/// <returns>False when the file is absent, unreadable or not a schema-1 JSON object.</returns>
/// <remarks>Never raises. Env vars in path fields are expanded.</remarks>
function  TryLoadProjectContext(const AFile: string; out ACtx: TProjectContext): Boolean;

/// <summary>Walks up from the unit's folder to the first *.dlcontext.json (nearest wins).</summary>
/// <param name="AUnitPath">A source file path.</param>
/// <param name="ACtx">Receives the context.</param>
/// <returns>True when one was found and loaded.</returns>
/// <remarks>Never raises. Several context files in one folder: the first by name.</remarks>
function  FindProjectContextForUnit(const AUnitPath: string; out ACtx: TProjectContext): Boolean;

/// <summary>The central defaults file: env DRAGLINT_CONTEXT_DEFAULTS when set (tests),
/// else %LOCALAPPDATA%\drag-lint\context-defaults.json.</summary>
/// <returns>The path; it may not exist.</returns>
function  ContextDefaultsFile: string;

/// <summary>Reads the central defaults (read-only; absence is normal).</summary>
/// <param name="ADefaults">Receives the defaults; Default() on failure.</param>
/// <returns>False when the file is absent or unreadable.</returns>
/// <remarks>Never raises. Env vars in libraryDb / libraryRoots are expanded.</remarks>
function  TryLoadContextDefaults(out ADefaults: TContextDefaults): Boolean;

/// <summary>The `libraries.&lt;APlatform&gt;.libraryDb` of ADefaults, or ''.</summary>
/// <param name="ADefaults">From TryLoadContextDefaults.</param>
/// <param name="APlatform">A Delphi platform name; compared case-insensitively.</param>
/// <returns>The expanded path or ''.</returns>
function  DefaultsLibraryDb(const ADefaults: TContextDefaults; const APlatform: string): string;

implementation

uses
  System.IOUtils
  , System.JSON
  , System.Hash
  , Winapi.Windows
  ;

const
  CONTEXT_EXT          = '.dlcontext.json';
  CONTEXT_SCHEMA       = 1;
  DEFAULTS_ENV         = 'DRAGLINT_CONTEXT_DEFAULTS';
  DEFAULTS_DIR         = 'drag-lint';
  DEFAULTS_FILE        = 'context-defaults.json';
  ENV_BUF_CHARS        = MAX_PATH * 4; // ExpandEnvironmentStrings buffer

function ExpandEnv(const AValue: string): string;
var
  Buf: array[0..ENV_BUF_CHARS] of Char;
  N  : DWORD;
begin
  Result:= AValue;
  if Pos('%', AValue) = 0 then Exit;
  N:= ExpandEnvironmentStrings(PChar(AValue), @Buf[0], Length(Buf));
  if (N > 0) and (N <= DWORD(Length(Buf))) then Result:= string(PChar(@Buf[0]));
end;

function StrOf(const AObj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  Result:= '';
  if AObj = nil then Exit;
  V:= AObj.GetValue(AName);
  if V is TJSONString then Result:= V.Value;
end;

function StrArrOf(const AObj: TJSONObject; const AName: string; AExpand: Boolean): TArray<string>;
var
  V: TJSONValue;
begin
  Result:= nil;
  if AObj = nil then Exit;
  V:= AObj.GetValue(AName);
  if not (V is TJSONArray) then Exit;
  for var E: TJSONValue in TJSONArray(V) do
    if E is TJSONString then
      Result:= Result + [if AExpand then ExpandEnv(E.Value) else E.Value];
end;

function ReadJsonObject(const AFile: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result:= nil;
  if (AFile = '') or not TFile.Exists(AFile) then Exit;
  V:= TJSONObject.ParseJSONValue(TFile.ReadAllText(AFile, TEncoding.UTF8));
  if V is TJSONObject then Result:= TJSONObject(V)
  else V.Free;
end;

function ContextFileFor(const AProjectFile: string): string;
begin
  Result:= ChangeFileExt(AProjectFile, '') + CONTEXT_EXT;
end;

function TryLoadProjectContext(const AFile: string; out ACtx: TProjectContext): Boolean;
var
  Root: TJSONObject;
begin
  ACtx  := Default(TProjectContext);
  Result:= False;
  try
    Root:= ReadJsonObject(AFile);
    if Root = nil then Exit;
    try
      ACtx.Schema:= Root.GetValue<Integer>('schema', 0);
      if ACtx.Schema <> CONTEXT_SCHEMA then Exit;
      ACtx.ContextFile   := ExpandFileName(AFile);
      ACtx.Project       := ExpandEnv(StrOf(Root, 'project'));
      ACtx.Platform      := StrOf(Root, 'platform');
      ACtx.Config        := StrOf(Root, 'config');
      ACtx.TargetCompiler:= StrOf(Root, 'targetCompiler');
      ACtx.Defines       := StrArrOf(Root, 'defines', False);
      ACtx.SearchPath    := StrArrOf(Root, 'searchPath', True);
      ACtx.Namespaces    := StrArrOf(Root, 'namespaces', False);
      ACtx.LibraryRoots  := StrArrOf(Root, 'libraryRoots', True);
      ACtx.LibraryDb     := ExpandEnv(StrOf(Root, 'libraryDb'));
      ACtx.ProjectDb     := ExpandEnv(StrOf(Root, 'projectDb'));
      var Aliases: TJSONValue:= Root.GetValue('unitAliases');
      if Aliases is TJSONObject then
        for var P: TJSONPair in TJSONObject(Aliases) do
          ACtx.UnitAliases:= ACtx.UnitAliases + [TPair<string,string>.Create(P.JsonString.Value, P.JsonValue.Value)];
      var Src: TJSONValue:= Root.GetValue('source');
      if Src is TJSONObject then
      begin
        ACtx.SourceFile:= ExpandEnv(StrOf(TJSONObject(Src), 'file'));
        ACtx.SourceSha1:= StrOf(TJSONObject(Src), 'sha1');
      end;
      { Spec 1: stale only against a .dproj source; a .dpr-only context never is. }
      if SameText(ExtractFileExt(ACtx.SourceFile), '.dproj') and TFile.Exists(ACtx.SourceFile) then
        ACtx.Stale:= not SameText(THashSHA1.GetHashStringFromFile(ACtx.SourceFile), ACtx.SourceSha1);
      Result:= True;
    finally
      Root.Free;
    end;
  except // dl:ok bare-except@a672 -- REVIEWED CORE 2026-10-28 never-raises contract: a malformed context file reads as absent
    ACtx  := Default(TProjectContext);
    Result:= False;
  end;
end;

function FindProjectContextForUnit(const AUnitPath: string; out ACtx: TProjectContext): Boolean;
var
  Dir, Parent: string;
begin
  ACtx  := Default(TProjectContext);
  Result:= False;
  if AUnitPath = '' then Exit;
  try
    Dir:= ExtractFileDir(ExpandFileName(AUnitPath));
    while Dir <> '' do
    begin
      if TDirectory.Exists(Dir) then
        for var F: string in TDirectory.GetFiles(Dir, '*' + CONTEXT_EXT) do
          if TryLoadProjectContext(F, ACtx) then Exit(True);
      Parent:= ExtractFileDir(Dir);
      if SameText(Parent, Dir) then Break;
      Dir:= Parent;
    end;
  except // dl:ok bare-except@79dc -- REVIEWED CORE 2026-10-28 never-raises contract: an unreadable folder means no context
    Result:= False;
  end;
end;

function ContextDefaultsFile: string;
begin
  Result:= GetEnvironmentVariable(DEFAULTS_ENV);
  if Result <> '' then Exit(ExpandEnv(Result));
  Result:= TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), DEFAULTS_DIR), DEFAULTS_FILE);
end;

function TryLoadContextDefaults(out ADefaults: TContextDefaults): Boolean;
var
  Root: TJSONObject;
begin
  ADefaults:= Default(TContextDefaults);
  Result   := False;
  try
    Root:= ReadJsonObject(ContextDefaultsFile);
    if Root = nil then Exit;
    try
      ADefaults.Schema        := Root.GetValue<Integer>('schema', 0);
      ADefaults.Platform      := StrOf(Root, 'platform');
      ADefaults.Config        := StrOf(Root, 'config');
      ADefaults.TargetCompiler:= StrOf(Root, 'targetCompiler');
      var Libs: TJSONValue:= Root.GetValue('libraries');
      if Libs is TJSONObject then
        for var P: TJSONPair in TJSONObject(Libs) do
          if P.JsonValue is TJSONObject then
          begin
            var L: TContextLibrary;
            L.Platform    := P.JsonString.Value;
            L.LibraryDb   := ExpandEnv(StrOf(TJSONObject(P.JsonValue), 'libraryDb'));
            L.LibraryRoots:= StrArrOf(TJSONObject(P.JsonValue), 'libraryRoots', True);
            ADefaults.Libraries:= ADefaults.Libraries + [L];
          end;
      Result:= True;
    finally
      Root.Free;
    end;
  except // dl:ok bare-except@80f1 -- REVIEWED CORE 2026-10-28 never-raises contract: unreadable defaults read as absent
    ADefaults:= Default(TContextDefaults);
    Result   := False;
  end;
end;

function DefaultsLibraryDb(const ADefaults: TContextDefaults; const APlatform: string): string;
begin
  Result:= '';
  for var L: TContextLibrary in ADefaults.Libraries do
    if SameText(L.Platform, APlatform) then Exit(L.LibraryDb);
end;

end.
