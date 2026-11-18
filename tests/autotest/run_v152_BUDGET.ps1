# v152 BUDGET: per-rule runtime budget in the v151/v152 rule frame (PLAN 1.52 D9) and the near-parse-limit warning.
# Usage: run_v152_BUDGET.ps1 [-Exe <drag-lint.exe>]
#
# Budget cases use tests\autotest\fixtures\v152budget\BudgetFixture.pas, which raises one weak-cipher and one
# writeln-in-gui-app finding (both from the APP lane). The test seam DRAGLINT_TEST_RULE_SLEEP_MS=<rule>=<ms>
# (DRagLint.Core.LintBudget) sleeps the first time a lane asks for that rule in a file, so the rule overruns.
#   B1 baseline (no seam, default budget): both findings, no rule-skipped-budget note.
#   B2 seam 900 ms, budget 300 ms: writeln-in-gui-app dropped, ONE note naming it, weak-cipher kept (positive control).
#   B3 seam 900 ms, rule_time_budget_ms 0: budget off -> both findings, no note.
#   B4 seam 900 ms, budget 300 ms, DRAGLINT_NO_BUDGET=1: budget off -> both findings, no note.
#   B5 seam 100 ms, budget 2000 ms: under budget -> both findings, no note.
#   B6 rules --json lists rule-skipped-budget (category other, severity info, on).
#   B7 seam 900 ms, budget 300 ms, --no-budget: budget off -> both findings, no note.
#   B8 lint-all with the seam over the default budget: ONE 'rule budget:' summary line naming the rule, plus the note.
#   T1 TScan fixture (stringlist rules through alias / Self.F := / comma lists): findings pinned from the pre-change engine.
# B2-B5, B7, B8 need the frame / CLI hunks of lane BUDGET (HANDOVER patches applied by INT).
# Parse-limit cases (index of a scratch folder, private --db):
#   P1 a 1900 KB unit (within 10 percent of 2048 KB) -> one WARN line naming it and the limit.
#   P2 a 1000 KB unit -> no WARN line (negative) ...
#   P3 ... while a 2100 KB unit in the same run gets the existing SKIP line (positive control for the walker output).
param(
  [string]$Exe = 'third_party\dll-win64\drag-lint.exe'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not [IO.Path]::IsPathRooted($Exe)) { $Exe = Join-Path $repo $Exe }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "SKIP: exe not found: $Exe"; exit 77 }
