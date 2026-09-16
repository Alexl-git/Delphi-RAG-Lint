<#
  run_convert_apply_link_carry.ps1 -- row 6 (2026-09-16): TYPE-IDENTITY sub-leaf
  carry under a class-typed #link.

  THE RULE (converter team, taken verbatim):
    A #link dst <- src between class-typed properties carries the source's
    sub-leaves automatically WHEN the two property types are identical. When
    the types differ, it carries nothing implicitly and every dotted leaf must
    be named.

  Plus their two implementation details:
    * an EXPLICIT leaf rule always WINS over a carried one;
    * a carried leaf is VISIBLE in --format json, distinguishable from an
      explicitly linked one (kind 'sub-leaf-carried', path = the leaf).

  FIXTURE: TOldBtn and TNewBtn both declare Font: TFontX (IDENTICAL), and
  Glyph: TPicX vs Glyph: TGlyphY (DIFFERENT, each with a Kind leaf). The .dfm
  streams the sub-leaves the way the VCL does -- DOTTED lines, not nested
  object blocks:

      Font.Name = 'Tahoma'     <- carried (nobody typed it)
      Font.Size = 9            <- EXPLICIT #link Font.Size <- Font.Size: wins, not "carried"
      Font.Color = 5           <- EXPLICIT #ignore Font.Color: wins, Ignored
      Glyph.Kind = 1           <- under #link Glyph <- Glyph, types differ: DROPPED

  POSITIVE CONTROL: against the pre-carry engine Font.Name is DROPPED, so the
  first section is red there. A fixture with only the identity case could not
  tell "carries everything" from "carries on identity" -- Glyph is what pins
  the boundary.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-convert-apply-link-carry).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-apply-link-carry"
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
  Classes, SharedUnit;

type
  TPicX = class(TPersistent)
  private
    FKind: Integer;
  published
    property Kind: Integer read FKind write FKind;
  end;

  TOldBtn = class(TComponent)
  private
    FCaption: string;
    FFont: TFontX;
    FGlyph: TPicX;
  published
    property Caption: string read FCaption write FCaption;
    property Font: TFontX read FFont write FFont;
    property Glyph: TPicX read FGlyph write FGlyph;
  end;

implementation

end.
'@

$SharedUnit = @'
unit SharedUnit;

interface

uses
  Classes;

type
  TFontX = class(TPersistent)
  private
    FName: string;
    FSize: Integer;
    FColor: Integer;
  published
    property Name: string read FName write FName;
    property Size: Integer read FSize write FSize;
    property Color: Integer read FColor write FColor;
  end;

implementation

end.
'@

$NewUnit = @'
unit NewUnit;

interface

uses
  Classes, SharedUnit;

type
  TGlyphY = class(TPersistent)
  private
    FKind: Integer;
  published
    property Kind: Integer read FKind write FKind;
  end;

  TNewBtn = class(TComponent)
  private
    FText: string;
    FFont: TFontX;
    FGlyph: TGlyphY;
  published
    property Text: string read FText write FText;
    property Font: TFontX read FFont write FFont;
    property Glyph: TGlyphY read FGlyph write FGlyph;
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
    Btn1: TOldBtn;
  end;

implementation

{$R *.dfm}

end.
'@

$FormDfm = @'
object UForm: TUForm
  object Btn1: TOldBtn
    Caption = 'A'
    Font.Name = 'Tahoma'
    Font.Size = 9
    Font.Color = 5
    Glyph.Kind = 1
  end
end
'@

# Line numbers matter: the carried leaf must cite line 2 (the parent #link).
$Rules = @'
#convert TOldBtn -> TNewBtn, NewUnit
#link Font <- Font
#link Text <- Caption
#link Font.Size <- Font.Size
#ignore Font.Color
#link Glyph <- Glyph
'@

$fix = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $fix | Out-Null
Write-Ascii (Join-Path $fix 'SharedUnit.pas') $SharedUnit
Write-Ascii (Join-Path $fix 'OldUnit.pas')    $OldUnit
Write-Ascii (Join-Path $fix 'NewUnit.pas')    $NewUnit
Write-Ascii (Join-Path $fix 'UForm.pas')      $FormPas
Write-Ascii (Join-Path $fix 'UForm.dfm')      $FormDfm
$rulesPath = Join-Path $WorkDir 'rules.txt'; Write-Ascii $rulesPath $Rules

$db = Join-Path $WorkDir 'carry.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $fix --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) ($indexOut -join ' | ')

