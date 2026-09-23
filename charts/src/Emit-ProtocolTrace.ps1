<#
  Emit-ProtocolTrace.ps1 -- the `protocol-trace` question, both catalogue rows:
  selecting a COMMAND CONSTANT (or a wire field) and selecting a METHOD.

  >>> THIS WAS BLOCKED UNTIL 2026-09-23 AND IS NOT BLOCKED ANY MORE <<<
  ---------------------------------------------------------------------
  Enum-value references were never bound to a symbol id, so a protocol command
  had no traceable uses at all -- filed as INBOX-enum-value-refs-never-bound.md
  and retired the same day by resolver 1.6.0-alpha. The corpus we read was
  already re-resolved, so the bindings are present:

      cmdDelta       38 refs, 38 bound   (was 38 / 0)
      cmdTableLoad   42 refs, 42 bound   (was 42 / 0)
      index-wide     5,983 refs bound to 592 enum_value symbols (CLIENT)

  BUT THE VERB CANNOT SEE THEM ON THIS BUILD. Our engine is resolver 1.5.1 and
  `query find-callers --name cmdDelta --resolved` returns `[]`, because the
  union arm that reads enum-value bindings is 1.6.0 code we do not have. So this
  emitter reads `refs` by SQL. That is a deliberate workaround with a shelf life:
  when the engine is redeployed the verb becomes available, and this emitter
  should be re-examined rather than left on SQL out of habit.

  THE COLUMN IS `kind`, AND THERE IS NO `mode` (measured)
  --------------------------------------------------------
  `refs` is (id, symbol_id, file_id, kind, name_text, start_line, start_col,
  end_line, end_col, enclosing_symbol_id, receiver_text, external_target).
  There is no `mode` column -- `kind` is the classifier, and EVERY enum-value
  ref carries `kind = 'read'` (CLIENT 5983/5983, SERVER 1970/1970), exactly as
  the owner ruled. `receiver_text` and `external_target` are empty on them.

  ATTRIBUTION IS `enclosing_symbol_id`, AND IT IS POPULATED
  ---------------------------------------------------------
  5,949 of 5,983 on CLIENT; the 34 NULLs are all unit-level const/type context
  in COMMON\MSCTYPES.PAS. For TCommandID specifically it is ZERO NULLs on both
  sides. A ref with no enclosing routine is still SHOWN here, in its own row,
  because "used at unit level" is a real answer and dropping it would silently
  shrink the trace.

  ZONES, NOT DATABASES (the double-count hazard)
  -----------------------------------------------
  Every TCommandID member has at least one ref in COMMON -- `CommandIDToStr`
  (Pipes.Protocol.pas:642) touches all 42 of them -- and COMMON is a member of
  BOTH project closures. So the same physical line is present in the CLIENT
  index and in the SERVER index. Rows are therefore classified by FILE PATH
  zone, never by which database answered, or a cross-index reading would count
  the shared protocol layer twice.
#>
[CmdletBinding()]
param(
  # a command constant (bare `cmdDelta` or qualified), a wire FIELD
  # (Pipes.Protocol.TPipeMessageHeader.CommandID), or a METHOD
  [Parameter(Mandatory)][Alias('Qname','Field','Method')][string] $Target,
  [Parameter(Mandatory)][string] $DbPath,
  [string] $OutDir,
  [int]    $Cap        = 14,
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
  cmdBorder   = '#7C3AED'; cmdFill   = '#F3EEFF'; cmdHdr   = '#7C3AED'   # the protocol itself
  zoneBorder  = '#3B5BDB'; zoneFill  = '#EDF2FF'; zoneHdr  = '#3B5BDB'
  commonBorder= '#0F766E'; commonFill= '#E2F1EF'; commonHdr= '#0F766E'   # shared layer
  focusBorder = '#B45309'; focusFill = '#FEF6EC'; focusHdr = '#B45309'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}

Write-Host "protocol-trace: $Target"

# ---- 1. resolve the selection and pick the mode --------------------------------
$sel = Resolve-MemberSelection $Target `
         @('enum_value', 'field', 'property', 'method', 'function', 'procedure') `
         -Hint 'protocol-trace selects a command constant, a wire field, or a method'

$mode = switch ($sel.Kind) {
  'enum_value' { 'command' }
  'field'      { 'field' }
  'property'   { 'field' }
  default      { 'method' }
}
Write-Host "  selection: $($sel.Qname) ($($sel.Kind)) -- $mode trace"

