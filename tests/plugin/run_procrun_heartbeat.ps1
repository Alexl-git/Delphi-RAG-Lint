<#
  run_procrun_heartbeat.ps1 -- build and run ProcRunHeartbeatTests.dpr (1.40 lane beat).

  WHAT IT COVERS. Owner design 2026-11-01: the plugin kills an engine child only on NO PROGRESS, and
  once the child answers a heartbeat (DRagLint.Core.ControlChannel: BeatChannelOpen / RequestEngineBeat)
  progress means its STATUS changing. A frozen status for the stall budget = stuck (killed even while the
  CPU spins); an advancing status = slow (kept, even while silent and idle). A child with no heartbeat is
  judged by the pre-1.40 output/CPU rule. The dpr is its own child (see its header for H1-H5).

  RED: -Defines BASE_PROCRUN builds the harness against the pre-lane ProcRun (H5 compiled out, it calls
  the new ProcRunBeatText): H1a, H1b, H2a, H2b fail, H3 and H4 pass.

  NOT dl:serial: it spawns only its own children, on pipes named after their own pids.

  Usage: pwsh -File tests\plugin\run_procrun_heartbeat.ps1 [-Defines BASE_PROCRUN]
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\ProcRunHeartbeatTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-procrun-heartbeat-build-$PID",
  [string]$Defines = ''
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
  ('dcc64 -B {3} -E"{0}" -N0"{1}" {2}' -f $WorkDir, $DcuDir, $DprName, $(if ($Defines) { '-D' + $Defines } else { '' })),
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
  foreach ($d23 in @("$env:TEMP\drag-lint-procrun-heartbeat-build-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
