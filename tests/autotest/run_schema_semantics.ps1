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

  GAP, stated rather than left implicit: these assertions pin the curated list
  against careless edits, but they cannot yet prove it still matches the DATA.
  Once `drag-lint sql` ships, this guard should cross-check each vocabulary with
  SELECT DISTINCT against a real index -- that is the version that would catch
  the extractor emitting a NEW refs.kind nobody added here.
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

Write-Host ''
if ($script:Failed) { Write-Host 'SCHEMA SEMANTICS GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'SCHEMA SEMANTICS GUARD: PASS' -ForegroundColor Green
exit 0
