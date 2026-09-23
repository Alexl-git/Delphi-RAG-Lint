<#
  Emit-ChangeImpact.ps1 -- the `change-impact` question: if I change this, what
  else is affected?

  WHY THIS IS SAFE TO BUILD WHILE THE CALLEE DIRECTION IS NOT
  -------------------------------------------------------------
  This question was parked as "walks call_edges, which is skewed". That was too
  coarse. Impact fans out over CALLERS -- from the symbol UP to everything that
  depends on it -- and measured 2026-09-23 the caller direction is intact:
  `SendDeltaOperation` reports 9 callers, exactly matching the assertion frozen
  before the corpus was reindexed, and the depth-3 caller assertions in
  Test-Emitters.ps1 still pass. It is the CALLEE direction that lost edges
  (32 call refs in that method's body, only 2 with a call_edges row).

  So: callers yes, callees no. That distinction is the whole reason this ships
  now and `tested-by`'s callee half does not.

  IT IS NOT who-calls WITH A BIGGER DEPTH
  ----------------------------------------
  who-calls answers "who calls this", and its rows are CALL SITES. The impact
  question is answered in UNITS and ZONES, because that is the unit of work a
  reader plans against: "this touches 3 zones and 17 units" is actionable where
  "this has 84 call sites" is not. Same edges, deliberately different summary --
  the rows here are the DISTANCE-RANKED dependents, grouped by where they live.

  A TYPE IS NOT JUST ITS METHODS
  -------------------------------
  Selecting a type seeds the walk with the type symbol AND every member it
  declares AND the `type_use` references to the type itself, because code that
  merely names the type in a declaration is affected by changing it even though
  it calls nothing.

  THE WALK IS BOUNDED, AND SAYS SO
  ---------------------------------
  Impact is transitively enormous in a 563-unit project, so the frontier is
  capped and the cap is reported. A truncated blast radius that does not admit
  it is worse than a small one.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][Alias('Qname','Type')][string] $Target,
  [Parameter(Mandatory)][string] $DbPath,
  [string] $OutDir,
  [int]    $Depth    = 3,
  [int]    $MaxNodes = 400,          # frontier cap; reported when hit
  [int]    $Cap      = 8,            # rows shown per zone cluster
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$DbPath = Get-CloneDb $DbPath

$PAL = @{
  d1Border    = '#B02A37'; d1Fill    = '#FDECEE'; d1Hdr    = '#B02A37'   # direct
  d2Border    = '#B45309'; d2Fill    = '#FEF6EC'; d2Hdr    = '#B45309'
  d3Border    = '#3B5BDB'; d3Fill    = '#EDF2FF'; d3Hdr    = '#3B5BDB'
  focusBorder = '#0F766E'; focusFill = '#E2F1EF'; focusHdr = '#0F766E'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}

Write-Host "change-impact: $Target (depth $Depth)"

$sel = Resolve-MemberSelection $Target `
         @('method', 'function', 'procedure', 'constructor', 'destructor', 'class', 'interface', 'record', 'type') `
         -Hint 'change-impact selects a METHOD or a TYPE'

$isType = $sel.Kind -in @('class', 'interface', 'record', 'type')

# ---- seeds --------------------------------------------------------------------
$seeds = @($sel.Id)
$memberCount = 0
if ($isType) {
  $mem = Invoke-IndexQuery "SELECT id FROM symbols WHERE parent_id = $($sel.Id)"
  $memberCount = $mem.Count
  foreach ($m in $mem) { $seeds += [int]$m.id }
  Write-Host "  type selection: seeded with $memberCount member(s) as well as the type itself"
}

# ---- BFS over CALLERS ------------------------------------------------------------
$dist = @{}
foreach ($s in $seeds) { $dist[[int]$s] = 0 }
$frontier = @($seeds | ForEach-Object { [int]$_ })
$capped = $false

for ($d = 1; $d -le $Depth; $d++) {
  if ($frontier.Count -eq 0) { break }
  $next = New-Object System.Collections.ArrayList
  # chunked: an IN-list of 400 ids is fine, but the 200-row RESULT cap is not,
  # so each chunk is read in pages.
  for ($i = 0; $i -lt $frontier.Count; $i += 60) {
    $chunk = @($frontier[$i..([Math]::Min($i + 59, $frontier.Count - 1))])
    $inList = ($chunk -join ',')
    $off = 0
    while ($true) {
      $page = Invoke-IndexQuery @"
SELECT DISTINCT r.enclosing_symbol_id AS caller
  FROM call_edges ce JOIN refs r ON r.id = ce.ref_id
 WHERE ce.target_symbol_id IN ($inList) AND r.enclosing_symbol_id IS NOT NULL
 ORDER BY r.enclosing_symbol_id LIMIT 180 OFFSET $off
"@
      if ($page.Count -eq 0) { break }
      foreach ($p in $page) {
        $cid = [int]$p.caller
        if (-not $dist.ContainsKey($cid)) { $dist[$cid] = $d; [void]$next.Add($cid) }
      }
      if ($page.Count -lt 180) { break }
      $off += 180
    }
  }
  # a TYPE is also affected through plain type references, not only calls
  if ($isType -and $d -eq 1) {
    $off = 0
    while ($true) {
      $page = Invoke-IndexQuery @"
SELECT DISTINCT r.enclosing_symbol_id AS caller
  FROM refs r
 WHERE r.symbol_id = $($sel.Id) AND r.kind = 'type_use' AND r.enclosing_symbol_id IS NOT NULL
 ORDER BY r.enclosing_symbol_id LIMIT 180 OFFSET $off
"@
      if ($page.Count -eq 0) { break }
      foreach ($p in $page) {
        $cid = [int]$p.caller
        if (-not $dist.ContainsKey($cid)) { $dist[$cid] = $d; [void]$next.Add($cid) }
      }
      if ($page.Count -lt 180) { break }
      $off += 180
    }
  }
  if ($dist.Count -gt $MaxNodes) { $capped = $true; break }
  $frontier = @($next.ToArray())
}

$affected = @($dist.Keys | Where-Object { $dist[$_] -gt 0 })
if ($affected.Count -eq 0) {
  throw ("nothing in this index depends on $($sel.Qname) -- 0 callers at any depth. " +
         'That is a real answer for a leaf, an entry point, or something reached only by ' +
         'interface dispatch, whose call edges are incomplete on this build.')
}

# ---- resolve the affected symbols ------------------------------------------------
$info = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $affected.Count; $i += 60) {
  $chunk = @($affected[$i..([Math]::Min($i + 59, $affected.Count - 1))])
  $rows = Invoke-IndexQuery @"
SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS line,
       s.start_line AS dline, f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.id IN ($($chunk -join ','))
"@
  foreach ($r in $rows) { [void]$info.Add($r) }
}

# zone map, PAGED (the unpaged DISTINCT path query silently returns 200)
$dirs = New-Object System.Collections.ArrayList
$off = 0
while ($true) {
  $page = Invoke-IndexQuery "SELECT DISTINCT path AS p FROM files ORDER BY path LIMIT 180 OFFSET $off"
  if ($page.Count -eq 0) { break }
  foreach ($p in $page) { [void]$dirs.Add([IO.Path]::GetDirectoryName([string]$p.p)) }
  if ($page.Count -lt 180) { break }
  $off += 180
}
$rootLen = Get-CommonRootLen @($dirs.ToArray())

$items = @($info | ForEach-Object {
  [pscustomobject]@{
    Id = [int]$_.id; Q = [string]$_.q
    Line = $(if ($_.line) { [int]$_.line } else { [int]$_.dline })
    Path = [string]$_.path
    Unit = Get-UnitName ([string]$_.path)
    Zone = Get-PathZone ([string]$_.path) $rootLen
    D = $dist[[int]$_.id]
  } })

