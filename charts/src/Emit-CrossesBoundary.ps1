<#
  Emit-CrossesBoundary.ps1 -- the `crosses-boundary` question: does this method's
  work leave the process, and if so on what protocol command.

  WHAT COUNTS AS EVIDENCE HERE, AND WHY IT IS NOT CALL EDGES ALONE
  -----------------------------------------------------------------
  The obvious implementation -- "walk what this method calls until you hit the
  pipe" -- is the one thing that cannot be trusted on this corpus, and the reason
  is sharper than it first looked.

  An earlier version of this comment blamed the 1.6.0 resolver for losing
  interface-dispatch edges wholesale. That was WRONG. The engine team gave the
  real mechanism on 2026-09-23 and we verified it on our own clone: a whole-DB
  resolve clears call_edges UNCONDITIONALLY but re-derives only non-stale files,
  so a WITHHELD file's edges are cleared and never rebuilt. On CLIENT exactly one
  file was withheld -- `uPipeClientConnection.pas`, 161 call refs and ZERO call
  edges -- and `TPipeClientConnection.ExecuteCommand` lives in it with no
  outgoing edges at all.

  That file is the transport layer. So on THIS index a callee walk stops dead at
  precisely the boundary this chart is about, and would report "does not cross"
  for methods that plainly do. It is recoverable by one reindex, and
  Get-EdgelessFiles detects it rather than this comment asserting it -- when the
  index is healthy the disclosure disappears by itself.

  So this chart rests on THREE independent pieces of evidence, and says which
  ones it found:

    1. ZONE          -- which source zone the method lives in. A method inside a
                        pipe unit IS the boundary rather than crossing it.
    2. COMMANDS      -- protocol enum constants the method references. This comes
                        from `refs`, which is complete and unaffected by the call
                        edge loss, and it is the strongest signal available.
    3. PIPE CALLS    -- call edges from this method into a routine declared in a
                        pipe unit. Edges INTO the transport survive (they are
                        owned by the caller's file, so `ExecuteCommand` still has
                        586 distinct callers); it is edges OUT of the withheld
                        file that are gone. Its ABSENCE is never reported as
                        proof of anything.

  A chart that found (2) and not (3) still says "crosses". A chart that found
  neither says "no evidence in this index" -- NOT "does not cross". The
  difference matters: with an incomplete edge set, absence is not evidence.

  BOUNDARY UNITS ARE MATCHED BY NAME, AND THAT IS A CONVENTION
  --------------------------------------------------------------
  Measured: CLIENT has 5 pipe units declaring 113 routines, SERVER has 7
  declaring 212, under `Pipes.*` / `uPipe*` / `uBroadcast*`. Nothing in the index
  MARKS a unit as the transport layer, so this is a naming convention and the
  chart labels it as one. -BoundaryPattern overrides it for a corpus that names
  its transport differently.

  THE COUNTERPART SIDE IS A SEPARATE INDEX, AND IS OPTIONAL
  -----------------------------------------------------------
  "Who is on the other end" cannot be answered from one project index: the two
  halves are separate closures. With -CounterpartDb the chart adds the routines
  in that index which reference the SAME command, joined by command NAME -- the
  only join available, and legitimate here because all 42 TCommandID members
  appear in both indexes from the same COMMON declaration. Rows from the other
  index are drawn in their own cluster and labelled with it, never merged.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][Alias('Qname')][string] $Target,
  [Parameter(Mandatory)][string] $DbPath,
  [string] $CounterpartDb,                 # the other half, e.g. the SERVER index
  [string] $OutDir,
  [int]    $Cap = 12,
  [string] $BoundaryPattern = 'Pipes.%|uPipe%|uBroadcast%',
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$DbPath = Get-CloneDb $DbPath
if ($CounterpartDb) { $CounterpartDb = Get-CloneDb $CounterpartDb }

$PAL = @{
  cmdBorder   = '#7C3AED'; cmdFill   = '#F3EEFF'; cmdHdr   = '#7C3AED'
  pipeBorder  = '#B02A37'; pipeFill  = '#FDECEE'; pipeHdr  = '#B02A37'
  farBorder   = '#B45309'; farFill   = '#FEF6EC'; farHdr   = '#B45309'
  focusBorder = '#3B5BDB'; focusFill = '#EDF2FF'; focusHdr = '#3B5BDB'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}

Write-Host "crosses-boundary: $Target"

