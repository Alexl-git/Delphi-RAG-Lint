unit DRagLint.Core.ContextDefaults;

// The central per-user settings folder %LOCALAPPDATA%\drag-lint and the WRITER side of its
// context-defaults.json (schema 1). The reader and the record types live in
// DRagLint.Project.ContextFile (LSP owns the format); this unit carries no dependency beyond
// the RTL and DRagLint.Core.JsonFile, so the IDE plugin BPL can link it.

interface

const
  /// <summary>Environment variable that overrides the central defaults file path (tests).</summary>
  CORE_CONTEXT_DEFAULTS_ENV = 'DRAGLINT_CONTEXT_DEFAULTS';

/// <summary>The per-user settings folder %LOCALAPPDATA%\drag-lint (no trailing separator).</summary>
/// <returns>The folder path; '' when LOCALAPPDATA is not set. Does not create it.</returns>
/// <remarks>The ONE definition; DRagLint.Project.ContextFile.DragLintLocalDataDir forwards here.</remarks>
function DragLintLocalDataDir: string;

/// <summary>Path of the central defaults file.</summary>
/// <returns>The env DRAGLINT_CONTEXT_DEFAULTS when set (explicit override, for tests),
/// else DragLintLocalDataDir\context-defaults.json; '' when neither resolves.</returns>
function ContextDefaultsFile: string;

/// <summary>Records one platform's library DB in the central defaults file, keeping every
/// other key (platform, config, targetCompiler, other platforms, this platform's
/// libraryRoots) exactly as it was.</summary>
/// <param name="AFile">The defaults file (normally ContextDefaultsFile); its folder is created.</param>
/// <param name="APlatform">Platform key under "libraries", e.g. 'Win64'; must not be empty.</param>
/// <param name="ALibraryDb">Absolute path of that platform's library index; must not be empty.</param>
/// <returns>True when the file was written; False when the value was already there, when an
/// argument is empty, or when an existing file is not a JSON object (it is never overwritten:
/// a user's hand edit beats a regenerated default).</returns>
/// <remarks>I/O errors from the atomic write (WriteJsonFileAtomic) propagate to the caller.
/// A new file gets "schema": 1. Writes atomically (temp + rename), UTF-8 without BOM.
/// Not thread-safe across processes beyond the atomic rename; last writer wins.</remarks>
function MergeLibraryDefault(const AFile, APlatform, ALibraryDb: string): Boolean;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  DRagLint.Core.JsonFile;

const
  DEFAULTS_FILE_NAME = 'context-defaults.json';
  DEFAULTS_SCHEMA = 1;

function DragLintLocalDataDir: string;
var
  Base: string;
begin
  Base := GetEnvironmentVariable('LOCALAPPDATA');
  if Base = '' then Exit('');
  Result := ExcludeTrailingPathDelimiter(Base) + PathDelim + 'drag-lint';
end;

function ContextDefaultsFile: string;
var
  Dir: string;
begin
  Result := GetEnvironmentVariable(CORE_CONTEXT_DEFAULTS_ENV);
  if Result <> '' then Exit;
  Dir := DragLintLocalDataDir;
  if Dir <> '' then Result := Dir + PathDelim + DEFAULTS_FILE_NAME;
end;

function LoadOrNewRoot(const AFile: string; out ARoot: TJSONObject): Boolean;
var
  V: TJSONValue;
begin
  ARoot := nil;
  if not TFile.Exists(AFile) then
  begin
    ARoot := TJSONObject.Create;
    ARoot.AddPair('schema', TJSONNumber.Create(DEFAULTS_SCHEMA));
    Exit(True);
  end;
  V := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFile, TEncoding.UTF8));
  if V is TJSONObject then
    ARoot := TJSONObject(V)
  else
    V.Free;
  Result := ARoot <> nil;
end;

function ChildObject(AParent: TJSONObject; const AName: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := AParent.GetValue(AName);
  if V is TJSONObject then Exit(TJSONObject(V));
  if V <> nil then AParent.RemovePair(AName).Free;
  Result := TJSONObject.Create;
  AParent.AddPair(AName, Result);
end;

function MergeLibraryDefault(const AFile, APlatform, ALibraryDb: string): Boolean;
var
  Root, Libs, Entry: TJSONObject;
  Old: string;
begin
  Result := False;
  if (AFile = '') or (APlatform = '') or (ALibraryDb = '') then Exit;
  if not LoadOrNewRoot(AFile, Root) then Exit;
  try
    Libs := ChildObject(Root, 'libraries');
    Entry := ChildObject(Libs, APlatform);
    if not Entry.TryGetValue<string>('libraryDb', Old) then Old := '';
    if SameText(Old, ALibraryDb) then Exit;
    Entry.RemovePair('libraryDb').Free;
    Entry.AddPair('libraryDb', ALibraryDb);
    TDirectory.CreateDirectory(ExtractFileDir(AFile));
    WriteJsonFileAtomic(AFile, Root);
    Result := True;
  finally
    Root.Free;
  end;
end;

end.
