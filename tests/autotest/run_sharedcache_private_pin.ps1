<#
  run_sharedcache_private_pin.ps1 -- build and run tests\SharedCachePinTests.dpr,
  the pin for ruling R22: every drag-lint connection opens a PRIVATE SQLite
  cache (SharedCache=False in DRagLint.Storage.FileMembership.ConnectReadOnly /
  ConnectWriter). The parameter was documented as UNPINNED by any test.

  The dpr carries its own positive control: the same shape with
  SharedCache=True must FAIL the insert, or the harness cannot see the defect.
  Proven RED against the production code on 2026-09-28 by flipping ConnectWriter's
  parameter to True: T1 failed with SQLITE_LOCKED (recorded in the commit).
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\SharedCachePinTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-sharedcache-pin-$PID"
)
try {
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
$Dpr     = (Resolve-Path $Dpr).Path
$DprDir  = Split-Path $Dpr -Parent
$DprName = Split-Path $Dpr -Leaf

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$DcuDir = Join-Path $WorkDir 'dcu'
New-Item -ItemType Directory $DcuDir | Out-Null

# The engine units live in many folders; dcc64 needs them all on -U. Mirrors the
# CLI .dproj's DCC_UnitSearchPath (same list as run_ancestry_name_collision.ps1).
$srcDirs = @('preprocess','core','context','diagnostics','doc','forms','index','lint','lsp','mcp',
             'output','parser','project','query','refactor','report','resolver','sql','storage',
             'workspace','analysis') | ForEach-Object { "..\src\$_" }
$srcDirs += '..\third_party\delphi-tree-sitter'
$U = ($srcDirs -join ';')

$bat = Join-Path $WorkDir 'build.bat'
$lines = @(
  '@echo off',
  ('call "{0}"' -f $rs),
  ('cd /d "{0}"' -f $DprDir),
  ('dcc64 -B -U"{0}" -E"{1}" -N0"{2}" {3}' -f $U, $WorkDir, $DcuDir, $DprName),
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[System.IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)

$buildLog = Join-Path $WorkDir 'build.log'
Start-Process cmd.exe -ArgumentList "/c","`"$bat`"" `
  -RedirectStandardOutput $buildLog -RedirectStandardError "$buildLog.err" -NoNewWindow -Wait | Out-Null
$buildOut = Get-Content $buildLog -Raw
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FATAL: compile failed' -ForegroundColor Red
  Write-Host $buildOut
  exit 2
}

$exe = Join-Path $WorkDir ([IO.Path]::GetFileNameWithoutExtension($DprName) + '.exe')
if (-not (Test-Path $exe)) { Write-Host "FATAL: built exe missing: $exe" -ForegroundColor Red; exit 2 }
& $exe
$rc = $LASTEXITCODE
if ($rc -eq 0) { Write-Host 'PASS' -ForegroundColor Green } else { Write-Host 'FAIL' -ForegroundColor Red }
exit $rc
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\drag-lint-sharedcache-pin-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
