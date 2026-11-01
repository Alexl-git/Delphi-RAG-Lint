<#
  run_unused_unit_inline_methods.ps1 -- unused-unit-in-uses must keep a unit
  whose INLINE routine this file calls, even when the file names nothing the
  unit exports.

  THE DEFECT THIS PINS (docs\INBOX-unused-unit-inline-record-methods.md,
  backlog UNUSEDUNIT-INLINE, OCRPDF 2026-10-29):

      uses ImgU, GridU;               // GridU declares TByteGrid, At is inline
      Result:= I.Gray.At(1);          // Gray: TByteGrid, a field of ImgU's record

  The file names no GridU export -- the type arrives through ImgU's record
  field -- so the rule called GridU a dead import. Removing it makes dcc emit
  H2443 ("inline function has not been expanded because unit GridU is not
  specified in USES list"): the inline expansion needs the unit.

  NOT AN EXTRACTOR GAP. symbols.directives has carried `inline` since v22, and
  the call ref already resolves to GridU.TByteGrid.At. The rule simply never
  looked at resolved call targets.

  Positive control: UsePlain calls the NON-inline TByteGrid.Plain the same
  way. dcc needs no unit for that, so GridU there IS a dead import and must
  STILL be flagged -- a fix that silenced every member call would pass case A.

  Fixture after agent-lintfp's fx2 (lane lintfp RED).
#>

[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_unused_unit_inline_$PID"
)
try {

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

Write-Host 'run_unused_unit_inline_methods -- an inline callee keeps its unit' -ForegroundColor Cyan

if (-not (Test-Path $Exe)) {
  Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function WriteUnit([string]$name, [string[]]$lines) {
  [System.IO.File]::WriteAllText((Join-Path $WorkDir "$name.pas"), (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
}

WriteUnit 'GridU' @(
  'unit GridU;', '', 'interface', '', 'type',
  '  TByteGrid = record',
  '    Data: TArray<Byte>;',
  '    function At(X: Integer): Byte; inline;',
  '    function Plain(X: Integer): Byte;',
  '  end;', '', 'implementation', '',
  'function TByteGrid.At(X: Integer): Byte;', 'begin', '  Result:= Data[X];', 'end;', '',
  'function TByteGrid.Plain(X: Integer): Byte;', 'begin', '  Result:= Data[X];', 'end;', '',
  'end.')
WriteUnit 'ImgU' @(
  'unit ImgU;', '', 'interface', '', 'uses GridU;', '', 'type',
  '  TPageImage = record', '    Gray: TByteGrid;', '  end;', '', 'implementation', '', 'end.')
WriteUnit 'UseInline' @(
  'unit UseInline;', '', 'interface', '', 'uses ImgU, GridU;', '',
  'function Px(const I: TPageImage): Byte;', '', 'implementation', '',
  'function Px(const I: TPageImage): Byte;', 'begin', '  Result:= I.Gray.At(1);', 'end;', '', 'end.')
WriteUnit 'UsePlain' @(
  'unit UsePlain;', '', 'interface', '', 'uses ImgU, GridU;', '',
  'function Px2(const I: TPageImage): Byte;', '', 'implementation', '',
  'function Px2(const I: TPageImage): Byte;', 'begin', '  Result:= I.Gray.Plain(1);', 'end;', '', 'end.')

$db = Join-Path $WorkDir 'inl.sqlite'
& $Exe index $WorkDir --db $db *> $null
Check 'fixture indexed' (Test-Path $db) $db
if (-not (Test-Path $db)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

# Premise: the index already knows At is inline and the call resolves to it.
$dir = (& $Exe sql --query "select directives from symbols where qualified_name='GridU.TByteGrid.At'" --db $db --json 2>$null | Out-String)
Check 'premise: TByteGrid.At carries directives=inline' ($dir -match '"inline"') ''

$out = @(& $Exe lint-all --db $db --rule unused-unit-in-uses 2>$null)
$inl = @($out | Where-Object { $_ -match 'UseInline\.pas:' -and $_ -match "unused-unit-in-uses: Unit 'GridU'" })
$pln = @($out | Where-Object { $_ -match 'UsePlain\.pas:'  -and $_ -match "unused-unit-in-uses: Unit 'GridU'" })

Write-Host ''
Write-Host 'CASE A: GridU kept alive by a call to its inline TByteGrid.At' -ForegroundColor Cyan
Check 'UseInline: GridU is NOT reported' ($inl.Count -eq 0) ($inl -join ' | ')

Write-Host ''
Write-Host 'CASE B: positive control -- a non-inline member call keeps nothing' -ForegroundColor Cyan
Check 'UsePlain: GridU IS still reported' ($pln.Count -eq 1) "rows=$($pln.Count)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\draglint_unused_unit_inline_$PID")) { if (Test-Path -LiteralPath $d23) { [System.IO.Directory]::Delete($d23, $true) } }
}
