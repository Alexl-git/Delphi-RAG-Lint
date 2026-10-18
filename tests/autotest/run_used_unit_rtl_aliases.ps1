[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uurtl-$PID"
)
# Bug V-D: used-unit-not-resolvable flagged unscoped names of RTL/VCL units
# (ActiveX, ComObj, CommCtrl, ...) on a Delphi 5 index with no library DB, and its
# message carried in-house advice (Orpheus/BDE). Positive control: NoSuchUnitXyz
# IS still flagged, so the rule is demonstrably on.
try {
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

Write-Ascii (Join-Path $work 'Legacy.pas') @'
unit Legacy;
interface
uses
  Windows, SysUtils, ActiveX, ComObj, CommCtrl, ShellAPI, WinSock, Ole2, OleAuto, Registry, NoSuchUnitXyz;
implementation
end.
'@

$db=Join-Path $WorkDir 'uurtl.sqlite'
$null = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$out = (& $Exe lint-project --db $db --rule used-unit-not-resolvable 2>&1) -join "`n"
Check 'flags NoSuchUnitXyz (positive control)' ($out -match 'NoSuchUnitXyz') "out=$out"
foreach($u in 'ActiveX','ComObj','CommCtrl','ShellAPI','WinSock','Ole2','OleAuto','Registry','Windows','SysUtils'){
  Check "does NOT flag $u" (-not ($out -match "Unit '$u'")) "out=$out"
}
Check 'message has no Orpheus' (-not ($out -match 'Orpheus')) "out=$out"
Check 'message has no BDE advice' (-not ($out -match 'FireDAC')) "out=$out"

if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red; exit 1}else{Write-Host 'PASS' -ForegroundColor Green; exit 0}
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-uurtl-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
