<#
  run_with_and_external_refs.ps1 -- member A of the extractor batch
  (docs\PLAN-extractor-batch-2026-08-30.md sec 4.1).

  TWO GAPS, ONE RUNNER
  --------------------------------------------------------------------------------
  A1. `with A, B do` is ONE `with` node carrying REPEATED `entity:` fields:

        (with (kWith) entity: (identifier) entity: (identifier) (kDo) body: ...)

      EmitExpressionIdentReads asks ANode.ChildByField('entity')
      (DRagLint.Parser.Delphi13.pas:428), and ChildByField returns the FIRST
      field only. Entity 2..n is dropped.

      MEASURED, and it NARROWS the fix (session 51, engine extractor 1.8.0-alpha):
      only a BARE IDENTIFIER in slot 2..n is lost. `with A, TFoo(FList[0]) do`
      already emits A, TFoo and FList, because a non-identifier entity is its own
      node and ordinary Walk recursion reaches it. The note's claim that this was
      so had never been probed; it is probed here, as a GREEN control, so that a
      fix which "helpfully" widens the recursion and double-emits gets caught.

  A2. The `external` directive's library expression is walked by nothing.
      Shape (dumptree): (procExternal (kExternal) (identifier) (kName) (identifier))
      -- the libexpr AND the `name` expression are UNNAMED POSITIONAL children,
      so there is no field to ask for and the existing ReadAllDirectIdents helper
      is the right tool. Live case: CLIENT\BASICSF.pas:65 `external user32`.

  WHY 'read' AND NOT 'call'. Same reasoning as run_expr_bare_call_refs.ps1: a
  const in a library expression is a value read. Emitting REF_KIND_CALL would
  widen the call universe that ResolveCallTargets resolves against -- the defect
  T3i closed. Asserted directly below.

  EVERY HAZARD IS PAIRED WITH A CONTROL THAT IS GREEN TODAY, because an assertion
  that only says "the bad thing is gone" also passes with the feature switched
  off.

  WHY SlotTwoOnly EXISTS. The first draft of this runner asserted on EntityTwo,
  which is ALSO read by `result:= EntityTwo` inside MakeBox -- so the hazard
  assertion counted 1 and PASSED against the unfixed build. Counting a name is
  not locating a site. SlotTwoOnly appears exactly once in the whole fixture, in
  the entity-2 slot, so its count cannot be satisfied from anywhere else.

  NOTE for a future reader: HolderArr is an array in a var block, which member B2
  of the same batch also touches (it will start emitting a type_use for the
  element type there). No assertion in THIS runner counts that type, so the two
  members stay independent.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-with-external"
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
unit withext;

interface

const
  ExtLibName  = 'user32.dll';
  ExtProcName = 'MessageBoxA';

type
  TBoxA = class
    AlphaA: Integer;
  end;

  TBoxB = class
    BetaB: Integer;
  end;

function ExternallyBound(H: Integer): Integer; stdcall; external ExtLibName name ExtProcName;

procedure Drive;

implementation

var
  EntityOne       : TBoxA;
  EntityTwo       : TBoxB;
  HolderArr       : array [0..3] of Integer;
  PlainGlobal     : Integer;
  DeadBranchGlobal: Integer;
  LiveBranchGlobal: Integer;

function MakeBox: TBoxB;
begin
  result:= EntityTwo;
end;

procedure Drive;
var
  L: Integer;
