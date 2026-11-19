<#
  run_uses_audit_include_suffix.ps1 -- wave 150 tails T1 (G2): the message of
  `uses-movable-to-implementation` for an entry written INSIDE an include file carries
  the suffix " (in include MvUses.inc, line 2)" (TUnitUse.IncludeSuffix, as used-unit-not-
  resolvable / layering do), because the finding is anchored at the host's {$I} line and
  would otherwise not say where the entry really is. An inline entry has NO suffix.
  Positive control: the 1.49.0-alpha base engine emits no suffix -> FAILS.
  Fixture: tests\fixtures\uses-audit-inc. Run from any CWD, pwsh 7.
#>

[CmdletBinding()]
param(
  [string]$Exe = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-uses-audit-include-sfx-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_uses_audit_include_suffix: needs pwsh 7' -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$fx = (Resolve-Path "$PSScriptRoot\..\fixtures\uses-audit-inc").Path
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$db = Join-Path $WorkDir 'mv.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $fx --db $db *> (Join-Path $WorkDir 'index.log') }
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE"

$raw = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --rule uses-movable-to-implementation --json 2>$null }) -join "`n"
$f = @(($raw | ConvertFrom-Json) | ForEach-Object { $_ })
$h = @($f | Where-Object { $_.file_path -like '*\MvHost.pas' })
$n = @($f | Where-Object { $_.file_path -like '*\MvInline.pas' })
Check 'include entry: one finding in MvHost.pas' ($h.Count -eq 1) "count=$($h.Count)"
Check 'include entry message ends with " (in include MvUses.inc, line 2)"' (($h.Count -eq 1) -and ($h[0].message -like '*(in include MvUses.inc, line 2)')) "got: $($h[0].message)"
Check 'control: inline entry has no include suffix' (($n.Count -eq 1) -and ($n[0].message -notlike '*(in include*')) "got: $($n[0].message)"
try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (scratch not removed: $WorkDir)" }
if ($script:Failed) { Write-Host 'run_uses_audit_include_suffix: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_uses_audit_include_suffix: all checks passed' -ForegroundColor Green
exit 0