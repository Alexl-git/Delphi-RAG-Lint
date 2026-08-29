<#
  run_defasgn_gen_memo.ps1 --
  docs\INBOX-flowchecker-is-half-of-lint-all.md

  TDefiniteAssignment.Transfer is MEMOISED per block. This guards the property
  that makes that legal, and it guards it by re-deriving the answer rather than
  by comparing outputs -- because no corpus A/B can establish it.

  WHAT WAS MEASURED (session 47, this repo, 110 files):

    of which solver     85.26 s  (150820 block(s), 360267 visit(s) = 2.389/block)
      of which Transfer 84.89 s  (99.6% of the solver)
      TDefiniteAssignment  59.44 s  (2.880 visit(s)/block, Transfer 99.7%)
      TEscape              24.79 s  (1.156 visit(s)/block, Transfer 99.9%)

  Definite-assignment walks each block's AST 2.880 times and 99.7% of its cost
  is that walk, so 65% of it was recomputing a value that could not have
  changed. TEscape is at 1.156 and is deliberately NOT memoised: it would win
  13%, and its transfer is not gen-only.

  THE PROPERTY. After copying AIn, every write in TransferDirect is `:= True`,
  and the SET of indices written depends only on the block -- never on AIn. So
  Transfer(B, In) = In OR Gen(B). Add a `:= False`, or make a write depend on
  AIn, and the memo silently produces a WRONG FIXPOINT: fewer findings, all of
  them plausible, nothing failing. That is this repo's canonical failure mode,
  so the check is a self-check inside the engine (DRAGLINT_VERIFY_GEN=1) and
  this runner turns it on.

  AND THE CHECK ITSELF HAS A POSITIVE CONTROL. A verifier that has never been
  seen to fail is indistinguishable from one that is not wired up -- this repo
  has shipped a guard that passed by comparing two EMPTY sets, and a scrub whose
  mismatch branch returned its raw input and so never ran at all. The property
  under test lives inside one source file, so the fault cannot be planted from
  out here; DRAGLINT_VERIFY_GEN=break makes the engine corrupt its own checked
  value, and V3 fails if that does NOT get caught.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_defasgn_genmemo"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

# The fixture must RE-VISIT blocks, or V2 is vacuous: with one visit per block
# the memo and a direct transfer are trivially equal and the check proves
# nothing. Loops (back edges) are what force re-enqueues, so every routine here
# has one. V1 asserts the re-visit ratio actually exceeded 1.
Write-Ascii (Join-Path $src 'uGen.pas') @'
unit uGen;

interface

function Accumulate(ACount: Integer): Integer;
function PickLabel(AKind: Integer): string;
procedure Sweep(AFlag: Boolean);

implementation

uses
  System.SysUtils;

function Accumulate(ACount: Integer): Integer;
var
  I, Total, Seen: Integer;
begin
  Total := 0;
  for I := 0 to ACount - 1 do
  begin
    if I mod 2 = 0 then
      Seen := I
    else
      Total := Total + I;
    if Total > 100 then
      Total := Total - Seen;
  end;
  Result := Total;
end;

function PickLabel(AKind: Integer): string;
var
  S: string;
  I: Integer;
begin
  for I := 0 to AKind do
  begin
    if I = 3 then
      S := 'three';
    if I = 7 then
      Result := S;
  end;
  Result := 'none';
end;

procedure Sweep(AFlag: Boolean);
var
  Buf: string;
  N: Integer;
begin
  N := 0;
  while N < 10 do
  begin
    if AFlag then
      Buf := IntToStr(N);
    Inc(N);
  end;
  if Buf = '' then
    Exit;
end;

end.
'@

$db = Join-Path $WorkDir 'gen.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null

function RunLint([string]$VerifyMode, [bool]$Profile) {
  Remove-Item Env:\DRAGLINT_VERIFY_GEN -ErrorAction SilentlyContinue
  Remove-Item Env:\DRAGLINT_PROFILE    -ErrorAction SilentlyContinue
  if ($VerifyMode) { $env:DRAGLINT_VERIFY_GEN = $VerifyMode }
  if ($Profile)    { $env:DRAGLINT_PROFILE    = '1' }
  try   { return (& $exePath lint-all --db $db --rules-dir $rules 2>&1 | Out-String) }
  finally {
    Remove-Item Env:\DRAGLINT_VERIFY_GEN -ErrorAction SilentlyContinue
    Remove-Item Env:\DRAGLINT_PROFILE    -ErrorAction SilentlyContinue
  }
}
function FindingsOnly([string]$T) {
  ,@($T -split "`r?`n" | Where-Object { $_ -match ':\d+:\d+\s+\[(error|warning|info|hint)\]' } | Sort-Object)
}

Push-Location C:\TEMP
try {
  $plain     = RunLint $null  $false
  $plainProf = RunLint $null  $true
  $verified  = RunLint '1'    $false
  $broken    = RunLint 'break' $false

  $fPlain    = FindingsOnly $plain
  $fVerified = FindingsOnly $verified

  # ---- V1: the fixture is not vacuous -------------------------------------
  Check 'V1 the fixture produces findings at all' ($fPlain.Count -gt 0) `
        'no findings -- V2 would be comparing two empty sets, which is how a guard in this repo passed against an unfixed build'

  Check 'V1 definite-assignment actually ran (a flow finding is present)' `
        ($plain -match 'used-before-assignment|function-result-not-set|overwrite-before-read') `
        'no definite-assignment-driven rule fired, so the memoised path may never have been entered'

  $ratio = $null
  if ($plainProf -match 'TDefiniteAssignment\s+[0-9.]+ s\s+\(([0-9.]+) visit') { $ratio = [double]$Matches[1] }
  Check 'V1 the per-lattice profile line was parsed' ($null -ne $ratio) `
        'no TDefiniteAssignment line under DRAGLINT_PROFILE -- the solver counters are gone'
  if ($null -ne $ratio) {
    Check "V1 the fixture RE-VISITS blocks (ratio $ratio > 1.0)" ($ratio -gt 1.0) `
          "visits/block = $ratio -- with one visit per block the memo is trivially equal to a direct transfer and V2 tests nothing"
  }

  # ---- V2: the memo agrees with a direct transfer, on every block ----------
  Check 'V2 no gen-set mismatch under DRAGLINT_VERIFY_GEN=1' `
        (-not ($verified -match 'EDefAsgnGenMismatch')) `
        'the memoised gen-set disagreed with a direct transfer -- Transfer is no longer gen-only and the memo is unsound'

  Check 'V2 findings are IDENTICAL with and without the self-check' `
        (($fPlain -join "`n") -eq ($fVerified -join "`n")) `
        "plain=$($fPlain.Count) verified=$($fVerified.Count) -- the self-check must observe, never change"

  # ---- V3: THE POSITIVE CONTROL -------------------------------------------
  # Without this, V2 passes just as happily against a self-check that was
  # never wired up, or one whose comparison can never be false.
  Check 'V3 CONTROL an injected fault IS caught (DRAGLINT_VERIFY_GEN=break)' `
        ($broken -match 'EDefAsgnGenMismatch') `
        'the deliberately corrupted value was NOT reported -- the self-check is inert, so V2 proves nothing'

  Check 'V3 CONTROL the fault mode is not the default (plain run is clean)' `
        (-not ($plain -match 'EDefAsgnGenMismatch')) `
        'a run with no DRAGLINT_VERIFY_GEN reported a mismatch -- the gate is not gating'
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
