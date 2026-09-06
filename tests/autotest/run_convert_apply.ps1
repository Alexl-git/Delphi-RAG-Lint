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
    FEnabled: Boolean;
    FHint: string;
  published
    property Caption: string read FCaption write FCaption;
    property Font: TFont2 read FFont write FFont;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
    { Phase 8: absent from MyForm.dfm because it sits at its declared default,
      so its value is READABLE and must be carried across explicitly. }
    property Enabled: Boolean read FEnabled write FEnabled default True;
    { Phase 8 control: absent with NO default clause, so genuinely unknown. }
    property Hint: string read FHint write FHint;
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
    FEnabled2: Boolean;
    FHint2: string;
  published
    property Text: string read FText write FText;
    property Style: TStyle2 read FStyle write FStyle;
    property OnClick2: TNotifyEvent read FOnClick2 write FOnClick2;
    { Phase 8. Enabled2's default deliberately DISAGREES with TOldEdit.Enabled's,
      so carrying nothing across would silently change the value. }
    property Enabled2: Boolean read FEnabled2 write FEnabled2 default False;
    property Hint2: string read FHint2 write FHint2;
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

# Phase 4 only. Identical to $RulesBody but for the ': Round' cast suffix.
$CastRulesBody = @'
#convert TOldEdit -> TNewEdit, NewEditUnit
#link Text <- Caption : Round
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

# Phase 4's rule book: byte-identical to $RulesBody except for the ': Round'
# cast suffix on the Text <- Caption line. Keeping every other line the same is
# what makes Phase 1 a valid control for Phase 4 -- the ONLY variable is the cast.
$castRulesPath = Join-Path $WorkDir 'rules-cast.txt'
Write-Ascii $castRulesPath $CastRulesBody

# Phase 6's rule book: an #apply whose mapping matches NOTHING. The fixture's
# Edit1 has Caption = 'Hi'; the only #when tests for 'Nope' and there is no
# #else, so the value is left unmapped -- the mapping-not-applied remainder.
# The #apply sits AFTER the #convert deliberately: scope is the nearest
# preceding #convert, so putting it first would make it file-scope instead.
$MapRulesBody = @'
#convert TOldEdit -> TNewEdit, NewEditUnit
#mapping CapMap from U.TCapEnum to U.TNewEdit
#mapping CapMap #when Caption = 'Nope' -> Text = 'X'
#apply CapMap
#link Style.Active.Font.Size <- Font.Size
#link OnClick2 <- OnClick
'@
$mapRulesPath = Join-Path $WorkDir 'rules-mapping.txt'
Write-Ascii $mapRulesPath $MapRulesBody

# Phase 7's rule book: a #default on a path a #link ALREADY carries. The
# fixture's Edit1 has Caption = 'Hi' and the #link moves it to Text, so the
# #default has nothing left to do -- it must not fire, and it must be REPORTED.
# The #default sits on line 3 and that is the rule_line the item must carry.
$DefRulesBody = @'
#convert TOldEdit -> TNewEdit, NewEditUnit
#link Text <- Caption
#default Text = 'Zzz'
#link Style.Active.Font.Size <- Font.Size
#link OnClick2 <- OnClick
'@
$defRulesPath = Join-Path $WorkDir 'rules-default.txt'
Write-Ascii $defRulesPath $DefRulesBody

# Phase 8's rule book. Enabled is absent from MyForm.dfm because it sits at its
# declared default (True); TNewEdit.Enabled2 defaults to False, so carrying
# nothing across would silently flip it. Hint is absent with NO default clause,
# which is the genuinely-unknown case the narrowed divergence note still names.
$ResolvedRulesBody = @'
#convert TOldEdit -> TNewEdit, NewEditUnit
#link Text <- Caption
#link Enabled2 <- Enabled
#link Hint2 <- Hint
'@
$resolvedRulesPath = Join-Path $WorkDir 'rules-resolved.txt'
Write-Ascii $resolvedRulesPath $ResolvedRulesBody

# Phase 9's fixture: an OWNED PART with its own #convert, so HandleNested
# recurses and produces a report OF ITS OWN. Before the fold this phase pins,
# only Created and Dropped came back from that recursion and the other eleven
# arrays were discarded -- a remainder found inside a part never reached the
# caller at all.
$PartUnitBody = @'
unit PartUnit;

interface

uses
  Classes;

type
  TOldCol = class(TComponent)
  private
    FWidth: Integer;
  published
    property Width: Integer read FWidth write FWidth;
  end;

  TNewCol = class(TComponent)
  private
    FWidth: Integer;
  published
    property Width: Integer read FWidth write FWidth;
  end;

implementation

end.
'@

$PartFormBody = @'
unit PartForm;

interface

uses
  Classes, OldEditUnit, PartUnit;

type
  TPartForm = class(TForm)
    Edit1: TOldEdit;
  end;

implementation

{$R *.dfm}

end.
'@

