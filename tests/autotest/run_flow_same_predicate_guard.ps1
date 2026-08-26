<#
  run_flow_same_predicate_guard.ps1 -- a read guarded by the SAME bare predicate
  that guarded the assignment is not "used before assigned".

  The shape (INBOX-used-before-assignment-real-shape-is-intra-item-ordering):

      if Profiled then TMark := TStopwatch.GetTimeStamp;
      ...
      if Profiled then Inc(AccRes, TStopwatch.GetTimeStamp - TMark);

  The read cannot execute unassigned, but the lattice carries no predicate at all
  (TDefAsgnVal is just Must/May bit arrays) and the CFG models branching purely as
  edges, so the correlation is invisible. The suppression is therefore a syntactic
  AST check at emission time.

  DELIBERATELY NARROW. Only a BARE LOCAL IDENTIFIER predicate counts, and only
  when the assignment sits under a textually identical one. Measured effect on the
  self-index: 39 -> 35 findings, removing exactly the four `tmark` sites.

  Everything else in that population is left alone ON PURPOSE, and the surviving
  cases below are why:

    * WITNESS-FLAG pairs (`if C then begin X := ..; HaveX := True end;
      if HaveX then Use(X)`) -- the two predicates DIFFER, so suppressing needs a
      proof that one implies the other, and ANY GAP IN THAT PROOF HIDES A REAL
      use-before-assignment. Wrong failure direction for this rule.
    * `if not F`, else-arms, case, loop-crossing guards.
    * arrays/records only ever element-written -- a granularity problem no
      predicate check can reach.

  THE SURVIVING-FIRE CASES ARE THE TEST. "39 became 35" is also what deleting the
  rule produces, so a count assertion alone proves nothing.

    SamePredicate    assign and read under `if P`            -> SILENT
    TrueUnassigned   never assigned at all                   -> MUST FIRE (warning)
    FlagReassigned   `if P then V:=1; P:=Q; if P then Use(V)` -> MUST FIRE
    NotPredicate     assign under `if P`, read under `if not P` -> MUST FIRE
    ElseArm          assign in THEN, read in ELSE            -> MUST FIRE
    WitnessUnpaired  differing predicates                    -> MUST FIRE

  RED VERIFIED 2026-08-16: with the suppression neutralised and rebuilt,
  SamePredicate FAILS and all five controls still PASS -- perfect discrimination,
  so this suite measures the fix and nothing else.

  WIDENED 2026-08-26 (INBOX-then-guard-blind-to-ifelse): the grammar spells the
  with-else form as a THIRD node type, `ifElse`, and ThenGuardName accepted only
  `if`/`exprIf` -- so the suppression could never fire for ANY if..then..else,
  and two textually equivalent programs got different answers. Two fixtures pin
  the widening (guard variables Q/W/Tot, distinct from P/V/Sum so no anchor
  regex collides):

    SamePredicateIfElse     read in the THEN arm of if..then..ELSE,
                            assigned under the same bare predicate -> SILENT
    SamePredicateAsgIfElse  ASSIGNED in the THEN arm of if..then..ELSE,
                            read under the same bare predicate     -> SILENT

  ElseArm above is ALSO the else-arm control for the widening: its second `if`
  IS an ifElse node, and a read in the ELSE arm is guarded by the NEGATION, so
  it must keep firing after `ifElse` is accepted.

  RED VERIFIED 2026-08-26: against the pre-widening engine, both new SILENT
  assertions FAIL and every control still PASSES.

  MEASURED (the gate for shipping the widening, since it widens a SUPPRESSION):
  lint-all used-before-assignment on this repo, identical command before and
  after, 2026-08-26: 30 -> 30. ZERO findings were removed by the wider
  suppression. The only effect was four sites RE-TIERED warning -> info by the
  witness-flag tiering, which reads the same guard list and was equally blind:
  TextEdit.pas 612:7 + 612:42 (LastInSection under HaveLast) and
  Manifest.pas 1014:27 + 1015:27 (LocalManifest under HaveLocal,
  GlobalManifest under HaveGlobal). Each was hand-verified as the designed
  shape: a bare witness flag set exactly beside the guarded variable's
  assignment, read in the THEN arm of an if..then..else. The compound-predicate
  siblings at the same sites (TextEdit 604: `(not HaveLast) or ...`;
  Manifest 982: `HaveGlobal and HaveLocal`) correctly stayed warnings.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_samepred'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'samepred.pas'

$body = @'
unit samepred;

interface

implementation

{ NOTE: every read below is ARITHMETIC (`Sum := Sum + V`), never `Foo(V)`.
  A bare identifier passed as an argument is recorded as a CallDef, not a read,
  so a call-shaped fixture produces NO findings at all and every assertion --
  including the SILENT one -- passes vacuously. That happened on the first
  version of this suite. }

procedure SamePredicate(P: Boolean);
var
  V, Sum: Integer;
begin
  Sum := 0;
  if P then V := 1;
  if P then Sum := Sum + V;
end;

procedure TrueUnassigned;
var
  X, Y: Integer;
begin
  Y := X + 1;
  X := Y;
end;

procedure FlagReassigned(P, Q: Boolean);
var
  V, Sum: Integer;