$sel = Resolve-MemberSelection $Target @('method', 'function', 'procedure', 'constructor', 'destructor') `
         -Hint 'crosses-boundary selects a METHOD'

# ---- zone map (PAGED -- see Emit-ProtocolTrace for why the unpaged form lies) ----
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
$myZone = Get-PathZone $sel.Path $rootLen

# ---- boundary unit predicate -----------------------------------------------------
$likes = @($BoundaryPattern -split '\|' | ForEach-Object { "u.qualified_name LIKE '$(ConvertTo-SqlText $_)'" }) -join ' OR '

# Is the SELECTION itself inside the transport layer?
#
# Assigned DIRECTLY. `@(Invoke-IndexQuery ...)` NESTS the function's `, $array`
# return one level deep, so .Count reads 1 for an EMPTY result -- which made
# every method on the corpus report "is the boundary". The contract is in
# Emit-Common's header and this is the trap it warns about.
$pipeSelfRows = Invoke-IndexQuery @"
SELECT 1 AS x FROM symbols u JOIN files f ON f.id = u.file_id
 WHERE u.kind='unit' AND f.path = '$(ConvertTo-SqlText $sel.Path)' AND ($likes)
"@
$selfIsPipe = ($pipeSelfRows.Count -gt 0)

# ---- evidence 2: protocol commands this method references -------------------------
$cmdRows = Invoke-IndexQuery @"
SELECT tgt.qualified_name AS cmd, tgt.name AS nm, COUNT(*) AS n,
       MIN(r.start_line) AS line, f.path AS path
  FROM refs r
  JOIN symbols tgt ON tgt.id = r.symbol_id
  JOIN files f ON f.id = r.file_id
 WHERE r.enclosing_symbol_id = $($sel.Id) AND tgt.kind = 'enum_value'
 GROUP BY tgt.qualified_name, tgt.name, f.path
 ORDER BY n DESC
"@ 'crosses-boundary (commands)'

# ---- evidence 3: call edges from this method into a transport routine --------------
$pipeCalls = Invoke-IndexQuery @"
SELECT DISTINCT s.qualified_name AS q, s.impl_start_line AS line, f.path AS path
  FROM call_edges ce
  JOIN refs r ON r.id = ce.ref_id
  JOIN symbols s ON s.id = ce.target_symbol_id
  JOIN files f ON f.id = s.file_id
  JOIN symbols u ON u.file_id = f.id AND u.kind='unit'
 WHERE r.enclosing_symbol_id = $($sel.Id) AND ($likes)
 ORDER BY s.qualified_name
"@ 'crosses-boundary (pipe calls)'

# ---- the counterpart index, if one was given ---------------------------------------
$far = @()
$farName = ''
if ($CounterpartDb -and $cmdRows.Count -gt 0) {
  $farName = [IO.Path]::GetFileNameWithoutExtension($CounterpartDb)
  $names = @($cmdRows | ForEach-Object { [string]$_.nm } | Sort-Object -Unique)
  # Invoke-IndexQuery reads $DbPath from the caller's scope, so the counterpart
  # query runs with $DbPath temporarily rebound. Restored immediately -- every
  # other query in this emitter must hit the primary index.
  $primary = $DbPath
  try {
    $DbPath = $CounterpartDb
    $far = Invoke-IndexQuery @"
SELECT tgt.name AS cmd, encl.qualified_name AS routine,
       encl.impl_start_line AS line, ef.path AS path, COUNT(*) AS n
  FROM refs r
  JOIN symbols tgt ON tgt.id = r.symbol_id
  JOIN symbols encl ON encl.id = r.enclosing_symbol_id
  JOIN files ef ON ef.id = encl.file_id
 WHERE tgt.kind = 'enum_value' AND tgt.name IN ($(ConvertTo-SqlInList $names))
 GROUP BY tgt.name, encl.qualified_name, encl.impl_start_line, ef.path
 ORDER BY n DESC
"@ 'crosses-boundary (counterpart)'
  } finally { $DbPath = $primary }
}

# ---- the verdict --------------------------------------------------------------------
$verdict = if ($selfIsPipe) { 'is the boundary' }
           elseif ($cmdRows.Count -gt 0 -or $pipeCalls.Count -gt 0) { 'crosses' }
           else { 'no evidence in this index' }

Write-Host ("  zone={0}  verdict={1}  commands={2}  pipe calls={3}  counterpart rows={4}" -f `
            $myZone, $verdict, $cmdRows.Count, $pipeCalls.Count, $far.Count)

# ---- dot ------------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph crossesboundary {')
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
Add-DisclosureRow $ftbl "zone $myZone  &#183;  VERDICT: $verdict" $PAL.lineInk
if ($selfIsPipe) { Add-DisclosureRow $ftbl 'declared inside the transport layer itself' $PAL.lineInk }
Add-DisclosureRow $ftbl "$($cmdRows.Count) protocol command(s)  &#183;  $($pipeCalls.Count) call(s) into a transport routine" $PAL.lineInk
if ($verdict -eq 'no evidence in this index') {
  Add-DisclosureRow $ftbl 'this is NOT "does not cross" -- absence of an edge is not absence of a call' $PAL.lineInk
}
if ($pipeCalls.Count -eq 0 -and $cmdRows.Count -gt 0) {
  Add-DisclosureRow $ftbl 'commands found but no transport call: the call may be an interface dispatch, or its edge may be missing' $PAL.lineInk
}
Add-DisclosureRow $ftbl "transport units matched by naming convention ($BoundaryPattern)" $PAL.lineInk
$edgeless = Get-EdgelessFiles
$edgelessNote = Get-EdgelessDisclosure $edgeless
if ($edgelessNote) { Add-DisclosureRow $ftbl $edgelessNote $PAL.lineInk }
if (-not $CounterpartDb) {
  Add-DisclosureRow $ftbl 'no counterpart index given -- the far side is not shown' $PAL.lineInk
}
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

