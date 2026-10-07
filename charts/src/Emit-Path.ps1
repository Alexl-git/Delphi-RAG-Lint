<#
  Emit-Path.ps1 -- the `path` diagram question: every SHORTEST call path from routine A
  (-From) to routine B (-To), each call labelled with its call site and grade.

  WHERE THE ANSWER COMES FROM -- two existing facts, no new walk of the engine's own:
    1. `drag-lint call-path --from A --to B --max-depth N --json` decides the question:
       found (and how many calls the shortest route takes) or not found (exit 1). Its BFS
       runs over the resolved call_edges (GetCallEdgesFromSymbol: refs.enclosing_symbol_id
       -> call_edges.target_symbol_id) and returns ONE shortest path, without call sites.
    2. The SAME call_edges, read with one recursive SQL query, give EVERY shortest path:
       distance from A forward and to B backward, bounded by call-path's length L; a call
       u -> v is on a shortest path exactly when dist(A,u) + 1 + dist(v,B) = L. The same rows
       carry each call's SITE (refs file + line) and its GRADE (call_edges.confidence).
       call-path's own path must be one of them, or nothing is drawn (the two disagree --
       an engine defect to report, never a chart to trust).

  GRADES are the index's own words. `certain`: the call is bound to this routine.
  `ambiguous`: bound to this routine, but more than one candidate survived on the type
  chain. A call the index matched by NAME alone has no call_edges row, so call-path never
  walks it and it is never on a path -- the Legend says so, rather than drawing a "by name"
  grade that cannot occur here.

  THE CAP: -Cap paths are drawn (default 20, ordered by the routines' names hop by hop);
  every path left out is counted and DISCLOSED in the Legend ("+N more shortest paths not
  shown"), never dropped silently. The count is exact (dynamic programming over the
  shortest-path graph), not the size of an enumeration that stopped early.

  `neighbours` (everything within N hops of one routine, both directions) is NOT a
  separate question: that is `butterfly -Depth N` exactly (Emit-Butterfly.ps1).

  Refusals (no .svg): A = B; a routine not in this index; no path within -MaxDepth calls.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $From,
  [Parameter(Mandatory)][string] $To,
  [Parameter(Mandatory)][string] $DbPath,   # NOT -Db: CmdletBinding aliases that to -Debug
  [string] $OutDir,
  [int]    $Cap        = 20,
  [int]    $MaxDepth   = 20,                # call-path's own default
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
  endBorder = '#0F766E'; endFill = '#E2F1EF'; endHdr = '#0F766E'; endInk = '#0B3F39'
  midBorder = '#B45309'; midFill = '#FEF6EC'; midHdr = '#B45309'
  rowInk    = '#1F2933'; lineInk = '#8A94A6'; ambInk = '#9A5408'
}

# ---- 0. the selection ---------------------------------------------------------------
if ([string]::Equals($From, $To, [StringComparison]::OrdinalIgnoreCase)) {
  throw "path: name two different routines -- -From and -To are both $From"
}
foreach ($q in $From, $To) {
  $cand = Invoke-IndexQuery "SELECT s.kind AS kind, s.start_line AS line, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.qualified_name = '$(ConvertTo-SqlText $q)' ORDER BY f.path, s.start_line LIMIT 12"
  if ($cand.Count -eq 0) { throw "$q is not in this index (give the qualified name, Unit.Class.Method)" }
  # fix round 1, item 3: an OVERLOADED name is several symbols, and call-path would start (or stop) at ALL of
  # them -- the chart would draw their union while the Legend credits one routine. The index has no finer
  # name for an overload (they share the qualified name), so the honest answer is a refusal that lists them.
  if ($cand.Count -gt 1) {
    $list = ($cand | ForEach-Object { "$($_.kind) @$([IO.Path]::GetFileName([string]$_.path)):$($_.line)" }) -join ', '
    throw ("$q names $($cand.Count)$(if ($cand.Count -ge 12) { '+' }) symbols (an overload or a duplicate declaration): $list. " +
           'path needs each end to be exactly ONE routine, and overloads share their qualified name, so no spelling picks one -- ' +
           "ask butterfly or who-calls on $q instead, or start / end the path at a routine next to it.")
  }
}

# ---- 1. the engine decides: found, and how long --------------------------------------
Write-Host "path: $From -> $To (max depth $MaxDepth)"
$cpText = Get-EngineText @('call-path', '--from', $From, '--to', $To, '--max-depth', "$MaxDepth", '--json', '--db', $DbPath) -AllowNoMatch
$cp = $(if ($cpText) { $cpText | ConvertFrom-Json } else { $null })
if ($script:LastEngineNoMatch -or -not $cp -or -not $cp.found) {
  throw ("no call path from $From to $To within $MaxDepth calls (engine call-path, found:false). " +
         'call-path walks the resolved call_edges only, so a call the index matched by name alone is not followed.')
}
$enginePath = @($cp.path | ForEach-Object { [string]$_ })
$L = $enginePath.Count - 1
if ($L -lt 1) { throw "call-path returned a path of $($enginePath.Count) routine(s) for two different routines -- engine defect" }

