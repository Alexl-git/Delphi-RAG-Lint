<#
  run_v1523_FIXER2B.ps1 -- local-field-prefix --fix stripped the field prefix blindly (SLZ-S02 Convert.pas
  E2029, SLZ-S07 SharedFacts FIn; C:\TEMP\claude\lanes\v1523\SLZ\RULE-FP.tsv):
    - FIn -> In, a reserved word: the unit no longer compiles (E2029);
    - FTotal -> Total where the enclosing class has a member Total (own or inherited), and
      FValue -> Value inside a nested routine whose outer routine has a local / parameter Value:
      the new local HIDES that name, so a later `Total` / `Value` in the body silently rebinds.
  Each must be DECLINED (left as written, with a reason line); a rename with no clash (FTemp -> Temp)
  must still happen; a sibling-parameter clash (FRes vs param Res) stays declined. Every fixed unit
  must COMPILE (dcc32), so a decline that leaves broken code, or a rename that breaks it, fails.

  -Exe defaults to the worktree build; pass the e7a4443df engine to see RED.
#>
param(
  [string]$Exe = ''
)
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Exe) { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FAIL: engine not found: $Exe"; exit 2 }
$Dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc32.exe'
$HaveDcc = Test-Path -LiteralPath $Dcc
$Work = Join-Path ([IO.Path]::GetTempPath()) ('fixer2b-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
$Enc = [Text.Encoding]::GetEncoding(1252)
$script:Pass = 0; $script:Fail = 0

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "PASS  $Name" }
  else {
    $script:Fail++
    if ($Detail.Length -gt 600) { $Detail = $Detail.Substring(0, 600) + ' ...' }
    Write-Host "FAIL  $Name  $Detail"
  }
}
function Put([string]$Name, [string]$Text) {
  $p = Join-Path $Work $Name
  [IO.File]::WriteAllText($p, ($Text -replace "`r?`n", "`r`n"), $Enc)
  return $p
}
function Get-Text([string]$Path) { return [IO.File]::ReadAllText($Path, $Enc) }
function Invoke-Engine([string[]]$Arguments) {
  return (& { $ErrorActionPreference = 'Continue'; & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } } | Out-String)
}
# compile the unit through a one-line program; returns the dcc error lines ('' = compiled or no dcc32)
function Compile([string]$UnitPath) {
  if (-not $HaveDcc) { return '' }
  $u = [IO.Path]::GetFileNameWithoutExtension($UnitPath)
  $dir = Split-Path -Parent $UnitPath
  $dpr = Join-Path $dir "P_$u.dpr"
  [IO.File]::WriteAllText($dpr, "program P_$u;`r`n{`$APPTYPE CONSOLE}`r`nuses $u in '$u.pas';`r`nbegin end.`r`n", $Enc)
  $out = & { $ErrorActionPreference = 'Continue'; & $Dcc -Q -B $dpr "-E$dir" "-N$dir" 2>&1 | ForEach-Object { "$_" } }
  return (($out | Where-Object { $_ -match '(Error|Fatal)' }) -join ' | ')
}

