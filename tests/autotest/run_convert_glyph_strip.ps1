<#
  run_convert_glyph_strip.ps1 -- convert-apply --glyph-stitch realises a #link's
  G[I/N] expression on the .dfm surface: slices a TBitmap strip, stitches the
  chosen slots, writes the G[count] leaf after the image leaf (wave 146 g4;
  docs\superpowers\specs\2026-11-06-glyph-stitch-and-validate-cache.md; ruled
  grammar 2026-09-17-glyph-strip-G-grammar-design.md; asks 2026-10-06-c10-engine-asks.md).

  WHAT THIS PROVES, AND HOW:
    * the switch is OFF by default: no flag = today's refusal, no capability (O, I);
    * the ruled 3.4 table, per instance, on glyphs[] AND on the bytes (A, W);
    * bytes are PIXEL-COMPARED against the source columns, not measured by length,
      at 1/4/8/16/24/32 bpp with slots that do not start on a byte boundary (W);
    * the VCL / DevExpress really read the result: TdxSmartGlyph decodes it (D);
    * the three TODO outcomes write nothing and put a line at the top of
      implementation plus a prominent text line (T); POSITIVE CONTROL: the same
      unit under a book with no G-link has neither (P);
    * G[count] follows the image leaf whichever way the source streamed them (C);
    * no castlib = TODO, neither image nor count written (K);
    * a G-link on a class with no N reader is a validate error, only under the
      switch and never in parse-only mode (V);
    * a .pas site of a G-linked member is refused, not renamed (S);
    * with -RealDfm (default ORM3 CLIENT\VARINSP.DFM, skipped when absent): all 20
      real TabcToggleBtn payloads stitch and decode (R).

  Run from any CWD, pwsh 7. Builds its own fixture and castlib.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_glyph_strip_$PID",
  [string]$RealDfm = 'C:\Projects\DB\ORM3\CLIENT\VARINSP.DFM',
  [string]$CaptureDir = ''
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }
. (Join-Path $PSScriptRoot 'lib\DfmLoadCheck.ps1')
. (Join-Path $PSScriptRoot 'lib\GlyphDecodeCheck.ps1')

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null
$libA = Join-Path $WorkDir 'libA'; $libB = Join-Path $WorkDir 'libB'; $app = Join-Path $WorkDir 'app'
foreach ($d in @($libA, $libB, $app)) { [IO.Directory]::CreateDirectory($d) | Out-Null }

