<#
  capture_rule_baseline.ps1 -- the BEFORE/AFTER halves of the extractor-batch
  reindex comparison (docs\PLAN-MASTER-2026-08-30-reindex-first.md sec 1).

  WHY THIS EXISTS. The batch ADDS refs, and several already-shipped rules read
  refs, so their counts MOVE when the reindex lands. The master plan predicts a
  DIRECTION for each one:

      global-only-uses-edge                 FEWER   (new refs are new links)
      uses-global-census                    HIGHER  (more referenced globals)
      unused-public-symbol                  FEWER   (a const used only in an
      unused-private-member                 FEWER    array bound looked unused)
      duplicate-global-decl                 unchanged (symbols only, no refs)
      with-hides-outer-symbol               unchanged (AST + surfaces, no refs)

  A rule that moves the OTHER way is an extractor defect, and this diff is the
  cheapest detector available. Without the BEFORE half the after-numbers are
  uninterpretable, and the before half cannot be reconstructed once the indexes
  are rewritten -- which is why this runs BEFORE `index --all`.

  Run it twice: `-Tag before` (live indexes still on extractor 1.8.0-alpha) and
  `-Tag after` (once the reindex completes). Then diff the two summary files.

  Read-only: lint-all only READS an index. Safe to run against the live DBs.
