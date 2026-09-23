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
foreach ($d in @($CLI, $SRV, $DC)) {
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

# A contents page, so the gallery is browsable rather than a directory listing.
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<!doctype html><meta charset="utf-8"><title>dl-charts example gallery</title>')
[void]$sb.AppendLine('<style>body{font:15px/1.6 "Segoe UI",system-ui,sans-serif;margin:0;background:#F6F7F9;color:#131820}')
[void]$sb.AppendLine('header{padding:22px 26px;border-bottom:1px solid #DDE2E8}h1{margin:0 0 4px;font-size:22px}')
[void]$sb.AppendLine('main{padding:18px 26px}h2{margin:26px 0 8px;font-size:17px;color:#0F766E}')
[void]$sb.AppendLine('table{border-collapse:collapse;width:100%}td{padding:7px 10px;border-bottom:1px solid #E6EAEF;vertical-align:top}')
[void]$sb.AppendLine('code{font-family:Consolas,monospace;font-size:13px}.why{color:#5B6674;font-size:13.5px}')
[void]$sb.AppendLine('.db{color:#8A94A6;font-family:Consolas,monospace;font-size:12px}</style>')
[void]$sb.AppendLine('<header><h1>dl-charts &mdash; example gallery</h1>')
[void]$sb.AppendLine("<div class=`"why`">Three worked examples per question. Generated by <code>New-ExampleGallery.ps1</code> from the cloned indexes; regenerate rather than edit.</div></header><main>")
foreach ($g in ($made | Group-Object Question)) {
  [void]$sb.AppendLine("<h2>$($g.Name)</h2><table>")
  foreach ($m in $g.Group) {
    $rel = $m.Shell.Substring($m.Shell.IndexOf($m.Question))
    $rel = $rel.Replace('\', '/')
    [void]$sb.AppendLine("<tr><td><a href=`"$rel`"><code>$($m.Target)</code></a><div class=`"why`">$($m.Why)</div></td><td class=`"db`">$($m.Db)<br>$($m.Clicks) clicks</td></tr>")
  }
  [void]$sb.AppendLine('</table>')
}
[void]$sb.AppendLine('</main>')
$idx = Join-Path $OutRoot 'index.html'
[IO.File]::WriteAllText($idx, ($sb.ToString() -replace "`r`n", "`n" -replace "`n", "`r`n"), (New-Object Text.UTF8Encoding($false)))

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
