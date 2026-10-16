<#
  run_index_project_tag_refusal.ps1 -- `index --project <X> --db <Y>` refuses
  when Y is already stamped as ANOTHER project's index (1.31.2-alpha).

  THE INCIDENT, 2026-10-16. The IDE plugin paired the ACTIVE project with the
  LAST-OPENED project's DB, so every save and every "Rescan this unit" ran
    index --project ...\Micronite2027.dproj --db ...\Delphi13MigrationAssistant.sqlite
  The engine took it: the second project's DB was overwritten with the first
  project's closure (schema_meta project_tag = Micronite2027, 632 files) and
  Micronite2027.sqlite was never refreshed. Nothing failed, so nothing showed.

  The DB already said whose it was -- `project_tag`, stamped by every
  project-scoped run (D27). This pins that the engine READS it before writing.

  CASES
    R1 a project index into a DB tagged for another project exits non-zero
    R2 ... and the message names BOTH projects and points at resolve-dbs
    R3 ... and the DB is byte-identical afterwards (refused before Migrate)
    R4 --rebuild PROCEEDS with a NOTE: it is the remedy the rename's tag-mismatch
       advice prints, and it clears before it writes, so closures cannot mix
    R5 the bare .dpr target form is refused the same way
    P1 POSITIVE CONTROL the matching project still indexes into its own DB
    P2 POSITIVE CONTROL a fresh (untagged) DB accepts any project
    P3 POSITIVE CONTROL a DB whose tag was cleared (folder scan) accepts a project

  Run from any CWD, pwsh 7. Builds its own fixture; touches no real DB.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_index_project_tag_refusal_$PID"
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
$alpha = Join-Path $app 'AlphaApp.dpr'
$beta  = Join-Path $app 'BetaApp.dpr'

function Run([string[]]$argv) {
  Push-Location $WorkDir
  try {
    $o = (& $exePath @argv 2>&1 | ForEach-Object { "$_" }) -join "`n"
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $o }
  } finally { Pop-Location }
}
function Tag([string]$Db) {
  $j = & $exePath sql --db $Db --json --query "SELECT value FROM schema_meta WHERE key = 'project_tag'" 2>$null | ConvertFrom-Json
  if ($null -eq $j -or $j.rows.Count -eq 0) { return '' }
  return [string]$j.rows[0][0]
}
function HasFile([string]$Db, [string]$Leaf) {
  $j = & $exePath sql --db $Db --json --query "SELECT path FROM files" 2>$null | ConvertFrom-Json
  if ($null -eq $j) { return $false }
  foreach ($row in $j.rows) { if ([string]$row[0] -like "*\$Leaf") { return $true } }
  return $false
}
function Hash([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

# ---- setup: Alpha's own DB ----------------------------------------------------
$db = Join-Path $WorkDir 'Alpha.sqlite'
$r = Run @('index', '--project', $alpha, '--db', $db)
Check 'V setup: AlphaApp indexes into a fresh DB (exit 0)' ($r.Exit -eq 0) $r.Out
$t = Tag $db
Check "V setup: the DB is stamped AlphaApp (got '$t')" ($t -eq 'AlphaApp') ''
Check 'V setup: uA.pas is in it' (HasFile $db 'uA.pas') ''

# ---- P1: the matching project still indexes -----------------------------------
$r = Run @('index', '--project', $alpha, '--db', $db)
Check 'P1 the SAME project re-indexes into its own DB (exit 0)' ($r.Exit -eq 0) $r.Out

# ---- R1-R3: another project is refused ----------------------------------------
$before = Hash $db
$r = Run @('index', '--project', $beta, '--db', $db)
Check "R1 BetaApp into AlphaApp's DB is refused (exit $($r.Exit))" ($r.Exit -ne 0) $r.Out
Check 'R2 the refusal names both projects and suggests resolve-dbs' (
  ($r.Out -match 'AlphaApp') -and ($r.Out -match 'BetaApp') -and ($r.Out -match 'resolve-dbs --project')) $r.Out
Check 'R3 the refused DB is byte-identical' ((Hash $db) -eq $before) ''
Check 'R3b no BetaApp member leaked into it' (-not (HasFile $db 'uB.pas')) ''
Check "R3c the stamp is still AlphaApp (got '$(Tag $db)')" ((Tag $db) -eq 'AlphaApp') ''

# ---- R5: the bare .dpr form ---------------------------------------------------
$r = Run @('index', $beta, '--db', $db)
Check "R5 the bare-path project form is refused too (exit $($r.Exit))" ($r.Exit -ne 0) $r.Out
Check 'R5b ... byte-identical' ((Hash $db) -eq $before) ''

# ---- R4: --rebuild replaces the closure, with a NOTE --------------------------
$r = Run @('index', '--project', $beta, '--db', $db, '--rebuild')
Check "R4 --rebuild proceeds (exit $($r.Exit))" ($r.Exit -eq 0) $r.Out
Check 'R4b ... and says whose index it replaced' (($r.Out -match 'NOTE: .*AlphaApp.*--rebuild replaces it with BetaApp')) $r.Out
Check "R4c ... restamped BetaApp (got '$(Tag $db)')" ((Tag $db) -eq 'BetaApp') ''
Check 'R4d ... and no AlphaApp row survives (no mixed closure)' ((HasFile $db 'uB.pas') -and -not (HasFile $db 'uA.pas')) ''

# ---- P2: a fresh DB accepts any project ----------------------------------------
$db2 = Join-Path $WorkDir 'Fresh.sqlite'
$r = Run @('index', '--project', $beta, '--db', $db2)
Check 'P2 a fresh, untagged DB accepts BetaApp (exit 0)' ($r.Exit -eq 0) $r.Out

# ---- P3: a cleared tag accepts a project --------------------------------------
$db3 = Join-Path $WorkDir 'Lib.sqlite'
$r = Run @('index', $lib, '--db', $db3)
Check 'V setup: a folder scan builds an untagged DB (exit 0)' ($r.Exit -eq 0) $r.Out
Check "V setup: its tag is empty (got '$(Tag $db3)')" ((Tag $db3) -eq '') ''
$r = Run @('index', '--project', $beta, '--db', $db3)
Check 'P3 a DB with an empty tag accepts a project (exit 0)' ($r.Exit -eq 0) $r.Out

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_index_project_tag_refusal_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
