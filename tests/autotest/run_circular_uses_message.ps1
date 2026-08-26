# Guard: circular-uses gives advice that MATCHES the cycle it found.
#
# The rule was behaving as designed -- it reports implementation-section cycles
# as a coupling smell and its header says so -- but its ADVICE was wrong:
#
#   "break the cycle (extract shared code or move a use to the implementation section)"
#
# A pure interface-section cycle does not compile, so a cycle in a BUILDING
# project has already been routed through an implementation-section `uses`.
# Telling its author to move a use to the implementation section is telling them
# to do the thing they have already done. `DRagLint.Doc.Harvest` did exactly
# that, with a comment explaining why, and was then advised to do it again.
#
# THE CONTROL IS THE WHOLE POINT. Asserting only "the implementation-cycle
# message appears" would pass against a build that emitted that message
# unconditionally -- which would then be wrong for the other case instead. So
# both branches are exercised, on two fixtures that differ ONLY in which section
# carries the back-edge:
#
#   IMPL fixture -- uB's back-edge to uA is in its IMPLEMENTATION uses. Legal
#                   Delphi, compiles, and must get the "already routes through"
#                   wording with extraction as the only remedy.
#   INTF fixture -- both edges are in INTERFACE uses. Not legal Delphi (the
#                   linter does not compile, it parses), so no implementation
#                   edge exists and the original advice is still correct.
#
# Usage: pwsh -File tests/autotest/run_circular_uses_message.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-circular-msg"
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
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# ---- IMPL fixture: the back-edge lives in an implementation uses -------------
$impl = Join-Path $WorkDir 'impl'
New-Item -ItemType Directory $impl | Out-Null
Write-Ascii (Join-Path $impl 'uA.pas') @'
unit uA;

interface

uses
  uB;

type
  TA = class
  end;

implementation

end.
'@
Write-Ascii (Join-Path $impl 'uB.pas') @'
unit uB;

interface

type
  TB = class
  end;

implementation

uses
  uA;

end.
'@

# ---- INTF fixture: both edges are interface uses -----------------------------
$intf = Join-Path $WorkDir 'intf'
New-Item -ItemType Directory $intf | Out-Null
Write-Ascii (Join-Path $intf 'uC.pas') @'
unit uC;

interface

uses
  uD;

type
  TC = class
  end;

implementation

end.
'@
Write-Ascii (Join-Path $intf 'uD.pas') @'
unit uD;

interface

uses
  uC;

type
  TD = class
  end;

implementation

end.
'@

function CycleMessage([string]$Dir, [string]$DbName) {
  $db = Join-Path $WorkDir $DbName
  & $Exe index $Dir --db $db 2>&1 | Out-Null
  return ((& $Exe lint-project --db $db --rule circular-uses) -join "`n")
}

$implOut = CycleMessage $impl 'impl.sqlite'
$intfOut = CycleMessage $intf 'intf.sqlite'
Write-Host ''
Write-Host ('  IMPL: ' + (($implOut -split "`n" | Select-String 'circular-uses') -join ' ')) -ForegroundColor DarkGray
Write-Host ('  INTF: ' + (($intfOut -split "`n" | Select-String 'circular-uses') -join ' ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'CONTROL -- the rule fires on both fixtures at all' -ForegroundColor Cyan
Check 'implementation-section cycle IS reported' ($implOut -match 'circular-uses') "out=$implOut"
Check 'interface-section cycle IS reported'      ($intfOut -match 'circular-uses') "out=$intfOut"

Write-Host ''
Write-Host 'THE FIX -- advice matches the cycle' -ForegroundColor Cyan
Check 'impl cycle says it already routes through an implementation uses' `
    ($implOut -match 'already routes through an implementation-section uses') "out=$implOut"
Check 'impl cycle does NOT repeat the advice already taken' `
    (-not ($implOut -match 'extract shared code or move a use to the implementation section')) "out=$implOut"

Write-Host ''
Write-Host 'THE CONTROL BRANCH -- proves the wording is chosen by DATA, not hardcoded' -ForegroundColor Cyan
Check 'interface-only cycle keeps the original advice' `
    ($intfOut -match 'extract shared code or move a use to the implementation section') "out=$intfOut"
Check 'interface-only cycle does NOT claim it already routes through implementation' `
    (-not ($intfOut -match 'already routes through an implementation-section uses')) "out=$intfOut"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
