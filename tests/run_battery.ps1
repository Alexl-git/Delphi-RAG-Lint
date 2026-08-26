<#
  run_battery.ps1 -- THE battery. Runs EVERY runner under tests\, not a subset.

  Why this exists
  ---------------
  "Full battery" was folklore for the whole of Auto-Document Phase 3: six tasks
  in a row reported green against tests\autodoc + tests\autotest only, while
  tests\ held substantially more. The rest had never been run by any task in the
  phase, and one of them (autofix\run_missing_doc_fix.ps1) had been red since
  Task 3 changed the emitter. An unstated definition silently became the
  definition. This script IS the definition, and it prints its own denominator
  before running anything so a shrinking battery is visible instead of silent.

  Deliberately no counts in this comment. The old constraint failed BECAUSE it
  hardcoded a number ("31 tests"); a different hardcoded number is the same
  defect wearing a new value. The printed denominator is the only statement of
  the count that cannot go stale -- read it from the run, not from prose.

  What a runner is
  ----------------
  A runner is a file named run_*.ps1 anywhere under tests\ (RECURSIVE -- a
  non-recursive scan misses tests\lint-project's runners, which live one level
  down in per-case subdirectories; that discrepancy is how two different counts
  could both look right). Enumeration is dynamic. There is deliberately no
  hardcoded list: a literal list is exactly what drifted for six tasks.

  Exclusions
  ----------
  Only the -Exclude patterns below, each with a stated reason. Non-runner .ps1
  helpers (tests\autotest\_manifest_common.ps1, tests\preprocess\lib\oracle.ps1,
  tests\lint-store\enclosing-attribution\verify.ps1,
  tests\textindex\fts5_spike.ps1, tests\textindex\schema_v10.ps1) are not
  excluded -- they are simply not named run_*.ps1, so they never enter the set.

  Usage
  -----
    pwsh -File tests\run_battery.ps1                       # everything (default)
    pwsh -File tests\run_battery.ps1 -Include autodoc,autotest
    pwsh -File tests\run_battery.ps1 -Include callresolve -TimeoutSec 300
    pwsh -File tests\run_battery.ps1 -List                 # enumerate only
    pwsh -File tests\run_battery.ps1 -LogDir C:\TEMP\battery

  -Include / -Exclude match against the repo-relative path with forward slashes
  (e.g. 'tests/autodoc/run_doc_p3_marker.ps1'), so a bare suite name like
  'autodoc' selects the whole suite and a runner name selects one runner.
  Comma-separated lists work (they are split here rather than relying on
  PowerShell array binding, which `pwsh -File` does not do). Both switches print
  a "this is NOT the full battery" banner, in the header AND in the summary.

  A BATTERY NUMBER IS A PROPERTY OF A TREE, NOT OF A COMMIT (register K41)
  -----------------------------------------------------------------------
  A clean checkout of c4b78d0 enumerates 192 executed / 193 found; the working
  tree this phase was done in enumerates 194 / 195, because two runners
  (run_hover_callsite.ps1, run_typeat_generic_member.ps1) are UNTRACKED files
  that exist only there. Every report in the phase quoted the larger pair as if
  it described the commit. So this script now prints WHICH TREE it counted in --
  the path, the commit, whether the tree is dirty, and how many of the runners it
  found are untracked -- and any report quoting the denominator must quote that
  line with it.

  The same divergence has a second half that is not about counting: reproducing a
  green battery in a fresh checkout also needs a `rules` directory beside the exe,
  and without it a batch of runners fails for a reason none of them states. The
  tracked source is rules\ at the repo root (112 files); the copies beside the
  exe are gitignored (.gitignore:14 `Win64/`, :63 `third_party/*/rules/`) and
  nothing stages them, so a clone has none. That is now a LOUD, NAMED
  precondition printed before the first runner starts, instead of N obscure
  failures a hundred lines later.

  Exit codes
  ----------
    0  every runner in the enumerated set passed
    1  at least one FAIL or TIMEOUT
    2  the filters selected ZERO runners -- never reported as green
