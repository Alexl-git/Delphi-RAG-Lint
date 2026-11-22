<#
  setup_owner_circular_fx.ps1 -- (re)creates the CIRC owner-test project: Fx.dproj, a throwaway
  console project with ONE circular-uses group, CUnit <-> DUnit, whose cycles --fix dry run is
  'mechanical' with the cut CUnit -> DUnit.

  Why: the project used to live in C:\TEMP\claude\lanes\146\ide-test\website-fx\Fx.dproj and was
  hand-made; a disk purge (2026-11-22) deleted it. This script is now its only source.
  The .dproj is tests\fixtures\cyclefix\qualparta\QualPartA.dproj (Win32 + Win64, the IDE's
  Base / Base_Win32 / Base_Win64 shape) renamed; the units are the r1 shape of
  run_cyclefix_cycq_dcc.ps1 (CUnit calls DUnit.Foo; DUnit's implementation uses TCCls).

  Creates under -Root (default C:\TEMP\owner-tests\circular-fx):
    Fx.dproj / Fx.dpr / CUnit.pas / DUnit.pas
    _D-RAG\Fx.sqlite        the project index (the per-project default the IDE plugin looks for)
  Then checks, with -Engine: index exit 0; `cycles --fix --no-compile --format json` exit 0,
  one group, verdict mechanical, edge cunit -> dunit; the dry run writes nothing (SHA-256).
  Exit 1 when a check fails.

  Usage: pwsh -NoProfile -File setup_owner_circular_fx.ps1 [-Root <dir>] [-Engine <drag-lint.exe>]
  -Engine defaults to this repo's third_party\dll-win64\drag-lint.exe. An existing -Root is replaced.
#>
[CmdletBinding()]
param(
  [string]$Root   = 'C:\TEMP\owner-tests\circular-fx',
  [string]$Engine = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Engine) { $Engine = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Engine)) { Write-Host "FATAL: no engine: $Engine" -ForegroundColor Red; exit 2 }
$Engine = (Resolve-Path -LiteralPath $Engine).Path
$Tmpl = Join-Path $PSScriptRoot '..\fixtures\cyclefix\qualparta\QualPartA.dproj'
if (-not (Test-Path -LiteralPath $Tmpl)) { Write-Host "FATAL: no template: $Tmpl" -ForegroundColor Red; exit 2 }

$Ascii = [Text.ASCIIEncoding]::new()
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), $Ascii) }
$script:Fail = 0
function Check($n, $ok, $d = '') {
  if ($ok) { Write-Host "  [PASS] $n" -ForegroundColor Green } else { Write-Host "  [FAIL] $n  $d" -ForegroundColor Red; $script:Fail++ }
}
function SrcHash([string]$Dir) {
  ((Get-ChildItem -LiteralPath $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}

if (Test-Path -LiteralPath $Root) { [IO.Directory]::Delete($Root, $true) }
$dragDir = Join-Path $Root '_D-RAG'
[void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $Root 'Fx.dproj'; $db = Join-Path $dragDir 'Fx.sqlite'

WriteAscii (Join-Path $Root 'CUnit.pas') @'
unit CUnit;

interface

type
  TCCls = class
  public
    procedure Run;
  end;

procedure CRun;

implementation

uses
  DUnit;

procedure TCCls.Run;
begin
  Foo(1);
end;

procedure CRun;
var
  C: TCCls;
begin
  C := TCCls.Create;
  try
    C.Run;
  finally
    C.Free;
  end;
end;

end.
'@
WriteAscii (Join-Path $Root 'DUnit.pas') @'
unit DUnit;

interface

procedure Foo(pA: Integer);

implementation

uses
  CUnit;

procedure Foo(pA: Integer);
begin
  Writeln('D.Foo ', pA);
  TCCls.Create.Free;
end;

end.
'@
WriteAscii (Join-Path $Root 'Fx.dpr') @'
program Fx;

{$APPTYPE CONSOLE}

uses
  CUnit in 'CUnit.pas',
  DUnit in 'DUnit.pas';

begin
  CRun;
end.
'@
$d = [IO.File]::ReadAllText($Tmpl, $Ascii).Replace('QualPartA', 'Fx')
$d = [regex]::Replace($d, '<DCCReference Include="QpB.pas"/>\s*<DCCReference Include="QpA.pas"/>\s*<DCCReference Include="QpC.pas"/>',
  "<DCCReference Include=`"CUnit.pas`"/>`r`n        <DCCReference Include=`"DUnit.pas`"/>")
WriteAscii $dproj $d

Push-Location $Root
try {
  Write-Host "Indexing $dproj with $Engine" -ForegroundColor Cyan
  $out = & { $ErrorActionPreference = 'Continue'; $null | & $Engine index --project $dproj --db $db 2>&1 | Out-String }
  $code = $LASTEXITCODE
  $summary = (($out -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
  Check 'index exit 0, Fx.sqlite exists' (($code -eq 0) -and (Test-Path -LiteralPath $db)) "exit=$code $summary"
  Check 'dproj references CUnit + DUnit' ($d.Contains('<DCCReference Include="CUnit.pas"/>') -and $d.Contains('<DCCReference Include="DUnit.pas"/>'))

  $h0 = SrcHash $Root
  $fx = & { $ErrorActionPreference = 'Continue'; $null | & $Engine cycles --fix --project $dproj --db $db --no-compile --format json 2>$null | Out-String }
  $fcode = $LASTEXITCODE
  $j = $null; try { $j = $fx | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
  $c = if ($j) { @($j.cycles)[0] } else { $null }
  $edge = if ($c) { "$($c.edge)" } else { '' }
  Check 'cycles --fix dry run exit 0' ($fcode -eq 0) "exit=$fcode $fx"
  Check 'one circular group' ($j -and @($j.cycles).Count -eq 1) "groups=$(if ($j) { @($j.cycles).Count } else { 'no json' })"
  Check 'verdict mechanical' ($c -and $c.verdict -eq 'mechanical') "verdict=$(if ($c) { $c.verdict })"
  Check 'edge cunit -> dunit' ($edge -match '(?i)cunit\s*->\s*dunit') "edge=$edge"
  Check 'the dry run wrote nothing' ((SrcHash $Root) -ceq $h0)
} finally { Pop-Location }
Write-Host "project: $dproj  index: $summary"
if ($script:Fail -gt 0) { Write-Host "FAILED: $($script:Fail) check(s)" -ForegroundColor Red; exit 1 }
Write-Host 'OK' -ForegroundColor Green
exit 0
