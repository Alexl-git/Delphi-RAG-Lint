<#
  run_dfm_nonascii_identifier.ps1 -- the DFM extractor keeps a non-ASCII identifier WHOLE (wave 149 DF).

  148 CV NEXT-BUMP: `object btn<U-umlaut>ber: TButton` was stored as the symbol `btn` -- tree-sitter-dfm's
  identifier rule was ASCII-only ([A-Za-z_][A-Za-z0-9_]*), so the lexer stopped at the first
  non-ASCII letter and drag-lint emitted the ASCII prefix. convert-apply --only btn<U-umlaut>ber then
  reported "could not locate .dfm object block ... instance skipped". tree-sitter-dfm 1.2.0 accepts
  Unicode letters (\p{L}); DRagLint.Core.Indexer already hands the parser UTF-8 (EnsureUtf8Bytes:
  BOM-less ANSI = Windows-1252 and UTF-16 are transcoded, a UTF-8 BOM is stripped).

  D1. Index tests\fixtures\dfm-nonascii (FormAnsi.dfm Windows-1252, FormUtf8.dfm UTF-8 + BOM): the
      component symbols are btn<U-umlaut>ber / btnPlain (ANSI) and btn<U-umlaut>ber / btn<De><a> / btnPlain
      (UTF-8); qualified names carry the full name; NO symbol is named `btn` (the RED shape); the
      event-binding ref is btn<U-umlaut>berClick in both files.
      Positive control: the ASCII names (FormAnsi, FormUtf8, btnPlain) are stored exactly as before.
  D2. convert-apply --only btn<U-umlaut>ber on a generated Windows-1252 unit + .dfm (TSrcBtn -> TNewBtn):
      exit 0, converted = [btn<U-umlaut>ber: TSrcBtn -> TNewBtn], warnings = [], no instance-skipped
      item, only_matched = [btn<U-umlaut>ber]. Same for the UTF-8 + BOM twin.
      Positive control: --only btnPlain converts btnPlain in the same case.

  RED: run with -Exe <engine 1.48.0-alpha or older tree-sitter-dfm.dll>: D1 stores `btn`, D2 skips.
  Fixtures are NOT 7-bit ASCII on purpose; run_encoding_guard.ps1 lists them as deliberate.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_dfm_nonascii_$PID"
)
try {
$ErrorActionPreference = 'Continue'
# 149 INT: the engine is asked for --output-encoding utf8, so decode its stdout as UTF-8 too. Under the
# battery (redirected stdout) pwsh otherwise decodes with the OEM code page and every non-ASCII name
# compares unequal (D1a/D1b/D1d/D1f FAILED in the battery, PASSED in a console).
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir -Force | Out-Null

$U   = [string][char]0x00DC                               # U-umlaut
$Cy  = [string][char]0x0414 + [string][char]0x0430        # Cyrillic De + a
$Ueber = "btn${U}ber"; $Da = "btn${Cy}"
function Show([string]$s) { return ($s -replace [char]0x00DC,'<U>' -replace [char]0x0414,'<De>' -replace [char]0x0430,'<a>') }

# sql --json: {columns:[{name}], rows:[[positional]]} -- map rows onto the column names (lesson: $row.name is $null).
function SqlRows([string]$Db, [string]$Query) {
  $o = ($null | & $Exe sql --query $Query --db $Db --json --output-encoding utf8 2>&1) -join ''
  $a = $o.IndexOf('{'); if ($a -lt 0) { return ,@() }
  $j = $o.Substring($a) | ConvertFrom-Json
  $names = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = @()
  foreach ($r in @($j.rows)) {
    $h = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += [pscustomobject]$h
  }
  return ,$out
}

# ---- D1: the fixture index ----------------------------------------------------------------
$fx = (Resolve-Path "$PSScriptRoot\..\fixtures\dfm-nonascii").Path
$db = "$WorkDir\fx.sqlite"
$null | & $Exe index $fx --db $db 2>&1 | Out-Null
Check 'D1 fixture index built' (Test-Path $db)

$rows = SqlRows $db "select s.name, s.qualified_name, s.kind, f.path from symbols s join files f on f.id=s.file_id where f.path like '%.dfm' and s.kind in ('component','form') order by f.path, s.start_line"
$ansi = @($rows | Where-Object { $_.path -like '*FormAnsi.dfm' })
$utf8 = @($rows | Where-Object { $_.path -like '*FormUtf8.dfm' })
$ansiNames = @($ansi | Where-Object { $_.kind -eq 'component' } | ForEach-Object { $_.name })
$utf8Names = @($utf8 | Where-Object { $_.kind -eq 'component' } | ForEach-Object { $_.name })
$dump = 'ANSI=[' + (Show ($ansiNames -join ',')) + '] UTF8=[' + (Show ($utf8Names -join ',')) + ']'

Check 'D1a Windows-1252 .dfm: component names = btn<U>ber, btnPlain (full identifier stored)' `
  (($ansiNames.Count -eq 2) -and ($ansiNames -ccontains $Ueber) -and ($ansiNames -ccontains 'btnPlain')) $dump
Check 'D1b UTF-8+BOM .dfm: component names = btn<U>ber, btn<De><a>, btnPlain' `
  (($utf8Names.Count -eq 3) -and ($utf8Names -ccontains $Ueber) -and ($utf8Names -ccontains $Da) -and ($utf8Names -ccontains 'btnPlain')) $dump
Check 'D1c no .dfm symbol is the ASCII prefix "btn" (the pre-1.2.0 truncation)' `
  (@($rows | Where-Object { $_.name -ceq 'btn' }).Count -eq 0) $dump
Check 'D1d qualified names carry the full identifier (FormAnsi.btn<U>ber, FormUtf8.btn<De><a>)' `
  ((@($ansi | Where-Object { $_.qualified_name -ceq "FormAnsi.$Ueber" }).Count -eq 1) -and (@($utf8 | Where-Object { $_.qualified_name -ceq "FormUtf8.$Da" }).Count -eq 1)) `
  (Show (($rows | ForEach-Object { $_.qualified_name }) -join ','))
Check 'D1e positive control: ASCII names unchanged (forms FormAnsi/FormUtf8, btnPlain in both)' `
  ((@($ansi | Where-Object { $_.kind -eq 'form' -and $_.name -ceq 'FormAnsi' }).Count -eq 1) -and (@($utf8 | Where-Object { $_.kind -eq 'form' -and $_.name -ceq 'FormUtf8' }).Count -eq 1) -and ($ansiNames -ccontains 'btnPlain') -and ($utf8Names -ccontains 'btnPlain')) $dump

$refs = SqlRows $db "select r.name_text, f.path from refs r join files f on f.id=r.file_id where f.path like '%.dfm' and r.kind='event-binding' order by f.path"
Check 'D1f event-binding refs name btn<U>berClick in both .dfm files' `
  ((@($refs | Where-Object { $_.path -like '*FormAnsi.dfm' -and $_.name_text -ceq "${Ueber}Click" }).Count -eq 1) -and (@($refs | Where-Object { $_.path -like '*FormUtf8.dfm' -and $_.name_text -ceq "${Ueber}Click" }).Count -eq 1)) `
  (Show (($refs | ForEach-Object { $_.name_text }) -join ','))

# ---- D2: convert-apply --only finds the block -------------------------------------------------
$Ansi  = [Text.Encoding]::GetEncoding(1252)
$Utf8B = New-Object Text.UTF8Encoding($true)
$libText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures\unitrules\LibA.pas'))
$pasText = "unit Form1;`r`n`r`ninterface`r`n`r`nuses`r`n  Classes, LibA, DstLib;`r`n`r`ntype`r`n  TForm1 = class(TComponent)`r`n    ${Ueber}: TSrcBtn;`r`n    btnPlain: TSrcBtn;`r`n  end;`r`n`r`nimplementation`r`n`r`n{`$R *.dfm}`r`n`r`nend.`r`n"
$dfmText = "object Form1: TForm1`r`n  object ${Ueber}: TSrcBtn`r`n    Caption = '${U}ber'`r`n  end`r`n  object btnPlain: TSrcBtn`r`n    Caption = 'Plain'`r`n  end`r`nend`r`n"
$dstText = "unit DstLib;`r`n`r`ninterface`r`n`r`nuses`r`n  Classes;`r`n`r`ntype`r`n  TNewBtn = class(TPersistent)`r`n  private`r`n    FCaption: string;`r`n  published`r`n    property Caption: string read FCaption write FCaption;`r`n  end;`r`n`r`nimplementation`r`n`r`nend.`r`n"
function NewCase([string]$Name, [Text.Encoding]$Enc) {
  $d = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $d -Force | Out-Null
  [IO.File]::WriteAllText("$d\LibA.pas", $libText, [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText("$d\DstLib.pas", $dstText, [Text.Encoding]::ASCII)
  [IO.File]::WriteAllBytes("$d\Form1.pas", $Enc.GetPreamble() + $Enc.GetBytes($pasText))
  [IO.File]::WriteAllBytes("$d\Form1.dfm", $Enc.GetPreamble() + $Enc.GetBytes($dfmText))
  [IO.File]::WriteAllText("$d\book.rules", "#convert TSrcBtn -> TNewBtn`r`n#link Caption <- Caption`r`n", [Text.Encoding]::ASCII)
  $null | & $Exe index $d --db "$d\fx.sqlite" 2>&1 | Out-Null
  return $d
}
function Apply([string]$Dir, [string]$Only) {
  $o = ($null | & $Exe convert-apply --unit "$Dir\Form1.pas" --rules "$Dir\book.rules" --db "$Dir\fx.sqlite" --format json --only $Only --output-encoding utf8 2>&1) -join "`n"
  $a = $o.IndexOf('{'); $b = $o.LastIndexOf('}')
  $j = $null; if ($a -ge 0 -and $b -gt $a) { try { $j = $o.Substring($a, $b - $a + 1) | ConvertFrom-Json } catch { $j = $null } }
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o; Json = $j }
}
function Located($r, [string]$Name) {
  $j = $r.Json
  return (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and
          (@($j.converted).Count -eq 1) -and ([string]$j.converted[0]).StartsWith("${Name}: TSrcBtn -> TNewBtn") -and
          (@($j.warnings).Count -eq 0) -and
          (@($j.items | Where-Object { $_.kind -eq 'instance-skipped' }).Count -eq 0) -and
          (@($j.only_matched).Count -eq 1) -and ([string]$j.only_matched[0] -ceq $Name) -and
          (@($j.only_unmatched).Count -eq 0))
}
$cA = NewCase 'ansi' $Ansi
$r = Apply $cA $Ueber
Check 'D2a Windows-1252 case: --only btn<U>ber converts it (no "could not locate .dfm object block", no instance-skipped)' (Located $r $Ueber) (Show $r.Out)
$r = Apply $cA 'btnPlain'
Check 'D2b positive control: --only btnPlain converts btnPlain in the same case' (Located $r 'btnPlain') (Show $r.Out)
$cU = NewCase 'utf8bom' $Utf8B
$r = Apply $cU $Ueber
Check 'D2c UTF-8+BOM case: --only btn<U>ber converts it' (Located $r $Ueber) (Show $r.Out)

if ($script:fail) { Write-Host 'run_dfm_nonascii_identifier: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_dfm_nonascii_identifier: PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
