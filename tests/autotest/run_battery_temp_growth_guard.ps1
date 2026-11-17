<#
  run_battery_temp_growth_guard.ps1 -- v1511 HYG H01: the battery must not leave work dirs behind.

  Every engine-copying guard used to leave a ~100 MB dir per run (INBOX-test-battery-leaks-engine-copies:
  ~12 GB found on one disk). This is the battery-level net.

  Modes
    (no argument)        self-test: positive control (a planted dir IS reported as growth) and negative
                         control (no new dir = no growth). This is what the battery enumerates.
    -Snapshot <file>     write the names of the watched dirs to <file>   (run_battery.ps1 calls this at start)
    -Compare  <file>     list watched dirs not in <file>; exit 1 on any (run_battery.ps1 calls this at the end)
  Watched: C:\TEMP and %TEMP% children named drag-lint-*, draglint_*, draglint-*, drag_lint_*, reparse_guard_*,
  excluding drag-lint-hermetic (a bounded cache: Get-HermeticEngine keeps the newest 3) and drag-lint-cache*.
  Another session writing to C:\TEMP during the run counts as growth; the message names the dirs so it can be judged.
#>
[CmdletBinding()]
param([string]$Snapshot = '', [string]$Compare = '')
$ErrorActionPreference = 'Stop'
$Roots = @('C:\TEMP', [IO.Path]::GetTempPath().TrimEnd('\')) | Select-Object -Unique
function Get-Watched {
  @(foreach ($r in $Roots) {
      if (Test-Path -LiteralPath $r) {
        Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match '^(drag-lint-|draglint_|draglint-|drag_lint_|reparse_guard_)' -and $_.Name -notmatch '^drag-lint-(hermetic|cache)' } |
          ForEach-Object { $_.FullName }
      }
    }) | Sort-Object -Unique
}
function Get-Growth([string]$File) {
  $before = @(Get-Content -LiteralPath $File -ErrorAction Stop | Where-Object { $_ })
  @(Get-Watched | Where-Object { $before -notcontains $_ })
}
if ($Snapshot) { [IO.File]::WriteAllLines($Snapshot, [string[]]@(Get-Watched)); Write-Host "snapshot: $((Get-Watched).Count) watched dir(s) -> $Snapshot"; exit 0 }
if ($Compare) {
  $g = Get-Growth $Compare
  if ($g.Count -eq 0) { Write-Host 'TEMP GROWTH GUARD: PASS (no new work dirs)' -ForegroundColor Green; exit 0 }
  Write-Host "TEMP GROWTH GUARD: FAIL -- $($g.Count) new work dir(s) left behind:" -ForegroundColor Red
  $g | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  exit 1
}
$script:fail = $false
function Check($n, $ok) { Write-Host ("[{0}] {1}" -f @('FAIL','PASS')[[int][bool]$ok], $n) -ForegroundColor @('Red','Green')[[int][bool]$ok]; if (-not $ok) { $script:fail = $true } }
$snap = Join-Path ([IO.Path]::GetTempPath()) ("growth-guard-snap-$PID.txt")
$plant = Join-Path ([IO.Path]::GetTempPath()) ("drag-lint-growthprobe-$PID")
try {
  [IO.File]::WriteAllLines($snap, [string[]]@(Get-Watched))
  Check 'N1 negative control: nothing planted -> no growth (other sessions may add dirs; re-run if this names a foreign dir)' ((Get-Growth $snap | Where-Object { $_ -ne $plant }).Count -eq 0)
  [void][IO.Directory]::CreateDirectory($plant)
  Check 'P1 positive control: a planted drag-lint-* dir IS reported as growth' ((Get-Growth $snap) -contains $plant)
} finally {
  if (Test-Path -LiteralPath $plant) { [IO.Directory]::Delete($plant, $true) }
  if (Test-Path -LiteralPath $snap) { [IO.File]::Delete($snap) }
}
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0