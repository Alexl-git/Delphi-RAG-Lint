<#
  run_verify_index_tests.ps1 -- build and run tests\VerifyIndexTests.dpr, the pure tests of
  DRagLint.CLI.VerifyIndex (verify-index, 1.53.0 LSP1-VERB). No process, no DB.
  Exit 0 = all PASS, 1 = a test failed, 2 = the build failed.
#>
[CmdletBinding()]
param(
  [string]$Dpr     = '',
  [string]$WorkDir = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Dpr) { $Dpr = Join-Path $PSScriptRoot '..\VerifyIndexTests.dpr' }
if (-not $WorkDir) { $WorkDir = Join-Path $env:TEMP "drag-lint-verify-index-tests-$PID" }
if (-not (Test-Path $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
$Dpr     = (Resolve-Path $Dpr).Path
$DprName = Split-Path $Dpr -Leaf
$Base    = [IO.Path]::GetFileNameWithoutExtension($DprName)
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }
$rc = 2
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null
  $DcuDir = Join-Path $WorkDir 'dcu'
  New-Item -ItemType Directory $DcuDir | Out-Null
  # The engine units live in many (nested) folders and the list is too long for one command line:
  # a .cfg beside a COPY of the dpr carries the search path.
  $SrcRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\src')).Path
  $dirs = @(Get-ChildItem $SrcRoot -Directory -Recurse | ForEach-Object { $_.FullName })
  $dirs += (Resolve-Path (Join-Path $PSScriptRoot '..\..\third_party\delphi-tree-sitter')).Path
  Copy-Item $Dpr (Join-Path $WorkDir $DprName)
  $cfg = @('-NSSystem;Winapi;System.Win;Data;Data.Win', ('-U"{0}"' -f ($dirs -join ';')), ('-E"{0}"' -f $WorkDir), ('-N0"{0}"' -f $DcuDir))
  [IO.File]::WriteAllText((Join-Path $WorkDir "$Base.cfg"), (($cfg -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $bat = Join-Path $WorkDir 'build.bat'
  $lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f $WorkDir), ('dcc64 -B {0}' -f $DprName), 'echo BUILD_EXITCODE=%ERRORLEVEL%')
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $buildLog = Join-Path $WorkDir 'build.log'
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $buildLog -RedirectStandardError "$buildLog.err" -NoNewWindow -Wait | Out-Null
  $buildOut = Get-Content $buildLog -Raw
  if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
    Write-Host 'FATAL: compile failed' -ForegroundColor Red
    ($buildOut -split "`n" | Select-String 'Fatal|Error' | Select-Object -First 10) | ForEach-Object { Write-Host $_ }
    exit 2
  }
  $exe = Join-Path $WorkDir "$Base.exe"
  if (-not (Test-Path $exe)) { Write-Host "FATAL: built exe missing: $exe" -ForegroundColor Red; exit 2 }
  # the engine units import the tree-sitter / SQLite DLLs at load time
  Get-ChildItem (Join-Path $PSScriptRoot '..\..\third_party\dll-win64') -Filter *.dll | Copy-Item -Destination $WorkDir
  & $exe
  $rc = $LASTEXITCODE
  if ($rc -eq 0) { Write-Host 'PASS' -ForegroundColor Green } else { Write-Host 'FAIL' -ForegroundColor Red }
} finally {
  if ((-not $env:DL_KEEP_WORK) -and (Test-Path -LiteralPath $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
exit $rc