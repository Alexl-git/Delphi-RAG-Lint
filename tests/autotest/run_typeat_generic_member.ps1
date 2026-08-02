# drag-lint typeat GENERIC / INHERITED member resolution regression test.
#
# Bug (live IDE): hovering an instance member that is inherited or lives on a
# generic base (e.g. ATokens.Count where TTokenList = TList<TToken>) mis-resolved
# to an arbitrary same-named symbol, because TTypeAtResolver only checked DIRECT
# children of the LHS type and was single-store (the generic base lives in a
# separate library DB).
#
# This test is HERMETIC: two synthetic DBs stand in for (project DB, library DB).
#
# Usage: pwsh -File tests/autotest/run_typeat_generic_member.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-typeat-generic"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- LIBRARY db (db B): a generic base class with a Count property + an ancestor.
$libDir = "$WorkDir\lib"; New-Item -ItemType Directory $libDir | Out-Null
@'
unit MyColl;

interface

type
  TMyEnumerable<T> = class
  public
    function ToArray: TArray<T>;
  end;

  TMyList<T> = class(TMyEnumerable<T>)
  public
    property Count: NativeInt read GetCount;
  end;

implementation

end.
'@ | Set-Content "$libDir\MyColl.pas" -Encoding ascii
$dbLib = "$WorkDir\lib.sqlite"
$idxL = & $Exe index $libDir --db $dbLib 2>&1
Check 'index lib exits 0' ($LASTEXITCODE -eq 0) (($idxL | Select-Object -Last 1))

# --- PROJECT db (db A): the alias + a consumer that does ATokens.Count.
$prjDir = "$WorkDir\prj"; New-Item -ItemType Directory $prjDir | Out-Null
$consumer = "$prjDir\Consumer.pas"
@'
unit Consumer;

interface

type
  TThing = class end;
  TThingList = TMyList<TThing>;

  TUser = class
  public
    procedure Use;
  end;

var
  GGlobalOnlyInPrj: Integer;

implementation

procedure TUser.Use;
var
  ATokens: TThingList;
  N: NativeInt;
begin
  N := ATokens.Count;
  GGlobalOnlyInPrj := N;
end;

end.
'@ | Set-Content $consumer -Encoding ascii
$dbPrj = "$WorkDir\prj.sqlite"
$idxP = & $Exe index $prjDir --db $dbPrj 2>&1
Check 'index prj exits 0' ($LASTEXITCODE -eq 0) (($idxP | Select-Object -Last 1))

$lines = Get-Content $consumer

# --- Task 1a: multi-store plumbing + PRIMARY-store selection. dbLib is passed
#     AFTER dbPrj; the OLD single-store typeat used the LAST --db (dbLib) and the
#     project-local ATokens went unresolved. Now the store OWNING the file (dbPrj)
#     is primary, so the local resolves. Guards the original "last --db wins" bug.
$aLineText = '  N := ATokens.Count;'
$aIdx = [Array]::IndexOf($lines, $aLineText); Check 'located ATokens line' ($aIdx -ge 0)
$aLine = $aIdx + 1
$aCol  = $aLineText.IndexOf('ATokens') + 1
$aOut  = (& $Exe typeat "${consumer}:${aLine}:${aCol}" --db $dbPrj --db $dbLib --format json 2>&1) -join "`n"
Check 'local resolves with dbLib passed last (primary-store selection)' `
    ($aOut -match '"resolved":"Consumer\.TUser\.Use\.ATokens"') $aOut

# --- Task 1b: FLOOR -- ATokens.Count is NOT a direct child of the alias; before
#     Tasks 2-3 it must report owner_type_fallback:true (honest), NOT a wrong symbol.
$cLineText = '  N := ATokens.Count;'
$cIdx = [Array]::IndexOf($lines, $cLineText); Check 'located Count line' ($cIdx -ge 0)
$cLine = $cIdx + 1
$cCol  = $cLineText.IndexOf('.Count') + 2   # 1-based col ON the 'C' of Count
$cOut  = (& $Exe typeat "${consumer}:${cLine}:${cCol}" --db $dbPrj --db $dbLib --format json 2>&1) -join "`n"
# --- Task 3: ATokens.Count -> the generic base's Count property, resolved
#     CROSS-DB (the base TMyList<T> lives in dbLib, the alias in dbPrj).
Check 'ATokens.Count resolves to the generic base Count property' `
    ($cOut -match '"resolved":"MyColl\.TMyList<T>\.Count"') $cOut
Check 'and shows the real signature (NativeInt)' ($cOut -match '"signature":"NativeInt"') $cOut

# --- Floor stays honest for a genuinely-absent member on a generic alias.
@'
unit NoSuch;

interface

type
  TThing2 = class end;
  TList2 = TMyList<TThing2>;

  TU2 = class
    procedure P;
  end;

implementation

procedure TU2.P;
var
  L: TList2;
begin
  L.Nonexistent;
end;

end.
'@ | Set-Content "$prjDir\NoSuch.pas" -Encoding ascii
& $Exe index $prjDir --db $dbPrj 2>&1 | Out-Null
$ns = "$prjDir\NoSuch.pas"; $nsLines = Get-Content $ns
$nsText = '  L.Nonexistent;'
$nsLine = [Array]::IndexOf($nsLines, $nsText) + 1
$nsCol  = $nsText.IndexOf('.Nonexistent') + 2
$nsOut  = (& $Exe typeat "${ns}:${nsLine}:${nsCol}" --db $dbPrj --db $dbLib --format json 2>&1) -join "`n"
Check 'absent member -> honest owner-type floor (not a wrong symbol)' `
    ($nsOut -match '"owner_type_fallback":true') $nsOut

# --- Task 2: project-internal inheritance -- member on a plain (non-generic)
#     ancestor resolves via the same-store ancestry walk.
@'
unit Inh;

interface

type
  TBase = class
  public
    procedure BaseOp;
  end;

  TDerived = class(TBase)
  public
    procedure DerivedOp;
  end;

implementation

procedure TBase.BaseOp; begin end;

procedure TDerived.DerivedOp;
var
  D: TDerived;
begin
  D.BaseOp;
end;

end.
'@ | Set-Content "$prjDir\Inh.pas" -Encoding ascii
$idxP2 = & $Exe index $prjDir --db $dbPrj 2>&1   # incremental reindex of prj dir
Check 'reindex prj (with Inh) exits 0' ($LASTEXITCODE -eq 0) (($idxP2 | Select-Object -Last 1))

$inh = "$prjDir\Inh.pas"
$inhLines = Get-Content $inh
$inhCallText = '  D.BaseOp;'
$inhIdx = [Array]::IndexOf($inhLines, $inhCallText); Check 'located D.BaseOp line' ($inhIdx -ge 0)
$inhLine = $inhIdx + 1
$inhCol  = $inhCallText.IndexOf('.BaseOp') + 2
$inhOut  = (& $Exe typeat "${inh}:${inhLine}:${inhCol}" --db $dbPrj --db $dbLib --format json 2>&1) -join "`n"
Check 'inherited member resolves to the ancestor method' `
    ($inhOut -match '"resolved":"Inh\.TBase\.BaseOp"') $inhOut

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
