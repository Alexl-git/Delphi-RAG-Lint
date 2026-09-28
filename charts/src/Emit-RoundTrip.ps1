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

  Output is ONE document, trace.dlgraph, in Form A (charts\form-a-grammar-spec.md
  section 8): 7-bit ASCII, CRLF, every step anchored, a grade only when not
  certain, STOPS for every hop the walk cannot make, END TRACE recomputed. It is
  written LAST -- a refusal (a stale file: AC-14) leaves nothing behind.

  THE SHIM AND THE ASKS. The index holds tokens, not branches: conditions are
  quoted from FRESH source by Trace.Walk's Get-GuardCondition (E1). Dispatch is
  the first cross-unit bound call after the constant (E2); event wiring is a
  same-line name match (E3); the UPDATE / SELECT texts live in FIB$ rows the
  clones do not hold (E4); the accessor's field read is unbound (INBOX-in-class-
  field-reads-unbound); a member call on a unit-level var is resolved through the
  var's declared type (receiver-typed-calls, filed as INBOX-charts-receiver-typed-calls-unbound).
  Every such step names its ask.

  This task (5) walks WRITE -> SERVER -> DATABASE -> RESPONSE. READ is a single
  placeholder STOPS and ALSO holds only the other wirings on the dataset; Task 6
  replaces both.
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
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')
. (Join-Path $PSScriptRoot 'Trace.FormA.ps1')
. (Join-Path $PSScriptRoot 'Trace.Walk.ps1')

$DbPath       = Get-CloneDb $DbPath
$ServerDbPath = Get-CloneDb $ServerDbPath
$SqlDbPath    = Get-CloneDb $SqlDbPath
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
New-Item -ItemType Directory -Force $OutDir | Out-Null

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
$asOf = (Get-Item $DbPath).LastWriteTimeUtc.ToString('yyyy-MM-dd')
$regen = "New-DiagramArtifact.ps1 -Question round-trip -Target $Target -DbPath `"$DbPath`" -ServerDbPath `"$ServerDbPath`" -SqlDbPath `"$SqlDbPath`" -Depth $Depth"

# ---- 1. the anchor -------------------------------------------------------------------
$A = Resolve-TraceAnchor $Target $sqlSet $SourceOverride
if ($A.StaleFile) {
  throw "round-trip: $([IO.Path]::GetFileName($A.StaleFile)) differs from the indexed copy (sha256) -- refusing to follow the anchor chain through it. Reindex the project, then re-run."
}
$name = $(if ($A.TableColumn) { $A.TableColumn } else { $Target })
$T = New-Trace $name "How $name reaches $Target and goes back" $Target "$cliName + $srvName + SQL" $asOf $regen 'client -> pipe -> server -> database'
$secA = Add-TraceSection $T 'ANCHOR'
foreach ($i in $A.Items) { [void]$secA.Items.Add($i) }
$stopAnchor = $(if ($A.StopAnchor -and $A.StopAnchor -ne 'unknown:0') { $A.StopAnchor } elseif ($A.Items.Count) { $A.Items[-1].Anchor } else { 'index:0' })
if ($A.Stop) {
  # the resolver's reason is GENERATED text: made safe where the writer refuses, never truncated (T3-M2)
  [void]$secA.Items.Add((New-TraceStep 'stops' (ConvertTo-TraceStopText $A.Stop) $stopAnchor))
}

$Ctx = @{ Table = $A.Table; Column = $A.Column; TableColumn = $A.TableColumn; DataSet = $A.DataSet; SqlSet = $sqlSet; SourceOverride = $SourceOverride
          Likes = $likes; NearIndex = $cliName; FarIndex = $srvName; Seen = @{} }
$write = 0; $read = 0; $also = 0
$secW = Add-TraceSection $T 'WRITE'; $secS = Add-TraceSection $T 'SERVER'; $secD = Add-TraceSection $T 'DATABASE'; $secR = Add-TraceSection $T 'RESPONSE'
$secRd = Add-TraceSection $T 'READ'; $secAl = Add-TraceSection $T 'ALSO'
$alsoRows = New-Object System.Collections.ArrayList

