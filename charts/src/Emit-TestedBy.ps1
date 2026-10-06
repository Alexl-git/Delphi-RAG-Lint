<#
  Emit-TestedBy.ps1 -- the `tested-by` question: which tests reach this code?

  >>> `covered_by` IS 0/0 BY DESIGN. DO NOT WAIT FOR IT. <<<
  ------------------------------------------------------------
  `symbol_facts.covered_by` is empty in every index and always will be in a pure
  static index -- it was filed and answered. Coverage here is COMPUTED, by
  walking call edges from the code under test up to the routines carrying a
  DUnitX `[Test]` attribute.

  IT IS A SINGLE-DB PASS, NOT A CROSS-DB JOIN
  --------------------------------------------
  The earlier estimate assumed this needed the product index and the test index
  opened together. It does not: a test project's compile closure ALREADY
  CONTAINS the code under test. Measured on the MicroniteTests clone -- 5,152
  symbols, 66 files, 1,448 call edges, and 724 symbols from `MSCTYPES.PAS`
  sitting alongside the DUnitX fixtures. So the walk runs inside one database,
  once per test project. That is why this shipped at M rather than L.

  WHY IT IS SAFE WHILE THE CALLEE DIRECTION IS NOT
  --------------------------------------------------
  The walk goes from the code under test UP THROUGH ITS CALLERS until it reaches
  a test method -- the caller direction, which measured intact on 2026-09-23
  while the callee direction lost interface-dispatch edges. Walking DOWN from
  each test instead would have used exactly the broken direction.

  FINDING A TEST METHOD: NEAREST FOLLOWING DECLARATION
  ------------------------------------------------------
  `[Test]` is an attribute ref (71 of them in MicroniteTests, plus 11
  `[TestFixture]`) and it has **no `enclosing_symbol_id`** -- attributes are not
  inside the thing they decorate. The method it marks is the FIRST declaration at
  or after the attribute's line in the same file.

  A window instead of a nearest-match is wrong and it is not theoretical: these
  fixtures declare tests on consecutive lines, so a "+/- 2 lines" rule matched
  `[Test]` at line 15 to three different methods at 15, 16 and 17. One attribute
  marks one method: the nearest following one.

  AN EMPTY ANSWER IS NOT "UNTESTED"
  ----------------------------------
  Zero covering tests means no test in THIS index reaches it through a resolved
  call edge. Interface-dispatch edges are incomplete on this build, and a test
  that exercises the code through an interface is exactly the shape that goes
  missing. The chart says "no test reaches it here", never "untested".
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][Alias('Qname','Type')][string] $Target,
  [Parameter(Mandatory)][string] $DbPath,           # a TEST project index
  [string] $OutDir,
  [int]    $Depth = 6,                              # tests sit several hops up
  [int]    $Cap   = 10,
  [string] $Engine     = '',
  [string] $Dot        = '',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')
$Engine = Resolve-DragLintEngine $Engine   # R2: '' = DRAGLINT_ENGINE, settings.json, installed, shared (Emit-Common)
$DbPath = Get-CloneDb $DbPath

$PAL = @{
  testBorder  = '#0F766E'; testFill  = '#E2F1EF'; testHdr  = '#0F766E'
  pathBorder  = '#3B5BDB'; pathFill  = '#EDF2FF'; pathHdr  = '#3B5BDB'
  noneBorder  = '#9AA3AF'; noneFill  = '#F3F4F6'; noneHdr  = '#6B7280'
  focusBorder = '#B45309'; focusFill = '#FEF6EC'; focusHdr = '#B45309'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}

Write-Host "tested-by: $Target"

# ---- 1. is this a TEST index at all? (pre-check, before the symbol) --------------
$attr = Invoke-IndexQuery "SELECT COUNT(*) AS n FROM refs WHERE kind='attribute' AND name_text IN ('Test','TestCase')"
$nAttr = $(if ($attr.Count) { [int]$attr[0].n } else { 0 })
if ($nAttr -eq 0) {
  throw ('tested-by: this index carries no DUnitX [Test] attributes, so it is not a test project ' +
         'index. Point it at a test project DB -- the test closure already contains the code ' +
         'under test, so this is a single-DB question.')
}
Write-Host "  index has $nAttr [Test] attribute(s)"

# ---- 2. the test methods: nearest following declaration --------------------------
$testRows = Invoke-IndexQuery @"
SELECT DISTINCT
       (SELECT m.id FROM symbols m
         WHERE m.file_id = r.file_id AND m.kind IN ('method','procedure','function')
           AND m.start_line >= r.start_line
         ORDER BY m.start_line LIMIT 1) AS mid
  FROM refs r
 WHERE r.kind = 'attribute' AND r.name_text IN ('Test','TestCase')
