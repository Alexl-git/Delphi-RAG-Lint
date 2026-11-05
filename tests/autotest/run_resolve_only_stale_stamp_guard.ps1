<#
  run_resolve_only_stale_stamp_guard.ps1 -- 1.43 RESOLVE-ONLY-STAMPS-OVER-STALE-PARSES.

  WHAT IT PINS, with REAL kills: `index --resolve-only` walks nothing, so it may not
  claim a walk completed. It used to stamp indexer_fingerprint unconditionally, and
  the next plain run then read Prev = Cur and kept the stale parses for ever.

    S1 re-parse killed in the WALK with some files committed, then --resolve-only:
       the fingerprint stays old, the output says what is owed, the resolver stamp
       is written, and the next plain run parses EXACTLY the files not stamped
       current (> 0 and < all, so good parses survive), row-identical to a clean index
       (RED on the old code: fingerprint promoted, the next run parses 0)
    S2 re-parse killed in the CALLS pass, then --resolve-only: every parse is current,
       so the fingerprint IS promoted; the next plain run parses 0 and skips calls;
       row-identical to clean. The recovery path, and the control that S1's refusal
       is not simply "never promote"
    S3 healthy DB, --resolve-only: fingerprint unchanged, next plain run parses 0.
       Positive control
    S4 --rebuild killed in the walk, then --resolve-only: rebuild_in_progress is still
       set (RED on the old code: cleared, DbMembership trusted a half-built DB); the
       next plain run clears it and ends row-identical to clean
    S5 no kill at all, only a changed fingerprint (--no-preprocess first): the fingerprint
       stays old and the next plain run parses every file (RED on the old code)
    S6 S5 through `index --all --only <Section> --resolve-only`, the other call site
       (RED on the old code)

  Scratch only (-WorkDir); never a real project DB. Always --db. pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-resolve-only-stamp-guard-$PID"
)
. (Join-Path $PSScriptRoot 'exe-hint.ps1')   # Get-ExeStartFailureHint (GUARD-0XC07B)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$UnitCount      = 4
$CallsHoldMs    = 20000
$FileDelayMs    = 3000
$KillTimeoutMs  = 60000
$PollMs         = 20
$RunTimeoutMs   = 120000
$LinesPastBatchRoll = 3   # file lines before the kill: past the batch's 5 s roll, so some files committed
$RebuildMarkerKey   = 'rebuild_in_progress'
$CurrentStampLike   = '%pp=1%'
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
  if (-not $p.WaitForExit($RunTimeoutMs)) { try { $p.Kill($true) } catch { } }
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Out = $o.Result + $e.Result }
}
# Starts `index`, waits until stdout holds $Pattern $Times times, then kills the tree.
# Returns $true only when the process really was alive at the kill.
function Index-AndKill([string]$Db, [string]$Pattern, [int]$Times, [hashtable]$EnvVars, [string[]]$Extra = @()) {
  $log = Join-Path $WorkDir 'kill.log'
  [IO.File]::Delete($log)
  foreach ($k in $EnvVars.Keys) { [Environment]::SetEnvironmentVariable($k, [string]$EnvVars[$k]) }
  try {
    $p = Start-Process -FilePath $Exe -ArgumentList (@('index', "`"$Src`"", '--db', "`"$Db`"") + $Extra) -WorkingDirectory $WorkDir `
           -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -WindowStyle Hidden
  } finally {
    foreach ($k in $EnvVars.Keys) { [Environment]::SetEnvironmentVariable($k, $null) }
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
function Not-Current([string]$Db) {
  return [int](Scalar $Db "SELECT count(*) FROM files WHERE indexed_at_fingerprint IS NULL OR indexed_at_fingerprint NOT LIKE '$CurrentStampLike'")
}
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
function Same-As-Clean([string]$Db) {
  $clean = Join-Path $WorkDir "clean-$([guid]::NewGuid().ToString('N')).sqlite"
  $r = Run-Exe @('index', $Src, '--db', $clean)
  if ($r.Code -ne 0) { throw "clean index failed: $($r.Out)" }
  $a = Derived $Db; $b = Derived $clean
  return (($a -eq $b) -and ($a.Length -gt 0))
}
function Write-Unit([int]$I) {
  $j = if ($I -lt $UnitCount) { $I + 1 } else { 1 }
  $t = "unit StampUnit$I;`r`n`r`ninterface`r`n`r`nprocedure Work$I(A: Integer);`r`n`r`nimplementation`r`n`r`nuses StampUnit$j;`r`n`r`nprocedure Work$I(A: Integer);`r`nbegin`r`n  if A > 0 then begin Work$I(A - 1); Work$j(A - 1); end;`r`nend;`r`n`r`nend.`r`n"
  [IO.File]::WriteAllText((Join-Path $Src "StampUnit$I.pas"), $t, [Text.Encoding]::ASCII)
}
function New-Fixture([string]$Name) {
  $script:Src = Join-Path $WorkDir "src-$Name"
  New-Item -ItemType Directory $Src -Force | Out-Null
  for ($i = 1; $i -le $UnitCount; $i++) { Write-Unit $i }
  return (Join-Path $WorkDir "$Name.sqlite")
}
function Parsed-Count([string]$Out) { return ([regex]::Matches($Out, ' -> \d+ symbols')).Count }
$RxCallsRun  = 'stage: calls -- started'
$RxCallsSkip = 'stage: calls -- skipped'
$RxFalseParse = 're-parsing every file'
$RxOwedNote  = 'not at the current indexer fingerprint'

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir -Force | Out-Null

  # ---- S1: re-parse killed in the walk, then --resolve-only ----
  $db = New-Fixture 's1'
  $first = Run-Exe @('index', $Src, '--db', $db, '--no-preprocess')
  if ($first.Code -ne 0) { $hint = Get-ExeStartFailureHint $first.Code; if ($hint) { Write-Host "FATAL: $hint" -ForegroundColor Red }; Write-Host "FATAL: setup index failed: $($first.Out)" -ForegroundColor Red; exit 2 }
  $fpOld = Meta $db 'indexer_fingerprint'
  $killed = Index-AndKill $db ' -> \d+ symbols' $LinesPastBatchRoll @{ DRAGLINT_TEST_INDEX_FILE_DELAY_MS = $FileDelayMs }
  Check 'S1a the process was alive when killed in the walk' $killed
  $owed = Not-Current $db
  Check 'S1b setup: some files committed current, some not' (($owed -gt 0) -and ($owed -lt $UnitCount)) "not-current=$owed of $UnitCount"
  $ro = Run-Exe @('index', $Src, '--db', $db, '--resolve-only')
  Check 'S1c --resolve-only succeeded and did not claim a re-parse' (($ro.Code -eq 0) -and ($ro.Out -notmatch $RxFalseParse)) "exit=$($ro.Code)"
  Check 'S1d ... and names the count owed' ($ro.Out -match "$owed file\(s\) $RxOwedNote")
  Check 'S1e indexer_fingerprint is still the old one' ((Meta $db 'indexer_fingerprint') -eq $fpOld) (Meta $db 'indexer_fingerprint')
  Check 'S1f the pass really completed, so the resolver stamp is written' ((Meta $db 'resolver_fingerprint') -ne '') (Meta $db 'resolver_fingerprint')
  Check 'S1g --resolve-only touched no per-file stamp' ((Not-Current $db) -eq $owed) "not-current=$(Not-Current $db)"
  $next = Run-Exe @('index', $Src, '--db', $db)
  $parsed = Parsed-Count $next.Out
  Check 'S1h the next plain run parses exactly the files not stamped current' (($next.Code -eq 0) -and ($parsed -eq $owed)) "parsed=$parsed owed=$owed"
  Check 'S1i ... promotes the fingerprint' ((Meta $db 'indexer_fingerprint') -ne $fpOld) (Meta $db 'indexer_fingerprint')
  Check 'S1j ... and ends row-identical to a clean index' (Same-As-Clean $db)

  # ---- S2: re-parse killed in the calls pass, then --resolve-only ----
  $db = New-Fixture 's2'
  Run-Exe @('index', $Src, '--db', $db, '--no-preprocess') | Out-Null
  $fpOld = Meta $db 'indexer_fingerprint'
  $killed = Index-AndKill $db $RxCallsRun 1 @{ DRAGLINT_TEST_CALLS_START_DELAY_MS = $CallsHoldMs }
  Check 'S2a the process was alive when killed in the calls pass' $killed
  Check 'S2b setup: every file carries the current stamp' ((Not-Current $db) -eq 0) "not-current=$(Not-Current $db)"
  $ro = Run-Exe @('index', $Src, '--db', $db, '--resolve-only')
  Check 'S2c --resolve-only succeeded and did not claim a re-parse' (($ro.Code -eq 0) -and ($ro.Out -notmatch $RxFalseParse) -and ($ro.Out -notmatch $RxOwedNote)) "exit=$($ro.Code)"
  Check 'S2d the fingerprint is promoted: every parse is current' ((Meta $db 'indexer_fingerprint') -ne $fpOld) (Meta $db 'indexer_fingerprint')
  $next = Run-Exe @('index', $Src, '--db', $db)
  $parsed = Parsed-Count $next.Out
  Check 'S2e the next plain run parses 0 and skips the calls pass' (($next.Code -eq 0) -and ($parsed -eq 0) -and ($next.Out -match $RxCallsSkip)) "parsed=$parsed"
  Check 'S2f ... and ends row-identical to a clean index' (Same-As-Clean $db)

  # ---- S3: healthy DB ----
  $db = New-Fixture 's3'
  Run-Exe @('index', $Src, '--db', $db) | Out-Null
  $fpOld = Meta $db 'indexer_fingerprint'
  $ro = Run-Exe @('index', $Src, '--db', $db, '--resolve-only')
  Check 'S3a positive control: a healthy --resolve-only runs the pass, no note' (($ro.Code -eq 0) -and ($ro.Out -match $RxCallsRun) -and ($ro.Out -notmatch $RxOwedNote)) "exit=$($ro.Code)"
  Check 'S3b fingerprint unchanged' ((Meta $db 'indexer_fingerprint') -eq $fpOld) $fpOld
  $next = Run-Exe @('index', $Src, '--db', $db)
  $parsed = Parsed-Count $next.Out
  Check 'S3c the next plain run parses 0' (($next.Code -eq 0) -and ($parsed -eq 0)) "parsed=$parsed"

  # ---- S4: --rebuild killed in the walk, then --resolve-only ----
  $db = New-Fixture 's4'
  Run-Exe @('index', $Src, '--db', $db) | Out-Null
  $killed = Index-AndKill $db ' -> \d+ symbols' 1 @{ DRAGLINT_TEST_INDEX_FILE_DELAY_MS = $FileDelayMs } @('--rebuild')
  Check 'S4a the process was alive when killed in the walk' $killed
  Check 'S4b setup: the rebuild marker is set' ((Meta $db $RebuildMarkerKey) -eq '1') (Meta $db $RebuildMarkerKey)
  $ro = Run-Exe @('index', $Src, '--db', $db, '--resolve-only')
  Check 'S4c --resolve-only succeeded' ($ro.Code -eq 0) "exit=$($ro.Code)"
  Check 'S4d the rebuild marker is STILL set: the walk never completed' ((Meta $db $RebuildMarkerKey) -eq '1') (Meta $db $RebuildMarkerKey)
  $next = Run-Exe @('index', $Src, '--db', $db)
  Check 'S4e the next plain run clears the marker' (($next.Code -eq 0) -and ((Meta $db $RebuildMarkerKey) -eq '')) "exit=$($next.Code)"
  Check 'S4f ... and ends row-identical to a clean index' (Same-As-Clean $db)

  # ---- S5: a changed fingerprint and no kill at all ----
  $db = New-Fixture 's5'
  Run-Exe @('index', $Src, '--db', $db, '--no-preprocess') | Out-Null
  $fpOld = Meta $db 'indexer_fingerprint'
  $ro = Run-Exe @('index', $Src, '--db', $db, '--resolve-only')
  Check 'S5a --resolve-only leaves the old fingerprint' (($ro.Code -eq 0) -and ((Meta $db 'indexer_fingerprint') -eq $fpOld)) (Meta $db 'indexer_fingerprint')
  $next = Run-Exe @('index', $Src, '--db', $db)
  $parsed = Parsed-Count $next.Out
  Check 'S5b the next plain run parses every file' (($next.Code -eq 0) -and ($parsed -eq $UnitCount)) "parsed=$parsed"
  Check 'S5c ... and ends row-identical to a clean index' (Same-As-Clean $db)

  # ---- S6: S5 through the manifest path ----
  $db = New-Fixture 's6'
  $cfg = Join-Path $WorkDir 's6.drag-lint.json'
  $manifest = '{ "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 }, "indexes": { "outDir": "out", "sections": [ { "name": "StampSection", "db": "s6.sqlite", "include": ["src-s6"] } ] } }'
  [IO.File]::WriteAllText($cfg, $manifest, [Text.Encoding]::ASCII)
  $db = Join-Path $WorkDir 'out\s6.sqlite'
  New-Item -ItemType Directory (Split-Path $db) -Force | Out-Null
  Run-Exe @('index', $Src, '--db', $db, '--no-preprocess') | Out-Null
  $fpOld = Meta $db 'indexer_fingerprint'
  $ro = Run-Exe @('index', '--all', '--config', $cfg, '--only', 'StampSection', '--jobs', '1', '--resolve-only')
  Check 'S6a index --all --resolve-only ran the pass without claiming a re-parse' (($ro.Code -eq 0) -and ($ro.Out -match $RxCallsRun) -and ($ro.Out -notmatch $RxFalseParse)) "exit=$($ro.Code)"
  Check 'S6b ... names the count owed' ($ro.Out -match "$UnitCount file\(s\) $RxOwedNote")
  Check 'S6c ... leaves the old fingerprint' ((Meta $db 'indexer_fingerprint') -eq $fpOld) (Meta $db 'indexer_fingerprint')
  $next = Run-Exe @('index', '--all', '--config', $cfg, '--only', 'StampSection', '--jobs', '1')
  $parsed = Parsed-Count $next.Out
  Check 'S6d the next manifest run parses every file' (($next.Code -eq 0) -and ($parsed -eq $UnitCount)) "parsed=$parsed"
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
