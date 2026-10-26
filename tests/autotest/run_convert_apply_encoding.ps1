<#
  run_convert_apply_encoding.ps1 -- the convert-apply encoding guard (CONV-ENC E1'/E2/E3, 1.34.1).

  E1'. A value --apply would write into a unit's .pas that the file's CURRENT encoding cannot
       hold (here an ANSI file, new unit name with U+0413 U+0414) refuses the unit: exit 1,
       nothing written, apply/1 refused:true + refusal_kind 'encoding_refused' + the
       encoding_refused{file,file_encoding,raise_to,chars_total,chars[{code,text,line}]} object;
       the dry run reports the same. A character the ANSI code page HOLDS (e-acute) is a
       negative control: no refusal. A UTF-8 file never refuses.
  E2.  --raise-encoding "<path>=utf8-bom" (repeatable) writes that file as UTF-8 + BOM in the same
       transaction and the edits apply; a path that is not a file of the run, a level other than
       utf8-bom, or an entry without '=' is exit 2 with nothing written.
  E3.  A TEXT .dfm gets Delphi #codes for what its encoding cannot hold inside string literals and
       never refuses for them; a BINARY (TPF0) .dfm is never compared (one warnings[] line).
       E3e/E3f (lane H): an unfit character OUTSIDE a literal (identifier) has no #code: refused
       like a .pas; --raise-encoding on the .dfm writes it raw.
  U1.  (lane H) A UTF-8 + BOM .pas with a #use rule is a unit (was refused "not a unit").
  L1.  (lane L1) Every convert-apply READ decodes the file's own encoding: a BOM-less UTF-8 or a
       UTF-16 .pas with a non-ASCII comment before the field is retyped on the type token (was:
       column drift), a UTF-8 .dfm's non-ASCII caption survives the block re-emit (was: mojibake).
  Capability: info --json capabilities.convert_encoding_guard is JSON true.

  Fixtures are GENERATED here (bytes written with explicit encodings), in a $PID scratch folder.
  The machine ANSI code page must be Latin-1 (1252): e-acute fits, U+0413 does not.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_encoding_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir -Force | Out-Null

$Ansi  = [Text.Encoding]::GetEncoding(1252)
$Utf8  = New-Object Text.UTF8Encoding($false)
$Utf8B = New-Object Text.UTF8Encoding($true)
$CyG = [string][char]0x413; $CyD = [string][char]0x414; $Eac = [string][char]0x00E9
$Bom = [byte[]](0xEF,0xBB,0xBF)

$pasText = "unit Form1;`r`n`r`ninterface`r`n`r`nuses`r`n  Classes, LibA, DstLib;`r`n`r`ntype`r`n  TForm1 = class(TComponent)`r`n    btnOne: TSrcBtn;`r`n  end;`r`n`r`nimplementation`r`n`r`n{`$R *.dfm}`r`n`r`nend.`r`n{ caf$Eac }`r`n"
$dfmText = "object Form1: TForm1`r`n  object btnOne: TSrcBtn`r`n    Caption = 'One'`r`n  end`r`nend`r`n"
$libText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures\unitrules\LibA.pas'))

# One case = one folder: LibA.pas (ASCII), Form1.pas/.dfm in the given encodings, the book, an index.
function NewCase([string]$Name, [Text.Encoding]$PasEnc, [Text.Encoding]$DfmEnc, [string]$NewClass, [string]$ExtraRule = '', [byte[]]$DfmBytes = $null) {
  $d = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $d -Force | Out-Null
  [IO.File]::WriteAllText("$d\LibA.pas", $libText, $Ansi)
  [IO.File]::WriteAllBytes("$d\Form1.pas", $PasEnc.GetPreamble() + $PasEnc.GetBytes($pasText))
  if ($DfmBytes) { [IO.File]::WriteAllBytes("$d\Form1.dfm", $DfmBytes) }
  else { [IO.File]::WriteAllBytes("$d\Form1.dfm", $DfmEnc.GetPreamble() + $DfmEnc.GetBytes($dfmText)) }
  $dst = "unit DstLib;`r`n`r`ninterface`r`n`r`nuses`r`n  Classes;`r`n`r`ntype`r`n  $NewClass = class(TPersistent)`r`n  private`r`n    FCaption: string;`r`n    FHint: string;`r`n  published`r`n    property Caption: string read FCaption write FCaption;`r`n    property Hint: string read FHint write FHint;`r`n  end;`r`n`r`nimplementation`r`n`r`nend.`r`n{ caf$Eac }`r`n"
  [IO.File]::WriteAllBytes("$d\DstLib.pas", $Utf8B.GetPreamble() + $Utf8B.GetBytes($dst))
  $book = "#convert TSrcBtn -> $NewClass`r`n#link Caption <- Caption`r`n$ExtraRule"
  [IO.File]::WriteAllBytes("$d\book.rules", $Utf8B.GetPreamble() + $Utf8B.GetBytes($book))
  $null | & $Exe index $d --db "$d\fx.sqlite" 2>&1 | Out-Null
  return $d
}
function Apply([string]$Dir, [string[]]$Extra = @()) {
  $o = ($null | & $Exe @(@('convert-apply','--unit',"$Dir\Form1.pas",'--rules',"$Dir\book.rules",'--db',"$Dir\fx.sqlite",'--format','json') + $Extra) 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function Snap([string]$Dir) { return ((Get-ChildItem $Dir -File | Sort-Object Name | ForEach-Object { $_.Name + ':' + (Get-FileHash $_.FullName -Algorithm MD5).Hash }) -join '|') }
function Bytes([string]$p) { return ,[IO.File]::ReadAllBytes($p) }
function HasBom([string]$p) { $b = Bytes $p; return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) }
function Bck([string]$Dir) { return @(Get-ChildItem $Dir -Filter '*.BCK*' -ErrorAction SilentlyContinue).Count }

# ---- capability -----------------------------------------------------------------
$j = Json (($null | & $Exe info --json 2>&1) -join "`n")
Check 'CAP info --json: capabilities.convert_encoding_guard is JSON true' `
  (($null -ne $j) -and ($j.capabilities.convert_encoding_guard -is [bool]) -and ($j.capabilities.convert_encoding_guard -eq $true))

# ---- E1' the refusal (ANSI .pas, U+0413 U+0414, e-acute holds) --------------------
$cls = "Unit$CyG$CyD$Eac"   # a #use unit name: the one value path an ANSI .pas gets from the book (identifiers are lossy in the index)
$a = NewCase 'a_ansi' $Ansi $Ansi 'TDstBtn' "#use $cls`r`n"
$before = Snap $a
$r = Apply $a @('--apply')
$j = Json $r.Out
$ec = if ($j) { $j.encoding_refused } else { $null }
Check 'E1a ansi .pas --apply: exit 1, ok false, refused true, refusal_kind encoding_refused' `
  (($r.Code -eq 1) -and ($null -ne $j) -and ($j.schema -eq 'apply/1') -and ($j.ok -eq $false) -and ($j.refused -eq $true) -and ($j.refusal_kind -eq 'encoding_refused')) $r.Out
Check 'E1b encoding_refused: file, file_encoding ansi, raise_to utf8-bom, chars_total 2' `
  (($null -ne $ec) -and ($ec.file -eq "$a\Form1.pas") -and ($ec.file_encoding -eq 'ansi') -and ($ec.raise_to -eq 'utf8-bom') -and ($ec.chars_total -eq 2)) $r.Out
Check 'E1c chars[]: U+0413 and U+0414 (the e-acute that fits is NOT listed), text + 1-based line' `
  (($null -ne $ec) -and (@($ec.chars).Count -eq 2) -and ($ec.chars[0].code -eq 1043) -and ($ec.chars[0].text -eq $CyG) -and ($ec.chars[0].line -ge 1) -and `
   ($ec.chars[1].code -eq 1044) -and ($ec.chars[1].text -eq $CyD)) $r.Out
Check 'E1d reason names the count, the file, the encoding and the way out' `
  (($null -ne $j) -and ([string]$j.reason -match '^encoding: 2 character\(s\) do not fit .*Form1\.pas \(ansi\): U\+0413 line \d+, U\+0414 line \d+ -- raise the file to UTF-8 with BOM, or skip the unit$')) $r.Out
Check 'E1e refusal writes nothing: every file byte-identical, no .BCK backup' ((Snap $a) -eq $before -and (Bck $a) -eq 0)
$r = Apply $a
$j = Json $r.Out
Check 'E1f dry run (no --apply) reports the same refusal, exit 1, nothing written' `
  (($r.Code -eq 1) -and ($null -ne $j) -and ($j.refusal_kind -eq 'encoding_refused') -and ($j.encoding_refused.chars_total -eq 2) -and ((Snap $a) -eq $before)) $r.Out
$r = ($null | & $Exe convert-apply --unit "$a\Form1.pas" --rules "$a\book.rules" --db "$a\fx.sqlite" 2>&1) -join "`n"
Check 'E1g text mode prints REFUSED: encoding: ...' ($r -match '(?m)^REFUSED: encoding: 2 character\(s\)') $r

# ---- negative controls: a character the ANSI page holds, and UTF-8 ---------------
$d = NewCase 'b_fits' $Ansi $Ansi 'TDstBtn' "#use Unit$Eac`r`n"
$r = Apply $d @('--apply'); $j = Json $r.Out
$t = $Ansi.GetString((Bytes "$d\Form1.pas"))
Check 'NC1 e-acute unit name in an ANSI file (fits): exit 0, applied, no refusal key, file still ANSI (E9, no BOM)' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and -not ($j.PSObject.Properties.Name -contains 'refusal_kind') -and `
   ($t -match "Unit$Eac") -and -not (HasBom "$d\Form1.pas")) $r.Out
$d = NewCase 'c_utf8' $Utf8 $Utf8 'TDstBtn' "#use $cls`r`n"
$r = Apply $d @('--apply'); $j = Json $r.Out
$t = $Utf8.GetString((Bytes "$d\Form1.pas"))
Check 'NC2 BOM-less UTF-8 .pas + .dfm with U+0413 U+0414: never refuses, exit 0, applied, still no BOM' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and ($t -match [regex]::Escape($cls)) -and -not (HasBom "$d\Form1.pas")) $r.Out
$d = NewCase 'c2_utf8bom' $Utf8B $Utf8B 'TDstBtn' "#default Hint = '$CyG$CyD'`r`n"
$r = Apply $d @('--apply'); $j = Json $r.Out
Check 'NC3 UTF-8 + BOM .pas/.dfm, value U+0413 U+0414 in the .dfm: never refuses, exit 0, raw characters (no #codes), BOM kept' (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and (HasBom "$d\Form1.dfm") -and ($Utf8.GetString((Bytes "$d\Form1.dfm")) -match "Hint = '$CyG$CyD'")) $r.Out

# ---- E2 the raise ----------------------------------------------------------------
$a = Join-Path $WorkDir 'a_ansi'
$r = Apply $a @('--apply','--raise-encoding',"$a\Form1.pas=utf8-bom",'--raise-encoding',"$a\Form1.dfm=utf8-bom")
$j = Json $r.Out
$t = $Utf8.GetString((Bytes "$a\Form1.pas"))
Check 'E2a --raise-encoding .pas + .dfm: exit 0, both files written UTF-8 + BOM, the new unit name is in the .pas' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and (HasBom "$a\Form1.pas") -and (HasBom "$a\Form1.dfm") -and ($t -match [regex]::Escape($cls))) $r.Out
Check 'E2b the raise keeps the editor backup: a .BCK file exists' ((Bck $a) -ge 1)
$d = NewCase 'd_raise_fits' $Ansi $Ansi 'TDstBtn' "#use Unit$Eac`r`n"
$r = Apply $d @('--apply','--raise-encoding',"$d\Form1.pas=utf8-bom"); $j = Json $r.Out
$t = $Utf8.GetString((Bytes "$d\Form1.pas"))
Check 'E2c raise when every value would have fitted: still honoured (UTF-8 + BOM), e-acute intact' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and (HasBom "$d\Form1.pas") -and ($t -match "Unit$Eac")) $r.Out
$d = NewCase 'd2_raise_already' $Utf8B $Utf8B 'TDstBtn' "#default Hint = '$CyG$CyD'`r`n"
$r = Apply $d @('--apply','--raise-encoding',"$d\Form1.pas=utf8-bom"); $j = Json $r.Out
$b = Bytes "$d\Form1.pas"
Check 'E2d raising a file that is already UTF-8 + BOM: exit 0, exactly one BOM (idempotent)' (($r.Code -eq 0) -and ($b.Length -gt 6) -and -not (($b[3] -eq 0xEF) -and ($b[4] -eq 0xBB) -and ($b[5] -eq 0xBF))) $r.Out
$d = NewCase 'e_raise_dry' $Ansi $Ansi 'TDstBtn' "#use $cls`r`n"
$before = Snap $d
$r = Apply $d @('--raise-encoding',"$d\Form1.pas=utf8-bom"); $j = Json $r.Out
Check 'E2e raise without --apply writes nothing' (($r.Code -eq 0) -and ((Snap $d) -eq $before)) $r.Out

# ---- E2 usage errors (exit 2, nothing written) -------------------------------------
$d = NewCase 'f_usage' $Ansi $Ansi 'TDstBtn' "#use $cls`r`n"
$before = Snap $d
$r = Apply $d @('--apply','--raise-encoding',"$d\LibA.pas=utf8-bom")
Check 'E2f raise of a file that is not a file of this run: exit 2, "is not a file of this run", nothing written' `
  (($r.Code -eq 2) -and ($r.Out -match 'raise-encoding: .*LibA\.pas is not a file of this run') -and ((Snap $d) -eq $before)) $r.Out
$r = Apply $d @('--apply','--raise-encoding',"$d\Form1.pas=utf16-bom")
Check 'E2g any level other than utf8-bom: exit 2, nothing written' (($r.Code -eq 2) -and ($r.Out -match 'raise-encoding') -and ((Snap $d) -eq $before)) $r.Out
$r = Apply $d @('--apply','--raise-encoding',"$d\Form1.pas")
Check 'E2h an entry without =<level>: exit 2, nothing written' (($r.Code -eq 2) -and ($r.Out -match 'raise-encoding') -and ((Snap $d) -eq $before)) $r.Out

# ---- E3 text .dfm: #codes, never refuses -------------------------------------------
$d = NewCase 'g_dfmcodes' $Ansi $Ansi 'TDstBtn' "#default Hint = '$CyG$CyD'`r`n"
$r = Apply $d @('--apply'); $j = Json $r.Out
$t = $Ansi.GetString((Bytes "$d\Form1.dfm"))
Check 'E3a ANSI text .dfm, value U+0413 U+0414: exit 0, never refuses, the .dfm holds #1043#1044, no ? corruption, still ANSI' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and ($t -match '#1043#1044') -and ($t -notmatch '\?') -and -not (HasBom "$d\Form1.dfm")) ($t)
$d = NewCase 'g2_dfmfits' $Ansi $Ansi 'TDstBtn' "#default Hint = '$Eac'`r`n"
$r = Apply $d @('--apply')
$t = $Ansi.GetString((Bytes "$d\Form1.dfm"))
Check 'E3b negative control: a value the ANSI .dfm holds (e-acute) is written as is, no #code' (($r.Code -eq 0) -and ($t -match "Hint = '$Eac'") -and ($t -notmatch '#233')) ($t)

# ---- E3 identifiers: a #code is legal only inside a string literal (lane H, item 3) --------
$d = NewCase 'g3_dfmident' $Ansi $Ansi 'TDstBtn' "#default Hint = ab$CyD`r`n"
$before = Snap $d
$r = Apply $d @('--apply'); $j = Json $r.Out
$ec = if ($j) { $j.encoding_refused } else { $null }
Check 'E3e ANSI text .dfm, bare IDENTIFIER value ab+U+0414 (no #code possible): exit 1, refused, encoding_refused names the .dfm, chars_total 1, nothing written (was: silently written as ab?)' `
  (($r.Code -eq 1) -and ($null -ne $j) -and ($j.refusal_kind -eq 'encoding_refused') -and ($null -ne $ec) -and ($ec.file -eq "$d\Form1.dfm") -and `
   ($ec.file_encoding -eq 'ansi') -and ($ec.chars_total -eq 1) -and ($ec.chars[0].code -eq 1044) -and ([string]$j.reason -match 'outside a string literal') -and ((Snap $d) -eq $before)) $r.Out
$d = NewCase 'g4_dfmident_raise' $Ansi $Ansi 'TDstBtn' "#default Hint = ab$CyD`r`n"
$r = Apply $d @('--apply','--raise-encoding',"$d\Form1.dfm=utf8-bom"); $j = Json $r.Out
Check 'E3f the same identifier with --raise-encoding on the .dfm: exit 0, .dfm UTF-8 + BOM, raw identifier written' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and (HasBom "$d\Form1.dfm") -and ($Utf8.GetString((Bytes "$d\Form1.dfm")) -match "Hint = ab$CyD")) $r.Out

# ---- lane H item 2: a UTF-8 + BOM .pas with a #use rule is a unit -------------------
$d = NewCase 'i_bom_use' $Utf8B $Utf8B 'TDstBtn' "#use UnitBom`r`n"
$r = Apply $d @('--apply'); $j = Json $r.Out
$b = Bytes "$d\Form1.pas"
Check 'U1 UTF-8 + BOM .pas + #use: exit 0, applied (was: refused "not a unit"), UnitBom in the uses, exactly one BOM' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and ($Utf8.GetString($b) -match 'UnitBom') -and (HasBom "$d\Form1.pas") -and `
   -not (($b[3] -eq 0xEF) -and ($b[4] -eq 0xBB) -and ($b[5] -eq 0xBF))) $r.Out

# ---- lane L1: every convert-apply READ decodes the file's own encoding (BOM, else valid UTF-8, else ANSI) ----
$Utf16 = New-Object Text.UnicodeEncoding($false, $true)
$pasSave = $pasText; $dfmSave = $dfmText
$pasText = $pasSave.Replace('    btnOne: TSrcBtn;', "    { caf$Eac $CyD } btnOne: TSrcBtn;")
$d = NewCase 'l1a_utf8_col' $Utf8 $Utf8 'TDstBtn'
$r = Apply $d @('--apply'); $j = Json $r.Out
$t = $Utf8.GetString((Bytes "$d\Form1.pas"))
Check 'L1a BOM-less UTF-8 .pas, non-ASCII comment BEFORE the field on its line: the retype lands on the type token (was: column drift)' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and ($t -match [regex]::Escape("{ caf$Eac $CyD } btnOne: TDstBtn;")) -and -not (HasBom "$d\Form1.pas")) ($r.Out + "`n" + $t)
$d = NewCase 'l1c_utf16_pas' $Utf16 $Ansi 'TDstBtn'
$r = Apply $d @('--apply'); $j = Json $r.Out
$b = Bytes "$d\Form1.pas"
$t = $Utf16.GetString($b, 2, $b.Length - 2)
Check 'L1c UTF-16 LE + BOM .pas with a non-ASCII comment before the field: retyped on the token, still UTF-16 + BOM' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and ($b[0] -eq 0xFF) -and ($b[1] -eq 0xFE) -and ($t -match [regex]::Escape("{ caf$Eac $CyD } btnOne: TDstBtn;"))) ($r.Out + "`n" + $t)
$pasText = $pasSave
$dfmText = $dfmSave.Replace("Caption = 'One'", "Caption = 'O$CyD$Eac'")
$d = NewCase 'l1b_utf8_dfm' $Utf8 $Utf8 'TDstBtn'
$r = Apply $d @('--apply'); $j = Json $r.Out
$t = $Utf8.GetString((Bytes "$d\Form1.dfm"))
Check 'L1b BOM-less UTF-8 .dfm, non-ASCII caption in the converted block: re-emitted intact (was: mojibake), still no BOM' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and ($t -match 'TDstBtn') -and ($t -match [regex]::Escape("Caption = 'O$CyD$Eac'")) -and -not (HasBom "$d\Form1.dfm")) ($r.Out + "`n" + $t)
$d = NewCase 'l1d_utf8bom_dfm' $Utf8B $Utf8B 'TDstBtn'
$r = Apply $d @('--apply'); $j = Json $r.Out
$t = $Utf8.GetString((Bytes "$d\Form1.dfm"))
Check 'L1d UTF-8 + BOM .dfm, non-ASCII caption in the converted block: re-emitted intact, one BOM' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.ok -eq $true) -and ($t -match 'TDstBtn') -and ($t -match [regex]::Escape("Caption = 'O$CyD$Eac'")) -and (HasBom "$d\Form1.dfm")) ($r.Out + "`n" + $t)
$dfmText = $dfmSave
# ---- E3 binary .dfm: never compared, one warnings[] line ----------------------------
function PStr([string]$s) { return ,([byte[]]@([byte]$s.Length) + [Text.Encoding]::ASCII.GetBytes($s)) }
$bin = [byte[]]([Text.Encoding]::ASCII.GetBytes('TPF0')) + (PStr 'TForm1') + (PStr 'Form1') + [byte[]](0) `
  + (PStr 'TSrcBtn') + (PStr 'btnOne') + (PStr 'Caption') + [byte[]](6) + (PStr 'One') + [byte[]](0,0,0)
$d = NewCase 'h_bindfm' $Ansi $Ansi 'TDstBtn' '' $bin
$r = Apply $d @('--apply'); $j = Json $r.Out
$binBefore = Snap $d
Check 'E3c binary (TPF0) .dfm: never compared and never rewritten -- no refusal key, nothing written even with --raise-encoding on it (the planner skips a binary .dfm: ok false, no convertible instance)' (($null -ne $j) -and -not ($j.PSObject.Properties.Name -contains 'refusal_kind') -and ($j.ok -eq $false) -and ((Snap $d) -eq $binBefore)) $r.Out
$r = Apply $d @('--apply','--raise-encoding',"$d\Form1.dfm=utf8-bom"); $j = Json $r.Out
Check 'E3d --raise-encoding naming the binary .dfm: not rewritten (bytes identical, still TPF0)' (($r.Code -ne 0) -and ((Snap $d) -eq $binBefore) -and ([Text.Encoding]::ASCII.GetString((Bytes "$d\Form1.dfm"),0,4) -eq 'TPF0')) $r.Out

} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
if ($script:fail) { Write-Host 'run_convert_apply_encoding: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_convert_apply_encoding: all checks passed' -ForegroundColor Green
exit 0