# ---- the images: built by hand, so every pixel has a known value ------------
function Stride([int]$W, [int]$Bpp) { return [int]([Math]::Floor(($W * $Bpp + 31) / 32)) * 4 }
# The value at (x,y): unique per column inside its bit depth, varies with y.
function PixelValue([int]$X, [int]$Y, [int]$Bpp) {
  $v = ($X * 7 + $Y * 3 + ($X -shr 3))
  if ($Bpp -ge 32) { return [uint32](($X -shl 16) -bor ($Y -shl 8) -bor ($X -band 255)) }
  if ($Bpp -eq 24) { return [uint32](($X -shl 16) -bor ($Y -shl 8) -bor ($X -band 255)) }
  if ($Bpp -eq 16) { return [uint32](($X * 257 + $Y) -band 0xFFFF) }
  return [uint32]($v -band ((1 -shl $Bpp) - 1))
}
function SetPixel([byte[]]$B, [int]$RowStart, [int]$X, [int]$Bpp, [uint32]$V) {
  if ($Bpp -ge 8) {
    $n = [int]($Bpp / 8); $at = $RowStart + $X * $n
    for ($i = 0; $i -lt $n; $i++) { $B[$at + $i] = [byte](($V -shr (8 * $i)) -band 255) }
  } else {
    $bit = $X * $Bpp; $at = $RowStart + ($bit -shr 3); $shift = 8 - $Bpp - ($bit -band 7)
    $B[$at] = [byte]($B[$at] -bor ($V -shl $shift))
  }
}
function GetPixel([byte[]]$B, [int]$RowStart, [int]$X, [int]$Bpp) {
  if ($Bpp -ge 8) {
    $n = [int]($Bpp / 8); $at = $RowStart + $X * $n; [uint32]$v = 0
    for ($i = 0; $i -lt $n; $i++) { $v = $v -bor ([uint32]$B[$at + $i] -shl (8 * $i)) }
    return $v
  }
  $bit = $X * $Bpp; $at = $RowStart + ($bit -shr 3); $shift = 8 - $Bpp - ($bit -band 7)
  return [uint32](($B[$at] -shr $shift) -band ((1 -shl $Bpp) - 1))
}
function MakeBmp([int]$W, [int]$H, [int]$Bpp) {
  $palN = if ($Bpp -le 8) { 1 -shl $Bpp } else { 0 }
  $off = 14 + 40 + $palN * 4; $st = Stride $W $Bpp; $size = $off + $st * $H
  $b = New-Object byte[] $size
  $b[0] = 0x42; $b[1] = 0x4D
  [BitConverter]::GetBytes([int]$size).CopyTo($b, 2)
  [BitConverter]::GetBytes([int]$off).CopyTo($b, 10)
  [BitConverter]::GetBytes([int]40).CopyTo($b, 14)
  [BitConverter]::GetBytes([int]$W).CopyTo($b, 18)
  [BitConverter]::GetBytes([int]$H).CopyTo($b, 22)
  [BitConverter]::GetBytes([int16]1).CopyTo($b, 26)
  [BitConverter]::GetBytes([int16]$Bpp).CopyTo($b, 28)
  [BitConverter]::GetBytes([int]($st * $H)).CopyTo($b, 34)
  [BitConverter]::GetBytes([int]$palN).CopyTo($b, 46)
  for ($i = 0; $i -lt $palN; $i++) {
    $b[54 + $i * 4] = [byte](($i * 37) -band 255); $b[55 + $i * 4] = [byte](($i * 91) -band 255); $b[56 + $i * 4] = [byte](($i * 11) -band 255)
  }
  for ($y = 0; $y -lt $H; $y++) {
    for ($x = 0; $x -lt $W; $x++) { SetPixel $b ($off + $y * $st) $x $Bpp (PixelValue $x $y $Bpp) }
  }
  return ,$b
}
function Int32([int]$v) { return [BitConverter]::GetBytes($v) }
function Pic([byte[]]$File, [string]$Cls = 'TBitmap') {
  $inner = if ($Cls -eq 'TBitmap') { [byte[]]((Int32 $File.Length) + $File) } else { $File }
  return [byte[]](@([byte]$Cls.Length) + [Text.Encoding]::ASCII.GetBytes($Cls) + $inner)
}
function Hex([byte[]]$B) { return [BitConverter]::ToString($B).Replace('-', '') }
function DfmHex([byte[]]$B, [string]$Indent) {
  $h = Hex $B
  $lines = for ($i = 0; $i -lt $h.Length; $i += 64) { $Indent + $h.Substring($i, [Math]::Min(64, $h.Length - $i)) }
  return "{`r`n" + ($lines -join "`r`n") + '}'
}
function FromHex([string]$H) {
  $b = New-Object byte[] ($H.Length / 2)
  for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($H.Substring($i * 2, 2), 16) }
  return ,$b
}
# Every pixel of the stitched file against the source column it must come from.
function ComparePixels([byte[]]$Out, [byte[]]$Src, [int]$N, [int[]]$Slots) {
  if (($Out.Length -lt 54) -or ($Out[0] -ne 0x42)) { return 'not a BMP' }
  $sw = [BitConverter]::ToInt32($Src, 18); $sh = [BitConverter]::ToInt32($Src, 22); $bpp = [BitConverter]::ToInt16($Src, 28)
  $sOff = [BitConverter]::ToInt32($Src, 10); $oOff = [BitConverter]::ToInt32($Out, 10)
  $slotW = [int]($sw / $N)
  $ow = [BitConverter]::ToInt32($Out, 18); $oh = [BitConverter]::ToInt32($Out, 22)
  if ($ow -ne ($slotW * $Slots.Count)) { return "width $ow, want $($slotW * $Slots.Count)" }
  if ($oh -ne $sh) { return "height $oh, want $sh" }
  if ([BitConverter]::ToInt16($Out, 28) -ne $bpp) { return 'bpp changed' }
  if ($oOff -ne $sOff) { return 'palette or header size changed' }
  for ($i = 54; $i -lt $sOff; $i++) { if ($Out[$i] -ne $Src[$i]) { return "palette byte $i differs" } }
  $oSt = Stride $ow $bpp; $sSt = Stride $sw $bpp
  if ($Out.Length -ne ($oOff + $oSt * $oh)) { return "file length $($Out.Length), want $($oOff + $oSt * $oh)" }
  if ([BitConverter]::ToInt32($Out, 2) -ne $Out.Length) { return 'bfSize wrong' }
  if ([BitConverter]::ToInt32($Out, 34) -ne ($oSt * $oh)) { return 'biSizeImage wrong' }
  for ($y = 0; $y -lt $oh; $y++) {
    for ($k = 0; $k -lt $Slots.Count; $k++) {
      for ($x = 0; $x -lt $slotW; $x++) {
        $a = GetPixel $Out ($oOff + $y * $oSt) ($k * $slotW + $x) $bpp
        $e = GetPixel $Src ($sOff + $y * $sSt) (($Slots[$k] - 1) * $slotW + $x) $bpp
        if ($a -ne $e) { return "pixel ($($k * $slotW + $x),$y): $a, want $e" }
      }
    }
  }
  return ''
}

# ---- the fixture ------------------------------------------------------------
Write-Ascii (Join-Path $libA 'Abcbtn.pas') @'
unit Abcbtn;

interface

uses
  Classes, Graphics;

