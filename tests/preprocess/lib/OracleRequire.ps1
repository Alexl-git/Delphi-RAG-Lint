# Dot-source from a tests\preprocess runner: makes the JS preprocessor ORACLE optional.
#
# The oracle is the grammar project's own preprocess() (tree-sitter-delphi13,
# preprocessor\*.js), run under node, and every ORACLE-DIFF check compares the
# Pascal preprocessor's bytes with its bytes. It used to be required from a
# hard-coded C:\Projects\tree-sitter-delphi13, so on any machine without that
# checkout those checks FAILED -- five runners red for a missing tool, not for a
# defect. The tool must be self-contained, so the oracle now lives INSIDE the
# repo (tests\preprocess\oracle\preprocessor\, see oracle\README.md) and, until
# it is there, its checks are SKIPPED with the reason instead.
#
# What a runner gets:
#   $script:OracleOk      True when node and the oracle are both present
#   $script:OracleWhy     why not, '' when OracleOk
#   $script:OracleDir     where the oracle is expected
#   Check-Oracle <name> { <condition> }
#       runs Check with the condition when the oracle is available, otherwise
#       prints "[SKIP] <name> -- <why>" and records that a check was skipped.
#   $script:OracleSkipped True once any check was skipped. A runner whose other
#       checks all pass ends with exit 77 (SKIP) in that case, never exit 0:
#       a skipped comparison is not a passed one.
#
# The non-oracle checks of a runner always run and can still FAIL.

$script:OracleDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\oracle\preprocessor'))
$why = @()
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { $why += 'node is not on PATH' }
if (-not (Test-Path -LiteralPath (Join-Path $script:OracleDir 'preprocess.js'))) {
  $why += "the JS preprocessor is not in $($script:OracleDir) (see tests\preprocess\oracle\README.md)"
}
$script:OracleOk = ($why.Count -eq 0)
$script:OracleWhy = ($why -join '; ')
$script:OracleSkipped = $false

function Check-Oracle([string]$Name, [scriptblock]$Condition) {
  if ($script:OracleOk) { Check $Name (& $Condition); return }
  Write-Host ("[SKIP] {0} -- {1}" -f $Name, $script:OracleWhy) -ForegroundColor Yellow
  $script:OracleSkipped = $true
}
