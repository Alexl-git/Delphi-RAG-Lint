<#
  run_v1511_CLI_b16_rule_list_narrows.ps1 -- lane v1511 CLI, item B16.
  `lint-all --rule a,b` returned the right union but ran EVERY checker and filtered the
  report (520 s on a YADF copy vs 3 s for one id). Now a list narrows execution the way
  one id does. Asserted: (1) the list's findings equal the union of the two single-id
  runs (rule:file:line); (2) the list run takes < 2 x the slower single-id run;
  (3) no --shared-db peer is derived (the base ran a whole lint-all per peer -- the real
  520 s, and on a DB copy the peers are the REAL sibling DBs); (4) the text report does not claim "none detected" for circular-uses on a list run
  that did not ask for it.
  Needs a real index COPY (never a live DB): -Db, default the lane's YADF copy. The DB is
  copied to a private temp dir first, so the source is never opened. Do NOT point a pre-1.51.1
  engine at it: the old list path derives --shared-db peers from the manifest, which on a copy
  are the REAL sibling DBs (a whole lint-all each).
  Usage: pwsh -File tests\autotest\run_v1511_CLI_b16_rule_list_narrows.ps1 [-Exe <exe>] [-Db <copy.sqlite>]
#>
param(
  [string]$Exe = '',
  [string]$Db  = (Join-Path 'C:\' 'TEMP\claude\lanes\v1511\_dbs\YADF.sqlite'),
  [string]$RuleA = 'dictionary-get-without-check',
  [string]$RuleB = 'threadvar-managed'
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe') }
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
if (-not (Test-Path -LiteralPath $Db)) { Write-Host "SKIP: no index copy at $Db (pass -Db)"; exit 0 }
$script:scratch = Join-Path $env:TEMP ("v1511_cli_b16_" + $PID); $scratch = $script:scratch
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail" -ForegroundColor Red; $script:fail++ }
}
function Run-LintAll([string]$Rule) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $errF = Join-Path $script:scratch ("err-" + ($Rule -replace '[^a-z]', '') + ".txt")
  $out = & { $ErrorActionPreference = 'Continue'; $dlErrFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($errF); [IO.File]::WriteAllText($dlErrFile, ''); & $exePath lint-all --db $script:dbc --rule $Rule --json 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { [IO.File]::AppendAllText($dlErrFile, "$_" + [Environment]::NewLine) } else { $_ } } } | Out-String
  $sw.Stop()
  $rows = @()
  if ($out.Trim() -ne '') { $rows = @(($out | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) }
  $keys = @($rows | ForEach-Object { '{0}:{1}:{2}' -f $_.rule, $_.file_path, $_.start_line } | Sort-Object)
  [pscustomobject]@{ Secs = $sw.Elapsed.TotalSeconds; Keys = $keys; Err = [IO.File]::ReadAllText($errF) }
}
try {
  $script:dbc = Join-Path $scratch 'copy.sqlite'
  Copy-Item -LiteralPath $Db $script:dbc
  $a = Run-LintAll $RuleA
  $b = Run-LintAll $RuleB
  $l = Run-LintAll "$RuleA,$RuleB"
  Write-Host ("timing: {0}={1:N1}s  {2}={3:N1}s  list={4:N1}s" -f $RuleA, $a.Secs, $RuleB, $b.Secs, $l.Secs)
  $union = @(($a.Keys + $b.Keys) | Sort-Object -Unique)
  Check 'list findings == union of the two single-id runs' (($l.Keys -join '|') -eq ($union -join '|')) ("list=" + ($l.Keys -join '|') + " union=" + ($union -join '|'))
  Check 'control: the union is not empty (the check can fail)' ($union.Count -gt 0) "$($union.Count)"
  $slow = [Math]::Max($a.Secs, $b.Secs)
  Check ('list run < 2 x the slower single-id run ({0:N1}s < {1:N1}s)' -f $l.Secs, (2 * $slow)) ($l.Secs -lt (2 * $slow))
  $txt = & { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $script:dbc --rule "$RuleA,$RuleB" 2>&1 | ForEach-Object { "$_" } } | Out-String
  # text mode prints 'lint-all: --shared-db: running <db> ...' per peer (--json is silent): a list must derive none
  Check 'list run derived no --shared-db peer (no whole lint-all of a sibling -- possibly REAL -- DB)' (-not ($txt -match 'shared-db: running')) (($txt -split "`r?`n" | Select-String 'shared-db') -join ' | ')
  Check 'text report: circular-uses is NOT REPORTED, not "none detected"' (-not ($txt -match 'none detected across')) ($txt -split "`r?`n" | Select-String 'circular|NOT REPORTED' | Out-String)
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($fail -gt 0) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
