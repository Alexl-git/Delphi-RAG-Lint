<#
  run_finally_leading_comment.ps1 -- a comment as the FIRST thing inside a
  `finally` block must not delete the block from the control-flow graph.

  THE DEFECT THIS PINS. `DRagLint.Analysis.Cfg.pas` located the finally body by
  taking the first named child after `kFinally` that was not `kEnd`. A comment
  written at the top of the block is a named child of the `try` node itself --
  (kTry)(statements)(kFinally)(comment)(statements)(kEnd) -- so the COMMENT was
  taken as the body, EmitStmt hit its opaque default, and the real `statements`
  node never entered the CFG. The whole block vanished.

  IT WAS NOT ONE RULE'S BUG, which is why this runner asserts in both
  directions. On the same shape:
    * write-only-local FALSELY FIRED on a local whose only read is in the block;
    * used-before-assignment FALSELY WENT SILENT on a genuine use.
  A fix that only silenced the false positive would leave the false negative,
  and a guard that only checked the false positive would call that done.

  Reported from DataCopy 2026-09-02 as `X := Create; try ... finally X.Free;
  end` with a comment in the finally -- the commonest resource shape in Delphi,
  and the one this project's own rules mandate.

  BOTH COMMENT STYLES. An early bisection recorded `{ brace }` as unaffected.
  That was WRONG and the cell was vacuous -- that fixture had an unrelated read
  of the local in the `try` body, so it went silent for a reason unconnected to
  the test. Both styles attach identically in the AST and both are asserted here.

  `except` was never affected: its scan already filtered by node type. P7 pins
  that, so a future "simplification" of the finally scan cannot quietly take
  except with it.

  RED-CHECK: against an engine built before the Cfg.pas fix, P3/P4 report
  nothing and P5/P6 report write-only-local. Four assertions fail.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_finally_comment",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  if ($Quiet) { if (-not $ok) { $script:fail = $true }; return }
  Write-Host ("  [{0}] {1}" -f (@('FAIL', 'PASS')[[int]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int]$ok])
  if (-not $ok) { if ($d) { Write-Host "        $d" -ForegroundColor DarkGray }; $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null }

$src = @'
unit uFinallyComment;

interface

procedure P1_RuleIsLive;
procedure P2_UbaPlainControl;
procedure P3_UbaFinallyNoComment;
procedure P4_UbaFinallyLineComment;
procedure P5_WolFinallyLineComment;
procedure P6_WolFinallyBraceComment;
procedure P7_ExceptLeadingComment;
procedure P8_WolFinallyNoComment;

implementation

type
  TThing = class
    procedure Go;
  end;

var
  GFlag: Boolean;

procedure TThing.Go;
begin
end;

{ P1: a genuine write-only local. MUST FIRE -- if it does not, write-only-local
  is off or broken and every silence assertion below is vacuous. }
procedure P1_RuleIsLive;
var
  Z: Integer;
begin
  Z := 1;
  GFlag := True;
end;

{ P2: a genuine use-before-assignment with no try at all. MUST FIRE -- the
  liveness control for the other rule. }
procedure P2_UbaPlainControl;
var
  A, B: Integer;
begin
  B := A;
  GFlag := B > 0;
end;

{ P3: use-before-assignment inside a finally, no comment. MUST FIRE -- proves
  finally bodies are analysed at all. }
procedure P3_UbaFinallyNoComment;
var
  A, B: Integer;
begin
  try
    GFlag := True;
  finally
    B := A;
    GFlag := B > 0;
  end;
end;

{ P4: identical, but the finally opens with a line comment. MUST FIRE.
  Before the fix this was SILENT -- a false negative. }
procedure P4_UbaFinallyLineComment;
var
  A, B: Integer;
begin
  try
    GFlag := True;
  finally
    // leading comment
    B := A;
    GFlag := B > 0;
  end;
end;

{ P5: the reported shape. The local's ONLY read is in the finally, after a line
  comment. MUST NOT FIRE. Before the fix it did -- a false positive. }
procedure P5_WolFinallyLineComment;
var
  LThread: TThing;
begin
  LThread := TThing.Create;
  try
    GFlag := True;
  finally
    // leading comment
    LThread.Free;
  end;
end;

{ P6: the same with a BRACE comment. MUST NOT FIRE. Recorded once as unaffected;
  that observation came from a vacuous fixture. }