# ---- 2. every shortest path, over the same call_edges ---------------------------------
$fq = ConvertTo-SqlText $From; $tq = ConvertTo-SqlText $To
$edgeSql = @"
WITH RECURSIVE
 e(src, dst) AS (SELECT DISTINCT r.enclosing_symbol_id, ce.target_symbol_id FROM call_edges ce JOIN refs r ON r.id = ce.ref_id WHERE r.enclosing_symbol_id IS NOT NULL),
 fw(id, d) AS (SELECT id, 0 FROM symbols WHERE qualified_name = '$fq' UNION SELECT e.dst, fw.d + 1 FROM fw JOIN e ON e.src = fw.id WHERE fw.d < $L),
 bw(id, d) AS (SELECT id, 0 FROM symbols WHERE qualified_name = '$tq' UNION SELECT e.src, bw.d + 1 FROM bw JOIN e ON e.dst = bw.id WHERE bw.d < $L),
 da(id, d) AS (SELECT id, MIN(d) FROM fw GROUP BY id),
 db(id, d) AS (SELECT id, MIN(d) FROM bw GROUP BY id)
SELECT da.d AS hop, s.id AS src_id, s.qualified_name AS src, t.id AS dst_id, t.qualified_name AS dst,
       f.path AS path, r.start_line AS line, ce.confidence AS grade, r.id AS ref_id
  FROM call_edges ce JOIN refs r ON r.id = ce.ref_id
  JOIN da ON da.id = r.enclosing_symbol_id JOIN db ON db.id = ce.target_symbol_id
  JOIN symbols s ON s.id = r.enclosing_symbol_id JOIN symbols t ON t.id = ce.target_symbol_id
  JOIN files f ON f.id = r.file_id
 WHERE da.d + 1 + db.d = $L
"@
$siteRows = Get-AllIndexRows $edgeSql 'hop, src, dst, src_id, dst_id, line, ref_id'
if ($siteRows.Count -eq 0) { throw "call-path found a $L-call path but call_edges hold no call on any shortest path -- the two disagree (engine defect; nothing drawn)" }
# fix round 1, item 4: membership is not enough -- SQL's OWN shortest distance A -> B must be call-path's L.
# A shorter one means call-path missed a route; none within L means the two read different edges.
$distSql = $edgeSql.Substring(0, $edgeSql.IndexOf('SELECT da.d AS hop')) +
           "SELECT MIN(fw.d) AS dmin FROM fw WHERE fw.id IN (SELECT id FROM symbols WHERE qualified_name = '$tq')"
$dmin = (Invoke-IndexQuery $distSql)[0].dmin
if ($null -eq $dmin -or [int]$dmin -ne $L) {
  throw "call-path says the shortest path is $L call(s), but call_edges give $(if ($null -eq $dmin) { "none within $L" } else { [int]$dmin }) -- the two disagree (engine defect; nothing drawn)"
}

# the shortest-path graph: node = symbol id; one pair per distinct (src, dst), its sites in order
$name = @{}; $hopOf = @{}; $pairs = [ordered]@{}; $next = @{}
foreach ($s in $siteRows) {
  $si = [long]$s.src_id; $di = [long]$s.dst_id
  $name[$si] = [string]$s.src; $name[$di] = [string]$s.dst
  $hopOf[$si] = [int]$s.hop; $hopOf[$di] = [int]$s.hop + 1
  $k = "$si>$di"
  if (-not $pairs.Contains($k)) {
    $pairs[$k] = [pscustomobject]@{ Src = $si; Dst = $di; Sites = (New-Object System.Collections.ArrayList) }
    if (-not $next.ContainsKey($si)) { $next[$si] = New-Object System.Collections.ArrayList }
    [void]$next[$si].Add($di)
  }
  [void]$pairs[$k].Sites.Add([pscustomobject]@{ File = [string]$s.path; Line = [int]$s.line; Grade = [string]$s.grade })
}
$starts = @($hopOf.Keys | Where-Object { $hopOf[$_] -eq 0 } | Sort-Object { $name[$_] }, { $_ })
$isEnd  = { param($id) $hopOf[$id] -eq $L }

# call-path's own path must be a route through this graph (by name, hop by hop)
for ($i = 0; $i -lt $L; $i++) {
  $hit = @($pairs.Values | Where-Object { $name[$_.Src] -eq $enginePath[$i] -and $name[$_.Dst] -eq $enginePath[$i + 1] -and $hopOf[$_.Src] -eq $i })
  if ($hit.Count -eq 0) { throw "call-path's path ($($enginePath -join ' -> ')) is not among the shortest paths over call_edges at hop $i -- the two disagree (engine defect; nothing drawn)" }
}

