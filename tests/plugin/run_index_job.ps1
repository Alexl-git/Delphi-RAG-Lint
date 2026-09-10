<#
  run_index_job.ps1 -- build and run IndexJobTests.dpr.

  WHAT IT COVERS. Tier 1 of PLAN-lint-tree: saving a unit refreshes its project
  index, so tiers 2 and 3 answer from current data. DragLint.Plugin.IndexJob is
  the whole of tier 1's decision -- one command line and one coalesce key --
  and SaveNotifier.AfterSave now enqueues that job instead of firing a detached
  per-file CreateProcessW.

  THREE SILENT FAILURES, one per assertion group:

   * `--rebuild` on save would re-parse the entire project AND, on that path
     only, stop the resident LSP first to release the FTS trigger lock -- so
     Ctrl+S would take the IDE's own diagnostics down. Case 1b is a NEGATIVE
     assertion and 1a is its haystack control.
   * a FILE target cannot see a newly added unit's closure, and a FOLDER target
     silently widens a project DB into a directory DB (measured 2026-09-02:
     DataCopy 39 -> 72 files, findings 393 -> 1123).
   * a key per FILE rather than per DATABASE means Save All on 30 units queues
     30 runs against one database.

  WHY THE INCREMENTAL FORM IS SAFE AT ALL -- B0(c), measured 2026-09-10 with
  two resident LSP drag-lint.exe children alive: a no-op pass 0.37 s, a
  one-file write 1.21 s, both exit 0, no `database is locked`. The 2026-09-09
  "RISK, UNMEASURED" note on tier 1 is retired by that run.

  WHY A COMPILED CONSOLE TEST: IndexJob has no ToolsAPI -- it is a separate
  unit precisely so the string is assertable without an IDE. The AfterSave
  wiring itself is IDE-bound and belongs to the O-block.

  RED BASELINE, MEASURED 2026-09-10 with the unit absent:

    IndexJobTests.dpr(33) Fatal: F1026 File not found:
      '..\src\delphi-plugin\DragLint.Plugin.IndexJob.pas'

  MUTATION RESULTS, MEASURED 2026-09-10 against the finished build, since a
  compile-error RED proves only that the unit is new:

    M1 the save becomes a --rebuild            -> 1b, 5a
    M2 the coalesce key keeps the path case    -> 4b
    M3 coalescing switched off (empty key)     -> 5b, 5d
    M4 --platform emitted even when unknown    -> 2a

  M2 is the least obvious and the most likely to be "tidied" away: Windows
  hands the same path back in whatever case it likes, so two saves in one
  project would otherwise queue two full reindexes that each look distinct.

  GREEN: 17 passed, 0 failed, ~10 s (compile-dominated).

  Usage: pwsh -File tests\plugin\run_index_job.ps1
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\IndexJobTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-index-job-build"
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
$Dpr     = (Resolve-Path $Dpr).Path
$DprDir  = Split-Path $Dpr -Parent
$DprName = Split-Path $Dpr -Leaf

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$DcuDir = Join-Path $WorkDir 'dcu'
New-Item -ItemType Directory $DcuDir | Out-Null

# dcc64 refuses to create output into a directory that does not exist (F2039),
# hence both are made above rather than relying on the compiler to do it.
$bat = Join-Path $WorkDir 'build.bat'
$lines = @(
  '@echo off',
  ('call "{0}"' -f $rs),
  ('cd /d "{0}"' -f $DprDir),
  ('dcc64 -B -E"{0}" -N0"{1}" {2}' -f $WorkDir, $DcuDir, $DprName),
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[System.IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)

$buildLog = Join-Path $WorkDir 'build.log'
$p = Start-Process cmd.exe -ArgumentList "/c","`"$bat`"" `
       -RedirectStandardOutput $buildLog -RedirectStandardError "$buildLog.err" `
       -NoNewWindow -Wait -PassThru
$buildOut = Get-Content $buildLog -Raw
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FATAL: compile failed' -ForegroundColor Red
  Write-Host $buildOut
  exit 2
}

$exe = Join-Path $WorkDir ([System.IO.Path]::GetFileNameWithoutExtension($DprName) + '.exe')
if (-not (Test-Path $exe)) { Write-Host "FATAL: exe not produced: $exe" -ForegroundColor Red; exit 2 }

$out = & $exe 2>&1 | Out-String
$rc  = $LASTEXITCODE
Write-Host $out.TrimEnd()

if ($rc -ne 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
if ($out -notmatch '(\d+) passed, 0 failed') {
  # A run that printed nothing would otherwise sail through on exit 0.
  Write-Host 'FAIL: no pass/fail summary in output' -ForegroundColor Red; exit 1
}
Write-Host 'PASS' -ForegroundColor Green
exit 0
