<#
  run_context_resolved_callers.ps1 -- #40: the `context` bundle lists the
  call sites the resolved call graph binds to the routine, not every ref that
  spells its last name segment.

  The bundle took its callers from FindCallersByNameWithContext(<last segment>),
  so a task on a method with a common name listed every same-named member
  anywhere. Found on ProjectA: `context --task "modify UConfig.TConfig.Report"`
  filled its 200-row cap from 663 `Report` refs (aRD.Report.Headless, a
  property of another class, first) while 103 sites are bound to TConfig.Report.

  Fixture: uCore declares TStore.Save and TOther.Save; uApp calls
  FStore.Save three times (Run once, RunTwice twice) and FOther.Save once.
  Expected for "modify uCore.TStore.Save": 3 callers, none on the FOther line;
  for "modify uCore.TOther.Save": 1 caller, the FOther line.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-context-resolved-callers-$PID"
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
    procedure Other;
  end;

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

procedure TSvc.Other;
begin
  FOther.Save('d');
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
$otherLine = 33   # FOther.Save('d') in uApp.pas

Push-Location $WorkDir
try {
  $indexOut = & $Exe index $dir --db $db 2>&1
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut | Select-Object -Last 1)"

  $raw = & $Exe context --task 'modify uCore.TStore.Save' --db $db --format json --no-docs 2>$null | Out-String
  $doc = $null
  try { $doc = $raw | ConvertFrom-Json } catch { }
  Check 'TStore.Save: the bundle resolves' (($null -ne $doc) -and $doc.resolved) $raw
  Check 'TStore.Save: 3 callers (Run once, RunTwice twice), not the FOther.Save site' (($null -ne $doc) -and ($doc.caller_count -eq 3)) "caller_count=$($doc.caller_count)"

  $md = (& $Exe context --task 'modify uCore.TStore.Save' --db $db --format markdown --no-docs 2>$null) -join "`n"
  Check 'TStore.Save markdown: no caller on the FOther line' (-not ($md -match "uApp\.pas:$otherLine\b")) ''
  Check 'TStore.Save markdown: lists the Run site (line 22)' ($md -match 'uApp\.pas:22\b') ''

  $rawO = & $Exe context --task 'modify uCore.TOther.Save' --db $db --format json --no-docs 2>$null | Out-String
  $docO = $null
  try { $docO = $rawO | ConvertFrom-Json } catch { }
  Check 'TOther.Save: exactly 1 caller' (($null -ne $docO) -and ($docO.caller_count -eq 1)) "caller_count=$($docO.caller_count)"
  $mdO = (& $Exe context --task 'modify uCore.TOther.Save' --db $db --format markdown --no-docs 2>$null) -join "`n"
  Check 'TOther.Save markdown: the caller is the FOther line' ($mdO -match "uApp\.pas:$otherLine\b") ''
} finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
