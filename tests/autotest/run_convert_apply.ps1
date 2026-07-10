<#
  run_convert_apply.ps1 -- convert-apply verb headless test (Track 3, sub-
  project B, Task 2). DRY-RUN ONLY: this task implements instance location
  (FindConvertInstances) + surface #1 (.pas declaration retype) + surface #2
  (.pas uses-add), wired into the CLI as `convert-apply --unit F.pas --rules R
  --db D [--only ...]`. There is NO --apply path yet (Task 4); this script
  only exercises the dry-run preview and asserts NOTHING is written to disk.

  FIXTURE:
    OldEditUnit.pas  -- declares TOldEdit (published Caption: string), the F
                         (from) type being converted away from.
    NewEditUnit.pas  -- declares TNewEdit (published Text: string), the T
                         (to) type being converted to. Both units are indexed
                         so BuildPropTree / find-unit / the field-decl scan
                         can all resolve real symbols (per the brief: "must
                         be defined in indexable fixture units").
    MyForm.pas       -- a tiny form unit with one published field
                         'Edit1: TOldEdit' and a bare 'uses Classes,
                         OldEditUnit;' (no NewEditUnit yet -- surface #2 must
                         add it).
    MyForm.dfm       -- one component instance 'object Edit1: TOldEdit'
                         nested under 'object MyForm: TMyForm'.
    rules.txt        -- '#convert TOldEdit -> TNewEdit, NewEditUnit' +
                         '#link Text <- Caption'.

  ASSERTIONS (dry-run, NO --apply):
    - exits 0.
    - dry-run output shows the declaration retype: 'Edit1: TOldEdit' becoming
      'Edit1: TNewEdit' (rendered as a tekReplaceInLine preview line).
    - dry-run output shows a uses-add mentioning NewEditUnit (surface #2 via
      TFindUnitRefactoring.Build).
    - MyForm.pas is BYTE-UNCHANGED on disk after the dry-run (no write --
      this task's verb only prints TTextEditApplier.RenderDryRun).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-convert-apply by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-apply"
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

$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# ---------------------------------------------------------------------------
# Fixture units
# ---------------------------------------------------------------------------
$OldEditBody = @'
unit OldEditUnit;

interface

uses
  Classes;

type
  TOldEdit = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $work 'OldEditUnit.pas') $OldEditBody

$NewEditBody = @'
unit NewEditUnit;

interface

uses
  Classes;

type
  TNewEdit = class(TComponent)
  private
    FText: string;
  published
    property Text: string read FText write FText;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $work 'NewEditUnit.pas') $NewEditBody

$MyFormBody = @'
unit MyForm;

interface

uses
  Classes, OldEditUnit;

type
  TMyForm = class(TForm)
    Edit1: TOldEdit;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (Join-Path $work 'MyForm.pas') $MyFormBody

$MyFormDfm = @'
object MyForm: TMyForm
  object Edit1: TOldEdit
    Caption = 'Hi'
  end
end
'@
Write-Ascii (Join-Path $work 'MyForm.dfm') $MyFormDfm

$RulesBody = @'
#convert TOldEdit -> TNewEdit, NewEditUnit
#link Text <- Caption
'@
$rulesPath = Join-Path $WorkDir 'rules.txt'
Write-Ascii $rulesPath $RulesBody

# ---------------------------------------------------------------------------
# Index the fixture
# ---------------------------------------------------------------------------
$db = Join-Path $WorkDir 'convapply.sqlite'
Write-Host 'Indexing convert-apply fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

# ---------------------------------------------------------------------------
# Capture MyForm.pas bytes BEFORE the dry-run, to assert byte-identity after.
# ---------------------------------------------------------------------------
$myFormPath = Join-Path $work 'MyForm.pas'
$beforeBytes = [System.IO.File]::ReadAllBytes($myFormPath)

# ---------------------------------------------------------------------------
# convert-apply --unit MyForm.pas --rules rules.txt --db db  (DRY-RUN, no --apply)
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-apply --unit MyForm.pas --rules rules.txt --db db (dry-run)' -ForegroundColor Cyan
Push-Location $work
try {
  $applyRaw = (& $Exe convert-apply --unit 'MyForm.pas' --rules $rulesPath --db $db 2>&1) -join "`n"
  $applyExit = $LASTEXITCODE
} finally { Pop-Location }
Check 'convert-apply exits 0' ($applyExit -eq 0) "exit=$applyExit"
Write-Host $applyRaw -ForegroundColor DarkGray

# Surface #1: declaration retype. RenderDryRun emits a tekReplaceInLine line
# like: replace L9:C11..19 -> "TNewEdit"  -- so assert both tokens appear
# (the line context showing Edit1's field, and the replacement text TNewEdit).
Check 'shows FromType token TOldEdit' ($applyRaw -match 'TOldEdit') "raw=$applyRaw"
Check 'shows ToType replacement TNewEdit' ($applyRaw -match 'TNewEdit') "raw=$applyRaw"
Check 'shows MyForm.pas as the edited file' ($applyRaw -match [regex]::Escape('MyForm.pas')) "raw=$applyRaw"

# Surface #2: uses-add of NewEditUnit.
Check 'shows uses-add of NewEditUnit' ($applyRaw -match 'NewEditUnit') "raw=$applyRaw"

# Report: per-instance conversion line.
Check 'report mentions Edit1 instance' ($applyRaw -match 'Edit1') "raw=$applyRaw"

# ---------------------------------------------------------------------------
# No-write assertion: MyForm.pas must be byte-identical after the dry-run.
# ---------------------------------------------------------------------------
$afterBytes = [System.IO.File]::ReadAllBytes($myFormPath)
$sameBytes = ($beforeBytes.Length -eq $afterBytes.Length) -and
             (-not (Compare-Object $beforeBytes $afterBytes -SyncWindow 0))
Check 'MyForm.pas byte-unchanged after dry-run' $sameBytes "before=$($beforeBytes.Length)B after=$($afterBytes.Length)B"

# No .bak file should have been written either (dry-run must not touch disk at all).
Check 'no .bak written' (-not (Test-Path ($myFormPath + '.bak'))) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
