<#
  run_unit_missing_from_uses.ps1 -- rule `unit-missing-from-uses` (lint <file>,
  lint-all, lint --fix). A name the index left unbound that a unit the file does
  NOT use declares in its interface: "'CsSite' is declared in unit uCsLog -- add
  it to the <interface|implementation> uses clause".
   * used only in the implementation -> implementation clause (created when absent)
   * used as a type in the interface  -> interface clause
   * unit already in uses / a local of that name / a member after a dot -> nothing
   * interface edge that closes an interface-only cycle -> implementation offered
   * --fix writes the clause; the fixed unit then lints clean
  Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-missinguses-$PID"
)
. (Join-Path $PSScriptRoot 'exe-hint.ps1')   # Get-ExeStartFailureHint (GUARD-0XC07B)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$WorkDir = Join-Path $WorkDir ([guid]::NewGuid().ToString('N'))
$srcDir = Join-Path $WorkDir 'src'
$libDir = Join-Path $WorkDir 'lib'
New-Item -ItemType Directory $srcDir, $libDir -Force | Out-Null
function Emit([string]$name, [string]$text, [string]$dir = $srcDir) {
  [IO.File]::WriteAllText((Join-Path $dir $name), (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
Emit 'uCsLog.pas' @'
unit uCsLog;
interface
type
  TCsLogger = class
  public
    procedure Send(const S: string);
  end;
var
  CsSite: TCsLogger;
implementation
procedure TCsLogger.Send(const S: string);
begin
end;
end.
'@
Emit 'System.pas' @'
unit System;
interface
implementation
end.
'@
Emit 'uHelper.pas' @'
unit uHelper;
interface
implementation
end.
'@
Emit 'uUnknown.pas' @'
unit uUnknown;
interface
implementation
uses NoSuchUnit;
procedure P;
begin
  CsSite.Send('x');
end;
end.
'@
Emit 'uImplUse.pas' @'
unit uImplUse;
interface
procedure DoIt;
implementation
procedure DoIt;
begin
  CsSite.Send('x');
end;
end.
'@
Emit 'uIntfUse.pas' @'
unit uIntfUse;
interface
uses
  uHelper;
type
  TFoo = class
    F: TCsLogger;
  end;
implementation
end.
'@
Emit 'uAlready.pas' @'
unit uAlready;
interface
implementation
uses uCsLog;
procedure P;
var Q: TObject;
begin
  CsSite.Send('x');
  Q.CsSite;
end;
end.
'@
Emit 'uLocal.pas' @'
unit uLocal;
interface
implementation
procedure P;
var CsSite: Integer;
begin
  CsSite := 1;
end;
end.
'@
# INBOX-uses-dotted-name-whitespace: a dotted unit name padded around its dot
# (`uHelper      .Pad`, legal for dcc) must match unit uHelper.Pad. uHelper.Pad lives in a
# LIBRARY DB (as System.Generics.Collections does for YADF), so the project index leaves
# TPadList unbound and the rule reads the uses text; the head (uHelper) is itself an indexed
# unit, as System is. Reported by lint-all (the INBOX repro), so read from $all.
Emit 'uHelper.Pad.pas' -dir $libDir @'
unit uHelper.Pad;
interface
type
  TPadList<T> = class
  end;
implementation
end.
'@
Emit 'uWsDot.pas' @'
unit uWsDot;
interface
implementation
uses
  uImplUse
  , uHelper      .Pad
  ;
procedure P;
var
  L: TPadList<Integer>;
begin
  L := TPadList<Integer>.Create;
end;
end.
'@
Emit 'uWsMiss.pas' @'
unit uWsMiss;
interface
implementation
uses
  uHelper  .  Pad;
procedure P;
var
  L: TPadList<Integer>;
begin
  L := TPadList<Integer>.Create;
  CsSite.Send('x');
end;
end.
'@
# cycle: uCycB uses uCycA in its interface; uCycA needs TCycB (declared in uCycB) in its interface
Emit 'uCycB.pas' @'
unit uCycB;
interface
uses uCycA;
type
  TCycB = class
  end;
implementation
end.
'@
Emit 'uCycA.pas' @'
unit uCycA;
interface
type
  TCycA = class
    B: TCycB;
  end;
implementation
end.
'@
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
[IO.File]::WriteAllText($manifest, '{ "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 }, "indexes": { "outDir": "out", "sections": [ { "name": "SecMu", "db": "mu.sqlite", "include": ["src"] }, { "name": "SecMuLib", "db": "mulib.sqlite", "include": ["lib"] } ] } }', [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\mu.sqlite'
$libDb = Join-Path $WorkDir 'out\mulib.sqlite'
function LintOf([string]$unit) {
  @(& $Exe lint (Join-Path $srcDir $unit) --db $db --db $libDb --rule unit-missing-from-uses --quiet 2>&1 | Out-String) -split "`r?`n" |
    Where-Object { $_ -match 'unit-missing-from-uses' }
}
Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecMu --jobs 1 2>&1 | Out-Null
  & $Exe index --all --config $manifest --only SecMuLib --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) { $hint = Get-ExeStartFailureHint $LASTEXITCODE; if ($hint) { Write-Host "FATAL: $hint" -ForegroundColor Red }; Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2 }
  $impl = @(LintOf 'uImplUse.pas'); $intf = @(LintOf 'uIntfUse.pas'); $already = @(LintOf 'uAlready.pas')
  $local = @(LintOf 'uLocal.pas'); $unknown = @(LintOf 'uUnknown.pas'); $cyc = @(LintOf 'uCycA.pas')
  $all = & $Exe lint-all --db $db --db $libDb --rule unit-missing-from-uses --quiet 2>&1 | Out-String
  $allLines = $all -split "`r?`n" | Where-Object { $_ -match 'unit-missing-from-uses' }
  $wsDot = @($allLines | Where-Object { $_ -match 'uWsDot\.pas' }); $wsMiss = @($allLines | Where-Object { $_ -match 'uWsMiss\.pas' })
  $rules = & $Exe rules --json 2>&1 | Out-String
  Write-Host 'FINDINGS' -ForegroundColor Cyan
  # positive-control: unit-missing-from-uses
  Check 'impl-only use -> one finding, implementation clause' (($impl.Count -eq 1) -and ($impl[0] -match "uImplUse\.pas:7:3") -and ($impl[0] -match "'CsSite' is declared in unit uCsLog -- add it to the implementation uses clause")) ($impl -join ' | ')
  Check 'interface type use -> interface clause' (($intf.Count -eq 1) -and ($intf[0] -match "'TCsLogger' is declared in unit uCsLog -- add it to the interface uses clause")) ($intf -join ' | ')
  Check 'NEG: unit already in uses (and a member after a dot) -> nothing' ($already.Count -eq 0) ($already -join ' | ')
  Check 'NEG: a local of that name -> nothing' ($local.Count -eq 0) ($local -join ' | ')
  Check 'NEG: an unindexed used unit could declare it -> nothing' ($unknown.Count -eq 0) ($unknown -join ' | ')
  Check 'cycle: interface would close uCycA -> uCycB -> uCycA, implementation offered' (($cyc.Count -eq 1) -and ($cyc[0] -match 'add it to the implementation uses clause') -and ($cyc[0] -match 'circular unit reference: uCycA -> uCycB -> uCycA')) ($cyc -join ' | ')
  Check 'NEG: dotted uses entry padded before the dot (uHelper      .Pad) -> nothing' ($wsDot.Count -eq 0) ($wsDot -join ' | ')
  # positive-control: a padded entry (uHelper  .  Pad) covers only its own unit; a truly missing unit still fires
  Check 'padded entry does not hide a truly missing unit -> one finding for uCsLog' (($wsMiss.Count -eq 1) -and ($wsMiss[0] -match "'CsSite' is declared in unit uCsLog")) ($wsMiss -join ' | ')
  Check 'lint-all reports the same rule (impl + intf + cycle + wsMiss = 4)' (([regex]::Matches($all, 'unit-missing-from-uses')).Count -eq 4) ''
  Check 'rules --json lists the rule as fixable' ($rules -match '"id"\s*:\s*"unit-missing-from-uses"[^}]*"fixable"\s*:\s*true') ''
  Write-Host 'FIX' -ForegroundColor Cyan
  & $Exe lint (Join-Path $srcDir 'uImplUse.pas') --db $db --rule unit-missing-from-uses --fix --apply --quiet 2>&1 | Out-Null
  & $Exe lint (Join-Path $srcDir 'uIntfUse.pas') --db $db --rule unit-missing-from-uses --fix --apply --quiet 2>&1 | Out-Null
  $implTxt = [IO.File]::ReadAllText((Join-Path $srcDir 'uImplUse.pas'))
  $intfTxt = [IO.File]::ReadAllText((Join-Path $srcDir 'uIntfUse.pas'))
  Check '--fix creates the implementation clause' ($implTxt.Contains("implementation`r`n`r`nuses`r`n  uCsLog;`r`nprocedure DoIt;")) ($implTxt -replace "`r`n", '\n')
  Check '--fix extends the interface clause in its own layout' ($intfTxt.Contains("uses`r`n  uHelper,`r`n  uCsLog;")) ($intfTxt -replace "`r`n", '\n')
  Check '--fix output stays 7-bit ASCII + CRLF' ((-not ($implTxt -match "[^\x00-\x7F]")) -and (-not ($implTxt -match "[^\r]\n"))) ''
} finally { Pop-Location }
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
