<#
  New-ExampleGallery.ps1 -- three worked HTML examples per shipped question,
  written to charts\docs\examples\<question>\.

  WHY THIS EXISTS. The emitters are verified by numbers in Test-Emitters.ps1,
  which proves they are CORRECT but shows nobody what they LOOK like. A reviewer
  should be able to open three real charts per question without installing
  Graphviz, cloning a database or running anything.

  THE OUTPUT IS GITIGNORED, THE GENERATOR IS NOT. Same rule the rest of this
  project follows: an artifact is regenerable, so the durable thing is the
  recipe. `charts\.gitignore` carries `docs/examples/`.

  TARGETS ARE CHOSEN TO SHOW RANGE, NOT TO FLATTER. Each question gets one
  ordinary case and at least one edge -- the 602-reader cap, the zero answer,
  the ambiguous type name, the 96-event form, the class with 392 members. A
  gallery of easy cases would hide exactly the behaviour worth reviewing.

  RUNS AGAINST THE CLONES in charts\scratch\db\, never the live corpus. See
  PLAN-next-five-verbs.md for why: this worktree's engine is OLDER than the
  indexes, so a live run risks a lock and an `index` run would downgrade them.
#>
[CmdletBinding()]
param(
  [string] $DbDir   = (Join-Path $PSScriptRoot '..\scratch\db'),
  [string] $OutRoot = (Join-Path $PSScriptRoot '..\docs\examples'),
  [string[]] $Only,                      # regenerate just these questions
  [switch] $KeepGoing                    # report failures instead of stopping
)

$ErrorActionPreference = 'Stop'
$CLI = Join-Path $DbDir 'CLIENT-Micronite2027.sqlite'
$SRV = Join-Path $DbDir 'SERVER-MicroniteMW1Service.sqlite'
$DC  = Join-Path $DbDir 'DataCopy-DataCopy.sqlite'
# DL is the drag-lint self-index. It is here for ONE reason: it holds the only
# INTERFACE cycle in the corpus (a 4-unit strongly-connected component that is
# not a ring), and no other clone can show that shape.
$DL  = Join-Path $DbDir 'DL-drag-lint.sqlite'
# A TEST project index. `tested-by` is a SINGLE-DB question -- a test project's
# compile closure already contains the code under test -- so it needs this one
# and cannot be answered from CLIENT or SERVER at all.
$MT  = Join-Path $DbDir 'TESTS-MicroniteTests.sqlite'
foreach ($d in @($CLI, $SRV, $DC, $DL, $MT)) {
  if (-not (Test-Path $d)) { throw "clone missing: $d -- see PLAN-next-five-verbs.md for how they are made" }
}

