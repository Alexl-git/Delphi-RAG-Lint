<#
  run_rule_load_parallel.ps1 -- the per-process cost of loading the .scm rules.

  WHY (lane IPERF, 2026-10-28). tests\lint\run_lint_tests.ps1 went from ~300 s
  to 1148 s between 1.36.0 and gaps/int. Every `lint <file>` process compiles
  every rules\*.scm with ts_query_new before it reads a byte of the file, and
  the corpus grew from 55 to 95 queries: setup measured 1.6 s -> 3.2 s on a
  fixture whose rules themselves ran in 10 ms. The same fixed cost lands on every
  IDE single-file lint (budget 8 s).

  The guard reads the loader's own DRAGLINT_PROFILE line
      [rule-load] <n> rules compiled: wall <w> s, cpu-sum <c> s
  and asserts the compile is spread over cores: wall well below the summed
  per-rule time. A ratio, not a wall-clock bound, so machine load moves both
  sides together. Best of 3 runs.

  Positive control: the line exists and names >= 50 rules (a run that loaded
  nothing would pass any ratio).
#>
[CmdletBinding()]
param([string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check([string]$Name,[bool]$Ok,[string]$Detail=''){
  $s = if($Ok){'PASS'}else{'FAIL'}; $c = if($Ok){'Green'}else{'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $s,$Name,$Detail) -ForegroundColor $c
  if(-not $Ok){$script:Failed=$true}
}
if(-not(Test-Path $Exe)){Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2}
$Exe = (Resolve-Path $Exe).Path
$rulesDir = (Resolve-Path "$PSScriptRoot\..\..\rules").Path
$fixture  = (Resolve-Path "$PSScriptRoot\..\lint\assert-call.pas").Path
$cores = [Environment]::ProcessorCount

$best = $null; $line = ''; $total = 99.0; $rules = 0
$env:DRAGLINT_PROFILE = '1'
try {
  foreach ($i in 1..3) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = & $Exe lint $fixture --json --rules-dir $rulesDir 2>&1 | ForEach-Object { "$_" }
    $total = [Math]::Min($total, $sw.Elapsed.TotalSeconds)
    $l = $out | Where-Object { $_ -match '^\[rule-load\] (\d+) rules compiled: wall ([\d.]+) s, cpu-sum ([\d.]+) s' } | Select-Object -First 1
    if ($l -and ($l -match '^\[rule-load\] (\d+) rules compiled: wall ([\d.]+) s, cpu-sum ([\d.]+) s')) {
      $n = [int]$Matches[1]; $w = [double]$Matches[2]; $c = [double]$Matches[3]
      $r = if ($c -gt 0) { $w / $c } else { 1.0 }
      if (($null -eq $best) -or ($r -lt $best)) { $best = $r; $line = $l; $rules = $n }
    }
  }
} finally { $env:DRAGLINT_PROFILE = $null }

Check 'rule-load profile line present' ($null -ne $best) $line
Check 'rule-load names >= 50 rules (positive control)' ($rules -ge 50) "rules=$rules"
if ($cores -ge 4) {
  Check 'rule compile runs in parallel (wall <= 0.6 x cpu-sum)' (($null -ne $best) -and ($best -le 0.6)) ("ratio={0:n2} cores={1}" -f $best, $cores)
} else {
  Write-Host "  [SKIP] parallel ratio: only $cores logical CPUs"
}
# A query that does not compile and a duplicate id must still be reported, in
# order, without crashing: the parallel loader hands each compiled query to its
# rule, and a broken one once was freed twice (EAccessViolation after the
# RULE-LOAD-FAIL line).
$bad = Join-Path ([IO.Path]::GetTempPath()) ("dl-ruleload-" + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path (Join-Path $bad 'sub'))
Copy-Item (Join-Path $rulesDir 'bare-except.*') $bad
Copy-Item (Join-Path $rulesDir 'bare-except.*') (Join-Path $bad 'sub')
[IO.File]::WriteAllText((Join-Path $bad 'zz-broken.scm'), "((exprCall (nosuchnode)) @warn`r`n")
$bo = (& $Exe lint $fixture --rules-dir $bad 2>&1 | ForEach-Object { "$_" }) -join "`n"
Check 'broken .scm reported as RULE-LOAD-FAIL' ($bo -match 'RULE-LOAD-FAIL .*zz-broken\.scm: tree-sitter query compile failed') ''
Check 'duplicate .scm reported as RULE-DUPLICATE-ID' ($bo -match 'RULE-DUPLICATE-ID bare-except') ''
Check 'no crash after a failed rule load' (($bo -notmatch 'FATAL') -and ($bo -match '\d+ finding\(s\)')) ''
[IO.Directory]::Delete($bad, $true)
Check 'single-file lint inside the IDE 8 s budget' ($total -lt 8.0) ("best={0:n2} s" -f $total)

# [after-checkers] budget (lane PERF2, 2026-10-28). The phase between the last
# checker and the end of output (FinalizeAndOutput) went 0.03 -> 0.25 s per
# `lint` process: the review-marker pass rebuilt the whole rule catalogue --
# every rules\*.json sidecar plus compliance.json -- on every file, marker or
# not. Median over a 20-fixture sample so one slow run on a busy machine does
# not decide it; 0.04 s sits well under the measured unfixed 0.07-0.09 s
# (Debug, idle-ish box) and well over the fixed ~0.005 s.
$sample = @(Get-ChildItem (Join-Path $PSScriptRoot '..\lint') -Filter '*.pas' -File | Sort-Object Name | Select-Object -First 20)
$after = @()
$env:DRAGLINT_PROFILE = '1'
try {
  foreach ($fx in $sample) {
    $o = & $Exe lint $fx.FullName --rules-dir $rulesDir 2>&1 | ForEach-Object { "$_" }
    $m = $o | Where-Object { $_ -match '\[lint-phase\] after-checkers\s+([\d.]+) s' } | Select-Object -First 1
    if ($m -and ($m -match '\[lint-phase\] after-checkers\s+([\d.]+) s')) { $after += [double]$Matches[1] }
  }
} finally { $env:DRAGLINT_PROFILE = $null }
Check 'after-checkers profile line on every sampled fixture (positive control)' (($sample.Count -eq 20) -and ($after.Count -eq $sample.Count)) ("fixtures={0} lines={1}" -f $sample.Count, $after.Count)
$med = 99.0
if ($after.Count -gt 0) { $s = @($after | Sort-Object); $med = $s[[int][Math]::Floor(($s.Count - 1) / 2)] }
Check 'after-checkers median <= 0.04 s per file' ($med -le 0.04) ("median={0:n3} s max={1:n3} s" -f $med, (($after | Measure-Object -Maximum).Maximum))

Write-Host ''
if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red; exit 1}else{Write-Host 'PASS' -ForegroundColor Green; exit 0}