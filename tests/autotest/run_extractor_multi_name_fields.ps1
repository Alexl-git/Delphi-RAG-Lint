<#
  run_extractor_multi_name_fields.ps1 -- 1.39.2: a comma list of names in ONE
  declaration (`A, B: Integer;`) emits a symbol for EVERY name, not only the first.

  THE DEFECT (docs\INBOX-extractor-multi-name-field-list.md, filed by the
  tree-sitter-delphi13 session 2026-10-31): the grammar gives each name its own
  identifier node under the declaration; the extractor took the first one.

  Covers record fields, class fields, class var, unit var,
  routine locals and parameters -- each as a two- or three-name list -- plus two
  directive words used as names (Message, Platform: v1.4.0 grammar).
  CONTROL: the FIRST name of each list is found (it always was).

  Usage: pwsh -File tests/autotest/run_extractor_multi_name_fields.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\drag-lint-multiname-$PID"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  [void][IO.Directory]::CreateDirectory($WorkDir)
  $src = @'
unit MultiName;

interface

type
  TRec = record
    A, B: Integer;
    Message, Platform: string;
  end;

  TCls = class
  private
    FX, FY, FZ: Integer;
    class var CA, CB: Integer;
  public
    procedure Run(P1, P2: Integer);
  end;

var
  GOne, GTwo: Integer;

implementation

procedure TCls.Run(P1, P2: Integer);
var
  LOne, LTwo: Integer;
begin
  LOne:= P1;
  LTwo:= P2;
  FX:= LOne + LTwo;
end;

end.
'@
  [IO.File]::WriteAllText((Join-Path $WorkDir 'MultiName.pas'), ($src -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
  $db = Join-Path $WorkDir 'm.sqlite'
  Push-Location $WorkDir
  try {
    $o = & $Exe index $WorkDir --db $db --library-db none --rule-cache-warm off 2>&1 | Out-String
    Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
    $j = & $Exe sql --db $db --query "SELECT name FROM symbols" --json 2>$null | Out-String
  } finally { Pop-Location }
  $names = @()
  try { $names = @((($j | ConvertFrom-Json).rows) | ForEach-Object { [string]$_[0] }) } catch {}
  Write-Host ("  symbols: {0}" -f (($names | Sort-Object -Unique) -join ','))
  function Has([string]$n) { return [bool]($names | Where-Object { $_ -ceq $n }) }
  foreach ($first in 'A', 'Message', 'FX', 'CA', 'GOne', 'LOne', 'P1') {
    Check "CONTROL first name of its list: $first" (Has $first)
  }
  foreach ($rest in 'B', 'Platform', 'FY', 'FZ', 'CB', 'GTwo', 'LTwo', 'P2') {
    Check "ASSERT later name of its list is emitted too: $rest" (Has $rest)
  }
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