$units = @($items | ForEach-Object { $_.Unit } | Sort-Object -Unique)
$zones = @($items | ForEach-Object { $_.Zone } | Sort-Object -Unique)
Write-Host ("  affected: {0} routine(s) over {1} unit(s) in {2} zone(s){3}" -f `
            $items.Count, $units.Count, $zones.Count, $(if ($capped) { "  [CAPPED at $MaxNodes]" } else { '' }))

# ---- dot -----------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph changeimpact {')
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
Add-DisclosureRow $ftbl "BLAST RADIUS: $($items.Count) routine(s), $($units.Count) unit(s), $($zones.Count) zone(s)" $PAL.lineInk
Add-DisclosureRow $ftbl "walked $Depth level(s) of CALLERS$(if ($isType) { " from the type and its $memberCount member(s)" })" $PAL.lineInk
if ($capped) { Add-DisclosureRow $ftbl "frontier CAPPED at $MaxNodes -- the real radius is larger" $PAL.lineInk }
Add-DisclosureRow $ftbl 'impact fans out over CALLERS: edges INTO a symbol are owned by the calling file' $PAL.lineInk
Add-DisclosureRow $ftbl 'an unresolved caller is invisible here -- a small radius is a floor, not a ceiling' $PAL.lineInk
$edgeless = Get-EdgelessFiles
$edgelessNote = Get-EdgelessDisclosure $edgeless
if ($edgelessNote) { Add-DisclosureRow $ftbl $edgelessNote $PAL.lineInk }
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

# NOT `Sort-Object { @($items | Where-Object { $_.Zone -eq $_ }).Count }` -- the
# inner $_ is the ITEM being filtered, not the zone being sorted, so the
# comparison is $_.Zone against itself and every key comes back the same. Bind
# the zone to its own name first.
$zoneSize = @{}
foreach ($zn in $zones) { $zoneSize[$zn] = @($items | Where-Object { $_.Zone -eq $zn }).Count }
foreach ($z in ($zones | Sort-Object { $zoneSize[$_] } -Descending)) {
  $zi = @($items | Where-Object { $_.Zone -eq $z } | Sort-Object D, Q)
  if ($zi.Count -eq 0) { continue }
  $top = Get-TopRanked $zi $Cap 'D'
  $cells = New-Object System.Collections.ArrayList
  foreach ($it in $top.Shown) {
    $anchored++
    [void]$cells.Add([pscustomobject]@{
      Label = Get-ShortName $it.Q $it.Unit
      Line  = $it.Line
      Href  = New-RowHref $it.Path $it.Line
      Tip   = "$($it.Q) -- $($it.Unit):$($it.Line), $($it.D) hop(s) from the change"
      Note  = "hop $($it.D)"
    })
  }
  $d = Get-DisclosureText $top.HiddenRows 0 'routines'
  if ($d) { [void]$cells.Add((New-NoteRow $d)) }
  $zu = @($zi | ForEach-Object { $_.Unit } | Sort-Object -Unique).Count
  [void]$cells.Add((New-NoteRow "$zu unit(s) in this zone"))

  $minD = ($zi | Measure-Object -Property D -Minimum).Minimum
  $b = switch ($minD) { 1 { $PAL.d1Border } 2 { $PAL.d2Border } default { $PAL.d3Border } }
  $fi = switch ($minD) { 1 { $PAL.d1Fill }  2 { $PAL.d2Fill }  default { $PAL.d3Fill } }
  $h = switch ($minD) { 1 { $PAL.d1Hdr }   2 { $PAL.d2Hdr }   default { $PAL.d3Hdr } }

  $nodeId++; $clusters++
  $nid = "n$nodeId"
  [void](Add-RowCluster -Sb $sb -Cid "cluster_z_$nodeId" -Nid $nid `
           -Title $z -Subtitle "$($zi.Count) routine$(if ($zi.Count -ne 1) { 's' })" -Rows $cells.ToArray() `
           -Border $b -Fill $fi -Hdr $h -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans)
  [void]$sb.AppendLine("  ${fnid}:p1 -> $nid [color=`"$b`"];")
}
[void]$sb.AppendLine('}')

if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$lay = Invoke-DotLayout $sb.ToString() $OutDir ('impact_' + ($sel.Qname -replace '[^A-Za-z0-9]', '_'))

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Qname        = $sel.Qname
  IsType       = $isType
  Affected     = $items.Count
  Units        = $units.Count
  Zones        = $zones.Count
  MaxHop       = ($items | Measure-Object -Property D -Maximum).Maximum
  Capped       = $capped
  Clusters     = $clusters
  ClickTargets = $lay.Anchors
  Expected     = $anchored
  AllClickable = ($lay.Anchors -ge $anchored)
}
