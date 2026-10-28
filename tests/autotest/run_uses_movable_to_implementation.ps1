# Guard: uses-movable-to-implementation (gap-rules wave, lane G8, project-wide, hint, OFF by default).
#
# Fixture tests\lint-project\uses-movable-to-implementation: uA.pas has an interface uses of
#   uB (only the implementation calls BProc)  -> FIRES (line 6)
#   uC (the interface declares FC: TC)         -> silent (the non-hit)
#   uD (referenced nowhere)                    -> silent (that is unused-unit-in-uses, not this rule)
# uE.pas: uB is the LAST entry of a multi-line interface uses -> FIRES (line 11); the fix must
#   rewrite the line above to end in ';' (dogfood 2026-10-27: the removal was dropped, E2004).
# Fix: removes the entry from the interface uses and adds it to the implementation uses;
# expected\uA.fixed.pas is hand-written. Second run is a no-op.
# OFF by default (false positives: reference-to-function signatures leave no ref; the autofix would
# move a still-needed unit): no config and no --rule -> silent; --rule or the config opts in.
# Usage: pwsh -File tests/autotest/run_uses_movable_to_implementation.ps1 [-Exe <path>]
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-g8-umi-$PID")
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\g8-common.ps1"
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$rule = 'uses-movable-to-implementation'
try {
  $fx = New-G8Scratch $rule $WorkDir
  $db = Join-Path $WorkDir 'fx.sqlite'
  $cfg = Join-Path $PSScriptRoot "..\lint-project\$rule\expected\config.json"
  Check 'index exits 0' ((Invoke-G8Index $Exe $fx $db) -eq 0)
  $off = Get-G8Findings $Exe $db $rule -AllRules
  $viaCfg = Get-G8Findings $Exe $db $rule @('--config', $cfg) -AllRules
  $f = Get-G8Findings $Exe $db $rule
  Show-G8Findings $f
  Check 'positive: uB flagged on uA.pas line 6' (@($f | Where-Object { $_.file_path -match 'uA\.pas$' -and [int]$_.start_line -eq 6 }).Count -eq 1)
  Check 'positive: uB flagged on uE.pas line 11 (last entry)' (@($f | Where-Object { $_.file_path -match 'uE\.pas$' -and [int]$_.start_line -eq 11 }).Count -eq 1)
  Check 'negative: uC (used in the interface) and uD (unused) not flagged' ($f.Count -eq 2)
  Check 'message names the unit and points at uses-fix' (($f.Count -eq 2) -and ($f[0].message -match 'uB') -and ($f[0].message -match 'uses-fix'))
  Check 'severity is hint' (($f.Count -eq 2) -and ($f[0].severity -eq 'hint'))
  # --- fix
  $pas = Join-Path $fx 'uA.pas'
  $want = Join-Path $PSScriptRoot "..\lint-project\$rule\expected\uA.fixed.pas"
  & $Exe lint-all --db $db --rule $rule --fix --fix-rule $rule --apply --no-backup 2>&1 | Out-Null
  Check 'fix: result is byte-identical to expected\uA.fixed.pas' (Test-G8BytesEqual $pas $want)
  Check 'fix: last entry -- result is byte-identical to expected\uE.fixed.pas' (Test-G8BytesEqual (Join-Path $fx 'uE.pas') (Join-Path $PSScriptRoot "..\lint-project\$rule\expected\uE.fixed.pas"))
  $before = [IO.File]::ReadAllBytes($pas)
  & $Exe lint-all --db $db --rule $rule --fix --fix-rule $rule --apply --no-backup 2>&1 | Out-Null
  Check 'fix: second run leaves the bytes unchanged' ([Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]][IO.File]::ReadAllBytes($pas)))
  Check 'fix: reindexed fixed file no longer fires' ((Invoke-G8Index $Exe $fx $db) -eq 0 -and (Get-G8Findings $Exe $db $rule).Count -eq 0)
  Check 'OFF by default: no config, no --rule -> silent (control: --rule fired)' (($off.Count -eq 0) -and ($f.Count -eq 2))
  Check 'config enabled -> fires without --rule' ($viaCfg.Count -eq 2)
} finally { [IO.Directory]::Delete($WorkDir, $true) }
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }