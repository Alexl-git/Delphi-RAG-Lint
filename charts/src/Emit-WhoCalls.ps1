<#
  Emit-WhoCalls.ps1 -- the `who-calls` question: the N-deep CALLER tree.

  Different in shape from both shipping emitters, and the difference is the
  point:

    butterfly  one hop each way, clusters are units
    deps       one unit, rows are units, clusters are directories
    who-calls  N hops in ONE direction, clusters are (DEPTH, UNIT)

  A ROW IS A CALL SITE, NOT A METHOD. The port map is keyed by ORDINAL, never
  by qname, because the same method legitimately appears twice at different
  sites -- ReserveNextID has AddOperation at :4084 (depth 1) and again at :4102
  (depth 2, as a cycle row). Keying by name would collapse those two rows onto
  one port and silently lose an edge.

  Clustering by (Level, Unit) rather than by Unit alone is what makes the
  picture flow depth N -> ... -> depth 1 -> focus. It also guarantees no edge
  ever joins two ports of the SAME table, which dot renders as an unreadable
  self-loop through the box.

  TWO BUCKETS, NEVER ONE NUMBER
  -----------------------------
  `reverse-calltree` gives RESOLVED callers -- real call_edges. `query
  find-callers --name` gives NAME MATCHES, which is a different and much weaker
  claim. They are reported separately and never summed:

    Blueprint4.ViewModel.TBlueprint_ViewModel.ReserveNextID
      resolved 10   name 18   name-only 9

  All nine name-only rows are TBlueprint_CADImport_ViewModel.ReserveNextID and
  TBlueprint_PDFImport_ViewModel.ReserveNextID -- sibling classes that share a
  method name and call their OWN. None of them calls the focus.

  The same shape once produced a confidently wrong answer 63 times over:
  BASICSF.ProcessMessages has 0 resolved callers and 63 name matches, and all
  63 are `Application.ProcessMessages` -- a VCL symbol sharing a name.

  So the name bucket is COUNTED ALWAYS (it is cheap, and a silent zero is worth
  as much as a silent nine) but RENDERED only under -WithNameMatches, as a
  DASHED, explicitly labelled cluster with no edge to the focus. It is never
  added to Callers.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Qname,
  [Parameter(Mandatory)][string] $DbPath,   # NOT -Db: CmdletBinding aliases that to -Debug
  [string] $OutDir,
  [int]    $Depth      = 2,
  [switch] $WithNameMatches,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

# butterfly's palette, verbatim. No new roles: the name bucket is distinguished
# by a DASHED border and its own header text, the channel deps already uses for
# "true, but not the same grade of fact".
$PAL = @{
  callerBorder = '#3B5BDB'; callerFill = '#EDF2FF'; callerHdr = '#3B5BDB'
  focusBorder  = '#0F766E'; focusFill  = '#E2F1EF'; focusHdr  = '#0F766E'
  calleeBorder = '#B45309'; calleeFill = '#FEF6EC'; calleeHdr = '#B45309'
  rowInk       = '#1F2933'; lineInk    = '#8A94A6'; focusInk  = '#0B3F39'
}

# ---- 1. the RESOLVED bucket --------------------------------------------------
Write-Host "who-calls: $Qname (depth $Depth)"
$tree = Invoke-EngineJson @('reverse-calltree', '--qname', $Qname, '--direction', 'callers',
                            '--depth', "$Depth", '--format', 'json', '--db', $DbPath)

# Children live under `callers` at EVERY level. Parent is tracked by ORDINAL so
# an edge can point at the exact row it came from.
$rows = New-Object System.Collections.ArrayList
function Expand-Callers($node, [int] $parentIdx, [int] $lvl) {
  $kids = $node.callers
  if ($null -eq $kids) { return }
  foreach ($k in @($kids)) {
    $isCycle = [bool]$k.cycle
    $idx = $rows.Count
    [void]$rows.Add([pscustomobject]@{
      Idx = $idx; Qname = [string]$k.qname; Site = [string]$k.site
      File = [string]$k.file; Line = [int]$k.line
      Level = $lvl; Cycle = $isCycle; Parent = $parentIdx
    })
    # never expand a cycle row -- the engine already stopped there, and
    # recursing would re-walk a path we have already drawn
    if (-not $isCycle) { Expand-Callers $k $idx ($lvl + 1) }
  }
}
Expand-Callers $tree.root -1 1

$nodeCount = [int]$tree.summary.node_count
if (($rows.Count + 1) -ne $nodeCount) {
  throw "flatten mismatch: $($rows.Count) rows vs node_count $nodeCount -- did you read the wrong child key?"
}
if ($rows.Count -eq 0) {
  throw "$Qname has 0 callers in call_edges (node_count $nodeCount). If it is an event handler the caller is the DFM -- ask event-wiring instead."
}

$cycles   = @($rows | Where-Object { $_.Cycle }).Count
$maxDepth = ($rows | Measure-Object Level -Maximum).Maximum
Write-Host ("  resolved call sites={0}  cycles={1}  max depth={2}  truncated={3}" -f `
            $rows.Count, $cycles, $maxDepth, $tree.summary.truncated)

# ---- 2. the focus line -------------------------------------------------------
# root.line is 0 in this schema -- ask the index, and take the BODY (impl), not
# the interface declaration.
$focusLoc  = Get-SymbolLocation $Qname
$focusFile = $focusLoc.Path
$focusUnit = Get-UnitName $focusFile

# ---- 3. the NAME bucket, counted always, rendered only on request ------------
$bare = ($Qname -split '\.')[-1]
$nameRows = @()
$nameOnly = @()
try {
  $nm = Get-EngineText @('query', 'find-callers', '--name', $bare, '--db', $DbPath, '--json')
  if ($nm) { $nameRows = @($nm | ConvertFrom-Json) }
} catch {
  Write-Host "  NOTE: name-match probe failed ($($_.Exception.Message)); reporting resolved bucket only"
}
if ($nameRows.Count) {
  # subtract by CALL SITE (file+line), not by name -- a resolved caller and its
  # name match are the same physical site and must not be counted twice
  $seen = @{}
  foreach ($r in $rows) { $seen["$($r.File.ToLowerInvariant())|$($r.Line)"] = $true }
  $nameOnly = @($nameRows | Where-Object {
    -not $seen.ContainsKey("$(([string]$_.file_path).ToLowerInvariant())|$([int]$_.start_line)")
  })
}
Write-Host ("  name matches={0}  of which NOT resolved callers={1}{2}" -f `
            $nameRows.Count, $nameOnly.Count,
            $(if ($nameOnly.Count -and -not $WithNameMatches) { '  (pass -WithNameMatches to draw them)' } else { '' }))

# ---- 4. dot ------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph whocalls {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.1; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.5, arrowsize=0.8];")
[void]$sb.AppendLine('')

$nodeId  = 0
$portOf  = @{}   # row ORDINAL -> "nodeN:pM"
$clusters = 0

# deepest first, so the left-to-right flow is depth N -> ... -> depth 1 -> focus
$groups = $rows | Group-Object { "$($_.Level)|$(Get-UnitName $_.File)" } |
          Sort-Object { [int](($_.Name -split '\|')[0]) } -Descending
