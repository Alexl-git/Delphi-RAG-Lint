<#
  run_rename_qname_local_hints.ps1 -- IDE-test finding (1.40): rename of a bare
  local name from the plugin dialog.

  Contract, legacy `rename --qname` path:
    * a bare / unqualified name that matches nothing exits 1 and the message
      tells the user to qualify it and lists up to 5 candidate qnames;
    * renaming a ROUTINE-LOCAL symbol (local var / param) prints NO
      "unresolved reference ... not renamed" notes about other units' refs
      to a same-named thing (they can never be that local).
  Positive control: the pre-fix engine prints the foreign note (watched RED).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-qhints-$PID"
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
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
Write-Ascii (Join-Path $src 'Unit1.pas') @'
unit Unit1;

interface

type
  TA = class
  public
    procedure Go;
  end;

implementation

procedure TA.Go;
var
  R: Integer;
begin
  R:= 1;
  Inc(R);
end;

end.
'@
Write-Ascii (Join-Path $src 'Unit2.pas') @'
unit Unit2;

interface

type
  TB = class
  public
    R: Integer;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $src 'Unit3.pas') @'
unit Unit3;

interface

procedure Go;

implementation

uses
  ExtLib;

procedure Go;
begin
  ExtThing.R:= 2;
end;

end.
'@
$db = Join-Path $WorkDir 'fx.sqlite'
Push-Location $WorkDir
try {
  & $Exe index $src --db $db 2>&1 | Out-Null
  Write-Host 'Local target: no foreign unresolved-reference notes' -ForegroundColor Cyan
  $o = (& $Exe rename --qname Unit1.TA.Go.R --to ARect --db $db --dry-run 2>&1) -join "`n"
  Check 'local rename exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE out=$o"
  Check 'local rename finds the edits' ($o -match 'Dry run: [1-9]') $o
  Check 'no unresolved-reference note for a routine-local target' ($o -notmatch 'unresolved reference') $o
  Write-Host 'Bare name: message says to qualify, lists candidates' -ForegroundColor Cyan
  $o = (& $Exe rename --qname R --to ARect --db $db --dry-run 2>&1) -join "`n"
  Check 'bare name exits 1' ($LASTEXITCODE -eq 1) "exit=$LASTEXITCODE"
  Check 'message keeps the No edits computed prefix' ($o -match 'No edits computed for R') $o
  Check 'message says to qualify' ($o -match 'qualif') $o
  Check 'message lists the local candidate qname' ($o -match 'Unit1\.TA\.Go\.R') $o
  Check 'message lists the field candidate qname' ($o -match 'Unit2\.TB\.R') $o
  Write-Host 'Unknown qualified name: no candidates, original message' -ForegroundColor Cyan
  $o = (& $Exe rename --qname Unit1.TA.Nope --to X --db $db --dry-run 2>&1) -join "`n"
  Check 'unknown qname exits 1' ($LASTEXITCODE -eq 1) "exit=$LASTEXITCODE"
  Check 'unknown qname message intact' ($o -match 'No edits computed for Unit1\.TA\.Nope \(symbol may not exist\)') $o
} finally { Pop-Location }
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
