# dproj/dpr Reconciler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `reconcile-project` CLI command that makes a Delphi `.dpr`/`.dproj` member list honest -- adds used-but-unlisted project-local units, reports unused members, and loudly flags stale (old-version) units still pulled in via `uses`.

**Architecture:** A new unit `DRagLint.Index.Reconcile.pas` (`TProjectReconciler`) reuses the existing `TClosureResolver` (compile closure + using-unit), `TGlob` (stale matching), `TProjectResolver` (library roots), and `TManifestIO` (exclude globs). `Analyze` is read-only and returns Missing/Extra/Stale sets; `Apply` edits the `.dpr` `uses` clause and `.dproj` `<DCCReference>` ItemGroup (with `.bak` backups). The CLI command is dry-run by default, `--apply` to write.

**Tech Stack:** Delphi 13, Object Pascal, `System.RegularExpressions`/string ops for `.dpr`/`.dproj` text edits, msbuild, PowerShell smoke tests.

**Spec:** `docs/superpowers/specs/2026-06-15-dpr-reconciler-design.md`
**Branch:** `feat/index-manifest`. **Engine:** Win64; rebuild `cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win64 drag-lint.dproj"` then copy `src\cli\Win64\Debug\drag-lint.exe` over `third_party\dll-win64\drag-lint.exe`. Test exe at `src\cli\Win64\Debug\drag-lint.exe`.
**Conventions:** `.pas` 7-bit ASCII + CRLF; DocInsight `///` on public surface; register new unit in BOTH `src/cli/drag-lint.dpr` and `drag-lint.dproj`; `try-finally` for owned objects.

---

## File Structure
- Create `src/index/DRagLint.Index.Reconcile.pas` -- `TReconcileItem`, `TReconcileResult`, `TProjectReconciler` (`Analyze`, `Apply`).
- Create `tests/fixtures/reconcile/` -- a small project that exhibits Missing, Extra, and Stale.
- Create `tests/autotest/run_reconcile.ps1` -- smoke test.
- Modify `src/cli/DRagLint.CLI.pas` -- `DoReconcileProject` + `reconcile-project` dispatch + `PrintHelp` line.
- Modify `src/cli/drag-lint.dpr` + `drag-lint.dproj` -- register the unit.

---

## Task 1: Analyze + dry-run report (read-only)

**Files:**
- Create: `src/index/DRagLint.Index.Reconcile.pas`
- Create: `tests/fixtures/reconcile/` (files below)
- Create: `tests/autotest/run_reconcile.ps1`
- Modify: `src/cli/DRagLint.CLI.pas`, `src/cli/drag-lint.dpr`, `drag-lint.dproj`

- [ ] **Step 1: Create the fixture project**

`tests/fixtures/reconcile/App.dpr`:
```
program App;

uses
  uMain in 'uMain.pas';

begin
end.
```
`tests/fixtures/reconcile/uMain.pas`:
```
unit uMain;
interface
uses uHelper;
implementation
end.
```
`tests/fixtures/reconcile/uHelper.pas`:
```
unit uHelper;
interface
implementation
uses uFoo_OLD_20230828;
end.
```
`tests/fixtures/reconcile/uFoo_OLD_20230828.pas`:
```
unit uFoo_OLD_20230828;
interface
implementation
end.
```
`tests/fixtures/reconcile/uOrphan.pas`:
```
unit uOrphan;
interface
implementation
end.
```
`tests/fixtures/reconcile/App.dproj` (minimal; the DCCReference ItemGroup is what matters):
```
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup>
    <DCCReference Include="uMain.pas"/>
    <DCCReference Include="uOrphan.pas"/>
  </ItemGroup>
</Project>
```
(Closure of App.dpr = uMain -> uHelper -> uFoo_OLD_20230828. Listed = uMain (dpr+dproj) + uOrphan (dproj). So: Missing = uHelper, uFoo_OLD_20230828; Extra = uOrphan; Stale = uFoo_OLD_20230828 used by uHelper.)
Note: the repo `.gitignore` may match `*_OLD*` -- use `git add -f` for `uFoo_OLD_20230828.pas` if needed.

