# Guard: a witness-flag-guarded read is TIERED DOWN, never suppressed.
#
#     if C then begin X := ..; HaveX := True; end;
#     ...
#     if HaveX then Use(X);
#
# used-before-assignment reports X here. The read's guard (HaveX) is not the
# same predicate as the assignment's guard (C), so SAME-PREDICATE SUPPRESSION
# correctly declines to fire, and the finding lands at warning severity -- which
# since 2026-08-26 is one step below an ERROR-severity rule's top level.
#
# WHY NOT JUST SUPPRESS IT. A Fable analysis (2026-08-26) built three Pascal
# counter-examples in which a witness-flag pairing argument holds and X is still
# genuinely unassigned:
#   * the flag is never initialised, so on the else-path it is stack garbage and
#     can read True;
#   * the flag is set by a non-literal write (HaveX := HaveX or Retry), which no
#     ":= True" site scan sees;
#   * the flag is set from a NESTED routine, where "preceded in the same block"
#     has no meaning.
# An airtight suppression therefore needs roughly six clauses, and every clause
# omitted SUPPRESSES A TRUE POSITIVE -- the failure direction the SAME-PREDICATE
# SUPPRESSION block in FlowChecks.pas refuses in writing.
#
# Tiering bounds the cost of a classifier gap at one severity level instead: the
# finding survives, lint-all still counts it, and the message names the flag so
# a human can check the pairing in seconds.
#
# THE TWO CONTROLS ARE THE POINT:
#   (1) PPlain -- a may-unassigned read guarded by something that is NOT a
#       witness flag must STAY at warning. Without this, downgrading the whole
#       rule to info passes the witness assertion.
#   (2) PDefinite -- a DEFINITE unassigned read must stay an ERROR. The tiering
#       lives only in the `may` arm; if it ever reached the `must` arm it would
#       be demoting certainty, which is a different and worse change.
#
# A TRAP FOR ANYONE EDITING THIS FIXTURE: every read below is an ASSIGNMENT
# SOURCE (`RW := XW`), never a call argument. FlowChecks treats a call argument
# as a DEF, not a read -- "callee may be a var/out sink" -- so a fixture whose
# only use of X is `Writeln(X)` reports NOTHING AT ALL, including the controls.
# The first draft of this file did exactly that and every arm went red at once,
# which is the only reason it was caught rather than silently proving nothing.
#
# Usage: pwsh -File tests/autotest/run_witness_flag_tiering.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir  = "$env:TEMP\drag-lint-witness-tier"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

$Fixture = @'
unit uWitness;

interface

procedure PWitness(Cond: Boolean);
procedure PPlain(Cond, Other: Boolean);
procedure PDefinite;

implementation

procedure PWitness(Cond: Boolean);
var
  XW    : Integer;
  RW    : Integer;
  HaveXW: Boolean;
begin
  HaveXW := False;
  RW     := 0;
  if Cond then
  begin
    XW     := 1;
    HaveXW := True;
  end;
  if HaveXW then RW := XW;
  Writeln(RW);
end;

procedure PPlain(Cond, Other: Boolean);
var
  XP: Integer;
  RP: Integer;
begin
  RP := 0;
  if Cond then XP := 1;
  if Other then RP := XP;
  Writeln(RP);
end;

procedure PDefinite;
var
  XD: Integer;
  RD: Integer;
begin
  RD := XD;
  Writeln(RD);
end;

end.
'@
$file = Join-Path $WorkDir 'uWitness.pas'
[System.IO.File]::WriteAllText($file, (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$out = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$rows = @([regex]::Matches($out, '\[(?<sev>\w+)\]\s+used-before-assignment:\s+(?<msg>[^\r\n]+)') |
          ForEach-Object { [pscustomobject]@{ Sev = $_.Groups['sev'].Value; Msg = $_.Groups['msg'].Value } })
foreach ($r in $rows) { Write-Host ("  {0,-8} {1}" -f $r.Sev, $r.Msg) -ForegroundColor DarkGray }

function RowFor([string]$VarName) {
  return @($rows | Where-Object { $_.Msg -match ('"' + $VarName + '"') })
}

Write-Host ''
Write-Host 'CONTROLS' -ForegroundColor Cyan
$plain = RowFor 'XP'
Check 'a non-witness may-unassigned read is reported' ($plain.Count -eq 1) ("rows=" + ($plain | ConvertTo-Json -Compress))
Check 'and it STAYS at warning' (($plain.Count -eq 1) -and ($plain[0].Sev -eq 'warning')) ("sev=" + ($plain | ForEach-Object { $_.Sev }))

$def = RowFor 'XD'
Check 'a DEFINITE unassigned read is reported' ($def.Count -eq 1) ("rows=" + ($def | ConvertTo-Json -Compress))
Check 'and it STAYS an error (tiering never touches the must arm)' (($def.Count -eq 1) -and ($def[0].Sev -eq 'error')) ("sev=" + ($def | ForEach-Object { $_.Sev }))

Write-Host ''
Write-Host 'THE TIERING' -ForegroundColor Cyan
$wit = RowFor 'XW'
Check 'the witness-flag read is STILL REPORTED (not suppressed)' ($wit.Count -eq 1) ("rows=" + ($wit | ConvertTo-Json -Compress))
Check 'the witness-flag read is tiered down to info' (($wit.Count -eq 1) -and ($wit[0].Sev -eq 'info')) ("sev=" + ($wit | ForEach-Object { $_.Sev }))
Check 'and its message NAMES the flag, so the pairing can be checked' (($wit.Count -eq 1) -and ($wit[0].Msg -match 'HaveXW')) ("msg=" + ($wit | ForEach-Object { $_.Msg }))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