function Invoke-Apply([string[]]$extra) {
  Push-Location $fix
  try {
    $raw = (& $Exe convert-apply --unit 'UForm.pas' --rules $rulesPath --db $db @extra 2>$null) -join "`n"
    return @{ Raw = $raw; Exit = $LASTEXITCODE }
  } finally { Pop-Location }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 1. text: the identity leaf is carried, the boundary leaf is not ===' -ForegroundColor Cyan
$t = Invoke-Apply @()
Check 'dry-run exits 0' ($t.Exit -eq 0) "exit=$($t.Exit)"
Write-Host $t.Raw -ForegroundColor DarkGray
Check 'Font.Name is carried into the T block (nobody typed it)' ($t.Raw -match "Font\.Name\s*=\s*'Tahoma'") "raw=$($t.Raw)"
Check 'Font.Size lands too (explicit leaf link)' ($t.Raw -match 'Font\.Size\s*=\s*9') "raw=$($t.Raw)"
Check 'Font.Color does NOT land (explicit #ignore wins over the carry)' (-not ($t.Raw -match 'Font\.Color')) "raw=$($t.Raw)"
Check 'Glyph.Kind does NOT land (TPicX <> TGlyphY: different types carry nothing)' (-not ($t.Raw -match 'Glyph\.Kind\s*=')) "raw=$($t.Raw)"
$rn = [regex]::Match($t.Raw, '(?m)^ReemitNotes:([\s\S]*?)(\r?\n\r?\n|\z)').Groups[1].Value
Check 'ReemitNotes says Font.Name was carried, citing the parent #link line 2 and TFontX' ($rn -match 'carried Font\.Name -> Font\.Name .*line 2.*TFontX') "block=$rn"
Check 'ReemitNotes does NOT call Font.Size carried (explicit is not implicit)' (-not ($rn -match 'carried Font\.Size')) "block=$rn"
Check 'ReemitNotes reports Glyph.Kind DROPPED' ($rn -match 'dropped Glyph\.Kind') "block=$rn"
Check 'no Font leaf is reported dropped' (-not ($rn -match 'dropped Font\.')) "block=$rn"
Check 'no Font.Name in the unlinked warning' (-not ($t.Raw -match 'TOldBtn\.Font\.Name: no #link')) "raw=$($t.Raw)"
Check 'the unlinked warning names TOldBtn.Glyph.Kind' ($t.Raw -match 'TOldBtn\.Glyph\.Kind: no #link') "raw=$($t.Raw)"
# Font and Glyph are class-typed CONTAINERS (never streamed as leaves) and
# Font.Size is streamed as a DOTTED leaf; before 2026-09-16 all three were listed
# as 'absent from the F DFM' by step 4b, which read only nested-object shapes.
Check 'no defaults-may-diverge note (containers and dotted leaves are not absent)' (-not ($t.Raw -match 'defaults may diverge')) "raw=$($t.Raw)"

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 2. json: a carried leaf is machine-distinguishable ===' -ForegroundColor Cyan
$j = Invoke-Apply @('--format', 'json')
$doc = $null
try { $doc = $j.Raw | ConvertFrom-Json } catch { }
Check 'json parses' ($null -ne $doc) "raw=$($j.Raw)"
if ($null -ne $doc) {
  $carried = @($doc.items | Where-Object { $_.kind -eq 'sub-leaf-carried' })
  Check 'exactly ONE sub-leaf-carried item' ($carried.Count -eq 1) "n=$($carried.Count)"
  if ($carried.Count -eq 1) {
    Check 'its path is Font.Name (structured, not parsed from prose)' ($carried[0].path -eq 'Font.Name') "path=$($carried[0].path)"
    Check 'its rule_line is 2 (the parent #link)' ($carried[0].rule_line -eq 2) "rule_line=$($carried[0].rule_line)"
    Check 'its field is reemit_notes (info, not remainder)' ($carried[0].field -eq 'reemit_notes') "field=$($carried[0].field)"
  }
  $dropped = @($doc.items | Where-Object { $_.kind -eq 'unmapped-property' } | ForEach-Object { $_.path })
  Check 'unmapped-property items are exactly [Glyph.Kind]' (($dropped -join ',') -eq 'Glyph.Kind') "dropped=$($dropped -join ',')"
  $sum = @($doc.converted).Count + @($doc.access_sites).Count + @($doc.creator_sites).Count + @($doc.todos).Count + @($doc.reemit_notes).Count + @($doc.warnings).Count
  Check 'items.length = sum of the six arrays' (@($doc.items).Count -eq $sum) "items=$(@($doc.items).Count) sum=$sum"
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 3. convert-reemit json carries the same, as carried[] ===' -ForegroundColor Cyan
$blockPath = Join-Path $WorkDir 'block.dfm'
Write-Ascii $blockPath @'
object Btn1: TOldBtn
  Caption = 'A'
  Font.Name = 'Tahoma'
  Font.Size = 9
  Font.Color = 5
  Glyph.Kind = 1
end
'@
# convert-reemit takes QUALIFIED type names (a bare name resolves to an EMPTY tree,
# and the identity gate then correctly carries nothing -- TreesDescribeThisBlock).
$rr = (& $Exe convert-reemit --from OldUnit.TOldBtn --to NewUnit.TNewBtn --rules $rulesPath --from-block $blockPath --db $db 2>$null) -join "`n"
$rdoc = $null
try { $rdoc = $rr | ConvertFrom-Json } catch { }
Check 'convert-reemit json parses' ($null -ne $rdoc) "raw=$rr"
if ($null -ne $rdoc) {
  $c = @($rdoc.report.carried | Where-Object { $null -ne $_ })
  Check 'report.carried has one entry' ($c.Count -eq 1) ($rdoc.report | ConvertTo-Json -Compress -Depth 4)
  if ($c.Count -eq 1) {
    Check 'carried[0] = {Font.Name -> Font.Name, ruleLine 2, type TFontX}' ($c[0].fromPath -eq 'Font.Name' -and $c[0].toPath -eq 'Font.Name' -and $c[0].ruleLine -eq 2 -and $c[0].type -eq 'TFontX') ($c[0] | ConvertTo-Json -Compress)
  }
  Check 'report.dropped = [Glyph.Kind]' ((@($rdoc.report.dropped) -join ',') -eq 'Glyph.Kind') (@($rdoc.report.dropped) -join ',')
  Check 'report.ignored = [Font.Color]' ((@($rdoc.report.ignored) -join ',') -eq 'Font.Color') (@($rdoc.report.ignored) -join ',')
  Check 'emitted dfm has Font.Name = ''Tahoma'' as a DOTTED line (no classless object block)' ($rdoc.dfm -match "(?m)^\s*Font\.Name = 'Tahoma'" -and -not ($rdoc.dfm -match '(?m)^\s*object Font\s*$')) "dfm=$($rdoc.dfm)"
}

Write-Host ''
if ($script:Failed) { Write-Host 'run_convert_apply_link_carry: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_convert_apply_link_carry: PASS' -ForegroundColor Green
exit 0
