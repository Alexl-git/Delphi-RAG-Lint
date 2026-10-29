<#
  run_uba_method_homonym.ps1 -- a bare call to a METHOD of the enclosing class
  must not take its parameter modes from an unrelated FREE routine of the same
  name.

  THE DEFECT (gaps-wave INT sweep, 2026-10-27). In
  DRagLint.Diagnostics.BoundsNilChecks.pas, inside a TBnRun method:

      if not Lookup(Name, Info) then Exit;        { TBnRun.Lookup(...; out AInfo) }

  was reported "Local info is used before it is assigned" at ERROR severity on
  the line that FILLS it. The ParamMode oracle in FlowChecks resolves the callee
  by bare name and lets only free routines answer (methods are skipped so an
  unrelated class's `New` cannot answer for System.New -- see
  run_uba_param_modes.ps1, item 4). The project also has a FREE
  `Lookup(const AClassQName, AMember: string)` in another unit, so that routine
  answered "const" for position 1 and the out-argument became a READ.

  THE FIX: a method of the same name is not allowed to ANSWER, but it may VETO.
  When a same-named method disagrees with the free routines on the mode at that
  position, the call is ambiguous and the answer is pmUnknown (silence) -- the
  same "all matches must agree" rule the oracle already applies to overloads.

  Assertions: H1 is the fix. C1 (a free routine with no homonym method still
  makes a by-value bare arg a READ) and C2 (vacuity) are the controls -- without
  them, switching the oracle off would pass H1 too.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_uba_homonym_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

Write-Ascii (Join-Path $src 'uFree.pas') @'
unit uFree;
interface
function Probe(const AKey: string; AMember: Integer): Integer;
procedure ShowVal(const AKey: string; AValue: Integer);
implementation
function Probe(const AKey: string; AMember: Integer): Integer;
begin
  Result := Length(AKey) + AMember;
end;
procedure ShowVal(const AKey: string; AValue: Integer);
begin
  Writeln(AKey, AValue);
end;
end.
'@

Write-Ascii (Join-Path $src 'uRun.pas') @'
unit uRun;
interface
uses uFree;
type
  TRun = class
  public
    function Probe(const AName: string; out AInfo: Integer): Boolean;
    procedure Go;
    procedure Ctl;
  end;
implementation
function TRun.Probe(const AName: string; out AInfo: Integer): Boolean;
begin
  AInfo := Length(AName);
  Result := AInfo > 0;
end;
procedure TRun.Go;
var
  HInfo: Integer;
begin
  if Probe('x', HInfo) then
    Writeln(HInfo);
end;
procedure TRun.Ctl;
var
  CtlVal: Integer;
begin
  ShowVal('x', CtlVal);
end;
end.
'@

$db = Join-Path $WorkDir 'uba.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null

function Reported([string]$Text) {
  ,@([regex]::Matches($Text, 'used-before-assignment: Local "(\w+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

Push-Location C:\TEMP
try {
  $all = Reported ((& $exePath lint-all --db $db --rules-dir $rules --quiet 2>&1 | Out-String))
  Write-Host ("  lint-all reported: {0}" -f $(if($all){$all -join ','}else{'(none)'})) -ForegroundColor DarkGray
  Check 'H1 an out-arg to a homonym METHOD is NOT reported (the free routine must not answer)' `
        (-not ($all -contains 'hinfo')) ($all -join ',')
  Check 'C1 CONTROL a never-assigned local passed by value to a free routine IS reported' `
        ($all -contains 'ctlval') ($all -join ',')
  Check 'C2 VACUITY the run reported something at all' ([bool]$all) 'no findings -- the fixture is measuring nothing'
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d in @("C:\TEMP\draglint_uba_homonym_$PID")) { if (Test-Path -LiteralPath $d) { [System.IO.Directory]::Delete($d, $true) } }
}
