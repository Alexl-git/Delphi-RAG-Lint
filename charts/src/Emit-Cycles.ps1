<#
  Emit-Cycles.ps1 -- the `cycles` question: which units form a uses-cycle, which
  edge of each cycle you would cut, and how much the cycle actually costs.

  >>> A "CYCLE" IS A STRONGLY-CONNECTED COMPONENT, NOT A RING <<<
  ---------------------------------------------------------------
  Two separate corrections to the plan's P3, both measured 2026-09-23. Either
  one alone produces a confidently wrong picture.

  1. `units[]` IS NOT IN TRAVERSAL ORDER. On the CLIENT clone:

         units[]        blueprint4, controlplan2, blueprint4.viewmodel
         real edges     Blueprint4 -> Blueprint4.ViewModel
                        Blueprint4.ViewModel -> ControlPlan2
                        ControlPlan2 -> Blueprint4

     Following the array would draw `blueprint4 -> controlplan2`, an edge that
     DOES NOT EXIST in the index.

  2. THE GROUP NEED NOT BE A SINGLE RING. The DL self-index reports one
     "cycle" of size 4, and its five measured edges are:

         facts -> harvest        harvest -> regions       regions -> facts
         regions -> sharedfacts  sharedfacts -> regions

     That is TWO loops sharing `regions`, and it has no Hamiltonian cycle at
     all. An earlier draft of this emitter walked the members expecting a ring
     and correctly refused to draw arrows -- but the refusal was the symptom,
     not the answer. CLIENT hid this because both of its groups happen to be
     simple cycles.

  So: members come from the verb, and EVERY edge is looked up in `unit_uses` and
  drawn only if it is really there. No traversal order is assumed anywhere. An
  arrow in this chart is a measured uses edge or it is not drawn.

  The header says "group N" rather than "cycle N" for the same reason -- calling
  a 4-unit SCC a cycle is what invited the ring assumption in the first place.

  ANCHORING: THE TRAP IS CASE (P4)
  --------------------------------
  The verb lowercases unit names (`blueprint4.viewmodel`) while the index stores
  real casing (`Blueprint4.ViewModel`, `Gagefrm2` for a file called
  `GAGEFRM2.PAS`). Every lookup here is case-insensitive, and any member that
  fails to anchor is COUNTED AND SHOWN as unanchored rather than quietly drawn
  as a plain row -- an un-anchored cycle chart looks perfectly fine and clicks
  nowhere, which is the failure this project exists to prevent.

  Each row anchors to the `uses` clause that creates that unit's outgoing edge,
  because that line is the thing you would actually edit -- not the unit header.

  SEVERITY IS A REAL DISTINCTION, NOT DECORATION
  ----------------------------------------------
  `interface_cycle:false` means every edge is an implementation-section use,
  which Delphi permits and which carries no interface-recompile blast radius.
  Drawing that the same as an interface cycle would overstate it. Both CLIENT
  cycles are implementation-only; the interface styling is carried for a corpus
  that has one.

  `interface_cycle:true` is NOT an interface cycle either: the verb sets it when
  ANY intra-group edge is interface-section. R3 (2026-10-06) verified DL's group
  against the source: 1 of 7 edges is interface (Regions -> Facts, :42), every
  loop crosses an implementation use, and the project compiles. So the group
  keeps the interface styling (that coupling is real) but the verdict counts the
  sections and says "interface cycle" only for an all-interface loop, and each
  arrow is coloured by its OWN section.

  The one-line verdict per cycle comes from `cycles --plan`, the engine's own
  playbook, so this chart and that playbook cannot drift apart.
