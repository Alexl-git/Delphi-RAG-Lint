[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fresh-findings"
)
$ErrorActionPreference = 'Stop'
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
$db = Join-Path $WorkDir 'ff.sqlite'

# Task 1: the schema verb reports the new column exists after a migrate.
# Force a migrate by indexing an empty dir (creates + migrates the db).
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null
[System.IO.File]::WriteAllText((Join-Path $src 'Empty.pas'),
  "unit Empty;`r`ninterface`r`nimplementation`r`nend.`r`n", [System.Text.Encoding]::ASCII)
& $Exe index $src --db $db | Out-Null
$schema = (& $Exe schema --json --db $db) -join "`n"
Check "files.last_compiled_unix column exists" ($schema -match 'last_compiled_unix') "schema had no such column"

# Task 2: a hidden self-test verb exercises the new store methods on a temp db.
$storeTest = ((& $Exe test-store-freshness --db $db) 2>&1) -join "`n"
Check "store-freshness self-test OK" ($LASTEXITCODE -eq 0) "out=$storeTest"

# Task 4: end-to-end -- a unit with an unused private method must surface H2219.
# Uses a BARE .dpr (not a .dproj): TCompileChecker.Run on a non-.dproj target
# takes the "dcc64 -Q <target>" branch, which needs no msbuild/.dproj package
# list -- rtl/vcl are on dcc64's default search path via rsvars.bat. This
# avoids needing a generated .dproj fixture for this simple 1-unit program.
$proj = Join-Path $WorkDir 'ffproj'; New-Item -ItemType Directory $proj | Out-Null
$pas = @'
unit UHint;
interface
type
  TThing = class
  private
    procedure NeverCalled;
  public
    procedure DoIt;
  end;
implementation
procedure TThing.NeverCalled; begin end;
procedure TThing.DoIt; begin end;
end.
'@
[System.IO.File]::WriteAllText((Join-Path $proj 'UHint.pas'), ($pas -replace "`r?`n","`r`n"), [System.Text.Encoding]::ASCII)
$dpr = @'
program FFProj;
uses UHint in 'UHint.pas';
begin
end.
'@
[System.IO.File]::WriteAllText((Join-Path $proj 'FFProj.dpr'), ($dpr -replace "`r?`n","`r`n"), [System.Text.Encoding]::ASCII)
$db2 = Join-Path $WorkDir 'ff2.sqlite'
& $Exe index $proj --db $db2 | Out-Null
$out = (& $Exe refresh-findings --project (Join-Path $proj 'FFProj.dpr') --db $db2 --json 2>&1) -join "`n"
Check "refresh-findings exits 0/1 (ran)" ($LASTEXITCODE -le 1) "exit=$LASTEXITCODE out=$out"
Check "refresh-findings JSON has a mode field" ($out -match '"mode"\s*:\s*"(full|incremental|noop)"') "out=$out"
# query the stored findings: `query hints` reads compiler_findings directly
# (NOT `query --text`, which is the FTS5 index over .pas/.dfm/.sql SOURCE text,
# not the compiler_findings table -- the wrong tool for this assertion).
$dump = (& $Exe query hints --db $db2 2>&1) -join "`n"
Check "H2219 stored for the unused private method" ($out -match 'H2219' -or $out -match 'never used' -or $dump -match 'NeverCalled' -or $dump -match 'H2219') "out=$out dump=$dump"

# Re-running immediately afterward (files now freshly compiled) should be a noop.
$out2 = (& $Exe refresh-findings --project (Join-Path $proj 'FFProj.dpr') --db $db2 --json 2>&1) -join "`n"
Check "refresh-findings second run is a noop (nothing stale)" ($out2 -match '"mode"\s*:\s*"noop"') "out2=$out2"

# Task 5: mode decision transitions. First run above was full (all stale).
# Touch one unit -> exactly 1 stale -> incremental.
Start-Sleep -Milliseconds 1100
(Get-Item (Join-Path $proj 'UHint.pas')).LastWriteTime = Get-Date
& $Exe index $proj --db $db2 | Out-Null   # refresh files.mtime_unix
$m1 = ((& $Exe refresh-findings --project (Join-Path $proj 'FFProj.dpr') --db $db2 --json) 2>&1) -join "`n"
Check "1 stale -> incremental mode" ($m1 -match '"mode"\s*:\s*"incremental"') "out=$m1"
# No changes -> noop.
$m2 = ((& $Exe refresh-findings --project (Join-Path $proj 'FFProj.dpr') --db $db2 --json) 2>&1) -join "`n"
Check "0 stale after incremental -> noop mode" ($m2 -match '"mode"\s*:\s*"noop"') "out=$m2"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
