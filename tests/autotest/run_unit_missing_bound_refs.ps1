<#
  run_unit_missing_bound_refs.ps1 -- rule `unit-missing-from-uses` on a ref the index
  BOUND while the unit was still in uses (INBOX-missing-uses-skips-resolver-bound-refs).

  The resolver honours the uses list, so a bound ref outside it exists only while the
  index is older than the text: the unit was taken out of uses and no reindex ran yet
  (the LSP and lint both judge the live text). Each edit below keeps the line count on
  purpose: the rule answers nothing where the name moved from its indexed position.

   * bound function / const / enum value / type, unit gone from the text -> one finding each
   * still in uses                                        -> nothing
   * scoped unit, listed by its short name                -> nothing
   * another used unit declares the name                  -> nothing
   * the text now declares the name itself                -> nothing
   * bound member without a receiver (inherited field)    -> never a candidate
   * --fix puts the unit back
  Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-missingbound-$PID"
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
New-Item -ItemType Directory $srcDir -Force | Out-Null
function Emit([string]$name, [string]$text) {
  [IO.File]::WriteAllText((Join-Path $srcDir $name), (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Blank([string]$name, [string]$from, [string]$to) {
  $p = Join-Path $srcDir $name
  $t = [IO.File]::ReadAllText($p)
  if (-not $t.Contains($from)) { Write-Host "FATAL: $name holds no '$from'" -ForegroundColor Red; exit 2 }
  [IO.File]::WriteAllText($p, $t.Replace($from, $to), [Text.Encoding]::ASCII)
}
Emit 'System.pas' @'
unit System;
interface
implementation
end.
'@
Emit 'uDecl.pas' @'
unit uDecl;
interface
type
  TDeclKlass = class
    InheritedField: Integer;
  end;
  TDeclEnum = (deOne, deTwo);
const
  DeclConst: array[0..1] of Integer = (1, 2);
function DeclFn: Integer;
implementation
function DeclFn: Integer;
begin
  Result := 1;
end;
end.
'@
Emit 'uTwin.pas' @'
unit uTwin;
interface
function TwinFn: Integer;
implementation
function TwinFn: Integer;
begin
  Result := 2;
end;
end.
'@
Emit 'uTwin2.pas' @'
unit uTwin2;
interface
function TwinFn: Integer;
implementation
function TwinFn: Integer;
begin
  Result := 3;
end;
end.
'@
Emit 'System.AcmeScoped.pas' @'
unit System.AcmeScoped;
interface
function ScopedFn: Integer;
implementation
function ScopedFn: Integer;
begin
  Result := 4;
end;
end.
'@
Emit 'uGone.pas' @'
unit uGone;
interface
function Go: Integer;
implementation
uses uDecl;
function Go: Integer;
var
  K: TDeclKlass;
  E: TDeclEnum;
begin
  K := nil;
  E := deOne;
  Result := DeclFn + DeclConst[0];
end;
end.
'@
Emit 'uKept.pas' @'
unit uKept;
interface
function Go: Integer;
implementation
uses uDecl;
function Go: Integer;
begin
  Result := DeclFn + DeclConst[0];
end;
end.
'@
Emit 'uTwinUser.pas' @'
unit uTwinUser;
interface
function Go: Integer;
implementation
uses uTwin;
function Go: Integer;
begin
  Result := TwinFn;
end;
end.
'@
Emit 'uShort.pas' @'
unit uShort;
interface
function Go: Integer;
implementation
uses System.AcmeScoped;
function Go: Integer;
begin
  Result := ScopedFn;
end;
end.
'@
Emit 'uShadow.pas' @'
unit uShadow;
interface
function Go: Integer;
implementation
uses uDecl;
function Go: Integer;
{ placeholder }
begin
  Result := DeclFn;
end;
end.
'@
Emit 'uMember.pas' @'
unit uMember;
interface
uses uDecl;
type
  TKid = class(TDeclKlass)
    procedure Run;
  end;
implementation
procedure TKid.Run;
begin
  InheritedField := 1;
end;
end.
'@
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
[IO.File]::WriteAllText($manifest, '{ "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 }, "indexes": { "outDir": "out", "sections": [ { "name": "SecBound", "db": "b.sqlite", "include": ["src"] } ] } }', [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\b.sqlite'
function LintOf([string]$unit) {
  @(& $Exe lint (Join-Path $srcDir $unit) --db $db --rule unit-missing-from-uses --quiet 2>&1 | Out-String) -split "`r?`n" |
    Where-Object { $_ -match 'unit-missing-from-uses' }
}
function BoundCount([string]$unit, [string]$name) {
  # sql --json rows are POSITIONAL arrays
  $q = "select count(*) from refs r join files f on f.id=r.file_id where f.path like '%$unit' and r.name_text='$name' and r.symbol_id>0"
  $j = & $Exe sql --db $db --query $q --json 2>&1 | Out-String | ConvertFrom-Json
  [int]$j.rows[0][0]
}
Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecBound --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) { $hint = Get-ExeStartFailureHint $LASTEXITCODE; if ($hint) { Write-Host "FATAL: $hint" -ForegroundColor Red }; Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2 }

  Write-Host 'PRECONDITION: the refs are bound before the text changes' -ForegroundColor Cyan
  foreach ($c in @(@('uGone.pas', 'DeclFn'), @('uGone.pas', 'DeclConst'), @('uGone.pas', 'deOne'), @('uGone.pas', 'TDeclKlass'),
                   @('uTwinUser.pas', 'TwinFn'), @('uShort.pas', 'ScopedFn'), @('uShadow.pas', 'DeclFn'), @('uMember.pas', 'InheritedField'))) {
    Check "$($c[0]) $($c[1]) is bound" ((BoundCount $c[0] $c[1]) -gt 0)
  }

  # NEG before the edit: a fresh index holds no finding at all
  $fresh = @(& $Exe lint-all --db $db --rule unit-missing-from-uses --quiet 2>&1 | Out-String) -split "`r?`n" | Where-Object { $_ -match 'unit-missing-from-uses' }
  Check 'NEG: fresh index, every unit in uses -> lint-all silent' (@($fresh).Count -eq 0) ($fresh -join ' | ')

  Blank 'uGone.pas'     'uses uDecl;'         '//'
  Blank 'uTwinUser.pas' 'uses uTwin;'         'uses uTwin2;'
  Blank 'uShort.pas'    'uses System.AcmeScoped;' 'uses AcmeScoped;'
  Blank 'uShadow.pas'   'uses uDecl;'         'uses uTwin;'
  Blank 'uShadow.pas'   '{ placeholder }'     'var DeclFn: Integer;'

  Write-Host 'FINDINGS' -ForegroundColor Cyan
  $gone = @(LintOf 'uGone.pas')
  # positive-control: unit-missing-from-uses (bound ref, unit gone from the text)
  foreach ($n in 'DeclFn', 'DeclConst', 'deOne', 'TDeclKlass', 'TDeclEnum') {
    $hit = @($gone | Where-Object { $_ -match "'$n' is declared in unit uDecl -- add it to the implementation uses clause" })
    Check "bound $n, unit gone from uses -> finding names uDecl" ($hit.Count -ge 1) ($gone -join ' | ')
  }
  $kept = @(LintOf 'uKept.pas');       Check 'NEG: bound ref, unit still in uses -> nothing' ($kept.Count -eq 0) ($kept -join ' | ')
  $twin = @(LintOf 'uTwinUser.pas');   Check 'NEG: another used unit declares the name -> nothing' ($twin.Count -eq 0) ($twin -join ' | ')
  $short = @(LintOf 'uShort.pas');     Check 'NEG: scoped unit listed by its short name -> nothing' ($short.Count -eq 0) ($short -join ' | ')
  $shadow = @(LintOf 'uShadow.pas');   Check 'NEG: the text declares the name itself -> nothing' ($shadow.Count -eq 0) ($shadow -join ' | ')

  Blank 'uMember.pas' 'uses uDecl;' '//'
  $member = @(LintOf 'uMember.pas')
  Check 'NEG: bound member without a receiver is never a candidate' (@($member | Where-Object { $_ -match 'InheritedField' }).Count -eq 0) ($member -join ' | ')
  # positive-control: the same file DOES fire for the type, so the NEG above is not vacuous
  Check 'the same file fires for the base type' (@($member | Where-Object { $_ -match "'TDeclKlass' is declared in unit uDecl" }).Count -ge 1) ($member -join ' | ')

  Write-Host 'FIX' -ForegroundColor Cyan
  & $Exe lint (Join-Path $srcDir 'uGone.pas') --db $db --rule unit-missing-from-uses --fix --apply --quiet 2>&1 | Out-Null
  $txt = [IO.File]::ReadAllText((Join-Path $srcDir 'uGone.pas'))
  Check '--fix puts the unit back in the implementation clause' ($txt -match '(?s)implementation.*uses\s+uDecl;') ($txt -replace "`r`n", '\n')
} finally { Pop-Location }
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
