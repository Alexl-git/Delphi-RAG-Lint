<#
  run_plugin_cyclefix_summary.ps1 -- E18 Task 15b: the pure helpers behind the Structure tree's
  "Fix this cycle (dry run)..." / "Apply cycle fix..." on a circular-uses finding
  (DragLint.Plugin.DiagList: CycleFixSummary, CycleFixCanApply, CycleFixConfirmText,
  CycleFixWrittenFiles).

  Fed the cycle-fix/1 documents captured from real `cycles --fix` runs on circular-demo copies
  (tests\fixtures\cyclefix\outcome-*.json, paths scrubbed to C:\w\demo):
    outcome-15b-applied.json                --unit demoblueprint --apply (R1, routine-inversion), exit 0
    outcome-15b-dryrun.json                 --unit demoblueprint dry run, baseline ok, exit 0
    outcome-refused-dirty-baseline.json DemoConfig.pas line 1 -> `unit DemoConfigX;`, exit 1
    outcome-dryrun-parta.json           default group (Part A, move-globals, no single edge)
  plus inline documents for rolled back / group refusal / unreadable.

  Builds CycleFixHarness.dpr with dcc64 into the $PID scratch dir (deleted at the end;
  -KeepScratch keeps it on failure). -PluginDir points the build at another copy of the plugin
  sources (the RED run used a stub). Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$PluginDir  = "$PSScriptRoot\..\..\src\delphi-plugin",
  [string]$FixtureDir = "$PSScriptRoot\..\fixtures\cyclefix",
  [switch]$KeepScratch,
  [string]$WorkDir    = "$env:TEMP\drag-lint-cyclefix-summary-$PID"
)
function Remove-Scratch {
  if ($script:Failed -and $KeepScratch) { Write-Host "scratch kept: $WorkDir" -ForegroundColor Yellow; return }
  Set-Location -LiteralPath $env:TEMP
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
trap { $script:Failed = $true; Remove-Scratch; break }

$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
Write-Host '== cycle fix: summary, apply gate, confirm text, written files ==' -ForegroundColor Cyan
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$PluginDir  = (Resolve-Path $PluginDir).Path
$FixtureDir = (Resolve-Path $FixtureDir).Path
$harnessDir = (Resolve-Path "$PSScriptRoot\fixtures\cyclefix-summary").Path

# a bare .dpr cannot be built by msbuild, so dcc64 from rsvars (as run_diaglist_harness.ps1)
$rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
[IO.File]::WriteAllText($batPath, ((@(
  '@echo off'
  "call `"$rsvars`""
  "cd /d `"$harnessDir`""
  "dcc64 -CC -U`"$PluginDir`" -E`"$WorkDir`" -N0`"$WorkDir`" CycleFixHarness.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
) -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$null = Start-Process cmd.exe -ArgumentList '/c', "`"$batPath`"" `
          -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'CycleFixHarness.dpr builds (Win64)' $buildOk (($log -split "`r?`n" | Select-Object -Last 4) -join ' | ')
$exe = "$WorkDir\CycleFixHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) { Remove-Scratch; Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

$out = & $exe $FixtureDir 2>&1 | Out-String
$kv = @{}
foreach ($line in ($out -split "`r?`n")) { if ($line -match '^([A-Za-z0-9_.]+)=(.*)$') { $kv[$matches[1]] = $matches[2] } }
Check 'harness ran to completion' ($out -match '(?m)^DONE') $out

$dry     = Get-Content (Join-Path $FixtureDir 'outcome-15b-dryrun.json') -Raw | ConvertFrom-Json
$applied = Get-Content (Join-Path $FixtureDir 'outcome-15b-applied.json') -Raw | ConvertFrom-Json
$dryFiles = @($dry.cycles[-1].edits | ForEach-Object { $_.file.ToLowerInvariant() } | Sort-Object -Unique).Count
Check 'SANITY the dry run edits at least one file' ($dryFiles -gt 0) ''

Write-Host '-- CycleFixSummary: the three brief strings (rule 3)' -ForegroundColor Cyan
Check 'S1 applied' ($kv['sum.applied'] -eq 'applied: demoblueprint, democontrolplan, demoblueprint.viewmodel -- routine-inversion cut demoblueprint->demoblueprint.viewmodel; 3 file(s) written, 0 new; compile ok (4.4 s); verified') "got: $($kv['sum.applied'])"
Check 'S2 refused dirty-baseline names the first dcc line' ($kv['sum.dirty'] -eq "refused: dirty-baseline -- DemoConfig.pas(1): error E1038: Unit identifier 'DemoConfigX' does not match file name [C:\w\demo\CircularDemo.dproj]") "got: $($kv['sum.dirty'])"
Check 'S3 dry run mechanical' ($kv['sum.dry'] -eq 'dry run: mechanical -- routine-inversion cut demoblueprint->demoblueprint.viewmodel; baseline ok (1.8 s); add --apply') "got: $($kv['sum.dry'])"
Write-Host '-- CycleFixSummary: the other outcomes' -ForegroundColor Cyan
Check 'S4 a Part A recipe has no single edge: no " cut "' ($kv['sum.parta'] -eq 'dry run: mechanical -- move-globals; baseline ok (2.1 s); add --apply') "got: $($kv['sum.parta'])"
Check 'S5 stderr notes around the document are ignored' ($kv['sum.interleaved'] -eq $kv['sum.dry']) "got: $($kv['sum.interleaved'])"
Check 'S6 rolled back' ($kv['sum.rolled'] -eq 'rolled back: build error: E2003 Undeclared identifier') "got: $($kv['sum.rolled'])"
Check 'S7 a refusal on the group' ($kv['sum.grouprefused'] -eq 'refused: receiver-unknown -- Sender has no static class') "got: $($kv['sum.grouprefused'])"
Check 'S8 no JSON -> unreadable' ($kv['sum.garbage'] -eq 'cycle fix: unreadable output') "got: $($kv['sum.garbage'])"
Check 'S9 another schema -> unreadable' ($kv['sum.otherschema'] -eq 'cycle fix: unreadable output') "got: $($kv['sum.otherschema'])"

Write-Host '-- CycleFixCanApply: the confirm is offered only after a clean dry run' -ForegroundColor Cyan
Check 'G1 mechanical dry run, baseline ok -> TRUE' ($kv['can.dry'] -eq 'TRUE') "got: $($kv['can.dry'])"
Check 'G2 an apply document -> FALSE' ($kv['can.applied'] -eq 'FALSE') "got: $($kv['can.applied'])"
Check 'G3 refused dirty-baseline -> FALSE (no dialog)' ($kv['can.dirty'] -eq 'FALSE') "got: $($kv['can.dirty'])"

Write-Host '-- CycleFixConfirmText' -ForegroundColor Cyan
$ct = "$($kv['confirm.dry'])" -split '\|'
Check 'C1 the question names the cycle units' ($ct[0] -eq 'Apply the cycle fix to demoblueprint, democontrolplan, demoblueprint.viewmodel?') "got: $($ct[0])"
Check 'C2 recipe and edge' ($ct -contains 'Recipe: routine-inversion, cutting demoblueprint->demoblueprint.viewmodel') "got: $($kv['confirm.dry'])"
Check 'C3 files edited = distinct edits[].file of the fixture' ($ct -contains "Files edited: $dryFiles") "want $dryFiles got: $($kv['confirm.dry'])"
Check 'C4 no new unit -> none' ($ct -contains 'New units: none') "got: $($kv['confirm.dry'])"
Check 'C5 baseline status and time' ($ct -contains 'Baseline build: ok (1.8 s)') "got: $($kv['confirm.dry'])"
Check 'C6 says what a failed build does' ("$($kv['confirm.dry'])" -match 'rolled back when the build after the edit fails') "got: $($kv['confirm.dry'])"
Check 'C7 Part A: the new unit names' (("$($kv['confirm.parta'])" -split '\|') -contains 'New units: DemoSession.Untangle, DemoLogger.Untangle, DemoAudit.Untangle') "got: $($kv['confirm.parta'])"
Check 'C8 unreadable -> empty' ($kv['confirm.garbage'] -eq '[]') "got: $($kv['confirm.garbage'])"

Write-Host '-- CycleFixWrittenFiles: what is reloaded after an apply' -ForegroundColor Cyan
Check 'W1 applied: every written[] path' ($kv['written.count'] -eq "$(@($applied.cycles[-1].written).Count)") "got: $($kv['written.count'])"
Check 'W2 ... in the engine order' ($kv['written.first'] -eq $applied.cycles[-1].written[0]) "got: $($kv['written.first'])"
Check 'W3 a dry run wrote nothing' ($kv['written.dry'] -eq '0') "got: $($kv['written.dry'])"

Write-Host '-- CycleFixEditedFiles: the buffers that must be saved before --apply' -ForegroundColor Cyan
Check 'E1 the distinct edits[].file of the dry run' ($kv['edited.dry'] -eq "$dryFiles") "want $dryFiles got: $($kv['edited.dry'])"
Check 'E2 unreadable -> none' ($kv['edited.garbage'] -eq '0') "got: $($kv['edited.garbage'])"

Write-Host '-- the cycle-fix jobs use the ONE plugin time limit (fix round 1)' -ForegroundColor Cyan
# CYCLE_FIX_TIMEOUT_MS (DragLint.Plugin.CycleFix, 130 min) is above the longest --apply the engine's
# own limits allow (run_cyclefix_timeouts.ps1), so the engine's own rollback fires before the job queue kills an --apply mid-write.
$sf = [IO.File]::ReadAllText((Join-Path $PluginDir 'DragLint.Plugin.StructureForm.pas'))
$a  = $sf.IndexOf('procedure EnqueueCycleFixApply')
$b  = $sf.IndexOf('function TDragLintStructureForm.NodeIsCycleFinding')
$region = if ($a -ge 0 -and $b -gt $a) { $sf.Substring($a, $b - $a) } else { '' }
Check 'T0 SANITY the two cycle-fix job procedures are found' ($region -ne '') ''
Check 'T1 both cycle-fix jobs set Job.TimeoutMs := CYCLE_FIX_TIMEOUT_MS' `
  ([regex]::Matches($region, 'Job\.TimeoutMs\s*:=\s*CYCLE_FIX_TIMEOUT_MS\s*;').Count -eq 2) ''
Check 'T2 ... and no other TimeoutMs assignment there' ([regex]::Matches($region, 'TimeoutMs\s*:=').Count -eq 2) ''
Check 'T3 no private cycle-fix timeout constant or literal in StructureForm' `
  (($sf -notmatch 'CCycleFixTimeoutMs') -and ($region -notmatch '\b\d{4,}\b')) ''

Write-Host ("{0} PASS" -f $script:Passed)
Remove-Scratch
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
