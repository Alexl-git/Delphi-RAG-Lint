<#
  run_convert_apply_unlinked.ps1 -- row 6 steps 2/3 (2026-09-16): the UNLINKED
  source-property warning and count on convert-apply.

  WHAT IS PINNED
  --------------
  A source property that some converted instance carries in its .dfm block,
  that no #link carries and no #ignore acknowledges, is:

    * COUNTED once per (SOURCE TYPE, property) -- their refinement (a). Two
      source types both dropping 'Style' are TWO rows. Keyed by property name
      alone they would collapse into one and a rule-book gap would vanish the
      moment a book grew a second #convert block.
    * PRINTED as a FRACTION of that type's converted instances, '1 of 3',
      never a bare 'x1' -- their refinement (b). A minority site count is the
      STRONGER signal (the two ParentFont=False buttons somebody deliberately
      styled), and a bare multiplier reads as "rare" and invites a skim.
    * WARNED by default (step 3: the number earned it -- 2 distinct / 22 sites
      on a real 36-link book, and their own test was "2 is a warning, 200 is a
      report"), and SILENCED by --no-warn-unlinked WITHOUT losing the count.
    * NOT counted when #ignore acknowledges it -- the DSL already has the
      opt-out, so the warning must point at it honestly.

  FIXTURE: two source types (TOldEdit x3 instances, TOldBtn x2), both with a
  'Style' the book does not link. Edit1 carries Style, Edit3 carries Hint,
  Btn1 and Btn2 both carry Style. So the truth is:

      TOldBtn.Style   2 of 2
      TOldEdit.Hint   1 of 3
      TOldEdit.Style  1 of 3          -> 3 rows, 4 sites

  and with '#ignore Hint' in the TOldEdit block: 2 rows, 3 sites.

  POSITIVE CONTROL: the step-1 engine (json integers keyed by property NAME,
  no warning, no unlinked[]) reports unlinked_source_properties = 2 here, not
  3 -- so this runner is red against it. That is the shape that proves the
  key changed; a fixture with one source type could not tell.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-convert-apply-unlinked).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-apply-unlinked"
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

$OldUnit = @'
unit OldUnit;

interface

uses
  Classes;

type
  TOldEdit = class(TComponent)
  private
    FCaption: string;
    FStyle: Integer;
    FHint: string;
  published
    property Caption: string read FCaption write FCaption;
    property Style: Integer read FStyle write FStyle;
    property Hint: string read FHint write FHint;
  end;

  TOldBtn = class(TComponent)
  private
    FCaption: string;
    FStyle: Integer;
  published
    property Caption: string read FCaption write FCaption;
    property Style: Integer read FStyle write FStyle;
  end;

implementation

end.
'@

$NewUnit = @'
unit NewUnit;

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

  TNewBtn = class(TComponent)
  private
    FText: string;
  published
    property Text: string read FText write FText;
  end;

implementation

end.
'@

$FormPas = @'
unit UForm;

interface

uses
  Classes, OldUnit;

type
  TUForm = class(TForm)
    Edit1: TOldEdit;
    Edit2: TOldEdit;
    Edit3: TOldEdit;
    Btn1: TOldBtn;
    Btn2: TOldBtn;
  end;

implementation

{$R *.dfm}

end.
'@

$FormDfm = @'
object UForm: TUForm
  object Edit1: TOldEdit
    Caption = 'One'
    Style = 7
  end
  object Edit2: TOldEdit
    Caption = 'Two'
  end
  object Edit3: TOldEdit
    Caption = 'Three'
    Hint = 'h'
  end
  object Btn1: TOldBtn
    Caption = 'B1'
    Style = 1
  end
  object Btn2: TOldBtn
    Caption = 'B2'
    Style = 2
  end
end
'@

$Rules = @'
#convert TOldEdit -> TNewEdit, NewUnit
#link Text <- Caption
#convert TOldBtn -> TNewBtn, NewUnit
#link Text <- Caption
'@

# Same book plus an #ignore that acknowledges TOldEdit.Hint.
$RulesIgnore = @'
#convert TOldEdit -> TNewEdit, NewUnit
#link Text <- Caption
#ignore Hint
#convert TOldBtn -> TNewBtn, NewUnit
#link Text <- Caption
'@

$fix = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $fix | Out-Null
Write-Ascii (Join-Path $fix 'OldUnit.pas') $OldUnit
Write-Ascii (Join-Path $fix 'NewUnit.pas') $NewUnit
Write-Ascii (Join-Path $fix 'UForm.pas')   $FormPas
Write-Ascii (Join-Path $fix 'UForm.dfm')   $FormDfm
$rulesPath  = Join-Path $WorkDir 'rules.txt';        Write-Ascii $rulesPath  $Rules
$ignorePath = Join-Path $WorkDir 'rules-ignore.txt'; Write-Ascii $ignorePath $RulesIgnore

$db = Join-Path $WorkDir 'unlinked.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $fix --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) ($indexOut -join ' | ')

function Invoke-Apply([string[]]$extra, [string]$rules) {
  Push-Location $fix
  try {
    # stdout only: the engine's stale-index note is stderr and would interleave
    # INTO a json document (RESUME-ENGINE-2026-09-16-session98 gotcha).
    $raw = (& $Exe convert-apply --unit 'UForm.pas' --rules $rules --db $db @extra 2>$null) -join "`n"
    return @{ Raw = $raw; Exit = $LASTEXITCODE }
  } finally { Pop-Location }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 1. text, default: warned once per (source type, property), as a fraction ===' -ForegroundColor Cyan
$t = Invoke-Apply @() $rulesPath
Check 'dry-run exits 0' ($t.Exit -eq 0) "exit=$($t.Exit)"
Write-Host $t.Raw -ForegroundColor DarkGray
$warnBlock = [regex]::Match($t.Raw, '(?m)^Warnings:([\s\S]*?)(\r?\n\r?\n|\z)').Groups[1].Value
Check 'a Warnings: block is printed' ($warnBlock -ne '') "raw=$($t.Raw)"
Check 'TOldBtn.Style is 2 of 2'  ($warnBlock -match 'TOldBtn\.Style: .*dropped on 2 of 2 converted instance')  "block=$warnBlock"
Check 'TOldEdit.Style is 1 of 3' ($warnBlock -match 'TOldEdit\.Style: .*dropped on 1 of 3 converted instance') "block=$warnBlock"
Check 'TOldEdit.Hint is 1 of 3'  ($warnBlock -match 'TOldEdit\.Hint: .*dropped on 1 of 3 converted instance')  "block=$warnBlock"
$styleLines = @([regex]::Matches($warnBlock, '(?m)^\s*\S+\.Style: no #link')).Count
Check 'Style is TWO rows (one per source type), not one' ($styleLines -eq 2) "rows=$styleLines"
Check 'the warning names #ignore as the way to accept the drop' ($warnBlock -match '#ignore Style') "block=$warnBlock"
Check 'no bare multiplier (x2) anywhere' (-not ($t.Raw -match '\bx\d+\b')) "raw=$($t.Raw)"
# Ordering is by (source type, property), so TOldBtn precedes TOldEdit and
# Hint precedes Style -- stable across runs, independent of .dfm order.
$order = [regex]::Matches($warnBlock, '(?m)^\s*(T\w+\.\w+): no #link') | ForEach-Object { $_.Groups[1].Value }
Check 'rows are sorted by source type then property' (($order -join ',') -eq 'TOldBtn.Style,TOldEdit.Hint,TOldEdit.Style') "order=$($order -join ',')"

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 2. json: counts keyed by (source type, property) + unlinked[] ===' -ForegroundColor Cyan
$j = Invoke-Apply @('--format', 'json') $rulesPath
Check 'json exits 0' ($j.Exit -eq 0) "exit=$($j.Exit)"
$doc = $null
try { $doc = $j.Raw | ConvertFrom-Json } catch { }
Check 'json parses' ($null -ne $doc) "raw=$($j.Raw)"
if ($null -ne $doc) {
  Check 'unlinked_source_properties = 3 (rows, keyed by source type + property; step 1 said 2)' ($doc.unlinked_source_properties -eq 3) "got=$($doc.unlinked_source_properties)"
  Check 'unlinked_source_property_sites = 4' ($doc.unlinked_source_property_sites -eq 4) "got=$($doc.unlinked_source_property_sites)"
  Check 'unlinked[] has 3 rows' (@($doc.unlinked).Count -eq 3) "got=$(@($doc.unlinked).Count)"
  $btn = @($doc.unlinked | Where-Object { $_.from_type -eq 'TOldBtn' -and $_.path -eq 'Style' })
  Check 'unlinked[TOldBtn.Style] sites=2 instances=2' ($btn.Count -eq 1 -and $btn[0].sites -eq 2 -and $btn[0].instances -eq 2) "row=$($btn | ConvertTo-Json -Compress)"
  $edt = @($doc.unlinked | Where-Object { $_.from_type -eq 'TOldEdit' -and $_.path -eq 'Style' })
  Check 'unlinked[TOldEdit.Style] sites=1 instances=3' ($edt.Count -eq 1 -and $edt[0].sites -eq 1 -and $edt[0].instances -eq 3) "row=$($edt | ConvertTo-Json -Compress)"
  $kinds = @($doc.items | Where-Object { $_.kind -eq 'unlinked-source-property' })
  Check 'items[] carries kind unlinked-source-property x3, field warnings' ($kinds.Count -eq 3 -and (@($kinds | Where-Object { $_.field -eq 'warnings' }).Count -eq 3)) "n=$($kinds.Count)"
  Check 'each such item carries from_type and path structurally' (@($kinds | Where-Object { $_.from_type -ne '' -and $_.path -ne '' }).Count -eq 3) ($kinds | ConvertTo-Json -Compress)
  # Invariant 1 survives: items = sum of the six arrays (unlinked[] is OUTSIDE it).
  $sum = @($doc.converted).Count + @($doc.access_sites).Count + @($doc.creator_sites).Count + @($doc.todos).Count + @($doc.reemit_notes).Count + @($doc.warnings).Count
  Check 'items.length = sum of the six arrays' (@($doc.items).Count -eq $sum) "items=$(@($doc.items).Count) sum=$sum"
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 3. --no-warn-unlinked: no warning, count kept ===' -ForegroundColor Cyan
$q = Invoke-Apply @('--no-warn-unlinked') $rulesPath
Check 'quiet dry-run exits 0' ($q.Exit -eq 0) "exit=$($q.Exit)"
Check 'no unlinked warning line in text' (-not ($q.Raw -match 'no #link carries it')) "raw=$($q.Raw)"
$qj = Invoke-Apply @('--no-warn-unlinked', '--format', 'json') $rulesPath
$qdoc = $null
try { $qdoc = $qj.Raw | ConvertFrom-Json } catch { }
Check 'quiet json parses' ($null -ne $qdoc) "raw=$($qj.Raw)"
if ($null -ne $qdoc) {
  Check 'quiet json still counts 3 rows / 4 sites' ($qdoc.unlinked_source_properties -eq 3 -and $qdoc.unlinked_source_property_sites -eq 4) "got=$($qdoc.unlinked_source_properties)/$($qdoc.unlinked_source_property_sites)"
  Check 'quiet json still carries unlinked[] x3' (@($qdoc.unlinked).Count -eq 3) "got=$(@($qdoc.unlinked).Count)"
  Check 'quiet json has NO unlinked-source-property item' (@($qdoc.items | Where-Object { $_.kind -eq 'unlinked-source-property' }).Count -eq 0) ''
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 4. #ignore acknowledges a drop: it leaves the count ===' -ForegroundColor Cyan
$g = Invoke-Apply @('--format', 'json') $ignorePath
$gdoc = $null
try { $gdoc = $g.Raw | ConvertFrom-Json } catch { }
Check 'ignore json parses' ($null -ne $gdoc) "raw=$($g.Raw)"
if ($null -ne $gdoc) {
  Check '#ignore Hint: 2 rows / 3 sites' ($gdoc.unlinked_source_properties -eq 2 -and $gdoc.unlinked_source_property_sites -eq 3) "got=$($gdoc.unlinked_source_properties)/$($gdoc.unlinked_source_property_sites)"
  Check '#ignore Hint: no TOldEdit.Hint row' (@($gdoc.unlinked | Where-Object { $_.path -eq 'Hint' }).Count -eq 0) ($gdoc.unlinked | ConvertTo-Json -Compress)
  Check '#ignore Hint: the two Style rows survive (positive control)' (@($gdoc.unlinked | Where-Object { $_.path -eq 'Style' }).Count -eq 2) ($gdoc.unlinked | ConvertTo-Json -Compress)
}

Write-Host ''
if ($script:Failed) { Write-Host 'run_convert_apply_unlinked: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_convert_apply_unlinked: PASS' -ForegroundColor Green
exit 0