# Col1 is an owned part of Edit1 and carries Width = 5. The part-level
# #default Width = 99 is therefore SUPERSEDED by the part-level #link, and the
# part-level #apply matches nothing (the mapping tests for 999, not 5).
# Both remainders are discovered INSIDE the part.
$PartFormDfm = @'
object PartForm: TPartForm
  object Edit1: TOldEdit
    Caption = 'Hi'
    object Col1: TOldCol
      Width = 5
    end
  end
end
'@

$PartRulesBody = @'
#convert TOldEdit -> TNewEdit, NewEditUnit
#link Text <- Caption
#convert TOldCol -> TNewCol, PartUnit
#link Width <- Width
#default Width = 99
#mapping ColMap from PartUnit.TColEnum to PartUnit.TNewCol
#mapping ColMap #when Width = '999' -> Width = '1'
#apply ColMap
'@
$partRulesPath = Join-Path $WorkDir 'rules-part.txt'
Write-Ascii $partRulesPath $PartRulesBody

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
$phase4 = Join-Path $WorkDir 'phase4-castskip'
$phase6 = Join-Path $WorkDir 'phase6-mapping'
$phase7 = Join-Path $WorkDir 'phase7-default'
$phase8 = Join-Path $WorkDir 'phase8-resolved'
$phase9 = Join-Path $WorkDir 'phase9-ownedpart'
New-Fixture $phase1
New-Fixture $phase2
New-Fixture $phase3
New-Fixture $phase4
New-Fixture $phase6
New-Fixture $phase7
New-Fixture $phase8
New-Item -ItemType Directory $phase9 -Force | Out-Null
Write-Ascii (Join-Path $phase9 'OldEditUnit.pas') $OldEditBody
Write-Ascii (Join-Path $phase9 'NewEditUnit.pas') $NewEditBody
Write-Ascii (Join-Path $phase9 'PartUnit.pas')    $PartUnitBody
Write-Ascii (Join-Path $phase9 'PartForm.pas')    $PartFormBody
Write-Ascii (Join-Path $phase9 'PartForm.dfm')    $PartFormDfm
$castBeforeBytes = [System.IO.File]::ReadAllBytes((Join-Path $phase4 'MyForm.pas'))

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

# A1: ALL SIX report surfaces must be printed. CreatorSites and ReemitNotes were
# computed by BuildApplyPlan and then silently DISCARDED by both copies of the
# print block -- 4 refs each for Converted/AccessSites/Todos/Warnings, 0 for
# these two -- so the engine wrote "verify the creator manually" into a void.
# Both headings are absent from the pre-A1 build, which is what makes these RED.
Check 'dry-run output has a CreatorSites: block' ($applyRaw -match 'CreatorSites:') "raw=$applyRaw"
$creatorBlockMatch = [regex]::Match($applyRaw, 'CreatorSites:([\s\S]*?)(\r?\n\r?\n|\z)')
$creatorBlock = if ($creatorBlockMatch.Success) { $creatorBlockMatch.Groups[1].Value } else { '' }
Check 'CreatorSites block names the retyped ctor TOldEdit.Create -> TNewEdit.Create' `
  ($creatorBlock -match 'TOldEdit\.Create\s*->\s*TNewEdit\.Create') "block=$creatorBlock"

# ReemitNotes carries the DFM re-emit's per-instance notes.
#
# This block used to be proved non-empty by the F/T default-divergence note,
# which fired on EVERY conversion whose root types differ -- as these do
# (TOldEdit -> TNewEdit). D2/D4 NARROWED that note to the one case that is
# genuinely unknown: a rule-referenced source absent from the DFM with no
# `default` clause to resolve it to. This fixture streams every source its
# rules name, so the note is now correctly SILENT, and asserting it still fires
# would be asserting the old contract.
#
# The block is still non-empty on its own merits: the moved-depth #link
# synthesises Style/Active/Font and each creation is reported. Pinning that
# instead is strictly stronger -- it names real content rather than a warning
# that fired regardless.
Check 'dry-run output has a ReemitNotes: block' ($applyRaw -match 'ReemitNotes:') "raw=$applyRaw"
$reemitBlockMatch = [regex]::Match($applyRaw, 'ReemitNotes:([\s\S]*?)(\r?\n\r?\n|\z)')
$reemitBlock = if ($reemitBlockMatch.Success) { $reemitBlockMatch.Groups[1].Value } else { '' }
Check 'ReemitNotes block reports the synthesized intermediates' `
  ($reemitBlock -match 'created Style') "block=$reemitBlock"
