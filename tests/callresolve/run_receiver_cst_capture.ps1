<#
  run_receiver_cst_capture.ps1 -- T-11: the receiver of a qualified call /
  member access is a PARSE fact, and the resolver types it (kind 12).

  THE DEFECT. refs.receiver_text was re-read from ONE source line at resolve
  time (ExtractReceiverExpr). A fluent chain continued on the next line lost
  its receiver ('' -> treated as a BARE call) or kept a fragment that starts
  with '.' (garbage, never typed); a dot at line end gave ''. And no rung typed
  a `Name(...)` segment in chain position, so `O.Mk('a').Leaf.K` stayed unbound
  even on one line. R5: `(X as T).M` emitted no member-access ref at all.

  THE FIX. The extractor records the lhs of the exprDot (comments dropped,
  whitespace normalised) as receiver_text for every call / member-access; the
  resolver prefers it over the line scan; TypeReceiverCore kind 12 types a
  chain with call segments step by step (member, then method -> declared
  return type), declining on any untyped step. Ref-gap G4 emits the
  member-access of a parenthesised receiver.

  WHAT THIS GUARD PINS
    positive control  O.L.K (property chain, kind 10) binds to TLeaf.K
    P1  O.Mk('a') NL .Mk('b').Leaf.K   receivers + edges Mk -> TInner.Mk, K -> TLeaf.K
    P2  O. NL Mk('c')                   receiver `O`, edge -> TInner.Mk
    P3  O.Mk('d').L.K                   K -> TLeaf.K (call segment, then property)
    P4  (O as TInner) { note } .Leaf.K  comment dropped; K -> TLeaf.K
    P6  (O.Mk('e') as TInner).L.K       the blank after ')' survives: K -> TLeaf.K
    P5  M.Run                           interface head -> ICopy.Run
    R5  X:= (O as TInner).L             member-access L, receiver `(O as TInner)` -> TInner.L
    H1  X:= TInner(O).L                 hard cast: member-access L, receiver `TInner(O)` -> TInner.L
    H2  X:= Twin(O).L                   a FUNCTION of one arg: L typed by Twin's result -> TInner.L
    H3  X:= Nope(O).L                   undeclared head -> NO binding for L
    N1  Undeclared.Mk('x').K            untyped head -> NO binding for Mk or K
    N2  O.Missing('x').K                untyped call segment -> NO binding
    N3  K                               bare -> receiver '' after resolve, NO binding
    no fixture receiver starts with '.' or spans a line break
    idempotency: --resolve-only twice -> receivers and edges identical
    stale control: a line inserted at the TOP after indexing, re-resolved ->
      every receiver keeps its text (a line-scan engine shifts or blanks them);
      edges are not compared there -- a stale file declines, as before
  Two classes declare K (TLeaf, TOther): any edge on N1-N3 is a fabrication.

  Usage: pwsh -File tests\callresolve\run_receiver_cst_capture.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\recvcst')).Path
$scratch = Join-Path C:\TEMP "draglint_receiver_cst_capture_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$db  = Join-Path $scratch 'recvcst.sqlite'
$pas = Join-Path $scratch 'uRecvCst.pas'

# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function Sql([string]$Query) {
  $raw = (& $exePath sql --db $db --json --limit 5000 --query $Query 2>$null) -join "`n"
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

$lines = [System.IO.File]::ReadAllLines($pas)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}

# receiver_text of the ONE ref (KIND, NAME) on LINE; '<n refs>' otherwise, '<null>' for NULL.
function RcvOf([int]$Line, [string]$Name, [string]$Kind) {
  $r = Sql ("SELECT COALESCE(receiver_text, '<null>') AS t FROM refs WHERE kind = '$Kind' " +
            "AND start_line = $Line AND name_text = '$Name'")
  if ($r.Count -ne 1) { return "<$($r.Count) refs>" }
  return "$($r[0].t)"
}
# Every symbol any ref NAME on LINE binds to (refs.symbol_id or a call edge), sorted, ';'-joined.
function BoundOf([int]$Line, [string]$Name) {
  $r = Sql ("SELECT DISTINCT s.qualified_name AS q FROM refs r JOIN symbols s ON s.id = r.symbol_id " +
            "WHERE r.start_line = $Line AND r.name_text = '$Name' AND r.kind IN ('call','member-access') " +
            "UNION SELECT s.qualified_name FROM refs r JOIN call_edges ce ON ce.ref_id = r.id " +
            "JOIN symbols s ON s.id = ce.target_symbol_id WHERE r.start_line = $Line AND r.name_text = '$Name'")
  return ((@($r | ForEach-Object { "$($_.q)" }) | Sort-Object) -join ';')
}
function Snapshot([switch]$NoEdges) {
  $tail = if ($NoEdges) { "''" } else { "COALESCE(s.qualified_name,'')" }
  $r = Sql ("SELECT r.kind || ':' || r.name_text || ':' || r.start_col || ':' || COALESCE(r.receiver_text,'<null>') " +
            "|| '->' || $tail AS k FROM refs r LEFT JOIN call_edges ce ON ce.ref_id = r.id " +
            "LEFT JOIN symbols s ON s.id = ce.target_symbol_id WHERE r.kind IN ('call','member-access') " +
            "ORDER BY r.start_line, r.start_col, r.kind")
  return ((@($r | ForEach-Object { "$($_.k)" })) -join "`n")
}

