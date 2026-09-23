<#
  Emit-ClassSurface.ps1 -- the `class-surface` question: what does this TYPE
  actually expose, grouped by visibility.

  DO NOT BUILD THIS ON THE `surface` VERB.
  ----------------------------------------
  `surface --format json` returns a bare ARRAY of {kind, text, line}. Measured
  on Blueprint4.ViewModel.TBlueprint_ViewModel: 212 rows, EVERY ONE
  kind="source", lines 57..525. It is a flat SOURCE SLICE with no member kind
  and no visibility, so consuming it means re-parsing Delphi declarations out of
  text in PowerShell. That is a parser, and this project deliberately does not
  have one.

  Query `symbols` by `parent_id` instead. The same type yields 392 members --
  174 field, 115 property, 101 method, 1 constructor, 1 destructor -- each with
  `signature`, `start_line`, `modifiers` and `impl_start_line` ALREADY
  STRUCTURED.

  The two counts differ (392 vs 212) because `surface` applies a default
  visibility filter; it has --all-visibility. THEY ARE NOT THE SAME QUESTION,
  so neither number is asserted against the other. The structured query is the
  source of truth here.

  VISIBILITY IS IN `modifiers`, AND IT IS RELIABLE -- MEASURED
  ------------------------------------------------------------
  The plan flagged this as unverified, so it was measured before being designed
  on. `symbols.section` is 'interface' for all 392 (that is
  interface-vs-implementation, not visibility) and `vis_explicit` is 1 for all
  392 (a boolean "was it written explicitly", not the value). `modifiers` holds
  the visibility itself, as a plain lowercase string.

  Corpus-wide on CLIENT, for the member kinds this chart draws, every one is
  populated: method 9,345 / field 7,276 / property 2,451 / constructor 343 /
  destructor 324. The only empty tail under a class parent is 7 rows of nested
  const/var/record. So the clusters ARE visibility, not a kind fallback; the
  handful with no visibility recorded go to an explicitly named bucket rather
  than being silently folded into `public`.

  392 rows is not a readable chart, so each cluster is capped and DISCLOSES what
  it left out. Nothing is dropped silently.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Type,
  [Parameter(Mandatory)][string] $DbPath,   # NOT -Db: CmdletBinding aliases that to -Debug
  [int]    $Cap        = 12,                # PER VISIBILITY cluster
  [string] $OutDir,
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
  pubBorder   = '#0F766E'; pubFill   = '#E2F1EF'; pubHdr   = '#0F766E'
  protBorder  = '#B45309'; protFill  = '#FEF6EC'; protHdr  = '#B45309'
  privBorder  = '#98A2B3'; privFill  = '#F4F5F7'; privHdr  = '#98A2B3'
  focusBorder = '#0E7490'; focusFill = '#ECFEFF'; focusHdr = '#0E7490'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'; focusInk = '#0B3F39'
}

# Delphi's own order, most visible first -- so the chart reads as "the surface,
# then what is behind it" rather than in whatever order SQL returned.
$VIS_ORDER = @('published', 'public', 'protected', 'strict protected',
               'private', 'strict private')

Write-Host "class-surface: $Type"

