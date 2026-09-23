<#
  Emit-EventWiring.ps1 -- the `event-wiring` question, and a NEW TIER: the UI.

  butterfly / deps / who-calls all answer questions about CODE calling CODE.
  This one crosses a boundary none of them touch: the DFM says which control
  fires which handler, and that edge exists nowhere in the Pascal. It is why
  who-calls on an event handler correctly reports zero callers -- the caller is
  the form file.

  SELECTION IS THE FORM CLASS, NOT THE COMPONENT. Component names repeat
  freely across forms (every second form has a `Panel1`), so `-Control` is a
  FILTER applied after the class has scoped the question, never the selector.

  HANDLERS ARE NEVER MATCHED TO COMPONENTS BY NAME. The rows come from the
  `dfm_event` fact. uMain's `Exit2.OnClick` maps to `WindowClose1Execute` --
  a handler whose name has nothing to do with its component. A convention-based
  matcher would either drop that row or attach it to the wrong control, and it
  is far from the only one.

  CAVEAT, rendered as found: `dfm_event` holds ONE value per handler symbol, so
  a handler wired to two controls is reported once, against whichever control
  the fact records. This emitter shows the fact; it does not repair it.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Form,     # form CLASS qname, e.g. uMain.TfrmMAIN
  [Parameter(Mandatory)][string] $DbPath,
  [string] $Control,                        # optional filter, NOT a selector
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

# One new role, this emitter only: the UI tier is a different KIND of thing
# from a caller or a callee, and violet is unused by the other four roles.
$PAL = @{
  uiBorder     = '#7C3AED'; uiFill     = '#F3EEFF'; uiHdr     = '#7C3AED'
  calleeBorder = '#B45309'; calleeFill = '#FEF6EC'; calleeHdr = '#B45309'
  rowInk       = '#1F2933'; lineInk    = '#8A94A6'
}

Write-Host "event-wiring: $Form$(if ($Control) { "  (control: $Control)" })"

# ---- Q1: the handler facts ---------------------------------------------------
$fq = ConvertTo-SqlText $Form
$handlers = Invoke-IndexQuery @"
SELECT sf.dfm_event AS ev, s.name AS handler, s.qualified_name AS qname,
       s.start_line AS decl_line, s.impl_start_line AS impl_line, f.path AS pas
  FROM symbol_facts sf JOIN symbols s ON s.id = sf.symbol_id
  JOIN symbols c ON c.id = s.parent_id
  JOIN files f ON f.id = s.file_id
 WHERE c.qualified_name = '$fq' AND sf.dfm_event IS NOT NULL
 ORDER BY sf.dfm_event
"@ 'event-wiring Q1 (handlers)'

if ($handlers.Count -eq 0) {
  $all = Invoke-IndexQuery 'SELECT COUNT(*) AS n FROM symbol_facts WHERE dfm_event IS NOT NULL'
  $n = if ($all.Count) { $all[0].n } else { 0 }
  throw "no dfm_event facts under $Form (index has $n across all forms) -- is this a form class?"
}
$formEventCount = $handlers.Count

# split the fact at the FIRST dot only: the component name is everything before
# it, and a component name may itself contain dots in a nested-frame path.
$rows = @($handlers | ForEach-Object {
  $parts = @([string]$_.ev -split '\.', 2)
  [pscustomobject]@{
    Comp    = $parts[0]
    Event   = $(if ($parts.Count -gt 1) { $parts[1] } else { '(unknown)' })
    Handler = [string]$_.handler
    Qname   = [string]$_.qname
    Decl    = [int]$_.decl_line
    Impl    = $(if ($_.impl_line) { [int]$_.impl_line } else { [int]$_.decl_line })
    Pas     = [string]$_.pas
  } })

if ($Control) {
  $rows = @($rows | Where-Object { $_.Comp -eq $Control })
  if ($rows.Count -eq 0) {
    throw "control $Control has no dfm_event rows on $Form (the form has $formEventCount)"
  }
}