# exact count (paths from each node to B), then the first -Cap paths in name order
$ways = @{}
function Get-Ways([long] $id) {
  if ($ways.ContainsKey($id)) { return $ways[$id] }
  $w = [long]0
  if (& $isEnd $id) { $w = 1 } elseif ($next.ContainsKey($id)) { foreach ($d in $next[$id]) { $w += Get-Ways $d } }
  $ways[$id] = $w
  $w
}
$total = [long]0
foreach ($s in $starts) { $total += Get-Ways $s }

$shown = New-Object System.Collections.ArrayList
function Add-Paths([long] $id, [long[]] $prefix) {
  if ($shown.Count -ge $Cap) { return }
  $p = $prefix + $id
  if (& $isEnd $id) { [void]$shown.Add($p); return }
  if (-not $next.ContainsKey($id)) { return }
  foreach ($d in ($next[$id] | Sort-Object { $name[$_] }, { $_ })) { Add-Paths $d $p }
}
foreach ($s in $starts) { Add-Paths $s @() }
$hidden = [int]($total - $shown.Count)
Write-Host ("  shortest paths={0} of {1} call(s); drawn {2}; call sites on them={3}" -f $total, $L, $shown.Count, $siteRows.Count)

# what is drawn: the routines and pairs of the shown paths only
$drawnIds = [ordered]@{}; $drawnPairs = [ordered]@{}
foreach ($p in $shown) {
  for ($i = 0; $i -lt $p.Count; $i++) {
    $drawnIds[[string]$p[$i]] = $true
    if ($i -lt $p.Count - 1) { $drawnPairs["$($p[$i])>$($p[$i + 1])"] = $pairs["$($p[$i])>$($p[$i + 1])"] }
  }
}

# ---- 3. where each drawn routine is (its BODY line) ----------------------------------------
$idList = ($drawnIds.Keys | ForEach-Object { [long]$_ }) -join ','
$locRows = Get-AllIndexRows "SELECT s.id AS id, s.start_line AS start_line, s.impl_start_line AS impl_start_line, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id IN ($idList)" 's.id'
$loc = @{}
foreach ($r in $locRows) { $loc[[long]$r.id] = [pscustomobject]@{ Path = [string]$r.path; Line = $(if ($r.impl_start_line) { [int]$r.impl_start_line } else { [int]$r.start_line }) } }

# ---- 4. dot ---------------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph path {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.45; ranksep=1.3; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.5, arrowsize=0.8];")
[void]$sb.AppendLine('')

