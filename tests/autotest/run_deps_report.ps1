<#
  run_deps_report.ps1 -- deps-report headless test (Track 5.2 / Task 3):
  project-vs-external classification, grouping, shortest-path, and the
  text|json|csv output formats.

  FIXTURE (built fresh in a temp workdir, then indexed as a whole tree):
    projmain.pas    -- project unit. Interface `uses ProjHelper, NotIndexedLib,
                        System.SysUtils;`, implementation `uses LibUnit;`
                        (exercises both uses-clause sections).
    projhelper.pas  -- project unit (resolved, NOT a library path) -> the
                        NEGATIVE case: must NOT appear in externals at all.
    dcc\libunit.pas -- indexed but placed under a subdir literally named
                        `dcc`, so its path contains '\dcc\' and IsLibraryPath
                        (DRagLint.Report.Deps.pas) fires -> classified as an
                        external even though the index resolved it. This is
                        the reliable way to force "indexed-but-library"
                        classification without a real Embarcadero install path.
    NotIndexedLib   -- referenced but never given a file -> stays
                        unresolved/external, group 'unknown'.
    System.SysUtils -- a real RTL name; nothing in this bare fixture defines
                        it, so it resolves the same way as NotIndexedLib
                        (unresolved), but ClassifyDepsGroup's name-prefix
                        rule ('system.' -> RTL) still classifies it into
                        group 'RTL' rather than 'unknown'. This is the
                        resolved-vs-group distinction the brief calls out:
                        assert group='RTL' here, NOT resolved=true.

  Indexing $work (the parent of both projmain/projhelper.pas AND dcc\)
  picks up all four fixture files in one pass, so LibUnit is present in the
  index (resolved=true) while also living under a library path.

  Load-bearing assertions (per the brief -- don't over-fit fragile group
  labels beyond the obvious ones):
    - ProjHelper NOT in externals            (the whole point of the verb)
    - NotIndexedLib in externals, resolved=false, group=unknown
    - LibUnit       in externals, resolved=true  (indexed, but under \dcc\)
    - System.SysUtils in externals, group=RTL
    - used_by_count >= 1 for every external; projmain in NotIndexedLib's used_by
    - shortest_path for a direct import is bare '>'-joined: projmain>NotIndexedLib
    - --edges JSON has a projmain -> NotIndexedLib row
    - --format csv emits the documented header + at least one data row
    - --json is byte-identical across two runs (determinism)

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-deps-report by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-deps-report"
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
# Resolve $Exe to an ABSOLUTE path up front, matching run_doc_returns.ps1's
# convention -- we run '& $Exe' from a neutral CWD but do not Push-Location
# for this test, so this is mostly defense-in-depth against a relative -Exe.
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$work = Join-Path $WorkDir 'fixture'
$dccDir = Join-Path $work 'dcc'
New-Item -ItemType Directory $work | Out-Null
New-Item -ItemType Directory $dccDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$ProjMainBody = @'
unit projmain;
interface
uses
  ProjHelper, NotIndexedLib, System.SysUtils;
implementation
uses
  LibUnit;
end.
'@

$ProjHelperBody = @'
unit projhelper;
interface
implementation
end.
'@

# Placed under \dcc\ so IsLibraryPath (DRagLint.Report.Deps.pas) matches the
# resolved file's path -- the reliable way to force "indexed-but-library"
# classification without needing a real Embarcadero install path on disk.
$LibUnitBody = @'
unit libunit;
interface
implementation
end.
'@

Write-Ascii (Join-Path $work 'projmain.pas')   $ProjMainBody
Write-Ascii (Join-Path $work 'projhelper.pas') $ProjHelperBody
Write-Ascii (Join-Path $dccDir 'libunit.pas')  $LibUnitBody

$db = Join-Path $WorkDir 'deps.sqlite'

Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

Write-Host ''
Write-Host 'deps-report --format json (rollup)' -ForegroundColor Cyan
# NOTE: deps-report only consults --format (text|json|csv) -- the generic
# --json shorthand flag (AArgs.AsJson) is parsed by the CLI but never read by
# DoDepsReport, so it is silently a no-op here; --format json is required.
# Diagnostics (e.g. "(loaded defaults ...)", "FTS5 probe: ...") go to
# stderr, so stdout is captured WITHOUT a 2>&1 merge to keep it pure JSON.
Push-Location $WorkDir
try {
  $jsonRaw1 = (& $Exe deps-report --db $db --format json) -join "`n"
} finally {
  Pop-Location
}

$rep = $null
try {
  $rep = $jsonRaw1 | ConvertFrom-Json
} catch {
  Check 'deps-report --json parses as JSON' $false "parse error: $($_.Exception.Message); raw=$jsonRaw1"
}