procedure P6_WolFinallyBraceComment;
var
  LThread: TThing;
begin
  LThread := TThing.Create;
  try
    GFlag := True;
  finally
    { brace comment }
    LThread.Free;
  end;
end;

{ P7: except was never affected. MUST NOT FIRE -- pins that the finally scan's
  repair did not drag except along with it. }
procedure P7_ExceptLeadingComment;
var
  LThread: TThing;
begin
  LThread := TThing.Create;
  try
    GFlag := True;
  except
    // leading comment
    LThread.Free;
  end;
end;

{ P8: the plain shape, no comment. MUST NOT FIRE -- it never did. }
procedure P8_WolFinallyNoComment;
var
  LThread: TThing;
begin
  LThread := TThing.Create;
  try
    GFlag := True;
  finally
    LThread.Free;
  end;
end;

end.
'@

$pas = Join-Path $WorkDir 'uFinallyComment.pas'
[System.IO.File]::WriteAllText($pas, ($src -replace "`r`n", "`n" -replace "`n", "`r`n"),
                               (New-Object System.Text.UTF8Encoding($false)))

# used-before-assignment is store-backed: an UNINDEXED file runs neither the
# store-backed nor the project rules, and the engine says so in a trailing note.
# A run without --db would make P2/P3/P4 pass vacuously by silence.
$db = Join-Path $WorkDir 'fc.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
$out = (& $Exe lint $pas --db $db 2>&1 | Out-String) -split "`n"

# Map each finding to the routine it lands in. Anchored on the IMPLEMENTATION
# headers, which here are all `procedure Name;` at column 1.
$lines = Get-Content $pas
function RoutineAt([int]$ln) {
  $r = '?'
  for ($i = 0; $i -lt $ln -and $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^(?:procedure|function)\s+(\w+)\s*(?:\(|:|;)') { $r = $Matches[1] }
  }
  return $r
}
function Fired([string]$rule, [string]$routine) {
  foreach ($l in $out) {
    if ($l -match 'uFinallyComment\.pas:(\d+):\d+\s+\[\w+\]\s+' + [regex]::Escape($rule)) {
      if ((RoutineAt ([int]$Matches[1])) -eq $routine) { return $true }
    }
  }
  return $false
}

Write-Host '== a comment leading a `finally` must not delete the block from the CFG ==' -ForegroundColor Cyan
Write-Host '-- liveness controls (a failure here makes every assertion below vacuous)' -ForegroundColor DarkGray
Check 'P1 write-only-local is live'        (Fired 'write-only-local'        'P1_RuleIsLive')        'a genuine write-only local must be reported'
Check 'P2 used-before-assignment is live'  (Fired 'used-before-assignment'  'P2_UbaPlainControl')   'needs --db; without an index this rule does not run at all'
Check 'P3 finally bodies are analysed'     (Fired 'used-before-assignment'  'P3_UbaFinallyNoComment') 'a use-before-assignment inside a plain finally'

Write-Host '-- the defect: false NEGATIVE (the block vanished)' -ForegroundColor DarkGray
Check 'P4 a line comment does not hide a use-before-assignment' `
  (Fired 'used-before-assignment' 'P4_UbaFinallyLineComment') 'RED before the Cfg.pas fix -- the finally block was not in the CFG'

Write-Host '-- the defect: false POSITIVE (the read vanished with the block)' -ForegroundColor DarkGray
Check 'P5 a line comment does not hide the read of a local' `
  (-not (Fired 'write-only-local' 'P5_WolFinallyLineComment')) 'the reported DataCopy shape'
Check 'P6 a brace comment does not either' `
  (-not (Fired 'write-only-local' 'P6_WolFinallyBraceComment')) 'once recorded as unaffected -- from a vacuous fixture'

Write-Host '-- unchanged neighbours' -ForegroundColor DarkGray
Check 'P7 except was never affected and still is not' `
  (-not (Fired 'write-only-local' 'P7_ExceptLeadingComment')) ''
Check 'P8 the plain finally shape stays silent' `
  (-not (Fired 'write-only-local' 'P8_WolFinallyNoComment')) ''

Write-Host ''
if ($script:fail) { Write-Host 'FINALLY-LEADING-COMMENT GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FINALLY-LEADING-COMMENT GUARD: PASS' -ForegroundColor Green
exit 0
