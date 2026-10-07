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
  PLAN-next-five-verbs.md for why: a live run risks a lock, and a live DB can be
  re-indexed mid-run. Since 2026-09-27 the engine is the shared deployed one;
  the page prints the version it reports (--version, read at run time) and the
  clones' own schema_meta stamps -- never a number written here by hand.
#>
[CmdletBinding()]
param(
  [string] $DbDir   = (Join-Path $PSScriptRoot '..\scratch\db'),
  [string] $OutRoot = (Join-Path $PSScriptRoot '..\docs\examples'),
  [string[]] $Only,                      # regenerate just these questions
  [switch] $KeepGoing,                   # report failures instead of stopping
  [string] $Engine = ''                  # '' = Resolve-DragLintEngine (Emit-Common.ps1), as every emitter finds it
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
# The SQL-SCRIPT index (12 Firebird .SQL files): consumers / feeds-from /
# lands-where read tables, columns, triggers and procedures from it.
$SQL = Join-Path $DbDir 'SQL-drag-lint-sql.sqlite'
foreach ($d in @($CLI, $SRV, $DC, $DL, $MT, $SQL)) {
  if (-not (Test-Path $d)) { throw "clone missing: $d -- see PLAN-next-five-verbs.md for how they are made" }
}

# final-review I3: the page states the engine and the clone stamps it READ now -- the engine's own --version and the
# CLIENT clone's schema_meta fingerprints -- never a version written here by hand (one went stale at 1.18.0-alpha
# while the deployed engine moved to 1.19.1-alpha)
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')   # functions only; Resolve-DragLintEngine
$EngineExe = Resolve-DragLintEngine $Engine
$engVer = @(& $EngineExe --version 2>$null | Where-Object { $_ -match '^drag-lint \S+$' } | Select-Object -First 1)
$engVer = $(if ($engVer.Count) { ($engVer[0] -replace '^drag-lint\s+', '').Trim() } else { 'unknown (--version printed no version line)' })
$meta = @{}
try {
  $mj = (& $EngineExe sql --db $CLI --query "SELECT key, value FROM schema_meta WHERE key IN ('indexer_fingerprint', 'resolver_fingerprint', 'indexed_at_unix')" --format json 2>$null) -join "`n" | ConvertFrom-Json
  foreach ($row in $mj.rows) { $meta[[string]$row[0]] = [string]$row[1] }
} catch { }
$cloneVer = $(if ($meta.Count) { "$((($meta['indexer_fingerprint']) -split ';')[0]) / $((($meta['resolver_fingerprint']) -split ';')[0])" } else { 'unknown (schema_meta not read)' })
$cloneAt = $(if ($meta['indexed_at_unix'] -match '^\d+$') { [DateTimeOffset]::FromUnixTimeSeconds([long]$meta['indexed_at_unix']).UtcDateTime.ToString("yyyy-MM-dd HH:mm 'UTC'") } else { 'an unstamped time' })
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
  @{ Q='effects';      T='uMain.TfrmMAIN.GetConnection';                  D=$CLI; A=@{}; Why='PURE. The summary is NULL, which the naive reading calls "not analysed" -- and would be wrong for 2,918 CLIENT methods' }
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

  # PLAN-last-four-verbs. Every target below is one the gate pins, so the numbers
  # in these notes are the gate's numbers, not a second measurement.
  @{ Q='exception-paths';  T='uJobList.ViewModel.TJobListViewModel.BuildSchema'; D=$CLI; A=@{}; Why='a SOLID catch two levels up: EDatabaseError is caught at LoadAllAsync:632, where the call sits inside the try (checked by a nesting scan); 3 handlers that do not guard the call are counted, not drawn' }
  @{ Q='exception-paths';  T='MStreams.TABZMemoryStream.ReadBuffer';            D=$CLI; A=@{}; Why='fan-in: 140 callers walked, 139 evaluated for EReadError. It is caught on 2 call edges in AutoTestSetupDefaults, which ALSO lets it escape on a third -- one caller, both answers' }
  @{ Q='exception-paths';  T='BASICSF.CopyRecords';                             D=$CLI; A=@{}; Why='the source-only rows: bare except, raise; and raise E, drawn dashed [inferred] because directive state is not evaluated' }

  @{ Q='consumers';        T='CAUSFAIL';         D=$SRV; A=@{SqlDbPath=$SQL}; Why='table form: 1 certain reader and 1 certain writer by fact (engine D18, fixed in extractor 1.19, assembles SQL across SQL.Add lines -- PrepareLoadQuery was an INFERRED reader before), 3 triggers' }
  @{ Q='consumers';        T='CAUSFAIL.REASON';  D=$SRV; A=@{SqlDbPath=$SQL}; Why='column form: 2 server routines, trigger CAUSFAIL_BIU5, and 1 of 7 REASON grid bindings -- the other 6 resolve to other tables' }
  @{ Q='consumers';        T='FOLDERS';          D=$SRV; A=@{SqlDbPath=$SQL}; Why='declared TWICE in the scripts; the newest file wins (79 columns, the live count), and the collapse is printed' }

  @{ Q='feeds-from';       T='frmCausFail.colREASON';                         D=$CLI; A=@{SqlDbPath=$SQL}; Why='the whole chain, 5 graded hops: grid column &rarr; dsrCausFail &rarr; dataset assignment &rarr; view model &rarr; CAUSFAIL.REASON' }
  @{ Q='feeds-from';       T='frmBlueprint4.edtF1';                           D=$CLI; A=@{SqlDbPath=$SQL}; Why='the DFM says dmlSystem2.dsrFolder, which is not in this project [dangling]; the code re-points it at Blueprint4.pas:1015 -- both are drawn' }
  @{ Q='feeds-from';       T='frmDefineSerialNumbers.cxGrid1DBTableView1SID1'; D=$CLI; A=@{SqlDbPath=$SQL}; Why='AMBIGUOUS: three candidate tables (SERID, SERREAD, SERPART). The chain stops and lists them rather than pick one' }

  @{ Q='lands-where';      T='uCAUSFAIL.TmcCAUSFAIL.REASON';       D=$CLI; A=@{ServerDbPath=$SRV; SqlDbPath=$SQL}; Why='ORM property &rarr; the SERVER write and read path (2 certain member accesses, 2 inferred SQL literals) &rarr; CAUSFAIL.REASON by naming convention &rarr; trigger CAUSFAIL_BIU5' }
  @{ Q='lands-where';      T='uSTATIONS.TmcSTATIONS.GRIDS';        D=$CLI; A=@{ServerDbPath=$SRV; SqlDbPath=$SQL}; Why='column state server-sql: in NO script declaration, yet the server''s SQL writes it -- the scripts lag the schema, so "computed or UI-only" would be false' }
  @{ Q='lands-where';      T='uFOLDERCOUNT.TmcFOLDERCOUNT.TABLE';  D=$CLI; A=@{ServerDbPath=$SRV; SqlDbPath=$SQL}; Why='declared as the quoted identifier "TABLE" in MS1.SQL:3848 -- extracted since extractor 1.19 (engine D19), so an ordinary column; before that it was the one real column in the quoted state' }
  @{ Q='lands-where';      T='uINSPRSLT.TmcINSPRSLT.DistHist';     D=$CLI; A=@{ServerDbPath=$SRV; SqlDbPath=$SQL}; Why='column state not-a-column: named by no script and no server SQL -- computed or UI-only, and the DB side stays unanchored' }

  # round-trip (spec 2026-09-27) answers in TEXT: its bundle is trace.dlgraph shown in a <pre>, under the chart drawn from it (R5).
  # The three targets are the gate's (E-RT0 / RT-N1 / RT-N2), so the numbers below are the gate's numbers.
  @{ Q='round-trip';       T='frmBlueprint4.dxDBGrid1OperationVName'; D=$CLI; A=@{ServerDbPath=$SRV; SqlDbPath=$SQL}; Why='a grid column to OPERAT.NAME and both ways through the pipe: 76 steps, 31 conditions, 4 crossings, 2 unresolved (the statement for the posted row and the SELECT text live in FIB$ rows the clones do not hold, E4); ALSO 9 rows, owner-accepted 2026-09-28 (all callers count; dataset scope; anchors only)' }
  @{ Q='round-trip';       T='frmBlueprint4.cxGroupBox16';            D=$CLI; A=@{ServerDbPath=$SRV; SqlDbPath=$SQL}; Why='a control that is NOT data-bound: one STOPS saying why, and every later section notes it was not walked -- the title claims no reach' }
  @{ Q='round-trip';       T='OPERAT.NAME';                           D=$CLI; A=@{ServerDbPath=$SRV; SqlDbPath=$SQL}; Why='a TABLE.COLUMN that five datasets load: one STOPS naming all five, never a guess -- pass the control or the dataset field instead' }
)

