<#
  Emit-Deps.ps1 -- the SECOND question through the pipeline: unit dependencies.

  Deliberately a different SHAPE from butterfly, so the pipeline is proven on
  more than one kind of graph:

    butterfly  one symbol, rows are METHODS, clusters are units
    deps       one unit,   rows are UNITS,   clusters are DIRECTORIES

  Edges come from `unit_uses` in the index, NOT from `graph --format dot`. The
  graph verb emits dot, and dot is Graphviz's INPUT -- consuming it would mean
  writing a dot parser, which this project deliberately does not have. The table
  also carries two things the dot output drops:

    * section -- interface vs implementation. This is the distinction deps adds
      over butterfly, and it is what `uses-audit` exists to act on. Rendered
      solid vs dashed.
    * start_line -- the line of the USES CLAUSE ENTRY. So a dependency row is
      clickable to the exact place you would edit to remove it, which is better
      provenance than pointing at the used unit's own declaration.

  target_file_id is NULL for anything outside the project closure (RTL, VCL,
  third-party). Those are grouped separately and honestly labelled rather than
  silently dropped.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Unit,
  [Parameter(Mandatory)][string] $DbPath,
  [string] $OutDir,
  [switch] $IncludeExternal,
  [int]    $MaxRows   = 40,
  [string] $Engine    = '',
  [string] $Dot       = '',
  [string] $FontMono  = 'Consolas',
  [string] $FontSans  = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'

# This emitter predates Emit-Common.ps1 and keeps its own copies of the small
# helpers below. Dot-sourcing HERE -- before those local definitions -- means the
# local ones still win, so nothing about this emitter's behaviour changes; the
# only thing taken from Common is Get-CloneDb.
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')
$Engine = Resolve-DragLintEngine $Engine   # R2: '' = DRAGLINT_ENGINE, settings.json, installed, shared (Emit-Common)
# Refuse a live corpus DB (see Get-CloneDb): charts run against the frozen clones.
$DbPath = Get-CloneDb $DbPath

$PAL = @{
  userBorder = '#3B5BDB'; userFill = '#EDF2FF'; userHdr = '#3B5BDB'
  rootBorder = '#0F766E'; rootFill = '#E2F1EF'; rootHdr = '#0F766E'
  usesBorder = '#B45309'; usesFill = '#FEF6EC'; usesHdr = '#B45309'
  extBorder  = '#6B7280'; extFill  = '#F3F4F6'; extHdr  = '#6B7280'
  rowInk     = '#1F2933'; lineInk  = '#8A94A6'; rootInk = '#0B3F39'
}

function ConvertTo-XmlText([string] $s) {
  if ($null -eq $s) { return '' }
  $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}
function Get-DirLeaf([string] $path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return '(external)' }
  $d = Split-Path $path -Parent
  if ([string]::IsNullOrWhiteSpace($d)) { return '(root)' }
  Split-Path $d -Leaf
}

# Invoke-IndexQuery is the SHARED one from Emit-Common. This emitter used to
# carry a private copy that returned @() on an empty stdout, so a failed query
# (locked DB, time cap, bad SQL) drew an empty chart; the shared one throws (R19).

Write-Host "deps: $Unit"

# $MaxRows is a DISPLAY cap, not a population limit (R24): each side is also
# COUNTED with the same predicate, and the remainder is disclosed on the chart.
# The external filter is in the SQL, BEFORE the limit -- filtered after it, uMain
# (91 entries, 46 project units) drew 39 and claimed that was all.
$extFilter = $(if ($IncludeExternal) { '' } else { "AND t.path IS NOT NULL AND t.path <> ''" })

# what THIS unit uses -- provenance is the uses-clause line in THIS unit
$outFrom = @"
  FROM unit_uses u
  JOIN files f ON f.id = u.file_id
  LEFT JOIN files t ON t.id = u.target_file_id
 WHERE f.path LIKE '%\$Unit.pas' $extFilter
"@
$outSql = @"
SELECT u.unit_name AS name, u.section AS section, u.start_line AS line,
       f.path AS src, t.path AS target
$outFrom
 ORDER BY u.section, u.unit_name
 LIMIT $MaxRows
"@

