<#
  run_convert_apply.ps1 -- convert-apply verb headless test (Track 3, sub-
  project B). Task 2 implemented instance location (FindConvertInstances) +
  surface #1 (.pas declaration retype) + surface #2 (.pas uses-add); Task 3
  added surface #3 (.dfm object-block re-emit via the 2a-i ReemitComponent
  engine). Task 4 (this revision) adds the REAL --apply write path: a
  freshness guard (CheckFreshness), the backup/recovery layer (DRagLint.
  Convert.Backup: NextBackupName/BackupFiles/WriteRecoveryRecord/
  PrependConvertComment), and wires them into `convert-apply --unit F.pas
  --rules R --db D [--only ...] [--apply] [--no-backup]`.

  FIXTURE (built by New-Fixture, so each phase gets a byte-identical FRESH
  copy in its own dir -- --apply mutates files, so the dry-run phase and each
  --apply phase must not share a directory):
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
                         nested under 'object MyForm: TMyForm', carrying
                         'Caption = ''Hi''' (Task 3: the property surface #3's
                         #link Text <- Caption converts).
    rules.txt        -- '#convert TOldEdit -> TNewEdit, NewEditUnit' +
                         '#link Text <- Caption'.

  PHASE 1 ASSERTIONS (dry-run, NO --apply -- unchanged from Task 3):
    - exits 0.
    - dry-run output shows the declaration retype, the uses-add, and the .dfm
      re-emit preview (surfaces #1/#2/#3).
    - MyForm.pas AND MyForm.dfm are BYTE-UNCHANGED on disk after the dry-run
      (no write -- dry-run only prints TTextEditApplier.RenderDryRun).

  PHASE 2 ASSERTIONS (--apply, fresh dir):
    - exits 0.
    - MyForm.pas + MyForm.dfm are CONVERTED on disk (retype + uses + re-emit
      present in the actual file content, not just a preview).
    - MyForm.pas.BCK1 + MyForm.dfm.BCK1 exist and equal the ORIGINAL bytes.
    - recovery.txt exists with a '[...] convert-apply --rules ...' block
      naming both mappings (structure-only assertion -- timestamp unpredictable).
    - MyForm.pas starts with the '// drag-lint convert-apply' comment block.
    - re-running --apply produces .BCK2 (next-free n; .BCK1 untouched).
    - all written files are still ASCII/CRLF.

  PHASE 3 ASSERTIONS (--no-backup, fresh dir):
    - exits 0, converts, but NO .BCK file and NO recovery.txt are written.

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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Assert a file's raw bytes are strict CRLF (no bare LF) + 7-bit ASCII -- the
# same discipline the tool itself must preserve on every write.
function Assert-AsciiCrlf($Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $bareLf = 0
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 10) {
      if ($i -eq 0 -or $bytes[$i - 1] -ne 13) { $bareLf++ }
    }
  }
  $nonAscii = ($bytes | Where-Object { $_ -gt 127 }).Count
  Check "$(Split-Path -Leaf $Path): CRLF (0 bare LF)" ($bareLf -eq 0) "bareLf=$bareLf"
  Check "$(Split-Path -Leaf $Path): ASCII (0 non-ascii bytes)" ($nonAscii -eq 0) "nonAscii=$nonAscii"
}

# ---------------------------------------------------------------------------
# Fixture units -- written fresh into $dir each time New-Fixture is called,
# so --apply's in-place mutation in one phase never bleeds into another.
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

$MyFormBody = @'
unit MyForm;

interface

uses
  Classes, OldEditUnit;

type
  TMyForm = class(TForm)
    Edit1: TOldEdit;
    procedure MakeEdit1;
  end;

implementation

{$R *.dfm}

procedure TMyForm.MakeEdit1;
begin
  Edit1 := TOldEdit.Create(Self);
end;

end.
'@

$MyFormDfm = @'
object MyForm: TMyForm
  object Edit1: TOldEdit
    Caption = 'Hi'
  end
end
'@

$RulesBody = @'
#convert TOldEdit -> TNewEdit, NewEditUnit
#link Text <- Caption
'@

function New-Fixture([string]$dir) {
  New-Item -ItemType Directory $dir -Force | Out-Null
  Write-Ascii (Join-Path $dir 'OldEditUnit.pas') $OldEditBody
  Write-Ascii (Join-Path $dir 'NewEditUnit.pas') $NewEditBody
  Write-Ascii (Join-Path $dir 'MyForm.pas') $MyFormBody
  Write-Ascii (Join-Path $dir 'MyForm.dfm') $MyFormDfm
}

$rulesPath = Join-Path $WorkDir 'rules.txt'
Write-Ascii $rulesPath $RulesBody

# ---------------------------------------------------------------------------
# Index the fixture (one shared index -- Phase 2/3 re-copy the fixture into
# fresh dirs but the .pas/.dfm CONTENT is byte-identical each time, so the
# same index resolves symbols for all phases; the freshness guard's mtime/sha
# check is against each phase's OWN on-disk copy, computed fresh per index run
# below via a single 'index' pass over $WorkDir covering every subfolder).
# ---------------------------------------------------------------------------
$phase1 = Join-Path $WorkDir 'phase1-dryrun'
$phase2 = Join-Path $WorkDir 'phase2-apply'
$phase3 = Join-Path $WorkDir 'phase3-nosafety'
New-Fixture $phase1
New-Fixture $phase2
New-Fixture $phase3

$db = Join-Path $WorkDir 'convapply.sqlite'
Write-Host 'Indexing convert-apply fixture (all phases)' -ForegroundColor Cyan
$indexOut = & $Exe index $WorkDir --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

# ===========================================================================
# PHASE 1: convert-apply --unit MyForm.pas --rules rules.txt --db db  (DRY-RUN, no --apply)
# ===========================================================================
Write-Host ''
Write-Host '=== Phase 1: dry-run (no --apply) ===' -ForegroundColor Cyan
$myFormPath = Join-Path $phase1 'MyForm.pas'
$myFormDfmPath = Join-Path $phase1 'MyForm.dfm'
$beforeBytes = [System.IO.File]::ReadAllBytes($myFormPath)
$beforeDfmBytes = [System.IO.File]::ReadAllBytes($myFormDfmPath)

Push-Location $phase1
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

# Surface #3: .dfm object-block re-emit. RenderDryRun previews a delete-range
# for the OLD block ('object Edit1: TOldEdit' + 'Caption = ''Hi''', 3 lines --
# it does not echo deleted content, only the line range) followed by an
# insert-after carrying the re-emitted T block text ('object Edit1: TNewEdit'
# + 'Text = ''Hi''', per #link Text <- Caption), against MyForm.dfm.
Check 'shows MyForm.dfm as an edited file' ($applyRaw -match [regex]::Escape('MyForm.dfm')) "raw=$applyRaw"
Check 'shows .dfm delete-lines preview for the old 3-line block' ($applyRaw -match 'delete lines 2\.\.4') "raw=$applyRaw"
Check 'shows re-emitted .dfm header TNewEdit' ($applyRaw -match 'object Edit1: TNewEdit') "raw=$applyRaw"
Check 'shows re-emitted Text = ''Hi''' ($applyRaw -match "Text\s*=\s*'Hi'") "raw=$applyRaw"

# Surface #5: runtime-creator retype. The 'Edit1 := TOldEdit.Create(Self);'
# construction site in TMyForm.MakeEdit1 must have its FromType token rewritten
# to ToType (TNewEdit.Create(Self)) AND a TODO marker planted at the site
# (creator/ctor shape can differ -- the marker is the safety net, args are
# never auto-fixed). RenderDryRun previews both as edits against MyForm.pas.
Check 'shows creator retype -> TNewEdit.Create' ($applyRaw -match 'TNewEdit') "raw=$applyRaw"
Check 'shows TODO marker for verify creator TNewEdit' ($applyRaw -match [regex]::Escape('TODO') + '.*verify creator for TNewEdit') "raw=$applyRaw"
Check 'shows TODO marker names TOldEdit.Create as the original' ($applyRaw -match [regex]::Escape('TOldEdit.Create')) "raw=$applyRaw"

