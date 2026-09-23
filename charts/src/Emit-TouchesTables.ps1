<#
  Emit-TouchesTables.ps1 -- the `touches-tables` question, and a THIRD TIER:
  the database.

  Which physical tables does this method read, and which does it write.

  SERVER-ONLY BY DESIGN, AND THAT IS AN ANSWER, NOT A GAP. In ORM3 the client
  owns no FireDAC connection: it asks the server over a pipe, so no client
  method can touch a table. Measured, the CLIENT index has 0 sql_reads and 0
  sql_writes across 11,005 symbol_facts rows; the SERVER index has 19 and 148
  across 8,921. An emitter that answered "0 tables" for a client method would
  be technically true and completely misleading -- it would read as "this
  method does no database work" when the truth is "ask a different index".
  So the index-wide pre-check runs FIRST, before the symbol is even looked up,
  and refuses with the reason rather than drawing an empty chart.

  ZERO FOR ONE SYMBOL IS DIFFERENT FROM ZERO FOR THE INDEX. If the index has
  SQL facts but this method has none, that is a real, useful answer: the chart
  renders the focus alone with a note saying how many methods here DO touch
  tables, and exits 0.

  PROVENANCE IS A LITERAL, NOT THE FACT. A table row clicks through to the
  first string literal inside the method body that actually names that table,
  so the reader lands on the SQL rather than on the method header. The match
  is word-bounded on purpose: GEN_DRA1_ID must not resolve DRA1. When no
  literal names it -- the table reached the fact through a constant or a
  built-up string -- the row falls back to the method's own line and SAYS SO.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Qname,
  [Parameter(Mandatory)][string] $DbPath,
  [string] $OutDir,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

# New role, this emitter only: the DB tier is neither a caller, a callee, nor
# UI. Both wings share it -- DIRECTION carries read vs write, not hue.
$PAL = @{
  dbBorder    = '#BE185D'; dbFill    = '#FDF2F8'; dbHdr    = '#BE185D'
  focusBorder = '#0F766E'; focusFill = '#E2F1EF'; focusHdr = '#0F766E'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'; focusInk = '#0B3F39'
}

Write-Host "touches-tables: $Qname"

# ---- 1. index-wide pre-check, BEFORE anything else ---------------------------
$pre = Invoke-IndexQuery @'
SELECT SUM(sql_reads IS NOT NULL) AS r, SUM(sql_writes IS NOT NULL) AS w,
       SUM(sql_reads IS NOT NULL OR sql_writes IS NOT NULL) AS either,
       COUNT(*) AS n
  FROM symbol_facts
'@
$nReads  = [int]$pre[0].r
$nWrites = [int]$pre[0].w
$nEither = [int]$pre[0].either
$nFacts  = [int]$pre[0].n

if ($nEither -eq 0) {
  throw ("touches-tables: this index has NO SQL facts at all ($nReads sql_reads, $nWrites sql_writes " +
         "across $nFacts symbol_facts rows). That is correct, not a gap: this project has no FireDAC " +
         'connection, so no method can touch a table. Ask on the index of the process that owns the ' +
         'connection (for ORM3 that is the SERVER index).')
}
Write-Host "  index has SQL facts on $nEither of $nFacts symbols ($nReads read, $nWrites write)"

# ---- 2. the symbol, then its facts -------------------------------------------
$loc = Get-SymbolLocation $Qname     # throws "<Qname> is not in this index"
$unit = Get-UnitName $loc.Path

$fact = Invoke-IndexQuery "SELECT sf.sql_reads AS r, sf.sql_writes AS w FROM symbol_facts sf WHERE sf.symbol_id = $($loc.Id)"

function Split-Tables($v) {
  if ([string]::IsNullOrWhiteSpace([string]$v)) { return @() }
  @(([string]$v -split ',\s*') | ForEach-Object { $_.Trim().ToUpperInvariant() } |
    Where-Object { $_ -ne '' } | Sort-Object -Unique)
}
$reads  = @()
$writes = @()
if ($fact.Count) { $reads = Split-Tables $fact[0].r; $writes = Split-Tables $fact[0].w }

$both     = @($reads | Where-Object { $writes -contains $_ })
$distinct = @(($reads + $writes) | Sort-Object -Unique)
Write-Host ("  reads={0}  writes={1}  both={2}  distinct={3}" -f $reads.Count, $writes.Count, $both.Count, $distinct.Count)

# ---- 3. provenance: the first literal inside the body that NAMES the table ----
$lits = @()
if ($distinct.Count -and $loc.ImplStart -gt 0 -and $loc.ImplEnd -ge $loc.ImplStart) {
  $pq = ConvertTo-SqlText $loc.Path
  $lits = Invoke-IndexQuery @"
SELECT sl.start_line AS line, sl.kind AS kind, sl.text AS text
  FROM string_literals sl JOIN files f ON f.id = sl.file_id
 WHERE f.path = '$pq' AND sl.kind IN ('literal','format')
   AND sl.start_line BETWEEN $($loc.ImplStart) AND $($loc.ImplEnd)
 ORDER BY sl.start_line
"@ 'touches-tables (literal provenance)'
}