foreach ($g in $groups) {
  $parts = @($g.Name -split '\|')
  $lvl   = [int]$parts[0]
  $unit  = $parts[1]
  $nodeId++; $clusters++
  $nid = "n$nodeId"

  $cellRows = @($g.Group | ForEach-Object {
    [pscustomobject]@{
      Label = Get-ShortName $_.Qname $unit
      Line  = $_.Line
      Href  = New-RowHref $_.File $_.Line
      Tip   = "$($_.Qname)  --  $([IO.Path]::GetFileName($_.File)):$($_.Line)"
      Note  = $(if ($_.Cycle) { 'cycle' } else { $null })
    } })

  $ports = Add-RowCluster -Sb $sb -Cid "cluster_d${lvl}_$nodeId" -Nid $nid `
             -Title $unit -Subtitle "depth $lvl" -Rows $cellRows `
             -Border $PAL.callerBorder -Fill $PAL.callerFill -Hdr $PAL.callerHdr `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
  for ($i = 0; $i -lt $g.Group.Count; $i++) { $portOf[$g.Group[$i].Idx] = $ports[$i] }
}

# focus
[void]$sb.AppendLine('  subgraph cluster_focus {')
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=3;")
[void]$sb.AppendLine('    label=""; margin=12;')
$fhref = New-RowHref $focusFile $focusLoc.FocusLine
$fhdr  = "<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $focusUnit) &#183; focus </B></FONT></TD></TR>"
$ftip  = ConvertTo-XmlText "$Qname  --  $([IO.Path]::GetFileName($focusFile)):$($focusLoc.FocusLine)"
[void]$sb.AppendLine("    focus [label=<<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLSPACING=`"3`" CELLPADDING=`"7`">$fhdr<TR><TD HREF=`"$fhref`" TITLE=`"$ftip`"><FONT COLOR=`"$($PAL.focusInk)`" POINT-SIZE=`"18`"><B>$(ConvertTo-XmlText (Get-ShortName $Qname $focusUnit))</B></FONT></TD></TR></TABLE>>];")
[void]$sb.AppendLine('  }')

# the name bucket: DASHED, labelled, and deliberately NOT edged to the focus.
# An edge would assert a call relationship that is exactly what is unproven.
$nameRendered = $false
if ($WithNameMatches -and $nameOnly.Count) {
  $nameRendered = $true
  foreach ($g in ($nameOnly | Group-Object { Get-UnitName $_.file_path } | Sort-Object Name)) {
    $nodeId++; $clusters++
    $cellRows = @($g.Group | ForEach-Object {
      [pscustomobject]@{
        Label = [string]$_.name_text
        Line  = [int]$_.start_line
        Href  = New-RowHref ([string]$_.file_path) ([int]$_.start_line)
        Tip   = "NAME MATCH ONLY -- no resolved call edge to $Qname. $([IO.Path]::GetFileName([string]$_.file_path)):$($_.start_line)"
        Note  = 'name match'
      } })
    [void](Add-RowCluster -Sb $sb -Cid "cluster_nm_$nodeId" -Nid "n$nodeId" `
             -Title $g.Name -Subtitle 'name match, NOT a verified caller' -Rows $cellRows `
             -Border $PAL.callerBorder -Fill $PAL.callerFill -Hdr $PAL.callerHdr `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans `
             -Style 'rounded,filled,dashed')
  }
}

[void]$sb.AppendLine('')
foreach ($r in $rows) {
  $from = $portOf[$r.Idx]
  if (-not $from) { continue }
  $to = if ($r.Parent -lt 0) { 'focus' } else { $portOf[$r.Parent] }
  if (-not $to) { continue }
  $st = if ($r.Cycle) { ', style=dashed' } else { '' }
  [void]$sb.AppendLine("  $from -> $to [color=`"$($PAL.callerBorder)`"$st];")
}
[void]$sb.AppendLine('}')

# ---- 5. lay out --------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = ($Qname -replace '[^A-Za-z0-9]', '_')
$lay  = Invoke-DotLayout $sb.ToString() $OutDir $base

$drawn    = $rows.Count + $(if ($nameRendered) { $nameOnly.Count } else { 0 })
$expected = $drawn + 1

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Callers      = $rows.Count          # RESOLVED call sites. Never includes NameOnly.
  Cycles       = $cycles
  MaxDepth     = $maxDepth
  Truncated    = [bool]$tree.summary.truncated   # depth limit TOUCHED, not rows dropped
  Clusters     = $clusters
  NameMatches  = $nameRows.Count
  NameOnly     = $nameOnly.Count
  NameRendered = $nameRendered
  ClickTargets = $lay.Anchors
  Expected     = $expected
  AllClickable = ($lay.Anchors -ge $expected)
}
