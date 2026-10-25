<#
  run_local_read_chain_bind.ps1 -- the READ of a local variable / parameter, and
  the member chain hanging off it, binds to its symbol (refs.symbol_id set),
  including a chain through an ARRAY ELEMENT (`A[0].K`) or a POINTER
  (`P^.K`, implicit `p.K`).

  BACKGROUND. INBOX-local-var-read-refs-unbound / INBOX-2026-10-05-converter-
  to-engine-local-read-unresolved: every read of a local was symbol_id NULL.
  The bare read and the record chain (`R.K`, `R.Inner.K`) were fixed by the
  resolver (B-28, kind 10); PC1-PC3 pin that. What stayed open is the chain
  whose receiver is not a plain identifier chain:
    * `A[0].K`, `R.Arr[1].K`, `pM[X].Sev` (TArray<T> alias), `D[1].K`
      (`array of T` alias): TypeReceiver gave up on any '[', so the member
      stayed unbound;
    * `P^.K`: the extractor emitted NO member-access for a dereferenced
      receiver, and ExtractReceiverExpr stopped at '^' and returned '' -- the
      value a BARE call yields -- so `P^.Ping;` was resolved as a bare call on
      the enclosing class (TFix.Ping), the routine the compiler does not pick;
    * `p.K` (Delphi's implicit dereference of a pointer-to-record): the
      receiver typed to the POINTER type PInner, which has no members.

  A16 (owner decision 2026-10-24): the base R of `R.K := v` stays a READ ref;
  the store is on the member row. PC3 pins that kind.

  WHAT THIS GUARD PINS
    PC1-PC3 positive controls (already green before this change): bare reads
            of a local and a parameter, and the record chain R.K.
    C1-C5   array-element chains bind to the element type's member.
    C6-C7   pointer chains bind to the pointee's member.
    C8      `P^.Ping;` is a call on TInner, NOT the enclosing TFix.Ping.
    C9      `A [1].K` -- a blank before the subscript -- still reads `A [1]`.
    C10     `R.Inner.K := 6` -- the WRITE leaf of a nested record chain (reparse-batch
            C1, folded into X1) binds to TInner.K; the base R stays a READ (A16).
    NEG1    `Undecl[0].K` -- an undeclared head -- stays unbound.
    NEG2    `Use(Undecl)` -- an undeclared name -- stays unbound.

  Usage: pwsh -File tests\callresolve\run_local_read_chain_bind.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\localread')).Path
$scratch = Join-Path C:\TEMP "draglint_local_read_chain_bind_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$db = Join-Path $scratch 'localread.sqlite'

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

$lines = [System.IO.File]::ReadAllLines((Join-Path $scratch 'uLocalRead.pas'))
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}

$null = & $exePath index $scratch --db $db 2>&1 | Out-String
Check 'index exits 0' ($LASTEXITCODE -eq 0)

# Target of the ref KIND/NAME on LINE (receiver RCV; '' = no receiver), or '' when
# unbound, or '<n refs>' when the shape is not exactly one row.
function BoundTo([int]$Line, [string]$Kind, [string]$Name, [string]$Rcv) {
  $rc = if ($Rcv -eq '') { "r.receiver_text IS NULL" } else { "r.receiver_text = '$Rcv'" }
  $r = Sql ("SELECT s.qualified_name AS q FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id " +
            "WHERE r.kind = '$Kind' AND r.start_line = $Line AND r.name_text = '$Name' AND $rc")
  if ($r.Count -ne 1) { return "<$($r.Count) refs>" }
  return "$($r[0].q)"
}

$p1 = LineOf 'X := pA;';         $p2 = LineOf 'Y := X;';          $p3 = LineOf 'R.K := Y;'
$c1 = LineOf 'A[0].K := 2;';     $c2 = LineOf 'Use(A[0].Inner.K);'
$c3 = LineOf 'R.Arr[1].K := 3;'; $c4 = LineOf 'Use(pM[X].Sev);';  $c5 = LineOf 'Use(D[1].K);'
$c6 = LineOf 'P^.K := 4;';       $c7 = LineOf 'Use(p.K);';        $c8 = LineOf 'P^.Ping;'
$c9 = LineOf 'A [1].K := 5;';    $c10 = LineOf 'R.Inner.K := 6;'
$n1 = LineOf 'Use(Undecl[0].K);'; $n2 = LineOf 'Use(Undecl);'
Check 'fixture statements located' (@($p1,$p2,$p3,$c1,$c2,$c3,$c4,$c5,$c6,$c7,$c8,$c9,$c10,$n1,$n2) -notcontains -1)

