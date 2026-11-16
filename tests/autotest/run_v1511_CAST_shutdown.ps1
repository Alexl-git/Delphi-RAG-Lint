# v1511 CAST B25: a narrow-param / redundant-cast PLAN run opens the control channel, so `shutdown --db <its db>` stops it.
# Usage: run_v1511_CAST_shutdown.ps1 -Engine <drag-lint.exe> -DbPath <private DB copy> -Project <X.dproj>
# Scoped to ONE db (never --all) and to the PID this script started. RED when the run ignores the shutdown.
param([Parameter(Mandatory)][string]$Engine, [Parameter(Mandatory)][string]$DbPath, [Parameter(Mandatory)][string]$Project)
$ErrorActionPreference = 'Stop'
$fail = 0
function Test-One([string]$Name, [string[]]$VerbArgs) {
  $log = Join-Path $env:TEMP ("cast-shutdown-$Name-" + [guid]::NewGuid().ToString('N') + '.log')
  $p = Start-Process -FilePath $Engine -ArgumentList $VerbArgs -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  try {
    Start-Sleep -Seconds 3
    if ($p.HasExited) { Write-Host "SKIP ${Name}: run ended before the shutdown (too fast to test)"; return }
    & $Engine shutdown --db $DbPath --wait 30 *> $null
    $stopped = $p.WaitForExit(40000)
    if ($stopped -and $p.ExitCode -eq 1) { Write-Host "PASS ${Name}:  stopped by shutdown, exit 1" }
    else { Write-Host "FAIL ${Name}:  stopped=$stopped exit=$(if ($stopped) { $p.ExitCode } else { 'running' })"; $script:fail++ }
  } finally {
    if (-not $p.HasExited) { $p.Kill($true) }   # only the PID this script started
  }
}
Test-One 'narrow-param' @('narrow-param', '--all', '--db', $DbPath, '--project', $Project, '--library-db', 'none')
Test-One 'redundant-cast' @('lint', '--fix', '--fix-rule', 'redundant-cast', '--db', $DbPath, '--project', $Project, '--library-db', 'none')
if ($fail -gt 0) { Write-Host "RESULT: $fail FAIL"; exit 1 }
Write-Host 'RESULT: PASS'
