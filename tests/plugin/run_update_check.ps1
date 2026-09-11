<#
  run_update_check.ps1 -- build and run UpdateCheckTests.dpr.

  WHAT IT COVERS. Everything the About dialog's "Check for updates" button
  DECIDES: normalising two incompatible tag shapes, comparing versions field by
  field numerically, and classifying the outcome. The asking needs a network
  and the saying needs a dialog; neither is touched here.

  WHY THE SPLIT EARNS ITS KEEP. A person clicking the button sees that it said
  something. They cannot see that it compared '1.10.1' as LOWER than '1.4.0'
  and sent them to download an older release than the one they are running --
  which is precisely what a string compare does, and precisely the situation
  live today: drag-lint builds 1.10.1-alpha while its newest published release
  is v1.4.0-alpha.

  RED BASELINE: with DragLint.Plugin.Updates.pas absent the build fails
  F2063/F1026 and this runner exits 2 -- it cannot pass vacuously.

  THE COUNT IS ASSERTED, not just the exit code. run_fanout_state.ps1 shipped
  broken once because its -Dpr default still named the program it was seeded
  from, and reported a real, green run of the WRONG binary; only a count
  mismatch gave it away. So if the expected count below and the run disagree,
  suspect this runner before the code.

  GREEN: 30 passed, 0 failed.

  Usage: pwsh -File tests\plugin\run_update_check.ps1
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\UpdateCheckTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-update-check-build",
  [int]   $Expected = 30
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
$Dpr     = (Resolve-Path $Dpr).Path
$DprDir  = Split-Path $Dpr -Parent
$DprName = Split-Path $Dpr -Leaf

# The runner must be about the program it NAMES. See the header.
if ($DprName -ne 'UpdateCheckTests.dpr') {
  Write-Host "FATAL: this runner is for UpdateCheckTests.dpr, got $DprName" -ForegroundColor Red; exit 2
}

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }

New-Item -ItemType Directory -Force $WorkDir | Out-Null
$DcuDir = Join-Path $WorkDir 'dcu'
New-Item -ItemType Directory -Force $DcuDir | Out-Null

# dcc refuses to write into a directory that does not exist (F2039), hence both
# are created above rather than relying on the compiler.
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
$got = [int]$Matches[1]
if ($got -ne $Expected) {
  Write-Host "FAIL: expected $Expected checks, got $got -- did this runner build the right program?" -ForegroundColor Red
  exit 1
}
Write-Host 'PASS' -ForegroundColor Green
exit 0