Check 'the blanket divergence note is silent when every source resolved' `
  (-not ($reemitBlock -match 'defaults may diverge')) "block=$reemitBlock"

# Blocks are blank-line separated so a 'Heading:(...)(blank|end)' slice returns
# THAT block only. Without the separator every such slice ran to end-of-output,
# so e.g. the 'AccessSites block does NOT mention Other' assertion above was
# really checking the whole tail. Pin the separator so it cannot regress.
Check 'report blocks are blank-line separated' ($applyRaw -match '\r?\n\r?\nCreatorSites:') "raw=$applyRaw"

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

# ===========================================================================
# PHASE 4: a #link carrying a ': Cast' is SKIPPED on the .pas side, and warns.
#
# This is the guard commit 7acbe6c recorded as OWED ("NOT covered by a guard
# yet: the convert-apply skip-and-warn path").
#
# Why the skip exists: surface #4 rewrites a member IDENTIFIER at each access
# site ('obj.Caption' -> 'obj.Text'). A rule carrying ': Round' says the VALUE
# also needs converting, and convert-apply cannot do that. Before the FromPath
# cast split landed, ': Round' was swallowed into FromPath, matched no member,
# and nothing was rewritten by accident. Making the path resolve correctly
# therefore OPENED the hazard of renaming a property while silently dropping
# the value conversion -- source that compiles and is numerically wrong. The
# skip-and-warn is what keeps that closed, so it needs a guard of its own.
#
# POSITIVE CONTROL: Phase 1 runs this SAME fixture with a cast-free rule book
# and asserts >= 2 replace-to-Text edits. So 'exactly 0 here' cannot be passing
# because the access-site surface is dead -- Phase 1 proves it is alive. The
# two phases differ only by the ': Round' suffix on one rule line.
#
# Its own dir + own rules file: Phases 1-3 assert byte-exact things about their
# fixtures ('delete lines 2..8', exactly one TODO), so they must not be touched.
# ===========================================================================
Write-Host ''
Write-Host '=== Phase 4: #link with a cast is skipped on the .pas side ===' -ForegroundColor Cyan

Push-Location $phase4
try {
  $castRaw = (& $Exe convert-apply --unit 'MyForm.pas' --rules $castRulesPath --db $db 2>&1) -join "`n"
  $castExit = $LASTEXITCODE
} finally { Pop-Location }
Write-Host $castRaw -ForegroundColor DarkGray

# A skipped rule is NOT a failure: the rest of the conversion still applies.
Check 'cast: dry-run exits 0' ($castExit -eq 0) "exit=$castExit"

Check 'cast: warns that the link was SKIPPED on the .pas side' `
  ($castRaw -match 'SKIPPED on the \.pas side') "raw=$castRaw"

# The warning must NAME the rule, its line and its cast -- a bare "skipped"
# leaves the operator with nothing to act on, which is the defect this warning
# exists to prevent.
$warnBlockMatch = [regex]::Match($castRaw, 'Warnings:([\s\S]*?)(\r?\n\r?\n|\z)')
$warnBlock = if ($warnBlockMatch.Success) { $warnBlockMatch.Groups[1].Value } else { '' }
Check 'cast: warning names the cast (Round)' ($warnBlock -match 'Round') "block=$warnBlock"
Check 'cast: warning names the rule (Text <- Caption)' `
  ($warnBlock -match 'Text\s*<-\s*Caption') "block=$warnBlock"
Check 'cast: warning names the rule line number' ($warnBlock -match 'line \d+') "block=$warnBlock"

# The whole point: NO access site was rewritten to Text. Phase 1's '>= 2' on the
# identical fixture is the control that makes this 0 meaningful.
$castTextReplaceCount = ([regex]::Matches($castRaw, '->\s*"Text"')).Count
Check 'cast: ZERO replace-to-Text edits (rename refused, not half-applied)' `
  ($castTextReplaceCount -eq 0) "count=$castTextReplaceCount; raw=$castRaw"

# The cast only disables THIS link's .pas rewrite. The instance itself must
# still convert, or the skip would have quietly cost the whole conversion.
Check 'cast: the instance is still converted (Edit1 TOldEdit -> TNewEdit)' `
  ($castRaw -match 'Edit1:\s*TOldEdit\s*->\s*TNewEdit') "raw=$castRaw"

# Dry-run: nothing written.
$castAfter = [System.IO.File]::ReadAllBytes((Join-Path $phase4 'MyForm.pas'))
$castUnchanged = ($castBeforeBytes.Length -eq $castAfter.Length) -and
                 (-not (Compare-Object $castBeforeBytes $castAfter -SyncWindow 0))
Check 'cast: MyForm.pas byte-unchanged after dry-run' $castUnchanged `
  "before=$($castBeforeBytes.Length)B after=$($castAfter.Length)B"

# ===========================================================================
# PHASE 5: --format json emits schema apply/1.
#
# The point of the schema is that a consumer can DISPATCH on a conversion's
# remainder instead of parsing it out of prose. So the assertions below are
# about structure, not wording: the document parses at all, the six report
# arrays are present, items[] mirrors them exactly, and a known item carries
# the right kind and the right anchor.
#
# 2>$null is load-bearing: the engine writes a '(loaded defaults from ...)'
# note to stderr, and merging it into stdout would make ConvertFrom-Json throw.
# ===========================================================================
Write-Host ''
Write-Host '=== Phase 5: --format json (schema apply/1) ===' -ForegroundColor Cyan

Push-Location $phase1
try {
  $jsonRaw = (& $Exe convert-apply --unit 'MyForm.pas' --rules $rulesPath --db $db --format json 2>$null) -join "`n"
  $jsonExit = $LASTEXITCODE
} finally { Pop-Location }
Check 'json: exits 0' ($jsonExit -eq 0) "exit=$jsonExit"