if ($null -ne $rep) {
  Check 'deps-report --json parses as JSON' $true

  $externals = @($rep.externals)
  $byUnit = @{}
  foreach ($e in $externals) { $byUnit[$e.unit] = $e }

  # -- NotIndexedLib: never given a file -> unresolved/external, group unknown.
  Check 'NotIndexedLib is in externals' ($byUnit.ContainsKey('NotIndexedLib')) ($externals.unit -join ', ')
  if ($byUnit.ContainsKey('NotIndexedLib')) {
    $nil_ = $byUnit['NotIndexedLib']
    Check 'NotIndexedLib resolved=false' ($nil_.resolved -eq $false) "resolved=$($nil_.resolved)"
    Check 'NotIndexedLib group=unknown'  ($nil_.group -eq 'unknown')  "group=$($nil_.group)"
    Check 'NotIndexedLib used_by_count >= 1' ($nil_.used_by_count -ge 1) "used_by_count=$($nil_.used_by_count)"
    Check 'projmain is in NotIndexedLib used_by' (@($nil_.used_by) -contains 'projmain') ($nil_.used_by -join ', ')
    Check 'NotIndexedLib shortest_path is bare projmain>NotIndexedLib' `
      ($nil_.shortest_path -eq 'projmain>NotIndexedLib') "shortest_path=$($nil_.shortest_path)"
  }

  # -- LibUnit: indexed (resolved) but path contains \dcc\ -> IsLibraryPath
  #    fires -> classified as external despite being indexed.
  #    SURPRISE (verified against DRagLint.Report.Deps.pas ClassifyDepsGroup):
  #    the SAME '\dcc\' substring that IsLibraryPath uses to mark a resolved
  #    path as a library is ALSO one of ClassifyDepsGroup's resolved-path
  #    triggers for group RTL ('\embarcadero\' or '\dcc\' -> dgRTL). So this
  #    fixture's LibUnit lands in group 'RTL', not 'other' -- that is correct,
  #    real classifier behavior given the '\dcc\' trick, not a bug. The
  #    load-bearing assertion here is resolved=true + presence in externals;
  #    the group label is documented but not over-fit to 'other'.
  Check 'LibUnit is in externals' ($byUnit.ContainsKey('LibUnit')) ($externals.unit -join ', ')
  if ($byUnit.ContainsKey('LibUnit')) {
    $lib = $byUnit['LibUnit']
    Check 'LibUnit resolved=true (indexed, but under \dcc\)' ($lib.resolved -eq $true) "resolved=$($lib.resolved)"
    Check 'LibUnit used_by_count >= 1' ($lib.used_by_count -ge 1) "used_by_count=$($lib.used_by_count)"
    Check 'LibUnit group=RTL (dcc\ path trigger doubles as RTL classifier)' ($lib.group -eq 'RTL') "group=$($lib.group)"
  }

  # -- System.SysUtils: unresolved in this bare fixture index, but the
  #    name-prefix rule ('system.' -> RTL) still classifies it as RTL.
  Check 'System.SysUtils is in externals' ($byUnit.ContainsKey('System.SysUtils')) ($externals.unit -join ', ')
  if ($byUnit.ContainsKey('System.SysUtils')) {
    $sysu = $byUnit['System.SysUtils']
    Check 'System.SysUtils group=RTL' ($sysu.group -eq 'RTL') "group=$($sysu.group)"
  }

  # -- ProjHelper: resolved AND not a library path -> a project unit. The
  #    key negative assertion -- the whole point of project-vs-external.
  Check 'ProjHelper is NOT in externals (resolved, non-library project unit)' `
    (-not $byUnit.ContainsKey('ProjHelper')) ($externals.unit -join ', ')

  Check 'summary.external_unit_count == externals.Length' `
    ($rep.summary.external_unit_count -eq $externals.Count) "summary=$($rep.summary.external_unit_count) actual=$($externals.Count)"
  Check 'summary.external_unit_count >= 3' ($rep.summary.external_unit_count -ge 3) "external_unit_count=$($rep.summary.external_unit_count)"
  Check 'summary.unresolved_count >= 1 (NotIndexedLib)' ($rep.summary.unresolved_count -ge 1) "unresolved_count=$($rep.summary.unresolved_count)"
}

Write-Host ''
Write-Host 'deps-report --edges --format json (flat edge list)' -ForegroundColor Cyan
$edgesRaw = (& $Exe deps-report --db $db --edges --format json) -join "`n"
$edgesRep = $null
try {
  $edgesRep = $edgesRaw | ConvertFrom-Json
} catch {
  Check 'deps-report --edges --json parses as JSON' $false "parse error: $($_.Exception.Message); raw=$edgesRaw"
}
if ($null -ne $edgesRep) {
  Check 'deps-report --edges --json parses as JSON' $true
  $edges = @($edgesRep.edges)
  $hasEdge = @($edges | Where-Object { $_.source_unit -eq 'projmain' -and $_.external_unit -eq 'NotIndexedLib' }).Count -gt 0
  Check 'edges contains projmain -> NotIndexedLib' $hasEdge ($edges | ForEach-Object { "$($_.source_unit)->$($_.external_unit)" }) -join ', '
}

Write-Host ''
Write-Host 'deps-report --format csv' -ForegroundColor Cyan
$csvRaw = (& $Exe deps-report --db $db --format csv)
$csvLines = @($csvRaw | ForEach-Object { "$_" })
Check 'csv header line present' ($csvLines.Count -gt 0 -and $csvLines[0] -eq 'unit,group,resolved,used_by_count,shortest_path') "header=$($csvLines | Select-Object -First 1)"
$csvDataRows = @($csvLines | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne '' })
Check 'csv has at least one data row' ($csvDataRows.Count -ge 1) "rows=$($csvDataRows.Count)"
Check 'csv has a data row for a known external (NotIndexedLib)' `
  (@($csvDataRows | Where-Object { $_ -match '^NotIndexedLib,' }).Count -gt 0) ($csvDataRows -join ' | ')

Write-Host ''
Write-Host 'Determinism: --format json run twice, byte-identical' -ForegroundColor Cyan
$jsonRaw2 = (& $Exe deps-report --db $db --format json) -join "`n"
Check 'two --format json runs are byte-identical' ($jsonRaw1 -ceq $jsonRaw2) "len1=$($jsonRaw1.Length) len2=$($jsonRaw2.Length)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
