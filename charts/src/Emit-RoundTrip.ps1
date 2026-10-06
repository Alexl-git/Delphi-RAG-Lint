<#
  Emit-RoundTrip.ps1 -- the `round-trip` question (the Interface report's trace
  core, spec docs\superpowers\specs\2026-09-27-interface-report-trace-core-design.md).

  From ONE selection to its data anchor (dataset, field, table, column) and then
  both ways through the pipe: WRITE (the dataset's AfterPost handler -> sender ->
  CROSSES -> server dispatch -> handler -> apply -> column -> response) and READ
  (the routine that fills the dataset with the table literal -> CROSSES -> server
  -> query -> back). Three clones, queried SEPARATELY: -DbPath (CLIENT),
  -ServerDbPath (SERVER), -SqlDbPath (the SQL scripts). Rows are zoned by FILE
  PATH, never by which index answered (COMMON is in both).

  Output is the trace, trace.dlgraph, in Form A (charts\form-a-grammar-spec.md
  section 8): 7-bit ASCII, CRLF, every step anchored, a grade only when not
  certain, STOPS for every hop the walk cannot make, END TRACE recomputed -- AND
  (R5, 2026-10-06) its CHART, drawn from the SAME bytes: Read-FormA of the text,
  through Trace.Chart.ps1's ConvertTo-TraceChart, laid out once by Invoke-DotLayout
  (.dot/.svg/.png/.pdf/.plain). This run's outputs are REMOVED FIRST, before the
  walk, so a refusal (a stale file: AC-14) leaves neither an old text nor an old
  picture behind (A-R5-STALE). If dot fails the text is still delivered, the
  result carries ChartError, and no partial picture is left (owner answer 3).

  THE SHIM AND THE ASKS. The index holds tokens, not branches: conditions are
  quoted from FRESH source by Trace.Walk's Get-GuardCondition (E1). Dispatch is
  the first cross-unit bound call after the constant (E2); event wiring is a
  same-line name match (E3); the UPDATE / SELECT texts live in FIB$ rows the
  clones do not hold (E4); the accessor's field read is unbound (INBOX-in-class-
  field-reads-unbound); a member call on a unit-level var is resolved through the
  var's declared type while it is unbound (receiver-typed-calls, filed as INBOX-charts-receiver-typed-calls-unbound;
  resolver 1.11 RB-1 binds the GDatasetsDef / GBroadcastServer calls, so those hops are now certain);
  a field's declared type is matched to its class by name (type-use-binding, INBOX-charts-type-use-unbound).
  Every such step names its ask; a hop that is the walk's own inference names none (final-review M2).

  WRITE -> SERVER -> DATABASE -> RESPONSE (Task 5) is one section per tier; READ
  (Task 6) is one section whose steps carry their actor word (SERVER / DATABASE /
  CLIENT after the crossing). ALSO is DERIVED (AC-10): the other wirings on the
  dataset, the other callers of a sender that serves only the anchor's table, and
  the other fill lines -- every route the index holds minus the ones traced.

  A CALCULATED anchor field (Trace.Walk Part 6: an OnCalcFields handler writes it) stops at the anchor
  saying so, with the handler's guards verbatim, and a DERIVED section (grammar spec 8.5) offers each
  source field the computation reads, with a REGENERATE command that traces it instead.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][Alias('Qname', 'Control', 'Field')][string] $Target,
  [Parameter(Mandatory)][string] $DbPath,
  [Parameter(Mandatory)][string] $ServerDbPath,
  [Parameter(Mandatory)][string] $SqlDbPath,
  [string]    $OutDir,
  [int]       $Depth = 4,
  [hashtable] $SourceOverride,
  [string]    $BoundaryPattern = 'Pipes.%|uPipe%|uBroadcast%',
  # the chart's size caps (Trace.Chart.ps1): Also / Rows / Nodes, each optional
  [hashtable] $ChartCaps = @{},
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')
. (Join-Path $PSScriptRoot 'Trace.FormA.ps1')
. (Join-Path $PSScriptRoot 'Trace.Walk.ps1')
. (Join-Path $PSScriptRoot 'Trace.Chart.ps1')

