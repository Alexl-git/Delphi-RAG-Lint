<#
  run_plugin_cyclefix_args.ps1 -- E18 Task 15: pins DragLint.Plugin.CycleFix, the
  pure half of the IDE's `cycles --fix` surface -- the "Fix Circular Uses
  Mechanically (dry run)..." menu item and the Uses & Deps tab's "Circular uses"
  section.

  WHAT IT PINS
    A  the exact engine command lines: the menu's dry run (never --apply), the
       tab's list query, its Dry run (`--cycle n --format json`) and its Apply
       (the same + ` --apply`).
    L  the SCC rows read from a captured `cycles --format json --causes` run on
       circular-demo (tests\fixtures\cyclefix\causes.json): one row per SCC,
       1-based --cycle numbers, fix.available / fix.reason, a banner before the
       array and an engine note after it.
    O  the one-line outcome rendered from captured `cycle-fix/1` documents:
       a dirty baseline reads `refused: dirty-baseline -- <first dcc line>`, a
       per-cycle refusal names kind + file, a dry run says nothing was written,
       an apply says verified + how many files, and lists exactly the written[]
       paths the tab reloads. An unreadable document is NOT "nothing written".

  The fixtures were captured 2026-10-20 with the e18-cycle-fix engine
  (2f71d68c) on scratch copies of circular-demo, paths rewritten to C:\w\demo.

  Builds the harness with dcc64 (from rsvars) into a per-run scratch folder,
  removed in `finally`. Exit 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-args-$PID",
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }

$harnessDir = "$PSScriptRoot\fixtures\cyclefixargs"
$fixtureDir = (Resolve-Path "$PSScriptRoot\..\fixtures\cyclefix").Path
$pluginDir  = (Resolve-Path "$PSScriptRoot\..\..\src\delphi-plugin").Path

