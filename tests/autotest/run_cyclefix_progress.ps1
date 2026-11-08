<#
  run_cyclefix_progress.ps1 -- lane 142-cyc, owner ruling D4 (2026-11-03): NO time limit on a
  cycles --fix build ("what if the computer is slow? We do have a cancel button") -- instead the
  run SHOWS its progress and stays cancellable.

  WHAT IT PINS. While `cycles --fix` waits on a build (or any child it runs):
    P1  stderr carries progress lines `cycles --fix: <step> -- <n> s ...` that name the step
        (baseline build) and repeat while it waits: at least two, with growing seconds
    P2  the 1.40 heartbeat pipe answers with action `cycles --fix` and a step naming the build,
        and its seq ADVANCES between two samples -- what the IDE status strip shows
        (ProcRunBeatText), so the plugin needs no change of its own
    P3  POSITIVE CONTROL for the cancel path: `drag-lint shutdown --db` stops the run, exit 1,
        `cancelled`, and the parked build (a unique ping) is gone -- the engine killed its build tree
    P4  NEGATIVE: stdout under --format json is still ONE cycle-fix/1 document (progress never
        leaks onto stdout)

  RED on 1.41 (c2c4b750): P1 and P2 fail (no progress line; `cycles` opens no heartbeat pipe);
  P3 and P4 pass, which is what makes the RED meaningful.

  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing. The build environment is a FAKE
  rsvars.bat (--rsvars) that parks in a long ping from the first build, so the run is
  waiting on the baseline build by construction. Scratch only (%TEMP%): the demo copy, its DB
  and an EMPTY library DB indexed from an empty folder -- no real DB is read or written.
#>
[CmdletBinding()]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe") { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" } else { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }),
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-progress-$PID",
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  [PASS] $Name" -ForegroundColor Green; $script:Passed++ }
  else { Write-Host "  [FAIL] $Name" -ForegroundColor Red; if ($Detail) { Write-Host "      $Detail" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars) -- the gate needs dcc" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Demo = Join-Path $Repo 'circular-demo'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
Set-Location -LiteralPath $WorkDir

$PingHost = '127.{0}.{1}.{2}' -f (Get-Random -Min 2 -Max 250), (Get-Random -Min 2 -Max 250), (Get-Random -Min 2 -Max 250)
function Parked { return @(Get-CimInstance Win32_Process -Filter "Name = 'PING.EXE' OR Name = 'ping.exe'" | Where-Object { "$($_.CommandLine)" -match [regex]::Escape($PingHost) }) }
function Stop-Parked { foreach ($p in (Parked)) { try { [Diagnostics.Process]::GetProcessById([int]$p.ProcessId).Kill() } catch { } } }
function Remove-Scratch {
  Set-Location -LiteralPath $env:TEMP
  for ($i = 0; ($i -lt 20) -and (Test-Path -LiteralPath $WorkDir); $i++) {
    try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Milliseconds 500 }
  }
}
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
function BeatLeaf([int]$ProcId) {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $sess = (Get-Process -Id $PID).SessionId
  return "drag-lint-beat-$sid-s$sess-p$ProcId"
}
function Parse-Beat([string]$Reply) {
  foreach ($f in ($Reply -split "`t")) {
    if ($f.StartsWith('beat=')) {
      $p = $f.Substring(5) -split '\|'
      if ($p.Count -eq 6) { return [pscustomobject]@{ Seq = [int64]$p[0]; Action = $p[1]; Step = $p[2] } }
    }
  }
  return $null
}
function Read-Text([string]$Path) {
  if (-not (Test-Path $Path)) { return '' }
  $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
  try { return (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}
function Wait-For([scriptblock]$Cond, [int]$Seconds) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $Seconds) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 250 }
  return (& $Cond)
}

