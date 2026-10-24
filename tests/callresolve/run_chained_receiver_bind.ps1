<#
  run_chained_receiver_bind.ps1 -- a member reached through a CHAINED receiver
  binds: the leaf K of `R.Inner.K := 1` (receiver text `R.Inner`).

  THE DEFECT. TypeReceiver typed a single identifier (local, param, Result,
  field, unit var, type) and, for a dotted all-identifier receiver, only the
  UNIT-QUALIFIED TYPE shape (`Unit.TType.M` -> the LAST segment as a type
  name). `R.Inner` is a value chain, so the last segment `Inner` was looked up
  as a TYPE, found nothing, and K stayed unbound -- while the single-segment
  `L.K` beside it bound.

  THE FIX. A chained-member rung ahead of the unit-qualified one: type the
  head segment with the ordinary single-identifier rungs, then each following
  segment as a field / property (own type, then ancestors) of the previous
  segment's type. Any segment that cannot be typed ends the walk with no
  answer from this rung, and the unit-qualified rung runs exactly as before
  (so `Unit.TType.M` is unchanged).

  WHAT THIS GUARD PINS
    positive control  L.K (one segment) binds to TLeaf.K -- the binder works
    C1  R.Inner.K      record local -> field of the record -> TInner.K
    C2  O.Inner.K      param -> PROPERTY Inner -> TInner.K
    C3  O.Inner.Leaf.K three segments: Leaf -> TInner.Leaf, K -> TLeaf.K
    C4  O.Inner.Ping   a CALL through the chain -> call edge to TInner.Ping
    NEG1 O.Missing.K   an untypable middle segment -> K stays unbound
    NEG2 XUndeclared.Inner.K  an untypable head -> Inner and K stay unbound
  Three classes declare a K (TLeaf, TInner, TOther), so a name join cannot
  pass C1-C3 by accident.

  Usage: pwsh -File tests\callresolve\run_chained_receiver_bind.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\chainrecv')).Path
$scratch = Join-Path C:\TEMP "draglint_chained_receiver_bind_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$db = Join-Path $scratch 'chainrecv.sqlite'

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

$lines = [System.IO.File]::ReadAllLines((Join-Path $scratch 'uChainRcv.pas'))
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}

$idxOut = & $exePath index $scratch --db $db 2>&1 | Out-String
Check 'index exits 0' ($LASTEXITCODE -eq 0)

# Target of the member-access ref NAME on LINE (receiver text RCV), or '' when unbound.
function BoundTo([int]$Line, [string]$Name, [string]$Rcv) {
  $r = Sql ("SELECT s.qualified_name AS q FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id " +
            "WHERE r.kind = 'member-access' AND r.start_line = $Line AND r.name_text = '$Name' " +
            "AND r.receiver_text = '$Rcv'")
  if ($r.Count -ne 1) { return "<$($r.Count) refs>" }
  return "$($r[0].q)"
}

$l0 = LineOf 'L.K := 9;';          $l1 = LineOf 'R.Inner.K := 1;'
$l2 = LineOf 'O.Inner.K := 2;';    $l3 = LineOf 'O.Inner.Leaf.K := 3;'
$l4 = LineOf 'O.Inner.Ping;';      $n1 = LineOf 'O.Missing.K := 4;'
$n2 = LineOf 'XUndeclared.Inner.K := 5;'
Check 'fixture statements located' (@($l0,$l1,$l2,$l3,$l4,$n1,$n2) -notcontains -1)

$v = BoundTo $l0 'K' 'L';            Check 'positive control: L.K -> TLeaf.K' ($v -eq 'uChainRcv.TLeaf.K') $v
$v = BoundTo $l1 'K' 'R.Inner';      Check 'C1 R.Inner.K -> TInner.K' ($v -eq 'uChainRcv.TInner.K') $v
$v = BoundTo $l2 'K' 'O.Inner';      Check 'C2 O.Inner.K (property segment) -> TInner.K' ($v -eq 'uChainRcv.TInner.K') $v
$v = BoundTo $l3 'Leaf' 'O.Inner';   Check 'C3a O.Inner.Leaf -> TInner.Leaf' ($v -eq 'uChainRcv.TInner.Leaf') $v
$v = BoundTo $l3 'K' 'O.Inner.Leaf'; Check 'C3b O.Inner.Leaf.K -> TLeaf.K' ($v -eq 'uChainRcv.TLeaf.K') $v
$e = Sql ("SELECT COUNT(*) AS n FROM call_edges ce JOIN symbols s ON s.id = ce.target_symbol_id " +
          "WHERE s.qualified_name = 'uChainRcv.TInner.Ping'")
Check 'C4 O.Inner.Ping forms a call edge to TInner.Ping' ([int]$e[0].n -ge 1) "edges=$($e[0].n)"
$v = BoundTo $n1 'K' 'O.Missing';    Check 'NEG1 O.Missing.K stays unbound' ($v -eq '') $v
$v = BoundTo $n2 'Inner' 'XUndeclared';       Check 'NEG2a XUndeclared.Inner stays unbound' ($v -eq '') $v
$v = BoundTo $n2 'K' 'XUndeclared.Inner';     Check 'NEG2b XUndeclared.Inner.K stays unbound' ($v -eq '') $v

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  foreach ($d in @("C:\TEMP\draglint_chained_receiver_bind_$PID")) {
    if (Test-Path -LiteralPath $d) { try { [System.IO.Directory]::Delete($d, $true) } catch {} }
  }
}
