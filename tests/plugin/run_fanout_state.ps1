<#
  run_fanout_state.ps1 -- build and run FanOutStateTests.dpr.

  WHAT IT COVERS. Everything the interface-change fan-out DECIDES: generations
  and staleness, the edit episode and its baseline, the discard back-off, the
  worklist, the tier-3 quiet period and its forcing save, the engine command
  lines, and the row text. DragLint.Plugin.FanOutState has no ToolsAPI in it
  precisely so all of that is checkable without an IDE; DragLint.Plugin.FanOut
  is then only spawning, killing and painting, which is what the O-block looks
  at.

  WHY THE SPLIT EARNS ITS KEEP. A person watching a running IDE can see that
  rows appeared. They cannot see that the rows shown were the PREVIOUS
  generation's answer, that the baseline was silently recaptured on save, or
  that the back-off never engaged. Each of those makes the feature quietly
  worse and none of them raises anything.

  RED BASELINE, MEASURED 2026-09-10 with the unit absent:

    FanOutStateTests.dpr(32) Fatal: F1026 File not found:
      '..\src\delphi-plugin\DragLint.Plugin.FanOutState.pas'

  MUTATION RESULTS, MEASURED 2026-09-10 against the finished build:

    M1 the episode re-baselines on every call   -> 7b, 8c
    M2 a stale generation is accepted           -> 9b, and the back-off rows
    M3 a save ends the episode                  -> 8a, 8b, 8c
    M4 one dependent edit clears the worklist   -> 11b, 11c, 11d
    M5 an edit does not restart the tier-3 clock-> 14b, 14c
    M6 the discard back-off does not double     -> 10b, 10c, 10e
    M7 tier 3 stays armed after firing          -> 13e
    M8 the title drops the suppression count    -> 16e

  M5 TOOK TWO ATTEMPTS, and the reason is worth keeping. An edit does two
  things -- it lengthens the quiet period AND restarts it -- and the first
  version of 14b checked at an instant where the LENGTHENING alone was already
  enough to refuse. With the restart deleted outright the suite stayed 64/64
  GREEN. The check now falls after the original arming's deadline and before
  the edit's, where only a moved clock can refuse.

  THIS RUNNER ITSELF SHIPPED BROKEN ONCE: seeded from run_index_job.ps1, its
  -Dpr default still named IndexJobTests.dpr, so it reported "17 passed" -- a
  real, green run of the WRONG program. The 64/17 mismatch is what gave it
  away. If this header's count and the run's count ever disagree, suspect the
  runner before the code.

  GREEN: 64 passed, 0 failed, ~10 s (compile-dominated).

  Usage: pwsh -File tests\plugin\run_fanout_state.ps1
#>
#
#  COMPILED WITH -$Q+ -$R+ ON PURPOSE: the same overflow and range checking the
#  design-time BPL uses (see the dcc32 line in build_plugin_win32.bat). Without
#  it this harness built with checks OFF while the shipped package built with
#  them ON, so the two disagreed about what the code even means. That is not
#  hypothetical: CheapBufferHash and CheapHash are wraparound hashes, they
#  raised EIntOverflow on EVERY call inside the IDE, the fan-out never ran once
#  -- and this suite reported GREEN throughout. A test that compiles differently
#  from the thing it tests is not testing that thing.
#
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\FanOutStateTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-fanout-state-build"
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

# dcc64 refuses to create output into a directory that does not exist (F2039),
# hence both are made above rather than relying on the compiler to do it.
$bat = Join-Path $WorkDir 'build.bat'
$lines = @(
  '@echo off',
  ('call "{0}"' -f $rs),
  ('cd /d "{0}"' -f $DprDir),
  ('dcc64 -B -$Q+ -$R+ -E"{0}" -N0"{1}" {2}' -f $WorkDir, $DcuDir, $DprName),
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
