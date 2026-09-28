<#
  run_index_all_project_tag_stamp.ps1 -- the `project_tag` stamp written by the
  MANIFEST path (`index --all`), and its clearing.

  WHAT D27 SHIPPED (2026-09-24, ced256d9). The `[Project]` tag on reconciled doc
  facts comes from `schema_meta.project_tag`, stamped by BOTH index paths from
  the one project file a scan roots at, so the tag travels with the index
  instead of coming from the DB FILE NAME. run_doc_project_tags.ps1 covers the
  `index --project` path; nothing covered `index --all`, which is how nearly
  every real project DB is built (BACKLOG-TRIAGE-2026-09-28 TH-3).

  THE DEFECT THIS ALSO PINS. A section that names no single project -- two
  roots, or a folder (library) section -- records no tag, and its readers fall
  back to the DB base name. But it never CLEARED one: a DB stamped while its
  section had one root kept that project's name after the section grew a
  second root, so every doc fact written through it carried a project the
  section no longer is.

  CASES
    T1 a one-root closure section stamps the project file's base name (not the
       section name, not the DB name -- all three differ here on purpose)
    T2 the same DB after its section grows a second root: the stamp is cleared
    T3 a one-root section again: the stamp comes back (the clearing is not sticky)
    P1 CONTROL a folder (library) section over a DB stamped by T1's shape clears
       it too

  Run from any CWD, pwsh 7. Builds its own fixture and manifest; every engine
  run is `--only <this fixture's section>` from the fixture folder.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_index_all_project_tag_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$app = Join-Path $WorkDir 'app'
$lib = Join-Path $WorkDir 'lib'
New-Item -ItemType Directory -Force -Path $app, $lib | Out-Null
W (Join-Path $app 'uA.pas') @'
unit uA;
interface
procedure Go;
implementation
procedure Go;
begin
end;
end.
'@
W (Join-Path $app 'uB.pas') @'
unit uB;
interface
procedure Stop;
implementation
procedure Stop;
begin
end;
end.
'@
W (Join-Path $lib 'uL.pas') @'
unit uL;
interface
procedure Lib;
implementation
procedure Lib;
begin
end;
end.
'@
W (Join-Path $app 'AlphaApp.dpr') @'
program AlphaApp;
uses
  uA in 'uA.pas';
begin
end.
'@
W (Join-Path $app 'BetaApp.dpr') @'
program BetaApp;
uses
  uB in 'uB.pas';
begin
end.
'@

$SECTION = 'TagProbeSection'
$db      = Join-Path $WorkDir 'TagProbeDb.sqlite'
function Manifest([string[]]$Include) {
  $cfg = [ordered]@{ indexes = [ordered]@{ outDir = '.'; sections = @([ordered]@{ name = $SECTION; db = 'TagProbeDb.sqlite'; include = @($Include) }) } }
  [IO.File]::WriteAllText((Join-Path $WorkDir '.drag-lint.json'), ($cfg | ConvertTo-Json -Depth 8), [Text.Encoding]::ASCII)
}
function IndexAll([string]$Mode = '') {
  Push-Location $WorkDir
  try {
    $argv = @('index', '--all', '--only', $SECTION)
    if ($Mode) { $argv += $Mode }
    $o = (& $exePath @argv 2>&1 | ForEach-Object { "$_" }) -join "`n"
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $o }
  } finally { Pop-Location }
}
function Tag {
  $j = & $exePath sql --db $db --json --query "SELECT value FROM schema_meta WHERE key = 'project_tag'" 2>$null | ConvertFrom-Json
  if ($null -eq $j -or $j.rows.Count -eq 0) { return '' }
  return [string]$j.rows[0][0]
}

# ---- T1: one root -> the project file's name ---------------------------------
Manifest @('.\app\AlphaApp.dpr')
$r = IndexAll
Check 'V the one-root section indexed (exit 0)' ($r.Exit -eq 0) $r.Out
Check 'V the database the manifest names exists' (Test-Path $db) $db
$t1 = Tag
Check "T1 a one-root closure section stamps the project file's name (got '$t1')" ($t1 -eq 'AlphaApp') ''

# ---- T2: two roots -> the stamp is cleared ------------------------------------
Manifest @('.\app\AlphaApp.dpr', '.\app\BetaApp.dpr')
$r = IndexAll '--rebuild'
Check 'V the two-root section indexed (exit 0)' ($r.Exit -eq 0) $r.Out
$t2 = Tag
Check "T2 after the section grows a second root, the old project's stamp is gone (got '$t2')" ($t2 -eq '') ''

# ---- T3: back to one root -> stamped again ------------------------------------
Manifest @('.\app\BetaApp.dpr')
$r = IndexAll '--rebuild'
$t3 = Tag
Check "T3 a one-root section stamps again after being cleared (got '$t3')" ($t3 -eq 'BetaApp') $r.Out

# ---- P1: a folder section clears a stamp too ----------------------------------
Manifest @('.\lib')
$r = IndexAll '--rebuild'
Check 'V the folder section indexed (exit 0)' ($r.Exit -eq 0) $r.Out
$t4 = Tag
Check "P1 a folder (library) section over a stamped DB clears the stamp (got '$t4')" ($t4 -eq '') ''

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("C:\TEMP\draglint_index_all_project_tag_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
