# Index Manifest + Settings + Win64 Engine - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ad-hoc `--db` scoping and the 3-fixed-DB `scan-all` with a declarative, named-database manifest + settings (in `.drag-lint.json` beside the engine), supporting folder/dproj-closure include modes, glob + `.gitignore`/`.hgignore` excludes, cross-section dedup, per-platform library DBs, manifest-driven DB selection for all consumers (incl. the graph tool), a Win64-canonical engine (fixing the 1.4 GB OOM), and parallel `--jobs` reindex.

**Architecture:** A new `DRagLint.Index.Manifest` unit owns config load/merge/validate and resolves sections into a build plan (target DB, resolved roots, dedup, `{platform}` expansion). The CLI generalizes `DoScanAll` -> `DoIndexAll`, which either builds sequentially or fans out one child process per section (`index-section`). Folder-tree includes run through a new exclude/ignore engine; `.dproj`/`.dpr` includes run through a compile-closure resolver. A shared DB-selection helper lets CLI/LSP/MCP/graph-tool pick DBs from `(manifest, platform)` when `--db` is omitted. Engine ships Win64 only; interface BPLs build Win32+Win64.

**Tech Stack:** Delphi 13 (RAD Studio 37.0), Object Pascal, FireDAC + SQLite, tree-sitter via vendored DLLs, `System.JSON`, msbuild. Tests = PowerShell smoke scripts under `tests/autotest/` + fixtures under `tests/fixtures/`.

**Spec:** `docs/superpowers/specs/2026-06-15-index-manifest-design.md`

**Conventions:**
- All `.pas` files: strict 7-bit ASCII, CRLF, DocInsight `///` doc-comments on public surface (per `C:\Projects\CLAUDE.md`).
- Build the Win64 engine: from repo root
  `cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win64 drag-lint.dproj"`