# question, target, db, extra args, and WHY this one was picked. The note is
# rendered into the index, because a gallery without a reason per example is
# just thirty pictures.
$EX = @(
  @{ Q='butterfly';      T='Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation'; D=$CLI; A=@{Depth=2}; Why='the reference case: 9 callers, callees both ways at one hop' }
  @{ Q='butterfly';      T='uPipeSessionBuilder.TPipeSessionBuilder.HandleComputeSchedule'; D=$SRV; A=@{Depth=2}; Why='the server-side hub -- richest SQL facts in the index' }
  @{ Q='butterfly';      T='uZeissRoutines.TZEISSTransfer.TransferFile';                    D=$DC;  A=@{Depth=2}; Why='DataCopy: the busiest method there, 50 outgoing call edges' }

  @{ Q='deps';           T='Blueprint4.ViewModel';   D=$CLI; A=@{}; Why='18 uses / 3 used-by, clustered by directory' }
  @{ Q='deps';           T='uPipeSessionBuilder';    D=$SRV; A=@{}; Why='the server''s session builder -- the unit every handler lives in' }
  @{ Q='deps';           T='uMainZeissCopy';         D=$DC;  A=@{}; Why='DataCopy''s main form unit, 109 uses -- a fan-out worth seeing capped' }

  @{ Q='who-calls';      T='Blueprint4.ViewModel.TBlueprint_ViewModel.ReserveNextID';      D=$CLI; A=@{Depth=3}; Why='a CYCLE row at depth 2 plus 9 name-only matches that are NOT callers' }
  # NOT the pipe HANDLERS: they have 0 resolved callers because the server
  # dispatches to them by command id, not by a call, so who-calls correctly
  # refuses. That refusal is a true answer about ORM3's protocol design -- it is
  # simply not a chart. Picked callees with real inbound edges instead.
  @{ Q='who-calls';      T='Pipes.Protocol.WriteString';           D=$SRV; A=@{Depth=2}; Why='13 callers across the protocol layer -- the wire format''s chokepoint' }
  @{ Q='who-calls';      T='uFileUtils.AppendAlertLogLine';        D=$DC;  A=@{Depth=3}; Why='DataCopy: a logging utility reached from 13 places, three levels deep' }

  @{ Q='what-it-calls';  T='Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation'; D=$CLI; A=@{Depth=2}; Why='the -Direction callees switch on the same emitter as who-calls' }
  @{ Q='what-it-calls';  T='uZeissRoutines.TZEISSTransfer.TransferFile';                   D=$DC;  A=@{Depth=2}; Why='DataCopy: 50 out-edges, so the cluster layout has to work' }
  @{ Q='what-it-calls';  T='uMainZeissCopy.TfrmZeissCopy.LoadFromINIFile';                 D=$DC;  A=@{Depth=2}; Why='config load -- a readable fan-out of 32 edges' }

  @{ Q='who-writes';     T='MSCTYPES.RChartSampleData.R';                D=$CLI; A=@{}; Why='a FIELD: 7 writes over 3 routines, 3 of which also read it' }
  @{ Q='who-writes';     T='iINSPRSLT.ImcINSPRSLT.VERDICT';              D=$CLI; A=@{}; Why='a PROPERTY backed by methods -- 34 writes over 30 routines' }
  @{ Q='who-writes';     T='uMicroniteFormat.TMicroniteRawLimits.Upper'; D=$DC;  A=@{}; Why='DataCopy''s most-touched field' }

  @{ Q='who-reads';      T='uPipeClientConnection.TPipeClientConnection.Connected'; D=$CLI; A=@{Cap=25}; Why='THE CAP CASE: 602 reads over 598 routines, 25 shown, 573 disclosed' }
  @{ Q='who-reads';      T='MSCTYPES.RChartSampleData.R';                           D=$CLI; A=@{}; Why='13 reads -- the same field as who-writes, for comparison' }
  @{ Q='who-reads';      T='uInterface.IConfigurationService.BackupPath1';          D=$DC;  A=@{}; Why='DataCopy: a property on an interface' }

  @{ Q='hierarchy';      T='TInterfacedObject';         D=$CLI; A=@{}; Why='145 descendants, and the FOCUS is RTL so it is not declared here at all' }
  @{ Q='hierarchy';      T='TBlueprint_ViewModel';      D=$CLI; A=@{}; Why='an RTL ancestor rendered grey and un-anchored, beside a resolved interface' }
  @{ Q='hierarchy';      T='TDataService_DRA1_CLIENT';  D=$CLI; A=@{}; Why='the AMBIGUITY case: its ancestor IDataService is two real types' }

  @{ Q='class-surface';  T='Blueprint4.ViewModel.TBlueprint_ViewModel'; D=$CLI; A=@{}; Why='392 members over 2 visibility clusters, 368 disclosed' }
  @{ Q='class-surface';  T='uMainZeissCopy.TfrmZeissCopy';              D=$DC;  A=@{}; Why='DataCopy: a 318-member FORM class' }
  @{ Q='class-surface';  T='uConfigurationService.TConfigurationService'; D=$DC; A=@{}; Why='148 members, a service rather than a form' }

  @{ Q='event-wiring';   T='uMain.TfrmMAIN';            D=$CLI; A=@{}; Why='41 events / 41 handlers / 40 controls, DFM-resolved' }
  @{ Q='event-wiring';   T='Blueprint4.TfrmBlueprint4'; D=$CLI; A=@{}; Why='SCALE: 96 events across 24 event kinds' }
  @{ Q='event-wiring';   T='uMainZeissCopy.TfrmZeissCopy'; D=$DC; A=@{}; Why='DataCopy: a full lifecycle set (OnCreate/OnShow/OnCloseQuery/OnDestroy)' }

  # HandleComputeSchedule is the RICHEST target (8 read / 5 written) and is
  # deliberately NOT here: its body carries more than 200 string literals, so
  # the literal-provenance query hits the sql row cap and the emitter refuses
  # rather than render a short answer. Correct behaviour, real limitation --
  # recorded in PLAN-next-five-verbs.md rather than papered over with a
  # smaller example pretending to be the biggest.
  @{ Q='touches-tables'; T='uAREAOFINTEREST_SERVER.TDataService_AREAOFINTEREST_SERVER.PrepareSaveQuery'; D=$SRV; A=@{}; Why='WRITE-ONLY: one table written, none read -- the opposite wing to HandleCopyOperation' }
  @{ Q='touches-tables'; T='uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation';   D=$SRV; A=@{}; Why='5 read / 5 written / 2 BOTH -- a table in both wings' }
  @{ Q='touches-tables'; T='uPipeSessionBuilder.TPipeSessionBuilder.HandleTableLoad';       D=$SRV; A=@{}; Why='THE ZERO CASE: touches no tables, and that is an answer, not a failure' }

  @{ Q='lifecycle';    T='uMain.TfrmMAIN';                 D=$CLI; A=@{}; Why='THE DESIGN POINT: FormDestroy is implemented at uMain.pas:422 and wired by nothing -- "implemented, not wired", never "(not implemented)"' }
  @{ Q='lifecycle';    T='uMainZeissCopy.TfrmZeissCopy';   D=$DC;  A=@{}; Why='DataCopy: a full spine -- OnCreate / OnShow / OnCloseQuery / OnDestroy all wired' }
  @{ Q='lifecycle';    T='WarningFlags.TfrmWarningFlags';  D=$CLI; A=@{}; Why='a REAL form that wires nothing. It renders; only a non-form is refused, and that decision is made on heritage' }

  @{ Q='cycles';       T='project';    D=$CLI; A=@{}; Why='2 groups, 5 edges. Arrows follow measured uses edges -- the verb''s units[] order would have drawn an edge that does not exist' }
  @{ Q='cycles';       T='project';    D=$DL;  A=@{}; Why='THE SHAPE THAT BREAKS THE ASSUMPTION: an INTERFACE cycle of 4 units that is two loops sharing one unit, with no ring through all four' }
  @{ Q='cycles';       T='project';    D=$DC;  A=@{}; Why='THE ZERO CASE: an acyclic index. "No cycles" renders and exits 0' }

  @{ Q='wiring';       T='IABZLoggingSys'; D=$SRV; A=@{}; Why='2 registrations (both singleton) and 4 resolution sites, out of 535 registrations index-wide' }
  @{ Q='wiring';       T='IABZLoggingSys'; D=$CLI; A=@{}; Why='THE DISCLOSURE CASE: the SAME interface on a client index that holds only 4 registrations in total. The chart states the number and refuses to guess the cause' }
  @{ Q='wiring';       T='IMicObject';     D=$SRV; A=@{}; Why='ZERO registrations is an answer, readable only next to the index-wide total' }

  @{ Q='effects';      T='Ap.APVDotProduct';                              D=$CLI; A=@{}; Why='g,p0,p3,? over GROUPED parameters -- p0 is V1 and p3 is V2, named by parsing the signature because mutates_params is empty here' }
  @{ Q='effects';      T='uMain.TfrmMAIN.GetConnection';                  D=$CLI; A=@{}; Why='PURE. The summary is NULL, which the naive reading calls "not analysed" -- and would be wrong for 2,892 CLIENT methods' }
  @{ Q='effects';      T='uSetupDefaults.TGlobalSetupDefaults.GetDebug1'; D=$CLI; A=@{}; Why='genuinely NOT ANALYSED (effect_free IS NULL) -- only 855 on CLIENT are. The contrast with the card above is the point' }

  @{ Q='architecture'; T='project'; D=$CLI; A=@{}; Why='563 units in 3 source zones, 2,858 internal edges, and 3 BACK-EDGES -- 13 edges running against a 1,170-edge flow' }
  @{ Q='architecture'; T='project'; D=$SRV; A=@{}; Why='the server half, for comparison with the client''s zone shape' }
  @{ Q='architecture'; T='project'; D=$DC;  A=@{}; Why='a SINGLE-FOLDER project: no internal zones exist, and the chart says so rather than manufacturing layers' }

  @{ Q='protocol-trace';   T='cmdDelta';     D=$CLI; A=@{}; Why='UNBLOCKED THE DAY THE ENUM BINDING LANDED: 38 references that were 0 yesterday, zoned CLIENT 37 + COMMON 1' }
  @{ Q='protocol-trace';   T='rspError';     D=$SRV; A=@{}; Why='the response side: 69 references over 27 routines, the mirror of the client''s cmd* traffic' }
  @{ Q='protocol-trace';   T='Pipes.Protocol.TPipeMessageHeader.CommandID'; D=$CLI; A=@{}; Why='the WIRE FIELD rather than a constant -- 1,043 member accesses over 727 routines' }

  @{ Q='crosses-boundary'; T='Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation'; D=$CLI; A=@{CounterpartDb=$SRV}; Why='CROSSES, with the far side resolved from the SERVER index: 2 commands, 1 transport call, 18 counterpart routines' }
  @{ Q='crosses-boundary'; T='uPipeClientConnection.TPipeClientConnection.ExecuteCommand';   D=$CLI; A=@{}; Why='IS the boundary rather than crossing it -- declared inside the transport layer' }
  @{ Q='crosses-boundary'; T='gammafunc.LnGamma';  D=$CLI; A=@{}; Why='NO EVIDENCE, stated as that and never as "does not cross": interface-dispatch edges are incomplete on this build' }

  @{ Q='shown-where';      T='FTRNAMESTR';   D=$CLI; A=@{}; Why='4 grid columns on 2 forms, each anchored to its own .dfm line' }
  @{ Q='shown-where';      T='ID';           D=$CLI; A=@{}; Why='SCALE: 72 bindings over 25 forms -- and the honest note that code-driven display is invisible here' }
  @{ Q='shown-where';      T='SEVERITY';     D=$CLI; A=@{}; Why='a business column spread thinly -- 7 bindings across 7 different forms, one control each' }

  @{ Q='change-impact';    T='Blueprint4.ViewModel.TBlueprint_ViewModel.ReserveNextID'; D=$CLI; A=@{}; Why='a contained change: 9 dependent routines, all in one unit and one zone' }
  @{ Q='change-impact';    T='uPipeClientConnection.TPipeClientConnection';             D=$CLI; A=@{}; Why='THE CAP CASE: a TYPE seeded with its 25 members reaches 591 routines over 174 units, and the frontier cap is disclosed' }
  # NOT a Handle* routine: the server dispatches to those by command id rather
  # than calling them, so they have 0 callers and change-impact correctly refuses.
  # That refusal is a true fact about ORM3's protocol design, not a chart.
  @{ Q='change-impact';    T='uPipeSessionBuilder.Log'; D=$SRV; A=@{}; Why='the server''s logging chokepoint -- 24 direct callers, the widest real blast radius on that side' }

  @{ Q='tested-by';        T='uCompGroupTree.TCompGroupTree.Build';     D=$MT; A=@{}; Why='11 covering tests, COMPUTED from call edges -- symbol_facts.covered_by is empty by design' }
  @{ Q='tested-by';        T='uGageLineQueue.TGageLineQueue.TryDequeue'; D=$MT; A=@{}; Why='8 covering tests on a queue primitive' }
  @{ Q='tested-by';        T='uCompGroupTree.TCompGroupTree';            D=$MT; A=@{}; Why='a TYPE: seeded with its 9 members, reached by 13 tests' }
)