$idxOut = & $exePath index $scratch --db $db 2>&1 | Out-String
Check 'index exits 0' ($LASTEXITCODE -eq 0)

$p1 = LineOf ".Mk('b').Leaf.K;";  $p2 = LineOf "Mk('c');"
$pc = LineOf 'O.L.K;';            $p3 = LineOf "O.Mk('d').L.K;"
$p4 = LineOf '(O as TInner) { note } .Leaf.K;'
$p6 = LineOf "(O.Mk('e') as TInner).L.K;"
$p5 = LineOf 'M.Run;';            $r5 = LineOf 'X:= (O as TInner).L;'
$n1 = LineOf "Undeclared.Mk('x').K;"; $n2 = LineOf "O.Missing('x').K;"
$n3 = LineOf 'K;'
$h1 = LineOf 'X:= TInner(O).L;'; $h2 = LineOf 'X:= Twin(O).L;'; $h3 = LineOf 'X:= Nope(O).L;'
Check 'fixture statements located' (@($p1,$p2,$pc,$p3,$p4,$p6,$p5,$r5,$n1,$n2,$n3,$h1,$h2,$h3) -notcontains -1)

$v = RcvOf $pc 'K' 'call';  Check 'positive control: O.L.K receiver' ($v -eq 'O.L') $v
$v = BoundOf $pc 'K';       Check 'positive control: O.L.K -> TLeaf.K' ($v -eq 'uRecvCst.TLeaf.K') $v

$v = RcvOf $p1 'Mk' 'call'; Check "P1a receiver of the continued Mk is O.Mk('a')" ($v -eq "O.Mk('a')") $v
$v = BoundOf $p1 'Mk';      Check 'P1a continued Mk -> TInner.Mk' ($v -eq 'uRecvCst.TInner.Mk') $v
$v = RcvOf $p1 'K' 'call';  Check "P1b receiver of K is O.Mk('a').Mk('b').Leaf" ($v -eq "O.Mk('a').Mk('b').Leaf") $v
$v = BoundOf $p1 'K';       Check 'P1b K -> TLeaf.K' ($v -eq 'uRecvCst.TLeaf.K') $v

$v = RcvOf $p2 'Mk' 'call'; Check 'P2 dot at line end: receiver O' ($v -eq 'O') $v
$v = BoundOf $p2 'Mk';      Check 'P2 Mk -> TInner.Mk' ($v -eq 'uRecvCst.TInner.Mk') $v

$v = RcvOf $p3 'K' 'call';  Check "P3 receiver O.Mk('d').L" ($v -eq "O.Mk('d').L") $v
$v = BoundOf $p3 'K';       Check 'P3 call segment then property: K -> TLeaf.K' ($v -eq 'uRecvCst.TLeaf.K') $v

$v = RcvOf $p4 'K' 'call';  Check 'P4 comment dropped: receiver (O as TInner).Leaf' ($v -eq '(O as TInner).Leaf') $v
$v = BoundOf $p4 'K';       Check 'P4 K -> TLeaf.K' ($v -eq 'uRecvCst.TLeaf.K') $v

$v = RcvOf $p6 'K' 'call';  Check "P6 receiver keeps the blank after ')': (O.Mk('e') as TInner).L" ($v -eq "(O.Mk('e') as TInner).L") $v
$v = BoundOf $p6 'K';       Check 'P6 K -> TLeaf.K' ($v -eq 'uRecvCst.TLeaf.K') $v

