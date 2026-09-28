<#
  run_cycle_participant_unit.ps1 -- `cycle-participant-unit`, the PER-UNIT view
  of circular-uses (NR-C1, BACKLOG-TRIAGE-2026-09-28).

  WHY. circular-uses reports ONE finding per cycle, anchored at the
  alphabetically-first unit, so `lint <any other member>` -- what an editor
  shows for the open file -- said nothing about the cycle it is in. This rule
  puts one info finding on EACH member's `unit` line, names the group, says
  whether the coupling runs through an interface, and points at
  `cycles --plan`. It is a projection of the same Tarjan pass, so it can never
  name a different set of units than circular-uses. OFF by default.

  FIXTURES (each unit's `unit` clause is on LINE 3, so an anchor at line 1 would
  fail -- a header comment sits above it):
    intf\  uA interface-uses uB, uB implementation-uses uA   -> coupled via an interface
           uBystander, used by the program only             -> NOT in the cycle
    impl\  uP implementation-uses uQ, uQ implementation-uses uP -> implementation-only

  CASES
    T1 lint-all --rule: exactly uA and uB, each at line 3, both saying INTERFACE
    T2 the bystander unit gets no finding
    T3 a per-file `lint uB.pas --rule` (uB is NOT circular-uses' anchor) shows it
    T4 the implementation-only cycle says implementation-only
    P1 CONTROL circular-uses fires on the same fixture (one finding) -- the two
       rules agree about the cycle
    P2 CONTROL a default lint-all (rule OFF) prints no cycle-participant-unit

  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_cycle_participant_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
function U([string]$Name, [string]$IntfUses, [string]$ImplUses) {
  $iu = if ($IntfUses) { "`nuses $IntfUses;`n" } else { '' }
  $mu = if ($ImplUses) { "`nuses $ImplUses;`n" } else { '' }
  return "{ header comment }`n`nunit $Name;`n`ninterface$iu`nprocedure Go$Name;`n`nimplementation$mu`nprocedure Go$Name;`nbegin`nend;`n`nend.`n"
}

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$intf = Join-Path $WorkDir 'intf'
$impl = Join-Path $WorkDir 'impl'
New-Item -ItemType Directory -Path $intf, $impl -Force | Out-Null
W (Join-Path $intf 'uA.pas') (U 'uA' 'uB' '')
W (Join-Path $intf 'uB.pas') (U 'uB' '' 'uA')
W (Join-Path $intf 'uBystander.pas') (U 'uBystander' '' '')
W (Join-Path $intf 'App.dpr') "program App;`nuses`n  uA in 'uA.pas',`n  uB in 'uB.pas',`n  uBystander in 'uBystander.pas';`nbegin`nend.`n"
W (Join-Path $impl 'uP.pas') (U 'uP' '' 'uQ')
W (Join-Path $impl 'uQ.pas') (U 'uQ' '' 'uP')
W (Join-Path $impl 'Imp.dpr') "program Imp;`nuses`n  uP in 'uP.pas',`n  uQ in 'uQ.pas';`nbegin`nend.`n"

$dbI = Join-Path $WorkDir 'intf.sqlite'
$dbP = Join-Path $WorkDir 'impl.sqlite'
& $exePath index --project (Join-Path $intf 'App.dpr') --db $dbI 2>&1 | Out-Null
& $exePath index --project (Join-Path $impl 'Imp.dpr') --db $dbP 2>&1 | Out-Null
Check 'V both fixture indexes were built' ((Test-Path $dbI) -and (Test-Path $dbP)) ''

# Callers wrap the call in @(): PowerShell unrolls a one-element array on return,
# and $x[0] of the resulting STRING is its first character.
function Findings([string[]]$ArgList, [string]$Rule) {
  $o = & $exePath @ArgList 2>&1 | ForEach-Object { "$_" }
  return @($o | Where-Object { $_ -match (' ' + [regex]::Escape($Rule) + ': ') })
}
function FileOf([string]$Line) { if ($Line -match '([^\\/]+\.pas):(\d+):') { return "$($Matches[1]):$($Matches[2])" } return '' }

# ---- T1 / T2 -----------------------------------------------------------------
$f = @(Findings @('lint-all', '--db', $dbI, '--rule', 'cycle-participant-unit') 'cycle-participant-unit')
$where = @($f | ForEach-Object { FileOf $_ } | Sort-Object)
Check 'T1 exactly uA and uB, each anchored on its `unit` line (3)' (($where -join ',') -eq 'uA.pas:3,uB.pas:3') ($where -join ',')
Check 'T1b both say the coupling runs through an INTERFACE' (@($f | Where-Object { $_ -match 'INTERFACE coupling' }).Count -eq 2) ($f -join ' | ')
Check 'T1c the message names the group and points at cycles --plan' (@($f | Where-Object { $_ -match '\(uA, uB\)' -and $_ -match 'cycles --plan' }).Count -eq 2) ($f -join ' | ')
Check 'T2 the bystander unit gets no finding' (@($f | Where-Object { $_ -match 'uBystander' }).Count -eq 0) ''

# ---- T3 per-file view of the NON-anchor member --------------------------------
$pf = @(Findings @('lint', (Join-Path $intf 'uB.pas'), '--db', $dbI, '--rule', 'cycle-participant-unit') 'cycle-participant-unit')
Check 'T3 per-file lint of uB (not circular-uses'' anchor) shows its finding' (($pf.Count -eq 1) -and ((FileOf $pf[0]) -eq 'uB.pas:3')) ($pf -join ' | ')

# ---- T4 implementation-only ----------------------------------------------------
$fp = @(Findings @('lint-all', '--db', $dbP, '--rule', 'cycle-participant-unit') 'cycle-participant-unit')
Check 'T4 an implementation-only cycle: two findings saying implementation-only' `
      (($fp.Count -eq 2) -and (@($fp | Where-Object { $_ -match 'implementation-only' }).Count -eq 2)) ($fp -join ' | ')

# ---- controls ------------------------------------------------------------------
$cu = @(Findings @('lint-all', '--db', $dbI, '--rule', 'circular-uses') 'circular-uses')
Check 'P1 CONTROL circular-uses sees the same cycle (one finding naming uA and uB)' (($cu.Count -eq 1) -and ($cu[0] -match 'uA') -and ($cu[0] -match 'uB')) ($cu -join ' | ')
$def = @(Findings @('lint-all', '--db', $dbI) 'cycle-participant-unit')
Check 'P2 CONTROL the rule is OFF by default (a plain lint-all prints none)' ($def.Count -eq 0) ($def -join ' | ')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("C:\TEMP\draglint_cycle_participant_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
