<#
  run_enum_cast_bind.ps1 -- a hard cast to a project enum, `TEnum(x)`, binds to
  the enum type (lane X6, index gap G1 in
  docs\superpowers\specs\2026-10-25-three-lint-rules-design.md).

  THE DEFECT. `TCommandID(RspHdr.CommandID)` is extracted as a `call` ref with
  name_text 'TCommandID' and symbol_id NULL (1045 rows on ORM3), so a rule that
  asks "where does an ordinal become this enum" had to match by NAME.

  THE FIX: an EIGHTH calls-stage stream (ResolveEnumCastRefs ->
  TCallResolver.ResolveEnumCast). Same scope order as the type_use stream;
  only an ENUM binds; identity only (refs.symbol_id, NO call_edges row).

  WHAT THIS GUARD PINS
    EC-*   two casts bind: own-unit enum, used-unit enum
    NEG-*  three stay NULL: a CLASS cast (only enums bind), a unit-qualified
           cast (declined, not guessed), a name two used units declare
    no call_edges row for a bound cast (find-callers unchanged)
    the binding survives an incremental (scoped) reindex of the using unit
    the calls-stage `enum-casts:` log line

  Usage: pwsh -File tests\callresolve\run_enum_cast_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\enumcasts')).Path
$scratch = Join-Path C:\TEMP "draglint_enum_cast_bind_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$use = Join-Path $scratch 'uEcUse.pas'
$db  = Join-Path $scratch 'enumcasts.sqlite'

function Sql([string]$Query) {
  $raw = (& $exePath sql --db $db --json --limit 1000 --query $Query 2>$null) -join "`n"
  $b = $raw.IndexOf('{')
  if ($b -lt 0) { throw "sql returned no JSON for: $Query" }
  $o = $raw.Substring($b) | ConvertFrom-Json
  $names = @($o.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($o.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += $h
  }
  return ,@($out)
}
function LineOf([string]$Marker) {
  $m = @(Select-String -LiteralPath $use -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}
function CastAt([string]$Marker, [string]$Name) {
  $line = LineOf $Marker
  return @(Sql ("SELECT r.id, r.symbol_id, t.qualified_name AS tq, " +
                "(SELECT COUNT(*) FROM call_edges e WHERE e.ref_id = r.id) AS edges " +
                "FROM refs r JOIN files f ON f.id = r.file_id " +
                "LEFT JOIN symbols t ON t.id = r.symbol_id WHERE f.path LIKE '%uEcUse.pas' AND r.kind = 'call' " +
                "AND r.start_line = $line AND r.name_text = '$Name'") | Where-Object { $_ })
}
function CheckAll([string]$Phase) {
  foreach ($p in @(@('EC-OWN', 'TOwnKind', 'uEcUse.TOwnKind'), @('EC-USED', 'TLibKind', 'uEcLib.TLibKind'))) {
    $r = @(CastAt $p[0] $p[1])
    $got = if ($r.Count -eq 1) { [string]$r[0].tq } else { "rows=$($r.Count)" }
    Check "$Phase $($p[0]) binds $($p[1]) to $($p[2])" ($got -eq $p[2]) "got=$got"
    if ($r.Count -eq 1) { Check "$Phase $($p[0]) writes no call edge" ([int]$r[0].edges -eq 0) "edges=$($r[0].edges)" }
  }
  foreach ($n in @(@('NEG-CLASS', 'TLibClass'), @('NEG-QUALIFIED', 'TLibKind'), @('NEG-AMBIGUOUS', 'TClashE'))) {
    $r = @(CastAt $n[0] $n[1])
    Check "$Phase $($n[0]) $($n[1]) stays unbound" (($r.Count -ge 1) -and (@($r | Where-Object { $null -ne $_.symbol_id }).Count -eq 0)) `
      ("rows=$($r.Count) tq=" + $(if ($r.Count) { $r[0].tq } else { '' }))
  }
}

$log = & $exePath index $scratch --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
CheckAll 'full'
$line = @($log | Where-Object { "$_" -match 'enum-casts: (\d+) of (\d+)' })
Check 'calls-stage enum-casts: line present' ($line.Count -eq 1) "lines=$($line.Count)"

# incremental: touch the using unit (append a trailing comment) and reindex
[IO.File]::AppendAllText($use, "{ touched }`r`n", [Text.Encoding]::ASCII)
$log2 = & $exePath index $scratch --db $db 2>&1
Check 'incremental index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
CheckAll 'incremental'

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  if ($scratch -and (Test-Path $scratch)) { [System.IO.Directory]::Delete($scratch, $true) }
}
