<#
  run_purity_model.ps1 -- build and run tests\PurityModelTests.dpr, the
  database-free test of DRagLint.Analysis.Purity: the effect-summary lattice,
  the purity axioms and built-in table, the call-argument lexer, the body
  scanner, the escape classifier and callee translation (spec
  docs\superpowers\specs\2026-09-15-interprocedural-purity.md sections 3, 5.3
  and 7.3).

  Same dcc64 recipe as run_forward_stub_pairing.ps1; a regression in the MODEL
  is reported here as a named case rather than as a changed count over a
  fixture database.
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\PurityModelTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-purity-model"
)
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
