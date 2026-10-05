<#
  run_reports_text.ps1 -- build and run tests\reportstext\ReportTextTests.dpr (DUnitX).

  WHAT IT COVERS. DragLint.Plugin.ReportText is the IDE-free half of the
  drag-lint > Reports submenu: the question catalog, the DocInsight formatter
  that turns an Ask-Report.ps1 answer into a pasteable /// <remarks> block, and
  the parsers for typeat JSON, a DFM root object and the stale-index reindex
  commands. The IDE glue (DragLint.Plugin.Reports) is ToolsAPI-bound and is
  verified by clicking in a live IDE, not here.

  TWO-WAY CATALOG GUARD. After the tests pass, `ReportTextTests --ids` is
  compared against the ValidateSet of charts\src\New-DiagramArtifact.ps1. A
  question the script accepts with no menu item, or a menu item the script no
  longer accepts, fails the run -- either drift would otherwise be silent: the
  first is a missing feature nobody sees, the second a menu item that answers
  "unknown question" (exit 2) when clicked.

  Usage: pwsh -File tests\plugin\run_reports_text.ps1
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\reportstext\ReportTextTests.dpr",
  [string]$Bundler = "$PSScriptRoot\..\..\charts\src\New-DiagramArtifact.ps1",
  [string]$WorkDir = "$env:TEMP\drag-lint-reports-text-build-$PID"
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

# DUnitX ships with RAD Studio as precompiled units under lib\win64\release.
$DunitxLib = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release'
$bat = Join-Path $WorkDir 'build.bat'
$lines = @(
  '@echo off',
  ('call "{0}"' -f $rs),
  ('cd /d "{0}"' -f $DprDir),
  ('dcc64 -B -NSSystem;Winapi;Vcl -U"{3}" -E"{0}" -N0"{1}" {2}' -f $WorkDir, $DcuDir, $DprName, $DunitxLib),
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[System.IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)

$buildLog = Join-Path $WorkDir 'build.log'
$null = Start-Process cmd.exe -ArgumentList "/c","`"$bat`"" `
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

# ---- two-way catalog guard ----
$ids = @(& $exe --ids | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$valid = @((Get-Command (Resolve-Path $Bundler).Path).Parameters['Question'].Attributes |
           Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
           ForEach-Object { $_.ValidValues })
# positive control: an empty side would make both comparisons below vacuous
if ($ids.Count -eq 0 -or $valid.Count -eq 0) {
  Write-Host "FAIL: catalog guard read nothing (menu ids=$($ids.Count), ValidateSet=$($valid.Count))" -ForegroundColor Red; exit 1
}
$noMenu  = @($valid | Where-Object { $ids -notcontains $_ })
$unknown = @($ids | Where-Object { $valid -notcontains $_ })
if ($noMenu.Count -or $unknown.Count) {
  if ($noMenu.Count)  { Write-Host "FAIL: questions with no Reports menu item: $($noMenu -join ', ')" -ForegroundColor Red }
  if ($unknown.Count) { Write-Host "FAIL: menu items the script does not accept: $($unknown -join ', ')" -ForegroundColor Red }
  exit 1
}
Write-Host "catalog guard: $($ids.Count) menu questions = $($valid.Count) ValidateSet questions"
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  # this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d in @("$env:TEMP\drag-lint-reports-text-build-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
