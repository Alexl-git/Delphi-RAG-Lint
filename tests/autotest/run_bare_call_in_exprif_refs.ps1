<#
  run_bare_call_in_exprif_refs.ps1 -- a bare parameterless call used as the
  then / else branch of an `if` must reach the reference index as a CALL.

  THE DEFECT (INBOX-bare-call-in-if-else-and-pchar-name-fp.md section 1). Delphi
  13 has an inline if-EXPRESSION (`X:= if C then A else B`), and the grammar
  declares it in conflict with the if-STATEMENT ([$.exprIf, $.statementTr]).
  When BOTH branches of a statement-level `if` are expressions -- a bare
  identifier, `Foo(1)`, `Obj.Bar` -- GLR picks the expression reading. Dumped
  against tree_sitter_delphi13, 2026-10-14:

      if A = B then ResolveOrm else ResolveDfm;
      -> (statement (exprIf condition: (exprBinary ..)
                            then: (identifier) else: (identifier)))

  whereas `if A then ThenOnly;` is (if .. then: (statement (identifier))) and
  `if F then Obj.X else Obj.Y;` is (ifElse .. (statement (exprDot ..)) ..).
  The statement-level bare-call handler only knew `statement -> identifier |
  exprDot`, so an exprIf child emitted NOTHING for its branches: zero refs,
  and unused-private-member reported both routines as dead.

  SIBLINGS FIXED IN THE SAME CHANGE (same "bare identifier in a slot no
  handler reads" family as run_expr_bare_call_refs.ps1):
    * an `ifElse` CONDITION that is a bare identifier emitted no read
      (EmitExpressionIdentReads listed if/while/repeat, not ifElse);
    * an exprIf in EXPRESSION position (`N:= if C then A else B`) emitted no
      read for C, A or B.
  An exprIf branch in expression position stays a 'read' (ambiguous with a
  variable -- see the B3 note in DRagLint.Parser.Delphi13); only a branch in
  STATEMENT position is a call, because an expression statement is a call.

  CONTROLS (pass on the pre-fix engine): the bare call as the body of a
  then-only if, a begin-block, while, for, for-in, with, case arm, case else,
  repeat -- each already wrapped in (statement (identifier)).
  NO-DUPLICATE GUARD: every routine has exactly ONE ref row, so a fix that
  emits the branch twice (call + read at one span, register E1) fails.

  Run from a NEUTRAL CWD. pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

$exePath = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_exprif_calls_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$db = Join-Path $work 'exprif.sqlite'

$unit = @'
unit uExprIf;

interface

type
  TObj = class
  public
    procedure DotThen;
  end;

procedure Run(Obj: TObj; A, B: Integer);

implementation

procedure TObj.DotThen;
begin
end;

procedure StmtThen; begin end;
procedure StmtElse; begin end;
procedure NestA; begin end;
procedure NestB; begin end;
procedure NestC; begin end;
procedure MixElse; begin end;
procedure CallThen(X: Integer); begin end;
procedure CallMixElse; begin end;
procedure ArmThen; begin end;
procedure ArmElse; begin end;
procedure ThenOnly; begin end;
procedure InBlock; begin end;
procedure WhileBody; begin end;
procedure ForBody; begin end;
procedure ForInBody; begin end;
procedure WithBody; begin end;
procedure CaseArm; begin end;
procedure CaseElse; begin end;
procedure RepBody; begin end;
function CondIfElse: Boolean; begin Result:= True; end;
function CondExpr: Boolean; begin Result:= True; end;
function ValA: Integer; begin Result:= 1; end;
function ValB: Integer; begin Result:= 2; end;

procedure Run(Obj: TObj; A, B: Integer);
var
  N, I: Integer;
  F, G, LLocal: Boolean;
  L: TArray<Integer>;
begin
  F:= A > B;
  G:= not F;
  LLocal:= F;
  L:= [];
  { STATEMENT-position exprIf -- the defect }
  if A = B then
    StmtThen
  else
    StmtElse;
  if F then NestA else if G then NestB else NestC;
  if F then Obj.DotThen else MixElse;
  if F then CallThen(1) else CallMixElse;
  case A of
    1: if F then ArmThen else ArmElse;
  end;
  { siblings: ifElse condition, EXPRESSION-position exprIf }
  if CondIfElse then Obj.DotThen else Obj.DotThen;
  N:= if CondExpr then ValA else ValB;
  { a local in the same shape must NOT become a call site }
  if LLocal then N:= 1 else N:= 2;
  { controls -- already (statement (identifier)) }
  if F then ThenOnly;
  if F then begin InBlock end;
  while F do WhileBody;
  for I:= 1 to 2 do ForBody;
  for I in L do ForInBody;
  with Obj do WithBody;
  case N of
    1: CaseArm;
  else
    CaseElse;
  end;
  repeat RepBody until F;
end;

end.
'@
$norm = $unit -replace "`r`n", "`n" -replace "`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $work 'uExprIf.pas'), $norm, [Text.Encoding]::ASCII)

Push-Location $env:TEMP
try {
  & $exePath index $work --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  # sql --json rows are POSITIONAL arrays: [0]=name, [1]=kind, [2]=count.
  $q = "select r.name_text, r.kind, count(*) from refs r join files f on f.id = r.file_id where f.path like '%uExprIf.pas' group by r.name_text, r.kind"
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n" | ConvertFrom-Json
  $byName = @{}
  foreach ($row in $j.rows) {
    $nm = ([string]$row[0]).ToLowerInvariant()
    if (-not $byName.ContainsKey($nm)) { $byName[$nm] = @{} }
    $byName[$nm][[string]$row[1]] = [int]$row[2]
  }
  Check 'refs were read for the fixture' ($byName.ContainsKey('thenonly')) "names=$($byName.Count)"

  function Refs($name) { $k = $name.ToLowerInvariant(); if ($byName.ContainsKey($k)) { $byName[$k] } else { @{} } }
  function Total($name) { $t = 0; foreach ($v in (Refs $name).Values) { $t += $v }; $t }
  function ExpectCall($name) {
    $r = Refs $name; $c = if ($r.ContainsKey('call')) { $r['call'] } else { 0 }; $t = Total $name
    Check "$name has exactly one ref, kind call" (($c -eq 1) -and ($t -eq 1)) "call=$c total=$t"
  }
  function ExpectRead($name) {
    $r = Refs $name; $c = if ($r.ContainsKey('read')) { $r['read'] } else { 0 }
    $k = if ($r.ContainsKey('call')) { $r['call'] } else { 0 }
    Check "$name is read, not a call site" (($c -ge 1) -and ($k -eq 0)) "read=$c call=$k"
  }

  Write-Host 'CONTROLS (pass on the pre-fix engine):' -ForegroundColor Cyan
  foreach ($nm in 'ThenOnly','InBlock','WhileBody','ForBody','ForInBody','WithBody','CaseArm','CaseElse','RepBody','CallThen') { ExpectCall $nm }

  Write-Host 'DEFECT -- bare call as a branch of a statement-level exprIf:' -ForegroundColor Cyan
  foreach ($nm in 'StmtThen','StmtElse','NestA','NestB','NestC','MixElse','CallMixElse','ArmThen','ArmElse') { ExpectCall $nm }
  $dt = Refs 'DotThen'; $dc = if ($dt.ContainsKey('call')) { $dt['call'] } else { 0 }
  Check 'Obj.DotThen in an exprIf branch is a call (3 sites)' ($dc -eq 3) "call=$dc"

  Write-Host 'SIBLINGS -- ifElse condition, expression-position exprIf:' -ForegroundColor Cyan
  ExpectRead 'CondIfElse'
  ExpectRead 'CondExpr'
  ExpectRead 'ValA'
  ExpectRead 'ValB'
  ExpectRead 'LLocal'

  Write-Host 'find-callers' -ForegroundColor Cyan
  foreach ($nm in 'StmtThen','StmtElse','NestC') {
    $fc = (& $exePath query find-callers --name $nm --db $db 2>$null | Out-String)
    Check "find-callers resolves $nm" ($fc -match 'uExprIf\.pas')
  }
} finally { Pop-Location; Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