$DbPath       = Get-CloneDb $DbPath
$ServerDbPath = Get-CloneDb $ServerDbPath
$SqlDbPath    = Get-CloneDb $SqlDbPath
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
New-Item -ItemType Directory -Force $OutDir | Out-Null
# R5 (A-R5-STALE): this run's outputs go FIRST -- its own names and the names the bundler gives them in a bundle
# folder (trace.dlgraph, graph.*) -- so a refusal below cannot leave an earlier run's text or picture to be found
$base = 'roundtrip_' + ($Target -replace '[^A-Za-z0-9]', '_')
$chartOut = @('dot', 'svg', 'png', 'pdf', 'plain')
foreach ($f in @(@("$base.dlgraph", 'trace.dlgraph') + @($chartOut | ForEach-Object { "$base.$_"; "graph.$_" }))) {
  $fp = Join-Path $OutDir $f
  if (Test-Path -LiteralPath $fp) { Remove-Item -LiteralPath $fp -Force }
}

Write-Host "round-trip: $Target"

# Every Emit-Common query reads $DbPath from the CALLER's scope: this function's
# local IS the rebinding, and the scriptblock runs in its child scope. The one
# proof the gate pins: file counts differ between the two clones (A-RT5-ONDB).
function Invoke-OnDb([string] $Db, [scriptblock] $Body) { $DbPath = $Db; & $Body }

