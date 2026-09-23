<#
  Emit-Architecture.ps1 -- the `architecture` question, in the only two halves
  this index can actually answer.

  WHAT deps-report DOES AND DOES NOT SAY (P10)
  ---------------------------------------------
  `deps-report --format json` classifies EXTERNAL units only. On the CLIENT
  clone: 283 externals, 30,702 external edges, all 283 `resolved:false`, in 5
  groups -- RTL 58, DevExpress 163, Spring4D 4, FireDAC 10, unknown 48. Its
  `project_unit_count` is "project units that USE that group", not a count of
  project units in it, and the group objects carry NO edge_count at all
  (measured: group / unit_count / project_unit_count, nothing else).

  So it says NOTHING about the internal structure of the 563 project units,
  which is most of what an architecture chart is. That has to come from
  `unit_uses.target_file_id` -- 2,858 internal edges -- and a layering rule.

  THE LAYERING RULE, MEASURED RATHER THAN INVENTED
  -------------------------------------------------
  The obvious candidates were tested on the CLIENT clone and most of them fail:

      namespace prefix   512 of 563 units have NO DOT           -- unusable
      dotted suffix      ViewModel 36, Interfaces 4, Model 2    -- 9% coverage
      SOURCE DIRECTORY   CLIENT 268, COMMON/OBJECTS 268,
                         COMMON 27                              -- 100% coverage

  So the zones are SOURCE DIRECTORIES relative to the project's common root.
  That is a real structural boundary in this codebase (a shared object layer
  beneath a client app), it covers every unit, and it is read from the index
  rather than asserted. Where a project keeps everything in one folder there is
  only one zone, and the chart says so instead of manufacturing layers.

  BACK-EDGES ARE THE FINDING, AND THEY ARE MEASURED, NOT JUDGED
  --------------------------------------------------------------
  Between any two zones this chart reports BOTH directions. On CLIENT:

      CLIENT -> COMMON          721    COMMON -> CLIENT          8
      CLIENT -> COMMON/OBJECTS  449    COMMON/OBJECTS -> CLIENT  5

  13 edges run against a 1,170-edge flow. This chart calls that a BACK-EDGE
  against the dominant direction and draws it in red -- it does NOT call it a
  layering violation, because nothing in the index declares an intended layer
  order. The asymmetry is the measurement; what it means is the reader's call.

  NOT `graph` (P11)
  ------------------
  The `graph` verb's edges are `LOWER(s.name)=LOWER(r.name_text)` NAME MATCHES
  (CLI.pas:8088), not uses-edges. A dependency chart built on name collisions
  would be confidently wrong, which is worse than absent.

  EXTERNALS CANNOT BE ANCHORED, AND SAY SO
  -----------------------------------------
  All 283 externals are `resolved:false` -- they are not in this index -- so
  their rows carry no href. A dead link is worse than no link.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $DbPath,
  [string] $OutDir,
  [int]    $MaxPerZone = 6,
  [switch] $NoExternals,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

# Refuse a live corpus DB (see Get-CloneDb): charts run against the frozen clones.
$DbPath = Get-CloneDb $DbPath

$PAL = @{
  zoneBorder  = '#3B5BDB'; zoneFill  = '#EDF2FF'; zoneHdr  = '#3B5BDB'
  extBorder   = '#6B7280'; extFill   = '#F3F4F6'; extHdr   = '#6B7280'
  unkBorder   = '#B45309'; unkFill   = '#FEF6EC'; unkHdr   = '#B45309'
  backEdge    = '#B02A37'
  focusBorder = '#0F766E'; focusFill = '#E2F1EF'; focusHdr = '#0F766E'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}

Write-Host 'architecture: (whole project)'

# ---- 1. every unit, with its file -------------------------------------------------
# Paged: the sql verb caps at 200 rows SILENTLY, and a short answer here would
# quietly shrink the whole architecture.
function Get-AllRows([string] $Sql, [string] $OrderKey) {
  $out = New-Object System.Collections.ArrayList
  $off = 0
  while ($true) {
    $page = Invoke-IndexQuery "$Sql ORDER BY $OrderKey LIMIT 180 OFFSET $off"
    if ($page.Count -eq 0) { break }
    foreach ($r in $page) { [void]$out.Add($r) }
    if ($page.Count -lt 180) { break }
    $off += 180
  }
  , $out.ToArray()
}

