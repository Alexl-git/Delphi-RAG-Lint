<#
  run_confusable_identifier.ps1 -- the confusable-identifier rule warns on two
  unit/class-level declarations whose names differ only by underscores.

  WHY (owner ask 2026-10-13): StationType_Operator beside StationTypeOperator
  is the same word to a reader -- Delphi already ignores case, so the
  underscore is all that tells them apart, and code meant for one compiles
  against the other. It is also what makes a const-casing rename unsafe.

  CONTROLS: a lone constant, the SAME identifier in another case is not this
  rule's business, and a routine's locals are their own scope.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== confusable-identifier ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("draglint-confus-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
  $u = Join-Path $work 'uConfus.pas'
  [IO.File]::WriteAllText($u, ((@'
unit uConfus;

interface

const
  StationType_Operator = 1;
  StationTypeOperator = 2;
  Lonely = 3;

var
  Max_Val: Integer;
  MaxVal: Integer;

implementation

procedure P;
var
  a_b, ab: Integer;
begin
end;

end.
'@ -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
  $raw = (& $Exe lint $u --rule confusable-identifier --json 2>$null | Out-String)
  $hits = @(try { $raw | ConvertFrom-Json } catch { })   # an engine without the rule prints an error, not JSON
  $lines = @($hits | ForEach-Object { $_.start_line })
  Check 'R1 the later of two consts differing only by "_" is warned (line 7), naming the first' `
    ((@($hits | Where-Object { $_.start_line -eq 7 -and $_.message -match 'StationType_Operator" \(line 6\)' }).Count -eq 1)) "lines: $($lines -join ',')"
  Check 'R2 ... the same for two unit-level vars (line 12)' ($lines -contains 12) ''
  Check 'R3 it is a WARNING' (@($hits | Where-Object { $_.severity -ne 'warning' }).Count -eq 0) ''
  Check 'C1 CONTROL: one warning per pair, nothing on the first or the lone const' `
    (($lines -notcontains 6) -and ($lines -notcontains 8) -and ($lines -notcontains 11) -and ($hits.Count -eq 2)) "count=$($hits.Count)"
  Check 'C2 CONTROL: a routine''s locals (a_b, ab) are their own scope -- not flagged' ($lines -notcontains 18) ''
  $cat = @((& $Exe rules --json 2>$null | ConvertFrom-Json).rules | Where-Object { $_.id -eq 'confusable-identifier' })
  Check 'K1 the rule is in the catalog, naming, warning, on by default' `
    (($cat.Count -eq 1) -and ($cat[0].category -eq 'naming') -and ($cat[0].default_severity -eq 'warning') -and $cat[0].default_enabled) ''
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