# ---- 2. zone map ----------------------------------------------------------------
# PAGED, and that is not defensive tidiness: the unpaged form silently returned
# the first 200 of CLIENT's 625 files, every one of them under \CLIENT\, so the
# common root came back as ...\ORM3\CLIENT and EVERY row collapsed into a single
# '(root)' zone. cmdDelta reported 1 zone instead of CLIENT + COMMON -- a wrong
# chart produced by a cap that reports nothing.
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

# ---- 3. gather the rows ----------------------------------------------------------
# One query shape for all three modes: a ref, where it is, and the routine it sits
# in. The modes differ only in WHICH refs.
function Get-TraceRows([string] $Where) {
  $out = New-Object System.Collections.ArrayList
  $off = 0
  while ($true) {
    $page = Invoke-IndexQuery @"
SELECT r.id AS rid, r.kind AS kind, r.name_text AS nm, r.start_line AS line,
       f.path AS path, encl.qualified_name AS routine,
       encl.impl_start_line AS rline, ef.path AS rpath,
       tgt.qualified_name AS target_q, tgt.kind AS target_kind
  FROM refs r
  JOIN files f ON f.id = r.file_id
  LEFT JOIN symbols encl ON encl.id = r.enclosing_symbol_id
  LEFT JOIN files ef ON ef.id = encl.file_id
  LEFT JOIN symbols tgt ON tgt.id = r.symbol_id
 WHERE $Where
 ORDER BY r.id LIMIT 180 OFFSET $off
"@
    if ($page.Count -eq 0) { break }
    foreach ($p in $page) { [void]$out.Add($p) }
    if ($page.Count -lt 180) { break }
    $off += 180
  }
  , $out.ToArray()
}

$commands = @()   # command mode / method mode: the constants involved
switch ($mode) {
  'command' {
    $rows = Get-TraceRows "r.symbol_id = $($sel.Id)"
    $commands = @($sel.Qname)
  }
  'field' {
    $rows = Get-TraceRows "r.symbol_id = $($sel.Id)"
  }
  'method' {
    # every enum-value read inside this routine's body -- i.e. which protocol
    # commands this routine speaks
    $rows = Get-TraceRows "r.enclosing_symbol_id = $($sel.Id) AND tgt.kind = 'enum_value'"
    $commands = @($rows | ForEach-Object { [string]$_.target_q } | Sort-Object -Unique)
  }
}

if ($rows.Count -eq 0) {
  if ($mode -eq 'method') {
    throw ("$($sel.Qname) references no enum constant at all, so it speaks no protocol this index can see. " +
           'If you expected commands here, check that the constant is an enum value rather than a typed const.')
  }
  throw "$($sel.Qname) has no references in this index"
}

# ---- 4. classify every row by ZONE, and by whether it is attributed --------------
$tally = @{}
$unattributed = 0
foreach ($r in $rows) {
  $z = Get-PathZone ([string]$r.path) $rootLen
  if (-not $tally.ContainsKey($z)) { $tally[$z] = New-Object System.Collections.ArrayList }
  if (-not $r.routine) { $unattributed++ }
  [void]$tally[$z].Add($r)
}
$zones = @($tally.Keys | Sort-Object { $tally[$_].Count } -Descending)

# `kind` should be uniformly 'read' for enum values. If it ever is not, say so
# rather than quietly averaging two different facts into one picture.
$kinds = @($rows | ForEach-Object { [string]$_.kind } | Sort-Object -Unique)

