<#
  run_convert_apply_multidb.ps1 -- reproduces + guards against TWO root-caused
  convert-apply bugs that only surface when a component's From type, To type,
  and the form's own instances are indexed under THREE SEPARATE --db files
  (the real-world case: a library's source type lives in one index, a
  DevExpress-style target type in another, and the application's own forms in
  a third).

  BUG 2 (primary): DoConvertApply (src/cli/DRagLint.CLI.pas) opens the Store
  from only the FIRST readable --db (Break after the first hit) and hands that
  SAME single store to both CheckFreshness (the freshness guard) and
  BuildApplyPlan. When the From/To types are NOT in that first db, the guard's
  CheckTypeFreshness reports "not indexed (no skClass symbol found)" and
  BuildApplyPlan's TFindUnitRefactoring.Build can't resolve a unit for the To
  type ("could not resolve a unit declaring ..."), even though every db passed
  on the command line together DOES cover everything needed. DoConvertApply's
  OWN rule-validation TreeFor (used earlier in the same function, for
  ValidateConversionRules) already resolves types across ALL passed --db,
  first-db-that-resolves-wins -- this test proves the freshness guard and
  BuildApplyPlan must get the SAME cross-db treatment.

  BUG 1 (secondary): FindConvertRuleFor (src/report/DRagLint.Convert.Apply.pas)
  matches a #convert rule's FromType against the .dfm's bare 'object Name:
  Class' header via an exact SameText. convert-scaffold/the editor may emit a
  QUALIFIED header ('#convert LibA.TSrcBtn -> LibB.TDstBtn, LibB') -- but a
  .dfm object header is ALWAYS bare ('object btn1: TSrcBtn'), so a qualified
  FromType matches ZERO .dfm instances ("no convertible instances found").

  FIXTURE (self-contained, built fresh under $WorkDir so this test never
  depends on any real machine index):
    libA\LibA.pas   -- unit LibA; declares the SOURCE class TSrcBtn (published
                       Caption: string; Down: Boolean).
    libB\LibB.pas   -- unit LibB; declares the TARGET class TDstBtn (published
                       Caption: string; Down: Boolean) -- same shape, so a
                       plain identity #link Caption <- Caption / Down <- Down
                       is a valid, resolvable rule pair.
    app\MyForm.pas  -- unit MyForm; 'uses Classes, LibA;', TMyForm = class
                       (TForm) with a published field 'btn1: TSrcBtn;'.
    app\MyForm.dfm  -- 'object MyForm: TMyForm' containing a nested 'object
                       btn1: TSrcBtn' with Caption = 'Hi' and Down = True.

  Each fixture folder is indexed into its OWN db -- libA\ -> dbA.sqlite, libB\
  -> dbB.sqlite, app\ -> dbApp.sqlite -- so TSrcBtn, TDstBtn, and the btn1
  instance are each ONLY resolvable in a different db than the other two; a
  single-db Store can never see all three, reproducing Bug 2 exactly.

  Two rules files exercise Bug 1's bare vs. qualified #convert header:
    rules-bare.txt       -- '#convert TSrcBtn -> TDstBtn, LibB'
    rules-qualified.txt  -- '#convert LibA.TSrcBtn -> LibB.TDstBtn, LibB'
  both carry the same '#link Caption <- Caption' / '#link Down <- Down'.

  ASSERTIONS (dry-run only, NO --apply -- this test only needs to prove
  resolution/location succeed, not exercise the 5 rewrite surfaces, which are
  already covered by run_convert_apply.ps1): for EACH rules file, running
  'convert-apply --unit app\MyForm.pas --rules <rules> --db dbApp --db dbA
  --db dbB' (dbApp FIRST, matching the historical single-db bug: dbApp alone
  has neither TSrcBtn nor TDstBtn) must:
    - exit 0.
    - print "1 instance(s) converted" (instance LOCATED -- Bug 1 fixed).
    - NOT print "not indexed (no skClass symbol found)" (freshness guard
      resolves cross-db -- Bug 2 fixed, guard half).
    - NOT print "could not resolve a unit declaring" (uses-add resolves the To
      type's unit cross-db -- Bug 2 fixed, plan half).
  The qualified-header run additionally proves the qualified '#convert LibA.
  TSrcBtn -> LibB.TDstBtn, LibB' header ALSO locates the .dfm instance (bare-
  tail match), not just the bare-header run.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-convert-apply-multidb by
  default); Push-Location into app\ only for the actual convert-apply
  invocation (mirrors run_convert_apply.ps1's convention).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-apply-multidb"
)
$ErrorActionPreference = 'Continue'
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# ---------------------------------------------------------------------------
# Fixture: three folders, each destined for its OWN db (libA/libB/app), so
# the source type, target type, and the form's own instance are each
# resolvable in only ONE of the three dbs -- the real-world split this bug
# only reproduces when the From/To/instance dbs are all different.
# ---------------------------------------------------------------------------
$libADir = Join-Path $WorkDir 'libA'
$libBDir = Join-Path $WorkDir 'libB'
$appDir  = Join-Path $WorkDir 'app'
New-Item -ItemType Directory $libADir -Force | Out-Null
New-Item -ItemType Directory $libBDir -Force | Out-Null
New-Item -ItemType Directory $appDir  -Force | Out-Null