"@ 'tested-by (test methods)'
$testIds = @{}
foreach ($t in $testRows) { if ($t.mid) { $testIds[[int]$t.mid] = $true } }
Write-Host "  resolved to $($testIds.Count) distinct test method(s)"

# ---- 3. the selection ---------------------------------------------------------------
$sel = Resolve-MemberSelection $Target `
         @('method', 'function', 'procedure', 'constructor', 'destructor', 'class', 'interface', 'record', 'type') `
         -Hint 'tested-by selects a METHOD or a TYPE'
$isType = $sel.Kind -in @('class', 'interface', 'record', 'type')

$seeds = @([int]$sel.Id)
if ($isType) {
  # PAGED (R24): a type with more than 200 members was seeded with the first 200
  $mem = Get-AllIndexRows "SELECT id FROM symbols WHERE parent_id = $($sel.Id)" 'id'
  foreach ($m in $mem) { $seeds += [int]$m.id }
  Write-Host "  type selection: seeded with $($mem.Count) member(s)"
}

# ---- 4. BFS over CALLERS, stopping at tests -------------------------------------------
$dist = @{}
foreach ($s in $seeds) { $dist[$s] = 0 }
$frontier = @($seeds)
$hits = @{}    # test method id -> hop
for ($d = 1; $d -le $Depth -and $frontier.Count -gt 0; $d++) {
  $next = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $frontier.Count; $i += 60) {
    $chunk = @($frontier[$i..([Math]::Min($i + 59, $frontier.Count - 1))])
    $off = 0
    while ($true) {
      $page = Invoke-IndexQuery @"
SELECT DISTINCT r.enclosing_symbol_id AS caller
  FROM call_edges ce JOIN refs r ON r.id = ce.ref_id
 WHERE ce.target_symbol_id IN ($($chunk -join ',')) AND r.enclosing_symbol_id IS NOT NULL
 ORDER BY r.enclosing_symbol_id LIMIT 180 OFFSET $off
"@
      if ($page.Count -eq 0) { break }
      foreach ($p in $page) {
        $cid = [int]$p.caller
        if ($dist.ContainsKey($cid)) { continue }
        $dist[$cid] = $d
        if ($testIds.ContainsKey($cid)) { $hits[$cid] = $d }
        # a test method is a leaf of this walk: nothing calls a [Test] routine,
        # and continuing past it would only add the fixture's own plumbing
        else { [void]$next.Add($cid) }
      }
      if ($page.Count -lt 180) { break }
      $off += 180
    }
  }
  $frontier = @($next.ToArray())
}

$reached = @($dist.Keys | Where-Object { $_ -ne 0 -and $dist[$_] -gt 0 }).Count
Write-Host ("  covering tests={0}  routines walked={1}  max depth={2}" -f $hits.Count, $reached, $Depth)

# ---- 5. describe the covering tests ----------------------------------------------------
$tests = @()
if ($hits.Count -gt 0) {
  $ids = @($hits.Keys)
  for ($i = 0; $i -lt $ids.Count; $i += 60) {
    $chunk = @($ids[$i..([Math]::Min($i + 59, $ids.Count - 1))])
    $rows = Invoke-IndexQuery @"
SELECT s.id AS id, s.name AS nm, s.qualified_name AS q,
       s.impl_start_line AS impl, s.start_line AS decl,
       f.path AS path, p.name AS fixture
  FROM symbols s JOIN files f ON f.id = s.file_id
  LEFT JOIN symbols p ON p.id = s.parent_id
 WHERE s.id IN ($($chunk -join ','))
"@
    foreach ($r in $rows) {
      $tests += [pscustomobject]@{
        Name = [string]$r.nm; Q = [string]$r.q
        Line = $(if ($r.impl) { [int]$r.impl } else { [int]$r.decl })
        Path = [string]$r.path
        Fixture = $(if ($r.fixture) { [string]$r.fixture } else { Get-UnitName ([string]$r.path) })
        Hop = $hits[[int]$r.id]
      }
    }
  }
}
$fixtures = @($tests | ForEach-Object { $_.Fixture } | Sort-Object -Unique)

# ---- 6. dot -------------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph testedby {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.5; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')