- [ ] **Step 2: Declare the public API** in `src/index/DRagLint.Index.Reconcile.pas`:
```pascal
type
  TReconcileItem = record
    UnitName: string;
    FilePath: string;    // absolute
    RelPath:  string;    // relative to the project dir (POSIX-or-Windows sep as written)
    UsedBy:   string;    // the using unit ('' for project-direct)
  end;
  TReconcileResult = record
    Missing: TArray<TReconcileItem>;  // used (in closure) but not listed
    Extra:   TArray<TReconcileItem>;  // listed but not reached via closure
    Stale:   TArray<TReconcileItem>;  // used unit whose name matches a stale rule
  end;
  TProjectReconciler = class
  public
    /// <summary>ALibraryRoots = registry library folders (closure exclusion).
    /// AStaleGlobs = extra stale patterns (e.g. manifest excludes) on top of
    /// the built-in heuristics.</summary>
    constructor Create(const ALibraryRoots, AStaleGlobs: TArray<string>);
    /// <summary>Read-only: compute Missing/Extra/Stale for a .dpr/.dproj.</summary>
    function Analyze(const AProjectFile: string): TReconcileResult;
    /// <summary>Apply Missing additions to the .dpr + .dproj after .bak backup.</summary>
    procedure Apply(const AProjectFile: string; const AResult: TReconcileResult);
  end;

/// <summary>True if a file base name looks stale (built-in heuristics).</summary>
function IsStaleName(const AFileName: string; const AExtraGlobs: TArray<string>): Boolean;
```

- [ ] **Step 3: Write the failing smoke test** `tests/autotest/run_reconcile.ps1`:
```powershell
. "$PSScriptRoot\_manifest_common.ps1"
$fx = "$PSScriptRoot\..\fixtures\reconcile"
$rep = & $Exe reconcile-project "$fx\App.dpr" 2>&1 | Out-String
Check 'reconcile exits 0'        ($LASTEXITCODE -eq 0)
Check 'missing uHelper'          ($rep -match 'MISSING[\s\S]*uHelper')
Check 'missing uFoo_OLD'         ($rep -match 'MISSING[\s\S]*uFoo_OLD_20230828')
Check 'extra uOrphan'            ($rep -match 'EXTRA[\s\S]*uOrphan')
Check 'stale uFoo_OLD'           ($rep -match 'STALE[\s\S]*uFoo_OLD_20230828')
Check 'stale names using unit'   ($rep -match 'uFoo_OLD_20230828.*uHelper')
Check 'dry-run wrote nothing'    (-not (Test-Path "$fx\App.dpr.bak"))
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```
`_manifest_common.ps1` defines `$Exe` (returned) + `Check`; dot-source it and capture `$Exe` (it `return`s the path -- assign: `$Exe = . "$PSScriptRoot\_manifest_common.ps1"` if needed; follow the pattern used in `run_manifest.ps1`).

- [ ] **Step 4: Run -> FAIL** (`reconcile-project` not implemented).
Run: `pwsh -File tests/autotest/run_reconcile.ps1` -> FAIL.

