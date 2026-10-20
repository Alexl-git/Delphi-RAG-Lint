<#
  run_cycle_plan_split_identity.ps1 -- `cycles --plan` output must stay
  byte-identical across the E18 Task 1 planner / renderer split.

  WHY (2026-10-19, E18 T1): TCyclePlanner computed and printed each cycle in one
  pass. `cycles --fix` needs the plan as DATA (TCycleFixPlan), so the per-cycle
  computation moved into BuildPlan and the printing into RenderPlan. That is a
  behaviour-preserving refactor: the playbook a user (or a cheap model) follows
  must not change by one byte. This runner pins it against oracles captured
  from the engine BEFORE the split.

  HOW. Copies circular-demo to a scratch root, indexes it, runs
      cycles --db <db> --edges --causes --plan --format text
  capturing stdout as BYTES, replaces the scratch root with @@ROOT@@ and the db
  path with @@DB@@, and compares byte-for-byte with
  tests\fixtures\cyclefix\oracle\demo-plan.txt (CRLF, ASCII; stdout only -- the
  stderr note `(loaded defaults from ...)` is not part of it). Optional: the same
  for an index of drag-lint itself (-SelfDb + -SelfOracle; skipped when absent),
  where the root is the repo and the oracle is a raw (untokenised) capture.

  POSITIVE CONTROL: one byte of the oracle is flipped in memory and the compare
  must then FAIL -- a compare that cannot fail proves nothing.

  PLAN DATA = RENDERED TEXT (fix round 1). RenderPlan still prints the details
  from the planner's live state, while later tasks APPLY the plan's arrays, so
  identity of the text alone proves nothing about the arrays. The run sets
  DRAGLINT_TEST_DUMP_PLAN=<file>; the engine appends one line per cycle (verdict,
  refusal kinds, Items / Decisions / NewUnits / per-file Edits / DprEdits /
  DprojEdits / Predicted counts and names). Each is checked against what the
  same run printed: numbered moves (Step 1), decision bullets (Step 2), new-unit
  headers (Step 3), `E<n>.` lines per file heading (Step 4; the .dpr and .dproj
  headings for DprEdits / DprojEdits), and the group lines of the expected
  `cycles` output (Predicted = groups - (cycles - 1)). Demo verdicts are pinned:
  Cycle 1 is mechanical since E18 T7 (F5 allows its base class); Cycle 2 is mechanical since E18 T6 (recipe R2, member
  hand-over through an extracted interface); Cycle 3 is mechanical since E18 T5 (recipe R1, routine-call inversion). Its own
  positive control: one dumped count is changed in memory and the same compare
  must then report a mismatch.

  PLATFORM LIBRARY (E18 T6): R2 reads class ancestry from it, so every plan runs with
  --library-db on a COPY of -LibraryDb in the scratch dir (deleted at the end) -- never on the
  real one. Without -LibraryDb on disk the demo section is SKIPPED (its oracle needs the library).