$fixture = Join-Path $PSScriptRoot 'fixtures\v152budget\BudgetFixture.pas'
$work = Join-Path $env:TEMP ('v152budget-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$script:fail = 0
$script:pass = 0
function Check([bool]$Ok, [string]$What) {
  if ($Ok) { $script:pass++; Write-Host "PASS $What" } else { $script:fail++; Write-Host "FAIL $What" }
}

function RunLint([string]$CfgJson, [string]$Sleep, [string]$NoBudget) {
  $cfg = Join-Path $work 'cfg.json'
  [IO.File]::WriteAllText($cfg, $CfgJson, [Text.Encoding]::ASCII)
  $env:DRAGLINT_TEST_RULE_SLEEP_MS = $Sleep
  $env:DRAGLINT_NO_BUDGET = $NoBudget
  try { $out = & $Exe lint $fixture --config $cfg --json 2>$null }
  finally {
    Remove-Item Env:\DRAGLINT_TEST_RULE_SLEEP_MS -ErrorAction SilentlyContinue
    Remove-Item Env:\DRAGLINT_NO_BUDGET -ErrorAction SilentlyContinue
  }
  $txt = ($out -join "`n").Trim()
  if ($txt -eq '') { return @() }
  # lint --json is a bare array; rule id is "rule", line is "start_line"
  return @($txt | ConvertFrom-Json)
}
function Rules($F) { return @($F | ForEach-Object { $_.rule }) }

try {
  # B1
  $b1 = RunLint '{}' '' ''
  Write-Host ('raw B1: ' + (($b1 | ForEach-Object { "$($_.rule)@$($_.start_line)" }) -join ', '))
  Check ((Rules $b1) -contains 'weak-cipher') 'B1 baseline has weak-cipher'
  Check ((Rules $b1) -contains 'writeln-in-gui-app') 'B1 baseline has writeln-in-gui-app'
  Check (-not ((Rules $b1) -contains 'rule-skipped-budget')) 'B1 baseline has no rule-skipped-budget note'

  # B2
  $b2 = RunLint '{ "rule_time_budget_ms": 300 }' 'writeln-in-gui-app=900' ''
  Write-Host ('raw B2: ' + (($b2 | ForEach-Object { "$($_.rule)@$($_.start_line): $($_.message)" }) -join ' | '))
  $notes = @($b2 | Where-Object { $_.rule -eq 'rule-skipped-budget' })
  Check ($notes.Count -eq 1) "B2 exactly one rule-skipped-budget note (got $($notes.Count))"
  Check (($notes.Count -ge 1) -and ($notes[0].message -match 'writeln-in-gui-app') -and ($notes[0].message -match '300 ms')) 'B2 note names the rule and the budget'
  Check (($notes.Count -ge 1) -and ($notes[0].severity -eq 'info')) 'B2 note severity is info'
  Check (-not ((Rules $b2) -contains 'writeln-in-gui-app')) 'B2 overrunning rule is skipped for the file'
  Check ((Rules $b2) -contains 'weak-cipher') 'B2 positive control: the other rule of the same lane still reports'

  # B3
  $b3 = RunLint '{ "rule_time_budget_ms": 0 }' 'writeln-in-gui-app=900' ''
  Check ((Rules $b3) -contains 'writeln-in-gui-app') 'B3 budget 0 = off: writeln-in-gui-app reported'
  Check (-not ((Rules $b3) -contains 'rule-skipped-budget')) 'B3 budget 0 = off: no note'

  # B4
  $b4 = RunLint '{ "rule_time_budget_ms": 300 }' 'writeln-in-gui-app=900' '1'
  Check ((Rules $b4) -contains 'writeln-in-gui-app') 'B4 DRAGLINT_NO_BUDGET=1: writeln-in-gui-app reported'
  Check (-not ((Rules $b4) -contains 'rule-skipped-budget')) 'B4 DRAGLINT_NO_BUDGET=1: no note'

  # B5
  $b5 = RunLint '{}' 'writeln-in-gui-app=100' ''
  Check ((Rules $b5) -contains 'writeln-in-gui-app') 'B5 under the default budget: writeln-in-gui-app reported'
  Check (-not ((Rules $b5) -contains 'rule-skipped-budget')) 'B5 under the default budget: no note'

  # B7: the CLI switch --no-budget (same effect as DRAGLINT_NO_BUDGET)
  $cfg7 = Join-Path $work 'cfg7.json'
  [IO.File]::WriteAllText($cfg7, '{ "rule_time_budget_ms": 300 }', [Text.Encoding]::ASCII)
  $env:DRAGLINT_TEST_RULE_SLEEP_MS = 'writeln-in-gui-app=900'
  try { $b7 = @(((& $Exe lint $fixture --config $cfg7 --no-budget --json 2>$null) -join "`n") | ConvertFrom-Json) }
  finally { Remove-Item Env:\DRAGLINT_TEST_RULE_SLEEP_MS -ErrorAction SilentlyContinue }
  Check ((Rules $b7) -contains 'writeln-in-gui-app') 'B7 --no-budget: writeln-in-gui-app reported'
  Check (-not ((Rules $b7) -contains 'rule-skipped-budget')) 'B7 --no-budget: no note'

  # B8: lint-all names the skipped rules once in its summary (stderr note line); the default budget applies
  $fdir = Join-Path $work 'fx'
  [void][IO.Directory]::CreateDirectory($fdir)
  Copy-Item -LiteralPath $fixture -Destination $fdir
  $fdb = Join-Path $work 'fx.sqlite'
  & $Exe index $fdir --db $fdb *> $null
  $env:DRAGLINT_TEST_RULE_SLEEP_MS = 'writeln-in-gui-app=2600'
  try { $b8err = @(& $Exe lint-all --db $fdb 2>&1 | ForEach-Object { "$_" }) }
  finally { Remove-Item Env:\DRAGLINT_TEST_RULE_SLEEP_MS -ErrorAction SilentlyContinue }
  $sum = @($b8err | Where-Object { $_ -match 'rule budget:' })
  Write-Host ('raw B8 summary: ' + ($sum -join ' | '))
  Check (($sum.Count -eq 1) -and ($sum[0] -match '1 skip\(s\) on 1 file\(s\): writeln-in-gui-app \(1 file\)')) 'B8 lint-all summary names the skipped rule once'
  Check (@($b8err | Where-Object { $_ -match '\[rule-skipped-budget\]|rule-skipped-budget' -and $_ -match 'BudgetFixture' }).Count -ge 1) 'B8 lint-all also reports the per-file note'

  # B6
  $cat = (& $Exe rules --json 2>$null) | ConvertFrom-Json
  $row = @($cat.rules | Where-Object { $_.id -eq 'rule-skipped-budget' })
  Check ($row.Count -eq 1) 'B6 rules --json lists rule-skipped-budget'
  Check (($row.Count -eq 1) -and $row[0].default_severity -eq 'info' -and $row[0].category -eq 'other' -and $row[0].default_enabled) 'B6 rule-skipped-budget is info / other / on'

  # T1: TScan (RTLCOLL.Support) runs its alias / creation / declaration patterns anchored on their literal now;
  # the fixture's findings were captured with the 1.52 INT engine before the change (alias class(TStringList),
  # Self.F := creation, comma field list) and must not move.
  $tfx = Join-Path $PSScriptRoot 'fixtures\v152budget\TScanFixture.pas'
  $cfg0 = Join-Path $work 'cfg0.json'
  [IO.File]::WriteAllText($cfg0, '{}', [Text.Encoding]::ASCII)
  $tout = (& $Exe lint $tfx --config $cfg0 --json 2>$null) -join "`n"
  $got = @(($tout | ConvertFrom-Json) | Where-Object { $_.rule -match '^(stringlist-|dictionary-get)' } | ForEach-Object { "$($_.rule)@$($_.start_line)" })
  Write-Host ('raw T1: ' + ($got -join ', '))
  Check (($got -join ',') -eq 'stringlist-objects-leak@40,stringlist-unsorted@41,stringlist-unsorted@53,stringlist-unsorted@54') 'T1 TScan fixture findings unchanged (4, pinned from the pre-change engine)'

  # P1-P3: near-parse-limit warning at index time
  $dir = Join-Path $work 'big'
  [void][IO.Directory]::CreateDirectory($dir)
  function MakeUnit([string]$Name, [int]$KB) {
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append("unit $Name;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`n")
    $line = '// ' + ('x' * 96) + "`r`n"   # 101 bytes
    while ($sb.Length -lt ($KB * 1024)) { [void]$sb.Append($line) }
    [void]$sb.Append("`r`nend.`r`n")
    [IO.File]::WriteAllText((Join-Path $dir "$Name.pas"), $sb.ToString(), [Text.Encoding]::ASCII)
  }
  MakeUnit 'NearLimit' 1900
  MakeUnit 'FarBelow' 1000
  MakeUnit 'OverLimit' 2100
  $db = Join-Path $work 'idx.sqlite'
  $log = @(& $Exe index $dir --db $db 2>&1 | ForEach-Object { "$_" })
  $warn = @($log | Where-Object { $_ -match 'WARN' -and $_ -match 'parse limit' })
  Write-Host ('raw index WARN/SKIP lines: ' + (($log | Where-Object { $_ -match 'WARN|SKIP' }) -join ' | '))
  Check (@($warn | Where-Object { $_ -match 'NearLimit\.pas' -and $_ -match '2048 KB' }).Count -eq 1) 'P1 1900 KB unit gets one near-limit WARN line'
  Check (@($warn | Where-Object { $_ -match 'FarBelow\.pas' }).Count -eq 0) 'P2 1000 KB unit gets no WARN line'
  Check (@($log | Where-Object { $_ -match 'SKIP' -and $_ -match 'OverLimit\.pas' }).Count -eq 1) 'P3 positive control: 2100 KB unit gets the SKIP line'
} finally {
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: scratch left at $work" }
}
Write-Host "RESULT: $script:pass pass, $script:fail FAIL"
if ($script:fail -gt 0) { exit 1 }
exit 0
