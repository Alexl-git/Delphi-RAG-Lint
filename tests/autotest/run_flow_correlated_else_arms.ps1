<#
  run_flow_correlated_else_arms.ps1 -- C4: the same-predicate suppression must
  recognise ELSE/ELSE correlation, and must NOT flatten polarity while doing it.

  THE BUG (INBOX-c4-correlated-branches-plan.md)
  --------------------------------------------------------------------------------
  An emission-time same-predicate suppression has shipped since v1.4.0-alpha
  (FlowChecks.pas, GuardToken / AssignedUnderSameGuard). DataCopy's
  `used-before-assignment` on `LPlan` fired anyway, because the shipped version
  recognised only THEN/THEN:

      if AIf.Child(ThenIx) ... else Exit;     // an else-arm child was REFUSED

  and the field code is ELSE/ELSE -- `LPlan` is assigned in the else arm of
  `if LWasNew then ... else ...` and read, later, in the else arm of the same
  predicate. The backlog paraphrase said "read in a branch guarded by the SAME
  condition", which is polarity-inverted relative to the real code; the plan
  caught that only by reading the source.

  Guards are now signed tokens: '+name' for a then-arm position, '-name' for an
  else-arm one. Measured on DataCopy: used-before-assignment 5 -> 3, and no other
  rule's count moved. The 3 survivors are a different variable in a test unit.

  WHY THE SIGN IS THE WHOLE POINT. Dropping polarity instead of recording it
  would also have silenced DataCopy -- and would have silenced ThenAssignElseRead
  below, which is a REAL use-before-assignment. That case is the positive control
  here: a suppression that merely matched predicate NAMES would pass every other
  assertion in this file and hide genuine bugs.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_c4_else_arms"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [System.IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"),
                                 [System.Text.Encoding]::ASCII)
}

Write-Host '== used-before-assignment: correlated else arms ==' -ForegroundColor Cyan
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

Write-Ascii (Join-Path $WorkDir 'c4shapes.pas') @'
unit c4shapes;

interface

type
  TT = class
  public
    function ElseElse       (const AWasNew: Boolean): string;
    function ThenThen       (const AWasNew: Boolean): string;
    function ThenAssignElseRead(const AWasNew: Boolean): string;
    function PredicateRewritten(AWasNew: Boolean): string;
  end;

implementation

function ComputePlan: string;
begin
  Result := 'plan';
end;

{ THE DEFECT. Both sites are in the ELSE arm of the same bare-identifier
  predicate, so they are correlated and LPlan is always assigned when read. }
function TT.ElseElse(const AWasNew: Boolean): string;
var
  LPlan: TPlan;
begin
  if AWasNew then
    Result := 'new'
  else
  begin
    LPlan  := ComputePlan;
    Result := 'old';
  end;
  if AWasNew then
    Result := Result + '-a'
  else
    Result := Result + IntToStr(LPlan.Id);
end;

{ CONTROL: THEN/THEN was already suppressed before this change and must stay so.
  If it starts firing, the rename or the sign broke the existing path. }
function TT.ThenThen(const AWasNew: Boolean): string;
var
  LPlan: TPlan;
begin
  if AWasNew then
  begin
    LPlan  := ComputePlan;
    Result := 'new';
  end
  else
    Result := 'old';
  if AWasNew then
    Result := Result + LPlan
  else
    Result := Result + '-b';
end;

{ POSITIVE CONTROL: assigned in the THEN arm, read in the ELSE arm of the SAME
  predicate. The two are correlated in the opposite sense -- the read happens
  exactly when the assignment did NOT -- so this is a genuine
  used-before-assignment and MUST still be reported. A suppression that matched
  predicate names while ignoring polarity would silence it. }
function TT.ThenAssignElseRead(const AWasNew: Boolean): string;
var
  LPlan: TPlan;
begin
  if AWasNew then
  begin
    LPlan  := ComputePlan;
    Result := 'new';
  end
  else
    Result := 'old';
  if AWasNew then
    Result := Result + '-c'
  else
    Result := Result + IntToStr(LPlan.Id);
end;

{ POSITIVE CONTROL: correlated arms, but the PREDICATE ITSELF is rewritten in
  between, so the two `if AWasNew` tests do not denote the same value and the
  correlation does not hold. Must still be reported. This is the safety check
  that reads the predicate variable by its BARE name, which the signed token had
  to be stripped for. }
function TT.PredicateRewritten(AWasNew: Boolean): string;
var
  LPlan: TPlan;
begin
  if AWasNew then
    Result := 'new'
  else
  begin
    LPlan  := ComputePlan;
    Result := 'old';
  end;
  AWasNew := not AWasNew;
  if AWasNew then
    Result := Result + '-d'
  else
    Result := Result + IntToStr(LPlan.Id);
end;

end.
'@

$db  = Join-Path $WorkDir 'p.sqlite'
$rep = Join-Path $WorkDir 'rep.txt'
$idx = & $Exe index $WorkDir --db $db 2>&1 | Out-String
& $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-Null
$out = if (Test-Path $rep) { Get-Content $rep } else { @() }

Check 'control: the fixture parsed with no errors' `
  ($idx -notmatch '-> 0 symbols' -and $idx -notmatch ', [1-9]\d* errors') `
  'a parse failure would make every negative arm pass by silence'

$uba = @($out | Where-Object { $_ -match 'used-before-assignment' })
Check 'control: the rule ran and still reports something' ($uba.Count -gt 0) `
  "used-before-assignment lines=$($uba.Count)"

# Findings carry only the line, so map each reported line to its routine by
# scanning the fixture -- asserting on "which routine" is what makes the
# polarity arms meaningful.
$src   = Get-Content (Join-Path $WorkDir 'c4shapes.pas')
$owner = {
  param($line)
  $name = '?'
  for ($i = 0; $i -lt $line -and $i -lt $src.Count; $i++) {
    if ($src[$i] -match '^function TT\.(\w+)') { $name = $Matches[1] }
  }
  return $name
}
$hitRoutines = @()
foreach ($l in $uba) {
  if ($l -match ':(\d+):\d+\s+\[\w+\]\s+used-before-assignment') {
    $hitRoutines += (& $owner ([int]$Matches[1]))
  }
}
Write-Host ("  routines reported: " + (($hitRoutines | Sort-Object -Unique) -join ', '))

Check 'ELSE/ELSE correlation is suppressed (the defect)' `
  ($hitRoutines -notcontains 'ElseElse') 'assigned and read in the else arm of one predicate'
Check 'CONTROL: THEN/THEN stays suppressed' `
  ($hitRoutines -notcontains 'ThenThen') 'the path that already worked must not regress'
Check 'POSITIVE CONTROL: then-assign / else-read IS still reported' `
  ($hitRoutines -contains 'ThenAssignElseRead') `
  'polarity-blind matching would wrongly silence this genuine bug'
Check 'POSITIVE CONTROL: a rewritten predicate IS still reported' `
  ($hitRoutines -contains 'PredicateRewritten') `
  'the bare-name AssignedInRange safety check must survive the signed token'

Write-Host ''
if ($script:Failed) { Write-Host 'C4 ELSE-ARM GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'C4 ELSE-ARM GUARD: PASS' -ForegroundColor Green
exit 0