#>
[CmdletBinding()]
param(
  [string]$Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir    = "$env:TEMP\drag-lint-cycle-split-$PID",
  [string]$SelfDb     = '',
  [string]$SelfOracle = '',
  [string]$SelfRoot   = '',
  [string]$LibraryDb  = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($SelfRoot -eq '') { $SelfRoot = $Repo }
$Ascii = [Text.Encoding]::ASCII

# Runs the plan and returns stdout exactly as written (no PowerShell line splitting).
function Get-PlanText([string]$Db, [string]$RunDir) {
  $tag = [Guid]::NewGuid().ToString('N')
  $outFile  = Join-Path $WorkDir ('plan-' + $tag + '.txt')
  $dumpFile = Join-Path $WorkDir ('dump-' + $tag + '.txt')
  $env:DRAGLINT_TEST_DUMP_PLAN = $dumpFile
  try {
    $p = Start-Process -FilePath $Exe -WorkingDirectory $RunDir -NoNewWindow -Wait -PassThru `
      -ArgumentList (@('cycles', '--db', ('"' + $Db + '"'), '--edges', '--causes', '--plan', '--format', 'text') + $LibArgs) `
      -RedirectStandardOutput $outFile -RedirectStandardError (Join-Path $WorkDir 'plan-stderr.txt')
  } finally {
    $env:DRAGLINT_TEST_DUMP_PLAN = $null
  }
  $dump = if (Test-Path $dumpFile) { @([IO.File]::ReadAllLines($dumpFile) | Where-Object { $_ -ne '' }) } else { @() }
  return @{ Exit = $p.ExitCode; Text = $Ascii.GetString([IO.File]::ReadAllBytes($outFile)); Dump = $dump }
}

# What the rendered playbook shows per cycle: the counts / names the plan's arrays must equal.
function Get-TextFacts([string]$Text) {
  $facts = @{}
  $cur = $null; $sect = ''; $file = ''; $inExpected = $false; $wantFence = $false
  foreach ($l in ($Text -split "`r`n")) {
    if ($l -match '^## Cycle (\d+): ') {
      $cur = @{ items = 0; decisions = 0; newunits = [Collections.Generic.List[string]]::new()
                edits = [Collections.Generic.List[string]]::new(); counts = @{}; dpr = 0; dproj = 0; groups = -1 }
      $facts[[int]$Matches[1]] = $cur; $sect = ''; $file = ''; continue
    }
    if ($null -eq $cur) { continue }
    if ($wantFence) { $wantFence = $false; $inExpected = ($l -eq '```text'); if ($inExpected) { $cur.groups = 0 }; continue }
    if ($inExpected) {
      if ($l -eq '```') { $inExpected = $false } elseif ($l -match '^  \[\d+ units\] ') { $cur.groups++ }
      continue
    }
    if ($l -match '^### Step (\d+):') { $sect = 'step' + $Matches[1]; $file = ''; continue }
    if ($l -match '^### ') { $sect = 'other'; $file = ''; continue }
    if ($l -match 'It must print exactly:$') { $wantFence = $true; continue }
    switch ($sect) {
      'step1' { if ($l -match '^\d+\. `') { $cur.items++ } }
      'step2' { if ($l -match '^- `') { $cur.decisions++ } }
      'step3' { if ($l -match '^#### `([^`]+)` -> `') { $cur.newunits.Add($Matches[1]) } }
      'step4' {
        if ($l -match '^#### `([^`]+)`  \(') { $file = $Matches[1]; $cur.counts[$file] = 0; if ($file -notmatch '\.dpr(oj)?$') { $cur.edits.Add($file) } }
        elseif ($file -ne '' -and $l -match '^E\d+\. ') { $cur.counts[$file]++ }
      }
    }
  }
  foreach ($c in $facts.Values) {
    foreach ($k in $c.counts.Keys) {
      if ($k -match '\.dpr$') { $c.dpr = $c.counts[$k] } elseif ($k -match '\.dproj$') { $c.dproj = $c.counts[$k] }
    }
    $c.editText = (@($c.edits | ForEach-Object { '{0}:{1}' -f $_, $c.counts[$_] }) -join '|')
  }
  return $facts
}

function ConvertFrom-DumpLine([string]$Line) {
  $h = @{}
  foreach ($kv in ($Line -split "`t")) { $i = $kv.IndexOf('='); if ($i -gt 0) { $h[$kv.Substring(0, $i)] = $kv.Substring($i + 1) } }
  return $h
}

# Returns the mismatches between the dumped plans and the rendered text (empty = agree).
function Compare-PlanData([string[]]$Dump, $Facts) {
  $bad = [Collections.Generic.List[string]]::new()
  if ($Dump.Count -ne $Facts.Count) { $bad.Add("cycles: dump $($Dump.Count) vs text $($Facts.Count)") }
  foreach ($line in $Dump) {
    $d = ConvertFrom-DumpLine $line
    $n = [int]$d['cycle']
    if (-not $Facts.ContainsKey($n)) { $bad.Add("cycle $n not rendered"); continue }
    $t = $Facts[$n]
    $dumpEdits = (@($d['edits'] -split '\|' | Where-Object { $_ -ne '' -and $_ -notmatch ':0$' }) -join '|')
    $predText = if ($t.groups -lt 0) { 0 } else { $t.groups - ($Facts.Count - 1) }
    $pairs = @(
      @('items', [string]$t.items), @('decisions', [string]$t.decisions),
      @('newunits', ($t.newunits -join '|')), @('dpr', [string]$t.dpr), @('dproj', [string]$t.dproj),
      @('predicted', [string]$predText))
    foreach ($p in $pairs) {
      if ($d[$p[0]] -cne $p[1]) { $bad.Add("cycle ${n} $($p[0]): plan [$($d[$p[0]])] vs text [$($p[1])]") }
    }
    if ($dumpEdits -cne $t.editText) { $bad.Add("cycle ${n} edits: plan [$dumpEdits] vs text [$($t.editText)]") }
    $hasRef = $d['refusals'] -ne ''
    if (($d['verdict'] -eq 'refused') -ne $hasRef) { $bad.Add("cycle ${n} verdict [$($d['verdict'])] vs refusals [$($d['refusals'])]") }
  }
  return ,$bad
}

# Reports the first differing line so a drift is readable.
function Compare-Text([string]$Name, [string]$Actual, [string]$Expected) {
  if ($Actual -ceq $Expected) { Check "$Name byte-identical to the oracle" $true ("({0} bytes)" -f $Expected.Length); return }
  $a = $Actual -split "`n"; $e = $Expected -split "`n"
  $n = [Math]::Min($a.Count, $e.Count); $at = $n
  for ($i = 0; $i -lt $n; $i++) { if ($a[$i] -cne $e[$i]) { $at = $i; break } }
  $got = if ($at -lt $a.Count) { $a[$at].TrimEnd("`r") } else { '<eof>' }
  $exp = if ($at -lt $e.Count) { $e[$at].TrimEnd("`r") } else { '<eof>' }
  Check "$Name byte-identical to the oracle" $false ("first diff at line {0}: got [{1}] expected [{2}] (bytes {3} vs {4})" -f ($at + 1), $got, $exp, $Actual.Length, $Expected.Length)
}

if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$LibCopy = Join-Path $WorkDir 'library-copy.sqlite'
$LibArgs = @()
if (Test-Path $LibraryDb) {
  Copy-Item $LibraryDb $LibCopy
  $LibArgs = @('--library-db', ('"' + $LibCopy + '"'))
}
try {

# --- demo ---------------------------------------------------------------------
Write-Host ''
Write-Host '== circular-demo' -ForegroundColor Cyan
$oraclePath = Join-Path $Repo 'tests\fixtures\cyclefix\oracle\demo-plan.txt'
Check 'demo oracle exists' (Test-Path $oraclePath) $oraclePath
if ($LibArgs.Count -eq 0) {
  Write-Host "== circular-demo: SKIPPED (no platform library DB at $LibraryDb)" -ForegroundColor Yellow
} elseif (Test-Path $oraclePath) {
  $root = Join-Path $WorkDir 'circular-demo'
  New-Item -ItemType Directory $root | Out-Null
  Get-ChildItem (Join-Path $Repo 'circular-demo') -File |
    Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj', '.inc', '.dfm' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  $db = Join-Path $WorkDir 'demo.sqlite'
  & $Exe index --project (Join-Path $root 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir 'index-demo.log')
  Check 'demo indexed' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $run = Get-PlanText $db $WorkDir
  Check 'demo cycles --plan ran' ($run.Exit -eq 0 -or $run.Exit -eq 1) "exit=$($run.Exit)"
  $actual   = $run.Text.Replace($root, '@@ROOT@@').Replace($db, '@@DB@@')
  $expected = $Ascii.GetString([IO.File]::ReadAllBytes($oraclePath))
  Check 'demo oracle is CRLF ASCII and non-empty' (($expected.Length -gt 0) -and ($expected -notmatch "[^`r]`n") -and ($expected -notmatch '[^\x00-\x7F]')) ''
  Compare-Text 'demo' $actual $expected

  # POSITIVE CONTROL: a one-byte change in the oracle must make the compare fail.
  $mid = [int]($expected.Length / 2)
  $flip = if ($expected[$mid] -eq 'x') { 'y' } else { 'x' }
  $broken = $expected.Substring(0, $mid) + $flip + $expected.Substring($mid + 1)
  Check 'positive control: a one-byte oracle change is detected' (-not ($actual -ceq $broken)) "(byte $mid)"

  # Plan data vs the text rendered in the same run.
  $facts = Get-TextFacts $actual
  Check 'demo: plan dump written, one line per cycle' (($run.Dump.Count -eq 3) -and ($facts.Count -eq 3)) "dump=$($run.Dump.Count) text=$($facts.Count)"
  $bad = Compare-PlanData $run.Dump $facts
  Check 'demo: plan arrays equal the rendered playbook' ($bad.Count -eq 0) ($bad -join '; ')
  $byCycle = @{}
  foreach ($l in $run.Dump) { $d = ConvertFrom-DumpLine $l; $byCycle[[int]$d['cycle']] = $d }
  # E18 T7 F5: TDemoSession's switched sites are const parameters read for members / tested for nil -> mechanical.
  Check 'demo: cycle 1 is mechanical (base class allowed by F5)' (($byCycle[1].verdict -eq 'mechanical') -and ($byCycle[1].refusals -eq '')) "[$($byCycle[1].verdict) / $($byCycle[1].refusals)]"
  # E18 T6: cycle 2 is cut by R2 (member hand-over through an extracted interface) -- mechanical.
  Check "demo: cycle 2 is mechanical (R2)" (($byCycle[2].verdict -eq 'mechanical') -and ($byCycle[2].refusals -eq '')) "[$($byCycle[2].verdict) / $($byCycle[2].refusals)]"
  # E18 T5: cycle 3 is cut by R1 (routine-call inversion) -- mechanical, no refusal.
  Check "demo: cycle 3 is mechanical (R1)" (($byCycle[3].verdict -eq 'mechanical') -and ($byCycle[3].refusals -eq '')) "[$($byCycle[3].verdict) / $($byCycle[3].refusals)]"
  Check 'demo: cycle 1 plan is non-trivial (items, new units, edits)' (([int]$byCycle[1].items -gt 0) -and ($byCycle[1].newunits -ne '') -and ($byCycle[1].edits -ne '')) $run.Dump[0]

  # POSITIVE CONTROL: one dumped count off by one must be reported by the same compare.
  $mutated = @($run.Dump)
  $mutated[0] = [regex]::Replace($mutated[0], 'items=(\d+)', { param($m) 'items=' + ([int]$m.Groups[1].Value + 1) })
  $bad2 = Compare-PlanData $mutated $facts
  Check 'positive control: a one-count plan change is detected' (($mutated[0] -cne $run.Dump[0]) -and ($bad2.Count -gt 0)) ($bad2 -join '; ')
}

# --- self (optional) --------------------------------------------------------------
Write-Host ''
if ($SelfDb -ne '' -and $SelfOracle -ne '' -and (Test-Path $SelfDb) -and (Test-Path $SelfOracle)) {
  Write-Host '== self (drag-lint)' -ForegroundColor Cyan
  $run = Get-PlanText $SelfDb $WorkDir
  Check 'self cycles --plan ran' ($run.Exit -eq 0 -or $run.Exit -eq 1) "exit=$($run.Exit)"
  $actual   = $run.Text.Replace($SelfRoot, '@@ROOT@@').Replace($SelfDb, '@@DB@@')
  # A raw capture may hold the stderr note `(loaded defaults from ...)` (2>&1); it is not plan text.
  $expected = $Ascii.GetString([IO.File]::ReadAllBytes($SelfOracle)).Replace($SelfRoot, '@@ROOT@@').Replace($SelfDb, '@@DB@@')
  $expected = [regex]::Replace($expected, '(?m)^\(loaded defaults from [^\r\n]*\r\n', '')
  Compare-Text 'self' $actual $expected
  $facts = Get-TextFacts $actual
  Check 'self: plan dump written, one line per cycle' (($run.Dump.Count -gt 0) -and ($run.Dump.Count -eq $facts.Count)) "dump=$($run.Dump.Count) text=$($facts.Count)"
  $bad = Compare-PlanData $run.Dump $facts
  Check 'self: plan arrays equal the rendered playbook' ($bad.Count -eq 0) ($bad -join '; ')
} else {
  Write-Host '== self: SKIPPED (pass -SelfDb and -SelfOracle)' -ForegroundColor Yellow
}
} finally {
  if (Test-Path -LiteralPath $LibCopy) { [IO.File]::Delete($LibCopy) }
}

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
