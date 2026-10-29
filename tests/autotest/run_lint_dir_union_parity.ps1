<#
  run_lint_dir_union_parity.ps1 -- `lint <dir>` must report the UNION of what
  `lint <file>` reports for every file the walk scanned, with the same flags.

  Measured 2026-10-27 over tests\lint: with --rule, dir vs file gave
  raise-in-destructor 0 vs 2, nil-check-after-dereference 0 vs 5,
  try-except-swallowed 0 vs 12, and exception-escapes-thread 0 vs 3 with no
  --rule at all. The .scm rules agreed (weak-hash-for-secret 2 vs 2): the
  directory branch of DoLint ran only Linter.LintFolder, and every built-in
  Pascal checker sat behind a `TFile.Exists(EffPath)` gate.

  The fixture dir is built at run time from tests\lint copies, so the guard
  shares its fixtures with run_lint_tests.ps1 instead of forking them.

  Case 1: no --rule -- the full tuple multiset (file, rule, line) of the dir run
          equals the concatenation of the per-file runs.
  Case 2: --rule <id> for each built-in id above -- dir count = sum of file
          counts, and that sum is > 0 (positive control: a guard that passes
          on 0 = 0 proves nothing).

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_dir_union_$PID",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([bool]$ok, [string]$what) {
  if ($ok) { if (-not $Quiet) { Write-Host "PASS  $what" } }
  else     { Write-Host "FAIL  $what" -ForegroundColor Red; $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$src     = (Resolve-Path "$PSScriptRoot\..\lint").Path
$names   = @('raise-in-destructor', 'nil-check-after-dereference', 'try-except-swallowed',
             'exception-escapes-thread', 'weak-hash-for-secret')
New-Item -ItemType Directory -Force $WorkDir | Out-Null
foreach ($n in $names) { Copy-Item (Join-Path $src "$n.pas") $WorkDir -Force }

function Tuples([string]$path, [string[]]$extra) {
  $out = & $exePath lint $path --json @extra 2>$null
  $j = @($out | ConvertFrom-Json)
  return @($j | ForEach-Object { '{0}|{1}|{2}' -f (Split-Path $_.file_path -Leaf), $_.rule, $_.start_line } | Sort-Object)
}

Push-Location $env:TEMP
try {
  # Case 1: no --rule.
  $dir = Tuples $WorkDir @()
  $per = @()
  foreach ($n in $names) { $per += Tuples (Join-Path $WorkDir "$n.pas") @() }
  $per = @($per | Sort-Object)
  $missing = @($per | Where-Object { $dir -notcontains $_ })
  $extra   = @($dir | Where-Object { $per -notcontains $_ })
  Check ($missing.Count -eq 0) "dir run has every per-file finding (missing $($missing.Count): $(($missing | Select-Object -First 5) -join ', '))"
  Check ($extra.Count -eq 0)   "dir run adds nothing the per-file runs lack (extra $($extra.Count): $(($extra | Select-Object -First 5) -join ', '))"
  Check ($dir.Count -eq $per.Count) "dir total $($dir.Count) = per-file total $($per.Count)"

  # Case 2: --rule <id>.
  foreach ($r in $names) {
    $d = @(Tuples $WorkDir @('--rule', $r)).Count
    $f = 0
    foreach ($n in $names) { $f += @(Tuples (Join-Path $WorkDir "$n.pas") @('--rule', $r)).Count }
    Check (($f -gt 0) -and ($d -eq $f)) "--rule $r : dir $d = per-file sum $f (> 0)"
  }
} finally {
  Pop-Location
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:fail) { Write-Host 'run_lint_dir_union_parity: FAIL'; exit 1 }
Write-Host 'run_lint_dir_union_parity: PASS'
exit 0
