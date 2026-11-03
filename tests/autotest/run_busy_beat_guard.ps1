<#
  run_busy_beat_guard.ps1 -- 1.41 SQLITE-BUSY-BEAT (owner ruling 2026-11-01 20:25).

  WHAT IT PINS. A writer that meets SQLITE_BUSY waits as long as the HOLDER's
  heartbeat seq advances and gives up only once it stalls; a holder without a
  heartbeat keeps the fixed writer timeout (DRAGLINT_BUSY_TIMEOUT_MS, here 3 s).
  The holder is found through the heartbeat pipes: an engine answers
  `status<TAB>beat<TAB>writing` with `writing=<db>|...`, the databases it writes.

  TWO PROCESSES hold and wait on one scratch DB: python (_fk_perp.py --hold-ms)
  holds BEGIN IMMEDIATE; a PowerShell runspace serves a heartbeat pipe in the
  holder's place; the victim is a real `index --resolve-only`.

    BB1 advancing beat that names the DB: the victim waits the 15 s hold out and
        exits 0 (RED before 1.41: "database is locked" after ~3 s)
    BB2 frozen beat (seq constant): the victim gives up well before the hold ends
    BB3 no heartbeat pipe at all: gives up at about the fixed timeout
    BB4 an advancing beat that names ANOTHER database is not a holder: gives up
        (positive control for the database match)
    BB5 a real `index` publishes writing=<its db> when asked (RED before 1.41)
    BB6 the same engine asked WITHOUT `writing` carries no writing= field (old shape)

  Scratch only (-WorkDir); never a real project DB. Needs python on PATH. pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-busy-beat-guard-$PID",
  [int]$HoldMs     = 15000,
  [int]$TimeoutMs  = 3000
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name  $Detail" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
$perp = Join-Path $PSScriptRoot '_fk_perp.py'
$sid  = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$sess = (Get-Process -Id $PID).SessionId
function BeatLeaf([int]$ProcId) { return "drag-lint-beat-$sid-s$sess-p$ProcId" }

function Send-Pipe([string]$Leaf, [string]$Msg, [int]$TimeoutMs = 500) {
  $c = New-Object System.IO.Pipes.NamedPipeClientStream('.', $Leaf, [System.IO.Pipes.PipeDirection]::InOut)
  try {
    $c.Connect($TimeoutMs)
    $b = [System.Text.Encoding]::UTF8.GetBytes($Msg + "`n"); $c.Write($b, 0, $b.Length); $c.Flush()
    $ms = New-Object System.IO.MemoryStream; $buf = New-Object byte[] 4096
    while ($true) { $n = $c.Read($buf, 0, 4096); if ($n -le 0) { break }; $ms.Write($buf, 0, $n); if ($buf[$n - 1] -eq 10) { break } }
    return ([System.Text.Encoding]::UTF8.GetString($ms.ToArray())).TrimEnd("`r", "`n")
  } catch { return '' } finally { $c.Dispose() }
}

# A heartbeat pipe served in the holder's place. Mode: advancing | frozen; $DbField = the writing= value.
function Start-FakeBeat([string]$Leaf, [string]$Mode, [string]$DbField) {
  $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
  $ps = [powershell]::Create(); $ps.Runspace = $rs
  $state = [hashtable]::Synchronized(@{ Stop = $false; Served = 0 })
  [void]$ps.AddScript({
    param($Leaf, $Mode, $DbField, $State)
    $t0 = [Environment]::TickCount64
    while (-not $State.Stop) {
      $srv = New-Object System.IO.Pipes.NamedPipeServerStream($Leaf, [System.IO.Pipes.PipeDirection]::InOut, 4)
      try {
        $srv.WaitForConnection()
        if ($State.Stop) { break }
        $buf = New-Object byte[] 1024; [void]$srv.Read($buf, 0, 1024)
        $seq = if ($Mode -eq 'advancing') { 1 + [int](([Environment]::TickCount64 - $t0) / 300) } else { 7 }
        $line = "status`t4242`t1.41.0`tx`tbeat=$seq|index|resolve calls|$seq|0|0`twriting=$DbField`n"
        $b = [System.Text.Encoding]::UTF8.GetBytes($line); $srv.Write($b, 0, $b.Length); $srv.Flush()
        $State.Served++
        try { $srv.WaitForPipeDrain() } catch { }
      } catch { } finally { $srv.Dispose() }
    }
  }).AddArgument($Leaf).AddArgument($Mode).AddArgument($DbField).AddArgument($state)
  $h = $ps.BeginInvoke()
  Start-Sleep -Milliseconds 300
  return @{ PS = $ps; RS = $rs; H = $h; State = $state; Leaf = $Leaf }
}
function Stop-FakeBeat($F) {
  if ($null -eq $F) { return }
  $F.State.Stop = $true
  [void](Send-Pipe $F.Leaf 'wake' 300)
  [void]$F.H.AsyncWaitHandle.WaitOne(3000)
  $F.PS.Dispose(); $F.RS.Dispose()
}

function Run-Exe([string[]]$ArgList, [hashtable]$EnvVars) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $WorkDir
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(120000)) { try { $p.Kill($true) } catch { } }
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Out = ($o.Result + $e.Result); Secs = $sw.Elapsed.TotalSeconds }
}