# Parses AT ALL. This is the assertion that RenderDryRun and every summary
# Writeln are suppressed under --format json -- one stray line and this throws.
$doc = $null
try { $doc = $jsonRaw | ConvertFrom-Json } catch { $doc = $null }
Check 'json: output parses as JSON (no stray text on stdout)' ($null -ne $doc) `
  "raw=$($jsonRaw.Substring(0, [Math]::Min(300, $jsonRaw.Length)))"

if ($null -ne $doc) {
  Check 'json: schema is apply/1' ($doc.schema -eq 'apply/1') "schema=$($doc.schema)"
  Check 'json: mode is dry-run' ($doc.mode -eq 'dry-run') "mode=$($doc.mode)"
  Check 'json: ok is true' ($doc.ok -eq $true) "ok=$($doc.ok)"
  Check 'json: freshness.fresh is true' ($doc.freshness.fresh -eq $true) "fresh=$($doc.freshness.fresh)"
  Check 'json: edits_count is positive' ($doc.edits_count -gt 0) "edits_count=$($doc.edits_count)"

  # All six report surfaces are present as keys, including the two that the
  # pre-A1 text output dropped entirely.
  $six = @('converted','access_sites','creator_sites','todos','reemit_notes','warnings')
  $missing = $six | Where-Object { -not ($doc.PSObject.Properties.Name -contains $_) }
  Check 'json: all six report arrays present' ($missing.Count -eq 0) "missing=$($missing -join ',')"

  # THE INVARIANT: one item per reported line, across all six arrays.
  $sum = 0
  foreach ($k in $six) { $sum += @($doc.$k).Count }
  Check 'json: items.Count equals the sum of the six arrays' (@($doc.items).Count -eq $sum) `
    "items=$(@($doc.items).Count) sum=$sum"

  # No item may carry an unnamed kind -- KindStr-style '?' leakage would make
  # the whole vocabulary undispatchable while still looking populated.
  $badKind = @($doc.items) | Where-Object { [string]::IsNullOrWhiteSpace($_.kind) -or $_.kind -eq '?' }
  Check 'json: every item has a real kind (no blank, no "?")' ($badKind.Count -eq 0) `
    "bad=$($badKind.Count)"
  $badField = @($doc.items) | Where-Object { $_.field -notin $six }
  Check 'json: every item field names one of the six arrays' ($badField.Count -eq 0) `
    "bad=$(($badField | ForEach-Object { $_.field }) -join ',')"

  # A known item, checked against the fixture rather than a hardcoded number:
  # the verify-creator TODO must anchor at the real 'TOldEdit.Create' line.
  $formLines = Get-Content (Join-Path $phase1 'MyForm.pas')
  $ctorLine = 0
  for ($i = 0; $i -lt $formLines.Count; $i++) {
    if ($formLines[$i] -match 'TOldEdit\.Create') { $ctorLine = $i + 1; break }
  }
  Check 'json: fixture has a TOldEdit.Create line to anchor against' ($ctorLine -gt 0) "line=$ctorLine"
  $cv = @($doc.items) | Where-Object { $_.kind -eq 'creator-verify' }
  Check 'json: exactly one creator-verify item' ($cv.Count -eq 1) "count=$($cv.Count)"
  if ($cv.Count -eq 1) {
    Check 'json: creator-verify item names instance Edit1' ($cv[0].instance -eq 'Edit1') "instance=$($cv[0].instance)"
    Check 'json: creator-verify item carries from_type TOldEdit' ($cv[0].from_type -eq 'TOldEdit') "from_type=$($cv[0].from_type)"
    Check 'json: creator-verify item carries to_type TNewEdit' ($cv[0].to_type -eq 'TNewEdit') "to_type=$($cv[0].to_type)"
    Check 'json: creator-verify item anchors at the TOldEdit.Create line' ($cv[0].line -eq $ctorLine) `
      "item=$($cv[0].line) fixture=$ctorLine"
    Check 'json: creator-verify item is reported in the todos field' ($cv[0].field -eq 'todos') "field=$($cv[0].field)"
  }

  # The REMAINDER is the todos/reemit_notes/warnings subset -- the definition
  # the converter side consumes. Pin that it is non-empty for this fixture.
  $remainder = @($doc.items) | Where-Object { $_.field -in @('todos','reemit_notes','warnings') }
  Check 'json: remainder subset is non-empty for this fixture' ($remainder.Count -gt 0) `
    "count=$($remainder.Count)"
}
else {
  # The 19 assertions above are guarded by the parse succeeding. Without this
  # branch a broken document would SKIP them silently and report a single
  # failure, which reads like one small problem instead of "nothing was
  # checked". Make the skip loud.
  Check 'json: 19 structural assertions were SKIPPED (document did not parse)' $false `
    'fix the parse failure above -- until it parses, nothing below it is verified'
}

# The cast skip (Phase 4) must ALSO surface as a typed item, not only as prose.
Push-Location $phase4
try {
  $castJsonRaw = (& $Exe convert-apply --unit 'MyForm.pas' --rules $castRulesPath --db $db --format json 2>$null) -join "`n"
} finally { Pop-Location }
$castDoc = $null
try { $castDoc = $castJsonRaw | ConvertFrom-Json } catch { $castDoc = $null }
Check 'json: cast run parses as JSON' ($null -ne $castDoc) `
  "raw=$($castJsonRaw.Substring(0, [Math]::Min(300, $castJsonRaw.Length)))"
if ($null -ne $castDoc) {
  $cna = @($castDoc.items) | Where-Object { $_.kind -eq 'cast-not-applied' }
  Check 'json: cast skip surfaces as a cast-not-applied item' ($cna.Count -eq 1) "count=$($cna.Count)"
  if ($cna.Count -eq 1) {
    Check 'json: cast-not-applied is reported in the warnings field' ($cna[0].field -eq 'warnings') "field=$($cna[0].field)"
    Check 'json: cast-not-applied carries the rules-file line number' ($cna[0].rule_line -gt 0) `
      "rule_line=$($cna[0].rule_line)"
  }
}
else {
  Check 'json: cast-run assertions were SKIPPED (document did not parse)' $false `
    'fix the parse failure above'
}

# ===========================================================================
# PHASE 6: an #apply that matches nothing is REMAINDER, typed and reported.
#
# The engine used to RECOGNISE AND SKIP #mapping/#apply, emitting no rule at
# all -- so a rule book asking for a mapping got a clean exit 0 and no mapping,
# silently. That is the defect this phase pins: not that mapping works, but
# that a mapping which does NOT apply is REPORTED rather than swallowed.
# ===========================================================================
Write-Host ''
Write-Host '=== Phase 6: #apply that matches nothing (mapping-not-applied) ===' -ForegroundColor Cyan

Push-Location $phase6
try {
  $mapRaw  = (& $Exe convert-apply --unit 'MyForm.pas' --rules $mapRulesPath --db $db 2>&1) -join "`n"
  $mapExit = $LASTEXITCODE
  $mapJson = (& $Exe convert-apply --unit 'MyForm.pas' --rules $mapRulesPath --db $db --format json 2>$null) -join "`n"
} finally { Pop-Location }
Write-Host $mapRaw -ForegroundColor DarkGray