type
  TabcCustomPicSpeedBtn = class(TComponent)
  private
    FPicture: TPicture;
    FNumGlyphs: Integer;
    FCaption: string;
  published
    property Picture: TPicture read FPicture write FPicture;
    property NumGlyphs: Integer read FNumGlyphs write FNumGlyphs default 1;
    property Caption: string read FCaption write FCaption;
  end;

  TabcToggleBtn = class(TabcCustomPicSpeedBtn);

  TNoReaderBtn = class(TComponent)
  private
    FPicture: TPicture;
  published
    property Picture: TPicture read FPicture write FPicture;
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
    FFlat: TdxSmartGlyph;
    FFlatNum: Integer;
  published
    property OptionsImage: TGlyphDstOpts read FOptionsImage write FOptionsImage;
    property Caption: string read FCaption write FCaption;
    property FlatGlyph: TdxSmartGlyph read FFlat write FFlat;
    property FlatNum: Integer read FFlatNum write FFlatNum default 1;
  end;

implementation

end.
'@

$files = [ordered]@{
  btn4  = (MakeBmp 128 32 24)   # identity
  btn5  = (MakeBmp 160 32 24)   # slot 5 dropped by rule
  btn3  = (MakeBmp 96 16 24)    # reordered: slot 3 then slot 1
  btnP8 = (MakeBmp 64 8 8)      # 8bpp, palette kept
  btnP4 = (MakeBmp 52 8 4)      # 4bpp, slots start mid-byte
  btnP1 = (MakeBmp 65 8 1)      # 1bpp, N=5, slots start mid-byte
  btn16 = (MakeBmp 32 8 16)
  btn32 = (MakeBmp 32 8 32)
}
$nOf = @{ btn4 = 4; btn5 = 5; btn3 = 3; btnP8 = 4; btnP4 = 4; btnP1 = 5; btn16 = 4; btn32 = 4 }
$slotsOf = @{
  btn4 = 1, 2, 3, 4; btn5 = 1, 2, 3, 4; btn3 = 3, 1; btnP8 = 1, 2, 3, 4; btnP4 = 1, 2, 3, 4; btnP1 = 1, 2, 3, 4
  btn16 = 1, 2, 3, 4; btn32 = 1, 2, 3, 4
}
$ind = '      '
$pngFile = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0)
$dfm = "object GlyphForm: TGlyphForm`r`n"
foreach ($k in $files.Keys) {
  # btn4 streams the count BEFORE the picture, everything else after it: the
  # output order must not depend on that.
  $pic = "    Picture.Data = " + (DfmHex (Pic $files[$k]) $ind) + "`r`n"
  $num = "    NumGlyphs = $($nOf[$k])`r`n"
  $dfm += "  object ${k}: TabcToggleBtn`r`n    Caption = '$k'`r`n" + $(if ($k -eq 'btn4') { $num + $pic } else { $pic + $num }) + "  end`r`n"
}
$dfm += "  object btn2: TabcToggleBtn`r`n    Picture.Data = " + (DfmHex (Pic (MakeBmp 64 16 24)) $ind) + "`r`n    NumGlyphs = 2`r`n  end`r`n"
$dfm += "  object btnOdd: TabcToggleBtn`r`n    Picture.Data = " + (DfmHex (Pic (MakeBmp 64 16 24)) $ind) + "`r`n    NumGlyphs = 3`r`n  end`r`n"
$dfm += "  object btnPng: TabcToggleBtn`r`n    Picture.Data = " + (DfmHex (Pic $pngFile 'TPngImage') $ind) + "`r`n    NumGlyphs = 4`r`n  end`r`n"
$dfm += "  object btnDef: TabcToggleBtn`r`n    Picture.Data = " + (DfmHex (Pic (MakeBmp 32 16 24)) $ind) + "`r`n  end`r`n"
$dfm += "  object btnNone: TabcToggleBtn`r`n    Caption = 'no glyph at all'`r`n  end`r`n"
$dfm += "end`r`n"
Write-Ascii (Join-Path $app 'GlyphForm.dfm') $dfm
$fields = (@($files.Keys) + 'btn2', 'btnOdd', 'btnPng', 'btnDef', 'btnNone' | ForEach-Object { "    ${_}: TabcToggleBtn;" }) -join "`r`n"
Write-Ascii (Join-Path $app 'GlyphForm.pas') @"
unit GlyphForm;

interface

uses
  Classes, Abcbtn;

type
  TGlyphForm = class(TDataModule)
$fields
  end;

implementation

