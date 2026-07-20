[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uunr"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ $s= if($ok){'PASS'}else{'FAIL'}; $c= if($ok){'Green'}else{'Red'};
  Write-Host ("  [{0}] {1} {2}" -f $s,$n,$d) -ForegroundColor $c; if(-not $ok){$script:Failed=$true} }
function Write-Ascii([string]$Path,[string]$Body){
  $norm = $Body -replace "`r`n","`n" -replace "`n","`r`n"
  [IO.File]::WriteAllText($Path,$norm,[Text.Encoding]::ASCII) }

if(-not(Test-Path $Exe)){Write-Host "FATAL: no exe $Exe" -ForegroundColor Red; exit 2}
$Exe=(Resolve-Path $Exe).Path
if(Test-Path $WorkDir){Remove-Item -Recurse -Force $WorkDir}
New-Item -ItemType Directory $WorkDir | Out-Null
$work=Join-Path $WorkDir 'fixture'; New-Item -ItemType Directory $work | Out-Null

# A sibling project unit that IS indexed (so it resolves as a project member).
Write-Ascii (Join-Path $work 'TakeJob.pas') @'
unit TakeJob;
interface
type TJob = class end;
implementation
end.
'@

# The unit under test: uses a resolvable sibling + an unresolvable Orpheus unit.
Write-Ascii (Join-Path $work 'VarInsp.pas') @'
unit VarInsp;
interface
uses
  TakeJob,
  ovctcmmn,
  System.SysUtils;
type TDlg = class end;
implementation
end.
'@

$db=Join-Path $WorkDir 'uunr.sqlite'
$idx = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# Run the rule (no library DB passed -> ovctcmmn cannot resolve; SysUtils via RTL net).
$out = (& $Exe lint-project --db $db --rule used-unit-not-resolvable 2>&1) -join "`n"
Check 'flags ovctcmmn' ($out -match 'ovctcmmn')  "out=$out"
Check 'does NOT flag TakeJob (project member)'   (-not ($out -match '\bTakeJob\b.*used-unit-not-resolvable')) "out=$out"
Check 'does NOT flag System.SysUtils (RTL net)'  (-not ($out -match 'SysUtils')) "out=$out"
Check 'finding is on VarInsp.pas (uses file)'    ($out -match 'VarInsp\.pas:\d+:\d+') "out=$out"
# The ovctcmmn uses token is on line 5 of VarInsp.pas.
Check 'ovctcmmn finding line is 5'               ($out -match 'VarInsp\.pas:5:') "out=$out"

if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red; exit 1}else{Write-Host 'PASS' -ForegroundColor Green; exit 0}
