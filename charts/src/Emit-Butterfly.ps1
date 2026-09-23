<#
  Emit-Butterfly.ps1 -- prototype emitter for the `butterfly` diagram question.

  Pipeline proved end to end:
    drag-lint butterfly --format json
      -> group symbols by UNIT
      -> dot, one ROUNDED CLUSTER per unit, symbols as clickable TABLE ROWS
      -> dot.exe -Tsvg -o .. -Tplain -o ..   (ONE run, verified 2026-09-22)
      -> SVG whose rows are real <a xlink:href> anchors (verified 2026-09-22)

  Rows carry PORTs so edges attach to the ROW, not to the whole unit box --
  that is what keeps per-symbol precision while collapsing N nodes into one
  rectangle per unit.

  Provenance granularity is the ROW. Never the enclosing unit.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Qname,
  [Parameter(Mandatory)][string] $DbPath,   # NOT -Db: CmdletBinding aliases that to -Debug
  [string] $OutDir,
  [int]    $Depth      = 2,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'

# ---- palette. Role-coded, because the butterfly's meaning IS the role. -------
$PAL = @{
  callerBorder = '#3B5BDB'; callerFill = '#EDF2FF'; callerHdr = '#3B5BDB'
  focusBorder  = '#0F766E'; focusFill  = '#E2F1EF'; focusHdr  = '#0F766E'
  calleeBorder = '#B45309'; calleeFill = '#FEF6EC'; calleeHdr = '#B45309'
  rowInk       = '#1F2933'; lineInk    = '#8A94A6'; focusInk  = '#0B3F39'
}