function Add-Evidence([string] $Title, [string] $Sub, $Cells, [string] $B, [string] $F, [string] $H, [string] $Style) {
  $script:nodeId++; $script:clusters++
  $nid = "n$script:nodeId"
  [void](Add-RowCluster -Sb $script:sb -Cid "cluster_ev_$script:nodeId" -Nid $nid `
           -Title $Title -Subtitle $Sub -Rows $Cells -Border $B -Fill $F -Hdr $H `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style $Style)
  [void]$script:sb.AppendLine("  ${fnid}:p1 -> $nid [color=`"$B`"];")
}

if ($cmdRows.Count -gt 0) {
  $t = Get-TopRanked $cmdRows $Cap 'n'
  $cells = New-Object System.Collections.ArrayList
  foreach ($c in $t.Shown) {
    $anchored++
    [void]$cells.Add([pscustomobject]@{
      Label = [string]$c.nm; Line = [int]$c.line
      Href  = New-RowHref ([string]$c.path) ([int]$c.line)
      Tip   = "$([string]$c.cmd) -- referenced $($c.n) time(s) in this method"
      Note  = $(if ([int]$c.n -gt 1) { "$($c.n) refs" } else { $null })
    })
  }
  $d = Get-DisclosureText $t.HiddenRows 0 'commands'
  if ($d) { [void]$cells.Add((New-NoteRow $d)) }
  Add-Evidence 'commands spoken' "$($cmdRows.Count)" $cells.ToArray() $PAL.cmdBorder $PAL.cmdFill $PAL.cmdHdr 'rounded,filled'
}

if ($pipeCalls.Count -gt 0) {
  $t = Get-TopRanked $pipeCalls $Cap 'line'
  $cells = New-Object System.Collections.ArrayList
  foreach ($c in $t.Shown) {
    $anchored++
    [void]$cells.Add([pscustomobject]@{
      Label = Get-ShortName ([string]$c.q) (Get-UnitName ([string]$c.path))
      Line  = [int]$c.line
      Href  = New-RowHref ([string]$c.path) ([int]$c.line)
      Tip   = "$([string]$c.q) -- $([IO.Path]::GetFileName([string]$c.path)):$($c.line)"
      Note  = Get-UnitName ([string]$c.path)
    })
  }
  $d = Get-DisclosureText $t.HiddenRows 0 'routines'
  if ($d) { [void]$cells.Add((New-NoteRow $d)) }
  Add-Evidence 'reaches the transport' "$($pipeCalls.Count)" $cells.ToArray() $PAL.pipeBorder $PAL.pipeFill $PAL.pipeHdr 'rounded,filled'
}

if ($far.Count -gt 0) {
  $t = Get-TopRanked $far $Cap 'n'
  $cells = New-Object System.Collections.ArrayList
  foreach ($c in $t.Shown) {
    $anchored++
    [void]$cells.Add([pscustomobject]@{
      Label = Get-ShortName ([string]$c.routine) (Get-UnitName ([string]$c.path))
      Line  = [int]$c.line
      Href  = New-RowHref ([string]$c.path) ([int]$c.line)
      Tip   = "$([string]$c.routine) handles $([string]$c.cmd) -- from the $farName index"
      Note  = [string]$c.cmd
    })
  }
  $d = Get-DisclosureText $t.HiddenRows 0 'routines'
  if ($d) { [void]$cells.Add((New-NoteRow $d)) }
  [void]$cells.Add((New-NoteRow "from a DIFFERENT index ($farName), joined by command name"))
  Add-Evidence 'the far side' "$($far.Count) routine(s)" $cells.ToArray() $PAL.farBorder $PAL.farFill $PAL.farHdr 'rounded,filled,dashed'
}

if ($verdict -eq 'no evidence in this index') {
  $script:nodeId++; $script:clusters++
  $nid = "n$script:nodeId"
  [void](Add-RowCluster -Sb $sb -Cid "cluster_none_$nodeId" -Nid $nid `
           -Title 'no boundary evidence' -Subtitle 'in this index' `
           -Rows @((New-NoteRow 'no protocol command referenced, no call into a transport unit'),
                   (New-NoteRow 'absence is NOT proof: an unresolved or cleared edge looks the same as no call')) `
           -Border $PAL.lineInk -Fill '#F3F4F6' -Hdr '#6B7280' `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style 'rounded,filled,dashed')
  [void]$sb.AppendLine("  ${fnid}:p1 -> $nid [style=dashed];")
}
[void]$sb.AppendLine('}')

if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$lay = Invoke-DotLayout $sb.ToString() $OutDir ('boundary_' + ($sel.Qname -replace '[^A-Za-z0-9]', '_'))

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Qname        = $sel.Qname
  Zone         = $myZone
  Verdict      = $verdict
  Commands     = $cmdRows.Count
  PipeCalls    = $pipeCalls.Count
  FarSide      = $far.Count
  SelfIsPipe   = $selfIsPipe
  Clusters     = $clusters
  ClickTargets = $lay.Anchors
  Expected     = $anchored
  AllClickable = ($lay.Anchors -ge $anchored)
}