if ($Only) { $EX = @($EX | Where-Object { $Only -contains $_.Q }) }

$made = New-Object System.Collections.ArrayList
$failed = New-Object System.Collections.ArrayList
foreach ($e in $EX) {
  $dir = Join-Path $OutRoot $e.Q
  New-Item -ItemType Directory -Force $dir | Out-Null
  $label = "{0,-15} {1}" -f $e.Q, $e.T
  try {
    $splat = @{ Question = $e.Q; Target = $e.T; DbPath = $e.D; OutRoot = $dir } + $e.A
    $r = & (Join-Path $PSScriptRoot 'New-DiagramArtifact.ps1') @splat 6>$null
    if (-not (Test-Path $r.Shell)) { throw 'no index.html produced' }
    [void]$made.Add([pscustomobject]@{
      Question = $e.Q; Target = $e.T; Db = [IO.Path]::GetFileNameWithoutExtension($e.D)
      Why = $e.Why; Shell = $r.Shell; Clicks = $r.ClickTargets
      Bytes = (Get-Item $r.Shell).Length
    })
    Write-Host ("  OK   {0}  ({1} click targets)" -f $label, $r.ClickTargets)
  } catch {
    [void]$failed.Add([pscustomobject]@{ Question = $e.Q; Target = $e.T; Error = $_.Exception.Message })
    Write-Host ("  FAIL {0}  -- {1}" -f $label, $_.Exception.Message)
    if (-not $KeepGoing) { throw }
  }
}