$LibABody = @'
unit LibA;

interface

uses
  Classes;

type
  TSrcBtn = class(TPersistent)
  private
    FCaption: string;
    FDown: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Down: Boolean read FDown write FDown;
  end;

implementation

end.
'@

$LibBBody = @'
unit LibB;

interface

uses
  Classes;

type
  TDstBtn = class(TPersistent)
  private
    FCaption: string;
    FDown: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Down: Boolean read FDown write FDown;
  end;

implementation

end.
'@

$MyFormBody = @'
unit MyForm;

interface

uses
  Classes, LibA;

type
  TMyForm = class(TForm)
    btn1: TSrcBtn;
  end;

implementation

{$R *.dfm}

end.
'@

$MyFormDfm = @'
object MyForm: TMyForm
  object btn1: TSrcBtn
    Caption = 'Hi'
    Down = True
  end
end
'@

$RulesBareBody = @'
#convert TSrcBtn -> TDstBtn, LibB
#link Caption <- Caption
#link Down <- Down
'@

$RulesQualifiedBody = @'
#convert LibA.TSrcBtn -> LibB.TDstBtn, LibB
#link Caption <- Caption
#link Down <- Down
'@

Write-Ascii (Join-Path $libADir 'LibA.pas') $LibABody
Write-Ascii (Join-Path $libBDir 'LibB.pas') $LibBBody
Write-Ascii (Join-Path $appDir  'MyForm.pas') $MyFormBody
Write-Ascii (Join-Path $appDir  'MyForm.dfm') $MyFormDfm

$rulesBarePath      = Join-Path $WorkDir 'rules-bare.txt'
$rulesQualifiedPath = Join-Path $WorkDir 'rules-qualified.txt'
Write-Ascii $rulesBarePath $RulesBareBody
Write-Ascii $rulesQualifiedPath $RulesQualifiedBody

# ---------------------------------------------------------------------------
# Index EACH folder into its OWN db -- TSrcBtn only in dbA, TDstBtn only in
# dbB, the btn1 instance only in dbApp.
# ---------------------------------------------------------------------------
$dbA   = Join-Path $WorkDir 'dbA.sqlite'
$dbB   = Join-Path $WorkDir 'dbB.sqlite'
$dbApp = Join-Path $WorkDir 'dbApp.sqlite'

Write-Host 'Indexing libA -> dbA' -ForegroundColor Cyan
$idxAOut = & $Exe index $libADir --db $dbA 2>&1
Check 'index libA exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($idxAOut -join ' | ')"

Write-Host 'Indexing libB -> dbB' -ForegroundColor Cyan
$idxBOut = & $Exe index $libBDir --db $dbB 2>&1
Check 'index libB exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($idxBOut -join ' | ')"

Write-Host 'Indexing app -> dbApp' -ForegroundColor Cyan
$idxAppOut = & $Exe index $appDir --db $dbApp 2>&1
Check 'index app exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($idxAppOut -join ' | ')"

# ---------------------------------------------------------------------------
# Runs convert-apply (dry-run) for one rules file, --db dbApp FIRST (matching
# the historical bug: the first-opened db alone resolves neither type), and
# checks the 4 assertions from the task brief.
# ---------------------------------------------------------------------------
function Run-ConvertApplyCheck([string]$Label, [string]$RulesPath) {
  Push-Location $appDir
  try {
    $raw = (& $Exe convert-apply --unit 'MyForm.pas' --rules $RulesPath --db $dbApp --db $dbA --db $dbB 2>&1) -join "`n"
    $exit = $LASTEXITCODE
  } finally { Pop-Location }
  Write-Host "--- $Label output ---" -ForegroundColor DarkGray
  Write-Host $raw -ForegroundColor DarkGray

  Check "$Label`: exits 0" ($exit -eq 0) "exit=$exit"
  Check "$Label`: prints 1 instance(s) converted (instance located -- Bug 1)" `
    ($raw -match [regex]::Escape('1 instance(s) converted')) "raw=$raw"
  Check "$Label`: does NOT report freshness 'not indexed' (Bug 2, guard)" `
    (-not ($raw -match 'not indexed \(no skClass symbol found\)')) "raw=$raw"
  Check "$Label`: does NOT report 'could not resolve a unit declaring' (Bug 2, uses-add)" `
    (-not ($raw -match 'could not resolve a unit declaring')) "raw=$raw"
  Check "$Label`: no hard ERROR line" `
    (-not ($raw -match '(?m)^ERROR:')) "raw=$raw"
}

Write-Host ''
Write-Host '=== Bare #convert header (TSrcBtn -> TDstBtn) ===' -ForegroundColor Cyan
Run-ConvertApplyCheck 'bare' $rulesBarePath

Write-Host ''
Write-Host '=== Qualified #convert header (LibA.TSrcBtn -> LibB.TDstBtn) ===' -ForegroundColor Cyan
Run-ConvertApplyCheck 'qualified' $rulesQualifiedPath

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