$units = Get-AllRows @'
SELECT s.qualified_name AS q, s.start_line AS line, f.path AS path, f.id AS fid
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.kind = 'unit'
'@ 's.qualified_name'
if ($units.Count -eq 0) { throw 'architecture: this index holds no unit symbols at all' }

# ---- 2. zones = source directory relative to the common root ------------------------
# Get-CommonRootLen / Get-PathZone live in Emit-Common because protocol-trace and
# crosses-boundary zone the same paths, and a chart that compares zones across
# indexes cannot afford two definitions of where the root is.
$dirs = @($units | ForEach-Object { [IO.Path]::GetDirectoryName([string]$_.path) } | Sort-Object -Unique)
$rootLen = Get-CommonRootLen $dirs
$rootPath = $(if ($rootLen -gt 0) { (($dirs[0] -split '\\')[0..($rootLen - 1)]) -join '\' } else { '(no common root)' })

$zoneOf = @{}     # file id -> zone
$zoneUnits = @{}  # zone -> list of unit rows
foreach ($u in $units) {
  $z = Get-PathZone ([string]$u.path) $rootLen
  $zoneOf[[int]$u.fid] = $z
  if (-not $zoneUnits.ContainsKey($z)) { $zoneUnits[$z] = New-Object System.Collections.ArrayList }
  [void]$zoneUnits[$z].Add($u)
}
$zones = @($zoneUnits.Keys | Sort-Object { $zoneUnits[$_].Count } -Descending)
Write-Host ("  root: $rootPath")
foreach ($z in $zones) { Write-Host ("    zone $z : $($zoneUnits[$z].Count) units") }

$singleZone = ($zones.Count -le 1)

# ---- 3. internal edges, aggregated zone -> zone -------------------------------------
$edges = Get-AllRows @'
SELECT uu.file_id AS src, uu.target_file_id AS dst, uu.section AS section
  FROM unit_uses uu
 WHERE uu.target_file_id IS NOT NULL
'@ 'uu.id'

$matrix = @{}     # "a|b" -> @{ N; Intf }
$inDegree = @{}   # target file id -> count (how many units use it)
foreach ($e in $edges) {
  $a = $(if ($zoneOf.ContainsKey([int]$e.src)) { $zoneOf[[int]$e.src] } else { $null })
  $b = $(if ($zoneOf.ContainsKey([int]$e.dst)) { $zoneOf[[int]$e.dst] } else { $null })
  $tid = [int]$e.dst
  if (-not $inDegree.ContainsKey($tid)) { $inDegree[$tid] = 0 }
  $inDegree[$tid]++
  if ($null -eq $a -or $null -eq $b) { continue }
  $k = "$a|$b"
  if (-not $matrix.ContainsKey($k)) { $matrix[$k] = [pscustomobject]@{ N = 0; Intf = 0 } }
  $matrix[$k].N++
  if ([string]$e.section -eq 'interface') { $matrix[$k].Intf++ }
}
Write-Host ("  internal edges: $($edges.Count)")

# back-edges: for each unordered pair, the smaller direction against the larger
$backEdges = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $zones.Count; $i++) {
  for ($j = $i + 1; $j -lt $zones.Count; $j++) {
    $a = $zones[$i]; $b = $zones[$j]
    $ab = $(if ($matrix.ContainsKey("$a|$b")) { $matrix["$a|$b"].N } else { 0 })
    $ba = $(if ($matrix.ContainsKey("$b|$a")) { $matrix["$b|$a"].N } else { 0 })
    if ($ab -gt 0 -and $ba -gt 0) {
      if ($ab -ge $ba) { [void]$backEdges.Add([pscustomobject]@{ From = $b; To = $a; N = $ba; Against = $ab }) }
      else             { [void]$backEdges.Add([pscustomobject]@{ From = $a; To = $b; N = $ab; Against = $ba }) }
    }
  }
}
foreach ($b in $backEdges) { Write-Host ("  back-edge: $($b.From) -> $($b.To)  $($b.N) against $($b.Against)") }

# ---- 4. externals -------------------------------------------------------------------
$groups = @(); $extByGroup = @{}; $extUnits = 0; $extEdges = 0
if (-not $NoExternals) {
  $dr = Invoke-EngineJson @('deps-report', '--db', $DbPath, '--format', 'json')
  $groups = @($dr.summary.groups)
  $extUnits = [int]$dr.summary.external_unit_count
  $extEdges = [int]$dr.summary.external_edge_count
  foreach ($x in @($dr.externals)) {
    $g = [string]$x.group
    if (-not $extByGroup.ContainsKey($g)) { $extByGroup[$g] = New-Object System.Collections.ArrayList }
    [void]$extByGroup[$g].Add($x)
  }
  Write-Host ("  externals: $extUnits unit(s), $extEdges edge(s), $($groups.Count) group(s)")
}

# A vendor-looking name that landed in `unknown` is a CLASSIFIER gap, not a
# finding about the code. Detected rather than hardcoded to `spring`, so the
# note keeps working when the classifier changes.
$vendorish = New-Object System.Collections.ArrayList
if ($extByGroup.ContainsKey('unknown')) {
  $known = @($groups | ForEach-Object { [string]$_.group } | Where-Object { $_ -ne 'unknown' })
  foreach ($x in $extByGroup['unknown']) {
    $nm = [string]$x.unit
    foreach ($g in $known) {
      $stem = $g -replace '[^A-Za-z]', ''
      if ($stem.Length -ge 4 -and $nm -match "^(?i)$([regex]::Escape($stem.Substring(0, [Math]::Min(6, $stem.Length))))") {
        [void]$vendorish.Add("$nm is in 'unknown' but looks like $g")
        break
      }
    }
  }
}
foreach ($v in $vendorish) { Write-Host "  NOTE: $v" }

# ---- 5. dot ---------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph architecture {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.45; ranksep=1.5; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.8];")
[void]$sb.AppendLine('')

$nodeId = 0; $clusters = 0; $anchored = 0
$zonePort = @{}

# LEFT: one cluster per internal zone, rows are its most-depended-upon units
foreach ($z in $zones) {
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  $ranked = @($zoneUnits[$z] | Sort-Object @{ E = { $(if ($inDegree.ContainsKey([int]$_.fid)) { $inDegree[[int]$_.fid] } else { 0 }) }; Descending = $true },
                               @{ E = { [string]$_.q }; Descending = $false })
  $topz = Get-TopRanked $ranked $MaxPerZone 'fid'
  $cells = New-Object System.Collections.ArrayList
  foreach ($u in $topz.Shown) {
    $deg = $(if ($inDegree.ContainsKey([int]$u.fid)) { $inDegree[[int]$u.fid] } else { 0 })
    $anchored++
    [void]$cells.Add([pscustomobject]@{
      Label = [string]$u.q; Line = [int]$u.line
      Href  = New-RowHref ([string]$u.path) ([int]$u.line)
      Tip   = "$([string]$u.q) -- used by $deg unit(s) in this project"
      Note  = "used by $deg"
    })
  }
  $d = Get-DisclosureText $topz.HiddenRows 0 'units'
  if ($d) { [void]$cells.Add((New-NoteRow $d)) }
  $ports = Add-RowCluster -Sb $sb -Cid "cluster_zone_$nodeId" -Nid $nid `
             -Title $z -Subtitle "$($zoneUnits[$z].Count) units" -Rows $cells.ToArray() `
             -Border $PAL.zoneBorder -Fill $PAL.zoneFill -Hdr $PAL.zoneHdr `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
  $zonePort[$z] = $ports[0]
}

# arrows between zones, labelled with the measured edge count
[void]$sb.AppendLine('')
$backKey = @{}
foreach ($b in $backEdges) { $backKey["$($b.From)|$($b.To)"] = $b }
$drawn = 0
foreach ($k in $matrix.Keys) {
  $parts = $k -split '\|', 2
  $a = $parts[0]; $b = $parts[1]
  if ($a -eq $b) { continue }                       # self-dependency is not a layering fact
  if (-not ($zonePort.ContainsKey($a) -and $zonePort.ContainsKey($b))) { continue }
  $m = $matrix[$k]
  $isBack = $backKey.ContainsKey($k)
  $col = $(if ($isBack) { $PAL.backEdge } else { $PAL.zoneBorder })
  $sty = $(if ($isBack) { ', style=dashed' } else { '' })
  $lbl = "$($m.N)$(if ($isBack) { ' back' } else { '' })"
  [void]$sb.AppendLine("  $($zonePort[$a]) -> $($zonePort[$b]) [color=`"$col`", penwidth=$(if ($isBack) { '2.2' } else { '1.6' })$sty, label=`"$lbl`"];")
  $drawn++
}

