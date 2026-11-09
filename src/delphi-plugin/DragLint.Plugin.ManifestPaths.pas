unit DragLint.Plugin.ManifestPaths;

{ Installed layout v2, phase 3 (P2): where the IDE plugin looks for drag-lint.json.
  Spec: docs\superpowers\specs\2026-11-06-installed-layout-v2.md.

  The engine answers "which manifest" through TInstalledLayout.ManifestLocation; until this unit
  the plugin built '<dir>\drag-lint.json' by hand, so with DRAGLINT_LAYOUT=v2 (or an explicit
  DRAGLINT_MANIFEST) plugin and engine read different files. Every plugin manifest lookup now asks
  the same resolver. Pure: no ToolsAPI, so tests\ManifestPathsTests.dpr drives it directly. }

interface

uses
  System.SysUtils
  , System.IOUtils
  , DRagLint.Index.Manifest
  ;

/// <summary>The manifest the engine would read when it ran from ADir.</summary>
/// <param name="ADir">A folder: the engine exe folder or the BPL folder.</param>
/// <returns>TInstalledLayout.ManifestLocation(ADir): the explicit file (DRAGLINT_MANIFEST), else
/// under DRAGLINT_LAYOUT=v2 the roaming file when it exists, else ADir\drag-lint.json.</returns>
/// <remarks>Layout OFF and no explicit file: Path = ADir + 'drag-lint.json', the plugin's
/// behaviour before phase 3. Reads the environment; thread-safe.</remarks>
function PluginManifestIn(const ADir: string): TManifestLocation;

/// <summary>The manifests the library lookup probes, in order: the engine's, then the BPL's.</summary>
/// <param name="AEngineExe">Full path of drag-lint.exe; '' skips the engine rung.</param>
/// <param name="ABplDir">Folder of the plugin BPL.</param>
/// <returns>Each folder's PluginManifestIn path, duplicates removed (case-insensitive). With an
/// explicit or roaming manifest both rungs answer the same file, so the result has one entry.</returns>
function PluginManifestCandidates(const AEngineExe, ABplDir: string): TArray<string>;

/// <summary>The library outDir a manifest names, the way the engine reads it.</summary>
/// <param name="ARawOutDir">The raw indexes.outDir text ('' when absent).</param>
/// <param name="AManifestPath">The manifest file the value came from.</param>
/// <returns>Layout v2: %NAME% expanded (E6); an empty value in the roaming manifest gives
/// %LOCALAPPDATA%\drag-lint\library (ruling 3). Layout OFF: ARawOutDir unchanged.</returns>
function PluginLibraryOutDir(const ARawOutDir, AManifestPath: string): string;

/// <summary>The global manifest file the Options page writes when no project is open.</summary>
/// <param name="AEngineDir">The engine exe folder ('' when unresolved).</param>
/// <returns>TInstalledLayout.WriteTarget(AEngineDir): the file the engine reads; under v2 with no
/// manifest anywhere, the roaming file. Layout OFF: AEngineDir\drag-lint.json.</returns>
function PluginManifestWriteTarget(const AEngineDir: string): string;

implementation

function PluginManifestIn(const ADir: string): TManifestLocation;
begin
  Result:= TInstalledLayout.ManifestLocation(ADir);
end;

function PluginManifestCandidates(const AEngineExe, ABplDir: string): TArray<string>;

  procedure AddUnique(const APath: string);
  begin
    for var Have in Result do
      if SameText(Have, APath) then Exit;
    Result:= Result + [APath];
  end;

begin
  Result:= nil;
  if AEngineExe <> '' then AddUnique(PluginManifestIn(ExtractFilePath(AEngineExe)).Path);
  AddUnique(PluginManifestIn(ABplDir).Path);
end;

function PluginLibraryOutDir(const ARawOutDir, AManifestPath: string): string;
begin
  Result:= TInstalledLayout.ExpandOutDir(ARawOutDir);
  if Result = '' then Result:= TInstalledLayout.DefaultOutDir(ExtractFilePath(AManifestPath));
end;

function PluginManifestWriteTarget(const AEngineDir: string): string;
begin
  Result:= TInstalledLayout.WriteTarget(AEngineDir);
end;

end.