{`$R *.dfm}

procedure Touch(F: TGlyphForm);
begin
  F.btn4.Picture:= nil;
end;

end.
"@
$cast = Join-Path $WorkDir 'g.castlib'
Write-Ascii $cast @'
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
$expr = 'G[*/4], G[1/5]G[2/5]G[3/5]G[4/5], G[3/3]G[1/3]'
$rules = Join-Path $WorkDir 'g.rules'
Write-Ascii $rules @"
#convert Abcbtn.TabcToggleBtn -> LibB.TGlyphDstBtn, LibB
#link Caption <- Caption
#link OptionsImage.Glyph <- Picture $expr : AssignGraphic
#link OptionsImage.NumGlyphs <- Picture G[count]
"@
$rulesPlain = Join-Path $WorkDir 'plain.rules'
Write-Ascii $rulesPlain @'
#convert Abcbtn.TabcToggleBtn -> LibB.TGlyphDstBtn, LibB
#link Caption <- Caption
#link OptionsImage.Glyph <- Picture : AssignGraphic
#link OptionsImage.NumGlyphs <- NumGlyphs
'@
$dbA = Join-Path $WorkDir 'dbA.sqlite'; $dbB = Join-Path $WorkDir 'dbB.sqlite'; $dbApp = Join-Path $WorkDir 'dbApp.sqlite'
& $Exe index $libA --db $dbA 2>&1 | Out-Null
& $Exe index $libB --db $dbB 2>&1 | Out-Null
& $Exe index $app --db $dbApp 2>&1 | Out-Null
Check 'V1 the three fixture indexes were built' ((Test-Path $dbA) -and (Test-Path $dbB) -and (Test-Path $dbApp))

function Run([string]$Dir, [string]$Db, [string]$Book, [string[]]$Extra) {
  Push-Location $Dir
  try { $raw = (& $Exe convert-apply --unit 'GlyphForm.pas' --rules $Book --db $Db --db $dbA --db $dbB @Extra 2>&1) -join "`n"; $ec = $LASTEXITCODE }
  finally { Pop-Location }
  $line = ($raw -split "`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1)
  $j = $null; if ($line) { try { $j = $line | ConvertFrom-Json } catch { } }
  return @{ Raw = $raw; J = $j; Exit = $ec }
}

# ---- O / I: OFF by default ---------------------------------------------------
$off = Run $app $dbApp $rules @('--castlib', $cast)
Check 'O1 without the switch a G-link book is still REFUSED (exit 1, not yet realised)' `
      (($off.Exit -eq 1) -and ($off.Raw -match 'not yet realised')) $off.Raw
$info = (& $Exe info --json --db $dbApp 2>&1) -join "`n"
Check 'I1 info --json does not advertise glyph_stitch while the switch is OFF' `
      (($info -match 'lazy_validate') -and ($info -notmatch 'glyph_stitch')) $info

# ---- A: the ruled 3.4 table on glyphs[] --------------------------------------
$dry = Run $app $dbApp $rules @('--glyph-stitch', '--castlib', $cast, '--format', 'json')
Check 'A0 dry run exits 0 with a parsed apply/1' (($dry.Exit -eq 0) -and ($null -ne $dry.J)) $dry.Raw
function Outcome([string]$Inst) { return @($dry.J.glyphs | Where-Object { $_.instance -eq $Inst })[0] }
$o4 = Outcome 'btn4'; $o5 = Outcome 'btn5'; $o2 = Outcome 'btn2'; $oOdd = Outcome 'btnOdd'; $oPng = Outcome 'btnPng'; $oDef = Outcome 'btnDef'
Check 'A1 N=4: glyph-stitched, identity, no dropped slot, rule line 3' `
      (($o4.kind -eq 'glyph-stitched') -and ($o4.source_n -eq 4) -and ($o4.alternative -eq 'G[*/4]') -and (@($o4.dropped_slots).Count -eq 0) -and ($o4.rule_line -eq 3)) ($o4 | ConvertTo-Json -Compress)
Check 'A2 N=5: glyph-stitched, slots 1-4, dropped_slots [5], named to the rule line' `
      (($o5.kind -eq 'glyph-stitched') -and ($o5.source_n -eq 5) -and ($o5.alternative -eq 'G[1/5]G[2/5]G[3/5]G[4/5]') -and ((@($o5.dropped_slots) -join ',') -eq '5') -and ($o5.message -match 'slot 5 dropped by rule line 3')) ($o5 | ConvertTo-Json -Compress)
Check 'A3 N=2: glyph-no-alternative with source_n' (($o2.kind -eq 'glyph-no-alternative') -and ($o2.source_n -eq 2)) ($o2 | ConvertTo-Json -Compress)
Check 'A4 N=3 on a 64 wide bitmap: glyph-not-a-strip' ($oOdd.kind -eq 'glyph-not-a-strip') ($oOdd | ConvertTo-Json -Compress)
Check 'A5 a PNG payload: glyph-format-unsupported' ($oPng.kind -eq 'glyph-format-unsupported') ($oPng | ConvertTo-Json -Compress)
Check 'A6 count property ABSENT = the declared default 1: no N=1 alternative here, so glyph-no-alternative with source_n 1' `
      (($oDef.kind -eq 'glyph-no-alternative') -and ($oDef.source_n -eq 1)) ($oDef | ConvertTo-Json -Compress)
Check 'A7 an EMPTY source glyph is not an error: no outcome at all' (@($dry.J.glyphs | Where-Object { $_.instance -eq 'btnNone' }).Count -eq 0) ''
Check 'A8 a count link produces no outcome of its own (one per instance with a glyph)' (@($dry.J.glyphs).Count -eq 12) (@($dry.J.glyphs).Count)
$sum = @($dry.J.converted).Count + @($dry.J.access_sites).Count + @($dry.J.creator_sites).Count + @($dry.J.todos).Count + @($dry.J.reemit_notes).Count + @($dry.J.warnings).Count
Check 'A9 invariant 1 holds: items[] = the sum of the six arrays' (@($dry.J.items).Count -eq $sum) "$(@($dry.J.items).Count) vs $sum"
Check 'A10 converted[] still counts INSTANCES (13), not outcomes' (@($dry.J.converted).Count -eq 13) (@($dry.J.converted).Count)
Check 'A11 three TODO kinds are items with field todos' `
      (@($dry.J.items | Where-Object { $_.kind -match '^glyph-' -and $_.field -eq 'todos' }).Count -eq 4) (($dry.J.items | Where-Object { $_.kind -match '^glyph-' } | ConvertTo-Json -Compress))
$allNotes = (@($dry.J.reemit_notes) + @($dry.J.warnings)) -join ' || '
Check 'A12 the source count property is not reported dropped: G[count] replaced it' ($allNotes -notmatch 'dropped NumGlyphs') $allNotes
Check 'A13 Picture.Data is not reported dropped or mismatched' ($allNotes -notmatch '(dropped|mismatched) Picture') $allNotes
if ($CaptureDir) {
  [IO.Directory]::CreateDirectory($CaptureDir) | Out-Null
  $ver = ((& $Exe --version 2>&1) -join ' ')
  $line = ($dry.Raw -split "`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1)
  [IO.File]::WriteAllText((Join-Path $CaptureDir 'apply-glyphs-capture.json'), $line.Replace($WorkDir, 'FIXTURE') + "`r`n", [Text.Encoding]::ASCII)
  $txt = Run $app $dbApp $rules @('--glyph-stitch', '--castlib', $cast)
  [IO.File]::WriteAllText((Join-Path $CaptureDir 'apply-glyphs-capture.txt'), "engine: $ver`r`n" + $txt.Raw.Replace($WorkDir, 'FIXTURE').Replace("`n", "`r`n") + "`r`n", [Text.Encoding]::ASCII)
}

