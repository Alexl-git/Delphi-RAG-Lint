<#
  run_cyclefix_cancel.ps1 -- lane X-BT (owner ruling 2026-10-26): an IDE cycle-fix run has NO time
  limit, so Cancel is the only way to stop one, and Cancel must never hard-kill the engine in the
  middle of an --apply. The engine listens on the maintenance control channel
  (DRagLint.Core.ControlChannel, the pipe `drag-lint shutdown` talks to) for its whole `cycles --fix`
  run; a stand-down request kills the build it is waiting on, rolls every written file back and exits
  1 with "cancelled -- rolled back".

  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing. Every project copy and DB copy lives under
  %TEMP%; the platform library is used through a scratch copy only; no real _D-RAG DB is touched.

  The build environment is a FAKE rsvars.bat (--rsvars) that calls the real one and then, ONLY when
  a .BCK<n> backup exists in the project folder -- that is, only in a build that runs after the
  files were written -- marks `after-started.flag` and parks in a long ping. So the cancel lands in
  the after-build by construction, not by timing.

  (c) cancel in the after-build: `cycles --fix --apply --build-timeout 600` parks in the after-build;
      `drag-lint shutdown --db <its db>` asks it to stand down ->
      c1 the edits were on disk when the cancel was sent (the cancel is mid-apply, not before it);
      c2 every .BCK<n> backup held the pre-run bytes of its source;
      c3 the engine exits 1 within 60 s of the request (it was not killed: nobody kills it here);
      c4 its document says "cancelled -- rolled back";
      c5 every source is byte-identical to its backup as captured mid-run;
      c6 the whole tree (sources, backups, recovery.txt, new leaves) is byte-identical to before;
      c7 the parked build (the unique ping) is gone -- the engine killed its own build tree.
  (t) --build-timeout <s>: a build parked from its first call, --build-timeout 3 ->
      t1 exit 1, the baseline refusal build-timeout, within 60 s; t2 nothing written.
  (v) --build-timeout with a value that is not a whole number of seconds -> exit 2, the message
      names the flag.

  RED (measured against the pre-lane engine, see the lane report): c3-c6 and t1 fail -- the engine
  opens no channel for `cycles`, so `shutdown` finds nothing, the parked build runs to its end and
  the apply completes; --build-timeout is not a flag.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [switch]$KeepScratch,
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-cancel-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [string]$Rsvars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
function Remove-Scratch {
  if ($script:Failed -and $KeepScratch) { Write-Host "scratch kept: $WorkDir" -ForegroundColor Yellow; return }
  Set-Location -LiteralPath $env:TEMP
  # the library copy alone is ~3 GB: retry while a just-exited engine or build still holds a file
  for ($i = 0; ($i -lt 20) -and (Test-Path -LiteralPath $WorkDir); $i++) {
    try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Milliseconds 500 }
  }
  if (Test-Path -LiteralPath $WorkDir) { Write-Host "WARNING: scratch not removed: $WorkDir" -ForegroundColor Yellow }
}
trap { Write-Host ("ERROR: " + $_ + " " + $_.InvocationInfo.PositionMessage) -ForegroundColor Red; $script:Failed = $true; Stop-Parked; try { Remove-Scratch } catch { }; break }

$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars) -- --apply needs dcc" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library to copy ($LibraryDb)" -ForegroundColor Yellow; exit 0 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Demo = Join-Path $Repo 'circular-demo'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Lib = Join-Path $WorkDir 'library-copy.sqlite'
Copy-Item $LibraryDb $Lib -Force

