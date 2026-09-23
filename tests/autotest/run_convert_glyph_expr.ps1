<#
  run_convert_glyph_expr.ps1 -- CV-4: the validate half of the G[I/N] glyph
  grammar (docs\superpowers\specs\2026-09-17-glyph-strip-G-grammar-design.md,
  sections 3 and 8).

  WHAT IT PINS.
    * A #link may carry a G-expression after its FromPath:
          #link OptionsImage.Glyph <- Picture G[*/4], G[1/5]G[2/5] : AssignGraphic
      The parser splits it off at the first ' G[' (FromPath stays 'Picture',
      the expression is kept VERBATIM) -- visible through --print-parsed.
    * convert-validate REJECTS a bad expression with the rule line AND the
      column inside the expression: malformed term, I > N, I < 1, N < 1, mixed
      denominators in one alternative, two alternatives for one N, two
      denominator-less alternatives, G[count] not standing alone, and G[count]
      with zero or several image links from its FromPath in its #convert block.
    * A straight carry of the source glyph count (#link X.NumGlyphs <-
      NumGlyphs) beside a G-link is a WARNING -- printed, exit code unchanged.
    * Glyph checks need no property tree, so they fire in parse-only mode (the
      mode the editor's save-validate runs in) -- most cases below pass no --db.
    * With trees, the STRIPPED FromPath is what is checked against --from.
    * convert-apply REFUSES a book carrying a G-link (the extraction/stitching
      half is CV-2's build): refusing is the only honest answer while nothing
      realises the expression, because carrying the image whole is the ruled
      "never fall back to carry-whole" violation.

  POSITIVE CONTROLS. Every negative case asserts the SPECIFIC message, and the
  valid books must stay OK -- a validator that rejected every G-expression
  would satisfy the negatives alone. The warning has a control too: the same
  straight count carry WITHOUT a G-link in its block must stay silent.

  RED, THEN GREEN (2026-09-23).
  RED against a copy of the pre-change engine (1.17.0-alpha, built 13:21:07):
  13 PASS / 25 FAIL. Parse-only mode had no glyph checks at all, so every
  negative case validated OK; the tree-backed case failed with
  'link FromPath not found in --from tree: Picture G[*/1]'; convert-apply
  refused, but through that same path error, not the CV-2 message. The 13 that
  passed are fixture setup and positive controls (valid books stay OK, the
  silent-warning controls, the plain convert-apply control, no instance
  converted) -- they fence the fix, they do not measure it.
  GREEN against the rebuilt engine: 38 PASS / 0 FAIL.

  Run from a NEUTRAL CWD, pwsh 7.
    pwsh -File tests\autotest\run_convert_glyph_expr.ps1
    pwsh -File tests\autotest\run_convert_glyph_expr.ps1 -Exe <engine>
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-glyph-expr"
)
$ErrorActionPreference = 'Stop'
# convert-validate exits 1 on a rules error, which is the EXPECTED outcome for
# most cases below; keep a native non-zero exit a value, not a terminating error.
$PSNativeCommandUseErrorActionPreference = $false

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

$script:Seq = 0
# Validate a rules body in parse-only mode; returns @{ Exit; Raw }.
function Invoke-Validate([string]$Body, [string[]]$Extra = @()) {
  $script:Seq++
  $p = Join-Path $WorkDir ("case{0:D2}.rules" -f $script:Seq)
  Write-Ascii $p $Body
  $raw = (& $Exe convert-validate --rules $p @Extra 2>&1) -join "`n"
  return @{ Exit = $LASTEXITCODE; Raw = $raw }
}

# A case that must validate clean: exit 0, 'OK', no error line, no warning.
function Expect-Ok([string]$Label, [string]$Body) {
  $r = Invoke-Validate $Body
  Check "OK: $Label" (($r.Exit -eq 0) -and ($r.Raw -match '(?m)^OK\s*$') -and
    -not ($r.Raw -match 'G-expression|warning:')) "exit=$($r.Exit) raw=$($r.Raw)"
}

# A case that must FAIL: exit 1 and the given message fragment on a 'line N:'.
function Expect-Error([string]$Label, [string]$Body, [int]$Line, [string]$Fragment) {
  $r = Invoke-Validate $Body
  $pat = '(?m)^line ' + $Line + ': .*' + [regex]::Escape($Fragment)
  Check "ERR: $Label" (($r.Exit -eq 1) -and ($r.Raw -match $pat)) "exit=$($r.Exit) raw=$($r.Raw)"
}

$hdr = "#convert Abcbtn.TabcToggleBtn -> cxButtons.TcxButton, cxButtons`n"

Write-Host '=== valid G-expressions (positive controls) ===' -ForegroundColor Cyan
Expect-Ok 'the design''s worked example (3.4)' ($hdr +
  "#link OptionsImage.Glyph     <- Picture G[*/4], G[1/5]G[2/5]G[3/5]G[4/5] : AssignGraphic`n" +
  "#link OptionsImage.NumGlyphs <- Picture G[count]`n")
Expect-Ok 'single glyph G[1/1]'            ($hdr + "#link Glyph <- Picture G[1/1]`n")
Expect-Ok 'denominator-less G[1]G[2]'      ($hdr + "#link Glyph <- Picture G[1]G[2]`n")
Expect-Ok 'whitespace between terms/commas' ($hdr + "#link Glyph <- Picture G[1/6] G[2/6] ,  G[1/2]G[2/2]`n")
Expect-Ok 're-ordered stitch G[2/2]G[1/2]' ($hdr + "#link Glyph <- Picture G[2/2]G[1/2]`n")
Expect-Ok 'one per-N form plus one denominator-less' ($hdr + "#link Glyph <- Picture G[*/4], G[1]`n")
Expect-Ok 'G[I] beside G[I/N] in one alternative, I <= N' ($hdr + "#link Glyph <- Picture G[1/4]G[2]`n")
Expect-Ok 'no G-expression at all (unchanged behaviour)' ($hdr + "#link Caption <- Caption`n")

Write-Host '=== the expression is split off FromPath, verbatim (--print-parsed) ===' -ForegroundColor Cyan
$r = Invoke-Validate ($hdr + "#link OptionsImage.Glyph <- Picture G[*/4], G[1/5]G[2/5] : AssignGraphic`n") @('--print-parsed')
Check 'print-parsed shows FromPath=Picture, the expression and the cast as separate fields' `
  ($r.Raw -match [regex]::Escape('line 2: link OptionsImage.Glyph <- Picture [glyph G[*/4], G[1/5]G[2/5]] [cast AssignGraphic]')) "raw=$($r.Raw)"

Write-Host '=== malformed terms: rejected with line AND column ===' -ForegroundColor Cyan
Expect-Error 'unterminated term'             ($hdr + "#link Glyph <- Picture G[1/4`n")        2 'column 1: unterminated term'
Expect-Error 'non-numeric slot'              ($hdr + "#link Glyph <- Picture G[a/4]`n")       2 'column 3: expected a decimal slot number'
Expect-Error 'whitespace inside G[..]'       ($hdr + "#link Glyph <- Picture G[ 1/4]`n")      2 'column 3: expected a decimal slot number'
Expect-Error 'non-numeric count'             ($hdr + "#link Glyph <- Picture G[1/x]`n")       2 'column 5: expected a decimal count'
Expect-Error 'junk after a term'             ($hdr + "#link Glyph <- Picture G[1/4]x`n")      2 'column 7: expected "G["'
Expect-Error 'trailing comma = empty alternative' ($hdr + "#link Glyph <- Picture G[1/4],`n") 2 'column 8: empty alternative'
Expect-Error 'double comma = empty alternative'   ($hdr + "#link Glyph <- Picture G[1/4],,G[1/2]`n") 2 'column 8: empty alternative'
Expect-Error 'bare star without /N'          ($hdr + "#link Glyph <- Picture G[*]`n")         2 'column 3: "*" needs a count'

Write-Host '=== range and selection errors ===' -ForegroundColor Cyan
Expect-Error 'I > N'                         ($hdr + "#link Glyph <- Picture G[5/4]`n")       2 'column 1: slot 5 exceeds its count 4'
Expect-Error 'I < 1'                         ($hdr + "#link Glyph <- Picture G[0/4]`n")       2 'column 1: slot 0 is out of range'
Expect-Error 'N < 1'                         ($hdr + "#link Glyph <- Picture G[1/0]`n")       2 'column 1: count 0 is out of range'
Expect-Error 'G[*/0]'                        ($hdr + "#link Glyph <- Picture G[*/0]`n")       2 'column 1: count 0 is out of range'
Expect-Error 'G[I] beyond the alternative''s N' ($hdr + "#link Glyph <- Picture G[1/4]G[5]`n") 2 'column 7: slot 5 exceeds its count 4'
Expect-Error 'mixed denominators'            ($hdr + "#link Glyph <- Picture G[1/4]G[2/5]`n") 2 'column 7: mixed denominators in one alternative (/4 and /5)'
Expect-Error 'two alternatives for one N'    ($hdr + "#link Glyph <- Picture G[1/4], G[*/4]`n") 2 'column 9: two alternatives for N=4'
Expect-Error 'two denominator-less alternatives' ($hdr + "#link Glyph <- Picture G[1], G[2]`n") 2 'column 7: two denominator-less alternatives'
Expect-Error 'G[count] mixed with a slot'    ($hdr + "#link Glyph <- Picture G[count]G[1/4]`n") 2 'column 1: G[count] must be the whole expression'

Write-Host '=== G[count] needs exactly one image link from its FromPath ===' -ForegroundColor Cyan
Expect-Error 'G[count] with no image link' ($hdr + "#link NumGlyphs <- Picture G[count]`n") 2 'G[count] needs exactly one image link from Picture; found 0'
Expect-Error 'G[count] with two image links' ($hdr +
  "#link Glyph <- Picture G[*/4]`n#link Glyph2 <- Picture G[1/4]`n#link NumGlyphs <- Picture G[count]`n") 4 'G[count] needs exactly one image link from Picture; found 2'
Expect-Error 'G[count] only counts its OWN #convert block' ($hdr +
  "#link Glyph <- Picture G[*/4]`n#convert A.TOther -> B.TOther`n#link NumGlyphs <- Picture G[count]`n") 4 'G[count] needs exactly one image link from Picture; found 0'
Expect-Error 'G[count] counts only the SAME FromPath' ($hdr +
  "#link Glyph <- LargePicture G[*/4]`n#link NumGlyphs <- Picture G[count]`n") 3 'G[count] needs exactly one image link from Picture; found 0'

Write-Host '=== straight count carry beside a G-link: WARNING, not error ===' -ForegroundColor Cyan
$r = Invoke-Validate ($hdr + "#link OptionsImage.Glyph <- Picture G[*/4]`n#link OptionsImage.NumGlyphs <- NumGlyphs`n")
Check 'straight count carry beside a G-link warns and still exits 0' `
  (($r.Exit -eq 0) -and ($r.Raw -match '(?m)^line 3: warning: .*straight carry of the source glyph count') -and
   ($r.Raw -match '(?m)^OK\s*$')) "exit=$($r.Exit) raw=$($r.Raw)"
$r = Invoke-Validate ($hdr + "#link OptionsImage.NumGlyphs <- NumGlyphs`n")
Check 'CONTROL: the same count carry WITHOUT a G-link is silent' `
  (($r.Exit -eq 0) -and -not ($r.Raw -match 'warning:')) "exit=$($r.Exit) raw=$($r.Raw)"
$r = Invoke-Validate ($hdr + "#link OptionsImage.Glyph <- Picture G[*/4]`n#convert A.TOther -> B.TOther`n#link NumGlyphs <- NumGlyphs`n")
Check 'CONTROL: a count carry in a DIFFERENT #convert block is silent' `
  (($r.Exit -eq 0) -and -not ($r.Raw -match 'warning:')) "exit=$($r.Exit) raw=$($r.Raw)"

# ---------------------------------------------------------------------------
# Tree-backed: the STRIPPED FromPath is what is checked, and convert-apply
# refuses a G-linked book instead of carrying the image whole.
# ---------------------------------------------------------------------------
Write-Host '=== with property trees, and convert-apply ===' -ForegroundColor Cyan
$libDir = Join-Path $WorkDir 'lib'
$appDir = Join-Path $WorkDir 'app'
New-Item -ItemType Directory $libDir, $appDir -Force | Out-Null
Write-Ascii (Join-Path $libDir 'GlyphLib.pas') @'
unit GlyphLib;

interface

uses
  Classes;

type
  TSrcBtn = class(TPersistent)
  private
    FCaption: string;
    FPicture: Integer;
  published
    property Caption: string read FCaption write FCaption;
    property Picture: Integer read FPicture write FPicture;
  end;

  TDstBtn = class(TPersistent)
  private
    FCaption: string;
    FGlyph: Integer;
  published
    property Caption: string read FCaption write FCaption;
    property Glyph: Integer read FGlyph write FGlyph;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $appDir 'MyForm.pas') @'
unit MyForm;

interface

uses
  Classes, GlyphLib;

type
  TMyForm = class(TForm)
    btn1: TSrcBtn;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (Join-Path $appDir 'MyForm.dfm') @'
object MyForm: TMyForm
  object btn1: TSrcBtn
    Caption = 'Hi'
    Picture = 1
  end
end
'@
$db = Join-Path $WorkDir 'glyph.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'index the fixture' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($idx -join ' | ')"

$gRules = Join-Path $WorkDir 'glinked.rules'
Write-Ascii $gRules "#convert GlyphLib.TSrcBtn -> GlyphLib.TDstBtn`n#link Caption <- Caption`n#link Glyph <- Picture G[*/1]`n"
$plainRules = Join-Path $WorkDir 'plain.rules'
Write-Ascii $plainRules "#convert GlyphLib.TSrcBtn -> GlyphLib.TDstBtn`n#link Caption <- Caption`n#link Glyph <- Picture`n"

$raw = (& $Exe convert-validate --rules $gRules --from GlyphLib.TSrcBtn --to GlyphLib.TDstBtn --db $db 2>&1) -join "`n"
Check 'with trees: the stripped FromPath "Picture" validates against --from' `
  (($LASTEXITCODE -eq 0) -and ($raw -match '(?m)^OK\s*$')) "exit=$LASTEXITCODE raw=$raw"

Push-Location $appDir
try {
  $raw = (& $Exe convert-apply --unit 'MyForm.pas' --rules $plainRules --db $db 2>&1) -join "`n"
  $plainExit = $LASTEXITCODE
  $rawG = (& $Exe convert-apply --unit 'MyForm.pas' --rules $gRules --db $db 2>&1) -join "`n"
  $gExit = $LASTEXITCODE
} finally { Pop-Location }
Check 'CONTROL: convert-apply converts the same book WITHOUT the G-expression' `
  (($plainExit -eq 0) -and ($raw -match [regex]::Escape('1 instance(s) converted'))) "exit=$plainExit raw=$raw"
Check 'convert-apply refuses a G-linked book (exit 1), naming the line and CV-2' `
  (($gExit -eq 1) -and ($rawG -match 'line 3: .*glyph-expression links are validated but not yet realised')) "exit=$gExit raw=$rawG"
Check '...and writes no converted instance' `
  (-not ($rawG -match 'instance\(s\) converted')) "raw=$rawG"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