# ---- the central index -------------------------------------------------------
#
# This page covers the WHOLE catalogue, not just what happens to have samples.
# A gallery that lists only the shipped questions quietly answers "what can
# dl-charts do?" with "whatever is finished", and the unfinished rows are the
# ones a reviewer most needs to see -- with the REASON, so "not here yet" can be
# told apart from "cannot be done".
#
# The catalogue is the same 26 rows as charts\STATUS-questions.md. Keep them in
# step: this list is the page's own copy and nothing checks it against that doc.
$CATALOGUE = @(
  @{ Q='butterfly';       Sel='method';          St='shipped' }
  @{ Q='deps';            Sel='unit';            St='shipped' }
  @{ Q='who-calls';       Sel='method';          St='shipped' }
  @{ Q='what-it-calls';   Sel='method';          St='shipped' }
  @{ Q='who-writes';      Sel='field/property';  St='shipped' }
  @{ Q='who-reads';       Sel='field/property';  St='shipped' }
  @{ Q='hierarchy';       Sel='type';            St='shipped' }
  @{ Q='class-surface';   Sel='type';            St='shipped' }
  @{ Q='event-wiring';    Sel='form class';      St='shipped' }
  @{ Q='touches-tables';  Sel='method';          St='shipped' }
  @{ Q='lifecycle';       Sel='form class';      St='shipped' }
  @{ Q='cycles';          Sel='unit/project';    St='shipped' }
  @{ Q='wiring';          Sel='interface';       St='shipped' }
  @{ Q='effects';         Sel='method';          St='shipped' }
  @{ Q='architecture';    Sel='project';         St='shipped' }

  @{ Q='protocol-trace';  Sel='command / wire field'; St='shipped' }
  @{ Q='protocol-trace';  Sel='method';          St='shipped' }
  @{ Q='crosses-boundary';Sel='method';          St='shipped' }
  @{ Q='change-impact';   Sel='method/type';     St='shipped' }
  @{ Q='tested-by';       Sel='any symbol';      St='shipped' }
  @{ Q='shown-where';     Sel='db column';       St='shipped' }

  @{ Q='exception-paths'; Sel='method';          St='blocked'
     Note='Genuinely unanswerable from this index, and measured rather than assumed: <code>refs.kind</code> has no <code>raise</code> or <code>except</code> value (only read / type_use / call / member-access / write / event-binding / attribute / di-*), and <code>symbol_facts</code> has no exception column. Exception TYPES are referenced -- 17 <code>E*</code> classes, 12 descending from an Exception base -- but nothing separates <code>raise E.Create</code> from <code>on E do</code> from a bare declaration, so a chart would mislabel handlers as throwers.' }

  @{ Q='lands-where';     Sel='field';           St='needs-data'
     Note='<code>orm_links</code> is 0 rows everywhere. It is written by <code>drag-lint fb-snapshot</code>, which opens a live Firebird connection -- empty by construction in a pure Delphi index.' }
  @{ Q='feeds-from';      Sel='control';         St='needs-data'
     Note='Needs <code>orm_links</code> and <code>fb_datasets</code>; both 0 rows.' }
  @{ Q='consumers';       Sel='table/column';    St='needs-data'
     Note='Needs <code>fb_columns</code> and <code>fb_relations</code>; both 0 rows. The work here is the ingest, not the chart.' }

  @{ Q='compare';         Sel='two index runs';  St='parked'
     Note='Parked by owner decision, and genuinely dependent on the IR: there is no <code>ir</code> or <code>compare</code> verb in the deployed engine, confirmed against a deliberate fake control.' }
)

