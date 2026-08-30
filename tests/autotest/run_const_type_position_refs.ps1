<#
  run_const_type_position_refs.ps1 -- member B of the extractor batch
  (docs\PLAN-extractor-batch-2026-08-30.md sec 4.2 and sec 0-bis.4).

  ONE ROOT CAUSE, TWO MISSING REF KINDS
  --------------------------------------------------------------------------------
  Walk already emits a type_use for ANY typeref it reaches
  (DRagLint.Parser.Delphi13.pas:2227), and declField recurses into its children
  on purpose -- its own comment says "Walk children so the field's type is
  visited and emits a type_use ref". But the declType arm dispatches to TryWalk*
  handlers that each Exit, and the last of them, TryWalkOtherTypeDecl -- which
  claims "a subrange, an array type and a set type" -- exits WITHOUT recursing.
  declVar uses a non-recursive FindNamedChildOfType(VTypeField, 'typeref'), which
  sees declArray as the direct child and stops.

  So the type subtree under declType/declVar is never walked, and TWO different
  things go missing from it:

    B1  a const in a TYPE POSITION emits no 'read'
        -- array bounds, string[N], subrange bounds, expression bounds.
        Cost, measured once: Z14_MAXLotGroups was deleted from ORM3's Z19b5.pas
        on a clean refs pre-check and the build broke E2003 plus two cascades.
        An index answering "no rows" is not "no uses", and a DELETION gate is
        exactly where that difference bites.

    B2  an array's ELEMENT TYPE (and its INDEX type) emits no 'type_use'
        -- but the SAME array written as a record or class FIELD does emit it.

  MEASURED SHAPES (dumptree, session 51):
    array bound      (range (literalNumber) (identifier))
    expression bound (range (literalNumber) (exprBinary lhs: rhs:))
    string[N]        (declString (kString) (identifier))
    subrange         (subrangeType (identifier))
  `range` alone covers five positions, which is why the plan's re-scope kill
  condition was discharged in favour of the full scope.

  EVERY ASSERTED NAME APPEARS EXACTLY ONCE in the fixture outside its own
  declaration. That is deliberate: counting a name is not locating a site, and
  the sibling runner's first draft passed against the unfixed build precisely
  because a second, unrelated use satisfied the count.

  THE DOUBLE-EMIT GUARD MATTERS MOST HERE. Record/class fields already emit
  their element type_use today. If the recursion fix is applied too broadly --
  recursing after TryWalkClassOrRecord rather than only after
  TryWalkOtherTypeDecl -- those sites emit TWICE at an identical span, which is
  the register-E1 shape that once made every resolved call also look unverified.
  TElemField must stay EXACTLY 1.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-const-typepos"
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
unit constpos;

interface

const
  CBoundType       = 4;
  CBoundRecField   = 4;
  CBoundClassField = 4;
  CBoundVar        = 4;
  CStrLen          = 8;
  CSubHigh         = 9;
  CExprA           = 2;
  CExprB           = 3;
  CInitSrc         = 7;
  CPlainRead       = 1;
  CCaseLabel       = 2;

type
  TElemDeclType = record XA: Integer; end;
  TElemDeclVar  = record XB: Integer; end;
  TElemField    = record XC: Integer; end;
  TIndexEnum    = (ieAlpha, ieBeta);

  TArrInType  = array [0..CBoundType] of TElemDeclType;
  TSubRange   = 0..CSubHigh;
  TShortStr   = string [CStrLen];
  TExprBound  = array [1..CExprA * CExprB] of Integer;
  TIndexedArr = array [TIndexEnum] of Integer;

  TRecHost = record
    RF: array [0..CBoundRecField] of TElemField;
  end;

  TClsHost = class
    CF: array [0..CBoundClassField] of Integer;
  end;

const
  CDerived = CInitSrc + 1;

var
  GVarArr: array [0..CBoundVar] of TElemDeclVar;

procedure Drive(V: Integer);

implementation

procedure Drive(V: Integer);
var
  N: Integer;
begin
  N:= CPlainRead;
  case V of
    CCaseLabel: N:= 1;
  end;
  Writeln(N);
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path $WorkDir 'constpos.pas'), $src, [System.Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'constpos.sqlite'
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
for nm in ('CBoundType','CBoundRecField','CBoundClassField','CBoundVar','CStrLen',
           'CSubHigh','CExprA','CExprB','CInitSrc','CPlainRead','CCaseLabel',
           'TElemDeclType','TElemDeclVar','TElemField','TIndexEnum'):
    out[nm] = n(nm)
out['CBoundType_read']    = n('CBoundType', 'read')
out['CBoundType_call']    = n('CBoundType', 'call')
out['CStrLen_call']       = n('CStrLen', 'call')
out['TElemDeclType_tu']   = n('TElemDeclType', 'type_use')
out['TElemDeclType_call'] = n('TElemDeclType', 'call')
print(json.dumps(out))
c.close()
'@ | Set-Content $py -Encoding ascii
$r = (& python $py $db) -join "`n" | ConvertFrom-Json

Write-Host 'B1 -- a const in a TYPE POSITION emits a read' -ForegroundColor Cyan
Check 'HAZARD: array bound in a type decl'        ($r.CBoundType       -ge 1) "refs=$($r.CBoundType)"
Check 'HAZARD: array bound in a RECORD field'     ($r.CBoundRecField   -ge 1) "refs=$($r.CBoundRecField)"
Check 'HAZARD: array bound in a CLASS field'      ($r.CBoundClassField -ge 1) "refs=$($r.CBoundClassField)"
Check 'HAZARD: array bound in a typed var'        ($r.CBoundVar        -ge 1) "refs=$($r.CBoundVar)"
Check 'HAZARD: string [N] length'                 ($r.CStrLen          -ge 1) "refs=$($r.CStrLen)"
Check 'HAZARD: subrange bound'                    ($r.CSubHigh         -ge 1) "refs=$($r.CSubHigh)"
Check 'HAZARD: expression bound, lhs'             ($r.CExprA           -ge 1) "refs=$($r.CExprA)"
Check 'HAZARD: expression bound, rhs'             ($r.CExprB           -ge 1) "refs=$($r.CExprB)"

Write-Host ''
Write-Host 'B1 controls -- these are GREEN today and must stay green' -ForegroundColor Cyan
Check 'CONTROL: const in another const initialiser' ($r.CInitSrc   -eq 1) "refs=$($r.CInitSrc)"
Check 'CONTROL: ordinary expression read'           ($r.CPlainRead -eq 1) "refs=$($r.CPlainRead)"
Check 'CONTROL: case label'                         ($r.CCaseLabel -eq 1) "refs=$($r.CCaseLabel)"

Write-Host ''
Write-Host 'B2 -- an array element/index TYPE emits a type_use' -ForegroundColor Cyan
Check 'HAZARD: element type under declType'  ($r.TElemDeclType -ge 1) "refs=$($r.TElemDeclType)"
Check 'HAZARD: element type under declVar'   ($r.TElemDeclVar  -ge 1) "refs=$($r.TElemDeclVar)"
Check 'HAZARD: array INDEX type name'        ($r.TIndexEnum    -ge 1) "refs=$($r.TIndexEnum)"
Check 'the new element-type ref is a type_use' ($r.TElemDeclType_tu -ge 1) "type_use refs=$($r.TElemDeclType_tu)"

Write-Host ''
Write-Host 'B2 DOUBLE-EMIT guard -- fields already emit; they must not emit twice' -ForegroundColor Cyan
Check 'CONTROL: element type under a record FIELD is emitted' ($r.TElemField -ge 1) "refs=$($r.TElemField)"
Check 'and is emitted EXACTLY ONCE'                           ($r.TElemField -eq 1) "refs=$($r.TElemField), a 2 here is the register-E1 duplicate-span shape"

Write-Host ''
Write-Host 'The call universe was not widened (T3i)' -ForegroundColor Cyan
Check 'a type-position const read is kind=read'   ($r.CBoundType_call -eq 0) "call refs=$($r.CBoundType_call)"
Check 'a string [N] length is not a call site'    ($r.CStrLen_call    -eq 0) "call refs=$($r.CStrLen_call)"
Check 'an element type is not a call site'        ($r.TElemDeclType_call -eq 0) "call refs=$($r.TElemDeclType_call)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
