<#
  New-DiagramArtifact.ps1 -- closes the loop: question -> chart -> bundle ->
  browser shell -> a cross-reference you paste into the code.

  These artifacts are NOT autodocumentation. They are large, slow to produce and
  stable over time, so nothing generates them on a build. Someone asks a question
  deliberately, and inserts a REFERENCE into the code or its documentation. The
  volatility therefore lives in the FILE -- a stable path plus a regenerated
  artifact -- and never in the comment, which is what keeps the autodoc rewriter
  entirely out of it.

  Produces, under <OutRoot>\<question>-<symbol>\ :
    graph.svg      the picture, rows are real <a xlink:href> anchors
    graph.plain    the geometry, from the SAME layout run (cannot drift)
    graph.dot      the dot we emitted (we never parse dot; it is our output)
    graph.png      raster export
    graph.pdf      document export
    trace.dlgraph  round-trip only, INSTEAD of the graph.* files: a TEXT
                   question ships its Form A document, shown in the shell
    index.html     the shell: opens in a browser, clicks are explained
    meta.json      index fingerprint + regenerate command (staleness detectable)
    xref.txt       the DocInsight <remarks> block to paste into the unit

  Clicks: the SVG anchors are draglint://open?file=..&line=.. and they WORK.
  Verified live 2026-09-23: DragLint.Plugin.OpenSourceServer.pas runs the pipe
  server (started at DragLint.Plugin.Wizard.pas:117), \\.\pipe\drag-lint-open-source
  was listening in the running IDE, and a <file><TAB><line><LF> write navigated it.

  An earlier note in docs\BACKLOG-archify-parity.md calls the plugin's pipe
  server "the one piece genuinely missing". That was true when written on
  2026-09-16 and is NOT true now -- the unit is dated 2026-09-11 and is in the
  .dpk. Only the BROWSER hop needed building, because a browser cannot write to
  a named pipe: see Register-DragLintProtocol.ps1.
#>
[CmdletBinding()]
param(
  # the SELECTION, and it differs per question: a qualified symbol for
  # butterfly / who-calls / touches-tables, a unit name for deps, a form CLASS
  # for event-wiring, a TABLE or TABLE.COLUMN for consumers, a <Form>.<Control>
  # (e.g. frmCausFail.colREASON) for feeds-from; an ORM property (uCAUSFAIL.TmcCAUSFAIL.REASON)
  # or a <Form>.<Control> for lands-where; a control, an interface field, a TField
  # variable or TABLE.COLUMN for round-trip.
  # `cycles` and `architecture` select the PROJECT, not a symbol. Target stays
  # mandatory rather than gaining a special "omit it" mode, because a bundle with
  # no target in its name and no target in its meta.json is unidentifiable six
  # months later. The literal 'project' IS the selection for those two.
  [Parameter(Mandatory)][Alias('Qname','Unit','Form','Interface','Type')][string] $Target,
  [Parameter(Mandatory)][string] $DbPath,
  [ValidateSet('butterfly','deps','who-calls','what-it-calls','who-writes','who-reads',
               'hierarchy','class-surface','event-wiring','touches-tables',
               'lifecycle','cycles','wiring','effects','architecture',
               'protocol-trace','crosses-boundary','shown-where','change-impact','tested-by',
               'exception-paths','consumers','feeds-from','lands-where','round-trip')]
  [string] $Question = 'butterfly',
  # crosses-boundary only: the other half of the system, so the far side of a
  # protocol command can be named. Optional -- without it the chart shows one side
  # and says so.
  [string] $CounterpartDb,
  # consumers, feeds-from and lands-where: the SQL-SCRIPT index clone (tables,
  # triggers, procedures). -DbPath stays the Delphi project index; -Target is
  # TABLE or TABLE.COLUMN for consumers, <Form>.<Control> for feeds-from.
  [string] $SqlDbPath,
  # lands-where and round-trip: the SERVER clone (TDataService_<T>_SERVER, the write/read path).
  # -DbPath stays the CLIENT clone there (ORM classes + DFM bindings), so the verb
  # reads THREE indexes: -DbPath, -ServerDbPath, -SqlDbPath.
  [string] $ServerDbPath,
  [string] $Control,                      # event-wiring only: filter, not selector
  [int]    $Depth   = 2,
  [int]    $Cap     = 20,                 # member-access / hierarchy: readability cap
  # class-surface caps PER VISIBILITY CLUSTER, so its useful value is much
  # smaller -- a shared default of 20 would put 40 rows in one picture.
  [int]    $SurfaceCap = 12,
  [ValidateSet('write','read','both')]
  [string] $Mode    = 'both',             # member-access only; who-writes/who-reads force it
  [string] $OutRoot = (Join-Path $PSScriptRoot '..\artifacts'),
  [switch] $Open
)

$ErrorActionPreference = 'Stop'

# exception-paths walks CALLERS three levels by default (who-calls' precedent in
# the plan), while the shared -Depth default here is 2. An explicit -Depth wins.
if ($Question -in 'consumers', 'feeds-from', 'lands-where' -and -not $SqlDbPath) {
  throw "$Question needs -SqlDbPath: the SQL-script index clone (charts\scratch\db\SQL-drag-lint-sql.sqlite)"
}

if ($Question -eq 'lands-where' -and -not $ServerDbPath) {
  throw 'lands-where needs -ServerDbPath: the SERVER clone (charts\scratch\db\SERVER-MicroniteMW1Service.sqlite); -DbPath is the CLIENT clone'
}

if ($Question -eq 'round-trip' -and (-not $SqlDbPath -or -not $ServerDbPath)) {
  throw 'round-trip needs -ServerDbPath (the SERVER clone) and -SqlDbPath (the SQL-script clone); -DbPath is the CLIENT clone'
}

# round-trip walks four call levels by default (the emitter's own default).
$EffDepth = $(if ($PSBoundParameters.ContainsKey('Depth')) { $Depth } elseif ($Question -eq 'exception-paths') { 3 } elseif ($Question -eq 'round-trip') { 4 } else { $Depth })

$Qname   = $Target
$slug    = (($Target + $(if ($Control) { ".$Control" } else { '' })) -replace '[^A-Za-z0-9]', '_')
$dir     = Join-Path $OutRoot "$Question-$slug"
$dirWasNew = -not (Test-Path $dir)
New-Item -ItemType Directory -Force $dir | Out-Null

