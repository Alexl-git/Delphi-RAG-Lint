<#
  Emit-Wiring.ps1 -- the `wiring` question: who REGISTERS an interface, with what
  lifetime, and where it is RESOLVED.

  BUILD ON di_bindings, NEVER symbol_facts.wiring
  -----------------------------------------------
  `symbol_facts.wiring` is 0 non-NULL on BOTH ORM3 indexes (measured 2026-09-23).
  A chart built on it would have no rows and no way to tell that apart from an
  interface nobody registers. The `wiring` verb reads `di_bindings`, which has
  CLIENT 4 / SERVER 535 rows, and that is the only source used here.

  THE VERB CANNOT TELL YOU WHAT YOU ASKED IT
  -------------------------------------------
  Measured: `wiring --qname` returns the SAME document -- empty implementations,
  empty resolved_at -- for an unregistered INTERFACE and for a CLASS:

      wiring --qname IMicObject      -> {implementations:[], resolved_at:[], event_handlers:[]}
      wiring --qname TABZLoggingSys  -> {implementations:[], resolved_at:[], event_handlers:[]}

  Those are completely different answers. "Nothing registers this interface" is a
  legitimate finding about the wiring; "you asked about a class" is a mistake in
  the question. So the KIND CHECK happens here, against the index, before the
  verb is called at all -- the verb's silence is not evidence.

  DISCLOSE THE INDEX-WIDE TOTAL, ALWAYS (P7)
  -------------------------------------------
  CLIENT holds FOUR registrations in total (all in uClientContainer.pas:41-55)
  against SERVER's 535. On CLIENT, "1 registration" reads as "barely wired" when
  the honest statement is "this index contains 4 registrations in total".
  Following touches-tables' precedent, the index-wide pre-check runs FIRST and
  its numbers go on every chart, not just the empty ones.

  It states the NUMBER and stops. "The client resolves over a pipe" is a
  plausible reason and we have NOT evidenced it from the index (P7b), so it is
  not on the chart. A chart here asserts what it measured.

  event_handlers: the verb returns this third array and it was EMPTY for all 12
  registered interfaces probed on SERVER. It is read and rendered when present
  rather than dropped, so a corpus that populates it is not silently truncated.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Interface,
  [Parameter(Mandatory)][string] $DbPath,
  [string] $OutDir,
  [int]    $MaxRows    = 25,
  [string] $Engine     = '',
  [string] $Dot        = '',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')
$Engine = Resolve-DragLintEngine $Engine   # R2: '' = DRAGLINT_ENGINE, settings.json, installed, shared (Emit-Common)
# Refuse a live corpus DB (see Get-CloneDb): charts run against the frozen clones.
$DbPath = Get-CloneDb $DbPath

# Providers on the left in teal, the interface in blue, consumers on the right in
# amber -- the same left-to-right reading the call charts use.
$PAL = @{
  regBorder   = '#0F766E'; regFill   = '#E2F1EF'; regHdr   = '#0F766E'
  focusBorder = '#3B5BDB'; focusFill = '#EDF2FF'; focusHdr = '#3B5BDB'
  useBorder   = '#B45309'; useFill   = '#FEF6EC'; useHdr   = '#B45309'
  ehBorder    = '#7C3AED'; ehFill    = '#F3EEFF'; ehHdr    = '#7C3AED'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}

Write-Host "wiring: $Interface"

# ---- 1. index-wide pre-check, BEFORE anything else -------------------------------
$pre = Invoke-IndexQuery 'SELECT COUNT(*) AS n, COUNT(DISTINCT interface_name) AS ifaces FROM di_bindings'
$idxRegs   = $(if ($pre.Count) { [int]$pre[0].n } else { 0 })
$idxIfaces = $(if ($pre.Count) { [int]$pre[0].ifaces } else { 0 })
Write-Host "  index has $idxRegs registration(s) over $idxIfaces interface(s)"
if ($idxRegs -eq 0) {
  throw ("wiring: this index has NO DI registrations at all (di_bindings is empty), so no interface in " +
         'it can be shown as wired. Ask the index that holds the container configuration.')
}

