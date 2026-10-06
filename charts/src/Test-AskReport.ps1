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
    AR-JSON      a note line starting with '[' before the engine's JSON does not break resolution
    AR-INDEX     every answer names the index(es) that answered, after BUNDLE
    AR-TARGET    a chart's own focus row is marked TARGET, not listed like a result
    AR-CAP       a capped chart prints its "+N more ... not shown" disclosure and the -Cap to raise
    AR-DOC-PORT  Report.DocInsight.ps1 gives, byte for byte, what the IDE plugin's own formatter wrote
                 (charts\fixtures\docinsight\*.expected.txt) for the same answers
    AR-DOC-CAPTIONS  its caption table equals the plugin's REPORT_QUESTIONS (read from the plugin source)
    AR-DOC-RT    the DEFAULT answer (no -Plain) is the DocInsight block of the -Plain answer (owner answer 2, R5)

  Every check of the answer's plain shape passes -Plain; the default is the DocInsight block.

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
  $r = Invoke-Ask @('-Question', 'who-writes', '-Target', $Q_FNR)
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
  Chk 'AR-OUTROOT' "$e1|$(@($o1)[0])" "0|BUNDLE $tmp\drag-lint-reports\who-reads-Blueprint4_TfrmBlueprint4_FNoRecursion"
  if (-not (Test-Path (Join-Path $tmp 'drag-lint-reports\who-reads-Blueprint4_TfrmBlueprint4_FNoRecursion\index.html'))) { Fail 'AR-OUTROOT' 'no index.html under the default OutRoot' }
  if (Test-Path (Join-Path $PSScriptRoot '..\artifacts\who-reads-Blueprint4_TfrmBlueprint4_FNoRecursion\meta.json') -NewerThan (Get-Date).AddMinutes(-5)) { Fail 'AR-OUTROOT' 'a bundle was written under charts\artifacts' }
  Chk 'AR-ENV' "$live1|$(if ($null -eq $live2) { 'absent' } else { "[$live2]" })|$e2" 'sentinel|absent|0'
  # the chart form of the text: a CHART header, then anchored rows
  Chk 'AR-INDEX' "$(@($o1)[1])" "INDEX $([IO.Path]::GetFullPath($DbCli))"
  Chk 'AR-CHART' "$(@($o1)[2])" 'CHART who-reads Blueprint4.TfrmBlueprint4.FNoRecursion -- 0 resolved read sites reported by find-callers + 9 unbound read(s) named FNoRecursion in Blueprint4.pas / 0 routines reported by find-callers'
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
  $b = "$($r.Out[0])"
  if ($b -cnotlike 'BUNDLE *') { Fail 'AR-RT' "line 1 is not BUNDLE <folder>: $b" }
  Chk 'AR-INDEX-RT' (($r.Out[1..3]) -join '|') ("INDEX $([IO.Path]::GetFullPath($DbCli))|INDEX $([IO.Path]::GetFullPath($DbSrv)) (server)|INDEX $([IO.Path]::GetFullPath($DbSql)) (sql)")
  if ("$($r.Out[4])" -cnotlike 'TRACE *') { Fail 'AR-RT' "the text does not begin with TRACE: $($r.Out[4])" }
  $tr = Join-Path $b.Substring(7) 'trace.dlgraph'
  if (-not (Test-Path $tr)) { Fail 'AR-RT' "no trace.dlgraph in $b" }
  elseif ((($r.Out | Select-Object -Skip 4) -join "`r`n") -cne [IO.File]::ReadAllText($tr).TrimEnd("`r", "`n")) { Fail 'AR-RT' 'stdout after BUNDLE is not the whole trace.dlgraph' }
  # AR-DOC-RT: the same question WITHOUT -Plain answers the DocInsight block the IDE's Reports menu makes of that text
  $d = Invoke-Ask @('-Question', 'round-trip', '-Target', 'frmBlueprint4.dxDBGrid1FtrsVNum', '-DbPath', $DbCli, '-ServerDbPath', $DbSrv, '-SqlDbPath', $DbSql, '-OutRoot', (Join-Path $OutDir 'rt-doc'))
  . (Join-Path $PSScriptRoot 'Report.DocInsight.ps1')
  $want = (Format-ReportAsDocInsight 'round-trip' 'frmBlueprint4.dxDBGrid1FtrsVNum' (Get-Date) ($r.Out -join "`r`n")).TrimEnd("`r", "`n")
  Chk 'AR-DOC-RT' "$($d.Exit)|$(@($d.Out)[0])|$(@($d.Out)[-1])|$((($d.Out) -join "`r`n") -ceq $want)" '0|/// <remarks>|/// </remarks>|True'
}

Write-Host 'the DocInsight formatter against the plugin ...'
Step 'AR-DOC-PORT' {
  . (Join-Path $PSScriptRoot 'Report.DocInsight.ps1')
  $fx = Join-Path $PSScriptRoot '..\fixtures\docinsight'
  $n = 0; $same = 0; $diff = @()
  foreach ($l in (Get-Content (Join-Path $fx 'cases.txt'))) {
    if ($l -match '^#' -or -not $l.Trim()) { continue }
    $c = $l -split '\|'; $n++
    $a = [regex]::Replace([IO.File]::ReadAllText((Join-Path $fx $c[0])), '\{U\+([0-9A-F]{4,5})\}', { param($m) [char]::ConvertFromUtf32([Convert]::ToInt32($m.Groups[1].Value, 16)) })
    if ((Format-ReportAsDocInsight $c[1] $c[2] ([datetime]'2026-10-06') $a) -ceq [IO.File]::ReadAllText((Join-Path $fx $c[3]))) { $same++ } else { $diff += $c[3] }
  }
  Chk 'AR-DOC-PORT' "$same/$n$(if ($diff) { ' differ: ' + ($diff -join ',') })" '4/4'
  # the port must go red when it drifts: one byte of the wrap width changed
  $script:ReportDocMaxLine = 99
  $c = (Get-Content (Join-Path $fx 'cases.txt') | Where-Object { $_ -like 'chart-who-writes*' }) -split '\|'
  $a = [regex]::Replace([IO.File]::ReadAllText((Join-Path $fx $c[0])), '\{U\+([0-9A-F]{4,5})\}', { param($m) [char]::ConvertFromUtf32([Convert]::ToInt32($m.Groups[1].Value, 16)) })
  Chk 'AR-DOC-PORT-MUT' ((Format-ReportAsDocInsight $c[1] $c[2] ([datetime]'2026-10-06') $a) -ceq [IO.File]::ReadAllText((Join-Path $fx $c[3]))) 'False'
  $script:ReportDocMaxLine = 100
}
Step 'AR-DOC-CAPTIONS' {
  . (Join-Path $PSScriptRoot 'Report.DocInsight.ps1')
  $pas = 'C:\Projects\Delphi-RAG-lint\src\delphi-plugin\DragLint.Plugin.ReportText.pas'
  if (-not (Test-Path -LiteralPath $pas)) { Write-Host "  AR-DOC-CAPTIONS skipped: $pas is not on this machine" }
  else {
    $pq = @([regex]::Matches([IO.File]::ReadAllText($pas), "\(Id: '([^']+)'\s*; Caption: '((?:[^']|'')*)'") | ForEach-Object { "$($_.Groups[1].Value)=$($_.Groups[2].Value -replace "''", "'")" })
    $mine = @($script:ReportCaptions.Keys | ForEach-Object { "$_=$($script:ReportCaptions[$_])" })
    Chk 'AR-DOC-CAPTIONS' "$($pq.Count)|$(($pq -join ';') -ceq ($mine -join ';'))" '25|True'
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
