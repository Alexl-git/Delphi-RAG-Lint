<#
  run_stage_progress_guard.ps1 -- a long resolve stage says N of M, in its beat line and to outside readers.

  WHY. In the 1.42 re-parse a heartbeat printed "still running" for six hours while the rows crawled. A beat
  proves the timer thread is alive and nothing else; the log could not tell slow from stuck.

    P1 a stage whose counter moves prints it on the "still running" line, with a rate
    P2 control: the same hold with a counter that stands still shows no rate above 0
    P3 `shutdown --all --dry-run` shows the running engine's step from outside; it asks nothing
       (the engine still ends 0 with its rows)
    P4 the resolve streams report N of an exact M: esolve calls on the beat line, over a fixture of known size

  Scratch only (-WorkDir); --dry-run only, so it cannot stop an engine it did not start. pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-progress-guard-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name  $Detail" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Start-Exe([string[]]$ArgList, [hashtable]$EnvVars) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $WorkDir
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  return @{ P = $p; O = $p.StandardOutput.ReadToEndAsync(); E = $p.StandardError.ReadToEndAsync() }
}
function Finish($H) {
  if (-not $H.P.WaitForExit(120000)) { try { $H.P.Kill($true) } catch { } }
  $H.P.WaitForExit()
  return @{ Code = $H.P.ExitCode; Text = $H.O.Result + $H.E.Result }
}
function Run-Exe([string[]]$ArgList, [hashtable]$EnvVars = @{}) { return Finish (Start-Exe $ArgList $EnvVars) }

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory $src -Force | Out-Null
  for ($i = 1; $i -le 3; $i++) {
    $j = if ($i -lt 3) { $i + 1 } else { 1 }
    $t = "unit ProgUnit$i;`r`n`r`ninterface`r`n`r`nprocedure Work$i(A: Integer);`r`n`r`nimplementation`r`n`r`nuses ProgUnit$j;`r`n`r`nprocedure Work$i(A: Integer);`r`nbegin`r`n  if A > 0 then begin Work$i(A - 1); Work$j(A - 1); end;`r`nend;`r`n`r`nend.`r`n"
    [IO.File]::WriteAllText((Join-Path $src "ProgUnit$i.pas"), $t, [Text.Encoding]::ASCII)
  }
  $db = Join-Path $WorkDir 'prog.sqlite'
  $first = Run-Exe @('index', $src, '--db', $db)
  if ($first.Code -ne 0) { Write-Host "FATAL: setup index failed: $($first.Text)" -ForegroundColor Red; exit 2 }

  $Beat = @{ DRAGLINT_STAGE_HEARTBEAT_MS = 200; DRAGLINT_TEST_RESOLVE_DELAY_MS = 1500 }
  $moving = $Beat + @{ DRAGLINT_TEST_BEAT_MOVES = '1' }
  $v = Run-Exe @('index', $src, '--db', $db, '--resolve-only') $moving
  $line = @($v.Text -split "`r?`n" | Where-Object { $_ -match 'stage: calls -- still running' })
  $last = if ($line.Count) { $line[-1] } else { '' }
  Check 'P1 a moving counter is on the beat line, with a rate' ($last -match 'still running, \d+m\d{2}s elapsed, calls \d+, \d+/s$') "beats=$($line.Count) last='$last'"

  $s = Run-Exe @('index', $src, '--db', $db, '--resolve-only') $Beat
  $line2 = @($s.Text -split "`r?`n" | Where-Object { $_ -match 'stage: calls -- still running' })
  $moved = @($line2 | Where-Object { $_ -match ', [1-9]\d*/s$' })
  Check 'P2 control: a held stage whose counter stands still never reports a rate above 0' (($line2.Count -gt 0) -and ($moved.Count -eq 0)) "beats=$($line2.Count) moving=$($moved.Count)"

  $h = Start-Exe @('index', $src, '--db', $db, '--resolve-only') (@{ DRAGLINT_TEST_RESOLVE_DELAY_MS = 6000; DRAGLINT_TEST_BEAT_MOVES = '1' })
  $seen = ''
  $until = (Get-Date).AddSeconds(5)
  while ((Get-Date) -lt $until -and $seen -eq '') {
    $d = Run-Exe @('shutdown', '--all', '--dry-run')
    $row = @($d.Text -split "`r?`n" | Where-Object { $_ -match "pid $($h.P.Id) beat: index: calls \d+" })
    if ($row.Count) { $seen = $row[0].Trim() } else { Start-Sleep -Milliseconds 300 }
  }
  $e = Finish $h
  Check 'P3 shutdown --dry-run shows the step from outside, and the engine carries on to exit 0' (($seen -ne '') -and ($e.Code -eq 0)) "exit=$($e.Code) '$seen'"

  $big = Join-Path $WorkDir 'big'
  New-Item -ItemType Directory $big -Force | Out-Null
  $Calls = 1500
  $body = (1..$Calls | ForEach-Object { '  Work;' }) -join "`r`n"
  $extraDecl = (1..300 | ForEach-Object { "procedure Extra$_;" }) -join "`r`n"
  $extraImpl = (1..300 | ForEach-Object { "procedure Extra$_;`r`nbegin`r`n  Work;`r`nend;" }) -join "`r`n`r`n"
  [IO.File]::WriteAllText((Join-Path $big 'ProgBig.pas'), "unit ProgBig;`r`n`r`ninterface`r`n`r`nprocedure Work;`r`nprocedure Many;`r`n$extraDecl`r`n`r`nimplementation`r`n`r`nprocedure Work;`r`nbegin`r`nend;`r`n`r`n$extraImpl`r`n`r`nprocedure Many;`r`nbegin`r`n$body`r`nend;`r`n`r`nend.`r`n", [Text.Encoding]::ASCII)
  $bdb = Join-Path $WorkDir 'big.sqlite'
  $b = Run-Exe @('index', $big, '--db', $bdb) @{ DRAGLINT_STAGE_HEARTBEAT_MS = 1 }
  $counted = @($b.Text -split "`r?`n" | Where-Object { $_ -match 'resolve calls (\d+) of (\d+)' -and [int]$Matches[2] -ge $Calls })
  Check 'P4 the calls stream reports N of an exact M' (($b.Code -eq 0) -and ($counted.Count -gt 0)) "exit=$($b.Code) lines=$($counted.Count) first='$(if ($counted.Count) { $counted[0].Trim() })'"
  $pur = @($b.Text -split "`r?`n" | Where-Object { $_ -match 'stage: purity -- still running.*purity \w+' })
  $sea = @($b.Text -split "`r?`n" | Where-Object { $_ -match 'stage: search -- still running.*search \w+' })
  Check 'P5 purity and search name their step on the beat line' (($pur.Count -gt 0) -and ($sea.Count -gt 0)) "purity=$($pur.Count) search=$($sea.Count)"
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