if (-not $A.Stop) {
  # ---- 2. WRITE: the first event wiring on the dataset, its handler, down to the send ------
  $wiring = Get-EventWiring $A.DataSet
  if (-not $wiring.Count) {
    [void]$secW.Items.Add((New-TraceStep 'stops' "no $($script:RtEvents -join '/') handler is wired on $($A.DataSet.Name) in $(Get-UnitName $A.DataSet.File)" (Get-TraceAnchorText $A.DataSet.File $A.DataSet.Line) '' '' '' 'E3'))
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
      [void]$secW.Items.Add((New-TraceStep 'stops' "$($w0.HandlerShort) never reaches a transport call carrying a protocol constant within $Depth call levels" $clientItems[-1].Anchor '' $w0.HandlerShort '' ''))
    } else {
      for ($k = 0; $k -le $xi; $k++) { [void]$secW.Items.Add($clientItems[$k]) }
      $xing = $clientItems[$xi]
      # ---- 3. SERVER, on the other index ------------------------------------------------
      $srv = Invoke-OnDb $ServerDbPath { Get-ServerHandling $xing.Command $Ctx $Depth }
      if ($srv.Contract) { [void]$xing.Children.Add((New-TraceFacet 'CONTRACT' $srv.Contract.Text $srv.Contract.Anchor 'the far side, from the counterpart index')) }
      foreach ($i in $srv.Items) { [void]$secS.Items.Add($i) }
      # ---- 4. DATABASE, still on the SERVER index: its routine facts and its fb_datasets count (P15) --
      $dbItems = Invoke-OnDb $ServerDbPath { Get-DatabaseSteps $srv.Items $Ctx 'write' $sqlSet $SourceOverride }
      foreach ($i in $dbItems) { [void]$secD.Items.Add($i) }
      # ---- 5. RESPONSE: back across, then the client's remaining lines --------------------
      # anchored at the SAME line as the request: the one ExecuteCommand call sends the request
      # and returns the response frame (ruling P4 -- two CROSSES steps at one anchor is correct)
      $back = New-TraceStep 'crosses' 'process boundary' $xing.Anchor '' $xing.Routine 'the response frame'
      [void]$back.Children.Add((New-TraceFacet 'FROM' $srvName '' 'server index'))
      [void]$back.Children.Add((New-TraceFacet 'TO' $cliName '' 'client index'))
      [void]$back.Children.Add((New-TraceFacet 'WITH' $(if ($srv.Responses.Count) { $srv.Responses -join ' or ' } else { 'no rsp* constant read in the handler' }) $xing.Anchor ''))
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
  # ---- 6. READ (Task 6) and ALSO -----------------------------------------------------------
  [void]$secRd.Items.Add((New-TraceStep 'stops' 'the READ direction is not walked yet (Task 6)' (Get-TraceAnchorText $A.DataSet.File $A.DataSet.Line)))
  foreach ($r in $alsoRows) { [void]$secAl.Items.Add($r) }
  $read = $secRd.Items.Count; $also = $secAl.Items.Count
}

# ---- 7. write it -- LAST, so a refusal above leaves nothing behind -------------------------
$text = Write-FormA $T
$base = 'roundtrip_' + ($Target -replace '[^A-Za-z0-9]', '_')
$path = Join-Path $OutDir "$base.dlgraph"
[IO.File]::WriteAllText($path, $text, (New-Object Text.ASCIIEncoding))
Write-Host $text
$c = Get-TraceCounts $T
$proof = "$((Invoke-IndexQuery 'SELECT COUNT(*) AS n FROM files')[0].n)/$((Invoke-OnDb $ServerDbPath { (Invoke-IndexQuery 'SELECT COUNT(*) AS n FROM files')[0].n }))"
Write-Host ("  anchor={0}  steps={1}  conditions={2}  crossings={3}  unresolved={4}  write/read/also={5}/{6}/{7}" -f $name, $c.Steps, $c.Conditions, $c.Crossings, $c.Unresolved, $write, $read, $also)

[pscustomobject]@{
  Trace        = $path
  Text         = $text
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
  Sections     = (@($T.Sections | ForEach-Object { $_.Name }) -join ',')
  OnDbProof    = $proof
  ClickTargets = (Get-TraceAnchors $T)
  Expected     = (Get-TraceAnchors $T)
  AllClickable = $true
}
