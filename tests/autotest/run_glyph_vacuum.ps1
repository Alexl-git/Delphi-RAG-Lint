<#
  run_glyph_vacuum.ps1 -- `glyph-vacuum` walks .dfm files, extracts every streamed
  graphic, decodes it and pairs it with its count property, writing instances.tsv,
  classes.tsv, skipped.tsv, images\ and gallery.html.

  Spec: docs\superpowers\specs\2026-09-17-glyph-vacuum-design.md. This guard
  generates its OWN fixtures (24bpp BMP strips wrapped exactly as a .dfm streams a
  TPicture: [len]'TBitmap' [4-byte size] BM...) so it depends on no corpus and no
  index. RAW ROWS ARE PRINTED BEFORE ANY ASSERTION.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_glyph_vacuum"
)
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

# A 24bpp bottom-up BMP, W x H, split into $Slots vertical bands of distinct solid colour.
function New-StripBmp([int]$W,[int]$H,[int]$Slots){
  $stride = [int](([math]::Floor(($W*3 + 3) / 4)) * 4)
  $pix = $stride * $H
  $b = New-Object byte[] (54 + $pix)
  $b[0]=0x42; $b[1]=0x4D
  [BitConverter]::GetBytes([int32](54+$pix)).CopyTo($b,2)
  [BitConverter]::GetBytes([int32]54).CopyTo($b,10)
  [BitConverter]::GetBytes([int32]40).CopyTo($b,14)
  [BitConverter]::GetBytes([int32]$W).CopyTo($b,18)
  [BitConverter]::GetBytes([int32]$H).CopyTo($b,22)
  [BitConverter]::GetBytes([int16]1).CopyTo($b,26)
  [BitConverter]::GetBytes([int16]24).CopyTo($b,28)
  [BitConverter]::GetBytes([int32]$pix).CopyTo($b,34)
  $slotW = [int]($W / $Slots)
  for($y=0;$y -lt $H;$y++){ for($x=0;$x -lt $W;$x++){
    $s = [math]::Min([int]($x / $slotW), $Slots-1)
    $o = 54 + $y*$stride + $x*3
    $b[$o] = [byte](40*$s); $b[$o+1] = [byte](200-30*$s); $b[$o+2] = [byte](60+50*$s)
  }}
  return ,$b
}
# Wrap image bytes the way TPicture streams into Picture.Data: [len]Class [int32 size] bytes.
function New-PicturePayload([string]$Class,[byte[]]$Img){
  $c = [Text.Encoding]::ASCII.GetBytes($Class)
  $b = New-Object byte[] (1 + $c.Length + 4 + $Img.Length)
  $b[0] = [byte]$c.Length; $c.CopyTo($b,1)
  [BitConverter]::GetBytes([int32]$Img.Length).CopyTo($b, 1+$c.Length)
  $Img.CopyTo($b, 1+$c.Length+4)
  return ,$b
}
# Render bytes as a .dfm binary-property block: { hex, 64 chars per line }.
function ConvertTo-DfmHex([byte[]]$B){
  $hex = ([BitConverter]::ToString($B)).Replace('-','')
  $lines = @(); for($i=0;$i -lt $hex.Length;$i+=64){ $lines += ('    ' + $hex.Substring($i,[math]::Min(64,$hex.Length-$i))) }
  return "{`n" + ($lines -join "`n") + "}"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$src = Join-Path $WorkDir 'src'; $out = Join-Path $WorkDir 'out'
New-Item -ItemType Directory $src -Force | Out-Null

# ---- fixture 1: text .dfm, one 128x32 strip with NumGlyphs = 4 ----------------
$strip4 = New-StripBmp 128 32 4
$pay4   = New-PicturePayload 'TBitmap' $strip4
Write-Ascii (Join-Path $src 'FrmA.pas') "unit FrmA;`ninterface`nimplementation`nend."
Write-Ascii (Join-Path $src 'FrmA.dfm') @"
object FrmA: TFrmA
  Left = 0
  Top = 0
  Caption = 'A'
  object Panel1: TPanel
    Left = 8
    object Btn1: TabcToggleBtn
      Left = 8
      Top = 8
      NumGlyphs = 4
      Picture.Data = $(ConvertTo-DfmHex $pay4)
    end
  end
end
"@

# ---- fixture 2: count disagreement, inherited object, container, icon ----------
$strip2 = New-StripBmp 64 32 2                      # really 2 glyphs
$pay2   = New-PicturePayload 'TBitmap' $strip2
$ico    = [byte[]](0x00,0x00,0x01,0x00,0x01,0x00,0x10,0x10,0x00,0x00,0x01,0x00,0x20,0x00,0x68,0x04,0x00,0x00,0x16,0x00,0x00,0x00) + (New-Object byte[] 1128)
$payIco = New-PicturePayload 'TIcon' $ico
$blob   = New-Object byte[] 40; for($i=0;$i -lt 40;$i++){ $blob[$i]=[byte]($i*3) }   # not a picture: an image-list blob
Write-Ascii (Join-Path $src 'FrmB.dfm') @"
inherited FrmB: TFrmB
  Caption = 'B'
  inherited Btn2: TabcToggleBtn
    NumGlyphs = 3
    Picture.Data = $(ConvertTo-DfmHex $pay2)
  end
  object BtnIco: TSpeedButton
    Glyph.Data = $(ConvertTo-DfmHex $payIco)
  end
  object ImageList1: TImageList
    Bitmap = $(ConvertTo-DfmHex $blob)
  end
  object cxImageList1: TcxImageList
    FormatVersion = 1
    ImageInfo = <
      item
        Image.Data = $(ConvertTo-DfmHex $pay4)
      end>
  end
end
"@

# ---- fixture 3 (Task 10): length-prefixed bare bitmap, raw SVG, a non-image
# blob that must NOT sniff as EMF from the bare iType alone, and a genuine EMF
# positive control (the real ' EMF' signature 40 bytes into the header) ---------
$stripBB = New-StripBmp 64 32 2
$payBB   = New-Object byte[] (4 + $stripBB.Length)
[BitConverter]::GetBytes([int32]$stripBB.Length).CopyTo($payBB, 0)
$stripBB.CopyTo($payBB, 4)

$svgText = '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16"/></svg>'
$paySvg  = [Text.Encoding]::ASCII.GetBytes($svgText)

$fake1 = [byte[]](0x01,0x00,0x00,0x00,0x01,0x02,0x03,0x04,0x05,0x06)

$emfCtl = New-Object byte[] 100
$emfCtl[0] = 0x01; $emfCtl[1] = 0x00; $emfCtl[2] = 0x00; $emfCtl[3] = 0x00
$emfCtl[40] = 0x20; $emfCtl[41] = 0x45; $emfCtl[42] = 0x4D; $emfCtl[43] = 0x46

# Fix round 1 finding 1: a BARE bitmap at payload offset 0 -- no length prefix,
# no class name -- so ParseStreamedGraphic's FIRST branch (bare magic at 0)
# must fire and fall through to the tail ReadDibHeader call. This is the exact
# branch an earlier draft of this fix broke with a premature Exit (caught in
# review, fixed before commit 2343c0bc) -- no fixture exercised it until now.
$stripBare1 = New-StripBmp 96 32 3
$payBare1   = $stripBare1

# Fix round 1 finding 2: the first Int32 LE equals Length-4 (an 8-byte length
# field claiming an 8-byte image), so the length-prefixed branch's OWN size
# check passes -- but SniffImageFormat at offset 4 finds no magic (all zero
# bytes), so InnerFmt stays '' and the payload must fall through to the
# class-name preamble test, which must ALSO reject it (byte 0 = 8 is read as
# N = 8, but 1+N+4 = 13 > Length = 12, so the preamble's own length check
# rejects it -- not the printable-ASCII check, since N and the Int32 share the
# same low byte by construction whenever the high 3 bytes are 0, the preamble
# length check always fires first for this shape). Either way the payload must
# never be reported as an image: format/wrapper stay empty.
$collPay = [byte[]](0x08,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)

Write-Ascii (Join-Path $src 'FrmD.dfm') @"
object FrmD: TFrmD
  Caption = 'D'
  object BitBtn1: TBitBtn
    NumGlyphs = 2
    Glyph.Data = $(ConvertTo-DfmHex $payBB)
  end
  object Svg1: TcxButton
    OptionsImage.Glyph.Data = $(ConvertTo-DfmHex $paySvg)
  end
  object Fake1: TPanel
    Blob.Data = $(ConvertTo-DfmHex $fake1)
  end
  object EmfCtl: TPanel
    Blob.Data = $(ConvertTo-DfmHex $emfCtl)
  end
  object Bare1: TImage
    Picture.Data = $(ConvertTo-DfmHex $payBare1)
  end
  object Coll1: TPanel
    Blob.Data = $(ConvertTo-DfmHex $collPay)
  end
end
"@

# ---- run ------------------------------------------------------------------------
$o = & $Exe glyph-vacuum --root $src --out $out 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Host "--- raw stdout ---"; Write-Host $o
Check 'T1 exit 0 on a completed walk' ($code -eq 0) "exit=$code"
Check 'T1 summary line names the counts' ($o -match 'glyph-vacuum: dfm=3 graphics=11 distinct=10 skipped=0') $o

$inst = Join-Path $out 'instances.tsv'
Check 'T1 instances.tsv written' (Test-Path $inst)
if (Test-Path $inst) {
  $raw = Get-Content $inst
  Write-Host "--- raw instances.tsv ---"; $raw | ForEach-Object { Write-Host $_ }
  $rows = @(Import-Csv $inst -Delimiter "`t")
  $r = $rows | Where-Object { $_.object_path -eq 'Panel1.Btn1' }
  Check 'T1 dfm_path is the fixture' ($r.dfm_path -eq (Join-Path $src 'FrmA.dfm')) $r.dfm_path
  Check 'T1 pas_unit is the sibling'  ($r.pas_unit -eq 'FrmA.pas') $r.pas_unit
  Check 'T1 surface=dfm'              ($r.surface -eq 'dfm')
  Check 'T1 form_class'               ($r.form_class -eq 'TFrmA') $r.form_class
  Check 'T1 object_path is dotted'    ($r.object_path -eq 'Panel1.Btn1') $r.object_path
  Check 'T1 component_name'           ($r.component_name -eq 'Btn1')
  Check 'T1 component_class bare'     ($r.component_class -eq 'TabcToggleBtn') $r.component_class
  Check 'T1 property is the leaf path' ($r.property -eq 'Picture.Data') $r.property
  Check 'T1 wrapper TBitmap'          ($r.wrapper -eq 'TBitmap') $r.wrapper
  Check 'T1 format bmp'               ($r.format -eq 'bmp') $r.format
  Check 'T1 bytes = payload length'   ([int]$r.bytes -eq $pay4.Length) "$($r.bytes) vs $($pay4.Length)"
  Check 'T1 width 128'                ([int]$r.width -eq 128) $r.width
  Check 'T1 height 32'                ([int]$r.height -eq 32) $r.height
  Check 'T1 bpp 24'                   ([int]$r.bpp -eq 24) $r.bpp
  Check 'T1 palette_entries 0'        ([int]$r.palette_entries -eq 0) $r.palette_entries
  $sha = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($pay4))).Replace('-','').ToLower()
  Check 'T1 payload_sha is SHA-256 of the payload' ($r.payload_sha -eq $sha) "$($r.payload_sha) vs $sha"
  Check 'T1 image_file names images\<sha>.bmp' ($r.image_file -eq "images\$sha.bmp") $r.image_file
  $img = Join-Path $out $r.image_file
  Check 'T1 image file exists'        (Test-Path $img)
  if (Test-Path $img) {
    $ib = [IO.File]::ReadAllBytes($img)
    Check 'T1 image file is the BARE image (BM first), not the wrapped payload' ($ib.Length -eq $strip4.Length -and $ib[0] -eq 0x42 -and $ib[1] -eq 0x4D) "len=$($ib.Length)"
  }
  $b2  = $rows | Where-Object { $_.object_path -eq 'Btn2' }
  $ico = $rows | Where-Object { $_.object_path -eq 'BtnIco' }
  $il  = $rows | Where-Object { $_.object_path -eq 'ImageList1' }
  $cx  = $rows | Where-Object { $_.object_path -eq 'cxImageList1' }
  $a1  = $rows | Where-Object { $_.object_path -eq 'Panel1.Btn1' }
  $bb  = $rows | Where-Object { $_.object_path -eq 'BitBtn1' }
  $sv  = $rows | Where-Object { $_.object_path -eq 'Svg1' }
  $fk  = $rows | Where-Object { $_.object_path -eq 'Fake1' }
  $ec  = $rows | Where-Object { $_.object_path -eq 'EmfCtl' }
  $ba  = $rows | Where-Object { $_.object_path -eq 'Bare1' }
  $cl  = $rows | Where-Object { $_.object_path -eq 'Coll1' }
  Check 'T2 eleven rows' ($rows.Count -eq 11) "rows=$($rows.Count)"
  Check 'T2 Btn1 count_prop NumGlyphs'     ($a1.count_prop -eq 'NumGlyphs') $a1.count_prop
  Check 'T2 Btn1 count_value 4'           ($a1.count_value -eq '4') $a1.count_value
  Check 'T2 Btn1 count_effective 4 (no db: from the value)' ($a1.count_effective -eq '4') $a1.count_effective
  Check 'T2 Btn1 inferred_n 4 (128/32)'   ($a1.inferred_n -eq '4') $a1.inferred_n
  Check 'T2 Btn1 agree Y'                 ($a1.agree -eq 'Y') $a1.agree
  Check 'T2 Btn1 kind strip'              ($a1.kind -eq 'strip') $a1.kind
  Check 'T2 Btn1 inherited empty'         ($a1.inherited -eq '') $a1.inherited
  Check 'T2 Btn2 inherited Y'             ($b2.inherited -eq 'Y') $b2.inherited
  Check 'T2 Btn2 form_class TFrmB'        ($b2.form_class -eq 'TFrmB') $b2.form_class
  Check 'T2 Btn2 count_value 3 vs inferred 2 -> agree N' ($b2.count_value -eq '3' -and $b2.inferred_n -eq '2' -and $b2.agree -eq 'N') "$($b2.count_value)/$($b2.inferred_n)/$($b2.agree)"
  Check 'T2 icon wrapper TIcon format ico' ($ico.wrapper -eq 'TIcon' -and $ico.format -eq 'ico') "$($ico.wrapper)/$($ico.format)"
  Check 'T2 icon has no count -> count_prop, agree, inferred_n empty' ($ico.count_prop -eq '' -and $ico.agree -eq '' -and $ico.inferred_n -eq '') "$($ico.count_prop)/$($ico.agree)/$($ico.inferred_n)"
  Check 'T2 icon kind single'             ($ico.kind -eq 'single') $ico.kind
  Check 'T2 icon width/height 0 (not a BMP)' ($ico.width -eq '0' -and $ico.height -eq '0') "$($ico.width)x$($ico.height)"
  Check 'T2 TImageList.Bitmap kind container, wrapper empty' ($il.kind -eq 'container' -and $il.wrapper -eq '') "$($il.kind)/$($il.wrapper)"
  Check 'T2 TImageList image_file uses .bin' ($il.image_file -like 'images\*.bin') $il.image_file
  Check 'T2 cxImageList item row property ImageInfo[0].Image.Data' ($cx.property -eq 'ImageInfo[0].Image.Data') $cx.property
  Check 'T2 cxImageList item kind container, format bmp' ($cx.kind -eq 'container' -and $cx.format -eq 'bmp') "$($cx.kind)/$($cx.format)"
  Check 'T2 cxImageList item shares Btn1 sha' ($cx.payload_sha -eq $a1.payload_sha)

  # ---- Task 10: length-prefixed bare bitmap (TBitBtn.Glyph.Data, no class name) --
  Check 'T8 BitBtn1 wrapper empty (no class-name preamble)' ($bb.wrapper -eq '') $bb.wrapper
  Check 'T8 BitBtn1 format bmp'            ($bb.format -eq 'bmp') $bb.format
  Check 'T8 BitBtn1 width 64 height 32'    ($bb.width -eq '64' -and $bb.height -eq '32') "$($bb.width)x$($bb.height)"
  Check 'T8 BitBtn1 count_value 2, inferred_n 2, agree Y, kind strip' ($bb.count_value -eq '2' -and $bb.inferred_n -eq '2' -and $bb.agree -eq 'Y' -and $bb.kind -eq 'strip') "$($bb.count_value)/$($bb.inferred_n)/$($bb.agree)/$($bb.kind)"
  Check 'T8 BitBtn1 image_file .bmp'       ($bb.image_file -like 'images\*.bmp') $bb.image_file
  $bbImg = Join-Path $out $bb.image_file
  if (Test-Path $bbImg) {
    $bbBytes = [IO.File]::ReadAllBytes($bbImg)
    Check 'T8 BitBtn1 image file is the bare BMP (BM first), length = image length' ($bbBytes.Length -eq $stripBB.Length -and $bbBytes[0] -eq 0x42 -and $bbBytes[1] -eq 0x4D) "len=$($bbBytes.Length) vs $($stripBB.Length)"
  }

  # ---- Task 10: raw SVG text, no preamble (TdxSmartGlyph-style) ------------------
  Check 'T8 Svg1 format svg, wrapper empty' ($sv.format -eq 'svg' -and $sv.wrapper -eq '') "$($sv.format)/$($sv.wrapper)"
  Check 'T8 Svg1 width/height 0 (not inferred for SVG)' ($sv.width -eq '0' -and $sv.height -eq '0') "$($sv.width)x$($sv.height)"
  Check 'T8 Svg1 kind single'              ($sv.kind -eq 'single') $sv.kind
  Check 'T8 Svg1 image_file .svg'          ($sv.image_file -like 'images\*.svg') $sv.image_file
  $svImg = Join-Path $out $sv.image_file
  if (Test-Path $svImg) {
    $svTxt = [IO.File]::ReadAllText($svImg, [Text.Encoding]::ASCII)
    Check 'T8 Svg1 image file text starts with <?xml' ($svTxt.StartsWith('<?xml')) $svTxt.Substring(0, [Math]::Min(20, $svTxt.Length))
  }

  # ---- Task 10: a short non-image blob must NOT sniff as EMF from iType alone ----
  Check 'T8 Fake1 format empty (NOT emf)'  ($fk.format -eq '') $fk.format
  Check 'T8 Fake1 image_file .bin'         ($fk.image_file -like 'images\*.bin') $fk.image_file

  # ---- Task 10: EMF positive control -- the real ENHMETAHEADER ' EMF' signature --
  Check 'T8 EmfCtl format emf'             ($ec.format -eq 'emf') $ec.format

  # ---- Fix round 1, finding 1: bare BMP at offset 0 reaching ReadDibHeader -------
  Check 'T9 Bare1 wrapper empty (bare, no preamble)' ($ba.wrapper -eq '') $ba.wrapper
  Check 'T9 Bare1 format bmp'               ($ba.format -eq 'bmp') $ba.format
  Check 'T9 Bare1 width 96 height 32'       ($ba.width -eq '96' -and $ba.height -eq '32') "$($ba.width)x$($ba.height)"
  Check 'T9 Bare1 bpp 24'                   ($ba.bpp -eq '24') $ba.bpp
  Check 'T9 Bare1 inferred_n 3 (96/32)'     ($ba.inferred_n -eq '3') $ba.inferred_n
  $baImg = Join-Path $out $ba.image_file
  if (Test-Path $baImg) {
    $baBytes = [IO.File]::ReadAllBytes($baImg)
    Check 'T9 Bare1 image file is the exact bare BMP, same length as the source strip' ($baBytes.Length -eq $stripBare1.Length -and $baBytes[0] -eq 0x42 -and $baBytes[1] -eq 0x4D) "len=$($baBytes.Length) vs $($stripBare1.Length)"
  }

  # ---- Fix round 1, finding 2: Int32-equals-Length-4 collision with no magic at
  # offset 4 must fall through to (and be rejected by) the class-name preamble ---
  Check 'T9 Coll1 format empty (falls through, not length-prefixed)' ($cl.format -eq '') $cl.format
  Check 'T9 Coll1 wrapper empty (preamble also rejects it)' ($cl.wrapper -eq '') $cl.wrapper
  Check 'T9 Coll1 image_file .bin'          ($cl.image_file -like 'images\*.bin') $cl.image_file
}

# ---- positive control: count column stays empty with no count property ----------
$src3 = Join-Path $WorkDir 'src3'; New-Item -ItemType Directory $src3 -Force | Out-Null
Write-Ascii (Join-Path $src3 'FrmC.dfm') @"
object FrmC: TFrmC
  object Btn3: TabcToggleBtn
    Picture.Data = $(ConvertTo-DfmHex $pay4)
  end
end
"@
$o5 = & $Exe glyph-vacuum --root $src3 --out (Join-Path $WorkDir 'out3') 2>&1 | Out-String
$r3 = (Import-Csv (Join-Path $WorkDir 'out3\instances.tsv') -Delimiter "`t")[0]
Write-Host "--- raw positive-control row ---"; Get-Content (Join-Path $WorkDir 'out3\instances.tsv') | ForEach-Object { Write-Host $_ }
Check 'T2 positive control: no count property -> count_value, count_effective, agree EMPTY; inferred_n still 4' ($r3.count_prop -eq '' -and $r3.count_value -eq '' -and $r3.count_effective -eq '' -and $r3.agree -eq '' -and $r3.inferred_n -eq '4') "$($r3.count_prop)/$($r3.count_value)/$($r3.count_effective)/$($r3.agree)/$($r3.inferred_n)"
Check 'T2 positive control: kind strip from inferred_n alone' ($r3.kind -eq 'strip') $r3.kind

