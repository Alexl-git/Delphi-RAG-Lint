<#
  verify.ps1 -- standalone probe for refs.enclosing_symbol_id attribution
  (v0.82 Task 1). Indexes sample.pas into a throwaway DB, runs the
  `dump-refs` diagnostic, and asserts per-routine enclosing attribution:

    * the Helper call inside TThing.Bar   -> resolves to Bar
    * the Helper call inside Outer's body -> resolves to Outer (NOT Bar/Helper)

  Two Helper calls in two non-overlapping routine bodies prove each ref is
  attributed to the routine that actually contains it, chosen correctly among
  several candidate routines. (Nested-proc innermost tie-break is correct in
  ResolveEnclosingSymbolId but unobservable: the parser does not emit nested
  procedures as symbols -- see sample.pas.)

  This dir has NO expected.txt on purpose, so run_store_tests.ps1 skips it;
  this script is the assertion surface. Exit 0 = pass, 1 = mismatch.

  dump-refs line format: name_text|start_line|enclosing_symbol_id|enclosing_symbol_name
#>
[CmdletBinding()]
param(
  [string]$Exe = "third_party\dll-win64\drag-lint.exe"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo

$exePath = (Resolve-Path $Exe).Path
$caseDir = $PSScriptRoot
$sample  = Join-Path $caseDir "sample.pas"

$db = Join-Path $env:TEMP "enclosing_attribution_verify.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }

& $exePath index $caseDir --db $db 2>$null | Out-Null

$raw = & $exePath dump-refs $sample --db $db 2>$null

if (Test-Path $db) { Remove-Item $db -Force }

# Parse "name|line|enclId|enclName" lines into objects.
$refs = @()
foreach ($ln in $raw) {
  $parts = $ln -split '\|'
  if ($parts.Count -lt 4) { continue }
  $refs += [pscustomobject]@{
    name   = $parts[0]
    line   = [int]$parts[1]
    enclId = [int]$parts[2]
    encl   = $parts[3]
  }
}

$problems = @()

# Both Helper call sites (one in Bar, one in Outer's body).
$helperCalls = @($refs | Where-Object { $_.name -eq 'Helper' })
if ($helperCalls.Count -lt 2) {
  $problems += "expected >=2 'Helper' call refs, got $($helperCalls.Count)"
}

# Assertion 1: the Helper call inside Bar resolves to Bar (and to a real id).
$inBar = @($helperCalls | Where-Object { $_.encl -eq 'Bar' -and $_.enclId -gt 0 })
if ($inBar.Count -lt 1) {
  $problems += "no 'Helper' ref attributed to enclosing 'Bar' (expected the call in TThing.Bar's body)"
}

# Assertion 2: the Helper call inside Outer's body resolves to Outer, not Bar/Helper.
$inOuter = @($helperCalls | Where-Object { $_.encl -eq 'Outer' -and $_.enclId -gt 0 })
if ($inOuter.Count -lt 1) {
  $problems += "no 'Helper' ref attributed to enclosing 'Outer' (per-routine containment failed)"
}

# Cross-check: the two Helper calls must land in DIFFERENT routines (not both
# collapsed to one), proving the containing routine is chosen, not guessed.
$distinctEncl = @($helperCalls | ForEach-Object { $_.encl } | Sort-Object -Unique)
if ($helperCalls.Count -ge 2 -and $distinctEncl.Count -lt 2) {
  $problems += "both 'Helper' refs share enclosing '$($distinctEncl -join ',')' -- expected Bar and Outer distinctly"
}

Write-Host "dump-refs output for sample.pas:"
foreach ($ln in $raw) { Write-Host ("    " + $ln) }
Write-Host ""

if ($problems.Count -eq 0) {
  Write-Host "PASS  enclosing-attribution" -ForegroundColor Green
  exit 0
} else {
  Write-Host "FAIL  enclosing-attribution" -ForegroundColor Red
  foreach ($p in $problems) { Write-Host ("        " + $p) -ForegroundColor Red }
  exit 1
}
