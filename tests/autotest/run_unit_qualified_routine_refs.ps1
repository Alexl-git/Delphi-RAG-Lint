<#
run_unit_qualified_routine_refs.ps1 -- ref-gap G2.

THE DEFECT. A UNIT-QUALIFIED reference to a routine -- `Alpha.Beta.Tools.Proc`
-- was not recorded in `refs` AT ALL. Ref-gap G in
`src\parser\DRagLint.Parser.Delphi13.pas` emits a `member-access` for the rhs of
a dotted access only when the lhs is a PLAIN IDENTIFIER, and its own comment
argued the deeper levels were covered "via the recursion below". They were not:
the recursion emits a ref for each level's OWN rhs, so `A.B.C.Proc` yielded
`read A` and `member-access B` and lost `C` and `Proc` entirely.

WHY IT MATTERED MORE THAN IT LOOKED. `find-callers` UNDER-REPORTS on that
shape, and an under-report is worse than an error: a zero reads as "nothing
calls this", which is exactly the answer the index exists to be trusted for.
`unused-public-symbol` then fires on live code -- the finding most likely to get
working code deleted.

MEASURED, on the plugin index, before the fix -- two assignments on adjacent
lines of `DragLint.Plugin.Editor.pas`:
    GAfterSaveFanOutHook:= NotifyFanOutSave;                    -> 1 caller
    AddWrappedItem(..., DragLint.Plugin.FanOut.InvokeCompileDependents);  -> 0
Same routine kind, same file, same run. The only difference is the qualifier.

'member-access', NOT a call kind, and case 4 pins it. `FindCallersByName` --
behind `find-callers` and, via `IsReferenced`, behind `unused-public-symbol` --
is KIND-BLIND, so member-access fixes both consumers. Emitting a `call` would
widen the resolver's universe of call edges for a construct that is frequently
not a call at all, which is the defect T3i closed.

RED/GREEN IS BY ENGINE, NOTHING ELSE. Point -Exe at a pre-fix build and cases
1-3 fail while 4-6 pass; point it at a fixed build and all six pass. Same
runner, same fixture, same fixture hash.

Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){
  Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''}))
  if(-not $ok){ $script:fail = $true }
}

$work = Join-Path $env:TEMP ("dl-uqref-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
function W([string]$p,[string[]]$l){ [IO.File]::WriteAllText($p, (($l -join "`r`n")+"`r`n"), [Text.Encoding]::ASCII) }

# A DOTTED unit name is the whole point -- a single-segment unit would make
# `Tools.Passed` a two-segment access, which ref-gap G already handled.
W (Join-Path $work 'Alpha.Beta.Tools.pas') @(
  'unit Alpha.Beta.Tools;','','interface','',
  'type','  TIntFunc = function: Integer;','',
  'function Hooked: Integer;',
  'function Passed: Integer;',
  'function Valued: Integer;',
  'function NeverUsed: Integer;','',
  'implementation','',
  'function Hooked: Integer;','begin','  Result:= 1;','end;','',
  'function Passed: Integer;','begin','  Result:= 2;','end;','',
  'function Valued: Integer;','begin','  Result:= 3;','end;','',
  'function NeverUsed: Integer;','begin','  Result:= 4;','end;','',
  'end.')

# Three EXPRESSION positions, which is where the gap lived: assignment rhs,
# call argument, and an operand. Statement-position `A.B.Proc;` already worked
# through the statement branch, so it is not what this pins.
W (Join-Path $work 'uConsumer.pas') @(
  'unit uConsumer;','','interface','','uses','  Alpha.Beta.Tools;','',
  'procedure Drive;','',
  'implementation','',
  'var','  GHook: TIntFunc;','',
  'procedure Register(AFn: TIntFunc);','begin','end;','',
  'procedure Drive;','var','  N: Integer;','begin',
  '  GHook:= Alpha.Beta.Tools.Hooked;',
  '  Register(Alpha.Beta.Tools.Passed);',
  '  N:= Alpha.Beta.Tools.Valued * 2;',
  '  if N > 0 then Exit;',
  'end;','',
  'end.')

$db = Join-Path $work 'fx.sqlite'
& $Exe index $work --db $db --rebuild *> $null
Check 'fixture indexed' (Test-Path $db) $db

$py = Join-Path $work 'q.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
out = {}
for nm in ('Hooked','Passed','Valued','NeverUsed'):
    out[nm] = c.execute(
        "SELECT COUNT(*) FROM refs WHERE name_text LIKE ? COLLATE NOCASE", (nm,)).fetchone()[0]
    out[nm + '_call'] = c.execute(
        "SELECT COUNT(*) FROM refs WHERE name_text LIKE ? COLLATE NOCASE AND kind = 'call'",
        (nm,)).fetchone()[0]
c.close()
print(json.dumps(out))
'@ | Set-Content $py -Encoding ascii
$refs = (& python $py $db 2>$null | Out-String | ConvertFrom-Json)

# 1-3 -- THE FIX. Each is a different expression position.
Check '1 an assignment rhs records a ref (GHook := Alpha.Beta.Tools.Hooked)' `
      ($refs.Hooked -ge 1) "refs=$($refs.Hooked)"
Check '2 a call ARGUMENT records a ref (Register(Alpha.Beta.Tools.Passed))' `
      ($refs.Passed -ge 1) "refs=$($refs.Passed)"
Check '3 an OPERAND records a ref (N := Alpha.Beta.Tools.Valued * 2)' `
      ($refs.Valued -ge 1) "refs=$($refs.Valued)"

# 4 -- THE KIND. member-access is enough for both consumers; a call ref would
# widen the resolver's call universe for something that is often not a call.
Check '4 and the ref is NOT recorded as a call' `
      (($refs.Hooked_call -eq 0) -and ($refs.Passed_call -eq 0) -and ($refs.Valued_call -eq 0)) `
      "call-kind refs: $($refs.Hooked_call)/$($refs.Passed_call)/$($refs.Valued_call)"

# 5 -- NEGATIVE CONTROL. Without it, cases 1-3 are equally satisfied by a change
# that emits a ref for every identifier it walks past.
Check '5 NEGATIVE CONTROL: a routine nobody references stays at zero refs' `
      ($refs.NeverUsed -eq 0) `
      "NeverUsed has $($refs.NeverUsed) ref(s) -- the fix is emitting refs indiscriminately"

# 6 -- the consumer that actually bit us. find-callers must SEE all three.
$seen = 0
foreach ($nm in 'Hooked','Passed','Valued') {
  $fc = (& $Exe query find-callers --name $nm --db $db 2>$null | Out-String)
  if ($fc -match 'uconsumer\.pas') { $seen++ }
}
Check '6 find-callers resolves all three qualified call sites' ($seen -eq 3) `
      "$seen of 3 -- an under-reporting find-callers is worse than an erroring one"

Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
if($fail){ Write-Host 'UNIT-QUALIFIED REF GUARD: FAIL' -ForegroundColor Red; exit 1 }
else     { Write-Host 'UNIT-QUALIFIED REF GUARD: PASS' -ForegroundColor Green; exit 0 }
