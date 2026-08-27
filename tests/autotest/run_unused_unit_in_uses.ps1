<#
  run_unused_unit_in_uses.ps1 -- the rule must actually FIRE, must use the unit's
  EXPORT surface, and must not report registration units.

  Why this exists
  ---------------
  unused-unit-in-uses reported ZERO on every project it had ever run on. Three
  layers, diagnosed across two sessions:

    1. its "is this unit indexed?" gate queried a single PROJECT store. A
       project store cannot see System.IniFiles, so the gate answered False for
       every RTL/VCL import and the rule skipped it. The gate is load-bearing --
       removing it outright yields 208 findings on DataCopy, nearly all wrong --
       so the fix is to give it the LIBRARY store, not to delete it.
    2. it matched ANY symbol name, including implementation-section locals, so a
       loop counter named I inside a unit made every file that uses a variable I
       "reference" that unit. Only what a unit EXPORTS can keep an import alive.
    3. the generics gap, closed in session 40.

  This guard pins 1 and 2 with a two-database fixture, because a single-store
  test cannot distinguish "found it in the project" from "found it at all".

  What is checked
  ---------------
    * a genuinely dead import IS reported                    (the rule fires)
    * an import whose EXPORT is called is NOT reported       (no false positive)
    * an import referenced only by a name that the unit declares in its
      IMPLEMENTATION is STILL reported                       (layer 2)
    * a registration unit (dxSkin*) is NOT reported          (the FP family)

  The third is the one that separates this fix from the old behaviour: under the
  old stem match that file counted as a user of the unit and stayed silent.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_unused_unit_in_uses"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Host '== unused-unit-in-uses ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
$lib = Join-Path $WorkDir 'lib'
$prj = Join-Path $WorkDir 'prj'
New-Item -ItemType Directory -Force -Path $lib | Out-Null
New-Item -ItemType Directory -Force -Path $prj | Out-Null

# --- the "library": exports ONE routine; declares Helper only in the impl -----
Write-Ascii (Join-Path $lib 'Far.Lib.pas') @'
unit Far.Lib;

interface

type
  { A GENERIC export. It is STORED under its declared name, TBox<T>, while a use
    site says TBox<Integer> -- so a literal match fires on neither side and the
    unit reads as unused. Measured on drag-lint's own source: 15 of 91 findings
    were System.Generics.Defaults in files that demonstrably call
    TComparer<T>.Construct. }
  TBox<T> = record
    Value: T;
  end;

procedure ExportedThing;

implementation

procedure HiddenHelper;
begin
end;

procedure ExportedThing;
begin
  HiddenHelper;
end;

end.
'@

# A registration unit: exports nothing anyone references, by design.
Write-Ascii (Join-Path $lib 'dxSkinFake.pas') @'
unit dxSkinFake;

interface

implementation

end.
'@

# --- the project ------------------------------------------------------------
# Uses the export -> must NOT be reported.
Write-Ascii (Join-Path $prj 'uGood.pas') @'
unit uGood;

interface

uses
  Far.Lib;

procedure Run;

implementation

procedure Run;
begin
  ExportedThing;
end;

end.
'@

# References only HiddenHelper, which the unit declares in its IMPLEMENTATION.
# Under the old any-symbol match this counted as usage and stayed silent.
Write-Ascii (Join-Path $prj 'uImplOnly.pas') @'
unit uImplOnly;

interface

uses
  Far.Lib;

procedure Go;

implementation

procedure HiddenHelper;
begin
end;

procedure Go;
begin
  HiddenHelper;
end;

end.
'@

# A registration import -> must NOT be reported.
Write-Ascii (Join-Path $prj 'uSkinUser.pas') @'
unit uSkinUser;

interface

uses
  dxSkinFake;

implementation

end.
'@

# Uses ONLY the generic export -> must NOT be reported.
Write-Ascii (Join-Path $prj 'uGeneric.pas') @'
unit uGeneric;

interface

uses
  Far.Lib;

procedure UseBox;

implementation

procedure UseBox;
var
  B: TBox<Integer>;
begin
  B.Value := 1;
end;

end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'
$prjDb = Join-Path $WorkDir 'prj.sqlite'
& $Exe index $lib --db $libDb 2>&1 | Out-Null
& $Exe index $prj --db $prjDb 2>&1 | Out-Null

$rep = Join-Path $WorkDir 'rep.txt'
& $Exe lint-all --db $prjDb --db $libDb --output $rep 2>&1 | Out-Null
$out = if (Test-Path $rep) { Get-Content $rep -Raw } else { '' }
$uuiu = ($out -split "`n") | Where-Object { $_ -match 'unused-unit-in-uses' }

Check 'the rule produced any finding at all (it reported ZERO for months)' `
  ($uuiu.Count -gt 0) "count=$($uuiu.Count)"
Check 'a unit referenced only via an IMPLEMENTATION-section name IS reported' `
  (($uuiu -join "`n") -match 'uImplOnly[\s\S]{0,200}?Far\.Lib') "the export surface is what counts"
Check 'a unit whose EXPORT is called is NOT reported' `
  (-not (($uuiu -join "`n") -match 'uGood')) 'false positive on a live import'
Check 'a unit used ONLY through a GENERIC export is NOT reported' `
  (-not (($uuiu -join "`n") -match 'uGeneric')) 'TBox<T> declared vs TBox<Integer> used -- both sides need stripping'
Check 'a registration unit (dxSkin*) is NOT reported' `
  (-not (($uuiu -join "`n") -match 'dxSkinFake')) 'registration units export nothing by design'

Write-Host ''
if ($script:Failed) { Write-Host 'UNUSED-UNIT-IN-USES GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'UNUSED-UNIT-IN-USES GUARD: PASS' -ForegroundColor Green
exit 0