# RIGHT: third-party groups
if (-not $NoExternals) {
  foreach ($g in ($groups | Sort-Object { [int]$_.unit_count } -Descending)) {
    $gname = [string]$g.group
    $nodeId++; $clusters++
    $nid = "n$nodeId"
    $isUnknown = ($gname -eq 'unknown')
    $list = $(if ($extByGroup.ContainsKey($gname)) { @($extByGroup[$gname] | Sort-Object { [int]$_.used_by_count } -Descending) } else { @() })
    $topg = Get-TopRanked $list $MaxPerZone 'used_by_count'
    $cells = New-Object System.Collections.ArrayList
    foreach ($x in $topg.Shown) {
      # unresolved by definition: no file in this index, so NO href
      [void]$cells.Add((New-NoteRow "$([string]$x.unit)  (used by $([int]$x.used_by_count))"))
    }
    $d = Get-DisclosureText $topg.HiddenRows 0 'units'
    if ($d) { [void]$cells.Add((New-NoteRow $d)) }
    [void]$cells.Add((New-NoteRow "used by $([int]$g.project_unit_count) project unit(s)"))
    [void](Add-RowCluster -Sb $sb -Cid "cluster_ext_$nodeId" -Nid $nid `
             -Title $gname -Subtitle "$([int]$g.unit_count) external units" -Rows $cells.ToArray() `
             -Border $(if ($isUnknown) { $PAL.unkBorder } else { $PAL.extBorder }) `
             -Fill $(if ($isUnknown) { $PAL.unkFill } else { $PAL.extFill }) `
             -Hdr $(if ($isUnknown) { $PAL.unkHdr } else { $PAL.extHdr }) `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style 'rounded,filled,dashed')
  }
}

# FOCUS
$nodeId++; $clusters++
$fnid = "n$nodeId"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> architecture </B></FONT></TD></TR>")
Add-DisclosureRow $ftbl "$($units.Count) project units in $($zones.Count) source zone(s) under $rootPath" $PAL.lineInk
Add-DisclosureRow $ftbl "$($edges.Count) internal uses edges  &#183;  $drawn cross-zone arrow(s) drawn" $PAL.lineInk
if ($singleZone) {
  Add-DisclosureRow $ftbl 'this project keeps every unit in one folder, so there are no internal zones to draw' $PAL.lineInk
}
foreach ($b in $backEdges) {
  Add-DisclosureRow $ftbl "back-edge: $($b.From) -> $($b.To), $($b.N) edge(s) against $($b.Against) the other way" $PAL.lineInk
}
if ($backEdges.Count -gt 0) {
  Add-DisclosureRow $ftbl 'a back-edge is an asymmetry this index measured; no layer order is declared anywhere' $PAL.lineInk
}
Add-DisclosureRow $ftbl 'zones are SOURCE DIRECTORIES: namespace prefixes cover only 9% of units here' $PAL.lineInk
if (-not $NoExternals) {
  Add-DisclosureRow $ftbl "$extUnits external units over $extEdges external edges, none resolved in this index" $PAL.lineInk
  Add-DisclosureRow $ftbl 'third-party rows carry no link: those units are not in this index' $PAL.lineInk
  foreach ($v in $vendorish) { Add-DisclosureRow $ftbl "classifier gap: $v" $PAL.lineInk }
}
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')
[void]$sb.AppendLine('}')

# ---- 6. lay out --------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$lay = Invoke-DotLayout $sb.ToString() $OutDir 'architecture'

[pscustomobject]@{
  Dot           = $lay.Dot
  Svg           = $lay.Svg
  Plain         = $lay.Plain
  Png           = $lay.Png
  Pdf           = $lay.Pdf
  Units         = $units.Count
  Zones         = $zones.Count
  InternalEdges = $edges.Count
  CrossZone     = $drawn
  BackEdges     = $backEdges.Count
  ExternalUnits = $extUnits
  ExternalEdges = $extEdges
  Groups        = $groups.Count
  ClassifierGaps= $vendorish.Count
  Clusters      = $clusters
  ClickTargets  = $lay.Anchors
  Expected      = $anchored
  AllClickable  = ($lay.Anchors -ge $anchored)
}