# ---- 1. the type ------------------------------------------------------------
$sel = Resolve-MemberSelection $Type @('class', 'interface', 'record') `
         -Hint 'class-surface needs a type; a unit has no members to expose'
$unit = Get-UnitName $sel.Path
Write-Host "  selection: $($sel.Qname) ($($sel.Kind)) $([IO.Path]::GetFileName($sel.Path)):$($sel.FocusLine)"

# ---- 2. the members, structured ---------------------------------------------
# Counted with an AGGREGATE first: the row list is capped at 200 and this type
# has 392 members, so taking totals from the rows themselves would under-report
# by 192 and never say so.
$tot = Invoke-IndexQuery @"
SELECT c.kind AS kind, COUNT(*) AS n
  FROM symbols c JOIN symbols t ON t.id = c.parent_id
 WHERE t.qualified_name = '$(ConvertTo-SqlText $sel.Qname)'
 GROUP BY 1 ORDER BY 2 DESC
"@ 'class-surface (kind totals)'

$byKind = [ordered]@{}
$total  = 0
foreach ($r in $tot) { $byKind[[string]$r.kind] = [int]$r.n; $total += [int]$r.n }
if ($total -eq 0) {
  throw "$($sel.Qname) is a $($sel.Kind) with no members in this index"
}
Write-Host ("  members={0}  ({1})" -f $total,
            (($byKind.Keys | ForEach-Object { "$_ $($byKind[$_])" }) -join ', '))

$visTot = Invoke-IndexQuery @"
SELECT CASE WHEN c.modifiers IS NULL OR c.modifiers = '' THEN '(no visibility recorded)'
            ELSE c.modifiers END AS vis, COUNT(*) AS n
  FROM symbols c JOIN symbols t ON t.id = c.parent_id
 WHERE t.qualified_name = '$(ConvertTo-SqlText $sel.Qname)'
 GROUP BY 1 ORDER BY 2 DESC
"@ 'class-surface (visibility totals)'
$byVis = [ordered]@{}
foreach ($r in $visTot) { $byVis[[string]$r.vis] = [int]$r.n }
Write-Host ("  visibility: {0}" -f (($byVis.Keys | ForEach-Object { "$_ $($byVis[$_])" }) -join ', '))

# ---- 3. the rows that will actually be DRAWN --------------------------------
# One bounded query per visibility, ordered so the cap keeps the most
# interesting members: methods before properties before fields, then by name.
# Bounded by LIMIT, so it cannot reach the 200-row cap.
$visKeys = @(@($VIS_ORDER | Where-Object { $byVis.Contains($_) }) +
             @($byVis.Keys | Where-Object { $VIS_ORDER -notcontains $_ }))

$clusters = New-Object System.Collections.ArrayList
foreach ($vis in $visKeys) {
  $n = [int]$byVis[$vis]
  $pred = if ($vis -eq '(no visibility recorded)') {
    "(c.modifiers IS NULL OR c.modifiers = '')"
  } else {
    "c.modifiers = '$(ConvertTo-SqlText $vis)'"
  }
  $rows = Invoke-IndexQuery @"
SELECT c.kind AS kind, c.name AS name, c.signature AS signature,
       c.start_line AS start_line, c.impl_start_line AS impl_start_line,
       c.is_virtual AS is_virtual
  FROM symbols c JOIN symbols t ON t.id = c.parent_id
 WHERE t.qualified_name = '$(ConvertTo-SqlText $sel.Qname)' AND $pred
 ORDER BY CASE c.kind WHEN 'constructor' THEN 0 WHEN 'destructor' THEN 1
                      WHEN 'method' THEN 2 WHEN 'property' THEN 3
                      WHEN 'field' THEN 4 ELSE 5 END, c.name
 LIMIT $Cap
"@ "class-surface ($vis)"
  [void]$clusters.Add([pscustomobject]@{
    Vis = $vis; Total = $n; Rows = $rows
    Hidden = [Math]::Max(0, $n - $rows.Count)
  })
}

$shown  = (@($clusters | ForEach-Object { $_.Rows.Count }) | Measure-Object -Sum).Sum
$hidden = (@($clusters | ForEach-Object { $_.Hidden })     | Measure-Object -Sum).Sum
if ($shown + $hidden -ne $total) {
  throw "class-surface: shown $shown + hidden $hidden does not equal $total members -- the cap accounting is wrong"
}
Write-Host ("  shown={0}  disclosed={1}  clusters={2}" -f $shown, $hidden, $clusters.Count)

# ---- 4. dot ------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph classsurface {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.2; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.5, arrowsize=0.8];")
[void]$sb.AppendLine('')

# focus first: everything hangs off it
[void]$sb.AppendLine('  subgraph cluster_focus {')
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=3;")
[void]$sb.AppendLine('    label=""; margin=12;')
$fhref = New-RowHref $sel.Path $sel.FocusLine
$fhdr  = "<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $unit) &#183; $($sel.Kind) </B></FONT></TD></TR>"
$ftip  = ConvertTo-XmlText "$($sel.Qname)  --  $([IO.Path]::GetFileName($sel.Path)):$($sel.FocusLine)"
$ftbl  = New-Object System.Text.StringBuilder
[void]$ftbl.Append("<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLSPACING=`"3`" CELLPADDING=`"7`">$fhdr")
[void]$ftbl.Append("<TR><TD HREF=`"$fhref`" TITLE=`"$ftip`"><FONT COLOR=`"$($PAL.focusInk)`" POINT-SIZE=`"18`"><B>$(ConvertTo-XmlText $sel.Name)</B></FONT></TD></TR>")
Add-DisclosureRow $ftbl ("$total members: " + (($byKind.Keys | ForEach-Object { "$($byKind[$_]) $_" }) -join ', ')) $PAL.lineInk
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("    focus [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

$nid = 0
$edges = New-Object System.Collections.ArrayList
foreach ($c in $clusters) {
  $nid++
  # public/published read as the SURFACE; protected is the extension seam;
  # anything private is the inside, drawn grey so the eye skips it.
  # NOT $pal: PowerShell variable names are CASE-INSENSITIVE, so `$pal` and the
  # palette `$PAL` are THE SAME VARIABLE -- the same trap this repo already
  # documents for `$E` / `$e`. Assigning $pal in this loop wiped the palette and
  # dot then warned "'' is not a known color" for every row ink after the first
  # cluster. Renamed, not worked around.
  $rolePal = switch -Regex ($c.Vis) {
    'published|^public'  { @{ B = $PAL.pubBorder;  F = $PAL.pubFill;  H = $PAL.pubHdr } ; break }
    'protected'          { @{ B = $PAL.protBorder; F = $PAL.protFill; H = $PAL.protHdr }; break }
    default              { @{ B = $PAL.privBorder; F = $PAL.privFill; H = $PAL.privHdr } }
  }
  $cells = New-Object System.Collections.ArrayList
  foreach ($r in $c.Rows) {
    # Anchor to the BODY when there is one; a reader asking what a method does
    # wants the implementation, not the interface line.
    $ln = if ($r.impl_start_line) { [int]$r.impl_start_line } else { [int]$r.start_line }
    $sig = [string]$r.signature
    if ([string]::IsNullOrWhiteSpace($sig)) { $sig = "$([string]$r.kind) $([string]$r.name)" }
    [void]$cells.Add([pscustomobject]@{
      Label = [string]$r.name
      Line  = $ln
      Href  = New-RowHref $sel.Path $ln
      Tip   = "$sig  --  $([IO.Path]::GetFileName($sel.Path)):$ln"
      Note  = $(if ([int]$r.is_virtual -eq 1) { "$([string]$r.kind), virtual" } else { [string]$r.kind })
    })
  }
  $d = Get-DisclosureText $c.Hidden 0 'members'
  if ($d) { [void]$cells.Add((New-NoteRow $d)) }

  $ports = Add-RowCluster -Sb $sb -Cid "cluster_vis$nid" -Nid "nv$nid" `
             -Title $c.Vis -Subtitle "$($c.Total) member$(if ($c.Total -ne 1) { 's' })" `
             -Rows $cells -Border $rolePal.B -Fill $rolePal.F -Hdr $rolePal.H `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
  # ONE edge per cluster, not per row: 392 edges would draw a hairball, and the
  # relationship "this type declares these" is the same fact for every row.
  [void]$edges.Add("  focus -> nv$nid [color=`"$($rolePal.B)`", penwidth=2];")
}

[void]$sb.AppendLine('')
foreach ($e in $edges) { [void]$sb.AppendLine($e) }
[void]$sb.AppendLine('}')

# ---- 5. lay out --------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = ($sel.Qname -replace '[^A-Za-z0-9]', '_') + '_surface'
$lay  = Invoke-DotLayout $sb.ToString() $OutDir $base

$expected = $shown + 1

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Resolved     = $sel.Qname
  Kind         = $sel.Kind
  Members      = $total
  ByKind       = $byKind
  ByVisibility = $byVis
  Shown        = $shown
  Hidden       = $hidden
  Clusters     = $clusters.Count
  ClickTargets = $lay.Anchors
  Expected     = $expected
  AllClickable = ($lay.Anchors -ge $expected)
}
