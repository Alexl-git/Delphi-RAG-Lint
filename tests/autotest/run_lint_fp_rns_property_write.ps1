<#
  run_lint_fp_rns_property_write.ps1 -- referenced-never-set on a field written
  through a PROPERTY whose write specifier is the field (`write FX`).

  Callers assign `X.Prop := v` (often from another unit), so the field is
  written although no method of the class assigns it.

  Positive controls: a field behind a read-only property with no writes, and a
  field behind `write SetX` where SetX never assigns it, must still be reported.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fp-rns-propwrite-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory $WorkDir -Force | Out-Null

$src = @'
unit fprnsprop;

interface

type
  TBox = class
  private
    FMenus: Integer;
    FRoOnly: Integer;
    FLazy: Integer;
    FSet: Integer;
  public
    procedure SetSet(pV: Integer);
    procedure SetLazy(pV: Integer);
    function Sum: Integer;
    property Menus: Integer read FMenus write FMenus;
    property RoOnly: Integer read FRoOnly;
    property Lazy: Integer read FLazy write SetLazy;
    property Setd: Integer read FSet write SetSet;
  end;

implementation

procedure TBox.SetSet(pV: Integer);
begin
  FSet := pV;
end;

procedure TBox.SetLazy(pV: Integer);
begin
  if FLazy > pV then Exit;
end;

function TBox.Sum: Integer;
begin
  Result := FMenus + FRoOnly + FLazy + FSet;
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$unit = Join-Path $WorkDir 'fprnsprop.pas'
[System.IO.File]::WriteAllText($unit, $src, [System.Text.Encoding]::ASCII)

$out = (& $Exe lint $unit --rule referenced-never-set 2>$null | Out-String)

Write-Host 'False positives that must be GONE' -ForegroundColor Cyan
Check 'FMenus behind `write FMenus` is not reported' (-not ($out -match 'fprnsprop\.pas:8:')) ''
Check 'FSet behind `write SetSet` (setter assigns) is not reported' (-not ($out -match 'fprnsprop\.pas:11:')) ''
Write-Host 'True positives that must SURVIVE' -ForegroundColor Cyan
Check 'FRoOnly behind a read-only property is still reported' ($out -match 'fprnsprop\.pas:9:') 'else any property credits the field'
Check 'FLazy behind `write SetLazy` (setter never assigns) is still reported' ($out -match 'fprnsprop\.pas:10:') 'else any write clause credits the field'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