#>
[CmdletBinding()]
param(
  # Substring/wildcard filters kept from the enumerated set. Default: everything.
  [string[]]$Include = @(),

  # Substring/wildcard filters removed from the enumerated set. Every entry here
  # MUST carry a reason in the table below -- an undocumented exclusion is the
  # bug this script exists to kill. Passing this ALWAYS raises the same
  # "NOT the full battery" banner -Include raises: -Include visibly collapses the
  # denominator to something obviously small, whereas -Exclude removes a handful
  # from an otherwise-full run and leaves a count that still LOOKS right. That is
  # the more dangerous of the two, so it gets the louder warning, not the quieter.
  [string[]]$Exclude = @(),

  # Per-runner wall-clock budget.
  #
  # 300, not the 180 the 2026-07-27 sweep used. tests\lint\run_lint_tests.ps1
  # takes 194.1 s standalone on this machine and passes 156/156, so at 180 it was
  # killed and reported TIMEOUT -- but only when the machine was busy, so the same
  # commit reported 0 timeouts on one run and 1 on the next. An intermittent red
  # that is really "the cap is below the runner's honest cost" is worse than a
  # slow suite: it teaches a reader to discount timeouts, which is exactly when a
  # real hang gets waved through.
  #
  # This does NOT weaken the guard. A genuinely hung runner is still killed, and
  # killed with its whole process tree, because an orphaned drag-lint.exe holds a
  # .sqlite lock that fails the NEXT runner too. Raise this again only with a
  # measured standalone time for the runner that needed it.
  [int]$TimeoutSec = 300,

  # Enumerate and print the set, run nothing.
  [switch]$List,

  # Where per-runner transcripts go. Default: a timestamped dir under $env:TEMP.
  [string]$LogDir = ''
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Documented default exclusions. Format: pattern = one-line reason.
# KEEP THIS AS SHORT AS POSSIBLE. Anything added here is a hole in the battery,
# so a reason that is not "this is not a test" needs a second opinion.
# ---------------------------------------------------------------------------
$DefaultExclusions = [ordered]@{
  'tests/run_battery.ps1' = 'this driver itself -- it is named run_*.ps1 and would recurse into itself forever'
}

$repoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testsRoot = (Resolve-Path $PSScriptRoot).Path

function RelPath([string]$full) {
  $full.Substring($repoRoot.Length + 1).Replace('\', '/')
}

# Flatten a filter list into individual patterns.
#
# Load-bearing under `pwsh -File`, which is how every caller invokes this script:
# -File does NOT parse PowerShell array syntax, so `-Include autodoc,autotest`
# arrives as the SINGLE string 'autodoc,autotest' (and quoting it makes the quote
# characters part of the value). That matched no runner at all, so this script's
# own documented usage example selected ZERO runners and still exited 0 -- a green
# report from an empty battery, which is the precise failure this script exists to
# prevent. Split on commas, and strip stray quotes, so the documented form works.
function SplitPatterns([string[]]$pats) {
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($p in $pats) {
    if ($null -eq $p) { continue }
    foreach ($piece in ($p -split ',')) {
      $t = $piece.Trim().Trim("'", '"')
      if (-not [string]::IsNullOrWhiteSpace($t)) { $out.Add($t) }
    }
  }
  return $out.ToArray()
}

function MatchesAny([string]$rel, [string[]]$pats) {
  foreach ($p in $pats) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $g = $(if ($p -match '[\*\?]') { $p } else { "*$p*" })
    if ($rel -like $g) { return $true }
  }
  return $false
}

# --- Enumerate (dynamic, recursive, run_*.ps1 only) ------------------------
$allRunners = Get-ChildItem -LiteralPath $testsRoot -Recurse -Filter 'run_*.ps1' -File |
              Sort-Object FullName
$totalFound = $allRunners.Count

$Include = SplitPatterns $Include
$Exclude = SplitPatterns $Exclude

$excludePats = @($DefaultExclusions.Keys) + $Exclude
$excluded    = @($allRunners | Where-Object { MatchesAny (RelPath $_.FullName) $excludePats })
$kept        = @($allRunners | Where-Object { -not (MatchesAny (RelPath $_.FullName) $excludePats) })
if ($Include.Count -gt 0) {
  $kept = @($kept | Where-Object { MatchesAny (RelPath $_.FullName) $Include })
}

# --- WHICH TREE is this? (register K41) ------------------------------------
# The denominator below is a property of THIS tree. Print the tree beside it so a
# report cannot quote one without the other, and count the enumerated runners
# that are UNTRACKED -- those are exactly the files that make this tree's number
# differ from a clean checkout's.
$gitHead = ''; $gitDirty = ''; $untrackedRunners = @()
try {
  Push-Location $repoRoot
  $gitHead = (git rev-parse --short HEAD 2>$null | Out-String).Trim()
  $porcelain = @(git status --porcelain 2>$null)
  $gitDirty = if ($porcelain.Count -gt 0) { "DIRTY ($($porcelain.Count) entr(ies))" } else { 'clean' }
  $trackedSet = @{}
  foreach ($t in @(git ls-files -- 'tests' 2>$null)) { $trackedSet[$t.ToLowerInvariant()] = $true }
  if ($trackedSet.Count -gt 0) {
    $untrackedRunners = @($allRunners | Where-Object { -not $trackedSet.ContainsKey((RelPath $_.FullName).ToLowerInvariant()) })
  }
} catch { } finally { Pop-Location }

# --- Print the denominator BEFORE running anything -------------------------
Write-Host ''
Write-Host '=== drag-lint battery ===' -ForegroundColor Cyan
Write-Host ("  tree                                             : {0}" -f $repoRoot) -ForegroundColor Cyan
Write-Host ("  commit / worktree state                          : {0} / {1}" -f `
            $(if ($gitHead) { $gitHead } else { '(git unavailable)' }), `
            $(if ($gitDirty) { $gitDirty } else { 'unknown' })) -ForegroundColor Cyan
Write-Host ("  runners found under tests\ (run_*.ps1, recursive) : {0}" -f $totalFound)
Write-Host ("  ... of which UNTRACKED in this tree              : {0}" -f $untrackedRunners.Count) `
           -ForegroundColor $(if ($untrackedRunners.Count -gt 0) { 'Yellow' } else { 'Gray' })
foreach ($u in $untrackedRunners) {
  Write-Host ("      {0}  -- exists only in THIS tree; a clean checkout does not enumerate it" -f (RelPath $u.FullName)) -ForegroundColor Yellow
}
# LEGACY .bat TESTS -- HOW MANY ARE REACHED, AND HOW MANY ARE STILL DARK.
#
# This battery discovers by FILENAME PATTERN, which silently defines "coverage"
# as "files matching run_*.ps1". 68 .bat integration tests lived under tests\ --
# schema, MCP, LSP, hover, rename, refactor, lint rules, workspace config -- and
# none were skipped or reported; they were simply never seen.
#
# What that cost: `resolve-uses` shipped a user-visible multi-DB defect while
# carrying a fixture here that PASSES, because it puts both units in ONE
# database -- the configuration in which the bug cannot appear. And every
# fixture hard-coded the RETIRED Win32 third_party\dll\drag-lint.exe, which
# still exists and still reports the same version string as the current Win64
# build, so a run against the dead binary was indistinguishable from a real one.
# Run as they stood, 15 of 27 sections FAILED; repointed, all 27 PASS.
#
# Now: tests\run_doctests_v021.ps1 (a real runner, enumerated above) drives
# run_v021_doctests.bat and its 21 .bat fixtures. The v016-v020 drivers were
# strict subsets and are deleted. The REMAINDER is what this line is for -- it
# is not "some old files", it is the part of the suite still nobody can see.
#
# The unreached ones are NOT run here on purpose: their pass/fail status is
# unknown, and running them inside the gate everything else depends on would
# convert that unknown into unattributed red. Triage is its own job -- see
# docs\INBOX-68-bat-tests-are-invisible-to-the-battery.md.
# Counted from the two runners' own contents, so the number cannot drift from
# what is actually driven: whichever fixtures they name are covered, and the
# remainder is what nobody runs.
$legacyBat  = @(Get-ChildItem -Path (Join-Path $repoRoot 'tests') -Filter '*.bat' -Recurse -File -ErrorAction SilentlyContinue)
$covered    = New-Object System.Collections.Generic.HashSet[string]
$v021Driver = Join-Path $repoRoot 'tests\run_v021_doctests.bat'
if (Test-Path $v021Driver) {
  [void]$covered.Add('run_v021_doctests')
  foreach ($m in [regex]::Matches((Get-Content $v021Driver -Raw), 'fixtures\\([A-Za-z0-9_]+)\.bat')) {
    [void]$covered.Add($m.Groups[1].Value)
  }
}
$legacyRunner = Join-Path $repoRoot 'tests\run_legacy_cli_fixtures.ps1'
if (Test-Path $legacyRunner) {
  # Both lists it drives: the T* fixtures under tests\fixtures\ and the
  # root-level drivers (run_phase1_e2e). Matching only 'T...' would leave the
  # latter counted as dark forever -- a banner that under-reports its own
  # coverage trains readers to ignore it.
  foreach ($m in [regex]::Matches((Get-Content $legacyRunner -Raw), "'((?:T|run_)[A-Za-z0-9_]+)'")) {
    [void]$covered.Add($m.Groups[1].Value)
  }
}
$darkNames = @($legacyBat | Where-Object { -not $covered.Contains([IO.Path]::GetFileNameWithoutExtension($_.Name)) })
Write-Host ("  legacy .bat tests                                : {0} ({1} now driven by run_*.ps1)" -f `
            $legacyBat.Count, ($legacyBat.Count - $darkNames.Count))
