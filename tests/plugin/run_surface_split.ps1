<#
  run_surface_split.ps1 -- build and run SurfaceSplitTests.dpr.

  WHAT IT COVERS. DragLint.Plugin.SurfaceSplit tells an INTERFACE edit from an
  IMPLEMENTATION edit in an unsaved buffer, and TFanOutGate turns that into the
  launch decision for the fan-out (PLAN-lint-tree P2). LiveDiagnostics hashes
  the whole buffer, so before this the two were indistinguishable and a
  background feature would have run while you typed inside a method body.

  THE ASYMMETRY IS THE DESIGN. Over-firing costs one BELOW_NORMAL engine run
  that the engine short-circuits; under-firing means an interface edit reaches
  no dependent and nobody is told. Every judgement in the unit resolves that
  way, which is why the split point is the LAST `implementation` candidate
  rather than the first, and why case 8c asserts the resulting over-fire
  explicitly instead of leaving it to be discovered.

  WHY A COMPILED CONSOLE TEST rather than an exe-driven autotest: the unit uses
  System.SysUtils and System.Hash and nothing else -- no OTA, no VCL -- so it
  links outside the IDE, and TFanOutGate takes the tick count as a PARAMETER so
  its 2 s debounce can be tested without waiting 2 s. The IDE-bound half (the
  poll-loop wiring in LiveDiagnostics) is verified separately, in the O-block.

  RED BASELINE, MEASURED 2026-09-10 with the unit absent from the tree:

    SurfaceSplitTests.dpr(28) Fatal: F1026 File not found:
      '..\src\delphi-plugin\DragLint.Plugin.SurfaceSplit.pas'

  MUTATION RESULTS, MEASURED 2026-09-10 against the finished build. A compile-
  error RED proves only that the unit is new, so every load-bearing rule was
  checked by breaking it:

    M1  line-comment state removed        -> 2b only
    M1b brace-comment state removed       -> 3b only
    M1c (* *) comment state removed       -> 4b only
    M1d string-literal state removed      -> 5b only
    M2  FIRST candidate wins, not last    -> 8b and 8c
    M3  idle debounce removed             -> 14a, 14c, 17b, 18a, 18b, 18c, 18e
    M4  gate hashes the WHOLE buffer      -> 16b only   (the pre-P2 behaviour)
    M5  silent-shape short-circuit removed-> 18d only

  TWO OF THOSE ROWS COST A TEST REWRITE, and both are worth knowing about:

   * M1/M1b/M1c ALL PASSED at first, 35/35 green with the comment states
     deleted. The decoy `implementation` sat BEFORE the real one, and
     last-match-wins survives that on its own -- the a-variants discriminate
     against first-match-wins, not against comment blindness. The b-variants
     put the decoy AFTER the real keyword, which is also the shape real code
     has (a comment inside an implementation section that mentions the word).
   * the b-variants then STILL passed, because the decoy sat before the text
     the assertion looked for, so a late split excluded it anyway. The decoy
     has to sit past the asserted text. Two rounds of "the guard cannot fail"
     on the same four cases.

  GREEN: 35 passed, 0 failed, ~15 s (compile-dominated; the tests themselves
  are pure string work and take no measurable time).

  Usage: pwsh -File tests\plugin\run_surface_split.ps1
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
  [string]$Dpr     = "$PSScriptRoot\..\SurfaceSplitTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-surface-split-build"
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