#>
[CmdletBinding()]
param(
  [string] $Unit,                            # optional: only cycles containing this unit
  [Parameter(Mandatory)][string] $DbPath,
  [string] $OutDir,
  [int]    $MaxCycles  = 12,
  # Fetch the engine's one-line verdict from `cycles --plan`.
  #
  # OFF BY DEFAULT, and the reason is measured: on the CLIENT clone
  # `cycles --format json` takes 0.8s and `cycles --plan` takes 46.5s -- 58x the
  # whole cost of the chart, to supply ONE label per cycle. The fallback says the
  # same thing in substance ("interface coupling" / "implementation-only") from
  # the `interface_cycle` flag and the edge sections the chart already reads.
  #
  # This is a deliberate deviation from PLAN-next-five-verbs.md Task 2, which
  # specified `--plan` for the playbook text unconditionally. Pass -Playbook when
  # the engine's exact wording is wanted and the 46s is acceptable.
  [switch] $Playbook,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

# Refuse a live corpus DB (see Get-CloneDb): charts run against the frozen clones.
$DbPath = Get-CloneDb $DbPath

$PAL = @{
  implBorder  = '#B45309'; implFill  = '#FEF6EC'; implHdr  = '#B45309'   # implementation-only
  intfBorder  = '#B02A37'; intfFill  = '#FDECEE'; intfHdr  = '#B02A37'   # interface coupling: costly
  cleanBorder = '#0F766E'; cleanFill = '#E2F1EF'; cleanHdr = '#0F766E'   # no cycles
  focusBorder = '#3B5BDB'; focusFill = '#EDF2FF'; focusHdr = '#3B5BDB'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}

Write-Host "cycles: $(if ($Unit) { $Unit } else { '(whole project)' })"

# ---- 1. the cycles themselves --------------------------------------------------
# `cycles` exits 0 and prints `[]` when there are none (measured on DataCopy),
# so an EMPTY answer is a failure, not "no cycles" (R19).
$cyclesTxt = Get-EngineText @('cycles', '--db', $DbPath, '--format', 'json')
if ([string]::IsNullOrWhiteSpace($cyclesTxt)) { throw "cycles returned no document (exit $script:LastEngineExit)" }
$cycles = @($cyclesTxt | ConvertFrom-Json)

# ---- 2. the engine's own verdict line, per cycle --------------------------------
# Parsed from `cycles --plan` rather than re-derived, so the chart says exactly
# what the playbook says. A missing Status line degrades to the interface_cycle
# flag below; it never guesses. Skipped entirely when there are no cycles --
# there would be nothing to say, and it is the slowest call in the emitter.
$verdicts = @{}
if ($Playbook -and $cycles.Count -gt 0) {
  Write-Host '  fetching cycles --plan (measured ~46s on CLIENT) ...'
  # through the shared wrapper: a failed --plan run throws instead of reading
  # as "no Status lines" (R19)
  $planTxt = Invoke-EngineRaw @('cycles', '--db', $DbPath, '--plan')
  foreach ($m in [regex]::Matches($planTxt, '(?m)^##\s+Cycle\s+(\d+):[^\r\n]*\r?\n+Status:\s*(.+?)\r?$')) {
    $verdicts[[int]$m.Groups[1].Value] = ($m.Groups[2].Value -replace '\*\*', '').Trim()
  }
}

# ---- 3. filter to the selection -------------------------------------------------
if ($Unit) {
  $needle = $Unit.ToLowerInvariant()
  $kept = @($cycles | Where-Object { @($_.units | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $needle })
  if ($kept.Count -eq 0 -and $cycles.Count -gt 0) {
    throw ("$Unit is in no cycle in this index ($($cycles.Count) cycle(s) exist). " +
           'Run without -Unit to see them, or check the spelling -- the verb lowercases unit names.')
  }
  # Remember which indexes they were, so the verdict numbering still matches --plan.
  $selected = @()
  for ($i = 0; $i -lt $cycles.Count; $i++) {
    if (@($cycles[$i].units | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $needle) {
      $selected += [pscustomobject]@{ Ordinal = $i + 1; Cycle = $cycles[$i] }
    }
  }
} else {
  $selected = @()
  for ($i = 0; $i -lt $cycles.Count; $i++) {
    $selected += [pscustomobject]@{ Ordinal = $i + 1; Cycle = $cycles[$i] }
  }
}

$totalCycles = $cycles.Count
$top = Get-TopRanked $selected $MaxCycles 'Ordinal'
$selected = @($top.Shown)

# ---- 4. resolve every member unit to a file (case-insensitively) ----------------
$members = @($selected | ForEach-Object { $_.Cycle.units } | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
$unitRow = @{}
if ($members.Count) {
  $rows = Invoke-IndexQuery @"
SELECT s.qualified_name AS q, f.path AS path, f.id AS fid, s.start_line AS line
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.kind = 'unit' AND LOWER(s.qualified_name) IN ($(ConvertTo-SqlInList $members))
"@ 'cycles Q1 (member units)'
  foreach ($r in $rows) { $unitRow[([string]$r.q).ToLowerInvariant()] = $r }
}

# ---- 5. the REAL edges among those members --------------------------------------
# Only edges the index actually holds. Anything the verb implies but the index
# does not contain is reported, never drawn.
$edgeKey = @{}
if ($members.Count) {
  $inList = ConvertTo-SqlInList $members
  $erows = Invoke-IndexQuery @"
SELECT LOWER(su.qualified_name) AS src, LOWER(uu.unit_name) AS dst,
       uu.section AS section, uu.start_line AS line, sf.path AS path
  FROM unit_uses uu
  JOIN files sf ON sf.id = uu.file_id
  JOIN symbols su ON su.file_id = sf.id AND su.kind = 'unit'
 WHERE LOWER(su.qualified_name) IN ($inList) AND LOWER(uu.unit_name) IN ($inList)
"@ 'cycles Q2 (member edges)'
  foreach ($e in $erows) {
    $k = [string]$e.src + '|' + [string]$e.dst
    if (-not $edgeKey.ContainsKey($k)) { $edgeKey[$k] = $e }
  }
}

# Every measured intra-group edge leaving a unit, in line order. Sorted, not left
# in the verb's member order: the row anchors to the FIRST of these, and R3
# measured the difference -- DL's SharedFacts uses Regions at :446 and
# ProjectTags at :447, and member order anchored the row at :447.
function Get-OutEdges([string] $From, [string[]] $Members) {
  $out = New-Object System.Collections.ArrayList
  foreach ($m in $Members) {
    if ($m -eq $From) { continue }
    $k = $From + '|' + $m
    if ($edgeKey.ContainsKey($k)) {
      [void]$out.Add([pscustomobject]@{ To = $m; Edge = $edgeKey[$k] })
    }
  }
  , @($out | Sort-Object { [int]$_.Edge.line })
}

# True when the INTERFACE-section edges alone close a loop among the members --
# the shape the compiler refuses (F2047). `interface_cycle:true` from the verb
# means only that ONE intra-group edge is interface-section (R3: DL's group has
# 1 of 7, and it compiles), so the verdict must not be read off that flag alone.
function Test-InterfaceLoop([string[]] $Members) {
  $state = @{}   # 1 = on the DFS path, 2 = done
  $visit = {
    param([string] $u)
    $state[$u] = 1
    foreach ($m in $Members) {
      $e = $edgeKey[$u + '|' + $m]
      if (-not $e -or [string]$e.section -ne 'interface') { continue }
      if ($state[$m] -eq 1) { return $true }
      if (-not $state[$m] -and (& $visit $m)) { return $true }
    }
    $state[$u] = 2
    $false
  }
  foreach ($u in $Members) { if (-not $state[$u] -and (& $visit $u)) { return $true } }
  $false
}

# ---- 6. dot ---------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph cycles {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.4; ranksep=0.9; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')

$nodeId = 0; $clusters = 0
$anchored = 0; $unanchored = 0; $drawnEdges = 0; $unwalkable = 0
$edgeList = New-Object System.Collections.ArrayList   # 'src->dst section line', for the pins
$focusNote = New-Object System.Collections.ArrayList

foreach ($item in $selected) {
  $c = $item.Cycle
  $mem = @($c.units | ForEach-Object { ([string]$_).ToLowerInvariant() })

  # rows: each member, anchored to the FIRST uses clause that keeps it in the
  # group -- the line you would actually edit to break it. A member with several
  # intra-group uses (regions, in the DL group) names all of them in its tooltip
  # and carries the count on the row, so the one href is never mistaken for the
  # whole story.
  $cells = New-Object System.Collections.ArrayList
  $rowMember = New-Object System.Collections.ArrayList
  foreach ($u in $mem) {
    $ur = $(if ($unitRow.ContainsKey($u)) { $unitRow[$u] } else { $null })
    $outs = Get-OutEdges $u $mem
    $label = $(if ($ur) { [string]$ur.q } else { $u })
    [void]$rowMember.Add($u)

    if ($outs.Count -gt 0) {
      $first = $outs[0]
      $anchored++
      $all = ($outs | ForEach-Object { "$($_.To) ($([string]$_.Edge.section), line $($_.Edge.line))" }) -join '; '
      [void]$cells.Add([pscustomobject]@{
        Label = $label; Line = [int]$first.Edge.line
        Href  = New-RowHref ([string]$first.Edge.path) ([int]$first.Edge.line)
        Tip   = "$label uses $all"
        Note  = $(if ($outs.Count -eq 1) { "uses $($first.To) ($([string]$first.Edge.section))" }
                  else { "uses $($outs.Count) of these units; href goes to the first" })
      })
    } elseif ($ur) {
      # In a strongly-connected group every member has an outgoing intra-group
      # edge, so this is a genuine index gap, not a normal shape.
      $anchored++
      [void]$cells.Add([pscustomobject]@{
        Label = $label; Line = [int]$ur.line
        Href  = New-RowHref ([string]$ur.path) ([int]$ur.line)
        Tip   = "$label -- $([IO.Path]::GetFileName([string]$ur.path)); the index holds NO uses edge from it to another member of this group"
        Note  = 'no measured outgoing edge in this group'
      })
      $unwalkable++
      [void]$focusNote.Add("group $($item.Ordinal): $u has no measured outgoing edge to another member")
    } else {
      $unanchored++
      [void]$cells.Add((New-NoteRow "$u (not resolvable in this index)"))
    }
  }

  $isIntf = [bool]$c.interface_cycle
  $border = $(if ($isIntf) { $PAL.intfBorder } else { $PAL.implBorder })
  $fill   = $(if ($isIntf) { $PAL.intfFill }   else { $PAL.implFill })
  $hdr    = $(if ($isIntf) { $PAL.intfHdr }    else { $PAL.implHdr })
  # implementation-only cycles are legal Delphi: dashed, so they do not read with
  # the same weight as an interface cycle.
  $style  = $(if ($isIntf) { 'rounded,filled' } else { 'rounded,filled,dashed' })

  # The fallback verdict counts the sections instead of echoing the flag: an
  # "interface cycle" is a loop the compiler refuses, and a group with one
  # interface edge among implementation ones is not that (R3, DL group 1).
  $grpEdges = @(foreach ($u in $mem) { foreach ($o in (Get-OutEdges $u $mem)) { $o } })
  $nIntf = @($grpEdges | Where-Object { [string]$_.Edge.section -eq 'interface' }).Count
  $verdict = $(if ($verdicts.ContainsKey($item.Ordinal)) { $verdicts[$item.Ordinal] }
               elseif (-not $isIntf) { 'implementation-only' }
               elseif (Test-InterfaceLoop $mem) { "interface cycle: an all-interface loop, which the compiler refuses ($nIntf of $($grpEdges.Count) uses interface-section)" }
               else { "interface coupling: $nIntf of $($grpEdges.Count) uses interface-section; every loop crosses an implementation use" })
  [void]$cells.Add((New-NoteRow $verdict))

  $nodeId++; $clusters++
  $nid = "n$nodeId"
  $ports = Add-RowCluster -Sb $sb -Cid "cluster_cycle_$nodeId" -Nid $nid `
             -Title "group $($item.Ordinal)" -Subtitle "$($c.size) units" -Rows $cells.ToArray() `
             -Border $border -Fill $fill -Hdr $hdr `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style $style

  # arrows: EVERY measured intra-group edge, each labelled with the line and
  # section that create it. No traversal order is assumed, because the group is
  # a strongly-connected component and need not be a single ring.
  $portOf = @{}
  for ($i = 0; $i -lt $rowMember.Count; $i++) { $portOf[$rowMember[$i]] = $ports[$i] }
  foreach ($u in $mem) {
    foreach ($o in (Get-OutEdges $u $mem)) {
      if (-not ($portOf.ContainsKey($u) -and $portOf.ContainsKey($o.To))) { continue }
      $isIntfEdge = ([string]$o.Edge.section -eq 'interface')
      # colour by the EDGE's section, not the group's: in a mixed group the one
      # interface arrow must stand out from the implementation ones
      $ecol = $(if ($isIntfEdge) { $PAL.intfBorder } else { $PAL.implBorder })
      $epen = $(if ($isIntfEdge) { '2.2' } else { '1.6' })
      [void]$sb.AppendLine("  $($portOf[$u]) -> $($portOf[$o.To]) [color=`"$ecol`", penwidth=$epen, label=`":$($o.Edge.line)`"];")
      $drawnEdges++
      [void]$edgeList.Add("$u->$($o.To) $([string]$o.Edge.section) $([int]$o.Edge.line)")
    }
  }
}

# ---- 7. the zero case is an ANSWER (N18) -----------------------------------------
if ($selected.Count -eq 0) {
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  [void](Add-RowCluster -Sb $sb -Cid "cluster_clean_$nodeId" -Nid $nid `
           -Title 'no cycles' -Subtitle 'uses-graph is acyclic' `
           -Rows @((New-NoteRow 'the index holds no unit cycle')) `
           -Border $PAL.cleanBorder -Fill $PAL.cleanFill -Hdr $PAL.cleanHdr `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans)
}

# ---- 8. focus box ------------------------------------------------------------------
$nodeId++; $clusters++
$fnid = "n$nodeId"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
$title = $(if ($Unit) { "cycles containing $Unit" } else { 'unit cycles' })
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $title) </B></FONT></TD></TR>")
Add-DisclosureRow $ftbl "$totalCycles cycle(s) in this index  &#183;  $($selected.Count) shown" $PAL.lineInk
Add-DisclosureRow $ftbl "$drawnEdges measured uses edge(s) drawn  &#183;  $anchored anchored row(s)" $PAL.lineInk
if ($unanchored -gt 0) { Add-DisclosureRow $ftbl "$unanchored member(s) could not be anchored" $PAL.lineInk }
Add-DisclosureRow $ftbl 'arrows are uses edges read from the index, not the order the verb lists members in' $PAL.lineInk
$disc = Get-DisclosureText $top.HiddenRows 0 'cycles'
if ($disc) { Add-DisclosureRow $ftbl $disc $PAL.lineInk }
foreach ($n in $focusNote) { Add-DisclosureRow $ftbl $n $PAL.lineInk }
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')
[void]$sb.AppendLine('}')

Write-Host ("  cycles={0} shown={1}  edges drawn={2}  anchored={3}  unanchored={4}  unwalkable={5}" -f `
            $totalCycles, $selected.Count, $drawnEdges, $anchored, $unanchored, $unwalkable)

# ---- 9. lay out ---------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = 'cycles_' + $(if ($Unit) { ($Unit -replace '[^A-Za-z0-9]', '_') } else { 'project' })
$lay = Invoke-DotLayout $sb.ToString() $OutDir $base

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Cycles       = $totalCycles
  Shown        = $selected.Count
  Edges        = $drawnEdges
  EdgeList     = $edgeList.ToArray()
  Anchored     = $anchored
  Unanchored   = $unanchored
  Unwalkable   = $unwalkable
  Clusters     = $clusters
  ClickTargets = $lay.Anchors
  Expected     = $anchored
  AllClickable = ($lay.Anchors -ge $anchored)
}
