<#
  run_convert_apply.ps1 -- convert-apply verb headless test (Track 3, sub-
  project B). Task 2 implemented instance location (FindConvertInstances) +
  surface #1 (.pas declaration retype) + surface #2 (.pas uses-add); Task 3
  added surface #3 (.dfm object-block re-emit via the 2a-i ReemitComponent
  engine). Task 4 added the REAL --apply write path: a freshness guard
  (CheckFreshness), the backup/recovery layer (DRagLint.Convert.Backup:
  NextBackupName/BackupFiles/WriteRecoveryRecord/PrependConvertComment), and
  wires them into `convert-apply --unit F.pas --rules R --db D [--only ...]
  [--apply] [--no-backup]`. Task 6 added surface #4: instance-scoped
  property/event ACCESS rewrite at .pas use sites, via ref-gap G's
  'member-access' refs (Edit1.Caption -> Edit1.Text) -- the differentiator
  that makes a renamed-property conversion actually COMPILE. Task 7 (this
  revision) adds the CONSOLIDATED end-to-end case: ALL 5 surfaces exercised
  in ONE --apply run, PLUS a moved-depth nested property (Font.Size ->
  Style.Active.Font.Size, .dfm-only -- surface #4 is deliberately
  single-segment-only per BuildApplyPlan's own doc comment, so a moved-depth
  path is exactly the surface-#3-only case a real conversion needs to prove)
  and an event rename (OnClick -> OnClick2, .dfm-only, the same dnkEvent leaf
  path DfmReemit already re-emits). This is the "real-life-shaped smoke":
  the .dfm and the .pas must agree on the SAME renamed name, or the result
  would not compile.

  FIXTURE (built by New-Fixture, so each phase gets a byte-identical FRESH
  copy in its own dir -- --apply mutates files, so the dry-run phase and each
  --apply phase must not share a directory):
    OldEditUnit.pas  -- declares TOldEdit (published Caption: string; Font:
                         TFont2 class-typed sub-object with Size: Integer;
                         OnClick: TNotifyEvent), the F (from) type being
                         converted away from.
    NewEditUnit.pas  -- declares TNewEdit (published Text: string; Style:
                         TStyle2 -> Active: TActiveStyle -> Font: TFont2 with
                         Size: Integer, a 3-deep moved-depth chain; OnClick2:
                         TNotifyEvent), the T (to) type being converted to.
                         Both units are indexed so BuildPropTree / find-unit /
                         the field-decl scan can all resolve real symbols
                         (per the brief: "must be defined in indexable
                         fixture units").
    OtherUnit.pas    -- declares TSomethingElse (a plain, UNCONVERTED class
                         with its own Caption field) so 'Other.Caption' is a
                         real member-access on a receiver that is NOT a
                         converted instance -- the surface #4 negative case.
    MyForm.pas       -- a tiny form unit with one published field
                         'Edit1: TOldEdit', a field 'Other: TSomethingElse',
                         and a bare 'uses Classes, OldEditUnit, OtherUnit;'
                         (no NewEditUnit yet -- surface #2 must add it). The
                         MakeEdit1 body also exercises surface #4:
                         'Edit1.Caption := ''x'';' (write-side access),
                         'y := Edit1.Caption;' (read-side access), and
                         'Other.Caption := ''z'';' (NOT a converted instance
                         -- must NOT be rewritten).
    MyForm.dfm       -- one component instance 'object Edit1: TOldEdit'
                         nested under 'object MyForm: TMyForm', carrying
                         'Caption = ''Hi''' (surface #3's #link Text <-
                         Caption converts), a nested 'object Font: TFont2 /
                         Size = 12 / end' sub-object (surface #3's moved-depth
                         #link Style.Active.Font.Size <- Font.Size converts,
                         re-nesting Size 3 levels deep under Style/Active/
                         Font), and 'OnClick = MyForm1Click' (surface #3's
                         event #link OnClick2 <- OnClick converts).
    rules.txt        -- '#convert TOldEdit -> TNewEdit, NewEditUnit' +
                         '#link Text <- Caption' +
                         '#link Style.Active.Font.Size <- Font.Size' +
                         '#link OnClick2 <- OnClick'.

  PHASE 1 ASSERTIONS (dry-run, NO --apply -- unchanged from Task 3/6, PLUS
  Task 7's moved-depth/event assertions):
    - exits 0.
    - dry-run output shows the declaration retype, the uses-add, and the .dfm
      re-emit preview (surfaces #1/#2/#3), including the moved-depth Style/
      Active/Font nesting and the re-emitted OnClick2 event line.
    - both Edit1.Caption access sites (write in MakeEdit1's 'Edit1.Caption :=
      ''x'';' and read in 'y := Edit1.Caption;') are rewritten to Edit1.Text;
      Report.AccessSites lists both. 'Other.Caption := ''z'';' is UNCHANGED
      (Other is not a converted instance) and does NOT appear in AccessSites.
    - MyForm.pas AND MyForm.dfm are BYTE-UNCHANGED on disk after the dry-run
      (no write -- dry-run only prints TTextEditApplier.RenderDryRun).

  PHASE 2 ASSERTIONS (--apply, fresh dir) -- THE CONSOLIDATED END-TO-END CASE,
  all 5 surfaces + safety in ONE --apply run:
    - exits 0.
    - MyForm.pas + MyForm.dfm are CONVERTED on disk (retype + uses + re-emit
      present in the actual file content, not just a preview): surface #1
      (Edit1: TNewEdit), #2 (uses NewEditUnit), #3 (object Edit1: TNewEdit,
      Text = 'Hi', the moved-depth Style/Active/Font/Size = 12 nesting, and
      OnClick2 = MyForm1Click), #4 (Edit1.Text at both access sites, Other.
      Caption left untouched), #5 (TNewEdit.Create(Self) + the verify-creator
      TODO marker).
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
  TNotifyEvent = procedure(Sender: TObject) of object;

  TFont2 = class(TPersistent)
  private
    FSize: Integer;
  published
    property Size: Integer read FSize write FSize;
  end;

  TOldEdit = class(TComponent)
  private
    FCaption: string;
    FFont: TFont2;
    FOnClick: TNotifyEvent;
  published
    property Caption: string read FCaption write FCaption;
    property Font: TFont2 read FFont write FFont;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
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
  TNotifyEvent = procedure(Sender: TObject) of object;

  TFont2 = class(TPersistent)
  private
    FSize: Integer;
  published
    property Size: Integer read FSize write FSize;
  end;

  TActiveStyle = class(TPersistent)
  private
    FFont: TFont2;
  published
    property Font: TFont2 read FFont write FFont;
  end;

  TStyle2 = class(TPersistent)
  private
    FActive: TActiveStyle;
  published
    property Active: TActiveStyle read FActive write FActive;
  end;

  TNewEdit = class(TComponent)
  private
    FText: string;
    FStyle: TStyle2;
    FOnClick2: TNotifyEvent;
  published
    property Text: string read FText write FText;
    property Style: TStyle2 read FStyle write FStyle;
    property OnClick2: TNotifyEvent read FOnClick2 write FOnClick2;
  end;

implementation

end.
'@

$OtherBody = @'
unit OtherUnit;

interface

uses
  Classes;

type
  TSomethingElse = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@

$MyFormBody = @'
unit MyForm;

interface

uses
  Classes, OldEditUnit, OtherUnit;

type
  TMyForm = class(TForm)
    Edit1: TOldEdit;
    Other: TSomethingElse;
    procedure MakeEdit1;
  end;

implementation

{$R *.dfm}

procedure TMyForm.MakeEdit1;
var
  s: string;
  y: string;
begin
  Edit1 := TOldEdit.Create(Self);
  s := TOldEdit.ClassName;
  Edit1.Caption := 'x';
  y := Edit1.Caption;
  Other.Caption := 'z';
end;

end.
'@

$MyFormDfm = @'
object MyForm: TMyForm
  object Edit1: TOldEdit
    Caption = 'Hi'
    OnClick = MyForm1Click
    object Font: TFont2
      Size = 12
    end
  end
end
'@

$RulesBody = @'
#convert TOldEdit -> TNewEdit, NewEditUnit
#link Text <- Caption
#link Style.Active.Font.Size <- Font.Size
#link OnClick2 <- OnClick
'@

function New-Fixture([string]$dir) {
  New-Item -ItemType Directory $dir -Force | Out-Null
  Write-Ascii (Join-Path $dir 'OldEditUnit.pas') $OldEditBody
  Write-Ascii (Join-Path $dir 'NewEditUnit.pas') $NewEditBody
  Write-Ascii (Join-Path $dir 'OtherUnit.pas') $OtherBody
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
# for the OLD block ('object Edit1: TOldEdit' .. its matching 'end', 7 lines
# (header + Caption + OnClick + nested Font sub-object's 3 lines + end) --
# it does not echo deleted content, only the line range) followed by an
# insert-after carrying the re-emitted T block text ('object Edit1: TNewEdit'
# + 'Text = ''Hi''', per #link Text <- Caption), against MyForm.dfm.
Check 'shows MyForm.dfm as an edited file' ($applyRaw -match [regex]::Escape('MyForm.dfm')) "raw=$applyRaw"
Check 'shows .dfm delete-lines preview for the old 7-line block' ($applyRaw -match 'delete lines 2\.\.8') "raw=$applyRaw"
Check 'shows re-emitted .dfm header TNewEdit' ($applyRaw -match 'object Edit1: TNewEdit') "raw=$applyRaw"
Check 'shows re-emitted Text = ''Hi''' ($applyRaw -match "Text\s*=\s*'Hi'") "raw=$applyRaw"

# Surface #3 (moved-depth): '#link Style.Active.Font.Size <- Font.Size' must
# re-nest the F-side 'object Font: TFont2 / Size = 12' sub-object 3 levels
# deep under a newly-created Style/Active/Font chain in the re-emitted T
# block (this is a .dfm-only surface -- BuildApplyPlan's own doc comment
# marks surface #4's .pas access rewrite as single-segment-paths-only, so a
# dotted #link path like this one is correctly OUT of surface #4's scope and
# must show up here, on the .dfm side, instead).
Check 'shows moved-depth nesting object Style' ($applyRaw -match 'object Style') "raw=$applyRaw"
Check 'shows moved-depth nesting object Active' ($applyRaw -match 'object Active') "raw=$applyRaw"
Check 'shows moved-depth nesting object Font' ($applyRaw -match 'object Font') "raw=$applyRaw"
Check 'shows moved-depth Size = 12 preserved' ($applyRaw -match 'Size\s*=\s*12') "raw=$applyRaw"

# Surface #3 (event): '#link OnClick2 <- OnClick' re-emits the event binding
# under its new name, value unchanged (DfmReemit classifies "On*" + an
# identifier_value as a dnkEvent leaf and remaps the LEAF NAME only).
Check 'shows re-emitted event OnClick2 = MyForm1Click' ($applyRaw -match 'OnClick2\s*=\s*MyForm1Click') "raw=$applyRaw"

# Surface #5: runtime-creator retype. The 'Edit1 := TOldEdit.Create(Self);'
# construction site in TMyForm.MakeEdit1 must have its FromType token rewritten
# to ToType (TNewEdit.Create(Self)) AND a TODO marker planted at the site
# (creator/ctor shape can differ -- the marker is the safety net, args are
# never auto-fixed). RenderDryRun previews both as edits against MyForm.pas.
Check 'shows creator retype -> TNewEdit.Create' ($applyRaw -match 'TNewEdit') "raw=$applyRaw"
Check 'shows TODO marker for verify creator TNewEdit' ($applyRaw -match [regex]::Escape('TODO') + '.*verify creator for TNewEdit') "raw=$applyRaw"
Check 'shows TODO marker names TOldEdit.Create as the original' ($applyRaw -match [regex]::Escape('TOldEdit.Create')) "raw=$applyRaw"

# Surface #4: instance-scoped property/event ACCESS rewrite (Task 6, via
# ref-gap G's 'member-access' refs). 'Edit1.Caption := ''x'';' (write) and
# 'y := Edit1.Caption;' (read) both name a CONVERTED instance (Edit1) -- both
# access sites must be rewritten to Edit1.Text, and both must be listed in
# the AccessSites: block. 'Other.Caption := ''z'';' names Other, which is NOT
# a converted instance (TSomethingElse has no #convert rule) -- it must NOT
# be rewritten and must NOT appear in AccessSites.
Check 'dry-run output has an AccessSites: block' ($applyRaw -match 'AccessSites:') "raw=$applyRaw"
$accessBlockMatch = [regex]::Match($applyRaw, 'AccessSites:([\s\S]*?)(\r?\n\r?\n|\z)')
$accessBlock = if ($accessBlockMatch.Success) { $accessBlockMatch.Groups[1].Value } else { '' }
Check 'AccessSites block lists Edit1 Caption -> Text' ($accessBlock -match 'Edit1.*Caption.*Text') "block=$accessBlock"
$edit1AccessCount = ([regex]::Matches($accessBlock, 'Edit1')).Count
Check 'AccessSites block lists BOTH Edit1.Caption sites (write + read)' ($edit1AccessCount -ge 2) "count=$edit1AccessCount; block=$accessBlock"
Check 'AccessSites block does NOT mention Other (not a converted instance)' (-not ($accessBlock -match 'Other')) "block=$accessBlock"

# The edit plan itself: two tekReplaceInLine edits rewriting the Caption token
# to Text on Edit1's lines, and the plan must show at least 2 "-> ""Text"""
# replacements (write + read sites) while the Other.Caption line is untouched.
$textReplaceCount = ([regex]::Matches($applyRaw, '->\s*"Text"')).Count
Check 'at least 2 replace-to-Text edits in the plan (Edit1.Caption write+read)' ($textReplaceCount -ge 2) "count=$textReplaceCount; raw=$applyRaw"

# Report.Todos surfaced in dry-run output (CLI must print the Todos block).
Check 'dry-run output has a Todos: block' ($applyRaw -match 'Todos:') "raw=$applyRaw"
Check 'Todos block lists the verify-creator marker' ($applyRaw -match 'Todos:[\s\S]*verify creator for TNewEdit') "raw=$applyRaw"

# I-1 regression: 's := TOldEdit.ClassName;' is a class-STATIC reference, not
# a construction -- ClassName is not a constructor of TOldEdit. It must NOT be
# misdetected as surface #5 (no false 'verify creator ... ClassName' TODO, and
# it must not appear in Report.Todos as a creator entry). The type token on
# that line MAY still be rewritten TOldEdit -> TNewEdit (that is the harmless,
# correct type-conversion side effect) -- only the false-creator flagging is
# asserted against here. Exact-count assertion (exactly 1 marker inside the
# canonical 'Todos:' summary block -- the real TOldEdit.Create site only) is
# the strongest signal -- a substring absence check alone would not catch a
# false marker with different wording. (The dry-run edit-plan preview ALSO
# echoes each TODO's insert text once, so the count is taken from the Todos:
# block specifically, not the whole raw output, to avoid double-counting.)
Check 'no false creator TODO for ClassName' (-not ($applyRaw -match [regex]::Escape('verify creator for TNewEdit (was TOldEdit.ClassName)'))) "raw=$applyRaw"
$todosBlockMatch = [regex]::Match($applyRaw, 'Todos:([\s\S]*?)(\r?\n\r?\n|\z)')
$todosBlock = if ($todosBlockMatch.Success) { $todosBlockMatch.Groups[1].Value } else { '' }
$todoMarkerCount = ([regex]::Matches($todosBlock, [regex]::Escape('TODO: drag-lint convert -- verify creator'))).Count
Check 'exactly 1 verify-creator TODO marker in Todos: block (Create only, not ClassName)' ($todoMarkerCount -eq 1) "count=$todoMarkerCount; block=$todosBlock"

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

# Surface #4 on disk: both Edit1.Caption access sites (write + read) are
# rewritten to Edit1.Text; Other.Caption is untouched (Other is not a
# converted instance).
Check 'MyForm.pas converted: Edit1.Caption write -> Edit1.Text' ($p2PasText -match [regex]::Escape('Edit1.Text := ''x''')) "text=$p2PasText"
Check 'MyForm.pas converted: Edit1.Caption read -> Edit1.Text' ($p2PasText -match [regex]::Escape('y := Edit1.Text;')) "text=$p2PasText"
Check 'MyForm.pas converted: Other.Caption UNCHANGED (not a converted instance)' ($p2PasText -match [regex]::Escape('Other.Caption := ''z''')) "text=$p2PasText"
Check 'MyForm.pas converted: no stray Other.Text (Other must not be rewritten)' (-not ($p2PasText -match [regex]::Escape('Other.Text'))) "text=$p2PasText"
Check 'MyForm.dfm converted: Text = ''Hi''' ($p2DfmText -match "Text\s*=\s*'Hi'") "text=$p2DfmText"

# Surface #3 (moved-depth) on disk: Font.Size is re-nested 3 levels deep under
# Style/Active/Font in the WRITTEN .dfm, and the .pas is untouched by it
# (moved-depth is .dfm-only, surface #4's access rewrite is single-segment
# paths only -- see BuildApplyPlan's own doc comment).
Check 'MyForm.dfm converted: moved-depth object Style' ($p2DfmText -match 'object Style') "text=$p2DfmText"
Check 'MyForm.dfm converted: moved-depth object Active' ($p2DfmText -match 'object Active') "text=$p2DfmText"
Check 'MyForm.dfm converted: moved-depth object Font' ($p2DfmText -match 'object Font') "text=$p2DfmText"
Check 'MyForm.dfm converted: moved-depth Size = 12 preserved' ($p2DfmText -match 'Size\s*=\s*12') "text=$p2DfmText"

# Surface #3 (event) on disk: OnClick -> OnClick2, value (the handler method
# name MyForm1Click) carried across unchanged.
Check 'MyForm.dfm converted: event OnClick2 = MyForm1Click' ($p2DfmText -match 'OnClick2\s*=\s*MyForm1Click') "text=$p2DfmText"
Check 'MyForm.dfm converted: old event name OnClick gone (only OnClick2 remains)' (-not ($p2DfmText -match '(?<!2)OnClick\s*=')) "text=$p2DfmText"

# I-1 regression on disk: the ClassName class-static reference line must NOT
# carry a false verify-creator TODO after the real --apply write.
$classNameLine = ($p2PasText -split "`r`n") | Where-Object { $_ -match 'ClassName' }
Check 'on-disk: ClassName line has no verify-creator TODO' (-not ($classNameLine -match 'TODO.*verify creator')) "line=$classNameLine"

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