$STATUS = @{
  'shipped'    = @{ Label='shipped';              Cls='ok'   }
  'data-ready' = @{ Label='fact ready, verb not'; Cls='near' }
  'held'       = @{ Label='held: engine skew';    Cls='hold' }
  'unplanned'  = @{ Label='unplanned';            Cls='hold' }
  'blocked'    = @{ Label='blocked: engine gap';  Cls='no'   }
  'needs-data' = @{ Label='needs a live Firebird';Cls='no'   }
  'parked'     = @{ Label='parked by owner';      Cls='no'   }
}

$css = @'
<style>
:root{--bg:#F6F7F9;--panel:#fff;--ink:#131820;--muted:#5B6674;--line:#DDE2E8;
      --accent:#0F766E;--accent-soft:#E2F1EF;--warn:#9A5408;--warn-soft:#FBF0E0;
      --mono:'Cascadia Mono',Consolas,monospace;--sans:'Segoe UI',system-ui,sans-serif;
      --ok:#0F766E;--ok-bg:#E2F1EF;--near:#1D4ED8;--near-bg:#E8EEFE;
      --hold:#B45309;--hold-bg:#FDF1E3;--no:#6B7280;--no-bg:#EFF1F4;}
@media (prefers-color-scheme:dark){:root{--bg:#0E1319;--panel:#151C24;--ink:#E6EBF1;
      --muted:#96A2B1;--line:#293441;--accent:#4FD1C0;--accent-soft:#12312D;
      --ok:#4FD1C0;--ok-bg:#12312D;--near:#8AB4FF;--near-bg:#16233D;
      --hold:#E0A458;--hold-bg:#33260F;--no:#9AA6B4;--no-bg:#1E262F;}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 var(--sans);}
header{padding:24px 26px 20px;border-bottom:1px solid var(--line);}
h1{margin:0 0 6px;font-size:23px;font-weight:650;}
.sub{color:var(--muted);font-size:14px;max-width:78ch;}
.counts{margin-top:12px;display:flex;flex-wrap:wrap;gap:8px 10px;}
.pill{font-family:var(--mono);font-size:12px;padding:3px 10px;border-radius:99px;
      background:var(--no-bg);color:var(--no);}
.pill.ok{background:var(--ok-bg);color:var(--ok);}
.pill.near{background:var(--near-bg);color:var(--near);}
.pill.hold{background:var(--hold-bg);color:var(--hold);}
main{padding:22px 26px 40px;}
h2{margin:30px 0 4px;font-size:18px;}
h2 .sel{font-family:var(--mono);font-size:12px;color:var(--muted);font-weight:400;margin-left:8px;}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:12px;margin-top:10px;}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:13px 15px;}
.card a{color:var(--accent);text-decoration:none;font-family:var(--mono);
        font-size:13px;word-break:break-word;}
.card a:hover{text-decoration:underline;}
.why{color:var(--muted);font-size:13px;margin-top:6px;}
.foot{margin-top:9px;font-family:var(--mono);font-size:11.5px;color:var(--muted);
      display:flex;gap:14px;flex-wrap:wrap;}
table{border-collapse:collapse;width:100%;margin-top:10px;}
th{text-align:left;font-size:12px;text-transform:uppercase;letter-spacing:.04em;
   color:var(--muted);padding:6px 10px;border-bottom:1px solid var(--line);font-weight:600;}
td{padding:9px 10px;border-bottom:1px solid var(--line);vertical-align:top;font-size:14px;}
td.q{font-family:var(--mono);white-space:nowrap;}
td.n{color:var(--muted);font-size:13.5px;}
code{font-family:var(--mono);font-size:12.5px;background:var(--accent-soft);
     color:var(--accent);padding:1px 5px;border-radius:4px;}
.note{margin:22px 0 0;border-left:4px solid var(--warn);background:var(--warn-soft);
      padding:13px 17px;border-radius:0 8px 8px 0;font-size:13.5px;}
.note b{color:var(--warn);}
footer{padding:0 26px 34px;color:var(--muted);font-family:var(--mono);font-size:11.5px;}
</style>
'@

$byQ = @{}
foreach ($g in ($made | Group-Object Question)) { $byQ[$g.Name] = @($g.Group) }
$rootFull = (Resolve-Path $OutRoot).Path
function Get-RelHref([string] $Full) {
  $r = $Full
  if ($r.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
    $r = $r.Substring($rootFull.Length)
  }
  $r.TrimStart('\', '/').Replace('\', '/')
}

$nShipped = @($CATALOGUE | Where-Object { $_.St -eq 'shipped' }).Count
$nOther   = $CATALOGUE.Count - $nShipped

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<!doctype html><html lang="en"><meta charset="utf-8">')
[void]$sb.AppendLine('<meta name="viewport" content="width=device-width,initial-scale=1">')
[void]$sb.AppendLine('<title>dl-charts &mdash; diagram gallery</title>')
[void]$sb.AppendLine($css)
[void]$sb.AppendLine('<header><h1>dl-charts &mdash; diagram gallery</h1>')
[void]$sb.AppendLine('<div class="sub">Every question in the catalogue, whether or not it is built yet. Worked examples open a real chart &mdash; the rows are live anchors, so a click opens the file in a running RAD Studio. The unbuilt rows carry the reason they are unbuilt, because &ldquo;not here yet&rdquo; and &ldquo;cannot be done&rdquo; are different answers.</div>')
[void]$sb.AppendLine('<div class="counts">')
[void]$sb.AppendLine("<span class=`"pill ok`">$nShipped shipped</span>")
[void]$sb.AppendLine("<span class=`"pill`">$($CATALOGUE.Count) catalogue questions</span>")
[void]$sb.AppendLine("<span class=`"pill`">$($made.Count) worked examples</span>")
[void]$sb.AppendLine("<span class=`"pill hold`">$nOther not yet shipped</span>")
[void]$sb.AppendLine('</div></header><main>')

[void]$sb.AppendLine('<h2>Shipped</h2>')
foreach ($c in ($CATALOGUE | Where-Object { $_.St -eq 'shipped' })) {
  $q = $c.Q
  [void]$sb.AppendLine("<h2 id=`"$q`">$q<span class=`"sel`">selects $($c.Sel)</span></h2>")
  if (-not $byQ.ContainsKey($q)) {
    [void]$sb.AppendLine('<div class="why">No sample generated in this run.</div>')
    continue
  }
  [void]$sb.AppendLine('<div class="grid">')
  foreach ($m in $byQ[$q]) {
    $href = Get-RelHref $m.Shell
    [void]$sb.AppendLine('<div class="card">')
    [void]$sb.AppendLine("<a href=`"$href`">$([Net.WebUtility]::HtmlEncode($m.Target))</a>")
    [void]$sb.AppendLine("<div class=`"why`">$($m.Why)</div>")
    [void]$sb.AppendLine("<div class=`"foot`"><span>$($m.Db)</span><span>$($m.Clicks) click targets</span></div>")
    [void]$sb.AppendLine('</div>')
  }
  [void]$sb.AppendLine('</div>')
}

[void]$sb.AppendLine('<h2>Not yet shipped</h2>')
[void]$sb.AppendLine('<table><tr><th>question</th><th>selects</th><th>status</th><th>why not</th></tr>')
foreach ($c in ($CATALOGUE | Where-Object { $_.St -ne 'shipped' })) {
  $s = $STATUS[$c.St]
  [void]$sb.AppendLine("<tr><td class=`"q`">$($c.Q)</td><td class=`"n`">$($c.Sel)</td>" +
                       "<td><span class=`"pill $($s.Cls)`">$($s.Label)</span></td>" +
                       "<td class=`"n`">$($c.Note)</td></tr>")
}
[void]$sb.AppendLine('</table>')

[void]$sb.AppendLine('<div class="note"><p><b>These charts were generated against frozen clones, not the live corpus.</b> ' +
  'The engine deployed in this worktree is older than the indexes it is reading ' +
  '(engine 1.16.0-alpha / resolver 1.5.1-alpha against v=1.17.0-alpha / r=1.6.0-alpha), ' +
  'which yields smaller confident answers rather than errors. The callee direction is ' +
  'affected; callers, uses-edges, DFM events, DI bindings, purity facts and the ' +
  'dependency report are not. Anything on this page reached through <code>call_edges</code> ' +
  'in the callee direction should be read with that in mind.</p></div>')

[void]$sb.AppendLine('</main><footer>')
[void]$sb.AppendLine("generated $((Get-Date).ToUniversalTime().ToString('s'))Z by New-ExampleGallery.ps1 &middot; the output is gitignored and regenerable; edit the generator, not this page")
[void]$sb.AppendLine('</footer></html>')

$idx = Join-Path $OutRoot 'index.html'
if ($Only) {
  # The index is built from $made, which with -Only holds ONLY the regenerated
  # questions. Writing it would silently replace a complete contents page with a
  # partial one -- the bundles for every other question would still be on disk
  # and unreachable from the index. Leave the existing page alone and say so.
  Write-Host "  NOTE: -Only was used, so $idx was NOT rewritten (it would list only the $($Only -join ', ') examples). Re-run without -Only to refresh it."
} else {
  [IO.File]::WriteAllText($idx, ($sb.ToString() -replace "`r`n", "`n" -replace "`n", "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

Write-Host ''
Write-Host ("gallery: {0} example(s) over {1} question(s){2}" -f $made.Count,
            @($made | Group-Object Question).Count,
            $(if ($failed.Count) { ", $($failed.Count) FAILED" } else { '' }))
Write-Host "contents: $idx"

[pscustomobject]@{
  Made = $made.Count; Failed = $failed.Count
  Questions = @($made | Group-Object Question).Count
  Index = $idx; Failures = $failed.ToArray()
}
