<#
  run_schema_semantics.ps1 -- `schema --format json` must carry what a column
  MEANS and what it may contain, not just its name and SQL type.

  Why this exists
  ---------------
  This is the prerequisite half of `drag-lint sql`. Agents rarely invent TABLE
  names -- those are discoverable from the schema. They invent SEMANTICS: that
  refs.kind might be 'reference', that symbols.section is always one of two
  things, that a parent_id of 0 means "no parent". A schema that lists
  `kind TEXT` and stops invites exactly that.

  Every vocabulary asserted here was verified against a live index with
  SELECT DISTINCT on 2026-08-26.

  The empty-string case is called out on purpose
  ----------------------------------------------
  symbols.section has THREE values and one of them is ''. It is what the unit
  symbol itself carries, so a filter of section='interface' silently drops it.
  That value looks like a mistake and invites "tidying" out of the list, which
  is why it has its own assertion.

  THE GAP THIS USED TO DECLARE IS NOW CLOSED
  ------------------------------------------
  Until `drag-lint sql` shipped, the assertions below could only pin the curated
  list against careless EDITS -- they could not prove it still matched the DATA.
  An extractor emitting a brand-new refs.kind would have sailed past every one
  of them, and the vocabulary would have quietly become a lie.

  Check 2 closes that: it walks EVERY column the schema says has a closed
  vocabulary, runs SELECT DISTINCT against a live index, and fails when the data
  holds a value nobody curated.

  The comparison is deliberately ASYMMETRIC. A value in the data that is not in
  the list is a DEFECT -- the document is wrong about the world. A curated value
  that this particular index happens not to contain is NOT: a small or
  single-project index legitimately lacks kinds a big one has, and failing on
  that would make the guard depend on which database it was pointed at. That
  direction is reported as a NOTE, never as a failure.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$DbFile  = "$PSScriptRoot\..\..\src\cli\_D-RAG\drag-lint.sqlite"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

Write-Host '== schema carries column semantics ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
if (-not (Test-Path $DbFile)) { Write-Host "SKIP: no self-index at $DbFile" -ForegroundColor Yellow; exit 0 }
$DbFile = (Resolve-Path $DbFile).Path

$raw = (& $Exe schema --db $DbFile --format json 2>$null) -join "`n"
$i   = $raw.IndexOf('{')
$obj = $null
if ($i -ge 0) { try { $obj = ($raw.Substring($i) | ConvertFrom-Json) } catch { } }
Check 'schema --format json is ONE valid object' ($null -ne $obj) ''
if ($null -eq $obj) { Write-Host 'FATAL: no JSON'; exit 1 }

function Col($table, $column) {
  $t = $obj.tables | Where-Object { $_.name -eq $table }
  if (-not $t) { return $null }
  return $t.columns | Where-Object { $_.name -eq $column }
}

Write-Host ''
Write-Host '-- check 1: the document carries the curated semantics' -ForegroundColor Cyan

$refKind = Col 'refs' 'kind'
Check 'refs.kind enumerates its vocabulary' `
  (($null -ne $refKind) -and ($null -ne $refKind.values)) ''
if ($refKind.values) {
  $expected = @('call','member-access','read','type_use','write')
  $got = @($refKind.values | Sort-Object)
  Check 'refs.kind is exactly the five verified values' `
    ((@(Compare-Object $expected $got -SyncWindow 0)).Count -eq 0) "got: $($got -join ',')"
}

$sec = Col 'symbols' 'section'
Check 'symbols.section enumerates its vocabulary' (($null -ne $sec) -and ($null -ne $sec.values)) ''
Check 'symbols.section keeps the EMPTY value (it is real, not a mistake)' `
  (($null -ne $sec.values) -and ($sec.values -contains '')) "got: $($sec.values -join '|')"

$par = Col 'symbols' 'parent_id'
Check 'symbols.parent_id says it is never NULL' `
  (($null -ne $par) -and ($par.description -match 'NEVER NULL')) "$($par.description)"

