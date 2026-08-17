<#
  run_ancestry_name_collision.ps1 -- build and run AncestryNameCollisionTests.dpr.

  A RECORD sharing a class's name must not decide an ancestry question.
  IsDescendantOf resolved through ResolveTypeSymbolId, which returns the FIRST
  class/interface/record match; library-Win32.sqlite holds three TTimer symbols
  and DosCommand.TTimer (a RECORD) sorts first, so the question was answered by
  the one candidate that could never say yes. Consumer symptom: an object-leak
  false positive on an owned `TTimer.Create(LDlg)` in DataCopy.

  Direct store calls, not a parsed fixture, because the defect is about the ORDER
  candidates come back in -- hand-built rows make the record precede the class
  deterministically. The assertions live in the .dpr; RED was confirmed by
  restoring the single-candidate lookup, where exactly the headline assertion
  fails and all three controls still pass.
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\AncestryNameCollisionTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-ancestry-collision"
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

# The engine units live in many folders; dcc64 needs them all on -U. Mirrors the
# CLI .dproj's DCC_UnitSearchPath.
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

# Run from the WorkDir: the test writes its scratch DB to a relative path.
Push-Location $WorkDir
try   { $out = & $exe 2>&1 | Out-String; $rc = $LASTEXITCODE }
finally { Pop-Location }
Write-Host $out.TrimEnd()

if ($rc -ne 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
if ($out -notmatch '(\d+) passed, 0 failed') {
  Write-Host 'FAIL: no pass/fail summary in output' -ForegroundColor Red; exit 1
}
Write-Host 'PASS' -ForegroundColor Green
exit 0