$Run = 'uLocalRead.TFix.Run'
$v = BoundTo $p1 'read' 'pA' '';     Check 'PC1 read of a parameter binds' ($v -eq "$Run.pA") $v
$v = BoundTo $p2 'read' 'X' '';      Check 'PC2 read of a local binds' ($v -eq "$Run.X") $v
$v = BoundTo $p3 'read' 'R' '';      Check 'PC3a base R of R.K := v is a READ ref (A16) and binds' ($v -eq "$Run.R") $v
$v = BoundTo $p3 'member-access' 'K' 'R'; Check 'PC3b R.K -> TRec.K' ($v -eq 'uLocalRead.TRec.K') $v
$v = BoundTo $p3 'read' 'Y' '';      Check 'PC3c RHS local read binds' ($v -eq "$Run.Y") $v

$v = BoundTo $c1 'read' 'A' '';      Check 'C1a base A of A[0].K binds' ($v -eq "$Run.A") $v
$v = BoundTo $c1 'member-access' 'K' 'A[0]'; Check 'C1b A[0].K -> TRec.K (array[..] of T local)' ($v -eq 'uLocalRead.TRec.K') $v
$v = BoundTo $c2 'member-access' 'Inner' 'A[0]';  Check 'C2a A[0].Inner -> TRec.Inner' ($v -eq 'uLocalRead.TRec.Inner') $v
$v = BoundTo $c2 'member-access' 'K' 'A[0].Inner'; Check 'C2b A[0].Inner.K -> TInner.K' ($v -eq 'uLocalRead.TInner.K') $v
$v = BoundTo $c3 'member-access' 'K' 'R.Arr[1]'; Check 'C3 R.Arr[1].K -> TInner.K (array field)' ($v -eq 'uLocalRead.TInner.K') $v
$v = BoundTo $c4 'member-access' 'Sev' 'pM[X]'; Check 'C4 pM[X].Sev -> TMsg.Sev (TArray<T> alias param)' ($v -eq 'uLocalRead.TMsg.Sev') $v
$v = BoundTo $c5 'member-access' 'K' 'D[1]'; Check 'C5 D[1].K -> TRec.K (array of T alias)' ($v -eq 'uLocalRead.TRec.K') $v
$v = BoundTo $c6 'read' 'P' '';      Check 'C6a base P of P^.K binds' ($v -eq "$Run.P") $v
$v = BoundTo $c6 'member-access' 'K' 'P^'; Check 'C6b P^.K -> TInner.K (explicit dereference)' ($v -eq 'uLocalRead.TInner.K') $v
$v = BoundTo $c7 'member-access' 'K' 'p'; Check 'C7 p.K -> TInner.K (implicit dereference)' ($v -eq 'uLocalRead.TInner.K') $v
$e = Sql ("SELECT s.qualified_name AS q FROM call_edges ce JOIN refs r ON r.id = ce.ref_id " +
          "JOIN symbols s ON s.id = ce.target_symbol_id WHERE r.start_line = $c8 AND r.name_text = 'Ping'")
$tg = @($e | ForEach-Object { $_.q }) -join ','
Check 'C8 P^.Ping is a call on TInner.Ping, not the enclosing TFix.Ping' ($tg -eq 'uLocalRead.TInner.Ping') $tg

$v = BoundTo $c9 'member-access' 'K' 'A [1]'; Check 'C9 A [1].K (blank before the subscript) -> TRec.K' ($v -eq 'uLocalRead.TRec.K') $v
$v = BoundTo $c10 'read' 'R' '';    Check 'C10a base R of R.Inner.K := 6 is a READ ref (A16) and binds' ($v -eq "$Run.R") $v
$v = BoundTo $c10 'member-access' 'Inner' 'R'; Check 'C10b R.Inner -> TRec.Inner' ($v -eq 'uLocalRead.TRec.Inner') $v
$v = BoundTo $c10 'member-access' 'K' 'R.Inner'; Check 'C10c leaf K of R.Inner.K := 6 -> TInner.K' ($v -eq 'uLocalRead.TInner.K') $v

$v = BoundTo $n1 'member-access' 'K' 'Undecl[0]'; Check 'NEG1 Undecl[0].K stays unbound' ($v -eq '') $v
$v = BoundTo $n2 'read' 'Undecl' '';  Check 'NEG2 read of an undeclared name stays unbound' ($v -eq '') $v

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  foreach ($d in @("C:\TEMP\draglint_local_read_chain_bind_$PID")) {
    if (Test-Path -LiteralPath $d) { try { [System.IO.Directory]::Delete($d, $true) } catch {} }
  }
}