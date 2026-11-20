<#
  run_param_prefix_list_autofix.ps1 -- owner ruling Q7 (2026-11-19, 1.52.2):
    * param-name-prefix is ON by default with an allowed-prefix LIST
      (naming.param_prefixes, default ["p","A"]), user-settable;
    * a param wearing the FIELD prefix (F) is always reported;
    * a Hungarian/Microsoft typed prefix (naming.hungarian_prefixes: str, b,
      n, ...) is ACCEPTED by default (naming.param_hungarian = "allowed");
      "off" stops accepting it;
    * the autofix renames the param in decl + impl + body, and DECLINES when
      the routine is an override / virtual / dynamic / abstract / message
      method, a method of an interface type, or a method of a class that
      implements an interface (the parameter list is a shared contract).

  CHECK cases (no --fix): default config, hungarian off, a user list.
  FIX cases (--fix --apply, default config): plain class method renamed at
  all three sites; F-param renamed to pName (F stripped); override, virtual,
  interface-type and interface-implementing methods left UNCHANGED.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-param-prefix-list-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$env:DRAGLINT_RENAME_TEST_UNGATED = '1'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
# Index ASrc into a fresh db; return the db path.
function New-Case([string]$Name, [string]$Body, [string]$Cfg) {
  $dir = Join-Path $WorkDir $Name
  $src = Join-Path $dir 'src'
  New-Item -ItemType Directory $src | Out-Null
  $file = Join-Path $src "$Name.pas"
  Write-Ascii $file ($Body -replace 'UNITNAME', $Name)
  $cfgPath = Join-Path $dir 'drag-lint-lint.json'
  [IO.File]::WriteAllText($cfgPath, $Cfg, [Text.Encoding]::ASCII)
  $db = Join-Path $dir 'p.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  return [pscustomobject]@{ File = $file; Db = $db; Cfg = $cfgPath }
}
# Names reported by param-name-prefix (parsed from the quoted name in the message).
function Get-Flagged($C) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $C.Db --config $C.Cfg --rule param-name-prefix --json 2>$null }
  $txt = ($raw | Where-Object { $_ -is [string] }) -join "`n"
  $i = $txt.IndexOf('['); if ($i -lt 0) { return @() }
  $arr = $txt.Substring($i) | ConvertFrom-Json | ForEach-Object { $_ }
  return ,@($arr | Where-Object { $_.rule -eq 'param-name-prefix' -or $_.rule_id -eq 'param-name-prefix' } |
            ForEach-Object { if ($_.message -match '"([^"]+)"') { $Matches[1] } })
}

$CheckBody = @'
unit UNITNAME;
interface
procedure Go(Value: Integer; AValue: Integer; pName: string; FName: string; strName: string; Sender: TObject; N: Integer);
implementation
procedure Go(Value: Integer; AValue: Integer; pName: string; FName: string; strName: string; Sender: TObject; N: Integer);
begin
end;
end.
'@

Write-Host 'CHECK 1: default config (no naming block)' -ForegroundColor Cyan
$k1 = New-Case 'chk1' $CheckBody '{}'
$f1 = Get-Flagged $k1
Check 'CHECK1: Value reported (no allowed prefix)'      ($f1 -contains 'Value')   ($f1 -join ',')
Check 'CHECK1: FName reported (field prefix F)'         ($f1 -contains 'FName')   ($f1 -join ',')
Check 'CHECK1: AValue accepted (A in default list)'     (-not ($f1 -contains 'AValue')) ($f1 -join ',')
Check 'CHECK1: pName accepted (p in default list)'      (-not ($f1 -contains 'pName'))  ($f1 -join ',')
Check 'CHECK1: strName accepted (Hungarian allowed)'    (-not ($f1 -contains 'strName')) ($f1 -join ',')
Check 'CHECK1: Sender exempt (event signature)'          (-not ($f1 -contains 'Sender')) ($f1 -join ',')
Check 'CHECK1: single-letter N exempt (owner card C)'    (-not ($f1 -contains 'N')) ($f1 -join ',')
Check 'CHECK1: both header sites reported for Value'    (@($f1 | Where-Object { $_ -eq 'Value' }).Count -eq 2) ($f1 -join ',')

Write-Host 'CHECK 2: param_hungarian = off' -ForegroundColor Cyan
$k2 = New-Case 'chk2' $CheckBody '{ "naming": { "param_hungarian": "off" } }'
$f2 = Get-Flagged $k2
Check 'CHECK2: strName reported when Hungarian is off'  ($f2 -contains 'strName') ($f2 -join ',')
Check 'CHECK2: AValue still accepted'                   (-not ($f2 -contains 'AValue')) ($f2 -join ',')