# Who uses THIS unit -- provenance is the uses-clause line in the OTHER unit.
#
# Joined on the RESOLVED target_file_id, not on unit_name_norm. Measured
# 2026-09-23: unit_name_norm is the LAST DOTTED SEGMENT, lowercased --
# 'Blueprint4.ViewModel' and 'Blueprint4.CADImport.ViewModel' BOTH normalise to
# 'viewmodel'. Matching on it either misses everything (when you pass the full
# dotted name, which never appears in that column) or over-matches across
# namespaces. The resolved file id is unambiguous.
$inFrom = @"
  FROM unit_uses u
  JOIN files f ON f.id = u.file_id
  JOIN files t ON t.id = u.target_file_id
 WHERE t.path LIKE '%\$Unit.pas'
"@
$inSql = @"
SELECT f.path AS src, u.section AS section, u.start_line AS line
$inFrom
 ORDER BY f.path
 LIMIT $MaxRows
"@

$uses  = Invoke-IndexQuery $outSql
$users = Invoke-IndexQuery $inSql
$usesTotal  = [int]((Invoke-IndexQuery "SELECT COUNT(*) AS n $outFrom")[0].n)
$usersTotal = [int]((Invoke-IndexQuery "SELECT COUNT(*) AS n $inFrom")[0].n)
$usesHidden  = $usesTotal - $uses.Count
$usersHidden = $usersTotal - $users.Count
Write-Host ("  uses={0} of {1}  used-by={2} of {3}" -f $uses.Count, $usesTotal, $users.Count, $usersTotal)

# ---- dot ---------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
$nodeId = 0
$ports  = @{}

function Add-Cluster {
  param([string] $Side, [string] $Title, $Rows, [string] $Border, [string] $Fill, [string] $Hdr)
  $script:nodeId++
  $nid = "n$script:nodeId"
  [void]$sb.AppendLine("  subgraph cluster_${Side}_$script:nodeId {")
  [void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$Border`"; fillcolor=`"$Fill`"; penwidth=2;")
  [void]$sb.AppendLine('    label=""; margin=10;')
  $tbl = New-Object Text.StringBuilder
  [void]$tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
  [void]$tbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$Hdr`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $Title) </B></FONT></TD></TR>")
  $p = 0
  foreach ($r in $Rows) {
    $p++
    $label = ConvertTo-XmlText $r.Label
    $href  = 'draglint://open?file=' + [uri]::EscapeDataString($r.File) + '&amp;line=' + $r.Line
    $tip   = ConvertTo-XmlText ("$($r.Label)  --  uses clause at $([IO.Path]::GetFileName($r.File)):$($r.Line)  [$($r.Section)]")
    [void]$tbl.Append("<TR><TD PORT=`"p$p`" ALIGN=`"LEFT`" HREF=`"$href`" TITLE=`"$tip`">")
    [void]$tbl.Append("<FONT COLOR=`"$($PAL.rowInk)`">$label</FONT>")
    [void]$tbl.Append("  <FONT COLOR=`"$($PAL.lineInk)`" POINT-SIZE=`"12`">:$($r.Line)</FONT>")
    [void]$tbl.Append('</TD></TR>')
    $ports["$Side|$($r.Key)"] = @{ Port = "${nid}:p$p"; Section = $r.Section }
  }
  [void]$tbl.Append('</TABLE>')
  [void]$sb.AppendLine("    $nid [label=<$($tbl.ToString())>];")
  [void]$sb.AppendLine('  }')
}

