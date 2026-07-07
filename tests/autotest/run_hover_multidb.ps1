# drag-lint hover multi-db regression test (v0.94.1).
#
# BUG: `hover --qname` used only ONE --db (the LAST one the arg parser saw),
# not all of them. The IDE passes several --db values (project index + SQL index
# + platform library index). When the hovered symbol lived in an EARLIER db, the
# CLI returned "No symbol matched" -> FetchHoverModel got exit 1 -> the IDE
# silently fell back to the plain string hover popup (no colors / no structured
# view). Root cause of the "old-fashioned format" the user saw in live smoke.
#
# FIX: DoHover now iterates ResolveConsumerDbs(AArgs) (ALL --db paths) and uses
# the first db that contains the qname -- mirroring how query find-callers walks
# multiple dbs.
#
# This test indexes a symbol into ONE db, then hovers it with that db in EVERY
# position of a 3-db list (first / middle / last) plus decoy empty dbs, and
# asserts the JSON model comes back each time. Before the fix, "target db not
# last" returned "No symbol matched".
#
# Usage: pwsh -File tests/autotest/run_hover_multidb.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-hover-multidb"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $s = if ($Ok) {'PASS'} else {'FAIL'}
    $c = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
    if (-not $Ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- fixture: a unit with a function that mines two distinct returns ---
$srcTarget = "$WorkDir\target"
New-Item -ItemType Directory $srcTarget | Out-Null
@'
unit MultiDbFixture;
interface
function GrabDIB(const AWidth: integer): boolean;
implementation
function GrabDIB(const AWidth: integer): boolean;
var rlines: integer;
begin
  Result := False;
  rlines := AWidth;
  Result := rlines <> 0;
end;
end.
'@ | Set-Content "$srcTarget\MultiDbFixture.pas" -Encoding ascii

# --- a decoy source (different symbols) for the other dbs ---
$srcDecoy = "$WorkDir\decoy"
New-Item -ItemType Directory $srcDecoy | Out-Null
@'
unit DecoyFixture;
interface
procedure Nothing;
implementation
procedure Nothing; begin end;
end.
'@ | Set-Content "$srcDecoy\DecoyFixture.pas" -Encoding ascii

# --- index target into targetDb, decoy into two other dbs ---
$targetDb = "$WorkDir\target.sqlite"
$decoyDb1 = "$WorkDir\decoy1.sqlite"
$decoyDb2 = "$WorkDir\decoy2.sqlite"
& $Exe index $srcTarget --db $targetDb | Out-Null
Check 'target db built' (Test-Path $targetDb)
& $Exe index $srcDecoy --db $decoyDb1 | Out-Null
& $Exe index $srcDecoy --db $decoyDb2 | Out-Null
Check 'decoy dbs built' ((Test-Path $decoyDb1) -and (Test-Path $decoyDb2))

# helper: run hover --json with a given ordered db list, return the raw stdout+stderr
function HoverJson([string[]]$Dbs) {
    $dbArgs = @()
    foreach ($d in $Dbs) { $dbArgs += @('--db', $d) }
    return (& $Exe hover --qname MultiDbFixture.GrabDIB @dbArgs --format json 2>&1) -join "`n"
}

# extract just the {...} object (mirror the plugin's slice) so trailing banners
# don't fool the assertion.
function JsonObj([string]$s) {
    $i = $s.IndexOf('{'); if ($i -lt 0) { return '' }
    return $s.Substring($i)
}

# --- target db in each position of a 3-db list ---
$first  = JsonObj (HoverJson @($targetDb, $decoyDb1, $decoyDb2))
Check 'target FIRST resolves'  ($first  -match '"qname":"MultiDbFixture\.GrabDIB"') $first
$middle = JsonObj (HoverJson @($decoyDb1, $targetDb, $decoyDb2))
Check 'target MIDDLE resolves' ($middle -match '"qname":"MultiDbFixture\.GrabDIB"') $middle
# THE REGRESSION CASE: before the fix, only the LAST db was used, so target-first
# (library-style db last) returned "No symbol matched". Now target can be first.
$last   = JsonObj (HoverJson @($decoyDb1, $decoyDb2, $targetDb))
Check 'target LAST resolves'   ($last   -match '"qname":"MultiDbFixture\.GrabDIB"') $last

# --- the mined returns come through in all positions (the structured view data) ---
Check 'returns mined (False)'        ($first -match 'False')        $first
Check 'returns mined (rlines <> 0)'  ($first -match 'rlines <> 0')  $first
Check 'return_type boolean'          ($first -match '(?i)"return_type":"boolean"') $first
Check 'params carry name+type'       ($first -match '"name":"AWidth"') $first

# --- a genuinely-absent symbol still fails cleanly (exit 1, no crash) ---
$absent = HoverJson @($decoyDb1, $decoyDb2)  # target NOT in this list
Check 'absent symbol -> No symbol matched' ($absent -match 'No symbol matched') $absent

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