# ---- dotted count property (T2 dotted): TcxButton-style OptionsImage.NumGlyphs --
# A DevExpress .dfm streams a nested property as a flat dotted scalar name, not a
# nested object block. FindCountProp must match CountPropNames on the LAST
# dot-segment of the scalar's name, and keep the FULL dotted name as count_prop.
$src4   = Join-Path $WorkDir 'src4'; New-Item -ItemType Directory $src4 -Force | Out-Null
$stripCx = New-StripBmp 64 32 2
$payCx   = New-PicturePayload 'TBitmap' $stripCx
Write-Ascii (Join-Path $src4 'FrmD.dfm') @"
object FrmD: TFrmD
  object Btn4: TcxButton
    OptionsImage.NumGlyphs = 2
    OptionsImage.Glyph.Data = $(ConvertTo-DfmHex $payCx)
  end
end
"@
$out4 = Join-Path $WorkDir 'out4'
$o9 = & $Exe glyph-vacuum --root $src4 --out $out4 2>&1 | Out-String
Write-Host "--- raw stdout (dotted count run) ---"; Write-Host $o9
$r4 = @(Import-Csv (Join-Path $out4 'instances.tsv') -Delimiter "`t")
Write-Host "--- raw instances.tsv (dotted count run) ---"; Get-Content (Join-Path $out4 'instances.tsv') | ForEach-Object { Write-Host $_ }
Check 'T2 dotted count_prop keeps full dotted name OptionsImage.NumGlyphs' ($r4[0].count_prop -eq 'OptionsImage.NumGlyphs') $r4[0].count_prop
Check 'T2 dotted count_value 2' ($r4[0].count_value -eq '2') $r4[0].count_value
Check 'T2 dotted count_effective 2, inferred_n 2, agree Y' ($r4[0].count_effective -eq '2' -and $r4[0].inferred_n -eq '2' -and $r4[0].agree -eq 'Y') "$($r4[0].count_effective)/$($r4[0].inferred_n)/$($r4[0].agree)"

# ---- fixture 4: an index that DECLARES the class, for the qualification columns --
$lib = Join-Path $WorkDir 'lib'; New-Item -ItemType Directory $lib -Force | Out-Null
Write-Ascii (Join-Path $lib 'Abcbtn.pas') @'
unit Abcbtn;

interface

uses
  Classes, Graphics;

type
  TabcNumGlyphs = 1..5;

  TabcCustomPicSpeedBtn = class(TGraphicControl)
  private
    FPicture: TPicture;
    FNumGlyphs: TabcNumGlyphs;
  published
    property Picture: TPicture read FPicture write FPicture;
    property NumGlyphs: TabcNumGlyphs read FNumGlyphs write FNumGlyphs default 1;
  end;

  TabcToggleBtn = class(TabcCustomPicSpeedBtn)
  end;

implementation

end.
'@
Write-Ascii (Join-Path $lib 'UsesBtn.pas') @'
unit UsesBtn;

interface

uses
  Abcbtn;

procedure Touch(B: TabcToggleBtn);

implementation

procedure Touch(B: TabcToggleBtn);
begin
  B.Picture.Assign(nil);
  B.Picture := nil;
end;

end.
'@
$libDb = Join-Path $WorkDir 'lib.sqlite'
& $Exe index $lib --db $libDb | Out-Null

$outDb = Join-Path $WorkDir 'out-db'
$o6 = & $Exe glyph-vacuum --root $src --out $outDb --db $libDb 2>&1 | Out-String
Write-Host "--- raw stdout (db run) ---"; Write-Host $o6
Check 'T3 db run exit 0' ($LASTEXITCODE -eq 0) $o6
$rowsDb = Import-Csv (Join-Path $outDb 'instances.tsv') -Delimiter "`t"
Write-Host "--- raw instances.tsv (db run) ---"; Get-Content (Join-Path $outDb 'instances.tsv') | ForEach-Object { Write-Host $_ }
$a1d = $rowsDb | Where-Object { $_.object_path -eq 'Panel1.Btn1' }
$icd = $rowsDb | Where-Object { $_.object_path -eq 'BtnIco' }
Check 'T3 class_unit Abcbtn for TabcToggleBtn' ($a1d.class_unit -eq 'Abcbtn') $a1d.class_unit
Check 'T3 count_default 1 (declared on the ancestor)' ($a1d.count_default -eq '1') $a1d.count_default
Check 'T3 count_effective stays 4 when the value is present' ($a1d.count_effective -eq '4') $a1d.count_effective
Check 'T3 TSpeedButton not in this index -> class_unit empty, count_default empty' ($icd.class_unit -eq '' -and $icd.count_default -eq '') "$($icd.class_unit)/$($icd.count_default)"
# the default half of count_effective: same class, no value streamed
$o7 = & $Exe glyph-vacuum --root $src3 --out (Join-Path $WorkDir 'out3-db') --db $libDb 2>&1 | Out-String
$r3d = (Import-Csv (Join-Path $WorkDir 'out3-db\instances.tsv') -Delimiter "`t")[0]
Check 'T3 no value + declared default 1 -> count_effective 1, inferred 4, agree N, kind strip' ($r3d.count_value -eq '' -and $r3d.count_default -eq '1' -and $r3d.count_effective -eq '1' -and $r3d.agree -eq 'N' -and $r3d.kind -eq 'strip') "$($r3d.count_value)/$($r3d.count_default)/$($r3d.count_effective)/$($r3d.agree)/$($r3d.kind)"

# ---- fixture 4 (continued): classes.tsv, the per-class summary ------------------
$cls = Join-Path $outDb 'classes.tsv'
Check 'T4 classes.tsv written' (Test-Path $cls)
if (Test-Path $cls) {
  Write-Host "--- raw classes.tsv ---"; Get-Content $cls | ForEach-Object { Write-Host $_ }
  $c = Import-Csv $cls -Delimiter "`t"
  $tb = $c | Where-Object { $_.component_class -eq 'TabcToggleBtn' }
  # 4 original (TabcToggleBtn, TSpeedButton, TImageList, TcxImageList) + 3 from
  # Task 10's FrmD fixtures (TBitBtn, TcxButton, TPanel -- Fake1+EmfCtl share TPanel)
  # + 1 from fix round 1 (TImage -- Bare1; Coll1 is TPanel, already counted)
  Check 'T4 eight classes' ($c.Count -eq 8) "n=$($c.Count)"
  Check 'T4 TabcToggleBtn instances 2'      ($tb.instances -eq '2') $tb.instances
  Check 'T4 graphic_props Picture.Data'      ($tb.graphic_props -eq 'Picture.Data') $tb.graphic_props
  Check 'T4 count_props NumGlyphs'           ($tb.count_props -eq 'NumGlyphs') $tb.count_props
  Check 'T4 count_default 1'                 ($tb.count_default -eq '1') $tb.count_default
  Check 'T4 n_distribution 4:1;3:1'          ($tb.n_distribution -eq '4:1;3:1') $tb.n_distribution
  Check 'T4 inferred_distribution 4:1;2:1'   ($tb.inferred_distribution -eq '4:1;2:1') $tb.inferred_distribution
  Check 'T4 disagreements 1'                 ($tb.disagreements -eq '1') $tb.disagreements
  Check 'T4 formats bmp:2'                   ($tb.formats -eq 'bmp:2') $tb.formats
  Check 'T4 distinct_payloads 2'             ($tb.distinct_payloads -eq '2') $tb.distinct_payloads
  # runtime_refs: B.Picture.Assign / B.Picture := in UsesBtn.pas bind to the
  # DECLARING class Abcbtn.TabcCustomPicSpeedBtn.Picture (Picture is inherited,
  # not redeclared, on TabcToggleBtn) -- confirmed by the raw find-callers
  # output below. CountRuntimeRefs follows the property's DeclaredIn from the
  # class's own prop tree, so TabcToggleBtn's count is the ancestor's 2, not 0.
  $fc = & $Exe query find-callers --name Picture --resolved --db $libDb 2>&1 | Out-String
  Write-Host "--- raw find-callers --name Picture --resolved --db `$libDb ---"; Write-Host $fc
  Check 'T4 runtime_refs 2 (UsesBtn.pas touches Picture twice)' ($tb.runtime_refs -eq '2') $tb.runtime_refs
  $sp = $c | Where-Object { $_.component_class -eq 'TSpeedButton' }
  Check 'T4 unresolved class -> runtime_refs empty' ($sp.runtime_refs -eq '') $sp.runtime_refs
}

# ---- fixture 4 (continued): gallery.html, the visual-review page -----------------
$gal = Join-Path $outDb 'gallery.html'
Check 'T5 gallery.html written' (Test-Path $gal)
if (Test-Path $gal) {
  $g = Get-Content $gal -Raw
  $imgs = [regex]::Matches($g, 'src="(images/[0-9a-f]{64}\.[a-z]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
  $files = Get-ChildItem (Join-Path $outDb 'images') | ForEach-Object { 'images/' + $_.Name } | Sort-Object -Unique
  Check 'T5 gallery references every image file and nothing else' (($imgs -join ',') -eq ($files -join ',')) "refs=$($imgs -join ',') files=$($files -join ',')"
  Check 'T5 one h2 per class' (([regex]::Matches($g, '<h2>')).Count -eq 8)
  Check 'T5 Btn1 strip has 3 separators at 32/64/96 px' ($g -match 'left:32px' -and $g -match 'left:64px' -and $g -match 'left:96px')
  Check 'T5 caption carries N/inferred/agree' ($g -match 'N=4 inferred=4 agree=Y')
  Check 'T5 no script tag' (-not ($g -match '<script'))
}

# ---- append: same roots twice = same rows; a second root adds, never duplicates --
$outA = Join-Path $WorkDir 'out-append'
& $Exe glyph-vacuum --root $src --out $outA | Out-Null
$n1 = (Import-Csv (Join-Path $outA 'instances.tsv') -Delimiter "`t").Count
& $Exe glyph-vacuum --root $src --out $outA --append | Out-Null
$n2 = (Import-Csv (Join-Path $outA 'instances.tsv') -Delimiter "`t").Count
Check 'T6 append of the same root is idempotent' ($n1 -eq 11 -and $n2 -eq 11) "n1=$n1 n2=$n2"
& $Exe glyph-vacuum --root $src3 --out $outA --append | Out-Null
$rowsA = Import-Csv (Join-Path $outA 'instances.tsv') -Delimiter "`t"
Check 'T6 append of a second root adds its rows' ($rowsA.Count -eq 12) "n=$($rowsA.Count)"
Check 'T6 merged classes.tsv counts both roots' (((Import-Csv (Join-Path $outA 'classes.tsv') -Delimiter "`t") | Where-Object { $_.component_class -eq 'TabcToggleBtn' }).instances -eq '3')
Check 'T6 images dir holds one file per distinct sha (10)' ((Get-ChildItem (Join-Path $outA 'images')).Count -eq 10)
& $Exe glyph-vacuum --root $src3 --out $outA | Out-Null
Check 'T6 without --append the file is REPLACED' ((@(Import-Csv (Join-Path $outA 'instances.tsv') -Delimiter "`t")).Count -eq 1)

# ---- fixture 5: a BINARY .dfm (TPF0) written by hand in the TWriter format --------
function New-BinaryDfm(){
  $ms = New-Object IO.MemoryStream
  $w  = New-Object IO.BinaryWriter($ms)
  function S([string]$s){ $b=[Text.Encoding]::ASCII.GetBytes($s); $w.Write([byte]$b.Length); $w.Write($b) }
  $w.Write([Text.Encoding]::ASCII.GetBytes('TPF0'))
  S 'TFrmBin'; S 'FrmBin'                     # root: class, name
  $w.Write([byte]0)                           # end of root properties
    S 'TabcToggleBtn'; S 'BtnBin'             # child object
    S 'NumGlyphs'; $w.Write([byte]2); $w.Write([byte]4)          # vaInt8 = 2, value 4
    S 'Picture.Data'; $w.Write([byte]10); $w.Write([int32]$pay4.Length); $w.Write($pay4)   # vaBinary = 10
    $w.Write([byte]0)                         # end of child properties
    $w.Write([byte]0)                         # end of child children
  $w.Write([byte]0)                           # end of root children
  $w.Flush(); return ,$ms.ToArray()
}
$srcBin = Join-Path $WorkDir 'srcbin'; New-Item -ItemType Directory $srcBin -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $srcBin 'FrmBin.dfm'), (New-BinaryDfm))
[IO.File]::WriteAllText((Join-Path $srcBin 'Broken.dfm'), "this is not a dfm at all: no object block", [Text.Encoding]::ASCII)   # ParseDfmBlock returns False: no top-level object
$outBin = Join-Path $WorkDir 'out-bin'
$o8 = & $Exe glyph-vacuum --root $srcBin --out $outBin 2>&1 | Out-String
Write-Host "--- raw stdout (binary run) ---"; Write-Host $o8
Write-Host "--- raw skipped.tsv ---"; Get-Content (Join-Path $outBin 'skipped.tsv') | ForEach-Object { Write-Host $_ }
$rb = @(Import-Csv (Join-Path $outBin 'instances.tsv') -Delimiter "`t")
Check 'T7 binary .dfm decoded: one row, object_path BtnBin, count 4, 128x32' ($rb.Count -eq 1 -and $rb[0].object_path -eq 'BtnBin' -and $rb[0].count_value -eq '4' -and $rb[0].width -eq '128') ($rb | Out-String)
Check 'T7 binary row keeps the ORIGINAL dfm_path' ($rb[0].dfm_path -eq (Join-Path $srcBin 'FrmBin.dfm')) $rb[0].dfm_path
$sk = @(Import-Csv (Join-Path $outBin 'skipped.tsv') -Delimiter "`t")
Check 'T7 unparseable file listed in skipped.tsv with a reason' ($sk.Count -eq 1 -and $sk[0].dfm_path -like '*Broken.dfm' -and $sk[0].reason -ne '') ($sk | Out-String)
Check 'T7 summary counts skipped=1 dfm=2' ($o8 -match 'dfm=2 graphics=1 distinct=1 skipped=1') $o8
Check 'T7 skipped.tsv exists even when empty (db run)' (Test-Path (Join-Path $outDb 'skipped.tsv'))

# ---- exit codes ------------------------------------------------------------------
$empty = Join-Path $WorkDir 'empty'; New-Item -ItemType Directory $empty -Force | Out-Null
$o2 = & $Exe glyph-vacuum --root $empty --out (Join-Path $WorkDir 'out-empty') 2>&1 | Out-String
Check 'T1 empty tree -> exit 0 and says 0 graphics' ($LASTEXITCODE -eq 0 -and $o2 -match 'graphics=0') $o2
$o3 = & $Exe glyph-vacuum --root (Join-Path $WorkDir 'nope') --out (Join-Path $WorkDir 'out-nope') 2>&1 | Out-String
Check 'T1 missing root -> exit 2' ($LASTEXITCODE -eq 2) $o3
$o4 = & $Exe glyph-vacuum --out (Join-Path $WorkDir 'out-noroot') 2>&1 | Out-String
Check 'T1 no --root -> exit 2 with usage' ($LASTEXITCODE -eq 2 -and $o4 -match 'Usage') $o4

if ($script:fail) { Write-Host "RESULT: FAIL" -ForegroundColor Red; exit 1 }
Write-Host "RESULT: PASS" -ForegroundColor Green; exit 0