begin
  Sum := 0;
  if P then V := 1;
  P := Q;
  if P then Sum := Sum + V;
end;

procedure NotPredicate(P: Boolean);
var
  V, Sum: Integer;
begin
  Sum := 0;
  if P then V := 1;
  if not P then Sum := Sum + V;
end;

procedure ElseArm(P: Boolean);
var
  V, Sum: Integer;
begin
  Sum := 0;
  if P then
    V := 1
  else
    Sum := Sum + V;
end;

procedure WitnessUnpaired(C1, C2: Boolean);
var
  V, Sum: Integer;
  HaveV : Boolean;
begin
  Sum := 0;
  HaveV := False;
  if C1 then HaveV := True;
  if C2 then V := 1;
  if HaveV then Sum := Sum + V;
end;

procedure SamePredicateIfElse(Q: Boolean);
var
  W, Tot: Integer;
begin
  Tot := 0;
  if Q then W := 1;
  if Q then Tot := Tot + W else Tot := 1;
end;

procedure SamePredicateAsgIfElse(Q: Boolean);
var
  W, Tot: Integer;
begin
  Tot := 0;
  if Q then W := 1 else Tot := 2;
  if Q then Tot := Tot + W;
end;

end.
'@
[System.IO.File]::WriteAllText($target, (($body -replace "`r`n","`n") -replace "`n","`r`n"),
  (New-Object System.Text.UTF8Encoding($false)))

# Map routine name -> the source line its guarded READ sits on, so assertions are
# anchored to a routine rather than to a global count.
$lines = [System.IO.File]::ReadAllLines($target)
function LineOf($pattern) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i + 1 } }
  return -1
}

Push-Location C:\TEMP
try {
  $out = & $exePath lint $target 2>&1 | Out-String
  $ub  = @(($out -split "`r?`n") | Where-Object { $_ -match 'used-before-assignment' })

  Check 'SANITY: the linter ran' ($out.Trim().Length -gt 0) $out
  Check 'SANITY: the fixture produces used-before-assignment findings at all' `
        ($ub.Count -ge 1) $out

  function FiredAt($ln) { return (@($ub | Where-Object { $_ -match ":$ln`:" }).Count -gt 0) }

  $lSame    = LineOf 'if P then Sum := Sum \+ V;'
  $lTrue    = LineOf 'Y := X \+ 1;'
  $lNot     = LineOf 'if not P then Sum := Sum \+ V;'
  $lElse    = LineOf '^\s{4}Sum := Sum \+ V;'
  $lWitness = LineOf 'if HaveV then Sum := Sum \+ V;'
  # The ifElse fixtures use Q/W/Tot, so neither line collides with the
  # second-occurrence scan for FlagReassigned below.
  $lIfElse    = LineOf 'if Q then Tot := Tot \+ W else'
  $lAsgIfElse = LineOf 'if Q then Tot := Tot \+ W;'
  # FlagReassigned's read is the SECOND `if P then Sum := Sum + V;` in the file.
  $lReasgn  = -1
  $seen = 0
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'if P then Sum := Sum \+ V;') { $seen++; if ($seen -eq 2) { $lReasgn = $i + 1; break } }
  }

  Check 'SANITY: all eight anchor lines were located' `
        (($lSame -gt 0) -and ($lTrue -gt 0) -and ($lNot -gt 0) -and ($lElse -gt 0) -and ($lWitness -gt 0) -and ($lIfElse -gt 0) -and ($lAsgIfElse -gt 0)) `
        "same=$lSame true=$lTrue not=$lNot else=$lElse witness=$lWitness ifelse=$lIfElse asgifelse=$lAsgIfElse"

  # --- the suppression ---
  Check 'SamePredicate: read under the SAME bare predicate is SILENT' `
        (-not (FiredAt $lSame)) ($ub -join "`n")
  Check 'SamePredicateIfElse: read in the THEN arm of if..then..ELSE, same predicate, is SILENT' `
        (-not (FiredAt $lIfElse)) ($ub -join "`n")
  Check 'SamePredicateAsgIfElse: ASSIGNMENT in the THEN arm of if..then..ELSE, read under same predicate, is SILENT' `
        (-not (FiredAt $lAsgIfElse)) ($ub -join "`n")

  # --- the controls: each of these must SURVIVE ---
  Check 'CONTROL: TrueUnassigned STILL fires (rule not switched off)' `
        (FiredAt $lTrue) ($ub -join "`n")
  Check 'CONTROL: FlagReassigned STILL fires (predicate rewritten between the two guards)' `
        (FiredAt $lReasgn) ("line=$lReasgn`n" + ($ub -join "`n"))
  Check 'CONTROL: NotPredicate STILL fires (`if not P` is not the same predicate)' `
        (FiredAt $lNot) ($ub -join "`n")
  Check 'CONTROL: ElseArm STILL fires (else arm of an ifElse node is guarded by the NEGATION)' `
        (FiredAt $lElse) ($ub -join "`n")
  Check 'CONTROL: WitnessUnpaired STILL fires (differing predicates are not correlated)' `
        (FiredAt $lWitness) ($ub -join "`n")
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
