<#
  Emit-ShownWhere.ps1 -- the `shown-where` question: which UI controls display
  this database column.

  >>> THE PLANNED PREMISE WAS WRONG. READ THIS BEFORE CHANGING ANYTHING. <<<
  ---------------------------------------------------------------------------
  Every prior plan said to build this on `symbol_facts.ui_affinity` (230 rows on
  CLIENT, 37 on SERVER) and to treat it as "partial by nature". Measured
  2026-09-23, it is not partial -- it is a DIFFERENT FACT:

    * `ui_affinity` is a THREAD-AFFINITY hint. It lists identifier names whose
      declared type is a VCL/DevExpress base or the globals Application/Screen,
      and it renders as "UI thread only -- touches X"
      (src\doc\DRagLint.Doc.SymbolFacts.pas:11-13).
    * Its top values are `Application` (134), `Screen` (25), `FForm` (16),
      `AForm` (5) -- globals, parameters and locals, not controls.
    * It is carried ONLY by routines: method 169, procedure 29, function 28,
      constructor 4. **ZERO of the 13,131 fields and properties on CLIENT have
      one.** The coverage for the question as posed is 0.0%, not "thin".
    * 0 of its 230 tokens match any component or form symbol name anywhere.

  Building on it would have produced a chart that looked plausible and answered
  a question nobody asked.

  WHAT THIS IS BUILT ON INSTEAD
  ------------------------------
  The DFM data bindings, which are real and complete for what they cover:
  `string_literals` rows of kind `dfm-prop` whose owner is a binding property.
  Measured on CLIENT:

      DataBinding.FieldName               686 rows, 378 distinct columns
      DataBinding.DataField               122 rows, 117 distinct
      DataController.KeyFieldNames         43 rows,  14 distinct
      FieldName                            34 rows,  26 distinct
      Properties.KeyFieldNames             11 rows,   4 distinct
      DataController.DetailKeyFieldNames    4, IndexFieldNames 2,
      DataController.MasterKeyFieldNames    1

  Every one of the 842 binding rows carries a `symbol_id` resolving to a
  `component` symbol with a parent chain, so each row anchors to the exact .dfm
  line and names the control and the view it sits in.

  WHAT IT CANNOT SEE, SAID ON THE CHART
  --------------------------------------
  Code-driven display -- `Label1.Caption := Q.FieldByName('X').AsString` -- is
  invisible to this route. So a small answer means "not data-bound in the DFM",
  never "not shown". The chart prints that.

  SERVER HAS ZERO BINDING ROWS and that is correct, not a failure: it is a
  service with no data-aware UI. The chart says "not applicable to this index"
  rather than "0 found", because those are different claims.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][Alias('Qname','Field','Target')][string] $Column,
  [Parameter(Mandatory)][string] $DbPath,
  [string] $OutDir,
  [int]    $Cap = 10,
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
  formBorder  = '#7C3AED'; formFill  = '#F3EEFF'; formHdr  = '#7C3AED'
  focusBorder = '#0F766E'; focusFill = '#E2F1EF'; focusHdr = '#0F766E'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}

# The binding properties, measured above. Anything else is not a data binding.
$BIND = @('DataBinding.FieldName', 'DataBinding.DataField', 'FieldName', 'DataField',
          'DataController.KeyFieldNames', 'Properties.KeyFieldNames',
          'DataController.DetailKeyFieldNames', 'DataController.MasterKeyFieldNames',
          'IndexFieldNames')

Write-Host "shown-where: $Column"

# ---- 1. index-wide pre-check FIRST (the touches-tables precedent) -----------------
$pre = Invoke-IndexQuery @"
SELECT COUNT(*) AS n, COUNT(DISTINCT text) AS cols, COUNT(DISTINCT file_id) AS forms
  FROM string_literals
 WHERE kind = 'dfm-prop' AND owner_name IN ($(ConvertTo-SqlInList $BIND))
"@
$idxRows  = $(if ($pre.Count) { [int]$pre[0].n } else { 0 })
$idxCols  = $(if ($pre.Count) { [int]$pre[0].cols } else { 0 })
$idxForms = $(if ($pre.Count) { [int]$pre[0].forms } else { 0 })
Write-Host "  index has $idxRows data binding(s) over $idxCols column(s) in $idxForms form file(s)"

if ($idxRows -eq 0) {
  throw ("shown-where: this index contains NO DFM data bindings at all, so the question is not " +
         'applicable to it -- that is different from the column not being shown. A service or ' +
         'console project has no data-aware UI. Ask the index that holds the forms.')
}

