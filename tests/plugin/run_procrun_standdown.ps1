<#
  run_procrun_standdown.ps1 -- build and run ProcRunStandDownTests.dpr (lane X-BT).

  WHAT IT COVERS. Owner ruling 2026-10-26: an IDE cycle-fix run has no time limit, and its Cancel
  must not hard-kill the engine in the middle of an --apply. RunCaptureStdout's AStandDownGraceMs
  sends the maintenance control channel's `shutdown` to the child (pipe named after its pid), keeps
  reading its output, and kills the tree only when the grace ends. The dpr is its own child, with a
  real TControlChannel (see the dpr header for S1-S4).

  RED: the harness does not compile against the pre-lane ProcRun (E2034 too many actual parameters:
  RunCaptureStdout has no AStandDownGraceMs) -- the weak compile-error RED of run_procrun_cancel.ps1;
  the mutation "RunCaptureStdout passes 0 for the grace" is the behavioural one (S1a-S1c, S2b-S2d,
  S3b fail; see the lane report).

  NOT dl:serial: it spawns only its own children, on pipes named after their own pids.

  Usage: pwsh -File tests\plugin\run_procrun_standdown.ps1
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\ProcRunStandDownTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-procrun-standdown-build-$PID"
)
try {
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
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\drag-lint-procrun-standdown-build-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
