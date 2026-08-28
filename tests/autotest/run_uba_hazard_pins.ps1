<#
  run_uba_hazard_pins.ps1 -- docs\PLAN-SESSION-47.md T5
  (docs\INBOX-used-before-assignment-false-positives.md)

  Companion to run_uba_param_modes.ps1. That guard's header names FOUR
  unsoundness channels found while making a bare by-value argument count as a
  read (1ae5c04). Channel 1 (pointer-typed value params) is pinned there as S3.
  Channels 3 and 4 were described in PROSE ONLY -- no executable pin -- which is
  what this file adds, before T6 starts churning exactly that code.

  S4 -- INTRINSICS ANSWER ONLY IN THE var/out DIRECTION.
  IntrinsicSignature is documented "for display". `SizeOf(X)` parses as a value
  parameter but is a COMPILE-TIME TYPE QUERY that does not read X. Trusting it
  as a read added 402 findings on ORM3, including the perfect self-refutation
  `FillChar(StartupInfo, SizeOf(StartupInfo), 0)` -- reported on the very line
  that zeroes the record.

  S5 -- ONLY A FREE ROUTINE MAY ANSWER A BARE-NAME CALL.
  Allowing methods to answer made resolution a NAME MATCH: `New(Data)` matched
  PDFlibSmartAccess.TSmartPDFWriter.New. The recorded lesson is sharper than
  "be careful" -- an "all matches must agree" rule did NOT save this, because
  there was exactly ONE match and it was wrong. Agreement is not resolution.

  The fixture makes the wrong answer OBSERVABLE rather than merely possible: the
  colliding method takes a `const` parameter, so if it were consulted the local
  would read as a never-assigned READ and surface as a false
  used-before-assignment. Silence is therefore evidence, not absence.

  RED PROTOCOL -- DEVIATION, STATED HONESTLY. These pin behaviour that is
  already correct, so they cannot go red against a preserved older binary: that
  binary contains the fix too (1ae5c04 predates it). Red was demonstrated by
  MUTATION -- letting intrinsics answer in the value direction, and letting
  methods answer bare-name calls, in a throwaway build -- observed, then
  reverted. See the commit message for the observed output.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_uba_hazard_pins"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$fixture = @'
unit uUbaHazards;

interface

uses
  System.SysUtils;

type
  { A METHOD whose name collides with the RTL intrinsic New, declared with a
    const parameter ON PURPOSE. If the bare-name lookup consults methods, this
    one answers "read", and the never-assigned local below is reported. }
  TCollide = class
    class procedure New(const pIn: Integer);
  end;

procedure IntrinsicIsNotARead;
procedure IntrinsicControl;
procedure BareNameMethodMustNotAnswer;
procedure FreeRoutineIsConsulted;
procedure FreeRoutineControl;

implementation

class procedure TCollide.New(const pIn: Integer);
begin
end;

{ A free routine with a var parameter: this one MUST be consulted. }
procedure Grab(var pOut: Integer);
begin
  pOut:= 1;
end;

{ Same name shape, const parameter: a read, so its argument must be reported. }
procedure Peek(const pIn: Integer);
begin
end;

{ S4: SizeOf is a compile-time type query. uHazA is never assigned and must NOT
  be reported -- SizeOf does not read it. }
procedure IntrinsicIsNotARead;
var
  uHazA: Integer;
  uSize: Integer;
begin
  uSize:= SizeOf(uHazA);
  Writeln(uSize);
end;

{ S4 CONTROL: the same never-assigned local in a genuine read position MUST be
  reported. Without this, S4 passes for a build where the rule died. }
procedure IntrinsicControl;
var
  uHazB: Integer;
  uCopy: Integer;
begin
  uCopy:= uHazB;
  Writeln(uCopy);
end;

{ S5: the RTL intrinsic New DEFINES uHazC. A method named New must not answer. }
procedure BareNameMethodMustNotAnswer;
var
  uHazC: PInteger;
begin
  New(uHazC);
  uHazC^:= 1;
  Dispose(uHazC);
end;

{ S5 CONTROL a: a FREE routine with a var parameter IS consulted, so its
  argument is a def and must stay silent. This is what proves the bare-name
  mechanism is alive rather than switched off wholesale. }
procedure FreeRoutineIsConsulted;
var
  uHazD: Integer;
begin
  Grab(uHazD);
  Writeln(uHazD);
end;

{ S5 CONTROL b: a FREE routine with a const parameter is a READ, so a
  never-assigned argument MUST be reported. }
procedure FreeRoutineControl;
var
  uHazE: Integer;
begin
  Peek(uHazE);
end;

end.
'@

$file = Join-Path $WorkDir 'uUbaHazards.pas'
Write-Ascii $file $fixture

# A STORE IS REQUIRED, and finding that out is why S5d exists. The bare-name
# channel resolves a callee's SIGNATURE through the index; store-free there is
# no signature to find, every bare call answers pmUnknown, and nothing is
# consulted at all. Run that way, S5 and S5c both pass on silence that means
# "I did not look" -- the precise failure mode this repo keeps re-learning.
# S5d is what exposed it: a const-parameter free routine MUST be reported, and
# store-free it was not.
$db  = Join-Path $WorkDir 'hazards.sqlite'
$idx = & $exePath index $WorkDir --db $db 2>&1 | Out-String
Check 'SANITY: fixture indexed with no errors' `
      ($LASTEXITCODE -eq 0 -and $idx -notmatch '\b[1-9]\d* errors\b') $idx

$out = & $exePath lint $file --db $db --rules-dir $rules 2>&1 | Out-String

function Reported($text, $local) {
  @($text -split "`r?`n" |
      Where-Object { $_ -match 'used-before-assignment' -and $_ -match ('"' + [regex]::Escape($local) + '"') }).Count
}

Check 'VACUITY: the run produced used-before-assignment findings at all' `
      (@($out -split "`r?`n" | Where-Object { $_ -match 'used-before-assignment' }).Count -ge 1) `
      "no findings of this rule -- every silence assertion below would be meaningless"

Check 'S4  SizeOf(X) is NOT a read -- the never-assigned local stays silent' `
      ((Reported $out 'uHazA') -eq 0) `
      "SizeOf is a compile-time type query; reporting it is the +402-finding regression"

Check 'S4c CONTROL: the same local in a genuine read position IS reported' `
      ((Reported $out 'uHazB') -ge 1) `
      "if this is 0 the rule is not firing at all and S4 proves nothing"

Check 'S5  a METHOD may not answer a bare-name call' `
      ((Reported $out 'uHazC') -eq 0) `
      "TCollide.New takes a const param; if methods answer bare names it reads as a never-assigned READ"

Check 'S5c CONTROL a: a FREE routine with a var param IS consulted (def, silent)' `
      ((Reported $out 'uHazD') -eq 0) `
      "if this is reported, bare-name resolution is switched off wholesale rather than restricted to free routines"

Check 'S5d CONTROL b: a FREE routine with a const param IS consulted (read, reported)' `
      ((Reported $out 'uHazE') -ge 1) `
      "this is what distinguishes 'free routines are consulted' from 'nothing is consulted' -- without it S5 and S5c both pass for a dead mechanism"

Write-Host ''
if ($fail) { Write-Host 'run_uba_hazard_pins: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_uba_hazard_pins: PASS' -ForegroundColor Green
exit 0
