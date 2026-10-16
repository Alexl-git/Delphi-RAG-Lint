<#
  run_ambiguous_pick_stable.ps1 -- an 'ambiguous' edge must name the same
  candidate whatever order the files were indexed in (backlog #36, resolver
  1.20.0-alpha).

  THE DEFECT. When nothing could choose between candidates, PickFromMatches
  answered with the FIRST of the list, and the list is in symbol-id order --
  an accident of indexing. Re-parsing UPrimary.pas without changing a byte
  gave it new ids and moved 267 ambiguous `strin` edges to another unit, so an
  incremental database and a --rebuild one differed with no change in the
  source. The guess is now the smallest (qualified name, start line,
  signature).

  The fixture indexes the SAME sources twice, the program listing UA then UB
  in one database and UB then UA in the other -- so the two Pick overloads get
  their ids in opposite orders. Both are `overload` with the same arity, the
  case uses order does not settle (Gitea #21), so the edge stays ambiguous.

  WHAT THIS ASSERTS
    1. both databases give the call the SAME target                     <- THE FIX
    2. that target is UA.Pick (the smaller qualified name)              <- THE FIX
    3. CONTROL: the edge is [ambiguous] in both (still a guess, still marked)
    4. CONTROL: a call arity decides is [certain] and identical in both

  SCOPE: only the UNIT-LEVEL rung is reordered. A method's candidates are in
  hierarchy order (the receiver type's own member before an ancestor's) and
  that order is the right guess -- a first version of this fix sorted them by
  name too and bound `B.TransferFile` (B: TBeta) to the ancestor interface
  ICopy.TransferFile; tests\autodoc\run_doc_covered_by_dispatch.ps1 caught it
  and pins it.

  RED-CHECK: against the pre-fix build 1 FAILS (each database names the unit it
  indexed first) and 2 fails in the database that indexed UB first; 3 and 4
  pass on both builds.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
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

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

$work = Join-Path C:\TEMP "draglint_stablepick_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

function Lib([string]$name) {
  return @"
unit $name;

interface

function Pick(X: Integer): Integer; overload;
function Single$name(X, Y: Integer): Integer;

implementation

function Pick(X: Integer): Integer;
begin
  Result := X;
end;

function Single$name(X, Y: Integer): Integer;
begin
  Result := X + Y;
end;

end.
"@
}
$main = @'
unit UMain;

interface

procedure Run;

implementation

uses UA, UB;

procedure Run;
begin
  Pick(1);
  SingleUB(1, 2);
end;

end.
'@

function Build([string]$tag, [string]$first, [string]$second) {
  $dir = Join-Path $work $tag
  Write-Ascii (Join-Path $dir 'UA.pas') (Lib 'UA')
  Write-Ascii (Join-Path $dir 'UB.pas') (Lib 'UB')
  Write-Ascii (Join-Path $dir 'UMain.pas') $main
  Write-Ascii (Join-Path $dir 'P.dpr') @"
program P;

uses
  $first in '$first.pas',
  $second in '$second.pas',
  UMain in 'UMain.pas';

begin
end.
"@
  $db = Join-Path $dir 'p.sqlite'
  & $Exe index --project (Join-Path $dir 'P.dpr') --db $db *> $null
  $out = @(& $Exe find-callees --qname UMain.Run --db $db 2>$null)
  Write-Host ("  {0}: {1}" -f $tag, ($out -join ' | ')) -ForegroundColor DarkGray
  return $out
}

$ab = Build 'ab' 'UA' 'UB'
$ba = Build 'ba' 'UB' 'UA'
$pickAB = @($ab | Where-Object { $_ -match '\.Pick\s' }) -join ''
$pickBA = @($ba | Where-Object { $_ -match '\.Pick\s' }) -join ''

Write-Host ''
Check '1. both databases give Pick(1) the same target' (($pickAB -ne '') -and ($pickAB.Trim() -eq $pickBA.Trim())) "ab=[$pickAB] ba=[$pickBA]"
Check '2. that target is UA.Pick (smaller qualified name)' (($pickAB -match 'UA\.Pick') -and ($pickBA -match 'UA\.Pick')) "ab=[$pickAB] ba=[$pickBA]"
Check '3. CONTROL: still marked [ambiguous] in both' (($pickAB -match '\[ambiguous\]') -and ($pickBA -match '\[ambiguous\]')) ''
$sAB = @($ab | Where-Object { $_ -match 'SingleUB' }) -join ''
$sBA = @($ba | Where-Object { $_ -match 'SingleUB' }) -join ''
Check '4. CONTROL: an unambiguous call is [certain] and identical in both' `
  (($sAB -match 'UB\.SingleUB\s+\[certain\]') -and ($sAB.Trim() -eq $sBA.Trim())) "ab=[$sAB] ba=[$sBA]"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_stablepick_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
