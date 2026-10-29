<#
  run_battery_prepare_guard.ps1 -- the battery's known-environment prerequisites
  (1.20.5 #3 of INBOX-2026-09-30-engine-followups-from-1.20.5).

  WHY THIS EXISTS
  ---------------
  Two guards need GITIGNORED artifacts that a fresh worktree does not have:
    run_mcp_protocol_guard        tests\calls.sqlite
    run_lsp_proxy_lifecycle_guard tests\autotest\fixtures\lspproxy\Win64\Debug\LspStubServer.exe
  The fix is tests\autotest\prepare_battery.ps1 (builds every such artifact,
  idempotent) called by tests\run_battery.ps1 before it runs anything. Two
  things can rot silently and turn a fresh worktree battery red again:

    * run_battery.ps1 stops calling prepare_battery (or the call is gated on
      something that is false by default);
    * a guard's default path for the artifact drifts away from the path
      prepare_battery.ps1 creates, so the artifact is "present" but not where
      the guard looks.

  Both are asserted statically here (no build, no engine). The positive control
  removes the calls.sqlite row from a COPY of prepare_battery.ps1's text and
  must be reported, so a vacuous pass is impossible.

  Exit 0 = PASS, 1 = FAIL.
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = "$PSScriptRoot\..\.."
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$RepoRoot = (Resolve-Path $RepoRoot).Path
$driver   = Join-Path $RepoRoot 'tests\run_battery.ps1'
$prepare  = Join-Path $RepoRoot 'tests\autotest\prepare_battery.ps1'
foreach ($f in @($driver, $prepare)) {
  if (-not (Test-Path -LiteralPath $f)) { Write-Host "FATAL: missing $f" -ForegroundColor Red; exit 2 }
}
$driverText  = Get-Content -LiteralPath $driver  -Raw
$prepareText = Get-Content -LiteralPath $prepare -Raw

# One row per (guard, artifact leaf, the token its prepare_battery Need row must carry).
$rows = @(
  @{ Guard = 'run_mcp_protocol_guard.ps1';        Leaf = 'calls.sqlite';        Token = "'tests\calls.sqlite'" },
  @{ Guard = 'run_lsp_proxy_lifecycle_guard.ps1'; Leaf = 'LspStubServer.exe';   Token = "'LspStubServer.exe'" }
)

Write-Host ''
Write-Host 'The driver prepares the environment before running anything' -ForegroundColor Cyan
Check 'run_battery.ps1 invokes autotest\prepare_battery.ps1' `
  ($driverText -match 'prepare_battery\.ps1') ''
Check 'the call is skipped only by -SkipPrepare / a nested run, never by default' `
  ($driverText -match '(?s)-not\s+\$List\s+-and\s+-not\s+\$SkipPrepare\s+-and\s+-not\s+\$env:DRAGLINT_BATTERY_PREPARED') `
  'a default-false gate would leave a fresh worktree red'

function Missing-Rows([string]$PrepText) {
  $m = @()
  foreach ($r in $rows) {
    $guard = Join-Path $RepoRoot ('tests\autotest\' + $r.Guard)
    $gText = if (Test-Path -LiteralPath $guard) { Get-Content -LiteralPath $guard -Raw } else { '' }
    if ($gText -notmatch [regex]::Escape($r.Leaf)) { $m += "$($r.Guard) no longer names $($r.Leaf)" }
    if (-not $PrepText.Contains($r.Token))          { $m += "prepare_battery has no row for $($r.Leaf)" }
  }
  return $m
}

Write-Host ''
Write-Host 'Every gitignored prerequisite has a prepare_battery row, and its guard still looks for it' -ForegroundColor Cyan
$miss = @(Missing-Rows $prepareText)
Check 'calls.sqlite + LspStubServer.exe rows present and named by their guards' ($miss.Count -eq 0) ($miss -join '; ')

Write-Host ''
Write-Host 'POSITIVE CONTROL: a prepare_battery text without the calls.sqlite row is reported' -ForegroundColor Cyan
$broken = $prepareText.Replace("'tests\calls.sqlite'", "'removed'")
$ctl = @(Missing-Rows $broken)
Check 'the missing row is detected' ($ctl.Count -eq 1 -and $ctl[0] -match 'calls\.sqlite') ($ctl -join '; ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
