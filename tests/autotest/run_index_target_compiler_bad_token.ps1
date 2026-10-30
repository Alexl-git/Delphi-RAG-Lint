<#
  run_index_target_compiler_bad_token.ps1 -- `index --target-compiler <token>`
  refuses a version token it cannot resolve with exit 2, as lint / lint-all /
  rules always did (whole-branch review, 1.39).

  THE DEFECT. ApplyPreprocessCompilerVersion ignored a failed resolve: `index
  --target-compiler 99` ran at the installed Delphi's CompilerVersion and stamped
  that `cv=` into the fingerprint, while `lint --target-compiler 99` exited 2.

  WHAT THIS ASSERTS
    1. index --target-compiler 99: exit 2, the refusal on stderr, no database made  <- THE FIX
    2. CONTROL: index --target-compiler 12: exit 0
    3. CONTROL: index --target-compiler auto on a .dpr (no ProjectVersion): exit 0
       -- an unmappable "auto" stays silent (index --all resolves it per section)

  RED-CHECK: against the build before the fix 1 FAILS (exit 0); 2 and 3 pass on both.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$work = Join-Path C:\TEMP "draglint_tcbad_$PID"
[void][System.IO.Directory]::CreateDirectory($work)
function Write-Ascii([string]$path, [string]$text) {
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
Write-Ascii (Join-Path $work 'Tc.dpr') "program Tc;`n`nuses`n  UTc in 'UTc.pas';`n`nbegin`nend.`n"
Write-Ascii (Join-Path $work 'UTc.pas') "unit UTc;`n`ninterface`n`nprocedure Touch;`n`nimplementation`n`nprocedure Touch;`nbegin`nend;`n`nend.`n"
$dpr = Join-Path $work 'Tc.dpr'
function Run([string]$Tok, [string]$Db) {
  $out = Join-Path $work "o-$Tok.log"
  cmd /c "`"$Exe`" index --project `"$dpr`" --db `"$Db`" --rule-cache-warm off --target-compiler $Tok > `"$out`" 2>&1" | Out-Null
  @{ Code = $LASTEXITCODE; Out = (Get-Content -LiteralPath $out -Raw) }
}

$bad = Join-Path $work 'bad.sqlite'
$r = Run '99' $bad
Check '1. --target-compiler 99: exit 2, refused, no database made' (($r.Code -eq 2) -and ($r.Out -match 'drag-lint: ') -and -not (Test-Path -LiteralPath $bad)) "exit=$($r.Code) out=$("$($r.Out)".Trim())"
$r = Run '12' (Join-Path $work 'ok12.sqlite')
Check '2. CONTROL: --target-compiler 12: exit 0' ($r.Code -eq 0) "exit=$($r.Code)"
$r = Run 'auto' (Join-Path $work 'auto.sqlite')
Check '3. CONTROL: --target-compiler auto on a .dpr: exit 0' ($r.Code -eq 0) "exit=$($r.Code)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
}
catch { Write-Host "[FAIL] harness: $_" -ForegroundColor Red; exit 1 }
finally {
  $w = Join-Path C:\TEMP "draglint_tcbad_$PID"
  if (Test-Path -LiteralPath $w) { try { [System.IO.Directory]::Delete($w, $true) } catch { } }
}
