<#
  run_doc_drift_input_only.ps1 -- doc-drift's "var/out param documented as
  input-only" (ddParamVolatileMode) reads the WHOLE description, not only its
  first word.

  THE DEFECT (INBOX-2026-09-29-converter-to-engine-doc-drift-input-only-fp).
  DescReadsInputOnly returned True whenever the description's FIRST word was
  'input' or 'in'. The converter's TMappingForm documents a two-way var param
  as "IN: the current nodes ... OUT (only when the result is True): ... the
  caller now owns", and it was reported as input-only -- a false positive.
  The predicate now also requires that no later WHOLE word marks an output
  direction (out, output, returns, returned, replaced, replaces, receives,
  updated, owns, filled). Whole words only: 'without' and 'layout' are not
  markers.

  Nothing in tests\ pinned this rule before; this is its first guard, so it
  carries positive controls (the rule must still fire on genuinely input-only
  var AND out params) and a non-vacuity count.

  Fixture: tests\autodoc\fixtures\docinonly\uInOnly.pas, copied to a scratch
  folder and indexed into a scratch DB (the folder-target index is correct
  here: the DB is a throwaway over a throwaway folder, not a project DB).

  Usage: pwsh -File tests\autodoc\run_doc_drift_input_only.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$Fixture = Join-Path $PSScriptRoot 'fixtures\docinonly\uInOnly.pas'
if (-not (Test-Path -LiteralPath $Fixture)) { Write-Host "FATAL: fixture not found: $Fixture" -ForegroundColor Red; exit 2 }

$W = Join-Path $env:TEMP "drag-lint-inonly-$PID"
if (Test-Path $W) { Remove-Item -Recurse -Force -LiteralPath $W }
New-Item -ItemType Directory $W | Out-Null
Copy-Item -LiteralPath $Fixture -Destination (Join-Path $W 'uInOnly.pas')
$Db = Join-Path $W 't.sqlite'

Push-Location $W
try {
  & $Exe index $W --db $Db 2>$null | Out-Null

  # lint-all --json prints progress text around ONE array.
  $raw = (& $Exe lint-all --db $Db --json 2>$null) -join "`n"
  $a = $raw.IndexOf('['); $b = $raw.LastIndexOf(']')
  $f = if ($a -ge 0 -and $b -gt $a) { @(ConvertFrom-Json $raw.Substring($a, $b - $a + 1)) } else { @() }

  $hits = @($f | Where-Object { $_.rule -eq 'doc-drift' -and $_.message -like '*documented as input-only*' })
  $names = @($hits | ForEach-Object {
    if ($_.message -match 'var/out param "([^"]+)" documented as input-only') { $Matches[1] }
  })
  $seen = 'reported=[' + ($names -join ',') + ']'

  Check 'ANodes NOT reported (IN: ... OUT: ... is two-way -- the INBOX case)' ($names -notcontains 'ANodes') $seen
  Check 'ABuf NOT reported (returned is an output marker)' ($names -notcontains 'ABuf') $seen
  Check 'AValue reported (positive control: var + input-only)' ($names -contains 'AValue') $seen
  Check 'ACount reported (out + input-only)' ($names -contains 'ACount') $seen
  Check 'AMode reported (layout/without are not markers -- whole words only)' ($names -contains 'AMode') $seen
  Check 'AText NOT reported (by-value param is never graded)' ($names -notcontains 'AText') $seen
  Check 'AResult NOT reported (leads with Out)' ($names -notcontains 'AResult') $seen
  Check 'non-vacuity: at least 3 input-only findings' ($hits.Count -ge 3) ("count=$($hits.Count); lint-all findings=$($f.Count)")
} finally {
  Pop-Location
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0

} finally {
  if ($W -and (Test-Path -LiteralPath $W)) { Remove-Item -LiteralPath $W -Recurse -Force -ErrorAction SilentlyContinue }
}
