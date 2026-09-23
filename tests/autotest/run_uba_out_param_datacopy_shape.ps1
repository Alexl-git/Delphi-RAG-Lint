<#
  run_uba_out_param_datacopy_shape.ps1 -- ENG-7,
  docs\INBOX-used-before-assignment-out-params.md (filed 2026-09-20 from DataCopy).

  THE REPORT: `used-before-assignment` fired [error] on
      if not ReplaceOutputIfUnchanged(LOut, LExBytes, LOutLines, LChanged, LErrCode, LErr) then
  where LChanged / LErrCode are passed to `out` parameters, declared in ANOTHER
  unit with a signature WRAPPED over three lines.

  WHAT WAS MEASURED BEFORE THIS FILE EXISTED (2026-09-23), and why it is a
  guard rather than a fix: `out` IS modelled -- 99c45c6f (2026-08-28) made a
  KNOWN var/out argument a def, and run_uba_param_modes.ps1 pins it on a
  single-unit fixture. The DataCopy report did NOT reproduce on main 4629a769:
  not on this synthetic copy of its shape, not on DataCopy's own rev-339
  sources (the revision the report was filed against), and not with its
  workaround lines removed. The cause of the original report is therefore
  UNKNOWN -- this file pins the exact reported shape so that, if it comes back,
  it fails here instead of in a customer's error-severity report.

  The positive control is the same call shape with the parameter declared BY
  VALUE: that must still fire, or every "not reported" below is vacuous.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uba-out-datacopy"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory $WorkDir | Out-Null }
foreach ($stale in @(Get-ChildItem -LiteralPath $WorkDir -File -ErrorAction SilentlyContinue)) {
  [System.IO.File]::Delete($stale.FullName)
}

Write-Ascii (Join-Path $WorkDir 'uOutCallee.pas') @'
unit uOutCallee;

interface

uses
  System.SysUtils, Winapi.Windows;

function ReplaceOutputIfUnchanged(const pFile: string; const pExpected: TBytes;
                        const pLines: TArray<string>; out pChanged: Boolean;
                        out pErrCode: DWord; out pErr: string): Boolean;

function ReplaceByValue(const pFile: string; const pExpected: TBytes;
                        const pLines: TArray<string>; pChanged: Boolean;
                        pErrCode: DWord; out pErr: string): Boolean;

implementation

function ReplaceOutputIfUnchanged(const pFile: string; const pExpected: TBytes;
                        const pLines: TArray<string>; out pChanged: Boolean;
                        out pErrCode: DWord; out pErr: string): Boolean;
begin
  Result  := False;
  pChanged:= False;
  pErrCode:= 0;
  pErr    := '';
end;

function ReplaceByValue(const pFile: string; const pExpected: TBytes;
                        const pLines: TArray<string>; pChanged: Boolean;
                        pErrCode: DWord; out pErr: string): Boolean;
begin
  Result:= pChanged and (pErrCode = 0);
  pErr  := '';
end;

end.
'@
Write-Ascii (Join-Path $WorkDir 'uOutCaller.pas') @'
unit uOutCaller;

interface

procedure RunOut(const AOut: string);
procedure RunValue(const AOut: string);

implementation

uses
  System.SysUtils, Winapi.Windows, uOutCallee;

procedure RunOut(const AOut: string);
var
  LChanged : Boolean;
  LErrCode : DWord;
  LErr     : string;
  LExBytes : TBytes;
  LOutLines: TArray<string>;
begin
  LExBytes := nil;
  LOutLines:= nil;
  if not ReplaceOutputIfUnchanged(AOut, LExBytes, LOutLines, LChanged, LErrCode, LErr) then
  begin
    if LChanged then Writeln(LErrCode);
  end;
end;

procedure RunValue(const AOut: string);
var
  VChanged : Boolean;
  VErrCode : DWord;
  VErr     : string;
  VExBytes : TBytes;
  VOutLines: TArray<string>;
begin
  VExBytes := nil;
  VOutLines:= nil;
  if not ReplaceByValue(AOut, VExBytes, VOutLines, VChanged, VErrCode, VErr) then
    Writeln(VErr);
end;

end.
'@
Write-Ascii (Join-Path $WorkDir 'OutParams.dpr') @'
program OutParams;

uses
  uOutCallee in 'uOutCallee.pas',
  uOutCaller in 'uOutCaller.pas';

begin
  RunOut('x');
  RunValue('x');
end.
'@

$db = Join-Path $WorkDir 'OutParams.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$uba = @(& $Exe lint (Join-Path $WorkDir 'uOutCaller.pas') --db $db 2>&1 |
         ForEach-Object { "$_" } | Where-Object { $_ -match 'used-before-assignment' })
$uba | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

Write-Host 'POSITIVE CONTROL -- the same shape BY VALUE still fires' -ForegroundColor Cyan
Check 'by-value VChanged is reported' (@($uba | Where-Object { $_ -match '"vchanged"' }).Count -ge 1)
Check 'by-value VErrCode is reported' (@($uba | Where-Object { $_ -match '"verrcode"' }).Count -ge 1)

Write-Host 'THE REPORTED SHAPE -- out parameters, wrapped cross-unit signature, if-not call' -ForegroundColor Cyan
Check 'LChanged passed to `out` is NOT reported' (@($uba | Where-Object { $_ -match '"lchanged"' }).Count -eq 0)
Check 'LErrCode passed to `out` is NOT reported' (@($uba | Where-Object { $_ -match '"lerrcode"' }).Count -eq 0)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL: uba-out-param-datacopy-shape' -ForegroundColor Red; exit 1 }
Write-Host 'PASS: uba-out-param-datacopy-shape' -ForegroundColor Green
exit 0
