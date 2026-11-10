<#
  run_grammar_shape_audit_149.ps1 -- lane 150-RG2: the lint rules read the grammar v1.4.9 shape.

  Construct: Automation named arguments `Foo(Name := Value)`, new node exprArgNamed(name: identifier,
  kAssign, value: _expr) inside exprArgs (JvgExportComponents, JvDBGridExport).
  Fixtures: tests\fixtures\grammar-shape-audit\RG_149.pas (parse), RG_149b.pas (label vs. read).

  Checks:
    N1  RG_149.pas has no syntax-error / parser-error finding (needs the v1.4.9 DLL beside the exe);
    N2  used-before-assignment does NOT fire on the LABEL of a named argument whose name equals an
        unassigned local (`pSheet.AutoFormat(FileName := 'x', Format := pFormat)` with locals FileName,
        Format) -- the label is not a read of the local (Flow.Lattices CollectReadsAndCallDefs);
    N3  POSITIVE CONTROL: used-before-assignment still fires on a REAL read of the unassigned local
        (`Result := Count`), so N2 cannot pass with the rule off;
    N4  the index records a read ref for the VALUE of a named argument (Format := lTmp) and none for
        a LABEL (Format, FileName) (Parser.Delphi13 exprArgs branch; EXTRACTOR change, needs the wave bump).
  RED: on the engine built before the RG2 change (v1.4.9 DLL) N2 FAILS (lines 20 and 29) and N4 FAILS;
  N1 FAILS on any v1.4.8 DLL. GREEN with the RG2 change + v1.4.9 DLL.

  Usage: pwsh -File tests\autotest\run_grammar_shape_audit_149.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = 'src\cli\Win64\Debug\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$fxDir = Join-Path $Repo 'tests\fixtures\grammar-shape-audit'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Get-RgLine([string]$File, [string]$Text) {
  $hit = Select-String -Path $File -SimpleMatch -Pattern $Text | Select-Object -First 1
  if (-not $hit) { throw "fixture $File lost the line '$Text'" }
  return $hit.LineNumber
}
function Get-Findings([string]$PasCopy, [string]$Db, [string]$Rules) {
  $txt = (& $exePath lint $PasCopy --db $Db --library-db none --enable $Rules --json 2>$null) -join "`n"
  if ($txt.Trim() -eq '') { return @() }
  return @($txt | ConvertFrom-Json)
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("rg149-" + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
try {
  foreach ($unit in 'RG_149', 'RG_149b') {
    $one = Join-Path $tmp $unit
    [IO.Directory]::CreateDirectory($one) | Out-Null
    [IO.File]::Copy((Join-Path $fxDir "$unit.pas"), (Join-Path $one "$unit.pas"))
    & $exePath index $one --db (Join-Path $one 'db.sqlite') 2>&1 | Out-Null
  }
  # N1
  $a = Join-Path $tmp 'RG_149'
  $errs = @(Get-Findings (Join-Path $a 'RG_149.pas') (Join-Path $a 'db.sqlite') 'syntax-error,parser-error' |
    Where-Object { $_.rule -eq 'syntax-error' -or $_.rule -eq 'parser-error' })
  Check 'N1 RG_149.pas (named arguments) parses' ($errs.Count -eq 0) ("errors at lines " + (($errs | ForEach-Object { $_.start_line }) -join ','))
  # N2 / N3
  $b = Join-Path $tmp 'RG_149b'
  $pasB = Join-Path $fxDir 'RG_149b.pas'
  $fb = @(Get-Findings (Join-Path $b 'RG_149b.pas') (Join-Path $b 'db.sqlite') 'used-before-assignment')
  $ubaLines = @($fb | Where-Object { $_.rule -eq 'used-before-assignment' } | ForEach-Object { [int]$_.start_line })
  $lnLabel1 = Get-RgLine $pasB 'pSheet.AutoFormat(FileName'
  $lnLabel2 = Get-RgLine $pasB 'pSheet.Do(Count := 3)'
  $lnRead = Get-RgLine $pasB 'Result := Count'
  Check 'N2 used-before-assignment ignores named-argument labels' (($ubaLines -notcontains $lnLabel1) -and ($ubaLines -notcontains $lnLabel2)) ("fires at lines " + ($ubaLines -join ','))
  Check 'N3 used-before-assignment still fires on a real read (positive control)' ($ubaLines -contains $lnRead)
  # N4
  $q = "select kind, name_text, start_line from refs where start_line in ($(Get-RgLine $pasB 'pSheet.Other(Format'), $lnLabel1)) and kind = 'read'"
  $rows = (& $exePath sql --db (Join-Path $b 'db.sqlite') --query $q --json 2>$null) -join "`n"
  $names = @(($rows | ConvertFrom-Json).rows | ForEach-Object { $_[1] })
  Check 'N4 named-argument VALUE lTmp is a read ref' ($names -contains 'lTmp') ("read refs: " + ($names -join ','))
  Check 'N4 named-argument LABEL Format/FileName is no ref' (($names -notcontains 'Format') -and ($names -notcontains 'FileName'))
} finally {
  [IO.Directory]::Delete($tmp, $true)
}
if ($script:Failed) { Write-Host 'run_grammar_shape_audit_149: FAIL'; exit 1 }
Write-Host 'run_grammar_shape_audit_149: PASS'
