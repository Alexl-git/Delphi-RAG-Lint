<#
  run_dangling_else_cfg.ps1 -- a nested single-statement `if/else` must be
  DECOMPOSED by the CFG builder, not swallowed as one opaque statement.

  THE DEFECT THIS PINS:
    tree-sitter-delphi13 types the dangling-else construct

        if A then           <- an `if` with NO else
          if B(out V) then  <- single-statement then-part
            S1
          else
            S2

    NOT as `ifElse` but as an **exprIf**, wrapped in a **statement** node
    (measured with tools\dumpnode; an if/else nested in a `for`, `while`, `case`
    or `begin..end` is a plain `ifElse` and was always handled). TBuilderState.
    EmitStmt has arms for 'if', 'ifElse', 'block' and 'statements' -- none for
    'statement' or 'exprIf' -- so the whole nested construct fell through to the
    unknown-statement path and was added as ONE opaque block item.

    Once it is one item, DRagLint.Diagnostics.FlowChecks' per-item replay hands
    CollectReadsAndCallDefs a node spanning BOTH branches and runs the read
    check before that item's own CallDefs are applied. So V -- definitely
    assigned by the `out` argument in the inner CONDITION, which dominates both
    branches -- is reported as read before assignment, anchored on the inner
    `if` keyword rather than on the read.

    Real instances: DataCopy uZeissRoutines.pas:1375 and :1675, both
    `if SafeDelete(LFile, LSweepErr) then inc(LCleaned) else pLogger.LogError(
    ... [LFile, LSweepErr, ...])`. The line the finding pointed at is a WRITE,
    so these could not even be silenced with `dl:ok` honestly.

  Bisected 2026-08-14 over 13 variants; the probe unit is kept at
  docs\probe-used-before-assignment-dangling-else.pas. What the bisect killed:
  the else branch is NOT where the read has to be (it fires with the read in the
  THEN branch), the outer condition's content is irrelevant (`if True` fires),
  and the read FORM is irrelevant (an open-array element and a bare `V + 1` both
  fire). Only the dangling-else ambiguity matters -- give either `if` a
  `begin..end`, give the outer one an `else`, take the inner one's `else` away,
  or make the outer construct a `while`, and it goes silent.

  Asserts:
    1. Bad     -- the dangling-else shape reports NO used-before-assignment.
                  THIS IS THE FIX; it fails before it and passes after.
    2. Good    -- the same code with begin..end still reports none (the fix must
                  not have been achieved by breaking the shape that worked).
    3. Unsafe  -- a genuinely-unassigned read after an ELSELESS `if Fill(...)`
                  still DOES report. Without this the whole file would pass with
                  the rule disabled, which is the failure mode two earlier doc
                  guards in this repo actually shipped with.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dangling-else-cfg"
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

# Fill assigns its `out` parameter unconditionally, so a call to it in an `if`
# CONDITION defines Err on BOTH branches. Every read of Err below is therefore
# safe EXCEPT the one in Unsafe, where the elseless `if` can skip the call.
$FixtureBody = @'
unit uDangle;
interface
function Fill(const A: string; out E: DWord): Boolean;
procedure Bad(const F: string);
procedure Good(const F: string);
procedure Unsafe(const F: string);
implementation
function Fill(const A: string; out E: DWord): Boolean;
begin
  E := Length(A);
  Result := E > 0;
end;
procedure Bad(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
    if Fill(F, Err) then
      Writeln('ok')
    else
      Writeln(Err + 1);
end;
procedure Good(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
  begin
    if Fill(F, Err) then
      Writeln('ok')
    else
      Writeln(Err + 1);
  end;
end;
procedure Unsafe(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
    Fill(F, Err);
  Writeln(Err + 1);
end;
end.
'@
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
$file = Join-Path $WorkDir 'uDangle.pas'
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

$src = Get-Content $file
# Anchor rows are DERIVED from the fixture, so editing it cannot silently
# retarget the assertions at the wrong routine.
#
# TAKE THE **LAST** MATCH, NOT THE FIRST. Each routine is named twice -- once in
# the interface, once in the implementation -- and -First 1 picks the interface
# header. That put every anchor at rows 4-6, so EVERY finding in the file
# attributed to the last routine and the two "no finding" assertions passed
# while the fixture was firing. This test went green for the wrong reason once
# already; the row echo in each Check's detail column is what exposed it.
function Line-Of([string]$Pattern) {
  ($src | Select-String -Pattern $Pattern -SimpleMatch | Select-Object -Last 1).LineNumber
}
$badRow    = Line-Of 'procedure Bad(const F: string);'
$goodRow   = Line-Of 'procedure Good(const F: string);'
$unsafeRow = Line-Of 'procedure Unsafe(const F: string);'
if (($badRow -ge $goodRow) -or ($goodRow -ge $unsafeRow)) {
  Write-Host "FATAL: anchor rows not in source order (Bad=$badRow Good=$goodRow Unsafe=$unsafeRow)" -ForegroundColor Red
  exit 2
}

$out = & $Exe lint $file 2>&1 | Out-String
$hits = @([regex]::Matches($out, 'uDangle\.pas:(\d+):(\d+)\s+\[(\w+)\]\s+used-before-assignment') | ForEach-Object {
  [pscustomobject]@{ Row = [int]$_.Groups[1].Value; Sev = $_.Groups[3].Value }
})
# Attribute each finding to the routine it falls in: the last declaration header
# at or before its row.
function In-Routine([int]$Row) {
  if ($Row -ge $unsafeRow) { return 'Unsafe' }
  if ($Row -ge $goodRow)   { return 'Good'   }
  if ($Row -ge $badRow)    { return 'Bad'    }
  '(none)'
}
function Rows-In([string]$Proc) {
  ($hits | Where-Object { (In-Routine $_.Row) -eq $Proc } | ForEach-Object { $_.Row }) -join ','
}

Write-Host 'A dangling-else if/else must be decomposed, not swallowed' -ForegroundColor Cyan
Write-Host ("  anchors: Bad={0} Good={1} Unsafe={2}; findings at {3}" -f `
  $badRow, $goodRow, $unsafeRow, (($hits | ForEach-Object { $_.Row }) -join ',')) -ForegroundColor DarkGray
$badRows    = Rows-In 'Bad'
$goodRows   = Rows-In 'Good'
$unsafeRows = Rows-In 'Unsafe'
Check 'Bad: no used-before-assignment (out arg in the inner condition dominates both branches)' `
  ($badRows -eq '')  "rows=$badRows"
Check 'Good: no used-before-assignment (the begin..end shape still works)' `
  ($goodRows -eq '') "rows=$goodRows"
Check 'Unsafe: the rule STILL FIRES on a genuinely unassigned read' `
  ($unsafeRows -ne '') "rows=$unsafeRows"

if ($unsafeRows -eq '') {
  Write-Host '  !! The positive control did not fire. The two assertions above' -ForegroundColor Yellow
  Write-Host '  !! prove nothing -- they would also pass with the rule off.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