$conf = Col 'call_edges' 'confidence'
Check 'call_edges.confidence enumerates ambiguous/certain' `
  (($null -ne $conf) -and ($conf.values -contains 'ambiguous') -and ($conf.values -contains 'certain')) ''

# NEGATIVE CONTROL: the emitter must not blanket-attach prose to every column,
# or "has a description" stops meaning anything.
$plain = Col 'call_edges' 'ref_id'
Check 'negative control: an undocumented column carries NO description' `
  (($null -ne $plain) -and ($null -eq $plain.description) -and ($null -eq $plain.values)) `
  'semantics must be curated, not blanket-applied'

# ---------------------------------------------------------------------------
# CHECK 2 -- the curated vocabularies vs the DATA
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 2: every closed vocabulary vs SELECT DISTINCT' -ForegroundColor Cyan

# Discovered from the document rather than hardcoded, so a vocabulary added to
# ColumnSemantics is cross-checked the day it appears instead of the day someone
# remembers to extend this list.
$vocab = @()
foreach ($t in $obj.tables) {
  foreach ($c in $t.columns) {
    if ($null -ne $c.values) { $vocab += [pscustomobject]@{ Table = $t.name; Column = $c.name; Values = @($c.values) } }
  }
}

# POSITIVE CONTROL. A document that stopped emitting `values` entirely would
# make the loop below iterate zero times and report a clean pass.
Check 'the schema document actually declares closed vocabularies' ($vocab.Count -ge 3) "found $($vocab.Count)"

$sqlErrFile = Join-Path ([IO.Path]::GetTempPath()) ("draglint-schemasem-" + [Guid]::NewGuid().ToString('N') + ".txt")
foreach ($v in $vocab) {
  # Identifier-shaped only. These names come from our own document, but they are
  # about to be inlined into SQL, and "it came from a trusted source" is how
  # injection gets in.
  if (($v.Table -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') -or ($v.Column -notmatch '^[A-Za-z_][A-Za-z0-9_]*$')) {
    Check "$($v.Table).$($v.Column): name is identifier-shaped" $false 'refusing to inline it'
    continue
  }
  # BARE identifiers, not quoted ones. PowerShell rewrites a double quote inside
  # a native-command argument as \" , so "SELECT DISTINCT \"kind\" ..." reached
  # SQLite as `unrecognized token: "\"`. The identifier-shape test above is what
  # makes bare names safe here.
  $q   = "SELECT DISTINCT $($v.Column) AS v FROM $($v.Table)"
  $raw = (& $Exe sql --query $q --db $DbFile --json --limit 500 2>$sqlErrFile) -join "`n"
  $rc  = $LASTEXITCODE
  $doc = $null
  if ($rc -eq 0) { try { $doc = $raw | ConvertFrom-Json } catch { } }
  if ($null -eq $doc) {
    $why = if (Test-Path -LiteralPath $sqlErrFile) { (Get-Content -LiteralPath $sqlErrFile -Raw).Trim() } else { '' }
    Check "$($v.Table).$($v.Column): SELECT DISTINCT ran" $false "exit $rc / $why"
    continue
  }
  Check "$($v.Table).$($v.Column): the DISTINCT scan was not truncated" (-not $doc.truncated) `
    'a truncated scan cannot prove the vocabulary is complete'

  # A NULL cell arrives as JSON null; it is not a vocabulary value and the
  # curated lists do not claim to cover nullability.
  $actual = @($doc.rows | ForEach-Object { $_[0] } | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
  $undocumented = @($actual | Where-Object { $v.Values -notcontains $_ })
  Check "$($v.Table).$($v.Column): the data holds NO value the document omits" `
    ($undocumented.Count -eq 0) `
    $(if ($undocumented.Count) { "undocumented: '" + ($undocumented -join "', '") + "'" } else { "$($actual.Count) distinct value(s) verified" })

  $unseen = @($v.Values | Where-Object { $actual -notcontains $_ })
  if ($unseen.Count) {
    # NOT a failure -- see the header. This index simply does not exercise them.
    Write-Host ("  [NOTE] {0}.{1}: curated but absent from THIS index: '{2}'" -f `
      $v.Table, $v.Column, ($unseen -join "', '")) -ForegroundColor DarkGray
  }
}
Remove-Item -LiteralPath $sqlErrFile -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:Failed) { Write-Host 'SCHEMA SEMANTICS GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'SCHEMA SEMANTICS GUARD: PASS' -ForegroundColor Green
exit 0