# ---- 2. resolve the selection -- the kind check the verb cannot do (N15) ----------
$sel = Resolve-MemberSelection $Interface @('interface') -AllowMissing `
         -Hint 'wiring selects an INTERFACE -- ask hierarchy for a class'
$iname = $(if ($sel) { $sel.Name } else { ($Interface -split '\.')[-1] })

# An interface registered here but DECLARED elsewhere is a real shape -- the same
# one hierarchy handles for RTL types. Accept it, say so, and carry on.
$declaredHere = [bool]$sel
if (-not $declaredHere) {
  $reg = Invoke-IndexQuery "SELECT COUNT(*) AS n FROM di_bindings WHERE interface_name = '$(ConvertTo-SqlText $iname)'"
  $rn = $(if ($reg.Count) { [int]$reg[0].n } else { 0 })
  if ($rn -eq 0) {
    throw ("$Interface is not declared in this index and nothing in it registers that name. " +
           "This index has $idxRegs registration(s) over $idxIfaces interface(s).")
  }
  Write-Host "  selection: $iname is not declared in this index, but $rn registration(s) name it"
} else {
  Write-Host "  selection: $($sel.Qname) (interface) $([IO.Path]::GetFileName($sel.Path)):$($sel.FocusLine)"
}

# ---- 3. the verb ------------------------------------------------------------------
$w = Invoke-EngineJson @('wiring', '--qname', $iname, '--db', $DbPath, '--format', 'json')
$impls    = @($w.implementations)
$resolved = @($w.resolved_at)
$handlers = @($w.event_handlers)

# ---- 4. name the routine each resolution site sits in ------------------------------
# resolved_at gives file+line only, and a bare "file:249" row is a weak thing to
# click. The innermost symbol whose impl range contains the line is the routine
# doing the resolving. Capped rows only, so this stays one small query per shown
# row rather than a scan.
$resTop = Get-TopRanked $resolved $MaxRows 'line'
function Get-SiteOwner([string] $Path, [int] $Line) {
  $rows = Invoke-IndexQuery @"
SELECT s.qualified_name AS q
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE f.path = '$(ConvertTo-SqlText $Path)'
   AND s.impl_start_line IS NOT NULL AND s.impl_end_line IS NOT NULL
   AND s.impl_start_line <= $Line AND s.impl_end_line >= $Line
 ORDER BY s.impl_start_line DESC
 LIMIT 1
"@
  if ($rows.Count) { [string]$rows[0].q } else { '' }
}

$implTop = Get-TopRanked $impls $MaxRows 'line'

Write-Host ("  registrations={0}  resolution sites={1}  event handlers={2}" -f `
            $impls.Count, $resolved.Count, $handlers.Count)

# ---- 5. dot --------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph wiring {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.3; ranksep=1.4; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')

$nodeId = 0; $clusters = 0; $anchored = 0

# LEFT: registrations. The lifetime is an architectural fact, so it is ON the row.
$nodeId++; $clusters++
$lnid = "n$nodeId"
$regCells = New-Object System.Collections.ArrayList
foreach ($im in $implTop.Shown) {
  $anchored++
  [void]$regCells.Add([pscustomobject]@{
    Label = [string]$im.impl; Line = [int]$im.line
    Href  = New-RowHref ([string]$im.file) ([int]$im.line)
    Tip   = "$([string]$im.impl) registered as $iname with lifetime $([string]$im.lifetime) -- $([IO.Path]::GetFileName([string]$im.file)):$($im.line)"
    Note  = [string]$im.lifetime
  })
}
if ($impls.Count -eq 0) {
  # 0 registrations is an ANSWER (N16), not an error -- but it is only readable
  # next to the index-wide total, which is why that total is always present.
  [void]$regCells.Add((New-NoteRow 'nothing in this index registers it'))
  [void]$regCells.Add((New-NoteRow "this index has $idxRegs registration(s) in total"))
}
$d = Get-DisclosureText $implTop.HiddenRows 0 'registrations'
if ($d) { [void]$regCells.Add((New-NoteRow $d)) }
$lports = Add-RowCluster -Sb $sb -Cid "cluster_reg_$nodeId" -Nid $lnid `
            -Title 'registered by' -Subtitle "$($impls.Count) registration$(if ($impls.Count -ne 1) { 's' })" `
            -Rows $regCells.ToArray() -Border $PAL.regBorder -Fill $PAL.regFill -Hdr $PAL.regHdr `
            -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans

# FOCUS: the interface
$nodeId++; $clusters++
$fnid = "n$nodeId"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $iname) </B></FONT></TD></TR>")
if ($declaredHere) {
  $anchored++
  [void]$ftbl.Append("<TR><TD PORT=`"p1`" ALIGN=`"LEFT`" HREF=`"$(New-RowHref $sel.Path $sel.FocusLine)`" TITLE=`"$(ConvertTo-XmlText $sel.Qname)`">")
  [void]$ftbl.Append("<FONT COLOR=`"$($PAL.rowInk)`">$(ConvertTo-XmlText (Get-UnitName $sel.Path))</FONT>")
  [void]$ftbl.Append("  <FONT COLOR=`"$($PAL.lineInk)`" POINT-SIZE=`"12`">:$($sel.FocusLine)</FONT></TD></TR>")
} else {
  Add-DisclosureRow $ftbl 'not declared in this index' $PAL.lineInk
}
Add-DisclosureRow $ftbl "index-wide: $idxRegs registration(s) over $idxIfaces interface(s)" $PAL.lineInk
$lifetimes = @($impls | ForEach-Object { [string]$_.lifetime } | Sort-Object -Unique)
if ($lifetimes.Count -gt 1) {
  Add-DisclosureRow $ftbl "registered with DIFFERENT lifetimes: $($lifetimes -join ', ')" $PAL.lineInk
}
if ($impls.Count -eq 0) {
  Add-DisclosureRow $ftbl 'a registration made in another project index is not visible here' $PAL.lineInk
}
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