# ---- W: the write path, on a COPY --------------------------------------------
$appW = Join-Path $WorkDir 'appw'; [IO.Directory]::CreateDirectory($appW) | Out-Null
foreach ($n in 'GlyphForm.pas', 'GlyphForm.dfm') { [IO.File]::Copy((Join-Path $app $n), (Join-Path $appW $n), $true) }
$dbW = Join-Path $WorkDir 'dbW.sqlite'
& $Exe index $appW --db $dbW 2>&1 | Out-Null
$w = Run $appW $dbW $rules @('--glyph-stitch', '--castlib', $cast, '--apply')
$wDfm = Join-Path $appW 'GlyphForm.dfm'; $wPas = Join-Path $appW 'GlyphForm.pas'
$written = [IO.File]::ReadAllText($wDfm); $writtenPas = [IO.File]::ReadAllText($wPas)
Check 'W0 --apply exits 0 and wrote the target type' (($w.Exit -eq 0) -and ($written -match 'TGlyphDstBtn')) $w.Raw
$loadFails = Test-DfmLoads @($wDfm)
Check 'W1 the converted .dfm parses (DfmLoadCheck)' ($loadFails.Count -eq 0) ($loadFails -join "`n")
function BlockOf([string]$Text, [string]$Comp) {
  $m = [regex]::Match($Text, "(?s)object $Comp\b.*?\r?\n  end")
  return $m.Value
}
function GlyphBytes([string]$Comp) {
  $m = [regex]::Match((BlockOf $written $Comp), "(?s)OptionsImage\.Glyph\.Data = \{([0-9A-Fa-f\s]*)\}")
  if (-not $m.Success) { return ,([byte[]]@()) }
  return ,(FromHex ($m.Groups[1].Value -replace '\s', ''))
}
foreach ($k in $files.Keys) {
  $r = ComparePixels (GlyphBytes $k) $files[$k] $nOf[$k] $slotsOf[$k]
  Check "W2 $k`: stitched pixels equal the source columns (N=$($nOf[$k]), slots $($slotsOf[$k] -join ','), $([BitConverter]::ToInt16($files[$k], 28))bpp)" ($r -eq '') $r
}
# POSITIVE CONTROL for the comparer: the identity bytes against the WRONG slots.
$ctl = ComparePixels (GlyphBytes 'btn4') $files['btn4'] 4 @(2, 1, 3, 4)
Check 'W3 POSITIVE CONTROL the pixel compare FAILS on the wrong slot order' ($ctl -ne '') 'the comparer cannot fail'
foreach ($k in 'btn2', 'btnOdd', 'btnPng', 'btnDef') {
  $b = BlockOf $written $k
  Check "W4 $k`: a TODO outcome writes neither the image nor the count" (($b -notmatch 'OptionsImage\.Glyph') -and ($b -notmatch 'OptionsImage\.NumGlyphs')) $b
}
$bn = BlockOf $written 'btnNone'
Check 'W5 btnNone: no source glyph, no target leaf' ($bn -notmatch 'OptionsImage') $bn

