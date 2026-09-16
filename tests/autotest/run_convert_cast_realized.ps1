<#
  run_convert_cast_realized.ps1 --
  ROW 6: a `#link To <- From : CastName` must be REALIZED on the .pas side, not
  refused -- and when it cannot be, it must say WHICH of the two reasons applies.

  THE DEFECT. `convert-apply` refuses every link carrying a cast:

    line 52: #link OptionsImage.Glyph <- Picture : AssignGraphic SKIPPED on the
             .pas side -- the cast is not applied by convert-apply ...

  The refusal itself was correct when written (Convert.Apply.pas:1519-1532
  explains it: renaming without converting the value would emit source that
  compiles and is WRONG, which is worse than not converting). What is missing is
  the other half -- actually performing the cast when the cast library says how.

  THREE OUTCOMES, NEVER TWO, AND NEVER SILENCE. This is the whole contract, and
  the reason this guard has a case for each:

    1. cast resolves AND has a `pas` template  -> APPLIED  (`cast-applied`)
    2. cast resolves, `pas` template is EMPTY  -> still `cast-not-applied`, but
       the message must say the cast was FOUND and carries no template, so the
       operator fixes the .castlib instead of hunting a missing rule
    3. cast name resolves to NOTHING           -> the original message

  Collapsing 2 into 3 is the trap: both currently produce the same sentence, and
  they need opposite fixes.

  WHAT THE PLAN GOT WRONG, verified before this guard was written and recorded
  here so the next reader does not re-derive it:
  * `ClassCastFor(ADefs, AFrom, ATo)` takes two TYPE names and returns a cast
    NAME. It is the editor's "is there a cast for these types" helper. Row 6
    needs the INVERSE -- name in, TCastDef out -- and no such function exists
    (`FindEnumCast` is the by-name lookup for ENUMS only).
  * The plan's acceptance command passes `--castlib convrules\casts.castlib`.
    There is no .castlib under convrules\ at all; the shipped one is
    docs\examples\convrules\casts.castlib.

  Run from any CWD, pwsh 7. Builds its own fixture and its own castlib, so it
  does not depend on the shipped rule book or on any machine index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_cast_realized"
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
  TSrcPic = class(TPersistent)
  private
    FData: string;
  published
    property Data: string read FData write FData;
  end;

  TSrcBtn = class(TPersistent)
  private
    FPicture: TSrcPic;
    FCaption: string;
  published
    property Picture: TSrcPic read FPicture write FPicture;
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
  TDstGlyph = class(TPersistent)
  private
    FData: string;
  published
    property Data: string read FData write FData;
  end;

  TDstOpts = class(TPersistent)
  private
    FGlyph: TDstGlyph;
  published
    property Glyph: TDstGlyph read FGlyph write FGlyph;
  end;

  TDstBtn = class(TPersistent)
  private
    FOptionsImage: TDstOpts;
    FCaption: string;
  published
    property OptionsImage: TDstOpts read FOptionsImage write FOptionsImage;
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
    btn1: TSrcBtn;
    procedure Setup;
  end;

implementation

{$R *.dfm}

procedure TMyForm.Setup;
begin
  btn1.Caption := 'hello';
  btn1.Picture.Data := 'seed';
end;

end.
'@

Write-Ascii (Join-Path $app 'MyForm.dfm') @'
object MyForm: TMyForm
  object btn1: TSrcBtn
    Caption = 'Hi'
    Picture.Data = 'PNGBYTES'
  end
end
'@

# The fixture's OWN cast library -- three casts covering the three outcomes.
# `NoPasTemplate` deliberately carries no `pas` line; that is outcome 2, and it
# is the case that currently cannot be told apart from outcome 3.
$castlib = Join-Path $WorkDir 'fixture.castlib'
Write-Ascii $castlib @'
# fixture cast library -- strict 7-bit ASCII, CRLF

cast AssignGraphic
  accepts TSrcPic
  yields  TDstGlyph
  dfm     keep-bytes-if-compatible
  compat  png, bmp
  pas     '{dst}.Assign({src});'
  todo    'transfer the image from {src} by hand'
end

cast NoPasTemplate
  accepts TSrcPic
  yields  TDstGlyph
  todo    'this cast deliberately has no pas template'
end
'@

function WriteRules([string]$Name, [string]$CastSuffix) {
  $p = Join-Path $WorkDir $Name
  $link = if ($CastSuffix -eq '') { '#link OptionsImage.Glyph <- Picture' }
          else { "#link OptionsImage.Glyph <- Picture : $CastSuffix" }
  Write-Ascii $p (@'
#convert TSrcBtn -> TDstBtn, LibB
#link Caption <- Caption
'@ + "`r`n" + $link + "`r`n")
  return $p
}
$rulesGood    = WriteRules 'r-good.rules'    'AssignGraphic'
$rulesNoPas   = WriteRules 'r-nopas.rules'   'NoPasTemplate'
$rulesUnknown = WriteRules 'r-unknown.rules' 'NoSuchCastAtAll'
$rulesNoCast  = WriteRules 'r-nocast.rules'  ''

$dbA   = Join-Path $WorkDir 'dbA.sqlite'
$dbB   = Join-Path $WorkDir 'dbB.sqlite'
$dbApp = Join-Path $WorkDir 'dbApp.sqlite'
& $Exe index $libA --db $dbA   2>&1 | Out-Null
& $Exe index $libB --db $dbB   2>&1 | Out-Null
& $Exe index $app  --db $dbApp 2>&1 | Out-Null
Check 'V the three fixture indexes were built' ((Test-Path $dbA) -and (Test-Path $dbB) -and (Test-Path $dbApp))

# convert-apply prints the JSON document on the FIRST line and may follow it
# with a plain-text freshness note, so the document is taken as line 1 rather
# than by parsing the whole stream.
function ApplyJson([string]$Rules) {
  Push-Location $app
  try { $raw = (& $Exe convert-apply --unit 'MyForm.pas' --rules $Rules --castlib $castlib --db $dbApp --db $dbA --db $dbB --format json 2>&1) -join "`n" }
  finally { Pop-Location }
  $line = ($raw -split "`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1)
  if (-not $line) { return @{ Raw = $raw; J = $null } }
  try { return @{ Raw = $raw; J = ($line | ConvertFrom-Json) } } catch { return @{ Raw = $raw; J = $null } }
}
function KindsOf($r) { if ($r.J -and $r.J.items) { return @($r.J.items | ForEach-Object { $_.kind }) } else { return @() } }
function TextOfKind($r,[string]$k) {
  if ($r.J -and $r.J.items) { return (@($r.J.items | Where-Object { $_.kind -eq $k } | ForEach-Object { $_.text }) -join ' || ') }
  return ''
}

# ---- P1 POSITIVE CONTROL: the fixture converts at all -----------------------
# Without this, every assertion below could be failing because the fixture never
# converts, not because the cast is unrealized.
$noCast = ApplyJson $rulesNoCast
Check 'P1 POSITIVE CONTROL the fixture converts when no cast is involved' `
      (($noCast.J -ne $null) -and ($noCast.J.converted.Count -ge 1)) `
      ("the fixture does not convert, so nothing below proves anything:`n" + $noCast.Raw)

# ---- OUTCOME 1: cast resolves AND has a pas template -> APPLIED ------------
$good = ApplyJson $rulesGood
Check 'T1 a cast with a pas template is APPLIED, not refused' `
      ((KindsOf $good) -contains 'cast-applied') `
      ("kinds: " + ((KindsOf $good) -join ', ') + "`n" + (TextOfKind $good 'cast-not-applied'))

Check 'T2 the rendered statement substitutes BOTH {dst} and {src}' `
      ((TextOfKind $good 'cast-applied') -match 'btn1\.OptionsImage\.Glyph\.Assign\(btn1\.Picture\);') `
      ("cast-applied text was: " + (TextOfKind $good 'cast-applied'))

Check 'T2b no placeholder survives into the emitted statement' `
      (-not ((TextOfKind $good 'cast-applied') -match '\{dst\}|\{src\}')) `
      ("a placeholder was emitted verbatim: " + (TextOfKind $good 'cast-applied'))

Check 'T3 the applied case does NOT also emit the refusal' `
      (-not ((KindsOf $good) -contains 'cast-not-applied')) `
      ("both outcomes emitted for one link -- the operator cannot tell what happened:`n" + (TextOfKind $good 'cast-not-applied'))

# ---- OUTCOME 2: cast resolves, NO pas template ------------------------------
$noPas = ApplyJson $rulesNoPas
Check 'T4 a cast with NO pas template is still refused' `
      ((KindsOf $noPas) -contains 'cast-not-applied') `
      ("kinds: " + ((KindsOf $noPas) -join ', '))

Check 'T4b and the message says the cast was FOUND but carries no template' `
      ((TextOfKind $noPas 'cast-not-applied') -match '(?i)no pas template|found .*no .*template|carries no') `
      ("the operator cannot tell this from an unknown cast name, and the two need OPPOSITE fixes:`n" + (TextOfKind $noPas 'cast-not-applied'))

# ---- OUTCOME 3: cast name resolves to nothing -------------------------------
$unknown = ApplyJson $rulesUnknown
Check 'T5 an UNRESOLVED cast name is refused' `
      ((KindsOf $unknown) -contains 'cast-not-applied') `
      ("kinds: " + ((KindsOf $unknown) -join ', '))

Check 'T5b DISCRIMINATION the unresolved message is NOT the no-template message' `
      (-not ((TextOfKind $unknown 'cast-not-applied') -match '(?i)no pas template|carries no')) `
      ("outcomes 2 and 3 produce the same sentence, which is the defect this guard exists to prevent:`n" + (TextOfKind $unknown 'cast-not-applied'))

Check 'T5c and it names the cast that could not be resolved' `
      ((TextOfKind $unknown 'cast-not-applied') -match 'NoSuchCastAtAll') `
      ("the operator is not told WHICH cast name failed: " + (TextOfKind $unknown 'cast-not-applied'))

# ---- T6 the schema still parses and items[] is still coherent ---------------
Check 'T6 the apply/1 document still parses with the new item kind' `
      (($good.J -ne $null) -and ($good.J.schema -eq 'apply/1')) `
      'adding an item kind broke the JSON document'

# ============================================================================
# THE .dfm HALF -- this is the one that stops data being destroyed.
#
# The converter team's report: `20 instance(s) converted, 60 edit(s) planned`
# -- a clean-looking success -- with `btnEWAcAQL: dropped Picture.Data` for
# every one of the twenty. The image bytes went nowhere and the operator had no
# reason to look.
#
# The leaf is `Picture.Data`, which is UNDER the linked `Picture` and carries no
# rule of its own, so it falls through to Dropped. `dfm keep-bytes-if-compatible`
# is the instruction to carry it to the matching path under the TARGET, and
# `compat` is the whitelist of payload formats the target will accept.
#
# NEVER RE-ENCODE, NEVER GUESS -- the converter team's own words: "rather have a
# loud could-not-carry than a silent re-encode." So an unrecognised payload must
# produce the cast's `todo`, not a best effort.
# ============================================================================

# btnPng carries a real PNG signature; btnOdd carries bytes matching nothing in
# `compat`. One fixture, both outcomes, so neither can pass by the other's path.
Write-Ascii (Join-Path $app 'TwoPic.pas') @'
unit TwoPic;

interface

uses
  Classes, LibA;

type
  TTwoForm = class(TForm)
    btnPng: TSrcBtn;
    btnOdd: TSrcBtn;
  end;

implementation

{$R *.dfm}

end.
'@

Write-Ascii (Join-Path $app 'TwoPic.dfm') @'
object TwoForm: TTwoForm
  object btnPng: TSrcBtn
    Caption = 'png'
    Picture.Data = {89504E470D0A1A0A0000000D49484452}
  end
  object btnOdd: TSrcBtn
    Caption = 'odd'
    Picture.Data = {DEADBEEFDEADBEEFDEADBEEFDEADBEEF}
  end
end
'@

& $Exe index $app --db $dbApp 2>&1 | Out-Null

function ApplyTwo([string]$Rules) {
  Push-Location $app
  try { $raw = (& $Exe convert-apply --unit 'TwoPic.pas' --rules $Rules --castlib $castlib --db $dbApp --db $dbA --db $dbB --format json 2>&1) -join "`n" }
  finally { Pop-Location }
  $line = ($raw -split "`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1)
  if (-not $line) { return @{ Raw = $raw; J = $null } }
  try { return @{ Raw = $raw; J = ($line | ConvertFrom-Json) } } catch { return @{ Raw = $raw; J = $null } }
}
$two = ApplyTwo $rulesGood
$notes2 = (($two.J.reemit_notes + $two.J.warnings + $two.J.todos) -join ' || ')

Check 'V2 POSITIVE CONTROL the two-instance fixture converts' `
      (($two.J -ne $null) -and ($two.J.converted.Count -eq 2)) `
      ("the .dfm assertions below would be measuring a failed conversion:`n" + $two.Raw)

Check 'T7 a COMPATIBLE payload is no longer reported as dropped' `
      (-not ($notes2 -match '(?i)btnPng.*dropped\s+Picture\.Data')) `
      ("the PNG payload is still being dropped -- this is the data-loss case:`n" + $notes2)

# The assertions below name the EXACT observable, not a word that might appear
# in either outcome. The first draft matched `carried`, which also matches the
# refusal's own "bytes NOT carried" -- so it passed on the failing path and
# failed on the passing one. A grep over output whose shape you have not
# inspected is a hypothesis about the shape, not a measurement.
Check 'T8 and the target sub-object path is created for it' `
      (($notes2 -match '(?i)btnPng[^|]*created OptionsImage\.Glyph') -and `
       (-not ($notes2 -match '(?i)btnPng[^|]*mismatched Picture\.Data'))) `
      ("the PNG payload did not take the carry path:`n" + $notes2)

Check 'T9 an INCOMPATIBLE payload produces the cast todo, naming the instance' `
      (($notes2 -match '(?i)btnOdd[^|]*mismatched Picture\.Data') -and ($notes2 -match '(?i)transfer the image')) `
      ("an unrecognised payload must be reported loudly, never re-encoded or silently dropped:`n" + $notes2)

Check 'T9b DISCRIMINATION the incompatible one is NOT created at the target' `
      (-not ($notes2 -match '(?i)btnOdd[^|]*created OptionsImage\.Glyph')) `
      ("the incompatible payload was carried anyway -- that is the silent re-encode the cast exists to avoid:`n" + $notes2)

Check 'T9c the todo does not leak an unsubstituted placeholder' `
      (-not ($notes2 -match '\{src\}|\{dst\}')) `
      ("a raw placeholder reached the operator:`n" + $notes2)

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