# ---- 2. the bindings for this column ----------------------------------------------
# Matched case-insensitively: DFM text is authored by the designer and the SQL
# side of this corpus is upper-case, so an exact match would miss real rows.
$q = ConvertTo-SqlText $Column
$rows = Invoke-IndexQuery @"
SELECT sl.text AS col, sl.owner_name AS prop, sl.start_line AS line,
       f.path AS dfm, c.name AS control, c.qualified_name AS cq,
       p.name AS parent
  FROM string_literals sl
  JOIN files f ON f.id = sl.file_id
  LEFT JOIN symbols c ON c.id = sl.symbol_id
  LEFT JOIN symbols p ON p.id = c.parent_id
 WHERE sl.kind = 'dfm-prop' AND UPPER(sl.text) = UPPER('$q')
   AND sl.owner_name IN ($(ConvertTo-SqlInList $BIND))
 ORDER BY f.path, sl.start_line
"@ 'shown-where (bindings)'

# A Delphi FIELD asked of this chart is a different question with 0% coverage,
# and saying so is more useful than an empty picture.
$asField = $null
if ($rows.Count -eq 0) {
  $asField = Resolve-MemberSelection $Column @('field', 'property') -AllowMissing -Hint 'shown-where selects a DB COLUMN'
  $what = $(if ($asField) { "$($asField.Qname) is a Delphi $($asField.Kind), and no DFM binds a column of that name" }
            else { "no DFM in this index binds a column called '$Column'" })
  throw ("$what. This chart reads DFM data bindings ($idxRows in this index over $idxCols columns); " +
         'it cannot see code-driven display such as Label.Caption := Field.AsString, and ' +
         'symbol_facts.ui_affinity does NOT answer this question -- it is a thread-affinity hint ' +
         'carried by routines, with zero coverage on fields and properties.')
}

$unresolved = @($rows | Where-Object { -not $_.control }).Count
$byForm = @($rows | Group-Object { [string]$_.dfm })
Write-Host ("  {0} binding(s) over {1} form(s), {2} unresolved control(s)" -f $rows.Count, $byForm.Count, $unresolved)

# ---- 3. dot -------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph shownwhere {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.4; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')

$nodeId = 0; $clusters = 0; $anchored = 0

$nodeId++; $clusters++
$fnid = "n$nodeId"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $Column) </B></FONT></TD></TR>")
Add-DisclosureRow $ftbl "$($rows.Count) data binding(s) on $($byForm.Count) form(s)" $PAL.lineInk
Add-DisclosureRow $ftbl "index-wide: $idxRows binding(s) over $idxCols column(s) in $idxForms form file(s)" $PAL.lineInk
Add-DisclosureRow $ftbl 'DFM data bindings only -- code-driven display is not indexed and is not shown' $PAL.lineInk
if ($unresolved -gt 0) { Add-DisclosureRow $ftbl "$unresolved binding(s) did not resolve to a control symbol" $PAL.lineInk }
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

$top = Get-TopRanked @($byForm | Sort-Object { $_.Count } -Descending) $Cap 'Count'
foreach ($g in $top.Shown) {
  $dfm = [string]$g.Group[0].dfm
  $cells = New-Object System.Collections.ArrayList
  foreach ($b in $g.Group) {
    $anchored++
    $ctl = $(if ($b.control) { [string]$b.control } else { '(unresolved control)' })
    [void]$cells.Add([pscustomobject]@{
      Label = $ctl; Line = [int]$b.line
      Href  = New-RowHref $dfm ([int]$b.line)
      Tip   = "$ctl.$([string]$b.prop) = '$([string]$b.col)' -- $([IO.Path]::GetFileName($dfm)):$($b.line)"
      Note  = $(if ($b.parent) { "in $([string]$b.parent)" } else { [string]$b.prop })
    })
  }
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  [void](Add-RowCluster -Sb $sb -Cid "cluster_form_$nodeId" -Nid $nid `
           -Title (Get-UnitName $dfm) -Subtitle "$($g.Count) control$(if ($g.Count -ne 1) { 's' })" `
           -Rows $cells.ToArray() -Border $PAL.formBorder -Fill $PAL.formFill -Hdr $PAL.formHdr `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans)
  [void]$sb.AppendLine("  ${fnid} -> $nid [color=`"$($PAL.formBorder)`"];")
}
$d = Get-DisclosureText $top.HiddenRows 0 'forms'
if ($d) {
  $nodeId++; $clusters++
  [void](Add-RowCluster -Sb $sb -Cid "cluster_more_$nodeId" -Nid "n$nodeId" `
           -Title 'not shown' -Subtitle '' -Rows @((New-NoteRow $d)) `
           -Border $PAL.lineInk -Fill '#F3F4F6' -Hdr '#6B7280' `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style 'rounded,filled,dashed')
}
[void]$sb.AppendLine('}')

if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$lay = Invoke-DotLayout $sb.ToString() $OutDir ('shownwhere_' + ($Column -replace '[^A-Za-z0-9]', '_'))

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Column       = $Column
  Bindings     = $rows.Count
  Forms        = $byForm.Count
  Unresolved   = $unresolved
  IndexRows    = $idxRows
  IndexColumns = $idxCols
  Clusters     = $clusters
  ClickTargets = $lay.Anchors
  Expected     = $anchored
  AllClickable = ($lay.Anchors -ge $anchored)
}