Write-Host ("  ... still reached by NOTHING (status unknown)    : {0}" -f $darkNames.Count) `
           -ForegroundColor $(if ($darkNames.Count -gt 0) { 'Yellow' } else { 'Gray' })
if ($darkNames.Count -gt 0) {
  Write-Host '      see docs\INBOX-68-bat-tests-are-invisible-to-the-battery.md' -ForegroundColor DarkGray
}
Write-Host ("  excluded by policy                               : {0}" -f $excluded.Count)
foreach ($k in $DefaultExclusions.Keys) {
  Write-Host ("      {0}  -- {1}" -f $k, $DefaultExclusions[$k]) -ForegroundColor DarkGray
}
foreach ($k in $Exclude) {
  Write-Host ("      {0}  -- (caller-supplied -Exclude)" -f $k) -ForegroundColor Yellow
}
# BOTH narrowing switches raise the SAME banner. -Exclude is the more dangerous
# of the two -- it drops a handful from an otherwise-full run and leaves a count
# that still looks right, which is the silent-coverage-loss shape this whole
# script exists to kill -- so it must never be the quieter of the two.
if ($Exclude.Count -gt 0) {
  Write-Host ("  -Exclude filter                                  : {0}" -f ($Exclude -join ', ')) -ForegroundColor Yellow
  Write-Host ('  EXCLUSIONS APPLIED -- this is NOT the full battery.') -ForegroundColor Yellow
  Write-Host ('  Every -Exclude entry needs a stated reason in the report that quotes this run.') -ForegroundColor Yellow
}
if ($Include.Count -gt 0) {
  Write-Host ("  -Include filter                                  : {0}" -f ($Include -join ', ')) -ForegroundColor Yellow
  Write-Host ('  SUBSET RUN -- this is NOT the full battery.') -ForegroundColor Yellow
}
Write-Host ("  runners to execute                               : {0}" -f $kept.Count) -ForegroundColor Cyan
Write-Host ("  per-runner timeout                               : {0}s" -f $TimeoutSec)

# An empty selection is ALWAYS an error, never a pass. A battery that runs
# nothing and exits 0 reports green while testing nothing -- the exact failure
# this script exists to prevent, so it must not be reachable from this script.
# (It WAS reachable: a mistyped or unparsed -Include silently selected zero.)
if ($kept.Count -eq 0) {
  Write-Host ''
  Write-Host '  ERROR: the filters selected ZERO runners. Refusing to report a green empty battery.' -ForegroundColor Red
  if ($Include.Count -gt 0) { Write-Host ("         -Include: {0}" -f ($Include -join ' | ')) -ForegroundColor Red }
  if ($Exclude.Count -gt 0) { Write-Host ("         -Exclude: {0}" -f ($Exclude -join ' | ')) -ForegroundColor Red }
  Write-Host ('         Patterns match the repo-relative path, e.g. tests/autodoc/run_doc_cap.ps1') -ForegroundColor Red
  Write-Host ''
  exit 2
}

# Per-suite breakdown, so a suite vanishing is visible. v(ADP3 T3d2): a
# runner placed DIRECTLY under tests\ has only 2 path segments
# ('tests/run_x.ps1'), so Split('/')[1] would return the FILENAME itself and
# report it as its own one-off "suite" -- exactly the kind of shape-change
# this breakdown exists to make visible, so it must degrade to a clearly
# labelled bucket instead of masquerading as a normal suite name.
$bySuite = $kept | Group-Object {
  $parts = (RelPath $_.FullName).Split('/')
  if ($parts.Count -gt 2) { $parts[1] } else { '(tests root)' }
} | Sort-Object Name
Write-Host '  by suite:'
foreach ($g in $bySuite) { Write-Host ("      {0,-16} {1}" -f $g.Name, $g.Count) }
Write-Host ''

# --- PRECONDITION: the rule catalogue beside the exe (register K41) ---------
# Several autofix/autotest runners invoke the exe with no --rules-dir, so it
# resolves <exe-dir>\rules. That directory is GITIGNORED and nothing stages it,
# so a fresh checkout has none and those runners fail without ever saying why --
# the same trap that made T4d fix round 1's first blast-radius measurement fake.
# Say it here, once, loudly, naming the tracked source and the fix.
$rulesSrc = Join-Path $repoRoot 'rules'
# third_party\dll-win32\rules is in this list for a reason that is NOT
# about the test suite: no runner uses the Win32 exe. The IDE design-time BPL
# lives in that directory, and DragLint.Plugin.ExeResolver falls back to the
# engine beside the BPL whenever the Win64 one is absent -- which it is, for a
# few seconds, every time build_draglint_win64.bat stages over a locked exe.
# With no rules\ there, that fallback loads 0 external rules and reports
# "0 finding(s)" for every file; the live-diagnostics runner publishes the
# emptiness into the diagnostic cache, and the editor gutter draws nothing.
# Found 2026-08-25 by reading the plugin telemetry log, not by a test.
$rulesDsts = @('src\cli\Win64\Debug\rules', 'third_party\dll-win64\rules', 'third_party\dll-win32\rules')
$missingRules = @($rulesDsts | Where-Object {
  $p = Join-Path $repoRoot $_
  (-not (Test-Path -LiteralPath $p)) -or
  (@(Get-ChildItem -LiteralPath $p -File -Filter '*.scm' -ErrorAction SilentlyContinue).Count -eq 0)
})
# CONTENT, not just presence (register K41, extended 2026-08-16). The check
# below asks "is there a corpus beside the exe?"; a directory holding 113 STALE
# .scm files answers yes and prints "present". That happened during the
# bare-except anchor fix: rules\bare-except.scm was edited, the battery reported
# the catalogue present, and every suite silently measured the OLD rule. Nothing
# stages these directories (they are gitignored build outputs that no build
# produces), so drift is the normal state, not the exception.
$staleRules = @()
if ($missingRules.Count -eq 0) {
  foreach ($d in $rulesDsts) {
    $dst = Join-Path $repoRoot $d
    foreach ($srcFile in (Get-ChildItem -LiteralPath $rulesSrc -File -Include '*.scm','*.json' -Recurse -ErrorAction SilentlyContinue)) {
      $dstFile = Join-Path $dst $srcFile.Name
      if (-not (Test-Path -LiteralPath $dstFile)) { $staleRules += ("{0}: MISSING {1}" -f $d, $srcFile.Name); continue }
      if ((Get-FileHash -LiteralPath $srcFile.FullName).Hash -ne (Get-FileHash -LiteralPath $dstFile).Hash) {
        $staleRules += ("{0}: DIFFERS {1}" -f $d, $srcFile.Name)
      }
    }
  }
}
if ($staleRules.Count -gt 0) {
  Write-Host '  *** RULE CATALOGUE BESIDE THE EXE IS STALE ***' -ForegroundColor Red
  foreach ($s in $staleRules | Select-Object -First 12) { Write-Host ("      {0}" -f $s) -ForegroundColor Red }
  if ($staleRules.Count -gt 12) { Write-Host ("      ... and {0} more" -f ($staleRules.Count - 12)) -ForegroundColor Red }
  Write-Host  '      The suites below will measure the OLD rules, and will PASS while doing it.' -ForegroundColor Red
  Write-Host  '      Fix:' -ForegroundColor Red
  foreach ($m in $rulesDsts) {
    Write-Host ("        Copy-Item ""{0}\*.scm"",""{0}\*.json"" ""{1}\{2}\"" -Force" -f $rulesSrc, $repoRoot, $m) -ForegroundColor Red
  }
  Write-Host  '      Continuing anyway -- same reasoning as the presence check below.' -ForegroundColor Red
  Write-Host ''
} elseif ($missingRules.Count -eq 0) {
  Write-Host '  rule catalogue matches rules\ by content     : yes' -ForegroundColor Gray
}

if ($missingRules.Count -gt 0) {
  Write-Host '  *** PRECONDITION MISSING: no rule catalogue beside the exe ***' -ForegroundColor Red
  foreach ($m in $missingRules) { Write-Host ("      absent or empty: {0}" -f $m) -ForegroundColor Red }
  Write-Host  '      Runners that invoke the exe without --rules-dir resolve <exe-dir>\rules and' -ForegroundColor Red
  Write-Host  '      will fail WITHOUT naming this as the cause. The tracked source is rules\ at' -ForegroundColor Red
  Write-Host  '      the repo root; the copies beside the exe are gitignored and nothing stages' -ForegroundColor Red
  Write-Host  '      them, so a fresh clone never has them. Fix:' -ForegroundColor Red
  foreach ($m in $missingRules) {
    Write-Host ("        Copy-Item ""{0}\*.scm"",""{0}\*.json"" ""{1}\{2}\"" -Force" -f $rulesSrc, $repoRoot, $m) -ForegroundColor Red
  }
  Write-Host  '      Continuing anyway -- a battery that refuses to start hides more than it saves.' -ForegroundColor Red
  Write-Host ''
} else {
  Write-Host ("  rule catalogue beside the exe                     : present ({0})" -f ($rulesDsts -join ', ')) -ForegroundColor Gray
  Write-Host ''
}

if ($List) {
  foreach ($r in $kept) { Write-Host (RelPath $r.FullName) }
  exit 0
}

if ($LogDir -eq '') {
  $LogDir = Join-Path $env:TEMP ('draglint_battery_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Write-Host ("  logs: {0}" -f $LogDir)
Write-Host ''

# --- Run ------------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]
$i = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($r in $kept) {
  $i++
  $rel = RelPath $r.FullName
  $logFile = Join-Path $LogDir (($rel -replace '[\\/]', '__') + '.log')
  Write-Host ("[{0,3}/{1}] {2} ... " -f $i, $kept.Count, $rel) -NoNewline

  $rsw = [System.Diagnostics.Stopwatch]::StartNew()
  # Each runner gets its own pwsh process so a crash/exit cannot take the
  # battery with it.
  #
  # CWD = the repo root, and that is the DELIBERATE WORST CASE, not just the
  # prior sweep's convention. From inside C:\Projects the engine's config walk-up
  # finds C:\Projects\.drag-lint.json and emits a '(loaded defaults from ...)'
  # line on stderr -- which is precisely what made run_manifest flake (~4 runs in
  # 40) until its captures were separated. Running from a neutral CWD would hide
  # that entire class of defect from the battery while leaving it live for every
  # developer and every IDE-side invocation, which run from inside the tree.
  #
  # This does NOT contradict tests\README.md's advice to Push-Location C:\TEMP
  # inside a runner: a runner pushes to a neutral CWD so that ITS OWN fixture
  # work is not perturbed by a stray drag-lint-lint.json, and it does so from a
  # known-hostile starting point. The driver supplies the hostility on purpose.
  # DO NOT "fix" this to C:\TEMP -- that would make the flake class invisible.
  $proc = Start-Process -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $r.FullName) `
            -WorkingDirectory $repoRoot -PassThru `
            -RedirectStandardOutput $logFile -RedirectStandardError ($logFile + '.err') `
            -WindowStyle Hidden

  $state = ''
  if ($proc.WaitForExit($TimeoutSec * 1000)) {
    $code  = $proc.ExitCode
    $state = $(if ($code -eq 0) { 'PASS' } else { 'FAIL' })
  } else {
    $state = 'TIMEOUT'
    $code  = $null
    # Kill the whole tree -- runners spawn drag-lint.exe children, and an
    # orphaned one holds a .sqlite lock that fails the NEXT runner too.
    try { $proc.Kill($true) } catch { }
  }
  $rsw.Stop()

  $colour = @{ PASS = 'Green'; FAIL = 'Red'; TIMEOUT = 'Magenta' }[$state]
  Write-Host ("{0} ({1:N1}s)" -f $state, $rsw.Elapsed.TotalSeconds) -ForegroundColor $colour

  $results.Add([pscustomobject]@{
    Runner = $rel; State = $state; ExitCode = $code
    Seconds = [math]::Round($rsw.Elapsed.TotalSeconds, 1); Log = $logFile
  })
}
$sw.Stop()