# ---- 1. emit -- dispatch on the question, exactly as `ask --question` will ---
# A refusal is a RESULT here (touches-tables on a client index, who-calls on an
# event handler), so a failed emitter must not leave a half-made bundle behind
# for someone to find later and mistake for an answer.
try {
  $r = switch ($Question) {
    'butterfly'      { & (Join-Path $PSScriptRoot 'Emit-Butterfly.ps1')     -Qname $Target -DbPath $DbPath -Depth $Depth -OutDir $dir }
    'deps'           { & (Join-Path $PSScriptRoot 'Emit-Deps.ps1')          -Unit  $Target -DbPath $DbPath -OutDir $dir }
    'who-calls'      { & (Join-Path $PSScriptRoot 'Emit-WhoCalls.ps1')      -Qname $Target -DbPath $DbPath -Depth $Depth -OutDir $dir -Direction callers }
    'what-it-calls'  { & (Join-Path $PSScriptRoot 'Emit-WhoCalls.ps1')      -Qname $Target -DbPath $DbPath -Depth $Depth -OutDir $dir -Direction callees }
    'event-wiring'   {
      # splatted, because -Control must be ABSENT rather than empty: passing
      # -Control '' would filter every component away and read as "no rows"
      $ew = @{ Form = $Target; DbPath = $DbPath; OutDir = $dir }
      if ($Control) { $ew.Control = $Control }
      & (Join-Path $PSScriptRoot 'Emit-EventWiring.ps1') @ew
    }
    # The question NAMES the direction, so -Mode is not consulted here: asking
    # who-writes and getting both wings back would answer a different question
    # than the one the bundle is labelled with.
    'who-writes'     { & (Join-Path $PSScriptRoot 'Emit-MemberAccess.ps1')   -Qname $Target -DbPath $DbPath -Mode write -Cap $Cap -OutDir $dir }
    'who-reads'      { & (Join-Path $PSScriptRoot 'Emit-MemberAccess.ps1')   -Qname $Target -DbPath $DbPath -Mode read  -Cap $Cap -OutDir $dir }
    'hierarchy'      { & (Join-Path $PSScriptRoot 'Emit-Hierarchy.ps1')     -Type  $Target -DbPath $DbPath -Cap $Cap -OutDir $dir }
    'class-surface'  { & (Join-Path $PSScriptRoot 'Emit-ClassSurface.ps1')  -Type  $Target -DbPath $DbPath -Cap $SurfaceCap -OutDir $dir }
    'touches-tables' { & (Join-Path $PSScriptRoot 'Emit-TouchesTables.ps1') -Qname $Target -DbPath $DbPath -OutDir $dir }
    'lifecycle'      { & (Join-Path $PSScriptRoot 'Emit-Lifecycle.ps1')     -Form  $Target -DbPath $DbPath -OutDir $dir }
    'wiring'         { & (Join-Path $PSScriptRoot 'Emit-Wiring.ps1')        -Interface $Target -DbPath $DbPath -MaxRows $Cap -OutDir $dir }
    'effects'        { & (Join-Path $PSScriptRoot 'Emit-Effects.ps1')       -Qname $Target -DbPath $DbPath -OutDir $dir }
    # PROJECT-scoped: 'project' means "no -Unit", i.e. every cycle in the index.
    # Splatted for the same reason event-wiring is -- passing -Unit '' would
    # filter every cycle away and render as "no cycles", which is a different
    # and wrong answer.
    'cycles'         {
      $cy = @{ DbPath = $DbPath; OutDir = $dir }
      if ($Target -ne 'project') { $cy.Unit = $Target }
      & (Join-Path $PSScriptRoot 'Emit-Cycles.ps1') @cy
    }
    'architecture'   { & (Join-Path $PSScriptRoot 'Emit-Architecture.ps1')  -DbPath $DbPath -OutDir $dir }
    'protocol-trace' { & (Join-Path $PSScriptRoot 'Emit-ProtocolTrace.ps1') -Target $Target -DbPath $DbPath -Cap $Cap -OutDir $dir }
    'shown-where'    { & (Join-Path $PSScriptRoot 'Emit-ShownWhere.ps1')    -Column $Target -DbPath $DbPath -Cap $Cap -OutDir $dir }
    'change-impact'  { & (Join-Path $PSScriptRoot 'Emit-ChangeImpact.ps1')  -Target $Target -DbPath $DbPath -Depth $Depth -OutDir $dir }
    'tested-by'      { & (Join-Path $PSScriptRoot 'Emit-TestedBy.ps1')      -Target $Target -DbPath $DbPath -Cap $Cap -OutDir $dir }
    'exception-paths'{ & (Join-Path $PSScriptRoot 'Emit-ExceptionPaths.ps1') -Qname $Target -DbPath $DbPath -Depth $EffDepth -Cap $Cap -OutDir $dir }
    # TABLE or TABLE.COLUMN: the dot decides the form, so one -Target serves both
    'consumers'      {
      $co = @{ DbPath = $DbPath; SqlDbPath = $SqlDbPath; Cap = $Cap; OutDir = $dir }
      if ($Target.Contains('.')) { $co.Column = $Target } else { $co.Table = $Target }
      & (Join-Path $PSScriptRoot 'Emit-Consumers.ps1') @co
    }
    # a data-aware CONTROL; the SQL clone checks the TABLE.COLUMN at the bottom
    'feeds-from'     { & (Join-Path $PSScriptRoot 'Emit-FeedsFrom.ps1')     -Control $Target -DbPath $DbPath -SqlDbPath $SqlDbPath -Cap $Cap -OutDir $dir }
    # an ORM property or a <Form>.<Control>; CLIENT + SERVER + the SQL scripts
    'lands-where'    { & (Join-Path $PSScriptRoot 'Emit-LandsWhere.ps1')    -Field $Target -DbPath $DbPath -ServerDbPath $ServerDbPath -SqlDbPath $SqlDbPath -Cap $Cap -OutDir $dir }
    # splatted so -CounterpartDb is ABSENT rather than empty: Get-CloneDb would
    # reject '' and the far side would fail instead of simply not being drawn.
    'crosses-boundary' {
      $cb = @{ Target = $Target; DbPath = $DbPath; OutDir = $dir; Cap = $Cap }
      if ($CounterpartDb) { $cb.CounterpartDb = $CounterpartDb }
      & (Join-Path $PSScriptRoot 'Emit-CrossesBoundary.ps1') @cb
    }
    # the Interface report's trace core: CLIENT + SERVER + SQL, a TEXT bundle (trace.dlgraph, no svg)
    'round-trip'     { & (Join-Path $PSScriptRoot 'Emit-RoundTrip.ps1')     -Target $Target -DbPath $DbPath -ServerDbPath $ServerDbPath -SqlDbPath $SqlDbPath -Depth $EffDepth -OutDir $dir }
  }
} catch {
  if ($dirWasNew -and (Test-Path $dir) -and -not (Get-ChildItem $dir -Force)) {
    Remove-Item $dir -Force
  }
  throw
}

