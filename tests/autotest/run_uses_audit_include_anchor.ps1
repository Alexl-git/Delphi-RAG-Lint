<#
  run_uses_audit_include_anchor.ps1 -- wave 150 lane CF, item 3: the uses-audit verdict
  (verb `uses-audit` and lint rule `uses-movable-to-implementation`) for a uses entry
  that is written INSIDE an include file (`uses {$I MvUses.inc}`, EX2 F4).

  The index gives such an entry host unit_uses coordinates INSIDE the .inc (origin_path
  + include_line set). Before 150 CF the audit reported them as if they were the
  host's: MvHost.pas:2:3 -- a line of the host that has nothing to do with the entry.
  Contract: an include-origin entry is anchored at the host's `{$I}` directive line
  (column 1), exactly as used-unit-not-resolvable anchors it; an inline entry keeps its
  own coordinates (control: MvInline.pas, line 6 col 13).
  Positive control: the 1.49.0-alpha base engine reports line 2 for MvHost -> FAILS.

  Fixture: tests\fixtures\uses-audit-inc (3 units + 1 include). Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uses-audit-include-$PID"
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_uses_audit_include_anchor: needs pwsh 7' -ForegroundColor Red; exit 2 }
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
& $Exe index $fx --db $db *> (Join-Path $WorkDir 'index.log')
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE"

# Raw shape first: lint-all --json is a bare ARRAY with file_path + start_line.
$raw = (& $Exe lint-all --db $db --rule uses-movable-to-implementation --json 2>$null) -join "`n"
$f = @($raw | ConvertFrom-Json)
$host1 = @($f | Where-Object { $_.file_path -like '*\MvHost.pas' })
$inl   = @($f | Where-Object { $_.file_path -like '*\MvInline.pas' })
Check 'LINT include entry: exactly one finding in MvHost.pas' ($host1.Count -eq 1) "count=$($host1.Count)"
Check 'LINT include entry anchored at the {$I} directive (line 6, col 1)' (($host1.Count -eq 1) -and ($host1[0].start_line -eq 6) -and ($host1[0].start_col -eq 1) -and ($host1[0].end_line -eq 6)) "got $($host1[0].start_line):$($host1[0].start_col)-$($host1[0].end_line):$($host1[0].end_col)"
Check 'LINT control: inline entry keeps its own coordinates (line 6, col 13)' (($inl.Count -eq 1) -and ($inl[0].start_line -eq 6) -and ($inl[0].start_col -eq 13)) "got $($inl[0].start_line):$($inl[0].start_col)"

$a = @((& $Exe uses-audit (Join-Path $fx 'MvHost.pas') --db $db --format json 2>$null) -join "`n" | ConvertFrom-Json)
Check 'VERB include entry: uses-audit reports line 6' (($a.Count -eq 1) -and ($a[0].unit -eq 'MvB') -and ($a[0].line -eq 6)) "got $($a[0].unit) line $($a[0].line)"
$b = @((& $Exe uses-audit (Join-Path $fx 'MvInline.pas') --db $db --format json 2>$null) -join "`n" | ConvertFrom-Json)
Check 'VERB control: inline entry reports its own line 6' (($b.Count -eq 1) -and ($b[0].line -eq 6)) "got line $($b[0].line)"

try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (scratch not removed: $WorkDir)" }
if ($script:Failed) { Write-Host 'run_uses_audit_include_anchor: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_uses_audit_include_anchor: all checks passed' -ForegroundColor Green
exit 0