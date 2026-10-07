<#
  run_convert_apply_glyph_framing.ps1 --
  A graphic carried by `dfm keep-bytes-if-compatible` must be TRANSFORMED between
  the two properties' FILER formats, never copied (1.26.2).

  THE DEFECT (converter team, measured on 1.25.2, ORM3 CLIENT\VARINSP): twenty
  TabcToggleBtn -> TcxButton conversions carried `Picture.Data` to
  `OptionsImage.Glyph.Data` BYTE-IDENTICAL. Every file parsed, DfmLoadCheck was
  green, and every glyph raised `EdxException: Unsupported image format.` the
  moment it was read -- because the bytes still held TPicture's own framing:

      07 'TBitmap'  76080000  424D...
      ^^ class name ^^^^^^^^  the BMP file starts HERE
         (TPicture.WriteData) (TBitmap.WriteData: Int32 size)

  TdxSmartGlyph does not override TGraphic.ReadData, so its Data is the bare
  image file (TGraphic.ReadData -> LoadFromStream). Stripping exactly those 12
  bytes made the button decode 128x32, NumGlyphs=4, as the original.

  WHAT THIS PROVES, AND HOW:
    * the hand-built TPicture payloads ARE what the VCL reader reads -- the
      ORIGINAL .dfm is decoded first (D0); without it every later assertion
      could be measuring a fixture the VCL would reject too;
    * the converted .dfm parses (DfmLoadCheck) AND decodes (GlyphDecodeCheck:
      the real TdxSmartGlyph reads Width/Height) with the original's size;
    * POSITIVE CONTROL: the 1.25.2 shape -- the wrapped bytes put back -- FAILS
      the same decode, so the decode check is capable of failing;
    * a payload that cannot be unwrapped (an unknown graphic class, a size that
      does not match) or whose image the cast does not accept (ico) is REPORTED
      per instance and NOT written;
    * a cast whose target filer format is unknown (no `dfmdata`, a yields class
      the engine has no framing for) refuses to carry, and says what to declare.

  Run from any CWD, pwsh 7. Builds its own fixture and castlib.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_glyph_framing_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
. (Join-Path $PSScriptRoot 'lib\DfmLoadCheck.ps1')
. (Join-Path $PSScriptRoot 'lib\GlyphDecodeCheck.ps1')

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$libA = Join-Path $WorkDir 'libA'; $libB = Join-Path $WorkDir 'libB'; $app = Join-Path $WorkDir 'app'
foreach ($d in @($libA,$libB,$app)) { New-Item -ItemType Directory $d -Force | Out-Null }

Check 'V0 the decode checker builds (RAD Studio + DevExpress dcus)' (Test-GlyphDecodeChecker) `
      'without it nothing below can tell a loadable glyph from a corrupt one'

# ---- the images: real files, made by GDI+ ----------------------------------
Add-Type -AssemblyName System.Drawing
function ImageBytes([int]$W, [int]$H, [System.Drawing.Imaging.ImageFormat]$Fmt) {
  $bmp = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  try {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.Clear([System.Drawing.Color]::Teal); $g.FillRectangle([System.Drawing.Brushes]::Yellow, 2, 2, [int]($W / 2), [int]($H / 2)) }
    finally { $g.Dispose() }
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, $Fmt)
    return ,$ms.ToArray()
  } finally { $bmp.Dispose() }
}
$bmpFile = ImageBytes 64 16 ([System.Drawing.Imaging.ImageFormat]::Bmp)
$pngFile = ImageBytes 48 16 ([System.Drawing.Imaging.ImageFormat]::Png)
# A Vista-style .ico holding the PNG: ICONDIR + one ICONDIRENTRY + the image.
$icoFile = [byte[]](@(0,0,1,0,1,0, 48,16,0,0, 1,0,32,0) + [BitConverter]::GetBytes([int]$pngFile.Length) + [BitConverter]::GetBytes([int]22) + $pngFile)

function Int32([int]$v) { return [BitConverter]::GetBytes($v) }
function Wrapped([string]$Cls, [byte[]]$Inner) {
  return [byte[]](@([byte]$Cls.Length) + [Text.Encoding]::ASCII.GetBytes($Cls) + $Inner)
}
# TPicture.WriteData: one length byte, the graphic's class name, then the
# graphic's OWN WriteData -- [Int32 size][file] for TBitmap, the bare file for
# TPngImage / TIcon (Vcl.Graphics, Vcl.Imaging.pngimage: no WriteData override).
$picBmp  = Wrapped 'TBitmap'   ([byte[]]((Int32 $bmpFile.Length) + $bmpFile))
$picPng  = Wrapped 'TPngImage' $pngFile
$picIco  = Wrapped 'TIcon'     $icoFile
$picFoo  = Wrapped 'TFooImage' $pngFile
$picBad  = Wrapped 'TBitmap'   ([byte[]]((Int32 ($bmpFile.Length + 5)) + $bmpFile))

function Hex([byte[]]$B) { return (($B | ForEach-Object { $_.ToString('X2') }) -join '') }
function DfmHex([byte[]]$B, [string]$Indent) {
  $h = Hex $B
  $lines = for ($i = 0; $i -lt $h.Length; $i += 64) { $Indent + $h.Substring($i, [Math]::Min(64, $h.Length - $i)) }
  return "{`r`n" + ($lines -join "`r`n") + '}'
}

Write-Ascii (Join-Path $libA 'LibA.pas') @'
unit LibA;

interface

uses
  Classes, Graphics;

type
  TGlyphSrcBtn = class(TComponent)
  private
    FPicture: TPicture;
    FNumGlyphs: Integer;
    FCaption: string;
  published
    property Picture: TPicture read FPicture write FPicture;
    property NumGlyphs: Integer read FNumGlyphs write FNumGlyphs default 1;
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $libB 'LibB.pas') @'
unit LibB;

interface

uses
  Classes, dxGDIPlusClasses;

type
  TGlyphDstOpts = class(TPersistent)
  private
    FGlyph: TdxSmartGlyph;
    FNumGlyphs: Integer;
  published
    property Glyph: TdxSmartGlyph read FGlyph write FGlyph;
    property NumGlyphs: Integer read FNumGlyphs write FNumGlyphs default 1;
  end;

  TGlyphDstBtn = class(TComponent)
  private
    FOptionsImage: TGlyphDstOpts;
    FCaption: string;
  published
    property OptionsImage: TGlyphDstOpts read FOptionsImage write FOptionsImage;
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $app 'GlyphForm.pas') @'
unit GlyphForm;

interface

uses
  Classes, LibA;

type
  TGlyphForm = class(TDataModule)
    btnBmp: TGlyphSrcBtn;
    btnPng: TGlyphSrcBtn;
    btnIco: TGlyphSrcBtn;
    btnFoo: TGlyphSrcBtn;
    btnBad: TGlyphSrcBtn;
  end;

implementation

{$R *.dfm}

end.
'@

$ind = '      '
$dfmText = "object GlyphForm: TGlyphForm`r`n" +
  "  object btnBmp: TGlyphSrcBtn`r`n    Caption = 'bmp'`r`n    NumGlyphs = 4`r`n    Picture.Data = " + (DfmHex $picBmp $ind) + "`r`n  end`r`n" +
  "  object btnPng: TGlyphSrcBtn`r`n    Caption = 'png'`r`n    Picture.Data = " + (DfmHex $picPng $ind) + "`r`n  end`r`n" +
  "  object btnIco: TGlyphSrcBtn`r`n    Caption = 'ico'`r`n    Picture.Data = " + (DfmHex $picIco $ind) + "`r`n  end`r`n" +
  "  object btnFoo: TGlyphSrcBtn`r`n    Caption = 'foo'`r`n    Picture.Data = " + (DfmHex $picFoo $ind) + "`r`n  end`r`n" +
  "  object btnBad: TGlyphSrcBtn`r`n    Caption = 'bad'`r`n    Picture.Data = " + (DfmHex $picBad $ind) + "`r`n  end`r`n" +
  "end`r`n"
Write-Ascii (Join-Path $app 'GlyphForm.dfm') $dfmText

$castDecl = Join-Path $WorkDir 'declared.castlib'
Write-Ascii $castDecl @'
# fixture cast library -- strict 7-bit ASCII, CRLF
cast AssignGraphic
  accepts TPicture
  yields  TdxSmartGlyph
  dfm     keep-bytes-if-compatible
  dfmdata graphic
  compat  png, bmp
  pas     '{dst}.Assign({src});'
  todo    'transfer the image from {src} by hand'
end
'@
# The same cast WITHOUT dfmdata: TdxSmartGlyph is a DevExpress class whose
# filer format the engine does not claim to know, so it must refuse to carry.
$castBare = Join-Path $WorkDir 'bare.castlib'
Write-Ascii $castBare ((Get-Content $castDecl -Raw) -replace '(?m)^\s*dfmdata.*\r?\n', '')

$rules = Join-Path $WorkDir 'g.rules'
Write-Ascii $rules @'
#convert TGlyphSrcBtn -> TGlyphDstBtn, LibB
#link Caption <- Caption
#link OptionsImage.Glyph <- Picture : AssignGraphic
#link OptionsImage.NumGlyphs <- NumGlyphs
'@

$dbA = Join-Path $WorkDir 'dbA.sqlite'; $dbB = Join-Path $WorkDir 'dbB.sqlite'; $dbApp = Join-Path $WorkDir 'dbApp.sqlite'
& $Exe index $libA --db $dbA   2>&1 | Out-Null
& $Exe index $libB --db $dbB   2>&1 | Out-Null
& $Exe index $app  --db $dbApp 2>&1 | Out-Null
Check 'V1 the three fixture indexes were built' ((Test-Path $dbA) -and (Test-Path $dbB) -and (Test-Path $dbApp))

# ---- D0: the ORIGINAL payloads are what the VCL reader reads ----------------
$orig = Invoke-GlyphDecode @((Join-Path $app 'GlyphForm.dfm'))
Check 'D0 POSITIVE CONTROL the hand-built TPicture payloads decode in the VCL (bmp 64x16, png 48x16)' `
      ((@($orig) -contains 'PIC GlyphForm.dfm btnBmp w=64 h=16') -and (@($orig) -contains 'PIC GlyphForm.dfm btnPng w=48 h=16')) `
      ("the fixture is not a real TPicture stream, so nothing below proves anything:`n" + ($orig -join "`n"))

function ApplyRun([string]$Dir, [string]$Db, [string]$Castlib, [string[]]$Extra) {
  Push-Location $Dir
  try { $raw = (& $Exe convert-apply --unit 'GlyphForm.pas' --rules $rules --castlib $Castlib --db $Db --db $dbA --db $dbB @Extra 2>&1) -join "`n"; $ec = $LASTEXITCODE }
  finally { Pop-Location }
  $line = ($raw -split "`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1)
  $j = $null; if ($line) { try { $j = $line | ConvertFrom-Json } catch { } }
  return @{ Raw = $raw; J = $j; Exit = $ec }
}

# ---- the dry run: what is carried, what is refused, and why ----------------
$dry = ApplyRun $app $dbApp $castDecl @('--format','json')
$notes = (@($dry.J.reemit_notes) + @($dry.J.warnings) + @($dry.J.todos)) -join ' || '
Check 'P1 the fixture converts all five instances' (($dry.J -ne $null) -and ($dry.J.converted.Count -eq 5)) $dry.Raw
Check 'P2 the bmp and png payloads are carried to the target' `
      (($notes -match '(?i)btnBmp[^|]*created OptionsImage\.Glyph') -and ($notes -match '(?i)btnPng[^|]*created OptionsImage\.Glyph')) $notes
Check 'P3 an ico payload is REFUSED -- ico is not in the compat list -- with the cast todo' `
      (($notes -match '(?i)btnIco[^|]*mismatched Picture\.Data[^|]*\bico\b') -and ($notes -match '(?i)btnIco[^|]*transfer the image')) $notes
Check 'P4 an UNKNOWN graphic class in the TPicture wrapper is reported by name, not carried' `
      (($notes -match '(?i)btnFoo[^|]*mismatched Picture\.Data[^|]*TFooImage') -and -not ($notes -match '(?i)btnFoo[^|]*created OptionsImage\.Glyph')) $notes
Check 'P5 a TBitmap size field that does not match its bytes is reported, not carried' `
      (($notes -match '(?i)btnBad[^|]*mismatched Picture\.Data[^|]*size') -and -not ($notes -match '(?i)btnBad[^|]*created OptionsImage\.Glyph')) $notes

# ---- N1: no dfmdata and a yields class the engine has no framing for --------
$bare = ApplyRun $app $dbApp $castBare @('--format','json')
$notesBare = (@($bare.J.reemit_notes) + @($bare.J.warnings) + @($bare.J.todos)) -join ' || '
Check 'N1 an unknown TARGET filer format refuses to carry and names the dfmdata key' `
      (($notesBare -match '(?i)btnBmp[^|]*mismatched Picture\.Data[^|]*dfmdata') -and -not ($notesBare -match '(?i)btnBmp[^|]*created OptionsImage\.Glyph')) $notesBare

# ---- W: the write path, on a COPY ------------------------------------------
$appW = Join-Path $WorkDir 'appw'
New-Item -ItemType Directory $appW -Force | Out-Null
Copy-Item (Join-Path $app 'GlyphForm.pas'), (Join-Path $app 'GlyphForm.dfm') $appW -Force
$dbW = Join-Path $WorkDir 'dbW.sqlite'
& $Exe index $appW --db $dbW 2>&1 | Out-Null
$w = ApplyRun $appW $dbW $castDecl @('--apply')
$wDfm = Join-Path $appW 'GlyphForm.dfm'
$written = [IO.File]::ReadAllText($wDfm)
Check 'W0 --apply exits 0 and wrote the target type' (($w.Exit -eq 0) -and ($written -match 'TGlyphDstBtn')) $w.Raw

$loadFails = Test-DfmLoads @($wDfm)
Check 'W1 the converted .dfm parses (DfmLoadCheck)' ($loadFails.Count -eq 0) ($loadFails -join "`n")

function GlyphHexOf([string]$Text, [string]$Comp) {
  $m = [regex]::Match($Text, "(?s)object $Comp\b.*?OptionsImage\.Glyph\.Data = \{([0-9A-Fa-f\s]*)\}")
  if ($m.Success) { return ($m.Groups[1].Value -replace '\s','') } else { return '' }
}
Check 'W2 the carried bmp is the BARE file: no class name, no size field -- it starts BM' `
      ((GlyphHexOf $written 'btnBmp') -eq (Hex $bmpFile)) ("got: " + (GlyphHexOf $written 'btnBmp').Substring(0, [Math]::Min(48, (GlyphHexOf $written 'btnBmp').Length)))
Check 'W3 the carried png is the bare PNG file' ((GlyphHexOf $written 'btnPng') -eq (Hex $pngFile)) 'png payload not unwrapped'
Check 'W4 the refused payloads are written NOWHERE' `
      (((GlyphHexOf $written 'btnIco') -eq '') -and ((GlyphHexOf $written 'btnFoo') -eq '') -and ((GlyphHexOf $written 'btnBad') -eq '')) $written

$dec = Invoke-GlyphDecode @($wDfm)
Check 'W5 the converted bmp glyph DECODES in TdxSmartGlyph, original size and NumGlyphs' `
      (@($dec) -contains 'GLYPH GlyphForm.dfm btnBmp empty=False w=64 h=16 n=4') ($dec -join "`n")
Check 'W6 the converted png glyph DECODES in TdxSmartGlyph, original size' `
      (@($dec) -contains 'GLYPH GlyphForm.dfm btnPng empty=False w=48 h=16 n=1') ($dec -join "`n")
Check 'W7 no glyph on the converted form fails to decode' ((@($dec) -match '^(GLYPHFAIL|FATAL|ERR) ').Count -eq 0) ($dec -join "`n")

# ---- PC: the 1.25.2 shape FAILS the same decode -----------------------------
# Put the WRAPPED bytes back where the bare file went. If this decoded, W5 could
# not tell the defect from the fix.
$ctl = Join-Path $WorkDir 'control.dfm'
$ctlText = [regex]::Replace($written, "(?s)(object btnBmp\b.*?OptionsImage\.Glyph\.Data = )\{[0-9A-Fa-f\s]*\}",
  { param($m) $m.Groups[1].Value + (DfmHex $picBmp '      ') })
Write-Ascii $ctl $ctlText
$decCtl = Invoke-GlyphDecode @($ctl)
Check 'PC POSITIVE CONTROL the 1.25.2 wrapped bytes FAIL the decode (Unsupported image format)' `
      ((@($decCtl) -match '^GLYPHFAIL control\.dfm btnBmp .*Unsupported image format').Count -gt 0) ($decCtl -join "`n")

# ---- R: the root kind is chosen from the ROOT's own properties --------------
$rForm = Join-Path $WorkDir 'rootform.dfm'
Write-Ascii $rForm "object MainDlg: TMainDlg`r`n  ClientHeight = 100`r`n  ClientWidth = 200`r`nend`r`n"
$rDm = Join-Path $WorkDir 'rootdm.dfm'
Write-Ascii $rDm "object FrmData: TFrmData`r`n  object b: TGlyphSrcBtn`r`n    Caption = 'ClientHeight = 3'`r`n  end`r`nend`r`n"
$rk = Invoke-GlyphDecode @($rForm, $rDm)
Check 'R1 a root streaming ClientHeight/ClientWidth loads as a FORM (whatever its name)' (@($rk) -contains 'ROOT rootform.dfm TForm') ($rk -join "`n")
Check 'R2 a root named Frm* with no ClientHeight of its own loads as a DATA MODULE' (@($rk) -contains 'ROOT rootdm.dfm TDataModule') ($rk -join "`n")

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_glyph_framing_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