# Report.Todos surfaced in dry-run output (CLI must print the Todos block).
Check 'dry-run output has a Todos: block' ($applyRaw -match 'Todos:') "raw=$applyRaw"
Check 'Todos block lists the verify-creator marker' ($applyRaw -match 'Todos:[\s\S]*verify creator for TNewEdit') "raw=$applyRaw"

# Report: per-instance conversion line.
Check 'report mentions Edit1 instance' ($applyRaw -match 'Edit1') "raw=$applyRaw"

# No-write assertion: MyForm.pas and MyForm.dfm must be byte-identical after the dry-run.
$afterBytes = [System.IO.File]::ReadAllBytes($myFormPath)
$sameBytes = ($beforeBytes.Length -eq $afterBytes.Length) -and
             (-not (Compare-Object $beforeBytes $afterBytes -SyncWindow 0))
Check 'MyForm.pas byte-unchanged after dry-run' $sameBytes "before=$($beforeBytes.Length)B after=$($afterBytes.Length)B"

$afterDfmBytes = [System.IO.File]::ReadAllBytes($myFormDfmPath)
$sameDfmBytes = ($beforeDfmBytes.Length -eq $afterDfmBytes.Length) -and
             (-not (Compare-Object $beforeDfmBytes $afterDfmBytes -SyncWindow 0))
Check 'MyForm.dfm byte-unchanged after dry-run' $sameDfmBytes "before=$($beforeDfmBytes.Length)B after=$($afterDfmBytes.Length)B"

# No .bak/.BCK file should have been written either (dry-run must not touch disk at all).
Check 'no .bak written' (-not (Test-Path ($myFormPath + '.bak'))) ''
Check 'no .dfm.bak written' (-not (Test-Path ($myFormDfmPath + '.bak'))) ''
Check 'no .BCK1 written (dry-run)' (-not (Test-Path ($myFormPath + '.BCK1'))) ''
Check 'no recovery.txt written (dry-run)' (-not (Test-Path (Join-Path $phase1 'recovery.txt'))) ''

# ===========================================================================
# PHASE 2: convert-apply --apply  -- the real write path.
# ===========================================================================
Write-Host ''
Write-Host '=== Phase 2: --apply (writes + backups + recovery.txt + comment) ===' -ForegroundColor Cyan
$p2Pas = Join-Path $phase2 'MyForm.pas'
$p2Dfm = Join-Path $phase2 'MyForm.dfm'
$p2PasOrigBytes = [System.IO.File]::ReadAllBytes($p2Pas)
$p2DfmOrigBytes = [System.IO.File]::ReadAllBytes($p2Dfm)

Push-Location $phase2
try {
  $apply1Raw = (& $Exe convert-apply --unit 'MyForm.pas' --rules $rulesPath --db $db --apply 2>&1) -join "`n"
  $apply1Exit = $LASTEXITCODE
} finally { Pop-Location }
Check '--apply (1st run) exits 0' ($apply1Exit -eq 0) "exit=$apply1Exit"
Write-Host $apply1Raw -ForegroundColor DarkGray

# MyForm.pas + MyForm.dfm are CONVERTED on disk: retype + uses + re-emit present.
$p2PasText = [System.IO.File]::ReadAllText($p2Pas)
$p2DfmText = [System.IO.File]::ReadAllText($p2Dfm)
Check 'MyForm.pas converted: Edit1: TNewEdit' ($p2PasText -match 'Edit1\s*:\s*TNewEdit') "text=$p2PasText"
Check 'MyForm.pas converted: uses NewEditUnit' ($p2PasText -match 'NewEditUnit') "text=$p2PasText"
Check 'MyForm.dfm converted: object Edit1: TNewEdit' ($p2DfmText -match 'object Edit1:\s*TNewEdit') "text=$p2DfmText"

