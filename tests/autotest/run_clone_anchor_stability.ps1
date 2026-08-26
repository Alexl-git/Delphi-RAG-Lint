<#
  run_clone_anchor_stability.ps1 -- a duplicate-code finding must not move
  because some OTHER file changed.

  THE DEFECT THIS PINS (INBOX-duplicate-code-anchor-instability.md, found
  2026-08-21 during a LoopZero run on YADF). Removing ~44 lines from
  YADF.Layout.pas repartitioned the clone classes in two files that were not
  touched: different partner lines, different token counts, and three `dl:ok`
  markers orphaned as review-marker-unused.

  WHY IT MATTERS MORE THAN IT LOOKS. `dl:ok` markers are line-bound. If an
  anchor can move because of an edit somewhere else entirely, ANY source change
  can orphan an arbitrary number of previously-recorded reviews, and a project
  can never hold a stable zero -- the owner's standing goal. On that run it cost
  two marker-shuffling rounds, each rewriting dl:ok history for untouched code.

  THE MECHANISM, confirmed 2026-08-26 by reproducing it before fixing it:
  candidates were collected by iterating Buckets.Values (a TDictionary, whose
  enumeration order depends on the table layout and therefore on how many
  distinct window hashes the WHOLE CORPUS produced), then sorted by LENGTH ONLY
  with TList.Sort -- introsort, NOT stable. The greedy coverage loop then hands
  the tokens to whichever equal-length candidate happens to come first. Fix:
  sort by (Len desc, A asc, B asc), a total order over a candidate set that is
  itself independent of bucket order.

  HOW THIS FIXTURE ISOLATES IT. uKeepA and uKeepB are written BYTE-IDENTICAL in
  every state and hold the only clones. uEdit shares no vocabulary with them, so
  it can never pair with them; its only role is to change the token population.
  Any difference in the uKeep* findings between states is instability, nothing
  else.

  WHY FIVE STATES AND NOT TWO. The first draft used one pair (filler 40 vs 0)
  and PASSED against the unfixed build -- that pair happened not to perturb the
  bucket enumeration. A vacuous guard, and visible only because it was actually
  run against the unfixed build, which is the whole point of doing that. Several
  filler sizes give the instability several chances to show, and assert the
  stronger property anyway: the uKeep findings depend on the uKeep files ALONE.

  THE POSITIVE CONTROL: every state must actually FIND clones. "No findings
  anywhere" is trivially stable and would pass with duplicate-code disabled, or
  with a fixture the low-information filter suppresses -- which is what the very
  first draft hit (a --x/--no-x dispatch chain is precisely the periodic shape
  IsLowInformation rejects by design).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-clone-anchor"
)
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }

# The clone body: varied statements, wide vocabulary. It must survive
# IsLowInformation, which rejects periodic, low-vocabulary runs by design.
$CloneBody = @(
  "  LTotal := LTotal + ComputeWeight(ASource.Alpha, ASource.Beta);"
  "  if LTotal > FUpperBound then LTotal := FUpperBound;"
  "  LScaled := Round(LTotal * FScaleFactor) + FOffsetBase;"
  "  LBuffer.Append(Format('%s=%d', [ASource.Caption, LScaled]));"
  "  if not TryResolveTarget(ASource.Handle, LTarget) then Exit(False);"
  "  LTarget.Rebind(LScaled, FUpperBound - LTotal);"
  "  FHistory.Add(TSample.Create(LTarget.Id, LScaled, Now));"
  "  while FHistory.Count > FRetentionLimit do FHistory.Delete(0);"
  "  LRatio := LScaled / (FUpperBound + FOffsetBase + 1);"
  "  if LRatio < FMinimumRatio then FlagUnderflow(ASource.Caption, LRatio);"
  "  LStatus := DescribeRatio(LRatio, FMinimumRatio, FUpperBound);"
  "  FLogger.Trace('rebind', LStatus, LTarget.Id, LScaled, LRatio);"
) -join "`r`n"