$nodeId = 0; $clusters = 0; $anchored = 0
$nodeId++; $clusters++
$fnid = "n$nodeId"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $sel.Name) </B></FONT></TD></TR>")
$anchored++
[void]$ftbl.Append("<TR><TD PORT=`"p1`" ALIGN=`"LEFT`" HREF=`"$(New-RowHref $sel.Path $sel.FocusLine)`" TITLE=`"$(ConvertTo-XmlText $sel.Qname)`">")
[void]$ftbl.Append("<FONT COLOR=`"$($PAL.rowInk)`">$(ConvertTo-XmlText (Get-UnitName $sel.Path))</FONT>")
[void]$ftbl.Append("  <FONT COLOR=`"$($PAL.lineInk)`" POINT-SIZE=`"12`">:$($sel.FocusLine)</FONT></TD></TR>")
Add-DisclosureRow $ftbl "$($tests.Count) covering test(s) in $($fixtures.Count) fixture(s)" $PAL.lineInk
Add-DisclosureRow $ftbl "walked callers up to $Depth hop(s); this index has $($testIds.Count) test method(s)" $PAL.lineInk
Add-DisclosureRow $ftbl 'coverage is COMPUTED from call edges -- symbol_facts.covered_by is empty by design' $PAL.lineInk
$edgeless = Get-EdgelessFiles
$edgelessNote = Get-EdgelessDisclosure $edgeless
if ($edgelessNote) { Add-DisclosureRow $ftbl $edgelessNote $PAL.lineInk }
if ($tests.Count -eq 0) {
  Add-DisclosureRow $ftbl 'this is NOT "untested": a test reaching it through an unresolved edge is invisible here' $PAL.lineInk
}
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

if ($tests.Count -eq 0) {
  $nodeId++; $clusters++
  [void](Add-RowCluster -Sb $sb -Cid "cluster_none_$nodeId" -Nid "n$nodeId" `
           -Title 'no covering test' -Subtitle 'in this index' `
           -Rows @((New-NoteRow "none of this index's $($testIds.Count) test methods reaches it"),
                   (New-NoteRow 'absence is not proof: an unresolved or cleared edge looks the same as no call')) `
           -Border $PAL.noneBorder -Fill $PAL.noneFill -Hdr $PAL.noneHdr `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style 'rounded,filled,dashed')
  [void]$sb.AppendLine("  ${fnid}:p1 -> n$nodeId [style=dashed];")
} else {
  foreach ($fx in ($fixtures | Sort-Object { @($tests | Where-Object { $_.Fixture -eq $fx }).Count } -Descending)) {
    $ft = @($tests | Where-Object { $_.Fixture -eq $fx } | Sort-Object Hop, Name)
    $top = Get-TopRanked $ft $Cap 'Hop'
    $cells = New-Object System.Collections.ArrayList
    foreach ($t in $top.Shown) {
      $anchored++
      [void]$cells.Add([pscustomobject]@{
        Label = $t.Name; Line = $t.Line
        Href  = New-RowHref $t.Path $t.Line
        Tip   = "$($t.Q) -- reaches the selection in $($t.Hop) hop(s)"
        Note  = "$($t.Hop) hop$(if ($t.Hop -ne 1) { 's' })"
      })
    }
    $d = Get-DisclosureText $top.HiddenRows 0 'tests'
    if ($d) { [void]$cells.Add((New-NoteRow $d)) }
    $nodeId++; $clusters++
    $nid = "n$nodeId"
    [void](Add-RowCluster -Sb $sb -Cid "cluster_fx_$nodeId" -Nid $nid `
             -Title $fx -Subtitle "$($ft.Count) test$(if ($ft.Count -ne 1) { 's' })" -Rows $cells.ToArray() `
             -Border $PAL.testBorder -Fill $PAL.testFill -Hdr $PAL.testHdr `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans)
    [void]$sb.AppendLine("  $nid -> ${fnid}:p1 [color=`"$($PAL.testBorder)`"];")
  }
}
[void]$sb.AppendLine('}')

if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$lay = Invoke-DotLayout $sb.ToString() $OutDir ('testedby_' + ($sel.Qname -replace '[^A-Za-z0-9]', '_'))

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Qname        = $sel.Qname
  Tests        = $tests.Count
  Fixtures     = $fixtures.Count
  TestMethods  = $testIds.Count
  Walked       = $reached
  MaxHop       = $(if ($tests.Count) { ($tests | Measure-Object -Property Hop -Maximum).Maximum } else { 0 })
  Clusters     = $clusters
  ClickTargets = $lay.Anchors
  Expected     = $anchored
  AllClickable = ($lay.Anchors -ge $anchored)
}
