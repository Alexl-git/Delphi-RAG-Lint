<#
  run_lint_circular_uses_per_file.ps1 -- E18 Task 15b: `lint <file>` (the Structure tree's call)
  reports circular-uses for EVERY unit of a cycle, at the uses entry a person would edit.

  Until 15b the rule fired once per strongly-connected component, anchored at the SCC's
  alphabetically-first unit `:1:1` -- so `lint DemoUIConnect.pas` printed `[]` and the IDE had no
  node to hang "Fix this cycle" on. Asserts, on a COPY of circular-demo (no platform library:
  every run passes --library-db none):
    (a) `lint DemoUIConnect.pas --rule circular-uses --format json`: exactly 1 finding,
        rule circular-uses, severity warning, start_line 43 (DemoGagePort in the implementation
        uses), start_col 1, the SAME message lint-all prints for that cycle, and a fix_hint
        `cycles --fix --project "<X.dproj>" --db "<db>" --unit demouiconnect` (placeholder
        project without --project; the given one with it).
    (b) the SCC's anchor unit (DemoGagePort.pas) gets ONE finding too, at its own uses line 56 --
        not the 1:1 anchor AND the uses line.
    (c) DemoBlueprint.Interfaces.pas (in no cycle) -> 0 findings.
    (d) lint-all is unchanged: one finding per SCC, at the first unit `:1:1`, no fix_hint.
    (e) `rules --json` keeps circular-uses fixable:false (the fix is a verb, not lint --fix).
    (f) POSITIVE CONTROL: a copy with the cycle cut by hand (DemoGagePort removed from
        DemoUIConnect's implementation uses), re-indexed -> 0 findings for DemoUIConnect.pas.
        (The brief's "apply R2 by the follower" needs the platform library, which this runner
        never opens or copies; the hand cut is the same graph change.)
    (g) fix round 1, tests\fixtures\cyclefix\incuses: a cycle closed inside {$IFDEF} -> exactly one
        finding + fix_hint on each unit; a cycle closed through {$I} is printed as a NOTE (the index
        records no uses row from an include).
  Run from any CWD, pwsh 7. -KeepScratch keeps the scratch dir on failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [switch]$KeepScratch,
  [string]$WorkDir = "$env:TEMP\drag-lint-circular-per-file-$PID"
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
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
function Index-Copy([string]$Dir, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  $idx = & $Exe index --project (Join-Path $Dir 'CircularDemo.dproj') --db $db --library-db none 2>&1 | Out-String
  Check "${Tag}: SANITY the 10 units indexed with 0 errors" `
    (([regex]::Matches($idx, 'Demo[\w.]+\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors')).Count -eq 10) $idx
  return $db
}
# `lint <file> --rule circular-uses --format json`; the JSON is a bare array (field start_line).
function Lint-One([string]$File, [string]$Db, [string[]]$Extra = @()) {
  $a = @('lint', $File, '--db', $Db, '--rule', 'circular-uses', '--format', 'json', '--library-db', 'none') + $Extra
  $out = (& $Exe @a 2>$null | Out-String)
  $rows = @()
  try { $rows = @($out | ConvertFrom-Json) } catch { $rows = $null }
  return @{ Out = $out; Rows = $rows }
}

if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
Push-Location $WorkDir
try {
  $demo  = Join-Path $WorkDir 'demo'
  Copy-Tree (Join-Path $Repo 'circular-demo') $demo
  $db    = Index-Copy $demo 'demo'
  $dproj = Join-Path $demo 'CircularDemo.dproj'

  Write-Host '== (d) lint-all: one finding per SCC at the first unit :1:1 (read first, the oracle for (a))' -ForegroundColor Cyan
  $allOut = (& $Exe lint-all --db $db --rule circular-uses --json --library-db none 2>$null | Out-String)
  $all = @()
  try { $all = @(($allOut | ConvertFrom-Json) | Where-Object { $_.rule -eq 'circular-uses' }) } catch { $all = @() }
  Check 'd: lint-all prints 3 circular-uses findings' ($all.Count -eq 3) $allOut
  Check 'd: every one at start_line 1, start_col 1' (@($all | Where-Object { $_.start_line -ne 1 -or $_.start_col -ne 1 }).Count -eq 0) $allOut
  Check 'd: anchored at DemoAudit / DemoBlueprint / DemoGagePort' `
    ((@($all | ForEach-Object { [IO.Path]::GetFileName($_.file_path) } | Sort-Object) -join ',') -eq 'DemoAudit.pas,DemoBlueprint.pas,DemoGagePort.pas') $allOut
  Check 'd: no fix_hint on a lint-all finding' (@($all | Where-Object { $_.PSObject.Properties.Name -contains 'fix_hint' }).Count -eq 0) $allOut
  $gageMsg = @($all | Where-Object { $_.file_path -like '*DemoGagePort.pas' } | ForEach-Object { $_.message }) | Select-Object -First 1

  Write-Host '== (a) lint DemoUIConnect.pas: the finding, on the uses line' -ForegroundColor Cyan
  $r = Lint-One (Join-Path $demo 'DemoUIConnect.pas') $db
  $f = if ($r.Rows -and $r.Rows.Count -ge 1) { $r.Rows[0] } else { $null }
  Check 'a: exactly 1 finding' ($r.Rows -and $r.Rows.Count -eq 1) $r.Out
  Check 'a: rule = circular-uses, severity warning' ($f -and $f.rule -eq 'circular-uses' -and $f.severity -eq 'warning') $r.Out
  Check 'a: file_path = DemoUIConnect.pas' ($f -and $f.file_path -like '*DemoUIConnect.pas') $r.Out
  Check 'a: start_line 43 (DemoGagePort in the implementation uses), start_col 1' ($f -and $f.start_line -eq 43 -and $f.start_col -eq 1) $r.Out
  Check 'a: the same message lint-all prints for the cycle' ($f -and $gageMsg -and $f.message -eq $gageMsg) "per-file: $($f.message) | lint-all: $gageMsg"
  Check 'a: fix_hint names the unit' ($f -and "$($f.fix_hint)" -like '*--unit demouiconnect*') $r.Out
  Check 'a: fix_hint without --project carries the placeholder and the db' `
    ($f -and "$($f.fix_hint)" -eq ('cycles --fix --project "<X.dproj>" --db "{0}" --unit demouiconnect' -f $db)) "got: $($f.fix_hint)"
  $r = Lint-One (Join-Path $demo 'DemoUIConnect.pas') $db @('--project', $dproj)
  $f = if ($r.Rows -and $r.Rows.Count -ge 1) { $r.Rows[0] } else { $null }
  Check 'a: with --project the fix_hint names it' `
    ($f -and "$($f.fix_hint)" -eq ('cycles --fix --project "{0}" --db "{1}" --unit demouiconnect' -f $dproj, $db)) "got: $($f.fix_hint) out: $($r.Out)"
  $r = & $Exe lint (Join-Path $demo 'DemoUIConnect.pas') --db $db --rule circular-uses --library-db none 2>$null | Out-String
  Check 'a: text output has the one-line finding at :43:1' ($r -match 'DemoUIConnect\.pas:43:1  \[warning\] circular-uses: Circular unit dependency among 2 units') $r

  Write-Host '== (b) the anchor unit: one finding, on its own uses line' -ForegroundColor Cyan
  $r = Lint-One (Join-Path $demo 'DemoGagePort.pas') $db
  Check 'b: DemoGagePort.pas: exactly 1 finding' ($r.Rows -and $r.Rows.Count -eq 1) $r.Out
  Check 'b: ... at start_line 56 (DemoUIConnect in its implementation uses)' ($r.Rows -and $r.Rows[0].start_line -eq 56) $r.Out
  Check 'b: ... fix_hint --unit demogageport' ($r.Rows -and "$($r.Rows[0].fix_hint)" -like '*--unit demogageport') $r.Out

  Write-Host '== (c) a unit in no cycle' -ForegroundColor Cyan
  $r = Lint-One (Join-Path $demo 'DemoBlueprint.Interfaces.pas') $db
  Check 'c: DemoBlueprint.Interfaces.pas -> 0 findings' ($null -ne $r.Rows -and $r.Rows.Count -eq 0) $r.Out

  Write-Host '== (e) rules --json: circular-uses stays fixable:false' -ForegroundColor Cyan
  $rules = (& $Exe rules --json 2>$null | Out-String) | ConvertFrom-Json
  $cu = @(@($rules) + @($rules.rules) | Where-Object { $_ -and $_.id -eq 'circular-uses' }) | Select-Object -First 1
  Check 'e: circular-uses listed, fixable = false' ($cu -and $cu.fixable -eq $false) "got: $($cu | ConvertTo-Json -Compress)"

  Write-Host '== (f) POSITIVE CONTROL: the cycle cut -> no finding' -ForegroundColor Cyan
  $cut = Join-Path $WorkDir 'cut'
  Copy-Tree (Join-Path $Repo 'circular-demo') $cut
  $p = Join-Path $cut 'DemoUIConnect.pas'
  $txt = [IO.File]::ReadAllText($p)
  $new = [regex]::Replace($txt, '(?m)^(\s*)DemoGagePort(\s*[,;])', '${1}System.Types${2}', 1)
  Check 'f: SANITY the hand cut changed DemoUIConnect.pas' ($new -ne $txt) ''
  [IO.File]::WriteAllText($p, $new, [Text.Encoding]::ASCII)
  $cdb = Index-Copy $cut 'cut'
  $r = Lint-One $p $cdb
  Check 'f: DemoUIConnect.pas in the cut copy -> 0 findings' ($null -ne $r.Rows -and $r.Rows.Count -eq 0) $r.Out
  $r = Lint-One (Join-Path $cut 'DemoAudit.pas') $cdb
  Check 'f: CONTROL the untouched 4-unit cycle still reports on DemoAudit.pas' ($r.Rows -and $r.Rows.Count -eq 1) $r.Out

  Write-Host '== (g) fix round 1: a closing edge inside {$IFDEF} / {$I} (tests\fixtures\cyclefix\incuses)' -ForegroundColor Cyan
  $inc = Join-Path $WorkDir 'incuses'
  New-Item -ItemType Directory -Force $inc | Out-Null
  Copy-Item (Join-Path $Repo 'tests\fixtures\cyclefix\incuses\*') $inc -Force
  $idb = Join-Path $WorkDir 'incuses.sqlite'
  $iout = & $Exe index --project (Join-Path $inc 'IncUses.dproj') --db $idb --library-db none 2>&1 | Out-String
  Check 'g: SANITY incuses indexed with 0 errors' ($iout -match 'DefB\.pas\s*->.*0 errors' -and $iout -notmatch '[1-9]\d* errors') $iout
  foreach ($u in @(@('DefA.pas', 15, 'defa'), @('DefB.pas', 16, 'defb'))) {
    $r = Lint-One (Join-Path $inc $u[0]) $idb
    Check "g: $($u[0]): exactly 1 circular-uses finding" ($r.Rows -and $r.Rows.Count -eq 1) $r.Out
    Check "g: $($u[0]): on its uses entry, line $($u[1])" ($r.Rows -and $r.Rows[0].start_line -eq $u[1]) $r.Out
    Check "g: $($u[0]): fix_hint --unit $($u[2])" ($r.Rows -and "$($r.Rows[0].fix_hint)" -like "*--unit $($u[2])") $r.Out
  }
  # {$I}: the index records NO unit_uses row for a uses clause inside an include, so the IncA <-> IncB
  # cycle does not exist for lint-all, cycles or lint <file> alike (an extractor gap, reported, not
  # pinned here: a check would fail the day the gap is fixed).
  $cyc = & $Exe cycles --db $idb 2>$null | Out-String
  $r = Lint-One (Join-Path $inc 'IncB.pas') $idb
  Write-Host ("  NOTE include cycle: cycles groups=" + ([regex]::Matches($cyc, '\[\d+ units\]')).Count + ", lint IncB.pas findings=" + @($r.Rows).Count) -ForegroundColor DarkGray
} finally {
  Pop-Location
}
Write-Host ("{0} PASS" -f $script:Passed)
Remove-Scratch
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
