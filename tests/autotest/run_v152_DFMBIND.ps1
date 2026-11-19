<#
  run_v152_DFMBIND.ps1 -- 1.52 lane DFMBIND: dfm-duplicate-binding skips an editor whose DataField
  (directly or through DataBinding.DataField) the OWNING unit assigns in code (ORM3 Blueprint4:
  edtF1..edtF5 carry placeholder DataField values in the form file and are rebound at run time).

  Fixtures (each a form + unit in its own folder):
    A  3 duplicate editors, the unit assigns all three            -> 0 dfm-duplicate-binding findings
    B  the twin form, no assignments in the unit                  -> 2 findings (every duplicate fires)
    C  no assignments in the unit, ANOTHER unit assigns them      -> 2 findings (other unit does not silence)
    D  only the first editor assigned; two unassigned duplicates  -> 1 finding (the unassigned pair still fires)
    E  assignments only inside comments / strings                 -> 2 findings (noise is ignored)
  B, C, D and E are the positive controls of A: the rule is on and the fixture shape does fire.

  Usage: pwsh -File tests\autotest\run_v152_DFMBIND.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v152-dfmbind-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Force $Work)
$Pass = 0; $Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}
function WriteAscii([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
function FormLines() {
  return @(
    'object Form1: TForm1',
    '  object dsA: TDataSource',
    '    DataSet = tblA',
    '  end',
    '  object tblA: TFDTable',
    '  end',
    '  object edtF1: TDBEdit',
    '    DataSource = dsA',
    '    DataField = ''WrkOrdrNmbr''',
    '  end',
    '  object edtF2: TcxDBTextEdit',
    '    DataBinding.DataSource = dsA',
    '    DataBinding.DataField = ''WrkOrdrNmbr''',
    '  end',
    '  object edtF3: TDBEdit',
    '    DataSource = dsA',
    '    DataField = ''WrkOrdrNmbr''',
    '  end',
    'end')
}
function MakeUnit([string]$Dir, [string]$Unit, [string[]]$Body) {
  [void](New-Item -ItemType Directory -Force $Dir)
  WriteAscii (Join-Path $Dir "$Unit.dfm") (FormLines)
  $Src = @("unit $Unit;", '', 'interface', '', 'type', '  TForm1 = class', '  end;', '',
           'implementation', '', '{$R *.dfm}', '', 'procedure Rebind;', 'begin') + $Body + @('end;', '', 'end.')
  WriteAscii (Join-Path $Dir "$Unit.pas") $Src
}
function DupCount([string]$Dir, [string]$Unit) {
  $Pas = Join-Path $Dir "$Unit.pas"
  Push-Location $Dir
  try { $Out = & { $ErrorActionPreference = 'Continue'; & $Exe lint $Pas --json 2>$null } } finally { Pop-Location }
  $Txt = ($Out -join "`n")
  if ($Txt.Trim() -eq '') { return 0 }
  $J = $Txt | ConvertFrom-Json
  $All = if ($J -is [array]) { @($J) } elseif ($null -ne $J.findings) { @($J.findings) } else { @($J) }
  return @($All | Where-Object { ([string]$_.rule_id + [string]$_.rule) -eq 'dfm-duplicate-binding' }).Count
}

try {
  MakeUnit "$Work\A" 'FxA' @(
    '  edtF1.DataSource:= DS;', '  edtF1.DataField:= Fields[0];',
    '  edtF2.DataBinding.DataSource:= DS;', '  edtF2.DataBinding.DataField:= Fields[1];',
    '  Self.edtF3.DataField:= Fields[2];')
  MakeUnit "$Work\B" 'FxB' @('  Beep;')
  MakeUnit "$Work\C" 'FxC' @('  Beep;')
  WriteAscii "$Work\C\Other.pas" @('unit Other;', 'interface', 'implementation', 'procedure Rebind2;', 'begin',
    '  edtF1.DataField:= ''X'';', '  edtF2.DataBinding.DataField:= ''Y'';', '  edtF3.DataField:= ''Z'';', 'end;', 'end.')
  MakeUnit "$Work\D" 'FxD' @('  edtF1.DataField:= Fields[0];')
  MakeUnit "$Work\E" 'FxE' @(
    '  // edtF1.DataField:= ''X'';',
    '  { edtF2.DataBinding.DataField:= ''Y''; }',
    '  Memo.Add(''edtF3.DataField:= Z'');')

  $a = DupCount "$Work\A" 'FxA'; Check 'A: all editors assigned in code -> silent' ($a -eq 0) "got $a"
  $b = DupCount "$Work\B" 'FxB'; Check 'B (control): twin without assignments -> 2 findings' ($b -eq 2) "got $b"
  $c = DupCount "$Work\C" 'FxC'; Check 'C: assignment in ANOTHER unit does not silence -> 2' ($c -eq 2) "got $c"
  $d = DupCount "$Work\D" 'FxD'; Check 'D: only edtF1 assigned -> edtF2/edtF3 pair still fires (1)' ($d -eq 1) "got $d"
  $e = DupCount "$Work\E" 'FxE'; Check 'E: assignments in comments/strings do not silence -> 2' ($e -eq 2) "got $e"
} finally {
  Write-Host "dfmbind: $Pass passed, $Fail failed"
}
if ($Fail -gt 0) { exit 1 } else { exit 0 }
