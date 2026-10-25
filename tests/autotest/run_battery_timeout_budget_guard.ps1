<#
  run_battery_timeout_budget_guard.ps1 -- the battery's TIMEOUT report names the
  EFFECTIVE budget the runner was given, not the base -TimeoutSec.

  Defect (ENGINE wave 4, H1): under -Jobs N>1 the budget is scaled x2 (and
  RunnerBudgetSec floors raise it further) but the closing 'TIMEOUT (> Ns)' line
  printed the base -TimeoutSec, so a reader saw "> 2s" for a runner that was
  actually allowed 4s.

  Hermetic: copies the driver into a temp repo with one sleeping runner
  (-TimeoutSec 2 -Jobs 2 => effective 4 s; the sleeper outlives it).
  Positive control: the same run serial (-Jobs 1) must report the base 2 s,
  proving the assertion can tell the two values apart.
#>
[CmdletBinding()]
param([string]$RepoRoot = "$PSScriptRoot\..\..")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
$RepoRoot = (Resolve-Path $RepoRoot).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tob_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'tests\sleepy')
Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests\run_battery.ps1') -Destination (Join-Path $tmp 'tests\run_battery.ps1')
[IO.File]::WriteAllText((Join-Path $tmp 'tests\sleepy\run_sleeper.ps1'), "Start-Sleep -Seconds 30`r`n")

function Invoke-Driver([string]$Tag, [int]$Jobs) {
  $out = Join-Path $tmp "$Tag.log"
  $p = Start-Process pwsh -ArgumentList @('-NoProfile', '-NonInteractive', '-File', (Join-Path $tmp 'tests\run_battery.ps1'),
        '-SkipPrepare', '-TimeoutSec', '2', '-Jobs', $Jobs, '-HeartbeatMin', '0', '-LogDir', (Join-Path $tmp "logs_$Tag")) `
        -WorkingDirectory $tmp -PassThru -Wait -RedirectStandardOutput $out -RedirectStandardError "$out.err" -WindowStyle Hidden
  [pscustomobject]@{ Text = (Get-Content -LiteralPath $out -Raw); Exit = $p.ExitCode }
}
$par = Invoke-Driver 'par' 2
$ser = Invoke-Driver 'ser' 1
Check 'parallel run timed out the sleeper' ($par.Text -match 'TIMEOUT' -and $par.Exit -eq 1) "exit=$($par.Exit)"
Check 'parallel TIMEOUT report names the effective budget 4s' ($par.Text -match 'TIMEOUT \(> 4s\)|budget 4s') ''
Check 'parallel TIMEOUT report does NOT print the base 2s' ($par.Text -notmatch 'TIMEOUT \(> 2s\)') ''
Check 'POSITIVE CONTROL: serial run reports the base 2s' ($ser.Text -match 'TIMEOUT \(> 2s\)|budget 2s') ''
try { [IO.Directory]::Delete($tmp, $true) } catch { }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
