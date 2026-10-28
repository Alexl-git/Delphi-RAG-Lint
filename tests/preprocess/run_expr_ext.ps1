<#
  run_expr_ext.ps1 -- lane INC3 (2026-10-27): the {$IF} evaluator's constant-
  expression surface beyond defined()/comparisons: arithmetic (+ - * div mod),
  unary minus, xor, string comparison and concatenation, True/False, Ord,
  SizeOf/High/Low on basic types (pointer size from CPUX64), Declared() of a
  compiler built-in. Driven through dump-pp-eval (prints true/false).
  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false; $n = 0; $bad = 0
function Check($name, $ok) {
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]), $name) -ForegroundColor (@('Red','Green')[[int]$ok])
  $script:n++; if (-not $ok) { $script:fail = $true; $script:bad++ }
}
$exePath = (Resolve-Path $Exe).Path
function EvalExpr([string]$expr, [string[]]$defines, [string[]]$numeric) {
  $cliArgs = @('dump-pp-eval', '--expr', $expr)
  foreach ($d in $defines) { $cliArgs += @('--define', $d) }
  foreach ($v in $numeric) { $cliArgs += @('--numeric', $v) }
  return (& $exePath @cliArgs 2>$null | Out-String).Trim().ToLower()
}
function T([string]$expr, [string]$want, [string[]]$defines = @(), [string[]]$numeric = @()) {
  $got = EvalExpr $expr $defines $numeric
  Check ("{0} -> {1} (got {2})" -f $expr, $want, $got) ($got -eq $want)
}
Push-Location C:\TEMP
try {
  T '1 + 2 * 3 = 7' 'true'
  T '(1 + 2) * 3 = 9' 'true'
  T '10 div 3 = 3' 'true'
  T '10 mod 3 = 1' 'true'
  T '7 - 10 < 0' 'true'
  T '-2 < 0' 'true'
  T '-(2 + 1) = -3' 'true'
  T 'X * 2 = 6' 'true' @() @('X=3')
  T 'X * 2 = 7' 'false' @() @('X=3')
  T '(1 xor 3) = 2' 'true'
  T 'True xor False' 'true'
  T 'True xor True' 'false'
  T 'True' 'true'
  T 'not False' 'true'
  T "'abc' < 'abd'" 'true'
  T "'ab' = 'ab'" 'true'
  T "'a' + 'b' = 'ab'" 'true'
  T "'ab' <> 'ab'" 'false'
  T "Ord('A') = 65" 'true'
  T 'Ord(True) = 1' 'true'
  T 'SizeOf(Integer) = 4' 'true'
  T 'SizeOf(Int64) = 8' 'true'
  T 'High(Byte) = 255' 'true'
  T 'Low(ShortInt) = -128' 'true'
  T 'High(Integer) = 2147483647' 'true'
  T 'SizeOf(Pointer) = 8' 'true' @('CPUX64')
  T 'SizeOf(Pointer) = 4' 'true' @('CPUX86')
  T 'SizeOf(NativeInt) = 8' 'true' @('CPUX64')
  T 'Declared(Integer)' 'true'
  T 'Declared(CompilerVersion)' 'true' @() @('CompilerVersion=37')
  T 'Declared(NoSuchThing)' 'false'
  T 'CompilerVersion >= 37' 'true' @() @('CompilerVersion=37')
  T 'defined(WIN64) and (CompilerVersion + 1 > 37)' 'true' @('WIN64') @('CompilerVersion=37')
} finally { Pop-Location }
Write-Host ("RESULT: {0} passed, {1} failed" -f ($n - $bad), $bad)
if ($fail) { exit 1 } else { exit 0 }