function New-CloneUnit([string]$Name, [string[]]$Procs) {
  $decls = ($Procs | ForEach-Object { "function $_(const ASource: TSourceRec): Boolean;" }) -join "`r`n"
  $bodies = ($Procs | ForEach-Object {
@"
function $_(const ASource: TSourceRec): Boolean;
var
  LTotal, LScaled: Integer;
  LRatio: Double;
  LTarget: TTarget;
  LBuffer: TStringBuilder;
  LStatus: string;
begin
  Result := True;
  LTotal := 0;
  LBuffer := TStringBuilder.Create;
$CloneBody
  LBuffer.Free;
end;
"@ }) -join "`r`n`r`n"
@"
unit $Name;

interface

type
  TTarget = class
    Id: Integer;
    procedure Rebind(A, B: Integer);
  end;
  TSourceRec = record
    Alpha, Beta, Handle: Integer;
    Caption: string;
  end;

$decls

implementation

uses System.SysUtils, System.Classes, System.Generics.Collections;

$bodies

end.
"@
}

# uEdit: a wholly different vocabulary, so it can never pair with uKeep*.
# $Filler changes the token population between states, and nothing else.
function New-OtherUnit([int]$Filler) {
  $body = (0..13 | ForEach-Object {
    "  FZeta$_ := DecodeQuadrant(APacket.Marker$_, FEpoch);`r`n  if FZeta$_ > FCeiling then FCeiling := FZeta$_;"
  }) -join "`r`n"
  $marks = (0..13 | ForEach-Object { "    Marker$_`: Integer;" }) -join "`r`n"
  $zetas = (0..13 | ForEach-Object { "  FZeta$_`: Integer;" }) -join "`r`n"
  $pad = ''
  if ($Filler -gt 0) {
    $pad = (1..$Filler | ForEach-Object {
      $m = $_ + 2; $a = $_ + 3; $n = $_ + 7
@"
function Pad$_(A: Integer): Integer;
begin
  Result := A * $m + $a;
  if Result < 0 then Result := 0;
  Result := Result mod ($n + 1);
end;
"@ }) -join "`r`n`r`n"
  }
@"
unit uEdit;

interface

type
  TPacket = record
$marks
  end;

var
$zetas
  FCeiling, FEpoch: Integer;

procedure Absorb0(const APacket: TPacket);
procedure Absorb1(const APacket: TPacket);

implementation

uses System.SysUtils;

function DecodeQuadrant(A, B: Integer): Integer;
begin
  Result := A * 3 + B;
end;

procedure Absorb0(const APacket: TPacket);
begin
$body
end;

procedure Absorb1(const APacket: TPacket);
begin
$body
end;

$pad

end.
"@
}

function Write-State([string]$State, [int]$Filler) {
  $d = Join-Path $WorkDir $State
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  $files = @{
    'uKeepA.pas' = New-CloneUnit 'uKeepA' @('AlphaOne', 'AlphaTwo')
    'uKeepB.pas' = New-CloneUnit 'uKeepB' @('BetaOne',  'BetaTwo')
    'uEdit.pas'  = New-OtherUnit $Filler
  }
  foreach ($k in $files.Keys) {
    $t = ($files[$k] -replace "`r`n", "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $d $k), $t, [System.Text.Encoding]::ASCII)
  }
  $d
}

$FILLERS = @(0, 7, 23, 40, 61)
$states  = @()
foreach ($f in $FILLERS) { $states += ,(Write-State ("S$f") $f) }

# The whole comparison is meaningless unless the keep files really are identical.
foreach ($n in 'uKeepA.pas', 'uKeepB.pas') {
  $hashes = @($states | ForEach-Object { (Get-FileHash (Join-Path $_ $n)).Hash } | Sort-Object -Unique)
  if ($hashes.Count -ne 1) {
    Write-Host "FATAL: $n differs between states -- the fixture is broken" -ForegroundColor Red; exit 2
  }
}
Write-Host ("  uKeepA.pas / uKeepB.pas byte-identical across all {0} states" -f $states.Count) -ForegroundColor DarkGray

function Keep-Findings([string]$Dir) {
  $db = Join-Path $Dir 'x.sqlite'
  & $Exe index $Dir --db $db 2>$null | Out-Null
  $out = & $Exe lint-all --db $db 2>$null
  @($out | Select-String 'duplicate-code' | Where-Object { $_ -match 'uKeep' } |
    ForEach-Object { $_.Line -replace [regex]::Escape($Dir + '\'), '' } | Sort-Object)
}

$all = @{}
foreach ($d in $states) { $all[$d] = Keep-Findings $d }

Write-Host ''
foreach ($d in $states) {
  Write-Host ("state {0}:" -f (Split-Path $d -Leaf)) -ForegroundColor DarkGray
  $all[$d] | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
}

$counts = @($states | ForEach-Object { $all[$_].Count })
$joined = @($states | ForEach-Object { ($all[$_] -join "`n") } | Sort-Object -Unique)

Write-Host ''
Write-Host 'POSITIVE CONTROL -- there must be clones to be stable ABOUT' -ForegroundColor Cyan
Check 'every state reports at least 2 uKeep clone findings' `
  ((@($counts | Where-Object { $_ -lt 2 })).Count -eq 0) ("counts=" + ($counts -join ','))

Write-Host ''
Write-Host 'An edit to an UNRELATED file must not move the anchors' -ForegroundColor Cyan
Check ("uKeep findings identical across all {0} states" -f $states.Count) ($joined.Count -eq 1)

if ((@($counts | Where-Object { $_ -lt 2 })).Count -gt 0) {
  Write-Host '  !! The control failed. "Identical" is trivially true of empty sets,' -ForegroundColor Yellow
  Write-Host '  !! so the assertion above proves NOTHING in that state.' -ForegroundColor Yellow
}

if ($joined.Count -ne 1) {
  Write-Host ("  {0} DISTINCT result sets across {1} states:" -f $joined.Count, $states.Count) -ForegroundColor Red
  foreach ($j in $joined) {
    Write-Host '    ---' -ForegroundColor Red
    ($j -split "`n") | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
  }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