begin
  with EntityOne, EntityTwo do
    L:= AlphaA + BetaB;
  with EntityOne do
    L:= AlphaA;
  with EntityOne, TBoxB(HolderArr[0]) do
    L:= BetaB;
  with MakeBox do
    L:= BetaB;
  L:= PlainGlobal;
  L:= Length(ExtLibName);
{$IFDEF NEVER_DEFINED_IN_THIS_FIXTURE}
  L:= DeadBranchGlobal;
{$ELSE}
  L:= LiveBranchGlobal;
{$ENDIF}
  Writeln(L);
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path $WorkDir 'withext.pas'), $src, [System.Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'withext.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null

$py = Join-Path $WorkDir 'refs.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
out = {}
def n(name, kind=None):
    q = "SELECT COUNT(*) FROM refs WHERE name_text LIKE ? COLLATE NOCASE"
    a = [name]
    if kind:
        q += " AND kind = ?"
        a.append(kind)
    return c.execute(q, a).fetchone()[0]
for nm in ('EntityOne','EntityTwo','SlotTwoOnly','HolderArr','MakeBox','PlainGlobal',
           'ExtLibName','ExtProcName','DeadBranchGlobal','LiveBranchGlobal'):
    out[nm] = n(nm)
out['ExtLibName_call']  = n('ExtLibName', 'call')
out['ExtProcName_call'] = n('ExtProcName', 'call')
out['SlotTwoOnly_call'] = n('SlotTwoOnly', 'call')
print(json.dumps(out))
c.close()
'@ | Set-Content $py -Encoding ascii
$r = (& python $py $db) -join "`n" | ConvertFrom-Json

Write-Host 'A1 -- with entity slots' -ForegroundColor Cyan
Check 'HAZARD: bare identifier in entity slot 2 is recorded' ($r.SlotTwoOnly -ge 1) "refs=$($r.SlotTwoOnly)  -- SlotTwoOnly appears ONLY in the entity-2 slot"
Check 'CONTROL: that name IS otherwise reachable (EntityTwo, read in MakeBox)' ($r.EntityTwo -ge 1) "refs=$($r.EntityTwo)"
Check 'CONTROL: entity slot 1 is recorded'                   ($r.EntityOne -ge 1) "refs=$($r.EntityOne)"
Check 'CONTROL: entity slot 1 is not DOUBLE-emitted'         ($r.EntityOne -eq 3) "refs=$($r.EntityOne), expected exactly 3 (three with-statements name it)"
Check 'CONTROL: subscript entity in slot 2 already recurses' ($r.HolderArr -ge 1) "refs=$($r.HolderArr)  -- green TODAY; pins the measured recursion claim"
Check 'CONTROL: call entity in slot 1 already recurses'      ($r.MakeBox   -ge 1) "refs=$($r.MakeBox)"
Check 'CONTROL: a global read outside any with is recorded'  ($r.PlainGlobal -ge 1) "refs=$($r.PlainGlobal)"

Write-Host ''
Write-Host 'A2 -- the external directive' -ForegroundColor Cyan
Check 'HAZARD: the name-expression const is recorded'  ($r.ExtProcName -ge 1) "refs=$($r.ExtProcName)  -- ExtProcName appears NOWHERE else, so 0 means unwalked"
Check 'HAZARD: the library-expression const is recorded' ($r.ExtLibName -ge 2) "refs=$($r.ExtLibName)  -- 1 is the ordinary Length() read alone; the external site is the 2nd"
Check 'CONTROL: the same const read normally IS recorded' ($r.ExtLibName -ge 1) "refs=$($r.ExtLibName)"

Write-Host ''
Write-Host 'The call universe was not widened (T3i)' -ForegroundColor Cyan
Check 'external libexpr const is not a call site' ($r.ExtLibName_call  -eq 0) "call refs=$($r.ExtLibName_call)"
Check 'external name const is not a call site'    ($r.ExtProcName_call -eq 0) "call refs=$($r.ExtProcName_call)"
Check 'a with-entity is not a call site'          ($r.SlotTwoOnly_call -eq 0) "call refs=$($r.SlotTwoOnly_call)"

Write-Host ''
Write-Host 'Dead-IFDEF pin (this batch must not "fix" blanked branches)' -ForegroundColor Cyan
Check 'an identifier in a never-taken branch yields NO ref' ($r.DeadBranchGlobal -eq 0) "refs=$($r.DeadBranchGlobal)"
Check 'CONTROL: the same shape in the TAKEN branch fires'   ($r.LiveBranchGlobal -ge 1) "refs=$($r.LiveBranchGlobal)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
