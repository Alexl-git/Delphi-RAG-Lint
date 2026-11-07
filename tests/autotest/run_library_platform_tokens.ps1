<#
  run_library_platform_tokens.ps1 -- build and run tests\LibraryPlatformTests.dpr: a non-Windows dproj / fingerprint
  platform is honoured by LibraryReady.ChooseLibraryPlatform instead of silently falling to the Win32 manifest default (L-C20).
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\LibraryPlatformTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-library-platform-tokens-$PID"
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
             'workspace','analysis','cli') | ForEach-Object { "..\src\$_" }
$srcDirs += '..\third_party\delphi-tree-sitter'
$U = ($srcDirs -join ';')

$bat = Join-Path $WorkDir 'build.bat'
$lines = @(
  '@echo off',
  ('call "{0}"' -f $rs),
  ('cd /d "{0}"' -f $DprDir),
  ('dcc64 -B -NSSystem;System.Win;Winapi;Data;Data.Win -U"{0}" -E"{1}" -N0"{2}" {3}' -f $U, $WorkDir, $DcuDir, $DprName),
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
Get-ChildItem (Join-Path $PSScriptRoot '..\..\third_party\dll-win64') -Filter '*.dll' -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName $WorkDir -Force }
& $exe
$rc = $LASTEXITCODE
if ($rc -eq 0) { Write-Host 'PASS' -ForegroundColor Green } else { Write-Host 'FAIL' -ForegroundColor Red }
exit $rc
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\drag-lint-library-platform-tokens-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