$sqlSet = Get-SqlTableSet $SqlDbPath
if ($sqlSet.TableCount -eq 0) { throw "round-trip: $SqlDbPath is not a SQL index (0 sql_table symbols) -- -SqlDbPath takes the SQL-script clone" }
$cliName = [IO.Path]::GetFileNameWithoutExtension($DbPath) -replace '^CLIENT-', ''
$srvName = [IO.Path]::GetFileNameWithoutExtension($ServerDbPath) -replace '^SERVER-', ''
$likes = Get-BoundaryLikes $BoundaryPattern
# final-review M3: AS OF is each index's OWN last-indexed stamp (schema_meta indexed_at_unix), in the order the
# INDEX line names them, UTC to the minute -- not a file date. An index without the stamp says `unstamped`.
function Get-IndexStamp([string] $Db) {
  $r = Invoke-OnDb $Db { Invoke-IndexQuery "SELECT value AS v FROM schema_meta WHERE key = 'indexed_at_unix'" }
  $(if ($r.Count -and "$($r[0].v)" -match '^\d+$') { [DateTimeOffset]::FromUnixTimeSeconds([long]$r[0].v).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm'Z'") } else { 'unstamped' })
}
$asOf = (@($DbPath, $ServerDbPath, $SqlDbPath) | ForEach-Object { Get-IndexStamp $_ }) -join '/'
# the command that traces a target on these three indexes at this depth: the header's REGENERATE, and each DERIVED row's (8.5).
# Calc-field fix round 1 (M5): RUNNABLE as written -- the call operator and the bundler's ABSOLUTE path (a bare
# `New-DiagramArtifact.ps1 ...` is not found by PowerShell from any other folder)
$bundler = (Join-Path $PSScriptRoot 'New-DiagramArtifact.ps1') -replace "'", "''"
# fix round 2 (R2-6): the -Target value single-quoted (a target may carry `$`), any quote in it doubled
function Get-RegenerateCommand([string] $For) { "& '$bundler' -Question round-trip -Target '$($For -replace "'", "''")' -DbPath `"$DbPath`" -ServerDbPath `"$ServerDbPath`" -SqlDbPath `"$SqlDbPath`" -Depth $Depth" }
$regen = Get-RegenerateCommand $Target

# ---- 1. the anchor -------------------------------------------------------------------
$A = Resolve-TraceAnchor $Target $sqlSet $SourceOverride
if ($A.StaleFile) {
  throw "round-trip: $([IO.Path]::GetFileName($A.StaleFile)) differs from the indexed copy (sha256) -- refusing to follow the anchor chain through it. Reindex the project, then re-run."
}
$name = $(if ($A.TableColumn) { $A.TableColumn } else { $Target })
# calc-field brief: a CALCULATED anchor (Trace.Walk Part 6) stops with its guards and offers its source fields
$calc = $(if ($A.Calc -and $A.Calc.Kind -eq 'calculated') { New-CalcFieldItems $A.Calc ${function:Get-RegenerateCommand} } else { $null })
# fix round 1 (I3): a trace that STOPS at its anchor reaches nothing, so its title claims no reach -- and a calculated
# anchor says why in the title (8.2)
$title = $(if ($calc) { "Why $Target cannot be traced -- it is calculated" } elseif ($A.Stop) { "Why $Target cannot be traced" } else { "How $name reaches $Target and goes back" })
$T = New-Trace $name $title $Target "$cliName + $srvName + SQL" $asOf $regen 'client -> pipe -> server -> database'
$secA = Add-TraceSection $T 'ANCHOR'
foreach ($i in $A.Items) { [void]$secA.Items.Add($i) }
$stopAnchor = $(if ($A.StopAnchor -and $A.StopAnchor -ne 'unknown:0') { $A.StopAnchor } elseif ($A.Items.Count) { $A.Items[-1].Anchor } else { 'index:0' })
if ($calc) {
  [void]$secA.Items.Add($calc.Stop)
} elseif ($A.Stop) {
  # the resolver's reason is GENERATED text: made safe where the writer refuses, never truncated (T3-M2)
  [void]$secA.Items.Add((New-TraceStep 'stops' (ConvertTo-TraceStopText $A.Stop) $stopAnchor))
}
# DERIVED (8.5): only for a calculated anchor -- its lead-in note, then one numbered row per source field, each a
# true anchored fact (counted in steps, never unresolved) carrying the command that traces that field instead
$secDv = $null
if ($calc) {
  $secDv = Add-TraceSection $T 'DERIVED'
  $secDv.Note = ConvertTo-TraceNoteText $calc.Note
  foreach ($r in $calc.Rows) { [void]$secDv.Items.Add($r) }
}

$Ctx = @{ Table = $A.Table; Column = $A.Column; TableColumn = $A.TableColumn; DataSet = $A.DataSet; SqlSet = $sqlSet; SourceOverride = $SourceOverride
          Likes = $likes; NearIndex = $cliName; FarIndex = $srvName; Seen = @{} }
$write = 0; $read = 0; $also = 0
$secW = Add-TraceSection $T 'WRITE'; $secS = Add-TraceSection $T 'SERVER'; $secD = Add-TraceSection $T 'DATABASE'; $secR = Add-TraceSection $T 'RESPONSE'
$secRd = Add-TraceSection $T 'READ'; $secAl = Add-TraceSection $T 'ALSO'
$alsoRows = New-Object System.Collections.ArrayList
# fix round 1 (I3, the T6-R2 mechanism): after an anchor STOPS no later section is walked. Each one says so in a
# GENERATED section note -- not a STOPS, not counted unresolved -- so an empty WRITE never reads as "no write path".
# The anchor's STOPS is the last ANCHOR item, and ANCHOR is the first section, so its number is the ANCHOR count.
if ($A.Stop) {
  $notWalked = ConvertTo-TraceNoteText ("not walked: the trace stopped at [{0:00}]" -f $secA.Items.Count)
  foreach ($s in @($secW, $secS, $secD, $secR, $secRd, $secAl)) { $s.Note = $notWalked }
}

# final-review I2: a DIRECTION that stops after the anchor resolved. Its STOPS ends it, so the tiers it did not
# reach are not walked and say so -- the same generated section note (T6-R2: not a STOPS, not unresolved),
# naming the STOPS by the number it gets when written: WRITE stops (no wiring, no crossing) -> SERVER, DATABASE
# and RESPONSE; the server side stops (no dispatch arm, no one implementation) -> DATABASE, and RESPONSE claims no
# response. READ is one section, so a READ server stop skips its DATABASE steps. $WStop / $RStop: the STOPS that
# ended each direction ($null: walked through to the database tier); the TITLE claims only the walked ones.
$WStop = $null; $RStop = $null
$notes = New-Object System.Collections.ArrayList
function Add-NotWalked($Sec, $Stop, [string] $Dir) { [void]$notes.Add([pscustomobject]@{ Sec = $Sec; Stop = $Stop; Dir = $Dir }) }
# the number Write-FormA will give $Item: its place across the sections, counted after every merge
function Get-TraceItemNumber($Trace, $Item) {
  $n = 0
  foreach ($s in $Trace.Sections) { foreach ($i in $s.Items) { $n++; if ([object]::ReferenceEquals($i, $Item)) { return $n } } }
  throw "Get-TraceItemNumber: the item is not in the trace"
}
$unknownRsp = 'unknown, no server handler was reached'

if (-not $A.Stop) {
  # ---- 2. WRITE: the preferred event wiring on the dataset, its handler, down to the send ------
  # final-review I4: Get-EventWiring orders by write preference (AfterPost first, a delete last), then line
  $wiring = Get-EventWiring $A.DataSet
  if (-not $wiring.Count) {
    $WStop = New-TraceStep 'stops' "no $($script:RtEvents -join '/') handler is wired on $($A.DataSet.Name) in $(Get-UnitName $A.DataSet.File)" (Get-TraceAnchorText $A.DataSet.File $A.DataSet.Line) '' '' '' 'E3'
    [void]$secW.Items.Add($WStop)
    foreach ($s in @($secS, $secD, $secR)) { Add-NotWalked $s $WStop 'write' }
  } else {
    $w0 = $wiring[0]
    [void]$secW.Items.Add((New-TraceStep 'step' "FIRES $($A.DataSet.Name).$($w0.Event) -> $($w0.Handler)" (Get-TraceAnchorText $A.DataSet.File $w0.Line) $w0.Grade $w0.Routine 'handler named on the wiring line' 'E3'))
    $visited = @{}
    $sub = Walk-Routine $w0.HandlerId $Depth $visited $Ctx
    # fix round 1: the handler runs ON the event -- the routine that wires it (Create) does not call it
    $entry = New-TraceStep 'step' "CALLS $($w0.HandlerShort)" (Get-TraceAnchorText $w0.HandlerPath $w0.HandlerImpl) '' '' "on $($A.DataSet.Name).$($w0.Event), wired at :$($w0.Line) in $($w0.Routine)"
    foreach ($c in $sub.Conds) { [void]$entry.Children.Add($c) }
    $clientItems = @($entry) + @($sub.Items)
    $xi = [array]::IndexOf(@($clientItems | ForEach-Object { $_.Kind }), 'crosses')
    if ($xi -lt 0) {
      foreach ($i in $clientItems) { [void]$secW.Items.Add($i) }
      $WStop = New-TraceStep 'stops' "$($w0.HandlerShort) never reaches a transport call carrying a protocol constant within $Depth call levels" $clientItems[-1].Anchor '' $w0.HandlerShort '' ''
      [void]$secW.Items.Add($WStop)
      foreach ($s in @($secS, $secD, $secR)) { Add-NotWalked $s $WStop 'write' }
    } else {
      for ($k = 0; $k -le $xi; $k++) { [void]$secW.Items.Add($clientItems[$k]) }
      $xing = $clientItems[$xi]
      # ---- 3. SERVER, on the other index ------------------------------------------------
      $srv = Invoke-OnDb $ServerDbPath { Get-ServerHandling $xing.Command $Ctx $Depth }
      if ($srv.Contract) { [void]$xing.Children.Add((New-TraceFacet 'CONTRACT' $srv.Contract.Text $srv.Contract.Anchor 'the far side, from the counterpart index')) }
      foreach ($i in $srv.Items) { [void]$secS.Items.Add($i) }
      # ---- 4. DATABASE, still on the SERVER index: its routine facts and its fb_datasets count (P15) --
      # final-review I2: only below a server handler that was walked -- a list holding just the server's STOPS
      # has no statement and no apply to name
      if ($srv.Walked) {
        $dbItems = Invoke-OnDb $ServerDbPath { Get-DatabaseSteps $srv.Items $Ctx 'write' $sqlSet $SourceOverride }
        foreach ($i in $dbItems) { [void]$secD.Items.Add($i) }
      } else { $WStop = $srv.Stop; Add-NotWalked $secD $srv.Stop 'write' }
      # ---- 5. RESPONSE: back across, then the client's remaining lines --------------------
      # anchored at the SAME line as the request: the one ExecuteCommand call sends the request
      # and returns the response frame (ruling P4 -- two CROSSES steps at one anchor is correct)
      $back = New-TraceStep 'crosses' 'process boundary' $xing.Anchor '' $xing.Routine 'the response frame'
      [void]$back.Children.Add((New-TraceFacet 'FROM' $srvName '' 'server index'))
      [void]$back.Children.Add((New-TraceFacet 'TO' $cliName '' 'client index'))
      [void]$back.Children.Add((New-TraceFacet 'WITH' $(if (-not $srv.Walked) { $unknownRsp } elseif ($srv.Responses.Count) { $srv.Responses -join ' or ' } else { 'no rsp* constant read in the handler' }) $xing.Anchor ''))
      [void]$secR.Items.Add($back)
      for ($k = $xi + 1; $k -lt $clientItems.Count; $k++) { [void]$secR.Items.Add($clientItems[$k]) }
    }
    # the other wirings converge on the same sender: ALSO (Task 6 derives the rest)
    foreach ($w in @($wiring | Select-Object -Skip 1)) {
      [void]$alsoRows.Add((New-TraceStep 'step' "FIRES $($A.DataSet.Name).$($w.Event) -> $($w.Handler)" (Get-TraceAnchorText $A.DataSet.File $w.Line) $w.Grade $w.Routine 'another wiring on the same dataset' 'E3'))
    }
  }
  # T5-R1: one OMITS disclosure per section, whichever routines the walk left them in
  foreach ($sec in @($secW, $secS, $secD, $secR)) { Merge-TraceOmits $sec }
  $write = $secW.Items.Count + $secS.Items.Count + $secD.Items.Count + $secR.Items.Count
  # ---- 6. READ: the first fill route, its callee to the send, the server, and back -----------
  # One section; the actor word says which side a step runs on (the WRITE half has a section per tier).
  # Each route walks with its own Seen (Get-FillRoutes): the READ path runs the FIB$ reads WRITE showed.
  $routes = Get-FillRoutes $A.DataSet $Ctx $Depth
  if (-not $routes.Count) {
    $RStop = New-TraceStep 'stops' (ConvertTo-TraceStopText "no bound call on a line naming '$($A.Table)' beside $($A.DataSet.Name) in $(Get-UnitName $A.DataSet.File) reaches a transport call carrying a protocol constant within $Depth call levels") (Get-TraceAnchorText $A.DataSet.File $A.DataSet.Line)
    [void]$secRd.Items.Add($RStop)
  } else {
    $r0 = $routes[0]
    [void]$secRd.Items.Add((New-TraceStep 'step' "LOADS $($A.DataSet.Name) VIA $($r0.TargetShort)$($r0.Lits)" (Get-TraceAnchorText $A.DataSet.File $r0.Line) '' $r0.Routine 'the fill call carrying the table literal'))
    $entry = New-TraceStep 'step' "CALLS $($r0.TargetShort)$($r0.Lits)" (Get-TraceAnchorText $r0.TargetPath $r0.TargetImpl) '' $r0.Routine "from :$($r0.Line)"
    foreach ($c in $r0.Walk.Conds) { [void]$entry.Children.Add($c) }
    $ri = @($entry) + @($r0.Walk.Items)
    $xi = [array]::IndexOf(@($ri | ForEach-Object { $_.Kind }), 'crosses')
    for ($k = 0; $k -le $xi; $k++) { [void]$secRd.Items.Add($ri[$k]) }
    $xr = $ri[$xi]
    # the far side on the SERVER index, then its DATABASE facts, still on the SERVER index (AC-9)
    $srvR = Invoke-OnDb $ServerDbPath { Get-ServerHandling $xr.Command $r0.Ctx $Depth }
    if ($srvR.Contract) { [void]$xr.Children.Add((New-TraceFacet 'CONTRACT' $srvR.Contract.Text $srvR.Contract.Anchor 'the far side, from the counterpart index')) }
    # final-review I2: no DATABASE steps below a server side that stopped (READ is one section: nothing to note)
    $dbR = @()
    if ($srvR.Walked) { $dbR = Invoke-OnDb $ServerDbPath { Get-DatabaseSteps $srvR.Items $r0.Ctx 'read' $sqlSet $SourceOverride } } else { $RStop = $srvR.Stop }
    foreach ($i in $dbR) { $i.Actor = 'DATABASE' }
    # fix round 1 (M4): the DATABASE steps stand right after the SERVER step that RUNS the query (the stop's
    # After), in source order -- not after the whole server walk
    $runAt = @($dbR | Where-Object { $_.PSObject.Properties['After'] -and $_.After } | ForEach-Object { $_.After } | Select-Object -First 1)
    $dbPlaced = $false
    foreach ($i in $srvR.Items) {
      $i.Actor = 'SERVER'; [void]$secRd.Items.Add($i)
      if (-not $dbPlaced -and $runAt.Count -and [object]::ReferenceEquals($i, $runAt[0])) { foreach ($d in $dbR) { [void]$secRd.Items.Add($d) }; $dbPlaced = $true }
    }
    if (-not $dbPlaced) { foreach ($d in $dbR) { [void]$secRd.Items.Add($d) } }
    # the rows come back on the SAME ExecuteCommand call (ruling P4: request and response share its anchor)
    $backR = New-TraceStep 'crosses' 'process boundary' $xr.Anchor '' $xr.Routine 'the rows come back'
    [void]$backR.Children.Add((New-TraceFacet 'FROM' $srvName '' 'server index'))
    [void]$backR.Children.Add((New-TraceFacet 'TO' $cliName '' 'client index'))
    [void]$backR.Children.Add((New-TraceFacet 'WITH' $(if (-not $srvR.Walked) { $unknownRsp } elseif ($srvR.Responses.Count) { $srvR.Responses -join ' or ' } else { 'no rsp* constant read in the handler' }) $xr.Anchor ''))
    [void]$secRd.Items.Add($backR)
    for ($k = $xi + 1; $k -lt $ri.Count; $k++) { $ri[$k].Actor = 'CLIENT'; [void]$secRd.Items.Add($ri[$k]) }
    Merge-TraceOmits $secRd
  }
  # ---- ALSO (AC-10, ruling P10): every other route to the anchor the index holds, minus the traced ones --
  # the other wirings (above), the other callers of a sender that serves only this table, the other fill lines
  # fix round 1: the senders are each direction's first CLIENT crossing (M1), and every routine on the client
  # path before it is already on the page (Important 2) -- with each listed wiring's handler, never "another caller"
  $traced = Get-TracedRouteIds (@(, @($secW.Items)) + @(, @($secRd.Items)))
  $skipIds = @(@($traced.Callers) + @($wiring | ForEach-Object { [int]$_.HandlerId }) | Select-Object -Unique)
  foreach ($r in (Get-AlsoRoutes $traced.Senders $skipIds $Ctx)) { [void]$alsoRows.Add($r) }
  foreach ($r in @($routes | Select-Object -Skip 1)) {
    [void]$alsoRows.Add((New-TraceStep 'step' "LOADS $($A.DataSet.Name) VIA $($r.TargetShort)$($r.Lits)" (Get-TraceAnchorText $A.DataSet.File $r.Line) '' $r.Routine 'another fill route'))
  }
  foreach ($r in $alsoRows) { [void]$secAl.Items.Add($r) }
  # T6-R2: an empty ALSO is not a hop that failed -- no STOPS, nothing unresolved; the section says so in a note
  if (-not $secAl.Items.Count) { $secAl.Note = 'no other route to this anchor in the index' }
  $read = $secRd.Items.Count; $also = $secAl.Items.Count
}

# ---- 7. write it -- LAST, so a refusal above leaves nothing behind -------------------------
# final-review I2: the not-walked notes and the title, now that every step has its final number
foreach ($x in $notes) { $x.Sec.Note = ConvertTo-TraceNoteText ("not walked: the {0} direction stopped at [{1:00}]" -f $x.Dir, (Get-TraceItemNumber $T $x.Stop)) }
if (-not $A.Stop -and ($WStop -or $RStop)) {
  $nW = $(if ($WStop) { Get-TraceItemNumber $T $WStop } else { 0 }); $nR = $(if ($RStop) { Get-TraceItemNumber $T $RStop } else { 0 })
  $T.Title = $(if ($WStop -and $RStop) { "Where the trace between $Target and $name stops (steps $([Math]::Min($nW, $nR)) and $([Math]::Max($nW, $nR)))" }
               elseif ($WStop) { "How $name reaches $Target (the way back stops at step $nW)" }
               else { "How $Target goes back to $name (the way there stops at step $nR)" })
}
$text = Write-FormA $T
$path = Join-Path $OutDir "$base.dlgraph"
$c = Get-TraceCounts $T
# DOC-R1 (2026-09-28): each ` @<file>:<line>` anchor's FULL path, so the bundle page can make the anchor a
# draglint:// link into the IDE. The text keeps the bare leaf (grammar spec section 8); the path is looked up
# in the three indexes and kept only when they name exactly ONE path for the leaf -- an ambiguous leaf stays text.
$leaves = @([regex]::Matches($text, ' @([A-Za-z0-9_$.\-]+\.(?:pas|dfm|dpr|inc|sql)):[1-9]\d*', 'IgnoreCase') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
$anchorPaths = @{}
if ($leaves.Count) {
  $leafWhere = ($leaves | ForEach-Object { "path LIKE '%\$($_ -replace "'", "''")'" }) -join ' OR '
  $pathsOf = @{}
  foreach ($db in @($DbPath, $ServerDbPath, $SqlDbPath)) {
    foreach ($row in (Invoke-OnDb $db { Invoke-IndexQuery "SELECT DISTINCT path AS p FROM files WHERE $leafWhere" 'round-trip anchor paths' })) {
      $leaf = [IO.Path]::GetFileName([string]$row.p)
      if ($leaves -notcontains $leaf) { continue }
      if (-not $pathsOf.ContainsKey($leaf)) { $pathsOf[$leaf] = @{} }
      $pathsOf[$leaf][([string]$row.p).ToLowerInvariant()] = [string]$row.p
    }
  }
  foreach ($k in $pathsOf.Keys) { if ($pathsOf[$k].Count -eq 1) { $anchorPaths[$k] = @($pathsOf[$k].Values)[0] } }
}
# ---- 8. the chart (R5): drawn from Read-FormA of the bytes just written, never from a second walk ------------------
# The in-memory model is drawn too, ONLY so the gate can prove the two give the same dot (A-R5-FROMTEXT). A renderer
# throw (R19: a section or lane it does not know) is loud and fails the run; a dot failure does not (owner answer 3):
# the text is delivered, ChartError says why, and every chart output is removed so no partial picture remains.
$chart = ConvertTo-TraceChart (Read-FormA $text) $anchorPaths $ChartCaps
$chartModelDot = (ConvertTo-TraceChart $T $anchorPaths $ChartCaps).Dot
$lay = $null; $chartError = ''
try { $lay = Invoke-DotLayout $chart.Dot $OutDir $base }
catch {
  $chartError = $_.Exception.Message
  foreach ($x in $chartOut) { $fp = Join-Path $OutDir "$base.$x"; if (Test-Path -LiteralPath $fp) { Remove-Item -LiteralPath $fp -Force } }
  Write-Host "round-trip: the chart could not be drawn -- $chartError"
}
# the text LAST, so a refusal anywhere above leaves nothing behind
[IO.File]::WriteAllText($path, $text, (New-Object Text.ASCIIEncoding))
Write-Host $text
$proof = "$((Invoke-IndexQuery 'SELECT COUNT(*) AS n FROM files')[0].n)/$((Invoke-OnDb $ServerDbPath { (Invoke-IndexQuery 'SELECT COUNT(*) AS n FROM files')[0].n }))"
Write-Host ("  anchor={0}  steps={1}  conditions={2}  crossings={3}  unresolved={4}  write/read/also={5}/{6}/{7}" -f $name, $c.Steps, $c.Conditions, $c.Crossings, $c.Unresolved, $write, $read, $also)

[pscustomobject]@{
  Trace        = $path
  Text         = $text
  # R5: the chart, laid out from the same text ($null each when dot failed -- ChartError says why)
  Dot          = $(if ($lay) { $lay.Dot } else { $null })
  Svg          = $(if ($lay) { $lay.Svg } else { $null })
  Plain        = $(if ($lay) { $lay.Plain } else { $null })
  Png          = $(if ($lay) { $lay.Png } else { $null })
  Pdf          = $(if ($lay) { $lay.Pdf } else { $null })
  ChartError   = $chartError
  ChartNodes   = $chart.Manifest.Nodes
  ChartManifest = $chart.Manifest
  ChartModelDot = $chartModelDot
  Title        = $T.Title
  # final-review I2: each section's generated note, `<SECTION>=<note>` (empty sections only)
  Notes        = (@($T.Sections | Where-Object { $_.Note } | ForEach-Object { "$($_.Name)=$($_.Note)" }) -join ' | ')
  Anchor       = $name
  DataSet      = $(if ($A.DataSet) { $A.DataSet.Name } else { '' })
  Table        = $A.Table
  Column       = $A.Column
  TableColumn  = $A.TableColumn
  Stop         = $A.Stop
  Steps        = $c.Steps
  Conditions   = $c.Conditions
  Crossings    = $c.Crossings
  Unresolved   = $c.Unresolved
  WriteSteps   = $write
  ReadSteps    = $read
  AlsoSteps    = $also
  Also         = @($secAl.Items | ForEach-Object { $_.Text })
  # calc-field brief: the DERIVED section of a calculated anchor -- its lead-in note and each row as
  # `<text> => <target>` (the target is '' for a value the walk cannot map)
  DerivedNote  = $(if ($secDv) { $secDv.Note } else { '' })
  Derived      = @($(if ($secDv) { $secDv.Items | ForEach-Object { $ri = $_; "$($ri.Text) => $((@($ri.Children | Where-Object { $_.Kind -eq 'facet' -and $_.Head -eq 'REGENERATE' } | ForEach-Object { if ($_.Text -match "-Target '((?:[^']|'')*)'") { $Matches[1] -replace "''", "'" } }) -join ''))" } }))
  DerivedCommands = @($(if ($secDv) { $secDv.Items | ForEach-Object { $_.Children | Where-Object { $_.Kind -eq 'facet' -and $_.Head -eq 'REGENERATE' } | ForEach-Object { $_.Text } } }))
  Sections     = (@($T.Sections | ForEach-Object { $_.Name }) -join ',')
  OnDbProof    = $proof
  ClickTargets = (Get-TraceAnchors $T)
  Expected     = (Get-TraceAnchors $T)
  # P14: computed from the written step lines, never assumed
  AllClickable = (@(Get-TraceUnclickable $text).Count -eq 0)
  # DOC-R1: anchor leaf -> the one full path the indexes hold for it (the bundle page links these)
  AnchorPaths  = $anchorPaths
}
