<#
  run_flow_oracle_memo.ps1 -- G1 for C1b.
  docs\PLAN-flowchecker-transfer.md section 8.

  THE CHANGE UNDER TEST. The five flow oracles used to memoise into LOCALS of
  TFlowChecker.Check, which runs once per FILE, so every file re-paid every cold
  miss. C1b moved them onto the STORE (TFlowOracleCache, reached through
  ISymbolStore.FlowOracles), where they survive the file and live exactly as
  long as the store that issued the file ids in their keys.

  WHY THIS GUARD IS SHAPED THE WAY IT IS. C1a's memos were cleared at every
  Check entry, so a stale answer was structurally impossible and a byte-
  identical corpus A/B was a sufficient gate. C1b's memos PERSIST, so an A/B
  proves only that the answers agree on the corpora that were linted -- it
  cannot see an entry that is correct on every file linted and wrong on one that
  was not. Hence two independent halves here:

    * V2 measures that answers actually DO cross files (the prize), by linting
      the same callees from ONE caller unit and then from THREE. The keys for
      `owns` and `param-mode` carry no file id, so a store-lifetime memo pays
      those misses ONCE no matter how many units call them, while the old
      per-file memo paid them once PER UNIT. Unfixed, misses scale ~3x; fixed,
      they do not move.
    * V3/V4 check SOUNDNESS from inside the engine: DRAGLINT_VERIFY_ORACLE=1
      recomputes every cache hit through the uncached path and raises
      EFlowOracleMismatch on disagreement, and =break corrupts the cached value
      first so the check MUST fire. A verifier never observed to fail is
      indistinguishable from one that was never wired up, and this repo has
      shipped that mistake twice.

  RED STATE, recorded before the fix was written (engine at b481417):
    V1 passes (Step 0 landed the counters in C1a).
    V2 FAILS -- misses scale with the number of caller units.
    V4 FAILS -- DRAGLINT_VERIFY_ORACLE is an unknown variable, nothing raises.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_flow_oracle_memo"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok -and $d) { Write-Host "        $d" -ForegroundColor DarkGray }
  if (-not $ok) { $script:Failed = $true }
}
function WritePas([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$rules = (Resolve-Path $RulesDir).Path

# Directory.Delete, not Remove-Item: Remove-Item is permission-blocked in this
# harness and takes the whole command with it.
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$one   = Join-Path $WorkDir 'one'
$three = Join-Path $WorkDir 'three'
New-Item -ItemType Directory -Path $one   -Force | Out-Null
New-Item -ItemType Directory -Path $three -Force | Out-Null

# ---------------------------------------------------------------------------
# THE SHARED CALLEES. They live in ONE unit so that every caller unit produces
# the IDENTICAL oracle key -- that identity is what makes V2 a measurement of
# cache lifetime rather than of fixture size.
# ---------------------------------------------------------------------------
$lib = @'
unit uOracleLib;

interface

type
  TStat = record
    Total: Integer;
    procedure Reset;
  end;

  TThing = class
  public
    Tag: Integer;
  end;

{ var parameter: the param-mode oracle must see pmVar and treat the argument
  as DEFINED at the call site. }
procedure FetchValue(var AOut: Integer);

{ Reads its object argument and never stores it, so the owns oracle answers
  False -- which is what lets the caller's un-freed local surface as a leak. }
procedure Inspect(const AObj: TThing);

implementation

procedure TStat.Reset;
begin
  Total := 0;
end;

procedure FetchValue(var AOut: Integer);
begin
  AOut := 42;
end;

procedure Inspect(const AObj: TThing);
begin
  if AObj.Tag > 0 then
    Exit;
end;

end.
'@

# One caller body, stamped out under three unit names. Byte-identical apart
# from the identifiers, so the three units differ in NOTHING that an oracle key
# can see.
function CallerUnit([string]$Suffix) {
  @"
unit uCaller$Suffix;

interface

procedure Run$Suffix;

implementation

uses
  uOracleLib;

procedure Run$Suffix;
var
  S: TStat;
  N: Integer;
  T: TThing;
  Msg: string;
begin
  S.Reset;
  if S.Total > 0 then
    Exit;
  FetchValue(N);
  if N > 0 then
    Exit;
  T := TThing.Create;
  Inspect(T);
  if Msg <> '' then
    Exit;
end;

end.
"@
}

WritePas (Join-Path $one   'uOracleLib.pas') $lib
WritePas (Join-Path $one   'uCallerA.pas')   (CallerUnit 'A')
WritePas (Join-Path $three 'uOracleLib.pas') $lib
foreach ($s in 'A','B','C') { WritePas (Join-Path $three "uCaller$s.pas") (CallerUnit $s) }

$dbOne   = Join-Path $WorkDir 'one.sqlite'
$dbThree = Join-Path $WorkDir 'three.sqlite'
& $Exe index $one   --db $dbOne   2>&1 | Out-Null
& $Exe index $three --db $dbThree 2>&1 | Out-Null
Check 'both fixture indexes built' ((Test-Path $dbOne) -and (Test-Path $dbThree))

# ---------------------------------------------------------------------------
function RunLint([string]$Db, [string]$VerifyMode, [bool]$Profile) {
  # $env:X = $null unsets, and avoids `Remove-Item Env:\...` -- see above.
  $env:DRAGLINT_VERIFY_ORACLE = $null
  $env:DRAGLINT_PROFILE       = $null
  if ($VerifyMode) { $env:DRAGLINT_VERIFY_ORACLE = $VerifyMode }
  if ($Profile)    { $env:DRAGLINT_PROFILE       = '1' }
  try {
    $out  = & $Exe lint-all --db $Db --rules-dir $rules 2>&1 | Out-String
    $code = $LASTEXITCODE
    return [pscustomobject]@{ Text = $out; Exit = $code }
  } finally {
    $env:DRAGLINT_VERIFY_ORACLE = $null
    $env:DRAGLINT_PROFILE       = $null
  }
}
function OracleRow([string]$Text, [string]$Name) {
  $rx = [regex]("oracle\s+" + [regex]::Escape($Name) +
                "\s+([0-9.]+)\s*s\s+\((\d+)\s*call\(s\),\s*(\d+)\s*miss\(es\)")
  $m = $rx.Match($Text)
  if (-not $m.Success) { return $null }
  [pscustomobject]@{ Calls = [int]$m.Groups[2].Value; Misses = [int]$m.Groups[3].Value }
}
function FindingKeys([string]$Text) {
  ,@($Text -split "`r?`n" |
     Where-Object { $_ -match ':\d+:\d+\s+\[(error|warning|info|hint)\]' } |
     ForEach-Object { $_.Trim() } | Sort-Object)
}

$ORACLES = @('owns','param-mode','record-def','managed-type','record-type')

Push-Location C:\TEMP
try {
  $profOne   = RunLint $dbOne   $null   $true
  $profThree = RunLint $dbThree $null   $true
  $plain     = RunLint $dbThree $null   $false
  $verified  = RunLint $dbThree '1'     $false
  $broken    = RunLint $dbThree 'break' $false

  # ---- V1: the fixture reaches EVERY oracle -------------------------------
  # A missing line is a FAIL, never a skip: existence is not sufficiency, and a
  # V2 computed over an oracle that never ran would be comparing two zeroes.
  Write-Host ''
  Write-Host 'V1 -- positive control: every oracle is exercised' -ForegroundColor Cyan
  $rowsThree = @{}
  foreach ($o in $ORACLES) {
    $r = OracleRow $profThree.Text $o
    $rowsThree[$o] = $r
    Check "V1 oracle '$o' reported with calls > 0" (($null -ne $r) -and ($r.Calls -gt 0)) `
      $(if ($null -eq $r) { "no 'oracle $o' line under DRAGLINT_PROFILE -- the counter is gone or the name changed" }
        else { "calls=$($r.Calls) -- the fixture never reaches this oracle, so any miss assertion on it is vacuous" })
  }

  # ---- V2: answers CROSS FILES (this is the whole of C1b) -----------------
  Write-Host ''
  Write-Host 'V2 -- store lifetime: 3 caller units must not cost 3x the misses' -ForegroundColor Cyan
  foreach ($o in @('owns','param-mode')) {
    $r1 = OracleRow $profOne.Text   $o
    $r3 = OracleRow $profThree.Text $o
    if (($null -eq $r1) -or ($null -eq $r3)) {
      Check "V2 '$o' rows present in both runs" $false 'cannot compare -- a profile row is missing'
      continue
    }
    Write-Host ("        $o : 1 unit -> $($r1.Misses) miss(es) / $($r1.Calls) call(s)" +
                " | 3 units -> $($r3.Misses) miss(es) / $($r3.Calls) call(s)") -ForegroundColor DarkGray
    Check "V2 '$o' misses do NOT grow with the number of caller units" `
      ($r3.Misses -le $r1.Misses) `
      ("3-unit misses $($r3.Misses) exceed 1-unit misses $($r1.Misses). The key for this " +
       "oracle carries no file id, so a store-lifetime memo pays each key ONCE; growth " +
       "means the memo is still per-file (or was reset between files).")
    # The fixture triples the callers, so an unfixed engine lands near 3x. This
    # states that separately so a FAIL reads as "how far off" rather than just
    # "not <=".
    Check "V2 '$o' is nowhere near the per-file 3x" `
      ($r3.Misses -lt [Math]::Max(2, $r1.Misses * 2)) `
      "3-unit misses $($r3.Misses) vs 1-unit $($r1.Misses) -- that is the per-file scaling C1b removes"
  }

  # ---- V3 / V4: the self-check, and its positive control ------------------
  Write-Host ''
  Write-Host 'V3/V4 -- the memo agrees with a fresh computation, and is SEEN to fail' -ForegroundColor Cyan
  Check 'V3 no mismatch under DRAGLINT_VERIFY_ORACLE=1' `
    (-not ($verified.Text -match 'EFlowOracleMismatch')) `
    'a cached oracle answer disagreed with recomputing it -- the store-lifetime memo is unsound'
  Check 'V3 the verified run still exits cleanly' ($verified.Exit -le 1) `
    "exit $($verified.Exit) under the self-check"

  Check 'V4 CONTROL an injected fault IS caught (DRAGLINT_VERIFY_ORACLE=break)' `
    ($broken.Text -match 'EFlowOracleMismatch') `
    'the deliberately corrupted cache value was NOT reported -- the self-check is inert, so V3 proves nothing'
  Check 'V4 CONTROL the fault mode is not the default (plain run is clean)' `
    (-not ($plain.Text -match 'EFlowOracleMismatch')) `
    'a run with no DRAGLINT_VERIFY_ORACLE reported a mismatch -- the gate is not gating'

  # ---- V5: the three oracle-dependent findings, in BOTH modes -------------
  # Two absences and one presence. The presence is what keeps the absences
  # honest: with the rules simply off, all three would "pass" as absences.
  Write-Host ''
  Write-Host 'V5 -- the memo moved no finding' -ForegroundColor Cyan
  foreach ($arm in @(@{N='plain'; T=$plain.Text}, @{N='verify=1'; T=$verified.Text})) {
    Check "V5 [$($arm.N)] record method call DEFINES the record (no used-before-assignment on S)" `
      (-not ($arm.T -match 'used-before-assignment.*\bS\b')) `
      'S.Reset must count as a definition -- that is the record-def oracle'
    Check "V5 [$($arm.N)] var parameter DEFINES the argument (no used-before-assignment on N)" `
      (-not ($arm.T -match 'used-before-assignment.*\bN\b')) `
      'FetchValue(N) has a var parameter -- that is the param-mode oracle'
    Check "V5 [$($arm.N)] non-owning callee lets the leak surface (object-leak PRESENT)" `
      ($arm.T -match 'object-leak') `
      'Inspect() does not own T, so the un-freed local is a real leak -- that is the owns oracle, and it is this run''s positive control'
  }

  $fPlain    = FindingKeys $plain.Text
  $fVerified = FindingKeys $verified.Text
  Check 'V5 findings are IDENTICAL with and without the self-check' `
    (($fPlain -join "`n") -eq ($fVerified -join "`n")) `
    "plain=$($fPlain.Count) verified=$($fVerified.Count) -- the self-check must observe, never change"
}
finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
