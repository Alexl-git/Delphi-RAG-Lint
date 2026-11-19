<#
  run_v1511_AST_fixes.ps1 -- lane AST of 1.51.1: Y2, Y3 (deep-nesting), R8 (mutable-global-variable),
  B18a (default-encoding-io), B19 (referenced-never-set),
  B15 (hardcoded-absolute-path: bare 2-char drive root with no sink).

  Each tests\autotest\fixtures\v1511-AST\<X>.pas has <X>.expected (format of tests\lint\run_lint_tests.ps1:
  "<rule> <line>" must fire, "!<rule> <line>" must not). Every item carries a positive control, so the
  runner cannot pass with a rule switched off.

  Usage: pwsh -File tests\autotest\run_v1511_AST_fixes.ps1 [-Exe <drag-lint.exe>]
#>
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = (Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe') }
$ErrorActionPreference = 'Stop'
$fx  = Join-Path $PSScriptRoot 'fixtures\v1511-AST'
$cfg = Join-Path $fx 'config.json'
$exePath = (Resolve-Path $Exe).Path
$pass = 0; $fail = 0
foreach ($pas in Get-ChildItem (Join-Path $fx '*.pas')) {
  $expFile = [IO.Path]::ChangeExtension($pas.FullName, '.expected')
  if (-not (Test-Path $expFile)) { continue }
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath lint $pas.FullName --config $cfg --json 2>$null }
  $findings = @()
  try { $findings = @($raw | ConvertFrom-Json) } catch { $findings = @() }
  $pairs = @{}
  foreach ($f in $findings) { if ($null -ne $f) { $pairs["$($f.rule):$($f.start_line)"] = $true } }
  foreach ($d in Get-Content $expFile) {
    $t = $d.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $neg = $t.StartsWith('!')
    $parts = $t.TrimStart('!').Trim() -split '\s+'
    $key = "$($parts[0]):$($parts[1])"
    $ok = if ($neg) { -not $pairs.ContainsKey($key) } else { $pairs.ContainsKey($key) }
    if ($ok) { $pass++; Write-Host "PASS $($pas.Name) $t" }
    else     { $fail++; Write-Host "FAIL $($pas.Name) $t" }
  }
}
Write-Host "v1511-AST: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0