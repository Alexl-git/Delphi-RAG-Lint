<#
  run_double_free_loops_and_members.ps1 -- `double-free` counted three things as
  "the same object freed twice" that are three DIFFERENT objects.

  THE DEFECT THIS PINS: 42 findings on this repo's own source, every one false,
  in three shapes with three separate causes. Sampled 42/42 against source on
  2026-08-16; none was a double free.

    A. THE FREED EXPRESSION IS NOT THE VARIABLE.
         for ColKv in SqlColumns do ColKv.Value.Free;   <- reported on ColKv
         if Assigned(FieldMaps[I]) then FieldMaps[I].Free;
       DetectFreedVarKind resolved the freed operand with LeftmostBaseVar, which
       walks DOWN to the leftmost identifier -- so `X.Value.Free` and `X[I].Free`
       were both credited to X. What they free is a member or an element: a
       different object every pass. Fixed by FreedOperandVar, which requires the
       operand to BE the variable (a bare identifier), not merely start with it.

    B. THE for-in ITERATOR IS REBOUND EVERY PASS.
         for L in ImplBy.Values do L.Free;              <- reported on L
       The CFG already records the iterator in TCfgBlock.EntryDefs and the
       definite-assignment lattice already honours it; TFreedState did not, so
       the loop back-edge carried "L is dangling" into the next iteration -- an
       iteration that sees a different object. Fixed by ApplyEntryDefs, now the
       single shared implementation both lattices and both replays call.

    C. AN INLINE `var X := T.Create` WAS NOT A DEFINITION AT ALL.
         for var I := 0 to N do
         begin
           var SB := TStringBuilder.Create;
           try ... finally SB.Free; end;                <- reported on SB
         end;
       AssignmentTargetIndex resolved a varAssignDef lhs with NamedChild(0) --
       and in tree-sitter-delphi13 the `var` KEYWORD is a named child, so it
       looked up a routine var literally called "var" and returned -1. Every
       inline declaration therefore failed to kill any prior state. This is the
       fourth bug in this tree from "keywords are NAMED nodes"; the fix is
       FirstIdentChild, the same one LeftmostBaseVar already used two functions
       away.

  THE THREE POSITIVE CONTROLS ARE THE POINT OF THIS FILE. The cheap fix for
  every rule in this family is to stop reporting inside loops, and that silences
  the real thing. So:
    * GenuineStraightLine -- Free; Free; with no loop at all MUST fire.
    * GenuineInLoop       -- ONE object created OUTSIDE a loop and freed INSIDE
      it is a genuine double free from the second iteration on, and MUST still
      fire. This is what separates "the object is per-iteration" (B, C) from
      "the free is in a loop" (which is not, by itself, a reason to stay quiet).
    * GenuineInlineDouble -- an inline-declared var freed twice MUST fire, so
      fix C cannot degrade into "inline vars are exempt".
  Without all three, every assertion above would pass with the rule disabled.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-double-free-loops"
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

$FixtureBody = @'
unit uDoubleFreeLoops;
interface
procedure MemberOfIterator(const F: string);
procedure ElementOfArray(const F: string);
procedure ForInIterator(const F: string);
procedure InlineVarInLoop(const F: string);
procedure GenuineStraightLine(const F: string);
procedure GenuineInLoop(const F: string);
procedure GenuineInlineDouble(const F: string);
implementation
uses System.SysUtils, System.Classes, System.Generics.Collections;

{ CAUSE A -- Pair.Value is a member of Pair, a different object every pass. }
procedure MemberOfIterator(const F: string);
var
  Map : TDictionary<string, TStringList>;
  Pair: TPair<string, TStringList>;
begin
  Map := TDictionary<string, TStringList>.Create;
  Map.Add(F, TStringList.Create);
  for Pair in Map do Pair.Value.Free;
  Map.Free;
end;

{ CAUSE A -- Items[I] is an element of Items, a different object every pass. }
procedure ElementOfArray(const F: string);
var
  Items: TArray<TStringList>;
  I    : Integer;
begin
  SetLength(Items, 2);
  Items[0] := TStringList.Create;
  Items[1] := TStringList.Create;
  Items[0].Add(F);
  for I := 0 to High(Items) do Items[I].Free;
end;

{ CAUSE B -- the for-in iterator is rebound at the top of every iteration. }
procedure ForInIterator(const F: string);
var
  List: TObjectList<TStringList>;
  L   : TStringList;
begin
  List := TObjectList<TStringList>.Create(False);
  List.Add(TStringList.Create);
  List[0].Add(F);
  for L in List do L.Free;
  List.Free;
end;

{ CAUSE C -- a fresh object per iteration, declared with an inline var. }
procedure InlineVarInLoop(const F: string);
begin
  for var I := 0 to 3 do
  begin
    var SB := TStringBuilder.Create;
    try
      SB.Append(F);
    finally
      SB.Free;
    end;
  end;
end;

{ POSITIVE CONTROL 1 -- no loop anywhere. MUST fire. }
procedure GenuineStraightLine(const F: string);
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  SB.Append(F);
  SB.Free;
  SB.Free;