Write-Host ("  rows={0}  zones={1}  routines={2}  unattributed={3}  kinds={4}" -f `
            $rows.Count, $zones.Count,
            @($rows | Where-Object { $_.routine } | ForEach-Object { [string]$_.routine } | Sort-Object -Unique).Count,
            $unattributed, ($kinds -join '/'))

# ---- 5. dot ----------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph prototrace {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.4; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')

$nodeId = 0; $clusters = 0; $anchored = 0

# FOCUS: the constant / field / method
$nodeId++; $clusters++
$fnid = "n$nodeId"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $sel.Name) </B></FONT></TD></TR>")
$anchored++
[void]$ftbl.Append("<TR><TD PORT=`"p1`" ALIGN=`"LEFT`" HREF=`"$(New-RowHref $sel.Path $sel.FocusLine)`" TITLE=`"$(ConvertTo-XmlText $sel.Qname)`">")
[void]$ftbl.Append("<FONT COLOR=`"$($PAL.rowInk)`">$(ConvertTo-XmlText (Get-UnitName $sel.Path))</FONT>")
[void]$ftbl.Append("  <FONT COLOR=`"$($PAL.lineInk)`" POINT-SIZE=`"12`">:$($sel.FocusLine)</FONT></TD></TR>")
Add-DisclosureRow $ftbl "$($sel.Kind)  &#183;  $($rows.Count) reference(s) in $($zones.Count) zone(s)" $PAL.lineInk
if ($kinds.Count -eq 1) {
  Add-DisclosureRow $ftbl "every reference is a '$($kinds[0])'" $PAL.lineInk
} else {
  Add-DisclosureRow $ftbl "MIXED reference kinds: $($kinds -join ', ')" $PAL.lineInk
}
if ($unattributed -gt 0) {
  Add-DisclosureRow $ftbl "$unattributed reference(s) sit at unit level, not inside a routine" $PAL.lineInk
}
Add-DisclosureRow $ftbl 'rows are zoned by FILE PATH: a shared unit is in both project indexes' $PAL.lineInk
Add-DisclosureRow $ftbl 'read from refs by SQL -- find-callers --resolved cannot see enum values on this build' $PAL.lineInk
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

# one cluster per ZONE, rows are the routines that reference it
foreach ($z in $zones) {
  $zr = @($tally[$z])
  # collapse to one row per routine, carrying its site count
  $byRoutine = @()
  foreach ($g in ($zr | Group-Object { $(if ($_.routine) { [string]$_.routine } else { '(unit level) ' + (Get-UnitName ([string]$_.path)) }) })) {
    $first = $g.Group[0]
    $byRoutine += [pscustomobject]@{
      Name = $g.Name
      Sites = $g.Count
      HasRoutine = [bool]$first.routine
      # anchor at the REFERENCE, not the routine header: the reference is the
      # line you came here to read.
      Path = [string]$first.path
      Line = [int]$first.line
      Cmd  = [string]$first.target_q
    }
  }
  $byRoutine = @($byRoutine | Sort-Object @{ E = { $_.Sites }; Descending = $true }, @{ E = { $_.Name } })
  $top = Get-TopRanked $byRoutine $Cap 'Sites'

  $cells = New-Object System.Collections.ArrayList
  foreach ($b in $top.Shown) {
    $anchored++
    $note = $(if ($b.Sites -gt 1) { "$($b.Sites) sites" } else { $null })
    if ($mode -eq 'method' -and $b.Cmd) { $note = (($b.Cmd -split '\.')[-1]) + $(if ($b.Sites -gt 1) { " x$($b.Sites)" } else { '' }) }
    [void]$cells.Add([pscustomobject]@{
      Label = $(if ($b.HasRoutine) { Get-ShortName $b.Name (Get-UnitName $b.Path) } else { $b.Name })
      Line  = $b.Line
      Href  = New-RowHref $b.Path $b.Line
      Tip   = "$($b.Name) -- $([IO.Path]::GetFileName($b.Path)):$($b.Line)$(if ($b.Sites -gt 1) { "  ($($b.Sites) references)" })"
      Note  = $note
    })
  }
  $d = Get-DisclosureText $top.HiddenRows $top.HiddenSites 'routines'
  if ($d) { [void]$cells.Add((New-NoteRow $d)) }

  $isCommon = ($zr.Count -gt 0 -and $z -notmatch '(?i)client|server')
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  [void](Add-RowCluster -Sb $sb -Cid "cluster_zone_$nodeId" -Nid $nid `
           -Title $z -Subtitle "$($zr.Count) reference$(if ($zr.Count -ne 1) { 's' })" -Rows $cells.ToArray() `
           -Border $(if ($isCommon) { $PAL.commonBorder } else { $PAL.zoneBorder }) `
           -Fill $(if ($isCommon) { $PAL.commonFill } else { $PAL.zoneFill }) `
           -Hdr $(if ($isCommon) { $PAL.commonHdr } else { $PAL.zoneHdr }) `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans)
  [void]$sb.AppendLine("  ${fnid}:p1 -> $nid [color=`"$($PAL.cmdBorder)`"];")
}
[void]$sb.AppendLine('}')

# ---- 6. lay out --------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = 'prototrace_' + ($sel.Qname -replace '[^A-Za-z0-9]', '_')
$lay = Invoke-DotLayout $sb.ToString() $OutDir $base

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Qname        = $sel.Qname
  Mode         = $mode
  Refs         = $rows.Count
  Zones        = $zones.Count
  Routines     = @($rows | Where-Object { $_.routine } | ForEach-Object { [string]$_.routine } | Sort-Object -Unique).Count
  Commands     = $commands.Count
  Unattributed = $unattributed
  Kinds        = ($kinds -join ',')
  Clusters     = $clusters
  ClickTargets = $lay.Anchors
  Expected     = $anchored
  AllClickable = ($lay.Anchors -ge $anchored)
}
