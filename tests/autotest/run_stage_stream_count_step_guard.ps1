<#
  run_stage_stream_count_step_guard.ps1 -- while a resolve stream COUNTS its rows, the status record names
  that stream, not the one before it (148 IX, OM row 3).

  WHY. OM (wave 148) watched "enum-values 4096 of 4434, 0/s" stand for 1-4 minutes on a self-index. The
  enum stream had finished; the NEXT stream was running its `SELECT count(*)` (BeatStreamOpen) before it
  called BeatStep, so the heartbeat and NO PROGRESS lines kept naming the finished stream. BeatStreamOpen
  now names the new step first: "<step> (counting rows)".

    C1 a NO PROGRESS line during the count names "(counting rows)"        (RED before the fix)
    C2 the run exits 0
    C3 CONTROL: without the count hold no NO PROGRESS line is printed (the hold is what the guard sees)

  Seam DRAGLINT_TEST_STREAM_COUNT_DELAY_MS holds each stream's count. Scratch only (-WorkDir). pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-stream-count-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name  $Detail" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Invoke-Engine([string[]]$ArgList, [hashtable]$EnvVars = @{}) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $WorkDir
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(180000)) { try { $p.Kill($true) } catch { } }
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Text = $o.Result + $e.Result }
}

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory $src -Force | Out-Null
  $t = "unit CountUnit;`r`n`r`ninterface`r`n`r`ntype TColor = (clRed, clBlue);`r`n`r`nprocedure Work(A: Integer);`r`n`r`nimplementation`r`n`r`nprocedure Work(A: Integer);`r`nvar C: TColor;`r`nbegin`r`n  C:= clRed;`r`n  if C = clBlue then Work(A - 1);`r`nend;`r`n`r`nend.`r`n"
  [IO.File]::WriteAllText((Join-Path $src 'CountUnit.pas'), $t, [Text.Encoding]::ASCII)
  $db = Join-Path $WorkDir 'count.sqlite'
  $first = Invoke-Engine @('index', $src, '--db', $db)
  if ($first.Code -ne 0) { Write-Host "FATAL: setup index failed: $($first.Text)" -ForegroundColor Red; exit 2 }
  $Idx  = @('index', $src, '--db', $db, '--resolve-only')
  $Fast = @{ DRAGLINT_STAGE_HEARTBEAT_MS = 50; DRAGLINT_STAGE_STALL_WARN_MS = 150 }

  $s = Invoke-Engine $Idx ($Fast + @{ DRAGLINT_TEST_STREAM_COUNT_DELAY_MS = 600 })
  $np = [regex]::Matches($s.Text, 'stage: calls -- NO PROGRESS for \d+ s at ([^\r\n]*)') | ForEach-Object { $_.Groups[1].Value }
  $counting = @($np | Where-Object { $_ -match '\(counting rows\)' })
  Check 'C1 a NO PROGRESS line during a count names the counting step' ($counting.Count -ge 1) "at=[$((@($np) | Select-Object -First 3) -join ' | ')]"
  Check 'C2 the run exits 0' ($s.Code -eq 0) "exit=$($s.Code)"
  $beatCount = ([regex]::Matches($s.Text, 'stage: calls -- still running, [^\r\n]*\(counting rows\)')).Count
  Check 'C4 the beat line names the counting step too' ($beatCount -ge 1) "lines=$beatCount"

  $c = Invoke-Engine $Idx $Fast
  Check 'C3 CONTROL: no count hold -> no NO PROGRESS line' (($c.Text -notmatch 'stage: calls -- NO PROGRESS') -and ($c.Code -eq 0)) "exit=$($c.Code)"
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'run_stage_stream_count_step_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_stage_stream_count_step_guard: PASS'
exit 0