try {
  if (-not $HaveDcc) { Write-Host "NOTE: dcc32 not found, the compile checks pass vacuously: $Dcc" }

  $src = @'
unit FxLfp;

interface

type
  TBase = class
  private
    FSize: Integer;
  public
    property Size: Integer read FSize write FSize;
  end;

  TBox = class(TBase)
  private
    FCount: Integer;
  public
    function Total: Integer;
    procedure Run(const AText: string; Res: Integer);
    procedure Grow;
  end;

function Outer(Limit: Integer): Integer;
function Plain(const S: string): Integer;

implementation

function TBox.Total: Integer;
begin
  Result := FCount;
end;

procedure TBox.Run(const AText: string; Res: Integer);
var
  FIn: Integer;
  FRes: Integer;
  FTotal: Integer;
begin
  FIn := Length(AText);
  FRes := Res + FIn;
  FTotal := FRes + 1;
  FCount := FTotal;
end;

procedure TBox.Grow;
var
  FSize: Integer;
begin
  FSize := FCount + 1;
  FCount := FSize;
end;

function Outer(Limit: Integer): Integer;
var
  Value: Integer;

  function Inner: Integer;
  var
    FValue: Integer;
    FLimit: Integer;
  begin
    FValue := 1;
    FLimit := 2;
    Result := FValue + FLimit;
  end;

begin
  Value := Limit;
  Result := Inner;
end;

function Plain(const S: string): Integer;
var
  FTemp: Integer;
begin
  FTemp := Length(S);
  Result := FTemp * 2;
end;

end.
'@
  $p = Put 'FxLfp.pas' $src
  Check 'fixture compiles before the fix' ((Compile $p) -eq '')
  $db = Join-Path $Work 'lfp.sqlite'
  $oi = Invoke-Engine @('index', $Work, '--db', $db)
  $ol = Invoke-Engine @('lint', '--in', $p, '--db', $db, '--rule', 'local-field-prefix')
  foreach ($n in @('FIn', 'FRes', 'FTotal', 'FSize', 'FValue', 'FLimit', 'FTemp')) {
    Check "positive control: local-field-prefix reports $n" ($ol -match ('\b' + $n + '\b')) $ol
  }
  $of = Invoke-Engine @('lint', '--in', $p, '--db', $db, '--rule', 'local-field-prefix', '--fix', '--apply', '--no-backup', '--no-compile-gate')
  $t = Get-Text $p
  $err = Compile $p
  Check 'the fixed unit compiles' ($err -eq '') $err

  # reserved word
  Check 'FIn -> In (reserved word) is declined: FIn stays' ($t.Contains('  FIn := Length(AText);') -and $t.Contains('  FIn: Integer;')) $t
  Check 'FIn decline names the reason' ($of -match 'local-field-prefix: declined .*"FIn" -> "In" -- .*reserved') $of
  # sibling parameter (already declined before this lane)
  Check 'FRes -> Res (a parameter of the same routine) stays declined' ($t.Contains('  FRes := Res + ') -and $t.Contains('  FRes: Integer;')) $t
  Check 'FRes decline names the reason' ($of -match 'local-field-prefix: declined .*"FRes" -> "Res" -- ') $of
  # own class member: the body never says Total, so the capture proof passes -- the new local still HIDES TBox.Total
  Check 'FTotal -> Total (a method of the enclosing class) is declined' ($t.Contains('  FTotal := FRes + 1;')) $t
  Check 'FTotal decline names the class member' ($of -match 'local-field-prefix: declined .*"FTotal" -> "Total" -- .*TBox') $of
  # inherited class member
  Check 'FSize -> Size (a property inherited from TBase) is declined' ($t.Contains('  FSize := FCount + 1;')) $t
  Check 'FSize decline names the inherited member' ($of -match 'local-field-prefix: declined .*"FSize" -> "Size" -- .*TBase') $of
  # outer routine's local / parameter
  Check 'FValue -> Value (a local of the outer routine) is declined' ($t.Contains('    FValue := 1;')) $t
  Check 'FValue decline names the outer routine' ($of -match 'local-field-prefix: declined .*"FValue" -> "Value" -- .*Outer') $of
  Check 'FLimit -> Limit (a parameter of the outer routine) is declined' ($t.Contains('    FLimit := 2;')) $t
  Check 'FLimit decline names the outer routine' ($of -match 'local-field-prefix: declined .*"FLimit" -> "Limit" -- .*Outer') $of
  # positive control: a clash-free rename still happens
  Check 'positive control: FTemp -> Temp is renamed (decl + both uses)' (
    $t.Contains('  Temp: Integer;') -and $t.Contains('  Temp := Length(S);') -and $t.Contains('  Result := Temp * 2;') -and -not $t.Contains('FTemp')) $t
}
finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { Write-Host "NOTE: could not remove $Work" }
}
Write-Host ''
Write-Host "run_v1523_FIXER2B: $($script:Pass) pass, $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