$v = RcvOf $p5 'Run' 'call'; Check 'P5 receiver M' ($v -eq 'M') $v
$v = BoundOf $p5 'Run';      Check 'P5 interface head -> ICopy.Run' ($v -eq 'uRecvCst.ICopy.Run') $v

$v = RcvOf $r5 'L' 'member-access'; Check 'R5 (X as T).M emits member-access L, receiver (O as TInner)' ($v -eq '(O as TInner)') $v
$v = BoundOf $r5 'L';               Check 'R5 L -> TInner.L' ($v -eq 'uRecvCst.TInner.L') $v

# 2b (1.37.0 B-FLOW): the HARD cast T(X).M emits the member-access too; the resolver's
# kind 6 / kind 11 decide cast vs call, so a real function is typed by its RESULT.
$v = RcvOf $h1 'L' 'member-access'; Check 'H1 T(X).M emits member-access L, receiver TInner(O)' ($v -eq 'TInner(O)') $v
$v = BoundOf $h1 'L';               Check 'H1 hard cast: L -> TInner.L' ($v -eq 'uRecvCst.TInner.L') $v
$v = RcvOf $h2 'L' 'member-access'; Check 'H2 F(X).M emits member-access L, receiver Twin(O)' ($v -eq 'Twin(O)') $v
$v = BoundOf $h2 'L';               Check 'H2 function, not a cast: L -> TInner.L via the result type' ($v -eq 'uRecvCst.TInner.L') $v
$v = RcvOf $h3 'L' 'member-access'; Check 'H3 the ref exists (the no-binding check below is not vacuous)' ($v -eq 'Nope(O)') $v
$v = BoundOf $h3 'L';               Check 'H3 undeclared head Nope(O): L has NO binding' ($v -eq '') $v

$v = RcvOf $n1 'K' 'call';  Check "N1 receiver Undeclared.Mk('x')" ($v -eq "Undeclared.Mk('x')") $v
$v = BoundOf $n1 'K';       Check 'N1 untyped head: K has NO binding' ($v -eq '') $v
$v = BoundOf $n1 'Mk';      Check 'N1 untyped head: Mk has NO binding' ($v -eq '') $v
$v = BoundOf $n2 'K';       Check 'N2 untyped call segment: K has NO binding' ($v -eq '') $v
$v = RcvOf $n3 'K' 'call';  Check "N3 bare K: receiver '' after resolve" ($v -eq '') $v
$v = BoundOf $n3 'K';       Check 'N3 bare K has NO binding' ($v -eq '') $v

$bad = Sql ("SELECT name_text || '@' || start_line || ' [' || receiver_text || ']' AS b FROM refs " +
            "WHERE receiver_text LIKE '.%' OR receiver_text LIKE '%' || char(10) || '%' OR receiver_text LIKE '%' || char(13) || '%'")
Check 'no receiver starts with . or spans a line break' ($bad.Count -eq 0) ((@($bad | ForEach-Object { $_.b })) -join ', ')

$snap1 = Snapshot
$text1 = Snapshot -NoEdges
$null = & $exePath index $scratch --db $db --resolve-only 2>&1 | Out-String
$snap2 = Snapshot
Check 'idempotency: a second resolve changes no receiver or edge' ($snap1 -eq $snap2)

# stale control: shift every line by one AFTER indexing, then re-resolve only.
$src = [System.IO.File]::ReadAllText($pas)
[System.IO.File]::WriteAllText($pas, "{ shifted }`r`n" + $src, [System.Text.Encoding]::ASCII)
$null = & $exePath index $scratch --db $db --resolve-only 2>&1 | Out-String
# Edges in a stale file are the existing decline-not-guess policy (1.35.1 drops them too); the TEXT is the fact.
$snap3 = Snapshot -NoEdges
Check 'stale control: every receiver keeps its text in a shifted source' ($text1 -eq $snap3)
if ($text1 -ne $snap3) {
  $a = $text1 -split "`n"; $b = $snap3 -split "`n"
  Compare-Object $a $b | Select-Object -First 8 | ForEach-Object { Write-Host ("   {0} {1}" -f $_.SideIndicator, $_.InputObject) }
}

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  foreach ($d in @("C:\TEMP\draglint_receiver_cst_capture_$PID")) {
    if (Test-Path -LiteralPath $d) { try { [System.IO.Directory]::Delete($d, $true) } catch {} }
  }
}