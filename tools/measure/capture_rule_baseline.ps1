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
  [Parameter(Mandatory)][ValidateSet('before','after')][string]$Tag,
  [string]$Exe = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe',
  [string]$OutDir = 'C:\TEMP\claude\c--Projects-Delphi-RAG-lint\f4374ad8-1700-45f4-9237-81dac7d7805d\scratchpad\baseline'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null

$corpora = @(
  @{ key='cli';    db='C:\Projects\Delphi-RAG-lint\src\cli\_D-RAG\drag-lint.sqlite' },
  @{ key='client'; db='C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite' },
  @{ key='server'; db='C:\Projects\DB\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite' }
)

# The engine's own rule catalogue, so a rule ADDED or RENAMED between the two
# runs is visible rather than silently read as a count change.
& $Exe rules --json 2>$null | Set-Content (Join-Path $OutDir "rules_$Tag.json") -Encoding ascii

$summary = @()
foreach ($c in $corpora) {
  if (-not (Test-Path $c.db)) { Write-Host "SKIP $($c.key): no db at $($c.db)" -ForegroundColor Yellow; continue }

  # The indexer fingerprint is recorded WITH the counts. Without it a later
  # reader cannot tell which side of the reindex a number came from -- and that
  # is the whole question this file answers.
  $fp = (& $Exe sql --query "SELECT value FROM schema_meta WHERE key='indexer_fingerprint'" --db $c.db 2>$null | Out-String).Trim()

  $raw = Join-Path $OutDir "lintall_$($c.key)_$Tag.json"
  Write-Host "lint-all $($c.key) ($Tag) ..." -ForegroundColor Cyan
  & $Exe lint-all --db $c.db --json --quiet 2>&1 | Set-Content $raw -Encoding ascii

  # COUNT FROM THE JSON `rule` FIELD, never from the text renderer. An earlier
  # draft regex-matched kebab-case tokens per line, which also matches ordinary
  # words in a finding's MESSAGE ("read-only", "name resolution") -- that would
  # have made the one artifact this whole comparison rests on into noise.
  #
  # The engine prints a banner before the array (an FTS5 probe line, a scanning
  # line), so skip to the first '['.
  $txt = Get-Content $raw -Raw
  $i   = $txt.IndexOf('[')
  if ($i -lt 0) { Write-Host "  $($c.key): NO JSON ARRAY -- lint-all failed?" -ForegroundColor Red; continue }
  $findings = $txt.Substring($i) | ConvertFrom-Json

  $counts = @{}
  foreach ($f in $findings) {
    if (-not $f.rule) { continue }
    if ($counts.ContainsKey($f.rule)) { $counts[$f.rule]++ } else { $counts[$f.rule] = 1 }
  }
  foreach ($k in ($counts.Keys | Sort-Object)) {
    $summary += [pscustomobject]@{ corpus=$c.key; rule=$k; count=$counts[$k]; fingerprint=$fp }
  }
  # Total is recorded too: a rule that vanishes entirely has NO row above, and a
  # missing row reads as "unchanged" unless the totals disagree.
  $summary += [pscustomobject]@{ corpus=$c.key; rule='__TOTAL__'; count=$findings.Count; fingerprint=$fp }
  Write-Host ("  $($c.key): $($counts.Count) distinct rule id(s), fingerprint $fp")
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
