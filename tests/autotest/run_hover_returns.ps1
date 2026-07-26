[CmdletBinding()]
param([string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string] $WorkDir = "$env:TEMP\drag-lint-hover-returns")
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check([string]$Name,[bool]$Ok,[string]$Detail=''){
  $s = if($Ok){'PASS'}else{'FAIL'}; $c = if($Ok){'Green'}else{'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $s,$Name,$Detail) -ForegroundColor $c
  if(-not $Ok){$script:Failed=$true}
}
if(-not(Test-Path $Exe)){Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2}
if(Test-Path $WorkDir){Remove-Item -Recurse -Force $WorkDir}
New-Item -ItemType Directory $WorkDir | Out-Null
$src = "$WorkDir\src"; New-Item -ItemType Directory $src | Out-Null
@'
unit RetFixture;
interface
function IsPos(const S2: string): boolean;
function Authy(const AUser: string): Integer;
procedure DoStuff;
procedure ExitLoop(x: Integer);
function Looper(const AVal: Integer): Integer;
implementation
const ERROR_OK = 0; ERROR_NO_USER = 1; ERROR_BAD = 2;
function IsPos(const S2: string): boolean;
begin
  Result := S2.Length > 0;
end;
function Authy(const AUser: string): Integer;
begin
  Result := ERROR_OK;
  if AUser = '' then Result := ERROR_NO_USER;
  if AUser = 'x' then Result := ERROR_BAD;
  Result := ERROR_OK; // duplicate -- must dedup
end;
procedure DoStuff;
begin
  Beep;
end;
procedure ExitLoop(x: Integer);
begin
  Beep;
end;
function Looper(const AVal: Integer): Integer;
begin
  ExitLoop(AVal);
  Result := ERROR_OK;
end;
end.
'@ | Set-Content "$src\RetFixture.pas" -Encoding ascii

$db = "$WorkDir\ret.sqlite"
& $Exe index $src --db $db | Out-Null
Check 'db created' (Test-Path $db)

$boolJson = (& $Exe hover --qname RetFixture.IsPos --db $db --format json 2>&1) -join "`n"
Check 'bool: mined Result := S2.Length > 0' ($boolJson -match '"returns":\["S2\.Length > 0"\]') $boolJson
Check 'bool: return_type boolean' ($boolJson -match '(?i)"return_type":"boolean"') $boolJson
# FB3: the mined return carries its absolute source line (Result:= is on file line 12).
Check 'bool: returns_lines carries the Result:= source line (12)' ($boolJson -match '"returns_lines":\[12\]') $boolJson

$intJson = (& $Exe hover --qname RetFixture.Authy --db $db --format json 2>&1) -join "`n"
Check 'int: ERROR_OK present' ($intJson -match 'ERROR_OK') $intJson
Check 'int: ERROR_NO_USER present' ($intJson -match 'ERROR_NO_USER') $intJson
Check 'int: ERROR_BAD present' ($intJson -match 'ERROR_BAD') $intJson
# dedup: ERROR_OK appears once in the returns array
$okCount = ([regex]::Matches($intJson, 'ERROR_OK')).Count
Check 'int: ERROR_OK dedup (1 occurrence)' ($okCount -eq 1) "count=$okCount"
# FB3: the three distinct returns are mined at their FIRST-seen lines 16/17/18.
Check 'int: returns_lines are the first-seen source lines [16,17,18]' ($intJson -match '"returns_lines":\[16,17,18\]') $intJson

$procJson = (& $Exe hover --qname RetFixture.DoStuff --db $db --format json 2>&1) -join "`n"
Check 'proc: empty returns' ($procJson -match '"returns":\[\]') $procJson

# params structured
Check 'params carry name+type' ($boolJson -match '"name":"S2","type":"string"') $boolJson

# ExitRhs hardening: a call to an unrelated local proc ExitLoop(AVal) must NOT
# be mined as a value-form Exit() return -- word-boundary check after 'exit'.
$looperJson = (& $Exe hover --qname RetFixture.Looper --db $db --format json 2>&1) -join "`n"
Check 'ExitLoop(AVal) call not mined as a return' ($looperJson -notmatch '"returns":\["AVal"\]') $looperJson
Check 'Looper: Result := ERROR_OK is mined (not AVal)' ($looperJson -match '"returns":\["ERROR_OK"\]') $looperJson

# markdown format (the IDE popup) must ALSO surface the mined cases as a
# "Returns (observed):" line -- not just the JSON.
$boolMd = (& $Exe hover --qname RetFixture.IsPos --db $db --format md 2>&1) -join "`n"
Check 'md: Returns (observed) line shows the mined case' ($boolMd -match '\*\*Returns \(observed\):\*\*.*S2\.Length > 0') $boolMd
$procMd = (& $Exe hover --qname RetFixture.DoStuff --db $db --format md 2>&1) -join "`n"
Check 'md: procedure has NO Returns (observed) line' ($procMd -notmatch 'Returns \(observed\)') $procMd

Write-Host ''
if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red; exit 1}else{Write-Host 'PASS' -ForegroundColor Green; exit 0}
