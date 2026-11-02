<#
  run_type_read_bind.ps1 -- a bare READ of a type name binds to the type:
  the class in a constructor call `TTrStore.Create(..)`, in a class-method call
  `TTrStore.Kind`, and a class-reference value `C := TTrStore`.

  WHAT WAS WRONG (resolver at main 7d1f399c): the parse records the receiver
  class of `TSQLiteSymbolStore.Create(` as a `read` ref named after the class,
  and no stream bound it -- the value stream keeps value kinds only. On a fresh
  index of src\cli\drag-lint.dproj all 53 such reads of TSQLiteSymbolStore
  stayed NULL (3,294 type-named reads overall), so `usages --name <qualified
  class>` reported `reads: 0` for a class constructed at 53 sites
  (stats\draglint-gaps.log 2026-10-30, backlog GAP-CALLERS).

  WHAT THIS GUARD PINS
    TR1  `TTrStore.Create('p')` -- the receiver read binds uTrStore.TTrStore
    TR2  `TTrStore.Kind`        -- the receiver read binds uTrStore.TTrStore
    TR3  `C := TTrStore`        -- the class-reference read binds uTrStore.TTrStore
    USG  usages --name uTrStore.TTrStore reports reads: 3
    PC   positive controls: the Create call still binds TTrStore.Create (call edge),
         and the value read `S` still binds the local (the value stream is not displaced)
    NOEDGE the type reads add no call_edges row

  Usage: pwsh -File tests\callresolve\run_type_read_bind.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\typeread')).Path
$scratch = Join-Path C:\TEMP "draglint_type_read_bind_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$db = Join-Path $scratch 'typeread.sqlite'

# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
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

$lines = [System.IO.File]::ReadAllLines((Join-Path $scratch 'uTrUser.pas'))
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  throw "fixture line not found: $Needle"
}

$null = & $exePath index $scratch --db $db 2>&1 | Out-String
Check 'index exits 0' ($LASTEXITCODE -eq 0)

$TYPE = 'uTrStore.TTrStore'
# The symbol the `read` ref named NAME on the line whose trimmed text is NEEDLE binds.
function ReadBinds([string]$Needle, [string]$Name) {
  $ln = LineOf $Needle
  $r = Sql ("SELECT COALESCE(s.qualified_name, '') AS q FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id " +
            "WHERE r.kind = 'read' AND r.name_text = '$Name' AND r.start_line = $ln")
  if ($r.Count -ne 1) { return "<$($r.Count) read refs>" }
  return $r[0].q
}

$q = ReadBinds "S := TTrStore.Create('p');" 'TTrStore'
Check 'TR1 TTrStore.Create receiver read -> TTrStore' ($q -eq $TYPE) $q
$q = ReadBinds 'K := TTrStore.Kind;' 'TTrStore'
Check 'TR2 TTrStore.Kind receiver read -> TTrStore' ($q -eq $TYPE) $q
$q = ReadBinds 'C := TTrStore;' 'TTrStore'
Check 'TR3 class-reference value read -> TTrStore' ($q -eq $TYPE) $q

$u = (& $exePath usages --name $TYPE --db $db 2>$null) -join "`n"
Check 'USG usages of the qualified class reports reads: 3' ($u -match 'reads: 3\b') (($u -split "`n" | Where-Object { $_ -match 'reads:' }) -join ' ')

$ln = LineOf "S := TTrStore.Create('p');"
$c = Sql ("SELECT COALESCE(t.qualified_name, '') AS q FROM refs r LEFT JOIN call_edges e ON e.ref_id = r.id " +
          "LEFT JOIN symbols t ON t.id = e.target_symbol_id WHERE r.kind = 'call' AND r.name_text = 'Create' AND r.start_line = $ln")
Check 'PC Create call still edges TTrStore.Create' (($c.Count -eq 1) -and ($c[0].q -eq 'uTrStore.TTrStore.Create')) $(if ($c.Count) { $c[0].q } else { 'no call ref' })
$q = ReadBinds 'K := K + S.ClassName;' 'S'
Check 'PC value read S still binds the local' ($q -eq 'uTrUser.UseStore.S') $q

$e = Sql ("SELECT COUNT(*) AS n FROM call_edges e JOIN symbols t ON t.id = e.target_symbol_id WHERE t.qualified_name = '$TYPE'")
Check 'NOEDGE no call_edges row targets the type' ($e[0].n -eq 0) "n=$($e[0].n)"

if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'
exit 0
} finally {
  if ($scratch -and (Test-Path $scratch)) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}