# One scenario: python holds the lock HoldMs; optional fake beat; the victim reindexes.
function Run-Case([string]$Mode, [string]$DbField) {
  $out = Join-Path $WorkDir "perp-$Mode.out"
  $hp = Start-Process python -ArgumentList @('-I', $perp, $db, 'BusyUnit1.pas', '--hold-ms', "$HoldMs") -PassThru -NoNewWindow -RedirectStandardOutput $out
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while (((-not (Test-Path $out)) -or ((Get-Content $out -Raw) -notmatch 'READY')) -and $sw.ElapsedMilliseconds -lt 10000) { Start-Sleep -Milliseconds 100 }
  $fake = $null
  if ($Mode -ne 'none') { $fake = Start-FakeBeat (BeatLeaf $hp.Id) $Mode $DbField }
  try {
    $v = Run-Exe @('index', $src, '--db', $db, '--resolve-only') @{ DRAGLINT_BUSY_TIMEOUT_MS = $TimeoutMs }
  } finally {
    Stop-FakeBeat $fake
    if (-not $hp.WaitForExit($HoldMs + 10000)) { try { $hp.Kill() } catch { } }
  }
  $v.Served = if ($null -ne $fake) { $fake.State.Served } else { 0 }
  return $v
}

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory $src -Force | Out-Null
  for ($i = 1; $i -le 3; $i++) {
    $t = "unit BusyUnit$i;`r`n`r`ninterface`r`n`r`nprocedure Work$i(A: Integer);`r`n`r`nimplementation`r`n`r`nprocedure Work$i(A: Integer);`r`nbegin`r`n  if A > 0 then Work$i(A - 1);`r`nend;`r`n`r`nend.`r`n"
    [IO.File]::WriteAllText((Join-Path $src "BusyUnit$i.pas"), $t, [Text.Encoding]::ASCII)
  }
  $db = Join-Path $WorkDir 'busy.sqlite'
  $first = Run-Exe @('index', $src, '--db', $db) @{}
  if ($first.Code -ne 0) { Write-Host "FATAL: setup index failed: $($first.Out)" -ForegroundColor Red; exit 2 }
  $dbKey = [IO.Path]::GetFullPath($db).ToLowerInvariant()

  $r1 = Run-Case 'advancing' $dbKey
  Check 'BB1 advancing beat naming the DB: the victim waits the hold out (exit 0, no lock error)' (($r1.Code -eq 0) -and ($r1.Out -notmatch 'database is locked') -and ($r1.Secs -ge ($HoldMs / 1000 - 4))) ("exit={0} {1:N1}s served={2}" -f $r1.Code, $r1.Secs, $r1.Served)

  $r2 = Run-Case 'frozen' $dbKey
  Check 'BB2 frozen beat: the victim gives up before the hold ends' (($r2.Code -ne 0) -and ($r2.Out -match 'database is locked') -and ($r2.Secs -lt ($HoldMs / 1000 - 3))) ("exit={0} {1:N1}s served={2}" -f $r2.Code, $r2.Secs, $r2.Served)

  $r3 = Run-Case 'none' ''
  Check 'BB3 no heartbeat: fixed timeout kept (gives up early)' (($r3.Code -ne 0) -and ($r3.Out -match 'database is locked') -and ($r3.Secs -lt ($HoldMs / 1000 - 3))) ("exit={0} {1:N1}s" -f $r3.Code, $r3.Secs)

  $r4 = Run-Case 'advancing' ($dbKey + '.other')
  Check 'BB4 advancing beat on ANOTHER db is not a holder: gives up' (($r4.Code -ne 0) -and ($r4.Out -match 'database is locked') -and ($r4.Secs -lt ($HoldMs / 1000 - 3))) ("exit={0} {1:N1}s served={2}" -f $r4.Code, $r4.Secs, $r4.Served)

  # ---- BB5/BB6: a real engine publishes the database it writes ----
  $db2 = Join-Path $WorkDir 'busy2.sqlite'
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe; $psi.Arguments = "index `"$src`" --db `"$db2`""
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $WorkDir
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['DRAGLINT_TEST_INDEX_FILE_DELAY_MS'] = '1500'
  $p = [System.Diagnostics.Process]::Start($psi)
  $oT = $p.StandardOutput.ReadToEndAsync(); $eT = $p.StandardError.ReadToEndAsync()
  $withW = ''; $without = ''
  $db2Key = [IO.Path]::GetFullPath($db2).ToLowerInvariant()
  $named = $false
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  # The pipe opens before the store does: sample until the writer field names the DB (or the run ends).
  while (-not $p.HasExited -and $sw.ElapsedMilliseconds -lt 30000 -and -not $named) {
    $r = Send-Pipe (BeatLeaf $p.Id) "status`tbeat`twriting"
    if ($r -ne '') { $withW = $r }
    foreach ($f in ($r -split "`t")) { if ($f.StartsWith('writing=')) { $named = @($f.Substring(8) -split '\|') -contains $db2Key } }
    if ($named) { $without = Send-Pipe (BeatLeaf $p.Id) "status`tbeat" } else { Start-Sleep -Milliseconds 200 }
  }
  if (-not $p.WaitForExit(60000)) { try { $p.Kill($true) } catch { } }
  Check 'BB5 a real index publishes writing=<its db> when asked' $named "reply=$withW"
  Check 'BB6 without the writing argument the reply has no writing= field' (($without -like 'status*') -and ($without -notmatch 'writing=')) "reply=$without"
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