function ConvertTo-XmlText([string] $s) {
  if ($null -eq $s) { return '' }
  $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Get-UnitName([string] $file) {
  if ([string]::IsNullOrWhiteSpace($file)) { return '(unknown)' }
  [IO.Path]::GetFileNameWithoutExtension($file)
}

function Get-ShortName([string] $qname, [string] $unit) {
  if ($qname.StartsWith("$unit.", [StringComparison]::OrdinalIgnoreCase)) {
    return $qname.Substring($unit.Length + 1)
  }
  $qname
}

# ---- flatten the tree the engine returns ------------------------------------
function Flatten($node, [string] $childKey, [System.Collections.ArrayList] $acc, [int] $lvl) {
  if ($null -eq $node) { return }
  $kids = $node.$childKey
  if ($null -eq $kids) { return }
  foreach ($k in $kids) {
    [void]$acc.Add([pscustomobject]@{
      Qname = [string]$k.qname
      File  = [string]$k.file
      Line  = [int]$k.line
      Level = $lvl
    })
    Flatten $k $childKey $acc ($lvl + 1)
  }
}

# ---- 1. ask the engine -------------------------------------------------------
Write-Host "butterfly: $Qname (depth $Depth)"
$raw = & $Engine butterfly --qname $Qname --depth $Depth --format json --db $DbPath 2>&1 |
       Where-Object { $_ -notmatch 'loaded defaults' -and $_ -notmatch '^drag-lint: ' -and $_ -notmatch '^\s+may be stale' -and $_ -notmatch '^\s+drag-lint index ' }
$json = ($raw -join "`n")
if ([string]::IsNullOrWhiteSpace($json)) { throw "engine returned nothing for $Qname" }
$bf = $json | ConvertFrom-Json

$callers = New-Object System.Collections.ArrayList
$callees = New-Object System.Collections.ArrayList
# NOTE: schema reverse-calltree/1 nests children under "callers" on BOTH sides --
# the callees tree reuses the field name. Passing 'callees' silently yields 0.
Flatten $bf.callers.root 'callers' $callers 1
Flatten $bf.callees.root 'callers' $callees 1

Write-Host ("  callers={0}  callees={1}" -f $callers.Count, $callees.Count)

# NO DISCLOSURE HERE, and that absence is deliberate.
# On 2026-09-23 I added a warning claiming reverse-calltree silently drops
# callers of unit-level routines. It was WRONG and is removed. What actually
# happened: `--format json` splices a human staleness note INTO the JSON, my
# parser returned -1, and I reported those -1s as zeros. Re-measured with the
# note stripped: Pipes.Protocol.WriteString = 13 callers, MStreams.ReverseBytes
# = 9. Both resolve correctly. The one real zero, BASICSF.ProcessMessages, is
# also CORRECT -- its 63 "name-matched callers" are every `Application.ProcessMessages;`
# in the codebase, i.e. Vcl.Forms.TApplication.ProcessMessages, a different
# symbol that shares a name. Nobody calls BASICSF.ProcessMessages.
# A caveat printed on every unit-level target for a defect that is not there
# would be its own kind of wrong answer.
$focusFile = [string]$bf.callers.root.file
if ([string]::IsNullOrWhiteSpace($focusFile)) { $focusFile = [string]$bf.callees.root.file }
$focusUnit = Get-UnitName $focusFile

# ---- 2. build the dot --------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
$nodeId = 0
$portMap = @{}   # qname -> "nodeN:pM"

function Add-UnitCluster {
  param([string] $Side, [string] $Unit, $Rows, [string] $Border, [string] $Fill, [string] $Hdr)

  $script:nodeId++
  $nid = "n$script:nodeId"
  $cid = "cluster_${Side}_$($script:nodeId)"

  # The cluster supplies ROUNDED CORNERS and the fill; it carries NO label --
  # Graphviz draws a cluster label inside the border and the rounded border cuts
  # through it. The unit name is a HEADER ROW of the table instead, which is both
  # the intended design and free of that artefact.
  [void]$sb.AppendLine("  subgraph $cid {")
  [void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$Border`"; fillcolor=`"$Fill`"; penwidth=2;")
  [void]$sb.AppendLine('    label=""; margin=10;')

  $tbl = New-Object System.Text.StringBuilder
  [void]$tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
  [void]$tbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$Hdr`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $Unit) </B></FONT></TD></TR>")
  $p = 0
  foreach ($r in $Rows) {
    $p++
    $short = ConvertTo-XmlText (Get-ShortName $r.Qname $Unit)
    $href  = 'draglint://open?file=' + [uri]::EscapeDataString($r.File) + '&amp;line=' + $r.Line
    $tip   = ConvertTo-XmlText ("$($r.Qname)  --  $([IO.Path]::GetFileName($r.File)):$($r.Line)")
    [void]$tbl.Append("<TR><TD PORT=`"p$p`" ALIGN=`"LEFT`" HREF=`"$href`" TITLE=`"$tip`">")
    [void]$tbl.Append("<FONT COLOR=`"$($PAL.rowInk)`">$short</FONT>")
    [void]$tbl.Append("  <FONT COLOR=`"$($PAL.lineInk)`" POINT-SIZE=`"12`">:$($r.Line)</FONT>")
    [void]$tbl.Append('</TD></TR>')
    $portMap[$r.Qname] = "${nid}:p$p"
  }
  [void]$tbl.Append('</TABLE>')

  [void]$sb.AppendLine("    $nid [label=<$($tbl.ToString())>];")
  [void]$sb.AppendLine('  }')
}

[void]$sb.AppendLine('digraph butterfly {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.1; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.5, arrowsize=0.8];")
[void]$sb.AppendLine('')

foreach ($g in ($callers | Group-Object { Get-UnitName $_.File } | Sort-Object Name)) {
  Add-UnitCluster 'in' $g.Name $g.Group $PAL.callerBorder $PAL.callerFill $PAL.callerHdr
}

$focusShort = ConvertTo-XmlText (Get-ShortName ([string]$bf.qname) $focusUnit)
[void]$sb.AppendLine('  subgraph cluster_focus {')
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=3;")
[void]$sb.AppendLine('    label=""; margin=12;')
$fhref = 'draglint://open?file=' + [uri]::EscapeDataString($focusFile) + '&amp;line=' + [int]$bf.callers.root.line
$fhdr  = "<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $focusUnit) &#183; focus </B></FONT></TD></TR>"
[void]$sb.AppendLine("    focus [label=<<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLSPACING=`"3`" CELLPADDING=`"7`">$fhdr<TR><TD HREF=`"$fhref`" TITLE=`"$(ConvertTo-XmlText ([string]$bf.qname))`"><FONT COLOR=`"$($PAL.focusInk)`" POINT-SIZE=`"18`"><B>$focusShort</B></FONT></TD></TR></TABLE>>];")
[void]$sb.AppendLine('  }')

foreach ($g in ($callees | Group-Object { Get-UnitName $_.File } | Sort-Object Name)) {
  Add-UnitCluster 'out' $g.Name $g.Group $PAL.calleeBorder $PAL.calleeFill $PAL.calleeHdr
}

[void]$sb.AppendLine('')
foreach ($c in $callers) {
  if ($portMap.ContainsKey($c.Qname)) {
    [void]$sb.AppendLine("  $($portMap[$c.Qname]) -> focus [color=`"$($PAL.callerBorder)`"];")
  }
}
foreach ($c in $callees) {
  if ($portMap.ContainsKey($c.Qname)) {
    [void]$sb.AppendLine("  focus -> $($portMap[$c.Qname]) [color=`"$($PAL.calleeBorder)`"];")
  }
}
[void]$sb.AppendLine('}')

# ---- 3. write + lay out ------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$base   = ($Qname -replace '[^A-Za-z0-9]', '_')
$dotOut = Join-Path $OutDir "$base.dot"
$svgOut = Join-Path $OutDir "$base.svg"
$plnOut = Join-Path $OutDir "$base.plain"
$pngOut = Join-Path $OutDir "$base.png"
$pdfOut = Join-Path $OutDir "$base.pdf"

[IO.File]::WriteAllText($dotOut, ($sb.ToString() -replace "`r`n", "`n" -replace "`n", "`r`n"),
                        (New-Object Text.UTF8Encoding($false)))

# ONE layout run, four outputs. Verified 2026-09-22: the picture and the geometry
# come from the SAME layout, so hit-test rectangles can never drift from the SVG.
& $Dot -Tsvg -o $svgOut -Tplain -o $plnOut -Tpng -Gdpi=110 -o $pngOut -Tpdf -o $pdfOut $dotOut 2>&1 |
  Where-Object { $_ -notmatch 'Pango-WARNING' -and $_.ToString().Trim() -ne '' } |
  ForEach-Object { Write-Host "  dot: $_" }

if (-not (Test-Path $svgOut)) { throw "dot produced no SVG" }

$svg     = [IO.File]::ReadAllText($svgOut)
$anchors = ([regex]::Matches($svg, '<a[\s>]')).Count
$rows    = $callers.Count + $callees.Count + 1
function Get-FileSize([string] $f) { if (Test-Path $f) { (Get-Item $f).Length } else { 0 } }

[pscustomobject]@{
  Dot          = $dotOut
  Svg          = $svgOut
  Plain        = $plnOut
  # Png/Pdf as PATHS, not just sizes: the bundler moves outputs BY PROPERTY, so
  # it never has to guess that the raster is called "<slug>.png".
  Png          = $pngOut
  Pdf          = $pdfOut
  Callers      = $callers.Count
  Callees      = $callees.Count
  ClickTargets = $anchors
  Expected     = $rows
  AllClickable = ($anchors -ge $rows)
  ExportSvg    = Get-FileSize $svgOut
  ExportPng    = Get-FileSize $pngOut
  ExportPdf    = Get-FileSize $pdfOut
}