Write-Host '== cycles --fix: plugin command lines, SCC rows, outcome text ==' -ForegroundColor Cyan
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null

  $batPath = "$WorkDir\build_harness.bat"
  $logPath = "$WorkDir\build_harness.log"
  $batBody = (@(
    '@echo off'
    "call `"$Rsvars`""
    "cd /d `"$harnessDir`""
    "dcc64 -CC -U`"$pluginDir`" -E`"$WorkDir`" -N0`"$WorkDir`" CycleFixArgsHarness.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
  ) -join "`r`n")
  [IO.File]::WriteAllText($batPath, $batBody, [Text.Encoding]::ASCII)
  $null = Start-Process cmd.exe -ArgumentList '/c', "`"$batPath`"" `
            -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -NoNewWindow -Wait -PassThru
  $log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
  $buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
  Check 'CycleFixArgsHarness.dpr builds (Win64)' $buildOk (($log -split "`r?`n" | Select-Object -Last 4) -join ' | ')
  $exe = "$WorkDir\CycleFixArgsHarness.exe"
  if (-not $buildOk -or -not (Test-Path $exe)) { throw 'harness did not build' }

  $out = & $exe $fixtureDir 2>&1 | Out-String
  $kv = @{}
  foreach ($line in ($out -split "`r?`n")) { if ($line -match '^([A-Za-z0-9_.]+)=(.*)$') { $kv[$matches[1]] = $matches[2] } }
  Check 'harness ran to completion' ($out -match '(?m)^DONE') $out

  Write-Host '-- A: command lines' -ForegroundColor Cyan
  $dry = 'cycles --fix --project "<P>" --db "<D>" --cycle 2 --format json'
  Check 'A1 Dry run for cycle 2'           ($kv['args.dry'] -ceq $dry) "got: $($kv['args.dry'])"
  Check 'A2 Apply = the dry run + --apply' ($kv['args.apply'] -ceq "$dry --apply") "got: $($kv['args.apply'])"
  Check 'A3 the menu runs a text dry run (engine-picked SCC), never --apply' `
    ($kv['args.menu'] -ceq 'cycles --fix --project "<P>" --db "<D>" --format text') "got: $($kv['args.menu'])"
  Check 'A4 the list query carries --causes (the fix object lives there)' `
    ($kv['args.list'] -ceq 'cycles --project "<P>" --db "<D>" --format json --causes') "got: $($kv['args.list'])"

  Write-Host '-- T: time limits (fix round 1, R1)' -ForegroundColor Cyan
  # A kill at the plugin's limit takes engine + msbuild/dcc down mid-apply, past the engine's own
  # rollback; the plugin's limit must therefore sit ABOVE the engine's 30 min build timeout.
  Check 'T1 CYCLE_FIX_TIMEOUT_MS is 35 min' ($kv['timeout.cyclefix'] -eq '2100000') "got: $($kv['timeout.cyclefix'])"
  Check 'T2 ... which is above the engine''s 30 min build timeout' ([int]"0$($kv['timeout.cyclefix'])" -gt 1800000) "got: $($kv['timeout.cyclefix'])"
  $frameSrc  = [IO.File]::ReadAllText((Join-Path $pluginDir 'DragLint.Plugin.UsesDepsFrame.pas'))
  $editorSrc = [IO.File]::ReadAllText((Join-Path $pluginDir 'DragLint.Plugin.Editor.pas'))
  Check 'T3 the other Uses & Deps sections keep 180 s (ENGINE_TIMEOUT_MS, used by RunEngine)' `
    (($frameSrc -match '(?m)^\s*ENGINE_TIMEOUT_MS\s*=\s*180000;') -and ($frameSrc.Contains('AOutput, ENGINE_TIMEOUT_MS)'))) ''
  Check 'T4 the tab''s Dry run / Apply job runs under CYCLE_FIX_TIMEOUT_MS' ($frameSrc -match 'Job\.TimeoutMs\s*:=\s*CYCLE_FIX_TIMEOUT_MS;') ''
  Check 'T5 the menu dry run passes CYCLE_FIX_TIMEOUT_MS; other menu reports keep 180 s' `
    ($editorSrc.Contains("DLRunReport(CycleFixMenuArgs(Proj, Db), 'drag-lint-circular-uses-fix.txt', CYCLE_FIX_TIMEOUT_MS);") -and ($editorSrc -match 'REPORT_TIMEOUT_MS\s*=\s*180000;') -and ($editorSrc.Contains('RunAndCaptureStdout(Cmd, Output, ATimeoutMs);'))) ''
  $runFix = [regex]::Match($frameSrc, 'procedure TCircularUsesSection\.RunFix\([\s\S]*?end; // procedure').Value
  Check 'T6 Dry run / Apply go through the JobQueue, not the blocking RunEngine' `
    (($runFix -ne '') -and $runFix.Contains('JobQueue.Enqueue(Job)') -and $runFix.Contains('Job.Busy       := True') -and -not $runFix.Contains('RunEngine(')) ''
  Check 'T7 a second start is refused while a run is in flight' ($runFix.Contains('if FRunning or JobQueueBusy then')) ''
  $setRun = [regex]::Match($frameSrc, 'procedure TCircularUsesSection\.SetRunning\([\s\S]*?\r?\nend;').Value
  Check 'T8 both fix buttons follow the in-flight state' ($setRun.Contains('FBtnTickAll.Enabled:= not AValue') -and $setRun.Contains('FBtnApply.Enabled  := not AValue')) ''
  $finish = [regex]::Match($frameSrc, 'procedure TCircularUsesSection\.FinishFix\([\s\S]*?end; // procedure').Value
  Check 'T9 OnDone re-enables first, before any outcome branch (completion, failure, timeout)' `
    (($finish -ne '') -and ($finish.IndexOf('SetRunning(False)') -ge 0) -and ($finish.IndexOf('SetRunning(False)') -lt $finish.IndexOf('PROCRUN_TIMED_OUT_EXIT_CODE'))) ''
  Write-Host '-- L: SCC rows from cycles --format json --causes' -ForegroundColor Cyan
  Check 'L1 one row per SCC (3 on circular-demo), banner + note tolerated' ($kv['rows.count'] -eq '3') "got: $($kv['rows.count'])"
  Check 'L2 rows are numbered 1..n, the --cycle value' (($kv['rows.0.cycle'] -eq '1') -and ($kv['rows.1.cycle'] -eq '2') -and ($kv['rows.2.cycle'] -eq '3')) "got: $($kv['rows.0.cycle']),$($kv['rows.1.cycle']),$($kv['rows.2.cycle'])"
  Check 'L3 units joined in engine order' ($kv['rows.0.units'] -ceq 'demologger <-> democonfig <-> demoaudit <-> demosession') "got: $($kv['rows.0.units'])"
  Check 'L4 fix.available + part read' (($kv['rows.0.fixable'] -eq 'TRUE') -and ($kv['rows.0.part'] -eq 'a')) "got: $($kv['rows.0.fixable']) $($kv['rows.0.part'])"
  Check 'L5 fixable caption' ($kv['rows.0.caption'] -ceq '1. demologger <-> democonfig <-> demoaudit <-> demosession   -- fixable (part a)') "got: $($kv['rows.0.caption'])"
  Check 'L6 an unfixable SCC carries fix.reason' (($kv['rows.1.fixable'] -eq 'FALSE') -and ("$($kv['rows.1.reason'])".StartsWith('receiver-unknown: `TDemoGagePort`'))) "got: $($kv['rows.1.fixable']) $($kv['rows.1.reason'])"
  Check 'L7 unfixable caption says why' ("$($kv['rows.1.caption'])".StartsWith('2. demouiconnect <-> demogageport   -- not fixable: receiver-unknown: ')) "got: $($kv['rows.1.caption'])"
  Check 'L8 an empty array -> no rows' ($kv['rows.empty'] -eq '0') "got: $($kv['rows.empty'])"
  Check 'L9 no JSON at all -> no rows, no exception' ($kv['rows.garbage'] -eq '0') "got: $($kv['rows.garbage'])"

  Write-Host '-- O: outcome text from cycle-fix/1' -ForegroundColor Cyan
  Check 'O1 dirty baseline: readable, refused, baseline error' (($kv['refused.readable'] -eq 'TRUE') -and ($kv['refused.refusals'] -eq '1') -and ($kv['refused.baseline'] -eq 'error')) "got: $($kv['refused.readable']) $($kv['refused.refusals']) $($kv['refused.baseline'])"
  Check 'O2 dirty baseline reads "refused: dirty-baseline -- <first dcc line>"' `
    ($kv['refused.text'] -ceq "cycles --fix (dry run): refused: dirty-baseline -- DemoConfig.pas(1): error E1038: Unit identifier 'DemoConfigX' does not match file name; baseline error.") "got: $($kv['refused.text'])"
  Check 'O3 ... and wrote nothing' ($kv['refused.wrote'] -eq 'FALSE') ''
  Check 'O4 per-cycle refusals: kind + file, verdict, baseline, repairs' `
    ($kv['cycle.text'] -ceq 'cycles --fix (dry run): verdict refused; refused: receiver-unknown -- DemoUIConnect.pas; refused: manual-edit -- DemoGagePort.pas; baseline ok; 0 repair(s).') "got: $($kv['cycle.text'])"
  Check 'O5 a clean dry run says nothing was written' `
    ($kv['dry.text'] -ceq 'cycles --fix (dry run): verdict mechanical; baseline ok; 0 repair(s); nothing written (dry run) -- press Apply to write and verify.') "got: $($kv['dry.text'])"
  Check 'O6 ... and leaves nothing to reload' (($kv['dry.written'] -eq '0') -and ($kv['dry.wrote'] -eq 'FALSE')) "got: $($kv['dry.written']) $($kv['dry.wrote'])"
  Check 'O7 an apply: verified, files written' `
    ($kv['applied.text'] -ceq 'cycles --fix (apply): verdict mechanical; baseline ok; 0 repair(s); verified; 9 file(s) written.') "got: $($kv['applied.text'])"
  Check 'O8 ... and every written[] path is handed to the reload' (($kv['applied.written'] -eq '9') -and ($kv['applied.wrote'] -eq 'TRUE') -and ($kv['applied.verified'] -eq 'TRUE')) "got: $($kv['applied.written']) $($kv['applied.wrote']) $($kv['applied.verified'])"
  Check 'O9 no document: unreadable, and NOT reported as nothing written' `
    (($kv['garbage.readable'] -eq 'FALSE') -and ("$($kv['garbage.text'])" -match 'may or may not have been written')) "got: $($kv['garbage.text'])"
  Check 'O10 another verb''s document is not a cycle-fix/1 outcome' ($kv['other.readable'] -eq 'FALSE') "got: $($kv['other.readable'])"
}
catch {
  Check "runner: $($_.Exception.Message)" $false
}
finally {
  Set-Location -LiteralPath $env:TEMP
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
Write-Host ''
if ($script:Failed) { Write-Host 'CYCLEFIX ARGS: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'CYCLEFIX ARGS: PASS' -ForegroundColor Green; exit 0 }