# A loopback address no other process pings: the parked build is found by it, and only it.
$PingHost = '127.{0}.{1}.{2}' -f (Get-Random -Min 2 -Max 250), (Get-Random -Min 2 -Max 250), (Get-Random -Min 2 -Max 250)
function Parked { return @(Get-CimInstance Win32_Process -Filter "Name = 'PING.EXE' OR Name = 'ping.exe'" | Where-Object { "$($_.CommandLine)" -match [regex]::Escape($PingHost) }) }
function Stop-Parked { foreach ($p in (Parked)) { try { [Diagnostics.Process]::GetProcessById([int]$p.ProcessId).Kill() } catch { } } }

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
function Get-TreeHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File -Recurse | Where-Object {
      $_.FullName -notmatch '\\(Win32|Win64|__history|__recovery)\\' -and $_.Name -notmatch '\.flag$' -and
      $_.Extension -notmatch '^\.(dcu|exe|res|identcache|local|stat|dsk|map|rsm|drc)$' } |
    Sort-Object FullName | ForEach-Object { '{0}={1}' -f $_.FullName.Substring($Dir.Length), (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function Get-FileSha([string]$Path) { return (Get-FileHash $Path -Algorithm SHA256).Hash }
function Backups([string]$Dir) { return @(Get-ChildItem $Dir -File | Where-Object { $_.Name -match '\.BCK\d+$' }) }
function New-Demo([string]$Tag) {
  $proj = Join-Path $WorkDir "$Tag-proj"
  Copy-Tree $Demo $proj
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project (Join-Path $proj 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir "$Tag-index.log")
  return @{ Proj = $proj; Dproj = (Join-Path $proj 'CircularDemo.dproj'); Db = $db }
}
# The fake build environment. pWhen = 'after': park only once a .BCK backup exists; 'always': park at once.
function New-FakeRsvars([string]$Tag, [string]$Proj, [string]$When) {
  $flag = Join-Path $WorkDir "$Tag-after-started.flag"
  $bat  = Join-Path $WorkDir "$Tag-rsvars.bat"
  $park = @("echo.> `"$flag`"", "ping -n 300 $PingHost > nul")
  $lines = @('@echo off', "call `"$Rsvars`"")
  if ($When -eq 'after') { $lines += @("if not exist `"$Proj\*.BCK*`" goto :eof") }
  $lines += $park
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  return @{ Bat = $bat; Flag = $flag }
}
function Start-Fix([hashtable]$D, [string[]]$Extra, [string]$Tag) {
  $a = @('cycles', '--fix', '--project', $D.Dproj, '--db', $D.Db, '--library-db', $Lib, '--format', 'json') + $Extra
  $q = ($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $out = Join-Path $WorkDir "$Tag.out"; $err = Join-Path $WorkDir "$Tag.err"
  $p = Start-Process -FilePath $Exe -ArgumentList $q -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
  return @{ P = $p; Out = $out; Err = $err }
}
function Wait-For([scriptblock]$Cond, [int]$Seconds) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $Seconds) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 250 }
  return (& $Cond)
}
# shared read: the file may still be open for writing by the running engine
function Read-Text([string]$Path) {
  if (-not (Test-Path $Path)) { return '' }
  $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
  try { return (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}

# ---------------------------------------------------------------- (c) cancel in the after-build
Write-Host '== (c) cancel during the after-build -> rolled back, exit 1' -ForegroundColor Cyan
$C = New-Demo 'c'
Check 'setup: demo indexed' (Test-Path $C.Db) ''
$before = Get-TreeHash $C.Proj
$srcBefore = @{}
foreach ($f in (Get-ChildItem $C.Proj -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' })) { $srcBefore[$f.Name] = Get-FileSha $f.FullName }
$fake = New-FakeRsvars 'c' $C.Proj 'after'
$run = Start-Fix $C @('--unit', 'demogageport', '--apply', '--build-timeout', '600', '--rsvars', $fake.Bat) 'c'
$parked = Wait-For { (Test-Path $fake.Flag) -or $run.P.HasExited } 240
Check 'setup: the after-build parked (the run reached it)' ($parked -and (Test-Path $fake.Flag) -and -not $run.P.HasExited) ("exited=" + $run.P.HasExited + ' ' + (Read-Text $run.Out) + (Read-Text $run.Err))
$bck = Backups $C.Proj
$changed = @($srcBefore.Keys | Where-Object { (Test-Path (Join-Path $C.Proj $_)) -and ((Get-FileSha (Join-Path $C.Proj $_)) -ne $srcBefore[$_]) })
Check 'c1 the edits are on disk when the cancel is sent (mid-apply)' (($bck.Count -gt 0) -and ($changed.Count -gt 0)) ("backups=" + $bck.Count + ' changed=' + ($changed -join ','))
# each backup, as it is mid-run: <File>.<ext>.BCK<n> holds the pre-run bytes of <File>.<ext>
$bckSha = @{}
foreach ($b in $bck) { $bckSha[($b.Name -replace '\.BCK\d+$', '')] = Get-FileSha $b.FullName }
$bad = @($bckSha.Keys | Where-Object { $bckSha[$_] -ne $srcBefore[$_] })
Check 'c2 every backup holds the pre-run bytes of its source' (($bckSha.Count -gt 0) -and ($bad.Count -eq 0)) ("mismatch: " + ($bad -join ','))
$sdOut = (& $Exe shutdown --db $C.Db --wait 60 2>&1 | Out-String)
$sw = [Diagnostics.Stopwatch]::StartNew()
$exited = Wait-For { $run.P.HasExited } 60
$secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
if (-not $exited) { try { $run.P.Kill($true) } catch { } ; $run.P.WaitForExit(10000) | Out-Null }
$code = $run.P.ExitCode
$text = Read-Text $run.Out
Check 'c3 the engine exits 1 within 60 s of the stand-down request' ($exited -and ($code -eq 1)) "exited=$exited exit=$code after $secs s; shutdown said: $sdOut; stderr: $(Read-Text $run.Err)"
Check 'c4 its document says "cancelled -- rolled back"' ($text -match 'cancelled -- rolled back') $text
$srcAfter = @{}
foreach ($k in $bckSha.Keys) { $srcAfter[$k] = if (Test-Path (Join-Path $C.Proj $k)) { Get-FileSha (Join-Path $C.Proj $k) } else { '' } }
$bad = @($bckSha.Keys | Where-Object { $srcAfter[$_] -ne $bckSha[$_] })
Check 'c5 every source is byte-identical to its backup (as captured mid-run)' (($bckSha.Count -gt 0) -and ($bad.Count -eq 0)) ("differ: " + ($bad -join ','))
Check 'c6 the tree is byte-identical to before (no new leaf, no .BCK, no recovery.txt)' ((Get-TreeHash $C.Proj) -eq $before) (Get-TreeHash $C.Proj)
Check 'c7 the parked build is gone (the engine killed its own build tree)' ((Parked).Count -eq 0) ("still alive: " + ((Parked | ForEach-Object ProcessId) -join ','))
Stop-Parked

# ---------------------------------------------------------------- (t) --build-timeout
Write-Host '== (t) --build-timeout 3 on a build that never finishes' -ForegroundColor Cyan
$T = New-Demo 't'
$beforeT = Get-TreeHash $T.Proj
$fakeT = New-FakeRsvars 't' $T.Proj 'always'
$runT = Start-Fix $T @('--unit', 'demogageport', '--apply', '--build-timeout', '3', '--rsvars', $fakeT.Bat) 't'
$exitedT = Wait-For { $runT.P.HasExited } 60
if (-not $exitedT) { try { $runT.P.Kill($true) } catch { } ; $runT.P.WaitForExit(10000) | Out-Null }
$jT = $null; try { $jT = (Read-Text $runT.Out) | ConvertFrom-Json } catch { }
# a baseline refusal is the run's own (top-level refusals[]), not a cycle's
$kindT = if ($jT) { "$(@($jT.refusals)[0].kind)" } else { '' }
Check 't1 exit 1 with refusal build-timeout within 60 s' ($exitedT -and ($runT.P.ExitCode -eq 1) -and ($kindT -eq 'build-timeout')) ("exited=$exitedT exit=" + $runT.P.ExitCode + " kind=$kindT " + (Read-Text $runT.Out) + (Read-Text $runT.Err))
Check 't2 nothing written' ((Get-TreeHash $T.Proj) -eq $beforeT) ''
Stop-Parked

# ---------------------------------------------------------------- (v) a bad value
Write-Host '== (v) --build-timeout with a bad value' -ForegroundColor Cyan
$errV = Join-Path $WorkDir 'v.err'
$outV = (& $Exe cycles --fix --project $T.Dproj --db $T.Db --library-db $Lib --build-timeout 2m 2>$errV | Out-String)
$codeV = $LASTEXITCODE
$allV = $outV + (Read-Text $errV)
Check 'v1 exit 2 and the message names --build-timeout' (($codeV -eq 2) -and ($allV -match '--build-timeout')) "exit=$codeV $allV"

Write-Host ''
if ($script:Failed) { Write-Host "FAIL ($script:Passed passed)" -ForegroundColor Red; Remove-Scratch; exit 1 }
Write-Host "PASS ($script:Passed checks)" -ForegroundColor Green
Remove-Scratch
exit 0