# ---- C: the count leaf and its order ----------------------------------------
foreach ($p in @(@('btn4', 4), @('btn5', 4), @('btn3', 2), @('btnP1', 4))) {
  $b = BlockOf $written $p[0]
  $mC = [regex]::Match($b, 'OptionsImage\.NumGlyphs = (\d+)')
  Check "C1 $($p[0])`: G[count] = $($p[1]), the chosen alternative's slots" ($mC.Success -and ([int]$mC.Groups[1].Value -eq $p[1])) $mC.Value
  Check "C2 $($p[0])`: the count leaf is AFTER the image leaf" ($b.IndexOf('OptionsImage.Glyph.Data') -lt $b.IndexOf('OptionsImage.NumGlyphs') -and $b.IndexOf('OptionsImage.Glyph.Data') -ge 0) ''
}

# ---- T: the TODO line and the prominent message ------------------------------
$implAt = $writtenPas.IndexOf('implementation')
$todoLines = @($writtenPas -split "`r?`n" | Where-Object { $_ -match '^\{ TODO\(converter\): drag-lint glyph: ' })
Check 'T1 one TODO line per TODO outcome, in the unit' ($todoLines.Count -eq 4) ($todoLines -join "`n")
$afterImpl = ($writtenPas.Substring($implAt) -split "`r?`n")
Check 'T2 the TODOs sit at the TOP of the implementation section' `
      (($afterImpl[1] -match '^\{ TODO\(converter\)') -or ($afterImpl[2] -match '^\{ TODO\(converter\)')) (($afterImpl | Select-Object -First 6) -join "`n")
Check 'T3 each TODO names instance, source path and rule line' (@($todoLines | Where-Object { $_ -match 'btn2\.Picture .*rule line 3' }).Count -eq 1) ($todoLines -join "`n")
$tx = Run $app $dbApp $rules @('--glyph-stitch', '--castlib', $cast)
Check 'T4 text mode prints a prominent GLYPH TODO line per TODO outcome' (([regex]::Matches($tx.Raw, '(?m)^\*\*\* GLYPH TODO: ')).Count -eq 4) $tx.Raw
Check 'T5 text mode prints the ruled glyph-stitched sentence' ($tx.Raw -match 'glyph-stitched: Picture N=5 -> OptionsImage\.Glyph G\[1/5\]G\[2/5\]G\[3/5\]G\[4/5\] \(slot 5 dropped by rule line 3\)') $tx.Raw

# ---- P: POSITIVE CONTROL, the same unit with no G-link ------------------------
$pl = Run $app $dbApp $rulesPlain @('--glyph-stitch', '--castlib', $cast, '--format', 'json')
Check 'P1 a book with no G-link has no glyph outcome and no glyph TODO' `
      (($pl.Exit -eq 0) -and (@($pl.J.glyphs).Count -eq 0) -and (@($pl.J.todos | Where-Object { $_ -match 'glyph' }).Count -eq 0)) $pl.Raw
$plOff = Run $app $dbApp $rulesPlain @('--castlib', $cast, '--format', 'json')
Check 'P2 glyphs[] is present and empty with the switch off too (additive)' `
      (($plOff.Raw -match '"glyphs":\[\]')) ''

# ---- K: no cast library ------------------------------------------------------
$k = Run $app $dbApp $rules @('--glyph-stitch', '--format', 'json')
$kCount = @($k.J.glyphs | Where-Object { $_.kind -eq 'glyph-stitched' }).Count
Check 'K1 no --castlib: nothing is stitched, every glyph is a TODO naming the cast library' `
      (($k.Exit -eq 0) -and ($kCount -eq 0) -and (@($k.J.glyphs | Where-Object { $_.kind -eq 'glyph-format-unsupported' -and $_.message -match 'cast library' }).Count -ge 8)) $k.Raw

# ---- V: N4, a G-link on a class with no N reader -----------------------------
$vb = Join-Path $WorkDir 'v.rules'
Write-Ascii $vb "#link OptionsImage.Glyph <- Picture G[*/4] : AssignGraphic`r`n"
$vOut = (& $Exe convert-validate --glyph-stitch --rules $rules --castlib $cast --from Abcbtn.TabcToggleBtn --to LibB.TGlyphDstBtn --db $dbA --db $dbB 2>&1) -join "`n"; $vEc = $LASTEXITCODE
Check 'V2 a descendant of a table class validates under the switch' ($vEc -eq 0) $vOut
$nb = Join-Path $WorkDir 'n.rules'
Write-Ascii $nb @"
#convert Abcbtn.TNoReaderBtn -> LibB.TGlyphDstBtn, LibB
#link OptionsImage.Glyph <- Picture G[*/4] : AssignGraphic
"@
$vOut = (& $Exe convert-validate --glyph-stitch --rules $nb --castlib $cast --from Abcbtn.TNoReaderBtn --to LibB.TGlyphDstBtn --db $dbA --db $dbB 2>&1) -join "`n"; $vEc = $LASTEXITCODE
Check 'V3 a class outside the table is a validate ERROR under the switch, naming the class' `
      (($vEc -eq 1) -and ($vOut -match 'line 2: link OptionsImage\.Glyph <- Picture: no glyph-count reader for Abcbtn\.TNoReaderBtn')) $vOut
$vOut = (& $Exe convert-validate --rules $nb --castlib $cast --from Abcbtn.TNoReaderBtn --to LibB.TGlyphDstBtn --db $dbA --db $dbB 2>&1) -join "`n"; $vEc = $LASTEXITCODE
Check 'V4 POSITIVE CONTROL without the switch the same book is not refused for its reader' ($vOut -notmatch 'no glyph-count reader') $vOut
$vOut = (& $Exe convert-validate --glyph-stitch --rules $nb 2>&1) -join "`n"; $vEc = $LASTEXITCODE
Check 'V5 parse-only stays silent: nothing to resolve' (($vEc -eq 0) -and ($vOut -notmatch 'no glyph-count reader')) $vOut

# ---- S: a .pas site of a G-linked member -------------------------------------
$sb = Join-Path $WorkDir 's.rules'
Write-Ascii $sb @"
#convert Abcbtn.TabcToggleBtn -> LibB.TGlyphDstBtn, LibB
#link FlatGlyph <- Picture G[*/4]
#link FlatNum <- Picture G[count]
"@
$appS = Join-Path $WorkDir 'apps'; [IO.Directory]::CreateDirectory($appS) | Out-Null
foreach ($n in 'GlyphForm.pas', 'GlyphForm.dfm') { [IO.File]::Copy((Join-Path $app $n), (Join-Path $appS $n), $true) }
$dbS = Join-Path $WorkDir 'dbS.sqlite'
& $Exe index $appS --db $dbS 2>&1 | Out-Null
$s = Run $appS $dbS $sb @('--glyph-stitch', '--apply', '--format', 'json')
$sPas = [IO.File]::ReadAllText((Join-Path $appS 'GlyphForm.pas'))
Check 'S1 a plain-path G-link does NOT rename its .pas access site' (($sPas -match 'btn4\.Picture') -and ($sPas -notmatch 'btn4\.FlatGlyph')) $sPas
Check 'S2 the site is reported, never silent' (((@($s.J.warnings) + @($s.J.todos)) -join ' ') -match 'glyph[^|]*(GlyphForm\.pas|access|site)') $s.Raw
Check 'S3 a no-cast G-link across different leaf types writes nothing (no identity to keep the framing by)' `
      ((@($s.J.glyphs | Where-Object { $_.instance -eq 'btn4' })[0].kind) -eq 'glyph-format-unsupported') $s.Raw

# ---- D: the real reader ------------------------------------------------------
Check 'D0 the decode checker builds (RAD Studio + DevExpress dcus)' (Test-GlyphDecodeChecker) 'without it nothing below can tell a loadable glyph from a corrupt one'
$srcCtl = Join-Path $WorkDir 'srcctl.dfm'
Write-Ascii $srcCtl ($dfm -replace 'TabcToggleBtn', 'TGlyphSrcBtn')
$orig = Invoke-GlyphDecode @($srcCtl)
Check 'D1 POSITIVE CONTROL the hand-built source payloads decode in the VCL' (@($orig) -contains 'PIC srcctl.dfm btn4 w=128 h=32') ($orig -join "`n")
$dec = Invoke-GlyphDecode @($wDfm)
foreach ($e in 'btn4 empty=False w=128 h=32 n=4', 'btn5 empty=False w=128 h=32 n=4', 'btn3 empty=False w=64 h=16 n=2', 'btnP8 empty=False w=64 h=8 n=4') {
  Check "D2 TdxSmartGlyph reads $e" (@($dec) -contains "GLYPH GlyphForm.dfm $e") ($dec -join "`n")
}
Check 'D3 no glyph on the converted form fails to decode' ((@($dec) -match '^(GLYPHFAIL|FATAL|ERR) ').Count -eq 0) ($dec -join "`n")

