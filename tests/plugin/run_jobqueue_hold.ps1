# dl:serial
<#
  run_jobqueue_hold.ps1 -- build and run JobQueueHoldTests.dpr.

  dl:serial, and NOT for speed. The engine hold is ONE SENTINEL FILE PER USER
  (DRagLint.Core.EngineHold), so any other runner that writes or clears it
  concurrently would make this one's results meaningless in both directions --
  a hold cleared underneath test 2 reads as "the gate does not work", and a
  hold left behind by a neighbour reads as "the gate works" even with the gate
  removed. run_engine_hold.ps1 carries the same marker for the same reason.

  WHAT IT COVERS. Every heavy job in the plugin's queue runs the DEPLOYED
  drag-lint.exe, which a build stages over. `ide-release` writes a hold meaning
  "do not start anything", and the queue used to ignore it entirely: WorkerLoop
  extracted and RunOne spawned unconditionally.

  WHY A COMPILED CONSOLE TEST rather than an exe-driven autotest: JobQueue.pas's
  implementation uses only DragLint.Plugin.ProcRun, and the gate's one new
  dependency (DRagLint.Core.EngineHold) reads a sentinel file and touches no
  process, so the unit links and runs with no IDE. The design-time BPL cannot be
  rebuilt while RAD Studio is open, so in-IDE behaviour stays unverified either
  way -- but the gate itself does not need an IDE to be exercised, and waiting
  for a closed one would mean not testing it at all. Same recipe as
  run_codelens_cache_lru.ps1.

  RED BASELINE, MEASURED 2026-09-07 against the ungated JobQueue.pas, in two
  runs because one assertion cannot compile without the fix:

    run 1, the file as it stands -> COMPILE ERROR, E2003 undeclared
      identifier 'GJobQueueDeferredHook'. That is row 7's RED, and the
      plan that specified this harness said to record it as such.
    run 2, test 7 removed so the rest can execute -> 6 passed, 4 failed.
      RED   2a 2b 4a 6b
      GREEN 1 3 3b 4b 5 6a

  TWO CORRECTIONS TO THE PREDICTION, recorded because a predicted baseline
  that is never checked against a measured one is how a guard comes to be
  trusted for the wrong reason:

   * 4a was expected to be GREEN both before and after -- a pure regression
     fence for the PEEK design. It is RED before. Ungated, the first job
     starts immediately, so the queue is not holding three coalescible jobs
     when the depth is read. 4b IS the fence that was intended (a gate that
     extracted and re-queued would run the first job and then the last), and
     it is green before and after. So is 5.
   * row 6 was expected RED as a whole, on the reasoning that the job runs
     during the destructor's WaitFor. Only 6b is RED: shutdown WAS already
     prompt (6a green), and what was broken is that the job ran at all. 6a
     still earns its place -- after the gate it pins that a live hold cannot
     pin IDE unload for a whole 5 s recheck interval, which is a NEW way to
     hang that this change introduces.

  GREEN after the gate: 12 passed, 0 failed.

  Usage: pwsh -File tests\plugin\run_jobqueue_hold.ps1
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\JobQueueHoldTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-jobqueue-hold-build"
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

# BELT AND BRACES ON THE SENTINEL. The dpr releases in a finally, but if it
# crashed hard the hold would outlive it and every drag-lint on this machine
# would defer. Clearing it here costs nothing and cannot mask a failure, since
# the verdict below is already decided.
$engine = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe"
if (Test-Path $engine) { & $engine ide-release --resume 2>&1 | Out-Null }

if ($rc -ne 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
if ($out -notmatch '(\d+) passed, 0 failed') {
  # A run that printed nothing would otherwise sail through on exit 0.
  Write-Host 'FAIL: no pass/fail summary in output' -ForegroundColor Red; exit 1
}
Write-Host 'PASS' -ForegroundColor Green
exit 0
