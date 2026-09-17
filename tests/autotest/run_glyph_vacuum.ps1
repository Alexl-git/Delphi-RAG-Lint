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

# ---- run ------------------------------------------------------------------------
$o = & $Exe glyph-vacuum --root $src --out $out 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Host "--- raw stdout ---"; Write-Host $o
Check 'T1 exit 0 on a completed walk' ($code -eq 0) "exit=$code"
Check 'T1 summary line names the counts' ($o -match 'glyph-vacuum: dfm=1 graphics=1 distinct=1 skipped=0') $o

$inst = Join-Path $out 'instances.tsv'
Check 'T1 instances.tsv written' (Test-Path $inst)
if (Test-Path $inst) {
  $raw = Get-Content $inst
  Write-Host "--- raw instances.tsv ---"; $raw | ForEach-Object { Write-Host $_ }
  $rows = @(Import-Csv $inst -Delimiter "`t")
  Check 'T1 one row' ($rows.Count -eq 1) "rows=$($rows.Count)"
  $r = $rows[0]
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
}

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
