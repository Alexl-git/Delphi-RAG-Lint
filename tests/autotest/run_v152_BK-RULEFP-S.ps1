<#
  run_v152_BK-RULEFP-S.ps1 -- 1.52 lane BK-RULEFP-S: lint-rule false-positive fixes.
    B02  used-before-assignment: `on E:` read vs a later inline `var E` (fixture tests\lint\used-before-assignment-on-e-inline-var.pas)
    B35  dfm-duplicate-binding: the code-bound skip reads the paired unit's AST (assignment targets), not a text scan:
         a receiver-qualified `Other.edtB.DataField :=` no longer silences this form's edtB; bare, Self.-qualified
         and DataBinding.DataField assignments still do.
  Every guard has a must-fire control. Usage: pwsh -File run_v152_BK-RULEFP-S.ps1 [-Exe <drag-lint.exe>]
  Exit code = number of failed checks.
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
$Exe = (Resolve-Path $Exe).Path
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v152-bkrfps-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Force $Work)
$Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { $script:Fail++; Write-Host "FAIL  $Name  $Detail" }
}
function WriteAscii([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
function Hits([string]$File, [string]$Rule, [string[]]$Extra = @()) {
  Push-Location (Split-Path $File)
  try { $o = & { $ErrorActionPreference = 'Continue'; & $Exe lint $File --json --rule $Rule @Extra 2>$null } } finally { Pop-Location }
  $t = ($o -join "`n").Trim()
  if ($t -eq '') { return @() }
  $j = $t | ConvertFrom-Json
  @(@($j) | Where-Object { $_.rule -eq $Rule } | ForEach-Object { [int]$_.start_line })
}
try {
  # ---- B02 ----
  $fx = Join-Path $Root 'tests\lint\used-before-assignment-on-e-inline-var.pas'
  $h = @(Hits $fx 'used-before-assignment')
  Check 'B02 positive control: plain unassigned local (line 37) fires' ($h -contains 37) "hits=$($h -join ',')"
  Check 'B02 `on E:` read (line 27) before a later inline var E is silent' ($h -notcontains 27) "hits=$($h -join ',')"

  # ---- B35 ----
  $form = @(
    'object Form1: TForm1',
    '  object dsA: TDataSource',
    '    DataSet = tblA',
    '  end',
    '  object tblA: TFDTable',
    '  end',
    '  object edtA: TDBEdit',
    '    DataSource = dsA',
    '    DataField = ''Fld''',
    '  end',
    '  object edtB: TDBEdit',
    '    DataSource = dsA',
    '    DataField = ''Fld''',
    '  end',
    'end')
  function MakeUnit([string]$Name, [string[]]$Body) {
    $d = Join-Path $Work $Name; [void](New-Item -ItemType Directory -Force $d)
    WriteAscii (Join-Path $d "$Name.dfm") $form
    WriteAscii (Join-Path $d "$Name.pas") (@("unit $Name;", '', 'interface', '', 'type', '  TForm1 = class', '  end;', '',
      'implementation', '', '{$R *.dfm}', '', 'procedure Rebind;', 'begin') + $Body + @('end;', '', 'end.'))
    Join-Path $d "$Name.pas"
  }
  $p = MakeUnit 'FxNone' @('  Beep;')
  Check 'B35 positive control: no assignment -> duplicate fires' ((@(Hits $p 'dfm-duplicate-binding')).Count -eq 1)
  $p = MakeUnit 'FxBare' @('  edtB.DataField:= ''X'';')
  Check 'B35 bare edtB.DataField := silences' ((@(Hits $p 'dfm-duplicate-binding')).Count -eq 0)
  $p = MakeUnit 'FxSelf' @('  Self.edtB.DataField:= ''X'';')
  Check 'B35 Self.edtB.DataField := silences' ((@(Hits $p 'dfm-duplicate-binding')).Count -eq 0)
  $p = MakeUnit 'FxOther' @('  OtherForm.edtB.DataField:= ''X'';')
  Check 'B35 OtherForm.edtB.DataField := (another instance) does NOT silence' ((@(Hits $p 'dfm-duplicate-binding')).Count -eq 1)
  $p = MakeUnit 'FxNoise' @('  // edtB.DataField:= ''X'';', '  Writeln(''edtB.DataField:= 1'');')
  Check 'B35 comment / string mentions do NOT silence' ((@(Hits $p 'dfm-duplicate-binding')).Count -eq 1)
}
finally {
  [IO.Directory]::Delete($Work, $true)
}
Write-Host "failed=$Fail"
exit $Fail
