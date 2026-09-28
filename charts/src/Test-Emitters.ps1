<#
  Test-Emitters.ps1 -- executable verification for the diagram emitters.

  Mirrors Test-FormA.ps1: param block, $fail list, Fail, exit 0/1, -Quiet.

  Every expected number here was MEASURED against the named indexes on
  2026-09-23 and is asserted, not recomputed. If one of them moves, that is a
  FINDING -- the index changed, or an emitter did -- and the right response is
  to investigate before editing the number. Re-baselined 2026-09-24 against the
  extractor 1.19 / resolver 1.8 clones: every moved pin says RE-BASELINED or
  "was N at 1.18" beside it, with the mechanism traced against *.pre-1.19.

  The negative cases matter as much as the positive ones, and they assert two
  things each: that the failure message says the RIGHT thing, and that NO .svg
  was left behind. A refusal that still writes a chart is the failure this
  suite exists to catch, because the chart outlives the message.
#>
[CmdletBinding()]
param(
  # The CLONES, not the live corpus. The defaults used to be the originals, which
  # made the safe path the one you had to remember -- and Get-CloneDb now refuses
  # them outright, so the old defaults would fail every block for the right
  # reason but at the wrong moment. Clones also freeze the counts asserted below.
  [string] $DbCli  = (Join-Path $PSScriptRoot '..\scratch\db\CLIENT-Micronite2027.sqlite'),
  [string] $DbSrv  = (Join-Path $PSScriptRoot '..\scratch\db\SERVER-MicroniteMW1Service.sqlite'),
  # DL carries the only INTERFACE cycle in the corpus and DataCopy the only
  # acyclic index and the only single-folder project, so between them they cover
  # three shapes CLIENT and SERVER simply do not contain.
  [string] $DbDl   = (Join-Path $PSScriptRoot '..\scratch\db\DL-drag-lint.sqlite'),
  [string] $DbDc   = (Join-Path $PSScriptRoot '..\scratch\db\DataCopy-DataCopy.sqlite'),
  # A TEST project index. tested-by cannot be asked of CLIENT or SERVER at all:
  # the [Test] attributes live here, and so does the code under test.
  [string] $DbMt   = (Join-Path $PSScriptRoot '..\scratch\db\TESTS-MicroniteTests.sqlite'),
  # The SQL-SCRIPT index (12 Firebird .SQL files). consumers / lands-where read
  # tables, columns and trigger bodies from it; it holds no Delphi code.
  [string] $DbSql  = (Join-Path $PSScriptRoot '..\scratch\db\SQL-drag-lint-sql.sqlite'),
  [string] $OutDir = (Join-Path $PSScriptRoot ('..\scratch\test-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))),
  [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
$fail = New-Object System.Collections.ArrayList
function Fail([string] $code, [string] $msg) {
  [void]$fail.Add([pscustomobject]@{ Code = $code; Message = $msg })
}
function Chk([string] $code, $actual, $expected) {
  if ("$actual" -ne "$expected") { Fail $code "expected $expected, got $actual" }
}
function Note([string] $s) { if (-not $Quiet) { Write-Host $s } }

# Each positive block runs under Step so an UNEXPECTED throw is recorded and the
# suite carries on. Without it the first broken emitter aborts the run and the
# report is silently truncated -- you learn that something failed, not what
# else would have.
#
# The blocks assign with $script: on purpose. Dot-sourcing a scriptblock INSIDE
# a function runs it in that FUNCTION's scope, not the caller's, so a plain
# `$b = ...` would vanish when Step returned -- and the summary would print "?"
# for every number while still reporting PASS. Measured: it did exactly that.
function Step([string] $code, [scriptblock] $body) {
  try { . $body } catch { Fail $code "unexpected error: $($_.Exception.Message)" }
}
# summary access that survives a block that never ran
function V($o, [string] $p) { if ($o) { $o.$p } else { '?' } }

New-Item -ItemType Directory -Force $OutDir | Out-Null
$SRC = $PSScriptRoot
$Q_SEND = 'Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation'
$Q_RESV = 'Blueprint4.ViewModel.TBlueprint_ViewModel.ReserveNextID'
$Q_COPY = 'uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation'
$Q_LOAD = 'uPipeSessionBuilder.TPipeSessionBuilder.HandleTableLoad'

# ---- 1. bytes: strict 7-bit ASCII, CRLF, no BOM ------------------------------
$nonAscii = 0; $bareLf = 0
foreach ($f in (Get-ChildItem "$SRC\*.ps1")) {
  $t = [IO.File]::ReadAllText($f.FullName)
  $n = ([regex]::Matches($t, '[^\x09\x0A\x0D\x20-\x7E]')).Count
  $l = ([regex]::Matches($t, "(?<!\r)\n")).Count
  if ($n) { Fail 'E-CHARSET' "$($f.Name): $n byte(s) outside 0x20-0x7E/CR/LF" }
  if ($l) { Fail 'E-EOL' "$($f.Name): $l bare LF" }
  $nonAscii += $n; $bareLf += $l
}

# ---- 2. positives ------------------------------------------------------------
function Dot([object] $r) { [IO.File]::ReadAllText($r.Dot) }
# href assertions anchor on the closing quote so line=52 cannot match line=521
function HasLine([string] $dot, [int] $line) { $dot -match ("line=$line" + '"') }

Note 'butterfly (regression) ...'
Step 'E-BF' {
  $script:b = & "$SRC\Emit-Butterfly.ps1" -Qname $Q_SEND -DbPath $DbCli -Depth 2 -OutDir $OutDir
  Chk 'A-BF-CALLERS' $b.Callers 9
  # 9 callees / 19 clicks / 18 arrows, was 8 / 18 / 17 on the 1.18 clone. Traced
  # (1.19 re-baseline, engine D1/ENG-16 parenless calls now bound): hop 2 gains
  # TPipeClientConnection.NextSeq, called bare -- `BuildHeader(ACmd, NextSeq, ...)`
  # at uPipeClientConnection.pas:470 in ExecuteCommand. No other row moved.
  Chk 'A-BF-CALLEES' $b.Callees 9
  Chk 'A-BF-CLICKS'  $b.ClickTargets 19
  if (-not $b.AllClickable) { Fail 'A-BF-CLICKABLE' 'butterfly rows are not all anchored' }
  # D6 fix: arrows follow the tree. All 9 callers are depth 1; of the 9 callees
  # only 2 are called BY SendDeltaOperation (what-it-calls d1 = 2), the other 7
  # are hop 2. The old flatten drew all of them as direct calls.
  Chk 'A-BF-FOCUSIN'  $b.FocusIn 9
  Chk 'A-BF-FOCUSOUT' $b.FocusOut 2
  Chk 'A-BF-EDGES'    $b.Edges 18
}

# D6 (engine INBOX, 2026-09-23): the butterfly listed duplicate callee rows. The
# engine's tree repeats a symbol reached through a second parent (the repeat is
# marked cycle and not expanded); the emitter flattened the tree and appended
# every node. On this target the 1.18 tree had 14 callee nodes for 11 symbols:
# GetTransitiveAncestors, GetSymbolById and VisibleHere each appeared twice
# (1.19: 19 for 16 -- see A-BF6-SIDEPARSE).
Note 'butterfly D6 (duplicate rows) ...'
Step 'E-BF-D6' {
  $script:b6 = & "$SRC\Emit-Butterfly.ps1" -Qname 'DRagLint.Index.CallResolver.TCallResolver.ResolveEnumValueRead' `
                 -DbPath $DbDl -Depth 2 -OutDir $OutDir
  $t6 = Dot $b6
  # FAILS ON ANY DUPLICATE: every row TITLE is "<qname>  --  <file>:<line>", so a
  # repeated title is a repeated row, and a repeated edge line a repeated arrow.
  # Scoped PER SIDE: a symbol that is both a caller and a callee legitimately
  # has one row on each side. The side is the cluster id (cluster_in_ /
  # cluster_out_); each cluster's table is the node line inside it.
  $sideTitles = New-Object System.Collections.ArrayList
  foreach ($cm in [regex]::Matches($t6, '(?s)subgraph (cluster_(in|out)_\d+) \{.*?\n  \}')) {
    foreach ($tm in [regex]::Matches($cm.Value, 'TITLE="([^"]+)"')) {
      [void]$sideTitles.Add("$($cm.Groups[2].Value)|$($tm.Groups[1].Value)")
    }
  }
  # RE-BASELINED at 1.19 (2026-09-24). The DL clone is a self-index of the
  # engine's OWN source, re-taken at 1.19 (130 -> 134 files), and the focus body
  # itself was rewritten (CallResolver.pas 1979-2106 -> 2667-2810): it now calls
  # AncestorsOf where it called ISymbolStore.GetTransitiveAncestors, and adds
  # WithScopeAt (the D14 with-body work), whose 4 children are new hop-2 rows
  # (WithStatementsOf, FileIsStale, PosAtOrBefore, LayerVerdict); and two hop-1
  # bodies swapped FStore.GetSymbolById / GetTransitiveAncestors for the local
  # SymbolById / AncestorsOf. So +7 callee symbols, -2 (GetTransitiveAncestors,
  # GetSymbolById): 11 -> 16. The 2 callers only moved lines.
  # A SOURCE change, not a binding change -- diffed row by row against the
  # pre-1.19 clone. The D6 shape survives: 19 callee tree nodes for 16 symbols,
  # the 3 repeats now VisibleHere, AncestorsOf and SymbolById.
  if ($sideTitles.Count -ne 18) { Fail 'A-BF6-SIDEPARSE' "expected 18 side rows (2 in + 16 out), parsed $($sideTitles.Count)" }
  $dupRows  = @($sideTitles | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
  $dupEdges = @([regex]::Matches($t6, '(?m)^\s+(\S+ -> \S+) \[') | ForEach-Object { $_.Groups[1].Value } |
                Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
  if ($dupRows.Count)  { Fail 'A-BF6-DUPROWS'  ("duplicate rows: " + ($dupRows -join '; ')) }
  if ($dupEdges.Count) { Fail 'A-BF6-DUPEDGES' ("duplicate edges: " + ($dupEdges -join '; ')) }
  Chk 'A-BF6-CALLERS'  $b6.Callers 2
  Chk 'A-BF6-CALLEES'  $b6.Callees 16      # 19 tree nodes, 3 repeats
  # 21 = one arrow per tree node (2 + 19): the 3 repeats are REAL calls from a
  # second parent, so they keep their arrow and lose only their row.
  Chk 'A-BF6-EDGES'    $b6.Edges 21
  Chk 'A-BF6-FOCUSOUT' $b6.FocusOut 7      # the engine's depth-1 children (6 - GetTransitiveAncestors + AncestorsOf + WithScopeAt)
  Chk 'A-BF6-CLICKS'   $b6.ClickTargets 19 # 2 + 16 + focus
}

Note 'deps (regression) ...'
Step 'E-DEP' {
  $script:d = & "$SRC\Emit-Deps.ps1" -Unit 'Blueprint4.ViewModel' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-DEP-USEDBY' $d.UsedBy 3
  Chk 'A-DEP-USES'   $d.Uses 18
  Chk 'A-DEP-EXP'    $d.Expected 21
}

Note 'who-calls SendDeltaOperation d2 ...'
Step 'E-WC1' {
  $script:w1 = & "$SRC\Emit-WhoCalls.ps1" -Qname $Q_SEND -DbPath $DbCli -Depth 2 -OutDir $OutDir
  Chk 'A-WC1-CALLERS'  $w1.Callers 9
  Chk 'A-WC1-CYCLES'   $w1.Cycles 0
  Chk 'A-WC1-MAXDEPTH' $w1.MaxDepth 1
  Chk 'A-WC1-TRUNC'    $w1.Truncated $false
  Chk 'A-WC1-CLUSTERS' $w1.Clusters 1
  Chk 'A-WC1-EXP'      $w1.Expected 10
  Chk 'A-WC1-NAMEONLY' $w1.NameOnly 0
  if (-not (HasLine (Dot $w1) 3960)) { Fail 'A-WC1-FOCUS' 'focus href is not the impl line 3960' }
}

Note 'who-calls ReserveNextID d3 ...'
Step 'E-WC2' {
  $script:w2 = & "$SRC\Emit-WhoCalls.ps1" -Qname $Q_RESV -DbPath $DbCli -Depth 3 -OutDir $OutDir
  Chk 'A-WC2-CALLERS'  $w2.Callers 10
  Chk 'A-WC2-CYCLES'   $w2.Cycles 1
  Chk 'A-WC2-MAXDEPTH' $w2.MaxDepth 2
  Chk 'A-WC2-CLUSTERS' $w2.Clusters 2
  Chk 'A-WC2-EXP'      $w2.Expected 11
  Chk 'A-WC2-NAMES'    $w2.NameMatches 18
  Chk 'A-WC2-NAMEONLY' $w2.NameOnly 9
  $t2 = Dot $w2
  Chk 'A-WC2-EDGES' ([regex]::Matches($t2, '(?m)^\s+n\d+:p\d+ -> ')).Count 10
  if (-not (HasLine $t2 4018)) { Fail 'A-WC2-FOCUS' 'focus href is not the impl line 4018' }
  if (-not (HasLine $t2 4102)) { Fail 'A-WC2-CYCLEROW' 'the depth-2 cycle row at :4102 is missing' }
  Chk 'A-WC2-DASHED' ([regex]::Matches($t2, 'style=dashed')).Count 1
}

Note 'who-calls ReserveNextID d1 (depth limit touched) ...'
Step 'E-WC3' {
  $script:w3 = & "$SRC\Emit-WhoCalls.ps1" -Qname $Q_RESV -DbPath $DbCli -Depth 1 -OutDir $OutDir
  Chk 'A-WC3-CALLERS' $w3.Callers 9
  Chk 'A-WC3-TRUNC'   $w3.Truncated $true
}

Note 'who-calls ReserveNextID d3 -WithNameMatches ...'
Step 'E-WC4' {
  $script:w4 = & "$SRC\Emit-WhoCalls.ps1" -Qname $Q_RESV -DbPath $DbCli -Depth 3 -WithNameMatches -OutDir (Join-Path $OutDir 'nm')
  Chk 'A-WC4-CALLERS'  $w4.Callers 10          # the resolved count must NOT move
  Chk 'A-WC4-RENDERED' $w4.NameRendered $true
  Chk 'A-WC4-CLUSTERS' $w4.Clusters 4
  Chk 'A-WC4-EXP'      $w4.Expected 20
  # name rows get NO edge: an edge would assert the very call that is unproven
  Chk 'A-WC4-EDGES' ([regex]::Matches((Dot $w4), '(?m)^\s+n\d+:p\d+ -> ')).Count 10
}

# what-it-calls is who-calls walked the other way, so it is tested at THREE
# depths: the rows+1 == node_count invariant was challenged for the callee
# direction and then verified, cycles present and all (2/3, 9/10, 18/19). The
# depth-2 row count is also the regression that ties this emitter to butterfly's
# Callees -- if those two ever disagree, one of them is reading the tree wrong.
Note 'what-it-calls SendDeltaOperation d1/d2/d3 ...'
Step 'E-WIC' {
  $script:c1 = & "$SRC\Emit-WhoCalls.ps1" -Qname $Q_SEND -DbPath $DbCli -Direction callees -Depth 1 -OutDir $OutDir
  Chk 'A-WIC1-ROWS'  $c1.Rows 2
  Chk 'A-WIC1-NODES' $c1.NodeCount 3
  Chk 'A-WIC1-TRUNC' $c1.Truncated $true

  $script:c2 = & "$SRC\Emit-WhoCalls.ps1" -Qname $Q_SEND -DbPath $DbCli -Direction callees -Depth 2 -OutDir $OutDir
  # 9 / 10, was 8 / 9 at 1.18: + NextSeq (engine D1 parenless call, see A-BF-CALLEES)
  Chk 'A-WIC2-ROWS'    $c2.Rows 9
  Chk 'A-WIC2-NODES'   $c2.NodeCount 10
  Chk 'A-WIC2-CYCLES'  $c2.Cycles 0
  Chk 'A-WIC2-CALLERS' $c2.Callers 0        # the callers counter must stay empty
  # the tie to butterfly: same method, same depth, same callee count
  if ($b -and $b.Callees -ne $c2.Rows) {
    Fail 'A-WIC2-BUTTERFLY' "butterfly says $($b.Callees) callees, what-it-calls says $($c2.Rows)"
  }
  # NOT asked downward, so it must be $null -- a 0 would read as a measured zero
  if ($null -ne $c2.NameMatches) { Fail 'A-WIC2-NAMENULL' "NameMatches must be null walking callees, got $($c2.NameMatches)" }

  $script:c3 = & "$SRC\Emit-WhoCalls.ps1" -Qname $Q_SEND -DbPath $DbCli -Direction callees -Depth 3 -OutDir $OutDir
  # 18 / 19, was 16 / 17 at 1.18 -- both engine D1 (parenless calls bound):
  # + NextSeq (hop 2) and + uLogPaths.ResolveLogDir (hop 3), a parenless FREE
  # function called as `IncludeTrailingPathDelimiter(ResolveLogDir)` at
  # uLogPaths.pas:91 in LogFilePath. Cycles unchanged.
  Chk 'A-WIC3-ROWS'   $c3.Rows 18
  Chk 'A-WIC3-NODES'  $c3.NodeCount 19
  Chk 'A-WIC3-CYCLES' $c3.Cycles 5
  # the arrow means "calls", so walking callees it must leave the FOCUS, never
  # arrive at it. An edge INTO focus here would assert the relationship backwards.
  $t3 = Dot $c3
  if ([regex]::Matches($t3, '(?m)^\s+focus -> ').Count -eq 0) {
    Fail 'A-WIC3-EDGEDIR' 'no edge leaves the focus -- the callee arrows are reversed'
  }
  if ([regex]::Matches($t3, '(?m)^\s+n\d+:p\d+ -> focus').Count -gt 0) {
    Fail 'A-WIC3-EDGEDIR2' 'an edge points INTO the focus -- that is the caller direction'
  }
  # the two directions must not overwrite each other's artifacts
  if ($w1 -and $c2.Svg -eq $w1.Svg) { Fail 'A-WIC-COLLIDE' 'callers and callees wrote the same .svg path' }
}

Note 'event-wiring uMain.TfrmMAIN ...'
Step 'E-EW1' {
  $script:e1 = & "$SRC\Emit-EventWiring.ps1" -Form 'uMain.TfrmMAIN' -DbPath $DbCli -OutDir $OutDir
  # 43/41/5, was 41/40/3 before extractor 1.18 (2026-09-23): the define profile
  # now reads Base_Win64, EUREKALOG is live, and the two EurekaLogEvents1 handlers
  # (OnCustomDataRequest, OnExceptionNotify) declared under {$IFDEF EurekaLog} parse.
  Chk 'A-EW1-EVENTS'     $e1.Events 43
  Chk 'A-EW1-HANDLERS'   $e1.Handlers 43
  Chk 'A-EW1-COMPONENTS' $e1.Components 41
  Chk 'A-EW1-KINDS'      $e1.EventKinds 5
  Chk 'A-EW1-DFMSUM'     ($e1.DfmResolved + $e1.DfmFallback) 43
  Chk 'A-EW1-EXP'        $e1.Expected 86
  Chk 'A-EW1-CLICKS'     $e1.ClickTargets 86
  $te = Dot $e1
  foreach ($ln in 52, 790, 4371) {                       # DFM: OnCreate / OnClick / Exit2
    if (-not (HasLine $te $ln)) { Fail 'A-EW1-DFMHREF' "uMain.dfm:$ln is not anchored" }
  }
  foreach ($ln in 1122, 266, 956) {                      # PAS: handler impl lines
    if (-not (HasLine $te $ln)) { Fail 'A-EW1-PASHREF' "uMain.pas:$ln is not anchored" }
  }
  # the fact, not the naming convention: Exit2.OnClick -> WindowClose1Execute
  if ($te -notmatch 'WindowClose1Execute') { Fail 'A-EW1-FACT' 'Exit2.OnClick did not resolve to WindowClose1Execute' }
}

Note 'event-wiring -Control PrinterSetup1 ...'
Step 'E-EW2' {
  $script:e2 = & "$SRC\Emit-EventWiring.ps1" -Form 'uMain.TfrmMAIN' -Control 'PrinterSetup1' -DbPath $DbCli -OutDir (Join-Path $OutDir 'ctl')
  Chk 'A-EW2-EVENTS'   $e2.Events 1
  Chk 'A-EW2-HANDLERS' $e2.Handlers 1
  Chk 'A-EW2-EXP'      $e2.Expected 2
}

Note 'event-wiring Blueprint4.TfrmBlueprint4 (scale, 516 dfm-type rows vs a 200 cap) ...'
Step 'E-EW3' {
  $script:e3 = & "$SRC\Emit-EventWiring.ps1" -Form 'Blueprint4.TfrmBlueprint4' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-EW3-EVENTS'     $e3.Events 96
  Chk 'A-EW3-HANDLERS'   $e3.Handlers 96
  Chk 'A-EW3-COMPONENTS' $e3.Components 74
  Chk 'A-EW3-EXP'        $e3.Expected 192
  Chk 'A-EW3-FALLBACK'   $e3.DfmFallback 0
}

# who-writes / who-reads. Every number here came from TWO independent routes --
# the uncapped verb and the bounded site SQL -- and CrossCheck asserts they
# agreed. A mismatch is a finding, so the suite treats it as a failure rather
# than reporting whichever number happened to be larger.
Note 'who-writes/who-reads R (field, both wings) ...'
Step 'E-MA1' {
  $script:m1 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'MSCTYPES.RChartSampleData.R' -Mode both -DbPath $DbCli -OutDir $OutDir
  Chk 'A-MA1-KIND'     $m1.Kind 'field'
  Chk 'A-MA1-WRITES'   $m1.Writes 7
  Chk 'A-MA1-READS'    $m1.Reads 13
  Chk 'A-MA1-ROUTINES' $m1.Routines 4
  Chk 'A-MA1-SITES'    $m1.Sites 20
  Chk 'A-MA1-HIDDEN'   $m1.HiddenRoutines 0
  Chk 'A-MA1-UNANCH'   $m1.Unanchored 0
  Chk 'A-MA1-XCHECK'   $m1.CrossCheck 'agree'
  # 3 writers + 4 readers: three routines appear on BOTH sides, which is the
  # honest answer, not a double count. Routines (4) is DISTINCT; Shown (7) is rows.
  Chk 'A-MA1-WRITERS'  $m1.ShownWriters 3
  Chk 'A-MA1-READERS'  $m1.ShownReaders 4
  Chk 'A-MA1-SHOWN'    $m1.Shown 7
  # a field access has accessor_symbol_id NULL by owner ruling -- 0 routines
  # here would mean the emitter read that column instead of asking the verb
  if ($m1.Routines -eq 0) { Fail 'A-MA1-FINDING1' 'read accessor_symbol_id instead of asking the verb' }
  # the site anchor is the ACCESS, not the routine declaration
  if (-not (HasLine (Dot $m1) 4072)) { Fail 'A-MA1-SITE' 'BASICSF.pas:4072 is not anchored' }
}

Note 'who-writes/who-reads VERDICT (property with method accessors) ...'
Step 'E-MA2' {
  $script:m2 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'iINSPRSLT.ImcINSPRSLT.VERDICT' -Mode both -DbPath $DbCli -OutDir $OutDir
  Chk 'A-MA2-KIND'     $m2.Kind 'property'
  Chk 'A-MA2-WRITES'   $m2.Writes 34
  Chk 'A-MA2-READS'    $m2.Reads 12
  Chk 'A-MA2-ROUTINES' $m2.Routines 30
  Chk 'A-MA2-SITES'    $m2.Sites 46
  Chk 'A-MA2-XCHECK'   $m2.CrossCheck 'agree'
  # backed by METHODS, so the note offers who-calls, not who-writes
  Chk 'A-MA2-BACKING'  (($m2.Backing | Sort-Object) -join ',') 'GetVERDICT,SetVERDICT'
  # D13 by-name counts (unbound write refs of the NAME). RE-BASELINED at 1.19
  # (engine D13 fixed, 21,916 of 32,909 CLIENT write refs now bound):
  #   VERDICT 0/2 -> 0/0: both "elsewhere" writes (uINSPRSLT.PAS:2138, :2685) are
  #     now bound to uINSPRSLT.TmcINSPRSLT.VERDICT -- a DIFFERENT symbol, exactly
  #     the "may be other symbols" the disclosure warned of. Now silent.
  #   R 0/35 -> 0/1: 34 now bound -- 26 locals, 4 params, 4 fields, NONE to
  #     RChartSampleData.R; the one left is `R:= ClipRect` at uStyles.pas:452,
  #     inside `with img do with img.Canvas do` (1.19 binds with-body READS, D14).
  # Neither member has a write bound to ITSELF, so BoundUnreported is 0 on both.
  Chk 'A-MA2-D13'      "$($m2.D13SameFile)/$($m2.D13Elsewhere)/$($m2.BoundUnreported)" '0/0/0'
  if ((Dot $m2) -match 'engine D13') { Fail 'A-MA2-D13' 'the D13 disclosure still fires on VERDICT, where every write it named is now bound elsewhere' }
  # a missing precondition FAILS (final wave, item 9): `if ($m1) { ... }` used to
  # skip this row silently whenever E-MA1 had thrown, and the run still passed
  if (-not $m1) { Fail 'A-MA1-D13' 'precondition: E-MA1 produced no result, so the D13 count of R was never checked' }
  else { Chk 'A-MA1-D13' "$($m1.D13SameFile)/$($m1.D13Elsewhere)/$($m1.BoundUnreported)" '0/1/0' }
}

# ENGINE D13: up to 1.18 write refs were never bound on CLIENT, so the verb saw
# only member-access writes. FConnected is assigned bare inside its own class
# four times; the chart said "no RESOLVED write sites" and listed the four
# unbound lines by name.
# RE-BASELINED at 1.19 (D13 fixed): the four are now BOUND to FConnected, so the
# by-name check is silent (4/0 -> 0/0) -- but find-callers still reports none of
# them (no bound write ref has a member_accesses row: 0 of 21,916), and the chart
# said "no write sites (602 reads)", a FALSE absence. Emit-MemberAccess now
# counts writes BOUND to the member that the verb does not report, and says so.
Note 'who-writes FConnected (bound writes the verb does not report) ...'
Step 'E-MA-D13' {
  $script:m14 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'uPipeClientConnection.TPipeClientConnection.FConnected' -Mode write -DbPath $DbCli -OutDir $OutDir
  Chk 'A-MA14-WRITES' $m14.Writes 0
  Chk 'A-MA14-D13'    "$($m14.D13SameFile)/$($m14.D13Elsewhere)" '0/0'
  Chk 'A-MA14-BOUND'  "$($m14.BoundUnreported) $($m14.BoundLines)" '4 :164,:320,:455,:543'
  $t14 = Dot $m14
  # FIX ROUND 1 (R26): the zero note names the verb's count for what it is and adds
  # both directions' unreported populations -- never "no write sites" / "0 writes".
  # FConnected also has 3 UNBOUND bare reads in its own unit (the read-side twin).
  Chk 'A-MA14-READS' "$($m14.ReadsBound)/$($m14.ReadsSameFile)/$($m14.ReadsElsewhere)" '0/3/0'
  if ($t14 -notmatch [regex]::Escape('0 member-access write(s) reported by find-callers + 4 bound write(s) find-callers does not report (602 member-access read(s) reported by find-callers + 3 unbound read(s) named FConnected in uPipeClientConnection.pas)')) {
    Fail 'A-MA14-ZERO' 'the zero note does not say it is only what find-callers REPORTS, with both populations' }
  if ($t14 -match 'no write sites') { Fail 'A-MA14-ZERO' 'a "no write sites" claim sits beside 4 bound writes (R26)' }
  if ($t14 -notmatch '4 bare write\(s\) BOUND to FConnected in the index at :164, :320, :455, :543 -- find-callers does not report them') { Fail 'A-MA14-LINES' 'the four bound write lines are not listed' }
  if ($t14 -match 'engine D13') { Fail 'A-MA14-SILENT' 'the by-name D13 disclosure still fires on FConnected, whose writes are all bound now' }
}

# The by-name D13 path on REAL data after the fix (R25): 1.19 still leaves a
# field written inside a `with` body unbound. uPLANLIST.PAS:2547
# `fLOTSIZE := StrToIntA(...)` sits in `with Z14slctFrm do` (TANSIZ14Plan.EditForm).
# The same chart carries 5 in-class writes BOUND to fLOTSIZE -- both disclosures at once.
Note 'who-writes fLOTSIZE (engine D13 residue: a write in a with body) ...'
Step 'E-MA-D13B' {
  $script:m15 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'uPLANLIST.TmcPLANLIST.fLOTSIZE' -Mode write -DbPath $DbCli -OutDir $OutDir
  Chk 'A-MA15-D13'   "$($m15.Writes)/$($m15.D13SameFile)/$($m15.D13Elsewhere)" '0/1/0'
  Chk 'A-MA15-BOUND' "$($m15.BoundUnreported) $($m15.BoundLines)" '5 :1315,:1453,:1517,:1580,:2055'
  $t15 = Dot $m15
  if ($t15 -notmatch 'engine D13: 1 UNBOUND write\(s\) named fLOTSIZE in uPLANLIST\.PAS at :2547 -- by name, NOT counted above') { Fail 'A-MA15-D13' 'the unbound with-body write is not listed by name' }
  # ... and the zero note with unbound writes and NO bound one (it said "no RESOLVED
  # write sites" before fix round 1, R26): TTabSwitchMessage.Result (7 `Result :=` lines in its own unit, by name --
  # 10,481 of the 10,993 writes 1.19 leaves unbound are `Result`)
  $script:m16 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'INSPFLDR.Messages.TTabSwitchMessage.Result' -Mode write -DbPath $DbCli -OutDir $OutDir
  Chk 'A-MA16-D13'   "$($m16.Writes)/$($m16.D13SameFile)/$($m16.D13Elsewhere)/$($m16.BoundUnreported)" '0/7/10474/0'
  Chk 'A-MA16-READS'  "$($m16.ReadsBound)/$($m16.ReadsSameFile)/$($m16.ReadsElsewhere)" '0/0/4888'
  if ((Dot $m16) -notmatch [regex]::Escape('0 member-access write(s) reported by find-callers + 7 unbound write(s) named Result in INSPFLDR.Messages.pas + 10474 unbound same-name write(s) in other files (may be other symbols) (0 member-access read(s) reported by find-callers + 4888 unbound same-name read(s) in other files (may be other symbols))')) {
    Fail 'A-MA16-ZERO' 'the zero note does not name what find-callers reports beside the unbound populations' }
}

# FIX ROUND 1 (ruling R26): nothing may claim zero writes -- or zero reads --
# while the index holds bound or unbound ones. Blueprint4.TfrmBlueprint4.FNoRecursion
# is the shape 1,073 CLIENT fields share: 48 bare writes BOUND (none reported by
# find-callers) and 9 UNBOUND bare reads in its own unit, 0 of either reported.
# The first cut printed "48 bare write(s) BOUND" and right under it "no read
# sites (0 writes)"; -Mode read printed "(0 writes)" with no disclosure at all.
Note 'who-writes/who-reads FNoRecursion (R26: bound writes, unbound reads, 0 reported) ...'
Step 'E-MA-R26' {
  $script:mfb = & "$SRC\Emit-MemberAccess.ps1" -Qname 'Blueprint4.TfrmBlueprint4.FNoRecursion' -Mode both -DbPath $DbCli -OutDir $OutDir
  $script:mfr = & "$SRC\Emit-MemberAccess.ps1" -Qname 'Blueprint4.TfrmBlueprint4.FNoRecursion' -Mode read -DbPath $DbCli -OutDir (Join-Path $OutDir 'r26')
  foreach ($p in @(@('A-MA-R26-BOTH', $mfb), @('A-MA-R26-READ', $mfr))) {
    Chk $p[0] "$($p[1].Writes)/$($p[1].Reads) w=$($p[1].BoundUnreported)/$($p[1].D13SameFile)/$($p[1].D13Elsewhere) r=$($p[1].ReadsBound)/$($p[1].ReadsSameFile)/$($p[1].ReadsElsewhere)" '0/0 w=48/0/0 r=0/9/0'
  }
  $wPh = '0 member-access write(s) reported by find-callers + 48 bound write(s) find-callers does not report'
  $rPh = '0 member-access read(s) reported by find-callers + 9 unbound read(s) named FNoRecursion in Blueprint4.pas'
  $tb = Dot $mfb; $tr = Dot $mfr
  if ($tb -notmatch [regex]::Escape("$wPh ($rPh)")) { Fail 'A-MA-R26-BOTH' 'the write-side zero note does not carry both populations' }
  if ($tb -notmatch [regex]::Escape("$rPh ($wPh)")) { Fail 'A-MA-R26-BOTH' 'the read-side zero note does not carry both populations' }
  if ($tb -notmatch 'engine: 9 UNBOUND read\(s\) named FNoRecursion in Blueprint4\.pas at :1950, :2084, :2113, :2138, :2163, :2179, :2238, :3142, :3546 -- by name') { Fail 'A-MA-R26-BOTH' 'the 9 unbound reads are not listed' }
  if ($tr -notmatch [regex]::Escape("$rPh ($wPh)")) { Fail 'A-MA-R26-READ' 'who-reads prints the write count without its bound population' }
  if ($tr -match 'BOUND to FNoRecursion') { Fail 'A-MA-R26-READ' 'who-reads draws the write lines it does not render' }
  # the bundle HEADER (New-DiagramArtifact): who-writes FConnected must not read
  # "0 write sites / 0 routines" beside 4 listed bound writes
  $art = & "$SRC\New-DiagramArtifact.ps1" -Question who-writes -Target 'uPipeClientConnection.TPipeClientConnection.FConnected' -DbPath $DbCli -OutRoot (Join-Path $OutDir 'bundle-r26')
  $meta = Get-Content (Join-Path $art.Bundle 'meta.json') -Raw | ConvertFrom-Json
  Chk 'A-MA-R26-HDR' "$($meta.leftCount) $($meta.leftLabel) / $($meta.rightCount) $($meta.rightLabel)" '0 member-access write sites reported by find-callers + 4 bound write(s) find-callers does not report / 0 routines reported by find-callers'
  $script:r26html = [IO.File]::ReadAllText((Join-Path $art.Bundle 'index.html'))
  # a real bundle says it is not a test chart (fix round 2: meta.testChart)
  Chk 'A-MA-R26-META' $meta.testChart 'False'
  if ($r26html -notmatch [regex]::Escape('<span><b>0</b> member-access write sites reported by find-callers + 4 bound write(s) find-callers does not report</span>')) { Fail 'A-MA-R26-HDR' 'the rendered bundle header does not name the bound writes' }
}

Note 'who-reads Connected at scale (602 sites, 598 routines, cap 25) ...'
Step 'E-MA3' {
  $script:m3 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'uPipeClientConnection.TPipeClientConnection.Connected' -Mode read -Cap 25 -DbPath $DbCli -OutDir $OutDir
  Chk 'A-MA3-READS'    $m3.Reads 602          # the VERB is uncapped; sql truncates at 200
  Chk 'A-MA3-ROUTINES' $m3.Routines 598
  Chk 'A-MA3-SHOWN'    $m3.ShownReaders 25
  Chk 'A-MA3-HIDDEN'   $m3.HiddenRoutines 573
  Chk 'A-MA3-UNANCH'   $m3.Unanchored 0
  Chk 'A-MA3-XCHECK'   $m3.CrossCheck 'agree'
  Chk 'A-MA3-BACKING'  ($m3.Backing -join ',') 'FConnected'
  # nothing is dropped silently: the disclosure row must be in the picture
  if ((Dot $m3) -notmatch '\+573 more routines') { Fail 'A-MA3-DISCLOSE' 'the disclosure row is missing' }
}

# The backing-field regression. The verb attributes these 602 reads to
# FConnected; member_accesses records them against Connected with FConnected as
# the ACCESSOR. Matching the site query on the member alone left every row
# unanchored, so Unanchored 0 here is what guards the accessor OR-clause.
Note 'who-reads FConnected (the backing field itself) ...'
Step 'E-MA4' {
  $script:m4 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'uPipeClientConnection.TPipeClientConnection.FConnected' -Mode read -Cap 5 -DbPath $DbCli -OutDir $OutDir
  Chk 'A-MA4-KIND'   $m4.Kind 'field'
  Chk 'A-MA4-READS'  $m4.Reads 602
  Chk 'A-MA4-UNANCH' $m4.Unanchored 0
  Chk 'A-MA4-XCHECK' $m4.CrossCheck 'agree'
}

Note 'hierarchy TBlueprint_ViewModel (RTL parent is unresolved, not missing) ...'
Step 'E-HI1' {
  $script:h1 = & "$SRC\Emit-Hierarchy.ps1" -Type 'TBlueprint_ViewModel' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-HI1-DECLARED'  $h1.FocusDeclared $true
  Chk 'A-HI1-ANCESTORS' $h1.Ancestors 2
  Chk 'A-HI1-UNRES'     $h1.UnresolvedAnc 1      # TInterfacedObject: RTL, real, not drawable
  Chk 'A-HI1-DESC'      $h1.Descendants 0
  Chk 'A-HI1-SELFREF'   $h1.SelfRefs 0
  # the unresolved parent is NAMED and NOT linked -- a dead link is worse than none
  $t = Dot $h1
  if ($t -notmatch 'TInterfacedObject') { Fail 'A-HI1-RTL' 'the RTL ancestor is not named at all' }
  if ($t -notmatch "outside this project") { Fail 'A-HI1-DISCLOSE' 'the unresolved ancestor is not disclosed as outside the closure' }
}

# The focus is RTL, so this index does not declare it -- and that is NOT a
# refusal: 145 types here inherit from it. Guards the -AllowMissing path.
Note 'hierarchy TInterfacedObject (145 descendants, focus not declared here) ...'
Step 'E-HI2' {
  $script:h2 = & "$SRC\Emit-Hierarchy.ps1" -Type 'TInterfacedObject' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-HI2-DECLARED' $h2.FocusDeclared $false
  Chk 'A-HI2-DESC'     $h2.Descendants 145
  Chk 'A-HI2-SHOWN'    $h2.ShownDescendants 20
  Chk 'A-HI2-HIDDEN'   $h2.HiddenDescendants 125
  Chk 'A-HI2-CLICKS'   $h2.ClickTargets 20      # no focus anchor: nothing to open
  $t = Dot $h2
  foreach ($n in 'TBlueprint_ViewModel','TBlueprintCADImport_ViewModel','TBlueprintPDFImport_ViewModel','TABZLoggingSys','TCADFileService') {
    if ($t -notmatch ('>' + [regex]::Escape($n) + '<')) { Fail 'A-HI2-NAMED' "$n is not a row" }
  }
  if ($t -notmatch '\+125 more descendants not shown') { Fail 'A-HI2-DISCLOSE' 'the disclosure row is missing' }
}

# A colliding ancestor name must be drawn UN-ANCHORED and counted, never linked
# to an arbitrary one of the candidates. IDataService is two real types here
# (generic and non-generic), each with a forward declaration -- FOUR rows, TWO
# types -- so Collisions 1 also guards the forward-declaration collapse.
Note 'hierarchy TDataService_DRA1_CLIENT (ancestor name collides) ...'
Step 'E-HI3' {
  $script:h3 = & "$SRC\Emit-Hierarchy.ps1" -Type 'TDataService_DRA1_CLIENT' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-HI3-COLLISIONS' $h3.Collisions 1
  Chk 'A-HI3-UNLOCATE'   $h3.Unlocatable 0
  $t = Dot $h3
  if ($t -notmatch '2 types share this name') { Fail 'A-HI3-TEXT' 'the collision is not stated as 2 types (forward decls not collapsed?)' }
}

Note 'class-surface TBlueprint_ViewModel (392 members, clustered by visibility) ...'
Step 'E-CS1' {
  $script:cs1 = & "$SRC\Emit-ClassSurface.ps1" -Type 'Blueprint4.ViewModel.TBlueprint_ViewModel' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-CS1-MEMBERS'  $cs1.Members 392
  Chk 'A-CS1-FIELD'    $cs1.ByKind['field'] 174
  Chk 'A-CS1-PROP'     $cs1.ByKind['property'] 115
  Chk 'A-CS1-METHOD'   $cs1.ByKind['method'] 101
  Chk 'A-CS1-CTOR'     $cs1.ByKind['constructor'] 1
  Chk 'A-CS1-DTOR'     $cs1.ByKind['destructor'] 1
  # nothing dropped silently: the totals come from an AGGREGATE the 200-row cap
  # cannot distort, and every member is either shown or disclosed
  Chk 'A-CS1-ACCOUNT'  ($cs1.Shown + $cs1.Hidden) 392
  # visibility is real, measured -- not a kind fallback
  Chk 'A-CS1-VIS'      (($cs1.ByVisibility.Keys | Sort-Object) -join ',') 'public,strict private'
  Chk 'A-CS1-PUBLIC'   $cs1.ByVisibility['public'] 191
  Chk 'A-CS1-PRIVATE'  $cs1.ByVisibility['strict private'] 201
  if (-not $cs1.AllClickable) { Fail 'A-CS1-CLICK' 'not every shown member row is anchored' }
  # the $PAL/$pal case-insensitivity trap: an empty colour kills dot's rendering
  if ((Dot $cs1) -match 'color=""') { Fail 'A-CS1-COLOR' 'an empty colour reached the dot file' }
}

Note 'touches-tables HandleCopyOperation (SERVER) ...'
Step 'E-TT1' {
  $script:s1 = & "$SRC\Emit-TouchesTables.ps1" -Qname $Q_COPY -DbPath $DbSrv -OutDir $OutDir
  Chk 'A-TT1-READS'      $s1.Reads 5
  Chk 'A-TT1-WRITES'     $s1.Writes 5
  Chk 'A-TT1-BOTH'       $s1.Both 2
  Chk 'A-TT1-DISTINCT'   $s1.Distinct 8
  Chk 'A-TT1-UNRESOLVED' $s1.Unresolved 0
  # 250, was 157 at 1.18: engine D18 (SQL assembled across SQL.Add lines) gave
  # sql_reads to 93 routines that had no SQL fact at all -- every one a
  # TDataService_<T>_SERVER.PrepareLoadQuery. No existing fact changed.
  Chk 'A-TT1-INDEXSQL'   $s1.IndexSqlSymbols 250
  Chk 'A-TT1-EXP'        $s1.Expected 11
  $ts = Dot $s1
  foreach ($ln in 1654, 1681, 1381) {                    # DRA1, TOOLFLDR, the focus
    if (-not (HasLine $ts $ln)) { Fail 'A-TT1-HREF' "uPipeSessionBuilder.pas:$ln is not anchored" }
  }
}

Note 'touches-tables HandleTableLoad (zero is a real answer) ...'
Step 'E-TT2' {
  $script:s2 = & "$SRC\Emit-TouchesTables.ps1" -Qname $Q_LOAD -DbPath $DbSrv -OutDir $OutDir
  Chk 'A-TT2-READS'  $s2.Reads 0
  Chk 'A-TT2-WRITES' $s2.Writes 0
  if (-not (Test-Path $s2.Svg)) { Fail 'A-TT2-SVG' 'the zero case must still produce an .svg' }
}

# ---- 3. negatives: right message AND no .svg ---------------------------------
$negDir = Join-Path $OutDir 'neg'
New-Item -ItemType Directory -Force $negDir | Out-Null

function NegTest([string] $code, [string] $phrase, [string] $slug, [scriptblock] $body) {
  $threw = $false
  try { & $body | Out-Null } catch { $threw = $true; $m = $_.Exception.Message }
  if (-not $threw) { Fail $code 'did not throw'; return }
  if ($m -notlike "*$phrase*") { Fail $code "message did not contain '$phrase' -- got: $m" }
  $svg = Join-Path $negDir "$slug.svg"
  if (Test-Path $svg) { Fail $code "left an .svg behind ($slug.svg)" }
}

Note 'negatives N1-N6 ...'
NegTest 'N1' 'engine returned nothing for' 'No_Such_Method' {
  & "$SRC\Emit-WhoCalls.ps1" -Qname 'No.Such.Method' -DbPath $DbCli -OutDir $negDir }
NegTest 'N2' 'ask event-wiring instead' 'uMain_TfrmMAIN_FormCreate' {
  & "$SRC\Emit-WhoCalls.ps1" -Qname 'uMain.TfrmMAIN.FormCreate' -DbPath $DbCli -Depth 2 -OutDir $negDir }
NegTest 'N3' 'control NoSuchControl has no dfm_event rows on uMain.TfrmMAIN (the form has 43)' 'uMain_TfrmMAIN_NoSuchControl' {
  & "$SRC\Emit-EventWiring.ps1" -Form 'uMain.TfrmMAIN' -Control 'NoSuchControl' -DbPath $DbCli -OutDir $negDir }
NegTest 'N4' 'is this a form class?' 'Blueprint4_ViewModel_TBlueprint_ViewModel' {
  & "$SRC\Emit-EventWiring.ps1" -Form 'Blueprint4.ViewModel.TBlueprint_ViewModel' -DbPath $DbCli -OutDir $negDir }
NegTest 'N5' 'this project has no FireDAC connection' 'Blueprint4_ViewModel_TBlueprint_ViewModel_SendDeltaOperation' {
  & "$SRC\Emit-TouchesTables.ps1" -Qname $Q_SEND -DbPath $DbCli -OutDir $negDir }
NegTest 'N6' 'No.Such.Method is not in this index' 'No_Such_Method' {
  & "$SRC\Emit-TouchesTables.ps1" -Qname 'No.Such.Method' -DbPath $DbSrv -OutDir $negDir }

# N8: a leaf must say "calls nothing". The event-wiring hint would be nonsense
# pointed downward -- a DFM is never a callee -- so the message is asserted to
# NOT mention it, not merely to mention the right thing.
Note 'negative N8 (leaf calls nothing) ...'
$Q_LEAF = 'AssignGroups.ViewModel.TAssignGroupsViewModel.CanAddGroup'
NegTest 'N8' 'calls nothing in call_edges' 'AssignGroups_ViewModel_TAssignGroupsViewModel_CanAddGroup_callees' {
  & "$SRC\Emit-WhoCalls.ps1" -Qname $Q_LEAF -DbPath $DbCli -Direction callees -OutDir $negDir }
$n8msg = ''
try { & "$SRC\Emit-WhoCalls.ps1" -Qname $Q_LEAF -DbPath $DbCli -Direction callees -OutDir $negDir | Out-Null }
catch { $n8msg = $_.Exception.Message }
if ($n8msg -match 'event-wiring') { Fail 'N8-HINT' "the callee refusal offered the event-wiring hint: $n8msg" }

Note 'negatives N9-N10 + ambiguity ...'
NegTest 'N9' 'is a method, not a field or property -- ask who-calls instead' 'Blueprint4_ViewModel_TBlueprint_ViewModel_SendDeltaOperation_both' {
  & "$SRC\Emit-MemberAccess.ps1" -Qname $Q_SEND -DbPath $DbCli -OutDir $negDir }
NegTest 'N10' 'No.Such.Field is not in this index' 'No_Such_Field_both' {
  & "$SRC\Emit-MemberAccess.ps1" -Qname 'No.Such.Field' -DbPath $DbCli -OutDir $negDir }
# Refusing an ambiguous BARE name is the whole reason Resolve-MemberSelection
# exists: 40% of bare field/property names on this index match more than one
# symbol, and picking the wrong one mislabels every row in the picture rather
# than just one. Kind-filtered, so the 150 properties named ID are what counts.
NegTest 'N10b' 'ID is ambiguous -- 154 symbols share that name' 'ID_both' {
  & "$SRC\Emit-MemberAccess.ps1" -Qname 'ID' -DbPath $DbCli -OutDir $negDir }

Note 'negatives N11-N12 ...'
NegTest 'N11' 'NoSuchType is not in this index, and nothing in it inherits' 'NoSuchType_hierarchy' {
  & "$SRC\Emit-Hierarchy.ps1" -Type 'NoSuchType' -DbPath $DbCli -OutDir $negDir }
NegTest 'N12' 'is a unit, not a class or interface or record' 'Blueprint4_ViewModel_surface' {
  & "$SRC\Emit-ClassSurface.ps1" -Type 'Blueprint4.ViewModel' -DbPath $DbCli -OutDir $negDir }
# A bare type name matching two REAL types is refused, and the message must name
# what separates them: they share a qualified name, so "qualify it" is useless.
NegTest 'N12b' 'they differ by generic parameters' 'IDataService_hierarchy' {
  & "$SRC\Emit-Hierarchy.ps1" -Type 'IDataService' -DbPath $DbCli -OutDir $negDir }

# N13 is NOT a refusal: zero in the rendered direction is a real answer, and it
# must still draw and exit 0 -- with the OTHER direction's count beside it, so
# "0 writes" cannot read as "nothing uses this".
Note 'N13 (zero writes is an answer, not a failure) ...'
Step 'N13' {
  $script:m13 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'uPipeClientConnection.TPipeClientConnection.Connected' -Mode write -DbPath $DbCli -OutDir (Join-Path $OutDir 'zero')
  Chk 'A-N13-WRITES' $m13.Writes 0
  Chk 'A-N13-READS'  $m13.Reads 602
  if (-not (Test-Path $m13.Svg)) { Fail 'A-N13-SVG' 'the zero case must still produce an .svg' }
  $t13 = Dot $m13
  if ($t13 -notmatch 'no write sites \(602 reads\)') { Fail 'A-N13-NOTE' 'the zero note does not carry the read count' }
  if ($t13 -match 'cluster_writers') { Fail 'A-N13-EMPTY' 'an empty writers cluster was drawn' }
}

# R26 SWEEP (fix round 1; hardened in fix round 2): EVERY who-writes / who-reads
# text this run rendered. A zero claim in a direction whose unreported population
# (bound + unbound) is above zero FAILS -- whichever chart, whichever mode. "10
# writes" is not "0 writes": the zero must not follow a digit or a thousands
# comma. The SAME pattern shape for both directions ("0 write(s)" and "0 read(s)"
# alike). A result object WITHOUT the two population counts FAILS rather than
# passing: on the pre-fix code `$null -gt 0` was false, so the sweep would have
# passed every chart silently -- proven below on a synthetic pre-fix object.
function Get-R26Problems([string] $Name, [string] $Text, $Counts) {
  $p = New-Object System.Collections.ArrayList
  foreach ($prop in 'WritesUnreported', 'ReadsUnreported') {
    if (-not $Counts -or -not $Counts.PSObject.Properties[$prop] -or $null -eq $Counts.$prop) {
      [void]$p.Add("${Name}: the result carries no $prop -- the sweep cannot judge it")
    }
  }
  # NO unary comma: callers wrap in @() and count, and @(, $arr) nests -- Count 1 always
  if ($p.Count) { return $p.ToArray() }
  if ([int]$Counts.WritesUnreported -gt 0 -and $Text -match '(?<![\d,])0 writes?\b|no write sites|(?<![\d,])0 write sites') {
    [void]$p.Add("${Name}: claims zero writes beside $($Counts.WritesUnreported) unreported write(s)") }
  if ([int]$Counts.ReadsUnreported -gt 0 -and $Text -match '(?<![\d,])0 reads?\b|no read sites|(?<![\d,])0 read sites') {
    [void]$p.Add("${Name}: claims zero reads beside $($Counts.ReadsUnreported) unreported read(s)") }
  $p.ToArray()
}
Note 'R26 sweep (no zero claim beside an unreported population) ...'
Step 'A-MA-R26-SWEEP' {
  $seen = 0
  foreach ($p in @(@('m1', $m1), @('m2', $m2), @('m3', $m3), @('m4', $m4), @('m13', $m13), @('m14', $m14),
                   @('m15', $m15), @('m16', $m16), @('mfb', $mfb), @('mfr', $mfr), @('r26-bundle', $r26html))) {
    $o = $p[1]
    if (-not $o) { Fail 'A-MA-R26-SWEEP' "precondition: $($p[0]) produced no result, so it was never swept"; continue }
    # the bundle html is judged with the counts of the chart it wraps (m14, FConnected)
    if ($o -is [string]) { $txt = $o; $cnt = $m14 } else { $txt = Dot $o; $cnt = $o }
    $seen++
    foreach ($msg in (Get-R26Problems $p[0] $txt $cnt)) { Fail 'A-MA-R26-SWEEP' $msg }
  }
  Chk 'A-MA-R26-SWEPT' $seen 11
  # THE SWEEP ITSELF MUST BE ABLE TO FAIL (fix round 2). Synthetic inputs:
  #   pre-fix  the old FNoRecursion text on an old-shape object (no counts)  -> 2 problems
  #   old      the old text with the counts present                           -> 2 (both)
  #   writes   "no write sites (602 reads)" beside 4 bound writes (FConnected) -> 1
  #   reads    "(0 read(s))" beside unreported reads (the old regex missed it) -> 1 (reads)
  #   clean    the fixed text                                                 -> 0
  $old   = '48 bare write(s) BOUND to FNoRecursion ... no read sites (0 writes)'
  $preFx = [pscustomobject]@{ Writes = 0; Reads = 0; BoundUnreported = 48 }
  $cnts  = [pscustomobject]@{ WritesUnreported = 48; ReadsUnreported = 9 }
  $syn = "$(@(Get-R26Problems 'pre' $old $preFx).Count)/$(@(Get-R26Problems 'w' $old $cnts).Count)/" +
         "$(@(Get-R26Problems 'w1' 'no write sites (602 reads)' ([pscustomobject]@{ WritesUnreported = 4; ReadsUnreported = 0 })).Count)/" +
         "$(@(Get-R26Problems 'r' 'x (0 read(s))' $cnts).Count)/" +
         "$(@(Get-R26Problems 'ok' '0 member-access write(s) reported by find-callers + 48 bound write(s) find-callers does not report (0 member-access read(s) reported by find-callers + 9 unbound read(s) named FNoRecursion in Blueprint4.pas)' $cnts).Count)"
  Chk 'A-MA-R26-SWEEP-CANFAIL' $syn '2/2/1/1/0'
}
# N7 is the BUNDLER's contract, not an emitter's: the refusal must propagate AND
# leave no directory for someone to find later and mistake for an answer.
Note 'negative N7 (bundle cleanup) ...'
$n7Root = Join-Path $OutDir 'bundle'
$n7Dir  = Join-Path $n7Root ('touches-tables-' + ($Q_SEND -replace '[^A-Za-z0-9]', '_'))
$threw = $false
try {
  & "$SRC\New-DiagramArtifact.ps1" -Question touches-tables -Target $Q_SEND -DbPath $DbCli -OutRoot $n7Root | Out-Null
} catch { $threw = $true; $m7 = $_.Exception.Message }
if (-not $threw) { Fail 'N7' 'did not throw' }
elseif ($m7 -notlike '*no FireDAC connection*') { Fail 'N7' "wrong message: $m7" }
if (Test-Path $n7Dir) { Fail 'N7-DIR' 'the failed bundle directory still exists' }

# ---- the second batch: lifecycle / cycles / wiring / effects / architecture ----
# Same rule as above: every number was MEASURED on 2026-09-23 against the clones
# and is asserted, not recomputed.

Note 'lifecycle ...'
Step 'E-LC' {
  # uMain wires OnCreate + OnShow and IMPLEMENTS FormDestroy without wiring it.
  $script:lc1 = & "$SRC\Emit-Lifecycle.ps1" -Form 'uMain.TfrmMAIN' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-LC1-WIRED'    $lc1.Wired 2
  Chk 'A-LC1-NOTWIRED' $lc1.NotWired 1
  Chk 'A-LC1-ABSENT'   $lc1.Absent 4
  Chk 'A-LC1-HERITAGE' $lc1.Heritage 'TdxRibbonForm'
  $t = Dot $lc1
  # N14b: the whole point of the chart. FormDestroy exists at uMain.pas:422.
  if ($t -notmatch 'implemented, NOT wired') { Fail 'A-LC1-UNWIRED-ROW' 'the unwired stage is not labelled' }
  if (-not (HasLine $t 422)) { Fail 'A-LC1-ANCHOR' 'FormDestroy is not anchored to its body at 422' }
  if (-not $lc1.AllClickable) { Fail 'A-LC1-CLICK' 'lifecycle rows are not all anchored' }

  $script:lc2 = & "$SRC\Emit-Lifecycle.ps1" -Form 'varnames.TfrmVarNames' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-LC2-WIRED' $lc2.Wired 3
  Chk 'A-LC2-NOTWIRED' $lc2.NotWired 0

  # U2: a REAL form that wires nothing still renders. "Not a form" and "a form
  # with nothing wired" are different answers and must not collapse together.
  $script:lc3 = & "$SRC\Emit-Lifecycle.ps1" -Form 'WarningFlags.TfrmWarningFlags' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-LC3-WIRED'  $lc3.Wired 0
  Chk 'A-LC3-ABSENT' $lc3.Absent 7
  if (-not (Test-Path $lc3.Svg)) { Fail 'A-LC3-SVG' 'a form with zero wired events must still render' }
}

Note 'cycles ...'
Step 'E-CY' {
  $script:cy1 = & "$SRC\Emit-Cycles.ps1" -DbPath $DbCli -OutDir $OutDir
  Chk 'A-CY1-GROUPS'   $cy1.Cycles 2
  Chk 'A-CY1-EDGES'    $cy1.Edges 5
  Chk 'A-CY1-ANCHORED' $cy1.Anchored 5
  Chk 'A-CY1-UNANCH'   $cy1.Unanchored 0
  $t = Dot $cy1
  # P4: names come back lowercased; anchoring is case-insensitive or nothing clicks.
  if ($t -notmatch 'Blueprint4\.ViewModel') { Fail 'A-CY1-CASE' 'unit names did not resolve to their real casing' }
  # The array order would have drawn blueprint4 -> controlplan2, which does not exist.
  if ($t -match 'Blueprint4</FONT>[^<]*</TD></TR>[^!]*uses controlplan2') { Fail 'A-CY1-FAKE-EDGE' 'drew the array-order edge' }

  # DL is a strongly-connected component with NO Hamiltonian ring: loops sharing
  # `regions`, every edge must still be drawn. 7 edges / 5 members, was 5 / 4 at
  # 1.18: the DL clone re-indexes the engine's own source, and 1.19 added the unit
  # DRagLint.Doc.ProjectTags, which joins the SCC -- ProjectTags uses Regions
  # (:267) and SharedFacts uses ProjectTags (:431). A SOURCE change, diffed
  # against the pre-1.19 clone; the other 5 are the 1.18 edges (2 at new lines).
  $script:cy2 = & "$SRC\Emit-Cycles.ps1" -DbPath $DbDl -OutDir $OutDir
  Chk 'A-CY2-GROUPS' $cy2.Cycles 1
  Chk 'A-CY2-EDGES'  $cy2.Edges 7
  Chk 'A-CY2-GAPS'   $cy2.Unwalkable 0

  # N18: no cycles is an ANSWER -- it renders and exits 0.
  $script:cy3 = & "$SRC\Emit-Cycles.ps1" -DbPath $DbDc -OutDir $OutDir
  Chk 'A-CY3-GROUPS' $cy3.Cycles 0
  if (-not (Test-Path $cy3.Svg)) { Fail 'A-CY3-SVG' 'the acyclic case must still produce an .svg' }
  if ((Dot $cy3) -notmatch 'no cycles') { Fail 'A-CY3-NOTE' 'the acyclic case does not say so' }
}

Note 'wiring ...'
Step 'E-WI' {
  $script:wi1 = & "$SRC\Emit-Wiring.ps1" -Interface 'IABZLoggingSys' -DbPath $DbSrv -OutDir $OutDir
  Chk 'A-WI1-REGS'      $wi1.Registrations 2
  Chk 'A-WI1-RESOLVED'  $wi1.ResolvedAt 4
  Chk 'A-WI1-LIFETIME'  $wi1.Lifetimes 'singleton'
  Chk 'A-WI1-IDXREGS'   $wi1.IndexRegs 535
  $t = Dot $wi1
  foreach ($ln in @(425, 429, 194, 227)) {
    if (-not (HasLine $t $ln)) { Fail "A-WI1-L$ln" "registration/resolution line $ln is not anchored" }
  }

  # N16: zero registrations is an ANSWER, and it is only readable next to the
  # index-wide total -- so the total must be on the chart.
  $script:wi2 = & "$SRC\Emit-Wiring.ps1" -Interface 'IMicObject' -DbPath $DbSrv -OutDir $OutDir
  Chk 'A-WI2-REGS' $wi2.Registrations 0
  if (-not (Test-Path $wi2.Svg)) { Fail 'A-WI2-SVG' 'the unregistered case must still render' }
  if ((Dot $wi2) -notmatch 'index-wide: 535 registration') { Fail 'A-WI2-DISCLOSE' 'the index-wide total is missing' }

  # P7: the SAME interface on CLIENT, where the whole index holds 4 registrations.
  # P7b: state the number, never the cause.
  $script:wi3 = & "$SRC\Emit-Wiring.ps1" -Interface 'IABZLoggingSys' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-WI3-REGS'    $wi3.Registrations 1
  Chk 'A-WI3-IDXREGS' $wi3.IndexRegs 4
  $t3 = Dot $wi3
  if ($t3 -notmatch 'index-wide: 4 registration') { Fail 'A-WI3-DISCLOSE' 'CLIENT does not disclose its 4-registration total' }
  if ($t3 -match '(?i)pipe') { Fail 'A-WI3-CAUSE' 'the chart asserts a CAUSE we have not evidenced (P7b)' }
}

Note 'effects ...'
Step 'E-FX' {
  # N17: NULL summary + effect_free=1 is PURE. The naive reading calls this
  # "not analysed" and is wrong for 2,918 CLIENT methods (1.19; 2,895 at 1.18).
  $script:fx1 = & "$SRC\Emit-Effects.ps1" -Qname 'uMain.TfrmMAIN.GetConnection' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-FX1-OUTCOME' $fx1.Outcome 'pure'
  Chk 'A-FX1-FREE'    $fx1.EffectFree '1'
  if ((Dot $fx1) -match 'not analysed') { Fail 'A-FX1-MISLABEL' 'a PURE method was labelled not analysed' }

  # N17b: effect_free IS NULL genuinely is "not analysed" -- only 855 on CLIENT.
  $script:fx2 = & "$SRC\Emit-Effects.ps1" -Qname 'uSetupDefaults.TGlobalSetupDefaults.GetDebug1' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-FX2-OUTCOME' $fx2.Outcome 'not-analysed'
  if ((Dot $fx2) -notmatch 'not analysed') { Fail 'A-FX2-NOTE' 'the unanalysed case does not say so' }

  $script:fx3 = & "$SRC\Emit-Effects.ps1" -Qname 'uMain.TExit.HandleException' -DbPath $DbCli -OutDir $OutDir
  # 's,?' / 1 unknown, was 's' / 0 before extractor 1.18: the whole body is under
  # {$IFDEF EUREKALOG}, now live, and calls ExceptionManager.Handle -- an external
  # routine with no effect facts, so the unknown is CORRECT, not a regression.
  Chk 'A-FX3-SUMMARY' $fx3.Summary 's,?'
  Chk 'A-FX3-EFFECTS' $fx3.Effects 1
  Chk 'A-FX3-UNKNOWN' $fx3.Unknown 1

  $script:fx4 = & "$SRC\Emit-Effects.ps1" -Qname 'uMain.TExit.Execute' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-FX4-SUMMARY' $fx4.Summary 'g,s,?'
  Chk 'A-FX4-EFFECTS' $fx4.Effects 2
  Chk 'A-FX4-UNKNOWN' $fx4.Unknown 1

  # P8: parameter ordinals are ZERO-BASED. p1 on (Sender; var Key; Shift) is Key.
  $script:fx5 = & "$SRC\Emit-Effects.ps1" -Qname 'EWrkSLCT.TfrmEwrkSlct.FormKeyUp' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-FX5-SUMMARY' $fx5.Summary 'g,p1,?'
  if ((Dot $fx5) -notmatch 'parameter #1 \(Key\)') { Fail 'A-FX5-ORDINAL' 'p1 did not resolve to the SECOND parameter' }

  # The grouped-parameter form the plan expected to be unnameable:
  # ( V1; I11, I12; V2; I21, I22 ) -- p0 is V1 and p3 is V2, and mutates_params
  # is EMPTY here, so the name can only come from parsing the signature.
  $script:fx6 = & "$SRC\Emit-Effects.ps1" -Qname 'Ap.APVDotProduct' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-FX6-PARAMS'  $fx6.ParamCount 6
  Chk 'A-FX6-UNNAMED' $fx6.Unnamed 0
  $t6 = Dot $fx6
  if ($t6 -notmatch 'parameter #0 \(V1\)') { Fail 'A-FX6-P0' 'p0 did not resolve to V1' }
  if ($t6 -notmatch 'parameter #3 \(V2\)') { Fail 'A-FX6-P3' 'p3 did not resolve to V2 across grouped parameters' }
  # its witness is "calls Assert (unbound)", not its own name: g stays drawn
  Chk 'A-FX6-D12'     $fx6.D12Suspect $false

  # ENGINE D12: AP_FP_Greater_Eq := X >= Y was scored as a GLOBAL write (summary
  # `g`, witness "writes AP_FP_Greater_Eq (non-local)") -- one of 31 such CLIENT
  # functions on the 1.18 clone, drawn as the dashed D12 disclosure.
  # RE-BASELINED at 1.19 (D12 fixed; R25): it is now PURE (effect_free 1, empty
  # summary, no witness), and 0 functions on any clone carry an own-name witness
  # (CLIENT 31 -> 0: 20 turned pure, 11 keep a genuine effect). So the chart must
  # say pure, with NO D12 cluster and no global write.
  $script:fx7 = & "$SRC\Emit-Effects.ps1" -Qname 'Ap.AP_FP_Greater_Eq' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-FX7-D12'     "$($fx7.Outcome):$($fx7.D12Suspect)" 'pure:False'
  Chk 'A-FX7-EFFECTS' $fx7.Effects 0
  Chk 'A-FX7-SUMMARY' $fx7.Summary ''
  $t7 = Dot $fx7
  if ($t7 -match 'writes global state') { Fail 'A-FX7-NOG' 'a global write is drawn on a routine the engine now scores pure' }
  if ($t7 -match 'engine D12')          { Fail 'A-FX7-NOTE' 'the D12 disclosure still fires where its premise is gone' }
  # ... and the detector itself stays covered on SYNTHETIC rows (R25): no real
  # row reaches it any more. Own-name witness + g -> suspect; another name, a
  # missing g, or no witness -> not.
  $script:fx12 = & {
    . "$SRC\Emit-Common.ps1"
    $g = @([pscustomobject]@{ Kind = 'g' }, [pscustomobject]@{ Kind = '?' })
    $s = @([pscustomobject]@{ Kind = 's' })
    "$(Test-D12OwnNameWrite 'F' 'writes F (non-local)' $g)/$(Test-D12OwnNameWrite 'F' 'WRITES f (NON-LOCAL)' $g)/" +
    "$(Test-D12OwnNameWrite 'F' 'writes G (non-local)' $g)/$(Test-D12OwnNameWrite 'F' 'writes F (non-local)' $s)/" +
    "$(Test-D12OwnNameWrite 'F' '' $g)"
  }
  Chk 'A-FX12-DETECT' $fx12 'True/True/False/False/False'
  # ... and WIRED (fix round 1): the function passing is not enough -- if
  # Emit-Effects stopped calling it, nothing above would fail. The 1.18 facts of
  # AP_FP_Greater_Eq are injected through the emitter's -FactOverride test hook
  # and the D12 render must come back: dashed disclosure, no global write, and
  # the TEST CHART row that stops such a chart passing for an index answer.
  $script:fx13 = & "$SRC\Emit-Effects.ps1" -Qname 'Ap.AP_FP_Greater_Eq' -DbPath $DbCli -OutDir (Join-Path $OutDir 'fx-d12') `
                   -FactOverride @{ ef = 0; es = 'g'; ew = 'writes AP_FP_Greater_Eq (non-local)' }
  Chk 'A-FX13-WIRED'  "$($fx13.Outcome):$($fx13.D12Suspect):$($fx13.Effects):$($fx13.Summary)" 'effects:True:0:g'
  # stamped in the RESULT, not only drawn (fix round 2); a real chart is not
  Chk 'A-FX13-STAMP'  "$($fx13.TestChart)/$($fx7.TestChart)" 'True/False'
  $t13fx = Dot $fx13
  if ($t13fx -notmatch 'cluster_d12_\d+ \{\s*style="rounded,filled,dashed"') { Fail 'A-FX13-WIRED' 'the injected D12 case does not draw the dashed D12 cluster' }
  if ($t13fx -match 'writes global state') { Fail 'A-FX13-WIRED' 'the injected own-name g was drawn as a global write' }
  if ($t13fx -notmatch 'TEST CHART: the effect facts below were INJECTED') { Fail 'A-FX13-WIRED' 'an injected-fact chart does not say so' }
}

Note 'architecture ...'
Step 'E-AR' {
  $script:ar1 = & "$SRC\Emit-Architecture.ps1" -DbPath $DbCli -OutDir $OutDir
  # Extractor 1.18 (2026-09-23) fixed the define profile, so the .dpr's
  # {$IFDEF EurekaLog} uses block is live: +1 internal edge (EExtraExceptionInfo),
  # +10 external units (EAppVCL, EDebugExports, EDebugMap, EDialogWinAPISteps-
  # ToReproduce, EFixSafeCallException, EMapWin32, EMemLeaks, EResLeaks,
  # EResourceStrings, ExceptionLog7). EXTEDGES is deps-report's own count: +14
  # against +12 raw unresolved unit_uses rows -- the 2 extra are its attribution
  # of ETypes/EEvents/ECompatibility, asked about in the engine INBOX.
  Chk 'A-AR1-UNITS'    $ar1.Units 563
  Chk 'A-AR1-ZONES'    $ar1.Zones 3
  Chk 'A-AR1-INTERNAL' $ar1.InternalEdges 2859
  Chk 'A-AR1-EXTUNITS' $ar1.ExternalUnits 293
  Chk 'A-AR1-EXTEDGES' $ar1.ExternalEdges 30716
  Chk 'A-AR1-GROUPS'   $ar1.Groups 5
  Chk 'A-AR1-BACK'     $ar1.BackEdges 3
  # The red-team's classifier gap: bare `spring` lands in `unknown`.
  Chk 'A-AR1-GAPS'     $ar1.ClassifierGaps 1
  if (-not $ar1.AllClickable) { Fail 'A-AR1-CLICK' 'architecture rows are not all anchored' }

  # A single-folder project has no internal zones, and must SAY so rather than
  # manufacture layers.
  $script:ar2 = & "$SRC\Emit-Architecture.ps1" -DbPath $DbDc -OutDir $OutDir
  Chk 'A-AR2-ZONES' $ar2.Zones 1
  Chk 'A-AR2-CROSS' $ar2.CrossZone 0
  if ((Dot $ar2) -notmatch 'every unit in one folder') { Fail 'A-AR2-NOTE' 'the single-zone case does not disclose itself' }
}

Note 'negatives N14-N19 ...'
# U2: refusing must be a HERITAGE decision. A real form that wires nothing also
# has zero dfm_event rows, and A-LC3 above proves it still renders.
NegTest 'N14' 'is not a form: its heritage is TInterfacedObject' 'lifecycle_Blueprint4_ViewModel_TBlueprint_ViewModel' {
  & "$SRC\Emit-Lifecycle.ps1" -Form 'Blueprint4.ViewModel.TBlueprint_ViewModel' -DbPath $DbCli -OutDir $negDir }
# N15: the verb returns the same empty document for a class as for an
# unregistered interface, so the emitter must name the KIND itself.
NegTest 'N15' 'is a class, not a interface' 'wiring_TABZLoggingSys' {
  & "$SRC\Emit-Wiring.ps1" -Interface 'TABZLoggingSys' -DbPath $DbSrv -OutDir $negDir }
NegTest 'N18b' 'is in no cycle in this index' 'cycles_uMain' {
  & "$SRC\Emit-Cycles.ps1" -Unit 'uMain' -DbPath $DbCli -OutDir $negDir }

# N19: no emitter may be pointed at a live corpus DB by habit.
# A MISSING precondition FAILS (Task 0 review, 2026-09-23). This used to print
# "skipped" and pass, so a moved or renamed live DB would have switched the
# guard off in silence and the battery would still read green. Get-CloneDb
# checks existence BEFORE the refusal rules, so the refusal cannot be exercised
# without the file; the honest outcome when it is absent is a named failure.
$liveDb = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite'
if (Test-Path $liveDb) {
  NegTest 'N19' 'refusing a non-clone database' 'lifecycle_uMain_TfrmMAIN' {
    & "$SRC\Emit-Lifecycle.ps1" -Form 'uMain.TfrmMAIN' -DbPath $liveDb -OutDir $negDir }
} else {
  Fail 'N19-PRE' "precondition missing: $liveDb -- the live-DB refusal cannot be exercised"
}

# ---- the third batch: protocol-trace / crosses-boundary / shown-where /
#      change-impact / tested-by -------------------------------------------------

Note 'protocol-trace ...'
Step 'E-PT' {
  # These numbers were ZERO before 2026-09-23: enum-value refs were unbound.
  # They are the regression guard for the engine team's enum binding.
  $script:pt1 = & "$SRC\Emit-ProtocolTrace.ps1" -Target 'cmdDelta' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-PT1-REFS'     $pt1.Refs 38
  Chk 'A-PT1-ROUTINES' $pt1.Routines 38
  Chk 'A-PT1-KINDS'    $pt1.Kinds 'read'
  Chk 'A-PT1-UNATTR'   $pt1.Unattributed 0
  # 2 zones, not 1. The unpaged file query returned only the first 200 paths, so
  # the common root came back as ...\ORM3\CLIENT and every row collapsed into one
  # zone -- a wrong chart caused by a cap that reports nothing.
  Chk 'A-PT1-ZONES'    $pt1.Zones 2

  $script:pt2 = & "$SRC\Emit-ProtocolTrace.ps1" -Target 'Pipes.Protocol.TPipeMessageHeader.CommandID' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-PT2-MODE'     $pt2.Mode 'field'
  # 1047/728, was 1043/727. The old pair was baselined while uPipeClientConnection
  # was a WITHHELD file with no resolved refs; the 2026-09-23 CLIENT reindex bound
  # its 4 CommandID reads (all in HeaderCommandID). Recovered data, not drift.
  Chk 'A-PT2-REFS'     $pt2.Refs 1047
  Chk 'A-PT2-ROUTINES' $pt2.Routines 728
  Chk 'A-PT2-KINDS'    $pt2.Kinds 'member-access'

  $script:pt3 = & "$SRC\Emit-ProtocolTrace.ps1" -Target 'Pipes.Protocol.CommandIDToStr' -DbPath $DbSrv -OutDir $OutDir
  Chk 'A-PT3-MODE'     $pt3.Mode 'method'
  Chk 'A-PT3-COMMANDS' $pt3.Commands 42      # every TCommandID member
  # One routine reading 42 DIFFERENT constants. The row note was the FIRST ref's
  # constant times the site count -- '<first> x42' -- a claim that one command is
  # read 42 times. The note names the distinct constants, or counts them.
  $pt3dot = Dot $pt3
  Chk 'A-PT3-NOTE-NOX'   ([regex]::IsMatch($pt3dot, ' x42\b')) $false
  Chk 'A-PT3-NOTE-COUNT' $pt3dot.Contains('42 constants') $true

  # The Blueprint4 Operation grid's outbound wire routine: cmdDelta out, rspOK
  # back, ONE read each. It rendered as 'cmdDelta x2'.
  $script:pt4 = & "$SRC\Emit-ProtocolTrace.ps1" -Target $Q_SEND -DbPath $DbCli -OutDir $OutDir
  Chk 'A-PT4-COMMANDS' $pt4.Commands 2
  Chk 'A-PT4-NOTE'     (Dot $pt4).Contains('cmdDelta, rspOK') $true
}

Note 'crosses-boundary ...'
Step 'E-CB' {
  $script:cb1 = & "$SRC\Emit-CrossesBoundary.ps1" -Target 'Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation' `
                    -DbPath $DbCli -CounterpartDb $DbSrv -OutDir $OutDir
  Chk 'A-CB1-VERDICT'  $cb1.Verdict 'crosses'
  Chk 'A-CB1-COMMANDS' $cb1.Commands 2
  Chk 'A-CB1-PIPE'     $cb1.PipeCalls 1
  Chk 'A-CB1-FAR'      $cb1.FarSide 18
  Chk 'A-CB1-SELFPIPE' $cb1.SelfIsPipe $false

  # SelfIsPipe was TRUE for every method until @(Invoke-IndexQuery ...) was
  # unwrapped -- the nesting makes .Count read 1 on an EMPTY result.
  $script:cb2 = & "$SRC\Emit-CrossesBoundary.ps1" -Target 'uPipeClientConnection.TPipeClientConnection.ExecuteCommand' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-CB2-VERDICT'  $cb2.Verdict 'is the boundary'
  Chk 'A-CB2-SELFPIPE' $cb2.SelfIsPipe $true

  # The honest negative: no evidence is NOT "does not cross".
  $script:cb3 = & "$SRC\Emit-CrossesBoundary.ps1" -Target 'gammafunc.LnGamma' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-CB3-VERDICT' $cb3.Verdict 'no evidence in this index'
  if (-not (Test-Path $cb3.Svg)) { Fail 'A-CB3-SVG' 'the no-evidence case must still render' }
  if ((Dot $cb3) -notmatch 'absence is NOT proof') { Fail 'A-CB3-NOTE' 'the no-evidence case overclaims' }
}

Note 'shown-where ...'
Step 'E-SW' {
  $script:sw1 = & "$SRC\Emit-ShownWhere.ps1" -Column 'FTRNAMESTR' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-SW1-BINDINGS' $sw1.Bindings 4
  Chk 'A-SW1-FORMS'    $sw1.Forms 2
  Chk 'A-SW1-UNRES'    $sw1.Unresolved 0
  Chk 'A-SW1-IDXROWS'  $sw1.IndexRows 903
  Chk 'A-SW1-IDXCOLS'  $sw1.IndexColumns 459

  $script:sw2 = & "$SRC\Emit-ShownWhere.ps1" -Column 'ID' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-SW2-BINDINGS' $sw2.Bindings 72
  Chk 'A-SW2-FORMS'    $sw2.Forms 25
}

Note 'change-impact ...'
Step 'E-CI' {
  $script:ci1 = & "$SRC\Emit-ChangeImpact.ps1" -Target 'Blueprint4.ViewModel.TBlueprint_ViewModel.ReserveNextID' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-CI1-AFFECTED' $ci1.Affected 9
  Chk 'A-CI1-UNITS'    $ci1.Units 1
  Chk 'A-CI1-ZONES'    $ci1.Zones 1
  Chk 'A-CI1-CAPPED'   $ci1.Capped $false

  $script:ci2 = & "$SRC\Emit-ChangeImpact.ps1" -Target 'uPipeClientConnection.TPipeClientConnection' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-CI2-ISTYPE'   $ci2.IsType $true
  Chk 'A-CI2-AFFECTED' $ci2.Affected 591
  Chk 'A-CI2-UNITS'    $ci2.Units 174
  Chk 'A-CI2-CAPPED'   $ci2.Capped $true
  if ((Dot $ci2) -notmatch 'frontier CAPPED') { Fail 'A-CI2-DISCLOSE' 'the capped radius does not admit it' }
}

Note 'tested-by ...'
Step 'E-TB' {
  $script:tb1 = & "$SRC\Emit-TestedBy.ps1" -Target 'uCompGroupTree.TCompGroupTree.Build' -DbPath $DbMt -OutDir $OutDir
  Chk 'A-TB1-TESTS'    $tb1.Tests 11
  Chk 'A-TB1-FIXTURES' $tb1.Fixtures 1
  # 71, not 213: one [Test] marks ONE method -- the nearest FOLLOWING declaration.
  # A "+/- 2 lines" window matched three methods per attribute on these fixtures.
  Chk 'A-TB1-METHODS'  $tb1.TestMethods 71

  $script:tb2 = & "$SRC\Emit-TestedBy.ps1" -Target 'uGageLineQueue.TGageLineQueue.TryDequeue' -DbPath $DbMt -OutDir $OutDir
  Chk 'A-TB2-TESTS' $tb2.Tests 8

  $script:tb3 = & "$SRC\Emit-TestedBy.ps1" -Target 'uCompGroupTree.TCompGroupTree' -DbPath $DbMt -OutDir $OutDir
  Chk 'A-TB3-TESTS' $tb3.Tests 13
}

Note 'negatives N20-N24 ...'
# SERVER has no data-aware UI. "Not applicable to this index" and "0 found" are
# different claims and the emitter must make the first one.
NegTest 'N20' 'contains NO DFM data bindings at all' 'shownwhere_FTRNAMESTR' {
  & "$SRC\Emit-ShownWhere.ps1" -Column 'FTRNAMESTR' -DbPath $DbSrv -OutDir $negDir }
# The ui_affinity premise, refused with the reason: 0 of 13,131 fields carry one.
NegTest 'N21' 'is a Delphi field' 'shownwhere_MSCTYPES_RChartSampleData_R' {
  & "$SRC\Emit-ShownWhere.ps1" -Column 'MSCTYPES.RChartSampleData.R' -DbPath $DbCli -OutDir $negDir }
NegTest 'N22' 'it is not a test project index' 'testedby_uMain_TfrmMAIN_FormCreate' {
  & "$SRC\Emit-TestedBy.ps1" -Target 'uMain.TfrmMAIN.FormCreate' -DbPath $DbCli -OutDir $negDir }
# A DFM-dispatched handler has no callers, which is a true answer about ORM3 and
# must not be dressed up as an empty blast radius.
NegTest 'N23' '0 callers at any depth' 'impact_uMain_TfrmMAIN_FormCreate' {
  & "$SRC\Emit-ChangeImpact.ps1" -Target 'uMain.TfrmMAIN.FormCreate' -DbPath $DbCli -OutDir $negDir }
NegTest 'N24' 'references no enum constant at all' 'prototrace_gammafunc_LnGamma' {
  & "$SRC\Emit-ProtocolTrace.ps1" -Target 'gammafunc.LnGamma' -DbPath $DbCli -OutDir $negDir }

# ---- PLAN-last-four-verbs, Task 0: the shared helpers ----------------------------
# Every number below was measured on 2026-09-23 against the clones and is PINNED
# (controller ruling R5: no >= assertions). Where a pin differs from the plan's
# section 1, the comment names the mechanism (R6) -- none was silently re-based.
Note 'task-0 helpers (SQL set, triggers, verb scan, source context, datasource chain) ...'
Step 'E-T0' {
  $script:t0 = & "$SRC\Test-Task0Helpers.ps1" -DbCli $DbCli -DbSql $DbSql -OutDir $OutDir

  # P15: 252 declarations collapse to 135 names; 117 names are declared twice
  # (MS1.SQL and MScript2.SQL -- no other script declares a table).
  Chk 'A-CO0-TABLES'    "$($t0.SqlTables)/$($t0.SqlDeclarations)" '135/252'
  Chk 'A-CO0-COLLAPSED' $t0.SqlCollapsed 117
  Chk 'A-CO0-PROCS'     $t0.SqlProcedures '90/168'
  # FINDING vs the plan's "LAST declaration in file order": that picks
  # MScript2.SQL, which is the OLDER script (mtime 2025-02-11 vs MS1 2026-06-22)
  # and gives FOLDERS 47 columns. The newest-file rule picks MS1: FOLDERS 79 and
  # CAUSFAIL 4, exactly the live Firebird counts (P16/P24).
  Chk 'A-CO0-WINNER'    "$($t0.FoldersColumns) from $($t0.FoldersFrom)" '79 from MS1.SQL'
  Chk 'A-CO0-CAUSCOLS'  $t0.CausfailColumns 'ID,REASON,SEVERITY,SYSTID'

  Chk 'A-CO0-TRIGGERS'  "$($t0.TriggerBodies)/$($t0.Triggers)" '183/183'
  Chk 'A-CO0-TRIGSTALE' $t0.TriggerStale 0
  # 183, NOT the plan's 177. The 6 "missing" triggers are FOR FIB$... tables: a
  # `\w+` read of the FOR clause stops at the `$` (the same truncation as P21's
  # `FIB`). The engine's own sql_table_ref on each CREATE TRIGGER line carries
  # the whole name, and all 183 are in the collapsed set.
  Chk 'A-CO0-FORTABLE'  $t0.TriggerForKnown 183
  Chk 'A-CO0-NEWOLD'    $t0.TriggerNewOld 183
  # P19's "4 also name ANOTHER table", by name
  Chk 'A-CO0-OTHER'     $t0.TriggerOther 'HEATBOOK_AIU5>FOLHEAT,MACHINES_AI10>MACHINESTAT,MACHINES_AU10>MACHINESTAT,TOOLS_AI0>TOOLGR12'
  # P39's CAUSFAIL rows
  Chk 'A-CO0-CAUSTRIG'  $t0.CausfailTriggers 'CAUSFAIL_BIU0=ID,CAUSFAIL_BIU5=REASON+SEVERITY+SYSTID,CAUSFAIL_BUD0=SYSTID'
  # Pinned at 9 (the P23 cases in Test-Task0Helpers.ps1). The failure list is
  # checked for PRESENCE first: a $null list is "the check never ran", which the
  # old `@($null).Count` test could not tell apart from nine clean passes.
  Chk 'A-CO0-VERBCASES' $t0.VerbCases 9
  if ($null -eq $t0.VerbCaseFailures) { Fail 'A-CO0-VERB' 'VerbCaseFailures is null -- the verb-case check did not run' }
  elseif (@($t0.VerbCaseFailures).Count) { Fail 'A-CO0-VERB' (@($t0.VerbCaseFailures) -join '; ') }

  # P2 through Get-SourceContext: of 430 candidate refs, 168 reads sit after
  # `raise` and 185 type_uses after `on [E:]` -- with 0 stale files among them
  # and 0 refs whose stripped token is not the ref's own name (column alignment).
  Chk 'A-EP0-CAND'      $t0.ExcCandidates 430
  Chk 'A-EP0-CLASSIFY'  "$($t0.ExcRaise)/$($t0.ExcHandle)" '168/185'
  Chk 'A-EP0-FRESH'     $t0.ExcStale 0
  Chk 'A-EP0-TOKEN'     $t0.ExcTokenMiss 0

  # 54 / 5 / 49, NOT the plan's 54 / 5 / 51. The plan matched `.DataSet` sites
  # by BARE receiver name across files; the two DFM-wired `DSR` datasources then
  # "had" 8 code sites each in uAutoTest.pas, where DSR is a LOCAL variable
  # (`var DSR : TDataSource:= VM.GetpdsrFolder`) -- the P28 collision. Same-file
  # matching: 49 datasources have a code site, all 49 assign.
  Chk 'A-FF0-DS'        "$($t0.DsTotal)/$($t0.DsDfmWired)/$($t0.DsCodeSite)" '54/5/49'
  Chk 'A-FF0-ASSIGN'    $t0.DsAssigned 49
  Chk 'A-FF0-RESOLVE'   "$($t0.DsOne)/$($t0.DsMany)/$($t0.DsNone)" '22/17/9'
  # 6 of the 17 break the tie on bound columns. The plan listed 5 NAMES --
  # dsrAssigned is two datasources (AssignGroups and AssignTools2), both resolve.
  Chk 'A-FF0-BYCOL'     $t0.DsByColumns 6
  Chk 'A-FF0-GRADES'    $t0.DsGrades 'by-columns=6,dfm-dataset=5,many=11,no-type=1,none=9,one-table=22'
  Chk 'A-FF0-REASON'    $t0.DsNoReason 0
  Chk 'A-FF0-HOPS'      $t0.DsNoHops 0
  # MOVED by Task 3 (was certain>inferred>by name>inferred): the dataset hop is
  # CERTAIN when every non-nil assignment site in the unit agrees on one RHS and
  # none is in a stale file (brief section 6: "certain, anchored to the
  # assignment line"). dsrCausFail has one: uCausFailForm.pas:125. It stays
  # inferred, with the reason, when the sites disagree.
  Chk 'A-FF0-CAUSFAIL'  $t0.CausFailChain 'one-table:CAUSFAIL:certain>certain>by name>inferred'
  # 65 dangling rows, 63 of them re-pointed by an ASSIGNMENT in code. The plan's
  # 21 was receiver_text-only and counted 3 READS as re-pointings
  # (viewSPCMU/PP/CP.DataController.DataSource.DataSet.Append, ControlPlan2.pas
  # 1689-1702); receiver_text alone finds 18 assignments. The other 45 have the
  # control recovered from source because `edtF2   .DataBinding   .DataSource:=`
  # stores receiver_text '.DataBinding' (P29).
  Chk 'A-FF0-DANGLING'  "$($t0.DanglingRows)/$($t0.RePointedAny)" '65/63'
  Chk 'A-FF0-DANGMOD'   $t0.DanglingMissing 65
  Chk 'A-FF0-DANGRECV'  $t0.RePointedRecv 18

  # N21 at helper level: a MANUFACTURED stale copy (one trailing blank added) is
  # stale, every DataSet site in it reads `stale`, none is classified, and the
  # context carries no text; an UNCHANGED copy under a different path is fresh
  # and resolves -- so the check is on content, not on the path.
  Chk 'A-T0-OVR-SAME'   $t0.OverrideSameFresh $true
  Chk 'A-T0-OVR-STALE'  $t0.OverrideStaleFresh $false
  Chk 'A-T0-STALECHAIN' $t0.StaleChain 'stale source::stale,stale'
  Chk 'A-T0-STALECLASS' $t0.StaleClassified 0
  Chk 'A-T0-STALECTX'   $t0.StaleContext 'True:True:True'
  Chk 'A-T0-FRESHCOPY'  $t0.FreshCopyChain 'one-table:CAUSFAIL'
  # ...and on the SQL side: one changed line in MS5.SQL stales exactly its 73
  # triggers, and not one of them is scanned.
  Chk 'A-T0-SQLSTALE'   "$($t0.SqlStaleTriggers)/$($t0.Ms5Triggers)" '73/73'
  Chk 'A-T0-SQLSCAN'    $t0.SqlStaleScanned 0
}

# N-MAXPATH (Task 1 report, 2026-09-23): dot.exe cannot open an output path over
# 259 characters and used to leave only "dot produced no SVG". Invoke-DotRun now
# refuses BEFORE dot runs, naming the length and the path. The FOLDER is sized
# to 200 characters -- under every tool's limit, so it stays deletable -- and the
# qname slug (67 characters for the .plain) carries the FILE path over 259.
Note 'negative N-MAXPATH (dot output path over MAX_PATH) ...'
$longDir = [IO.Path]::GetFullPath($negDir)
$longDir = Join-Path $longDir ('p' * (199 - $longDir.Length))
$threw = $false
try { & "$SRC\Emit-Butterfly.ps1" -Qname $Q_SEND -DbPath $DbCli -Depth 1 -OutDir $longDir | Out-Null }
catch { $threw = $true; $m = $_.Exception.Message }
if (-not $threw) { Fail 'N-MAXPATH' 'did not throw' }
elseif ($m -notlike '*that dot.exe can open*') { Fail 'N-MAXPATH' "message did not name the path limit -- got: $m" }
if (@(Get-ChildItem -LiteralPath $longDir -Filter '*.svg' -ErrorAction SilentlyContinue).Count) {
  Fail 'N-MAXPATH' 'left an .svg behind'
}
# R19 (Task 5 fix round 1): the engine wrappers FAIL LOUDLY. A failed query used
# to come back as zero rows -- a time cap, a bad table or a locked database all
# read as "nothing found". Each case below is a real engine call on the clone,
# except the lock, which uses a fake engine so the retry path is deterministic.
Note 'negatives W-* (engine wrappers fail loudly, R19) ...'
Step 'E-W' {
  & {
    . "$SRC\Emit-Common.ps1"
    $Engine = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
    $DbPath = Get-CloneDb $DbCli
    function Throws([string] $code, [string] $phrase, [scriptblock] $b) {
      $threw = $false
      try { & $b | Out-Null } catch {
        $threw = $true
        if ($_.Exception.Message -notlike "*$phrase*") { Fail $code "message lacks '$phrase': $($_.Exception.Message)" }
      }
      if (-not $threw) { Fail $code 'did not throw' }
    }
    # a zero-row answer is still an answer
    $z = Invoke-IndexQuery "SELECT id FROM symbols WHERE name = 'ZzNoSuchName'"
    Chk 'W-EMPTY' $z.Count 0
    # the time cap (10,000 ms) -- exit 1, `ERROR: stopped -- ... time cap`, empty stdout
    Throws 'W-TIMECAP' 'time cap' {
      Invoke-IndexQuery 'WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c) SELECT COUNT(*) FROM c' }
    Throws 'W-BADTABLE' 'no such table' { Invoke-IndexQuery 'SELECT id FROM no_such_table' }
    # the paged reader inherits it: a failing page is not the end of the data
    Throws 'W-PAGED' 'no such table' { Get-AllIndexRows 'SELECT id FROM no_such_table' 'id' }
    # no match: exit 1, nothing on stderr but notes -- accepted ONLY when asked
    $nm = Get-EngineText @('query', 'find-callers', '--name', 'ZzNoSuchName', '--db', $DbPath, '--json') -AllowNoMatch
    Chk 'W-NOMATCH' "[$nm]/$script:LastEngineExit/$script:LastEngineNoMatch" '[]/1/True'
    Throws 'W-NOMATCH-STRICT' '(exit 1)' {
      Get-EngineText @('query', 'find-callers', '--name', 'ZzNoSuchName', '--db', $DbPath, '--json') }
    # -AllowNoMatch never excuses a real error on stderr
    Throws 'W-NOMATCH-ERR' 'no such table' {
      Get-EngineText @('sql', '--db', $DbPath, '--query', 'SELECT 1 FROM no_such_table', '--format', 'json') -AllowNoMatch }

    # `database is locked`: bounded retry (3 attempts), then throw. Fake engines:
    # locked.cmd always fails and counts its calls; once.cmd fails on the FIRST
    # call only (it creates once.txt) and then answers.
    $fk = Join-Path $OutDir 'fake-engine'
    New-Item -ItemType Directory -Force $fk | Out-Null
    $A = New-Object Text.ASCIIEncoding
    [IO.File]::WriteAllText((Join-Path $fk 'locked.cmd'),
      "@echo off`r`necho x>>`"%~dp0calls.txt`"`r`necho FATAL: ESQLiteNativeException: database is locked 1>&2`r`nexit /b 3`r`n", $A)
    [IO.File]::WriteAllText((Join-Path $fk 'once.cmd'),
      ("@echo off`r`nif not exist `"%~dp0once.txt`" (echo x>`"%~dp0once.txt`" & echo FATAL: database is locked 1>&2 & exit /b 3)`r`n" +
       'echo {"schema":"sql/1","columns":[{"name":"x","type":"Integer"}],"rows":[[7]],"row_count":1,"truncated":false,"row_cap":200}' + "`r`n"), $A)
    $Engine = Join-Path $fk 'locked.cmd'
    Throws 'W-LOCK' 'database is locked' { Invoke-IndexQuery 'SELECT 1' }
    Chk 'W-LOCK-TRIES' @(Get-Content (Join-Path $fk 'calls.txt')).Count 3
    $Engine = Join-Path $fk 'once.cmd'
    $one = Invoke-IndexQuery 'SELECT 1'
    Chk 'W-LOCK-RECOVER' "$($one.Count)/$($one[0].x)" '1/7'
  }
}
Note 'negatives N33, N35 (database refusals for the new helpers) ...'
# N33: the SQL index is reached through Get-CloneDb like every other DB, so a
# -SqlDbPath habit cannot open the live one. Get-CloneDb only resolves the path;
# it never opens the file.
$liveSql = 'C:\Projects\DB\SQL\drag-lint-sql.sqlite'
# A missing file FAILS, as for N19.
if (Test-Path $liveSql) {
  NegTest 'N33' 'refusing a non-clone database' 't0_n33' {
    & { . "$SRC\Emit-Common.ps1"; Get-SqlTableSet $liveSql } }
} else {
  Fail 'N33-PRE' "precondition missing: $liveSql -- the SQL-index refusal cannot be exercised"
}
# N35 (ruling R3): a history copy sits UNDER the clone root, so the whitelist
# alone accepts it and it answers with the older parse. The suffix rule refuses.
$preCli = Join-Path $PSScriptRoot '..\scratch\db\CLIENT-Micronite2027.sqlite.pre-1.18'
# A missing history copy FAILS, as for N19: without it the suffix rule is untested.
if (Test-Path $preCli) {
  NegTest 'N35' 'does not end in .sqlite' 'shownwhere_FTRNAMESTR' {
    & "$SRC\Emit-ShownWhere.ps1" -Column 'FTRNAMESTR' -DbPath $preCli -OutDir $negDir }
} else {
  Fail 'N35-PRE' "precondition missing: $preCli -- the .sqlite suffix refusal cannot be exercised"
}

# ---- PLAN-last-four-verbs, Task 1: exception-paths ------------------------------
# Every number measured 2026-09-23 on the CLIENT clone and PINNED (R5). Where a
# pin differs from the plan, the comment names the mechanism (R6).
# The words "unhandled" may appear in NO chart (R3): the walk ending is not the
# exception escaping.
function NoUnhandled([string] $code, $r) {
  if ((Dot $r) -match '(?i)unhandled') { Fail $code 'the chart says "unhandled" -- it may only say where the walk ended (R3)' }
}
Note 'exception-paths ...'
Step 'E-EP' {
  $script:ep1 = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'Blueprint4.PDFImport.ViewModel.TBlueprintPDFImport_ViewModel.PersistScanToDB' -DbPath $DbCli -OutDir $OutDir
  # the index-wide line on the focus box: the name-filtered candidates, minus
  # the names declared only as non-classes (P5), each classified by source token
  Chk 'A-EP0-CANDS'     "$($ep1.IndexRaise)/$($ep1.IndexHandle)" '168/185'
  Chk 'A-EP0-ROUTINES'  "$($ep1.IndexRaiseRoutines)/$($ep1.IndexHandleRoutines)" '120/106'
  # 30 decl + 17 class( + 8 is + 2 as + 8 call-cast + 7 member-access; 425 = 168 + 185 + 72
  Chk 'A-EP0-DROPPED'   $ep1.IndexDropped 72
  Chk 'A-EP0-CANDCOUNT' $ep1.IndexCandidates 425

  Chk 'A-EP1-RAISES'    $ep1.Raises 6
  Chk 'A-EP1-LINES'     $ep1.RaiseLines '1624,1653,1667,1679,1691,1707'
  Chk 'A-EP1-TYPES'     "$($ep1.RaiseTypes):$($ep1.RaiseTypeNames)" '1:Exception'
  Chk 'A-EP1-HANDLES'   $ep1.Handles 0
  Chk 'A-EP1-CALLERS'   $ep1.Callers 2
  Chk 'A-EP1-CHAIN'     $ep1.CallerNames 'd1:AutoScanIfNeeded,d2:ForceRescan'
  Chk 'A-EP1-CAUGHT'    $ep1.Caught 0
  # per-node walk (R12): AutoScanIfNeeded -> ForceRescan, which has no resolved
  # caller of its own -- counted, not left implicit
  Chk 'A-EP1-WALK'      $ep1.WalkSentence 'no handler found within 3 caller levels (2 callers evaluated); reaches 1 caller with no resolved caller of its own'
  # type:caught edges/escapes/no-caller ends/callers evaluated/capped callers
  Chk 'A-EP1-PATHS'     $ep1.TypePaths 'Exception:0/0/1/2/0'
  Chk 'A-EP1-FRESH'     $ep1.StaleFiles 0
  Chk 'A-EP1-CLICK'     "$($ep1.ClickTargets)/$($ep1.Expected)" '9/9'
  $t1 = Dot $ep1
  foreach ($ln in 1624, 1653, 1667, 1679, 1691, 1707) { if (-not (HasLine $t1 $ln)) { Fail 'A-EP1-ANCHOR' "raise row :$ln is not anchored" } }
  if ($t1 -notmatch 'no handler found within 3 caller levels \(2 callers evaluated\)') { Fail 'A-EP1-SENTENCE' 'the walk sentence is not on the chart' }
  NoUnhandled 'A-EP1-WORDS' $ep1

  $script:ep2 = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'Gagefrm2.TfrmGageport2.Configure_ComPort' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-EP2-RAISES'    "$($ep2.Raises):$($ep2.RaiseLines)" '1:1703'
  Chk 'A-EP2-HANDLES'   "$($ep2.Handles):$($ep2.HandleLines)" '3:1690,1705,1732'
  # the `is EAPDException` at :1695 (type_use) and the EAPDException(E) cast at
  # :1696 (call) -- counted, never drawn
  Chk 'A-EP2-DROPPED'   $ep2.Dropped 2
  Chk 'A-EP2-CALLERS'   "$($ep2.Callers):$($ep2.WalkSentence)" '0:no resolved caller in this index'
  Chk 'A-EP2-FRESH'     $ep2.StaleFiles 0
  NoUnhandled 'A-EP2-WORDS' $ep2

  $script:ep3 = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'uMain.Model.TMainModel.LoadInspectionNames' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-EP3-RAISES'    "$($ep3.Raises):$($ep3.RaiseTypeNames):$($ep3.RaiseLines)" '7:EDataError:65,68,71,74,78,81,85'
  Chk 'A-EP3-CALLERS'   $ep3.Callers 0
  Chk 'A-EP3-FRESH'     $ep3.StaleFiles 0
  if ((Dot $ep3) -notmatch 'no resolved caller in this index') { Fail 'A-EP3-SENTENCE' 'the no-caller sentence is not on the chart' }
  NoUnhandled 'A-EP3-WORDS' $ep3

  $script:ep4 = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'BASICSF.CopyRecords' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-EP4-HANDLES'   "$($ep4.Handles):$($ep4.HandleLines)" '1:5037'
  # 5, NOT the plan's 2. The plan named `raise E`@5046 and `raise`@5064 only; the
  # same span (4957-5074) also holds `raise;`@5054 (`if not IgnoreErrors then
  # raise;`) and two BARE `except` blocks (5053, 5063) that the plan's own step 3
  # requires drawing. And `raise E`@5046 DOES have a ref (`read E`, col 26) --
  # on the caught VARIABLE, so the classifier leaves it to the source scan.
  Chk 'A-EP4-INFERRED'  $ep4.InferredLines 'raise-var@5046,bare-except@5053,reraise@5054,bare-except@5063,reraise@5064'
  Chk 'A-EP4-SPLIT'     "$($ep4.InferredRaises)/$($ep4.BareExcepts)" '3/2'
  Chk 'A-EP4-RAISES'    $ep4.Raises 0
  Chk 'A-EP4-FRESH'     $ep4.StaleFiles 0
  NoUnhandled 'A-EP4-WORDS' $ep4

  $script:ep5 = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'uAutoTest.RunAutoTest' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-EP5-HANDLES'   $ep5.Handles 41
  if ((Dot $ep5) -notmatch '\+29 more handler clauses not shown') { Fail 'A-EP5-CAP' 'the 41 handlers are not capped at 12 with the +29 disclosure' }
  Chk 'A-EP5-FRESH'     $ep5.StaleFiles 0
  NoUnhandled 'A-EP5-WORDS' $ep5

  # A-EP6 RE-PINNED in fix round 1 (controller ruling R10). The first version
  # matched a caller's handler ANYWHERE in its body and pinned `caught (exact)`
  # at depth 1 -- FALSE in source: LoadAll (:525) and ApplyRawPayload (:569)
  # call BuildSchema inside a try..FINALLY; their `on E: EDatabaseError`
  # handlers (:532 / :579) guard only LoadFromStream (:530 / :574), and both
  # re-raise (`raise;` :540 / :585). Those two handlers, and LoadAllAsync's
  # :627 handler (its try covers the pipe call, not the queued apply), guard
  # other statements: NotGuarding 3, and none of the three lines is drawn.
  # The real catch is one level up: LoadAllAsync :632 is `try if Ok then
  # ApplyRawPayload(RspPayload); except on E: Exception do ...` -- call at col
  # 40, between the try (col 25) and the except, and the handler does not
  # re-raise. Verified by a targeted read of uJobList.ViewModel.pas 602-636.
  $script:ep6 = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'uJobList.ViewModel.TJobListViewModel.BuildSchema' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-EP6-CALLERS'   "$($ep6.Callers)/$($ep6.CallerLevels)" '7/3'
  Chk 'A-EP6-EVENTS'    $ep6.Events 'caught:LoadAllAsync:632'
  # 3 DISTINCT handler positions (:532, :579, :627), none drawn -- the per-edge
  # sum happened to equal it here (each sits on one edge); item 3 counts distinct
  Chk 'A-EP6-NOTGUARD'  "$($ep6.NotGuarding)/$($ep6.NotGuardingUndrawn)" '3/3'
  Chk 'A-EP6-NOTEVAL'   $ep6.NotEvaluated 'd3:DoInitLoad'
  Chk 'A-EP6-CAUGHT'    "$($ep6.Caught):$($ep6.ReRaised):$($ep6.Unverified):$($ep6.MayCatch)" '1:0:0:0'
  # R12, fix round 2: the catch at LoadAllAsync stops EDatabaseError through
  # LoadAllAsync ONLY. The LoadAll path goes on to btnRefreshClick,
  # btnRefreshGridClick and RefreshFolders, none of which catches and none of which
  # has a resolved caller (DFM event handlers) -- 3 path ends, counted. 7 callers are
  # walked (the graph), 6 EVALUATED by the type: DoInitLoad is reached only through
  # LoadAllAsync, which caught (final wave item 3: the two terms are distinct).
  # catchers / escapes past the depth bound / no-caller ends / callers evaluated:
  Chk 'A-EP6-PATHS'     $ep6.TypePaths 'EDatabaseError:1/0/3/6/0'
  Chk 'A-EP6-WALK'      $ep6.WalkSentence 'caught on 1 call edge (LoadAllAsync:632 on the call to ApplyRawPayload) within 3 caller levels (6 callers evaluated); reaches 3 callers with no resolved caller of their own'
  $t6 = Dot $ep6
  foreach ($ln in 532, 579, 627) { if (HasLine $t6 $ln) { Fail 'A-EP6-NOTCONTAINED' "the handler at :$ln guards another statement but was drawn" } }
  if ($t6 -notmatch 'caught \(catch-all\) at LoadAllAsync:632') { Fail 'A-EP6-EDGE' 'the verified catch at LoadAllAsync:632 is not drawn' }
  if ($t6 -notmatch '3 matching handler\(s\) in callers guard other statements') { Fail 'A-EP6-DISCLOSE' 'the not-guarding handlers are not disclosed' }
  NoUnhandled 'A-EP6-WORDS' $ep6

  # A GENUINE solid catch at depth 1, verified by a targeted read of uAutoTest.pas
  # 363-569: AutoTestSetupDefaults calls ReadBuffer at :433 inside the try opened
  # at :411, whose except (:465) holds `on E: Exception do Check(...)` at :466 --
  # no re-raise. The other handler in that body (:402) closes its try at :403,
  # before the call.
  $script:ep7 = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'MStreams.TABZMemoryStream.ReadBuffer' -DbPath $DbCli -OutDir $OutDir
  # EDGE-LEVEL truth (R13, fix round 3), verified by targeted reads of uAutoTest.pas.
  # AutoTestSetupDefaults stops EReadError on TWO call edges -- ReadBuffer at :433
  # and uSTATIONS_CLIENT...Save at :461, both inside the try at :411 whose except
  # (:465) holds `on E: Exception` at :466 -- and lets it ESCAPE on a third: its
  # calls to TSetupDefaultsViewModel.Save at :513/:561 sit in try..finally only.
  # Round 2 marked it visited after the catch and dropped that path.
  Chk 'A-EP7-EVENTS'    $ep7.Events 'caught:AutoTestSetupDefaults:466,caught:AutoTestSetupDefaults:466'
  Chk 'A-EP7-CAUGHT'    "$($ep7.RaiseTypeNames):$($ep7.Caught):$($ep7.CatchAndPass)" 'EReadError:2:1'
  # not guarding: :402 (its try is 390..401) on each of the three edges, and
  # :466 on the escaping Save edge (513/561 lie outside the try at 411..465).
  # RE-PINNED in the final wave (item 3), 140/4 -> 140/139/2/1. The old 4 was a
  # SUM over call edges: :402 judged on 3 edges + :466 on 1. Distinct handler
  # positions are 2 (:402, :466); :466 is DRAWN (it catches on the ReadBuffer
  # and Save :461 edges), so only 1 is "not drawn", and the chart says both.
  # 140 = callers WALKED (the caller graph to depth 3); 139 = callers EVALUATED
  # by EReadError's walk -- RunAutoTest (graph depth 2) is not: its callee
  # AutoTestSetupDefaults catches on its level-1 edge and passes the type only at
  # level 3, so for the type RunAutoTest is past the bound (one of the 3 escapes).
  Chk 'A-EP7-CALLERS'   "$($ep7.Callers)/$(($ep7.TypePaths -split '/')[3])/$($ep7.NotGuarding)/$($ep7.NotGuardingUndrawn)" '140/139/2/1'
  Chk 'A-EP7-NOTEVAL'   $ep7.NotEvaluated 'd2:RunAutoTest'
  $t7n = Dot $ep7
  if ($t7n -notmatch 'callers walked: 140 over 3 level') { Fail 'A-EP7-TERMS' 'the focus box does not say "callers walked: 140"' }
  if ($t7n -notmatch '\(139 callers evaluated\)') { Fail 'A-EP7-TERMS' 'the walk sentence does not say "139 callers evaluated"' }
  if ($t7n -notmatch '2 matching handler\(s\) in callers guard other statements, not the call, on at least one call edge -- 1 not drawn; 1 drawn where they do enclose a call') {
    Fail 'A-EP7-NOTGUARD' 'the distinct not-guarding handlers (2: 1 not drawn, 1 drawn) are not disclosed' }
  # THE SIBLING-PATH ROW. Per edge, EReadError walks all 134 direct callers and
  # everything above the ones that pass it: 139 callers evaluated, 133 path ends
  # with no resolved caller (mostly interface-dispatched Save methods), 3 past the
  # depth bound -- SaveDefaults and AutoTestSetupBools at depth 3, and
  # AutoTestSetupDefaults itself, which PASSES at level 3 through Save and whose
  # caller RunAutoTest (:1651, inside `try .. except on E: Exception`) is beyond
  # the bound. Round 1 stopped the type after depth 1; round 2 read 1/2/133/139.
  Chk 'A-EP7-PATHS'     $ep7.TypePaths 'EReadError:2/3/133/139/0'
  Chk 'A-EP7-WALK'      $ep7.WalkSentence 'caught on 2 call edges (AutoTestSetupDefaults:466 on the call to ReadBuffer, AutoTestSetupDefaults:466 on the call to Save) within 3 caller levels (139 callers evaluated); 1 catching caller also lets it escape on another call; escapes the walk on 3 path ends after 3 levels; reaches 133 callers with no resolved caller of their own'
  $t7 = Dot $ep7
  if ($t7 -notmatch 'escapes the walk on 3 path ends after 3 levels') { Fail 'A-EP7-DISCLOSE' 'the escaping paths are not on the chart' }
  if ($t7 -notmatch 'caught \(catch-all\) at AutoTestSetupDefaults:466 on the call to ReadBuffer') { Fail 'A-EP7-EDGE' 'the verified catch is not drawn' }
  # both halves of the same node, anchored: the escaping calls are rows at :513 / :561
  foreach ($ln in 513, 561) { if (-not (HasLine $t7 $ln)) { Fail 'A-EP7-ESCROW' "the escaping call at :$ln is not an anchored row" } }
  if ($t7 -notmatch 'escapes via the call to Save') { Fail 'A-EP7-ESCROW' 'the escaping call is not labelled' }

  # THE CAP (fix round 3): -MaxCallers 10 keeps 124 of ReadBuffer's 134 direct
  # callers out of the walk. They are counted as NOT WALKED (cap) -- never as
  # "no resolved caller". The 10 walked ones are real no-caller ends (their own
  # callers were queried and, had any existed, would show as capped too).
  $script:ep10 = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'MStreams.TABZMemoryStream.ReadBuffer' -DbPath $DbCli -OutDir (Join-Path $OutDir 'ep-cap') -MaxCallers 10
  Chk 'A-EP10-PATHS'    $ep10.TypePaths 'EReadError:0/0/10/10/124'
  Chk 'A-EP10-WALK'     $ep10.WalkSentence 'no handler found within 3 caller levels (10 callers evaluated); reaches 10 callers with no resolved caller of their own; 124 callers not walked (cap)'
  if ((Dot $ep10) -notmatch '124 callers not walked \(cap\)') { Fail 'A-EP10-DISCLOSE' 'the capped callers are not on the chart' }
  NoUnhandled 'A-EP7-WORDS' $ep7

  # Finding 3: a STALE caller is not read, and the sentence says so instead of
  # letting "no handler found" cover it. uAutoTest.pas is manufactured stale
  # (one trailing blank, -SourceOverride): its 3 callers are not read, so the
  # verified catch above disappears and the sentence counts them.
  $stDir9 = Join-Path $OutDir 'ep-stale-caller'
  New-Item -ItemType Directory -Force $stDir9 | Out-Null
  $atp = 'C:\Projects\DB\ORM3\CLIENT\uAutoTest.pas'
  $al = [IO.File]::ReadAllLines($atp); $al[0] = $al[0] + ' '
  [IO.File]::WriteAllText((Join-Path $stDir9 'uAutoTest.pas'), (($al -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $script:ep9 = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'MStreams.TABZMemoryStream.ReadBuffer' -DbPath $DbCli -OutDir $stDir9 `
                  -SourceOverride @{ $atp = (Join-Path $stDir9 'uAutoTest.pas') }
  Chk 'A-EP9-STALE'     "$($ep9.StaleCallers):$($ep9.Caught):$($ep9.Events)" '3:0:'
  # the stale catcher passes EReadError on, so all 140 are walked and one more
  # node ends without a caller (134, not 133)
  Chk 'A-EP9-WALK'      $ep9.WalkSentence 'no handler found within 3 caller levels (140 callers evaluated); escapes the walk on 2 path ends after 3 levels; reaches 134 callers with no resolved caller of their own; 3 callers not read: source changed since indexing'
  Chk 'A-EP9-PATHS'     $ep9.TypePaths 'EReadError:0/2/134/140/0'
  if ((Dot $ep9) -notmatch '3 callers not read: source changed since indexing') { Fail 'A-EP9-DISCLOSE' 'the unread callers are not on the chart' }

  # the SOURCE-ONLY rows inside every indexed impl span, index-wide
  $script:ex0 = & "$SRC\Test-ExceptionPathsHelpers.ps1" -DbCli $DbCli
  Chk 'A-EP0-SPANS'     "$($ex0.Spans)/$($ex0.SpanStaleFiles)" '11007/1'
  # bare except / on-except / raise; / raise <var> / routines with a bare except.
  # 13 / 1, NOT the plan's 12 / 2: BASICSF.pas:5064 is `then raise` + newline +
  # `else` -- a re-raise with no semicolon. The plan's scan read `else` as the
  # raised variable. P6's own census agrees (12 `raise;` + 1 `then raise` + 1 `raise E`).
  Chk 'A-EP0-SOURCE'    "$($ex0.BareExcept)/$($ex0.OnExcept)/$($ex0.Reraise)/$($ex0.RaiseVar)/$($ex0.BareRoutines)" '86/180/13/1/56'
  # 169, NOT the plan's 180: every in-span `raise X.Create` has a raise-classified
  # read ref (168 name-filtered + EdxException, uStyles.pas:965). Whole-file the
  # stripped count is 177; the other 8 are the uJobList.pas {$IFDEF
  # M2022_REFERENCE} lines, where the index has no routine span (P6).
  Chk 'A-EP0-CREATE'    "$($ex0.RaiseCreate)/$($ex0.RaiseOther)" '169/0'
  # R10's nesting scan over EVERY indexed span: 2 of 10,995 fresh spans are not
  # decided, both correctly -- MStreams.pas:917 is an `asm` body split by
  # {$IF}/{$ELSE} (its Pascal `begin` sits in a blanked branch), and
  # uJobList.pas:971 starts on a line that closes the PREVIOUS routine
  # (`end; procedure ...`). A not-decided span can only draw dashed edges.
  Chk 'A-EP0-TRYSCAN'   "$($ex0.TryDecided)|$($ex0.TryUndecided)" '10993|MStreams.pas:917,uJobList.pas:971'
  # focused checks: finding 4's split handler (`on` / `E: T do`), and the
  # nesting scan on synthetic bodies (nested try, record case, asm, unbalanced)
  if (@($ex0.ClassifierFailures).Count) { Fail 'A-EP-F4-CLASSIFY' (@($ex0.ClassifierFailures) -join '; ') }
  if (@($ex0.TryScanFailures).Count)    { Fail 'A-EP-R10-SCAN'    (@($ex0.TryScanFailures) -join '; ') }
  # re-raise detection (R10): synthetic handlers, then the REAL ones A-EP6/A-EP7 rest on --
  # LoadAll:532 and ApplyRawPayload:579 re-raise; LoadAllAsync:632 and
  # AutoTestSetupDefaults:466 do not. No CLIENT re-raising try guards a call into a
  # raising path (measured: 0 within 2 levels), so no chart row can pin 'reraised'.
  # the column base: refs.start_col and the nesting scan are both 1-based --
  # ref col / scan col of the same name / try col / call inside -- on
  # LoadAllAsync:632, where the call and its try/except share one line
  Chk 'A-EP-R12-COLBASE' $ex0.ColumnBase '40/40/25/True'
  # the per-EDGE walk (R13) on synthetic graphs: catch on one edge + escape on
  # another reaching the same node deeper, a full stop, a cycle that must
  # terminate, the depth bound, capped-only callers, a focus without callers
  if (@($ex0.WalkFailures).Count) { Fail 'A-EP-R13-WALK' (@($ex0.WalkFailures) -join '; ') }
  if (@($ex0.ReraiseFailures).Count)    { Fail 'A-EP-R10-RERAISE' (@($ex0.ReraiseFailures) -join '; ') }
}

Note 'exception-paths negatives and stale source ...'
# N20: a field is not a routine, and the refusal names the kind and the verb's selection.
NegTest 'EP-N20' 'is a field, not a method or procedure or function or constructor or destructor -- exception-paths selects a routine' 'excpaths_MSCTYPES_RChartSampleData_R' {
  & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'MSCTYPES.RChartSampleData.R' -DbPath $DbCli -OutDir $negDir }
# N21: a MANUFACTURED stale source (R4) -- a copy with one trailing blank on line
# 1, handed over through -SourceOverride. Nothing writes to a database, and the
# check does not depend on uMain.ViewModel.pas happening to differ on disk.
Step 'EP-N21' {
  $stDir = Join-Path $OutDir 'ep-stale'
  New-Item -ItemType Directory -Force $stDir | Out-Null
  $mk = { param($src, $dst) $l = [IO.File]::ReadAllLines($src); $l[0] = $l[0] + ' '
          [IO.File]::WriteAllText($dst, (($l -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding)) }
  $vm = 'C:\Projects\DB\ORM3\CLIENT\uMain.ViewModel.pas'
  & $mk $vm (Join-Path $stDir 'uMain.ViewModel.pas')
  $script:ep21 = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'uMain.ViewModel.TMainViewModel.LoadFolders' -DbPath $DbCli -OutDir $stDir `
                   -SourceOverride @{ $vm = (Join-Path $stDir 'uMain.ViewModel.pas') }
  Chk 'A-EP-N21-FRESH'  $ep21.FocusFresh $false
  Chk 'A-EP-N21-CLASS'  "$($ep21.Raises)/$($ep21.Handles)/$($ep21.Inferred)/$($ep21.Dropped)" '0/0/0/0'
  if ((Dot $ep21) -notmatch '\[stale source\]') { Fail 'A-EP-N21-MARK' 'the stale focus is not marked [stale source]' }
  # the same mechanism on a body that HAS exception rows, so "every row reads
  # [stale source]" is asserted on rows that would otherwise be classified
  $gf = 'C:\Projects\DB\ORM3\CLIENT\Gagefrm2.pas'
  & $mk $gf (Join-Path $stDir 'Gagefrm2.pas')
  $script:ep21b = & "$SRC\Emit-ExceptionPaths.ps1" -Qname 'Gagefrm2.TfrmGageport2.Configure_ComPort' -DbPath $DbCli -OutDir $stDir `
                    -SourceOverride @{ $gf = (Join-Path $stDir 'Gagefrm2.pas') }
  Chk 'A-EP-N21B-CLASS' "$($ep21b.Raises)/$($ep21b.Handles)/$($ep21b.Inferred)/$($ep21b.Dropped)" '0/0/0/0'
  Chk 'A-EP-N21B-STALE' $ep21b.StaleRows 5
  $labels = @([regex]::Matches((Dot $ep21b), '(?i)HREF="[^"]*Gagefrm2\.pas[^"]*" TITLE="[^"]*"><FONT COLOR="[^"]*">([^<]*)</FONT>') |
              ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne 'Gagefrm2' })
  Chk 'A-EP-N21B-ROWS'  $labels.Count 5
  if (@($labels | Where-Object { $_ -notmatch '\[stale source\]$' }).Count) {
    Fail 'A-EP-N21B-ROWS' "a row of the stale file was not marked [stale source]: $($labels -join '; ')" }
}
# N22: the source-only rows are DASHED ([inferred] clusters) and the one ref-anchored
# handler is solid. 1 solid + 5 dashed, not the plan's 1 + 2 -- see A-EP4-INFERRED.
Step 'EP-N22' {
  $t22 = Dot $ep4
  $solid = [regex]::Match($t22, '(?s)subgraph cluster_handlers_\d+ \{\s*style="rounded,filled";.*?\n  \}')
  $dash  = @([regex]::Matches($t22, '(?s)subgraph cluster_inferred(raises|handlers)_\d+ \{\s*style="rounded,filled,dashed";.*?\n  \}'))
  if (-not $solid.Success) { Fail 'A-EP-N22-SOLID' 'no solid HANDLERS IN BODY cluster' }
  else { Chk 'A-EP-N22-SOLID' ([regex]::Matches($solid.Value, 'HREF=')).Count 1 }
  Chk 'A-EP-N22-DASHED' (($dash | ForEach-Object { ([regex]::Matches($_.Value, 'HREF=')).Count } | Measure-Object -Sum).Sum) 5
  if ($t22 -notmatch 'compiler directives not evaluated') { Fail 'A-EP-N22-NOTE' 'the [inferred] rows do not carry the directive note' }
}
# N23: the `is`-test at :1695 and the cast at :1696 are neither raise nor handle rows.
Step 'EP-N23' {
  $t23 = Dot $ep2
  if (HasLine $t23 1695) { Fail 'A-EP-N23' 'the is-test at :1695 was drawn' }
  if (HasLine $t23 1696) { Fail 'A-EP-N23' 'the cast at :1696 was drawn' }
}

# ---- PLAN-last-four-verbs, Task 2: consumers ---------------------------------------
# Two indexes per run: a Delphi project clone (-DbPath) and the SQL-SCRIPT clone
# (-SqlDbPath). Every number measured 2026-09-23 and PINNED (R5); where a pin
# differs from the plan, the comment names the mechanism (R6). Gate codes carry
# a CO- prefix: N20-N24 were already taken by earlier emitters.
Note 'consumers ...'
Step 'E-CO' {
  # the body-end scanner on SYNTHETIC lines (a manufactured .SQL copy is always
  # stale and never scanned, so the Task 0 review's "stop at the next CREATE"
  # can only be shown on text): trigger A lost its terminator and must NOT run
  # on into B; B ends at its own `END^`; SET TERM state is read from above.
  $script:co0 = & {
    . "$SRC\Emit-Common.ps1"
    $syn = [string[]]@('SET TERM ^ ;', 'CREATE TRIGGER A FOR T', 'AS BEGIN', '  NEW.X = 1;', 'END', '',
                       'CREATE TRIGGER B FOR U', 'AS BEGIN NEW.Y = 2;', 'END^', 'SET TERM ; ^', 'CREATE TABLE Z (ID INTEGER);')
    $a = Find-SqlBodyEnd $syn 2 '^'
    $b = Find-SqlBodyEnd $syn 7 '^'
    # item 6: a consumers key is a routine id (> 0) or -file id (< 0, one
    # "(unit level)" row per UNIT). No clone holds a unit-level SQL literal
    # (measured: 0 on all eight), so the split is checked on SYNTHETIC keys:
    # routine 5 by fact AND literal is ONE routine; -3 is one unit, however many
    # literals it holds (the old counter counted hits).
    $mk = Measure-ConsumerKeys @(5) @(5, 7, -3, -3)
    $mk0 = Measure-ConsumerKeys @() @()
    [pscustomobject]@{ A = "$($a.Found):$($a.EndLine)"; AReason = $a.Reason; B = "$($b.Found):$($b.EndLine)"
                       Term = "$(Get-SqlTermAt $syn 7)$(Get-SqlTermAt $syn 11)"
                       Keys = "$($mk.Routines)/$($mk.Units) $($mk0.Routines)/$($mk0.Units)" }
  }
  Chk 'A-CO0-KEYS'      $co0.Keys '2/1 0/0'
  Chk 'A-CO0-BODYEND-A' $co0.A 'False:0'
  if ($co0.AReason -notlike '*next statement at line 7*') { Fail 'A-CO0-BODYEND-A' "reason: $($co0.AReason)" }
  Chk 'A-CO0-BODYEND-B' $co0.B 'True:9'
  Chk 'A-CO0-TERM'      $co0.Term '^;'

  $script:co1 = & "$SRC\Emit-Consumers.ps1" -Table 'CAUSFAIL' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-CO1-CERT-W'    $co1.CertainWriters 1
  Chk 'A-CO1-CERT-WN'   $co1.CertainWriterNames 'uCAUSFAIL_SERVER.TDataService_CAUSFAIL_SERVER.PrepareSaveQuery'
  # RE-BASELINED at 1.19 (engine D18 fixed; R25). On 1.18 PrepareLoadQuery was the
  # one INFERRED reader: `SQL.Add('FROM CAUSFAIL')` at uCAUSFAIL_SERVER.PAS:110
  # with no sql_reads fact (P22). 1.19 assembles SQL across SQL.Add lines, so its
  # fact now reads `CAUSFAIL` and it is a [certain] reader: 0/1 -> 1/0. The
  # inferred-reader path stays covered on REAL data by FOLDERS (A-CO4-ROWS,
  # A-CO4-DASHED), which D18 does not reach. PrepareSaveQuery's `UPDATE OR INSERT
  # INTO CAUSFAIL` is a WRITE literal and is already certain: no inferred writer.
  Chk 'A-CO1-CERT-R'    $co1.CertainReaders 1
  Chk 'A-CO1-INF-R'     $co1.InferredReaders 0
  Chk 'A-CO1-INF-RN'    $co1.InferredReaderNames ''
  Chk 'A-CO1-INF-W'     $co1.InferredWriters 0
  Chk 'A-CO1-TRIG'      $co1.TriggerNames 'CAUSFAIL_BIU0@MS6.SQL:34,CAUSFAIL_BIU5@MS5.SQL:15,CAUSFAIL_BUD0@MS6.SQL:44'
  # the procedure scanner (R2) converged: 168/168 bodies; two of them name CAUSFAIL
  Chk 'A-CO1-PROCS'     "$($co1.ProcBodies) $($co1.ProcedureNames)" '168/168 SP_GET_CAUSFAIL_ID,SP_MAXID_FORALL_TABLES'
  Chk 'A-CO1-INDEXES'   $co1.Indexes 0
  # on SERVER the [by name] half is the log-context / generator literals
  # (TLogContext.ForDB('CAUSFAIL', ...)), none inside a routine already drawn
  Chk 'A-CO1-BYNAME-SRV' $co1.ByNameLines 'uCAUSFAIL_SERVER:71+134+188+211+252+283'
  Chk 'A-CO1-CLICK'     "$($co1.ClickTargets)/$($co1.Expected)" '9/9'
  # item 6: the header pair counts ROUTINES; unit-level rows are counted per unit, apart
  Chk 'A-CO1-HEADER'    "$($co1.Readers)/$($co1.Writers)/$($co1.ReaderUnits)/$($co1.WriterUnits)/$($co1.UnitLevelUnits)" '1/1/0/0/0'
  $tc1 = Dot $co1
  # R15 (item 7): [by name] is a neutral "mentions (not SQL)" cluster -- never on
  # the readers side, and NO arrow from any of its rows into the focus
  $bnm = [regex]::Match($tc1, 'subgraph cluster_byname_(\d+) \{')
  if (-not $bnm.Success) { Fail 'A-CO1-R15' 'the [by name] cluster is missing' }
  else {
    $bn = "n$($bnm.Groups[1].Value)"
    if ($tc1 -match "$bn`:p\d+ -> focus") { Fail 'A-CO1-R15' 'a [by name] row still has a read arrow into the focus' }
    if ($tc1 -notmatch "focus -> $bn \[[^\]]*style=`"dotted`", arrowhead=none, label=`" mentions `"") { Fail 'A-CO1-R15' 'the neutral dotted "mentions" line is missing' }
    if ($tc1 -notmatch 'mentions \(not SQL\) \[by name\] -- a literal equal to CAUSFAIL') { Fail 'A-CO1-R15' 'the cluster is not titled "mentions (not SQL)"' }
    if ($tc1 -notmatch "rank=same; focus;[^}]*\b$bn\b") { Fail 'A-CO1-R15' 'the mentions cluster is not in the focus rank (neither readers nor writers side)' }
  }
  if ($tc1 -notmatch 'declared 2 times in the scripts; showing the newest \(MS1\.SQL:1408') { Fail 'A-CO1-DECL' 'the collapse sentence is missing' }
  if ($tc1 -notmatch '\[certain\] by fact: 1 reader\(s\) / 1 writer\(s\); \[inferred\] by SQL literal: 0 reader\(s\) / 0 writer\(s\)') { Fail 'A-CO1-R7' 'both grades are not on the focus box (R7)' }
  # silent where the premise is gone: no inferred-readers cluster on CAUSFAIL now
  if ($tc1 -match 'cluster_infreads_\d+') { Fail 'A-CO1-DASHED' 'an inferred-readers cluster is drawn on CAUSFAIL, whose one literal reader is now certain' }
  if ($tc1 -notmatch 'script-derived schema: 135 tables; 5 live tables are not in the scripts') { Fail 'A-CO1-SCHEMA' 'the script-derived disclosure is missing' }
  # 1.19 re-baseline (D19 fixed): the table form no longer claims the engine gap
  if ($tc1 -match 'quoted column name is not extracted') { Fail 'A-CO1-D19' 'the table form still claims a quoted column name is not extracted' }
  if (-not (HasLine $tc1 110)) { Fail 'A-CO1-HREF' 'PrepareLoadQuery is not anchored on its FROM CAUSFAIL literal (:110)' }
  if (-not (HasLine $tc1 123)) { Fail 'A-CO1-HREF' 'PrepareSaveQuery is not anchored on its INSERT INTO literal (:123)' }

  # index-wide (P21/P22): 112 / 148 / 250 facts; 104 tables read by fact. Was
  # 19 / 148 / 157 and 14 on the 1.18 clone: engine D18 gave sql_reads to 93
  # routines with no fact before (all DataService PrepareLoadQuery); no existing
  # read or write fact changed. The literal side (791 / 133) did not move.
  # 791, NOT the plan's 782: the count here is every literal/format string holding
  # an upper-case SELECT/INSERT/UPDATE/DELETE/FROM/JOIN/INTO/EXECUTE as a word. The
  # plan recorded no query; no variant tried (statement verbs only 603, verb +
  # following token 643, case-insensitive 952, verb+name 614) gives 782, and the
  # 133 FROM/JOIN tables and (1.18's) 14 fact tables DO reproduce -- so the
  # population definition, not the data, differs.
  Chk 'A-CO-IDX'        "$($co1.IndexReadFacts)/$($co1.IndexWriteFacts)/$($co1.IndexFactSymbols)" '112/148/250'
  Chk 'A-CO-LITS'       "$($co1.IndexVerbLiterals)/$($co1.IndexFromJoinTables)/$($co1.IndexFactReadTables)" '791/133/104'

  $script:co2 = & "$SRC\Emit-Consumers.ps1" -Column 'CAUSFAIL.REASON' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-CO2-SRV'       $co2.ServerRoutineNames 'uCAUSFAIL_SERVER.TDataService_CAUSFAIL_SERVER.PrepareLoadQuery,uCAUSFAIL_SERVER.TDataService_CAUSFAIL_SERVER.PrepareSaveQuery'
  Chk 'A-CO2-TRIG'      $co2.ColumnTriggerNames 'CAUSFAIL_BIU5'
  $script:co2c = & "$SRC\Emit-Consumers.ps1" -Column 'CAUSFAIL.REASON' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $OutDir
  # 7 REASON bindings index-wide; each chain resolves (one-table), and only the
  # one on dsrCausFail lands on CAUSFAIL -- the other 6 are CHIPFORM, ENDPROC x2,
  # STOPREAS, SURFFIN, TLLWEAR, counted and never drawn (P34)
  Chk 'A-CO2-BIND'      "$($co2c.IndexBindings)/$($co2c.DrawnBindings)" '7/1'
  Chk 'A-CO2-BINDROW'   $co2c.DrawnBindingRows 'uCausFailForm.dfm:60:colREASON'
  Chk 'A-CO2-BINDELSE'  "$($co2c.BindingsElsewhere)/$($co2c.BindingsUnresolved)" '6/0'

  $script:co3 = & "$SRC\Emit-Consumers.ps1" -Column 'DRA1.FLDRID' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-CO3-SRV'       $co3.ServerRoutineNames 'uDRA1_SERVER.TDataService_DRA1_SERVER.PrepareLoadQuery,uDRA1_SERVER.TDataService_DRA1_SERVER.PrepareSaveQuery,uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation'

  $script:co4 = & "$SRC\Emit-Consumers.ps1" -Table 'FOLDERS' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-CO4-DECL'      "$($co4.Declarations)/$($co4.Columns)" '2/79'
  Chk 'A-CO4-ROWS'      "$($co4.CertainReaders)/$($co4.CertainWriters)/$($co4.InferredReaders)/$($co4.InferredWriters)/$($co4.Triggers)/$($co4.Procedures)/$($co4.Indexes)" '1/2/3/0/3/1/2'
  if ((Dot $co4) -notmatch 'declared 2 times in the scripts; showing the newest') { Fail 'A-CO4-DECL' 'the collapse sentence is missing' }
  # The inferred-reader path on REAL data after D18 (R25; moved here from A-CO1):
  # FOLDERS' 3 literal-only readers are TDataService_FOLDERS_SERVER.PrepareLoadQuery
  # (its column list goes through `SQL.Add(sTmp)`, a VARIABLE, which D18's fix
  # does not assemble -- 38 of the 40 DataService PrepareLoadQuery still without
  # a read fact have that shape), HandleCreateFolder and HandlePrePlanPreset.
  Chk 'A-CO4-INF-RN'    $co4.InferredReaderNames 'uFOLDERS_SERVER.TDataService_FOLDERS_SERVER.PrepareLoadQuery,uPipeSessionBuilder.TPipeSessionBuilder.HandleCreateFolder,uPipeSessionBuilder.TPipeSessionBuilder.HandlePrePlanPreset'
  if ((Dot $co4) -notmatch 'cluster_infreads_\d+ \{\s*style="rounded,filled,dashed"') { Fail 'A-CO4-DASHED' 'the inferred readers are not dashed' }

  # THE KNOWN GAP (Get-SqlTableSet): IPCHART.ACTION is live and EXTRACTED only
  # from the older MScript2.SQL declaration. RE-PINNED in the final wave (items
  # 1-2), older -> quoted: the newest MS1.SQL DOES declare it, at :2243, as the
  # quoted identifier "ACTION", which the SQL extractor drops (engine D19). The
  # old label "the newest has 136 columns without it" was false. The shared
  # Get-SqlColumnState tries quoted BEFORE older, so the column is anchored on
  # the newest declaration and the older extraction is named beside it.
  # RE-BASELINED at 1.19 (engine D19 fixed; R25): MS1.SQL's "ACTION" is now
  # EXTRACTED (newest IPCHART 136 -> 137 columns, matching live Firebird), so the
  # state is `yes`, [certain], and no quoted / older wording may appear. The line
  # is the engine's sql_column start, 2242 -- ONE LINE EARLY, as for every
  # extracted column (A-LW1-HREF pins REASON at 1410; it is declared on 1411):
  # the node starts after the previous token. An ENGINE defect (SQL extractor),
  # pre-existing and identical on the 1.18 clone, filed as
  # C:\Projects\Delphi-RAG-lint\docs\INBOX-sql-column-start-line-one-early.md. When the engine
  # fixes it, this pin (2242), A-CO-QUOTED / A-LW-N31-QUOTED (3847) and
  # A-LW1-HREF (1410) each move by +1 -- that move is the fix, not a regression.
  $script:co5 = & "$SRC\Emit-Consumers.ps1" -Column 'IPCHART.ACTION' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-CO5-OLDER'     "$($co5.ColumnState):$($co5.ColumnLine):$($co5.ColumnOlderOnly)" 'yes:MS1.SQL:2242:False'
  $tc5 = Dot $co5
  if ($tc5 -notmatch '\[certain\] a column of the newest of 2 declaration\(s\), MS1\.SQL') { Fail 'A-CO5-OLDER' 'the [certain] column label is missing' }
  if ($tc5 -match 'QUOTED|extracts it unquoted') { Fail 'A-CO5-OLDER' 'the quoted / older-copy wording still fires on an extracted column' }
  if ($tc5 -match 'columns without it') { Fail 'A-CO5-OLDER' 'the false "the newest has N columns without it" is back' }

  # item 1: a QUOTED column consumers used to REFUSE ("no column TABLE in
  # FOLDERCOUNT") while lands-where anchored it -- now the same state, same line.
  # RE-BASELINED at 1.19 (D19 fixed): an ordinary extracted column, `yes`, at the
  # engine's sql_column line 3847 -- an ENGINE defect, one line early (declared on
  # 3848; INBOX-sql-column-start-line-one-early.md, see A-CO5-OLDER): moves to 3848 when fixed.
  $script:coq = & "$SRC\Emit-Consumers.ps1" -Column 'FOLDERCOUNT.TABLE' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-CO-QUOTED'     "$($coq.ColumnState):$($coq.ColumnLine):$($coq.ServerRoutines)" 'yes:MS1.SQL:3847:2'
  if (-not (HasLine (Dot $coq) 3847)) { Fail 'A-CO-QUOTED' 'the focus is not anchored on the extracted column (MS1.SQL:3847)' }
  if ((Dot $coq) -match 'QUOTED') { Fail 'A-CO-QUOTED' 'the quoted wording still fires on an extracted column' }

  # R25: the QUOTED state has no real input left, so it is driven on a HAND-MADE
  # table set -- the real one with the column taken back out of the newest
  # declaration's extracted names. The source is the real, FRESH MS1.SQL, so the
  # scan runs and must find `"TABLE"` on :3848 and `"ACTION"` on :2243; ACTION
  # also gets its old MScript2 extraction back as an older-only column, which is
  # exactly the 1.18 shape (quoted is tried BEFORE older).
  $script:cqs = & {
    $Engine = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
    . "$SRC\Emit-Common.ps1"
    $real = Get-SqlTableSet $DbSql
    $ip = $real.Tables['IPCHART']
    $ipOld = @($ip.Declarations | Where-Object { $_.File -notlike '*MS1.SQL' })[0]
    # the SAME helpers the emitters' -TestHideColumn hook uses (Emit-Common)
    $fake = Hide-ExtractedColumns $real @('FOLDERCOUNT.TABLE')
    $fake.Tables['IPCHART'] = Copy-SqlTableWithout $ip 'ACTION' ([pscustomobject]@{ Column = 'ACTION'; File = $ipOld.File; Line = $ipOld.Line })
    $q1 = Get-SqlColumnState $fake 'FOLDERCOUNT' 'TABLE' $null $null ''
    $q2 = Get-SqlColumnState $fake 'IPCHART' 'ACTION' $null $null ''
    # the cached real set is untouched by the hide
    $untouched = $real.Tables['FOLDERCOUNT'].Columns.Contains('TABLE') -and $real.Tables['IPCHART'].Columns.Contains('ACTION')
    [pscustomobject]@{ Q1 = "$($q1.State):$([IO.Path]::GetFileName($q1.File)):$($q1.Line):$($q1.QuotedScan)"; L1 = $q1.Label
                       Q2 = "$($q2.State):$([IO.Path]::GetFileName($q2.File)):$($q2.Line)"; L2 = $q2.Label
                       Untouched = $untouched
                       # feeds-from's column-hop label (no real chain can end on a quoted column)
                       Hop = "$(Get-ColumnHopLabel $q1) / $(Get-ColumnHopLabel ([pscustomobject]@{ State = 'yes'; Column = 'REASON' }))" }
  }
  Chk 'A-COLSTATE-QUOTED' "$($cqs.Q1) $($cqs.Q2) $($cqs.Untouched)" 'quoted:MS1.SQL:3848:hit quoted:MS1.SQL:2243 True'
  # FIX ROUND 1 (item 11): the label no longer says the index "does not extract a
  # quoted name" -- false as a general statement since 1.19 -- only that THIS one
  # was not extracted
  if ($cqs.L1 -ne '[inferred -- source scan] a QUOTED identifier in the newest declaration (MS1.SQL:3848) that the SQL index did not extract as a column') {
    Fail 'A-COLSTATE-QUOTED' "the quoted label moved: $($cqs.L1)" }
  if ($cqs.L2 -ne '[inferred -- source scan] a QUOTED identifier in the newest declaration (MS1.SQL:2243) that the SQL index did not extract as a column; an older declaration (MScript2.SQL:1902) extracts it unquoted') {
    Fail 'A-COLSTATE-QUOTED' "the quoted-plus-older label moved: $($cqs.L2)" }
  Chk 'A-FF-QUOTED' $cqs.Hop 'column "TABLE" / column REASON'
  # The quoted state RENDERED through the emitters (fix round 1, item 7). A doctored
  # scratch .SQL cannot drive it -- it is stale by construction and renders
  # [stale source] (A-LW-STALE-Q) -- so -TestHideColumn takes FOLDERCOUNT.TABLE back
  # out of the extracted set and the REAL, fresh MS1.SQL is scanned.
  $script:coqh = & "$SRC\Emit-Consumers.ps1" -Column 'FOLDERCOUNT.TABLE' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir (Join-Path $OutDir 'co-quoted') -TestHideColumn 'FOLDERCOUNT.TABLE'
  Chk 'A-CO-QUOTED-RENDER' "$($coqh.ColumnState):$($coqh.ColumnLine):$($coqh.ServerRoutines)" 'quoted:MS1.SQL:3848:2'
  Chk 'A-CO-QUOTED-STAMP'  "$($coqh.TestChart)/$($coq.TestChart)" 'True/False'
  $tqh = Dot $coqh
  if (-not (HasLine $tqh 3848)) { Fail 'A-CO-QUOTED-RENDER' 'the quoted column is not anchored on its scanned line MS1.SQL:3848' }
  if ($tqh -notmatch [regex]::Escape('column state quoted: [inferred -- source scan] a QUOTED identifier in the newest declaration (MS1.SQL:3848) that the SQL index did not extract as a column')) {
    Fail 'A-CO-QUOTED-RENDER' 'the quoted column state is not rendered on the focus box' }
  if ($tqh -notmatch 'TEST CHART: FOLDERCOUNT\.TABLE taken OUT') { Fail 'A-CO-QUOTED-RENDER' 'a hook-driven chart does not say TEST CHART' }
  # ... and a column in NO script declaration that this index's own SQL names
  # (STATIONS.GRIDS: uSTATIONS_SERVER.PAS:110 reads it, :129 writes it)
  $script:cog = & "$SRC\Emit-Consumers.ps1" -Column 'STATIONS.GRIDS' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-CO-SRVSQL'     "$($cog.ColumnState):$($cog.ColumnLine):$($cog.ServerRoutines)" 'server-sql:uSTATIONS_SERVER.PAS:110:2'
  if ((Dot $cog) -notmatch 'not extracted as a column by the SQL index \(23 columns extracted from the newest of 2 declaration\(s\), MS1\.SQL:3495\)') {
    Fail 'A-CO-SRVSQL' 'the server-sql label does not say what was read' }
  if ((Dot $cog) -match 'NOT in the SQL scripts') { Fail 'A-CO-SRVSQL' 'the old "NOT in the SQL scripts" absence claim is back' }

  # item 6 through the bundler: the header pair is ROUTINES, and says so
  $artRoot = Join-Path $OutDir 'bundle-co'
  $art = & "$SRC\New-DiagramArtifact.ps1" -Question consumers -Target 'CAUSFAIL' -DbPath $DbSrv -SqlDbPath $DbSql -OutRoot $artRoot
  $meta = Get-Content (Join-Path $art.Bundle 'meta.json') -Raw | ConvertFrom-Json
  Chk 'A-CO-ART'        "$($meta.leftCount) $($meta.leftLabel) / $($meta.rightCount) $($meta.rightLabel)" '1 reading routines / 1 writing routines'
  # the TestChart stamp reaches meta.json both ways (fix round 2): top-level and in the emitter's counts
  Chk 'A-CO-ART-STAMP'  "$($meta.testChart)/$($meta.emitter.TestChart)" 'False/False'
}

Note 'consumers negatives and draws ...'
# N24: OPERATION is in the scripts (dropped live) -- it RENDERS; absence from the
# live schema is a human validation step the emitter cannot make.
Step 'CO-N24' {
  $script:co24 = & "$SRC\Emit-Consumers.ps1" -Table 'OPERATION' -SqlDbPath $DbSql -DbPath $DbSrv -OutDir $OutDir
  $t24 = Dot $co24
  if ($t24 -notmatch 'declared 1 time in the scripts \(MScript2\.SQL') { Fail 'A-CO-N24' 'no "declared 1 time" on the focus box' }
  if ($t24 -notmatch 'script-derived schema') { Fail 'A-CO-N24' 'no script-derived sentence' }
}
NegTest 'CO-N25' 'no table PDF_SCAN in the SQL index (script-derived; the scripts may lag the live schema) -- nearest: PDF1' 'consumers_PDF_SCAN' {
  & "$SRC\Emit-Consumers.ps1" -Table 'PDF_SCAN' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $negDir }
# RE-WORDED in the final wave (items 1-2): a refusal says what was READ -- not
# extracted, not quoted in the newest declaration, not named by this index's SQL
NegTest 'CO-N26' 'no column NOPE in FOLDERS: not extracted as a column by the SQL index (79 columns extracted from the newest of 2 declaration(s), MS1.SQL:1834); nor a quoted identifier in that declaration; no SQL for FOLDERS in SERVER-MicroniteMW1Service.sqlite names it' 'consumers_FOLDERS_NOPE' {
  & "$SRC\Emit-Consumers.ps1" -Column 'FOLDERS.NOPE' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $negDir }
# the same real column CLIENT cannot see: CLIENT holds no SQL for STATIONS, so it
# refuses -- and names the index it searched, not "the scripts"
NegTest 'CO-N26b' 'no SQL for STATIONS in CLIENT-Micronite2027.sqlite names it' 'consumers_STATIONS_GRIDS' {
  & "$SRC\Emit-Consumers.ps1" -Column 'STATIONS.GRIDS' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $negDir }
# N27: CLIENT has no facts but DOES have text -- the [by name] half renders
Step 'CO-N27' {
  $script:co27 = & "$SRC\Emit-Consumers.ps1" -Table 'CAUSFAIL' -DbPath $DbCli -SqlDbPath $DbSql -OutDir (Join-Path $OutDir 'cli')
  Chk 'A-CO1-CLIENT'    "$($co27.ByNameUnits) $($co27.ByNameLines)" '1 uCausFail.ViewModel:37+258+259'
  Chk 'A-CO-N27-FACTS'  $co27.NoSqlFacts $true
  if ((Dot $co27) -notmatch 'this index has no SQL facts') { Fail 'A-CO-N27' 'the fact half does not say "this index has no SQL facts"' }
  if (-not (Test-Path $co27.Svg)) { Fail 'A-CO-N27' 'no .svg for the CLIENT render' }
  # item 8: the [by name] match is EXACT; a literal equal to the table only
  # case-insensitively is COUNTED and named, not drawn -- FOLDERS' one is 'Folders',
  # a ribbon tab caption (uJobList.pas:552). This run also needs the PAGED routine
  # query: uJobList.pas holds more than 200 routines (it stopped at the row cap).
  $script:cof = & "$SRC\Emit-Consumers.ps1" -Table 'FOLDERS' -DbPath $DbCli -SqlDbPath $DbSql -OutDir (Join-Path $OutDir 'cli')
  Chk 'A-CO-CASE'       "$($cof.ByNameCaseOnly) | $($cof.ByNameLines)" "'Folders' uJobList.pas:552 | Blueprint4:815,Blueprint4.ViewModel:1221,uJobList:439,uJobList.ViewModel:288,uSetupDefaultsFrm:2413+2427,uFieldsInfoCache:158"
  if ((Dot $cof) -notmatch "1 literal\(s\) equal FOLDERS only case-insensitively, not drawn: 'Folders' uJobList\.pas:552") { Fail 'A-CO-CASE' 'the case-only literal is not disclosed' }
}
NegTest 'CO-N34' 'is not a SQL index (0 sql_table symbols)' 'consumers_CAUSFAIL' {
  & "$SRC\Emit-Consumers.ps1" -Table 'CAUSFAIL' -DbPath $DbSrv -SqlDbPath $DbCli -OutDir $negDir }
# R11 on the SQL side: a MANUFACTURED stale MS5.SQL (one trailing blank, via
# -SourceOverride). Its trigger renders [stale source] and its procedure bodies
# are not scanned -- the two CAUSFAIL-named procedures fall back to name-only rows.
Step 'CO-STALE' {
  $stDir = Join-Path $OutDir 'co-stale'
  New-Item -ItemType Directory -Force $stDir | Out-Null
  $ms5 = 'C:\Projects\DB\SQL\MS5.SQL'
  $l = [IO.File]::ReadAllLines($ms5); $l[0] = $l[0] + ' '
  [IO.File]::WriteAllText((Join-Path $stDir 'MS5.SQL'), (($l -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $script:cost = & "$SRC\Emit-Consumers.ps1" -Table 'CAUSFAIL' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $stDir `
                   -SourceOverride @{ $ms5 = (Join-Path $stDir 'MS5.SQL') }
  # 77 MS5 procedure declarations are not scanned: 168 - 77 = 91
  Chk 'A-CO-STALE-PROCS' "$($cost.ProcBodies)/$($cost.Procedures)/$($cost.ProcsUnscanned)" '91/168/0/2'
  $ts = Dot $cost
  if ($ts -notmatch 'CAUSFAIL_BIU5</FONT>\s*<FONT[^>]*>:15</FONT>\s*<FONT[^>]*>&#183; \[stale source\]') { Fail 'A-CO-STALE-TRIG' 'CAUSFAIL_BIU5 (MS5.SQL) is not marked [stale source]' }
  if ($ts -notmatch '77 of 168 procedure bodies not scanned') { Fail 'A-CO-STALE-NOTE' 'the unscanned-procedure disclosure is missing' }
}
# item 4: the COLUMN form over the same manufactured stale MS5.SQL. CAUSFAIL_BIU5
# (MS5.SQL:15) is the one trigger that uses REASON (A-CO2-TRIG); unread, it has no
# Columns, and the old column form dropped it without a word. Now it is counted,
# named and said; the unscanned procedures are said too. Own scratch path: the
# freshness cache is keyed per read path.
Step 'CO-STALE-COL' {
  $stDir = Join-Path $OutDir 'co-stale-col'
  New-Item -ItemType Directory -Force $stDir | Out-Null
  $ms5 = 'C:\Projects\DB\SQL\MS5.SQL'
  $l = [IO.File]::ReadAllLines($ms5); $l[0] = $l[0] + ' '
  [IO.File]::WriteAllText((Join-Path $stDir 'MS5.SQL'), (($l -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $script:costc = & "$SRC\Emit-Consumers.ps1" -Column 'CAUSFAIL.REASON' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $stDir `
                    -SourceOverride @{ $ms5 = (Join-Path $stDir 'MS5.SQL') }
  Chk 'A-CO-STALE-COL'  "$($costc.ColumnTriggers)/$($costc.ColumnTriggersStale)/$($costc.ColumnTriggersNoBody)" '0/1/0'
  $tsc = Dot $costc
  if ($tsc -notmatch '1 trigger\(s\) FOR CAUSFAIL in a script that differs from the index \[stale source\] -- not scanned for REASON: CAUSFAIL_BIU5@MS5\.SQL:15') {
    Fail 'A-CO-STALE-COL' 'the stale trigger is dropped from the column form without a word' }
  if ($tsc -notmatch '77 of 168 procedure bodies not scanned') { Fail 'A-CO-STALE-COL' 'the column form does not say which procedure bodies were not scanned' }
}
# ---- PLAN-last-four-verbs, Task 3: feeds-from --------------------------------------
# CLIENT (-DbPath) + the SQL-SCRIPT clone (-SqlDbPath). Every number measured
# 2026-09-23 and PINNED (R5); where a pin differs from the plan the comment names
# the mechanism (R6). Gate codes carry an FF- prefix: N20-N24 were taken.
Note 'feeds-from: the three routed chain fixes ...'
Step 'E-FF0' {
  $script:ff0 = & "$SRC\Test-FeedsFromHelpers.ps1" -DbCli $DbCli -DbSql $DbSql
  # (a) a module prefix naming ANOTHER form's file is a name match, not a fact;
  # the same prefix naming the form's own file stays certain
  Chk 'A-FF0-FIXA'      $ff0.FixA 'datasource:by name'
  Chk 'A-FF0-FIXA-SELF' $ff0.FixASelf 'certain:CAUSFAIL'
  # (b) `_` is not a LIKE wildcard any more (5 literal cases, evaluated by SQLite)
  if (@($ff0.FixBFailures).Count) { Fail 'A-FF0-FIXB' (@($ff0.FixBFailures) -join '; ') }
  # (c) Self.edtX.DataBinding -> edtX; (VM as IFoo).MemTable -> a sentence, not ''
  if (@($ff0.FixC1Failures).Count) { Fail 'A-FF0-FIXC1' (@($ff0.FixC1Failures) -join '; ') }
  if (@($ff0.FixC2Failures).Count) { Fail 'A-FF0-FIXC2' (@($ff0.FixC2Failures) -join '; ') }
  # candidates in FIRST-LITERAL order -- the brief's "SERID, SERREAD, SERPART"
  Chk 'A-FF0-ORDER'     "$($ff0.PListOrder)@$($ff0.PListLines)" 'SERID,SERREAD,SERPART@76,310,311'
  # the shared control -> datasource rule reaches a grid column through its view
  Chk 'A-FF0-CTLDS'     $ff0.ColReasonDs 'dsrCausFail'
}

Note 'feeds-from ...'
Step 'E-FF' {
  $script:ff1 = & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmCausFail.colREASON' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-FF1-TABLE'     $ff1.TableColumn 'CAUSFAIL.REASON'
  Chk 'A-FF1-COLUMN'    $ff1.ColumnExists 'yes'
  # control, datasource, assignment, type, table.column
  Chk 'A-FF1-HOPS'      $ff1.ChainRows 5
  Chk 'A-FF1-GRADES'    $ff1.HopGrades 'certain>certain>certain>by name>inferred'
  Chk 'A-FF1-CLICK'     "$($ff1.ClickTargets)/$($ff1.Expected)" '7/7'
  $tf1 = Dot $ff1
  # colREASON FieldName (.dfm:60), dsrCausFail (.dfm:88), the assignment
  # (uCausFailForm.pas:125, FormActivate), the CAUSFAIL literal
  # (uCausFail.ViewModel.pas:37), the REASON column (MS1.SQL:1410)
  foreach ($ln in 60, 88, 125, 37, 1410) { if (-not (HasLine $tf1 $ln)) { Fail 'A-FF1-HREF' "no row anchored on line $ln" } }
  if ($tf1 -notmatch 'TfrmCausFail\.FormActivate') { Fail 'A-FF1-ROUTINE' 'the assignment row does not name FormActivate' }
  if ($tf1 -notmatch 'cluster_hop_\d+ \{\s*style="rounded,filled,dashed"') { Fail 'A-FF1-DASHED' 'no dashed hop' }

  # THE INDEX-WIDE ROWS. Per datasource, as Task 0 measured (54 / 5 / 49, NOT
  # the plan's 51: same-file DataSet matching, see A-FF0-DS).
  Chk 'A-FF0-DS-CHART'  "$($ff1.IndexDs)/$($ff1.IndexDsDfm)/$($ff1.IndexDsCode)" '54/5/49'
  Chk 'A-FF0-RES-CHART' "$($ff1.IndexDsOne)/$($ff1.IndexDsMany)/$($ff1.IndexDsNone)/$($ff1.IndexDsByCol)/$($ff1.IndexDsOther)" '22/17/9/6/6'
  # PER CONTROL (R9: measured, the 41% is NOT quoted). 808 DataBinding.FieldName
  # / DataField rows (the 34 plain FieldName rows are persistent TFields, not
  # controls). 267 resolve to one table = 33.0%, 254 to a column that table has:
  # LOWER than 41%, as R9 predicted, because the busy forms sit on the
  # unresolved datasources:
  #   dangling 426 -- Blueprint4_Model.* 226 (dsrFtrs 154, dsrOperation 50, ...),
  #                   ControlPlan_Model.* 171 (dsrFtrs 132, ...), dmlSystem2 29;
  #                   the brief's 65 counts the DataSource-bearing ROWS, this
  #                   counts every field-bound control under them
  #   stops 77     -- dfm-dataset 42, none 34 (interface-typed VMs), no-type 1
  #   ambiguous 37 -- CompGroup2 dsrFtrs 31, dsrPList 2, AssignGroups/Tools2 dsrFtrs 2+2
  #   not-column 13 -- all uJobList on FOLDERS (DueInStr, LotStatusC, *VerdictStr,
  #                   Status_*Str ...): memtable-computed fields, not DB columns
  #   no-ds 1      -- CADFNotes.dxDBEdit1, whose DataSource is set only in code
  Chk 'A-FF0-PERCTL'    "$($ff1.Controls):$($ff1.CtlTable)/$($ff1.CtlColumn)/$($ff1.CtlNotColumn)/$($ff1.CtlAmbiguous)/$($ff1.CtlStops)/$($ff1.CtlDangling)/$($ff1.CtlNoDs)/$($ff1.CtlStale)" '808:267/254/13/37/77/426/1/0'
  if ($tf1 -notmatch 'per control: 808 field-bound controls; 267 resolve to one table \(33%\)') { Fail 'A-FF0-PERCTL' 'the per-control coverage is not printed on the chart' }
  if ($tf1 -match '41 ?%') { Fail 'A-FF0-R9' 'the chart quotes the per-datasource 41%' }

  # P33 tie-break: 4 candidates in literal order, 6 bound columns, one survivor
  $script:ff2 = & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmMachineList.colMACHINEID' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-FF2-CANDS'     "$(@($ff2.Candidates -split ',').Count)/$($ff2.AfterTieBreak) ($($ff2.ResolvedTable))" '4/1 (MACHINES)'
  Chk 'A-FF2-ORDER'     "$($ff2.Candidates) bound=$($ff2.BoundColumns)" 'MACHINES,STATIONS,PLANT,DEPARTTBL bound=6'
  Chk 'A-FF2-TABLE'     $ff2.TableColumn 'MACHINES.MACHINEID'
  if ((Dot $ff2) -notmatch 'tie broken by 6 bound column') { Fail 'A-FF2-TIE' 'the tie-break is not stated' }

  # the interface-typed view model: the chain stops, exit 0, no table
  $script:ff4 = & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmBlueprintCADImport.grdBalsViewNUM' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-FF4-STOP'      "$($ff4.Grade):$([string]$ff4.ResolvedTable):$($ff4.HopGrades)" 'none::certain>certain>certain>by name>stop'
  if ((Dot $ff4) -notmatch 'chain stops here' -or (Dot $ff4) -notmatch 'interface-typed view-model\] .*IBlueprintCADImport_ViewModel') { Fail 'A-FF4-STOP' 'no interface-typed stop row' }
}

Note 'feeds-from negatives and draws ...'
NegTest 'FF-N28' 'feeds-from selects a data-aware CONTROL, not a datasource -- ask consumers/shown-where' 'feedsfrom_frmCausFail_dsrCausFail' {
  & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmCausFail.dsrCausFail' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $negDir }
# a persistent TField is not a control either
NegTest 'FF-N28b' 'is a persistent FIELD' 'feedsfrom_frmCompGroupSetup2_tblCompTreeName' {
  & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmCompGroupSetup2.tblCompTreeName' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $negDir }
NegTest 'FF-N34' 'is not a SQL index (0 sql_table symbols)' 'feedsfrom_frmCausFail_colREASON' {
  & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmCausFail.colREASON' -DbPath $DbCli -SqlDbPath $DbCli -OutDir $negDir }
# N29 (R8). The brief names the DFM module `Blueprint4_Model.dsrFolder`; the DFM
# actually says `dmlSystem2.dsrFolder` (Blueprint4.dfm:235) -- Blueprint4_Model
# is the prefix of the OTHER 27 dangling rows. Both are dangling; the line is
# what is asserted.
Step 'FF-N29' {
  $script:ff29 = & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmBlueprint4.edtF1' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $OutDir
  $t29 = Dot $ff29
  if ($t29 -notmatch '\[dangling\]') { Fail 'A-FF-N29' 'the DFM row does not read [dangling]' }
  if ($t29 -notmatch '\[re-pointed at TfrmBlueprint4\.RepointJobHeaderToFolder:1015\] edtF1\.DataBinding\.DataSource := DS') { Fail 'A-FF-N29' 'no [re-pointed at] row for Blueprint4.pas:1015' }
  if ($t29 -notmatch 'the DFM names dmlSystem2, which is not in this project') { Fail 'A-FF-N29' 'the dangling disclosure is missing' }
  # the DataField is ALSO re-bound in code (:1016) -- drawn, because the DFM
  # column is then not the runtime column
  Chk 'A-FF-N29-ROWS'   "$($ff29.Grade):$($ff29.RePointedAt):$($ff29.Rebound):$($ff29.HopGrades)" 'dangling:Blueprint4.pas:1015:1:certain>dangling>stop'
}
# N30: ambiguous after the tie-break -- exit 0, the candidates printed, NO TABLE.COLUMN
Step 'FF-N30' {
  $script:ff30 = & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmDefineSerialNumbers.cxGrid1DBTableView1SID1' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-FF3-AMBIG'     "$($ff30.AfterTieBreak):$($ff30.BoundColumns):$([string]$ff30.TableColumn)" '3:2:'
  $t30 = Dot $ff30
  if ($t30 -notmatch 'ambiguous: SERID, SERREAD, SERPART') { Fail 'A-FF-N30' 'no "ambiguous: SERID, SERREAD, SERPART"' }
  if ($t30 -match 'SER(ID|READ|PART)\.SID') { Fail 'A-FF-N30' 'a TABLE.COLUMN row was drawn for an ambiguous chain' }
  foreach ($ln in 76, 310, 311) { if (-not (HasLine $t30 $ln)) { Fail 'A-FF-N30' "candidate literal :$ln not anchored" } }
}
# R11: a MANUFACTURED stale uCausFailForm.pas (one trailing blank) -- the chain
# stops [stale source] and no table is drawn; the index-wide rows are recomputed
# against the same override (never cached), so the CausFail controls count stale.
Step 'FF-STALE' {
  $stDir = Join-Path $OutDir 'ff-stale'
  New-Item -ItemType Directory -Force $stDir | Out-Null
  $cfp = 'C:\Projects\DB\ORM3\CLIENT\uCausFailForm.pas'
  $l = [IO.File]::ReadAllLines($cfp); $l[125] = $l[125] + ' '
  [IO.File]::WriteAllText((Join-Path $stDir 'uCausFailForm.pas'), (($l -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $script:ffst = & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmCausFail.colREASON' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $stDir `
                   -SourceOverride @{ $cfp = (Join-Path $stDir 'uCausFailForm.pas') }
  Chk 'A-FF-STALE'      "$($ffst.Grade):$([string]$ffst.ResolvedTable):$($ffst.HopGrades)" 'stale source::certain>certain>stop'
  # colREASON + colSEVERITY... every field-bound control on dsrCausFail
  Chk 'A-FF-STALE-CTL'  $ffst.CtlStale 4
  if ((Dot $ffst) -notmatch 'chain stops here.*\[stale source\]') { Fail 'A-FF-STALE' 'no [stale source] stop row' }
}
# the verb through the bundler: dispatch, -SqlDbPath carried into meta.json
Step 'FF-ART' {
  $artRoot = Join-Path $OutDir 'bundle-ff'
  $art = & "$SRC\New-DiagramArtifact.ps1" -Question feeds-from -Target 'frmCausFail.colREASON' -DbPath $DbCli -SqlDbPath $DbSql -OutRoot $artRoot
  $meta = Get-Content (Join-Path $art.Bundle 'meta.json') -Raw | ConvertFrom-Json
  Chk 'A-FF-ART'        "$($meta.leftCount) $($meta.leftLabel) / $($meta.rightCount)" '5 chain rows / 267'
  if ($meta.regenerate -notmatch '-SqlDbPath ') { Fail 'A-FF-ART' 'the regenerate command drops -SqlDbPath' }
}
# ---- PLAN-last-four-verbs, Task 4: lands-where -------------------------------------
# THREE clones: CLIENT (-DbPath: ORM classes + DFM bindings), SERVER (-ServerDbPath:
# TDataService_<T>_SERVER) and the SQL scripts (-SqlDbPath). Every number measured
# 2026-09-23 and PINNED (R5); where a pin differs from the plan the comment names
# the mechanism (R6). Gate codes carry an LW- prefix: N20-N24 were taken.
Note 'lands-where ...'
Step 'E-LW' {
  # PATH B DETECTOR (plan section 7): orm_links is EXPECTED empty on both Delphi
  # clones. A non-zero here is the SIGNAL that fb-snapshot landed in a clone and
  # the switch must be built -- not a number to re-pin.
  # Emit-Common resolves $Engine from the CALLER's scope (its header), so the block names it
  $script:ol = & { $Engine = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'; . "$SRC\Emit-Common.ps1"; "$((Get-OrmLinksState $DbCli).Rows)/$((Get-OrmLinksState $DbSrv).Rows)" }
  Chk 'A-OL-ROWS'       $ol '0/0'

  $script:lw1 = & "$SRC\Emit-LandsWhere.ps1" -Field 'uCAUSFAIL.TmcCAUSFAIL.REASON' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  # P35, measured on this run and printed on the chart (R10). 1,992 (was 1,991 at
  # 1.18) = 1,992 extracted from the newest declarations: engine D19 (extractor
  # 1.19) now extracts the quoted MS1.SQL `"TABLE"` (FOLDERCOUNT) and `"ACTION"`
  # (IPCHART). ACTION already counted through the older MScript2.SQL copy (the R8
  # known gap), so only TABLE is new: +1.
  Chk 'A-LW0-CONV'      "$($lw1.ConvProps)/$($lw1.ConvOnTable)/$($lw1.ConvColumn)" '2063/1997/1992'
  # FINDING vs the plan's list: the non-columns were TmcFOLDERCOUNT.TABLE (not
  # TmcFOLDERS), INSPRSLT x3 and STATIONS x2. At 1.19 FOLDERCOUNT.TABLE is an
  # extracted column (D19), so 5 remain and none is quoted (R25: the quoted path
  # is driven synthetically by A-COLSTATE-QUOTED)
  # (+ stale=: none of the 5 was left unscanned -- a stale scan is named, never dropped; item 5)
  Chk 'A-LW0-NONCOL'    "$($lw1.ConvNonColumn) quoted=$($lw1.ConvQuoted) stale=$($lw1.ConvStale)" 'INSPRSLT.DistHist,INSPRSLT.DistHistLim,INSPRSLT.f_tb,STATIONS.GRIDS,STATIONS.MENUS quoted= stale='
  Chk 'A-LW0-DS'        $lw1.DsClasses 133
  # P37: 189 / 182 reproduce. The plan's 390 index-wide is 383 on the SERVER
  # clone (the index join and a raw regex over every indexed .pas agree: 383 in
  # 135 files); not reconciled with the plan, which recorded no query. All 189 in
  # a DataService routine are in Load (188) or FindOperatorName (1): Save binds
  # Params[i] positionally, so there is no "Save ParamByName" row.
  # 183 a column, was 182 at 1.18: ParamByName('TABLE') at uFOLDERCOUNT_SERVER.PAS:155
  # names FOLDERCOUNT.TABLE, now extracted (engine D19).
  Chk 'A-LW-PARAM'      "$($lw1.ParamByNameDs)/$($lw1.ParamByNameCol) of $($lw1.ParamByNameAll)" '189/183 of 383'
  Chk 'A-LW-OL-CHART'   "$($lw1.OrmLinksCli)/$($lw1.OrmLinksSrv)" '0/0'
  Chk 'A-LW1-COL'       "$($lw1.TableColumn):$($lw1.ColumnState)" 'CAUSFAIL.REASON:yes'
  # 4 server rows as the plan says, but the Save row is the member access
  # Obj.REASON (:229, [certain]) -- the plan's "Save ParamByName" does not exist
  Chk 'A-LW1-SRV'       $lw1.ServerRows 4
  Chk 'A-LW1-SRV-ROWS'  "W=$($lw1.ServerWrite) R=$($lw1.ServerRead)" 'W=PrepareSaveQuery:124,Save:229 R=PrepareLoadQuery:109,Load:159'
  Chk 'A-LW1-TRIG'      $lw1.TriggerNames 'CAUSFAIL_BIU5@MS5.SQL:15'
  # the reverse of feeds-from: 7 REASON bindings, 1 resolves to CAUSFAIL (the
  # same 7/1 consumers' column form counts, A-CO2-BIND)
  Chk 'A-LW1-CLIENT'    "$($lw1.ClientBindings) $($lw1.ClientRows) +$($lw1.ClientOther)" '1 uCausFailForm.dfm:60:colREASON +6'
  Chk 'A-LW1-PROCS'     $lw1.Procedures 0
  Chk 'A-LW1-CLICK'     "$($lw1.ClickTargets)/$($lw1.Expected)" '9/9'
  $tl1 = Dot $lw1
  # 1410 is CAUSFAIL.REASON's column anchor: the engine's sql_column start, ONE LINE
  # EARLY (declared on 1411) -- an ENGINE defect, INBOX-sql-column-start-line-one-early.md;
  # it moves to 1411 when the engine fixes it (see A-CO5-OLDER).
  foreach ($ln in 81, 124, 109, 229, 159, 1410, 15, 60) { if (-not (HasLine $tl1 $ln)) { Fail 'A-LW1-HREF' "no row anchored on line $ln" } }
  # RE-WORDED in the final wave (item 2): the count is what the SQL index EXTRACTS.
  # At 1.19 (D19 fixed) the quoted FOLDERCOUNT.TABLE is extracted, so the grade is
  # 1,992 with NO "+1 a QUOTED column" and the coverage line names no quoted column.
  if ($tl1 -notmatch 'inferred -- naming convention, 1,992 of 1,997 properties on table-named classes are extracted as a column of that table ') { Fail 'A-LW1-GRADE' 'the convention grade with its measured count is missing' }
  if ($tl1 -notmatch '\(1,997 sit on a table-named class; 5 are not extracted as a column by the SQL index\)') { Fail 'A-LW1-GRADE' 'the coverage line claims more than was read' }
  if ($tl1 -match 'QUOTED') { Fail 'A-LW1-GRADE' 'the quoted-column wording still fires, with no quoted column left' }
  if ($tl1 -match 'not a column in the scripts') { Fail 'A-LW1-GRADE' 'the self-contradicting "not a column in the scripts" is back' }
  if ($tl1 -notmatch 'cluster_db_\d+ \{\s*style="rounded,filled,dashed"') { Fail 'A-LW1-DASHED' 'the convention hop (TABLE.COLUMN) is not dashed' }
  if ($tl1 -notmatch 'orm_links rows: 0 on CLIENT-Micronite2027\.sqlite, 0 on SERVER-MicroniteMW1Service\.sqlite') { Fail 'A-LW1-ROUTE' 'the path-A route is not printed' }
  if ($tl1 -notmatch 'positional Fields\[i\]') { Fail 'A-LW1-DISC' 'positional-read disclosure missing' }
  if ($tl1 -notmatch 'script-derived schema: 135 tables; 5 live tables are not in the scripts') { Fail 'A-LW1-DISC' 'script-derived disclosure missing' }
  if ($tl1 -match '99\.7') { Fail 'A-LW1-R10' 'the chart quotes the plan''s 99.7%' }

  # the interface property: SYSTID is touched by TWO triggers (P39)
  $script:lw2 = & "$SRC\Emit-LandsWhere.ps1" -Field 'iCAUSFAIL.ImcCAUSFAIL.SYSTID' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-LW2-TRIG'      $lw2.TriggerNames 'CAUSFAIL_BIU5@MS5.SQL:15,CAUSFAIL_BUD0@MS6.SQL:44'
  Chk 'A-LW2-SRV'       "W=$($lw2.ServerWrite) R=$($lw2.ServerRead)" 'W=PrepareSaveQuery:124,Save:231 R=PrepareLoadQuery:109,Load:161'

  # the backing field resolves to its property, [by name]; same landing
  $script:lw3 = & "$SRC\Emit-LandsWhere.ps1" -Field 'uCAUSFAIL.TmcCAUSFAIL.fREASON' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-LW3-FIELD'     "$($lw3.Property)|$($lw3.TableColumn)|$($lw3.ServerRows)" 'uCAUSFAIL.TmcCAUSFAIL.REASON|CAUSFAIL.REASON|4'
  if ((Dot $lw3) -notmatch '\[by name\] backing field of REASON') { Fail 'A-LW3-FIELD' 'the field -> property hop is not graded [by name]' }

  # the DFM-field kind: the SAME chain feeds-from draws (A-FF1), continued as the ORM case
  $script:lw4 = & "$SRC\Emit-LandsWhere.ps1" -Field 'frmCausFail.colREASON' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-LW4-DFM'       "$($lw4.Kind):$($lw4.ChainOutcome):$($lw4.TableColumn):$($lw4.Property):$($lw4.ServerRows)" 'dfm:column:CAUSFAIL.REASON:uCAUSFAIL.TmcCAUSFAIL.REASON:4'
  foreach ($ln in 60, 88, 125, 37) { if (-not (HasLine (Dot $lw4) $ln)) { Fail 'A-LW4-HREF' "chain hop :$ln not anchored" } }
  Chk 'A-LW4-CLICK'     "$($lw4.ClickTargets)/$($lw4.Expected)" '14/14'
}

Note 'lands-where: the not-a-column rows, refusals and draws ...'
# N31. The plan's selector `uFOLDERS.TmcFOLDERS.TABLE` does not exist -- TABLE is a
# property of TmcFOLDERCOUNT (FINDING) -- so it REFUSES, naming what it tried.
NegTest 'LW-N31-BRIEF' 'uFOLDERS.TmcFOLDERS.TABLE resolves to no property or field in this index' 'landswhere_uFOLDERS_TmcFOLDERS_TABLE' {
  & "$SRC\Emit-LandsWhere.ps1" -Field 'uFOLDERS.TmcFOLDERS.TABLE' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $negDir }
# N31 on a TRUE non-column: INSPRSLT.DistHist is in no script AND no server SQL
# -> "not a column", no DB side, no trigger rows, exits 0 with a chart
Step 'LW-N31' {
  $script:lw31 = & "$SRC\Emit-LandsWhere.ps1" -Field 'uINSPRSLT.TmcINSPRSLT.DistHist' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-LW-N31'        "$($lw31.ColumnState):$([string]$lw31.TableColumn):$($lw31.Triggers):$($lw31.Procedures):$($lw31.ServerRows)" 'no::0:0:0'
  if ((Dot $lw31) -notmatch 'DistHist is not a column of INSPRSLT -- computed or UI-only') { Fail 'A-LW-N31' 'no "not a column of INSPRSLT" row' }
  if (-not (Test-Path $lw31.Svg)) { Fail 'A-LW-N31' 'no .svg' }
}
# FINDING: STATIONS.GRIDS is in no script, but uSTATIONS_SERVER.PAS:129 writes it
# (`UPDATE OR INSERT INTO STATIONS (... GRIDS ...)`) -- NOT "computed or UI-only"
Step 'LW-N31-SRVSQL' {
  $script:lw31g = & "$SRC\Emit-LandsWhere.ps1" -Field 'uSTATIONS.TmcSTATIONS.GRIDS' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-LW-N31-SRVSQL' "$($lw31g.ColumnState):$($lw31g.TableColumn):W=$($lw31g.ServerWrite) R=$($lw31g.ServerRead)" 'server-sql:STATIONS.GRIDS:W=PrepareSaveQuery:129,Save:271 R=PrepareLoadQuery:110,Load:176'
  $tg = Dot $lw31g
  if ($tg -match 'computed or UI-only') { Fail 'A-LW-N31-SRVSQL' 'a server-persisted column is called computed or UI-only' }
  # RE-WORDED (item 2): what was read, not "NOT in the SQL scripts"; the SAME label consumers prints (A-CO-SRVSQL)
  if ($tg -notmatch 'not extracted as a column by the SQL index \(23 columns extracted from the newest of 2 declaration\(s\), MS1\.SQL:3495\); nor a quoted identifier in that declaration -- but the SQL for STATIONS in TDataService_STATIONS_SERVER\.PrepareLoadQuery names it') { Fail 'A-LW-N31-SRVSQL' 'the scripts-lag sentence is missing' }
  # item 1, no fork: consumers decides the same state from the same function, on the same line
  if (-not $cog) { Fail 'A-COLSTATE-AGREE' 'precondition: the consumers STATIONS.GRIDS run (E-CO) produced no result' }
  elseif ($cog.ColumnLabel -ne $lw31g.ColumnLabel) { Fail 'A-COLSTATE-AGREE' "consumers and lands-where label STATIONS.GRIDS differently: '$($cog.ColumnLabel)' vs '$($lw31g.ColumnLabel)'" }
}
# FINDING (1.18): FOLDERCOUNT."TABLE" was a QUOTED column (MS1.SQL:3848) the SQL
# index dropped. RE-BASELINED at 1.19 (engine D19 fixed; R25): it is EXTRACTED,
# so lands-where draws an ordinary [certain] column anchored on the engine's
# sql_column line 3847 -- an ENGINE defect, one line early (INBOX-sql-column-start-line-one-early.md;
# see A-CO5-OLDER): moves to 3848 when fixed -- and says nothing quoted.
# The quoted state itself is driven synthetically by A-COLSTATE-QUOTED.
Step 'LW-N31-QUOTED' {
  $script:lw31q = & "$SRC\Emit-LandsWhere.ps1" -Field 'uFOLDERCOUNT.TmcFOLDERCOUNT.TABLE' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-LW-N31-QUOTED' "$($lw31q.ColumnState):$($lw31q.TableColumn)" 'yes:FOLDERCOUNT.TABLE'
  if (-not (HasLine (Dot $lw31q) 3847)) { Fail 'A-LW-N31-QUOTED' 'the extracted column is not anchored on its sql_column line MS1.SQL:3847' }
  if ((Dot $lw31q) -match 'QUOTED') { Fail 'A-LW-N31-QUOTED' 'the quoted wording still fires on an extracted column' }
  # The quoted state RENDERED through lands-where (fix round 1, item 7): the same
  # hook as A-CO-QUOTED-RENDER. This also drives the convention wording branches
  # the re-baseline left uncovered (Emit-LandsWhere "+N a QUOTED column" and "of
  # those, X is a QUOTED column"): with TABLE hidden the counts are the 1.18 ones.
  $script:lwqh = & "$SRC\Emit-LandsWhere.ps1" -Field 'uFOLDERCOUNT.TmcFOLDERCOUNT.TABLE' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql `
                   -OutDir (Join-Path $OutDir 'lw-quoted') -TestHideColumn 'FOLDERCOUNT.TABLE'
  Chk 'A-LW-QUOTED-RENDER' "$($lwqh.ColumnState):$($lwqh.TableColumn):$($lwqh.ConvColumn):$($lwqh.ConvQuoted)" 'quoted:FOLDERCOUNT.TABLE:1991:FOLDERCOUNT.TABLE'
  Chk 'A-LW-QUOTED-STAMP'  "$($lwqh.TestChart)/$($lw31q.TestChart)" 'True/False'
  $tlq = Dot $lwqh
  if (-not (HasLine $tlq 3848)) { Fail 'A-LW-QUOTED-RENDER' 'the quoted column is not anchored on its scanned line MS1.SQL:3848' }
  if ($tlq -notmatch '1,991 of 1,997 properties on table-named classes are extracted as a column of that table \(\+1 a QUOTED column the index does not extract\)') { Fail 'A-LW-QUOTED-RENDER' 'the convention grade does not add the quoted column' }
  if ($tlq -notmatch '6 are not extracted as a column by the SQL index; of those, FOLDERCOUNT\.TABLE is a QUOTED column the index does not extract') { Fail 'A-LW-QUOTED-RENDER' 'the coverage line does not name the quoted column' }
  if ($tlq -notmatch 'TEST CHART: FOLDERCOUNT\.TABLE taken OUT') { Fail 'A-LW-QUOTED-RENDER' 'a hook-driven chart does not say TEST CHART' }
  if (-not $coq) { Fail 'A-COLSTATE-AGREE' 'precondition: the consumers FOLDERCOUNT.TABLE run (E-CO) produced no result' }
  elseif ($coq.ColumnLabel -ne $lw31q.ColumnLabel) { Fail 'A-COLSTATE-AGREE' "consumers and lands-where label FOLDERCOUNT.TABLE differently: '$($coq.ColumnLabel)' vs '$($lw31q.ColumnLabel)'" }
}
# R17: a uJobList control on a COMPUTED FOLDERS field classifies exactly as
# feeds-from does (A-FF0-PERCTL not-column 13) -- the SAME chain, the SAME test
Step 'LW-R17' {
  $script:lw17 = & "$SRC\Emit-LandsWhere.ps1" -Field 'frmJobList.cxGrid1DBTableView1DueInStr1' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-LW-R17'        "$($lw17.ChainOutcome):$($lw17.Table):$($lw17.ColumnState):$($lw17.Triggers):$($lw17.ServerRows)" 'not-column:FOLDERS:no:0:0'
  $t17 = Dot $lw17
  if ($t17 -notmatch 'DueInStr is not a column of FOLDERS -- computed or UI-only') { Fail 'A-LW-R17' 'no "not a column of FOLDERS -- computed or UI-only"' }
  # item 8 (R21), measured: UPPER(sl.text) would add 'DueIN' (uJobList.ViewModel.pas:301, a
  # computed-field name) as a SECOND candidate and turn this chain -- 73 controls, one-table
  # FOLDERS -- into "many". The match stays exact and the case-only literal is NAMED on the hop.
  if ($t17 -notmatch "the only upper-case table-name literal in uJobList\.ViewModel\.pas; 1 literal\(s\) equal a table name only case-insensitively and are not taken as one: 'DueIN' :301") { Fail 'A-LW-R17-CASE' 'the case-only table literal is not named on the table hop' }
}
NegTest 'LW-N32' 'not an ORM object property (class is not Tmc<T>) and not a DFM-bound field' 'landswhere_uPipeClientConnection_TPipeClientConnection_Connected' {
  & "$SRC\Emit-LandsWhere.ps1" -Field 'uPipeClientConnection.TPipeClientConnection.Connected' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $negDir }
NegTest 'LW-FIB' 'no table named FIB_FIELDS_INFO in the SQL index (the scripts declare FIB$FIELDS_INFO)' 'landswhere_uFIB_FIELDS_INFO_TmcFIB_FIELDS_INFO_FIELD_NAME' {
  & "$SRC\Emit-LandsWhere.ps1" -Field 'uFIB_FIELDS_INFO.TmcFIB_FIELDS_INFO.FIELD_NAME' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $negDir }
NegTest 'LW-MEMCTL' 'no table named MEMCONTROLPLANNINGPRESETS in the SQL index (script-derived' 'landswhere_uMEMCONTROLPLANNINGPRESETS_TmcMEMCONTROLPLANNINGPRESETS_OLDID' {
  & "$SRC\Emit-LandsWhere.ps1" -Field 'uMEMCONTROLPLANNINGPRESETS.TmcMEMCONTROLPLANNINGPRESETS.OLDID' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $negDir }
NegTest 'LW-PERSIST' 'is a persistent FIELD' 'landswhere_frmCompGroupSetup2_tblCompTreeName' {
  & "$SRC\Emit-LandsWhere.ps1" -Field 'frmCompGroupSetup2.tblCompTreeName' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $negDir }
NegTest 'LW-ROLES' 'holds no TDataService_<T>_SERVER class' 'landswhere_uCAUSFAIL_TmcCAUSFAIL_REASON' {
  & "$SRC\Emit-LandsWhere.ps1" -Field 'uCAUSFAIL.TmcCAUSFAIL.REASON' -DbPath $DbCli -ServerDbPath $DbCli -SqlDbPath $DbSql -OutDir $negDir }
NegTest 'LW-ROLES2' 'so it is a SERVER index' 'landswhere_uCAUSFAIL_TmcCAUSFAIL_REASON' {
  & "$SRC\Emit-LandsWhere.ps1" -Field 'uCAUSFAIL.TmcCAUSFAIL.REASON' -DbPath $DbSrv -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $negDir }
NegTest 'LW-N34' 'is not a SQL index (0 sql_table symbols)' 'landswhere_uCAUSFAIL_TmcCAUSFAIL_REASON' {
  & "$SRC\Emit-LandsWhere.ps1" -Field 'uCAUSFAIL.TmcCAUSFAIL.REASON' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbCli -OutDir $negDir }
# R11 on the SQL side: a MANUFACTURED stale MS5.SQL (one trailing blank) -- its
# CAUSFAIL_BIU5 is not scanned, so REASON shows 0 triggers AND says 1 is stale
Step 'LW-STALE' {
  $stDir = Join-Path $OutDir 'lw-stale'
  New-Item -ItemType Directory -Force $stDir | Out-Null
  $ms5 = 'C:\Projects\DB\SQL\MS5.SQL'
  $l = [IO.File]::ReadAllLines($ms5); $l[0] = $l[0] + ' '
  [IO.File]::WriteAllText((Join-Path $stDir 'MS5.SQL'), (($l -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $script:lwst = & "$SRC\Emit-LandsWhere.ps1" -Field 'uCAUSFAIL.TmcCAUSFAIL.REASON' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $stDir `
                   -SourceOverride @{ $ms5 = (Join-Path $stDir 'MS5.SQL') }
  Chk 'A-LW-STALE'      "$($lwst.Triggers)/$($lwst.TriggersStale)" '0/1'
  if ((Dot $lwst) -notmatch '1 trigger\(s\) FOR CAUSFAIL in a script that differs from the index \[stale source\]') { Fail 'A-LW-STALE' 'the stale-trigger disclosure is missing' }
}
# item 5 (R11): a MANUFACTURED stale MS1.SQL -- the script every newest table
# declaration here lives in. DistHist (state `no` on fresh source, A-LW-N31) must
# now read [stale source] and "NOT known", never "computed or UI-only"; and the
# convention coverage must NAME the properties it could not scan for a quoted
# identifier instead of silently dropping them. 5 at 1.19, was 6: FOLDERCOUNT.TABLE
# is extracted now (engine D19), so it is never scanned -- the stale path is
# unchanged and still exercised on the other 5.
Step 'LW-STALE-Q' {
  $stDir = Join-Path $OutDir 'lw-stale-q'
  New-Item -ItemType Directory -Force $stDir | Out-Null
  $ms1 = 'C:\Projects\DB\SQL\MS1.SQL'
  $l = [IO.File]::ReadAllLines($ms1); $l[0] = $l[0] + ' '
  [IO.File]::WriteAllText((Join-Path $stDir 'MS1.SQL'), (($l -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $script:lwsq = & "$SRC\Emit-LandsWhere.ps1" -Field 'uINSPRSLT.TmcINSPRSLT.DistHist' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $stDir `
                   -SourceOverride @{ $ms1 = (Join-Path $stDir 'MS1.SQL') }
  Chk 'A-LW-STALE-Q'    "$($lwsq.ColumnState)|quoted=$($lwsq.ConvQuoted)|stale=$($lwsq.ConvStale)" 'stale|quoted=|stale=INSPRSLT.DistHist,INSPRSLT.DistHistLim,INSPRSLT.f_tb,STATIONS.GRIDS,STATIONS.MENUS'
  $tq = Dot $lwsq
  if ($tq -match 'computed or UI-only') { Fail 'A-LW-STALE-Q' 'a stale quoted scan reads as an absence ("computed or UI-only")' }
  if ($tq -notmatch 'MS1\.SQL differs from the indexed copy, so it was not scanned for a quoted identifier -- whether DISTHIST is a column of INSPRSLT is NOT known') {
    Fail 'A-LW-STALE-Q' 'the [stale source] column state is not said' }
  if ($tq -notmatch 'INSPRSLT\.DISTHIST \[stale source\]') { Fail 'A-LW-STALE-Q' 'the column box title does not carry [stale source]' }
  if ($tq -notmatch 'not scanned for a quoted identifier \[stale source\]: INSPRSLT\.DistHist,INSPRSLT\.DistHistLim,INSPRSLT\.f_tb,STATIONS\.GRIDS,STATIONS\.MENUS\)') { Fail 'A-LW-STALE-Q' 'the coverage line drops the unscanned properties' }
}
# the verb through the bundler: dispatch, -ServerDbPath and -SqlDbPath carried into meta.json
Step 'LW-ART' {
  $artRoot = Join-Path $OutDir 'bundle-lw'
  $art = & "$SRC\New-DiagramArtifact.ps1" -Question lands-where -Target 'uCAUSFAIL.TmcCAUSFAIL.REASON' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutRoot $artRoot
  $meta = Get-Content (Join-Path $art.Bundle 'meta.json') -Raw | ConvertFrom-Json
  Chk 'A-LW-ART'        "$($meta.leftCount) $($meta.leftLabel) / $($meta.rightCount) $($meta.rightLabel)" '4 server DataService rows / 1 triggers touching the column'
  if ($meta.regenerate -notmatch '-SqlDbPath ' -or $meta.regenerate -notmatch '-ServerDbPath ') { Fail 'A-LW-ART' "the regenerate command drops a DB: $($meta.regenerate)" }
}
# FIX ROUND 2: a -TestHideColumn run must not POISON the process-wide chains cache
# ($global:DlFeedChains, keyed on the SQL set's .Db, which the doctored copy
# keeps). Run in a CLEAN child process so the doctored run is the FIRST to touch
# the cache -- the only order in which the leak shows: hide CAUSFAIL.REASON
# (a column colREASON binds), then draw the NORMAL lands-where and feeds-from in
# the same process. Measured on the pre-fix code: Cache 1 after the hidden run
# and feeds-from's coverage 267/253 instead of 267/254 -- a doctored answer
# served to a real chart. Fixed: a Doctored set neither reads nor writes the
# cache, and the hidden run's OWN DFM side reflects the hide (not-column, 253).
Step 'LW-CACHE' {
  $cDir = Join-Path $OutDir 'lw-cache'
  New-Item -ItemType Directory -Force $cDir | Out-Null
  $childPs = Join-Path $cDir 'child.ps1'
  [IO.File]::WriteAllText($childPs, (@'
param([string] $SRC, [string] $DbCli, [string] $DbSrv, [string] $DbSql, [string] $Out)
$ErrorActionPreference = 'Stop'
# 1. the doctored run FIRST, in a process whose chains cache is empty
$h = & "$SRC\Emit-LandsWhere.ps1" -Field 'uCAUSFAIL.TmcCAUSFAIL.REASON' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir (Join-Path $Out 'h') -TestHideColumn 'CAUSFAIL.REASON'
$cachedAfterHide = @($(if ($global:DlFeedChains) { $global:DlFeedChains.Keys })).Count
# 2. then the NORMAL charts in the same process
$n = & "$SRC\Emit-LandsWhere.ps1" -Field 'uCAUSFAIL.TmcCAUSFAIL.REASON' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir (Join-Path $Out 'n')
$f = & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmCausFail.colREASON' -DbPath $DbCli -SqlDbPath $DbSql -OutDir (Join-Path $Out 'f')
$o = [pscustomobject]@{
  Hid   = "$($h.ColumnState):$($h.ClientBindings) $($h.ClientOutcomes) +$($h.ClientOther):$($h.IndexBindColumn):$($h.TestChart)"
  Cache = $cachedAfterHide
  Norm  = "$($n.ColumnState):$($n.ClientBindings) $($n.ClientOutcomes) +$($n.ClientOther):$($n.IndexBindColumn):$($n.TestChart)"
  Feeds = "$($f.TableColumn):$($f.CtlTable)/$($f.CtlColumn)"
}
'R26CHILD:' + ($o | ConvertTo-Json -Compress)
'@ -replace "`r?`n", "`r`n"), (New-Object Text.ASCIIEncoding))
  $raw = @(& pwsh -NoProfile -File $childPs -SRC $SRC -DbCli $DbCli -DbSrv $DbSrv -DbSql $DbSql -Out $cDir 2>&1)
  $line = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_ -like 'R26CHILD:*' })
  if ($line.Count -ne 1) { Fail 'A-LW-CACHE' "the child process returned no result (exit $LASTEXITCODE): $(($raw | Select-Object -Last 3) -join ' | ')" }
  else {
    $c = $line[0].Substring(9) | ConvertFrom-Json
    Chk 'A-LW-CACHE-HID'   $c.Hid   'server-sql:1 not-column +6:253:True'
    Chk 'A-LW-CACHE-KEPT'  $c.Cache 0
    Chk 'A-LW-CACHE-NORM'  $c.Norm  'yes:1 column +6:254:False'
    Chk 'A-LW-CACHE-FEEDS' $c.Feeds 'CAUSFAIL.REASON:267/254'
  }
}
NegTest 'LW-ART-N' 'lands-where needs -ServerDbPath' 'never' {
  & "$SRC\New-DiagramArtifact.ps1" -Question lands-where -Target 'uCAUSFAIL.TmcCAUSFAIL.REASON' -DbPath $DbCli -SqlDbPath $DbSql -OutRoot (Join-Path $OutDir 'bundle-lw-n') }
# ---- output sweep: no escaped entity printed as text -------------------------
# Add-DisclosureRow escapes its text, and nine call sites in seven emitters
# passed a '&#183;' separator into it -- so each of those charts printed the six
# literal characters "&#183;" instead of a middle dot. Swept over EVERY .dot this
# run wrote, because the defect lived in a shared helper, not in one chart.
$ent = @(Get-ChildItem $OutDir -Recurse -Filter *.dot | Where-Object { [IO.File]::ReadAllText($_.FullName).Contains('&amp;#183;') })
if ($ent.Count) { Fail 'E-ENTITY' "$($ent.Count) .dot file(s) print a literal '&#183;': $(($ent | Select-Object -First 4 | ForEach-Object Name) -join ', ')" }

# ---- report ------------------------------------------------------------------
if (-not $Quiet) {
  Write-Host ''
  Write-Host 'Emitter verification -- fifteen questions, thirteen emitters, four indexes'
  Write-Host ("  bytes          : {0} non-ascii, {1} bare LF" -f $nonAscii, $bareLf)
  Write-Host ("  butterfly      : {0} callers / {1} callees, {2} clicks" -f (V $b 'Callers'), (V $b 'Callees'), (V $b 'ClickTargets'))
  Write-Host ("  butterfly D6   : {0} callees from 19 tree nodes, {1} arrows, {2} leave the focus; D12 {3} (synthetic {4}); FConnected bound-unreported {5}, fLOTSIZE D13 {6}" -f (V $b6 'Callees'), (V $b6 'Edges'), (V $b6 'FocusOut'), (V $fx7 'D12Suspect'), $fx12, (V $m14 'BoundUnreported'), (V $m15 'D13SameFile'))
  Write-Host ("  deps           : {0} used by / {1} uses" -f (V $d 'UsedBy'), (V $d 'Uses'))
  Write-Host ("  who-calls      : {0} sites d2, {1} sites + {2} cycle d3, {3} name-only NOT merged" -f (V $w1 'Callers'), (V $w2 'Callers'), (V $w2 'Cycles'), (V $w2 'NameOnly'))
  Write-Host ("  what-it-calls  : {0}/{1}/{2} rows at d1/d2/d3, {3} cycles, ties butterfly's {4}" -f (V $c1 'Rows'), (V $c2 'Rows'), (V $c3 'Rows'), (V $c3 'Cycles'), (V $b 'Callees'))
  Write-Host ("  who-writes     : {0} writes / {1} reads over {2} routines, {3} sites; verb-vs-sql {4}" -f (V $m1 'Writes'), (V $m1 'Reads'), (V $m1 'Routines'), (V $m1 'Sites'), (V $m1 'CrossCheck'))
  Write-Host ("  who-reads      : {0} reads over {1} routines, {2} shown + {3} disclosed" -f (V $m3 'Reads'), (V $m3 'Routines'), (V $m3 'ShownReaders'), (V $m3 'HiddenRoutines'))
  Write-Host ("  event-wiring   : {0} events / {1} handlers / {2} controls; {3} at scale" -f (V $e1 'Events'), (V $e1 'Handlers'), (V $e1 'Components'), (V $e3 'Events'))
  Write-Host ("  hierarchy      : {0} ancestors ({1} outside closure), {2} descendants, {3} collision(s)" -f (V $h1 'Ancestors'), (V $h1 'UnresolvedAnc'), (V $h2 'Descendants'), (V $h3 'Collisions'))
  Write-Host ("  class-surface  : {0} members over {1} visibility clusters, {2} shown + {3} disclosed" -f (V $cs1 'Members'), (V $cs1 'Clusters'), (V $cs1 'Shown'), (V $cs1 'Hidden'))
  Write-Host ("  touches-tables : {0} read / {1} written / {2} both, of {3} SQL symbols" -f (V $s1 'Reads'), (V $s1 'Writes'), (V $s1 'Both'), (V $s1 'IndexSqlSymbols'))
  Write-Host ("  lifecycle      : {0} wired / {1} implemented-not-wired / {2} absent, heritage {3}" -f (V $lc1 'Wired'), (V $lc1 'NotWired'), (V $lc1 'Absent'), (V $lc1 'Heritage'))
  Write-Host ("  cycles         : {0} groups / {1} edges on CLIENT, {2} edges in DL's SCC, {3} on DataCopy" -f (V $cy1 'Cycles'), (V $cy1 'Edges'), (V $cy2 'Edges'), (V $cy3 'Cycles'))
  Write-Host ("  wiring         : {0} regs / {1} sites on SERVER ({2} index-wide); CLIENT {3} of {4}" -f (V $wi1 'Registrations'), (V $wi1 'ResolvedAt'), (V $wi1 'IndexRegs'), (V $wi3 'Registrations'), (V $wi3 'IndexRegs'))
  Write-Host ("  effects        : pure={0}, not-analysed={1}, 'g,s,?'={2}+{3}?, p-ordinals zero-based over {4} params" -f (V $fx1 'Outcome'), (V $fx2 'Outcome'), (V $fx4 'Effects'), (V $fx4 'Unknown'), (V $fx6 'ParamCount'))
  Write-Host ("  architecture   : {0} units / {1} zones / {2} internal edges, {3} back-edge(s); {4} externals in {5} groups" -f (V $ar1 'Units'), (V $ar1 'Zones'), (V $ar1 'InternalEdges'), (V $ar1 'BackEdges'), (V $ar1 'ExternalUnits'), (V $ar1 'Groups'))
  Write-Host ("  protocol-trace : {0} refs over {1} zones (was 0 before the enum binding); field {2} refs; method speaks {3} commands" -f (V $pt1 'Refs'), (V $pt1 'Zones'), (V $pt2 'Refs'), (V $pt3 'Commands'))
  Write-Host ("  crosses-bndry  : {0} ({1} cmds / {2} transport / {3} far); transport itself {4}; no-evidence {5}" -f (V $cb1 'Verdict'), (V $cb1 'Commands'), (V $cb1 'PipeCalls'), (V $cb1 'FarSide'), (V $cb2 'Verdict'), (V $cb3 'Verdict'))
  Write-Host ("  shown-where    : {0} bindings on {1} forms, of {2} index-wide over {3} columns" -f (V $sw1 'Bindings'), (V $sw1 'Forms'), (V $sw1 'IndexRows'), (V $sw1 'IndexColumns'))
  Write-Host ("  change-impact  : {0} routines / {1} unit; a TYPE reaches {2} over {3} units (capped {4})" -f (V $ci1 'Affected'), (V $ci1 'Units'), (V $ci2 'Affected'), (V $ci2 'Units'), (V $ci2 'Capped'))
  Write-Host ("  tested-by      : {0} / {1} / {2} covering tests, from {3} test methods" -f (V $tb1 'Tests'), (V $tb2 'Tests'), (V $tb3 'Tests'), (V $tb1 'TestMethods'))
  Write-Host ("  task-0 helpers : SQL {0}/{1} tables, {2}/{3} trigger bodies; raise/handle {4}/{5}; datasources {6}/{7}/{8} resolve {9}/{10}/{11}; dangling {12}/{13}" -f (V $t0 'SqlTables'), (V $t0 'SqlDeclarations'), (V $t0 'TriggerBodies'), (V $t0 'Triggers'), (V $t0 'ExcRaise'), (V $t0 'ExcHandle'), (V $t0 'DsTotal'), (V $t0 'DsDfmWired'), (V $t0 'DsCodeSite'), (V $t0 'DsOne'), (V $t0 'DsMany'), (V $t0 'DsNone'), (V $t0 'DanglingRows'), (V $t0 'RePointedAny'))
  Write-Host ("  disk vs index  : CLIENT files differing today (informational, not pinned): {0}" -f (V $t0 'DiskStaleCli'))
  Write-Host ("  exception-paths: {0} raises / {1} callers / {2} caught; index {3}/{4}; source bare/on/reraise/var {5}/{6}/{7}/{8}" -f (V $ep1 'Raises'), (V $ep1 'Callers'), (V $ep1 'Caught'), (V $ep1 'IndexRaise'), (V $ep1 'IndexHandle'), (V $ex0 'BareExcept'), (V $ex0 'OnExcept'), (V $ex0 'Reraise'), (V $ex0 'RaiseVar'))
  Write-Host ("  consumers      : CAUSFAIL cert/inf readers {0}/{1}, writers {2}/{3}, {4} triggers; REASON bindings {5}/{6}; facts {7}/{8}/{9}; literals {10}/{11}/{12}; proc bodies {13}" -f (V $co1 'CertainReaders'), (V $co1 'InferredReaders'), (V $co1 'CertainWriters'), (V $co1 'InferredWriters'), (V $co1 'Triggers'), (V $co2c 'IndexBindings'), (V $co2c 'DrawnBindings'), (V $co1 'IndexReadFacts'), (V $co1 'IndexWriteFacts'), (V $co1 'IndexFactSymbols'), (V $co1 'IndexVerbLiterals'), (V $co1 'IndexFromJoinTables'), (V $co1 'IndexFactReadTables'), (V $co1 'ProcBodies'))
  Write-Host ("  feeds-from     : colREASON {0} ({1} rows, {2}); datasources {3}/{4}/{5}; per control {6} of {7} resolve to one table ({8}%), {9} to a column" -f (V $ff1 'TableColumn'), (V $ff1 'ChainRows'), (V $ff1 'HopGrades'), (V $ff1 'IndexDs'), (V $ff1 'IndexDsDfm'), (V $ff1 'IndexDsCode'), (V $ff1 'CtlTable'), (V $ff1 'Controls'), (V $ff1 'CoveragePct'), (V $ff1 'CtlColumn'))
  Write-Host ("  lands-where    : REASON {0} ({1} server rows, {2} trigger, {3} client); convention {4}/{5}/{6}; DataService {7}; ParamByName {8}/{9}; orm_links {10}" -f (V $lw1 'TableColumn'), (V $lw1 'ServerRows'), (V $lw1 'Triggers'), (V $lw1 'ClientBindings'), (V $lw1 'ConvProps'), (V $lw1 'ConvOnTable'), (V $lw1 'ConvColumn'), (V $lw1 'DsClasses'), (V $lw1 'ParamByNameDs'), (V $lw1 'ParamByNameCol'), $ol)
  Write-Host ("  negatives      : N1-N12b, N14, N15, N18b, N19, N20-N24, N33, N35, EP-N20, CO-N25, CO-N26, CO-N26b, CO-N34, FF-N28, FF-N28b, FF-N34, LW-N31-BRIEF, LW-N32, LW-FIB, LW-MEMCTL, LW-PERSIST, LW-ROLES/2, LW-N34, LW-ART-N, N-MAXPATH, W-* (R19 wrappers), each asserting message AND absent .svg; N13/N16/N17, EP-N21..N23, CO-N24/N27/STALE/STALE-COL, FF-N29/N30/STALE, LW-N31/SRVSQL/QUOTED/R17/STALE/STALE-Q draw")
  Write-Host ("  output         : {0}" -f $OutDir)
  Write-Host ''
}

if ($fail.Count -eq 0) {
  if (-not $Quiet) { Write-Host '  PASS -- every measured number reproduced; every refusal refused.' -ForegroundColor Green }
  exit 0
}
Write-Host "  FAIL -- $($fail.Count) problem(s):" -ForegroundColor Red
$fail | ForEach-Object { Write-Host ("    [{0}] {1}" -f $_.Code, $_.Message) }
exit 1
