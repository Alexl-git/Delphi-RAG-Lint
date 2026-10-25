<#
  run_cli_exit_unknown.ps1 -- the documented exit codes for a mistyped command line
  (AI-USAGE 2a "Exit codes common to every verb", e3d W5 item 4).

  An unknown VERB exits 2 with `ERROR: unknown command:`; an unknown FLAG exits 3 with
  `FATAL:` on stderr -- the code menu-tree / menu-drift / ask use for a stale index, told
  apart by stderr. Kept (not renumbered) because guards and verb contracts pin the 3.

  Positive control: `--version` exits 0, so a crashing exe cannot pass the checks.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$null = & $Exe --version 2>&1
Check 'control: --version exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$v = (& $Exe nosuchverb-w5 2>&1 | Out-String)
Check 'unknown verb exits 2 with "unknown command"' (($LASTEXITCODE -eq 2) -and ($v -match 'unknown command: nosuchverb-w5')) "exit=$LASTEXITCODE"
$f = (& $Exe cycles --no-such-flag-w5 2>&1 | Out-String)
Check 'unknown flag exits 3 with FATAL on stderr' (($LASTEXITCODE -eq 3) -and ($f -match 'FATAL: .*Unknown argument: --no-such-flag-w5')) "exit=$LASTEXITCODE"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