$unresolved = 0
function New-TableRow([string] $Table, [string] $Mode) {
  # word-bounded so GEN_DRA1_ID does not resolve DRA1
  $re  = "(?i)(^|[^A-Z0-9_])$([regex]::Escape($Table))([^A-Z0-9_]|`$)"
  $hit = $lits | Where-Object { [string]$_.text -match $re } | Select-Object -First 1
  if ($hit) {
    [pscustomobject]@{
      Label = $Table; Line = [int]$hit.line
      Href  = New-RowHref $loc.Path ([int]$hit.line)
      Tip   = "$Table ($Mode)  --  $([IO.Path]::GetFileName($loc.Path)):$($hit.line)"
      Note  = $null
    }
  } else {
    $script:unresolved++
    [pscustomobject]@{
      Label = $Table; Line = $loc.FocusLine
      Href  = New-RowHref $loc.Path $loc.FocusLine
      Tip   = "$Table ($Mode)  --  (fact only; no literal names $Table inside the method)"
      Note  = 'fact only'
    }
  }
}
$readRows  = @($reads  | ForEach-Object { New-TableRow $_ 'read' })
$writeRows = @($writes | ForEach-Object { New-TableRow $_ 'written' })

# ---- 4. dot ------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph touchestables {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.3; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.5, arrowsize=0.8];")
[void]$sb.AppendLine('')

$readPorts = @()
if ($readRows.Count) {
  $readPorts = Add-RowCluster -Sb $sb -Cid 'cluster_reads' -Nid 'nr' `
                 -Title 'reads' -Subtitle "$($readRows.Count) table$(if ($readRows.Count -ne 1) { 's' })" `
                 -Rows $readRows -Border $PAL.dbBorder -Fill $PAL.dbFill -Hdr $PAL.dbHdr `
                 -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
}

# focus
[void]$sb.AppendLine('  subgraph cluster_focus {')
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=3;")
[void]$sb.AppendLine('    label=""; margin=12;')
$fhref = New-RowHref $loc.Path $loc.FocusLine
$fhdr  = "<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $unit) &#183; focus </B></FONT></TD></TR>"
$ftip  = ConvertTo-XmlText "$Qname  --  $([IO.Path]::GetFileName($loc.Path)):$($loc.FocusLine)"
$ftbl  = New-Object System.Text.StringBuilder
[void]$ftbl.Append("<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLSPACING=`"3`" CELLPADDING=`"7`">$fhdr")
[void]$ftbl.Append("<TR><TD HREF=`"$fhref`" TITLE=`"$ftip`"><FONT COLOR=`"$($PAL.focusInk)`" POINT-SIZE=`"18`"><B>$(ConvertTo-XmlText (Get-ShortName $Qname $unit))</B></FONT></TD></TR>")
if ($distinct.Count -eq 0) {
  # A real answer, not a failure. Deliberately NOT anchored: there is no line to
  # go to, and a dead link would be worse than no link.
  [void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`"><FONT COLOR=`"$($PAL.lineInk)`" POINT-SIZE=`"12`">touches no tables ($nEither methods in this index do)</FONT></TD></TR>")
}
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("    focus [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

$writePorts = @()
if ($writeRows.Count) {
  $writePorts = Add-RowCluster -Sb $sb -Cid 'cluster_writes' -Nid 'nw' `
                  -Title 'writes' -Subtitle "$($writeRows.Count) table$(if ($writeRows.Count -ne 1) { 's' })" `
                  -Rows $writeRows -Border $PAL.dbBorder -Fill $PAL.dbFill -Hdr $PAL.dbHdr `
                  -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
}

[void]$sb.AppendLine('')
# A table in BOTH sets gets a row in BOTH clusters. That is the honest picture:
# collapsing it to one row would have to pick a direction, and there are two.
for ($i = 0; $i -lt $readRows.Count; $i++) {
  [void]$sb.AppendLine("  $($readPorts[$i]) -> focus [color=`"$($PAL.dbBorder)`"];")
}
for ($i = 0; $i -lt $writeRows.Count; $i++) {
  [void]$sb.AppendLine("  focus -> $($writePorts[$i]) [color=`"$($PAL.dbBorder)`", penwidth=2.2];")
}
[void]$sb.AppendLine('}')

# ---- 5. lay out --------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = ($Qname -replace '[^A-Za-z0-9]', '_')
$lay  = Invoke-DotLayout $sb.ToString() $OutDir $base

$expected = $readRows.Count + $writeRows.Count + 1

[pscustomobject]@{
  Dot             = $lay.Dot
  Svg             = $lay.Svg
  Plain           = $lay.Plain
  Png             = $lay.Png
  Pdf             = $lay.Pdf
  Reads           = $readRows.Count
  Writes          = $writeRows.Count
  Both            = $both.Count
  Distinct        = $distinct.Count
  Unresolved      = $unresolved
  IndexSqlSymbols = $nEither
  ClickTargets    = $lay.Anchors
  Expected        = $expected
  AllClickable    = ($lay.Anchors -ge $expected)
}
