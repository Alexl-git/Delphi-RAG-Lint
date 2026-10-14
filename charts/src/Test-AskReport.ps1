<#
  Test-AskReport.ps1 -- light verification for Ask-Report.ps1 (NOT part of Test-Emitters.ps1).

  Runs in about two minutes: one round-trip on the frozen clones (~1 min) and a few
  cheap calls. Resolution cases read the engine's live manifest through `resolve-dbs`,
  which is read-only; nothing here indexes anything.

    AR-PAIR      -Project resolves the client index; report-pairs.json supplies SERVER + SQL
    AR-PAIR-IN   -In on a unit two projects hold picks the paired index
    AR-NOPAIR    a pairs file with no entry: exit 2, stderr names the file to edit
    AR-NOPROJ    neither -Project nor -In: exit 2
    AR-OUTROOT   no -OutRoot: the bundle lands under $env:TEMP\drag-lint-reports
    AR-ENV       DRAGLINT_CHARTS_ALLOW_LIVE_DB is restored -- to its old value, and to absent
    AR-RT        round-trip on the clones (overrides): stdout is BUNDLE, then the trace from `TRACE `
    AR-STALE     a stale index (the DL clone) stops with exit 3 before anything runs
    AR-NOPAIRSFILE  a pairs file that does not exist is named as missing, not as "has no entry",
                 and the message says how to configure pairs (report-pairs.example.json, R2)
    AR-NOENGINE  an -Engine that does not exist: exit 2, stderr names it (R2)
    AR-ENGINE-CHILD  an explicit -Engine is the engine the EMITTER runs, not only Ask-Report's own calls (R2 fix 1)
    AR-NODOT-NOTE    dot that cannot be RESOLVED: round-trip still answers TRACE + the NOTE naming why (R2 fix 1)
    AR-JSON      a note line starting with '[' before the engine's JSON does not break resolution
    AR-INDEX     every answer names the index(es) that answered, after BUNDLE
    AR-TARGET    a chart's own focus row is marked TARGET, not listed like a result
    AR-CAP       a capped chart prints its "+N more ... not shown" disclosure and the -Cap to raise
    AR-CAPTIONS  Ask-Report's caption table (the -Plain header phrase) equals the plugin's REPORT_QUESTIONS
    AR-DOC-RT    the DEFAULT answer (no -Plain) is `drag-lint ask`'s answer -- the default mode is delegated to the
                 engine, whose DocInsight block of the -Plain answer ChartsTests.AskVerb pins (owner answer 2, R5;
                 Report.DocInsight.ps1 and its AR-DOC-PORT check were deleted 2026-10-14 -- the formatter is the
                 engine's DRagLint.Charts.DocInsight, checked against the same fixtures by ReportTextTests)

    AR-HDR       -Plain starts with the report sentence (date, time, engine) and a COMMAND line (no -DbPath, R5)
    AR-HDR-CASE  -Question Who-Reads (any case) emits the ValidateSet id lower-cased in the sentence and the COMMAND (R13)
    AR-HDR-CMD   Get-ReportCommandLine in isolation (fixed order, display switches and index overrides dropped)
    AR-HDR-DOC   the default block holds the COMMAND once, unwrapped
    AR-ALLOWSTALE  -AllowStale on the stale DL clone answers (exit 0) and says so on stderr

  Every check of the answer's plain shape passes -Plain; the default is the DocInsight block, made by the engine.
  ENGINE: the default mode runs `drag-lint ask` -- set DRAGLINT_ENGINE to an engine that has the verb (1.28.4+).

  FRESH CLONES NEEDED: AR-OUTROOT, AR-CHART, AR-CAP and AR-RT read the CLIENT / SERVER / SQL clones under
  charts\scratch\db, and Ask-Report checks freshness first -- once a source file those clones index changes
  on disk, they stop with exit 3 (stale), which is Ask-Report working, not a regression; re-take the clones.
  AR-STALE is the mirror image: it needs the DL clone to STAY stale (5 files on 2026-09-28).
#>
[CmdletBinding()]
param(
  [string] $DbCli  = (Join-Path $PSScriptRoot '..\scratch\db\CLIENT-Micronite2027.sqlite'),
  [string] $DbSrv  = (Join-Path $PSScriptRoot '..\scratch\db\SERVER-MicroniteMW1Service.sqlite'),
  [string] $DbSql  = (Join-Path $PSScriptRoot '..\scratch\db\SQL-drag-lint-sql.sqlite'),
  [string] $DbDl   = (Join-Path $PSScriptRoot '..\scratch\db\DL-drag-lint.sqlite'),
  [string] $OutDir = (Join-Path $PSScriptRoot ('..\scratch\ask-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))),
  # the script under test; a mutated copy beside it proves a pin can go red
  [string] $AskReport = (Join-Path $PSScriptRoot 'Ask-Report.ps1')
)

$ErrorActionPreference = 'Stop'
$fail = New-Object System.Collections.ArrayList
function Fail([string] $code, [string] $msg) { [void]$fail.Add([pscustomobject]@{ Code = $code; Message = $msg }) }
function Chk([string] $code, $actual, $expected) { if ("$actual" -cne "$expected") { Fail $code "expected $expected, got $actual" } }
function Step([string] $code, [scriptblock] $body) { try { . $body } catch { Fail $code "unexpected error: $($_.Exception.Message)" } }

New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).ProviderPath
$AR = $AskReport
$PROJ = 'C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj'
$Q_FNR = 'Blueprint4.TfrmBlueprint4.FNoRecursion'

# Ask-Report as an agent runs it: a child pwsh, stdout lines + stderr text + exit code
function Invoke-Ask([string[]] $ArgList) {
  $errFile = Join-Path $OutDir ('stderr-' + [guid]::NewGuid().ToString('N') + '.txt')
  $o = & pwsh -NoProfile -File $AR @ArgList 2> $errFile
  $code = $LASTEXITCODE
  [pscustomobject]@{ Exit = $code; Out = @($o); Err = [IO.File]::ReadAllText($errFile).Trim() }
}

Write-Host 'resolution ...'
Step 'AR-PAIR' {
  $r = Invoke-Ask @('-Question', 'round-trip', '-Target', 'frmBlueprint4.dxDBGrid1FtrsVNum', '-Project', $PROJ, '-ResolveOnly')
  Chk 'AR-PAIR' "$($r.Exit)|$($r.Out -join '|')" ('0|PROJECT C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite|' +
    'SERVER C:\Projects\DB\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite|SQL C:\Projects\DB\SQL\drag-lint-sql.sqlite')
}
Step 'AR-PAIR-IN' {
  # resolve-dbs --in Blueprint4.pas names Micronite2027 AND DMTEST; the pairing file declares the first
  $r = Invoke-Ask @('-Question', 'consumers', '-Target', 'MSCLIST', '-In', 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas', '-ResolveOnly')
  Chk 'AR-PAIR-IN' "$($r.Exit)|$($r.Out -join '|')" '0|PROJECT C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite|SQL C:\Projects\DB\SQL\drag-lint-sql.sqlite'
}
Step 'AR-NOPAIR' {
  $empty = Join-Path $OutDir 'no-pairs.json'
  [IO.File]::WriteAllText($empty, '{ "pairs": [] }', (New-Object Text.ASCIIEncoding))
  $r = Invoke-Ask @('-Question', 'round-trip', '-Target', 'frmBlueprint4.dxDBGrid1FtrsVNum', '-Project', $PROJ, '-PairsFile', $empty)
  Chk 'AR-NOPAIR' $r.Exit 2
  if ($r.Err -notlike "*$empty has no entry for C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite -- add one*") { Fail 'AR-NOPAIR' "stderr does not name the pairs file to edit: $($r.Err)" }
  if ($r.Out.Count) { Fail 'AR-NOPAIR' "printed on stdout while refusing: $($r.Out -join ' | ')" }
}
Step 'AR-NOPROJ' {
  # -Plain: Ask-Report's OWN resolution (the default mode is the engine's, whose message names --project / --in)
  $r = Invoke-Ask @('-Question', 'who-writes', '-Target', $Q_FNR, '-Plain')
  Chk 'AR-NOPROJ' $r.Exit 2
  if ($r.Err -notlike '*name the project: -Project <x.dproj> or -In*') { Fail 'AR-NOPROJ' "stderr: $($r.Err)" }
}

Write-Host 'default OutRoot and the environment variable (in-process) ...'
Step 'AR-OUTROOT' {
  $tmp = Join-Path $OutDir 'tempdir'
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $oldTemp = $env:TEMP; $oldLive = [Environment]::GetEnvironmentVariable('DRAGLINT_CHARTS_ALLOW_LIVE_DB', 'Process')
  try {
    $env:TEMP = $tmp
    $env:DRAGLINT_CHARTS_ALLOW_LIVE_DB = 'sentinel'
    $o1 = & $AR -Question who-reads -Target $Q_FNR -DbPath $DbCli -Plain
    $e1 = $LASTEXITCODE; $live1 = [Environment]::GetEnvironmentVariable('DRAGLINT_CHARTS_ALLOW_LIVE_DB', 'Process')
    Remove-Item Env:\DRAGLINT_CHARTS_ALLOW_LIVE_DB -ErrorAction SilentlyContinue
    $o2 = & $AR -Question who-reads -Target $Q_FNR -DbPath $DbCli -OutRoot (Join-Path $OutDir 'explicit') -Plain
    $e2 = $LASTEXITCODE; $live2 = [Environment]::GetEnvironmentVariable('DRAGLINT_CHARTS_ALLOW_LIVE_DB', 'Process')
  } finally {
    $env:TEMP = $oldTemp
    if ($null -eq $oldLive) { Remove-Item Env:\DRAGLINT_CHARTS_ALLOW_LIVE_DB -ErrorAction SilentlyContinue } else { $env:DRAGLINT_CHARTS_ALLOW_LIVE_DB = $oldLive }
  }
  Chk 'AR-OUTROOT' "$e1|$(@($o1)[2])" "0|BUNDLE $tmp\drag-lint-reports\who-reads-Blueprint4_TfrmBlueprint4_FNoRecursion"
  if (-not (Test-Path (Join-Path $tmp 'drag-lint-reports\who-reads-Blueprint4_TfrmBlueprint4_FNoRecursion\index.html'))) { Fail 'AR-OUTROOT' 'no index.html under the default OutRoot' }
  if (Test-Path (Join-Path $PSScriptRoot '..\artifacts\who-reads-Blueprint4_TfrmBlueprint4_FNoRecursion\meta.json') -NewerThan (Get-Date).AddMinutes(-5)) { Fail 'AR-OUTROOT' 'a bundle was written under charts\artifacts' }
  Chk 'AR-ENV' "$live1|$(if ($null -eq $live2) { 'absent' } else { "[$live2]" })|$e2" 'sentinel|absent|0'
  # the chart form of the text: a CHART header, then anchored rows
  Chk 'AR-INDEX' "$(@($o1)[3])" "INDEX $([IO.Path]::GetFullPath($DbCli))"
  Chk 'AR-CHART' "$(@($o1)[4])" 'CHART who-reads Blueprint4.TfrmBlueprint4.FNoRecursion -- 0 resolved read sites reported by find-callers + 9 unbound read(s) named FNoRecursion in Blueprint4.pas / 0 routines reported by find-callers'
  if (@($o1 | Where-Object { $_ -cmatch '^  \S.* @[A-Za-z0-9_.]+\.pas(:\d+)?( -- .*)?$' }).Count -lt 1) { Fail 'AR-CHART' "no anchored row in: $($o1 -join ' | ')" }
  # AR-TARGET (same run): the focus row is marked, and only once
  $tg = @($o1 | Where-Object { $_ -clike '  TARGET *' })
  Chk 'AR-TARGET' "$($tg.Count)|$($tg -join '')" '1|  TARGET Blueprint4.TfrmBlueprint4.FNoRecursion @Blueprint4.pas:681'
  if (@($o1 | Where-Object { $_ -clike '  Blueprint4.TfrmBlueprint4.FNoRecursion @*' }).Count) { Fail 'AR-TARGET' 'the focus row is also printed as a result row' }
}

Write-Host 'the cap disclosure ...'
Step 'AR-CAP' {
  # who-writes FNoRecursion: 26 routines, the chart draws 20 (-Cap 20) and says so in a cell with no link
  $c = Invoke-Ask @('-Question', 'who-writes', '-Target', $Q_FNR, '-DbPath', $DbCli, '-OutRoot', (Join-Path $OutDir 'cap'), '-Plain')
  Chk 'AR-CAP-EXIT' "$($c.Exit)|$($c.Err)" '0|'
  $shown = @($c.Out | Where-Object { $_ -cmatch '^  TfrmBlueprint4\.' }).Count
  $disc  = @($c.Out | Where-Object { $_ -clike '  ... *not shown*' })
  Chk 'AR-CAP' "$shown|$($disc -join '')" '20|  ... +6 more routines (+6 more sites) not shown (-Cap 20; raise -Cap to see them)'
}

Write-Host 'resolution edge cases ...'
Step 'AR-NOPAIRSFILE' {
  $missing = Join-Path $OutDir 'missing-pairs.json'
  $r = Invoke-Ask @('-Question', 'round-trip', '-Target', 'frmBlueprint4.dxDBGrid1FtrsVNum', '-Project', $PROJ, '-PairsFile', $missing)
  Chk 'AR-NOPAIRSFILE' $r.Exit 2
  if ($r.Err -notlike "*missing-pairs.json not found at $missing*" -or $r.Err -like '*has no entry*') { Fail 'AR-NOPAIRSFILE' "stderr: $($r.Err)" }
  # R2: an installed copy ships only report-pairs.example.json -- the message says how to configure pairs from it
  if ($r.Err -notlike '*no pairs are configured*report-pairs.example.json*') { Fail 'AR-NOPAIRSFILE-HOW' "stderr does not say how to configure pairs: $($r.Err)" }
  if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\report-pairs.example.json'))) { Fail 'AR-NOPAIRSFILE-HOW' 'charts\report-pairs.example.json is missing' }
}
Step 'AR-NOENGINE' {
  # R2: an -Engine that does not exist is a setup stop (exit 2) that names it -- never a silent switch to another engine
  $r = Invoke-Ask @('-Question', 'who-writes', '-Target', 'X.Y', '-Project', $PROJ, '-Engine', (Join-Path $OutDir 'no-such-engine.exe'), '-ResolveOnly')
  Chk 'AR-NOENGINE' "$($r.Exit)|$($r.Err -like '*-Engine*no-such-engine.exe does not exist*')" '2|True'
}
Step 'AR-ENGINE-CHILD' {
  # fix round 1: an explicit -Engine reaches the EMITTER, not only Ask-Report's own resolve/freshness calls. The stand-in
  # is a .ps1 (run in-process by `& $Engine`, so its arguments arrive intact) that logs every call and forwards it.
  $marker = Join-Path $OutDir 'engine-child-calls.txt'
  $standIn = Join-Path $OutDir 'engine-child.ps1'
  $real = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
  [IO.File]::WriteAllText($standIn, ("Add-Content -LiteralPath '$marker' -Value (`$args -join ' ')`r`n& '$real' @args`r`nexit `$LASTEXITCODE`r`n"), (New-Object Text.ASCIIEncoding))
  $r = Invoke-Ask @('-Question', 'who-writes', '-Target', $Q_FNR, '-DbPath', $DbCli, '-OutRoot', (Join-Path $OutDir 'engchild'), '-Engine', $standIn, '-Plain')
  Chk 'AR-ENGINE-CHILD-EXIT' "$($r.Exit)|$($r.Err)" '0|'
  $calls = @($(if (Test-Path -LiteralPath $marker) { Get-Content -LiteralPath $marker }))
  $fromEmitter = @($calls | Where-Object { $_ -notlike '*SELECT 1 AS n*' })
  if (-not $fromEmitter.Count) { Fail 'AR-ENGINE-CHILD' "the emitter did not run the -Engine stand-in ($($calls.Count) call(s), all Ask-Report's own)" }
}
Step 'AR-NODOT-NOTE' {
  # fix round 1: when dot RESOLUTION throws (DRAGLINT_DOT set to a missing file), round-trip still answers its text plus
  # the NOTE -- not only when dot fails at run time
  $prevDot = [Environment]::GetEnvironmentVariable('DRAGLINT_DOT', 'Process')
  try {
    $env:DRAGLINT_DOT = Join-Path $OutDir 'no-such-dot.exe'
    $r = Invoke-Ask @('-Question', 'round-trip', '-Target', 'frmBlueprint4.dxDBGrid1FtrsVNum', '-DbPath', $DbCli, '-ServerDbPath', $DbSrv, '-SqlDbPath', $DbSql, '-OutRoot', (Join-Path $OutDir 'nodot'), '-Plain')
  } finally {
    if ($null -eq $prevDot) { Remove-Item Env:\DRAGLINT_DOT -ErrorAction SilentlyContinue } else { $env:DRAGLINT_DOT = $prevDot }
  }
  Chk 'AR-NODOT-EXIT' "$($r.Exit)|$($r.Err)" '0|'
  if ("$($r.Out[6])" -cnotlike 'TRACE *') { Fail 'AR-NODOT-NOTE' "the text does not begin with TRACE: $($r.Out[6])" }
  $note = @($r.Out | Where-Object { $_ -clike 'NOTE the chart could not be drawn:*' })
  if ($note.Count -ne 1 -or $note[0] -notlike '*DRAGLINT_DOT*no-such-dot.exe*') { Fail 'AR-NODOT-NOTE' "no NOTE naming the unresolved dot: $($note -join ' | ')" }
}
Step 'AR-JSON' {
  # a stand-in engine whose stdout starts with a '[note]' line, then the JSON document
  $fakeEng = Join-Path $OutDir 'fake-engine.cmd'
  $cmdLines = @('@echo off', 'echo [note] loaded defaults', 'echo {"project":"x","db":"C:\\fake\\_D-RAG\\a.sqlite"}')
  [IO.File]::WriteAllText($fakeEng, (($cmdLines -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $proj = Join-Path $OutDir 'a.dproj'; Set-Content $proj 'x' -Encoding ascii
  $r = Invoke-Ask @('-Question', 'who-writes', '-Target', 'X.Y', '-Project', $proj, '-Engine', $fakeEng, '-ResolveOnly')
  Chk 'AR-JSON' "$($r.Exit)|$($r.Out -join '|')|$($r.Err)" '0|PROJECT C:\fake\_D-RAG\a.sqlite|'
}

Write-Host 'round-trip on the clones (about a minute) ...'
Step 'AR-RT' {
  $r = Invoke-Ask @('-Question', 'round-trip', '-Target', 'frmBlueprint4.dxDBGrid1FtrsVNum', '-DbPath', $DbCli, '-ServerDbPath', $DbSrv, '-SqlDbPath', $DbSql, '-OutRoot', (Join-Path $OutDir 'rt'), '-Plain')
  Chk 'AR-RT-EXIT' "$($r.Exit)|$($r.Err)" '0|'
  $b = "$($r.Out[2])"
  if ($b -cnotlike 'BUNDLE *') { Fail 'AR-RT' "line 3 is not BUNDLE <folder>: $b" }
  Chk 'AR-INDEX-RT' (($r.Out[3..5]) -join '|') ("INDEX $([IO.Path]::GetFullPath($DbCli))|INDEX $([IO.Path]::GetFullPath($DbSrv)) (server)|INDEX $([IO.Path]::GetFullPath($DbSql)) (sql)")
  if ("$($r.Out[6])" -cnotlike 'TRACE *') { Fail 'AR-RT' "the text does not begin with TRACE: $($r.Out[6])" }
  $tr = Join-Path $b.Substring(7) 'trace.dlgraph'
  if (-not (Test-Path $tr)) { Fail 'AR-RT' "no trace.dlgraph in $b" }
  elseif ((($r.Out | Select-Object -Skip 6) -join "`r`n") -cne [IO.File]::ReadAllText($tr).TrimEnd("`r", "`n")) { Fail 'AR-RT' 'stdout after BUNDLE is not the whole trace.dlgraph' }
  # AR-DOC-RT: the same question WITHOUT -Plain answers exactly what `drag-lint ask` answers (the delegated default mode)
  $d = Invoke-Ask @('-Question', 'round-trip', '-Target', 'frmBlueprint4.dxDBGrid1FtrsVNum', '-DbPath', $DbCli, '-ServerDbPath', $DbSrv, '-SqlDbPath', $DbSql, '-OutRoot', (Join-Path $OutDir 'rt-doc'))
  . (Join-Path $PSScriptRoot 'Emit-Common.ps1')   # Resolve-DragLintEngine
  $want = (& (Resolve-DragLintEngine '') ask round-trip --target 'frmBlueprint4.dxDBGrid1FtrsVNum' --db $DbCli --server-db $DbSrv --sql-db $DbSql --out-root (Join-Path $OutDir 'rt-doc-engine') 2>$null) -join "`r`n"
  # the two runs are minutes apart: the header's time of day is the one thing that legitimately differs
  $tm = { param($s) $s -replace 'asked on (\d{4}-\d{2}-\d{2}) \d{2}:\d{2}', 'asked on $1 HH:MM' }
  Chk 'AR-DOC-RT' "$($d.Exit)|$(@($d.Out)[0])|$(@($d.Out)[-1])|$((& $tm (($d.Out) -join "`r`n")) -ceq (& $tm $want))" '0|/// <remarks>|/// </remarks>|True'
}

Write-Host 'header contract (section 3) ...'
Step 'AR-HDR' {
  $r = Invoke-Ask @('-Question', 'who-reads', '-Target', $Q_FNR, '-DbPath', $DbCli, '-AllowStale', '-OutRoot', (Join-Path $OutDir 'hdr'), '-Plain')
  . (Join-Path $PSScriptRoot 'Emit-Common.ps1')   # Resolve-DragLintEngine
  $ver = (& (Resolve-DragLintEngine '') info --json | ConvertFrom-Json).version
  $sentOk = $r.Out[0] -cmatch ('^Who reads this field \(drag-lint report who-reads\) for ' + [regex]::Escape($Q_FNR) + ', asked on \d{4}-\d{2}-\d{2} \d{2}:\d{2}, engine ' + [regex]::Escape($ver) + '\.$')
  # R5: the COMMAND never carries -DbPath (or any index override)
  Chk 'AR-HDR' "$($r.Exit)|$sentOk|$($r.Out[1])|$($r.Out[2] -clike 'BUNDLE *')" "0|True|COMMAND who-reads -Target `"$Q_FNR`"|True"
}
Step 'AR-HDR-CASE' {
  # R13: the header names the MATCHED ValidateSet id, lower-cased -- never the caller's spelling, so two
  # answers to the same question carry the same id and ParseReportHeader ([a-z0-9-]+) reads both
  $r = Invoke-Ask @('-Question', 'Who-Reads', '-Target', $Q_FNR, '-DbPath', $DbCli, '-AllowStale', '-OutRoot', (Join-Path $OutDir 'hdrcase'), '-Plain')
  Chk 'AR-HDR-CASE' "$($r.Exit)|$($r.Out[0] -clike '* (drag-lint report who-reads) for *')|$($r.Out[1])" "0|True|COMMAND who-reads -Target `"$Q_FNR`""
}
Step 'AR-HDR-CMD' {
  # the builder in isolation: dot-source only the function out of Ask-Report.ps1 (the script itself runs on load)
  $src = [IO.File]::ReadAllText($AR)
  $m = [regex]::Match($src, '(?ms)^function Get-ReportCommandLine.*?^\}\r?$')
  if (-not $m.Success) { Fail 'AR-HDR-CMD' 'Get-ReportCommandLine is not defined in Ask-Report.ps1' }
  else {
    . ([scriptblock]::Create($m.Value))
    Chk 'AR-HDR-CMD' (Get-ReportCommandLine 'who-writes' 'T' @{ Project = 'C:\P\A.dproj'; Depth = 3; Open = $true; Plain = $true }) 'COMMAND who-writes -Target "T" -Project "C:\P\A.dproj" -Depth 3'
    Chk 'AR-HDR-CMD-ALL' (Get-ReportCommandLine 'path' 'A' @{ To = 'B'; In = 'C:\P\u.pas'; Cap = 5; SurfaceCap = 6; Control = 'c1'; Mode = 'x'; MaxRows = 7; DbPath = 'zz' }) 'COMMAND path -Target "A" -To "B" -In "C:\P\u.pas" -Cap 5 -SurfaceCap 6 -Control "c1" -Mode x -MaxRows 7'
  }
}
Step 'AR-HDR-DOC' {
  $r = Invoke-Ask @('-Question', 'who-reads', '-Target', $Q_FNR, '-DbPath', $DbCli, '-AllowStale', '-OutRoot', (Join-Path $OutDir 'hdrdoc'))
  $ci = @(0..($r.Out.Count - 1) | Where-Object { $r.Out[$_] -clike '/// COMMAND who-reads -Target *' })
  $nextOk = $ci.Count -eq 1 -and $r.Out[$ci[0] + 1] -ceq '///'
  Chk 'AR-HDR-DOC' "$($r.Exit)|$($r.Out[1] -clike '/// Who reads this field (drag-lint report who-reads) for *')|$($ci.Count)|$nextOk" '0|True|1|True'
}
Step 'AR-ALLOWSTALE' {
  $r = Invoke-Ask @('-Question', 'deps', '-Target', 'DRagLint.CLI', '-DbPath', $DbDl, '-AllowStale', '-OutRoot', (Join-Path $OutDir 'allowstale'), '-Plain')
  Chk 'AR-ALLOWSTALE' "$($r.Exit)|$($r.Err -like '*ask-report: note -- stale index allowed by -AllowStale*')" '0|True'
}

Write-Host 'the caption table against the plugin ...'
Step 'AR-CAPTIONS' {
  # this checkout's plugin source, not a fixed main-tree path: a worktree must compare against its OWN catalog
  $pas = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\src\delphi-plugin\DragLint.Plugin.ReportText.pas'))
  $src = [IO.File]::ReadAllText($AR)
  $m = [regex]::Match($src, '(?ms)^\$script:ReportCaptions = \[ordered\]@\{.*?^\}\r?$')
  if (-not $m.Success) { Fail 'AR-CAPTIONS' 'the caption table is not defined in Ask-Report.ps1' }
  elseif (-not (Test-Path -LiteralPath $pas)) { Write-Host "  AR-CAPTIONS skipped: $pas is not on this machine" }
  else {
    . ([scriptblock]::Create($m.Value))
    $pq = @([regex]::Matches([IO.File]::ReadAllText($pas), "\(Id: '([^']+)'\s*; Caption: '((?:[^']|'')*)'") | ForEach-Object { "$($_.Groups[1].Value)=$($_.Groups[2].Value -replace "''", "'")" })
    $mine = @($script:ReportCaptions.Keys | ForEach-Object { "$_=$($script:ReportCaptions[$_])" })
    Chk 'AR-CAPTIONS' "$($pq.Count)|$(($pq -join ';') -ceq ($mine -join ';'))" '26|True'
  }
}
Write-Host 'freshness ...'
Step 'AR-STALE' {
  $r = Invoke-Ask @('-Question', 'who-calls', '-Target', 'DRagLint.CLI.Main', '-DbPath', $DbDl, '-OutRoot', (Join-Path $OutDir 'stale'))
  Chk 'AR-STALE' $r.Exit 3
  if ($r.Err -notlike "*stale index*$([IO.Path]::GetFullPath($DbDl))*file(s) changed since it was indexed*") { Fail 'AR-STALE' "stderr: $($r.Err)" }
  if (Test-Path (Join-Path $OutDir 'stale')) { Fail 'AR-STALE' 'a bundle folder was created for a stale index' }
}

if ($fail.Count -eq 0) { Write-Host '  PASS -- Ask-Report resolves, refuses, restores and answers as specified.' -ForegroundColor Green; exit 0 }
Write-Host "  FAIL -- $($fail.Count) problem(s):" -ForegroundColor Red
$fail | ForEach-Object { Write-Host ("    [{0}] {1}" -f $_.Code, $_.Message) }
exit 1