- [ ] **Step 5: Implement `IsStaleName` + `Analyze` + the CLI dry-run command.**
- `IsStaleName`: base name matches any of (case-insensitive, via `TGlob.Matches`): `*_OLD*`, `* - Copy*`, `*-Copy*`, `*BACKUP*`, `*-bad*`, `*_20######*` (six digits), OR any `AExtraGlobs`.
- `Analyze`:
  1. `Closure := TClosureResolver.Create(FLibraryRoots).Resolve(AProjectFile, [])` -> closure files (+ you may need the using-unit; if `TClosureResult` doesn't already expose per-file using-unit, derive "used by" from a second pass or extend the closure result minimally -- see note). Build a map file->usingUnit.
  2. Parse listed members: `.dpr` `uses` units (reuse the closure unit's `ParseDprUses` approach or a local parse) + `.dproj` `<DCCReference Include="...pas">`. Resolve each to an absolute path.
  3. Missing = closure files not in listed (by abs path, case-insensitive). Extra = listed files not in closure. Stale = closure files whose base name `IsStaleName`. Fill `RelPath` (relative to project dir) and `UsedBy`.
- CLI `DoReconcileProject`: get library roots (`TProjectResolver.ResolveLibraryPaths`), stale globs (manifest `indexes.exclude` via `TManifestIO.Load`/`--config` if found, else `[]`), run `Analyze`, print the report:
```
MISSING (N) - used but not listed (will be added with --apply):
  <unit> -> <relpath>   (used by <UsedBy>)
EXTRA (N) - listed but never reached via uses (review):
  <unit> -> <relpath>
STALE (N) - used but looks stale (investigate):
  <unit> -> <relpath>   (used by <UsedBy>)
Run a full project build to verify after --apply.
```
Register `reconcile-project` in the `Run` dispatch + `PrintHelp`. Register the new unit in `.dpr` + `.dproj`.

> Note on using-unit: if `TClosureResolver` already records the using-unit per file (it does for warnings), reuse it; otherwise add a parallel `TArray` of using-units to `TClosureResult` or expose a helper. Keep the change minimal and documented.

- [ ] **Step 6: Build Win64 + run -> PASS.** `pwsh -File tests/autotest/run_reconcile.ps1` -> PASS. Also `pwsh -File tests/autotest/run_manifest.ps1` + `run_formsmap.ps1` -> still PASS.

- [ ] **Step 7: Commit**
```bash
git add src/index/DRagLint.Index.Reconcile.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dpr drag-lint.dproj tests/fixtures/reconcile tests/autotest/run_reconcile.ps1
git commit -m "feat(reconciler): analyze .dpr/.dproj -> missing/extra/stale (dry-run report)"
```

---

## Task 2: `--apply` (edit .dpr + .dproj with backups)

**Files:** Modify `src/index/DRagLint.Index.Reconcile.pas`, `src/cli/DRagLint.CLI.pas`, `tests/autotest/run_reconcile.ps1`

- [ ] **Step 1: Add the `--apply` assertions** to `run_reconcile.ps1` (after the dry-run checks, before the final block). Copy the fixture to a temp dir first so the test is repeatable and doesn't dirty the repo fixture:
```powershell
$work = "$env:TEMP\drag-lint-reconcile"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
Copy-Item -Recurse $fx $work
& $Exe reconcile-project "$work\App.dpr" --apply 2>&1 | Out-Null
Check 'apply exits 0'         ($LASTEXITCODE -eq 0)
Check 'dpr backup made'       (Test-Path "$work\App.dpr.bak")
Check 'dproj backup made'     (Test-Path "$work\App.dproj.bak")
$dpr = Get-Content "$work\App.dpr" -Raw
Check 'dpr now has uHelper'   ($dpr -match 'uHelper\s+in\s+''uHelper\.pas''')
Check 'dpr now has uFoo_OLD'  ($dpr -match 'uFoo_OLD_20230828\s+in\s+''uFoo_OLD_20230828\.pas''')
$dproj = Get-Content "$work\App.dproj" -Raw
Check 'dproj has uHelper ref' ($dproj -match 'DCCReference Include="uHelper\.pas"')
$rep2 = & $Exe reconcile-project "$work\App.dpr" 2>&1 | Out-String
Check 'reapply 0 missing'     ($rep2 -match 'MISSING \(0\)')
Check 'uOrphan untouched'     ($rep2 -match 'EXTRA[\s\S]*uOrphan')
```

- [ ] **Step 2: Run -> FAIL** (`--apply` not implemented).

- [ ] **Step 3: Implement `Apply` + `--apply` flag.**
- Add `--apply` parse -> `TArgs.Apply` (bool). In `DoReconcileProject`, when set, call `Reconciler.Apply(projectFile, result)` after printing the report.
- `Apply`:
  - Back up: copy `App.dpr`->`App.dpr.bak`, `App.dproj`->`App.dproj.bak` (overwrite existing .bak).
  - `.dpr` edit: locate the program/library `uses` clause (first `\buses\b` ... `;`). Insert each Missing item before the closing `;` as `,\r\n  <Unit> in '<RelPath>'` (preserve the existing leading indent; if the clause is single-line, keep it readable). Ensure no duplicate if already present.
  - `.dproj` edit: find the `ItemGroup` that already contains `<DCCReference`; insert `\r\n    <DCCReference Include="<RelPath>"/>` before that ItemGroup's `</ItemGroup>`. If no DCCReference ItemGroup exists, create one before `</Project>`.
  - `RelPath` uses backslashes relative to the project dir.
  - Write files as the original encoding (read as text, write back; keep CRLF).

- [ ] **Step 4: Build + run -> PASS** (`run_reconcile.ps1` all pass; `run_manifest.ps1` + `run_formsmap.ps1` still pass).

- [ ] **Step 5: Commit**
```bash
git add src/index/DRagLint.Index.Reconcile.pas src/cli/DRagLint.CLI.pas tests/autotest/run_reconcile.ps1
git commit -m "feat(reconciler): --apply edits .dpr uses + .dproj DCCReference with .bak backups"
```

---

## Task 3: `--json` output + help + real-project smoke

**Files:** Modify `src/cli/DRagLint.CLI.pas`, `tests/autotest/run_reconcile.ps1`

- [ ] **Step 1: Add `--json` assertion** to `run_reconcile.ps1`:
```powershell
$j = & $Exe reconcile-project "$fx\App.dpr" --json 2>&1 | Out-String
Check 'json has missing array' ($j -match '"missing"\s*:\s*\[')
Check 'json has stale array'   ($j -match '"stale"\s*:\s*\[')
Check 'json parses'            ({ $null = $j | ConvertFrom-Json; $true } | ForEach-Object { $_ })
```

- [ ] **Step 2: Run -> FAIL** (`--json` not implemented for this command).

- [ ] **Step 3: Implement `--json`** in `DoReconcileProject`: when `AArgs.AsJson`, emit `{ "missing":[{unit,file,usedBy}], "extra":[...], "stale":[...] }` instead of the text report (build with `System.JSON`, free the object). Add a `PrintHelp` line: `drag-lint reconcile-project <App.dpr|.dproj> [--apply] [--json] [--config <path>]  - sync project member list; flag stale used units`.

- [ ] **Step 4: Build + run -> PASS** (all three smoke suites green).

- [ ] **Step 5: Real-project smoke (manual confirter, not asserted):** run `drag-lint reconcile-project C:\Projects\Loader2019\Loader2025.dproj` (dry-run) and eyeball the report -- it should list any used-but-unlisted units and flag stale ones (e.g. `*_OLD_*`, `* - Copy*`). Do NOT `--apply` on the real project. Capture the output in the commit message or report.

- [ ] **Step 6: Commit**
```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_reconcile.ps1
git commit -m "feat(reconciler): --json output + help; reconcile-project complete"
```

---

## Self-Review
**Spec coverage:** command+flags (T1,T2,T3); Analyze missing/extra/stale (T1); stale heuristics+manifest globs (T1 `IsStaleName`); using-unit attribution (T1); Apply edits .dpr+.dproj+.bak, never removes (T2); re-run 0 missing (T2); --json (T3); dry-run default (T1); testing fixture (T1). All covered.
**Placeholders:** none -- fixtures, code, assertions, commands all concrete. The one "Note on using-unit" is a real implementation choice with a concrete fallback, not a placeholder.
**Type consistency:** `TReconcileItem`/`TReconcileResult` (Missing/Extra/Stale) and `TProjectReconciler.Analyze`/`Apply` used consistently T1->T3; `IsStaleName` signature stable; `--apply`->`TArgs.Apply`, `--json`->existing `TArgs.AsJson`.
