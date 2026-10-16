<#
  run_index_calls_pending_after_kill.ps1 -- an index run killed between its
  file commits and its call pass is finished by the NEXT run (#35, 2026-10-08).

  Why this exists
  ---------------
  A run commits parsed files in batches and derives their call edges at the end,
  in one later transaction. Killed in between, it left files that are up to date
  on disk with refs no pass ever resolved, and the next run -- nothing to parse --
  printed "calls -- skipped, no file changed, so every call edge already holds"
  and kept the gap for good. CallEdgesNeedRebuild only sees an EMPTY table.
  Measured on the ProjectA index with the 2026-10-08 exe: killed as its calls stage
  started, then re-run, it stayed 31,905 of 269,823 edges short; the daily index
  had lost 87,571 edges that way on 2026-10-01 and answered short for a week.

  The fix records the debt in schema_meta ('calls_pending') in the transaction of
  the run's first write and deletes it in the call pass's commit; a run that finds
  it set takes a WHOLE call pass.

  Steps (DRAGLINT_TEST_DIE_BEFORE_CALLS ends the process where the call pass
  would begin, the way a kill does):
    1  baseline index; its edge list is the reference
    2  edit a unit and index with the hook: the process dies, the edits are on
       disk, the key is set and the edited unit's edges are gone (CONTROL)
    3  plain index: calls NOT skipped, whole-database pass naming the reason,
       edge list identical to the baseline, key cleared
    4  plain index again: calls skipped (CONTROL: the key does not stick)
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_calls_pending_$PID"
)
try {

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

Write-Host '== a killed index run is finished by the next one ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force -Path $src | Out-Null

Write-Ascii (Join-Path $src 'uLeaf.pas') @'
unit uLeaf;
interface
procedure Leaf;
function LeafValue: Integer;
implementation
procedure Leaf;
begin
end;
function LeafValue: Integer;
begin
  Result:= 1;
end;
end.
'@
$midPath = Join-Path $src 'uMid.pas'
Write-Ascii $midPath @'
unit uMid;
interface
procedure Mid;
function MidValue: Integer;
implementation
uses uLeaf;
procedure Mid;
begin
  Leaf;
  Leaf;
end;
function MidValue: Integer;
begin
  Result:= LeafValue + 1;
end;
end.
'@
Write-Ascii (Join-Path $src 'uApp.pas') @'
unit uApp;
interface
procedure Run;
implementation
uses uMid;
procedure Run;
begin
  Mid;
  if MidValue > 0 then Mid;
end;
end.
'@
$db = Join-Path $WorkDir 'idx.sqlite'

function Index {
  $o = @(& $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" })
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($o -join "`n") }
}
function Sql([string]$q) {
  return @((& $Exe sql --db $db --format text --query $q 2>&1) | ForEach-Object { "$_" })
}
function Edges {
  $q = "SELECT f.path || ':' || r.start_line || ':' || r.start_col || ' -> ' || s.qualified_name || ' [' || e.confidence || ']' AS v FROM call_edges e JOIN refs r ON r.id = e.ref_id JOIN files f ON f.id = r.file_id JOIN symbols s ON s.id = e.target_symbol_id ORDER BY 1"
  return ((Sql $q) | Where-Object { $_ -match ' -> ' }) -join "`n"
}
function Pending { return ((Sql "SELECT 'key=' || value AS v FROM schema_meta WHERE key = 'calls_pending'") | Where-Object { $_ -match 'key=' }) -join '' }

Push-Location C:\TEMP
try {
  Write-Host '1 -- baseline' -ForegroundColor Cyan
  $r = Index
  Check '1 baseline indexed' ($r.Code -eq 0) $r.Text
  $baseEdges = Edges
  $midEdges = @(($baseEdges -split "`n") | Where-Object { $_ -match 'uMid\.pas' }).Count
  Check '1 the fixture has edges out of uMid' ($midEdges -ge 3) $baseEdges
  Check '1 a finished run leaves no calls_pending key' ((Pending) -eq '') (Pending)

  Write-Host '2 -- edit uMid, die before the call pass' -ForegroundColor Cyan
  $orig = [System.IO.File]::ReadAllText($midPath)
  [System.IO.File]::WriteAllText($midPath, $orig.Replace('procedure Mid;' + "`r`n" + 'begin', 'procedure Mid;' + "`r`n" + 'begin { edited }'), [System.Text.Encoding]::ASCII)
  [System.IO.File]::SetLastWriteTimeUtc($midPath, (Get-Date).ToUniversalTime().AddSeconds(30))
  $env:DRAGLINT_TEST_DIE_BEFORE_CALLS = '1'
  try { $r = Index } finally { Remove-Item Env:DRAGLINT_TEST_DIE_BEFORE_CALLS -ErrorAction SilentlyContinue }
  Check '2 the hooked run died (exit 9)' ($r.Code -eq 9) "exit $($r.Code)`n$($r.Text)"
  Check '2 it died before the call pass' ($r.Text -notmatch 'stage: calls') $r.Text
  Check '2 the dead run left the calls_pending key' ((Pending) -ne '') ''
  $deadEdges = Edges
  Check '2 CONTROL: uMid''s edges are gone with it' (@(($deadEdges -split "`n") | Where-Object { $_ -match 'uMid\.pas' }).Count -eq 0) $deadEdges

  Write-Host '3 -- plain index finishes the dead run''s work' -ForegroundColor Cyan
  $r = Index
  Check '3 indexed' ($r.Code -eq 0) $r.Text
  Check '3 calls was NOT skipped' ($r.Text -notmatch 'stage: calls -- skipped') (($r.Text -split "`n") | Where-Object { $_ -match 'calls' } | Out-String)
  Check '3 it took the whole database, naming the earlier run' ($r.Text -match 'whole database because an earlier run') (($r.Text -split "`n") | Where-Object { $_ -match 'calls' } | Out-String)
  $edges = Edges
  Check '3 every edge is back (== baseline; the edit is a comment on a line with no ref)' ($edges -eq $baseEdges) ((Compare-Object ($baseEdges -split "`n") ($edges -split "`n") | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join "`n")
  Check '3 the key is cleared' ((Pending) -eq '') (Pending)

  Write-Host '4 -- plain index again' -ForegroundColor Cyan
  $r = Index
  Check '4 indexed' ($r.Code -eq 0) $r.Text
  Check '4 CONTROL: calls skipped -- the key does not stick' ($r.Text -match 'stage: calls -- skipped') (($r.Text -split "`n") | Where-Object { $_ -match 'calls' } | Out-String)
} finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'CALLS PENDING AFTER KILL: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'CALLS PENDING AFTER KILL: PASS' -ForegroundColor Green
exit 0
} finally {
  Remove-Item Env:DRAGLINT_TEST_DIE_BEFORE_CALLS -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath "$env:TEMP\draglint_calls_pending_$PID") { Remove-Item -LiteralPath "$env:TEMP\draglint_calls_pending_$PID" -Recurse -Force -ErrorAction SilentlyContinue }
}
