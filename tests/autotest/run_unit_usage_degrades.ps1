<#
  run_unit_usage_degrades.ps1 -- `query unit-usage --unit U` (no `--in`) must
  answer with the importer list when U's EXPORTS are not in the open index,
  instead of exiting 2 with nothing.

  THE DEFECT THIS PINS:
    DoQueryUnitUsageProjectWide exited 2 the moment ResolveUnitExportSurface came
    back empty. For an RTL/VCL/third-party unit that is the NORMAL case with only
    a project DB open -- those units live in the platform library index by
    design. The importer list was sitting in `unit_uses` the whole time
    (measured: 4 DataCopy files importing ExceptionLog7, 0 ms) and the caller was
    told "may not be indexed" and sent to grep.

  WHAT THE DEGRADED ANSWER MUST NOT DO:
    With no export surface every reference count is structurally zero, so
    rendering the normal shape would print `DEAD IMPORT` next to four live
    imports -- the most confidently wrong thing this verb could say. The text
    output says reference counts were not computed; the JSON omits the count
    fields entirely and sets exports_known=false, so a consumer cannot read a
    zero that was never measured.

  THE CONTROLS:
    * a unit whose exports ARE indexed still gets the full breakdown with real
      counts -- the fix did not flatten every answer into the degraded shape;
    * a unit nobody imports and nothing declares STILL exits 2 -- "answer
      something" must not become "never fail";
    * the degraded text never contains DEAD IMPORT;
    * the degraded JSON carries no ref_count key at all.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-unitusage-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== query unit-usage: degrade, do not exit 2 ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$srcDir = (Resolve-Path "$PSScriptRoot\fixtures\unitusage").Path

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$fixDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force -Path $fixDir | Out-Null
Copy-Item (Join-Path $srcDir '*.pas') $fixDir
$db      = Join-Path $WorkDir 'unitusage.sqlite'
$errFile = Join-Path $WorkDir 'stderr.txt'

& $Exe index $fixDir --db $db 2>$errFile | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "FATAL: indexing the fixture failed ($LASTEXITCODE)" -ForegroundColor Red
  Write-Host (Get-Content -LiteralPath $errFile -Raw)
  exit 1
}

function Ask([string[]]$A) {
  $out = & $Exe @A 2>$errFile
  [pscustomobject]@{ Out = (($out | Out-String) -replace "`r`n", "`n"); Code = $LASTEXITCODE }
}

# The fixture is only meaningful if the absent unit really is absent from the
# index while its uses row is present. Prove both before asserting anything.
Write-Host ''
Write-Host '-- fixture sanity (the assertions below are vacuous without this)' -ForegroundColor Cyan
$rows = Ask @('sql', '--db', $db, '--query', "select count(*) as n from unit_uses where unit_name_norm='zzabsentlibunit'")
Check 'the absent unit HAS a uses row' ($rows.Out -match '\b1\b') (($rows.Out -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 3) -join ' / ')
$syms = Ask @('query', '--name', 'ZzAbsentLibUnit', '--db', $db, '--exact')
Check 'and NO symbol of its own in this index' ($syms.Out -match '0 match') (($syms.Out -split "`n" | Where-Object { $_ -match 'match' } | Select-Object -First 1))

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- the defect: exports elsewhere' -ForegroundColor Cyan
$deg = Ask @('query', 'unit-usage', '--unit', 'ZzAbsentLibUnit', '--db', $db)
Write-Host ("  output: " + (($deg.Out -split "`n" | Where-Object { $_ -match '\S' }) -join ' | ')) -ForegroundColor DarkGray
Check 'it exits 0 instead of 2' ($deg.Code -eq 0) "exit=$($deg.Code)"
Check 'and names the importing file' ($deg.Out -match 'uUuConsumer\.pas') ''
Check 'with the uses line number' ($deg.Out -match 'line \d+') ''
Check 'and says the exports are not in this DB' ($deg.Out -match 'exports not in this DB') ''
Check 'and says reference counts were NOT computed' ($deg.Out -match 'NOT computed') ''
Check 'CONTROL: it never says DEAD IMPORT (that would be an artefact, not a fact)' `
  ($deg.Out -notmatch 'DEAD IMPORT') ''

$degJson = Ask @('query', 'unit-usage', '--unit', 'ZzAbsentLibUnit', '--db', $db, '--json')
$parsed = $null
try { $parsed = $degJson.Out | ConvertFrom-Json } catch { }
Check 'the JSON form parses' ($null -ne $parsed) $degJson.Out
if ($null -ne $parsed) {
  $rowsJ = @($parsed)
  Check 'JSON: exports_known is false' `
    ($rowsJ.Count -ge 1 -and $rowsJ[0].exports_known -eq $false) "exports_known=$($rowsJ[0].exports_known)"
  Check 'CONTROL: JSON carries NO ref_count key -- an unmeasured 0 must not be readable as measured' `
    (-not ($rowsJ[0].PSObject.Properties.Name -contains 'ref_count')) `
    ("keys=[" + (($rowsJ[0].PSObject.Properties.Name) -join ',') + "]")
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- CONTROL: a unit whose exports ARE indexed is unaffected' -ForegroundColor Cyan
$full = Ask @('query', 'unit-usage', '--unit', 'uUuLib', '--db', $db)
Write-Host ("  output: " + (($full.Out -split "`n" | Where-Object { $_ -match '\S' }) -join ' | ')) -ForegroundColor DarkGray
Check 'exits 0' ($full.Code -eq 0) "exit=$($full.Code)"
Check 'reports the export count (the normal shape)' ($full.Out -match 'export\(s\)\)') ''
Check 'and REAL reference counts, not the degraded note' `
  ($full.Out -match 'ref\(s\) to \d+ export\(s\)' -and $full.Out -notmatch 'NOT computed') ''

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- CONTROL: a genuinely unknown unit still fails' -ForegroundColor Cyan
$none = Ask @('query', 'unit-usage', '--unit', 'ZzNobodyImportsThis', '--db', $db)
Write-Host ("  output: " + (($none.Out -split "`n" | Where-Object { $_ -match '\S' }) -join ' | ')) -ForegroundColor DarkGray
Check 'still exits 2 -- "degrade" must not become "never fail"' ($none.Code -eq 2) "exit=$($none.Code)"
Check 'and still says so' ($none.Out -match 'no interface-section symbols found') ''

# ---------------------------------------------------------------------------
# DOCS-IN-SYNC: --help used to state the old behaviour flatly.
Write-Host ''
Write-Host '-- DOCS-IN-SYNC: the banner no longer claims a flat exit 2' -ForegroundColor Cyan
$help = (& $Exe --help 2>$null | Out-String)
Check 'the banner mentions unit-usage at all (scan is not vacuous)' ($help -match 'unit-usage') ''
Check 'it does not still say the project DB alone exits 2' `
  ($help -notmatch 'with the project DB alone it exits 2') `
  (($help -split "`r?`n" | Where-Object { $_ -match 'exits 2' } | ForEach-Object { $_.Trim() }) -join ' | ')
Check 'and it says which form DOES exit 2' ($help -match 'only the --in form exits 2') ''

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
