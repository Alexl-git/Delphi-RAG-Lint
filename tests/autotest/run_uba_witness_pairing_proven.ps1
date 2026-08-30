<#
  run_uba_witness_pairing_proven.ps1 -- the TOP row of the owner's ladder.

  OWNER RULING 2026-08-30 gave used-before-assignment three outcomes:

    pairing PROVEN               -> silent
    pairing recognised, NOT provable -> warning, "POSSIBLE use before assignment"
    no pairing                   -> error, unchanged

  The middle row shipped first (28812ee). This guard is the TOP row: silence,
  and silence is the dangerous direction. WitnessFlagForRead is a RECOGNISER,
  not a proof -- its own header carries three Pascal counter-examples where a
  pairing of exactly the recognised shape holds and the variable is still
  genuinely unassigned. Every clause omitted from the proof SUPPRESSES A TRUE
  POSITIVE on a rule that is error severity in its certain arm. That is the
  failure direction the rule's author refused in writing, and it is why this
  file is structured as PAIRS.

  EVERY CLAUSE IS TESTED AS A PAIR. For each clause: the provable case goes
  SILENT, and a sibling differing ONLY in that clause is still REPORTED. Half a
  pair proves nothing -- "it went silent" also passes with the rule switched
  off, and "it still fires" also passes with the proof never implemented.

    clause 1  the flag is a LOCAL, never a var/out parameter
              (a caller can set a var param, so no in-routine scan can bound it)
    clause 2  the flag is must-assigned where it is read
              COUNTER-EXAMPLE 1: an uninitialised flag is stack garbage and can
              read True, so the guarded read runs with X unassigned
    clause 3  the flag is only ever assigned a True/False LITERAL, and appears
              nowhere else except as a bare if-condition
              COUNTER-EXAMPLE 2: `HaveX := HaveX or Retry` is a write no
              `:= True` site scan can see. The "appears nowhere else" half also
              covers passing the flag to a call, which could define it through
              a var/out parameter.
    clause 4  the flag is never assigned inside a NESTED routine
              COUNTER-EXAMPLE 3: "in the same block" has no meaning there
    clause 5  EVERY `flag := True` site is block-adjacent to an assignment of X
              (one site that sets the flag without assigning X breaks the
              pairing, however many well-formed sites sit beside it)

  EVERY READ IS AN ASSIGNMENT SOURCE (`R := X`), NEVER A CALL ARGUMENT. FlowChecks
  treats a call argument as a possible DEFINITION -- a var/out parameter would
  define it -- so `Consume(X)` makes the rule fire on nothing at all, and every
  assertion in this file then reads as "the proof works". The first draft of this
  guard did exactly that and reported 0 rows for all nine routines.

  POSITIVE CONTROLS, without which the silences above are unfalsifiable:
    * a may-unassigned read with NO witness flag is still reported
    * a DEFINITE unassigned read is still an error -- the proof must never
      reach the must arm, where there is no uncertainty to resolve