- After each build, the test exe is `$EXE` (pinned in Task 0). tree-sitter DLLs from `third_party\dll-win64\` must sit beside `$EXE` (Task 0 copies them).
- New units must be registered in BOTH `drag-lint.dpr` AND `drag-lint.dproj` (HARD RULE).

---

## File Structure

**New units (engine):**
- `src/index/DRagLint.Index.Manifest.pas` - config types (`TIndexSettings`, `TIndexSection`, `TIndexManifest`), load/merge(global+local)/validate, save; resolve -> `TIndexPlan` (per-section: target DB, mode, resolved roots, dedup-exclude roots, `{platform}` expansion).
- `src/index/DRagLint.Index.Glob.pas` - wildcard matcher (`*`,`?`,`**`) over file/folder names.
- `src/index/DRagLint.Index.IgnoreFiles.pas` - `.gitignore`/`.hgignore` practical subset (per-line glob, trailing `/`, leading `!`, nested deeper-wins).
- `src/index/DRagLint.Index.Closure.pas` - `.dpr`/`.dproj` compile-closure resolver (members + transitive project-local uses + `{$I}`, minus registry-library files; excluded-in-closure warnings).
- `src/index/DRagLint.Index.DbSelect.pas` - `(manifest, platform) -> ordered TArray<string>` DB list for consumers.

**Modified (engine):**
- `src/core/DRagLint.Core.Indexer.pas` - accept an exclude/ignore config object in the folder walk; add file-level glob/allowlist/ignore filtering alongside `ShouldPruneDir`.
- `src/core/DRagLint.Core.Interfaces.pas` - extend `IIndexer` with the exclude/ignore config setter.
- `src/cli/DRagLint.CLI.pas` - parse `--all/--only/--platform/--dry-run/--json/--jobs`; `DoIndexAll`; hidden `index-section`; size guard on DB open; `scan-all` delegates; default DB selection from manifest when `--db` omitted.
- `drag-lint.dpr` + `drag-lint.dproj` - register new units.
- `C:\Projects\CLAUDE.md` - point the drag-lint exe default at `third_party\dll-win64\drag-lint.exe`.

**Modified (graph tool, separate repo `C:\Projects\Delphi-RAG-Lint-Graph`):**
- DB-resolution path - read the same global config + platform when no `--db` given.

**Tests/fixtures (new):**
- `tests/autotest/run_manifest.ps1` - end-to-end smoke for the whole feature.
- `tests/fixtures/manifest/` - fixture tree + `.drag-lint.json` + a tiny `.dproj` project.

---

## Task 0: Win64 build harness + pin the engine path

**Files:**
- Modify: `drag-lint.dproj` (confirm Win64 Debug config exists)
- Create: `tests/autotest/_manifest_common.ps1`

- [ ] **Step 1: Build the Win64 engine**

Run (repo root):
```
cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win64 drag-lint.dproj"
```
Expected: `Build succeeded.` Note the produced exe path (e.g. `src\cli\Win64\Debug\drag-lint.exe`).

- [ ] **Step 2: Create the shared test prologue**

`tests/autotest/_manifest_common.ps1`:
```powershell
# Shared prologue for manifest smoke tests. Pins the Win64 exe + ensures DLLs.
param(
    [string] $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
# tree-sitter Win64 DLLs must sit beside the exe.
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
}
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}; $color = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status,$Name,$Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
return $Exe
```

- [ ] **Step 3: Verify exe runs**

Run: `pwsh -NoProfile -Command "& '<EXE>' --version"`
Expected: prints a version string, exit 0.

- [ ] **Step 4: Commit**
```bash
git add tests/autotest/_manifest_common.ps1 drag-lint.dproj
git commit -m "test(index-manifest): Win64 build harness + shared test prologue"
```

---

## Task 1: Manifest config types + load/merge/validate

**Files:**
- Create: `src/index/DRagLint.Index.Manifest.pas`
- Create: `tests/fixtures/manifest/global.drag-lint.json`
- Create: `tests/autotest/run_manifest.ps1`
- Modify: `drag-lint.dpr`, `drag-lint.dproj`

- [ ] **Step 1: Write the fixture config**

`tests/fixtures/manifest/global.drag-lint.json`:
```json
{
  "settings": { "currentProjectsIndexing": "perProject", "defaultPlatform": "Win32",
                "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 0 },
  "indexes": {
    "outDir": "OUT",
    "exclude": ["*BACKUP*", "*_OLD*.pas", "* - Copy.pas"],
    "sections": [
      { "name": "Proj", "include": ["proj"], "useIgnoreFiles": true },
      { "name": "SQL",  "include": ["sql"], "includeOnly": ["MS*.SQL"] },
      { "name": "Library", "source": "registry-libraries", "platforms": "all",
        "db": "library-{platform}.sqlite" },
      { "name": "All", "include": ["."], "dedupAgainst": "*" }
    ]
  }
}
```

- [ ] **Step 2: Declare the public types + API (the contract)**

In `src/index/DRagLint.Index.Manifest.pas` interface:
```pascal
type
  TProjectsIndexing = (piPerProject, piPerGroup, piSingle);

  TIndexSettings = record
    CurrentProjectsIndexing: TProjectsIndexing;
    DefaultPlatform: string;     // 'Win32'
    SizeGuardMB: Integer;        // 1500
    EnginePath: string;          // 'auto'
    MaxJobs: Integer;            // 0 = auto
    class function Defaults: TIndexSettings; static;
  end;

  TIndexSection = record
    Name: string;
    Db: string;                  // may be '', bare name, or contain '{platform}'
    Source: string;              // '' (=include) | 'registry-libraries'
    Platforms: TArray<string>;   // expanded; ['*'] means "all"
    Include: TArray<string>;     // folders or .dpr/.dproj
    Exclude: TArray<string>;
    IncludeOnly: TArray<string>;
    UseIgnoreFiles: Boolean;     // default True
    DedupAgainst: TArray<string>;// ['*'] or names
    SqlOnlyMS: Boolean;          // default True
  end;

  TIndexManifest = record
    RootDir: string;             // dir of the resolved config (for relative paths)
    OutDir: string;
    GlobalExclude: TArray<string>;
    Settings: TIndexSettings;
    Sections: TArray<TIndexSection>;
    function FindSection(const AName: string; out ASection: TIndexSection): Boolean;
  end;

  TManifestIO = class
  public
    /// <summary>Load + merge: global config (beside EXE) then local override (cwd..parents).</summary>
    class function Load(const AEngineDir, AStartDir: string): TIndexManifest; static;
    class function ParseText(const AJson, ARootDir: string): TIndexManifest; static;
    class procedure Save(const AManifest: TIndexManifest; const APath: string); static;
    /// <summary>Returns '' if valid, else the first human-readable error.</summary>
    class function Validate(const AManifest: TIndexManifest): string; static;
  end;
```

- [ ] **Step 3: Write the failing test (run_manifest.ps1, load assertions)**

`tests/autotest/run_manifest.ps1` (first slice):
```powershell
$Exe = & "$PSScriptRoot\_manifest_common.ps1"
$fx  = "$PSScriptRoot\..\fixtures\manifest"
# `index --all --dry-run --json` reads the fixture config via --config and prints the plan.
$plan = & $Exe index --all --dry-run --json --config "$fx\global.drag-lint.json" 2>&1 | Out-String
Check 'dry-run exits 0' ($LASTEXITCODE -eq 0)
Check 'plan is json'    ($plan.TrimStart().StartsWith('{') -or $plan.TrimStart().StartsWith('['))
Check 'section Proj'     ($plan -match '"name"\s*:\s*"Proj"')
Check 'section SQL'      ($plan -match '"name"\s*:\s*"SQL"')
Check 'settings parsed'  ($plan -match '"currentProjectsIndexing"\s*:\s*"perProject"')
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 4: Run to verify it fails**

Run: `pwsh -File tests/autotest/run_manifest.ps1`
Expected: FAIL (the `--config`/`--all`/`--dry-run`/`--json` flags and plan output do not exist yet).

- [ ] **Step 5: Implement Manifest load/merge/validate**

Implement `ParseText` (System.JSON), `Load` (read `<AEngineDir>\drag-lint.json`, then walk `AStartDir`..root for `.drag-lint.json`, merging local over global: local sections replace same-name global sections, local scalars override), `Validate` (non-empty unique `Name`; a section has either `include` or `source='registry-libraries'`; `dedupAgainst` names resolve), `Defaults`. Resolve relative `include`/`db`/`outDir` against `RootDir`. Map `useGitignore`->`useIgnoreFiles` if the older key appears (back-compat).

Register the unit in `drag-lint.dpr` (uses clause) AND `drag-lint.dproj` (`<DCCReference Include="src\index\DRagLint.Index.Manifest.pas"/>`).

(The CLI plumbing for `--config/--all/--dry-run/--json` lands in Task 7; for now make `index --all --dry-run --json --config X` print the parsed manifest as JSON so this test can pass. A minimal `DoIndexAll` stub that loads + echoes is acceptable here and is fleshed out in Task 7.)

- [ ] **Step 6: Build + run test to verify pass**

Run the Win64 build, then `pwsh -File tests/autotest/run_manifest.ps1`.
Expected: PASS.

- [ ] **Step 7: Commit**
```bash
git add src/index/DRagLint.Index.Manifest.pas drag-lint.dpr drag-lint.dproj tests/fixtures/manifest/global.drag-lint.json tests/autotest/run_manifest.ps1
git commit -m "feat(index-manifest): config types + load/merge/validate + dry-run json"
```

---

## Task 2: Glob matcher

**Files:**
- Create: `src/index/DRagLint.Index.Glob.pas`
- Test: extend `tests/autotest/run_manifest.ps1` via a hidden self-test command `selftest glob`

- [ ] **Step 1: Declare API**
```pascal
type
  TGlob = class
  public
    /// <summary>Match AName against Ap pattern. '*'=any run, '?'=one char,
    /// '**'=any incl. path separators. Case-insensitive (Windows). AName is a
    /// bare file or folder name unless the pattern contains a path separator.</summary>
    class function Matches(const AName, APattern: string): Boolean; static;
    class function MatchesAny(const AName: string; const APatterns: TArray<string>): Boolean; static;
  end;
```

- [ ] **Step 2: Add a `selftest glob` command (test hook)**

In `DRagLint.CLI.pas`, add a hidden `selftest` command: `selftest glob` runs assertions and prints `GLOB-OK` / `GLOB-FAIL: <case>` and exits 0/1. Cases:
`Matches('Foo - Copy.pas','* - Copy.pas')=True`,
`Matches('Unit_OLD.pas','*_OLD*.pas')=True`,
`Matches('BACKUP_ALL','*BACKUP*')=True`,
`Matches('Unit.pas','*_OLD*.pas')=False`,
`Matches('a/b/c.pas','**/c.pas')=True`,
`Matches('MSData.SQL','MS*.SQL')=True`,
`Matches('Other.SQL','MS*.SQL')=False`.

- [ ] **Step 3: Failing test**

Append to `run_manifest.ps1`:
```powershell
$g = & $Exe selftest glob 2>&1 | Out-String
Check 'glob selftest' ($g -match 'GLOB-OK')
```
Run: `pwsh -File tests/autotest/run_manifest.ps1` -> FAIL (`selftest`/`TGlob` missing).

- [ ] **Step 4: Implement `TGlob`**

Translate the glob to a regex (escape regex metachars, `**`->`.*`, `*`->`[^\\/]*` unless followed by `/`, `?`->`.`), anchored, `roIgnoreCase`. Register unit in `.dpr`+`.dproj`. Wire `selftest glob`.

- [ ] **Step 5: Build + run -> PASS**

- [ ] **Step 6: Commit**
```bash
git add src/index/DRagLint.Index.Glob.pas src/cli/DRagLint.CLI.pas drag-lint.dpr drag-lint.dproj tests/autotest/run_manifest.ps1
git commit -m "feat(index-manifest): glob matcher (*, ?, **) + selftest"
```

---

## Task 3: Ignore-file engine (.gitignore / .hgignore)

**Files:**
- Create: `src/index/DRagLint.Index.IgnoreFiles.pas`
- Create: fixture tree `tests/fixtures/manifest/proj/` with nested ignore files

- [ ] **Step 1: Declare API**
```pascal
type
  /// <summary>Stack of ignore rules accumulated while descending a tree.
  /// Deeper (later-pushed) files take precedence; '!' re-includes.</summary>
  TIgnoreStack = class
  public
    procedure PushDir(const ADir: string);  // loads .gitignore + .hgignore if present
    procedure PopDir;
    /// <summary>True if APath (file or dir) is ignored by the current stack.</summary>
    function IsIgnored(const APath: string; AIsDir: Boolean): Boolean;
  end;
```

- [ ] **Step 2: Build the fixture**

Create:
- `tests/fixtures/manifest/proj/.hgignore` containing `syntax: glob` line then `*.log` and `build/`.
- `tests/fixtures/manifest/proj/keep.pas`, `proj/drop.log`, `proj/build/x.pas`,
  `proj/sub/.gitignore` containing `*.tmp` and `!keep.tmp`,
  `proj/sub/a.tmp`, `proj/sub/keep.tmp`, `proj/sub/b.pas`.

- [ ] **Step 3: Failing test**

Append to `run_manifest.ps1` (asserts the indexed file set of section Proj). After `index --all` indexes Proj into `OUT\Proj.sqlite`, query indexed files:
```powershell
& $Exe index --only Proj --config "$fx\global.drag-lint.json" 2>&1 | Out-Null
$db = "$fx\OUT\Proj.sqlite"
$files = & $Exe selftest files --db $db 2>&1 | Out-String   # prints one indexed file path per line
Check 'keep.pas indexed'      ($files -match 'keep\.pas')
Check 'drop.log NOT indexed'  (-not ($files -match 'drop\.log'))
Check 'build/ pruned'         (-not ($files -match '[\\/]build[\\/]'))
Check 'a.tmp ignored'         (-not ($files -match 'sub[\\/]a\.tmp'))
Check 'keep.tmp re-included'  ($files -match 'sub[\\/]keep\.tmp')
```
(Add a `selftest files --db` command that prints the `files` table paths.)
Run -> FAIL.

- [ ] **Step 4: Implement `TIgnoreStack`**

Parse each ignore file: skip blank/`#`/`syntax:` lines; trailing `/` => dir-only; leading `!` => negation; reuse `TGlob`. `IsIgnored` evaluates rules outermost->innermost, last match wins (negation can re-include). Register in `.dpr`+`.dproj`. Add `selftest files`.

- [ ] **Step 5: Build + run -> PASS**

- [ ] **Step 6: Commit**
```bash
git add src/index/DRagLint.Index.IgnoreFiles.pas src/cli/DRagLint.CLI.pas drag-lint.dpr drag-lint.dproj tests/fixtures/manifest/proj tests/autotest/run_manifest.ps1
git commit -m "feat(index-manifest): .gitignore/.hgignore practical-subset engine"
```

---

## Task 4: Exclude/ignore wired into the folder-tree walk

**Files:**
- Modify: `src/core/DRagLint.Core.Indexer.pas`, `src/core/DRagLint.Core.Interfaces.pas`

- [ ] **Step 1: Extend `IIndexer`**

Add to `IIndexer`:
```pascal
type
  TWalkFilter = record
    GlobalExclude: TArray<string>;
    SectionExclude: TArray<string>;
    IncludeOnly: TArray<string>;     // empty = allow all
    UseIgnoreFiles: Boolean;
    SqlOnlyMS: Boolean;
  end;
procedure SetWalkFilter(const AFilter: TWalkFilter);
```

- [ ] **Step 2: Failing test**

The Task 3 assertions already exercise ignore files; add allowlist + exclude:
```powershell
& $Exe index --only SQL --config "$fx\global.drag-lint.json" 2>&1 | Out-Null
$sqlFiles = & $Exe selftest files --db "$fx\OUT\SQL.sqlite" 2>&1 | Out-String
Check 'SQL keeps MS*.SQL'    ($sqlFiles -match 'MS\w*\.SQL')
Check 'SQL drops .pas'       (-not ($sqlFiles -match '\.pas'))
Check 'global exclude *_OLD* drops Unit_OLD.pas in Proj' (-not ($files -match '_OLD'))
```
Add fixture files: `tests/fixtures/manifest/sql/MSData.SQL`, `sql/scratch.pas`, `sql/notes.SQL`; `tests/fixtures/manifest/proj/Unit_OLD.pas`.
Run -> FAIL.

- [ ] **Step 3: Implement filtering in `WalkAndIndex`/`ShouldPruneDir`**

In `ShouldPruneDir`: also prune a dir whose name matches `GlobalExclude`+`SectionExclude`. In the file loop: skip a file if it matches an exclude glob; if `IncludeOnly` non-empty, skip files not matching it; keep the existing `SqlFileAllowed` gate (now per `SqlOnlyMS`). When `UseIgnoreFiles`, maintain a `TIgnoreStack` (PushDir on enter, PopDir on leave) and skip ignored files/dirs. Built-in prunes stay first (lowest precedence); ignore files evaluated last (highest).

- [ ] **Step 4: Build + run -> PASS**

- [ ] **Step 5: Commit**
```bash
git add src/core/DRagLint.Core.Indexer.pas src/core/DRagLint.Core.Interfaces.pas tests/fixtures/manifest tests/autotest/run_manifest.ps1
git commit -m "feat(index-manifest): folder-tree exclude/includeOnly/ignore precedence"
```

---

## Task 5: dproj compile-closure resolver

**Files:**
- Create: `src/index/DRagLint.Index.Closure.pas`
- Create: fixture project `tests/fixtures/manifest/app/`

- [ ] **Step 1: Declare API**
```pascal
type
  TClosureResult = record
    Files: TArray<string>;        // .pas/.inc to index (project-local closure)
    Warnings: TArray<string>;     // excluded-but-in-closure messages
  end;
  TClosureResolver = class
  public
    constructor Create(const ALibraryRoots: TArray<string>);
    /// <summary>Resolve the compile closure of a .dpr/.dproj: members +
    /// transitive project-local uses + {$I}/{$INCLUDE}, minus files under any
    /// library root. AExclude globs flagged (not dropped) if reached via uses.</summary>
    function Resolve(const AProjectFile: string;
      const AExclude: TArray<string>): TClosureResult;
  end;
```

- [ ] **Step 2: Build the fixture**

`tests/fixtures/manifest/app/App.dpr` with `uses uAlpha, uBeta;`. `uAlpha.pas` (`uses uGamma;` + `{$I uAlpha.inc}`), `uBeta.pas`, `uGamma.pas`, `uAlpha.inc`, and a `uStale - Copy.pas` that `uBeta` still `uses` (to trigger the warning), plus an unreferenced `uOrphan.pas` that must NOT be in the closure.

- [ ] **Step 3: Failing test**
```powershell
$ap = "$fx\app"
$cl = & $Exe selftest closure --project "$ap\App.dpr" --exclude "* - Copy.pas" 2>&1 | Out-String
Check 'closure has uAlpha' ($cl -match 'uAlpha\.pas')
Check 'closure has uGamma (transitive)' ($cl -match 'uGamma\.pas')
Check 'closure has inc'    ($cl -match 'uAlpha\.inc')
Check 'orphan excluded'    (-not ($cl -match 'uOrphan\.pas'))
Check 'stale copy warned'  ($cl -match 'WARN.*uStale - Copy\.pas.*uBeta')
```
Add `selftest closure --project --exclude` printing files + `WARN ...` lines.
Run -> FAIL.

- [ ] **Step 4: Implement `TClosureResolver`**

Parse `.dpr`/`.dproj` members (reuse `TProjectResolver.ReadDProj`/`ReadDprUsesPaths`). BFS over `uses`: resolve each used unit to a file via the project search paths; skip units whose file is under a library root; collect `{$I file}` includes by scanning each unit's text. If a reached file matches `AExclude`, add it to `Files` AND push a warning naming the using unit. Register in `.dpr`+`.dproj`.

- [ ] **Step 5: Build + run -> PASS**

- [ ] **Step 6: Commit**
```bash
git add src/index/DRagLint.Index.Closure.pas src/cli/DRagLint.CLI.pas drag-lint.dpr drag-lint.dproj tests/fixtures/manifest/app tests/autotest/run_manifest.ps1
git commit -m "feat(index-manifest): dproj compile-closure resolver + stale-copy warning"
```

---

## Task 6: Section resolution -> build plan (incl. {platform} + dedup)

**Files:**
- Modify: `src/index/DRagLint.Index.Manifest.pas`

- [ ] **Step 1: Declare plan types + API**
```pascal
type
  TPlanSectionMode = (smFolderTree, smClosure, smLibrary);
  TPlanSection = record
    Name: string;
    Mode: TPlanSectionMode;
    DbPath: string;            // {platform}-expanded, absolute
    Platform: string;          // '' unless library
    Roots: TArray<string>;     // resolved include roots (folders) or project files
    DedupExcludeRoots: TArray<string>;
    Filter: TWalkFilter;
  end;
  TIndexPlan = record
    Items: TArray<TPlanSection>;
  end;

function ResolvePlan(const AManifest: TIndexManifest;
  const APlatformsFilter: TArray<string>;  // nil = all
  const AResolver: TProjectResolver): TIndexPlan;
```

- [ ] **Step 2: Failing test (dry-run plan assertions)**

Append to `run_manifest.ps1`:
```powershell
$plan = & $Exe index --all --dry-run --json --config "$fx\global.drag-lint.json" 2>&1 | Out-String
Check 'lib expands Win32' ($plan -match 'library-Win32\.sqlite')
Check 'lib expands Win64' ($plan -match 'library-Win64\.sqlite')
Check 'All dedups Proj root' ($plan -match '"dedupExcludeRoots"[\s\S]*proj')
Check 'Proj mode folderTree' ($plan -match '"name"\s*:\s*"Proj"[\s\S]*?"mode"\s*:\s*"folderTree"')
```
Run -> FAIL (plan not yet structured).

- [ ] **Step 3: Implement `ResolvePlan`**

For each section: classify mode (`source='registry-libraries'`->smLibrary; any include entry ending `.dpr`/`.dproj`->smClosure for that entry; else smFolderTree). Expand `{platform}` for library sections over `Platforms` (`'*'` -> `AResolver.EnumRegistryPlatforms`, intersected with `APlatformsFilter`). Resolve `DbPath` (abs; `<OutDir>\<Name>.sqlite` default). Build `Filter` from global+section excludes/includeOnly/useIgnoreFiles/sqlOnlyMS. Compute `DedupExcludeRoots` = union of resolved roots of the sections named by `dedupAgainst` (`'*'`=all others). Make `DoIndexAll --dry-run --json` serialize `TIndexPlan`.

- [ ] **Step 4: Build + run -> PASS**

- [ ] **Step 5: Commit**
```bash
git add src/index/DRagLint.Index.Manifest.pas src/cli/DRagLint.CLI.pas tests/autotest/run_manifest.ps1
git commit -m "feat(index-manifest): resolve sections to build plan ({platform}+dedup)"
```

---

## Task 7: `DoIndexAll` orchestrator (sequential) + CLI flags + scan-all alias

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas`

- [ ] **Step 1: Add CLI flags**

In the arg loop (near line 352, beside `--exclude-under`): parse `--config <path>` (sets `Args.ConfigPath`), `--only <csv>` (`Args.OnlySections`), `--platform <p>` (`Args.Platform`); in the bool section parse `--all` (`Args.IndexAll`), `--dry-run` (`Args.DryRun` already exists), `--json` (`Args.Json`), and `--jobs <n>` (`Args.Jobs`). Add the fields to `TArgs`.

- [ ] **Step 2: Failing test**
```powershell
& $Exe index --all --config "$fx\global.drag-lint.json" 2>&1 | Out-Null
Check 'index --all exits 0'  ($LASTEXITCODE -eq 0)
Check 'Proj.sqlite built'    (Test-Path "$fx\OUT\Proj.sqlite")
Check 'SQL.sqlite built'     (Test-Path "$fx\OUT\SQL.sqlite")
Check 'All.sqlite built'     (Test-Path "$fx\OUT\All.sqlite")
& $Exe index --only Proj --config "$fx\global.drag-lint.json" 2>&1 | Out-Null
Check 'only Proj exits 0'    ($LASTEXITCODE -eq 0)
```
Run -> FAIL (full build path not implemented).

- [ ] **Step 3: Implement sequential `DoIndexAll`**

Load manifest (`TManifestIO.Load` using engine dir + `--config` override), `ResolvePlan`, filter by `--only`/`--platform`. For `--dry-run`: emit plan (text or `--json`). Else for each plan item: create store, `SetWalkFilter`, `AddExcludeRoot` for each `DedupExcludeRoots`; smFolderTree -> `IndexFolder(root,true)`; smClosure -> resolve closure, `IndexFile` each, print warnings; smLibrary -> `ReadLibraryPaths([Platform])` then index those roots (shallow). `ResolveUnitUseTargets`. Print per-section timing. Replace `DoScanAll` body to translate the old `scan` block into a `TIndexManifest` and call `DoIndexAll` (alias).

- [ ] **Step 4: Build + run -> PASS**

- [ ] **Step 5: Commit**
```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_manifest.ps1
git commit -m "feat(index-manifest): index --all/--only/--platform/--dry-run + scan-all alias"
```

---

## Task 8: Parallel `--jobs N` (across-section worker processes)

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas`

- [ ] **Step 1: Add hidden `index-section` child command**

`index-section --db <path> --root <r> [--root <r>...] --mode folderTree|closure|library [--platform p] [--exclude g]... [--include-only g]... [--use-ignore] [--dedup-exclude r]...` - builds exactly one section's DB (the parent resolved everything; the child just indexes). Reuses the Task 7 per-item logic for one item.

- [ ] **Step 2: Failing test**
```powershell
Remove-Item "$fx\OUT\*.sqlite" -ErrorAction SilentlyContinue
$t = Measure-Command { & $Exe index --all --jobs 3 --config "$fx\global.drag-lint.json" 2>&1 | Out-Null }
Check 'jobs build exits 0' ($LASTEXITCODE -eq 0)
Check 'all DBs built'      ((Test-Path "$fx\OUT\Proj.sqlite") -and (Test-Path "$fx\OUT\SQL.sqlite") -and (Test-Path "$fx\OUT\All.sqlite"))
```
Run -> FAIL (`--jobs` not honored / `index-section` missing).

- [ ] **Step 3: Implement the job pool**

In `DoIndexAll`, when effective jobs (`--jobs` else `settings.maxJobs`; 0 -> `min(CpuCount, Length(Items))`) > 1: launch each plan item as a child `index-section` process (`CreateProcessW`, inherited console), throttle to N concurrent (`WaitForMultipleObjects`), collect exit codes; non-zero -> overall failure. jobs=1 stays the in-process sequential path. (Library section emits one child per platform DB.)

- [ ] **Step 4: Build + run -> PASS**

- [ ] **Step 5: Commit**
```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_manifest.ps1
git commit -m "feat(index-manifest): parallel --jobs across-section worker processes"
```

---

## Task 9: Consumer DB selection + size guard

**Files:**
- Create: `src/index/DRagLint.Index.DbSelect.pas`
- Modify: `src/cli/DRagLint.CLI.pas`, `src/lsp/DRagLint.LSP.Server.pas`, `src/mcp/DRagLint.MCP.Server.pas`

- [ ] **Step 1: Declare API**
```pascal
type
  TDbSelect = class
  public
    /// <summary>Ordered DB list for consumers: all non-library section DBs +
    /// the single library-{platform} DB for APlatform. Existing files only.</summary>
    class function Resolve(const AManifest: TIndexManifest;
      const APlatform: string): TArray<string>; static;
  end;
```

- [ ] **Step 2: Failing test**
```powershell
$sel = & $Exe selftest dbselect --platform Win64 --config "$fx\global.drag-lint.json" 2>&1 | Out-String
Check 'select includes Proj'         ($sel -match 'Proj\.sqlite')
Check 'select includes library-Win64'($sel -match 'library-Win64\.sqlite')
Check 'select excludes library-Win32'(-not ($sel -match 'library-Win32\.sqlite'))
# size guard (simulate): a flag forces the 32-bit branch + a tiny threshold
$g = & $Exe query --name X --db "$fx\OUT\All.sqlite" --force32 --size-guard-mb 0 2>&1 | Out-String
Check 'size guard warns' ($g -match 'size guard|too large|use the Win64')
```
Run -> FAIL.

- [ ] **Step 3: Implement**

`TDbSelect.Resolve` per spec. Add `selftest dbselect`. In CLI/LSP/MCP startup, when no `--db` given, load manifest + `TDbSelect.Resolve(settings.defaultPlatform or --platform)`. Size guard: before opening a DB, if process is 32-bit (compile-time `{$IFNDEF WIN64}` or `--force32` test hook) and file size > `sizeGuardMB`, print a clear message naming the Win64 exe and continue/skip per severity.

- [ ] **Step 4: Build + run -> PASS**

- [ ] **Step 5: Commit**
```bash
git add src/index/DRagLint.Index.DbSelect.pas src/cli/DRagLint.CLI.pas src/lsp/DRagLint.LSP.Server.pas src/mcp/DRagLint.MCP.Server.pas drag-lint.dpr drag-lint.dproj tests/autotest/run_manifest.ps1
git commit -m "feat(index-manifest): manifest-driven DB selection + 32-bit size guard"
```

---

## Task 10: Graph tool reads the same config + platform

**Files:**
- Modify: `C:\Projects\Delphi-RAG-Lint-Graph` DB-resolution unit (locate via its `.dpr`)

- [ ] **Step 1: Locate the viewer's `--db` handling**

Run: `pwsh -NoProfile -Command "Select-String -Path 'C:\Projects\Delphi-RAG-Lint-Graph\src\*.pas' -Pattern '--db' "` and identify the startup arg parser.

- [ ] **Step 2: Implement**

Add the `DRagLint.Index.Manifest` + `DRagLint.Index.DbSelect` units to the graph project (shared source path). When the viewer is launched with no `--db`, load the global config and call `TDbSelect.Resolve(platform)` (platform from `--platform` or the manifest `defaultPlatform`).

- [ ] **Step 3: Build the graph viewer (Win64)**

Run its msbuild (`/p:Platform=Win64 /p:Config=Debug`). Expected: build succeeds; launching with no `--db` opens the manifest's DB set.

- [ ] **Step 4: Commit (in the graph repo)**
```bash
cd C:/Projects/Delphi-RAG-Lint-Graph && git add -A && git commit -m "feat: resolve DBs from drag-lint manifest + platform when --db omitted"
```

---

## Task 11: Win64-canonical rollout + packages + reindex + test plan

**Files:**
- Modify: `C:\Projects\CLAUDE.md`; build BPLs; `docs/TEST-PLAN-IDE-FULL.md`

- [ ] **Step 1: Make Win64 canonical**

Update `C:\Projects\CLAUDE.md` drag-lint exe path to `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`. Copy the freshly built Win64 exe over `third_party\dll-win64\drag-lint.exe`.

- [ ] **Step 2: Build the BPLs (Win32 + Win64)**

Run:
```
cmd.exe /c "call \"...\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win32 src\delphi-plugin\dclDragLintWizard.dproj"
cmd.exe /c "call \"...\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win64 src\delphi-plugin\dclDragLintWizard.dproj"
```
Expected: both succeed; note the BPL output paths.

- [ ] **Step 3: Reindex everything (parallel)**

Run (uses the real machine config beside the engine):
`<Win64 EXE> index --all --jobs 0`
Expected: builds ORM3, Loader, SQL, working-set, `library-Win32`/`library-Win64`/..., AllProjects; prints per-section timing + a total. Verify each `.sqlite` exists and a sample query works:
`<Win64 EXE> query --name IIndexer --db <ORM3 or self DB>` -> 1 match.

- [ ] **Step 4: Update the IDE test plan**

Add a `## Manifest + Settings + Platform` section to `docs/TEST-PLAN-IDE-FULL.md`: edit `.drag-lint.json` beside the EXE; `index --all --dry-run` shows the plan; load the Win32 BPL in the 32-bit IDE; confirm hover/usages work with no `--db` (manifest-driven); switch active platform Win32<->Win64 and confirm the library DB swaps (reload event); switch active project and confirm DB selection per `currentProjectsIndexing`; open the graph tool with no `--db` and confirm it opens the manifest set.

- [ ] **Step 5: Full smoke + commit**

Run: `pwsh -File tests/autotest/run_manifest.ps1` and `pwsh -File tests/autotest/run_smoke.ps1`. Expected: PASS.
```bash
git add docs/TEST-PLAN-IDE-FULL.md
git commit -m "docs(index-manifest): IDE test-plan section + Win64-canonical rollout"
```
(Separately update `C:\Projects\CLAUDE.md` - outside the repo - and note it in the final report.)

---

## Self-Review

**Spec coverage:** config format/location (T1), settings block (T1,T7,T9), indexes schema (T1,T6), folder-tree vs closure (T4,T5), exclude/ignore precedence (T3,T4), dedup (T6), per-platform libs (T6,T7), consumer selection (T9,T10), reload events (T11 manual IDE test; engine determinism in T9), CLI surface incl. --jobs (T7,T8), bitness/Win64 canonical + BPLs (T0,T11), size guard (T9), parallel (T8), graph tool (T10), tests (T1-T9), deliverables BPL+reindex+test-plan (T11). All covered.

**Placeholders:** none - every task has concrete fixtures, assertions, commands, and contract code.

**Type consistency:** `TWalkFilter` defined in T4 (Interfaces) and reused in T6 plan + T7/T8 child; `TIndexManifest`/`TIndexSection` (T1) reused in T6/T9; `TDbSelect.Resolve` (T9) reused in T10; `selftest` subcommands (glob/files/closure/dbselect) consistently named.