if ($Only) { $EX = @($EX | Where-Object { $Only -contains $_.Q }) }

$made = New-Object System.Collections.ArrayList
$failed = New-Object System.Collections.ArrayList
# the charts are drawn by the SAME engine the page names (fix round 1): every emitter resolves DRAGLINT_ENGINE first,
# so it is set to the resolved full path for the loop and restored after (absent stays absent)
$prevEngEnv = [Environment]::GetEnvironmentVariable('DRAGLINT_ENGINE', 'Process')
$env:DRAGLINT_ENGINE = $EngineExe
try {
foreach ($e in $EX) {
  $dir = Join-Path $OutRoot $e.Q
  New-Item -ItemType Directory -Force $dir | Out-Null
  $label = "{0,-15} {1}" -f $e.Q, $e.T
  try {
    $splat = @{ Question = $e.Q; Target = $e.T; DbPath = $e.D; OutRoot = $dir } + $e.A
    $r = & (Join-Path $PSScriptRoot 'New-DiagramArtifact.ps1') @splat 6>$null
    if (-not (Test-Path $r.Shell)) { throw 'no index.html produced' }
    # a TEXT bundle (round-trip): its @file:line anchors are links into the IDE (DOC-R1), counted apart from chart click targets
    $isText = Test-Path (Join-Path $r.Bundle 'trace.dlgraph')
    [void]$made.Add([pscustomobject]@{
      Question = $e.Q; Target = $e.T; Db = [IO.Path]::GetFileNameWithoutExtension($e.D)
      Why = $e.Why; Shell = $r.Shell; Clicks = $r.ClickTargets; IsText = $isText
      Bytes = (Get-Item $r.Shell).Length
    })
    Write-Host ("  OK   {0}  ({1} {2})" -f $label, $r.ClickTargets, $(if ($isText) { 'text anchors' } else { 'click targets' }))
  } catch {
    [void]$failed.Add([pscustomobject]@{ Question = $e.Q; Target = $e.T; Error = $_.Exception.Message })
    Write-Host ("  FAIL {0}  -- {1}" -f $label, $_.Exception.Message)
    if (-not $KeepGoing) { throw }
  }
}
} finally {
  if ($null -eq $prevEngEnv) { Remove-Item Env:\DRAGLINT_ENGINE -ErrorAction SilentlyContinue } else { $env:DRAGLINT_ENGINE = $prevEngEnv }
}

