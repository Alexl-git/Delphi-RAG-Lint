<#
  run_resolve_uses_order_precedence.ps1 -- a free routine exported by two used
  units binds to the unit whose uses entry comes LAST (Gitea drag-lint#21,
  resolver 1.20.0-alpha).

  THE DEFECT. LookupUnitLevelRoutine gathered every used unit's candidate and,
  when arity could not choose, answered 'ambiguous' with the FIRST candidate --
  the first unit. Delphi binds the identifier from the unit listed LAST (the
  implementation uses clause is searched before the interface one, and within
  a clause the later unit hides the earlier). On ProjectA UFSummaryReport calls
  SiteOnline with UAuxGeneric at :664 and UAuxSupport at :668: the
  edge went to UAuxGeneric, and impact on UAuxSupport.SiteOnline
  missed the caller.

  WHAT THIS ASSERTS (find-callees on UMain.TMain.Run, one project per case)
    1. implementation `uses UA, UB`   -> UB.Pick [certain]               <- THE FIX
    2. implementation `uses UB, UA`   -> UA.Pick [certain]               <- THE FIX
    3. interface uses UA, implementation uses UB -> UB (impl is later)  <- THE FIX
    4. interface uses UB, implementation uses UA -> UA                  <- THE FIX
    5. CONTROL: both Pick declared `overload` (same arity) -> still
       [ambiguous]: Delphi resolves overloads across units by signature,
       which this rung does not model
    6. CONTROL: different arity (Pick(X) in UA, Pick(X, Y) in UB), call
       Pick(1) -> UA.Pick [certain] whatever the order (arity decides first)
    7. CONTROL: the calling unit declares Pick itself -> its own [certain]

  RED-CHECK: against the pre-fix build 1 and 3 FAIL (the first unit,
  [ambiguous]); 2 and 4 fail on the confidence only (the first candidate
  happens to be the right one); 5, 6 and 7 pass on both builds.
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

$work = Join-Path C:\TEMP "draglint_usesorder_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

function LibUnit([string]$name, [string]$params, [string]$directive) {
  return @"
unit $name;

interface

function Pick($params): Integer;$directive

implementation

function Pick($params): Integer;
begin
  Result := X;
end;

end.
"@
}

# Builds one project; returns the find-callees line for the Pick edge.
function Case([string]$tag, [string]$intfUses, [string]$implUses, [string]$ua, [string]$ub, [string]$own = '') {
  $dir = Join-Path $work $tag
  Write-Ascii (Join-Path $dir 'P.dpr') @'
program P;

uses
  UA in 'UA.pas',
  UB in 'UB.pas',
  UMain in 'UMain.pas';

begin
end.
'@
  Write-Ascii (Join-Path $dir 'UA.pas') $ua
  Write-Ascii (Join-Path $dir 'UB.pas') $ub
  $iu = if ($intfUses) { "uses $intfUses;`n" } else { '' }
  $mu = if ($implUses) { "uses $implUses;`n" } else { '' }
  Write-Ascii (Join-Path $dir 'UMain.pas') @"
unit UMain;

interface

$iu
type
  TMain = class
  public
    procedure Run;
  end;

implementation

$mu
$own
procedure TMain.Run;
begin
  Pick(1);
end;

end.
"@
  $db = Join-Path $dir 'p.sqlite'
  & $Exe index --project (Join-Path $dir 'P.dpr') --db $db *> $null
  $out = @(& $Exe find-callees --qname UMain.TMain.Run --db $db 2>$null | Where-Object { $_ -match 'Pick' })
  Write-Host ("  {0}: {1}" -f $tag, ($out -join ' | ')) -ForegroundColor DarkGray
  return ($out -join ' | ')
}

$a1 = LibUnit 'UA' 'X: Integer' ''
$b1 = LibUnit 'UB' 'X: Integer' ''

Write-Host ''
Write-Host '=== uses order decides ===' -ForegroundColor Cyan
$r = Case 'c1' '' 'UA, UB' $a1 $b1
Check '1. implementation uses UA, UB -> UB.Pick [certain]' ($r -match '^\s*UB\.Pick\s+\[certain\]') $r
$r = Case 'c2' '' 'UB, UA' $a1 $b1
Check '2. implementation uses UB, UA -> UA.Pick [certain]' ($r -match '^\s*UA\.Pick\s+\[certain\]') $r
$r = Case 'c3' 'UA' 'UB' $a1 $b1
Check '3. interface UA, implementation UB -> UB.Pick [certain]' ($r -match '^\s*UB\.Pick\s+\[certain\]') $r
$r = Case 'c4' 'UB' 'UA' $a1 $b1
Check '4. interface UB, implementation UA -> UA.Pick [certain]' ($r -match '^\s*UA\.Pick\s+\[certain\]') $r

Write-Host ''
Write-Host '=== CONTROLS ===' -ForegroundColor Cyan
$r = Case 'c5' '' 'UA, UB' (LibUnit 'UA' 'X: Integer' ' overload;') (LibUnit 'UB' 'X: Integer' ' overload;')
Check '5. CONTROL: both overload -> still [ambiguous]' ($r -match 'Pick\s+\[ambiguous\]') $r
$r = Case 'c6' '' 'UA, UB' $a1 (LibUnit 'UB' 'X, Y: Integer' '')
$r6b = Case 'c6b' '' 'UB, UA' $a1 (LibUnit 'UB' 'X, Y: Integer' '')
Check '6. CONTROL: arity decides first (UA.Pick in both orders)' `
  (($r -match '^\s*UA\.Pick\s+\[certain\]') -and ($r6b -match '^\s*UA\.Pick\s+\[certain\]')) "$r || $r6b"
$own = @'
function Pick(X: Integer): Integer;
begin
  Result := -X;
end;
'@
$r = Case 'c7' '' 'UA, UB' $a1 $b1 $own
Check '7. CONTROL: own unit declares Pick -> UMain.Pick [certain]' ($r -match '^\s*UMain\.Pick\s+\[certain\]') $r

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_usesorder_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
