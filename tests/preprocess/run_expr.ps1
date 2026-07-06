<#
  run_expr.ps1 -- TDD harness for PP-Task-3: the {$IF expr} evaluator
  (port of preprocessor/evalExpr.js).

  Exercises EvalPPExpr through the staged exe via the dump-pp-eval diagnostic
  verb. dump-pp-eval takes:
    --expr "<E>"        the compile-time expression to evaluate
    --define <SYM>      repeatable; adds a lowercased defined symbol
    --numeric <K=V>     repeatable; adds a lowercased numeric define (K -> int V)
  and prints exactly 'true' or 'false' (lowercase) on stdout.

  The assertion table mirrors the brief:
    defined(WIN64)                       [WIN64]              -> true
    defined(LINUX)                       [WIN64]              -> false
    defined(WIN64) and defined(UNICODE)  [WIN64,UNICODE]      -> true
    defined(WIN64) and defined(LINUX)    [WIN64,UNICODE]      -> false
    not defined(LINUX)                   [WIN64]              -> true
    WIN64  (bare)                        [WIN64]              -> true
    LINUX  (bare)                        [WIN64]              -> false
    CompilerVersion >= 37   numeric CompilerVersion=37        -> true
    CompilerVersion >= 38   numeric CompilerVersion=37        -> false
    (defined(LINUX) or defined(WIN64))   [WIN64]              -> true
    @#$%   (garbage)                                          -> false

  The numeric-comparison rows are the critical bool/number-mixing check: a
  numeric-map ident compared with >= to an INT literal must resolve as an
  arithmetic comparison, not a defined-test.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path

# Evaluate one expression and return the trimmed lowercase stdout ('true'/'false'
# or something unexpected). $defines / $numeric are string arrays; each element
# becomes a repeated --define / --numeric flag.
function EvalExpr([string]$expr, [string[]]$defines, [string[]]$numeric) {
  $cliArgs = @('dump-pp-eval', '--expr', $expr)
  foreach ($d in $defines) { $cliArgs += @('--define', $d) }
  foreach ($n in $numeric) { $cliArgs += @('--numeric', $n) }
  $out = & $exePath @cliArgs 2>$null | Out-String
  return $out.Trim().ToLower()
}

Push-Location C:\TEMP
try {
  # --- defined() membership ---
  Check 'defined(WIN64) with WIN64 defined -> true'                       ((EvalExpr 'defined(WIN64)' @('WIN64') @()) -eq 'true')
  Check 'defined(LINUX) with WIN64 defined -> false'                      ((EvalExpr 'defined(LINUX)' @('WIN64') @()) -eq 'false')

  # --- and ---
  Check 'defined(WIN64) and defined(UNICODE) both defined -> true'        ((EvalExpr 'defined(WIN64) and defined(UNICODE)' @('WIN64','UNICODE') @()) -eq 'true')
  Check 'defined(WIN64) and defined(LINUX) -> false'                      ((EvalExpr 'defined(WIN64) and defined(LINUX)' @('WIN64','UNICODE') @()) -eq 'false')

  # --- not ---
  Check 'not defined(LINUX) -> true'                                      ((EvalExpr 'not defined(LINUX)' @('WIN64') @()) -eq 'true')

  # --- bare identifier (treated as defined-test) ---
  Check 'bare WIN64 -> true'                                              ((EvalExpr 'WIN64' @('WIN64') @()) -eq 'true')
  Check 'bare LINUX -> false'                                             ((EvalExpr 'LINUX' @('WIN64') @()) -eq 'false')

  # --- numeric comparison (the bool/number-mixing check) ---
  Check 'CompilerVersion >= 37 (numeric=37) -> true'                      ((EvalExpr 'CompilerVersion >= 37' @() @('CompilerVersion=37')) -eq 'true')
  Check 'CompilerVersion >= 38 (numeric=37) -> false'                     ((EvalExpr 'CompilerVersion >= 38' @() @('CompilerVersion=37')) -eq 'false')

  # --- parenthesized or ---
  Check '(defined(LINUX) or defined(WIN64)) -> true'                      ((EvalExpr '(defined(LINUX) or defined(WIN64))' @('WIN64') @()) -eq 'true')

  # --- garbage -> conservative false (exception path) ---
  Check 'garbage @#$% -> false (conservative)'                           ((EvalExpr '@#$%' @() @()) -eq 'false')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
