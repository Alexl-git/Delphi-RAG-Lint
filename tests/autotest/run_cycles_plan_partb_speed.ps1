<#
  Lane 148 HP2B (149-CY-PERF, hub-SCC spec P2b part b): `cycles --plan` Part B render speed on a REAL hub group.

  Loader2025 (78-unit hub SCC around frmLoader2019_Main) spent 219 of 261 s in RenderPartB (lane CY). The cause was
  per-edge store round trips -- BuildEdgeSurface re-read every ref of the consumer and asked the store per ref for
  every edge, NeedsOf walked the class chain per (routine, name), BodyRanges re-queried per need. HP2B memoizes
  those reads (IEdgeSurfaceCache + planner memos). No behaviour change: the plan text must stay byte-identical.

  What it checks, on a COPY of the Loader index (never the real DB):
    1. `cycles --plan --ctor-wide` exits 0 and prints a plan;
    2. DRAGLINT_CYCLE_TIMING=1 stage `RenderIntfCycle RenderPartB` is under -BudgetMs (default 60000);
    3. with -RefPlan, stdout is byte-identical to that reference (a plan produced by the pre-fix engine).
  Positive control: run it with -Exe <a pre-HP2B build> -- check 2 FAILs (RenderPartB 145-219 s there).

  No Loader DB copy given -> SKIP (exit 0): the battery has no Loader index; this is a measurement guard.
  pwsh 7 only (Windows PowerShell 5 dies on the engine's stderr banner).
#>
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Db       = '',
  [string]$Project  = 'C:\Projects\Loader2019\Loader2025.dproj',
  [string]$LibDb    = 'C:\Projects\.drag-lint\library-Win32.sqlite',
  [string]$RefPlan  = '',
  [int]   $BudgetMs = 60000,
  [string]$WorkDir  = (Join-Path ([IO.Path]::GetTempPath()) 'dl-partb-speed')
)
$ErrorActionPreference = 'Stop'
$fail = 0
function Lane-Check([bool]$pOk, [string]$pWhat) {
  if ($pOk) { Write-Host "[PASS] $pWhat" } else { Write-Host "[FAIL] $pWhat" -ForegroundColor Red; $script:fail++ }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if ($Db -eq '' -or -not (Test-Path $Db) -or -not (Test-Path $Project)) {
  Write-Host '[SKIP] no Loader index copy (-Db) or project: measurement guard, nothing to measure'
  exit 0
}
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null
$out = Join-Path $WorkDir 'plan.txt'
$err = Join-Path $WorkDir 'timing.txt'
$env:DRAGLINT_CYCLE_TIMING = '1'
$cmdArgs = @('cycles', '--plan', '--ctor-wide', '--project', $Project, '--db', $Db)
if (Test-Path $LibDb) { $cmdArgs += @('--library-db', $LibDb) }
$p = Start-Process -FilePath $Exe -ArgumentList $cmdArgs -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput $out -RedirectStandardError $err
[Environment]::SetEnvironmentVariable('DRAGLINT_CYCLE_TIMING', $null)
Lane-Check ($p.ExitCode -eq 0) "cycles --plan exit code 0 (got $($p.ExitCode))"
$plan = [IO.File]::ReadAllText($out)
Lane-Check ($plan -match '### Part B') 'the plan prints a Part B section'
$m = Select-String -Path $err -Pattern 'cycles plan timing: RenderIntfCycle RenderPartB (\d+) ms' | Select-Object -First 1
Lane-Check ($null -ne $m) 'DRAGLINT_CYCLE_TIMING printed the RenderPartB stage'
if ($null -ne $m) {
  $ms = [int64]$m.Matches[0].Groups[1].Value
  Lane-Check ($ms -le $BudgetMs) "RenderPartB $ms ms <= budget $BudgetMs ms"
}
if ($RefPlan -ne '') {
  $same = [Linq.Enumerable]::SequenceEqual([IO.File]::ReadAllBytes($RefPlan), [IO.File]::ReadAllBytes($out))
  Lane-Check $same "plan stdout byte-identical to $RefPlan"
}
Write-Host ("partb_speed: {0} FAIL" -f $fail)
exit ([int]($fail -gt 0))