#>
[CmdletBinding()]
param(
  # 'mid' is the OLD engine against the NEW indexes -- the reading that makes
  # before/after interpretable. See post_reindex_sequence.ps1's header.
  [Parameter(Mandatory)][ValidateSet('before','mid','after')][string]$Tag,
  [string]$Exe = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe',
  [string]$OutDir = 'C:\TEMP\draglint-extractor-batch-2026-08-30\baseline',
  # Measure the still-off rules' VOLUME. That is a SEPARATE question from the
  # reindex comparison and a slow one (missing-doc / magic-literal on ORM3), so
  # it is opt-in and deliberately not part of the before/after pair.
  [switch]$MeasureOffRules
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null

$corpora = @(
  @{ key='cli';    db='C:\Projects\Delphi-RAG-lint\src\cli\_D-RAG\drag-lint.sqlite' },
  @{ key='client'; db='C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite' },
  @{ key='server'; db='C:\Projects\DB\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite' }
)

# RULES THAT ARE OFF BY DEFAULT AND MUST STILL BE TRACKED. `lint-all` does not
# run these, so a default-only capture records NOTHING for them -- and a missing
# row reads as "unchanged", which is the silent kind of wrong.
#
# This started as just the master plan's two primary predictions
# (global-only-uses-edge, uses-global-census); omitting them would have gutted
# the comparison while looking complete. Both are now ON by default (owner's
# ruling 2026-08-30), so they arrive through the DEFAULT pass instead, and this
# list is the 18 that remain off.
#
# It doubles as the VOLUME MEASUREMENT behind the standing question "should this
# rule ship on?". The house standard is every rule on unless it would flood, and
# the owner's own rule is that a finding count in the thousands IS the defect --
# so the decision needs numbers per corpus, not an opinion. These rows supply
# them.
$WatchOff = @(
  'exhaustive-enum-case','string-equality-comparison','unsafe-typecast-without-is',
  'commented-out-code','function-result-ignored','missing-doc','default-encoding-io',
  'boolean-flag-parameter','loop-control-flag','magic-literal','middle-man',
  'mutable-global-variable','public-writable-field','repeated-type-switch',
  'separate-query-from-modifier','split-variable','interface-object-mixing',
  'multiple-statements-per-line'
) -join ','

# The engine's own rule catalogue, so a rule ADDED or RENAMED between the two
# runs is visible rather than silently read as a count change.
& $Exe rules --json 2>$null | Set-Content (Join-Path $OutDir "rules_$Tag.json") -Encoding ascii

$summary = @()
foreach ($c in $corpora) {
  if (-not (Test-Path $c.db)) { Write-Host "SKIP $($c.key): no db at $($c.db)" -ForegroundColor Yellow; continue }

  # The indexer fingerprint is recorded WITH the counts. Without it a later
  # reader cannot tell which side of the reindex a number came from -- and that
  # is the whole question this file answers.
  # Pull the fingerprint out by PATTERN, not by trusting the row renderer: `sql`
  # prints a column header and a rule line around the value.
  $fpRaw = (& $Exe sql --query "SELECT value FROM schema_meta WHERE key='indexer_fingerprint'" --db $c.db 2>$null | Out-String)
  $fp = if ($fpRaw -match '(v=[^;\s]+;schema=\d+[^\s]*)') { $Matches[1] } else { 'UNKNOWN' }

 $passes = if ($MeasureOffRules) { @('default','enabled-watch') } else { @('default') }
 foreach ($pass in $passes) {
  $raw = Join-Path $OutDir "lintall_$($c.key)_$($pass)_$Tag.json"
  $rawErr = "$raw.err"
  Write-Host "lint-all $($c.key) ($Tag) ..." -ForegroundColor Cyan
  # STDERR GOES TO ITS OWN FILE. It used to be merged with `2>&1`, and that
  # corrupted the AFTER capture on 2026-08-31: the engine's stderr is unbuffered
  # while its stdout is block-buffered when redirected, so where a diagnostic
  # interleaves depends on when stdout's buffer happens to flush. ORM3 SERVER
  # emits 63 `duplicate-code: skipped a N-window hash bucket` lines; in the
  # BEFORE run 61 landed above the array and 2 below it, and in the AFTER run
  # the SAME two landed INSIDE an object, between "end_col" and "message".
  # ConvertFrom-Json then failed on the hyphen in `duplicate-code` --
  # "Invalid JavaScript property identifier character: -" -- and the sequence
  # stopped at step 3 with no CSV, no prediction diff and no battery.
  #
  # Note what made it expensive: the SAME command had worked hours earlier on
  # the SAME corpus, so it read as something the reindex had changed. It was a
  # race that had always been there. The two other engine calls in this script
  # (`rules --json`, `sql --query`) already discard stderr; only this one merged
  # it. Keeping it in a sibling .err file rather than `2>$null` means a genuine
  # engine failure is still readable afterwards.
  if ($pass -eq 'default') {
    & $Exe lint-all --db $c.db --json --quiet 2> $rawErr | Set-Content $raw -Encoding ascii
  } else {
    & $Exe lint-all --db $c.db --json --quiet --enable $WatchOff 2> $rawErr | Set-Content $raw -Encoding ascii
  }

  # COUNT FROM THE JSON `rule` FIELD, never from the text renderer. An earlier
  # draft regex-matched kebab-case tokens per line, which also matches ordinary
  # words in a finding's MESSAGE ("read-only", "name resolution") -- that would
  # have made the one artifact this whole comparison rests on into noise.
  #
  # The engine prints a banner before the array (an FTS5 probe line, a scanning
  # line), so skip to the first '['.
  # The engine prints a banner BEFORE the array and a summary AFTER it, so take
  # the span from the first '[' to the LAST ']'. Slicing only from the first '['
  # leaves the trailing summary attached and ConvertFrom-Json rejects the whole
  # document ("Additional text encountered after finished reading JSON content").
  $txt = Get-Content $raw -Raw
  $i   = $txt.IndexOf('[')
  $j   = $txt.LastIndexOf(']')
  if ($i -lt 0 -or $j -le $i) {
    Write-Host "  $($c.key): NO JSON ARRAY -- lint-all failed?" -ForegroundColor Red; continue
  }
  $findings = $txt.Substring($i, $j - $i + 1) | ConvertFrom-Json

  $counts = @{}
  foreach ($f in $findings) {
    if (-not $f.rule) { continue }
    if ($counts.ContainsKey($f.rule)) { $counts[$f.rule]++ } else { $counts[$f.rule] = 1 }
  }
  # The enabled-watch pass re-runs EVERY default rule too, so keep only the
  # watch-list rules from it -- otherwise every rule would appear twice and the
  # __TOTAL__ rows would double-count.
  $keep = if ($pass -eq 'default') { $counts.Keys } else { $counts.Keys | Where-Object { $WatchOff.Split(',') -contains $_ } }
  foreach ($k in ($keep | Sort-Object)) {
    $summary += [pscustomobject]@{ corpus=$c.key; pass=$pass; rule=$k; count=$counts[$k]; fingerprint=$fp }
  }
  # Total is recorded too: a rule that vanishes entirely has NO row above, and a
  # missing row reads as "unchanged" unless the totals disagree.
  if ($pass -eq 'default') {
    $summary += [pscustomobject]@{ corpus=$c.key; pass=$pass; rule='__TOTAL__'; count=$findings.Count; fingerprint=$fp }
  }
  Write-Host ("  $($c.key) [$pass]: $($counts.Count) distinct rule id(s), fingerprint $fp")
 }
}

# FAIL LOUDLY ON AN EMPTY RESULT. This file is the BEFORE half of a comparison
# that cannot be reconstructed once the indexes are rewritten, and an empty CSV
# is indistinguishable from "nothing changed" when it is read back weeks later.
# A fail-open write is exactly how a missing artifact stays invisible.
if ($summary.Count -eq 0) {
  Write-Host "FATAL: no findings collected from ANY corpus -- refusing to write an empty baseline." -ForegroundColor Red
  exit 2
}

$csv = Join-Path $OutDir "rule_counts_$Tag.csv"
$summary | Export-Csv -NoTypeInformation -Path $csv -Encoding ascii
Write-Host "wrote $csv ($($summary.Count) row(s))" -ForegroundColor Green