Check 'mapping: dry-run exits 0' ($mapExit -eq 0) "exit=$mapExit"

# TEXT surface: the Warnings block must name the mapping, or a human reading
# the default output never learns the mapping did nothing.
$mapWarnMatch = [regex]::Match($mapRaw, 'Warnings:([\s\S]*?)(\r?\n\r?\n|\z)')
$mapWarn = if ($mapWarnMatch.Success) { $mapWarnMatch.Groups[1].Value } else { '' }
Check 'mapping: Warnings block names the mapping (CapMap)' ($mapWarn -match 'CapMap') "block=$mapWarn"

# TYPED surface.
$mapDoc = $null
try { $mapDoc = $mapJson | ConvertFrom-Json } catch { $mapDoc = $null }
Check 'mapping: json parses' ($null -ne $mapDoc) `
  "raw=$($mapJson.Substring(0, [Math]::Min(200, $mapJson.Length)))"
if ($null -ne $mapDoc) {
  $mna = @($mapDoc.items) | Where-Object { $_.kind -eq 'mapping-not-applied' }
  Check 'mapping: a mapping-not-applied item is emitted' ($mna.Count -ge 1) "count=$($mna.Count)"
  if ($mna.Count -ge 1) {
    Check 'mapping: item is reported in the warnings field' ($mna[0].field -eq 'warnings') `
      "field=$($mna[0].field)"
    # rule_line must be the #apply line (4 in $MapRulesBody), not the mapping's
    # own line -- the #apply is what requested the work that did not happen.
    Check 'mapping: item rule_line is the #apply line (4)' ($mna[0].rule_line -eq 4) `
      "rule_line=$($mna[0].rule_line)"
    Check 'mapping: item names the source path (Caption)' ($mna[0].path -eq 'Caption') `
      "path=$($mna[0].path)"
  }
  # The invariant must still hold once a new kind joins the vocabulary.
  $six6 = @('converted','access_sites','creator_sites','todos','reemit_notes','warnings')
  $sum6 = 0
  foreach ($k in $six6) { $sum6 += @($mapDoc.$k).Count }
  Check 'mapping: items.Count still equals the sum of the six arrays' `
    (@($mapDoc.items).Count -eq $sum6) "items=$(@($mapDoc.items).Count) sum=$sum6"
}
else {
  Check 'mapping: typed assertions were SKIPPED (document did not parse)' $false `
    'fix the parse failure above'
}

# ===========================================================================
# PHASE 7: a #default on a path a #link already carries does NOT fire, and the
# skipped rule is reported (default-superseded).
#
# #default is documented on both sides as a FALLBACK -- "set a target property
# when NO SOURCE MAPS". The engine tested neither claim: it wrote
# unconditionally AFTER the leaf loop, so #default beat every #link and the
# form's real value vanished with exit 0 and no warning. This phase pins BOTH
# halves -- the source value survives, AND the dead rule is surfaced through
# the typed apply/1 item rather than only inside convert-reemit's own report.
# ===========================================================================
Write-Host ''
Write-Host '=== Phase 7: #default superseded by a #link (default-superseded) ===' -ForegroundColor Cyan

Push-Location $phase7
try {
  $defRaw  = (& $Exe convert-apply --unit 'MyForm.pas' --rules $defRulesPath --db $db 2>&1) -join "`n"
  $defExit = $LASTEXITCODE
  $defJson = (& $Exe convert-apply --unit 'MyForm.pas' --rules $defRulesPath --db $db --format json 2>$null) -join "`n"
} finally { Pop-Location }
Write-Host $defRaw -ForegroundColor DarkGray

Check 'default: dry-run exits 0' ($defExit -eq 0) "exit=$defExit"

# TEXT surface: a human reading the default output must learn the #default was
# ignored, or the rule book keeps a line that silently does nothing.
$defWarnMatch = [regex]::Match($defRaw, 'Warnings:([\s\S]*?)(\r?\n\r?\n|\z)')
$defWarn = if ($defWarnMatch.Success) { $defWarnMatch.Groups[1].Value } else { '' }
Check 'default: Warnings block reports the ignored #default' `
  ($defWarn -match 'did not fire') "block=$defWarn"

$defDoc = $null
try { $defDoc = $defJson | ConvertFrom-Json } catch { $defDoc = $null }
Check 'default: json parses' ($null -ne $defDoc) `
  "raw=$($defJson.Substring(0, [Math]::Min(200, $defJson.Length)))"
if ($null -ne $defDoc) {
  $dsu = @($defDoc.items) | Where-Object { $_.kind -eq 'default-superseded' }
  Check 'default: a default-superseded item is emitted' ($dsu.Count -ge 1) "count=$($dsu.Count)"
  if ($dsu.Count -ge 1) {
    Check 'default: item is reported in the warnings field' ($dsu[0].field -eq 'warnings') `
      "field=$($dsu[0].field)"
    # rule_line is the #default line (3 in $DefRulesBody) -- the line to delete.
    Check 'default: item rule_line is the #default line (3)' ($dsu[0].rule_line -eq 3) `
      "rule_line=$($dsu[0].rule_line)"
    Check 'default: item names the target path (Text)' ($dsu[0].path -eq 'Text') `
      "path=$($dsu[0].path)"
    Check 'default: item text names BOTH the ignored value and the winner' `
      ($dsu[0].text -match 'Zzz' -and $dsu[0].text -match 'Hi') "text=$($dsu[0].text)"
  }
  # The source value must actually survive into the re-emitted block. This is
  # the half that matters to the operator: reporting the skip is no use if the
  # value was clobbered anyway.
  #
  # Scope the search to the .dfm edit plan ONLY. The whole-output search that
  # stood here first was unsound in the "must NOT appear" direction: the new
  # warning line itself reads "#default Text = 'Zzz' did not fire", so a
  # correct engine failed its own assertion. A negative assertion has to be
  # scoped to the surface it is actually about.
  $dfmMatch = [regex]::Match($defRaw, "(?m)^File: MyForm\.dfm\r?\n([\s\S]*?)^File: ")
  $dfmTxt = if ($dfmMatch.Success) { $dfmMatch.Groups[1].Value } else { '' }
  Check 'default: the .dfm edit plan was located' ($dfmTxt -ne '') "raw=$defRaw"
  Check 'default: the SOURCE value reaches the T block' ($dfmTxt -match "Text = 'Hi'") `
    "dfm=$dfmTxt"
  Check 'default: the #default value is NOT written into the T block' `
    (-not ($dfmTxt -match 'Zzz')) "dfm=$dfmTxt"

  $six7 = @('converted','access_sites','creator_sites','todos','reemit_notes','warnings')
  $sum7 = 0
  foreach ($k in $six7) { $sum7 += @($defDoc.$k).Count }
  Check 'default: items.Count still equals the sum of the six arrays' `
    (@($defDoc.items).Count -eq $sum7) "items=$(@($defDoc.items).Count) sum=$sum7"
}
else {
  Check 'default: typed assertions were SKIPPED (document did not parse)' $false `
    'fix the parse failure above'
}

# ===========================================================================
# PHASE 8: a source absent BECAUSE it sits at its declared default is carried
# across explicitly, and reported as `default-resolved`.
#
# This is the apply/1 surface for the sparse-DFM work. Phase 7 covers the kind
# next to it (`default-superseded`), but nothing exercised THIS one: the item
# loop in Convert.Apply could have been deleted entirely and every assertion in
# this runner would still have passed. Computed-then-discarded is the exact
# shape session 68's A1 was about, so it gets its own end-to-end check.
#
# Hint is the control that keeps the claim honest: absent with NO default
# clause, so it must NOT be carried, and must instead be NAMED by the narrowed
# divergence note.
# ===========================================================================
Write-Host ''
Write-Host '=== Phase 8: absent-because-default is carried (default-resolved) ===' -ForegroundColor Cyan

Push-Location $phase8
try {
  $resRaw  = (& $Exe convert-apply --unit 'MyForm.pas' --rules $resolvedRulesPath --db $db 2>&1) -join "`n"
  $resExit = $LASTEXITCODE
  $resJson = (& $Exe convert-apply --unit 'MyForm.pas' --rules $resolvedRulesPath --db $db --format json 2>$null) -join "`n"
} finally { Pop-Location }
Write-Host $resRaw -ForegroundColor DarkGray

Check 'resolved: dry-run exits 0' ($resExit -eq 0) "exit=$resExit"

$resDoc = $null
try { $resDoc = $resJson | ConvertFrom-Json } catch { $resDoc = $null }
Check 'resolved: json parses' ($null -ne $resDoc) `
  "raw=$($resJson.Substring(0, [Math]::Min(200, $resJson.Length)))"
if ($null -ne $resDoc) {
  $dr = @($resDoc.items) | Where-Object { $_.kind -eq 'default-resolved' }
  Check 'resolved: a default-resolved item is emitted' ($dr.Count -eq 1) "count=$($dr.Count)"
  if ($dr.Count -ge 1) {
    Check 'resolved: it is informational (reemit_notes, not warnings)' `
      ($dr[0].field -eq 'reemit_notes') "field=$($dr[0].field)"
    Check 'resolved: it names the SOURCE property (Enabled)' ($dr[0].path -eq 'Enabled') `
      "path=$($dr[0].path)"
    # rule_line is the #link that carried it -- line 3 of $ResolvedRulesBody.
    Check 'resolved: rule_line is the #link that carried it (3)' ($dr[0].rule_line -eq 3) `
      "rule_line=$($dr[0].rule_line)"
    Check 'resolved: the text names the resolved value and both paths' `
      ($dr[0].text -match 'True' -and $dr[0].text -match 'Enabled2') "text=$($dr[0].text)"
  }

  # The value must actually land in the .dfm plan. Reporting it is no use if
  # nothing was written -- and TNewEdit.Enabled2 defaults to False, so an absent
  # property here would silently mean the opposite of what the form said.
  $dfmM = [regex]::Match($resRaw, "(?m)^File: MyForm\.dfm\r?\n([\s\S]*?)^File: ")
  $dfmB = if ($dfmM.Success) { $dfmM.Groups[1].Value } else { '' }
  Check 'resolved: the .dfm edit plan was located' ($dfmB -ne '') "raw=$resRaw"
  Check 'resolved: F''s resolved default is written explicitly (Enabled2 = True)' `
    ($dfmB -match 'Enabled2\s*=\s*True') "dfm=$dfmB"

  # CONTROL: Hint has no default clause, so it is genuinely unknown.
  Check 'resolved: CONTROL -- a source with no default clause is NOT carried' `
    (-not ($dfmB -match 'Hint2')) "dfm=$dfmB"
  $dv = @($resDoc.items) | Where-Object { $_.kind -eq 'defaults-may-diverge' }
  Check 'resolved: CONTROL -- the narrowed divergence note fires and NAMES it' `
    ($dv.Count -ge 1 -and ($dv[0].text -match 'Hint')) `
    "count=$($dv.Count) text=$($dv[0].text)"

  $six8 = @('converted','access_sites','creator_sites','todos','reemit_notes','warnings')
  $sum8 = 0
  foreach ($k in $six8) { $sum8 += @($resDoc.$k).Count }
  Check 'resolved: items.Count still equals the sum of the six arrays' `
    (@($resDoc.items).Count -eq $sum8) "items=$(@($resDoc.items).Count) sum=$sum8"
}
else {
  Check 'resolved: typed assertions were SKIPPED (document did not parse)' $false `
    'fix the parse failure above'
}

Write-Host ''

# ===========================================================================
# PHASE 9: remainders found inside an OWNED PART reach apply/1 -- exactly once.
#
# WHY THIS PHASE EXISTS, and what it refutes.
#
# INBOX-nested-part-report-is-mostly-discarded observes, correctly, that
# HandleNested (Convert.DfmReemit.pas) folds only 2 of TReemitReport's 13
# arrays up from a converted owned part. It concludes that remainders found
# inside a part are DISCARDED and never reach the caller. Measured 2026-09-06,
# that conclusion does not hold for apply/1, and this phase pins why.
#
# BuildApplyPlan iterates the instances discovered in the .dfm, and an owned
# part carrying its own #convert IS one of them -- it does not need a .pas
# field declaration to be found (this fixture's Col1 has none, and is still
# converted; the "could not locate field declaration" warning is that half
# reporting itself). So the part's report reaches apply/1 through the instance
# loop, under the part's OWN name, whether or not HandleNested folds anything.
#
# The fold was implemented and measured before being reverted. It did not add
# the missing items -- they were already there -- it added a SECOND copy of
# each under the parent's name with a 'Col1.' prefix, so one remainder was
# reported twice under two different path conventions. That is the ambiguity
# the note wants removed, not a fix for it.
#
# What genuinely IS lost is the convert-reemit verb's own report, which calls
# ReemitComponent directly with no instance loop above it. Which surface should
# own part remainders is a design question that changes a contract the
# converter team consumes, so it is theirs and the owner's, not a drive-by.
#
# THE DUPLICATE ASSERTION BELOW IS THE POINT. It goes RED the moment anyone
# re-applies the fold: with it, each kind's count was 2 rather than 1.
# ===========================================================================
Write-Host ''
Write-Host '=== Phase 9: owned-part remainders reach apply/1 exactly once ===' -ForegroundColor Cyan

Push-Location $phase9
try {
  $partRaw  = (& $Exe convert-apply --unit 'PartForm.pas' --rules $partRulesPath --db $db 2>&1) -join "`n"
  $partExit = $LASTEXITCODE
  $partJson = (& $Exe convert-apply --unit 'PartForm.pas' --rules $partRulesPath --db $db --format json 2>$null) -join "`n"
} finally { Pop-Location }
Write-Host $partRaw -ForegroundColor DarkGray

Check 'part: dry-run exits 0' ($partExit -eq 0) "exit=$partExit"

$partDoc = $null
try { $partDoc = $partJson | ConvertFrom-Json } catch { $partDoc = $null }
Check 'part: json parses' ($null -ne $partDoc) `
  "raw=$($partJson.Substring(0, [Math]::Min(300, $partJson.Length)))"

if ($null -ne $partDoc) {
  # --- the #default superseded INSIDE the part reaches apply/1 --------------
  $pdsu = @($partDoc.items) | Where-Object { $_.kind -eq 'default-superseded' }
  Check 'part: the part''s superseded #default reaches apply/1' `
    ($pdsu.Count -ge 1) "count=$($pdsu.Count)"
  Check 'part: it is reported EXACTLY ONCE (re-applying the HandleNested fold makes this 2)' `
    ($pdsu.Count -eq 1) "count=$($pdsu.Count) -- a second copy means the same remainder is being reported twice under two path conventions"
  if ($pdsu.Count -ge 1) {
    # The path is the part-LOCAL leaf, because the item comes from converting
    # the part as its own instance. Pinned as the current convention so a change
    # to it is a deliberate act rather than a silent one.
    Check 'part: its path is the part-local leaf (Width), the part being its own instance' `
      ($pdsu[0].path -eq 'Width') "path=$($pdsu[0].path)"
  }

  # --- the #apply that matched nothing INSIDE the part ----------------------
  $pna = @($partDoc.items) | Where-Object { $_.kind -eq 'mapping-not-applied' }
  Check 'part: the part''s unmatched #apply reaches apply/1' `
    ($pna.Count -ge 1) "count=$($pna.Count)"
  Check 'part: it too is reported EXACTLY ONCE' `
    ($pna.Count -eq 1) "count=$($pna.Count)"

  # --- CONTROL: the part really is nested, not a form field -----------------
  # If Col1 were declared in PartForm.pas this phase would prove nothing about
  # nested parts -- it would just be a second ordinary instance. The fixture's
  # own warning is the evidence, and it is asserted rather than assumed.
  Check 'part CONTROL: Col1 is NOT declared in the .pas, so it is genuinely a nested part' `
    ($partRaw -match 'could not locate field declaration "Col1: TOldCol"') `
    'the fixture must not quietly acquire a Col1 field declaration'

  # --- CONTROL: the six-array invariant still reconciles --------------------
  $six9 = @('converted','access_sites','creator_sites','todos','reemit_notes','warnings')
  $sum9 = 0
  foreach ($k in $six9) { $sum9 += @($partDoc.$k).Count }
  Check 'part: items.Count still equals the sum of the six arrays' `
    (@($partDoc.items).Count -eq $sum9) "items=$(@($partDoc.items).Count) sum=$sum9"
}
else {
  Check 'part: typed assertions were SKIPPED (document did not parse)' $false `
    'fix the parse failure above'
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
