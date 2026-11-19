<#
  run_usage_log_contract_guard.ps1 -- U1: the usage log has ONE row contract and the report reads it.
  Contract: ts, what, units, avoided, tool (grep|read|mcp), used, est_method (7 fields, TSV).
  Checks:
    1. report on the LIVE stats log: no numeric / 'report' tool key (the 2026-09-29 shifted rows are
       repaired on read), and every skipped row is classified.
    2. report on a synthetic shifted fixture: repaired=1, tool 'report' (positive control).
    3. append helper: a good row lands as 7 fields; a numeric tool, a text number and an embedded
       newline are refused or sanitised, and a refused call writes nothing.
  Usage: powershell -File run_usage_log_contract_guard.ps1 [-Log <path>]
#>
param([string]$Log = '')
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$explicitLog = [bool]$Log
if (-not $Log) { $Log = Join-Path $root 'stats\draglint-usage.log' }
# stats\ is untracked: a lane worktree has no live log. Fall back (READ-ONLY: the report only
# reads it) to the main checkout's log, found through git's common dir, not a hard-coded path.
if (-not $explicitLog -and -not (Test-Path $Log)) {
  $common = (& { $ErrorActionPreference = 'Continue'; & git -C $root rev-parse --path-format=absolute --git-common-dir 2>$null })
  if ($LASTEXITCODE -eq 0 -and $common) {
    $mainLog = Join-Path (Split-Path -Parent $common) 'stats\draglint-usage.log'
    if (Test-Path $mainLog) { Write-Host "note: worktree has no stats log; reading the main checkout's $mainLog"; $Log = $mainLog }
  }
}
$report = Join-Path $root 'tools\draglint-usage-report.cjs'
$append = Join-Path $root 'tools\draglint-usage-append.cjs'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('usage-guard-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$fail = 0
function Check($ok, $msg) { if ($ok) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }

# 1. live log
if (-not (Test-Path $Log)) {
  if ($explicitLog) { Write-Host "FAIL live log missing: $Log (pass -Log)"; exit 1 }
  # no checkout on this box has a live log (fresh clone): nothing to measure -> battery SKIP
  Write-Host "SKIP live log missing: $Log and no main-checkout log (pass -Log)"; exit 77
}
$j = (& node $report --log $Log --json) | ConvertFrom-Json
$bad = @($j.byTool.PSObject.Properties.Name | Where-Object { $_ -match '^\d+$' })
Check ($bad.Count -eq 0) "live log: no numeric tool key (shifted rows repaired) (found: $($bad -join ','))"
$cls = 0; foreach ($p in $j.skippedByClass.PSObject.Properties) { $cls += [int]$p.Value }
Check ($cls -eq $j.skipped) "live log: all $($j.skipped) skipped rows classified"

# 2. synthetic shifted row (positive control)
$fx = Join-Path $tmp 'fx.log'
$tab = "`t"
[IO.File]::WriteAllText($fx, ((@('2026-09-29T04:00:09Z','report','x round-trip','2','4000','report','900') -join $tab) + "`r`n"))
$f = (& node $report --log $fx --json) | ConvertFrom-Json
Check ($f.repaired -eq 1 -and $f.skipped -eq 0 -and $f.byTool.PSObject.Properties.Name -contains 'report') 'fixture: shifted report row repaired in memory'

# 3. append helper
$out = Join-Path $tmp 'out.log'
& node $append --log $out --what "a`tb`nc" --units 2 --avoided 500 --tool grep --used 40
$lines = @([IO.File]::ReadAllLines($out))
Check ($lines.Count -eq 1 -and $lines[0].Split("`t").Count -eq 7 -and $lines[0].EndsWith('cons-v1')) 'append: good row = 7 fields, one line, tabs/newlines sanitised'
$null = & { $ErrorActionPreference = 'Continue'; & node $append --log $out --what w --units 2 --avoided 500 --tool 4000 --used 40 2>&1 | ForEach-Object { "$_" } }
Check ($LASTEXITCODE -eq 2) 'append: numeric tool refused (exit 2)'
$null = & { $ErrorActionPreference = 'Continue'; & node $append --log $out --what w --units '~2' --avoided 500 --tool grep --used 40 2>&1 | ForEach-Object { "$_" } }
Check ($LASTEXITCODE -eq 2) 'append: ~N number refused (exit 2)'
Check (@([IO.File]::ReadAllLines($out)).Count -eq 1) 'append: refused calls wrote nothing'

[IO.Directory]::Delete($tmp, $true)
if ($fail) { Write-Host "RESULT: $fail FAILED"; exit 1 }
Write-Host 'RESULT: all passed'
