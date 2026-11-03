<#
  run_shared_unit_scope.ps1 -- SHARED-UNIT-SCOPE (1.41, owner ruling 2026-11-02: UNION).

  A unit compiled into several projects is unused only when NO project that lists it uses it.
  Spec: docs\superpowers\specs\2026-11-03-shared-unit-scope-design.md.

  Fixture: Shared.Ctl.pas lives in ONE folder and is listed by two .dproj projects (P1, P2).
  It carries NO dl:shared header -- the case of DRagLint.Core.ControlChannel.pas, which the
  1.40 engine judged from one DB only. P1 names nothing from it; P2 calls Beat and writes GLive.

    lint P1 (union)        : Beat, GLive NOT reported; DeadBeat, GDead reported (positive control)
    P2's DB stale          : DeadBeat, GDead NOT reported either (UNDECIDED -- conservative)

  RED on 1.40: Beat (unused-public-symbol) and GLive (unused-global) are reported for P1.

  Usage: pwsh -File tests\autotest\run_shared_unit_scope.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-shared-unit-scope-$PID"
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
function Write-Ascii([string]$Path, [string]$Body) {
  [System.IO.File]::WriteAllText($Path, ($Body -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
function Write-Project([string]$Dir, [string]$Name, [string]$MainUnit) {
  Write-Ascii (Join-Path $Dir "$Name.dpr") @"
program $Name;

uses
  Shared.Ctl in '..\shared\Shared.Ctl.pas',
  $MainUnit in '$MainUnit.pas';

begin
end.
"@
  Write-Ascii (Join-Path $Dir "$Name.dproj") @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>$Name.dpr</MainSource></PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="$Name.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
    <DCCReference Include="..\shared\Shared.Ctl.pas"/>
    <DCCReference Include="$MainUnit.pas"/>
  </ItemGroup>
</Project>
"@
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Rules = (Resolve-Path "$PSScriptRoot\..\..\rules").Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$sh = Join-Path $WorkDir 'shared'; $p1 = Join-Path $WorkDir 'P1'; $p2 = Join-Path $WorkDir 'P2'
foreach ($d in $sh, $p1, $p2) { New-Item -ItemType Directory -Force $d | Out-Null }

Write-Ascii (Join-Path $sh 'Shared.Ctl.pas') @'
unit Shared.Ctl;

interface

var
  GLive: Integer;
  GDead: Integer;

procedure Beat;
procedure DeadBeat;

implementation

procedure Beat;
begin
end;

procedure DeadBeat;
begin
end;

end.
'@
Write-Ascii (Join-Path $p1 'P1Main.pas') @'
unit P1Main;

interface

procedure RunOne;

implementation

uses Shared.Ctl;

procedure RunOne;
begin
end;

end.
'@
Write-Ascii (Join-Path $p2 'P2Main.pas') @'
unit P2Main;

interface

procedure RunTwo;

implementation

uses Shared.Ctl;

procedure RunTwo;
begin
  Beat;
  GLive:= 1;
end;

end.
'@
Write-Project $p1 'P1' 'P1Main'
Write-Project $p2 'P2' 'P2Main'

$db1 = Join-Path $WorkDir 'P1.sqlite'
$db2 = Join-Path $WorkDir 'P2.sqlite'
# Section names -> outDir\<name>.sqlite, the same mapping the sibling resolver reads.
$manifest = Join-Path $WorkDir 'drag-lint.json'
Write-Ascii $manifest (@'
{
  "settings": { "defaultPlatform": "Win64" },
  "indexes": {
    "outDir": "OUTDIR",
    "sections": [
      { "name": "P1", "include": ["ONEDIR"] },
      { "name": "P2", "include": ["TWODIR"] }
    ]
  }
}
'@ -replace 'OUTDIR', ($WorkDir -replace '\\', '\\') -replace 'ONEDIR', ($p1 -replace '\\', '\\') -replace 'TWODIR', ($p2 -replace '\\', '\\'))

foreach ($pair in @(@("$p1\P1.dproj", $db1), @("$p2\P2.dproj", $db2))) {
  $out = & $Exe index --project $pair[0] --db $pair[1] --quiet 2>&1
  Check ("index {0}" -f (Split-Path $pair[1] -Leaf)) ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
}
$both = (& $Exe sql --query "SELECT COUNT(*) FROM files WHERE path LIKE '%Shared.Ctl.pas'" --db $db2 2>&1) -join ' '
Check 'precondition: P2 lists the shared unit (one files row, same path)' ($both -match '\b1\b') $both

function Lint-P1 {
  $o = (@(& $Exe lint-all --db $db1 --config $manifest --rules-dir $Rules --enable unused-global --quiet 2>&1) | ForEach-Object { "$_" })
  return ($o | Where-Object { $_ -match 'unused-public-symbol|unused-global' }) -join "`n"
}

Write-Host 'union: lint P1 with both projects configured' -ForegroundColor Cyan
$u = Lint-P1
Check 'POSITIVE CONTROL: DeadBeat (dead in both) IS reported' ($u -match 'DeadBeat') $u
Check 'POSITIVE CONTROL: GDead (dead in both) IS reported' ($u -match 'GDead') $u
Check 'Beat (called only in P2) is NOT reported' ($u -notmatch '\bBeat\b') $u
Check 'GLive (written only in P2) is NOT reported' ($u -notmatch 'GLive') $u

Write-Host 'undecided: P2 index stale' -ForegroundColor Cyan
Start-Sleep -Seconds 2
$m2 = Join-Path $p2 'P2Main.pas'
[System.IO.File]::AppendAllText($m2, "`r`n", [System.Text.Encoding]::ASCII)
[System.IO.File]::SetLastWriteTimeUtc($m2, [DateTime]::UtcNow.AddMinutes(5))
$s = Lint-P1
Check 'stale listing DB: DeadBeat is NOT reported (cannot prove it dead)' ($s -notmatch 'DeadBeat') $s
Check 'stale listing DB: GDead is NOT reported' ($s -notmatch 'GDead') $s

Write-Host 'DLOK-UNDECIDED: a dl:ok on an undecided site is not review-marker-unused' -ForegroundColor Cyan
$ctl = Join-Path $sh 'Shared.Ctl.pas'
$src = [System.IO.File]::ReadAllText($ctl)
$src = $src.Replace('  GDead: Integer;', '  GDead: Integer; // dl:ok unused-global -- test: sibling index stale')
$src = [regex]::new('procedure DeadBeat;').Replace($src, 'procedure DeadBeat; // dl:ok unused-public-symbol -- test: sibling index stale', 1)
$src = [regex]::new('procedure Beat;').Replace($src, 'procedure Beat; // dl:ok bare-except -- CONTROL: no such finding, must stay unused', 1)
Write-Ascii $ctl $src
& $Exe index --project "$p1\P1.dproj" --db $db1 --quiet 2>&1 | Out-Null
$o = (@(& $Exe lint-all --db $db1 --config $manifest --rules-dir $Rules --enable unused-global,review-marker-unused --quiet 2>&1) | ForEach-Object { "$_" }) -join "`n"
Check 'POSITIVE CONTROL: a marker on a decided/no-finding line IS review-marker-unused' ($o -match 'review-marker-unused[^\n]*bare-except|bare-except[^\n]*review-marker-unused') $o
Check 'undecided unused-public-symbol marker NOT reported unused' ($o -notmatch 'unused-public-symbol" no longer') $o
Check 'undecided unused-global marker NOT reported unused' ($o -notmatch 'unused-global" no longer') $o
Write-Host ''
if ($script:Failed) { Write-Host 'SHARED-UNIT-SCOPE GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'SHARED-UNIT-SCOPE GUARD: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-shared-unit-scope-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