# Each emitter reports its own row vocabulary; the shell needs one pair of
# labelled numbers. Naming them per question beats guessing from property
# presence, which silently mislabels the moment two emitters share a name.
$vocab = @{
  'butterfly'      = @('Callers','callers',     'Callees','callees')
  'deps'           = @('UsedBy', 'used by',     'Uses',   'uses')
  'who-calls'      = @('Callers','call sites',  'Cycles', 'cycle rows')
  'what-it-calls'  = @('Callees','call sites',  'Cycles', 'cycle rows')
  # Both totals are reported whichever wing was drawn, so a zero never reads as
  # "nothing uses this" -- "0 writes / 602 reads" is the honest header.
  'who-writes'     = @('Writes', 'write sites', 'Routines','routines')
  'who-reads'      = @('Reads',  'read sites',  'Routines','routines')
  'hierarchy'      = @('Ancestors','ancestors', 'Descendants','descendants')
  'class-surface'  = @('Members','members',     'Shown',   'shown')
  'event-wiring'   = @('Events', 'events',      'Handlers','handlers')
  'touches-tables' = @('Reads',  'tables read', 'Writes', 'tables written')
  # The pair chosen per question is the one a reader needs to judge the chart at
  # a glance. For lifecycle that is NOT "wired / absent": the middle state is the
  # whole point, so the header carries wired and implemented-but-unwired.
  'lifecycle'      = @('Wired',  'stages wired', 'NotWired', 'implemented, not wired')
  'cycles'         = @('Cycles', 'groups',       'Edges',    'uses edges')
  'wiring'         = @('Registrations','registrations','ResolvedAt','resolution sites')
  # Unknown beside Effects on purpose: `?` is an admission, and a header showing
  # only the effect count would let an incomplete answer read as a complete one.
  'effects'        = @('Effects','effects',      'Unknown',  'unclassified tokens')
  'architecture'   = @('Units',  'project units','BackEdges','back-edges')
  'protocol-trace' = @('Refs',   'references',   'Zones',    'zones')
  # Commands beside the verdict: the verdict is a judgement made FROM the
  # evidence, so the header carries the evidence count too.
  'crosses-boundary'= @('Commands','commands',   'PipeCalls','transport calls')
  'shown-where'    = @('Bindings','data bindings','Forms',   'forms')
  'change-impact'  = @('Affected','routines affected','Units','units')
  'tested-by'      = @('Tests',  'covering tests','Fixtures','fixtures')
  # raises beside handlers-in-body; where they are CAUGHT is the picture itself,
  # and it is never summarised as 'unhandled' (plan R3).
  'exception-paths'= @('Raises', 'raise sites',  'Handles',  'handler clauses in body')
  # certain + inferred together; the split is on the focus box itself (R7).
  # ROUTINES only: a unit-level SQL literal is a unit, not a routine -- counted
  # apart (ReaderUnits / WriterUnits) and said on the focus box (final wave, item 6)
  'consumers'      = @('Readers','reading routines','Writers','writing routines')
  # the hops drawn, and how many controls in the whole index resolve to one
  # table -- the per-control coverage (R9), not the per-datasource 41%
  'feeds-from'     = @('ChainRows','chain rows','CtlTable','controls in the index that resolve to one table')
  # the server DataService routines that touch it, and the DB-side triggers on the column
  'lands-where'    = @('ServerRows','server DataService rows','Triggers','triggers touching the column')
  # steps beside unresolved: a trace with STOPS in it says so in its header (AC-12)
  'round-trip'     = @('Steps',  'steps',        'Unresolved', 'unresolved')
}
$v = $vocab[$Question]
$leftCount  = $r.($v[0]); $leftLabel  = $v[1]
$rightCount = $r.($v[2]); $rightLabel = $v[3]
# An emitter may NAME its own count (property "<Count>Label"): who-reads on a
# field whose bare reads the index leaves UNBOUND must not read "0 read sites"
# (ruling R26) -- it reads "0 resolved read sites reported by find-callers + 9
# unbound read(s) named FNoRecursion in Blueprint4.pas". Only Emit-MemberAccess sets one.
# (Its first use, bound writes find-callers did not report, retired with engine D31.)
if ($r.PSObject.Properties["$($v[0])Label"] -and $r."$($v[0])Label") { $leftLabel  = [string]$r."$($v[0])Label" }
if ($r.PSObject.Properties["$($v[2])Label"] -and $r."$($v[2])Label") { $rightLabel = [string]$r."$($v[2])Label" }

