<#
  run_procrun_cancel.ps1 -- build and run ProcRunCancelTests.dpr.

  WHAT IT COVERS. DragLint.Plugin.ProcRun grew a cancellable spawn so the
  fan-out worker (PLAN-lint-tree P3) can abandon a tier-2 run that a newer
  keystroke superseded. B0(b) measured ~26 s/MB for parse+extract+store, which
  makes supersession the NORMAL path for the largest ~1% of ORM3 CLIENT units
  (~6.2 s at p99, ~24.0 s at the largest) rather than an edge case.

  WHY A COMPILED CONSOLE TEST rather than an exe-driven autotest: ProcRun.pas
  uses Winapi.Windows and System.SysUtils and nothing else -- no OTA, no VCL --
  so it links and runs with no IDE. The design-time BPL cannot be rebuilt while
  RAD Studio is open, so in-IDE behaviour stays unverified either way, but none
  of the behaviour under test needs an IDE. Same recipe as
  run_jobqueue_hold.ps1 / run_codelens_cache_lru.ps1.

  RED BASELINE, MEASURED 2026-09-10 against HEAD's ProcRun.pas (6e47989) with
  the dpr compiled against a pristine copy of that unit:

    COMPILE ERROR, E2003 undeclared identifier 'RunCaptureStdoutCancellable'
    (first of five: also PROCRUN_KILLED_EXIT_CODE, CloseProcessHandle,
    KillProcess).

  That is the RED the plan specified for this row, and it is the same shape as
  run_jobqueue_hold.ps1's row 7: a compile error counts as RED when the whole
  point of the change is that the identifier does not exist yet.

  A COMPILE-ERROR RED IS A WEAK RED -- it cannot tell a correct implementation
  from a wrong one -- so each of the four design decisions was MUTATION-TESTED
  against the finished build instead. Measured 2026-09-10:

    M1 publish the handle AFTER the blocking read (undoes decision 2)
         -> 9 passed, 9 failed; 2a first, then the whole cancellation chain,
            because with no handle there is nothing to cancel.
    M2 KillProcess returns without waiting (undoes decision 4)
         -> 16 passed, 2 failed: 3c and 3d, and NOTHING else.
    M3 the spawner closes the published handle (undoes decision 3)
         -> 16 passed, 2 failed: 1c and 7b.

  M2 IS THE ONE WORTH READING. The assertion written to catch it -- 3b, "the
  process is gone the instant KillProcess returns" -- did NOT catch it. A
  ping.exe tears down faster than the check can observe, so 3b passed a race it
  happened to win, and the first mutation run came back 16/0 GREEN against a
  KillProcess with no wait in it at all. 3c/3d were then built to make the
  difference observable rather than hoped for: they kill through a
  SYNCHRONIZE-only handle, which cannot terminate, so the child stays alive and
  only an implementation that really waits can report the failure. 3b is kept,
  and its comment in the dpr says plainly that it is not the discriminator.

  GREEN after the change: 18 passed, 0 failed, ~60 s (dominated by the pings
  and the deliberate 400 ms wait budget in 3d).

  NOT dl:serial. It spawns only its own ping.exe children, holds no sentinel
  and touches no database, so a neighbour cannot invalidate it. It does assert
  on process PRIORITY, which is read back from the child's own handle rather
  than from any global state.

  Usage: pwsh -File tests\plugin\run_procrun_cancel.ps1
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\ProcRunCancelTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-procrun-cancel-build"
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
