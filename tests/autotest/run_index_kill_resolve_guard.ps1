<#
  run_index_kill_resolve_guard.ps1 -- 1.42 FINGERPRINT-STAMP-AFTER-WALK.

  WHAT IT PINS, with REAL kills (Process.Kill of the whole tree, no clean exit):
  a run killed between the first file write and the end of the calls pass never
  costs a re-parse and never leaves a later plain `index` skipping the resolve.

    K1 incremental edit, killed in the calls pass: the next plain run re-derives
       every edge and ends row-identical to a clean index
       (RED before 1.42: "calls -- skipped", the edited unit keeps 0 edges forever)
    K2 positive control: the resolve-incomplete mark is not sticky -- it was
       restamped, and one more plain run skips the calls pass
    K3 positive control: an ORDINARY completed incremental run leaves the stamp
       set, and the run after it skips the calls pass with no "no resolver stamp"
    K4 forced re-parse (fingerprint change), killed in the calls pass: the DB-level
       indexer fingerprint is still the OLD one (it stays end-of-run), the per-file
       stamps are all current, and the next plain run parses ZERO files, resolves
       and ends row-identical to a clean index
    K5 positive control for K4's instrument: the same re-parse killed DURING THE
       WALK does parse files on the next run, and ends row-identical
    K6 incremental edit of every unit, killed in the walk after a batch committed:
       the next plain run skips the committed units and ends row-identical (green
       before 1.42 too on this small fixture: a pin, not a reproduction)
    K7 a run that only PRUNED a deleted unit, killed in the calls pass: the next
       plain run re-derives and ends row-identical (RED before 1.42: "calls -- skipped")

  Scratch only (-WorkDir); never a real project DB. Always --db. pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-kill-resolve-guard-$PID"
)
. (Join-Path $PSScriptRoot 'exe-hint.ps1')   # Get-ExeStartFailureHint (GUARD-0XC07B)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$UnitCount      = 4
$CallsHoldMs    = 20000
$FileDelayMs    = 3000
$KillTimeoutMs  = 60000
$PollMs         = 20
$CalledUnitsAfterBatch = 3   # file lines before K6's kill: past the batch's 5 s roll
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name  $Detail" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Run-Exe([string[]]$ArgList) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $WorkDir
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(120000)) { try { $p.Kill($true) } catch { } }
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Out = $o.Result + $e.Result }
}
# Starts `index`, waits until stdout holds $Pattern $Times times, then kills the tree.
# Returns $true only when the process really was alive at the kill.
function Index-AndKill([string]$Db, [string]$Pattern, [int]$Times, [hashtable]$EnvVars) {
  $log = Join-Path $WorkDir 'kill.log'
  [IO.File]::Delete($log)
  foreach ($k in $EnvVars.Keys) { Set-Item "env:$k" ([string]$EnvVars[$k]) }
  try {
    $p = Start-Process -FilePath $Exe -ArgumentList @('index', "`"$Src`"", '--db', "`"$Db`"") -WorkingDirectory $WorkDir `
           -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -WindowStyle Hidden
  } finally {
    foreach ($k in $EnvVars.Keys) { Remove-Item "env:$k" }
  }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $hit = $false
  while ((-not $p.HasExited) -and ($sw.ElapsedMilliseconds -lt $KillTimeoutMs)) {
    if (Test-Path $log) {
      $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite,Delete')
      $r = New-Object IO.StreamReader($fs); $text = $r.ReadToEnd(); $r.Close()
      if (([regex]::Matches($text, $Pattern)).Count -ge $Times) { $hit = $true; break }
    }
    [Threading.Thread]::Sleep($PollMs)
  }
  $alive = -not $p.HasExited
  if ($alive) { $p.Kill($true) }
  $p.WaitForExit()
  return ($hit -and $alive)
}
function Sql-Rows([string]$Db, [string]$Query) {
  $out = & $Exe sql --db $Db --json --limit 1000000 --query $Query 2>$null | Out-String
  $j = $out | ConvertFrom-Json
  return , @($j.rows | ForEach-Object { , @($_) })
}
function Scalar([string]$Db, [string]$Query) { return [string](Sql-Rows $Db $Query)[0][0] }
function Meta([string]$Db, [string]$Key) { return Scalar $Db "SELECT coalesce((SELECT value FROM schema_meta WHERE key='$Key'),'')" }
# The derived state, by source position rather than row id: edges, member accesses, ref bindings.
function Derived([string]$Db) {
  $at = "f.path||':'||r.start_line||':'||r.start_col||':'||r.name_text"
  $qs = @(
    "SELECT 'ce '||$at||'>'||t.qualified_name||'|'||ce.confidence FROM call_edges ce JOIN refs r ON r.id=ce.ref_id JOIN files f ON f.id=r.file_id JOIN symbols t ON t.id=ce.target_symbol_id",
    "SELECT 'ma '||$at||'>'||t.qualified_name||'|'||ma.mode FROM member_accesses ma JOIN refs r ON r.id=ma.ref_id JOIN files f ON f.id=r.file_id JOIN symbols t ON t.id=ma.member_symbol_id",
    "SELECT 'rf '||$at||':'||r.kind||'>'||coalesce(t.qualified_name,'') FROM refs r JOIN files f ON f.id=r.file_id LEFT JOIN symbols t ON t.id=r.symbol_id")
  $all = foreach ($q in $qs) { (Sql-Rows $Db $q) | ForEach-Object { [string]$_[0] } }
  return (@($all) | Sort-Object) -join "`n"
}
function Edge-Count([string]$Db) { return [int](Scalar $Db 'SELECT count(*) FROM call_edges') }
function Same-As-Clean([string]$Db) {
  $clean = Join-Path $WorkDir "clean-$([guid]::NewGuid().ToString('N')).sqlite"
  $r = Run-Exe @('index', $Src, '--db', $clean)
  if ($r.Code -ne 0) { throw "clean index failed: $($r.Out)" }
  $a = Derived $Db; $b = Derived $clean
  return (($a -eq $b) -and ($a.Length -gt 0))
}
function Write-Unit([int]$I) {
  $j = if ($I -lt $UnitCount) { $I + 1 } else { 1 }
  $t = "unit KillUnit$I;`r`n`r`ninterface`r`n`r`nprocedure Work$I(A: Integer);`r`n`r`nimplementation`r`n`r`nuses KillUnit$j;`r`n`r`nprocedure Work$I(A: Integer);`r`nbegin`r`n  if A > 0 then begin Work$I(A - 1); Work$j(A - 1); end;`r`nend;`r`n`r`nend.`r`n"
  [IO.File]::WriteAllText((Join-Path $Src "KillUnit$I.pas"), $t, [Text.Encoding]::ASCII)
}
function New-Fixture([string]$Name) {
  $script:Src = Join-Path $WorkDir "src-$Name"
  New-Item -ItemType Directory $Src -Force | Out-Null
  for ($i = 1; $i -le $UnitCount; $i++) { Write-Unit $i }
  return (Join-Path $WorkDir "$Name.sqlite")
}
function Edit-Unit([int]$I) {
  $p = Join-Path $Src "KillUnit$I.pas"
  [IO.File]::AppendAllText($p, "{ edited $([DateTime]::Now.Ticks) }`r`n", [Text.Encoding]::ASCII)
  [IO.File]::SetLastWriteTimeUtc($p, [DateTime]::UtcNow.AddSeconds(2))
}
$RxCallsRun  = 'stage: calls -- started'
$RxCallsSkip = 'stage: calls -- skipped'
$RxNoStamp   = 'no resolver stamp'
$RxParsed    = ' -> \d+ symbols'

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir -Force | Out-Null

  # ---- K1 / K2: incremental edit, killed in the calls pass ----
  $db = New-Fixture 'k1'
  $first = Run-Exe @('index', $Src, '--db', $db)
  if ($first.Code -ne 0) { $hint = Get-ExeStartFailureHint $first.Code; if ($hint) { Write-Host "FATAL: $hint" -ForegroundColor Red }; Write-Host "FATAL: setup index failed: $($first.Out)" -ForegroundColor Red; exit 2 }
  if ((Edge-Count $db) -le 0) { Write-Host 'FATAL: setup resolved no edges' -ForegroundColor Red; exit 2 }
  Edit-Unit 1
  $killed = Index-AndKill $db $RxCallsRun 1 @{ DRAGLINT_TEST_CALLS_START_DELAY_MS = $CallsHoldMs }
  Check 'K1a the process was alive when killed in the calls pass' $killed
  $next = Run-Exe @('index', $Src, '--db', $db)
  Check 'K1b the next plain run runs the calls pass, it does not skip it' (($next.Code -eq 0) -and ($next.Out -match $RxCallsRun) -and ($next.Out -notmatch $RxCallsSkip)) "exit=$($next.Code)"
  Check 'K1c ... and ends row-identical to a clean index' (Same-As-Clean $db) "edges=$(Edge-Count $db)"
  Check 'K2a the resolve-incomplete mark was restamped' ((Meta $db 'resolver_fingerprint') -ne '') (Meta $db 'resolver_fingerprint')
  $again = Run-Exe @('index', $Src, '--db', $db)
  Check 'K2b positive control: one more plain run skips the calls pass' (($again.Code -eq 0) -and ($again.Out -match $RxCallsSkip)) "exit=$($again.Code)"

  # ---- K3: nothing killed ----
  $db = New-Fixture 'k3'
  Run-Exe @('index', $Src, '--db', $db) | Out-Null
  Edit-Unit 2
  $done = Run-Exe @('index', $Src, '--db', $db)
  $after = Run-Exe @('index', $Src, '--db', $db)
  Check 'K3 positive control: a completed run leaves no mark behind' (($done.Code -eq 0) -and ($done.Out -match $RxCallsRun) -and ($after.Out -match $RxCallsSkip) -and ($after.Out -notmatch $RxNoStamp) -and ((Meta $db 'resolver_fingerprint') -ne '')) "exit=$($done.Code)"

  # ---- K4: forced re-parse, killed in the calls pass ----
  $db = New-Fixture 'k4'
  Run-Exe @('index', $Src, '--db', $db, '--no-preprocess') | Out-Null
  $fpBefore = Meta $db 'indexer_fingerprint'
  $killed = Index-AndKill $db $RxCallsRun 1 @{ DRAGLINT_TEST_CALLS_START_DELAY_MS = $CallsHoldMs }
  Check 'K4a the process was alive when killed in the calls pass' $killed
  Check 'K4b the DB-level indexer fingerprint stays end-of-run (still the old one)' ((Meta $db 'indexer_fingerprint') -eq $fpBefore) $fpBefore
  $stamped = [int](Scalar $db "SELECT count(*) FROM files WHERE indexed_at_fingerprint LIKE '%pp=1%'")
  Check 'K4c every parsed file carries the current per-file stamp' ($stamped -eq $UnitCount) "stamped=$stamped"
  $next = Run-Exe @('index', $Src, '--db', $db)
  $parsed = ([regex]::Matches($next.Out, $RxParsed)).Count
  Check 'K4d the next plain run re-parses NOTHING' (($next.Code -eq 0) -and ($parsed -eq 0) -and ($next.Out -match "skipped $UnitCount up-to-date")) "parsed=$parsed"
  Check 'K4e ... runs the calls pass and stamps the new fingerprint' (($next.Out -match $RxCallsRun) -and ((Meta $db 'indexer_fingerprint') -ne $fpBefore)) (Meta $db 'indexer_fingerprint')
  Check 'K4f ... and ends row-identical to a clean index' (Same-As-Clean $db) "edges=$(Edge-Count $db)"

  # ---- K5: the same re-parse killed during the walk: K4d's instrument can see a parse ----
  $db = New-Fixture 'k5'
  Run-Exe @('index', $Src, '--db', $db, '--no-preprocess') | Out-Null
  $killed = Index-AndKill $db $RxParsed 1 @{ DRAGLINT_TEST_INDEX_FILE_DELAY_MS = $FileDelayMs }
  Check 'K5a the process was alive when killed in the walk' $killed
  $next = Run-Exe @('index', $Src, '--db', $db)
  $parsed = ([regex]::Matches($next.Out, $RxParsed)).Count
  Check 'K5b positive control: a run killed in the walk does parse on the next run' (($next.Code -eq 0) -and ($parsed -gt 0)) "parsed=$parsed"
  Check 'K5c ... and ends row-identical to a clean index' (Same-As-Clean $db) "edges=$(Edge-Count $db)"

  # ---- K6: incremental edit of every unit, killed in the walk after a batch committed ----
  $db = New-Fixture 'k6'
  Run-Exe @('index', $Src, '--db', $db) | Out-Null
  for ($i = 1; $i -le $UnitCount; $i++) { Edit-Unit $i }
  $killed = Index-AndKill $db $RxParsed $CalledUnitsAfterBatch @{ DRAGLINT_TEST_INDEX_FILE_DELAY_MS = $FileDelayMs }
  Check 'K6a the process was alive when killed in the walk' $killed
  $next = Run-Exe @('index', $Src, '--db', $db)
  Check 'K6b the next plain run ends row-identical to a clean index' (($next.Code -eq 0) -and ($next.Out -match 'skipped \d+ up-to-date') -and (Same-As-Clean $db)) "exit=$($next.Code) edges=$(Edge-Count $db)"

  # ---- K7: a run that only pruned, killed in the calls pass ----
  $db = New-Fixture 'k7'
  Run-Exe @('index', $Src, '--db', $db) | Out-Null
  [IO.File]::Delete((Join-Path $Src "KillUnit$UnitCount.pas"))
  $killed = Index-AndKill $db $RxCallsRun 1 @{ DRAGLINT_TEST_CALLS_START_DELAY_MS = $CallsHoldMs }
  Check 'K7a the process was alive when killed in the calls pass' $killed
  $next = Run-Exe @('index', $Src, '--db', $db)
  Check 'K7b the next plain run re-derives and ends row-identical to a clean index' (($next.Code -eq 0) -and ($next.Out -match $RxCallsRun) -and (Same-As-Clean $db)) "exit=$($next.Code) edges=$(Edge-Count $db)"
}
catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
finally {
  try { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } } catch { }
}
if ($script:Failed) { exit 1 }
Write-Host 'ALL PASS'
exit 0
