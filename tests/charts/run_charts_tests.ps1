<#
  run_charts_tests.ps1 -- build and run tests\charts\ChartsTests.dpr (DUnitX) with dcc64.

  WHAT IT COVERS. The engine-side charts units under src\charts (diff core, report
  adapters, compare, renderers). Engine units need the CLI's unit search path and
  namespaces (FireDAC, Storage, TreeSitter) and the tree-sitter DLLs beside the exe:
  both come from tests\autotest\lib\CliBuildPaths.ps1, which READS them from
  src\cli\drag-lint.dproj so this list cannot drift from the CLI's.

  Usage: pwsh -File tests\charts\run_charts_tests.ps1 [-Filter <fixture name prefix>]
         e.g. -Filter ChartsTests.Diff  (DUnitX TNameFilter: prefix of the fixture's full name)
  Exit:  0 pass, 1 test failure, 2 build failure or crash.
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\ChartsTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-charts-tests-$PID",
  [string]$Filter  = ''
)
try {
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\autotest\lib\CliBuildPaths.ps1')

if (-not (Test-Path $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
$Dpr     = (Resolve-Path $Dpr).Path
$DprDir  = Split-Path $Dpr -Parent
$DprName = Split-Path $Dpr -Leaf

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$DcuDir = Join-Path $WorkDir 'dcu'
New-Item -ItemType Directory $DcuDir -Force | Out-Null

# DUnitX ships with RAD Studio as precompiled units under lib\win64\release. It goes INTO the
# one -U list (a second -U switch would replace the CLI's list, not extend it).
$DunitxLib = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release'
$cli = Get-CliDcc64Args
$uArg = '-U"{0}"' -f ((@($DunitxLib) + $cli.SearchDirs) -join ';')
$bat = Join-Path $WorkDir 'build.bat'
$lines = @(
  '@echo off',
  ('call "{0}"' -f $rs),
  ('cd /d "{0}"' -f $DprDir),
  ('dcc64 -B -NU"{1}" -E"{0}" {3} {4} {2}' -f $WorkDir, $DcuDir, $DprName, $uArg, $cli.NSArg),
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

$buildLog = Join-Path $WorkDir 'build.log'
$null = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" `
       -RedirectStandardOutput $buildLog -RedirectStandardError "$buildLog.err" `
       -NoNewWindow -Wait -PassThru
$buildOut = Get-Content $buildLog -Raw
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FATAL: compile failed' -ForegroundColor Red
  Write-Host $buildOut
  exit 2
}

$exe = Join-Path $WorkDir ([IO.Path]::GetFileNameWithoutExtension($DprName) + '.exe')
if (-not (Test-Path $exe)) { Write-Host "FATAL: exe not produced: $exe" -ForegroundColor Red; exit 2 }
$null = Copy-TreeSitterDlls -Dest $WorkDir

$runArgs = @()
if ($Filter) { $runArgs = @('--filter', $Filter) }
$out = & $exe @runArgs 2>&1 | Out-String
$rc  = $LASTEXITCODE
Write-Host $out.TrimEnd()
if ($rc -ne 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
if ($out -notmatch '(\d+) passed, 0 failed') {
  # A run that printed nothing would otherwise sail through on exit 0.
  Write-Host 'FAIL: no pass/fail summary in output' -ForegroundColor Red; exit 1
}
if ([int]$Matches[1] -eq 0) {
  # A filter that matched no fixture would otherwise report '0 passed, 0 failed' as success.
  Write-Host 'FAIL: no test ran' -ForegroundColor Red; exit 1
}
Write-Host 'PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
} finally {
  # this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
