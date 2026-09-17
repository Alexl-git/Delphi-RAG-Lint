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

# ---- run ------------------------------------------------------------------------
$o = & $Exe glyph-vacuum --root $src --out $out 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Host "--- raw stdout ---"; Write-Host $o
Check 'T1 exit 0 on a completed walk' ($code -eq 0) "exit=$code"
Check 'T1 summary line names the counts' ($o -match 'glyph-vacuum: dfm=2 graphics=5 distinct=4 skipped=0') $o

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
  Check 'T2 five rows' ($rows.Count -eq 5) "rows=$($rows.Count)"
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
  Check 'T4 four classes (TabcToggleBtn, TSpeedButton, TImageList, TcxImageList)' ($c.Count -eq 4) "n=$($c.Count)"
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
  Check 'T5 one h2 per class' (([regex]::Matches($g, '<h2>')).Count -eq 4)
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
Check 'T6 append of the same root is idempotent' ($n1 -eq 5 -and $n2 -eq 5) "n1=$n1 n2=$n2"
& $Exe glyph-vacuum --root $src3 --out $outA --append | Out-Null
$rowsA = Import-Csv (Join-Path $outA 'instances.tsv') -Delimiter "`t"
Check 'T6 append of a second root adds its rows' ($rowsA.Count -eq 6) "n=$($rowsA.Count)"
Check 'T6 merged classes.tsv counts both roots' (((Import-Csv (Join-Path $outA 'classes.tsv') -Delimiter "`t") | Where-Object { $_.component_class -eq 'TabcToggleBtn' }).instances -eq '3')
Check 'T6 images dir holds one file per distinct sha (4)' ((Get-ChildItem (Join-Path $outA 'images')).Count -eq 4)
& $Exe glyph-vacuum --root $src3 --out $outA | Out-Null
Check 'T6 without --append the file is REPLACED' ((Import-Csv (Join-Path $outA 'instances.tsv') -Delimiter "`t").Count -eq 1)

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
