# drag-lint hover/typeat scope regression test (v0.94, hover scope fix).
#
# Bug: hovering a routine's PARAMETER or LOCAL VARIABLE resolved to an
# unrelated same-named GLOBAL symbol instead of the in-scope param/local.
# Root cause: TTypeAtResolver.Resolve's bare-identifier branch called
# FindSymbolByExactNameAnywhere (a flat whole-DB name lookup, Arr[0]) with
# no scope/enclosing-routine filter.
#
# Fix: before the flat lookup, look up the token as a param/local of the
# routine whose IMPLEMENTATION BODY span (impl_start_line..impl_end_line)
# contains the cursor line (FindEnclosingRoutineByImpl + FindChildSymbolByName).
#
# This fixture reproduces the shape of the real bug (BASICSF.pas Pad0/N):
# a field N on a class AND a local routine Shadow with its own param N.
# Hovering the param N inside Shadow's body must resolve to Shadow's N
# (a param), NOT TFoo.N (the field).
#
# Usage: pwsh -File tests/autotest/run_typeat_scope.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-typeat-scope"
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

# --- fixture: a field N on TFoo, and a free function Shadow(const N: integer)
#     whose own param N must win when hovered inside Shadow's body. ---
$srcDir = "$WorkDir\src"
New-Item -ItemType Directory $srcDir | Out-Null
$pas = "$srcDir\ScopeFixture.pas"
@'
unit ScopeFixture;

interface

type
  TFoo = class
  public
    N: TDateTime;
    procedure Touch;
  end;

function Shadow(const N, DIGITS: integer): string;

implementation

uses
  System.SysUtils;

procedure TFoo.Touch;
begin
  N := Now;
end;

function Shadow(const N, DIGITS: integer): string;
var
  S1: string;
begin
  S1 := StringOfChar('0', DIGITS) + IntToStr(N);
  Result := Copy(S1, Length(S1) - DIGITS + 1, DIGITS);
end;

end.
'@ | Set-Content $pas -Encoding ascii

# --- index it ---
$db = "$WorkDir\scope.sqlite"
$idxOut = & $Exe index $srcDir --db $db 2>&1
Check 'index fixture exits 0' ($LASTEXITCODE -eq 0) (($idxOut | Select-Object -Last 1))
Check 'db created' (Test-Path $db)

# --- locate the two probe lines by content (1-based line numbers) ---
$fixtureLines = Get-Content $pas
$sigLineText  = 'function Shadow(const N, DIGITS: integer): string;'
$bodyLineText = "  S1 := StringOfChar('0', DIGITS) + IntToStr(N);"
$sigLineIdx   = [Array]::IndexOf($fixtureLines, $sigLineText)
$bodyLineIdx  = [Array]::IndexOf($fixtureLines, $bodyLineText)
Check 'located Shadow signature line in fixture' ($sigLineIdx -ge 0)
Check 'located Shadow body line in fixture'      ($bodyLineIdx -ge 0)
$sigLine  = $sigLineIdx + 1
$bodyLine = $bodyLineIdx + 1

# --- signature: const N ---
$sigCol  = $sigLineText.IndexOf('const N') + 'const '.Length + 1
$sigOut  = (& $Exe typeat "${pas}:${sigLine}:${sigCol}" --db $db 2>&1) -join "`n"
Check 'signature N resolves to Shadow.N (not TFoo.N)' `
    ($sigOut -match 'Resolved:\s+ScopeFixture\.Shadow\.N\s*(\r|\n|$)') `
    $sigOut
Check 'signature N does NOT resolve to TFoo.N' `
    (-not ($sigOut -match 'ScopeFixture\.TFoo\.N')) `
    $sigOut

# --- body: N inside IntToStr(N) ---
$bodyCol  = $bodyLineText.IndexOf('IntToStr(N)') + 'IntToStr('.Length + 1
$bodyOut  = (& $Exe typeat "${pas}:${bodyLine}:${bodyCol}" --db $db 2>&1) -join "`n"
Check 'body N resolves to Shadow.N (not TFoo.N)' `
    ($bodyOut -match 'Resolved:\s+ScopeFixture\.Shadow\.N\s*(\r|\n|$)') `
    $bodyOut
Check 'body N does NOT resolve to TFoo.N' `
    (-not ($bodyOut -match 'ScopeFixture\.TFoo\.N')) `
    $bodyOut

# --- sanity: TFoo.N itself is still directly queryable (fix must not delete it) ---
$qOut = (& $Exe query --qname ScopeFixture.TFoo.N --db $db 2>&1) -join "`n"
Check 'TFoo.N (the field) is still indexed' ($qOut -match 'ScopeFixture\.TFoo\.N') $qOut

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