Write-Host 'CHECK 3: user list param_prefixes = ["p"]' -ForegroundColor Cyan
$k3 = New-Case 'chk3' $CheckBody '{ "naming": { "param_prefixes": ["p"] } }'
$f3 = Get-Flagged $k3
Check 'CHECK3: AValue reported (A not in user list)'    ($f3 -contains 'AValue') ($f3 -join ',')
Check 'CHECK3: pName accepted'                          (-not ($f3 -contains 'pName')) ($f3 -join ',')

Write-Host 'CHECK 4: user list includes F -- F still reported' -ForegroundColor Cyan
$k4 = New-Case 'chk4' $CheckBody '{ "naming": { "param_prefixes": ["p","A","F"] } }'
$f4 = Get-Flagged $k4
Check 'CHECK4: FName reported even when F is listed'    ($f4 -contains 'FName') ($f4 -join ',')

Write-Host 'CHECK 5: legacy param_prefix = "" disables the rule' -ForegroundColor Cyan
$k5 = New-Case 'chk5' $CheckBody '{ "naming": { "param_prefix": "" } }'
$f5 = Get-Flagged $k5
Check 'CHECK5: nothing reported'                        ($f5.Count -eq 0) ($f5 -join ',')

$FixBody = @'
unit UNITNAME;

interface

type
  IShape = interface
    procedure Draw(Size: Integer);
  end;

  TBase = class
  public
    procedure Plain(Count: Integer);
    procedure Hook(Depth: Integer); virtual;
    procedure Store(FName: string);
    procedure Single(N: Integer);
  end;

  TChild = class(TBase)
  public
    procedure Hook(Depth: Integer); override;
  end;

  TShape = class(TInterfacedObject, IShape)
  public
    procedure Draw(Size: Integer);
  end;

implementation

procedure TBase.Plain(Count: Integer);
begin
  Count:= Count + 1;
end;

procedure TBase.Hook(Depth: Integer);
begin
  Depth:= Depth + 1;
end;

procedure TBase.Store(FName: string);
begin
  FName:= FName + 'x';
end;

procedure TBase.Single(N: Integer);
begin
  N:= N + 4;
end;

procedure TChild.Hook(Depth: Integer);
begin
  Depth:= Depth + 2;
end;

procedure TShape.Draw(Size: Integer);
begin
  Size:= Size + 3;
end;

end.
'@

Write-Host 'FIX: default config, --fix --apply' -ForegroundColor Cyan
$x = New-Case 'fix1' $FixBody '{}'
$out = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $x.Db --config $x.Cfg --rule param-name-prefix --fix --apply 2>&1 | ForEach-Object { "$_" } }
$a = Get-Content -Raw $x.File
Check 'FIX: Plain decl renamed to pCount'       ($a -cmatch 'procedure Plain\(pCount: Integer\);') $a
Check 'FIX: Plain impl renamed to pCount'       ($a -cmatch 'procedure TBase\.Plain\(pCount: Integer\);') $a
Check 'FIX: Plain body renamed'                 ($a -cmatch 'pCount:= pCount \+ 1;') $a
Check 'FIX: FName param renamed to pName (decl)'  ($a -cmatch 'procedure Store\(pName: string\);') $a
Check 'FIX: FName param renamed to pName (impl+body)' ($a -cmatch 'TBase\.Store\(pName: string\);' -and $a -cmatch "pName:= pName \+ 'x';") $a
Check 'FIX: virtual Hook declined (decl)'       ($a -cmatch 'procedure Hook\(Depth: Integer\); virtual;') $a
Check 'FIX: override Hook declined (decl)'      ($a -cmatch 'procedure Hook\(Depth: Integer\); override;') $a
Check 'FIX: Hook impls + bodies unchanged'      ($a -cmatch 'TBase\.Hook\(Depth: Integer\);' -and $a -cmatch 'TChild\.Hook\(Depth: Integer\);' -and $a -cmatch 'Depth:= Depth \+ 2;') $a
Check 'FIX: interface method declined'          ($a -cmatch '    procedure Draw\(Size: Integer\);\r?\n  end;\r?\n\r?\n  TBase') $a
Check 'FIX: interface-implementing method declined' ($a -cmatch 'TShape\.Draw\(Size: Integer\);' -and $a -cmatch 'Size:= Size \+ 3;') $a
Check 'FIX: single-letter N not renamed (owner card C)' ($a -cmatch 'procedure Single\(N: Integer\);' -and $a -cmatch 'TBase\.Single\(N: Integer\);' -and $a -cmatch 'N:= N \+ 4;') $a
Check 'FIX: output names the declined override rename'     (($out -join "`n") -match 'param-name-prefix: declined .*Depth.* -- a virtual') ($out -join "`n")

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