end;

{ POSITIVE CONTROL 2 -- ONE object, created outside the loop, freed inside it.
  From the second iteration on this frees an already-freed pointer, so a fix
  that exempts "a Free inside a loop" would wrongly silence it. MUST fire. }
procedure GenuineInLoop(const F: string);
var
  SB: TStringBuilder;
  I : Integer;
begin
  SB := TStringBuilder.Create;
  SB.Append(F);
  for I := 0 to 3 do
    SB.Free;
end;

{ POSITIVE CONTROL 3 -- an inline-declared var freed twice. MUST fire, so the
  varAssignDef fix cannot degrade into "inline vars are exempt". }
procedure GenuineInlineDouble(const F: string);
begin
  var SB := TStringBuilder.Create;
  SB.Append(F);
  SB.Free;
  SB.Free;
end;

end.
'@
$file = Join-Path $WorkDir 'uDoubleFreeLoops.pas'
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

# Anchors derived from the fixture. LAST match: every routine is named twice
# (interface + implementation) and -First would put every anchor in the
# interface section, attributing every finding to the final routine.
$src = Get-Content $file
$names = @('MemberOfIterator','ElementOfArray','ForInIterator','InlineVarInLoop',
           'GenuineStraightLine','GenuineInLoop','GenuineInlineDouble')
function Impl-Row([string]$Name) {
  ($src | Select-String -Pattern ("procedure {0}(const F: string);" -f $Name) -SimpleMatch |
     Select-Object -Last 1).LineNumber
}
$rows = [ordered]@{}
foreach ($n in $names) { $rows[$n] = Impl-Row $n }
if (@($rows.Values | Sort-Object -Unique).Count -ne $names.Count) {
  Write-Host "FATAL: anchors collapsed: $($rows.Values -join ',')" -ForegroundColor Red; exit 2
}
Write-Host ("  anchors: " + (($rows.Keys | ForEach-Object { "$_=$($rows[$_])" }) -join ' ')) -ForegroundColor DarkGray

# FlowChecks runs on the bare per-file path, so `lint <file>` is sufficient here.
# (Whole-index rules like doc-drift would need lint-all -- see
# INBOX-lint-single-file-silently-omits-lint-all-rules.md.)
$out  = & $Exe lint $file 2>&1 | Out-String
$hits = @([regex]::Matches($out, 'uDoubleFreeLoops\.pas:(\d+):\d+\s+\[\w+\]\s+double-free') |
          ForEach-Object { [int]$_.Groups[1].Value })
function Proc-Of([int]$Row) {
  $best = '(none)'
  foreach ($n in $rows.Keys) { if ($Row -ge $rows[$n]) { $best = $n } }
  $best
}
function Rows-In([string]$P) { ($hits | Where-Object { (Proc-Of $_) -eq $P }) -join ',' }
Write-Host ("  double-free at rows: " + (($hits -join ',') -replace '^$','(none)')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'Three objects the rule mistook for one' -ForegroundColor Cyan
Check 'MemberOfIterator: Pair.Value.Free is not a free of Pair' `
  ((Rows-In 'MemberOfIterator') -eq '') "rows=$(Rows-In 'MemberOfIterator')"
Check 'ElementOfArray: Items[I].Free is not a free of Items' `
  ((Rows-In 'ElementOfArray') -eq '') "rows=$(Rows-In 'ElementOfArray')"
Check 'ForInIterator: the for-in iterator is a new object each pass' `
  ((Rows-In 'ForInIterator') -eq '') "rows=$(Rows-In 'ForInIterator')"
Check 'InlineVarInLoop: an inline var re-creates the object each pass' `
  ((Rows-In 'InlineVarInLoop') -eq '') "rows=$(Rows-In 'InlineVarInLoop')"

Write-Host ''
Write-Host 'POSITIVE CONTROLS -- the rule must still work' -ForegroundColor Cyan
Check 'GenuineStraightLine: Free; Free; STILL fires' `
  ((Rows-In 'GenuineStraightLine') -ne '') "rows=$(Rows-In 'GenuineStraightLine')"
Check 'GenuineInLoop: one object freed inside a loop STILL fires' `
  ((Rows-In 'GenuineInLoop') -ne '') "rows=$(Rows-In 'GenuineInLoop')"
Check 'GenuineInlineDouble: an inline-declared var freed twice STILL fires' `
  ((Rows-In 'GenuineInlineDouble') -ne '') "rows=$(Rows-In 'GenuineInlineDouble')"

if ((Rows-In 'GenuineStraightLine') -eq '' -or (Rows-In 'GenuineInLoop') -eq '' -or
    (Rows-In 'GenuineInlineDouble') -eq '') {
  Write-Host '  !! A control failed. The four assertions above prove NOTHING -- they' -ForegroundColor Yellow
  Write-Host '  !! would pass with the rule switched off, which is precisely the' -ForegroundColor Yellow
  Write-Host '  !! cheap "stop reporting inside loops" fix this guard exists to reject.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
