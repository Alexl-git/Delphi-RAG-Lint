<#
  run_v1511_DOCLINT_missingdoc.ps1 -- 1.51.1 DOCLINT lane (R2, R7, B20).

  R2  missing-doc skips (a) Get<X>/Set<X> of a DOCUMENTED property X, (b) an `override`,
      (c) a method a .dfm binds to an event. POSITIVE CONTROLS: an undocumented plain
      method, and a Get<Y> whose property Y is NOT documented, still report.
  R7  a grouped `<param name="S, WordDelims">` / `var Pos` tag names real params: lint
      reports no doc-param-not-in-signature / doc-drift for them. CONTROL: a true orphan
      tag still reports as an error.
  B20 an attribute argument above a parameterless method is not a param (no doc-drift).
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-doclint1511-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$src = Join-Path $WorkDir 'doclint1511.pas'
$dfm = Join-Path $WorkDir 'doclint1511.dfm'
$db  = Join-Path $WorkDir 'doclint1511.sqlite'
$lines = @(
  'unit doclint1511;', '', 'interface', '', 'type',
  '  /// <summary>Base.</summary>',
  '  TBase = class',
  '  public',
  '    /// <summary>Releases.</summary>',
  '    destructor Destroy; override;',
  '  end;', '',
  '  /// <summary>Holder.</summary>',
  '  THolder = class(TBase)',
  '  public',
  '    function GetDocd: Integer;',
  '    procedure SetDocd(const Value: Integer);',
  '    function GetBare: Integer;',
  '  public',
  '    destructor Destroy; override;',
  '    procedure PlainNoDoc;',
  '    procedure btnGoClick(Sender: TObject);',
  '    /// <summary>The documented value.</summary>',
  '    property Docd: Integer read GetDocd write SetDocd;',
  '    property Bare: Integer read GetBare;',
  '  end;', '',
  '/// <summary>Position of a word.</summary>',
  '/// <param name="N"> (cardinal) </param>',
  '/// <param name="S, WordDelims"> (string) </param>',
  '/// <param name="var Pos"> (cardinal) </param>',
  'function WordPosition(const N: cardinal; const S, WordDelims: string; var Pos: cardinal): Boolean;', '',
  '/// <summary>Cell value.</summary>',
  '/// <param name="AView"> (view) </param>',
  '/// <param name="AGone"> (gone) </param>',
  'function CellValue(AView: Integer): Double;', '',
  'type', '  TFx = class', '  public',
  '    /// <summary>Attribute argument is not a parameter.</summary>',
  "    [Test] [Ignore('awaits Task 4 reader (doc section 8)')]",
  '    procedure StoredLayout;', '  end;', '',
  'implementation', '',
  'destructor TBase.Destroy;', 'begin', 'end;', '',
  'function THolder.GetDocd: Integer;', 'begin', '  Result:= 0;', 'end;', '',
  'procedure THolder.SetDocd(const Value: Integer);', 'begin', 'end;', '',
  'function THolder.GetBare: Integer;', 'begin', '  Result:= 0;', 'end;', '',
  'destructor THolder.Destroy;', 'begin', 'end;', '',
  'procedure THolder.PlainNoDoc;', 'begin', 'end;', '',
  'procedure THolder.btnGoClick(Sender: TObject);', 'begin', 'end;', '',
  'function WordPosition(const N: cardinal; const S, WordDelims: string; var Pos: cardinal): Boolean;', 'begin', '  Result:= True;', 'end;', '',
  'function CellValue(AView: Integer): Double;', 'begin', '  Result:= 0;', 'end;', '',
  'procedure TFx.StoredLayout;', 'begin', 'end;', '', 'end.')
[IO.File]::WriteAllText($src, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$srcB = Join-Path $WorkDir 'doclint1511b.pas'
$lb = @('unit doclint1511b;', '', 'interface', 'type', '  /// <summary>Other.</summary>', '  TOther = class', '  public', '    procedure btnGoClick(Sender: TObject);', '  end;', '', 'implementation', '', 'procedure TOther.btnGoClick(Sender: TObject);', 'begin', 'end;', '', 'end.')
[IO.File]::WriteAllText($srcB, (($lb -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$dl = @('object Holder: THolder', '  OnClick = btnGoClick', 'end')
[IO.File]::WriteAllText($dfm, (($dl -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

function RowsOf([string]$o) { $r = @(); try { $r = @($o | ConvertFrom-Json) } catch { $r = @() }; return ,$r }
function At($rows, [string]$rule, [int]$line) { @($rows | Where-Object { $_.rule -eq $rule -and $_.start_line -eq $line }) }
Push-Location $WorkDir
try {
  & $Exe index $WorkDir --db $db --library-db none 2>&1 | Out-Null
  $la = (& $Exe lint-all --db $db --json --enable missing-doc --library-db none 2>$null | Out-String)
  $rows = RowsOf $la
  Check 'SANITY: lint-all JSON parsed' ($rows.Count -ge 1) $la
  Check 'R2a: GetDocd not missing-doc'  (@(At $rows 'missing-doc' 16).Count -eq 0)
  Check 'R2a: SetDocd not missing-doc'  (@(At $rows 'missing-doc' 17).Count -eq 0)
  Check 'R2a+ CONTROL: GetBare (undocumented property) still missing-doc' (@(At $rows 'missing-doc' 18).Count -ge 1) $la
  Check 'R2b: override Destroy not missing-doc' (@(At $rows 'missing-doc' 20).Count -eq 0)
  Check 'R2+ CONTROL: PlainNoDoc still missing-doc' (@(At $rows 'missing-doc' 21).Count -ge 1) $la
  Check 'R2c: dfm-bound btnGoClick not missing-doc' (@(At $rows 'missing-doc' 22).Count -eq 0)
  $r7 = @($rows | Where-Object { $_.rule -in @('doc-param-not-in-signature', 'doc-drift') -and $_.message -match 'WordDelims|Pos|"S"' })
  $o = @($rows | Where-Object { $_.rule -eq 'missing-doc' -and $_.start_line -eq 8 -and $_.file_path -like '*doclint1511b.pas' })
  Check 'R2c+ CONTROL: same-named handler in an unrelated unit (no .dfm) still missing-doc' ($o.Count -ge 1) $la
  Check 'R7: grouped / var-prefixed tags raise nothing' ($r7.Count -eq 0) ($r7 | ConvertTo-Json -Compress)
  $g = @($rows | Where-Object { $_.rule -eq 'doc-param-not-in-signature' -and $_.message -match 'AGone' })
  Check 'R7+ CONTROL: true orphan AGone still an error' ($g.Count -ge 1) $la
  $b = @($rows | Where-Object { $_.rule -eq 'doc-drift' -and $_.message -match 'Ignore|awaits' })
  Check 'B20: attribute argument is not a param' ($b.Count -eq 0) ($b | ConvertTo-Json -Compress)
} finally { Pop-Location }
Write-Host ("{0} PASS" -f $script:Passed)
if (-not $script:Failed -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { exit 1 }