[void]$sb.AppendLine('digraph deps {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.2; splines=spline;')
[void]$sb.AppendLine("  node [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge [fontname=`"$FontMono`", fontsize=11, penwidth=1.5, arrowsize=0.8];")
[void]$sb.AppendLine('')

$userRows = @($users | ForEach-Object {
  [pscustomobject]@{
    Label = [IO.Path]::GetFileNameWithoutExtension($_.src)
    File  = $_.src; Line = $_.line; Section = $_.section
    Key   = "$($_.src)|$($_.line)"; Dir = (Get-DirLeaf $_.src)
  } })
foreach ($g in ($userRows | Group-Object Dir | Sort-Object Name)) {
  Add-Cluster 'in' "$($g.Name)  (uses this)" $g.Group $PAL.userBorder $PAL.userFill $PAL.userHdr
}

[void]$sb.AppendLine('  subgraph cluster_root {')
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.rootBorder)`"; fillcolor=`"$($PAL.rootFill)`"; penwidth=3;")
[void]$sb.AppendLine('    label=""; margin=12;')
$rootTbl = New-Object System.Text.StringBuilder
[void]$rootTbl.Append("<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLSPACING=`"3`" CELLPADDING=`"7`"><TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.rootHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> unit &#183; focus </B></FONT></TD></TR><TR><TD><FONT COLOR=`"$($PAL.rootInk)`" POINT-SIZE=`"18`"><B>$(ConvertTo-XmlText $Unit)</B></FONT></TD></TR>")
# R24: the display cap admits itself -- a capped side never reads as the whole
if ($usersHidden -gt 0) { Add-DisclosureRow $rootTbl "+$usersHidden more units that use this not shown -- $($users.Count) of $usersTotal drawn (display cap $MaxRows)" $PAL.lineInk }
if ($usesHidden -gt 0)  { Add-DisclosureRow $rootTbl "+$usesHidden more units this uses not shown -- $($uses.Count) of $usesTotal drawn (display cap $MaxRows)" $PAL.lineInk }
[void]$rootTbl.Append('</TABLE>')
[void]$sb.AppendLine("    root [label=<$($rootTbl.ToString())>];")
[void]$sb.AppendLine('  }')

$useRows = @($uses | ForEach-Object {
  $ext = (-not $_.target) -or ($_.target -eq '')
  [pscustomobject]@{
    Label = $_.name; File = $_.src; Line = $_.line; Section = $_.section
    Key = "$($_.name)|$($_.line)"; Dir = $(if ($ext) { '(outside the project closure)' } else { Get-DirLeaf $_.target })
  } })
foreach ($g in ($useRows | Group-Object Dir | Sort-Object Name)) {
  $isExt = $g.Name -like '(outside*'
  Add-Cluster 'out' "$($g.Name)  (used by this)" $g.Group `
    $(if ($isExt) { $PAL.extBorder } else { $PAL.usesBorder }) `
    $(if ($isExt) { $PAL.extFill }   else { $PAL.usesFill })  `
    $(if ($isExt) { $PAL.extHdr }    else { $PAL.usesHdr })
}

[void]$sb.AppendLine('')
# interface uses are solid; implementation uses are DASHED -- the distinction
# uses-audit acts on, and the same dashed channel [inferred] edges will use.
foreach ($r in $userRows) {
  $e = $ports["in|$($r.Key)"]; if (-not $e) { continue }
  $st = if ($r.Section -eq 'implementation') { ', style=dashed' } else { '' }
  [void]$sb.AppendLine("  $($e.Port) -> root [color=`"$($PAL.userBorder)`"$st];")
}
foreach ($r in $useRows) {
  $e = $ports["out|$($r.Key)"]; if (-not $e) { continue }
  $st = if ($r.Section -eq 'implementation') { ', style=dashed' } else { '' }
  $col = if ($r.Dir -like '(outside*') { $PAL.extBorder } else { $PAL.usesBorder }
  [void]$sb.AppendLine("  root -> $($e.Port) [color=`"$col`"$st];")
}
[void]$sb.AppendLine('}')

# ---- write + lay out ---------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$base = ($Unit -replace '[^A-Za-z0-9]', '_')
$dotO = Join-Path $OutDir "$base.dot"; $svgO = Join-Path $OutDir "$base.svg"
$plnO = Join-Path $OutDir "$base.plain"; $pngO = Join-Path $OutDir "$base.png"
$pdfO = Join-Path $OutDir "$base.pdf"

[IO.File]::WriteAllText($dotO, ($sb.ToString() -replace "`r`n", "`n" -replace "`n", "`r`n"),
                        (New-Object Text.UTF8Encoding($false)))
Invoke-DotRun $dotO $svgO $plnO $pngO $pdfO   # Emit-Common: path-length check, stale-output clear, loud failure


$svg = [IO.File]::ReadAllText($svgO)
$anchors = ([regex]::Matches($svg, '<a[\s>]')).Count
$rows = $userRows.Count + $useRows.Count

[pscustomobject]@{
  Dot = $dotO; Svg = $svgO; Plain = $plnO
  # paths, so the bundler moves outputs BY PROPERTY rather than guessing names
  Png = $pngO; Pdf = $pdfO
  UsedBy = $userRows.Count; Uses = $useRows.Count
  # R24: the populations behind the display cap, and how many were not drawn
  UsedByTotal = $usersTotal; UsesTotal = $usesTotal
  UsedByHidden = $usersHidden; UsesHidden = $usesHidden
  ImplementationUses = @($useRows | Where-Object { $_.Section -eq 'implementation' }).Count
  ClickTargets = $anchors; Expected = $rows
  AllClickable = ($anchors -ge $rows)
}
