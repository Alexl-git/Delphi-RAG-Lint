<#
  run_v154_ormrules.ps1 -- v154 ORM-RULES (owner ruling 2026-11-23, INBOX-orm3-server-153.md item 1):
  param-name-prefix exempts the parameter names Value, Source and Owner (whole name,
  case-insensitive) in setter, constructor, plain routine and const/var parameters.
  The list is the rule parameter naming.param_exempt (default Value, Source, Owner);
  an overridden list REPLACES the default. Positive controls: NewValue, SourceFile,
  AOwner (accepted by prefix A, not by exemption), Foo still behave as before.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v154-ormrules-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
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

function New-Case([string]$Name, [string]$Body, [string]$Cfg) {
  $dir = Join-Path $WorkDir $Name
  $src = Join-Path $dir 'src'
  New-Item -ItemType Directory $src | Out-Null
  $file = Join-Path $src "$Name.pas"
  $norm = ($Body -replace 'UNITNAME', $Name) -replace "`r`n", "`n" -replace "`n", "`r`n"
  [IO.File]::WriteAllText($file, $norm, [Text.Encoding]::ASCII)
  $cfgPath = Join-Path $dir 'drag-lint-lint.json'
  [IO.File]::WriteAllText($cfgPath, $Cfg, [Text.Encoding]::ASCII)
  $db = Join-Path $dir 'p.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  return [pscustomobject]@{ File = $file; Db = $db; Cfg = $cfgPath }
}
function Get-Flagged($C) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $C.Db --config $C.Cfg --rule param-name-prefix --json 2>$null }
  $txt = ($raw | Where-Object { $_ -is [string] }) -join "`n"
  $i = $txt.IndexOf('['); if ($i -lt 0) { return @() }
  $arr = $txt.Substring($i) | ConvertFrom-Json | ForEach-Object { $_ }
  return ,@($arr | Where-Object { $_.rule -eq 'param-name-prefix' -or $_.rule_id -eq 'param-name-prefix' } |
            ForEach-Object { if ($_.message -match '"([^"]+)"') { $Matches[1] } })
}

$Body = @'
unit UNITNAME;
interface
type
  TThing = class
  public
    constructor Create(Owner: TObject; Source: string);
    procedure SetName(Value: string);
    procedure Keep(const Source: string; var Owner: TObject; out Value: Integer);
    procedure Lower(value: Integer; OWNER: TObject);
    procedure Controls(NewValue: Integer; SourceFile: string; AOwner: TObject; Foo: Integer);
  end;
procedure Plain(Value: Integer; Source: string; Owner: TObject; Foo: Integer);
implementation
constructor TThing.Create(Owner: TObject; Source: string);
begin
end;
procedure TThing.SetName(Value: string);
begin
end;
procedure TThing.Keep(const Source: string; var Owner: TObject; out Value: Integer);
begin
end;
procedure TThing.Lower(value: Integer; OWNER: TObject);
begin
end;
procedure TThing.Controls(NewValue: Integer; SourceFile: string; AOwner: TObject; Foo: Integer);
begin
end;
procedure Plain(Value: Integer; Source: string; Owner: TObject; Foo: Integer);
begin
end;
end.
'@

Write-Host 'CASE 1: default config' -ForegroundColor Cyan
$f1 = Get-Flagged (New-Case 'def' $Body '{}')
$j1 = $f1 -join ','
foreach ($n in 'Value','Source','Owner','value','OWNER') {
  Check "default: $n exempt (setter/ctor/plain/const/var/out/case)" (-not ($f1 -contains $n)) $j1
}
Check 'default: NewValue still reported'  ($f1 -contains 'NewValue')  $j1
Check 'default: SourceFile still reported' ($f1 -contains 'SourceFile') $j1
Check 'default: Foo still reported (decl + impl of Controls, Plain)' (@($f1 | Where-Object { $_ -eq 'Foo' }).Count -ge 3) $j1
Check 'default: AOwner accepted by prefix A' (-not ($f1 -contains 'AOwner')) $j1

Write-Host 'CASE 2: param_exempt = ["Foo"] replaces the default' -ForegroundColor Cyan
$f2 = Get-Flagged (New-Case 'ovr' $Body '{ "naming": { "param_exempt": ["Foo"] } }')
$j2 = $f2 -join ','
Check 'override: Foo exempt'               (-not ($f2 -contains 'Foo')) $j2
Check 'override: Value reported again'     ($f2 -contains 'Value') $j2
Check 'override: Source reported again'    ($f2 -contains 'Source') $j2
Check 'override: Owner reported again'     ($f2 -contains 'Owner') $j2

Write-Host 'CASE 3: param_exempt = [] exempts nothing' -ForegroundColor Cyan
$f3 = Get-Flagged (New-Case 'emp' $Body '{ "naming": { "param_exempt": [] } }')
Check 'empty list: Value reported' ($f3 -contains 'Value') ($f3 -join ',')
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
