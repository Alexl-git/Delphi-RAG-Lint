<#
run_flow_nil_guard_predicate.ps1 -- used-before-assignment: a `X <> nil` / `X = nil`
guard is as correlatable as a bare boolean one.

FILED 2026-11-03 (docs\INBOX-yadf-false-positives-2026-11-03.md item 4), YADFOT.Wizard.pas:

    if View <> nil then
    begin
      SavedPos:= View.CursorPos;
      SavedTop:= View.TopPos;
    end;
    WriteEditorText(Editor, Formatted);
    if View <> nil then
      RestoreViewPosition(View, SavedPos, SavedTop, ...);

The SAME-PREDICATE suppression (run_flow_same_predicate_guard.ps1) honoured only a
BARE identifier predicate, so the nil comparison -- the commonest guard in Delphi --
reported both locals. A comparison of a local identifier with the literal nil names
one variable and one constant: two textually equal ones mean the same thing exactly
when that variable is not rewritten in between, which is the check the bare form
already makes. The variable name, not the whole token, is what that check is handed.

Controls (each must STILL fire): the guard variable rewritten in between; `= nil`
vs `<> nil` (opposite predicates); a different variable compared with nil; a true
unassigned read.
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_nilguard_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'nilguard.pas'

# Every read is ARITHMETIC (see run_flow_same_predicate_guard.ps1: a bare argument
# is a CallDef, not a read, and would make every SILENT assertion vacuous).
$body = @'
unit nilguard;

interface

implementation

procedure SameNilGuard(P: TObject);
var
  V, Sum: Integer;
begin
  Sum := 0;
  if P <> nil then V := 1;
  Sum := Sum + 2;
  if P <> nil then Sum := Sum + V;
end;

procedure SameIsNilGuard(P: TObject);
var
  W, Tot: Integer;
begin
  Tot := 0;
  if P = nil then W := 1;
  Tot := Tot + 2;
  if P = nil then Tot := Tot + W;
end;

procedure GuardRewritten(P, Q: TObject);
var
  V, Sum: Integer;
begin
  Sum := 0;
  if P <> nil then V := 1;
  P := Q;
  if P <> nil then Sum := Sum + V {REWRITTEN};
end;

procedure OppositeNilGuard(P: TObject);
var
  V, Sum: Integer;
begin
  Sum := 0;
  if P <> nil then V := 1;
  if P = nil then Sum := Sum + V {OPPOSITE};
end;

procedure OtherVarNilGuard(P, Q: TObject);
var
  V, Sum: Integer;
begin
  Sum := 0;
  if P <> nil then V := 1;
  if Q <> nil then Sum := Sum + V {OTHERVAR};
end;

procedure TrueUnassigned;
var
  X, Y: Integer;
begin
  Y := X + 1;
  X := Y;
end;

end.
'@
[System.IO.File]::WriteAllText($target, ($body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)

$lines = [System.IO.File]::ReadAllLines($target)
function LineOf($pattern) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i + 1 } }
  return -1
}

Push-Location C:\TEMP
try {
  $out = & $exePath lint $target 2>&1 | Out-String
  $ub  = @(($out -split "`r?`n") | Where-Object { $_ -match 'used-before-assignment' })
  function FiredAt($ln) { return (@($ub | Where-Object { $_ -match ":$ln`:" }).Count -gt 0) }

  $lSame  = LineOf 'if P <> nil then Sum := Sum \+ V;'
  $lIsNil = LineOf 'if P = nil then Tot := Tot \+ W;'
  $lRe    = LineOf '\{REWRITTEN\}'
  $lOpp   = LineOf '\{OPPOSITE\}'
  $lOther = LineOf '\{OTHERVAR\}'
  $lTrue  = LineOf 'Y := X \+ 1;'

  Check 'SANITY: the fixture produces used-before-assignment findings at all' ($ub.Count -ge 1) $out
  Check 'SANITY: all six anchor lines were located' `
        (($lSame -gt 0) -and ($lIsNil -gt 0) -and ($lRe -gt 0) -and ($lOpp -gt 0) -and ($lOther -gt 0) -and ($lTrue -gt 0)) `
        "same=$lSame isnil=$lIsNil re=$lRe opp=$lOpp other=$lOther true=$lTrue"

  Check 'SameNilGuard: read under the SAME `P <> nil` guard is SILENT' (-not (FiredAt $lSame)) ($ub -join "`n")
  Check 'SameIsNilGuard: read under the SAME `P = nil` guard is SILENT' (-not (FiredAt $lIsNil)) ($ub -join "`n")

  Check 'CONTROL: GuardRewritten STILL fires (P reassigned between the guards)' (FiredAt $lRe) ($ub -join "`n")
  Check 'CONTROL: OppositeNilGuard STILL fires (`= nil` is not `<> nil`)' (FiredAt $lOpp) ($ub -join "`n")
  Check 'CONTROL: OtherVarNilGuard STILL fires (Q <> nil is not P <> nil)' (FiredAt $lOther) ($ub -join "`n")
  Check 'CONTROL: TrueUnassigned STILL fires (rule not switched off)' (FiredAt $lTrue) ($ub -join "`n")
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  $d = Join-Path C:\TEMP "draglint_nilguard_$PID"
  if (Test-Path -LiteralPath $d) { [IO.Directory]::Delete($d, $true) }
}
