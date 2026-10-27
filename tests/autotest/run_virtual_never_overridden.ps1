# Guard: virtual-never-overridden (gap-rules wave, lane G8, project-wide, hint, OFF by default).
#
# Fixture tests\lint-project\virtual-never-overridden\uV.pas:
#   DrawA virtual, no override anywhere          -> FIRES (line 8)
#   DrawB virtual, overridden by TCircle.DrawB   -> silent (the non-hit)
#   DrawC virtual abstract                       -> silent
#   DrawD dynamic, no override                   -> FIRES (line 11)
#   constructor Create virtual                   -> silent (metaclass construction is invisible to the index)
# OFF by default: with no config and no --rule the rule must be silent (positive control for the config below).
# Fix (risky): deletes the `virtual;` / `dynamic;` directive; expected\uV.fixed.pas is hand-written.
# Usage: pwsh -File tests/autotest/run_virtual_never_overridden.ps1 [-Exe <path>]
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-g8-vno-$PID")
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\g8-common.ps1"
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$rule = 'virtual-never-overridden'
try {
  $fx = New-G8Scratch $rule $WorkDir
  $db = Join-Path $WorkDir 'fx.sqlite'
  $cfg = Join-Path $PSScriptRoot "..\lint-project\$rule\expected\config.json"
  Check 'index exits 0' ((Invoke-G8Index $Exe $fx $db) -eq 0)
  $off = Get-G8Findings $Exe $db $rule -AllRules
  $f = Get-G8Findings $Exe $db $rule @('--config', $cfg)
  Show-G8Findings $f
  $lines = @($f | ForEach-Object { [int]$_.start_line } | Sort-Object)
  Check 'positive: DrawA flagged (line 8)' ($lines -contains 8)
  Check 'positive: DrawD (dynamic) flagged (line 11)' ($lines -contains 11)
  Check 'negative: overridden DrawB, abstract DrawC and virtual constructor silent' ($f.Count -eq 2)
  Check 'severity is hint' (($f.Count -gt 0) -and ($f[0].severity -eq 'hint'))
  # --- fix
  $pas = Join-Path $fx 'uV.pas'
  $want = Join-Path $PSScriptRoot "..\lint-project\$rule\expected\uV.fixed.pas"
  $fixArgs = @('--config', $cfg, '--fix', '--fix-rule', $rule, '--apply', '--no-backup')
  & $Exe lint-all --db $db --rule $rule @fixArgs 2>&1 | Out-Null
  Check 'fix: result is byte-identical to expected\uV.fixed.pas' (Test-G8BytesEqual $pas $want)
  $before = [IO.File]::ReadAllBytes($pas)
  & $Exe lint-all --db $db --rule $rule @fixArgs 2>&1 | Out-Null
  Check 'fix: second run leaves the bytes unchanged' ([Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]][IO.File]::ReadAllBytes($pas)))
  Check 'fix: reindexed fixed file no longer fires' ((Invoke-G8Index $Exe $fx $db) -eq 0 -and (Get-G8Findings $Exe $db $rule @('--config', $cfg)).Count -eq 0)
  # OFF by default is only meaningful beside the positive control above.
  Check 'OFF by default: no config, no --rule -> silent (control: the config run fired)' (($off.Count -eq 0) -and ($f.Count -eq 2))
} finally { [IO.Directory]::Delete($WorkDir, $true) }
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }