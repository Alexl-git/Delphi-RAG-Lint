<#
  run_convert_apply_index_precondition.ps1 --
  convert-apply's skip message must name the INDEX precondition, not make a
  false claim about the .dfm's contents.

  THE DEFECT (converter team, 2026-09-16, with a 261-byte reproduction).
  Running convert-apply on a unit covered by NO supplied --db printed, once per
  instance:

    btnTop: could not locate .dfm object block for "btnTop: TabcToggleBtn"
            in ...\VARINSP.dfm -- instance skipped     ... x20

  That sentence is FALSE ON ITS FACE. They verified before concluding anything:
  the .dfm is TEXT (not binary), and all twenty `: TabcToggleBtn` blocks are
  present at lines 4880, 14705, 17564, ... The message asserts something about
  the FILE when the real condition is that the UNIT IS NOT IN ANY SUPPLIED
  INDEX -- convert-apply resolves .dfm blocks through the index
  (Convert.Apply.pas:1647-1650, DfmStore.FindSymbolsByFile). Index the unit and
  the identical command converts all twenty.

  WHY IT COST A DAY, which is the reason this is worth a guard rather than a
  one-line edit: every reading the message INVITES is plausible and wrong. They
  tested and disproved three -- binary .dfm, nesting depth, and a qualified vs
  bare #convert type -- before finding the real one. A message that is merely
  unhelpful costs a minute; one that is confidently wrong costs a day.

  WHAT IS NOT CHANGING. Requiring an index is reasonable and may be
  load-bearing; the converter team explicitly did not ask for a behaviour
  change, and this guard does not encode one. Instance COUNTS and the
  skip/convert accounting are unchanged -- only the sentence differs.

  WHY INSTANCES STILL EXIST WITH NO INDEX (the fact that makes this fixture
  work): FindConvertInstances reads the .dfm TEXT (Convert.Apply.pas:1621), so
  an unindexed unit still yields N instances, each of which then fails the index
  lookup. If instances had come from the index there would have been no
  warnings at all, and no defect to report.

  THE THIRD ASSERTION IS THE ONE THAT MATTERS MOST. A reword that simply
  replaced one sentence with the other would trade a false claim for a false
  claim and make the REAL not-in-the-dfm case undiagnosable. T3 pins that: a
  unit that IS indexed, whose .dfm has an object the index does not know, must
  still get the ORIGINAL "could not locate" message.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_precondition"
)
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$libA = Join-Path $WorkDir 'libA'; $libB = Join-Path $WorkDir 'libB'; $app = Join-Path $WorkDir 'app'
foreach ($d in @($libA,$libB,$app)) { New-Item -ItemType Directory $d -Force | Out-Null }

Write-Ascii (Join-Path $libA 'LibA.pas') @'
unit LibA;

interface

uses
  Classes;

type
  TSrcBtn = class(TPersistent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $libB 'LibB.pas') @'
unit LibB;

interface

uses
  Classes;

type
  TDstBtn = class(TPersistent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $app 'MyForm.pas') @'
unit MyForm;

interface

uses
  Classes, LibA;

type
  TMyForm = class(TForm)
    btnTop: TSrcBtn;
    btnDeep: TSrcBtn;
  end;

implementation

{$R *.dfm}

end.
'@

# btnTop at depth 1 and btnDeep at depth 2 -- the converter team's own repro
# shape. Depth was one of the three hypotheses they disproved, so keeping both
# means a future depth regression cannot hide behind this guard.
Write-Ascii (Join-Path $app 'MyForm.dfm') @'
object MyForm: TMyForm
  object btnTop: TSrcBtn
    Caption = 'Top'
  end
  object pnlOuter: TPanel
    object btnDeep: TSrcBtn
      Caption = 'Deep'
    end
  end
end
'@

$rules = Join-Path $WorkDir 'rules.txt'
Write-Ascii $rules @'
#convert TSrcBtn -> TDstBtn, LibB
#link Caption <- Caption
'@

$dbA   = Join-Path $WorkDir 'dbA.sqlite'
$dbB   = Join-Path $WorkDir 'dbB.sqlite'
$dbApp = Join-Path $WorkDir 'dbApp.sqlite'
& $Exe index $libA --db $dbA   2>&1 | Out-Null
& $Exe index $libB --db $dbB   2>&1 | Out-Null
& $Exe index $app  --db $dbApp 2>&1 | Out-Null
Check 'V the three fixture indexes were built' `
      ((Test-Path $dbA) -and (Test-Path $dbB) -and (Test-Path $dbApp))

function Apply([string[]]$Dbs) {
  Push-Location $app
  try { return ((& $Exe convert-apply --unit 'MyForm.pas' --rules $rules @Dbs 2>&1) -join "`n") }
  finally { Pop-Location }
}

$OLD_MSG = 'could not locate .dfm object block'

# ---- R1: the defect -- the unit is in NO supplied index --------------------
$r1 = Apply @('--db', $dbA, '--db', $dbB)

Check 'T1 an UNINDEXED unit does not claim the .dfm block is missing' `
      (-not ($r1 -match [regex]::Escape($OLD_MSG))) `
      "still asserts something false about the .dfm:`n$r1"

Check 'T2 the message names the INDEX precondition instead' `
      ($r1 -match '(?i)not covered by any supplied --db|resolves \.dfm blocks through the index') `
      "the reader is given no route to the real cause:`n$r1"

# ---- R2: POSITIVE CONTROL -- with the covering db it converts --------------
# Without this, T1/T2 pass against a build where convert-apply always reports
# the precondition and never converts anything.
$r2 = Apply @('--db', $dbApp, '--db', $dbA, '--db', $dbB)

Check 'P1 POSITIVE CONTROL the covering --db converts both instances' `
      ($r2 -match '2 instance\(s\) converted') `
      "the fixture does not convert even when indexed, so T1/T2 prove nothing:`n$r2"

Check 'P2 POSITIVE CONTROL a successful run emits NEITHER message' `
      ((-not ($r2 -match [regex]::Escape($OLD_MSG))) -and `
       (-not ($r2 -match '(?i)not covered by any supplied --db'))) `
      "a clean run is emitting a skip message:`n$r2"

# ---- R3: DISCRIMINATION CONTROL -------------------------------------------
# The unit IS indexed; the .dfm on disk has since gained an object the index
# does not know. That is the GENUINE not-located case, and it must keep the
# original message -- otherwise the reword has merely swapped one false
# sentence for another.
#
# The .dfm is REWRITTEN WHOLE, not string-patched. The first draft of this
# fixture used
#     $dfmText.Replace("end`r`n", "<block>end`r`n", 1)
# intending "replace the first occurrence". .NET's String.Replace has NO
# count overload -- the `1` bound to StringComparison.CurrentCultureIgnoreCase,
# so it inserted btnGhost at EVERY `end` line. The guard still went green,
# because T3 needs only one genuinely-unknown object, and the mis-built fixture
# happened to supply several. A control that passes for a reason other than the
# one it states is not a control.
$dfmPath = Join-Path $app 'MyForm.dfm'
Write-Ascii $dfmPath @'
object MyForm: TMyForm
  object btnTop: TSrcBtn
    Caption = 'Top'
  end
  object pnlOuter: TPanel
    object btnDeep: TSrcBtn
      Caption = 'Deep'
    end
  end
  object btnGhost: TSrcBtn
    Caption = 'Ghost'
  end
end
'@
$r3 = Apply @('--db', $dbApp, '--db', $dbA, '--db', $dbB)

# Exactly ONE instance is unknown to the index, so exactly one skip is expected
# and the other two must still convert. Asserting the COUNT is what stops this
# control from passing on a fixture that accidentally broke everything.
Check 'T3pre the R3 fixture leaves exactly one unknown object, not a broken .dfm' `
      (($r3 -match '2 instance\(s\) converted') -and `
       (([regex]::Matches($r3, [regex]::Escape($OLD_MSG))).Count -eq 1)) `
      "expected 2 converted + exactly 1 not-located skip:`n$r3"

Check 'T3 DISCRIMINATION an INDEXED unit whose .dfm object is unknown keeps the original message' `
      ($r3 -match [regex]::Escape($OLD_MSG)) `
      "the genuine not-located case has become undiagnosable -- every skip now blames the index:`n$r3"

Check 'T3b DISCRIMINATION that case does NOT blame the index precondition' `
      (-not ($r3 -match '(?i)not covered by any supplied --db')) `
      "an indexed unit is being reported as unindexed:`n$r3"

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
