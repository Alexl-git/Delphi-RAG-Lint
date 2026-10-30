<#
  run_impl_header_type_refs.ps1 -- #39: every implementation header emits
  type_use refs for its parameter and return types.

  Only a METHOD implementation header (TClass.Method) walked its 'args' and
  'type' fields (Ref-gap E). A free routine declared in the interface, a free
  routine that exists only in the implementation, and a nested routine emitted
  no type_use for their header types, so `usages` and a type rename missed them.
  Found on ProjectA: ULabelReport.PrintLabel (ConfigKind: TConfig) and the nested
  UFRetry.TFRetry.ConfirmRetry._GetCfg (const aCfg: TConfig).

  Fixture lines holding TFoo in a header:
     8  method declaration          (already covered)
    11  free routine declaration    (already covered)
    15  free routine implementation          <- new
    19  implementation-only free routine: param AND return type (2 refs) <- new
    21  nested routine param                 <- new
    29  method implementation       (already covered)

  RED on 1.20.0-alpha: no TFoo ref on lines 15, 19, 21. Needs python on PATH
  for the direct DB read; SKIP without it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-impl-header-type-refs-$PID"
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
$Python = (Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $Python) {
  Write-Host 'SKIP: python is not on PATH; this runner reads the refs table straight from the DB'
  exit 77
}
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$FixtureBody = @'
unit uTr;

interface

type
  TFoo = class end;
  TBar = class
    procedure M(a: TFoo);
  end;

procedure Pub(a: TFoo);

implementation

procedure Pub(a: TFoo);
begin
end;

function Priv(a: TFoo): TFoo;

  procedure Nest(b: TFoo);
  begin
  end;

begin
  Result := a;
end;

procedure TBar.M(a: TFoo);
begin
end;

end.
'@
$dir  = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null
$file = Join-Path $dir 'uTr.pas'
$db   = Join-Path $dir 'fx.sqlite'
$norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

Push-Location $WorkDir
try {
  $indexOut = & $Exe index $dir --db $db 2>&1
  $indexExit = $LASTEXITCODE
} finally { Pop-Location }
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut | Select-Object -Last 1)"

$chk = Join-Path $WorkDir 'check.py'
Set-Content -Path $chk -Encoding ascii -Value @'
import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
for line, n in c.execute(
    "SELECT start_line, COUNT(*) FROM refs WHERE name_text = 'TFoo' AND kind = 'type_use' "
    "GROUP BY start_line ORDER BY start_line"):
    print("%d %d" % (line, n))
c.close()
'@
$rows = & $Python -I $chk $db
Write-Host ("  TFoo type_use refs by line: " + ($rows -join ' | ')) -ForegroundColor DarkGray
$byLine = @{}
foreach ($r in $rows) { if ($r -match '^(\d+) (\d+)$') { $byLine[[int]$Matches[1]] = [int]$Matches[2] } }

Check 'line 8, method declaration: 1 ref (unchanged)'          ($byLine[8] -eq 1)  "got=$($byLine[8])"
Check 'line 11, free routine declaration: 1 ref (unchanged)'   ($byLine[11] -eq 1) "got=$($byLine[11])"
Check 'line 15, free routine implementation header: 1 ref'     ($byLine[15] -eq 1) "got=$($byLine[15])"
Check 'line 19, implementation-only function: param + return'  ($byLine[19] -eq 2) "got=$($byLine[19])"
Check 'line 21, nested routine param: 1 ref'                   ($byLine[21] -eq 1) "got=$($byLine[21])"
Check 'line 29, method implementation header: 1 ref (unchanged)' ($byLine[29] -eq 1) "got=$($byLine[29])"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