# ---- setup: demo copy + its DB, an empty library DB, a build environment that parks at once
$Proj = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory -Force $Proj | Out-Null
Get-ChildItem $Demo -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | ForEach-Object { Copy-Item $_.FullName (Join-Path $Proj $_.Name) -Force }
$Dproj = Join-Path $Proj 'CircularDemo.dproj'
$Db = Join-Path $WorkDir 'demo.sqlite'
& $Exe index --project $Dproj --db $Db *> (Join-Path $WorkDir 'index.log')
$EmptyDir = Join-Path $WorkDir 'empty'
New-Item -ItemType Directory -Force $EmptyDir | Out-Null
$Lib = Join-Path $WorkDir 'lib.sqlite'
& $Exe index $EmptyDir --db $Lib *> (Join-Path $WorkDir 'lib.log')
$Fake = Join-Path $WorkDir 'rsvars.bat'
[IO.File]::WriteAllText($Fake, ((@('@echo off', "call `"$Rsvars`"", "ping -n 600 $PingHost > nul") -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
Write-Host '== setup' -ForegroundColor Cyan
Check 'setup: demo indexed' (Test-Path $Db) (Read-Text (Join-Path $WorkDir 'index.log'))

# ---- the run: a dry run, no --build-timeout (unbounded, the IDE's shape)
Write-Host '== cycles --fix parked in its baseline build' -ForegroundColor Cyan
$a = @('cycles', '--fix', '--project', $Dproj, '--db', $Db, '--library-db', $Lib, '--unit', 'demogageport', '--format', 'json', '--rsvars', $Fake)
$q = ($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
$Out = Join-Path $WorkDir 'run.out'; $Err = Join-Path $WorkDir 'run.err'
$run = Start-Process -FilePath $Exe -ArgumentList $q -RedirectStandardOutput $Out -RedirectStandardError $Err -NoNewWindow -PassThru
$parked = Wait-For { ((Parked).Count -gt 0) -or $run.HasExited } 120
Check 'setup: the baseline build parked' ($parked -and -not $run.HasExited) ("exited=" + $run.HasExited + ' ' + (Read-Text $Out) + (Read-Text $Err))

$leaf = BeatLeaf $run.Id
$b1 = Parse-Beat (Send-Pipe $leaf "status`tbeat")
Start-Sleep -Milliseconds 2500
$b2 = Parse-Beat (Send-Pipe $leaf "status`tbeat")
$rx = '(?m)^cycles --fix: baseline build -- (\d+) s\b'
$two = Wait-For { ([regex]::Matches((Read-Text $Err), $rx)).Count -ge 2 } 45
$secs = @([regex]::Matches((Read-Text $Err), $rx) | ForEach-Object { [int]$_.Groups[1].Value })
Check 'P1 stderr repeats a progress line naming the baseline build, seconds growing' ($two -and ($secs.Count -ge 2) -and ($secs[-1] -gt $secs[0])) ("stderr: " + (Read-Text $Err))
$beatOk = ($null -ne $b1) -and ($null -ne $b2) -and ($b1.Action -eq 'cycles --fix') -and ($b2.Step -match '^baseline build') -and ($b2.Seq -gt $b1.Seq)
Check 'P2 the heartbeat says cycles --fix / baseline build and its seq advances' $beatOk ("b1=" + ($b1 | Out-String).Trim() + " b2=" + ($b2 | Out-String).Trim())

$sd = (& $Exe shutdown --db $Db --wait 60 2>&1 | Out-String)
$exited = Wait-For { $run.HasExited } 60
if (-not $exited) { try { $run.Kill($true) } catch { }; $run.WaitForExit(10000) | Out-Null }
$text = Read-Text $Out
Check 'P3 shutdown cancels: exit 1, cancelled, the parked build tree is gone' ($exited -and ($run.ExitCode -eq 1) -and ($text -match 'cancelled') -and ((Parked).Count -eq 0)) ("exit=" + $run.ExitCode + " parked=" + (Parked).Count + " shutdown: $sd out: $text")
$doc = $null; try { $doc = $text | ConvertFrom-Json } catch { }
Check 'P4 stdout is one cycle-fix/1 document (no progress on stdout)' (($null -ne $doc) -and ($doc.schema -eq 'cycle-fix/1') -and ($text -notmatch 'cycles --fix: baseline build --')) $text
Stop-Parked

Write-Host ''
if ($script:Failed) { Write-Host "FAIL ($script:Passed passed)" -ForegroundColor Red; Remove-Scratch; exit 1 }
Write-Host "PASS ($script:Passed checks)" -ForegroundColor Green
Remove-Scratch
exit 0
