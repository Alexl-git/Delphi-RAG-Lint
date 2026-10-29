<#
  run_interface_dispatch_generic.ps1 -- RB-5 P2 + P3 (resolver 1.17.0-alpha):
  GENERIC interfaces get `implements` edges, and same-arity OVERLOADS of an
  interface method pair with the one implementing method of the same
  parameter types.

  OWNER RULING 2026-09-16: a call through an interface-typed receiver is
  attributed to the INTERFACE method only; implementors are reachable through
  dispatch_edges kind 'implements'.

  WHAT WAS WRONG (resolver 1.16.0-alpha, measured on this fixture):
  * P2. ResolveImplements skipped every interface with generic_params
    ("generic=133" on ORM3 CLIENT): IStore<T>.Get / Put had NO implements
    edge, so TIntStore (lists IStore<Integer>) and TListStore<T> (lists
    IStore<T>) were unreachable from the interface method.
  * P3. Implements narrowed by ARITY only. IReader.Read(var A: Integer) and
    Read(var A: string) both have arity 1, so each got an 'ambiguous' edge to
    BOTH TReader.Read overloads (ORM3 CLIENT: 454 ambiguous implements rows,
    all of this shape -- IABZMemoryStream.Read x20, WriteB x18, ...).

  WHAT THIS GUARD PINS
    BIND1-4  calls through IStore<Integer> / IStore<string> receivers ->
             uGenStore.IStore.Get / Put, certain (green before: controls)
    BIND5    non-generic control O: IOther -> uGenStore.IOther.Get
    IMPL1-4  IStore.Get / Put -> TIntStore.* and TListStore.*, implements, certain
    NOLEAK   no IStore edge to TOtherStore (same names, does not list IStore)
    CTRL     IOther.Get -> TOtherStore.Get only (positive control, non-generic)
    OVL1-4   IReader.Read / Seek overloads -> exactly ONE TReader method each,
             the one with the same parameter types, certain

  Usage: pwsh -File tests\callresolve\run_interface_dispatch_generic.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\ifacedispatch-generic')).Path
$scratch = Join-Path C:\TEMP "draglint_interface_dispatch_generic_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$db = Join-Path $scratch 'ifacedispatch-generic.sqlite'

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

$lines = [System.IO.File]::ReadAllLines((Join-Path $scratch 'uGenUser.pas'))
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  throw "fixture line not found: $Needle"
}

$null = & $exePath index $scratch --db $db 2>&1 | Out-String
Check 'index exits 0' ($LASTEXITCODE -eq 0)

# --- call side: the edge of the `call` ref NAME on the line NEEDLE ---------
function EdgeOf([string]$Name, [string]$Needle) {
  $ln = LineOf $Needle
  $r = Sql ("SELECT COALESCE(t.qualified_name, '') AS q, COALESCE(e.confidence, '') AS c FROM refs r " +
            "LEFT JOIN call_edges e ON e.ref_id = r.id LEFT JOIN symbols t ON t.id = e.target_symbol_id " +
            "WHERE r.kind = 'call' AND r.name_text = '$Name' AND r.start_line = $ln")
  if ($r.Count -ne 1) { return @{ q = "<$($r.Count) call refs>"; c = '' } }
  return $r[0]
}
$sites = [ordered]@{
  'BIND1 local L: IStore<Integer>'  = @('Get', 'N:= L.Get(1);',         'uGenStore.IStore.Get')
  'BIND2 param P: IStore<Integer>'  = @('Get', 'N:= P.Get(2);',         'uGenStore.IStore.Get')
  'BIND3 field FStore: IStore<string>' = @('Put', "FStore.Put('field');", 'uGenStore.IStore.Put')
  'BIND4 param P.Put'               = @('Put', 'P.Put(N);',             'uGenStore.IStore.Put')
  'BIND5 control O: IOther'         = @('Get', 'N:= O.Get(3);',         'uGenStore.IOther.Get')
}
foreach ($k in $sites.Keys) {
  $s = $sites[$k]
  $e = EdgeOf $s[0] $s[1]
  Check "$k -> $($s[2]), certain" (($e.q -eq $s[2]) -and ($e.c -eq 'certain')) "edge=$($e.q) conf=$($e.c)"
}

# --- implements edges -------------------------------------------------------
function ImplsOf([string]$Base) {
  return Sql ("SELECT i.qualified_name AS impl, d.kind AS k, d.confidence AS c FROM dispatch_edges d " +
              "JOIN symbols b ON b.id = d.base_symbol_id JOIN symbols i ON i.id = d.impl_symbol_id " +
              "WHERE b.qualified_name = '$Base' ORDER BY i.qualified_name")
}
function Fmt($rows) { return (@($rows | ForEach-Object { "$($_.impl)/$($_.k)/$($_.c)" }) -join ', ') }

foreach ($m in 'Get', 'Put') {
  $rows = ImplsOf "uGenStore.IStore.$m"
  foreach ($cls in 'TIntStore', 'TListStore') {
    $hit = @($rows | Where-Object { $_.impl -eq "uGenStore.$cls.$m" -and $_.k -eq 'implements' -and $_.c -eq 'certain' })
    Check "IMPL IStore.$m -> $cls.$m implements certain" ($hit.Count -eq 1) (Fmt $rows)
  }
  $leak = @($rows | Where-Object { $_.impl -like 'uGenStore.TOtherStore.*' })
  Check "NOLEAK IStore.$m has no edge to TOtherStore" ($leak.Count -eq 0) (Fmt $rows)
}
$ctrl = ImplsOf 'uGenStore.IOther.Get'
Check 'CTRL IOther.Get -> TOtherStore.Get only, certain' (($ctrl.Count -eq 1) -and ($ctrl[0].impl -eq 'uGenStore.TOtherStore.Get') -and ($ctrl[0].c -eq 'certain')) (Fmt $ctrl)

# --- P3: same-arity overloads pair by parameter types ------------------------
# Each IReader overload, keyed by its own signature, must have exactly ONE
# certain edge, to the TReader method with the SAME signature text modulo spacing.
$ovl = Sql ("SELECT b.signature AS bs, i.signature AS isig, d.confidence AS c FROM dispatch_edges d " +
            "JOIN symbols b ON b.id = d.base_symbol_id JOIN symbols bp ON bp.id = b.parent_id AND bp.name = 'IReader' " +
            "JOIN symbols i ON i.id = d.impl_symbol_id")
$baseSigs = Sql "SELECT b.name AS n, b.signature AS bs FROM symbols b JOIN symbols bp ON bp.id = b.parent_id AND bp.name = 'IReader' WHERE b.kind = 'method' ORDER BY b.id"
Check 'OVL fixture has 4 IReader overloads' ($baseSigs.Count -eq 4) "n=$($baseSigs.Count)"
$i = 0
foreach ($b in $baseSigs) {
  $i++
  $mine = @($ovl | Where-Object { $_.bs -eq $b.bs })
  $same = @($mine | Where-Object { ($_.isig -replace '\s', '') -eq ($b.bs -replace '\s', '') -and $_.c -eq 'certain' })
  Check "OVL$i IReader.$($b.n)$($b.bs) -> one certain edge, same types" (($mine.Count -eq 1) -and ($same.Count -eq 1)) ((@($mine | ForEach-Object { "$($_.isig)/$($_.c)" })) -join ', ')
}

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  $d = Join-Path C:\TEMP "draglint_interface_dispatch_generic_$PID"
  if (Test-Path -LiteralPath $d) { [System.IO.Directory]::Delete($d, $true) }
}