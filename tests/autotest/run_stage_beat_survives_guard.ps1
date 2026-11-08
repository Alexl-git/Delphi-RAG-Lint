<#
  run_stage_beat_survives_guard.ps1 -- a heartbeat line that raises does not end the heartbeat (148 IX, OM row 1).

  WHY. B5 (wave 147) saw ONE "LOW MEMORY" line and then 2 h 43 m of silence in the purity stage, although
  TStageHeartbeat.CheckStall must print NO PROGRESS every 15 min. An exception inside the beat body
  (EOutOfMemory in Format / Writeln) ends a TThread silently (FatalException), so "silent" could mean
  "dead beat". The beat now catches, says so once, and keeps beating.

    B1 the seam fired: the "heartbeat line failed" note is printed      (POSITIVE CONTROL: the seam works)
    B2 beats CONTINUE after the failed one: >= 2 "still running" lines (RED before the fix: the thread died)
    B3 the run still exits 0
    B4 CONTROL: without the seam the beat prints and no failure note appears

  The hold seam DRAGLINT_TEST_RESOLVE_DELAY_MS keeps the calls stage open long enough to beat.
  Scratch only (-WorkDir). pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-beat-survives-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name  $Detail" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Run-Exe([string[]]$ArgList, [hashtable]$EnvVars = @{}) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $WorkDir
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(120000)) { try { $p.Kill($true) } catch { } }
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Text = $o.Result + $e.Result }
}

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory $src -Force | Out-Null
  for ($i = 1; $i -le 3; $i++) {
    $j = if ($i -lt 3) { $i + 1 } else { 1 }
    $t = "unit BeatUnit$i;`r`n`r`ninterface`r`n`r`nprocedure Work$i(A: Integer);`r`n`r`nimplementation`r`n`r`nuses BeatUnit$j;`r`n`r`nprocedure Work$i(A: Integer);`r`nbegin`r`n  if A > 0 then begin Work$i(A - 1); Work$j(A - 1); end;`r`nend;`r`n`r`nend.`r`n"
    [IO.File]::WriteAllText((Join-Path $src "BeatUnit$i.pas"), $t, [Text.Encoding]::ASCII)
  }
  $db = Join-Path $WorkDir 'beat.sqlite'
  $first = Run-Exe @('index', $src, '--db', $db)
  if ($first.Code -ne 0) { Write-Host "FATAL: setup index failed: $($first.Text)" -ForegroundColor Red; exit 2 }
  $Idx  = @('index', $src, '--db', $db, '--resolve-only')
  $Fast = @{ DRAGLINT_STAGE_HEARTBEAT_MS = 50; DRAGLINT_TEST_RESOLVE_DELAY_MS = 1500 }

  $s = Run-Exe $Idx ($Fast + @{ DRAGLINT_TEST_BEAT_RAISE_ONCE = '1' })
  $failLine = [regex]::Match($s.Text, 'stage: calls -- heartbeat line failed[^\r\n]*')
  Check 'B1 the seam fired: a failure note is printed' $failLine.Success $failLine.Value
  # the seam raises BEFORE the first beat's line, so every "still running" line is a later beat
  $beats = ([regex]::Matches($s.Text, 'stage: calls -- still running')).Count
  Check 'B2 beats continue after the failed one' ($beats -ge 2) "beats after the failure=$beats"
  Check 'B3 the run still exits 0' ($s.Code -eq 0) "exit=$($s.Code)"

  $c = Run-Exe $Idx $Fast
  $cBeats = ([regex]::Matches($c.Text, 'stage: calls -- still running')).Count
  Check 'B4 CONTROL: no seam -> beats, no failure note' (($cBeats -ge 2) -and ($c.Text -notmatch 'heartbeat line failed') -and ($c.Code -eq 0)) "beats=$cBeats exit=$($c.Code)"
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'run_stage_beat_survives_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_stage_beat_survives_guard: PASS'
exit 0