$pas = $rows[0].Pas
$dfm = [IO.Path]::ChangeExtension($pas, '.dfm')
$unit = Get-UnitName $pas

# ---- Q2/Q3: where the DFM says it ---------------------------------------------
# Both IN-lists are MANDATORY, not an optimisation: Blueprint4.dfm has 516
# dfm-type rows against a hard 200-row cap, and a capped answer is silently
# short rather than an error.
$dq    = ConvertTo-SqlText $dfm
$comps = @($rows | ForEach-Object { $_.Comp } | Sort-Object -Unique)
$hnames = @($rows | ForEach-Object { $_.Handler } | Sort-Object -Unique)

$compLines = Invoke-IndexQuery @"
SELECT sl.owner_name AS comp, sl.start_line AS line
  FROM string_literals sl JOIN files f ON f.id = sl.file_id
 WHERE f.path = '$dq' AND sl.kind = 'dfm-type'
   AND sl.owner_name IN ($(ConvertTo-SqlInList $comps))
 ORDER BY sl.start_line
"@ 'event-wiring Q2 (component lines)'

$evLines = Invoke-IndexQuery @"
SELECT sl.owner_name AS ev, sl.start_line AS line, sl.text AS handler
  FROM string_literals sl JOIN files f ON f.id = sl.file_id
 WHERE f.path = '$dq' AND sl.kind = 'dfm-prop' AND sl.owner_name LIKE 'On%'
   AND sl.text IN ($(ConvertTo-SqlInList $hnames))
 ORDER BY sl.start_line
"@ 'event-wiring Q3 (event assignments)'

# component -> its first declaring line in the DFM
$compAt = @{}
foreach ($c in $compLines) {
  $k = [string]$c.comp
  if (-not $compAt.ContainsKey($k) -or [int]$c.line -lt $compAt[$k]) { $compAt[$k] = [int]$c.line }
}

# The event assignment belongs to the component whose block it sits in, so the
# right row is the FIRST matching assignment at or after the component's line.
$resolved = 0; $fallback = 0
foreach ($r in $rows) {
  $at = $(if ($compAt.ContainsKey($r.Comp)) { $compAt[$r.Comp] } else { -1 })
  $hit = $null
  if ($at -ge 0) {
    $hit = $evLines |
      Where-Object { [string]$_.ev -eq $r.Event -and [string]$_.handler -eq $r.Handler -and [int]$_.line -ge $at } |
      Select-Object -First 1
  }
  if ($hit) {
    Add-Member -InputObject $r -NotePropertyName DfmLine -NotePropertyValue ([int]$hit.line)
    Add-Member -InputObject $r -NotePropertyName DfmExact -NotePropertyValue $true
    $resolved++
  } else {
    # Honest degradation: point at the handler's DECLARATION in the .pas and
    # say so in the tooltip, rather than invent a DFM line.
    Add-Member -InputObject $r -NotePropertyName DfmLine -NotePropertyValue $r.Decl
    Add-Member -InputObject $r -NotePropertyName DfmExact -NotePropertyValue $false
    $fallback++
  }
}