$nodeOf = @{}; $nid = 0; $clicks = 0
foreach ($k in $drawnIds.Keys) {
  $id = [long]$k; $nid++; $nodeOf[$id] = "r$nid"
  $q = $name[$id]; $h = $hopOf[$id]
  $at = $loc[$id]
  $unit = Get-UnitName $at.Path
  $isEp = ($h -eq 0 -or $h -eq $L)
  $border = $(if ($isEp) { $PAL.endBorder } else { $PAL.midBorder })
  $fill   = $(if ($isEp) { $PAL.endFill } else { $PAL.midFill })
  $hdr    = $(if ($isEp) { $PAL.endHdr } else { $PAL.midHdr })
  $role   = $(if ($h -eq 0) { 'from' } elseif ($h -eq $L) { 'to' } else { "hop $h" })
  $tbl = "<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLSPACING=`"3`" CELLPADDING=`"6`">" +
         "<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$hdr`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $unit) &#183; $role </B></FONT></TD></TR>" +
         "<TR><TD ALIGN=`"LEFT`" HREF=`"$(New-RowHref $at.Path $at.Line)`" TITLE=`"$(ConvertTo-XmlText "$q  --  $([IO.Path]::GetFileName($at.Path)):$($at.Line)")`">" +
         "<FONT COLOR=`"$(if ($isEp) { $PAL.endInk } else { $PAL.rowInk })`">$(if ($isEp) { '<B>' })$(ConvertTo-XmlText (Get-ShortName $q $unit))$(if ($isEp) { '</B>' })</FONT>" +
         "  <FONT COLOR=`"$($PAL.lineInk)`" POINT-SIZE=`"12`">:$($at.Line)</FONT></TD></TR></TABLE>"
  $clicks++
  # the two ends are the SELECTION: in cluster_focus_* (Ask-Report prints them as TARGET rows)
  $cl = $(if ($h -eq 0) { 'cluster_focus_from' } elseif ($h -eq $L) { 'cluster_focus_to' } else { "cluster_hop_$nid" })
  [void]$sb.AppendLine("  subgraph $cl {")
  [void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$border`"; fillcolor=`"$fill`"; penwidth=$(if ($isEp) { 3 } else { 2 });")
  [void]$sb.AppendLine('    label=""; margin=10;')
  [void]$sb.AppendLine("    r$nid [label=<$tbl>];")
  [void]$sb.AppendLine('  }')
}
# NO rank=same: every call goes hop h -> h+1, so dot already ranks by hop, and a rankset would pull a
# node OUT of its cluster (measured: "r2 was already in a rankset, deleted from cluster").

# ---- the Legend: how many, what the grades mean, what was left out --------------------------
$leg = New-Object System.Text.StringBuilder
[void]$leg.Append("<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLSPACING=`"2`" CELLPADDING=`"4`">")
[void]$leg.Append("<TR><TD ALIGN=`"LEFT`"><FONT FACE=`"$FontSans`" POINT-SIZE=`"13`"><B>Legend</B></FONT></TD></TR>")
Add-DisclosureRow $leg "$total shortest path(s) of $L call(s) each, $($siteRows.Count) call site(s) on them -- found by engine call-path, every route enumerated over the same resolved call_edges"
Add-DisclosureRow $leg 'each arrow: one call, labelled with every call site (file:line) and its grade -- certain = bound to this routine; ambiguous = bound, more than one candidate on the type chain'
Add-DisclosureRow $leg 'a call the index matched by name alone has no call_edges row, so call-path never walks it'
$disc = Get-DisclosureText $hidden 0 $(if ($hidden -eq 1) { 'shortest path' } else { 'shortest paths' })
# no "(-Cap N)" here: Ask-Report appends the cap and how to raise it to every "+N more" row (measured: it doubled)
if ($disc) { Add-DisclosureRow $leg $disc -Ink $PAL.ambInk }
[void]$leg.Append('</TABLE>')
[void]$sb.AppendLine("  legend [label=<$($leg.ToString())>];")

[void]$sb.AppendLine('')
$siteCount = 0; $ambCount = 0
foreach ($pr in $drawnPairs.Values) {
  $et = New-Object System.Text.StringBuilder
  [void]$et.Append("<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLSPACING=`"0`" CELLPADDING=`"2`" BGCOLOR=`"#FFFFFF`">")
  foreach ($s in $pr.Sites) {
    $siteCount++
    $amb = $s.Grade -ne 'certain'
    if ($amb) { $ambCount++ }
    $leaf = [IO.Path]::GetFileName($s.File)
    $tip  = ConvertTo-XmlText "$($name[$pr.Src]) -> $($name[$pr.Dst]) ($($s.Grade))  --  ${leaf}:$($s.Line)"
    [void]$et.Append("<TR><TD HREF=`"$(New-RowHref $s.File $s.Line)`" TITLE=`"$tip`"><FONT COLOR=`"$(if ($amb) { $PAL.ambInk } else { $PAL.rowInk })`">$(ConvertTo-XmlText "${leaf}:$($s.Line)") &#183; $(ConvertTo-XmlText $s.Grade)</FONT></TD></TR>")
    $clicks++
  }
  [void]$et.Append('</TABLE>')
  $style = $(if (@($pr.Sites | Where-Object { $_.Grade -eq 'certain' }).Count -eq 0) { ', style=dashed' } else { '' })
  [void]$sb.AppendLine("  $($nodeOf[$pr.Src]) -> $($nodeOf[$pr.Dst]) [label=<$($et.ToString())>$style];")
}
[void]$sb.AppendLine('}')

# ---- 5. lay out --------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
# the METHOD names only: the bundler's folder already carries Class_Method for both ends, and two
# qualified names here ran a bundle's .dot to 262 characters, past dot's MAX_PATH (measured)
$short = { param($q) @($q -split '\.')[-1] }
$base = ('path_' + (& $short $From) + '__' + (& $short $To)) -replace '[^A-Za-z0-9_]', '_'
$lay = Invoke-DotLayout $sb.ToString() $OutDir $base
function Get-FileSize([string] $f) { if (Test-Path $f) { (Get-Item $f).Length } else { 0 } }

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Paths        = $total
  PathsShown   = $shown.Count
  Hops         = $L
  Routines     = $drawnIds.Count
  Edges        = $drawnPairs.Count
  Sites        = $siteCount
  Ambiguous    = $ambCount
  EnginePath   = ($enginePath -join ' -> ')
  ClickTargets = $lay.Anchors
  Expected     = $clicks
  AllClickable = ($lay.Anchors -ge $clicks)
  ExportSvg    = Get-FileSize $lay.Svg
  ExportPng    = Get-FileSize $lay.Png
  ExportPdf    = Get-FileSize $lay.Pdf
}
