<#
  run_convert_apply_dfm_facts.ps1 -- wave 150 lane CF, item 2: convert-apply reads
  the dfm_objects fact table (149 EX2 F5) to find the DECLARING ancestor of an
  inherited component, the text scan of the ancestor .dfm staying the fallback.

  THE CONTRACT this guard pins (DfmDeclaresComponentVia in DRagLint.Convert.Apply):
    ID1  `convert-apply --format json` stdout is BYTE-IDENTICAL between the table
         path (default) and the text path (DRAGLINT_NO_FILE_FACTS=1) on three
         chains: an ASCII chain (BaseForm / MidForm / ChildForm), a Windows-1252
         .dfm with a non-ASCII component name (no BOM) and a UTF-8-with-BOM .dfm
         with non-ASCII names (the encodings of tests\fixtures\dfm-nonascii).
    ON1  the default run answers from the table: stderr (DRAGLINT_DEBUG=1) carries
         `[dfm-facts] table` lines and no `[dfm-facts] text` line for the chain.
    OFF1 DRAGLINT_NO_FILE_FACTS=1 answers by the scan: `[dfm-facts] text` lines, no
         `[dfm-facts] table` line.
    STALE1 an ancestor .dfm edited after the index (same size, newer content) is NOT
         answered from the table: the run falls back to the scan and reports the
         edited text's class (the table's answer would be the old class).
  Positive control: on an engine without the reader (the 1.49.0-alpha base) ON1
  FAILS (no `[dfm-facts]` line at all) and OFF1 FAILS the same way.

  Fixture written fresh under a scratch folder and indexed into a scratch --db there.
  This file is ASCII: the non-ASCII bytes are built from code points below.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-apply-dfm-facts-$PID"
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_convert_apply_dfm_facts: needs pwsh 7' -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$ansi = [Text.Encoding]::GetEncoding(1252)
$utf8bom = New-Object Text.UTF8Encoding($true)
function P([string]$n) { Join-Path $WorkDir $n }
function Put([string]$Path, [string]$Body, [Text.Encoding]$Enc) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), $Enc)
}
$uml = [string][char]0xDC          # U+00DC, a 1-byte letter in Windows-1252
$cyr = [string][char]0x0434        # U+0434, 2 bytes in UTF-8

Put (P 'LibA.pas') @'
unit LibA;

interface

uses
  Classes;

type
  TSrcA = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@ $ansi
Put (P 'LibB.pas') @'
unit LibB;

interface

uses
  Classes;

type
  TDstB = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@ $ansi
Put (P 'plain.rules') @'
#convert LibA.TSrcA -> LibB.TDstB, LibB
#link Caption <- Caption
'@ $ansi

# ---- chain 1: ASCII ---------------------------------------------------------
Put (P 'BaseForm.pas') @'
unit BaseForm;

interface

uses
  Classes, Forms, LibA;

type
  TBaseForm = class(TForm)
    btnA: TSrcA;
    btnB: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@ $ansi
Put (P 'BaseForm.dfm') @'
object BaseForm: TBaseForm
  object btnA: TSrcA
    Caption = 'A'
  end
  object btnB: TSrcA
    Caption = 'B'
  end
end
'@ $ansi
Put (P 'MidForm.pas') @'
unit MidForm;

interface

uses
  Classes, Forms, LibA, BaseForm;

type
  TMidForm = class(TBaseForm)
  end;

implementation

{$R *.dfm}

end.
'@ $ansi
Put (P 'MidForm.dfm') @'
inherited MidForm: TMidForm
  inherited btnA: TSrcA
    Caption = 'mid'
  end
end
'@ $ansi
Put (P 'ChildForm.pas') @'
unit ChildForm;

interface

uses
  Classes, Forms, LibA, MidForm;

type
  TChildForm = class(TMidForm)
    btnOwn: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@ $ansi
Put (P 'ChildForm.dfm') @'
inherited ChildForm: TChildForm
  inherited btnA: TSrcA
    Caption = 'child'
  end
  inherited btnB: TSrcA
    Caption = 'childB'
  end
  object btnOwn: TSrcA
    Caption = 'own'
  end
end
'@ $ansi

# ---- chain 2: Windows-1252 .dfm / .pas, non-ASCII component name -------------
$nm = "btn${uml}ber"
Put (P 'AnsiBase.pas') @"
unit AnsiBase;

interface

uses
  Classes, Forms, LibA;

type
  TAnsiBase = class(TForm)
    ${nm}: TSrcA;
  end;

implementation

{`$R *.dfm}

end.
"@ $ansi
Put (P 'AnsiBase.dfm') @"
object AnsiBase: TAnsiBase
  object ${nm}: TSrcA
    Caption = 'U'
  end
end
"@ $ansi
Put (P 'AnsiChild.pas') @"
unit AnsiChild;

interface

uses
  Classes, Forms, LibA, AnsiBase;

type
  TAnsiChild = class(TAnsiBase)
  end;

implementation

{`$R *.dfm}

end.
"@ $ansi
Put (P 'AnsiChild.dfm') @"
inherited AnsiChild: TAnsiChild
  inherited ${nm}: TSrcA
    Caption = 'c'
  end
end
"@ $ansi

# ---- chain 3: UTF-8 with BOM, Cyrillic + umlaut names ------------------------
$nm2 = "btn${uml}ber"
$nm3 = "btn${cyr}"
Put (P 'UBase.pas') @"
unit UBase;

interface

uses
  Classes, Forms, LibA;

type
  TUBase = class(TForm)
    ${nm2}: TSrcA;
    ${nm3}: TSrcA;
  end;

implementation

{`$R *.dfm}

end.
"@ $utf8bom
Put (P 'UBase.dfm') @"
object UBase: TUBase
  object ${nm2}: TSrcA
    Caption = 'U'
  end
  object ${nm3}: TSrcA
    Caption = 'D'
  end
end
"@ $utf8bom
Put (P 'UChild.pas') @"
unit UChild;

interface

uses
  Classes, Forms, LibA, UBase;

type
  TUChild = class(TUBase)
  end;

implementation

{`$R *.dfm}

end.
"@ $utf8bom
Put (P 'UChild.dfm') @"
inherited UChild: TUChild
  inherited ${nm2}: TSrcA
    Caption = 'c'
  end
  inherited ${nm3}: TSrcA
    Caption = 'd'
  end
end
"@ $utf8bom

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx[-1])"

# One convert-apply --format json run; raw stdout bytes + stderr text.
function Run-Apply([string]$Unit, [bool]$Off, [string]$Db) {
  $o = P ("out-{0}-{1}.bin" -f $Unit, [int]$Off)
  $e = P ("err-{0}-{1}.txt" -f $Unit, [int]$Off)
  $env:DRAGLINT_DEBUG = '1'
  if ($Off) { $env:DRAGLINT_NO_FILE_FACTS = '1' } else { $env:DRAGLINT_NO_FILE_FACTS = $null }
  try {
    $p = Start-Process -FilePath $Exe -ArgumentList @('convert-apply', '--unit', (P "$Unit.pas"), '--rules', (P 'plain.rules'), '--db', $Db, '--format', 'json') `
      -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  } finally {
    $env:DRAGLINT_DEBUG = $null
    $env:DRAGLINT_NO_FILE_FACTS = $null
  }
  $errText = if (Test-Path $e) { [IO.File]::ReadAllText($e) } else { '' }
  $bytes = if (Test-Path $o) { [IO.File]::ReadAllBytes($o) } else { [byte[]]@() }
  [pscustomobject]@{
    Code = $p.ExitCode; Bytes = $bytes; Err = $errText
    Table = ([regex]::Matches($errText, '\[dfm-facts\] table')).Count
    Text  = ([regex]::Matches($errText, '\[dfm-facts\] text')).Count
    Hash  = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bytes))
  }
}

foreach ($u in @('ChildForm', 'AnsiChild', 'UChild')) {
  $on  = Run-Apply $u $false $db
  $off = Run-Apply $u $true  $db
  Check "$u the run produced a plan (non-empty stdout, exit 0)" (($on.Bytes.Length -gt 200) -and ($on.Code -eq 0)) "exit=$($on.Code) bytes=$($on.Bytes.Length)"
  $txt = [Text.Encoding]::UTF8.GetString($on.Bytes)
  Check "$u the plan names inherited instances (the walk ran)" ($txt -match '"inherited"\s*:\s*\[\s*\{') ''
  Check "$u ID1 stdout byte-identical, table path vs text path" (($on.Hash -eq $off.Hash) -and ($on.Bytes.Length -eq $off.Bytes.Length)) "on=$($on.Bytes.Length)B off=$($off.Bytes.Length)B"
  Check "$u ON1 default run answered from dfm_objects" (($on.Table -gt 0) -and ($on.Text -eq 0)) "table=$($on.Table) text=$($on.Text)"
  Check "$u OFF1 DRAGLINT_NO_FILE_FACTS=1 answered by the scan" (($off.Table -eq 0) -and ($off.Text -gt 0)) "table=$($off.Table) text=$($off.Text)"
  # the resolved ancestor must really be found (a vacuous identity of two 'not found' answers proves nothing)
  Check "$u the declaring ancestor was found" ($txt -match '"ancestor_state"\s*:\s*"unconverted"') ''
}

# STALE1: edit BaseForm.dfm after the index (btnB: TSrcA -> TDstB, same length) -> table must NOT answer.
$bd = [IO.File]::ReadAllText((P 'BaseForm.dfm'))
Put (P 'BaseForm.dfm') ($bd.Replace('object btnB: TSrcA', 'object btnB: TDstB')) $ansi
$st = Run-Apply 'ChildForm' $false $db
$stTxt = [Text.Encoding]::UTF8.GetString($st.Bytes)
Check 'STALE1 an ancestor edited after the index falls back to the scan' (($st.Text -gt 0) -and ($st.Err -match '\[dfm-facts\] text BaseForm\.dfm btnB')) "table=$($st.Table) text=$($st.Text)"
Check 'STALE1 the plan reports the EDITED class, not the indexed one' ($stTxt -match 'declared in BaseForm as TDstB|declared in BaseForm, which already has TDstB') $stTxt.Substring(0, [Math]::Min(300, $stTxt.Length))

try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (scratch not removed: $WorkDir)" }
if ($script:Failed) { Write-Host 'run_convert_apply_dfm_facts: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_convert_apply_dfm_facts: all checks passed' -ForegroundColor Green
exit 0
