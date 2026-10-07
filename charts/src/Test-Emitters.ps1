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
  # final-review I9: case-SENSITIVE -- a pin that differs only in case is a difference
  if ("$actual" -cne "$expected") { Fail $code "expected $expected, got $actual" }
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
  # R24: under the 40-row display cap on both sides, so nothing is disclosed
  Chk 'A-DEP-TOTALS' "$($d.UsesTotal)/$($d.UsedByTotal) hidden $($d.UsesHidden)/$($d.UsedByHidden)" '18/3 hidden 0/0'
  if ((Dot $d) -match 'more .* not shown') { Fail 'A-DEP-TOTALS' 'a "more exist" row fires on a unit under the cap' }
}

# R2(a), 2026-10-06: -Engine / -Dot default to '' and are found by Resolve-DragLintEngine /
# Resolve-GraphvizDot (Emit-Common). E-R2 forces every step of both chains on a fake layout;
# E-R2-DEPS is the behavioural half: the same deps chart with -Engine OMITTED and
# DRAGLINT_ENGINE pointing at the engine gives the same .dot as E-DEP, and DRAGLINT_ENGINE
# pointing at a stand-in proves the variable is what the emitter ran (the stand-in leaves a
# marker). The environment is restored exactly, absent staying absent.
Note 'R2 path resolver ...'
Step 'E-R2' {
  $script:r2 = @(& "$SRC\Test-PathResolver.ps1" -OutDir $OutDir -Quiet)
  foreach ($x in $r2) { Fail 'A-R2-RESOLVER' $x }
}
Step 'E-R2-DEPS' {
  $prevEng = [Environment]::GetEnvironmentVariable('DRAGLINT_ENGINE', 'Process')
  $r2Dir = Join-Path $OutDir 'r2-deps'
  $marker = Join-Path $r2Dir 'stand-in-ran.txt'
  $standIn = Join-Path $r2Dir 'stand-in.cmd'
  New-Item -ItemType Directory -Force $r2Dir | Out-Null
  [IO.File]::WriteAllText($standIn, "@echo off`r`necho ran>`"$marker`"`r`nexit /b 1`r`n", (New-Object Text.ASCIIEncoding))
  try {
    $env:DRAGLINT_ENGINE = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
    $script:dEnv = & "$SRC\Emit-Deps.ps1" -Unit 'Blueprint4.ViewModel' -DbPath $DbCli -OutDir $r2Dir
    Chk 'A-R2-DEPS' "$($dEnv.UsedBy)/$($dEnv.Uses)/$($dEnv.Expected)" "$($d.UsedBy)/$($d.Uses)/$($d.Expected)"
    if ((Dot $dEnv) -cne (Dot $d)) { Fail 'A-R2-DEPS' 'the .dot with -Engine omitted (DRAGLINT_ENGINE set) differs from E-DEP''s' }
    $env:DRAGLINT_ENGINE = $standIn
    try { $null = & "$SRC\Emit-Deps.ps1" -Unit 'Blueprint4.ViewModel' -DbPath $DbCli -OutDir (Join-Path $r2Dir 'stand-in') 6>$null } catch { }
    if (-not (Test-Path -LiteralPath $marker)) { Fail 'A-R2-DEPS-ENV' 'with -Engine omitted the emitter did not run DRAGLINT_ENGINE' }
  } finally {
    if ($null -eq $prevEng) { Remove-Item Env:\DRAGLINT_ENGINE -ErrorAction SilentlyContinue } else { $env:DRAGLINT_ENGINE = $prevEng }
  }
  Chk 'A-R2-ENV-RESTORED' "$([Environment]::GetEnvironmentVariable('DRAGLINT_ENGINE', 'Process'))" "$prevEng"
}

# R24 (2026-10-05): deps kept LIMIT $MaxRows (40) with no "more exist" row, and
# filtered the external units AFTER the limit -- so uMain (91 uses entries, 46 of
# them project units; measured on the CLIENT clone) drew fewer than 40 of its 46
# and claimed that was all. The cap stays (a display limit); the remainder is
# now counted and disclosed. uPipeClientConnection is used by 207 uses-clause
# entries (measured), the used-by side of the same defect.
Note 'deps R24 (display cap disclosed) ...'
Step 'E-DEP-R24' {
  $script:dR = & "$SRC\Emit-Deps.ps1" -Unit 'uMain' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-DEP-R24-USES'   "$($dR.Uses) of $($dR.UsesTotal), hidden $($dR.UsesHidden)" '40 of 46, hidden 6'
  if ((Dot $dR) -notmatch '\+6 more units this uses not shown -- 40 of 46 drawn \(display cap 40\)') { Fail 'A-DEP-R24-USES' 'the hidden uses are not disclosed' }
  $script:dR2 = & "$SRC\Emit-Deps.ps1" -Unit 'uPipeClientConnection' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-DEP-R24-USEDBY' "$($dR2.UsedBy) of $($dR2.UsedByTotal), hidden $($dR2.UsedByHidden)" '40 of 207, hidden 167'
  if ((Dot $dR2) -notmatch '\+167 more units that use this not shown -- 40 of 207 drawn \(display cap 40\)') { Fail 'A-DEP-R24-USEDBY' 'the hidden users are not disclosed' }
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
  # The third field (BoundUnreported, 0 on both) retired with engine D31
  # (2026-09-27): find-callers now reports a bare write bound to the member.
  Chk 'A-MA2-D13'      "$($m2.D13SameFile)/$($m2.D13Elsewhere)" '0/0'
  if ((Dot $m2) -match 'engine D13') { Fail 'A-MA2-D13' 'the D13 disclosure still fires on VERDICT, where every write it named is now bound elsewhere' }
  # a missing precondition FAILS (final wave, item 9): `if ($m1) { ... }` used to
  # skip this row silently whenever E-MA1 had thrown, and the run still passed
  if (-not $m1) { Fail 'A-MA1-D13' 'precondition: E-MA1 produced no result, so the D13 count of R was never checked' }
  else { Chk 'A-MA1-D13' "$($m1.D13SameFile)/$($m1.D13Elsewhere)" '0/1' }
}

# ENGINE D13: up to 1.18 write refs were never bound on CLIENT, so the verb saw
# only member-access writes. FConnected is assigned bare inside its own class
# four times; the chart said "no RESOLVED write sites" and listed the four
# unbound lines by name.
# RE-BASELINED at 1.19 (D13 fixed): the four are now BOUND to FConnected, so the
# by-name check is silent (4/0 -> 0/0) -- but find-callers still reports none of
# them (no bound write ref has a member_accesses row: 0 of 21,916), and the chart
# said "no write sites (602 reads)", a FALSE absence. Emit-MemberAccess now
# counted writes BOUND to the member that the verb did not report, and said so.
# RE-BASELINED 2026-09-27 (engine D31, shared engine 1.18.0 / resolver 1.9.0):
# find-callers --resolved now REPORTS those four bound writes, at the same
# lines, so they are the writers wing (Writes 0 -> 4, 3 routines: Connect x2,
# Create, Disconnect) and the "bound, not reported" disclosure is gone. The
# site query anchors them through its bound-ref arm; CrossCheck proves the verb
# and the SQL agree on all four.
Note 'who-writes FConnected (bare writes the verb now reports, engine D31) ...'
Step 'E-MA-D13' {
  $script:m14 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'uPipeClientConnection.TPipeClientConnection.FConnected' -Mode write -DbPath $DbCli -OutDir $OutDir
  Chk 'A-MA14-WRITES' $m14.Writes 4
  Chk 'A-MA14-ROUTINES' $m14.Routines 3
  Chk 'A-MA14-XCHECK' "$($m14.CrossCheck) $($m14.Unanchored)" 'agree 0'
  Chk 'A-MA14-D13'    "$($m14.D13SameFile)/$($m14.D13Elsewhere)" '0/0'
  $t14 = Dot $m14
  # a row anchors its routine's FIRST site; Connect's second (:455) is in its tooltip
  foreach ($ln in 164, 320, 543) {
    if (-not (HasLine $t14 $ln)) { Fail 'A-MA14-LINES' "the bound write at uPipeClientConnection.pas:$ln is not an anchored writer row" }
  }
  if ($t14 -notmatch [regex]::Escape('TITLE="2 write sites: 320:3, 455:3"')) { Fail 'A-MA14-LINES' 'Connect does not list both of its writes (:320, :455)' }
  # FConnected also has 3 UNBOUND bare reads in its own unit (the read-side twin,
  # R26): the write chart still carries the read count WITH that population.
  Chk 'A-MA14-READS' "$($m14.ReadsSameFile)/$($m14.ReadsElsewhere)" '3/0'
  if ($t14 -notmatch [regex]::Escape('reads (not drawn): 602 resolved read(s) reported by find-callers + 3 unbound read(s) named FConnected in uPipeClientConnection.pas')) {
    Fail 'A-MA14-READNOTE' 'the not-drawn read count does not carry its unbound population' }
  if ($t14 -match 'no write sites') { Fail 'A-MA14-ZERO' 'a "no write sites" claim beside 4 reported writes' }
  if ($t14 -match 'BOUND to FConnected') { Fail 'A-MA14-RETIRED' 'the retired "bound, not reported" disclosure still fires' }
  if ($t14 -match 'engine D13') { Fail 'A-MA14-SILENT' 'the by-name D13 disclosure still fires on FConnected, whose writes are all bound now' }
}

# The by-name D13 path on REAL data after the fix (R25): 1.19 still leaves a
# field written inside a `with` body unbound. uPLANLIST.PAS:2547
# `fLOTSIZE := StrToIntA(...)` sits in `with Z14slctFrm do` (TANSIZ14Plan.EditForm).
# The same chart carried 5 in-class writes BOUND to fLOTSIZE as a second
# disclosure. RE-BASELINED 2026-09-27 (engine D31): find-callers reports those 5
# now, at the same lines, so Writes 0 -> 5 and they are anchored writer rows.
Note 'who-writes fLOTSIZE (engine D13 residue: a write in a with body) ...'
Step 'E-MA-D13B' {
  $script:m15 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'uPLANLIST.TmcPLANLIST.fLOTSIZE' -Mode write -DbPath $DbCli -OutDir $OutDir
  Chk 'A-MA15-D13'   "$($m15.Writes)/$($m15.D13SameFile)/$($m15.D13Elsewhere)" '5/1/0'
  Chk 'A-MA15-XCHECK' "$($m15.CrossCheck) $($m15.Unanchored)" 'agree 0'
  $t15 = Dot $m15
  foreach ($ln in 1315, 1453, 1517, 1580, 2055) {
    if (-not (HasLine $t15 $ln)) { Fail 'A-MA15-LINES' "the bound write at uPLANLIST.PAS:$ln is not an anchored writer row" }
  }
  if ($t15 -notmatch 'engine D13: 1 UNBOUND write\(s\) named fLOTSIZE in uPLANLIST\.PAS at :2547 -- by name, NOT counted above') { Fail 'A-MA15-D13' 'the unbound with-body write is not listed by name' }
  # ... and the zero note with unbound writes and NO bound one (it said "no RESOLVED
  # write sites" before fix round 1, R26): TTabSwitchMessage.Result (7 `Result :=` lines in its own unit, by name --
  # 10,481 of the 10,993 writes 1.19 leaves unbound are `Result`)
  $script:m16 = & "$SRC\Emit-MemberAccess.ps1" -Qname 'INSPFLDR.Messages.TTabSwitchMessage.Result' -Mode write -DbPath $DbCli -OutDir $OutDir
  Chk 'A-MA16-D13'   "$($m16.Writes)/$($m16.D13SameFile)/$($m16.D13Elsewhere)" '0/7/10474'
  Chk 'A-MA16-READS'  "$($m16.ReadsSameFile)/$($m16.ReadsElsewhere)" '0/4888'
  # "member-access" -> "resolved" (2026-09-27, engine D31): the verb's count now
  # includes bare accesses bound to the member, so it is not member-access only.
  if ((Dot $m16) -notmatch [regex]::Escape('0 resolved write(s) reported by find-callers + 7 unbound write(s) named Result in INSPFLDR.Messages.pas + 10474 unbound same-name write(s) in other files (may be other symbols) (0 resolved read(s) reported by find-callers + 4888 unbound same-name read(s) in other files (may be other symbols))')) {
    Fail 'A-MA16-ZERO' 'the zero note does not name what find-callers reports beside the unbound populations' }
}

# FIX ROUND 1 (ruling R26): nothing may claim zero writes -- or zero reads --
# while the index holds bound or unbound ones. Blueprint4.TfrmBlueprint4.FNoRecursion
# is the shape 1,073 CLIENT fields share: 48 bare writes BOUND (none reported by
# find-callers at 1.16) and 9 UNBOUND bare reads in its own unit.
# The first cut printed "48 bare write(s) BOUND" and right under it "no read
# sites (0 writes)"; -Mode read printed "(0 writes)" with no disclosure at all.
# RE-BASELINED 2026-09-27 (engine D31): find-callers reports the 48 writes now
# (26 routines), so Writes 0 -> 48 and the write-side zero note is gone; the
# 9 unbound reads are still unreported, so the READ zero note still carries them.
Note 'who-writes/who-reads FNoRecursion (R26: 48 reported writes, 9 unbound reads) ...'
Step 'E-MA-R26' {
  $script:mfb = & "$SRC\Emit-MemberAccess.ps1" -Qname 'Blueprint4.TfrmBlueprint4.FNoRecursion' -Mode both -DbPath $DbCli -OutDir $OutDir
  $script:mfr = & "$SRC\Emit-MemberAccess.ps1" -Qname 'Blueprint4.TfrmBlueprint4.FNoRecursion' -Mode read -DbPath $DbCli -OutDir (Join-Path $OutDir 'r26')
  foreach ($p in @(@('A-MA-R26-BOTH', $mfb), @('A-MA-R26-READ', $mfr))) {
    Chk $p[0] "$($p[1].Writes)/$($p[1].Reads) w=$($p[1].D13SameFile)/$($p[1].D13Elsewhere) r=$($p[1].ReadsSameFile)/$($p[1].ReadsElsewhere)" '48/0 w=0/0 r=9/0'
  }
  Chk 'A-MA-R26-XCHECK' "$($mfb.CrossCheck) $($mfb.Unanchored) $($mfb.Routines)" 'agree 0 26'
  $rPh = '0 resolved read(s) reported by find-callers + 9 unbound read(s) named FNoRecursion in Blueprint4.pas'
  $tb = Dot $mfb; $tr = Dot $mfr
  if ($tb -notmatch [regex]::Escape("$rPh (48 writes)")) { Fail 'A-MA-R26-BOTH' 'the read-side zero note does not carry its unbound population and the write count' }
  if ($tb -notmatch 'engine: 9 UNBOUND read\(s\) named FNoRecursion in Blueprint4\.pas at :1950, :2084, :2113, :2138, :2163, :2179, :2238, :3142, :3546 -- by name') { Fail 'A-MA-R26-BOTH' 'the 9 unbound reads are not listed' }
  if ($tr -notmatch [regex]::Escape("$rPh (48 writes)")) { Fail 'A-MA-R26-READ' 'who-reads prints the zero without its unbound population' }
  if ("$tb $tr" -match 'BOUND to FNoRecursion') { Fail 'A-MA-R26-RETIRED' 'the retired "bound, not reported" disclosure still fires' }
  # the bundle HEADER (New-DiagramArtifact) takes the emitter's own label: who-reads
  # FNoRecursion must not read "0 read sites / 0 routines" beside 9 unbound reads.
  # (This was who-writes FConnected until D31 made its 4 bound writes reported.)
  $art = & "$SRC\New-DiagramArtifact.ps1" -Question who-reads -Target 'Blueprint4.TfrmBlueprint4.FNoRecursion' -DbPath $DbCli -OutRoot (Join-Path $OutDir 'bundle-r26')
  $meta = Get-Content (Join-Path $art.Bundle 'meta.json') -Raw | ConvertFrom-Json
  Chk 'A-MA-R26-HDR' "$($meta.leftCount) $($meta.leftLabel) / $($meta.rightCount) $($meta.rightLabel)" '0 resolved read sites reported by find-callers + 9 unbound read(s) named FNoRecursion in Blueprint4.pas / 0 routines reported by find-callers'
  $script:r26html = [IO.File]::ReadAllText((Join-Path $art.Bundle 'index.html'))
  # a real bundle says it is not a test chart (fix round 2: meta.testChart)
  Chk 'A-MA-R26-META' $meta.testChart 'False'
  if ($r26html -notmatch [regex]::Escape('<span><b>0</b> resolved read sites reported by find-callers + 9 unbound read(s) named FNoRecursion in Blueprint4.pas</span>')) { Fail 'A-MA-R26-HDR' 'the rendered bundle header does not name the unbound reads' }
  # a CHART bundle still takes the svg branch of the shell (Task 8 split it from the text branch)
  if ($r26html -notmatch '<div class="stage"><svg' -or $r26html -notmatch 'graph\.svg &middot; graph\.png') { Fail 'A-MA-R26-SVG' 'a chart bundle does not show its svg inline, or its footer does not name graph.svg' }
  # DOC-R1 (2026-09-28): a click on a chart row must REACH the draglint:// protocol handler. The page's handler
  # used to call preventDefault and only toast "sent to the IDE", so nothing was ever sent. It must not cancel
  # navigation, and it still toasts what it asked for.
  if ($r26html -cmatch 'preventDefault') { Fail 'A-DOC-R1-NAV' 'the chart bundle page cancels draglint:// navigation (preventDefault): a click never reaches the IDE' }
  if ($r26html -cnotmatch "toast\('opening ' \+ what") { Fail 'A-DOC-R1-TOAST' 'the chart bundle page no longer toasts the file and line a click asked for' }
  # fix round 1 (M-7): a malformed %-escape must not throw before the toast (navigation proceeds either way)
  if ($r26html -cnotmatch 'try \{ what = decodeURIComponent\(m\[1\]\)') { Fail 'A-DOC-R1-DECODE' 'decodeURIComponent is not guarded: a malformed % in a link kills the toast' }
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
    # the bundle html is judged with the counts of the chart it wraps (mfr, who-reads FNoRecursion)
    if ($o -is [string]) { $txt = $o; $cnt = $mfr } else { $txt = Dot $o; $cnt = $o }
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
         "$(@(Get-R26Problems 'ok' '0 resolved read(s) reported by find-callers + 9 unbound read(s) named FNoRecursion in Blueprint4.pas (0 resolved write(s) reported by find-callers + 48 unbound write(s))' $cnts).Count)"
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
  # (:304) and SharedFacts uses ProjectTags (:447), lines as of this clone,
  # verified in R3. A SOURCE change, diffed against the pre-1.19 clone; the other
  # 5 are the 1.18 edges (2 at new lines).
  $script:cy2 = & "$SRC\Emit-Cycles.ps1" -DbPath $DbDl -OutDir $OutDir
  Chk 'A-CY2-GROUPS' $cy2.Cycles 1
  Chk 'A-CY2-EDGES'  $cy2.Edges 7
  Chk 'A-CY2-GAPS'   $cy2.Unwalkable 0

  # R3 (2026-10-06): the DL SCC is the largest real multi-unit cycle in the clones
  # (5 units; CLIENT's groups are 3 and 2), and every edge below was checked by
  # hand against C:\Projects\Delphi-RAG-lint\src\doc\*.pas, each file's sha256
  # equal to the clone's files.sha256: the uses entry is on that line, in that
  # section. A change in edge extraction, section tagging or the cycle walk moves
  # this set and fails here.
  $cy2Want = @(
    'draglint.doc.facts->draglint.doc.harvest implementation 977'
    'draglint.doc.harvest->draglint.doc.regions implementation 206'
    'draglint.doc.projecttags->draglint.doc.regions implementation 304'
    'draglint.doc.regions->draglint.doc.facts interface 42'
    'draglint.doc.regions->draglint.doc.sharedfacts implementation 933'
    'draglint.doc.sharedfacts->draglint.doc.projecttags implementation 447'
    'draglint.doc.sharedfacts->draglint.doc.regions implementation 446'
  ) -join '; '
  Chk 'A-CY2-EDGESET' ((@($cy2.EdgeList) | Sort-Object) -join '; ') $cy2Want
  $t2 = Dot $cy2
  # A row anchors to its FIRST intra-group uses entry. SharedFacts uses Regions at
  # :446 and ProjectTags at :447; the walk used to follow the verb's member order
  # and anchored the row at :447.
  if ($t2 -notmatch 'DRagLint\.Doc\.SharedFacts\.pas&amp;line=446"') {
    Fail 'A-CY2-FIRST-USE' 'SharedFacts is not anchored to its first intra-group uses entry (:446)' }
  # interface_cycle:true means ONE interface edge, not an interface-only loop:
  # Regions -> Facts (:42) is the only one, so every loop crosses an
  # implementation use and the compiler accepts the group. Calling it an
  # "interface cycle" is the claim the source contradicts.
  # Positive on the EXACT default text, negative with no closing '<': a wrong
  # Test-InterfaceLoop would print "interface cycle: an all-interface loop ...
  # (1 of 7 uses interface-section)", which a '>interface cycle<' / '1 of 7'
  # pair would both have let through (fix round 1, I1).
  $cyCounted = 'interface coupling: 1 of 7 uses interface-section; every loop crosses an implementation use'
  if ($t2 -match '>interface cycle') { Fail 'A-CY2-VERDICT' 'the group is still called an interface cycle' }
  if (-not $t2.Contains(">$cyCounted<")) { Fail 'A-CY2-VERDICT-N' "the verdict is not exactly '$cyCounted'" }
  # Edge colour says the section: 1 interface arrow, 6 implementation arrows.
  Chk 'A-CY2-INTF-ARROWS' ([regex]::Matches($t2, '-> n\d+:p\d+ \[color="#B02A37"')).Count 1
  Chk 'A-CY2-IMPL-ARROWS' ([regex]::Matches($t2, '-> n\d+:p\d+ \[color="#B45309"')).Count 6

  # -Playbook: the engine's Status line ("units of this cycle use each other in
  # their INTERFACE uses clauses" -- engine job E14) is kept, but the counted
  # clause goes AHEAD of it, so the chart never prints a claim its own check
  # contradicts. --plan on the DL clone measured ~5.5s. Own folder: the base name
  # is the same as cy2's.
  $script:cy2p = & "$SRC\Emit-Cycles.ps1" -DbPath $DbDl -OutDir (Join-Path $OutDir 'cy-playbook') -Playbook
  $t2p = Dot $cy2p
  if (-not $t2p.Contains(">$cyCounted -- engine: interface coupling -- units of this cycle use each other in their INTERFACE uses clauses.<")) {
    Fail 'A-CY2P-VERDICT' 'the -Playbook verdict does not lead with the counted clause ahead of the engine line' }
  if ($t2p -match '>interface cycle') { Fail 'A-CY2P-NOCYCLE' 'the -Playbook verdict calls the group an interface cycle' }

  # Test-InterfaceLoop on synthetic graphs (fix round 1, item 3): the branch no
  # clone exercises -- no compiling project has an all-interface loop.
  $script:cyLoop = & {
    . "$SRC\Emit-Common.ps1"
    $i = [pscustomobject]@{ section = 'interface' }; $m = [pscustomobject]@{ section = 'implementation' }
    $ring  = @{ 'a|b' = $i; 'b|c' = $i; 'c|a' = $i }
    $mixIn = @{ 'a|b' = $i; 'b|a' = $m; 'b|c' = $i; 'c|b' = $i }   # SCC whose b<->c sub-loop is all-interface
    $mixNo = @{ 'a|b' = $i; 'b|c' = $i; 'c|a' = $m }               # every loop crosses an implementation use
    '{0}/{1}/{2}' -f (Test-InterfaceLoop $ring @('a','b','c')), (Test-InterfaceLoop $mixIn @('a','b','c')), (Test-InterfaceLoop $mixNo @('a','b','c'))
  }
  Chk 'A-CY-ILOOP' $cyLoop 'True/True/False'

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
  # RE-BASELINED 2026-09-27: 6880, was 30716. ENGINE change, not an index change
  # (both engines agree on the SAME clone: 1.16 says 30716, 1.18 says 6880).
  # Engine commit c4034b21 (their D5, which this pin's +14 note raised): an
  # external is credited only to the units that name it, one edge per
  # (importer, external). 6880 = distinct (file_id, unit_name_norm) unit_uses
  # rows with target_file_id NULL, measured on this clone and on *.pre-1.9.
  Chk 'A-AR1-EXTEDGES' $ar1.ExternalEdges 6880
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

  # R24: the type-members seed query was unpaged. TdlgSetupDefaults declares
  # 1,196 members (measured on the CLIENT clone), so the old query seeded -- and
  # the chart disclosed -- 200 of them. Depth 1: the seed is the point here.
  $script:ci3 = & "$SRC\Emit-ChangeImpact.ps1" -Target 'uSetupDefaultsFrm.TdlgSetupDefaults' -DbPath $DbCli -Depth 1 -OutDir $OutDir
  Chk 'A-CI3-MEMBERS'  $ci3.Members 1196
  if ((Dot $ci3) -notmatch 'from the type and its 1196 member\(s\)') { Fail 'A-CI3-MEMBERS' 'the chart does not disclose all 1196 members' }
  # R24 fix round 1: the frontier cap counted the 1,197 SEEDS, so every type with
  # more than 400 members read "CAPPED" whatever its radius -- at depth 1 here,
  # with 1 affected routine. The cap now counts only nodes the walk reached.
  Chk 'A-CI3-CAPPED'   "$($ci3.Capped)/$($ci3.Affected)" 'False/1'
  if ((Dot $ci3) -match 'frontier CAPPED') { Fail 'A-CI3-CAPPED' 'a 1-routine radius claims the frontier was capped' }
  $script:ci4 = & "$SRC\Emit-ChangeImpact.ps1" -Target 'uSetupDefaultsFrm.TdlgSetupDefaults' -DbPath $DbCli -OutDir $OutDir
  # default depth 3, MEASURED: the one routine reached at hop 1 has no caller of its own,
  # so the radius stays 1 routine / 1 unit and is NOT capped
  Chk 'A-CI4-DEPTH3'   "$($ci4.Capped)/$($ci4.Affected)/$($ci4.Units)/$($ci4.MaxHop)" 'False/1/1/1'
  # the cap still FIRES when the reached set really outgrows it: same target, -MaxNodes 0
  $script:ci5 = & "$SRC\Emit-ChangeImpact.ps1" -Target 'uSetupDefaultsFrm.TdlgSetupDefaults' -DbPath $DbCli -Depth 3 -MaxNodes 0 -OutDir (Join-Path $OutDir 'ci-cap')
  Chk 'A-CI5-CAPFIRES' "$($ci5.Capped)/$($ci5.Affected)" 'True/1'
  if ((Dot $ci5) -notmatch 'frontier CAPPED at 0') { Fail 'A-CI5-CAPFIRES' 'the capped radius does not admit it' }
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

# path (R4, Task 8): every SHORTEST call path A -> B. The engine's call-path verb answers
# found / not found and ONE shortest path; the emitter enumerates all of them over the same
# resolved call_edges and asserts call-path's own path is among them. MEASURED 2026-10-06 on
# the CLIENT clone (engine 1.25.1-alpha): AddOperation reaches NextSeq in 3 calls by TWO
# routes -- through ReserveNextID (:4084, then :4030) and through SendDeltaOperation (:4099,
# then :3985) -- both into ExecuteCommand, which calls NextSeq at uPipeClientConnection.pas:470
# (butterfly's hop-2 row, A-BF-CALLEES). Every site is grade certain.
Note 'path ...'
Step 'E-PATH' {
  $script:pa1 = & "$SRC\Emit-Path.ps1" -From 'Blueprint4.ViewModel.TBlueprint_ViewModel.AddOperation' `
                  -To 'uPipeClientConnection.TPipeClientConnection.NextSeq' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-PA1-COUNTS' "$($pa1.Paths)/$($pa1.PathsShown)/$($pa1.Hops)/$($pa1.Routines)/$($pa1.Edges)/$($pa1.Sites)/$($pa1.Ambiguous)" '2/2/3/5/5/5/0'
  Chk 'A-PA1-ENGINE' $pa1.EnginePath 'Blueprint4.ViewModel.TBlueprint_ViewModel.AddOperation -> Blueprint4.ViewModel.TBlueprint_ViewModel.ReserveNextID -> uPipeClientConnection.TPipeClientConnection.ExecuteCommand -> uPipeClientConnection.TPipeClientConnection.NextSeq'
  # 5 routine rows + 5 call-site rows on the edges, each one anchor
  Chk 'A-PA1-CLICKS' "$($pa1.ClickTargets)/$($pa1.AllClickable)" '10/True'
  $tp1 = Dot $pa1
  foreach ($ln in 4084, 4099, 4030, 3985, 470) { if (-not (HasLine $tp1 $ln)) { Fail 'A-PA1-SITES' "call site line $ln is not anchored" } }
  if ($tp1 -notmatch 'Blueprint4\.ViewModel\.pas:4084 &#183; certain') { Fail 'A-PA1-LABEL' 'the edge label does not carry its call site and grade' }
  if ($tp1 -match 'not shown') { Fail 'A-PA1-NODISC' 'an uncapped answer discloses hidden paths' }

  # the cap is DISCLOSED, never silent: -Cap 1 draws one route and says the other exists
  $script:pa2 = & "$SRC\Emit-Path.ps1" -From 'Blueprint4.ViewModel.TBlueprint_ViewModel.AddOperation' `
                  -To 'uPipeClientConnection.TPipeClientConnection.NextSeq' -DbPath $DbCli -Cap 1 -OutDir (Join-Path $OutDir 'path-cap')
  Chk 'A-PA2-COUNTS' "$($pa2.Paths)/$($pa2.PathsShown)/$($pa2.Routines)/$($pa2.Edges)" '2/1/4/3'
  if ((Dot $pa2) -notmatch '\+1 more shortest path not shown') { Fail 'A-PA2-DISC' 'the capped path is not disclosed' }

  # one call, TWO sites, both grade ambiguous (resolved to this routine, more than one candidate
  # on the type chain): ImportJenVICI -> GetLastPersistError at Blueprint4.ViewModel.pas:1841 and :1843
  $script:pa3 = & "$SRC\Emit-Path.ps1" -From 'Blueprint4.ViewModel.TBlueprint_ViewModel.ImportJenVICI' `
                  -To 'Blueprint4.ViewModel.TBlueprint_ViewModel.GetLastPersistError' -DbPath $DbCli -OutDir $OutDir
  Chk 'A-PA3-COUNTS' "$($pa3.Paths)/$($pa3.Hops)/$($pa3.Routines)/$($pa3.Edges)/$($pa3.Sites)/$($pa3.Ambiguous)" '1/1/2/1/2/2'
  $tp3 = Dot $pa3
  if ($tp3 -notmatch 'Blueprint4\.ViewModel\.pas:1841 &#183; ambiguous' -or -not (HasLine $tp3 1843)) { Fail 'A-PA3-SITES' 'both ambiguous sites must be labelled and anchored' }

  # the bundle: -To travels into the slug, meta.json and the regenerate command
  $art = & "$SRC\New-DiagramArtifact.ps1" -Question path -Target 'Blueprint4.ViewModel.TBlueprint_ViewModel.ImportJenVICI' `
           -To 'Blueprint4.ViewModel.TBlueprint_ViewModel.GetLastPersistError' -DbPath $DbCli -OutRoot (Join-Path $OutDir 'bundle-path')
  $pm = Get-Content (Join-Path $art.Bundle 'meta.json') -Raw | ConvertFrom-Json
  Chk 'A-PA-META' "$($pm.leftCount) $($pm.leftLabel) / $($pm.rightCount) $($pm.rightLabel)" '1 shortest paths / 1 calls on each path'
  if ($pm.regenerate -notmatch ' -To Blueprint4\.ViewModel\.TBlueprint_ViewModel\.GetLastPersistError' -or $pm.regenerate -notmatch ' -Cap 20') { Fail 'A-PA-REGEN' "regenerate lacks -To / -Cap: $($pm.regenerate)" }
  if ((Split-Path -Leaf $art.Bundle) -notmatch 'GetLastPersistError') { Fail 'A-PA-SLUG' "the bundle folder does not name B: $($art.Bundle)" }
}

# R24: population queries that ran into the 200-row cap with no real trigger on
# the clones (largest type in the TESTS index: 108 members; largest DataService:
# 11 routines -- measured), so a behavioural test cannot fail on them. Guard the
# SOURCE instead: the unpaged forms must not come back. change-impact's twin of
# the tested-by query is tested behaviourally (A-CI3-MEMBERS).
Note 'R24 paged population queries (source guard) ...'
foreach ($g in @(
    @('Emit-TestedBy.ps1',    'Invoke-IndexQuery "SELECT id FROM symbols WHERE parent_id'),
    @('Emit-ChangeImpact.ps1','Invoke-IndexQuery "SELECT id FROM symbols WHERE parent_id'),
    @('Emit-LandsWhere.ps1',  '$rts = Invoke-IndexQuery'),
    @('Emit-LandsWhere.ps1',  '$pbnRows = Invoke-IndexQuery'))) {
  if ([IO.File]::ReadAllText((Join-Path $SRC $g[0])).Contains($g[1])) { Fail 'A-R24-PAGED' "$($g[0]) still runs the unpaged population query: $($g[1])" }
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
# path: the reverse direction has NO path (call-path exit 1, found:false) -- an answer, said
# plainly, and no chart; an unknown routine and A = B are refused before the engine runs.
NegTest 'PA-N1' 'no call path from uPipeClientConnection.TPipeClientConnection.NextSeq to Blueprint4.ViewModel.TBlueprint_ViewModel.AddOperation' 'path_NextSeq__AddOperation' {
  & "$SRC\Emit-Path.ps1" -From 'uPipeClientConnection.TPipeClientConnection.NextSeq' -To 'Blueprint4.ViewModel.TBlueprint_ViewModel.AddOperation' -DbPath $DbCli -OutDir $negDir }
NegTest 'PA-N2' 'Blueprint4.ViewModel.TBlueprint_ViewModel.NoSuchRoutine is not in this index' 'path_NoSuchRoutine__NextSeq' {
  & "$SRC\Emit-Path.ps1" -From 'Blueprint4.ViewModel.TBlueprint_ViewModel.NoSuchRoutine' -To 'uPipeClientConnection.TPipeClientConnection.NextSeq' -DbPath $DbCli -OutDir $negDir }
NegTest 'PA-N3' 'name two different routines' 'path_NextSeq__NextSeq' {
  & "$SRC\Emit-Path.ps1" -From 'uPipeClientConnection.TPipeClientConnection.NextSeq' -To 'uPipeClientConnection.TPipeClientConnection.NextSeq' -DbPath $DbCli -OutDir $negDir }
# fix round 1, item 3: TPipeClientConnection.Log is TWO methods (an overload, measured: 2 rows, both kind method);
# call-path would walk from both, so path refuses and lists them rather than drawing their union
NegTest 'PA-N4' 'uPipeClientConnection.TPipeClientConnection.Log names 2 symbols (an overload or a duplicate declaration): method @uPipeClientConnection.pas:' 'path_Log__NextSeq' {
  & "$SRC\Emit-Path.ps1" -From 'uPipeClientConnection.TPipeClientConnection.Log' -To 'uPipeClientConnection.TPipeClientConnection.NextSeq' -DbPath $DbCli -OutDir $negDir }

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

  # RE-PINNED 2026-10-05 (re-clone at extractor 1.21.1): 430 -> 433. Ref-gap F -- a routine declared only in the
  # implementation section now records its parameter types -- adds three `E: Exception` type_uses (EExtraExceptionInfo:231,
  # ControlPlan2:1140, Blueprint4.ViewModel:1493; source sha identical). None is after `raise`/`on`, so 168/185 hold.
  # P2 through Get-SourceContext: of 433 candidate refs, 168 reads sit after
  # `raise` and 185 type_uses after `on [E:]` -- with 0 stale files among them
  # and 0 refs whose stripped token is not the ref's own name (column alignment).
  Chk 'A-EP0-CAND'      $t0.ExcCandidates 433
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
  # 30 decl + 17 class( + 8 is + 2 as + 8 call-cast + 7 member-access; 425 = 168 + 185 + 72 at 1.20.
  # RE-PINNED 2026-10-05 (extractor 1.21.1, Ref-gap F): +3 parameter-type Exception refs, all dropped (a decl-site
  # type_use is neither raise nor handle): 428 = 168 + 185 + 75
  Chk 'A-EP0-DROPPED'   $ep1.IndexDropped 75
  Chk 'A-EP0-CANDCOUNT' $ep1.IndexCandidates 428

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
  # Task 4 item 4 (fix round 1: the charts-side joiner was REVERTED -- controller
  # ruling). A statement split over SQL.Add lines (engine D18) is COVERED by the
  # engine's sql_reads fact, which 1.19+ assembles across SQL.Add lines, plus the
  # column form's span search over every routine in $rtIds (Emit-Consumers 3/3b/6).
  # The real case, measured: PrepareLoadQuery builds `SELECT` :108 / the column
  # list :109 / `FROM CAUSFAIL` :110 over separate SQL.Add lines, its fact reads
  # CAUSFAIL, and the column form finds REASON on :109 (A-CO2-SRV pins it).
  # What a charts-side join could add, measured: 5 SERVER verb literals END on a
  # verb (uPipeSessionBuilder.pas :544 :658 :1525 x2 :3004), and none has a next
  # line opening on a table of the set -- every one is `' FROM ' + <variable>` or
  # `INSERT INTO ' + '(` -- so 0 statements are left over.
  $script:cod18 = & {
    $Engine = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
    . "$SRC\Emit-Common.ps1"
    $S = Get-SqlTableSet $DbSql
    $DbPath = $DbSrv
    $rt = Invoke-IndexQuery @"
SELECT s.file_id AS fid, s.impl_start_line AS a, s.impl_end_line AS b, sf.sql_reads AS r
  FROM symbols s JOIN symbol_facts sf ON sf.symbol_id = s.id
 WHERE s.qualified_name = 'uCAUSFAIL_SERVER.TDataService_CAUSFAIL_SERVER.PrepareLoadQuery'
"@
    $lits = Get-AllIndexRows "SELECT sl.id AS id, sl.start_line AS line, sl.text AS text FROM string_literals sl WHERE sl.file_id = $([int]$rt[0].fid) AND sl.kind IN ('literal','format','const') AND sl.start_line BETWEEN $([int]$rt[0].a) AND $([int]$rt[0].b)" 'sl.start_line, sl.id'
    $fromL = @($lits | Where-Object { [regex]::IsMatch([string]$_.text, '(?<![A-Za-z0-9_$])FROM\s+CAUSFAIL(?![A-Za-z0-9_$])') } | ForEach-Object { $_.line }) -join '+'
    $colL  = @($lits | Where-Object { [regex]::IsMatch([string]$_.text, '(?<![A-Za-z0-9_$])REASON(?![A-Za-z0-9_$])') } | ForEach-Object { $_.line }) -join '+'
    $verbRx = '(?<![A-Za-z0-9_$])(SELECT|INSERT|UPDATE|DELETE|FROM|JOIN|INTO|EXECUTE)(?![A-Za-z0-9_$])'
    $glob = (@('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'FROM', 'JOIN', 'INTO', 'EXECUTE') | ForEach-Object { "sl.text GLOB '*$_*'" }) -join ' OR '
    $pre = Get-AllIndexRows "SELECT sl.id AS id, sl.file_id AS fid, sl.start_line AS line, sl.text AS text FROM string_literals sl WHERE sl.source = 'pas' AND sl.kind IN ('literal','format') AND ($glob)" 'sl.id'
    $ending = @($pre | Where-Object { [regex]::IsMatch([string]$_.text, $verbRx) -and [regex]::IsMatch([string]$_.text, '(?<![A-Za-z0-9_$.])(FROM|JOIN|INTO|UPDATE|PROCEDURE)\s*$') })
    $cross = 0
    foreach ($e in $ending) {
      $nx = Invoke-IndexQuery "SELECT sl.text AS text FROM string_literals sl WHERE sl.file_id = $([int]$e.fid) AND sl.start_line = $([int]$e.line + 1) AND sl.kind IN ('literal','format') ORDER BY sl.start_col LIMIT 1"
      if ($nx.Count) { $m = [regex]::Match([string]$nx[0].text, '^\s*([A-Z][A-Z0-9_$]*)'); if ($m.Success -and $S.Tables.ContainsKey($m.Groups[1].Value)) { $cross++ } }
    }
    [pscustomobject]@{ Covered = "reads=$($rt[0].r) col=$colL from=$fromL"; Leftover = "$($ending.Count)/$cross" }
  }
  Chk 'A-CO-D18-COVERED' $cod18.Covered 'reads=CAUSFAIL col=109 from=110'
  Chk 'A-CO-D18-LINES'  $cod18.Leftover '5/0'

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
  # Task 4 item 1: the focus box names the state as the docs do (`column`), never
  # the internal `yes` / `older` / `no` -- the summary's ColumnState stays internal
  $tc2c = Dot $co2c
  if ($tc2c -notmatch 'column state column: \[certain\] a column of the newest') { Fail 'A-CO-STATENAME' 'the focus box does not say "column state column:"' }
  if ($tc2c -match 'column state (yes|older|no):') { Fail 'A-CO-STATENAME' 'the focus box still prints an internal state name' }

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
  # is the engine's sql_column start, 2243 -- the column's own declaring line.
  # RE-PINNED 2026-09-28 (re-clone at extractor 1.20 / resolver 1.11): was 2242,
  # ONE LINE EARLY for every extracted column (the node started after the
  # previous token; INBOX-sql-column-start-line-one-early.md). Extractor 1.20
  # puts each sql_column row on its own identifier line, so this pin,
  # A-CO-QUOTED / A-LW-N31-QUOTED (3847 -> 3848) and A-LW1-HREF / A-FF1-HREF
  # (1410 -> 1411) each moved +1 -- the fix, not a regression.
  $script:co5 = & "$SRC\Emit-Consumers.ps1" -Column 'IPCHART.ACTION' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-CO5-OLDER'     "$($co5.ColumnState):$($co5.ColumnLine):$($co5.ColumnOlderOnly)" 'yes:MS1.SQL:2243:False'
  $tc5 = Dot $co5
  if ($tc5 -notmatch '\[certain\] a column of the newest of 2 declaration\(s\), MS1\.SQL') { Fail 'A-CO5-OLDER' 'the [certain] column label is missing' }
  if ($tc5 -match 'QUOTED|extracts it unquoted') { Fail 'A-CO5-OLDER' 'the quoted / older-copy wording still fires on an extracted column' }
  if ($tc5 -match 'columns without it') { Fail 'A-CO5-OLDER' 'the false "the newest has N columns without it" is back' }

  # item 1: a QUOTED column consumers used to REFUSE ("no column TABLE in
  # FOLDERCOUNT") while lands-where anchored it -- now the same state, same line.
  # RE-BASELINED at 1.19 (D19 fixed): an ordinary extracted column, `yes`, at the
  # engine's sql_column line. RE-PINNED 2026-09-28 (extractor 1.20, see A-CO5-OLDER):
  # 3847 -> 3848, the line `"TABLE"` is declared on (it was one line early).
  $script:coq = & "$SRC\Emit-Consumers.ps1" -Column 'FOLDERCOUNT.TABLE' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-CO-QUOTED'     "$($coq.ColumnState):$($coq.ColumnLine):$($coq.ServerRoutines)" 'yes:MS1.SQL:3848:2'
  if (-not (HasLine (Dot $coq) 3848)) { Fail 'A-CO-QUOTED' 'the focus is not anchored on the extracted column (MS1.SQL:3848)' }
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
    # Task 4 item 3: Get-DataSourceChain's by-columns tie-break (Get-ColumnsNotHeld)
    # used `.Columns.Contains`, which says NO to a quoted column (TABLE, hidden
    # here) and to an older-only one (GONOFF.OFF: MEASURED older-only, the newest
    # GONOFF declaration does not extract it) -- both of which Get-SqlColumnState
    # calls a column. NOSUCHCOL is the control: not held either way.
    $nh = @(Get-ColumnsNotHeld $fake 'FOLDERCOUNT' @('TABLE', 'NOSUCHCOL') $null) + @(Get-ColumnsNotHeld $real 'GONOFF' @('OFF') $null)
    $oldNh = @(@('TABLE', 'NOSUCHCOL') | Where-Object { -not $fake.Tables['FOLDERCOUNT'].Columns.Contains($_) }) + @(@('OFF') | Where-Object { -not $real.Tables['GONOFF'].Columns.Contains($_) })
    [pscustomobject]@{ Q1 = "$($q1.State):$([IO.Path]::GetFileName($q1.File)):$($q1.Line):$($q1.QuotedScan)"; L1 = $q1.Label
                       NotHeld = "$($nh -join ',')|old=$($oldNh -join ',')"
                       # Task 4 item 1: the RENDERED state names are the documented ones
                       # (STATUS-questions.md / question-catalogue.md); the internal values stay
                       StateNames = (@('yes', 'quoted', 'older', 'server-sql', 'stale', 'no') | ForEach-Object { Get-ColumnStateName $_ }) -join ','
                       Q2 = "$($q2.State):$([IO.Path]::GetFileName($q2.File)):$($q2.Line)"; L2 = $q2.Label
                       Untouched = $untouched
                       # feeds-from's column-hop label (no real chain can end on a quoted column)
                       Hop = "$(Get-ColumnHopLabel $q1) / $(Get-ColumnHopLabel ([pscustomobject]@{ State = 'yes'; Column = 'REASON' }))" }
  }
  Chk 'A-COLSTATE-QUOTED' "$($cqs.Q1) $($cqs.Q2) $($cqs.Untouched)" 'quoted:MS1.SQL:3848:hit quoted:MS1.SQL:2243 True'
  Chk 'A-DS-TIEBREAK-COLTEST' $cqs.NotHeld 'NOSUCHCOL|old=TABLE,NOSUCHCOL,OFF'
  Chk 'A-COLSTATE-NAMES' $cqs.StateNames 'column,quoted,older-only,server-sql,[stale source],not-a-column'
  # FIX ROUND 1 (item 11): the label no longer says the index "does not extract a
  # quoted name" -- false as a general statement since 1.19 -- only that THIS one
  # was not extracted
  if ($cqs.L1 -ne '[inferred -- source scan] a QUOTED identifier in the newest declaration (MS1.SQL:3848) that the SQL index did not extract as a column') {
    Fail 'A-COLSTATE-QUOTED' "the quoted label moved: $($cqs.L1)" }
  # RE-PINNED 2026-09-28 (extractor 1.20, see A-CO5-OLDER): the older declaration's sql_column line
  # MScript2.SQL:1902 -> 1903, the line `ACTION` is declared on (it was one line early)
  if ($cqs.L2 -ne '[inferred -- source scan] a QUOTED identifier in the newest declaration (MS1.SQL:2243) that the SQL index did not extract as a column; an older declaration (MScript2.SQL:1903) extracts it unquoted') {
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
# Task 4 item 2: the column form REFUSES when the column's state is [stale
# source] -- not extracted, and the newest declaration's script (a MANUFACTURED
# stale MS1.SQL, as A-LW-STALE-Q) could not be scanned, so whether it is a column
# is NOT known. The docs (question-catalogue.md, STATUS-questions.md) quote this
# message; measured on the clones, verbatim. Own scratch path (freshness cache).
# The brackets are backtick-escaped: NegTest matches with -like, where a bare
# [stale source] is a one-character class.
NegTest 'CO-STALE-REFUSE' 'consumers: cannot tell whether INSPRSLT.DISTHIST is a column -- `[stale source`] not extracted as a column by the SQL index (144 columns extracted from the newest of 2 declaration(s), MS1.SQL:2073); MS1.SQL differs from the indexed copy, so it was not scanned for a quoted identifier -- whether DISTHIST is a column of INSPRSLT is NOT known. Script-derived; the scripts may lag the live schema.' 'consumers_INSPRSLT_DISTHIST' {
  $stDir = Join-Path $OutDir 'co-stale-refuse'
  New-Item -ItemType Directory -Force $stDir | Out-Null
  $ms1 = 'C:\Projects\DB\SQL\MS1.SQL'
  $l = [IO.File]::ReadAllLines($ms1); $l[0] = $l[0] + ' '
  [IO.File]::WriteAllText((Join-Path $stDir 'MS1.SQL'), (($l -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  & "$SRC\Emit-Consumers.ps1" -Column 'INSPRSLT.DISTHIST' -DbPath $DbSrv -SqlDbPath $DbSql -OutDir $negDir -SourceOverride @{ $ms1 = (Join-Path $stDir 'MS1.SQL') } }
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
  # (uCausFail.ViewModel.pas:37), the REASON column (MS1.SQL:1411 -- RE-PINNED 2026-09-28
  # from 1410, extractor 1.20 puts sql_column on its declaring line; see A-CO5-OLDER)
  foreach ($ln in 60, 88, 125, 37, 1411) { if (-not (HasLine $tf1 $ln)) { Fail 'A-FF1-HREF' "no row anchored on line $ln" } }
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
  # RE-PINNED 2026-10-05 (Task 2) -- re-point followed: the 204 dangling controls whose owner's code re-point reaches a
  # table (Blueprint4_Model.dsrFtrs 154 -> MSCLIST, dsrOperation 50 -> OPERAT; A-FF-REPOINT-AGG) leave dangling:
  # table 267 -> 471 (+204), column 254 -> 443 (+189), not-column 13 -> 28 (+15), dangling 426 -> 222 (-204); 33% -> 58.3%
  Chk 'A-FF0-PERCTL'    "$($ff1.Controls):$($ff1.CtlTable)/$($ff1.CtlColumn)/$($ff1.CtlNotColumn)/$($ff1.CtlAmbiguous)/$($ff1.CtlStops)/$($ff1.CtlDangling)/$($ff1.CtlNoDs)/$($ff1.CtlStale)" '808:471/443/28/37/77/222/1/0'
  if ($tf1 -notmatch 'per control: 808 field-bound controls; 471 resolve to one table \(58\.3%\)') { Fail 'A-FF0-PERCTL' 'the per-control coverage is not printed on the chart' }
  if ($tf1 -match '41 ?%') { Fail 'A-FF0-R9' 'the chart quotes the per-datasource 41%' }
  # Task 2 (2026-10-05), the NEW aggregate: the 426 controls under a DANGLING designer datasource, by where
  # their owner's code re-point goes (Resolve-RePointTable, order table/no-table/stops/multi-rhs/no-site/stale/
  # no-owner). MEASURED on the CLIENT clone:
  #   table 204     -- Blueprint4_Model.dsrFtrs 154 (dxDBGrid1FtrsV 134 + 20 edits) -> MSCLIST, dsrOperation 50 -> OPERAT
  #                    (column 189, not-column 15: the 14 FtrsV / 1 OperationV fields MSCLIST / OPERAT do not hold)
  #   stops 18      -- dsrCustVendor 13 (GetpdsrCustomers reads 0 fields), dsrVarNames 4 + dsrOperNames 1 (LookupCache.Table( ))
  #   walk-limit 197 -- a shape the walk does not follow, NOT a fact of the code (fix round 1; these were stops reading
  #                    falsely "INIData.DataSet is never assigned" / "a bare datasource is the designer case"):
  #                    ControlPlan_Model.* 168 -- FControlPlan_ViewModel.INIData.dsrFtrs: INIData is a METHOD returning the
  #                    record RControlPlan_INIData (ControlPlan2.Model.Interfaces.pas:108), whose .dsrX members ARE assigned
  #                    (ControlPlan2.Model.pas:772-779); dmlSystem2.dsrFolder 29 -- re-pointed to the LOCAL DS of
  #                    RepointJobHeaderToFolder (Blueprint4.pas:984)
  #   multi-rhs 3   -- viewMachines, re-pointed at Blueprint4.pas:1073 AND :2334 with different right-hand sides
  #   no-site 4     -- DBText13 1, lookupSPCCP 3: no code re-point of the owner at all
  # RE-PINNED fix round 1: a walk-limit column after stops (order table/no-table/stops/walk-limit/multi-rhs/no-site/
  # stale/no-owner); stops 215 -> 18 + walk-limit 197 (ControlPlan_Model 168 + dsrFolder 29), the others unchanged
  Chk 'A-FF-REPOINT-AGG' "$($ff1.CtlDanglingAll):$($ff1.CtlRePoint)" '426:204/0/18/197/3/4/0/0'

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
  # RE-PINNED 2026-10-05 (Task 2) -- re-point followed: edtF1 -> the :1015 re-point hop [certain] (:= DS, a LOCAL variable),
  # then Get-RePointChain stops (fix round 1: a walk limit, see A-FF-N29-STOP); was certain>dangling>stop
  Chk 'A-FF-N29-ROWS'   "$($ff29.Grade):$($ff29.RePointedAt):$($ff29.Rebound):$($ff29.HopGrades)" 'dangling:Blueprint4.pas:1015:1:certain>dangling>certain>stop'
  # fix round 1 (Task 2): the stop says WHAT DS is -- a LOCAL variable of RepointJobHeaderToFolder (Blueprint4.pas:984,
  # assigned DS:= FBlueprint_ViewModel.pdsrFolder at :989), which the walk does not follow -- not the false
  # "a bare datasource is the designer case Get-DataSourceChain already follows", and graded a walk limit
  Chk 'A-FF-N29-STOP'   "$($ff29.RePoint)|$($ff29.StopReason)" 'walk-limit|the code re-point was followed to a shape this walk does not follow: DS is a local variable of RepointJobHeaderToFolder (TDataSource, :984) -- the value assigned to it there is not followed'
  if ((Dot $ff29) -match 'designer case Get-DataSourceChain already follows') { Fail 'A-FF-N29-STOP' 'the false designer-case sentence is still drawn' }
}
# Task 2 (2026-10-05, owner: "close all the existing gaps"): feeds-from and lands-where FOLLOW the runtime
# re-point past a DANGLING designer datasource, by the round-trip's own walk (Get-RePointPick ->
# Get-RePointChain -> Get-DataSetTableLiterals, Emit-Common). frmBlueprint4.dxDBGrid1OperationVName:
# Blueprint4_Model.dsrOperation dangles (Blueprint4.dfm:4497); its view is re-pointed at Blueprint4.pas:2282
# := FBlueprint_ViewModel.pdsrOperation. The hops and grades are A-RT3-HOPS's (member :171 certain, accessor
# :1263 by name, field :99 by name, DataSet := :657 certain), then FMTOperation (:78, certain) and the OPERAT
# literal beside it (:769, [inferred]) -- the round-trip's anchor OPERAT.NAME (A-RT3-ANCHOR).
Step 'FF-REPOINT' {
  $script:ffrp = & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmBlueprint4.dxDBGrid1OperationVName' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-FF-REPOINT'      "$($ffrp.Grade):$($ffrp.RePoint):$($ffrp.TableColumn):$($ffrp.ColumnExists)" 'dangling:table:OPERAT.NAME:yes'
  Chk 'A-FF-REPOINT-HOPS' $ffrp.HopGrades 'certain>dangling>certain>certain>by name>by name>certain>certain>inferred'
  $trp = Dot $ffrp
  foreach ($ln in 4497, 2282, 171, 1263, 99, 657, 78, 769, 2809) { if (-not (HasLine $trp $ln)) { Fail 'A-FF-REPOINT-HREF' "no row anchored on line $ln" } }
  if ($trp -match 'that right-hand side is not followed') { Fail 'A-FF-REPOINT' 'the chart still says the re-point is not followed' }
  $script:lwrp = & "$SRC\Emit-LandsWhere.ps1" -Field 'frmBlueprint4.dxDBGrid1OperationVName' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-LW-REPOINT'      "$($lwrp.ChainOutcome):$($lwrp.Table):$($lwrp.TableColumn):$($lwrp.ServerClass)" 'column:OPERAT:OPERAT.NAME:TDataService_OPERAT_SERVER'
  foreach ($ln in 2282, 657, 769) { if (-not (HasLine (Dot $lwrp) $ln)) { Fail 'A-LW-REPOINT-HREF' "no selection row anchored on line $ln" } }
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
  # RE-PINNED 2026-10-05 (Task 2) -- re-point followed: rightCount is A-FF0-PERCTL's CtlTable, 267 -> 471 (+204 dangling controls whose re-point reaches a table)
  Chk 'A-FF-ART'        "$($meta.leftCount) $($meta.leftLabel) / $($meta.rightCount)" '5 chain rows / 471'
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
  # R24: Get-EdgelessFiles was unpaged. At its real threshold it returns 1 file, so
  # drive the population with -MinCallRefs 0: every CLIENT file with no call edge
  # at all -- 222, measured (SELECT COUNT(*) over the same predicate). Unpaged it
  # returned the first 200.
  $script:eg0 = & { $Engine = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'; . "$SRC\Emit-Common.ps1"; $DbPath = $DbCli; (Get-EdgelessFiles 0).Count }
  Chk 'A-EDGELESS-PAGED' $eg0 222

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
  # 1411 is CAUSFAIL.REASON's column anchor: the engine's sql_column start, its declaring
  # line. RE-PINNED 2026-09-28 from 1410 (one line early until extractor 1.20;
  # INBOX-sql-column-start-line-one-early.md, see A-CO5-OLDER).
  foreach ($ln in 81, 124, 109, 229, 159, 1411, 15, 60) { if (-not (HasLine $tl1 $ln)) { Fail 'A-LW1-HREF' "no row anchored on line $ln" } }
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
  $script:lw31 = & "$SRC\Emit-LandsWhere.ps1" -Field 'uINSPRSLT.TmcINSPRSLT.DistHist' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir -InformationVariable lw31Info
  Chk 'A-LW-N31'        "$($lw31.ColumnState):$([string]$lw31.TableColumn):$($lw31.Triggers):$($lw31.Procedures):$($lw31.ServerRows)" 'no::0:0:0'
  # Task 4 item 1: the printed selection line names the state as the docs do;
  # the summary's ColumnState above stays the internal `no`
  $selLine = @($lw31Info | ForEach-Object { "$_" } | Where-Object { $_ -like '*selection:*' })
  Chk 'A-LW-STATENAME'  $(if ($selLine.Count) { $selLine[0].Trim() } else { '(no selection line)' }) 'selection: uINSPRSLT.TmcINSPRSLT.DistHist (orm); table INSPRSLT; column not-a-column'
  if ((Dot $lw31) -notmatch 'DistHist is not a column of INSPRSLT -- computed or UI-only') { Fail 'A-LW-N31' 'no "not a column of INSPRSLT" row' }
  if (-not (Test-Path $lw31.Svg)) { Fail 'A-LW-N31' 'no .svg' }
}
# FINDING: STATIONS.GRIDS is in no script, but uSTATIONS_SERVER.PAS:129 writes it
# (`UPDATE OR INSERT INTO STATIONS (... GRIDS ...)`) -- NOT "computed or UI-only"
Step 'LW-N31-SRVSQL' {
  $script:lw31g = & "$SRC\Emit-LandsWhere.ps1" -Field 'uSTATIONS.TmcSTATIONS.GRIDS' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir -InformationVariable lw31gInfo
  # Task 4 fix round 1: the printed selection line names the FINAL state. It was
  # printed before the server step, which turns `no` into `server-sql` here, so it
  # said `not-a-column` for a column the chart draws as server-sql.
  $selG = @($lw31gInfo | ForEach-Object { "$_" } | Where-Object { $_ -like '*selection:*' })
  Chk 'A-LW-STATENAME-FINAL' $(if ($selG.Count) { $selG[0].Trim() } else { '(no selection line)' }) 'selection: uSTATIONS.TmcSTATIONS.GRIDS (orm); table STATIONS; column server-sql'
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
# sql_column line 3848 -- and says nothing quoted. RE-PINNED 2026-09-28 from 3847
# (extractor 1.20, see A-CO5-OLDER). The old 3847 pin still PASSED on the new clone,
# because the FOLDERCOUNT table node anchors CREATE TABLE on :3847 -- it no longer
# proved the column's anchor.
# The quoted state itself is driven synthetically by A-COLSTATE-QUOTED.
Step 'LW-N31-QUOTED' {
  $script:lw31q = & "$SRC\Emit-LandsWhere.ps1" -Field 'uFOLDERCOUNT.TmcFOLDERCOUNT.TABLE' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-LW-N31-QUOTED' "$($lw31q.ColumnState):$($lw31q.TableColumn)" 'yes:FOLDERCOUNT.TABLE'
  if (-not (HasLine (Dot $lw31q) 3848)) { Fail 'A-LW-N31-QUOTED' 'the extracted column is not anchored on its sql_column line MS1.SQL:3848' }
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
  # R24 item 7: the focus line "N of 2,063 Tmc properties ... are a column" counted
  # only the EXTRACTED columns (1,991 with TABLE hidden), one short of the columns
  # the chart itself found -- the quoted FOLDERCOUNT.TABLE is a column too. It now
  # counts what the grade line counts: 1,991 extracted + 1 quoted = 1,992, which is
  # also what the unhidden run reports (A-LW0-CONV 2063/1997/1992).
  if ($tlq -notmatch '1,992 of 2,063 Tmc properties in this index are a column of their class') { Fail 'A-LW-R24-COUNT' 'the focus count leaves out the quoted column' }
  if ((Dot $lw31q) -notmatch '1,992 of 2,063 Tmc properties in this index are a column of their class') { Fail 'A-LW-R24-COUNT' 'the unhidden focus count moved' }
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
# R24 item 9 (folded T3): a DFM chain that stops before a table. The server line
# printed `no TDataService__SERVER in the SERVER index` and `Imc.` -- names built
# around an empty table. It must say the table could not be determined.
Step 'LW-R24-NOTABLE' {
  $script:lwnt = & "$SRC\Emit-LandsWhere.ps1" -Field 'frmBlueprint4.edtF1' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir
  Chk 'A-LW-R24-NOTABLE' "$($lwnt.ChainOutcome):$([string]$lwnt.Table):$($lwnt.ServerRows)" 'dangling::0'
  $tnt = Dot $lwnt
  if ($tnt -match 'TDataService__SERVER' -or $tnt -match 'Imc\.') { Fail 'A-LW-R24-NOTABLE' 'a name constructed around the empty table is printed' }
  if ($tnt -notmatch 'server: the table could not be determined, so no DataService was looked up') { Fail 'A-LW-R24-NOTABLE' 'the unknown table is not said' }
}
# R24 item 8: "computed or UI-only" is a claim about the FIELD, and with no
# TDataService_<T>_SERVER nothing on the server was searched. No real Tmc<T> sits
# on such a table (the 6 tables without one -- DEFCTRPL, OPERATION and 4 FIB$ --
# have no Tmc class; measured), so the sentence builder is driven directly.
Step 'LW-R24-NODS' {
  $script:nd = & { $Engine = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'; . "$SRC\Emit-Common.ps1"
    [pscustomobject]@{ No = (Format-NotAColumnNote 'DistHist' 'INSPRSLT' 'LBL' ''); Yes = (Format-NotAColumnNote 'DistHist' 'INSPRSLT' 'LBL' 'TDataService_INSPRSLT_SERVER') } }
  if ($nd.No -match 'computed or UI-only') { Fail 'A-LW-R24-NODS' "with no DataService searched the field is still called computed or UI-only: $($nd.No)" }
  Chk 'A-LW-R24-NODS' $nd.No 'DistHist is not extracted as a column of INSPRSLT: LBL; no DataService was searched (no TDataService_INSPRSLT_SERVER in the SERVER index), so whether it is computed, UI-only or written by server SQL is NOT known'
  Chk 'A-LW-R24-DS'   $nd.Yes 'DistHist is not a column of INSPRSLT -- computed or UI-only: LBL; the database side is empty'
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
    # RE-PINNED 2026-10-05 (Task 2) -- re-point followed: IndexBindColumn +189 (the dangling controls whose re-point reaches
    # a column of MSCLIST / OPERAT; A-FF0-PERCTL column 254 -> 443): hidden 253 -> 442, normal 254 -> 443, feeds 267/254 -> 471/443
    Chk 'A-LW-CACHE-HID'   $c.Hid   'server-sql:1 not-column +6:442:True'
    Chk 'A-LW-CACHE-KEPT'  $c.Cache 0
    Chk 'A-LW-CACHE-NORM'  $c.Norm  'yes:1 column +6:443:False'
    Chk 'A-LW-CACHE-FEEDS' $c.Feeds 'CAUSFAIL.REASON:471/443'
  }
}
NegTest 'LW-ART-N' 'lands-where needs -ServerDbPath' 'never' {
  & "$SRC\New-DiagramArtifact.ps1" -Question lands-where -Target 'uCAUSFAIL.TmcCAUSFAIL.REASON' -DbPath $DbCli -SqlDbPath $DbSql -OutRoot (Join-Path $OutDir 'bundle-lw-n') }
# ---- round-trip (spec 2026-09-27-interface-report-trace-core), Task 1: the re-measure ----
# Every string below was MEASURED 2026-09-27 on the 1.19 / 1.8 clones and is PINNED.
# RE-MEASURED 2026-09-28 on the 1.19 / 1.9 clones Task 0 re-took: the helper returns the
# SAME 23 values on both, so the re-clone (D22, D31, resolver 1.9) moved none of these facts.
# RE-MEASURED 2026-09-28 on the 1.20 / 1.11 clones: 3 moved, each traced -- GETTABLE / PUSH (resolver
# 1.11 RB-1: calls on a unit-level var receiver bind) and TABLELIT (extractor 1.20: sql_column on its
# own line, +1).
# A drift is a FINDING about the index (or about a helper), never a number to edit.
Note 'round-trip: the re-measure ...'
Step 'E-RT0' {
  $script:rt0 = & "$SRC\Test-RoundTripHelpers.ps1" -DbCli $DbCli -DbSrv $DbSrv -DbSql $DbSql -OutDir $OutDir
  # GetTable has one implementation. RE-PINNED 2026-09-28 (resolver 1.11, RB-1): every call site on the
  # unit var GDatasetsDef now BINDS to TDatasetsDef.GetTable (151229) -- was -1 (unbound) at all four,
  # which the walk resolved BY NAME (ask receiver-typed-calls). RE-PINNED 2026-10-05 (1.21.1 full re-parse renumbers
  # symbols): 151229 -> 107698, still TDatasetsDef.GetTable (method, decl line 59); the binding did not move.
  Chk 'A-RT0-GETTABLE'  $rt0.GetTableCalls 'uGenericTableRoute.pas:431:107698,uPipeSessionBuilder.pas:525:107698,uPipeSessionBuilder.pas:649:107698,uPipeSessionBuilder.pas:1301:107698'
  Chk 'A-RT0-GETIMPL'   $rt0.GetTableImpls 'uDatasetsDef.TDatasetsDef.GetTable:199'
  Chk 'A-RT0-GLOBALS'   $rt0.GlobalVars 'var:TBroadcastServer:136,var:TDatasetsDef:66'
  # the post-commit broadcast: one call in HandleDelta, one implementation (golden node 13 cites :120, the declaration area).
  # RE-PINNED 2026-09-28 (resolver 1.11, RB-1): the call on the unit var GBroadcastServer now BINDS to
  # TBroadcastServer.PushTableChanged (151569) -- was -1 (unbound). RE-PINNED 2026-10-05 (full re-parse renumbers):
  # 151569 -> 108038, still PushTableChanged (decl line 124, = PUSHIMPL's decl124).
  Chk 'A-RT0-PUSH'      $rt0.PushCalls 'uGenericTableRoute.pas:507:108038:HandleDelta'
  Chk 'A-RT0-PUSHIMPL'  $rt0.PushImpl 'uBroadcastServer.TBroadcastServer.PushTableChanged:401:decl124'
  # the Exit lines the 12 golden guards hang on (plus 4004, 193 and 612, which are branch ends, not golden guards;
  # 612 is HandleTableLoad's except-handler Exit after Rollback -- the plan's probe read 515-560 only, and 612 is on the 1.8 clone too)
  Chk 'A-RT0-EXITS'     $rt0.ExitLines 'DoAfterPostOperation=3950;SendDeltaOperation=3973/3974/4004;LoadOneTable=1133/1140;HandleDelta=415/425/435/451;HandleUpdateRecord=193/200;HandleTableLoad=530/554/612'
  # the anchor chain feeds-from stops at today (spec section 3): dangling DFM module, code re-point, bound property, one accessor, an unbound in-class read, one DataSet site
  # (REPOINT is the one pdsrOperation site right of a `.DataSource` ref; Blueprint4.pas holds 10 more, all `.DataSet` reads)
  Chk 'A-RT0-DFMDS'     "$($rt0.DfmDataSource)/$($rt0.DfmModuleSymbols)" 'Blueprint4_Model.dsrOperation@4497/0'
  Chk 'A-RT0-REPOINT'   $rt0.RePointMember '2282:FBlueprint_ViewModel:property:Blueprint4.Interfaces.IBlueprint_ViewModel.pdsrOperation:171:ro'
  Chk 'A-RT0-ACCESSOR'  "$($rt0.AccessorImpls)|$($rt0.AccessorReads)" 'Blueprint4.ViewModel.TBlueprint_ViewModel.GetpdsrOperation:1263|FDsrOperation:-1'
  Chk 'A-RT0-DSSITE'    "$($rt0.DataSetSites)|$($rt0.AnchorFields)" '657:Create|FDsrOperation:TDataSource:99,FMTOperation:TFDMemTable:78'
  # RE-PINNED 2026-09-28 (extractor 1.20, see A-CO5-OLDER): OPERAT.NAME's sql_column lines MS1.SQL:2808 -> 2809
  # and MScript2.SQL:1640 -> 1641, the lines NAME is declared on (they were one line early)
  Chk 'A-RT0-TABLELIT'  "$($rt0.TableLiterals)|$($rt0.SqlColumn)" '769:BuildSchema,1207:LoadAllForFolder,4306:VerifyAll|MS1.SQL:2809,MScript2.SQL:1641'
  # the ALSO basis (AC-10): 9 bound callers of the sender, 3 fill lines (B is not a route -- it never crosses)
  Chk 'A-RT0-CALLERS'   $rt0.SenderCallers 'ImportJenVICI:1853,ImportLK:2175,ImportNikon:2441,ImportSheffield:3124,ImportZEISS:3416,DoAfterPostOperation:3951,DoAfterDeleteOperation:3957,AddOperation:4099,VerifyAll:4273'
  Chk 'A-RT0-FILLS'     $rt0.FillLines '769:BuildSchema->B,1207:LoadAllForFolder->LoadOneTable,4306:VerifyAll->LoadOneTable'
  # the server dispatch: Pipes.Commands is SERVER-only; the first CROSS-UNIT bound call after the constant is the handler (ParseTableFromPayload is unit-local)
  Chk 'A-RT0-DISPATCH'  "$($rt0.DispatchArms)|$($rt0.PipesCommandsOnClient)" 'cmdDelta@173->Pipes.Protocol.IPipeSessionBuilder.HandleDelta@177:impl0;cmdTableLoad@142->Pipes.Protocol.IPipeSessionBuilder.HandleTableLoad@147:impl0|0'
  Chk 'A-RT0-HANDLERS'  $rt0.HandlerImpls 'uGenericTableRoute.TGenericTableRoute.HandleDelta:389:[],uPipeSessionBuilder.TPipeSessionBuilder.HandleDelta:1209:[TInterfacedObject, IPipeSessionBuilder],uPipeSessionBuilder.TPipeSessionBuilder.HandleTableLoad:502:[TInterfacedObject, IPipeSessionBuilder]'
  # the snapshot tables are EMPTY on both clones: the UPDATE / SELECT statement texts are STOPS (E4)
  Chk 'A-RT0-FBROWS'    $rt0.FbRows '0/0/0/0'
  # Task 2: the model writes 7 numbered items (2 anchor, 3 write, 2 database), 2 conditions, 1 crossing, 1 STOPS
  Chk 'A-RT2-COUNTS'    $rt0.FormACounts '7/2/1/1'
  Chk 'A-RT2-END'       $rt0.FormAEnd 'END TRACE  7 steps, 2 conditions, 1 crossings, 1 unresolved.'
  Chk 'A-RT2-ANCHOR'    $rt0.FormANoAnchor 'refused'
  Chk 'A-RT2-ANCHORS'   $rt0.FormAAnchors 12
  Chk 'A-RT2-ROUNDTRIP' $rt0.FormARoundTrip 'identical'
  Chk 'A-RT2-BYTES'     $rt0.FormABytes '0/0/noBOM'
  Chk 'A-RT2-FORMA'     "$($rt0.FormAChecker)/$($rt0.FormACheckerMut)" '0/1'
  Chk 'A-RT2-NONASCII'  $rt0.FormANonAscii 'refused'
  Chk 'A-RT2-BADNOTE'   $rt0.FormABadNote 'refused'
  # RE-PINNED 2026-10-06 (R5 Part 0; was P16's 'refused'): conditions are written UNQUOTED, so a double-quote is
  # ordinary text -- written as is, read back the same, counted by the checker (with a `--` inside a word too); a
  # condition carrying ' @<file>:<line>', ' -- ' or a trailing ' --' (what would make the line ambiguous) is refused
  Chk 'A-RT2-QUOTE'     $rt0.FormAQuote 'verbatim/refused/refused/refused'
  # P7: seven STOPS, one per section, five behind an actor word ([NN] SERVER STOPS twice): checker exit 0 =
  # it counted all 7 unresolved; the round trip holds; UNLESS SQL = '' is written verbatim
  Chk 'A-RT2-STOPSALL'  $rt0.FormAStopsAll '0/8/1/0/7/identical/2/verbatim'
  # fix round 1: a double-quote in the TITLE is refused (New-Trace / Write-FormA); the model refuses every
  # text its own parser or the checker would misread (16 cases), and not the three look-alikes that are safe
  Chk 'A-RT2-TITLEQUOTE' $rt0.FormATitleQuote 'refused/refused'
  Chk 'A-RT2-TEXTGUARD' $rt0.FormATextGuard 'refused 16/16; accepted []; wrongly refused []'
  # Task 3: the extraction is behaviour-preserving; the field form of the question answers :657
  Chk 'A-RT3-CHAIN-SAME' $rt0.ChainUnchanged 'one-table:CAUSFAIL:certain>certain>by name>inferred:1'
  Chk 'A-RT3-FIELDDS'    $rt0.FieldDataSetSites 'assign:657:FMTOperation:Create'
  # AC-15: dangling in the DFM, re-pointed at Blueprint4.pas:2282 (receiver kept the control), then
  # property [certain, bound] -> accessor [by name] -> field [by name, in-class read] -> DataSet := [certain] -> FMTOperation.
  # MEASURED 2 sites, not the plan's 1: :3213 is `DataSource:= nil` in FormClose (teardown) -- the trace skips a nil
  # re-point as the chain skips a nil DataSet assignment, so the anchor below still follows :2282 alone
  Chk 'A-RT3-REPOINT'    $rt0.RePointSite 'dangling:2:2282=FBlueprint_ViewModel.pdsrOperation,3213=nil:receiver'
  Chk 'A-RT3-HOPS'       $rt0.RePointHops 're-point=certain@Blueprint4.pas:2282,member=certain@Blueprint4.Interfaces.pas:171,accessor=by name@Blueprint4.ViewModel.pas:1263,field=by name@Blueprint4.ViewModel.pas:99,dataset=certain@Blueprint4.ViewModel.pas:657'
  Chk 'A-RT3-DATASET'    $rt0.RePointDataSet 'FMTOperation:TFDMemTable:78:'
  Chk 'A-RT3-ANCHOR'     $rt0.Anchor1 'OPERAT.NAME:FMTOperation:9:'
  Chk 'A-RT3-GRADES'     $rt0.Anchor1Grades 'certain>certain>certain>by name>by name>certain>certain>inferred>inferred'
  Chk 'A-RT3-FILES'      $rt0.Anchor1Files 'Blueprint4.dfm,Blueprint4.pas,Blueprint4.Interfaces.pas,Blueprint4.ViewModel.pas,MS1.SQL'
  Chk 'A-RT3-UNITFORM'   $rt0.Anchor2 'OPERAT.NAME:by name:'
  # Review Focus 2: OPERAT.NAME is loaded by several view models -> a named stop reason, no guess.
  # MEASURED FIVE, not the plan's three: AssignGroups (:306) and AssignTools2 (:282, :423) load OPERAT into a field
  # named FMTOperat. The candidate filter is a dataset-type SUFFIX match: `LIKE 'T%Table%'` also took the grid VIEW
  # Blueprint4.TfrmBlueprint4.dxDBGrid1OperationV (TcxGridDBTableView, 'OPERAT' beside it at Blueprint4.pas:2331).
  # P3: the RESOLVER returns the reason and ZERO chain items; the one numbered STOPS is the emitter's (Task 7, RT-N1)
  Chk 'A-RT3-COLUMN'     $rt0.Anchor3 'OPERAT.NAME:0:OPERAT.NAME: 5 datasets load OPERAT in this index (AssignGroups.ViewModel.TAssignGroupsViewModel.FMTOperat, AssignTools2.ViewModel.TAssignTools2ViewModel.FMTOperat, Blueprint4.ViewModel.TBlueprint_ViewModel.FMTOperation, CompGroup2.ViewModel.TCompGroup2ViewModel.FMTOperation, ControlPlan2.ViewModel.TControlPlan_ViewModel.FMTOperation) -- pass the control or the dataset field'
  # AC-13: not data-bound -> a stop reason anchored at the component (symbols.start_line 180), ZERO chain items (P3)
  Chk 'A-RT3-NOTBOUND'   $rt0.Anchor4 '0:Blueprint4.dfm:180:frmBlueprint4.cxGroupBox16 (TcxGroupBox) is not data-bound: no field binding and no DataSource on it or its two enclosing components in the DFM'
  # P13: the spec's own TField example (a DOTTED unit, 4 segments, split from the right) RESOLVES: the bound write at
  # :939 `FfOperation_FileName := FF(FMTOperation, 'FILENAME')` [by name: the FMTOperation read is unbound] -> the
  # dataset -> OPERAT -> OPERAT.FILENAME (4 items)
  Chk 'A-RT3-TFIELD'     $rt0.AnchorTField 'OPERAT.FILENAME:FMTOperation:4:'
  # fix round 1 (Important 1): only the FieldByName shape proves the column. The :939 FF(...) line is [inferred]
  # (an inference about FF), naming the call; the rule holds for a BOUND dataset read too (latent until the
  # in-class-read gap closes): FF/SomeLookup bound -> inferred, FieldByName bound -> certain, unbound -> by name
  Chk 'A-RT3-TFIELD-GRADE' $rt0.AnchorTFieldStep "inferred|in-class-field-reads|the TField variable via FF(dataset, literal), assumed to return the dataset's field named by the literal, and FMTOperation matched by name among the class's dataset fields"
  Chk 'A-RT3-FV-GRADES'  $rt0.FieldVarGrades 'FF/bound=inferred,FF/unbound=inferred,SomeLookup/bound=inferred,FieldByName/bound=certain,FieldByName/unbound=by name'
  # ruling T3-M1: the shared sanitiser touches only what the writer refuses (' [') -- an indexer stays as written;
  # the generated column label's grade tag reads '(certain)', rewritten at its source
  Chk 'A-RT3-WORD-INDEXER' $rt0.TraceWordIndexer 'X.Fields[0].DataSet (by name]'
  # RE-PINNED by final-review I7 (generated text is never truncated, T3-M2; the note states the SQL fact, not a grade
  # set against the hop's [inferred]): was 'column NAME of OPERAT: (certain) a column of the newest of 2 declarat...'
  # RE-PINNED 2026-09-28 (extractor 1.20, see A-RT0-TABLELIT): MS1.SQL:2808 -> 2809
  Chk 'A-RT3-COLNOTE'    $rt0.ColumnNote 'NAME is a column of the newest of 2 OPERAT declarations (SQL index, MS1.SQL:2809)'
  # Review Focus 5: the stale file named is the FORM unit
  Chk 'A-RT3-STALE-FORM' $rt0.Anchor5Stale 'Blueprint4.pas:'
  # Task 4: the 12 golden guards quoted verbatim (form:keyword:if-line:ok:<the EXACT condition> -- ruling T4-R2);
  # no negation anywhere
  Chk 'A-RT4-GUARDS'    $rt0.Guards ("1:inline:UNLESS:3950:ok:FSuppressEvents | 2:inline:UNLESS:3973:ok:FMTOperation.ChangeCount = 0 | " +
                                     '3:inline:UNLESS:3974:ok:not (Assigned(FConn) and FConn.Connected) | ' + "4:block:UNLESS:411:ok:TableName = '' | " +
                                     '5:block:UNLESS:421:ok:Length(StreamBytes) = 0 | 6:block:UNLESS:431:ok:not GDatasetsDef.GetTable(TableName, Def) | ' +
                                     '7:except:UNLESS:446:ok:Mem.LoadFromStream(MS, sfBinary) raises | ' + "8:block:UNLESS:196:ok:SQL = '' | " +
                                     '9:inline:UNLESS:1133:ok:not (Assigned(FConn) and FConn.Connected) | 10:block:UNLESS:525:ok:not GDatasetsDef.GetTable(ATableName, Def) | ' +
                                     '11:block:UNLESS:549:ok:not TryBuildSafeWhere(WhereStr, Def, WhereSql, WhereVals) | ' +
                                     '12:block:UNLESS:1137:ok:(GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspData)')
  # the response guard: block 3991-4005 holds CancelUpdates (AC-8 is proven on the trace in Task 5). The
  # `else FLastPersistError:=` at :3993 is the NESTED if's else, not this block's -- still UNLESS
  Chk 'A-RT4-RESPONSE'  $rt0.Guard3990 'block:UNLESS:3990:3991-4005:(GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK)'
  Chk 'A-RT4-EXITARG'   $rt0.Guard3973 'FMTOperation.ChangeCount = 0|True'
  # BlockStart is the `except` line; BlockEnd the `end` closing the try statement (:444), per Find-BlockEnd
  Chk 'A-RT4-EXCEPT'    $rt0.Guard446 'except:Mem.LoadFromStream(MS, sfBinary) raises:446-453'
  Chk 'A-RT4-CASE'      $rt0.Guard193 'case:UNLESS'
  # T1-C1: the third HandleTableLoad Exit, in the handler of the try at :591 (eleven statements, first ... last;
  # ' ... ' not ' .. ', which reads as Pascal's range operator -- ruling T4-R3)
  Chk 'A-RT4-EXCEPT612' $rt0.Guard612 'except:UNLESS:605:605-614:T0Open:= GetTickCount64 ... AThreadStorage.Transaction.Commit raises'
  Chk 'A-RT4-WRAP'      $rt0.ShimSynthetic 'block:UNLESS:(A = 1) or (B = 2):3|inline:WHEN:C|except:UNLESS:Load(S) raises:11'
  # Review Focus 3 on a stripped file: a wrapped line's trailing comment is dropped and the string's two spaces kept;
  # `end else begin` is WHEN; an Exit on the line after `then`; then the named results (Reason) for a `"`, a loop,
  # a case arm and an Exit in no branch -- each becomes a STOPS naming E1 in the walk, never a guess or a throw
  # RE-PINNED 2026-10-06 (R5 Part 0): the :25 condition holding a `"` is quoted as written now (inline UNLESS; it was a
  # named unknown while conditions were double-quoted); the refusal arm moved to P8 (:46), a condition holding ' -- '
  Chk 'A-RT4-SHAPES'    $rt0.ShimShapes ("block:UNLESS:(S = 'a  b') or (T = 1):3:5-7:|block:WHEN:C:11:14-16:|block:UNLESS:D:20:21-21:|" +
                                         'inline:UNLESS:S = ''"'':25:25-25:|' +
                                         'unknown:::0:0-0:the Exit at :30 sits under a while statement, a shape the source shim does not read|' +
                                         'unknown:::0:0-0:the Exit at :36 sits in a case arm, a shape the source shim does not read|' +
                                         'unknown:::0:0-0:the Exit at :42 is not inside a branch, a shape the source shim does not read|' +
                                         "unknown:::0:0-0:the condition over the Exit at :46 carries ' -- ', which reads as its note -- a Form A condition cannot carry it verbatim")
  # fix round 1: two Exits on the anchored line; a comment wrapping across a condition's lines (`{` with an
  # apostrophe in its tail, `(*` with `//` in its tail); a {$IFDEF}/{$ELSE}/{$ENDIF} choice between the guard and
  # the Exit (one line, wrapped) -- each a NAMED unknown (pre-fix: UNLESS A, "A and 't } B ", "A and", B, B).
  # Control: a comment closed on its own line inside a wrapped condition is quoted as written
  Chk 'A-RT4-FIX1'      $rt0.ShimFix1 ('unknown:::the Exit at :3 shares its line with another Exit, a shape the source shim does not read|' +
                                       'unknown:::the Exit at :9 has a condition that wraps a comment across lines, a shape the source shim does not read|' +
                                       'unknown:::the Exit at :15 has a condition that wraps a comment across lines, a shape the source shim does not read|' +
                                       'unknown:::the Exit at :19 sits under a conditional-compilation directive, a shape the source shim does not read|' +
                                       'unknown:::the Exit at :28 sits under a conditional-compilation directive, a shape the source shim does not read|' +
                                       'block:UNLESS:A and { c } B or C:')
  Chk 'A-RT4-STALE'     $rt0.ShimStale 'refused-named'
  # Task 5: WRITE -> SERVER -> DATABASE -> RESPONSE, and the READ/ALSO placeholders Task 6 fills
  Chk 'A-RT5-SECTIONS'  $rt0.RtSections 'ANCHOR,WRITE,SERVER,DATABASE,RESPONSE,READ,ALSO'
  # AC-8: the :3990 response guard's else note names FMTOperation.CancelUpdates @:3999. That block (3991-4005)
  # is the failure branch, so its lines are the note, not steps: CancelUpdates is NOT also a step of the path
  Chk 'A-RT5-CANCEL'    $rt0.RtCancel 1
  # AC-9 (ruling P4): CROSSES STEP lines only. TWO at :3985 -- the request (WRITE) and the response (RESPONSE)
  # ride the one FConn.ExecuteCommand call. Facets in text order: the request's FROM/TO/OVER/WITH, its own
  # CONTRACT (cmdDelta, Pipes.Protocol.pas:55) and the far side's (IPipeSessionBuilder.HandleDelta, :392,
  # from the SERVER index); then the response's FROM/TO/WITH.
  # READ SECTION ADDED (Task 6, ruling P6): the facet list doubles -- the READ request at :1136 (FROM/TO/OVER/WITH,
  # cmdTableLoad's CONTRACT, IPipeSessionBuilder.HandleTableLoad's) and its rows coming back (FROM/TO/WITH). The step
  # count stays 2: it counts the WRITE CROSSES at :3985 only (the READ ones anchor at :1136, A-RT6-XINGS counts all four)
  Chk 'A-RT5-CROSS'     "$($rt0.RtCrossOut)|$($rt0.RtCrossFacets)" '2|FROM,TO,OVER,WITH,CONTRACT,CONTRACT,FROM,TO,WITH,FROM,TO,OVER,WITH,CONTRACT,CONTRACT,FROM,TO,WITH'
  # the CALLS / ROUTES steps anchored in the five server units, in walk order. MEASURED, beyond the plan's six:
  # SplitPayload (:409, kept for its own `BarPos < 0` guard), EnsureLoaded [by name] (:429, the FIB$ reads sit
  # under it, so GetTable's by-name unit scan finds them Seen and adds none), LoadFromInternal (bound, under
  # EnsureLoaded) and BindParams (under HandleUpdateRecord, one LoadFromStream). GetTable / EnsureLoaded /
  # PushTableChanged WERE [by name] on the r=1.9 clones (ask receiver-typed-calls: member calls on the unit vars
  # GDatasetsDef / GBroadcastServer stayed unbound, D22). MOVED by T5-R1: CoerceMSCLISTPlanIds (:469) is gone -- its enclosing
  # condition `TableName = 'MSCLIST'` names another table, so the call is in the OMITS disclosure, not the path.
  # RE-PINNED 2026-09-28 (resolver 1.11, RB-1): the member calls on the unit vars GDatasetsDef / GBroadcastServer
  # now BIND, so EnsureLoaded / GetTable / PushTableChanged lost their [by name] grade (and their receiver-typed-calls
  # ask); same steps, same order. PushTableChanged binds into a transport-convention unit (uBroadcast%), which the
  # walk skips unless the callee makes an outward I/O call -- it does (WriteFile), so it stays a step (RC-R6)
  Chk 'A-RT5-SERVER'    $rt0.RtServer ('ROUTES cmdDelta TO IPipeSessionBuilder.HandleDelta|CALLS TPipeSessionBuilder.HandleDelta [by name]|' +
                                       'CALLS TGenericTableRoute.HandleDelta|CALLS SplitPayload|CALLS TDatasetsDef.EnsureLoaded|' +
                                       'CALLS TDatasetsDef.LoadFromInternal|CALLS TDatasetsDef.GetTable|' +
                                       'CALLS TGenericApplyContext.HandleUpdateRecord|CALLS TGenericApplyContext.BindParams|' +
                                       'CALLS TBroadcastServer.PushTableChanged')
  # the FIB$DATASETS_INFO SQL literal, once per direction (a message that merely NAMES the table, :433/:434, is not
  # SQL). READ SECTION ADDED (Task 6): 1 -> 2 -- the READ server walk runs EnsureLoaded -> LoadFromInternal too, and
  # each direction walks with its own Seen, so the read at :130 is a step of both paths
  Chk 'A-RT5-FIB'       $rt0.RtFib 2
  # AC-12 (ruling P15, scoped to WRITE/SERVER/DATABASE by P5): the STOPS says only what was queried --
  # FDef.UpdateSQL from its ref at uGenericTableRoute.pas:190 (in the routine that runs Cmd.Execute), "loaded at
  # uDatasetsDef.pas:149" because LoadFromInternal both names UpdateSQL and holds the walk's FIB$DATASETS_INFO
  # read, and the fb_datasets count of the SERVER clone taken at run time
  # RE-PINNED by final-review M7 (the statement for the POSTED row: HandleUpdateRecord picks Insert / Update / Delete by
  # `case ARequest of` :188, a condition the walk already quoted, and AfterPost fires for an inserted row too). Was
  # 'the UPDATE statement for OPERAT is FDef.UpdateSQL, loaded at uDatasetsDef.pas:149 from ...'; anchor unchanged (:190)
  # RE-PINNED AGAIN by the fix wave (FW-R1): one shared "loaded at uDatasetsDef.pas:149" was true of UpdateSQL
  # alone -- InsertSQL/DeleteSQL load at :148/:150 of the SAME routine. Each member now names its OWN load line
  Chk 'A-RT5-STOPS'     $rt0.RtStops ('the statement for the posted OPERAT row is FDef.InsertSQL (loaded at uDatasetsDef.pas:148), ' +
                                      'FDef.UpdateSQL (loaded at uDatasetsDef.pas:149) or FDef.DeleteSQL (loaded at uDatasetsDef.pas:150), ' +
                                      'picked by the case over ARequest at :188, from FIB$DATASETS_INFO rows the index does not hold (fb_datasets has 0 rows in MicroniteMW1Service)')
  Chk 'A-RT5-COLUMN'    $rt0.RtColumn 1
  Chk 'A-RT5-RSPOK'     $rt0.RtRspOk 2
  # the rebinding switched indexes: files on CLIENT / on SERVER, counted through Invoke-OnDb
  Chk 'A-RT5-ONDB'      $rt0.RtOnDb '625/471'
  # 50 steps (9 anchor, 5 write, 29 server, 2 database, 3 response, 1 read, 1 also), 12 conditions, 2 crossings,
  # 2 unresolved (the DATABASE STOPS and Task 6's READ placeholder). MOVED by T5-R1 from 61/19/2/2: the other-table
  # branches of HandleDelta (Coerce / CaptureOptrlistDelta + CurrentRoles / QChk.Open / ApplyOptrlistSyncItems +
  # SyncRolesOnConn: 12 steps, 7 conditions) and the routine-level `READS MSCLIST` sql fact left the path; ONE
  # OMITS step discloses them. A drift is a finding
  # FIX ROUND 1 moved it again, 50/12/2/2 -> 45/15/2/2: five SERVER lines are no longer path steps -- the :405
  # rspError DEFAULT (overwritten by :553 rspOK), the else of `if ApplyResult = 0` (:562 Rollback, :566 rspError)
  # and the except handler (:573 Rollback, :576 rspError) -- and three conditions say where they went:
  # WHEN ApplyResult = 0 (its else note), UNLESS <try body> raises (the handler), WHEN not WasTxn (the Commit)
  # FIX ROUND 2 (T5-R12): 45/15 -> 45/21 -- every path step inside a readable if now carries it: WHEN not WasTxn
  # on OPENS (:492), WHEN not GDatasetsDef.Loaded on EnsureLoaded (:429), WHEN not FLoaded on LoadFromInternal
  # (:97), WHEN Field is TBlobField + UNLESS IsOld or Field.IsNull on BindParams' LoadFromStream (:157/:160),
  # WHEN Assigned(GBroadcastServer) on PushTableChanged (:507). No step moved
  # READ SECTION ADDED (Task 6, ruling P6): 45/21/2/2 -> 76/31/4/2. The READ placeholder STOPS (1 step, 1 unresolved)
  # and the lone ALSO row are replaced by READ's 24 steps (fill call, callee, send, 15 SERVER, 2 DATABASE, rows back,
  # 3 CLIENT) and ALSO's 9 rows (A-RT6-ALSO): 45 - 2 + 24 + 9 = 76. Conditions +10 (A-RT6-READCONDS), crossings +2
  # (the cmdTableLoad request and its rows), unresolved stays 2 (the READ DATABASE STOPS replaces the placeholder)
  Chk 'A-RT5-COUNTS'    $rt0.RtCounts '76/31/4/2'
  # Pre-review rulings. T5-R1: no step from a branch for another table (failed 12 before the fix), ONE OMITS per
  # section counting the 5 candidate calls left out and quoting the 4 branch conditions verbatim (E1)
  Chk 'A-RT5-OTHERTABLE' $rt0.RtOtherTable 0
  # fix round 1 (T5-R6): the logger DeltaDiagLog (:523) no longer counts; the text states the innermost-if limit.
  # FIX ROUND 2 (Important): 4 -> 11 -- the number is STEPS, each call counted with its whole subtree (a dry walk):
  # CoerceMSCLISTPlanIds + its Q.Open (2), CaptureOptrlistDelta + CurrentRoles (2), QChk.Open (1),
  # ApplyOptrlistSyncItems + SyncRolesOnConn + Q.Open + 3 ExecSQL (6). (The 12th step 28101d5f removed, `READS
  # MSCLIST`, was a routine-level sql fact, dropped by the fact filter, not a line of these branches.)
  # RE-PINNED by final-review I5 (every if of a line's enclosing chain is tested, not only the innermost): the text no
  # longer states the innermost-if limit; the count stays 11 -- no line of HandleDelta sits one if deeper in these branches
  # RE-PINNED 2026-10-06 (R5 Part 0): conditions are written unquoted -- the same conditions, the quotes gone; no count moved
  Chk 'A-RT5-OMITS'     $rt0.RtOmits ("OMITS 11 step(s) in branches for other tables, every enclosing if read up to a loop or case arm @uGenericTableRoute.pas:468 -- in TGenericTableRoute.HandleDelta; " +
                                      "not walked, the branch conditions: WHEN TableName = 'MSCLIST' @uGenericTableRoute.pas:468 / " +
                                      "WHEN TableName = 'OPTRLIST' @uGenericTableRoute.pas:476 / " +
                                      "WHEN (TableName = 'MSCLIST') and (Ctx.AppliedIns > 0) @uGenericTableRoute.pas:515 / " +
                                      "WHEN (TableName = 'OPTRLIST') and (Length(RoleSyncItems) > 0) @uGenericTableRoute.pas:540; ask E1")
  # the enclosing-condition reader on synthetic lines: then -> WHEN, through begin/try -> WHEN, else -> UNLESS, no branch -> unknown
  Chk 'A-RT5-ENCLOSING' $rt0.RtEnclosing "block:WHEN:T = 'MSCLIST':3 | block:WHEN:(T = 'X') and (N > 0):5 | block:UNLESS:(T = 'X') and (N > 0):5 | unknown:::0"
  # the prune rule: only WHEN + `= '<known other table>'`; UNLESS, <>, or, a non-table literal, the anchor's table all keep the step
  Chk 'A-RT5-OTHERRULE' $rt0.RtOtherTableRule 'True,False,False,False,True,False,False,False'
  # T5-R2: HandleDelta's 411 / 421 conditions hang on CALLS SplitPayload and so name their own routine
  # fix round 1: each Exit guard between the :405 default and the :553 overwrite also says what it responds.
  # FIX ROUND 2 (T5-R11): the literal is :414's (the payload written to the ARspPayload parameter), not :413's logger text
  Chk 'A-RT5-CONDROUTINE' $rt0.RtCondRoutine ("in TGenericTableRoute.HandleDelta; else 'cmdDelta: TABLE= prefix missing', responds rspError, the default set at :405; ask E1 | " +
                                             "in TGenericTableRoute.HandleDelta; else 'cmdDelta: empty delta stream for ', responds rspError, the default set at :405; ask E1")
  # T5-R3: literals quoted as the source writes them -- the trailing blank of 'cmdDelta: empty delta stream for '
  # (above) is read from the source columns, because string_literals.text is stored TRIMMED; `"%s"` at :433 cannot be
  # carried, so its line is named; Pascal's doubled '' restored; '; ' named. The shim's string reader was NOT the cause
  # (the doubled-'' synthetic below already quoted verbatim before the fix)
  Chk 'A-RT5-ELSE431'   $rt0.RtElse431 'in TGenericTableRoute.HandleDelta; else a literal at :434, responds rspError, the default set at :405; ask E1'
  Chk 'A-RT5-ELSELITS'  $rt0.RtElseLits "else 'Can''t find the row' | else a literal at :5 | else a literal at :5"
  Chk 'A-RT5-DOUBLEQ'   $rt0.RtDoubledQuote "inline:UNLESS:S = 'it''s' | block:UNLESS:(S = 'a'' then') or (N = 0)"
  # the condition model's new routine field reads back: the written trace round-trips byte for byte
  Chk 'A-RT5-ROUNDTRIP' $rt0.RtRoundTrip 'identical'
  # Fix round 1, Important 1 (failed 5 before): no SERVER step from the :405 default, the else of `if ApplyResult = 0`
  # or the except handler; the success branch carries WHEN ApplyResult = 0 whose else note names the Rollback and
  # rspError; the handler is the note of UNLESS <try body> raises (the body's last statement is a 75-line if, so the
  # quote is `S1 ... raises`); the rspOK says what it overwrites. Protocol constants only in an else note (not mtError)
  Chk 'A-RT5-BRANCHSTEPS' $rt0.RtBranchSteps 0
  # FIX ROUND 2 (T5-R11): the else of :495 quotes no literal (its :563 text goes to a local, the payload line :565
  # has none); the handler quotes :575's payload literal, not :574's DeltaDiagLog text
  Chk 'A-RT5-APPLYWHEN' $rt0.RtApplyWhen "else AThreadStorage.UpdateTransaction.Rollback @uGenericTableRoute.pas:562, rspError; ask E1"
  # RE-PINNED 2026-10-06 (R5 Part 0): conditions are written unquoted -- the same conditions, the quotes gone; no count moved
  Chk 'A-RT5-EXCEPTCOND' $rt0.RtExceptCond "UNLESS ApplyResult:= Mem.ApplyUpdates(0) ... raises @uGenericTableRoute.pas:570 -- else AThreadStorage.UpdateTransaction.Rollback @uGenericTableRoute.pas:573, rspError, 'cmdDelta %s: %s'; ask E1"
  Chk 'A-RT5-RSPOKNOTE' $rt0.RtRspOkNote 'in TGenericTableRoute.HandleDelta; overwrites the rspError default set at :405'
  # the enclosing CHAIN reader (synthetic): if inside an else, an except handler, a then branch
  Chk 'A-RT5-CHAIN'     $rt0.RtChain "inline:WHEN:W:11 > block:UNLESS:R = 0:5 | except:WHEN:R:= Apply ... raises:13 | block:WHEN:R = 0:5"
  # an except whose try body ends in a compound statement (> 3 code lines) quotes `S1 ... raises` (was the whole block)
  Chk 'A-RT5-EXCEPTLONG' $rt0.RtExceptLong 'except:UNLESS:A:= 1 ... raises:10'
  # Important 2 (failed before: HandleUpdateRecord and Cmd.Execute stood BEFORE OPENS): the attached OnUpdateRecord
  # handler runs inside Mem.ApplyUpdates, so its subtree follows the APPLIES; the client entry is ON the event
  Chk 'A-RT5-APPLYORDER' $rt0.RtApplyOrder 'OPENS AThreadStorage.UpdateTransaction.StartTransaction > APPLIES Mem.ApplyUpdates > CALLS TGenericApplyContext.HandleUpdateRecord > RUNS Cmd.Execute'
  Chk 'A-RT5-HANDLERNOTE' $rt0.RtHandlerNote 'in TGenericTableRoute.HandleDelta; fired by Mem.ApplyUpdates at :494, attached as Mem.OnUpdateRecord at :479'
  Chk 'A-RT5-ENTRYNOTE' $rt0.RtEntryNote 'on FMTOperation.AfterPost, wired at :639 in Create'
  # T5-R5 (failed before: "TABLE=OPERAT|" / "AfterPost" re-quoted, 'sfBinary' hard-coded): source literals as written,
  # the stream format read from the SaveToStream arguments (a single argument, or an expression, gives just "stream")
  Chk 'A-RT5-PAYLOAD'   $rt0.RtPayload "WITH cmdDelta 'TABLE=OPERAT|' + sfBinary stream @Blueprint4.ViewModel.pas:3985 -- payload inferred from the literals before the send"
  Chk 'A-RT5-SENDARG'   $rt0.RtSendArg "CALLS TBlueprint_ViewModel.SendDeltaOperation 'AfterPost'"
  Chk 'A-RT5-STREAMFMT' $rt0.RtStreamFmt '[sfBinary],[],[]'
  # Fix round 2. T5-R10 (threw before): the path side of an if -- normal / INVERTED (`if Failed then ..rspError..
  # else ..rspOK..`: the else is the path) / both / neither; an rspError write alone is not success
  Chk 'A-RT5-PATHSIDE'  $rt0.RtPathSide 'then,else,both,none,False'
  # T5-R11 (picked the logger's literal before): the literal on the parameter-writing line; a logger-only block quotes none
  Chk 'A-RT5-ELSEPICK'  $rt0.RtElsePick "[else 'sent back to the caller'] []"
  # T5-R12 (only the Commit carried it before): the transaction's OPENS AND its Commit both carry WHEN not WasTxn;
  # EnsureLoaded and PushTableChanged gained the ifs they sit under (named in HandleDelta, T5-R2) -- EnsureLoaded
  # also keeps its own `FLoaded` guard, hung there as the callee's
  Chk 'A-RT5-WASTXN'    $rt0.RtWasTxn 'OPENS AThreadStorage.UpdateTransaction.StartTransaction@uGenericTableRoute.pas:492 | RUNS AThreadStorage.UpdateTransaction.Commit@uGenericTableRoute.pas:498'
  # RE-PINNED by final-review I6 (caller condition before callee guards: the enclosing if is evaluated before the call
  # runs); was UNLESS FLoaded first, then WHEN not GDatasetsDef.Loaded
  # RE-PINNED 2026-10-06 (R5 Part 0): conditions are written unquoted -- the same conditions, the quotes gone; no count moved
  Chk 'A-RT5-CONDENSURE' $rt0.RtCondEnsure ('CALLS TDatasetsDef.EnsureLoaded@uDatasetsDef.pas:92 :: WHEN not GDatasetsDef.Loaded @uGenericTableRoute.pas:429 | ' +
                                          'CALLS TDatasetsDef.EnsureLoaded@uDatasetsDef.pas:92 :: UNLESS FLoaded @uDatasetsDef.pas:94 | ' +
                                          'CALLS TBroadcastServer.PushTableChanged@uBroadcastServer.pas:401 :: WHEN Assigned(GBroadcastServer) @uGenericTableRoute.pas:507')
  # Task 6: the READ direction and ALSO. AC-6 both directions (green since Task 5's placeholder -- ruling P11: the RED
  # step was A-RT6-READ, which read the placeholder STOPS). AC-9: four crossings -- cmdDelta out and its response,
  # cmdTableLoad out and its rows -- on the CLIENT and SERVER clones queried separately (Invoke-OnDb, A-RT5-ONDB)
  Chk 'A-RT6-DIRS'      $rt0.RtDirs 'True/True'
  Chk 'A-RT6-XINGS'     $rt0.RtXings 4
  # every READ step in text order (routine names as the trace writes them, class kept -- ruling P8). The fill line
  # LoadAllForFolder :1207 carries 'OPERAT' beside FMTOperation (the first of the fill lines, by line; BuildSchema
  # :769's call reaches no crossing and is dropped); its callee LoadOneTable sends cmdTableLoad at :1136. SERVER:
  # dispatch :142 -> :147, the by-name implementation, EnsureLoaded's FIB$ reads (this direction's own Seen), GetTable
  # [by name], TryBuildSafeWhere (a step because the :549 guard turns on it; in a uPipe* unit, so not descended),
  # the read transaction, the query, SaveToStream, Commit, and rspData overwriting the :519 rspError default.
  # DATABASE: the SELECT STOPS (A-RT6-READSTOPS) and the column [inferred]. Then the rows back and the CLIENT
  # load: RECEIVES rspData, EmptyDataSet (under WHEN AMT.Active), LoadFromStream.
  # FIX ROUND 1 moved it: T6-R1 -- EmptyDataSet's verb is EMPTIES (was LOADS: it empties the dataset); M4 -- the two
  # DATABASE steps stand right after the RUNS that executes the query (Qry.Open :594), in source order, no longer after
  # SENDS rspData :618
  # RE-PINNED 2026-09-28 (resolver 1.11, RB-1): EnsureLoaded and GetTable are BOUND (calls on the unit var
  # GDatasetsDef), so their [by name] grade is gone; same steps, same order (HandleTableLoad stays [by name], ask E2)
  Chk 'A-RT6-READ'      $rt0.RtRead ("LOADS FMTOperation VIA TBlueprint_ViewModel.LoadOneTable 'OPERAT'|CALLS TBlueprint_ViewModel.LoadOneTable 'OPERAT'|CROSSES process boundary|" +
                                     'SERVER ROUTES cmdTableLoad TO IPipeSessionBuilder.HandleTableLoad|SERVER CALLS TPipeSessionBuilder.HandleTableLoad [by name]|' +
                                     'SERVER CALLS TDatasetsDef.EnsureLoaded|SERVER CALLS TDatasetsDef.LoadFromInternal|SERVER READS FROM FIB$DATASETS_INFO [inferred]|' +
                                     'SERVER RUNS Q.Open|SERVER READS FROM FIB$FIELDS_INFO [inferred]|SERVER RUNS Q.Open|SERVER CALLS TDatasetsDef.GetTable|' +
                                     'SERVER CALLS TryBuildSafeWhere|SERVER OPENS AThreadStorage.Transaction.StartTransaction|SERVER RUNS Qry.Open|DATABASE STOPS|DATABASE READS OPERAT.NAME [inferred]|' +
                                     'SERVER SERIALIZES Qry.SaveToStream|SERVER RUNS AThreadStorage.Transaction.Commit|SERVER SENDS rspData|CROSSES process boundary|' +
                                     'CLIENT RECEIVES rspData|CLIENT EMPTIES AMT.EmptyDataSet|CLIENT DESERIALIZES AMT.LoadFromStream')
  # AC-7 on the READ path, in WALK order (ruling P9): the client connection guard, the server's missing-definition
  # and unsafe-WHERE guards, the except handler whose Exit is :612 (T1-C1; its condition anchors at the `except`
  # line, :605, and hangs on the try body's FIRST step, Qry.Open), the response guard
  Chk 'A-RT6-READGUARDS' $rt0.RtReadGuards 'Blueprint4.ViewModel.pas:1133,uPipeSessionBuilder.pas:525,uPipeSessionBuilder.pas:549,uPipeSessionBuilder.pas:605,Blueprint4.ViewModel.pas:1137'
  # every READ condition verbatim: the five guards above plus the branch conditions of their steps (EnsureLoaded's own
  # FLoaded Exit, the ifs around EnsureLoaded / LoadFromInternal, around EmptyDataSet and LoadFromStream)
  # RE-PINNED by final-review I6 (caller condition before callee guards): WHEN not GDatasetsDef.Loaded @:523 now
  # stands ahead of EnsureLoaded's own UNLESS FLoaded @:94 (was the reverse)
  # RE-PINNED 2026-10-06 (R5 Part 0): conditions are written unquoted -- the same conditions, the quotes gone; no count moved
  Chk 'A-RT6-READCONDS' $rt0.RtReadConds ('UNLESS not (Assigned(FConn) and FConn.Connected) @Blueprint4.ViewModel.pas:1133 | WHEN not GDatasetsDef.Loaded @uPipeSessionBuilder.pas:523 | ' +
                                          'UNLESS FLoaded @uDatasetsDef.pas:94 | WHEN not FLoaded @uDatasetsDef.pas:97 | ' +
                                          'UNLESS not GDatasetsDef.GetTable(ATableName, Def) @uPipeSessionBuilder.pas:525 | ' +
                                          'UNLESS not TryBuildSafeWhere(WhereStr, Def, WhereSql, WhereVals) @uPipeSessionBuilder.pas:549 | ' +
                                          'UNLESS T0Open:= GetTickCount64 ... AThreadStorage.Transaction.Commit raises @uPipeSessionBuilder.pas:605 | ' +
                                          'UNLESS (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspData) @Blueprint4.ViewModel.pas:1137 | ' +
                                          'WHEN AMT.Active @Blueprint4.ViewModel.pas:1162 | WHEN Length(RspPayload) > 0 @Blueprint4.ViewModel.pas:1163')
  # AC-12: the SELECT text is a numbered STOPS. It says only what was queried: WHERE the statement is assembled, and the
  # FIB$ tables the READ walk reads have no snapshot rows in the SERVER clone. FIX ROUND 1 (M3) moved the text: it names
  # EVERY assignment to the variable the SELECT literal goes into -- :544 and the :556 ' WHERE ' extension -- each quoted
  # as written (was ":544 as <the :544 expression>" alone)
  Chk 'A-RT6-READSTOPS' $rt0.RtReadStops 1
  Chk 'A-RT6-READSTOPTEXT' $rt0.RtReadStopText ("DATABASE STOPS the SELECT statement for OPERAT is assembled in SQL at uPipeSessionBuilder.pas:544 (SQL:= 'SELECT ' + ColSQL + ' FROM ' + ATableName) and :556 (SQL:= SQL + ' WHERE ' + WhereSql), " +
                                                'from values the index holds no text for, and the FIB$ rows the walk reads (FIB$DATASETS_INFO, FIB$FIELDS_INFO) are not in the index ' +
                                                '(fb_datasets has 0 rows, fb_field_info has 0 rows in MicroniteMW1Service) @uPipeSessionBuilder.pas:544 -- in TPipeSessionBuilder.HandleTableLoad; ' +
                                                'the statement is assembled here, in the routine that runs it; ask E4')
  # the payload as the source ASSEMBLES it (one concatenating assignment, :1134) -- its literals alone, joined,
  # would read 'TABLE=' + '|BLOBS=0|WHERE=' as if that were the payload. FIX ROUND 1 (M5): the note says the text is the
  # assignment quoted as written (was "payload inferred from the literals before the send"). The WRITE WITH (A-RT5-PAYLOAD)
  # joins literals, quotes no assignment, and keeps its note
  Chk 'A-RT6-READPAYLOAD' $rt0.RtReadPayload "WITH cmdTableLoad 'TABLE=' + ATableName + '|BLOBS=0|WHERE=' + AWhere @Blueprint4.ViewModel.pas:1136 -- payload quoted from the assignment at :1134"
  # AC-10 (ruling P10): ALSO = every route to the anchor the index holds MINUS the routes traced. Derived:
  #   the other wiring on FMTOperation (AfterDelete, :640)                                               1
  #   SendDeltaOperation's 9 bound callers (A-RT0-CALLERS) minus the two already on the page -- the traced
  #   handler DoAfterPostOperation and DoAfterDeleteOperation, the AfterDelete row's handler: ImportJenVICI,
  #   ImportLK, ImportNikon, ImportSheffield, ImportZEISS, AddOperation, VerifyAll                       7
  #   the fill lines (A-RT0-FILLS) minus the traced LoadAllForFolder :1207 and BuildSchema :769 (reaches no
  #   crossing): VerifyAll :4306                                                                            1
  # LoadOneTable's other callers are NOT routes: it takes the table from its caller, so only a caller passing the
  # anchor's table reaches the anchor -- those ARE the fill lines. SendDeltaOperation names 'TABLE=OPERAT|' itself,
  # so every caller is a route. Measured 2026-09-28. OWNER-ACCEPTED 2026-09-28 (AC-10): all callers count; dataset scope; anchors only
  Chk 'A-RT6-ALSO'      $rt0.RtAlso 9
  Chk 'A-RT6-ALSOROWS'  $rt0.RtAlsoRows ('FIRES FMTOperation.AfterDelete -> DoAfterDeleteOperation|' + ((@('CALLS TBlueprint_ViewModel.SendDeltaOperation') * 7) -join '|') +
                                         "|LOADS FMTOperation VIA TBlueprint_ViewModel.LoadOneTable 'OPERAT'")
  Chk 'A-RT6-ALSOANCHORS' $rt0.RtAlsoAnchors ('Blueprint4.ViewModel.pas:640,Blueprint4.ViewModel.pas:1853,Blueprint4.ViewModel.pas:2175,Blueprint4.ViewModel.pas:2441,' +
                                              'Blueprint4.ViewModel.pas:3124,Blueprint4.ViewModel.pas:3416,Blueprint4.ViewModel.pas:4099,Blueprint4.ViewModel.pas:4273,Blueprint4.ViewModel.pas:4306')
  # AC-1 / AC-2 with both directions in the text: the checker passes it and it reads back byte for byte
  Chk 'A-RT6-FORMA'     $rt0.RtFormA '0/identical'
  # T5-R13 (failed before: rspNotFound / rspDenied read as success, the if read `both`): success is rspOK / rspData only
  Chk 'A-RT6-SUCCESSRSP' $rt0.RtSuccessRsp 'True,True,False,False,False,then'
  # Review Focus 1: a control whose datasource is NOT dangling completes -- no throw. The Task 3 resolver stops at
  # ANCHOR with a named reason: the chain reaches the property MemTable, follows it to its field FMemTable (final-review
  # I8), and the table comes through the constant CAUSFAIL_TABLE, which no literal on the dataset's line names. So TableColumn is empty
  # (the brief expected CAUSFAIL.REASON -- a resolver finding, reported, not fixed here)
  Chk 'A-RT6-OTHER'     $rt0.RtOther ':True:True'
  # RE-PINNED by final-review I8 (a dataset PROPERTY is followed to the field its read accessor names -- here the
  # member_accesses fact on the assignment line :125, certain): the anchor dataset is FMemTable, one step later. It still
  # stops -- the table comes through the constant CAUSFAIL_TABLE (a follow-on) -- but on the right symbol. Was 'MemTable|6/1|...MemTable...'
  Chk 'A-RT6-OTHERSTOP' $rt0.RtOtherStop 'FMemTable|7/1|no upper-case table-name literal shares a line with FMemTable in uCausFail.ViewModel -- the table cannot be inferred'
  # fix wave (FW-R2): the BINDS note's assignment-line locator is qualified with the FORM unit's filename --
  # `dsrCausFail.DataSet:= FViewModel.MemTable` sits in uCausFailForm.pas:125, a DIFFERENT file than the BINDS
  # step's own anchor (FMemTable's declaring unit, uCausFail.ViewModel.pas). Was '... bound on the assignment line :125'
  Chk 'A-RTF-R2-BINDNOTE' $rt0.RtOtherBindNote "BINDS FMemTable : TFDMemTable @uCausFail.ViewModel.pas:45 -- the anchor dataset, the read accessor of MemTable, bound on the assignment line uCausFailForm.pas:125"
  # Task 7 fix round 1 (I3): stopped at its anchor's [06] -> no reach in the title, six sections noted "not walked"
  # naming [06] (was "How frmCausFail.colREASON reaches frmCausFail.colREASON and goes back" and six bare headers)
  # RE-PINNED by final-review I8: the stop is now [07] (READS MemTable, then BINDS FMemTable); was [06]
  Chk 'A-RT6-OTHERSHAPE' $rt0.RtOtherShape 'Why frmCausFail.colREASON cannot be traced|6|[07]'
  # Task 6 FIX ROUND 1. Important 1 (threw before: no span): the guard-line rule takes only a call INSIDE the condition,
  # between `if` and `then` -- Foo on a one-line guard `if not X(A) then begin Foo(B); Exit; end;` is failure-branch code,
  # as is Log after the `then` of a wrapped one; the rule used to take every bound call on the if line
  Chk 'A-RT6-GUARDSPAN' $rt0.RtGuardSpan 'X:True,Foo:False,Y:True,Z:True,Log:False'
  # Important 2 + M1 (threw before): the routines on each client path before its first crossing are already on the page
  # (handler 10 -> helper 11 -> sender 12: the helper is NOT another caller); a SERVER-actor crossing (owner 99, a SERVER
  # id) is never taken as a sender, and nothing after a path's crossing counts (owner 77)
  Chk 'A-RT6-TRACEDIDS' $rt0.RtTracedIds 'callers 10,11,12,20; senders 12@50,20@70'
  # T6-R1 (was LOADS)
  Chk 'A-RT6-EMPTYVERB' $rt0.RtEmptyVerb 'EMPTIES'
  # T6-R2 (threw before: sections had no note): an empty ALSO writes no row -- checker exit 0, 0 steps, 0 unresolved --
  # and a generated `  -- no other route to this anchor in the index` under its header, read back byte for byte
  Chk 'A-RT6-ALSOEMPTY' $rt0.RtAlsoEmpty '0/0/0/True/identical'
  # M2 (threw before; the old rule, ANY literal naming the table, answered True,True): only the payload literals count
  Chk 'A-RT6-TABLESENDER' $rt0.RtTableSender 'False,True'
  # M3 (threw before): an assignment's expression anywhere on its line, as written; a statement that runs on gives none
  Chk 'A-RT6-ASSIGNAT'  $rt0.RtAssignAt "['SELECT ' + C + ' FROM ' + T],[SQL + ' WHERE ' + W],[]"
}
# ---- round-trip, Task 7: the golden matcher and the whole-trace checks, on the REAL trace ----
Note 'round-trip: the golden ...'
Step 'E-RT' {
  # AC-5: matched / disclosed / missing. A node is matched by a row in its FILE at the golden's line, IN its routine,
  # or ABOUT it (subject `X` or `Q.X`) -- a mere mention is not a match (A-RT7-CLASSIFY). The golden's 17: all matched,
  # nothing disclosed. Where a line differs the golden cites the declaration and the trace the body (4 277->3948,
  # 5 279->3960, 7 63->1209, 8 75->389, 9 59->199, 11 63->183, 14 321->1207 the fill call IN it, 15 266->1123,
  # 17 59->502). Two golden lines are COMMENTS (fix round 1, I1 -- A-RT7-DOCDECL): 6 is the far-side CONTRACT
  # IPipeSessionBuilder.HandleDelta @Pipes.Protocol.pas:392, the declaration its :389 payload contract sits above
  # (RE-PINNED 6=14/facet@55 -> 6=14/facet@392 by the doc-line rule: the TCommandID.cmdDelta constant at :55 is the
  # command id, a different fact, and no longer matches); 13 is PushTableChanged's body @:401, the implementation of
  # the :124 declaration its :120 comment sits above (unchanged)
  # RE-PINNED 2026-09-28 (extractor 1.20, see A-RT0-TABLELIT): node 12's column row MS1.SQL:2808 -> 2809
  Chk 'A-RT7-NODES'     "$($rt0.GoldenMatched)/$($rt0.GoldenDisclosed)/$($rt0.GoldenMissing)" '17//'
  Chk 'A-RT7-NODESBY'   $rt0.GoldenMatchedBy ('1=07@78,2=05@99,3=10@639,4=11@3948,5=12@3960,6=14/facet@392,7=16@1209,8=17@389,9=25@199,' +
                                              '10=21@130,11=31@183,12=09@2809,13=37@401,14=44@1207,15=45@1123,16=46/facet@57,17=48@502')
  # I1: the golden lines that are a line of the comment block directly above a declaration, from INDEX facts only
  # (`comment` string_literals covering every line down to the next symbol, nothing indexed between; symbol_docs
  # first): `<file>:<golden>=<decl>-<decl end>/<impl>-<impl end>`, every clone that indexes the file agreeing
  Chk 'A-RT7-DOCDECL'   $rt0.GoldenDocDecl 'Pipes.Protocol.pas:389=392-392/0-0,uBroadcastServer.pas:120=124-124/401-441'
  # ... and the negative: WITHOUT the :392 CONTRACT row node 6 is MISSING (16 matched) -- not matched via :55
  # (before the rule: '|17', node 6 read matched through the command-id constant)
  Chk 'A-RT7-DOCNEG'    $rt0.GoldenDocNeg '6|16'
  # I2 (controller ruling on golden READ [28]-[29]): the BLOBS / WHERE keys and the column list come from transport-
  # convention helpers, not steps -- DISCLOSED, never silently ignored. Goes red if the list changes or the walk
  # starts producing one (then it moves right of the `||`, as the synthetic A-RT7-FACTSPROD shows)
  Chk 'A-RT7-FACTS'     "$($rt0.GoldenFactsReason) | $($rt0.GoldenFactsDisclosed) || $($rt0.GoldenFactsOnPage)" ('transport-convention helper, not a step | ' +
                          'uPipeSessionBuilder.pas:533 READ [28] READS BLOBS key,uPipeSessionBuilder.pas:534 READ [28] READS WHERE key,' +
                          'uPipeSessionBuilder.pas:538 READ [29] BUILDS column list FROM Def.NonBlobCols || ')
  Chk 'A-RT7-FACTSPROD' $rt0.GoldenFactsProduced '2 || uPipeSessionBuilder.pas:533@07'
  # M: no numbered item of the real trace is unanchored; a nulled anchor ([05]) and a colon-less one ([07]) are
  # REPORTED -- both counted unanchored, node 2 (whose only row is [05]) missing -- where they used to throw
  Chk 'A-RT7-UNANCHORED' "$($rt0.GoldenUnanchored)/$($rt0.GoldenUnanchoredNeg)" '/05,07|2|16'
  # AC-7: every golden guard is a condition at its if/except line holding its word verbatim, client AND server
  Chk 'A-RT7-GUARDS'    "$($rt0.GuardsMatched)/$($rt0.GuardsDisclosed)/$($rt0.GuardsMissing)" '12//'
  Chk 'A-RT7-GUARDSBY'  $rt0.GuardsBy '1@11,2@12,3@12,4@18,5@18,6@25,7@26,8@31,9@45,10@55,11@56,12@65'
  # the matcher can FAIL and DISCLOSE (synthetic trace): LoadOneTable matched; a mention of LoadAllForFolder and GetTable
  # in the wrong file are not; a STOPS with its ask discloses 17 (E2), one without an ask leaves 13 missing (*);
  # guard 2 one line off is not matched, a STOPS at its line with E1 discloses it
  Chk 'A-RT7-CLASSIFY'  $rt0.GoldenClassify '15=01@1123 | 17:E2 | 1,2,3,4,5,6,7,8,9,10,11,12,13*,14,16 || 1@01 | 2:E1 | 3,4,5,6,7,8,9,10,11,12'
  # I4 (REPLACED, fix round 1; the name is kept): was a count of `not (` conditions minus an exclusion list keyed on
  # this golden's own text (0, and 0 on every mutation below). Now `bad/checked/skipped`: every condition not in the
  # ` ... raises` or `case X of` form occurs VERBATIM in the fresh source from its anchor line (whitespace collapsed,
  # at identifier boundaries, not behind a dropped `not`)
  Chk 'A-RT7-NONEGATE'  $rt0.TraceNegated '0/27/4'
  # ... and goes red on a mutated quote: `not ` prefixed to guard 1 (:3950), `not ` dropped from guard 6 (:431)
  Chk 'A-RT7-NONEGATEMUT' $rt0.TraceNegatedMut '1:Blueprint4.ViewModel.pas:3950,1:uGenericTableRoute.pas:431'
  # AC-1 on the generated trace, with the verb set the checker now reads after an actor word too (Task 2 gap:
  # `[NN] SERVER <anything>` passed as a section header, exit 0 before -- A-RT7-ACTORMUT); the golden gains EDITS
  Chk 'A-RT7-FORMA'     $rt0.TraceFormA 0
  Chk 'A-RT7-ACTORMUT'  $rt0.TraceFormAActorMut 1
  Chk 'A-RT7-VERBS'     $rt0.TraceVerbs 'APPLIES,ATTACHES,BINDS,CALLS,DESERIALIZES,EMPTIES,FIRES,LOADS,OMITS,OPENS,READS,RECEIVES,ROUTES,RUNS,SENDS,SERIALIZES,SETS,WRITES'
  Chk 'A-RT7-GOLDENVERBS' $rt0.GoldenVerbs ('ADDS,APPLIES,ATTACHES,BINDS,BROADCASTS,BUILDS,CALLS,COUNTS,DESERIALIZES,EDITS,EXTRACTS,FIRES,LOADS,LOGS,' +
                                           'NOTIFIES,OPENS,PREFIXES,READS,RECEIVES,ROUTES,RUNS,SENDS,SERIALIZES,SETS,SPLITS,VALIDATES,WRITES')
  # AC-2, AC-4, AC-11 on the generated trace. P14: AllClickable is COMPUTED (0 unclickable of 118 anchors), and
  # the same check counts 1 when the [07] anchor is cut from the text
  Chk 'A-RT7-ROUNDTRIP' $rt0.TraceRoundTrip 'identical'
  Chk 'A-RT7-BYTES'     $rt0.TraceBytes '0/0/noBOM'
  Chk 'A-RT7-ANCHORS'   $rt0.TraceAnchors '0/118/True'
  Chk 'A-RT7-ANCHORCUT' $rt0.TraceAnchorsCut '1/True'
  # T4-C3: the case guard quotes `case ARequest of` verbatim; the else arm is generated text (was "case ARequest of else")
  # RE-PINNED 2026-10-06 (R5 Part 0): conditions are written unquoted -- the same conditions, the quotes gone; no count moved
  Chk 'A-RT7-CASE'      $rt0.TraceCaseCond 'UNLESS case ARequest of @uGenericTableRoute.pas:188 -- else arm at :192; ask E1'
}
# ---- round-trip, R5: the CHART drawn from the trace (spec 2026-10-05-R5-round-trip-chart-design.md) ----
# MEASURED 2026-10-06 on the 1.21.1 clones, every value read from the files the runs WROTE (.dot / .svg), not from the
# renderer's Manifest (Test-RoundTripHelpers section 12). Owner answers (spec section 10): the golden shows all 9 ALSO
# rows (the fold is covered by A-R5-ALSOFOLD), a sub-walk both directions run is ONE row with both numbers.
Note 'round-trip: the chart ...'
Step 'E-R5' {
  # every step drawn or disclosed, never both, together exactly 1..76; every condition drawn, verbatim, unquoted
  Chk 'A-R5-COVER'      $rt0.R5Cover '76/0/0|both 0|extra 0'
  # fix round 1 (I2): checked PER STEP -- each condition against the guard rows under ITS step (it was a set test over
  # every guard row, blind to a guard drawn on the wrong step), the disclosed count measured (it was a literal 0)
  Chk 'A-R5-CONDS'      $rt0.R5Conds '31/0/0'
  Chk 'A-R5-VERBATIM'   $rt0.R5Verbatim '31/31'
  # facets the same way: drawn / in the row's tooltip (REGENERATE) / disclosed / missing
  Chk 'A-R5-FACETS'     $rt0.R5Facets '19/0/0/0'
  # ... and RED on a guard moved to another step: [11]'s UNLESS FSuppressEvents drawn under [13]
  Chk 'A-R5-CONDMUT'    $rt0.R5CondMut '30/0/1 [11] UNLESS @Blueprint4.ViewModel.pas:3950'
  # fix round 1 (I1): each edge into a crossing names what crosses -- the request's command, the response's WHOLE
  # alternative set (it read `[41] rspError`, the first WITH word: the failure code on the success path)
  Chk 'A-R5-CROSSLABEL' $rt0.R5CrossLabels '[14] cmdDelta | [41] rspError or rspOK | [46] cmdTableLoad | [64] rspData or rspError'
  # fix round 1 (5): a call edge carries `from :<line>` (spec 3.3); a row on a leaf not held at one path stays unlinked
  # with the "ambiguous file name" tooltip (spec 5) -- the golden drawn without uDatasetsDef.pas in the path map
  Chk 'A-R5-CALLFROM'   $rt0.R5CallFrom '[12] from :3951'
  Chk 'A-R5-AMBIGUOUS'  $rt0.R5Ambiguous '12 rows|12 unlinked with the tooltip|manifest 12'
  # fix round 1 (3): a step text past 5 lines is cut in its BODY, its grade kept (synthetic, 60 words, [inferred])
  Chk 'A-R5-SHORTEN'    $rt0.R5Shorten 'Word40 ... [inferred] @X.pas:1|5 lines|1 legend row'
  Chk 'A-R5-NOQUOTE'    $rt0.R5NoQuote 0
  # the golden's 17 nodes and 12 guards are DRAWN rows (not disclosures): matched/disclosed/missing
  Chk 'A-R5-GOLDNODES'  $rt0.R5GoldNodes '17/0/'
  Chk 'A-R5-GOLDGUARDS' $rt0.R5GoldGuards '12//'
  # one crossing node per send anchor (:3985, :1136), each holding its request and its response
  Chk 'A-R5-XING'       $rt0.R5Xing '2/4'
  Chk 'A-R5-STOPS'      $rt0.R5Stops '2:E4,E4'
  Chk 'A-R5-COUNTS'     $rt0.R5Counts 'identical'
  Chk 'A-R5-FROMTEXT'   $rt0.R5FromText 'identical'
  # nodes per lane client/pipe/server/database: client = anchor chain, event, DoAfterPostOperation, SendDeltaOperation,
  # LoadAllForFolder, LoadOneTable, ALSO; pipe = the two crossings; server = 12 routine cards; database = 2 STOPS + the column
  Chk 'A-R5-LANES'      $rt0.R5Lanes '7/2/12/3'
  # one row, both numbers: the column OPERAT.NAME read by both directions, and LoadFromInternal's sub-walk
  Chk 'A-R5-MERGE'      "$($rt0.R5Merged)|$($rt0.R5Column)" '[20]/[50],[21]/[51],[22]/[52],[23]/[53],[24]/[54],[09]/[60]|09,40,60'
  # failure edges: the two Rollbacks of the write, the read Rollback, and CancelUpdates at :3999
  Chk 'A-R5-FAILURE'    "$($rt0.R5Failure)/$($rt0.R5Cancel)" '4/1'
  # every <a> of the svg is a linked row, plus ONE: the header's REGENERATE tooltip; no row unlinked on these clones
  Chk 'A-R5-LINKS'      $rt0.R5Links '116=115+1/0'
  Chk 'A-R5-ASCII'      $rt0.R5Ascii '0/0'
  # owner answer 4: an ALSO cap of 6 on the same trace folds rows [74]-[76] into ONE disclosure row, repeated in the Legend
  Chk 'A-R5-ALSOFOLD'   $rt0.R5AlsoFold '73/3/0|0 not in the Manifest|+3 more routes not shown -- [74]-[76], full text in trace.dlgraph || +3 more routes not shown in ALSO -- [74]-[76], full text in trace.dlgraph'
  # the holdout MSCLIST.NUM: 103 steps drawn or disclosed, none missing; 35 of 35 conditions drawn; 4 CROSSES; 2 STOPS
  # RE-PINNED fix round 1 (I2): conditions per step, drawn/disclosed/missing of all 35 (was a set count, '35/35')
  Chk 'A-R5-HOLD'       $rt0.R5Hold '103/0|conds 35/0/0 of 35|xing 4|stops 2|lanes 7/2/13/3'
  # the calculated field: its STOPS node and a DERIVED card of 18 rows, each REGENERATE in its row's tooltip
  # RE-PINNED fix round 1 (I2): + its facets per step -- 2 drawn (the anchor's VIA at [01], the STOPS' VIA FtrNameString)
  # RE-PINNED Task 5b (owner 2026-10-06: DERIVED card capped like its components): 18 plain rows past the 14-row cap --
  # 14 drawn (14 REGENERATE in tooltips), the last 4 folded into the card's disclosure row (their 4 REGENERATE disclosed);
  # was '1/18|tooltip regenerate 18|27/0/0|facets 2/18/0/0' while DERIVED was exempt
  Chk 'A-R5-CALC'       $rt0.R5Calc '1/14|tooltip regenerate 14|23/4/0|facets 2/14/4/0'
  # a synthetic 300-step trace (150 routine cards of 2 steps): the ladder engages (150 nodes > 45) and the Legend says the
  # chart is drawn anyway. RE-PINNED Task 5b (owner 2026-10-06, a fold that saves no row is not made): a 2-row card folded
  # is header + 1 disclosure row + 1 Legend row, so no card folds -- all 300 drawn, ladder empty (was 'cards|...|0/300/0')
  Chk 'A-R5-SIZE'       $rt0.R5Size '|nodes 150|300/0/0|1 cap row'
  # Task 5b rule 1 (owner 2026-10-06, "1 row summary is OK"): 100 cards of 3 steps all fold under the ladder; above the
  # 5-fold threshold the Legend holds ONE summary row, its ranges measured exact against the undrawn steps (a mutated
  # range reads 'ranges mismatch' -- measured, not assumed)
  Chk 'A-R5-SUMMARY'    $rt0.R5Summary '1 legend fold row|0/300/0|summary ranges exact|100 cards folded (300 rows not shown) -- [01]-[300] -- the full trace is in the text answer|mut ranges mismatch'
  # ... cards alternating 3 and 2 steps: the 2-step cards stay whole, the 60 folded cards' ranges exceed one row, so the
  # summary carries only the count -- 180 = exactly the undrawn steps (a mutated count reads 'counts mismatch')
  Chk 'A-R5-SUMCOUNT'   $rt0.R5SumCount '1 legend fold row|120/180/0|summary counts exact|60 cards folded (180 rows not shown) -- 180 steps -- the full trace is in the text answer|mut counts mismatch'
  # ... the threshold: 5 folds keep 5 per-fold Legend rows; 6 folds become 1 summary row, coverage still exact
  Chk 'A-R5-FOLDTHRESH' $rt0.R5FoldThresh '5 cards: 5 per-fold/0 summary|6 cards: 0 per-fold/1 summary|cover 0 missing, summary counts exact'
  # ... a fold that saves no row is not made: at a row cap of 2 a 4-step card stays whole, a 5-step card folds 3
  Chk 'A-R5-NOSAVE'     $rt0.R5NoSave 'TSyn.R1: 4 drawn + 0 disclosure | TSyn.R2: 2 drawn + 1 disclosure'
  # Task 5b rule 2 (owner 2026-10-06, "calculated fields get same treatment as their components"): a DERIVED card over the
  # 14-row cap folds with a disclosure row; under the cap it is unchanged
  Chk 'A-R5-DERIVEDCAP' $rt0.R5DerivedCap '20: 14 drawn + +6 more steps not shown -- [15]-[20]|missing 0 || 10: 10 drawn + |missing 0'
  # R19: an unknown section, and an actor outside the TIERS, throw -- never a default lane
  Chk 'A-R5-UNKNOWN'    $rt0.R5Unknown 'refused/refused'
}
# ---- round-trip, the final review's fix wave (I1-I9, M2, M3, M7) ----
Note 'round-trip: the final review ...'
Step 'E-RTF' {
  # I1 (synthetic walk, no index): an Exit guard's IfLine is walked for its CONDITION only. Before: `APPLIES
  # FMT.CancelUpdates` and `SENDS rspError` were path steps carrying the guards that skip them (inverted), and
  # the WHEN guard's else note named its own then branch. After: the failure branch is the else note, nothing else
  Chk 'A-RTF-I1-WALK'   $rt0.FinI1Walk ('SERIALIZES FMT.SaveToStream [UNLESS not Ready (else FMT.CancelUpdates @fin-i1a.pas:4), UNLESS Failed (else rspError)] > ' +
                                        'APPLIES FMT.ApplyUpdates [] || pending:  ## APPLIES FMT.ApplyUpdates [WHEN Ready (else FMT.CancelUpdates @fin-i1b.pas:3)] || pending: ')
  # ... the failure span of a guard's `then` line: up to the if's own `;` (a statement after it is the path), an
  # else-branch Exit from its else, a nested if keeping its else, no span when the else is on a later line
  Chk 'A-RTF-I1-SPAN'   $rt0.FinI1Span '[then Exit;],[else Exit;],[then begin if B then X else Y; Exit; end;],[then Exit],[]'
  # I4: the WRITE direction starts at AfterPost even when an AfterDelete (or a BeforePost) is wired above it
  Chk 'A-RTF-I4-WIRING' $rt0.FinI4Wiring 'AfterPost@15,AfterPost@20,BeforePost@5,AfterDelete@10'
  # I5 (synthetic walk): a call one if DEEPER in another table's branch is omitted too (it was a path step)
  # RE-PINNED 2026-10-06 (R5 Part 0): conditions are written unquoted -- the same conditions, the quotes gone; no count moved
  Chk 'A-RTF-I5-OMITS'  $rt0.FinI5Omits ("OMITS 1 step(s) in branches for other tables, every enclosing if read up to a loop or case arm -- not walked, the branch conditions: " +
                                        "WHEN T = 'MSCLIST' @fin-i5.pas:3 > APPLIES FMT.CommitUpdates")
  # RC-R6 (synthetic walk): a transport-convention callee whose body calls WriteFile is KEPT as a CALLS step (not
  # descended); a logger-shaped transport callee is skipped; a non-transport callee with an empty body is pruned
  Chk 'A-RC-R6-OUTWARD' $rt0.RcR6Outward 'CALLS TB.PushX [] || pending: '
  # M2: the ask on each ANCHOR step of OPERAT.NAME || of colREASON. Before: 08=E4 (the table-literal hop) and colREASON
  # 04=E4 (FViewModel's declared type matched by name) -- E4 (populated fb_datasets) retires neither. Now the literal hop
  # names none (the walk's own inference) and the rhs-type hop names type-use-binding (0 of 60,603 type_use refs bound)
  Chk 'A-RTF-M2-ASKS'   $rt0.FinM2Asks '01=-,02=-,03=-,04=in-class-field-reads,05=in-class-field-reads,06=-,07=-,08=-,09=E4 || 01=-,02=-,03=-,04=type-use-binding,05=-,06=-,07=-'
  # M3: AS OF is each index's own schema_meta indexed_at_unix (CLIENT / SERVER / SQL, UTC to the minute) -- it was the
  # CLIENT clone FILE's UTC date, 2026-09-28, a stamp the header did not read
  # RE-PINNED 2026-09-28 (re-clone): the new clones' indexed_at_unix 1790633987 / 1790633975 / 1790633871 (was
  # 02:46Z / 02:46Z / 02:45Z on the r=1.9 clones). RE-PINNED 2026-10-05 (re-clone at 1.21.1): indexed_at_unix
  # 1791217538 / 1791217275 / 1791216661 (was 2026-09-28T22:19Z/22:19Z/22:17Z)
  Chk 'A-RTF-M3-ASOF'   $rt0.FinM3AsOf '  INDEX Micronite2027 + MicroniteMW1Service + SQL AS OF 2026-10-05T16:25Z/2026-10-05T16:21Z/2026-10-05T16:11Z'
}

Note 'round-trip negatives ...'
# Task 7 fix round 1 (I3): a trace that STOPS at its anchor claims no reach. Its shape, read off the written text:
# the TITLE, the sections carrying the GENERATED `  -- not walked: the trace stopped at [NN]` note (T6-R2: a note,
# never a STOPS, never unresolved), the stop numbers those notes name, the Test-FormA exit, and the Read-FormA
# round trip. Before the fix: "How X reaches X and goes back" and six bare section headers (readable as "no path").
function Get-StoppedTraceShape([string] $Text, [string] $Path) {
  . "$SRC\Trace.FormA.ps1"
  $ttl = $(if ($Text -cmatch '(?m)^  TITLE "([^"]*)"\r$') { $Matches[1] } else { '' })
  $nw = @([regex]::Matches($Text, '(?m)^([A-Z]+)\r\n  -- not walked: the trace stopped at (\[\d+\])\r$'))
  & "$SRC\Test-FormA.ps1" -Fixture $Path -Quiet 6>$null | Out-Null
  $fa = $LASTEXITCODE
  $rtp = $(try { if ((Write-FormA (Read-FormA $Text)) -ceq $Text) { 'identical' } else { 'differs' } } catch { "threw: $($_.Exception.Message)" })
  "$ttl|$(($nw | ForEach-Object { $_.Groups[1].Value }) -join ',')|$((@($nw | ForEach-Object { $_.Groups[2].Value } | Select-Object -Unique)) -join ',')|$fa|$rtp"
}
# AC-13 (ruling P3, asserted on the EMITTER): not data-bound -> no throw, ONE numbered STOPS, a trace the checker passes
Step 'RT-N1' {
  $script:rtn1 = & "$SRC\Emit-RoundTrip.ps1" -Target 'frmBlueprint4.cxGroupBox16' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir 6>$null
  & "$SRC\Test-FormA.ps1" -Fixture $rtn1.Trace -Quiet | Out-Null
  Chk 'A-RT-N1'         "$($rtn1.Steps)/$($rtn1.Unresolved)/$($rtn1.Conditions)/$($rtn1.AllClickable)/$LASTEXITCODE" '1/1/0/True/0'
  if ($rtn1.Text -cnotmatch '\[01\] STOPS frmBlueprint4\.cxGroupBox16 \(TcxGroupBox\) is not data-bound') { Fail 'A-RT-N1' 'the one step is not the STOPS naming why' }
  if ($rtn1.Text -cnotmatch 'END TRACE  1 steps, 0 conditions, 0 crossings, 1 unresolved\.') { Fail 'A-RT-N1' 'END TRACE does not count the STOPS' }
  # I3: no reach claimed; all six later sections say they were not walked, naming the [01] STOPS
  Chk 'A-RT-N1-SHAPE'   (Get-StoppedTraceShape $rtn1.Text $rtn1.Trace) 'Why frmBlueprint4.cxGroupBox16 cannot be traced|WRITE,SERVER,DATABASE,RESPONSE,READ,ALSO|[01]|0|identical'
  # A-R5-NOTBOUND: a one-step trace is a one-node chart, never an empty one -- the STOPS node alone (its ANCHOR has no
  # chain rows), and the Legend names each of the six sections that were not walked
  $n1d = [IO.File]::ReadAllText($rtn1.Dot)
  Chk 'A-R5-NOTBOUND'   "$(([regex]::Matches($n1d, '(?m)^\s+n\d+ \[')).Count)/$(([regex]::Matches($n1d, 'shape=note')).Count)/$(([regex]::Matches($n1d, '[A-Z]+ -- not walked: the trace stopped at \[01\]')).Count)" '1/1/6'
}
# Review Focus 2: TABLE.COLUMN loaded by several datasets -> ONE STOPS naming all five (the brief said three: the
# clone holds five, A-RT3-COLUMN), no throw
Step 'RT-N2' {
  $script:rtn2 = & "$SRC\Emit-RoundTrip.ps1" -Target 'OPERAT.NAME' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir 6>$null
  Chk 'A-RT-N2'         "$($rtn2.Steps)/$($rtn2.Unresolved)/$($rtn2.TableColumn)" '1/1/OPERAT.NAME'
  # I3: the same shape, and the N2 trace passes Test-FormA and reads back byte for byte too
  Chk 'A-RT-N2-SHAPE'   (Get-StoppedTraceShape $rtn2.Text $rtn2.Trace) 'Why OPERAT.NAME cannot be traced|WRITE,SERVER,DATABASE,RESPONSE,READ,ALSO|[01]|0|identical'
  if ($rtn2.Text -cnotmatch '\[01\] STOPS OPERAT\.NAME: 5 datasets load OPERAT in this index \(AssignGroups\.ViewModel\.TAssignGroupsViewModel\.FMTOperat, .*ControlPlan2\.ViewModel\.TControlPlan_ViewModel\.FMTOperation\)') { Fail 'A-RT-N2' 'the STOPS does not name the five datasets' }
}
# final-review I2 (a): a direction that stops AFTER the anchor resolved. frmAssignGroups.grdFtrsColNum is a read-only
# listing: its dataset FMTFtrs (AssignGroups.ViewModel, behind the property FtrsMT -- I8) has NO event wiring. Found on
# the CLIENT clone by querying every dataset field that feeds a `.DataSet :=` and has no AfterPost/.../OnReconcileError
# member-access in its unit (14 fields), then the field-bound controls of those view models' forms. The WRITE STOPS
# ([09], E3) ends the write direction: SERVER / DATABASE / RESPONSE carry the generated `not walked` note naming it (not
# a STOPS, not unresolved), and the title claims only the READ direction. Before the fix: "How MSCLIST.NUM reaches ...
# and goes back" over three bare headers (and, before I8, the anchor stopped on the property FtrsMT)
Step 'RT-NOWIRE' {
  $script:rtnw = & "$SRC\Emit-RoundTrip.ps1" -Target 'frmAssignGroups.grdFtrsColNum' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $OutDir 6>$null
  & "$SRC\Test-FormA.ps1" -Fixture $rtnw.Trace -Quiet 6>$null | Out-Null
  Chk 'A-RT-NOWIRE'       "$($rtnw.Title)|$($rtnw.Notes)" ('How MSCLIST.NUM reaches frmAssignGroups.grdFtrsColNum (the way back stops at step 9)|' +
                                                           'SERVER=not walked: the write direction stopped at [09] | DATABASE=not walked: the write direction stopped at [09] | ' +
                                                           'RESPONSE=not walked: the write direction stopped at [09] | ALSO=no other route to this anchor in the index')
  Chk 'A-RT-NOWIRE-COUNTS' "$($rtnw.Steps)/$($rtnw.Conditions)/$($rtnw.Crossings)/$($rtnw.Unresolved)|$($rtnw.WriteSteps)/$($rtnw.ReadSteps)/$($rtnw.AlsoSteps)|$LASTEXITCODE|$($rtnw.AllClickable)" '33/10/2/2|1/24/0|0|True'
  # fix wave (FW-R2): the same locator fix on a SECOND property (FtrsMT/FMTFtrs) -- the datasource wiring
  # `dsrFtrs.DataSet:= FViewModel.FtrsMT` sits in AssignGroups.pas:125 (the form), a different file than the
  # BINDS step's anchor (FMTFtrs declared in AssignGroups.ViewModel.pas). Was '... bound on the assignment line :125'
  $nwBind = (@(($rtnw.Text -split "`r`n") | Where-Object { $_ -match '^\[\d+\] BINDS FMTFtrs ' }))[0] -replace '^\[\d+\] ', ''
  Chk 'A-RTF-R2-NOWIRE' $nwBind 'BINDS FMTFtrs : TFDMemTable @AssignGroups.ViewModel.pas:43 -- the anchor dataset, the read accessor of FtrsMT, bound on the assignment line AssignGroups.pas:125'
}
# final-review I2 (b), synthetic: the server side stops but the walk goes on. No corpus case on the SERVER clone, so the
# CLIENT clone stands in as the server index -- it holds no dispatch routine (A-RT0-DISPATCH: Pipes.Commands is not in it),
# so both directions' server STOPS (E2) fire. The DATABASE tier is not walked (the write one gets the note; READ is one
# section and simply has no DATABASE step), and each response WITH says the response is unknown. Before the fix:
# Get-DatabaseSteps ran on the lone STOPS -- "no walked routine names the UPDATE statement ..., applied in  at <enum
# declaration>", a WRITES/READS column step -- and WITH read "no rsp* constant read in the handler"
Step 'RT-SRVSTOP' {
  $script:rtss = & "$SRC\Emit-RoundTrip.ps1" -Target 'frmBlueprint4.dxDBGrid1OperationVName' -DbPath $DbCli -ServerDbPath $DbCli -SqlDbPath $DbSql -OutDir (Join-Path $OutDir 'rt-srvstop') 6>$null
  $ssl = $rtss.Text -split "`r`n"
  Chk 'A-RT-SRVSTOP'      "$($rtss.Title)|$($rtss.Notes)" 'Where the trace between frmBlueprint4.dxDBGrid1OperationVName and OPERAT.NAME stops (steps 15 and 22)|DATABASE=not walked: the write direction stopped at [15]'
  Chk 'A-RT-SRVSTOP-SHAPE' "$($rtss.Steps)/$($rtss.Conditions)/$($rtss.Crossings)/$($rtss.Unresolved)|$(@($ssl | Where-Object { $_ -cmatch '^       WITH unknown, no server handler was reached @' }).Count)|$(@($ssl | Where-Object { $_ -cmatch '^\[\d+\] DATABASE |applied in  at|UPDATE statement' }).Count)" '35/8/4/2|2|0'
}
# Task 2 fix round 1: a stale file INSIDE the re-point walk (a copy of Blueprint4.ViewModel.pas, one trailing space)
# stops BOTH verbs [stale source] -- feeds-from and lands-where keep their own stale convention (a named stop, no
# table, exit 0; FF-STALE), the round-trip refuses (RT-STALE). The ViewModel holds the FDsrOperation.DataSet sites (:657).
Step 'FF-REPOINT-STALE' {
  $stDir = Join-Path $OutDir 'ff-repoint-stale'
  New-Item -ItemType Directory -Force $stDir | Out-Null
  $vmp = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.ViewModel.pas'
  $vl = [IO.File]::ReadAllLines($vmp); $vl[3949] = $vl[3949] + ' '
  [IO.File]::WriteAllText((Join-Path $stDir 'Blueprint4.ViewModel.pas'), (($vl -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $ov = @{ $vmp = (Join-Path $stDir 'Blueprint4.ViewModel.pas') }
  $script:ffrs = & "$SRC\Emit-FeedsFrom.ps1" -Control 'frmBlueprint4.dxDBGrid1OperationVName' -DbPath $DbCli -SqlDbPath $DbSql -OutDir $stDir -SourceOverride $ov
  Chk 'A-FF-REPOINT-STALE' "$($ffrs.RePoint)|$([string]$ffrs.ResolvedTable)|$($ffrs.TableColumn)|$($ffrs.StopReason)" 'stale|||[stale source] Blueprint4.ViewModel.pas differs from the indexed copy -- its 1 DataSet site(s) are not read'
  $script:lwrs = & "$SRC\Emit-LandsWhere.ps1" -Field 'frmBlueprint4.dxDBGrid1OperationVName' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $stDir -SourceOverride $ov
  Chk 'A-LW-REPOINT-STALE' "$($lwrs.ChainOutcome)|$([string]$lwrs.Table)|$($lwrs.TableColumn)|$($lwrs.ServerRows)|$($lwrs.StopReason)" 'stale|||0|[stale source] Blueprint4.ViewModel.pas differs from the indexed copy -- its 1 DataSet site(s) are not read'
  if ((Dot $ffrs) -match 'OPERAT\.NAME') { Fail 'A-FF-REPOINT-STALE' 'a TABLE.COLUMN is drawn past a stale file' }
}
# AC-14: a stale view model (a COPY with one trailing space, never the source) -> REFUSED, the file named, NO .dlgraph
Step 'RT-STALE' {
  $stDir = Join-Path $OutDir 'rt-stale'
  New-Item -ItemType Directory -Force $stDir | Out-Null
  $vmp = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.ViewModel.pas'
  $vl = [IO.File]::ReadAllLines($vmp); $vl[3949] = $vl[3949] + ' '
  [IO.File]::WriteAllText((Join-Path $stDir 'Blueprint4.ViewModel.pas'), (($vl -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $threw = $false; $m = ''
  try { & "$SRC\Emit-RoundTrip.ps1" -Target 'frmBlueprint4.dxDBGrid1OperationVName' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $stDir -SourceOverride @{ $vmp = (Join-Path $stDir 'Blueprint4.ViewModel.pas') } 6>$null | Out-Null }
  catch { $threw = $true; $m = $_.Exception.Message }
  if (-not $threw) { Fail 'A-RT-STALE' 'did not refuse' }
  elseif ($m -cnotlike '*Blueprint4.ViewModel.pas differs from the indexed copy*') { Fail 'A-RT-STALE' "refusal does not name the file: $m" }
  if (Get-ChildItem $stDir -Filter *.dlgraph) { Fail 'A-RT-STALE' 'left a .dlgraph behind after refusing' }
  $script:rtStale = $(if ($threw) { 'refused' } else { 'accepted' })
}
# A-R5-STALE (R5 spec section 8): the same refusal into a folder PRE-SEEDED with an earlier run's text and picture -- under
# the emitter's own names and the bundler's (trace.dlgraph, graph.*). The emitter removes its outputs FIRST, before the
# walk, so the refusal leaves none of them for a bundle to find and mistake for the answer (before R5 all 12 stayed).
Step 'RT-R5-STALE' {
  $stDir = Join-Path $OutDir 'rt-r5-stale'
  New-Item -ItemType Directory -Force $stDir | Out-Null
  $vmp = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.ViewModel.pas'
  $vl = [IO.File]::ReadAllLines($vmp); $vl[3949] = $vl[3949] + ' '
  [IO.File]::WriteAllText((Join-Path $stDir 'Blueprint4.ViewModel.pas'), (($vl -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $seed = @('trace.dlgraph', 'graph.svg', 'graph.dot', 'graph.png', 'graph.pdf', 'graph.plain') + @('dlgraph', 'svg', 'dot', 'png', 'pdf', 'plain' | ForEach-Object { "roundtrip_frmBlueprint4_dxDBGrid1OperationVName.$_" })
  foreach ($f in $seed) { [IO.File]::WriteAllText((Join-Path $stDir $f), 'an earlier run') }
  $m = ''
  try { & "$SRC\Emit-RoundTrip.ps1" -Target 'frmBlueprint4.dxDBGrid1OperationVName' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $stDir -SourceOverride @{ $vmp = (Join-Path $stDir 'Blueprint4.ViewModel.pas') } 6>$null | Out-Null; $m = 'accepted' }
  catch { $m = $(if ($_.Exception.Message -clike '*Blueprint4.ViewModel.pas differs from the indexed copy*') { 'refused' } else { "wrong: $($_.Exception.Message)" }) }
  Chk 'A-R5-STALE' "$m/$(@($seed | Where-Object { Test-Path (Join-Path $stDir $_) }).Count)" 'refused/0'
}
# A-R5-DOTFAIL (owner answer 3): dot fails -> the text is still delivered, ChartError carries dot's own words, and no
# chart output is left (no partial .svg). A stand-in dot.exe that prints an error and writes nothing; RT-N1's target
# (one step) keeps it fast. Fix round 1 (4): the stand-in writes a PARTIAL .svg before it fails -- the half-made
# picture a real dot can leave -- and the run must remove it (it is the .svg a bundle would otherwise show).
Step 'RT-R5-DOTFAIL' {
  $dfDir = Join-Path $OutDir 'rt-r5-dotfail'
  New-Item -ItemType Directory -Force $dfDir | Out-Null
  $fake = Join-Path $dfDir 'fake-dot.cmd'
  # dot's arguments: -Tsvg -o <svg> ...; %3 is the svg path
  [IO.File]::WriteAllText($fake, "@echo off`r`necho ^<svg partial^> > `"%~3`"`r`necho fake dot: syntax error near line 1 1>&2`r`nexit /b 1`r`n", (New-Object Text.ASCIIEncoding))
  $df = & "$SRC\Emit-RoundTrip.ps1" -Target 'frmBlueprint4.cxGroupBox16' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $dfDir -Dot $fake 6>$null
  $left = @(Get-ChildItem $dfDir | Where-Object { $_.Extension -in '.svg', '.dot', '.png', '.pdf', '.plain' }).Count
  # the svg existed when dot exited (Invoke-DotRun's "dot exited 1"), so the removal is what proves no partial picture
  Chk 'A-R5-DOTFAIL' "$(Test-Path $df.Trace)|$($df.Steps)|$($df.ChartError -like '*dot exited 1*fake dot: syntax error*')|$([bool]$df.Svg)|$left" 'True|1|True|False|0'
}
# the verb through the bundler: dispatch, the text AND its chart (R5; no svg before), -ServerDbPath / -SqlDbPath / -Depth in the regenerate command
# 6>$null: the emitter prints the whole trace (Write-Host), and its else notes quote 'OPERAT %s FAILED'
Step 'RT-ART' {
  $artRoot = Join-Path $OutDir 'bundle-rt'
  $art = & "$SRC\New-DiagramArtifact.ps1" -Question round-trip -Target 'frmBlueprint4.dxDBGrid1OperationVName' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutRoot $artRoot 6>$null
  $meta = Get-Content (Join-Path $art.Bundle 'meta.json') -Raw | ConvertFrom-Json
  Chk 'A-RT-ART-LABELS' "$($meta.leftLabel)/$($meta.rightLabel)" 'steps/unresolved'
  Chk 'A-RT-ART-COUNTS' "$($meta.leftCount)/$($meta.rightCount)" "$($rt0.RtCounts -split '/' | Select-Object -First 1)/$($rt0.RtCounts -split '/' | Select-Object -Last 1)"
  Chk 'A-RT-ART-DEPTH'  $meta.depth 4
  foreach ($flag in '-ServerDbPath ', '-SqlDbPath ', '-Depth 4') { if ($meta.regenerate -cnotlike "*$flag*") { Fail 'A-RT-ART' "the regenerate command drops $flag" } }
  if (-not (Test-Path (Join-Path $art.Bundle 'trace.dlgraph'))) { Fail 'A-RT-ART' 'no trace.dlgraph in the bundle' }
  $html = [IO.File]::ReadAllText((Join-Path $art.Bundle 'index.html'))
  if ($html -cnotmatch '<pre[^>]*>TRACE OPERAT\.NAME') { Fail 'A-RT-ART' 'index.html does not show the trace' }
  # A-R5-BUNDLE (RE-PINNED by R5: a round-trip bundle held NO graph.svg before -- the chart is drawn from the text now): the
  # bundle holds trace.dlgraph AND graph.svg, and the page shows both -- the chart, then the text
  Chk 'A-R5-BUNDLE' "$(Test-Path (Join-Path $art.Bundle 'trace.dlgraph'))/$(Test-Path (Join-Path $art.Bundle 'graph.svg'))|$($html -cmatch '(?s)<svg.*</svg>.*<pre[^>]*>TRACE OPERAT\.NAME')" 'True/True|True'
  # fix round 1 (I2, T8-R3): the footer names the text as what it is -- no paste-unchanged promise. RE-PINNED by R5: it
  # names the chart files before it (it named the text alone while the bundle held no chart)
  if ($html -cnotmatch '<footer>\s*graph\.svg &middot; graph\.png &middot; graph\.pdf &middot; graph\.plain \(geometry, same layout run\) &middot; trace\.dlgraph \(Form A text\) &middot; meta\.json' -or $html -cmatch 'DocInsight') { Fail 'A-RT-ART-FOOT' 'the round-trip bundle footer is not "graph.svg ... trace.dlgraph (Form A text) &middot; meta.json ..."' }
  # fix round 1 (I3): a text bundle is not a chart -- no "Every row" / "N click targets" chart wording
  if ($html -cmatch 'Every row is a real anchor|<b>\d+</b> click targets</span>|not click targets') { Fail 'A-RT-ART-NOTE' 'the text bundle page carries chart wording or the retired "not click targets" claim' }
  # DOC-R1 (supersedes T8-R1, 2026-09-28): every ` @File:line` anchor of the trace is a draglint:// link whose
  # path exists on disk, names the same leaf and line as the text, and the header says N of N.
  # Measured on the v=1.20 / r=1.11 clones: 126 anchors (12 files across CLIENT, COMMON, SERVER and SQL).
  $rtLinks = [regex]::Matches($html, '<a href="draglint://open\?file=([^"&]+)&amp;line=(\d+)">@([^<:]+):(\d+)</a>')
  $rtAnch  = [regex]::Matches((Get-Content (Join-Path $art.Bundle 'trace.dlgraph') -Raw), ' @([A-Za-z0-9_$.\-]+\.(?:pas|dfm|dpr|inc|sql)):[1-9]\d*', 'IgnoreCase').Count
  Chk 'A-RT-ART-LINKS' "$($rtLinks.Count)/$rtAnch" '126/126'
  $rtBadLink = @($rtLinks | Where-Object { $lp = [uri]::UnescapeDataString($_.Groups[1].Value); -not (Test-Path -LiteralPath $lp) -or [IO.Path]::GetFileName($lp) -ne $_.Groups[3].Value -or $_.Groups[2].Value -ne $_.Groups[4].Value })
  if ($rtBadLink.Count) { Fail 'A-RT-ART-LINKS' "$($rtBadLink.Count) link(s) point at a missing file or a different leaf/line than their text, first: $($rtBadLink[0].Value)" }
  if ($html -cnotmatch '<span><b>126</b> of <b>126</b> @file:line anchors link to the IDE</span>') { Fail 'A-RT-ART-LINKS' 'the header does not say "126 of 126 @file:line anchors link to the IDE"' }
  # fix round 1 (M-6): an unlinked anchor is a leaf the indexes hold at ZERO or several paths, not only several
  if ($html -cnotmatch 'holds? at zero or several paths') { Fail 'A-RT-ART-NOTE' 'the page does not say an unlinked anchor names a file held at zero or several paths' }
  # DOC-R1: the page's click handler never cancels navigation (the same script as a chart page)
  if ($html -cmatch 'preventDefault' -or $html -cnotmatch "toast\('opening ' \+ what") { Fail 'A-DOC-R1-NAV' 'the text bundle page cancels draglint:// navigation, or lost its opening toast' }
  if ((Get-Content (Join-Path $art.Bundle 'trace.dlgraph') -Raw) -cne $rt0.RtText) { Fail 'A-RT-ART' 'trace.dlgraph in the bundle differs from the emitter output' }
}
# AC-16, the holdout: a SECOND edited field, pinned only after the owner read its trace. frmBlueprint4.dxDBGrid1FtrsVNum
# -> MSCLIST.NUM, a different dataset (FMTFtrs) and sender (SendDeltaFtrs) than OPERAT.NAME; its datasource re-point at
# Blueprint4.pas:2283 is the P29 case (control recovered from source). The brief's default FtrName was NOT used: it is
# one of the 12 calculated fields added to FMTFtrs after BuildMemTable (Blueprint4.ViewModel.pas:748-761), no DB column.
# OWNER-ACCEPTED 2026-09-28: the owner compared the Num trace with the OPERAT.NAME trace and the golden and checked the
# path's shape, not every line. Measured 2026-09-28 on the 1.19 / 1.9 clones; a drift is a FINDING, not a number to edit.
Note 'round-trip: the holdout ...'
Step 'RT-HOLD' {
  Chk 'A-RT9-ANCHOR'  $rt0.HoldAnchor 'MSCLIST.NUM:FMTFtrs'
  # the sender call from DoAfterPostFtrs, the rspOK guard whose else arm reverts FMTFtrs, the datasource re-point: each exactly once
  Chk 'A-RT9-SENDER'  "$($rt0.HoldSender)/$($rt0.HoldCancel)/$($rt0.HoldRePoint)" '1/1/1'
  Chk 'A-RT9-FORMA'   $rt0.HoldFormA 0
  # fix wave (FW-R1): the per-statement load lines are DERIVED, not OPERAT-specific -- proven here on a
  # different anchor table (MSCLIST) and receiver: FDef.InsertSQL/UpdateSQL/DeleteSQL each name their OWN
  # uDatasetsDef.pas line (:148/:149/:150), the same routine LoadFromInternal used for OPERAT.NAME
  Chk 'A-RTF-R1-HOLDSTOPS' $rt0.HoldStops ('the statement for the posted MSCLIST row is FDef.InsertSQL (loaded at uDatasetsDef.pas:148), ' +
                                           'FDef.UpdateSQL (loaded at uDatasetsDef.pas:149) or FDef.DeleteSQL (loaded at uDatasetsDef.pas:150), ' +
                                           'picked by the case over ARequest at :188, from FIB$DATASETS_INFO rows the index does not hold (fb_datasets has 0 rows in MicroniteMW1Service)')
  # steps/conditions/crossings/unresolved -- the two unresolved are the statement for the posted row and the
  # SELECT STOPS (both E4), as for OPERAT.NAME
  Chk 'A-RT9-COUNTS'  $rt0.HoldCounts '103/35/4/2'
  # final-review I6: [27] CoerceMSCLISTPlanIds -- the caller's branch condition first, then the callee's own guards
  # (was UNLESS FieldCnt = 0, UNLESS Wanted.Count = 0, then WHEN TableName = 'MSCLIST')
  # RE-PINNED 2026-10-06 (R5 Part 0): conditions are written unquoted -- the same conditions, the quotes gone; no count moved
  Chk 'A-RT9-CONDORDER' $rt0.HoldCoerceConds "WHEN TableName = 'MSCLIST' @uGenericTableRoute.pas:468 | UNLESS FieldCnt = 0 @uGenericTableRoute.pas:310 | UNLESS Wanted.Count = 0 @uGenericTableRoute.pas:336"
}
# calc-field brief (owner, 2026-09-28, URGENT): a CALCULATED anchor says so and offers its source fields. The owner's
# pick FtrName stopped at [09] "MSCLIST.FTRNAME: not extracted as a column ..." (9/0/0/1) -- true, not WHY. Now: the
# STOPS names the calc field, where it is created (C(FMTFtrs, 'FtrName', ...) :756, whose C sets fkCalculated :735)
# and computed (FtrsOnCalcFields :961-1119, wired :790), the handler's guards VERBATIM, the call that computes it
# (FtrNameString, its body not walked), and DERIVED lists the 17 TField variables on :986-993 plus the local FtrType
# (:978, one hop to FfFtrs_FtrType) = 18 rows, each with a REGENERATE command. Rule: Trace.Walk Part 6 (generic).
# Measured 2026-09-28 on the 1.19 / 1.9 clones with the 1.20.0-alpha exe; red on HEAD f1cd1eb8 first (old stop, 9/0/0/1,
# no DERIVED; the synthetic ones threw: no Resolve-CalcField). Pins move at the re-clone only with a named mechanism.
# FIX ROUND 1 (calcfield-fix1-findings.md, red on HEAD 99c540c8 first; measured on the v=1.20 / r=1.11 clones). Moved,
# each by its mechanism: -STOP (M1 `created (FieldKind <k>) at`; I1 the cases that pick the formula in the note),
# -NOTE / -CHECK (M4 the shared binding reason stated once), -TOL-GUARDS (I1c the Assigned if encloses EVERY write, so no
# `around` note), -TOL-OFFER / -TOL-COUNTS 13 -> 15 (I1b the two case selectors are rows), the synthetic strings (M3 a
# constant-shaped name is no value, FfZ is a field; M4 row notes; the stop note is now in the string). New: -ROWNOTE,
# -CMD (M5), -SYN-FBNREAD (I2), -SYN-CASE (I1), -SYN-LOOP (I1a), -SYN-CREATING (M1).
# FIX ROUND 2 (calcfield-fix2-findings.md, red on HEAD 83ce59ae first). Moved: -CMD (R2-6 the -Target value single-quoted),
# -TOL-OFFER / -SYN-CASE (R2-3 one wording for every chooser: `the value is chosen by`, `chooses the value (case at :N)`),
# -SYN-OFFER (R2-2 ffFixed is no longer a constant by shape: a named row, 3 other values). New: -INSP-OFFER, -USL-OFFER,
# -SYN-IFCHOOSER (R2-3), -SYN-CASEBEGIN (R2-1), -SYN-INHERITED (R2-2). A-RTC-E2E runs the row + `-OutRoot <scratch>` (R2-5).
Note 'round-trip: calculated fields ...'
Step 'RT-CALC' {
  $bindWhy = "the TField variable via FF(dataset, literal), assumed to return the dataset's field named by the literal, and FMTFtrs matched by name among the class's dataset fields"
  Chk 'A-RTC-FTR-TITLE'  $rt0.CalcFtrTitle 'Why frmBlueprint4.dxDBGrid1FtrsVFtrName cannot be traced -- it is calculated'
  Chk 'A-RTC-FTR-STOP'   $rt0.CalcFtrStop ('STOPS FtrName is a calculated field of FMTFtrs (created (FieldKind fkCalculated) at :756, computed in FtrsOnCalcFields at :961-1119), not a column of MSCLIST in the SQL index ' +
                                           '@Blueprint4.ViewModel.pas:986 -- in FtrsOnCalcFields; wired as FMTFtrs.OnCalcFields at :790, the handler matched by name, C sets FieldKind fkCalculated at :735; ask E3')
  # RE-PINNED 2026-10-06 (R5 Part 0): conditions are written unquoted -- the same conditions, the quotes gone; no count moved
  Chk 'A-RTC-FTR-GUARDS' $rt0.CalcFtrChildren ('UNLESS DataSet.State = dsInsert @Blueprint4.ViewModel.pas:973 -- else Exit at :973 | WHEN Assigned(FfFtrs_FtrName) @Blueprint4.ViewModel.pas:985 | ' +
                                               'VIA FtrNameString @MSCTYPES.PAS:840 -- computed by this call at :986, its body is not walked, nor are those of TagOf')
  Chk 'A-RTC-FTR-NOTE'   $rt0.CalcFtrNote "FtrName is calculated from 18 fields -- trace one of them instead (every binding below: $bindWhy):"
  # every candidate and its column, in source order (:987-993, FtrType's row at its read :990); each target is the TField variable
  $vm = 'Blueprint4.ViewModel.TBlueprint_ViewModel'
  $ftrRows = @('NOTATION:Notation', 'SPECTYPE:SpecType', 'USL:USL', 'LSL:LSL', 'DECIMALS:Decimals', 'NOMINAL:Nominal', 'UPPERTOL:UpperTol', 'LOWERTOL:LowerTol', 'FTRTYPE:*FtrType',
               'MATHLINE:MathLine', 'DIMABBR:DimAbbr', 'DIMNAME:DimName', 'FTRSUFFIX:FtrSuffix', 'ATTRNAME:AttrName', 'ATTRTYPE:AttrType', 'ATTRCODE:AttrCode', 'ID:ID', 'MASTERID:MasterID') |
             ForEach-Object { $c, $v = $_ -split ':'; if ($v -like '*FtrType') { "FROM MSCLIST.$c VIA FtrType, set from FfFtrs_FtrType => $vm.FfFtrs_FtrType" } else { "FROM MSCLIST.$c VIA FfFtrs_$v => $vm.FfFtrs_$v" } }
  Chk 'A-RTC-FTR-ROWS'   $rt0.CalcFtrRows ($ftrRows -join ' ## ')
  # M4: the row keeps `bound at :N via FF`; the ~150-char reason is the note's, once
  Chk 'A-RTC-FTR-ROWNOTE' $rt0.CalcFtrRowLine 'FROM MSCLIST.FTRTYPE VIA FtrType, set from FfFtrs_FtrType [inferred] @Blueprint4.ViewModel.pas:990 -- in FtrsOnCalcFields; FtrType set at :978, FfFtrs_FtrType bound at :858 via FF; ask in-class-field-reads'
  # M5: the header and all 18 row commands are runnable as written -- the call operator and the bundler's absolute path
  $bundler = [IO.Path]::GetFullPath((Join-Path $SRC 'New-DiagramArtifact.ps1'))
  Chk 'A-RTC-CMD'        $rt0.CalcCmdHeads "19x & '$bundler' -Question round-trip -Target '"
  # the rows are anchored facts: counted in steps (9 + 18), never unresolved; the ONE unresolved is the STOPS
  Chk 'A-RTC-FTR-COUNTS' $rt0.CalcFtrCounts '27/2/0/1'
  Chk 'A-RTC-FTR-CHECK'  $rt0.CalcFtrCheck ("0|identical|True|ANCHOR,DERIVED,WRITE,SERVER,DATABASE,RESPONSE,READ,ALSO|DERIVED=FtrName is calculated from 18 fields -- trace one of them instead (every binding below: $bindWhy): | " +
                                            ((@('WRITE', 'SERVER', 'DATABASE', 'RESPONSE', 'READ', 'ALSO') | ForEach-Object { "$_=not walked: the trace stopped at [09]" }) -join ' | '))
  # the second case: Tolerance (:760), five writes in a nested case (:1043 on SpecType, :1044 on Notation). I1: the cases
  # are not guards -- the STOPS note names each case and the writes it picks among, their selectors are rows; the
  # Assigned if encloses every write, so it carries no `around` note (it read as guarding :1050 only)
  Chk 'A-RTC-TOL-TITLE'  $rt0.CalcTolTitle 'Why frmBlueprint4.dxDBGrid1FtrsVTolerance cannot be traced -- it is calculated'
  Chk 'A-RTC-TOL-STOP'   $rt0.CalcTolStop ('STOPS Tolerance is a calculated field of FMTFtrs (created (FieldKind fkCalculated) at :760, computed in FtrsOnCalcFields at :961-1119), not a column of MSCLIST in the SQL index ' +
                                           '@Blueprint4.ViewModel.pas:1045 -- in FtrsOnCalcFields; wired as FMTFtrs.OnCalcFields at :790, the handler matched by name, C sets FieldKind fkCalculated at :735, ' +
                                           'the formula is chosen by the case at :1043 (writes at :1045, :1046, :1047, :1049, :1050) and the case at :1044 (writes at :1045, :1046, :1047), their selectors are offered below; ask E3')
  # RE-PINNED 2026-10-06 (R5 Part 0): conditions are written unquoted -- the same conditions, the quotes gone; no count moved
  Chk 'A-RTC-TOL-GUARDS' $rt0.CalcTolChildren 'UNLESS DataSet.State = dsInsert @Blueprint4.ViewModel.pas:973 -- else Exit at :973 | WHEN Assigned(FfFtrs_Tolerance) @Blueprint4.ViewModel.pas:1041'
  Chk 'A-RTC-TOL-OFFER'  "$($rt0.CalcTolNote)|$($rt0.CalcTolRows)" ("Tolerance is calculated from 4 fields, and the value is chosen by 2 more (case at :1043, :1044) -- trace one of them instead (every binding below: $bindWhy):|" +
                                                                    ((@(@('USL', 'LSL', 'UpperTol', 'LowerTol') | ForEach-Object { "FROM MSCLIST.$($_.ToUpperInvariant()) VIA FfFtrs_$_ => $vm.FfFtrs_$_" }) +
                                                                      "FROM MSCLIST.SPECTYPE VIA FfFtrs_SpecType, chooses the value (case at :1043) => $vm.FfFtrs_SpecType" +
                                                                      "FROM MSCLIST.NOTATION VIA FfFtrs_Notation, chooses the value (case at :1044) => $vm.FfFtrs_Notation") -join ' ## '))
  Chk 'A-RTC-TOL-COUNTS' "$($rt0.CalcTolCounts)|$(($rt0.CalcTolCheck -split '\|')[0..2] -join '|')" '15/2/0/1|0|identical|True'
  # ONE candidate's REGENERATE command run end to end, AS WRITTEN (M5: the string itself, head and all): DimAbbr ->
  # MSCLIST.DIMABBR through FMTFtrs and SendDeltaFtrs. 98 = the owner-accepted Num holdout's 103 minus the 5
  # control-side anchor hops (DFM binding, re-point, accessor, datasource) a TField-variable target does not walk
  Chk 'A-RTC-E2E'        $rt0.CalcE2E "How MSCLIST.DIMABBR reaches $vm.FfFtrs_DimAbbr and goes back|END TRACE  98 steps, 35 conditions, 4 crossings, 2 unresolved."
  # synthetic facts, NO index (Resolve-CalcField is pure): the positive names every value it cannot map and marks a
  # calculated source without expanding it; the negatives keep today's stop or name the kind, never an offer
  $wired = 'wired as FMT.OnCalcFields at :20, the handler matched by name'
  $ffWhy = 'FF assumed to return the named field'
  Chk 'A-RTC-SYN-OFFER'  $rt0.CalcSynOffer ("calculated | A is a calculated field of FMT (computed in CalcH at :1-10), not a column of T in the SQL index @calc-syn.pas:8 -- $wired | " +
                                           'UNLESS DataSet.State = dsInsert -- else Exit at :5 / WHEN Assigned(FfA) / VIA Fmt -- computed by this call at :8, its body is not walked | ' +
                                           "A is calculated from 4 fields, and 3 other values the walk cannot map -- trace one of them instead (every binding below: $ffWhy): | " +
                                           'FROM T.B VIA FfB [inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB ## FROM T.K VIA L, set from FfK [inferred] -- L set at :6, FfK bound at :30 via FF => CMD uSynth.TSynth.FfK ## ' +
                                           'FROM C (calculated) VIA FfC [inferred] -- itself calculated in CalcH, not expanded, FfC bound at :30 via FF => CMD uSynth.TSynth.FfC ## ' +
                                           'FROM Zz, not mapped: not a field, local or parameter the walk can place =>  ## ' +
                                           'FROM FNum, not mapped: a field of TSynth of type Integer, not a TField variable =>  ## ' +
                                           'FROM FfZ, not mapped: FfZ is written on 2 line(s) naming 2 (dataset field, column literal) pairs =>  ## ' +
                                           'FROM ffFixed, not mapped: not a field, local or parameter the walk can place => ')
  Chk 'A-RTC-SYN-NOWIRE' "$($rt0.CalcSynNoWire)|$($rt0.CalcSynNoWrite)" 'not calculated|not calculated'
  Chk 'A-RTC-SYN-FBN'    $rt0.CalcSynFieldByName ("calculated | A is a calculated field of FMT (computed in CalcH at :1-4), not a column of T in the SQL index @calc-fbn.pas:3 -- $wired |  | " +
                                                  "A is calculated from 1 field -- trace it instead (the binding below: $ffWhy): | FROM T.B VIA FfB [inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB")
  Chk 'A-RTC-SYN-EVENT'  $rt0.CalcSynEvent 'event | A is not a column of T in the SQL index: it is set in CalcH, wired as FMT.AfterScroll at :20, not in an OnCalcFields handler, so no source fields are offered @calc-event.pas:8'
  Chk 'A-RTC-SYN-LOOKUP' $rt0.CalcSynLookup 'lookup | A is a lookup field of FMT: MakeLookup sets FieldKind fkLookup at :40, not a column of T in the SQL index, so no source fields are offered @calc-lookup.pas:12'
  # I2: DataSet.FieldByName('B') / ('W') / ('B') READ -> 2 rows, not one "DataSet, a parameter"; B through its bound
  # variable, W named with why no -Target resolves (2 datasets load T) -- and T.W when exactly one does
  $fbrHead = "calculated | A is a calculated field of FMT (computed in CalcH at :1-4), not a column of T in the SQL index @calc-fbr{0}.pas:3 -- $wired |  | "
  $fbrB = 'FROM T.B VIA DataSet.FieldByName [inferred] -- DataSet is a parameter of CalcH, taken as FMT, traced through FfB, bound at :30 via FF => CMD uSynth.TSynth.FfB'
  Chk 'A-RTC-SYN-FBNREAD' "$($rt0.CalcSynFbnRead) || $($rt0.CalcSynFbnReadOne)" (($fbrHead -f '') + "A is calculated from 2 fields -- trace it instead: | $fbrB ## " +
                                                                               "FROM T.W VIA DataSet.FieldByName [inferred] -- DataSet is a parameter of CalcH, taken as FMT, no -Target resolves to FMT: 2 datasets load T and no TField variable is bound to 'W' =>  || " +
                                                                               ($fbrHead -f '1') + "A is calculated from 2 fields -- trace one of them instead: | $fbrB ## " +
                                                                               'FROM T.W VIA DataSet.FieldByName [inferred] -- DataSet is a parameter of CalcH, taken as FMT, traced as T.W, the one dataset that loads T => CMD T.W')
  # I1: writes in the arms of `case TagOf(FfK) of` inside `if Assigned(FfA)` -- the if is written for both writes (no
  # `around`), the case is no guard: named in the stop note, its selector FfK a row that chooses the value
  Chk 'A-RTC-SYN-CASE'   $rt0.CalcSynCase ("calculated | A is a calculated field of FMT (computed in CalcH at :1-10), not a column of T in the SQL index @calc-case.pas:6 -- $wired, " +
                                           'the formula is chosen by the case at :5 (writes at :6, :7), its selector is offered below | WHEN Assigned(FfA) | ' +
                                           "A is calculated from 1 field, and the value is chosen by 1 more (case at :5) -- trace one of them instead (every binding below: $ffWhy): | " +
                                           'FROM T.B VIA FfB [inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB ## FROM T.K VIA FfK, chooses the value (case at :5) [inferred] -- FfK bound at :30 via FF => CMD uSynth.TSynth.FfK')
  # I1a: a shape the shim cannot place (a while loop) reaches the stop note with the shim's reason -- never silently dropped
  Chk 'A-RTC-SYN-LOOP'   $rt0.CalcSynLoop ("calculated | A is a calculated field of FMT (computed in CalcH at :1-5), not a column of T in the SQL index @calc-loop.pas:4 -- $wired, " +
                                           'not read as a guard: the statement at :4 sits under a while statement, a shape the source shim does not read |  | ' +
                                           "A is calculated from 1 field -- trace it instead (the binding below: $ffWhy): | FROM T.B VIA FfB [inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB")
  # FIX ROUND 2 (calcfield-fix2-findings.md, red on HEAD 83ce59ae first)
  # R2-3: the fields read in the if CONDITIONS that choose the value are rows, counted in the lead-in. InspAsVarStr
  # (:1104-1114, every write a constant) said "calculated from no field -- nothing to trace instead"; USLLSLName left out
  # FtrType (:1003) and FfFtrs_ID / FfFtrs_MasterID (:1023)
  $vmT = { param($v) "$vm.FfFtrs_$v" }
  Chk 'A-RTC-INSP-OFFER' $rt0.CalcInspOffer ("InspAsVarStr is calculated from no field, but its value is chosen by 2 (if at :1106, :1110) -- trace one of them instead (every binding below: $bindWhy): | " +
                                             "FROM MSCLIST.FTRTYPE VIA FtrType, set from FfFtrs_FtrType, chooses the value (if at :1106) => $(& $vmT 'FtrType') ## " +
                                             "FROM MSCLIST.INSPASVAR VIA FfFtrs_InspAsVar, chooses the value (if at :1110) => $(& $vmT 'InspAsVar') | 6/8/0/1 | 0/identical/True")
  Chk 'A-RTC-USL-OFFER'  $rt0.CalcUslOffer ("USLLSLName is calculated from 2 fields, and the value is chosen by 3 more (if at :1003, :1023), and 1 other value the walk cannot map -- trace one of them instead (every binding below: $bindWhy): | " +
                                            'FROM Spec, not mapped: a local of FtrsOnCalcFields set at 5 places before this read =>  ## ' +
                                            "FROM MSCLIST.ATTRNAME VIA FfFtrs_AttrName => $(& $vmT 'AttrName') ## FROM MSCLIST.DIMNAME VIA FfFtrs_DimName => $(& $vmT 'DimName') ## " +
                                            "FROM MSCLIST.FTRTYPE VIA FtrType, set from FfFtrs_FtrType, chooses the value (if at :1003) => $(& $vmT 'FtrType') ## " +
                                            "FROM MSCLIST.ID VIA FfFtrs_ID, chooses the value (if at :1023) => $(& $vmT 'ID') ## FROM MSCLIST.MASTERID VIA FfFtrs_MasterID, chooses the value (if at :1023) => $(& $vmT 'MasterID') | 10/8/0/1 | 0/identical/True")
  Chk 'A-RTC-SYN-IFCHOOSER' $rt0.CalcSynIfChooser ("calculated | A is a calculated field of FMT (computed in CalcH at :1-5), not a column of T in the SQL index @calc-if.pas:3 -- $wired | " +
                                                   'WHEN FfB.AsInteger > 0 -- around the write at :3 / UNLESS FfB.AsInteger > 0 -- around the write at :4 | ' +
                                                   "A is calculated from no field, but its value is chosen by 1 (if at :3) -- trace it instead (the binding below: $ffWhy): | " +
                                                   'FROM T.B VIA FfB, chooses the value (if at :3) [inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB')
  # R2-1: a begin-wrapped case arm (`1: begin .. end;`) is under the case like a bare arm -- selector offered, case named, no `around`
  Chk 'A-RTC-SYN-CASEBEGIN' $rt0.CalcSynCaseBegin ("calculated | A is a calculated field of FMT (computed in CalcH at :1-10), not a column of T in the SQL index @calc-caseb.pas:6 -- $wired, " +
                                                   'the formula is chosen by the case at :5 (writes at :6, :7), its selector is offered below | WHEN Assigned(FfA) | ' +
                                                   "A is calculated from 1 field, and the value is chosen by 1 more (case at :5) -- trace one of them instead (every binding below: $ffWhy): | " +
                                                   'FROM T.B VIA FfB [inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB ## FROM T.K VIA FfK, chooses the value (case at :5) [inferred] -- FfK bound at :30 via FF => CMD uSynth.TSynth.FfK')
  # R2-2: an unbound receiver (an inherited TField variable) is a named row, counted; TKind (type shape) and Integer(...) are constants
  Chk 'A-RTC-SYN-INHERITED' $rt0.CalcSynInherited ("calculated | A is a calculated field of FMT (computed in CalcH at :1-4), not a column of T in the SQL index @calc-inh.pas:3 -- $wired |  | " +
                                                   "A is calculated from 1 field, and 1 other value the walk cannot map -- trace it instead (the binding below: $ffWhy): | " +
                                                   'FROM FfInherited, not mapped: not a field, local or parameter the walk can place =>  ## FROM T.B VIA FfB [inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB')
  # M1: `created (FieldKind <k>)` only with the kind proven; otherwise the line only `named` the field
  $loopWhy = 'not read as a guard: the statement at :4 sits under a while statement, a shape the source shim does not read'
  Chk 'A-RTC-SYN-CREATING' $rt0.CalcSynCreating ("A is a calculated field of FMT (created (FieldKind fkCalculated) at :12, computed in CalcH at :1-5), not a column of T in the SQL index -- $wired, C sets FieldKind fkCalculated at :40, $loopWhy ## " +
                                                 "A is a calculated field of FMT (named at :12, computed in CalcH at :1-5), not a column of T in the SQL index -- $wired, $loopWhy")
}
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
  Write-Host ("  butterfly D6   : {0} callees from 19 tree nodes, {1} arrows, {2} leave the focus; D12 {3} (synthetic {4}); FConnected writes {5} (D31), fLOTSIZE D13 {6}" -f (V $b6 'Callees'), (V $b6 'Edges'), (V $b6 'FocusOut'), (V $fx7 'D12Suspect'), $fx12, (V $m14 'Writes'), (V $m15 'D13SameFile'))
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
  Write-Host ("  path           : {0} shortest paths of {1} calls ({2} routines, {3} sites); cap 1 draws {4} + discloses 1; ambiguous pair {5} sites" -f (V $pa1 'Paths'), (V $pa1 'Hops'), (V $pa1 'Routines'), (V $pa1 'Sites'), (V $pa2 'PathsShown'), (V $pa3 'Ambiguous'))
  Write-Host ("  task-0 helpers : SQL {0}/{1} tables, {2}/{3} trigger bodies; raise/handle {4}/{5}; datasources {6}/{7}/{8} resolve {9}/{10}/{11}; dangling {12}/{13}" -f (V $t0 'SqlTables'), (V $t0 'SqlDeclarations'), (V $t0 'TriggerBodies'), (V $t0 'Triggers'), (V $t0 'ExcRaise'), (V $t0 'ExcHandle'), (V $t0 'DsTotal'), (V $t0 'DsDfmWired'), (V $t0 'DsCodeSite'), (V $t0 'DsOne'), (V $t0 'DsMany'), (V $t0 'DsNone'), (V $t0 'DanglingRows'), (V $t0 'RePointedAny'))
  Write-Host ("  disk vs index  : CLIENT files differing today (informational, not pinned): {0}" -f (V $t0 'DiskStaleCli'))
  Write-Host ("  exception-paths: {0} raises / {1} callers / {2} caught; index {3}/{4}; source bare/on/reraise/var {5}/{6}/{7}/{8}" -f (V $ep1 'Raises'), (V $ep1 'Callers'), (V $ep1 'Caught'), (V $ep1 'IndexRaise'), (V $ep1 'IndexHandle'), (V $ex0 'BareExcept'), (V $ex0 'OnExcept'), (V $ex0 'Reraise'), (V $ex0 'RaiseVar'))
  Write-Host ("  consumers      : CAUSFAIL cert/inf readers {0}/{1}, writers {2}/{3}, {4} triggers; REASON bindings {5}/{6}; facts {7}/{8}/{9}; literals {10}/{11}/{12}; proc bodies {13}" -f (V $co1 'CertainReaders'), (V $co1 'InferredReaders'), (V $co1 'CertainWriters'), (V $co1 'InferredWriters'), (V $co1 'Triggers'), (V $co2c 'IndexBindings'), (V $co2c 'DrawnBindings'), (V $co1 'IndexReadFacts'), (V $co1 'IndexWriteFacts'), (V $co1 'IndexFactSymbols'), (V $co1 'IndexVerbLiterals'), (V $co1 'IndexFromJoinTables'), (V $co1 'IndexFactReadTables'), (V $co1 'ProcBodies'))
  Write-Host ("  feeds-from     : colREASON {0} ({1} rows, {2}); datasources {3}/{4}/{5}; per control {6} of {7} resolve to one table ({8}%), {9} to a column" -f (V $ff1 'TableColumn'), (V $ff1 'ChainRows'), (V $ff1 'HopGrades'), (V $ff1 'IndexDs'), (V $ff1 'IndexDsDfm'), (V $ff1 'IndexDsCode'), (V $ff1 'CtlTable'), (V $ff1 'Controls'), (V $ff1 'CoveragePct'), (V $ff1 'CtlColumn'))
  Write-Host ("  lands-where    : REASON {0} ({1} server rows, {2} trigger, {3} client); convention {4}/{5}/{6}; DataService {7}; ParamByName {8}/{9}; orm_links {10}" -f (V $lw1 'TableColumn'), (V $lw1 'ServerRows'), (V $lw1 'Triggers'), (V $lw1 'ClientBindings'), (V $lw1 'ConvProps'), (V $lw1 'ConvOnTable'), (V $lw1 'ConvColumn'), (V $lw1 'DsClasses'), (V $lw1 'ParamByNameDs'), (V $lw1 'ParamByNameCol'), $ol)
  Write-Host ("  round-trip     : golden nodes {0}/17 matched (disclosed: {1}); {9} golden facts disclosed ({10}): {11}; guards {2}/12 (disclosed: {3}); steps/conditions/crossings/unresolved {4}; ALSO {5}; N1 {6} step(s); stale {7}; holdout candidates {8}" -f (V $rt0 'GoldenMatched'), (V $rt0 'GoldenDisclosed'), (V $rt0 'GuardsMatched'), (V $rt0 'GuardsDisclosed'), (V $rt0 'RtCounts'), (V $rt0 'RtAlso'), (V $rtn1 'Steps'), $(if ($rtStale) { $rtStale } else { '?' }), (V $rt0 'HoldoutCandidates'), (V $rt0 'GoldenFactsDisclosedN'), (V $rt0 'GoldenFactsReason'), (V $rt0 'GoldenFactsDisclosed'))
  Write-Host ("  negatives      : N1-N12b, N14, N15, N18b, N19, N20-N24, PA-N1..N4, N33, N35, EP-N20, CO-N25, CO-N26, CO-N26b, CO-N34, CO-STALE-REFUSE, FF-N28, FF-N28b, FF-N34, LW-N31-BRIEF, LW-N32, LW-FIB, LW-MEMCTL, LW-PERSIST, LW-ROLES/2, LW-N34, LW-ART-N, N-MAXPATH, W-* (R19 wrappers), each asserting message AND absent .svg; RT-STALE (message AND absent .dlgraph); RT-N1, RT-N2 one-STOPS traces; N13/N16/N17, EP-N21..N23, CO-N24/N27/STALE/STALE-COL, FF-N29/N30/STALE, LW-N31/SRVSQL/QUOTED/R17/STALE/STALE-Q draw")
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