#>
[CmdletBinding()]
param(
    [string] $Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir  = "$env:TEMP\drag-lint-uba-proven"
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

# Every variable name is unique across the unit so a finding can be attributed
# to its routine from the message alone.
$Fixture = @'
unit uProven;

interface

procedure PProven(Cond: Boolean);
procedure PNoInit(Cond: Boolean);
procedure PNonLiteral(Cond, Retry: Boolean);
procedure PCallArg(Cond: Boolean);
procedure PNested(Cond: Boolean);
procedure PStraySite(Cond, Other: Boolean);
procedure PVarParam(Cond: Boolean; var HaveVp: Boolean);
procedure PNoWitness(Cond, Other: Boolean);
procedure PDefinite;

implementation

procedure Fill(var B: Boolean);
begin
  B := True;
end;

{ ALL FIVE CLAUSES HOLD -> silent. }
procedure PProven(Cond: Boolean);
var
  Xpv    : Integer;
  Rpv    : Integer;
  HaveXpv: Boolean;
begin
  Rpv := 0;
  HaveXpv := False;
  if Cond then
  begin
    Xpv     := 1;
    HaveXpv := True;
  end;
  if HaveXpv then Rpv := Xpv;
  Writeln(Rpv);
end;

{ CLAUSE 2 broken: the flag is never initialised, so on the else-path it is
  stack garbage and can read True. -> still reported. }
procedure PNoInit(Cond: Boolean);
var
  Xni    : Integer;
  Rni    : Integer;
  HaveXni: Boolean;
begin
  Rni := 0;
  if Cond then
  begin
    Xni     := 1;
    HaveXni := True;
  end;
  if HaveXni then Rni := Xni;
  Writeln(Rni);
end;

{ CLAUSE 3 broken: a NON-LITERAL write no ":= True" site scan can see.
  -> still reported. }
procedure PNonLiteral(Cond, Retry: Boolean);
var
  Xnl    : Integer;
  Rnl    : Integer;
  HaveXnl: Boolean;
begin
  Rnl := 0;
  HaveXnl := False;
  if Cond then
  begin
    Xnl     := 1;
    HaveXnl := True;
  end;
  HaveXnl := HaveXnl or Retry;
  if HaveXnl then Rnl := Xnl;
  Writeln(Rnl);
end;

{ CLAUSE 3, second half: the flag is passed to a call that can define it
  through a var parameter. -> still reported. }
procedure PCallArg(Cond: Boolean);
var
  Xca    : Integer;
  Rca    : Integer;
  HaveXca: Boolean;
begin
  Rca := 0;
  HaveXca := False;
  if Cond then
  begin
    Xca     := 1;
    HaveXca := True;
  end;
  Fill(HaveXca);
  if HaveXca then Rca := Xca;
  Writeln(Rca);
end;

{ CLAUSE 4 broken: the flag is set from a NESTED routine, where "the same
  block" has no meaning. -> still reported. }
procedure PNested(Cond: Boolean);
var
  Xnd    : Integer;
  Rnd    : Integer;
  HaveXnd: Boolean;

  procedure Inner;
  begin
    HaveXnd := True;
  end;

begin
  Rnd := 0;
  HaveXnd := False;
  if Cond then
  begin
    Xnd     := 1;
    HaveXnd := True;
  end;
  Inner;
  if HaveXnd then Rnd := Xnd;
  Writeln(Rnd);
end;

{ CLAUSE 5 broken: a SECOND ":= True" site that does not assign X sits beside a
  well-formed one. -> still reported. }
procedure PStraySite(Cond, Other: Boolean);
var
  Xss    : Integer;
  Rss    : Integer;
  HaveXss: Boolean;
begin
  Rss := 0;
  HaveXss := False;
  if Cond then
  begin
    Xss     := 1;
    HaveXss := True;
  end;
  if Other then
  begin
    HaveXss := True;
  end;
  if HaveXss then Rss := Xss;
  Writeln(Rss);
end;

{ CLAUSE 1 broken: the flag is a var PARAMETER, so the caller may have set it
  with no assignment to X anywhere. -> still reported. }
procedure PVarParam(Cond: Boolean; var HaveVp: Boolean);
var
  Xvp: Integer;
  Rvp    : Integer;
begin
  Rvp := 0;
  if Cond then
  begin
    Xvp    := 1;
    HaveVp := True;
  end;
  if HaveVp then Rvp := Xvp;
  Writeln(Rvp);
end;

{ POSITIVE CONTROL: no witness flag at all -- an unrelated guard. }
procedure PNoWitness(Cond, Other: Boolean);
var
  Xnw: Integer;
  Rnw    : Integer;
begin
  Rnw := 0;
  if Cond then Xnw := 1;
  if Other then Rnw := Xnw;
  Writeln(Rnw);
end;

{ POSITIVE CONTROL: definitely unassigned -- the proof must never reach here. }
procedure PDefinite;
var
  Xdf: Integer;
  Rdf    : Integer;
begin
  Rdf := Xdf;
  Writeln(Rdf);
end;

end.
'@
$file = Join-Path $WorkDir 'uProven.pas'
[System.IO.File]::WriteAllText($file, (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$out  = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$rows = @([regex]::Matches($out, '\[(?<sev>\w+)\]\s+used-before-assignment:\s+(?<msg>[^\r\n]+)') |
          ForEach-Object { [pscustomobject]@{ Sev = $_.Groups['sev'].Value; Msg = $_.Groups['msg'].Value } })

function RowsFor([string]$VarName) {
    @($rows | Where-Object { $_.Msg -match ('"' + [regex]::Escape($VarName) + '"') })
}

Write-Host ''
Write-Host 'THE PROOF SILENCES -- and only when every clause holds' -ForegroundColor Cyan
Check 'all five clauses hold -> SILENT' ((RowsFor 'xpv').Count -eq 0) `
  ("rows=" + ((RowsFor 'xpv') | ConvertTo-Json -Compress))

Write-Host ''
Write-Host 'ONE PAIR PER CLAUSE -- break it and the finding comes back' -ForegroundColor Cyan
foreach ($c in @(
    @('clause 2  flag never initialised (stack garbage reads True)', 'xni'),
    @('clause 3  non-literal write (HaveX := HaveX or Retry)',       'xnl'),
    @('clause 3  flag passed to a call (var-param define)',          'xca'),
    @('clause 4  flag set from a NESTED routine',                    'xnd'),
    @('clause 5  a stray ":= True" site that does not assign X',     'xss'),
    @('clause 1  the flag is a var PARAMETER',                       'xvp'))) {
    $r = RowsFor $c[1]
    Check ($c[0] + ' -> still reported') ($r.Count -ge 1) ("rows=" + ($r.Count))
    Check ($c[0] + ' -> and says POSSIBLE') `
      (($r.Count -ge 1) -and ($r[0].Msg -match 'POSSIBLE use before assignment')) `
      ("sev=" + ($r | ForEach-Object { $_.Sev }))
}

Write-Host ''
Write-Host 'POSITIVE CONTROLS -- without these the silence above is unfalsifiable' -ForegroundColor Cyan
$nw = RowsFor 'xnw'
Check 'a may-unassigned read with NO witness flag is still reported' ($nw.Count -eq 1) `
  ("rows=" + ($nw.Count))
Check 'and it does NOT say POSSIBLE (no pairing was recognised)' `
  (($nw.Count -eq 1) -and ($nw[0].Msg -notmatch 'POSSIBLE')) ("msg=" + ($nw | ForEach-Object { $_.Msg }))
$df = RowsFor 'xdf'
Check 'a DEFINITE unassigned read is still an error' `
  (($df.Count -eq 1) -and ($df[0].Sev -eq 'error')) ("rows=" + ($df | ConvertTo-Json -Compress))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