$kinds = @($rows | ForEach-Object { $_.Event } | Sort-Object -Unique)
Write-Host ("  events={0}  handlers={1}  components={2}  event kinds={3}  dfm resolved={4} fallback={5}" -f `
            $rows.Count, @($rows | ForEach-Object { $_.Qname } | Sort-Object -Unique).Count,
            $comps.Count, $kinds.Count, $resolved, $fallback)

# ---- dot ---------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph eventwiring {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.3; ranksep=1.4; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')

$nodeId = 0
$clusters = 0
$leftPort = @{}   # row ordinal -> port

# LEFT: one cluster per EVENT KIND, rows are COMPONENTS, href into the DFM.
$byKind = $rows | Group-Object Event | Sort-Object { $_.Group.Count } -Descending
foreach ($g in $byKind) {
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  $cells = @($g.Group | ForEach-Object {
    [pscustomobject]@{
      Label = $_.Comp
      Line  = $_.DfmLine
      Href  = New-RowHref $(if ($_.DfmExact) { $dfm } else { $pas }) $_.DfmLine
      Tip   = $(if ($_.DfmExact) {
                 "$($_.Comp).$($_.Event) = $($_.Handler)  --  $([IO.Path]::GetFileName($dfm)):$($_.DfmLine)"
               } else {
                 "$($_.Comp).$($_.Event) = $($_.Handler)  --  no matching assignment found in $([IO.Path]::GetFileName($dfm)); pointing at the handler declaration in $([IO.Path]::GetFileName($pas)):$($_.DfmLine)"
               })
      Note  = $(if ($_.DfmExact) { $null } else { 'pas fallback' })
    } })
  $ports = Add-RowCluster -Sb $sb -Cid "cluster_ev_$nodeId" -Nid $nid `
             -Title $g.Name -Subtitle "$($g.Group.Count) control$(if ($g.Group.Count -ne 1) { 's' })" `
             -Rows $cells -Border $PAL.uiBorder -Fill $PAL.uiFill -Hdr $PAL.uiHdr `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
  for ($i = 0; $i -lt $g.Group.Count; $i++) {
    $leftPort[[string]$g.Group[$i].Qname + '|' + $g.Group[$i].Comp + '|' + $g.Group[$i].Event] = $ports[$i]
  }
}

# RIGHT: one cluster, the form UNIT, rows are HANDLER METHODS, href into the .pas.
$nodeId++; $clusters++
$rnid = "n$nodeId"
$handlerRows = @($rows | Sort-Object Handler)
$cells = @($handlerRows | ForEach-Object {
  [pscustomobject]@{
    Label = $_.Handler
    Line  = $_.Impl
    Href  = New-RowHref $pas $_.Impl
    Tip   = "$($_.Qname)  --  $([IO.Path]::GetFileName($pas)):$($_.Impl)"
  } })
$rports = Add-RowCluster -Sb $sb -Cid "cluster_handlers_$nodeId" -Nid $rnid `
            -Title $unit -Subtitle (($Form -split '\.')[-1]) -Rows $cells `
            -Border $PAL.calleeBorder -Fill $PAL.calleeFill -Hdr $PAL.calleeHdr `
            -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
$rightPort = @{}
for ($i = 0; $i -lt $handlerRows.Count; $i++) {
  $rightPort[[string]$handlerRows[$i].Qname + '|' + $handlerRows[$i].Comp + '|' + $handlerRows[$i].Event] = $rports[$i]
}

[void]$sb.AppendLine('')
$edges = 0
foreach ($r in $rows) {
  $k = [string]$r.Qname + '|' + $r.Comp + '|' + $r.Event
  if ($leftPort.ContainsKey($k) -and $rightPort.ContainsKey($k)) {
    [void]$sb.AppendLine("  $($leftPort[$k]) -> $($rightPort[$k]) [color=`"$($PAL.uiBorder)`"];")
    $edges++
  }
}
[void]$sb.AppendLine('}')

# ---- lay out -----------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = (($Form + $(if ($Control) { ".$Control" } else { '' })) -replace '[^A-Za-z0-9]', '_')
$lay  = Invoke-DotLayout $sb.ToString() $OutDir $base

$expected = $rows.Count * 2

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Events       = $rows.Count
  Handlers     = @($rows | ForEach-Object { $_.Qname } | Sort-Object -Unique).Count
  Components   = $comps.Count
  EventKinds   = $kinds.Count
  DfmResolved  = $resolved
  DfmFallback  = $fallback
  Edges        = $edges
  Clusters     = $clusters
  ClickTargets = $lay.Anchors
  Expected     = $expected
  AllClickable = ($lay.Anchors -ge $expected)
}
