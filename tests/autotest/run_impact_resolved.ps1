<#
  run_impact_resolved.ps1 -- #38: `impact` counts callers over the RESOLVED
  call graph.

  The old walk matched refs by NAME TEXT and took as the "caller" every symbol
  whose DECLARATION range held the ref's line. A ref inside an implementation
  body lies in no routine's declaration range, only in the unit's, so level 1
  counted units, and level 2 followed refs to the unit NAMES (the uses
  clauses). Found on ProjectA: UConfig.SaveResult, 22 direct callers, reported
  "21 callers in 21 units" and then "7 callers" at depth 2 against 30 real ones.

  Fixture (two units):
    uCore.TStore.Save           <- target
    uCore.TOther.Save           <- same NAME, different routine: must not count
    uApp.TSvc.Run               calls Store.Save          (depth 1)
    uApp.TSvc.RunTwice          calls Store.Save twice    (depth 1, counted once)
    uApp.TSvc.Go                calls Run and RunTwice    (depth 2)
    uApp.Main                   calls Go                  (depth 3)
    uApp.TSvc.Other             calls an TOther.Save only (never counted)

  Expected: depth 1 = 2 callers in 1 unit, depth 2 = 1, depth 3 = 1, total 4;
  `--depth 1` stops after level 1; an unknown qname exits 1.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-impact-resolved-$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$Core = @'
unit uCore;

interface

type
  TStore = class
  public
    procedure Save(const S: string);
  end;

  TOther = class
  public
    procedure Save(const S: string);
  end;

implementation

procedure TStore.Save(const S: string);
begin
end;

procedure TOther.Save(const S: string);
begin
end;

end.
'@
$App = @'
unit uApp;

interface

uses uCore;

type
  TSvc = class
  private
    FStore: TStore;
    FOther: TOther;
  public
    procedure Run;
    procedure RunTwice;
    procedure Go;
    procedure Other;
  end;

procedure Main(ASvc: TSvc);

implementation

procedure TSvc.Run;
begin
  FStore.Save('a');
end;

procedure TSvc.RunTwice;
begin
  FStore.Save('b');
  FStore.Save('c');
end;

procedure TSvc.Go;
begin
  Run;
  RunTwice;
end;

procedure TSvc.Other;
begin
  FOther.Save('d');
end;

procedure Main(ASvc: TSvc);
begin
  ASvc.Go;
end;

end.
'@
$dir = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null
foreach ($p in @(@('uCore.pas', $Core), @('uApp.pas', $App))) {
  $norm = $p[1] -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText((Join-Path $dir $p[0]), $norm, [System.Text.Encoding]::ASCII)
}
$db = Join-Path $dir 'fx.sqlite'

Push-Location $WorkDir
try {
  $indexOut = & $Exe index $dir --db $db 2>&1
  $indexExit = $LASTEXITCODE
  Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut | Select-Object -Last 1)"

  $raw = & $Exe impact --qname uCore.TStore.Save --depth 5 --db $db --format json 2>$null | Out-String
  $exit = $LASTEXITCODE
  Check 'impact --format json exits 0' ($exit -eq 0) "exit=$exit"
  $doc = $null
  try { $doc = $raw | ConvertFrom-Json } catch { }
  Check 'and prints one JSON document' ($null -ne $doc) $raw
  if ($doc) {
    $lv = @{}
    foreach ($l in $doc.levels) { $lv[[int]$l.depth] = $l }
    Check 'depth 1: Run and RunTwice -- 2 callers (RunTwice once), not TSvc.Other' ($lv[1].callers -eq 2) "got=$($lv[1].callers)"
    Check 'depth 1: in 1 unit' ($lv[1].units -eq 1) "got=$($lv[1].units)"
    Check 'depth 2: Go -- 1 caller' ($lv[2].callers -eq 1) "got=$($lv[2].callers)"
    Check 'depth 3: Main -- 1 caller' ($lv[3].callers -eq 1) "got=$($lv[3].callers)"
    Check 'no depth 4 (Main has no caller)' (-not $lv.ContainsKey(4)) "levels=$($doc.levels | ConvertTo-Json -Compress)"
  }

  $txt = & $Exe impact --qname uCore.TStore.Save --depth 5 --db $db 2>$null
  Check 'text output gives the total of the levels' (($txt -join "`n") -match 'Total: 4 callers') ($txt -join ' | ')

  $raw1 = & $Exe impact --qname uCore.TStore.Save --depth 1 --db $db --format json 2>$null | Out-String
  $doc1 = $null
  try { $doc1 = $raw1 | ConvertFrom-Json } catch { }
  Check '--depth 1 stops after level 1' (($null -ne $doc1) -and (@($doc1.levels).Count -eq 1)) $raw1

  $null = & $Exe impact --qname uCore.TOther.Save --depth 3 --db $db 2>$null
  $oExit = $LASTEXITCODE
  $rawO = & $Exe impact --qname uCore.TOther.Save --depth 3 --db $db --format json 2>$null | Out-String
  $docO = $null
  try { $docO = $rawO | ConvertFrom-Json } catch { }
  Check 'TOther.Save: only TSvc.Other at depth 1' (($null -ne $docO) -and ($docO.levels[0].callers -eq 1)) $rawO
  Check 'TOther.Save exits 0' ($oExit -eq 0) "exit=$oExit"

  $null = & $Exe impact --qname uCore.TStore.Missing --depth 3 --db $db 2>$null
  $mExit = $LASTEXITCODE
  Check 'an unknown qname answers "no callers", exit 1' ($mExit -eq 1) "exit=$mExit"
} finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
