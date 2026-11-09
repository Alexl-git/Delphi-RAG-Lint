<#
  run_grammar_shape_audit_148.ps1 -- lane 150-RG: the lint rules read the grammar v1.4.7 / v1.4.8 shapes.

  Constructs that used to be ERROR regions and now parse: a comment inside a generic's type
  arguments (`TList<Integer (* c *)>.Create`, v1.4.8), a record / class last field
  `array [..] of string` with no ';' before end (v1.4.8), `external` tails with no ';' (v1.4.7).
  Fixture: tests\fixtures\grammar-shape-audit\RG_148.pas. Audit table: lanes\150\RG\REPORT.md.

  Checks:
    E1  RG_148.pas has no syntax-error / parser-error finding;
    E2  POSITIVE CONTROL: unused-private-member
        fires on the last no-';' class field (FUnusedLast) AND on the field before it (FUnusedRec),
        proving the rules still reach a field the new grammar only just parsed.
  RED: on the 1.49.0-alpha base engine (v1.4.7 grammar DLL) E1 FAILS at lines 8,13,28-30; E2 PASSES there\r\n  (error recovery keeps the fields); GREEN on the v1.4.8 DLL.

  Usage: pwsh -File tests\autotest\run_grammar_shape_audit_148.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = 'src\cli\Win64\Debug\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$fxDir = Join-Path $Repo 'tests\fixtures\grammar-shape-audit'
$pas = Join-Path $fxDir 'RG_148.pas'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Get-RgLine([string]$File, [string]$Text) {
  $hit = Select-String -Path $File -SimpleMatch -Pattern $Text | Select-Object -First 1
  if (-not $hit) { throw "fixture $File lost the line '$Text'" }
  return $hit.LineNumber
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("rg148-" + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
try {
  # the index is built from a one-file copy of the fixture so the other fixtures do not join it
  $one = Join-Path $tmp 'src'
  [IO.Directory]::CreateDirectory($one) | Out-Null
  $pasCopy = Join-Path $one 'RG_148.pas'
  [IO.File]::Copy($pas, $pasCopy)
  $db = Join-Path $tmp 'rg148.sqlite'
  & $exePath index $one --db $db 2>&1 | Out-Null
  $txt = (& $exePath lint $pasCopy --db $db --enable 'unused-private-member,syntax-error,parser-error' --json 2>$null) -join "`n"
  $f = if ($txt.Trim() -eq '') { @() } else { @($txt | ConvertFrom-Json) }
  $errs = @($f | Where-Object { $_.rule -eq 'syntax-error' -or $_.rule -eq 'parser-error' })
  Check 'E1 RG_148.pas parses (no syntax-error / parser-error)' ($errs.Count -eq 0) ("errors at lines " + (($errs | ForEach-Object { $_.start_line }) -join ','))
  $lnA = Get-RgLine $pas 'FUnusedRec'
  $lnB = Get-RgLine $pas 'FUnusedLast'
  $hitA = @($f | Where-Object { $_.rule -eq 'unused-private-member' -and $_.start_line -eq $lnA }).Count -gt 0
  $hitB = @($f | Where-Object { $_.rule -eq 'unused-private-member' -and $_.start_line -eq $lnB }).Count -gt 0
  Check 'E2 unused-private-member on the field before the last (positive control)' $hitA
  Check 'E2 unused-private-member on the last no-semicolon `array of string` field' $hitB
} finally {
  [IO.Directory]::Delete($tmp, $true)
}
if ($script:Failed) { Write-Host 'run_grammar_shape_audit_148: FAIL'; exit 1 }
Write-Host 'run_grammar_shape_audit_148: PASS'