# Move BY PROPERTY. The old form rebuilt "<slug>.png" by hand, which coupled the
# bundler to each emitter's private naming; event-wiring's -Control slug broke
# that coupling immediately.
foreach ($pair in @(@($r.Svg,'graph.svg'), @($r.Plain,'graph.plain'), @($r.Dot,'graph.dot'),
                    @($r.Png,'graph.png'), @($r.Pdf,'graph.pdf'))) {
  if ($pair[0] -and (Test-Path $pair[0])) { Move-Item $pair[0] (Join-Path $dir $pair[1]) -Force }
}
# a TEXT question ships its document, not a picture
if ($r.PSObject.Properties['Trace'] -and $r.Trace -and (Test-Path $r.Trace)) { Move-Item $r.Trace (Join-Path $dir 'trace.dlgraph') -Force }

# ---- 2. fingerprint the index, so staleness is DETECTABLE not merely visible -
$dbItem = Get-Item $DbPath
$fp = [pscustomobject]@{
  question    = $Question
  qname       = $Qname
  depth       = $EffDepth
  index       = $dbItem.FullName
  indexBytes  = $dbItem.Length
  indexMtime  = $dbItem.LastWriteTimeUtc.ToString('s') + 'Z'
  generated   = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
  leftLabel   = $leftLabel
  leftCount   = $leftCount
  rightLabel  = $rightLabel
  rightCount  = $rightCount
  # a chart drawn through a test hook says so here too (fix round 2); none of the
  # bundler's own calls passes one, so this is $false for every real bundle
  testChart   = [bool]$r.TestChart
  clickTargets= $r.ClickTargets
  allClickable= $r.AllClickable
  regenerate  = "New-DiagramArtifact.ps1 -Question $Question -Target $Target -DbPath `"$DbPath`"" +
                $(if ($Question -in 'butterfly','who-calls','what-it-calls','change-impact','exception-paths','round-trip') { " -Depth $EffDepth" } else { '' }) +
                $(if ($Question -in 'who-writes','who-reads','hierarchy','wiring','protocol-trace','shown-where','tested-by','crosses-boundary','exception-paths','consumers','feeds-from','lands-where') { " -Cap $Cap" } else { '' }) +
                $(if ($Question -in 'consumers', 'feeds-from', 'lands-where', 'round-trip') { " -SqlDbPath `"$SqlDbPath`"" } else { '' }) +
                $(if ($Question -in 'lands-where','round-trip') { " -ServerDbPath `"$ServerDbPath`"" } else { '' }) +
                $(if ($Question -eq 'crosses-boundary' -and $CounterpartDb) { " -CounterpartDb `"$CounterpartDb`"" } else { '' }) +
                $(if ($Question -eq 'class-surface') { " -SurfaceCap $SurfaceCap" } else { '' }) +
                $(if ($Question -eq 'event-wiring' -and $Control) { " -Control $Control" } else { '' })
  # every count the emitter reported, not just the two the shell shows. The
  # ones the header omits are exactly the ones worth auditing later --
  # who-calls' NameOnly, event-wiring's DfmFallback, touches-tables' Unresolved.
  # (round-trip's Trace is a path the move above made stale, and its Text IS trace.dlgraph)
  emitter     = ($r | Select-Object -ExcludeProperty Dot, Svg, Plain, Png, Pdf, Trace, Text)
}
$fp | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir 'meta.json') -Encoding ascii

# ---- 3. the shell ------------------------------------------------------------
# A TEXT question (round-trip) returns its document as .Trace; every other question
# draws a chart. The branch is on WHAT THE QUESTION PRODUCED, never on a missing
# svg: a chart question that wrote no svg must fail naming graph.svg, not be
# shown as a text bundle that is not there either.
$isText  = [bool]($r.PSObject.Properties['Trace'] -and $r.Trace)
$svgPath = Join-Path $dir 'graph.svg'
if ($isText) {
  $tracePath = Join-Path $dir 'trace.dlgraph'
  if (-not (Test-Path $tracePath)) { throw "$Question returned a trace but $tracePath is missing" }
  # the document itself, escaped, in a <pre>
  $doc = [IO.File]::ReadAllText($tracePath)
  $svg = '<pre style="margin:0;font:13px/1.5 var(--mono);white-space:pre">' + $doc.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') + '</pre>'
  # T8-R1: a text page has NO click targets -- its anchors are @File.pas:line TEXT
  $anchorSpan = "<span><b>$($r.ClickTargets)</b> anchors, written as @file:line text -- not click targets</span>"
  $note = "    <p><b>This is a document, not a chart.</b> <code class=`"k`">$Question</code> answers in`n" +
          "    Form A TEXT (<code class=`"k`">trace.dlgraph</code>; grammar:`n" +
          "    <code class=`"k`">charts\form-a-grammar-spec.md</code> section 8). Each step's anchor is`n" +
          "    written as <code class=`"k`">@File.pas:line</code> text, so nothing on this page is a`n" +
          "    click target. A chart drawn from this text is later work.</p>"
  $footFiles = 'trace.dlgraph (Form A text) &middot; '
} else {
  if (-not (Test-Path $svgPath)) { throw "$Question drew no chart: $svgPath is missing" }
  $svg = [IO.File]::ReadAllText($svgPath)
  $svg = $svg -replace '(?s)^.*?(?=<svg)', ''          # drop the XML prolog + DOCTYPE
  $anchorSpan = "<span><b>$($r.ClickTargets)</b> click targets</span>"
  $note = @'
    <p><b>Clicks open the file in your running IDE.</b> Every row is a real anchor
    carrying <code class="k">draglint://open?file=..&amp;line=..</code>. The IDE
    plugin already runs the pipe server
    (<code class="k">DragLint.Plugin.OpenSourceServer.pas</code>, started from
    <code class="k">DragLint.Plugin.Wizard.pas:117</code>), listening on
    <code class="k">\\.\pipe\drag-lint-open-source</code> for
    <code class="k">&lt;file&gt;&lt;TAB&gt;&lt;line&gt;&lt;LF&gt;</code>.</p>
    <p style="margin-top:10px">A browser cannot write to a named pipe, so the
    one-time bridge is a protocol handler:
    <code class="k">charts\src\Register-DragLintProtocol.ps1</code> (HKCU only,
    no elevation, <code class="k">-Unregister</code> to undo). Without it a click
    falls through to this page's own handler, which shows you the exact message
    it would have sent. If the IDE is not running, the handler falls back to
    ShellExecute, mirroring the standalone viewer.</p>
'@
  $footFiles = 'graph.svg &middot; graph.png &middot; graph.pdf &middot; graph.plain (geometry, same layout run) &middot; '
}

$short = $Qname
$html = @"
<!doctype html>
<meta charset="utf-8">
<title>$Question -- $short</title>
<style>
  :root{--bg:#F6F7F9;--panel:#fff;--ink:#131820;--muted:#5B6674;--line:#DDE2E8;
        --accent:#0F766E;--accent-soft:#E2F1EF;--warn:#9A5408;--warn-soft:#FBF0E0;
        --mono:'Cascadia Mono',Consolas,monospace;
        --sans:'Segoe UI',system-ui,sans-serif;}
  @media (prefers-color-scheme:dark){:root{--bg:#0E1319;--panel:#151C24;--ink:#E6EBF1;
        --muted:#96A2B1;--line:#293441;--accent:#4FD1C0;--accent-soft:#12312D;
        --warn:#E0A458;--warn-soft:#33260F;}}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 var(--sans);}
  header{padding:20px 24px;border-bottom:1px solid var(--line);}
  h1{margin:0 0 6px;font-size:22px;font-weight:650;}
  h1 code{font-family:var(--mono);font-size:.85em;}
  .meta{font-family:var(--mono);font-size:12.5px;color:var(--muted);
        display:flex;flex-wrap:wrap;gap:6px 22px;}
  .meta b{color:var(--ink);font-weight:600;}
  main{padding:20px 24px;}
  .stage{background:var(--panel);border:1px solid var(--line);border-radius:10px;
         padding:16px;overflow:auto;}
  .stage svg{max-width:100%;height:auto;}
  .stage a{cursor:pointer;}
  .stage a:hover text{text-decoration:underline;}
  .note{margin:18px 0 0;border-left:4px solid var(--warn);background:var(--warn-soft);
        padding:14px 18px;border-radius:0 8px 8px 0;font-size:14px;}
  .note b{color:var(--warn);}
  #toast{position:fixed;left:50%;bottom:26px;transform:translateX(-50%);
         background:var(--ink);color:var(--bg);font-family:var(--mono);font-size:13px;
         padding:11px 16px;border-radius:8px;max-width:min(92vw,720px);
         box-shadow:0 6px 24px rgba(0,0,0,.25);opacity:0;pointer-events:none;
         transition:opacity .18s;}
  #toast.on{opacity:1;}
  footer{padding:16px 24px 32px;color:var(--muted);font-family:var(--mono);font-size:12px;}
  code.k{background:var(--accent-soft);color:var(--accent);padding:1px 6px;border-radius:4px;}
</style>
<header>
  <h1>$Question &mdash; <code>$short</code></h1>
  <div class="meta">
    <span><b>$leftCount</b> $leftLabel</span>
    <span><b>$rightCount</b> $rightLabel</span>
    $anchorSpan
    <span>index <b>$([IO.Path]::GetFileName($DbPath))</b></span>
    <span>generated <b>$($fp.generated)</b></span>
  </div>
</header>
<main>
  <div class="stage">$svg</div>

  <div class="note">
$note
  </div>
</main>
<footer>
  ${footFiles}meta.json (regenerate command + index fingerprint)
</footer>
<div id="toast"></div>
<script>
(function () {
  var t = document.getElementById('toast'), timer = null;
  function toast(msg) {
    t.textContent = msg; t.classList.add('on');
    clearTimeout(timer); timer = setTimeout(function () { t.classList.remove('on'); }, 5200);
  }
  document.querySelector('.stage').addEventListener('click', function (ev) {
    var a = ev.target.closest('a'); if (!a) return;
    var href = a.getAttribute('xlink:href') || a.getAttribute('href') || '';
    if (href.indexOf('draglint://') !== 0) return;
    ev.preventDefault();
    var m = /file=([^&]*)&(?:amp;)?line=(\d+)/.exec(href);
    if (!m) { toast('unparseable target: ' + href); return; }
    var file = decodeURIComponent(m[1]), line = m[2];
    toast('sent to the IDE over \\\\\\\\.\\\\pipe\\\\drag-lint-open-source  ->  ' + file + ' TAB ' + line + '   (register the protocol handler to make this click go straight through)');
  });
})();
</script>
"@
[IO.File]::WriteAllText((Join-Path $dir 'index.html'),
  ($html -replace "`r`n", "`n" -replace "`n", "`r`n"), (New-Object Text.UTF8Encoding($false)))

# ---- 4. the cross-reference to paste into the unit ---------------------------
$rel = (Resolve-Path (Join-Path $dir 'index.html')).Path
$xref = @"
/// <remarks>
/// Diagram: $Question of $Target
/// Artifact: $rel
/// Generated: $($fp.generated) from $([IO.Path]::GetFileName($DbPath))
/// Regenerate: $($fp.regenerate)
/// The artifact is REGENERATED, not edited. This comment names a stable path
/// so it never needs rewriting when the diagram changes.
/// </remarks>
"@
[IO.File]::WriteAllText((Join-Path $dir 'xref.txt'),
  ($xref -replace "`r`n", "`n" -replace "`n", "`r`n"), (New-Object Text.ASCIIEncoding))

if ($Open) { Start-Process (Join-Path $dir 'index.html') }

[pscustomobject]@{
  Bundle       = $dir
  Shell        = (Join-Path $dir 'index.html')
  Xref         = (Join-Path $dir 'xref.txt')
  ClickTargets = $r.ClickTargets
  Files        = (Get-ChildItem $dir | Sort-Object Name | ForEach-Object { "$($_.Name) ($($_.Length))" }) -join ', '
}
