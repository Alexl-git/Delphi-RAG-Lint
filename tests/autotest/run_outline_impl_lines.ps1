<#
  run_outline_impl_lines.ps1 -- outline and query name a method's
  IMPLEMENTATION span, not only its declaration line.

  THE DEFECT THIS PINS (stats\draglint-gaps.log 2026-10-29T14:27:54, backlog
  GAP-OUTLINE-IMPL). `outline --file Blueprint4.PDFImport.ViewModel.pas` gave
  each method's class-declaration line only; the agent fell back to
  Select-String for the body lines. The index HAD them all along --
  symbols.impl_start_line / impl_end_line since v9, and `query --json` already
  emits them -- but outline (text and json) and the query TEXT view never
  printed them. A reporting gap, not an extraction gap: no re-parse needed.

  THE FIX: outline --json gains end_line, impl_start_line, impl_end_line;
  outline text and query text append `[impl A-B]` to a row with a body.

  Positive controls: a field (no body) gets impl 0 and no `[impl` tag, and the
  declaration line still comes first in the row, so a consumer reading the
  existing columns is unaffected.
#>

[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_outline_impl_lines_$PID"
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

Write-Host 'run_outline_impl_lines -- outline/query show the implementation span' -ForegroundColor Cyan

if (-not (Test-Path $Exe)) {
  Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

$unit = Join-Path $WorkDir 'ImplLines.pas'
$src = @(
  'unit ImplLines;'                 # 1
  ''                                # 2
  'interface'                       # 3
  ''                                # 4
  'type'                            # 5
  '  TBox = class'                  # 6
  '    FCount: Integer;'            # 7
  '    procedure Bump;'             # 8
  '    function Total: Integer;'    # 9
  '  end;'                          # 10
  ''                                # 11
  'implementation'                  # 12
  ''                                # 13
  'procedure TBox.Bump;'            # 14
  'begin'                           # 15
  '  Inc(FCount);'                  # 16
  'end;'                            # 17
  ''                                # 18
  'function TBox.Total: Integer;'   # 19
  'begin'                           # 20
  '  Result := FCount;'             # 21
  '  Inc(Result);'                  # 22
  'end;'                            # 23
  ''                                # 24
  'end.'                            # 25
) -join "`r`n"
[System.IO.File]::WriteAllText($unit, $src + "`r`n", [System.Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'impllines.sqlite'
& $Exe index $unit --db $db *> $null
Check 'fixture indexed' (Test-Path $db) $db
if (-not (Test-Path $db)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

function Num($row, [string]$f) {
  if ($null -eq $row) { return '<not found>' }
  if ($null -eq $row.PSObject.Properties[$f]) { return '<absent>' }
  return [string]$row.$f
}

# ---- CASE A: outline --json carries the body span -- the defect -----------
Write-Host ''
Write-Host 'CASE A: outline --json impl_start_line / impl_end_line / end_line' -ForegroundColor Cyan
$oj = @()
try { $oj = @((& $Exe outline --file $unit --db $db --format json 2>$null | Out-String) | ConvertFrom-Json) } catch { }
$oB = @($oj | Where-Object { $_.qname -eq 'ImplLines.TBox.Bump' })[0]
$oT = @($oj | Where-Object { $_.qname -eq 'ImplLines.TBox.Total' })[0]
$oF = @($oj | Where-Object { $_.qname -eq 'ImplLines.TBox.FCount' })[0]
Check 'Bump line stays the declaration (8)' ((Num $oB 'line') -eq '8') "got: $(Num $oB 'line')"
Check 'Bump impl_start_line=14' ((Num $oB 'impl_start_line') -eq '14') "got: $(Num $oB 'impl_start_line')"
Check 'Bump impl_end_line=17'   ((Num $oB 'impl_end_line')   -eq '17') "got: $(Num $oB 'impl_end_line')"
Check 'Total impl_start_line=19' ((Num $oT 'impl_start_line') -eq '19') "got: $(Num $oT 'impl_start_line')"
Check 'Total impl_end_line=23'   ((Num $oT 'impl_end_line')   -eq '23') "got: $(Num $oT 'impl_end_line')"
Check 'class TBox end_line=10' ((Num (@($oj | Where-Object { $_.qname -eq 'ImplLines.TBox' })[0]) 'end_line') -eq '10') ''
Check 'positive control: field FCount impl_start_line=0' ((Num $oF 'impl_start_line') -eq '0') "got: $(Num $oF 'impl_start_line')"

# ---- CASE B: outline text appends [impl A-B] -------------------------------
Write-Host ''
Write-Host 'CASE B: outline text' -ForegroundColor Cyan
$ot = @(& $Exe outline --file $unit --db $db 2>$null)
$tB = @($ot | Where-Object { $_ -match '\sImplLines\.TBox\.Bump\s' })[0]
$tF = @($ot | Where-Object { $_ -match '\sImplLines\.TBox\.FCount\s' })[0]
Check 'outline text: Bump row reads "8  [impl 14-17]"' ($tB -match '\s8\s+\[impl 14-17\]') "row: $tB"
Check 'positive control: field row has no [impl tag' (($null -ne $tF) -and ($tF -notmatch '\[impl')) "row: $tF"

# ---- CASE C: query text appends [impl A-B] ---------------------------------
Write-Host ''
Write-Host 'CASE C: query text' -ForegroundColor Cyan
$qt = (& $Exe query --name Total --db $db 2>$null | Out-String)
Check 'query text: Total row carries [impl 19-23]' ($qt -match '\[impl 19-23\]') ($qt.Trim() -replace "`r?`n", ' | ')
$qf = (& $Exe query --name FCount --db $db 2>$null | Out-String)
Check 'positive control: query text for a field has no [impl tag' (($qf -match 'FCount') -and ($qf -notmatch '\[impl')) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\draglint_outline_impl_lines_$PID")) { if (Test-Path -LiteralPath $d23) { [System.IO.Directory]::Delete($d23, $true) } }
}