# RIGHT: resolution sites
$nodeId++; $clusters++
$rnid = "n$nodeId"
$useCells = New-Object System.Collections.ArrayList
foreach ($rs in $resTop.Shown) {
  $owner = Get-SiteOwner ([string]$rs.file) ([int]$rs.line)
  $anchored++
  [void]$useCells.Add([pscustomobject]@{
    Label = $(if ($owner) { $owner } else { Get-UnitName ([string]$rs.file) })
    Line  = [int]$rs.line
    Href  = New-RowHref ([string]$rs.file) ([int]$rs.line)
    Tip   = "resolves $iname -- $([IO.Path]::GetFileName([string]$rs.file)):$($rs.line)"
    Note  = $(if ($owner) { $null } else { 'not inside a routine body' })
  })
}
if ($resolved.Count -eq 0) { [void]$useCells.Add((New-NoteRow 'no resolution site in this index')) }
$d2 = Get-DisclosureText $resTop.HiddenRows 0 'sites'
if ($d2) { [void]$useCells.Add((New-NoteRow $d2)) }
$rports = Add-RowCluster -Sb $sb -Cid "cluster_use_$nodeId" -Nid $rnid `
            -Title 'resolved at' -Subtitle "$($resolved.Count) site$(if ($resolved.Count -ne 1) { 's' })" `
            -Rows $useCells.ToArray() -Border $PAL.useBorder -Fill $PAL.useFill -Hdr $PAL.useHdr `
            -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans

# event_handlers, only when the corpus actually has them
if ($handlers.Count -gt 0) {
  $nodeId++; $clusters++
  $hnid = "n$nodeId"
  $hCells = New-Object System.Collections.ArrayList
  foreach ($h in $handlers) {
    $hf = [string]$h.file; $hl = [int]$h.line
    if ($hf) {
      $anchored++
      [void]$hCells.Add([pscustomobject]@{
        Label = $(if ($h.name) { [string]$h.name } else { Get-UnitName $hf })
        Line = $hl; Href = New-RowHref $hf $hl
        Tip = "event handler -- $([IO.Path]::GetFileName($hf)):$hl"
      })
    } else {
      [void]$hCells.Add((New-NoteRow ([string]$h)))
    }
  }
  [void](Add-RowCluster -Sb $sb -Cid "cluster_eh_$nodeId" -Nid $hnid `
           -Title 'event handlers' -Subtitle "$($handlers.Count)" -Rows $hCells.ToArray() `
           -Border $PAL.ehBorder -Fill $PAL.ehFill -Hdr $PAL.ehHdr `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans)
  [void]$sb.AppendLine("  $fnid -> $hnid [style=invis];")
}

# edges: registration -> interface -> resolution
[void]$sb.AppendLine('')
foreach ($p in $lports) { [void]$sb.AppendLine("  $p -> ${fnid}:p1 [color=`"$($PAL.regBorder)`"];") }
foreach ($p in $rports) { [void]$sb.AppendLine("  ${fnid}:p1 -> $p [color=`"$($PAL.useBorder)`"];") }
[void]$sb.AppendLine('}')

# ---- 6. lay out -----------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = 'wiring_' + ($iname -replace '[^A-Za-z0-9]', '_')
$lay = Invoke-DotLayout $sb.ToString() $OutDir $base

[pscustomobject]@{
  Dot            = $lay.Dot
  Svg            = $lay.Svg
  Plain          = $lay.Plain
  Png            = $lay.Png
  Pdf            = $lay.Pdf
  Interface      = $iname
  DeclaredHere   = $declaredHere
  Registrations  = $impls.Count
  ResolvedAt     = $resolved.Count
  EventHandlers  = $handlers.Count
  Lifetimes      = ($lifetimes -join ',')
  IndexRegs      = $idxRegs
  IndexIfaces    = $idxIfaces
  Clusters       = $clusters
  ClickTargets   = $lay.Anchors
  Expected       = $anchored
  AllClickable   = ($lay.Anchors -ge $anchored)
}