# --- Report ---------------------------------------------------------------
$pass    = @($results | Where-Object State -eq 'PASS').Count
$fail    = @($results | Where-Object State -eq 'FAIL')
$timeout = @($results | Where-Object State -eq 'TIMEOUT')

Write-Host ''
Write-Host '=== battery summary ===' -ForegroundColor Cyan
Write-Host ("  {0} pass / {1} fail / {2} timeout out of {3} executed  (of {4} found)" -f `
            $pass, $fail.Count, $timeout.Count, $results.Count, $totalFound)
# K41: the denominator above is a property of THIS tree. Repeated here because a
# report quotes the tail, not the header -- the same reason the narrowing banner
# is repeated below.
Write-Host ("  counted in: {0}  @ {1} ({2}){3}" -f `
            $repoRoot, $(if ($gitHead) { $gitHead } else { '(git unavailable)' }), $gitDirty, `
            $(if ($untrackedRunners.Count -gt 0) { "  -- INCLUDING $($untrackedRunners.Count) UNTRACKED runner(s)" } else { '' })) `
           -ForegroundColor $(if ($untrackedRunners.Count -gt 0) { 'Yellow' } else { 'Cyan' })
Write-Host ("  wall clock: {0:N1} min" -f $sw.Elapsed.TotalMinutes)
# Repeat the narrowing banner in the SUMMARY. A report usually quotes the tail,
# not the header, so a banner that only appears at the top is a banner a narrowed
# run can be reported without.
if ($Exclude.Count -gt 0 -or $Include.Count -gt 0) {
  Write-Host ''
  Write-Host '  *** NARROWED RUN -- this is NOT the full battery. Do not report it as one. ***' -ForegroundColor Yellow
  if ($Exclude.Count -gt 0) { Write-Host ("      -Exclude: {0}" -f ($Exclude -join ', ')) -ForegroundColor Yellow }
  if ($Include.Count -gt 0) { Write-Host ("      -Include: {0}" -f ($Include -join ', ')) -ForegroundColor Yellow }
}

if ($fail.Count -gt 0) {
  Write-Host ''
  Write-Host '  FAIL:' -ForegroundColor Red
  foreach ($f in $fail) { Write-Host ("    {0}  (exit {1})" -f $f.Runner, $f.ExitCode) -ForegroundColor Red }
}
if ($timeout.Count -gt 0) {
  Write-Host ''
  Write-Host ("  TIMEOUT (> {0}s):" -f $TimeoutSec) -ForegroundColor Magenta
  foreach ($t in $timeout) { Write-Host ("    {0}" -f $t.Runner) -ForegroundColor Magenta }
}

$csv = Join-Path $LogDir 'results.csv'
$results | Export-Csv -NoTypeInformation -Encoding utf8 -Path $csv
Write-Host ''
Write-Host ("  results: {0}" -f $csv)
Write-Host ''

exit $(if ($fail.Count -eq 0 -and $timeout.Count -eq 0) { 0 } else { 1 })
