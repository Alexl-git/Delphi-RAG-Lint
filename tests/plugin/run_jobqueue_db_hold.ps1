<#
  run_jobqueue_db_hold.ps1 -- build and run JobQueueDbHoldTests.dpr (C12 ask N6).

  While the conversion editor child lives, TDragLintJobQueue holds jkReindex /
  jkLintAll jobs whose --db is the launched project's DB; other jobs run. A queue
  predicate, not the engine-hold sentinel, so -- unlike run_jobqueue_hold.ps1 -- this
  runner never writes or clears the per-user hold and needs no dl:serial.

  RED, measured 2026-11-08 on base b036f2cb: COMPILE ERROR E2003 undeclared identifier
  'JobDbArg' (the hold did not exist). GREEN after the fix: 12 passed, 0 failed.

  Usage: pwsh -File tests\plugin\run_jobqueue_db_hold.ps1
#>
[CmdletBinding()]
param(
  [string]$Dpr     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-jobqueue-dbhold-build-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
# H01-AUTOWRAP (v152 DDFIX5): the work dir is removed in the finally below; DL_KEEP_WORKDIR=1 keeps it.
. (Join-Path $PSScriptRoot '..\autotest\lib\WorkDirCleanup.ps1')
$script:RunStart = (Get-Date).AddSeconds(-2)
try {
if (-not $Dpr) { $Dpr = "$PSScriptRoot\..\JobQueueDbHoldTests.dpr" }
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
$Dpr     = (Resolve-Path $Dpr).Path
$DprDir  = Split-Path $Dpr -Parent
$DprName = Split-Path $Dpr -Leaf

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }

$DcuDir = Join-Path $WorkDir 'dcu'
[System.IO.Directory]::CreateDirectory($DcuDir) | Out-Null

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
Start-Process cmd.exe -ArgumentList "/c","`"$bat`"" `
  -RedirectStandardOutput $buildLog -RedirectStandardError "$buildLog.err" `
  -NoNewWindow -Wait | Out-Null
$buildOut = Get-Content $buildLog -Raw
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FATAL: compile failed' -ForegroundColor Red
  ($buildOut -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal|BUILD_EXITCODE' } | ForEach-Object { Write-Host $_ }
  exit 2
}

$exe = Join-Path $WorkDir ([System.IO.Path]::GetFileNameWithoutExtension($DprName) + '.exe')
if (-not (Test-Path $exe)) { Write-Host "FATAL: exe not produced: $exe" -ForegroundColor Red; exit 2 }

$out = & { $ErrorActionPreference = 'Continue'; & $exe 2>&1 | ForEach-Object { "$_" } } | Out-String
$rc  = $LASTEXITCODE
Write-Host $out.TrimEnd()

try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { }

if ($rc -ne 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
if ($out -notmatch '(\d+) passed, 0 failed') {
  Write-Host 'FAIL: no pass/fail summary in output' -ForegroundColor Red; exit 1
}
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1')
  # the test program's own scratch: TPath.GetTempPath\drag-lint-jobqueue-dbhold-<its pid> (JobQueueDbHoldTests.dpr)
  Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'drag-lint-jobqueue-dbhold-*' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^drag-lint-jobqueue-dbhold-\d+$' -and $_.CreationTime -ge $script:RunStart } |
    ForEach-Object { Remove-WorkDir $_.FullName -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
}
