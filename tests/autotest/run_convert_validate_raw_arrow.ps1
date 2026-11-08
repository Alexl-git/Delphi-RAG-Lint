<#
  run_convert_validate_raw_arrow.ps1 -- E-VALIDATE-RAW-ARROW (wave 147, C1).

  THE DEFECT. A raw `A -> B` line (any non-# line containing ' -> ') is valid
  grammar, so convert-validate answered "OK" with no remark -- but convert-apply
  executes no raw line (rkPcre): the author got a book that validates and does
  nothing.

  THE CONTRACT: convert-validate prints `line N: warning: raw find/replace line
  is not executed by convert-apply ...` for each raw line, exit code unchanged
  (0, still "OK"). A clean book, a #note, and a comment print no such warning.
  CONTROL: the existing duplicate-From warning still prints beside it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_validate_raw_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory $WorkDir -Force | Out-Null
function P([string]$n) { return (Join-Path $WorkDir $n) }
function W([string]$n, [string]$t) { [IO.File]::WriteAllText((P $n), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
function Val([string]$Rules) {
  $o = (& $Exe convert-validate --rules (P $Rules) 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}

W 'raw.rules'   "#convert TOldBtn -> TNewBtn`nTFoo -> TBar`n#unuse LibOld`n"
W 'clean.rules' "#convert TOldBtn -> TNewBtn`n#unuse LibOld`n#note a -> b is only a note`n"
W 'two.rules'   "#convert TOldBtn -> TNewBtn`n#convert TOldBtn -> TNewBtn`nfoo(\d+) -> bar`n"

$r = Val 'raw.rules'
Check 'R1 a raw line warns at its own line number' ($r.Out -match '(?m)^line 2: warning: raw find/replace line is not executed by convert-apply') $r.Out
Check 'R2 exit code unchanged (0) and the book still reads OK' (($r.Code -eq 0) -and ($r.Out -match '(?m)^OK\s*$')) $r.Out
$c = Val 'clean.rules'
Check 'C1 CONTROL a clean book (a #note containing -> included) prints no raw warning' (($c.Code -eq 0) -and ($c.Out -notmatch 'raw find/replace')) $c.Out
$t = Val 'two.rules'
Check 'C2 CONTROL the duplicate-From warning still prints beside the raw one' (($t.Out -match 'duplicate From TOldBtn') -and ($t.Out -match '(?m)^line 3: warning: raw find/replace')) $t.Out
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}