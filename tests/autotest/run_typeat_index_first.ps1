# typeat / hover: a bare identifier answers from the INDEXED ref first (1.52 EXTGAPS, D7b).
#
# Bug (docs\INBOX-typeat-application-resolves-to-wrong-unit.md): typeat on `Application` in
# Micronite2027.dpr named iTOOLASSG.ImcTOOLASSG.APPLICATION -- a PROPERTY of a class in a used
# unit -- while the refs row at that very position says Vcl.Forms.Application. Root cause: the
# bare-identifier branch of TTypeAtResolver.Resolve never read the refs table; it ran a by-NAME
# lookup that prefers any symbol declared under a used unit, at any depth, so a class member
# (which a program block cannot see unqualified) won over the real global.
#
# Fix: before the by-name lookup, read the ref covering the cursor (ISymbolStore.FindReferenceAt):
# a bound symbol_id answers with that symbol; an external_target answers with the library symbol
# of that qualified name (or, with no library store attached, the qualified name itself).
#
# Fixture: AaTool declares TTool.Application (a property), ZzGlob declares a global
# `Application`; the program uses both, AaTool FIRST, so the old by-name lookup reaches the
# property first. The resolver binds the program's ref to ZzGlob.Application.
# Optional (SKIP when no library DB is configured): `uses Vcl.Forms` binds an external target.
#
# Usage: pwsh -File tests/autotest/run_typeat_index_first.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = '',
    [string] $WorkDir = "$env:TEMP\drag-lint-typeat-index-first-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $(if ($Ok) {''} else {$Detail})) -ForegroundColor $color
    if ($Ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$srcDir = "$WorkDir\src"
New-Item -ItemType Directory $srcDir -Force | Out-Null

@'
unit AaTool;

interface

type
  TTool = class
  private
    FApplication: Integer;
  public
    property Application: Integer read FApplication write FApplication;
  end;

implementation

end.
'@ | Set-Content "$srcDir\AaTool.pas" -Encoding ascii

@'
unit ZzGlob;

interface

type
  TApp = class
  public
    procedure Run;
  end;

var
  Application: TApp;

implementation

procedure TApp.Run;
begin
end;

end.
'@ | Set-Content "$srcDir\ZzGlob.pas" -Encoding ascii

$dpr = "$srcDir\IdxFirst.dpr"
@'
program IdxFirst;

uses
  AaTool,
  ZzGlob;

begin
  Application.Run;
end.
'@ | Set-Content $dpr -Encoding ascii

$db = "$WorkDir\idx.sqlite"
$idxOut = & { $ErrorActionPreference = 'Continue'; & $Exe index $srcDir --db $db 2>&1 | ForEach-Object { "$_" } }
Check 'index fixture exits 0' ($LASTEXITCODE -eq 0) (($idxOut | Select-Object -Last 1))

# The resolver's binding (the fact typeat must agree with).
$refOut = (& { $ErrorActionPreference = 'Continue'; & $Exe sql --db $db --query "select s.qualified_name from refs r join files f on f.id=r.file_id join symbols s on s.id=r.symbol_id where f.path like '%IdxFirst.dpr' and r.name_text='Application'" 2>&1 | ForEach-Object { "$_" } }) -join "`n"
Check 'resolver binds the program ref to ZzGlob.Application' ($refOut -match 'ZzGlob\.Application') $refOut

# typeat on `Application` (line 8, col 3, 1-based).
$out = (& { $ErrorActionPreference = 'Continue'; & $Exe typeat "${dpr}:8:3" --db $db 2>&1 | ForEach-Object { "$_" } }) -join "`n"
Check 'typeat names ZzGlob.Application' ($out -match 'Resolved:\s+ZzGlob\.Application\s*(\r|\n|$)') $out
Check 'typeat does NOT name the class property AaTool.TTool.Application' (-not ($out -match 'AaTool\.TTool\.Application')) $out

# Positive control: the property is still indexed and still answers where it IS visible.
$q = (& { $ErrorActionPreference = 'Continue'; & $Exe query --qname AaTool.TTool.Application --db $db 2>&1 | ForEach-Object { "$_" } }) -join "`n"
Check 'AaTool.TTool.Application still indexed' ($q -match 'AaTool\.TTool\.Application') $q

# External binding (library): a program that uses Vcl.Forms. SKIP without a library DB.
$src2 = "$WorkDir\src2"
New-Item -ItemType Directory $src2 -Force | Out-Null
Copy-Item "$srcDir\AaTool.pas" $src2
$dpr2 = "$src2\IdxVcl.dpr"
@'
program IdxVcl;

uses
  AaTool,
  Vcl.Forms;

begin
  Application.Initialize;
end.
'@ | Set-Content $dpr2 -Encoding ascii
$db2 = "$WorkDir\idx2.sqlite"
$lib = if ($env:DL_LIBRARY_DB) { $env:DL_LIBRARY_DB } else { 'C:\Projects\.drag-lint\library-Win64.sqlite' }
$libArgs = if (Test-Path $lib) { @('--library-db', $lib) } else { @() }
& { $ErrorActionPreference = 'Continue'; & $Exe index $src2 --db $db2 @libArgs 2>&1 | ForEach-Object { "$_" } } | Out-Null
$ext = (& { $ErrorActionPreference = 'Continue'; & $Exe sql --db $db2 --query "select r.external_target from refs r join files f on f.id=r.file_id where f.path like '%IdxVcl.dpr' and r.name_text='Application' and r.external_target is not null" 2>&1 | ForEach-Object { "$_" } }) -join "`n"
if ($ext -match 'Vcl\.Forms\.Application') {
    $out2 = (& { $ErrorActionPreference = 'Continue'; & $Exe typeat "${dpr2}:8:3" --db $db2 2>&1 | ForEach-Object { "$_" } }) -join "`n"
    Check 'typeat on a library-bound ref names Vcl.Forms.Application' ($out2 -match 'Resolved:\s+Vcl\.Forms\.Application') $out2
    Check 'typeat on a library-bound ref does NOT name AaTool.TTool.Application' (-not ($out2 -match 'AaTool\.TTool\.Application')) $out2
    # usages --name <library qname>: the project index declares nothing, the ref carries the binding.
    $u = (& { $ErrorActionPreference = 'Continue'; & $Exe usages --name Vcl.Forms.Application --db $db2 2>&1 | ForEach-Object { "$_" } }) -join "`n"
    Check 'usages --name Vcl.Forms.Application counts the library-bound read' ($u -match 'reads: 1\b') $u
} else {
    Write-Host '  [SKIP] library-bound ref: no external_target Vcl.Forms.Application (library DB $lib missing)' -ForegroundColor Yellow
}

Write-Host ''
Write-Host ("typeat index-first: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-typeat-index-first-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