# ---- the central index -------------------------------------------------------
#
# This page covers the WHOLE catalogue, not just what happens to have samples.
# A gallery that lists only the shipped questions quietly answers "what can
# dl-charts do?" with "whatever is finished", and the unfinished rows are the
# ones a reviewer most needs to see -- with the REASON, so "not here yet" can be
# told apart from "cannot be done".
#
# The catalogue is the same 27 rows as charts\STATUS-questions.md. Keep them in
# step: this list is the page's own copy and nothing checks it against that doc.
$CATALOGUE = @(
  @{ Q='butterfly';       Sel='method';          St='shipped'
     Note='Caller and callee walks follow resolved <code>call_edges</code>, and only RESOLVED calls are walked. Engine D1 (a parenless call such as <code>N := NextId;</code> never bound) was FIXED in resolver 1.7/1.8 -- CLIENT call edges 20,409 &rarr; 23,790 -- but a call the resolver still cannot bind is missing, so a short list remains a lower bound.' }
  @{ Q='deps';            Sel='unit';            St='shipped' }
  @{ Q='who-calls';       Sel='method';          St='shipped'
     Note='Caller and callee walks follow resolved <code>call_edges</code>, and only RESOLVED calls are walked. Engine D1 (a parenless call such as <code>N := NextId;</code> never bound) was FIXED in resolver 1.7/1.8 -- CLIENT call edges 20,409 &rarr; 23,790 -- but a call the resolver still cannot bind is missing, so a short list remains a lower bound.' }
  @{ Q='what-it-calls';   Sel='method';          St='shipped'
     Note='Caller and callee walks follow resolved <code>call_edges</code>, and only RESOLVED calls are walked. Engine D1 (a parenless call such as <code>N := NextId;</code> never bound) was FIXED in resolver 1.7/1.8 -- CLIENT call edges 20,409 &rarr; 23,790 -- but a call the resolver still cannot bind is missing, so a short list remains a lower bound.' }
  @{ Q='who-writes';      Sel='field/property';  St='shipped'
     Note='The writers wing is what <code>find-callers</code> reports: member-access writes AND, since engine 1.18 (D31), a BARE in-class assignment bound to the member (<code>FConnected := True</code>). A write or read the index still leaves unbound (e.g. inside a <code>with</code> body; bare in-class reads) is listed by name, never counted in a wing, and no count reads as a bare zero beside it.' }
  @{ Q='who-reads';       Sel='field/property';  St='shipped' }
  @{ Q='hierarchy';       Sel='type';            St='shipped' }
  @{ Q='class-surface';   Sel='type';            St='shipped' }
  @{ Q='event-wiring';    Sel='form class';      St='shipped' }
  @{ Q='touches-tables';  Sel='method';          St='shipped' }
  @{ Q='lifecycle';       Sel='form class';      St='shipped' }
  @{ Q='cycles';          Sel='unit/project';    St='shipped' }
  @{ Q='wiring';          Sel='interface';       St='shipped' }
  @{ Q='effects';         Sel='method';          St='shipped'
     Note='Engine D12 (a function''s own-name result assignment <code>F := X</code> scored as a GLOBAL write; 31 CLIENT functions on the 1.18 clone) is FIXED in extractor 1.19: 0 such witnesses on any clone. The chart keeps the guard -- a <code>g</code> whose witness names the routine itself is moved to a dashed D12 disclosure -- and it no longer fires.' }
  @{ Q='architecture';    Sel='project';         St='shipped' }

  @{ Q='protocol-trace';  Sel='command / wire field'; St='shipped' }
  @{ Q='protocol-trace';  Sel='method';          St='shipped' }
  @{ Q='crosses-boundary';Sel='method';          St='shipped' }
  @{ Q='change-impact';   Sel='method/type';     St='shipped'
     Note='Caller and callee walks follow resolved <code>call_edges</code>, and only RESOLVED calls are walked. Engine D1 (a parenless call such as <code>N := NextId;</code> never bound) was FIXED in resolver 1.7/1.8 -- CLIENT call edges 20,409 &rarr; 23,790 -- but a call the resolver still cannot bind is missing, so a short list remains a lower bound.' }
  @{ Q='tested-by';       Sel='any symbol';      St='shipped' }
  @{ Q='shown-where';     Sel='db column';       St='shipped' }

  @{ Q='exception-paths'; Sel='method';          St='shipped'
     Note='The index has no raise/handle ref kind, so each exception ref is CLASSIFIED from the source token before it (<code>raise</code> / <code>on E:</code>), on a freshness-checked file. A solid catch needs the call site inside the handler''s try. The caller walk is over resolved call edges only (engine D1 fixed in resolver 1.7/1.8; an unbindable call is still missing), and a walk that ends says &ldquo;no resolved caller&rdquo;, never &ldquo;unhandled&rdquo;.' }
  @{ Q='consumers';       Sel='table/column';    St='shipped'
     Note='Derived (path A; <code>orm_links</code> and <code>fb_*</code> are 0 rows): SQL facts are [certain], upper-case SQL-verb literals [inferred], because <code>sql_reads</code> misses SQL passed through a VARIABLE (<code>SQL.Add(sTmp)</code>: 38 of the 40 SERVER DataService loads still without a read fact) -- the SQL.Add-across-lines case, engine D18, is fixed in extractor 1.19. The schema is the SQL SCRIPTS, not the live database: 5 live <code>PDF_*</code> tables are absent.' }
  @{ Q='feeds-from';      Sel='control';         St='shipped'
     Note='DFM DataSource &rarr; dataset &rarr; view model &rarr; TABLE.COLUMN, every hop graded. Past a dangling designer datasource it follows the code re-point, as the round-trip does; it stops rather than guess on a re-point with several right-hand sides, an interface-typed view model or several candidate tables; 471 of 808 field-bound CLIENT controls reach one table, and each chart prints that coverage.' }
  @{ Q='lands-where';     Sel='ORM property / field'; St='shipped'
     Note='The TABLE.COLUMN hop is a naming CONVENTION, drawn [inferred] with its measured coverage (1,992 of 1,997 table-named properties). Column states: column, older-only, quoted, server-sql, not-a-column. Reads three clones: CLIENT, SERVER and SQL.' }

  @{ Q='round-trip';      Sel='control / field / TABLE.COLUMN'; St='shipped'
     Note='The answer is a Form A document (<code>trace.dlgraph</code>) and, since R5 (2026-10-06), the chart drawn FROM it (lanes client / pipe / server / database, every guard verbatim under its step, anything not drawn named in the Legend); each <code>@File.pas:line</code> anchor is a <code>draglint://</code> link into the IDE. Conditions are source text from sha256-fresh files (the try/except and case-header forms are marked); guards see only the innermost enclosing <code>if</code> (engine ask E1), and OMITS reads every enclosing <code>if</code> up to a loop or case arm; a direction that stops after the anchor leaves its later sections noted &ldquo;not walked&rdquo; and the title claims only the walked direction; a hop the index cannot make is a numbered STOPS counted as unresolved; ALSO is owner-accepted (2026-09-28): all callers count; dataset scope; anchors only.' }

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
[void]$sb.AppendLine('<div class="sub">Every question in the catalogue, whether or not it is built yet. Worked examples open a real chart &mdash; the rows are live anchors, so a click opens the file in a running RAD Studio &mdash; except <code>round-trip</code>, whose answer is a Form A text document with <code>@file:line</code> anchors as text. The unbuilt rows carry the reason they are unbuilt, because &ldquo;not here yet&rdquo; and &ldquo;cannot be done&rdquo; are different answers.</div>')
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
  # A shipped question can still carry a CAVEAT -- an engine defect it discloses
  # or a limit of the route it takes. It is printed above the cards, not hidden
  # in a tooltip, because it changes how every card below it reads.
  if ($c.Note) { [void]$sb.AppendLine("<div class=`"why`"><b>caveat:</b> $($c.Note)</div>") }
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
    [void]$sb.AppendLine("<div class=`"foot`"><span>$($m.Db)</span><span>$(if ($m.IsText) { "text document, $($m.Clicks) @file:line anchors (linked)" } else { "$($m.Clicks) click targets" })</span></div>")
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
  "Engine $engVer (the shared deployed engine, as its --version reports it) against clones at " +
  "$cloneVer (the CLIENT clone's schema_meta), indexed $cloneAt; the clones freeze the numbers so a " +
  'live re-index cannot move them underneath a run.</p></div>')

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
