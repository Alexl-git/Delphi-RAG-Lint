<#
  run_doc_recursion_and_seealso.ps1 -- two Phase C doc features:
    (4) a RECURSIVE routine says so, from a call_edges self-loop.
    (5) <seealso> is emitted BY DEFAULT; --no-seealso turns it off.

  (4) WHY RECURSION NEEDED ITS OWN FACT
  --------------------------------------------------------------------------------
  The Calls list deliberately DROPS the symbol's own name. Two good reasons, both
  recorded at its own site: the implementation span includes the routine header,
  whose `Name(` reads as a call to itself, and "Calls: self" is noise. The side
  effect was that GENUINE recursion -- which a reader wants flagged, because it
  bounds stack depth and termination -- became invisible in the documentation.

  So it is stated as its own one-word fact instead of as a list entry.

  Detected on the SYMBOL ID, not the name. A name test would call an overload
  pair recursive, which is exactly the shape B1 had to fix in the resolver: a
  2-arg delegator calling its own 3-arg overload once produced an edge to
  itself. Overloaded is therefore the control case below, and it must NOT be
  reported recursive.

  SELF-loops only. Mutual recursion (Ping -> Pong -> Ping) needs a cycle walk
  over call_edges and is not claimed; MutualA below pins that the fact stays
  silent rather than guessing, which is the "absence over wrong" policy applied
  to a claim the engine cannot support with one edge lookup.

  (5) WHY THE SEEALSO DEFAULT FLIPPED
  --------------------------------------------------------------------------------
  The cross-references a reader most wants -- the sibling overloads -- sat
  behind an opt-in flag, so they were absent from every doc block anyone
  actually generated. Nobody passes an opt-in flag they must first know exists.
  It costs nothing to compute (call graph + sibling scan, both already indexed),
  unlike --since, which spawns git per declaration and stays opt-in.

  The --no-seealso arm is asserted too: a default that cannot be turned off is a
  worse deal than an opt-in, and this file is the only thing that would notice
  if the new switch silently did nothing.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_doc_recseealso_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$src = Join-Path $scratch 'recs.pas'
$db  = Join-Path $scratch 'r.sqlite'

Write-Ascii $src @'
unit recs;

interface

function Countdown(const AN: Integer): Integer;
function Straight(const AN: Integer): Integer;
function Overloaded(const AN: Integer): Integer; overload;
function Overloaded(const AN, AM: Integer): Integer; overload;
procedure MutualA;
procedure MutualB;

implementation

{ genuine self-recursion }
function Countdown(const AN: Integer): Integer;
begin
  if AN <= 0 then
    Result:= 0
  else
    Result:= Countdown(AN - 1);
end;

{ control: no recursion at all }
function Straight(const AN: Integer): Integer;
begin
  Result:= AN + 1;
end;

{ CONTROL: a delegator calling its own SIBLING OVERLOAD is not recursion }
function Overloaded(const AN: Integer): Integer;
begin
  Result:= Overloaded(AN, 0);
end;

function Overloaded(const AN, AM: Integer): Integer;
begin
  Result:= AN + AM;
end;

{ CONTROL: mutual recursion is deliberately NOT claimed }
procedure MutualA;
begin
  MutualB;
end;

procedure MutualB;
begin
  MutualA;
end;

end.
'@

function Get-Block([string]$qname, [string[]]$extraArgs) {
  $argv = @('document','--qname',$qname,'--db',$db) + $extraArgs
  return (((& $exePath @argv 2>$null) -join "`n") -replace '</?para>','')
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # ---- (4) recursion -------------------------------------------------------
  $cd = Get-Block 'recs.Countdown' @()
  Write-Host "--- Countdown ---`n$cd" -ForegroundColor DarkGray
  Check 'RECURSION: a self-recursive function is marked Recursive' `
    ($cd -match '(?m)^\s*///\s*Recursive\s*$') $cd

  $st = Get-Block 'recs.Straight' @()
  Check 'CONTROL: a non-recursive function is NOT marked Recursive' `
    (-not ($st -match 'Recursive')) $st

  # THE DISCRIMINATOR: overload delegation is not recursion. This is what a
  # name-keyed implementation would get wrong, and nothing else here would.
  $ov = Get-Block 'recs.Overloaded' @()
  Write-Host "--- Overloaded ---`n$ov" -ForegroundColor DarkGray
  Check 'CONTROL: calling a SIBLING OVERLOAD is not reported as recursion' `
    (-not ($ov -match 'Recursive')) $ov

  $ma = Get-Block 'recs.MutualA' @()
  Check 'CONTROL: MUTUAL recursion is not claimed (self-loops only)' `
    (-not ($ma -match 'Recursive')) $ma

  # ---- (5) seealso ---------------------------------------------------------
  # Overloaded has a sibling, so it is the declaration with a related set.
  Check 'SEEALSO: <seealso cref> is emitted with NO flag at all (on by default)' `
    ($ov -match '<seealso cref=') $ov

  $ovOff = Get-Block 'recs.Overloaded' @('--no-seealso')
  Check 'SEEALSO: --no-seealso suppresses it' `
    (-not ($ovOff -match '<seealso cref=')) $ovOff

  # The explicit flag must still be accepted -- existing scripts pass it.
  $ovOn = Get-Block 'recs.Overloaded' @('--seealso')
  Check 'SEEALSO: the legacy --seealso flag is still accepted and still emits' `
    ($ovOn -match '<seealso cref=') $ovOn

  # CONTROL: --no-seealso must not be a blanket "emit nothing" switch.
  Check 'CONTROL: --no-seealso removes ONLY the seealso lines, the block survives' `
    ($ovOff -match 'drag-lint:auto BEGIN') $ovOff
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
