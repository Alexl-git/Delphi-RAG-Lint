<#
  run_ifelse_walker_audit.ps1 -- wave 149 EX1 item (1).

  Grammar v1.4.4 (PR #2, "an if statement is not read as an if expression")
  turned a statement-level `if C then X else Y` whose branches are both
  expressions -- the dangling else `if A then if B then X else Y` included --
  from (statement (exprIf ..)) into a plain `ifElse` with (statement ..)
  branches. Five walkers carried an exprIf arm: Parser.Delphi13 Walk's
  statement arm -> WalkStatementExprIf, Flow.Lattices
  CollectReadsAndCallDefs.Walk, FlowChecks ScanItemArgs.Walk, DataFlowFacts
  TCollector.Eval and Query.SyntaxCount ClassifyNode. 147 INT asked for the
  audit after the battery caught only AstChecks MaxNest.

  AUDIT RESULT (lanes\149\EX1\REPORT.md): none needs a change. The Cfg splits
  an ifElse into a condition item and branch blocks before the two item
  walkers (Lattices, ScanItemArgs) see it, and a lambda body -- the one place a
  whole if statement can sit inside an item -- is its own scope whose captured
  locals are excluded; the parser's generic `statement` arm emits the branch
  calls; DataFlowFacts FlatWalk / Eval reach the branches through their generic
  arms; SyntaxCount now counts only a REAL if-expression. The exprIf arms stay
  for the expression form (`X := if C then A else B`) and older grammar DLLs.

  This guard pins the post-1.4.4 behaviour per walker:
    P  parser       : every branch call is exactly ONE 'call' ref row (dangling
                      and plain if/else; a double emit = the co-located E1 shape).
    L  Lattices     : a read in the THEN and in the ELSE arm of a dangling else
                      is reported (used-before-assignment); a var call-defined by
                      the CONDITION is not reported in its branch.
    S  ScanItemArgs : an out arg in an else arm does not kill the store
                      (dead-store-before-out-arg silent there).
    D  DataFlowFacts: the param S passed in the else arm writes data_flows
                      row (arg Sink <- param S).
    C  SyntaxCount  : if-expr = 1 (the one real inline if), not 3.
  POSITIVE CONTROLS: PlainRead fires used-before-assignment, PlainOut fires
  dead-store-before-out-arg, InlineIf is counted -- so the guard fails with the
  rules off or the counter broken.
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
$work = Join-Path $env:TEMP ('draglint_ifelse_walk_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($work) | Out-Null
$db = Join-Path $work 'ifelse.sqlite'
$pas = Join-Path $work 'uIfElseWalk.pas'

$unit = @'
unit uIfElseWalk;

interface

procedure DanglingCalls(A, B: Boolean);
procedure PlainCalls(A: Boolean);
procedure CondDefines(A: Boolean);
procedure ElseArmRead(A, B: Boolean);
procedure ThenArmRead(A, B: Boolean);
procedure PlainRead;
procedure ElseArmOut(A, B: Boolean);
procedure PlainOut;
procedure ElseArmFlow(A, B: Boolean; S: string);
function InlineIf(A: Boolean): Integer;

implementation

function TryGet(out V: Integer): Boolean;
begin
  V := 1;
  Result := True;
end;

procedure Use(V: Integer);
begin
end;

procedure Sink(const S: string);
begin
end;

procedure Foo;
begin
end;

procedure Bar;
begin
end;

procedure Baz;
begin
end;

procedure Qux;
begin
end;

procedure DanglingCalls(A, B: Boolean);
begin
  if A then if B then Foo else Bar;
end;

procedure PlainCalls(A: Boolean);
begin
  if A then Baz else Qux;
end;

procedure CondDefines(A: Boolean);
var
  V: Integer;
begin
  if A then if TryGet(V) then Use(V) else Foo;
end;

procedure ElseArmRead(A, B: Boolean);
var
  V: Integer;
begin
  if A then if B then Foo else Use(V);
end;

procedure ThenArmRead(A, B: Boolean);
var
  V: Integer;
begin
  if A then if B then Use(V) else Foo;
end;

procedure PlainRead;
var
  V: Integer;
begin
  Use(V);
end;

procedure ElseArmOut(A, B: Boolean);
var
  V: Integer;
begin
  V := 5;
  if A then if B then Foo else TryGet(V);
  Use(V);
end;

procedure PlainOut;
var
  V: Integer;
begin
  V := 5;
  TryGet(V);
  Use(V);
end;

procedure ElseArmFlow(A, B: Boolean; S: string);
begin
  if A then if B then Foo else Sink(S);
end;

function InlineIf(A: Boolean): Integer;
begin
  Result := if A then 1 else 2;
end;

end.
'@
[IO.File]::WriteAllText($pas, ($unit -replace "`r?`n", "`r`n"))

& $exePath index $work --db $db 2>&1 | Out-Null
Check 'index' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# P: sql --json rows are POSITIONAL arrays (name_text, kind, start_line, start_col)
$q = "select name_text, kind, start_line, start_col from refs where name_text in ('Foo','Bar','Baz','Qux','Sink') order by start_line, start_col"
$rows = @((& $exePath sql --query $q --db $db --json 2>$null | ConvertFrom-Json).rows)
$got = ($rows | ForEach-Object { '{0}:{1}:{2}:{3}' -f $_[0], $_[1], $_[2], $_[3] }) -join ' '
$want = 'Foo:call:50:23 Bar:call:50:32 Baz:call:55:13 Qux:call:55:22 Foo:call:62:43 Foo:call:69:23 Foo:call:76:35 Foo:call:91:23 Foo:call:106:23 Sink:call:106:32'
Check 'P branch calls, one call row each' ($got -eq $want) "got=[$got]"

# L / S: lint --json is a bare array of {rule, start_line, ...}
$lint = @(& $exePath lint $pas --db $db --rule 'used-before-assignment,dead-store-before-out-arg' --json 2>$null | ConvertFrom-Json)
$uba = @($lint | Where-Object { $_.rule -eq 'used-before-assignment' } | ForEach-Object { [int]$_.start_line } | Sort-Object)
$dso = @($lint | Where-Object { $_.rule -eq 'dead-store-before-out-arg' } | ForEach-Object { [int]$_.start_line } | Sort-Object)
Check 'L positive control PlainRead (83) fires' ($uba -contains 83) "uba=[$($uba -join ',')]"
Check 'L else-arm read (69) fires' ($uba -contains 69)
Check 'L then-arm read (76) fires' ($uba -contains 76)
Check 'L condition-defined V is not read-before-assign (62)' (-not ($uba -contains 62))
Check 'L exactly 3 findings' ($uba.Count -eq 3)
Check 'S positive control PlainOut (99) fires' ($dso -contains 99) "dso=[$($dso -join ',')]"
Check 'S else-arm out arg does not kill the store (89)' ($dso.Count -eq 1)

# D: data_flows row for the else-arm argument
$q = "select dst_kind, dst_name, src_kind, src_name from data_flows where dst_line = 106"
$rows = @((& $exePath sql --query $q --db $db --json 2>$null | ConvertFrom-Json).rows)
$got = ($rows | ForEach-Object { '{0}:{1}<-{2}:{3}' -f $_[0], $_[1], $_[2], $_[3] }) -join ' '
Check 'D else-arm arg flow row' ($got -eq 'arg:Sink<-param:S') "got=[$got]"

# C: syntax-count --json = {totals: {feature: n}}
$sc = & $exePath syntax-count --in $pas --feature if-expr --json 2>$null | ConvertFrom-Json
$n = $sc.totals.'if-expr'
Check 'C if-expr counts the real inline if only' ($n -eq 1) "if-expr=$n"

try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "  (scratch kept: $work)" }
if ($script:Failed) { Write-Host 'run_ifelse_walker_audit: FAIL'; exit 1 }
Write-Host 'run_ifelse_walker_audit: PASS'
exit 0