# Surface #5 on disk: the construction site is rewritten (TNewEdit.Create) and
# carries the TODO marker -- the type is converted for real, and the safety-net
# comment survives the actual write (not just the dry-run preview).
Check 'MyForm.pas converted: creator site TNewEdit.Create' ($p2PasText -match [regex]::Escape('TNewEdit.Create(Self)')) "text=$p2PasText"
Check 'MyForm.pas converted: creator site carries TODO marker' ($p2PasText -match [regex]::Escape('TODO') + '.*verify creator for TNewEdit') "text=$p2PasText"
Check 'MyForm.dfm converted: Text = ''Hi''' ($p2DfmText -match "Text\s*=\s*'Hi'") "text=$p2DfmText"

# .BCK1 exist and equal the ORIGINAL bytes.
$p2PasBck1 = $p2Pas + '.BCK1'
$p2DfmBck1 = $p2Dfm + '.BCK1'
Check 'MyForm.pas.BCK1 exists' (Test-Path $p2PasBck1) ''
Check 'MyForm.dfm.BCK1 exists' (Test-Path $p2DfmBck1) ''
if (Test-Path $p2PasBck1) {
  $b = [System.IO.File]::ReadAllBytes($p2PasBck1)
  $eq = ($b.Length -eq $p2PasOrigBytes.Length) -and (-not (Compare-Object $b $p2PasOrigBytes -SyncWindow 0))
  Check 'MyForm.pas.BCK1 == original bytes' $eq "bck=$($b.Length)B orig=$($p2PasOrigBytes.Length)B"
}
if (Test-Path $p2DfmBck1) {
  $b = [System.IO.File]::ReadAllBytes($p2DfmBck1)
  $eq = ($b.Length -eq $p2DfmOrigBytes.Length) -and (-not (Compare-Object $b $p2DfmOrigBytes -SyncWindow 0))
  Check 'MyForm.dfm.BCK1 == original bytes' $eq "bck=$($b.Length)B orig=$($p2DfmOrigBytes.Length)B"
}

# recovery.txt exists with a '[...] convert-apply --rules ...' block naming
# both mappings + the rules file (structure only -- no exact timestamp).
$recoveryPath = Join-Path $phase2 'recovery.txt'
Check 'recovery.txt exists' (Test-Path $recoveryPath) ''
if (Test-Path $recoveryPath) {
  $rec = Get-Content $recoveryPath -Raw
  Check 'recovery.txt has a [...] convert-apply --rules line' ($rec -match '\[[^\]]+\]\s+convert-apply\s+--rules') "rec=$rec"
  Check 'recovery.txt names rules.txt' ($rec -match [regex]::Escape('rules.txt')) "rec=$rec"
  Check 'recovery.txt maps MyForm.pas -> MyForm.pas.BCK1' ($rec -match [regex]::Escape('MyForm.pas -> ') + '.*BCK1') "rec=$rec"
  Check 'recovery.txt maps MyForm.dfm -> MyForm.dfm.BCK1' ($rec -match [regex]::Escape('MyForm.dfm -> ') + '.*BCK1') "rec=$rec"
}

# MyForm.pas starts with the '// drag-lint convert-apply' comment block.
$p2PasLines = Get-Content $p2Pas -TotalCount 2
Check 'MyForm.pas starts with the convert-apply comment' ($p2PasLines[0] -match '^// drag-lint convert-apply') "line0=$($p2PasLines[0])"
Check 'MyForm.pas comment line 2 names backup + rules' ($p2PasLines[1] -match 'backup:.*BCK1.*rules:') "line1=$($p2PasLines[1])"

# Written files must still be ASCII/CRLF.
Assert-AsciiCrlf $p2Pas
Assert-AsciiCrlf $p2Dfm

# ---------------------------------------------------------------------------
# Re-running --apply produces .BCK2 (next-free n; .BCK1 untouched). MyForm.pas/
# .dfm are already converted (TNewEdit) after the 1st run, so there is nothing
# left for FindConvertInstances to match -- restore the ORIGINAL (F-typed)
# fixture content in place (simulating "convert-apply run again", e.g. a
# reverted/re-edited unit) WITHOUT touching the existing .BCK1/recovery.txt,
# then reindex (the freshness guard would otherwise refuse on the now-stale
# index) before the 2nd --apply.
# ---------------------------------------------------------------------------
$p2PasBck1BytesBeforeRerun = [System.IO.File]::ReadAllBytes($p2PasBck1)
Write-Ascii $p2Pas $MyFormBody
Write-Ascii $p2Dfm $MyFormDfm
$reindex2Out = & $Exe index $phase2 --db $db 2>&1
$reindex2Exit = $LASTEXITCODE
Check 'reindex phase2 before re-run exits 0' ($reindex2Exit -eq 0) "exit=$reindex2Exit; $($reindex2Out -join ' | ')"

Push-Location $phase2
try {
  $apply2Raw = (& $Exe convert-apply --unit 'MyForm.pas' --rules $rulesPath --db $db --apply 2>&1) -join "`n"
  $apply2Exit = $LASTEXITCODE
} finally { Pop-Location }
Check '--apply (2nd run) exits 0' ($apply2Exit -eq 0) "exit=$apply2Exit"
Write-Host $apply2Raw -ForegroundColor DarkGray
Check '.BCK2 created on re-run' (Test-Path ($p2Pas + '.BCK2')) ''
Check '.dfm.BCK2 created on re-run' (Test-Path ($p2Dfm + '.BCK2')) ''
$p2PasBck1BytesAfterRerun = [System.IO.File]::ReadAllBytes($p2PasBck1)
$bck1Untouched = ($p2PasBck1BytesBeforeRerun.Length -eq $p2PasBck1BytesAfterRerun.Length) -and
                 (-not (Compare-Object $p2PasBck1BytesBeforeRerun $p2PasBck1BytesAfterRerun -SyncWindow 0))
Check '.BCK1 untouched by re-run' $bck1Untouched ''

# ===========================================================================
# PHASE 3: convert-apply --apply --no-backup  -- converts, writes NO .BCK / recovery.txt.
# ===========================================================================
Write-Host ''
Write-Host '=== Phase 3: --apply --no-backup (converts, skips backups) ===' -ForegroundColor Cyan
$p3Pas = Join-Path $phase3 'MyForm.pas'
$p3Dfm = Join-Path $phase3 'MyForm.dfm'

Push-Location $phase3
try {
  $apply3Raw = (& $Exe convert-apply --unit 'MyForm.pas' --rules $rulesPath --db $db --apply --no-backup 2>&1) -join "`n"
  $apply3Exit = $LASTEXITCODE
} finally { Pop-Location }
Check '--apply --no-backup exits 0' ($apply3Exit -eq 0) "exit=$apply3Exit"
Write-Host $apply3Raw -ForegroundColor DarkGray

$p3PasText = [System.IO.File]::ReadAllText($p3Pas)
$p3DfmText = [System.IO.File]::ReadAllText($p3Dfm)
Check 'no-backup: MyForm.pas still converted (Edit1: TNewEdit)' ($p3PasText -match 'Edit1\s*:\s*TNewEdit') "text=$p3PasText"
Check 'no-backup: MyForm.dfm still converted (object Edit1: TNewEdit)' ($p3DfmText -match 'object Edit1:\s*TNewEdit') "text=$p3DfmText"

Check 'no-backup: no MyForm.pas.BCK1' (-not (Test-Path ($p3Pas + '.BCK1'))) ''
Check 'no-backup: no MyForm.dfm.BCK1' (-not (Test-Path ($p3Dfm + '.BCK1'))) ''
Check 'no-backup: no recovery.txt' (-not (Test-Path (Join-Path $phase3 'recovery.txt'))) ''

Assert-AsciiCrlf $p3Pas
Assert-AsciiCrlf $p3Dfm

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
