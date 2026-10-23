<#
  run_lint_fp_active_field.ps1 -- N-13 (INBOX-lint-fp-active-field-and-sized-plus-one, item 1).

  dataset-open-without-close fired on `lTop.Active := True` where lTop is a
  local of a class declared IN THE SAME FILE with a plain field `Active:
  Boolean` -- no dataset anywhere. A class that declares its own Active FIELD
  is not a TDataSet (TDataSet.Active is a property), so writing it opens no
  cursor.

  Positive control: a local typed TFDQuery (not declared here) set Active :=
  True with no Close in a finally must still be reported.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fp-active-$PID"
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
unit fpactive;

interface

type
  TCondFrame = class
  public
    Active: Boolean;
    Decided: Boolean;
  end;

procedure Mark(pTop: TCondFrame);
procedure Load;

implementation

uses FireDAC.Comp.Client;

procedure Mark(pTop: TCondFrame);
var
  lTop: TCondFrame;
begin
  lTop := pTop;
  lTop.Active := True;
end;

procedure Load;
var
  lQry: TFDQuery;
begin
  lQry := TFDQuery.Create(nil);
  lQry.Active := True;
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$unit = Join-Path $WorkDir 'fpactive.pas'
[System.IO.File]::WriteAllText($unit, $src, [System.Text.Encoding]::ASCII)

$out = (& $Exe lint $unit --rule dataset-open-without-close 2>$null | Out-String)

Write-Host 'False positive that must be GONE' -ForegroundColor Cyan
Check 'a plain Active field on a class declared in the file is not a dataset' `
  (-not ($out -match 'Dataset ltop is opened'))
Write-Host 'True positive that must SURVIVE' -ForegroundColor Cyan
Check 'a TFDQuery local set Active := True without Close is still reported' `
  ($out -match 'Dataset lqry is opened') 'else the fix just disabled the rule'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
