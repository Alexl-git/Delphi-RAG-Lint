<#
  run_const_casing_word_fix.ps1 -- the const-casing fix renames WORD-AWARE and
  asks the index before it renames.

  THE DEFECT THIS PINS (owner report 2026-10-13, ORM3): most const-casing
  findings looked like `StationType_Operator`. The fix only re-cased the first
  letter, which leaves that name unchanged, so the engine answered "no fixable
  findings" for nearly all of them.

  THE FIX (DRagLint.Refactor.NamingFix.ConstCaseCandidates): words split at '_'
  and at a lower-to-upper step, one candidate per configured const_case style
  (default PascalCase, then UPPER_CASE); the FIRST candidate the index says is
  free wins (TRenameRefactoring.ConflictReason), and with none free the
  constant is left alone.

  Cases (default const_case = PascalCase, UPPER_CASE):
    StationType_Operator -> StationTypeOperator  (declaration AND use)
    wrStr                -> WrStr
    Station_Name         -> STATION_NAME, because StationName ALREADY EXISTS --
                            the index check; StationName itself is untouched

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
Write-Host '== const-casing: word-aware rename, index-checked ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("draglint-ccword-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
  $u = Join-Path $work 'uCcWord.pas'
  [IO.File]::WriteAllText($u, ((@'
unit uCcWord;

interface

const
  StationType_Operator = 1;
  wrStr = 'x';
  Station_Name = 2;
  StationName = 3;

function Total: Integer;
function Text: string;

implementation

function Total: Integer;
begin
  Result:= StationType_Operator + Station_Name + StationName;
end;

function Text: string;
begin
  Result:= wrStr;
end;

end.
'@ -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
  $dpr = Join-Path $work 'CcWord.dpr'
  [IO.File]::WriteAllText($dpr, "program CcWord;`r`nuses`r`n  uCcWord in 'uCcWord.pas';`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)
  $db = Join-Path $work 'cc.sqlite'

  function FixOne([int]$Line) {
    & $Exe index --project $dpr --db $db 2>&1 | Out-Null
    (& $Exe lint --file $u --db $db --fix --fix-line $Line --fix-rule const-casing --apply 2>&1 | Out-String)
  }

  & $Exe index --project $dpr --db $db 2>&1 | Out-Null
  $found = @(& $Exe lint $u --db $db --rule const-casing --json 2>$null | ConvertFrom-Json | ForEach-Object { $_.start_line })
  Check 'P1 premise: the three bad names are findings (lines 6, 7, 8), StationName is not' `
    ((($found -contains 6) -and ($found -contains 7) -and ($found -contains 8)) -and ($found -notcontains 9)) "lines: $($found -join ',')"

  $o1 = FixOne 6
  $t = [IO.File]::ReadAllText($u)
  Check 'W1 StationType_Operator -> StationTypeOperator, declaration AND use' `
    (($t -cmatch '(?m)^\s*StationTypeOperator = 1;') -and ($t -cmatch 'Result:= StationTypeOperator \+') -and ($t -cnotmatch 'StationType_Operator')) `
    (($o1 -split "`r?`n" | Where-Object { $_ -match 'autofix' }) -join ' | ')

  $o2 = FixOne 7
  $t = [IO.File]::ReadAllText($u)
  Check 'W2 wrStr -> WrStr' (($t -cmatch '(?m)^\s*WrStr = ') -and ($t -cmatch 'Result:= WrStr;')) ''

  $o3 = FixOne 8
  $t = [IO.File]::ReadAllText($u)
  Check 'C1 Station_Name -> STATION_NAME: the PascalCase name StationName ALREADY EXISTS (index check)' `
    (($t -cmatch '(?m)^\s*STATION_NAME = 2;') -and ($t -cmatch '\+ STATION_NAME \+')) (($o3 -split "`r?`n" | Where-Object { $_ -match 'autofix' }) -join ' | ')
  Check 'C2 ... and the existing StationName is untouched' `
    (($t -cmatch '(?m)^\s*StationName = 3;') -and ($t -cmatch '\+ StationName;')) ''
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