# ---- R: real bytes, the 20 buttons of VARINSP -------------------------------
if ($RealDfm -and (Test-Path -LiteralPath $RealDfm)) {
  $src = [Text.Encoding]::GetEncoding(1252).GetString([IO.File]::ReadAllBytes($RealDfm))
  $ms = [regex]::Matches($src, '(?ms)^(\s*)object (\w+): TabcToggleBtn\r?\n.*?^\1end\r?\n')
  $appR = Join-Path $WorkDir 'appr'; [IO.Directory]::CreateDirectory($appR) | Out-Null
  $names = @(); $body = "object GlyphForm: TGlyphForm`r`n"
  $wanted = 'Caption', 'NumGlyphs', 'Picture\.Data'
  foreach ($m in $ms) {
    $names += $m.Groups[2].Value
    # Only the three properties the fixture classes declare; the rest of the real
    # block is irrelevant to the bytes and needs the real class.
    $pd = [regex]::Match($m.Value, '(?s)Picture\.Data = \{[0-9A-Fa-f\s]*\}').Value
    $ng = [regex]::Match($m.Value, 'NumGlyphs = \d+').Value
    $body += "  object $($m.Groups[2].Value): TabcToggleBtn`r`n    $pd`r`n    $ng`r`n  end`r`n"
  }
  $body += "end`r`n"
  [IO.File]::WriteAllText((Join-Path $appR 'GlyphForm.dfm'), $body, [Text.Encoding]::ASCII)
  $fld = ($names | ForEach-Object { "    ${_}: TabcToggleBtn;" }) -join "`r`n"
  Write-Ascii (Join-Path $appR 'GlyphForm.pas') "unit GlyphForm;`r`n`r`ninterface`r`n`r`nuses`r`n  Classes, Abcbtn;`r`n`r`ntype`r`n  TGlyphForm = class(TDataModule)`r`n$fld`r`n  end;`r`n`r`nimplementation`r`n`r`n{`$R *.dfm}`r`n`r`nend.`r`n"
  $dbR = Join-Path $WorkDir 'dbR.sqlite'
  & $Exe index $appR --db $dbR 2>&1 | Out-Null
  $rb = Join-Path $WorkDir 'r.rules'
  Write-Ascii $rb @"
#convert Abcbtn.TabcToggleBtn -> LibB.TGlyphDstBtn, LibB
#link OptionsImage.Glyph <- Picture G[2/4]G[1/4] : AssignGraphic
#link OptionsImage.NumGlyphs <- Picture G[count]
"@
  $before = [IO.File]::ReadAllText((Join-Path $appR 'GlyphForm.dfm'))
  $origR = Invoke-GlyphDecode @((Join-Path $appR 'GlyphForm.dfm'))
  $rr = Run $appR $dbR $rb @('--glyph-stitch', '--castlib', $cast, '--apply', '--format', 'json')
  $st = @($rr.J.glyphs | Where-Object { $_.kind -eq 'glyph-stitched' })
  Check "R1 all $($names.Count) real VARINSP buttons stitch (want 20)" (($names.Count -eq 20) -and ($st.Count -eq 20)) $rr.Raw
  $afterR = [IO.File]::ReadAllText((Join-Path $appR 'GlyphForm.dfm'))
  $bad = ''; $wantDec = @()
  foreach ($nm in $names) {
    $mb = [regex]::Match($before, "(?s)object $nm\b.*?Picture\.Data = \{([0-9A-Fa-f\s]*)\}")
    $pay = FromHex ($mb.Groups[1].Value -replace '\s', '')
    # 07 'TBitmap' [Int32 size] then the file.
    $file = [byte[]]$pay[12..($pay.Length - 1)]
    $ma = [regex]::Match($afterR, "(?s)object $nm\b.*?OptionsImage\.Glyph\.Data = \{([0-9A-Fa-f\s]*)\}")
    if (-not $ma.Success) { $bad = "$nm`: no glyph written"; break }
    $cmp = ComparePixels (FromHex ($ma.Groups[1].Value -replace '\s', '')) $file 4 @(2, 1)
    if ($cmp) { $bad = "$nm`: $cmp"; break }
    $wantDec += "GLYPH GlyphForm.dfm $nm empty=False w=$([int]([BitConverter]::ToInt32($file, 18) / 2)) h=$([BitConverter]::ToInt32($file, 22)) n=2"
  }
  Check 'R2 every real payload: slot 2 then slot 1 equal the source columns, pixel by pixel' ($bad -eq '') $bad
  $decR = Invoke-GlyphDecode @((Join-Path $appR 'GlyphForm.dfm'))
  $missing = @($wantDec | Where-Object { @($decR) -notcontains $_ })
  Check 'R3 all 20 real results DECODE in TdxSmartGlyph: half the source width, same height, two glyphs' `
        (($wantDec.Count -eq 20) -and ($missing.Count -eq 0)) (($missing -join "`n") + "`n" + ($decR -join "`n"))
  Check 'R4 no real glyph fails to decode' ((@($decR) -match '^(GLYPHFAIL|FATAL|ERR) ').Count -eq 0) ($decR -join "`n")
} else {
  Write-Host '  [SKIP] R: -RealDfm absent' -ForegroundColor Yellow
}

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
