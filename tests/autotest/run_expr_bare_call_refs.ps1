<#
  run_expr_bare_call_refs.ps1 -- a bare parameterless call in EXPRESSION position
  must reach the reference index.

  THE BUG (PLAN-autodoc-and-backlog-2026-08-06, PHASE B item B3)
  --------------------------------------------------------------------------------
  Delphi lets a parameterless routine be invoked by NAME ALONE, and in expression
  position that is indistinguishable from reading a variable:

      if not LoopsBackIntoScan then   <- exprUnary operand
      while KeepGoing do              <- while condition
      N:= ItemLimit * 2;              <- exprBinary lhs

  None of those is an `exprCall` node, and none of them was reached by any of the
  v0.42 usage-ref handlers either -- those covered only `obj.Member`, an
  assignment's bare-identifier RHS, and a bare argument. So NO ref row was written
  at all and the routine showed ZERO references. `unused-public-symbol` then
  reported live, called code as dead public API -- the same harm as the nested-
  routine gap (run_nested_routine_refs.ps1), from a different hole.

  WHY THE REF IS 'read' AND NOT 'call'. At parse time `KeepGoing` in a condition
  is genuinely ambiguous: it is either a parameterless call or a variable read,
  and nothing in the tree distinguishes them. Emitting REF_KIND_CALL would put
  every variable read into the call universe that ResolveCallTargets resolves and
  that both unresolved-call queries take their complement against -- which is the
  exact defect T3i closed (see the block comment above REF_KIND_CALL in
  DRagLint.Core.Model). 'read' is what the identical ambiguity already gets in
  `Result := MaxItems;` and `Foo(Bar)`, and it is enough: FindCallersByName --
  which is what unused-public-symbol consults -- matches ANY ref kind.

  This asserts the reference is recorded, that find-callers sees it, that the rule
  still fires on a genuinely uncalled export (a "fix" that merely disabled the rule
  would pass the first half and fail that), and that the call universe was NOT
  widened.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-expr-refs"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$src = @'
unit exprrefs;

interface

function LoopsBackIntoScan: Boolean;
function KeepGoing: Boolean;
function ItemLimit: Integer;
function GuardedByParens: Boolean;
function SelectorSource: Integer;
function NeverCalledAtAll: Boolean;

procedure Outer;

implementation

function LoopsBackIntoScan: Boolean;
begin
  result:= True;
end;

function KeepGoing: Boolean;
begin
  result:= False;
end;

function ItemLimit: Integer;
begin
  result:= 7;
end;

function GuardedByParens: Boolean;
begin
  result:= True;
end;

function SelectorSource: Integer;
begin
  result:= 1;
end;

function NeverCalledAtAll: Boolean;
begin
  result:= False;
end;

procedure Outer;
var
  N     : Integer;
  LLocal: Boolean;
begin
  LLocal:= False;
  { each of these is the ONLY call site of its routine, and every one of them is
    a bare parameterless call sitting in EXPRESSION position }
  if not LoopsBackIntoScan then
    Writeln('a');
  while KeepGoing do
    Writeln('b');
  N:= ItemLimit * 2;
  if (GuardedByParens) then
    Writeln('c');
  case SelectorSource of
    0: Writeln('d');
  end;
  { a plain local read in the same shape -- must NOT become a call site }
  if not LLocal then
    Writeln(N);
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path $WorkDir 'exprrefs.pas'), $src, [System.Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'expr.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null

$py = Join-Path $WorkDir 'refs.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
out = {}
for nm in ('LoopsBackIntoScan','KeepGoing','ItemLimit','GuardedByParens','SelectorSource','NeverCalledAtAll'):
    out[nm] = c.execute("SELECT COUNT(*) FROM refs WHERE name_text LIKE ? COLLATE NOCASE", (nm,)).fetchone()[0]
out['LLocal_call_refs'] = c.execute(
    "SELECT COUNT(*) FROM refs WHERE name_text LIKE 'LLocal' COLLATE NOCASE AND kind = 'call'").fetchone()[0]
out['LLocal_refs'] = c.execute(
    "SELECT COUNT(*) FROM refs WHERE name_text LIKE 'LLocal' COLLATE NOCASE").fetchone()[0]
print(json.dumps(out))
c.close()
'@ | Set-Content $py -Encoding ascii
$refs = (& python $py $db) -join "`n" | ConvertFrom-Json

Write-Host 'Reference index' -ForegroundColor Cyan
Check 'exprUnary operand  (if not X then)' ($refs.LoopsBackIntoScan -ge 1) "refs=$($refs.LoopsBackIntoScan)"
Check 'while condition    (while X do)'    ($refs.KeepGoing         -ge 1) "refs=$($refs.KeepGoing)"
Check 'exprBinary operand (X * 2)'         ($refs.ItemLimit         -ge 1) "refs=$($refs.ItemLimit)"
Check 'exprParens         (if (X) then)'   ($refs.GuardedByParens   -ge 1) "refs=$($refs.GuardedByParens)"
Check 'case selector      (case X of)'     ($refs.SelectorSource    -ge 1) "refs=$($refs.SelectorSource)"
Check 'an export nobody calls has no refs' ($refs.NeverCalledAtAll  -eq 0) "refs=$($refs.NeverCalledAtAll)"

Write-Host ''
Write-Host 'The call universe was not widened' -ForegroundColor Cyan
Check 'a local variable in a condition IS recorded' ($refs.LLocal_refs -ge 1) "refs=$($refs.LLocal_refs)"
Check 'a local variable in a condition is NOT a call site' ($refs.LLocal_call_refs -eq 0) `
  "call-kind refs=$($refs.LLocal_call_refs)"

Write-Host ''
Write-Host 'find-callers' -ForegroundColor Cyan
foreach ($nm in 'LoopsBackIntoScan','KeepGoing','ItemLimit','GuardedByParens','SelectorSource') {
  $fc = (& $Exe query find-callers --name $nm --db $db 2>$null | Out-String)
  Check "find-callers resolves $nm" ($fc -match 'exprrefs\.pas')
}

Write-Host ''
Write-Host 'unused-public-symbol' -ForegroundColor Cyan
$lint = (& $Exe lint-all --db $db 2>$null | Out-String)
foreach ($nm in 'LoopsBackIntoScan','KeepGoing','ItemLimit','GuardedByParens','SelectorSource') {
  Check "$nm is NOT called dead" (-not ($lint -match "unused-public-symbol.*$nm"))
}
Check 'a genuinely uncalled export IS still reported' `
  ($lint -match 'unused-public-symbol.*NeverCalledAtAll') 'else the fix just disabled the rule'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
