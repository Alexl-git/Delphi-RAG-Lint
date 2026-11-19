<#
  run_v152_HOVERCAP.ps1 -- lane HOVERCAP (1.52, B51 remainder): the hover 'Init:' / 'Set by:' section and
  check-init stay inside their wall-clock cap on the REAL drag-lint index, and an uncapped answer is unchanged.

  Before the lane, hover --format md took 5.3-7.3 s on the DL index with the 5 s cap: check-init's setup
  (ProgramInitOrders, run TWICE per solve: LoadRoots computed it again) ran with no budget check, and once the
  clock ran out the per-use loops (TSolver.JudgeUse's ancestor walk, TFieldSolver.Run's per-use reasoning,
  ComputeMustA's sweep) kept issuing index queries for every remaining routine / use.

  The DB is a COPY of the drag-lint project index (default <Repo>\src\cli\_D-RAG\drag-lint.sqlite); the
  original is never opened.

  Asserts:
    P0 every target resolves in the copy (positive control: a missing symbol would make T1 vacuous).
    T1 hover --format json under DRAGLINT_HOVER_SETBY_MAX_SECONDS=<Cap>: the solve's own clock (set_by.budget.ms)
       <= Cap + Margin, and the process wall clock minus the measured process baseline (B0) <= Cap + Margin.
    T2 positive control: at least one capped hover reports set_by.budget.timed_out = true (the cap was hit,
       so T1 measured the capped path and not a fast target).
    T3 check-init <target> --max-seconds <Cap>: budget.ms and (wall clock - B0) <= Cap + Margin; T3b it says it
       was stopped (budget.timed_out, never SET).
    B0 is the best-of-two wall clock of `query --name` on the same copy: process start, exe load and DB open,
    which no cap can cover (0.5-2 s for the 100 MB Debug exe on a loaded machine).
    T4 a capped hover keeps the writer list complete: set_by.writers == the uncapped check-init writers.
    V1 uncapped (--max-seconds 600) check-init answers are not budget-limited and are byte-identical (minus
       budget.ms) to -BaseExe's when one is given (the pre-lane engine); without -BaseExe, two runs agree.
    U1 DRAGLINT_PROFILE=1 hover --format md of a field with a 'Used in:' line prints the facts breakdown with
       the 'used-in directions' line and a call count >= 1 (it printed only under lint doc-drift before).

    H1 (v152 HOVERCACHE) the whole in-process hover (DRAGLINT_PROFILE 'total') under the default hover cap
       (-HoverCap 5 s) is <= cap + -HoverSlackMs (200 ms); median of -Runs (3) runs per cap target.
    C1-C3 (v152 HOVERCACHE) in one `serve` process the second check_init takes the init orders and the
       interface answers from the per-index-version cache, and answers byte-identically to a fresh CLI run.

  Parameters: -Exe (default src\cli\Win64\Debug\drag-lint.exe), -BaseExe, -Repo, -DbPath (source DB to copy),
  -WorkDir, -Cap (seconds, default 2), -Margin (seconds, default 1), -HoverCap, -HoverSlackMs, -Runs.
#>
[CmdletBinding()]
param(
  [string]$Repo    = '',
  [string]$Exe     = '',
  [string]$BaseExe = '',
  [string]$DbPath  = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-hovercap-$PID",
  [double]$Cap     = 2,
  [double]$Margin  = 1,
  [double]$HoverCap = 5,
  [int]$HoverSlackMs = 200,
  [int]$Runs = 3
)
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}
Write-Host '== v152 HOVERCAP: hover set-by and check-init inside the wall-clock cap ==' -ForegroundColor Cyan
if ($Exe -eq '') { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
if ($DbPath -eq '') { $DbPath = Join-Path $Repo 'src\cli\_D-RAG\drag-lint.sqlite' }
if (-not (Test-Path -LiteralPath $DbPath)) { Write-Host "FATAL: source DB not found: $DbPath (pass -DbPath <copy of the drag-lint index>)" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$copy = Join-Path $WorkDir 'dl-copy.sqlite'
Copy-Item -LiteralPath $DbPath -Destination $copy -Force
Write-Host "  exe $Exe"
Write-Host "  db  $copy (copy of $DbPath)"
# the engine's stderr notes (stale-file, resolver) must not stop the run under Windows PowerShell 5
$ErrorActionPreference = 'Continue'
# warm-up, untimed: the first open of a fresh 300 MB copy pays the file cache / on-access scan, not check-init
$null = & $Exe query --name GBeat --db $copy 2>&1

$capTargets = @(
  'DRagLint.Core.ControlChannel.GBeat',
  'DRagLint.Core.LintBudget.GClock',
  'DRagLint.Charts.Trace.Anchor.TTraceAnchorResolver.FIndex',
  'DRagLint.Storage.SQLite.TSQLiteSymbolStore.FConn'
)
$verdictTargets = @(
  'DRagLint.Query.HappensBefore.Types.GHbTimedOut',
  'DRagLint.Core.LintBudget.GClock',
  'DRagLint.Charts.Trace.Anchor.TTraceAnchorResolver.FIndex',
  'DRagLint.Lint.SharedScope.GUnindexedPeerOf'
)
$capText = $Cap.ToString([Globalization.CultureInfo]::InvariantCulture)

# Best of two runs: a wall-clock guard on a shared machine must not fail on one descheduled run; a real
# overshoot (the lane's bug: seconds of index reads past the cap) shows in both.
function Timed([scriptblock]$sb) {
  $best = $null
  for ($k = 0; $k -lt 2; $k++) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = & $sb
    $sw.Stop()
    if (($null -eq $best) -or ($sw.Elapsed.TotalSeconds -lt $best.Secs)) { $best = @{ Out = $out; Secs = $sw.Elapsed.TotalSeconds } }
  }
  return $best
}
function ParseJson($lines) {
  $raw = ($lines | ForEach-Object { "$_" }) -join "`n"
  $i = $raw.IndexOf('{')
  if ($i -lt 0) { return $null }
  try { return ($raw.Substring($i) | ConvertFrom-Json) } catch { return $null }
}
function WritersText($arr) { if ($null -eq $arr -or @($arr).Count -eq 0) { return '[]' }; return (ConvertTo-Json -InputObject @($arr) -Compress -Depth 8) }
function CheckInitRaw($exe, $qn, $secs) {
  return ((& $exe check-init $qn --db $copy --json --max-seconds $secs 2>$null) -join "`n")
}
function WithoutMs($raw) { return ($raw -replace '"ms":\d+', '"ms":0') }

$b0 = Timed { & $Exe query --name GBeat --db $copy 2>$null }
$base = $b0.Secs
Write-Host ("  B0 process baseline (query --name, best of 2): {0:N2} s" -f $base)
$limit = $Cap + $Margin

# ---- P0 + T1 + T2 + T4: capped hover
$anyTimedOut = $false
$uncapped = @{}
foreach ($q in $capTargets) {
  $env:DRAGLINT_HOVER_SETBY_MAX_SECONDS = $capText
  try {
    $r = Timed { & $Exe hover --qname $q --db $copy --format json 2>$null }
  } finally { $env:DRAGLINT_HOVER_SETBY_MAX_SECONDS = $null }
  $h = ParseJson $r.Out
  $hasSetBy = ($null -ne $h) -and ($h.PSObject.Properties.Name -contains 'set_by')
  Check "P0 $q resolves and has set_by" $hasSetBy ''
  if (-not $hasSetBy) { continue }
  $timed = [bool]$h.set_by.budget.timed_out
  if ($timed) { $anyTimedOut = $true }
  $ms = [double]$h.set_by.budget.ms
  Check ("T1a hover {0}: solve clock <= {1}+{2} s" -f $q, $Cap, $Margin) ($ms -le ($limit * 1000)) ("set-by ms {0}, state {1}, timed_out {2}" -f $ms, $h.set_by.state, $timed)
  Check ("T1b hover {0}: wall - B0 <= {1}+{2} s" -f $q, $Cap, $Margin) (($r.Secs - $base) -le $limit) ("wall {0:N2} s - B0 {1:N2} s" -f $r.Secs, $base)
  if ($q -like '*GClock' -or $q -like '*FIndex') {
    $ci = ParseJson (CheckInitRaw $Exe $q 600)
    $uncapped[$q] = $ci
    if ($timed) {
      Check "T4 capped hover $q keeps every writer" ((WritersText $h.set_by.writers) -ceq (WritersText $ci.writers)) ("capped {0} vs uncapped {1}" -f @($h.set_by.writers).Count, @($ci.writers).Count)
    }
  }
}
Check 'T2 control: at least one capped hover was stopped by the cap (timed_out)' $anyTimedOut ''

# ---- T3: capped check-init
foreach ($q in 'DRagLint.Core.ControlChannel.GBeat', 'DRagLint.Storage.SQLite.TSQLiteSymbolStore.FConn') {
  $r = Timed { CheckInitRaw $Exe $q $capText }
  $j = ParseJson $r.Out
  Check ("T3 check-init {0} --max-seconds {1}: budget.ms and wall - B0 <= {1}+{2} s" -f $q, $Cap, $Margin) (($null -ne $j) -and ([double]$j.budget.ms -le ($limit * 1000)) -and (($r.Secs - $base) -le $limit)) ("ms {0}, wall {1:N2} s, verdict {2}, timed_out {3}" -f $j.budget.ms, $r.Secs, $j.verdict, $j.budget.timed_out)
  Check "T3b check-init $q says it was stopped" (($null -ne $j) -and [bool]$j.budget.timed_out -and ($j.verdict -cne 'SET')) ''
}

# ---- V1: uncapped verdicts unchanged
foreach ($q in $verdictTargets) {
  $new = CheckInitRaw $Exe $q 600
  $nj = ParseJson $new
  Check "V1a $q uncapped answer is not budget-limited" (($null -ne $nj) -and -not [bool]$nj.budget.timed_out -and -not [bool]$nj.budget.exhausted) $(if ($nj) { "verdict $($nj.verdict)" })
  if ($BaseExe -ne '') {
    $old = CheckInitRaw $BaseExe $q 600
    Check "V1b $q uncapped answer == base engine's" ((WithoutMs $new) -ceq (WithoutMs $old)) $(if ($nj) { "verdict $($nj.verdict)" })
  } else {
    $again = CheckInitRaw $Exe $q 600
    Check "V1b $q uncapped answer is deterministic (no -BaseExe given)" ((WithoutMs $new) -ceq (WithoutMs $again)) ''
  }
}

# ---- U1: the 'Used in' profile timer prints from hover
$env:DRAGLINT_PROFILE = '1'
try {
  $err = Join-Path $WorkDir 'prof.err'
  $null = & $Exe hover --qname 'DRagLint.Storage.SQLite.TSQLiteSymbolStore.FConn' --db $copy --format md 2>$err
} finally { $env:DRAGLINT_PROFILE = $null }
$prof = if (Test-Path -LiteralPath $err) { [IO.File]::ReadAllText($err) } else { '' }
$m = [regex]::Match($prof, 'used-in directions\s+([0-9.]+) s \((\d+) call\(s\)')
Check 'U1 DRAGLINT_PROFILE hover prints the used-in directions line with >= 1 call' ($m.Success -and ([int]$m.Groups[2].Value -ge 1)) $(if ($m.Success) { $m.Value } else { 'no line' })

# ---- v152 HOVERCACHE (#113)
# H1 the WHOLE hover (in-process: assembly incl. the facts build, the check-init solve and the render) finishes
#    within the hover cap + HoverSlackMs. Before the lane the cap covered only the solve, so the facts build
#    (0.3-1.3 s on FConn: the 'Used in' directions) came on top of it. Median of -Runs runs per target (the
#    machine is shared). The number is the profile's 'total' (base engines print only 'assemble').
function Median($xs) { $s = @($xs | Sort-Object); if ($s.Count -eq 0) { return [double]::NaN }; return [double]$s[[int][math]::Floor(($s.Count - 1) / 2)] }
$hoverCapText = $HoverCap.ToString([Globalization.CultureInfo]::InvariantCulture)
$hoverLimitMs = $HoverCap * 1000 + $HoverSlackMs
foreach ($q in $capTargets) {
  $totals = @()
  for ($k = 0; $k -lt $Runs; $k++) {
    $herr = Join-Path $WorkDir "h1-$k.err"
    $env:DRAGLINT_PROFILE = '1'
    $env:DRAGLINT_HOVER_SETBY_MAX_SECONDS = $hoverCapText
    try { $null = & $Exe hover --qname $q --db $copy --format json 2>$herr }
    finally { $env:DRAGLINT_PROFILE = $null; $env:DRAGLINT_HOVER_SETBY_MAX_SECONDS = $null }
    $ptxt = if (Test-Path -LiteralPath $herr) { [IO.File]::ReadAllText($herr) } else { '' }
    $mt = [regex]::Match($ptxt, 'HOVER PROFILE .*?total (\d+) ms')
    if (-not $mt.Success) { $mt = [regex]::Match($ptxt, 'HOVER PROFILE assemble (\d+) ms') }
    if ($mt.Success) { $totals += [double]$mt.Groups[1].Value }
  }
  $med = Median $totals
  Check ("H1 hover {0}: total (median of {1}) <= {2} s + {3} ms" -f $q, $Runs, $HoverCap, $HoverSlackMs) (($totals.Count -eq $Runs) -and ($med -le $hoverLimitMs)) ("runs [{0}] ms, median {1}" -f ($totals -join ', '), $med)
}

# C1-C3 the whole-index loads are cached per index version in a long-running engine (serve = MCP; the LSP
#    shares the code): the SECOND check_init (another target) takes ProgramInitOrders and the escape
#    classifier's interface answers from the cache (DRAGLINT_PROFILE 'CHECK-INIT PROFILE' line on stderr),
#    and its answer is byte-identical (minus ms) to a fresh CLI process's (positive control: a stale or
#    partial cache would change it).
$first = 'DRagLint.Query.HappensBefore.Types.GHbTimedOut'
$second = 'DRagLint.Core.LintBudget.GClock'
function QJ($o) { ($o | ConvertTo-Json -Compress -Depth 6) }
$mreq = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
  (QJ @{ jsonrpc='2.0'; id=2; method='tools/call'; params=@{ name='check_init'; arguments=@{ target=$first; max_seconds=600 } } }),
  (QJ @{ jsonrpc='2.0'; id=3; method='tools/call'; params=@{ name='check_init'; arguments=@{ target=$second; max_seconds=600 } } })
) -join "`n"
$merr = Join-Path $WorkDir 'serve.err'
$env:DRAGLINT_PROFILE = '1'
try { $mout = $mreq | & $Exe serve --db $copy 2>$merr | Out-String } finally { $env:DRAGLINT_PROFILE = $null }
$mrep = @{}
foreach ($ln in ($mout -split "`n")) { try { $o = $ln.Trim() | ConvertFrom-Json; if ($o.id) { $mrep[[int]$o.id] = $o } } catch { } }
$profLines = @(([IO.File]::ReadAllText($merr) -split "`r?`n") | Where-Object { $_ -match 'CHECK-INIT PROFILE' })
Check 'C1 serve prints one CHECK-INIT PROFILE line per check_init' ($profLines.Count -eq 2) ("{0} line(s)" -f $profLines.Count)
$p2 = if ($profLines.Count -ge 2) { $profLines[1] } else { '' }
Check 'C2 second check_init: init-orders and interface-answers come from the cache' (($p2 -match 'init-orders \d+ ms \(cached\)') -and ($p2 -match 'interface-answers \d+ ms \(cached\)')) $p2
$mtxt = if ($mrep[3] -and $mrep[3].result -and $mrep[3].result.content) { ([string]@($mrep[3].result.content)[0].text).Trim() } else { '' }
$ctxt = (CheckInitRaw $Exe $second 600).Trim()
Check 'C3 the cached answer == a fresh process answer (minus ms)' (($mtxt -ne '') -and ((WithoutMs $mtxt) -ceq (WithoutMs $ctxt))) ("mcp {0} chars, cli {1} chars" -f $mtxt.Length, $ctxt.Length)

if (-not $env:HB_KEEP_WORK) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("v152 HOVERCAP: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'V152 HOVERCAP: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'V152 HOVERCAP: PASS' -ForegroundColor Green
exit 0
