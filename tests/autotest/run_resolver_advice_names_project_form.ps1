<#
  run_resolver_advice_names_project_form.ps1 --
  The resolver-staleness advice names the refresh form that is right for the
  database it is printed about.

  THE DEFECT (BACKLOG-TRIAGE-2026-09-28 FIX-5). Both resolver advisories -- the
  stderr note every read verb prints once, and the `remedy` field of
  `info --json` -- said `index <dir> --db <db> --resolve-only` (and, for a
  re-parse, `index <dir> --db <db>`) for EVERY database. Against a PROJECT
  database the `<dir>` form is the one the house rules forbid: a folder walk
  adds every loose .pas under the folder and adopts the widened set as the DB's
  scope (measured 2026-09-02: DataCopy 39 -> 72 files). `--resolve-only` is
  exempt from that refusal, but the operator copying the advice cannot know it,
  and the same line minus the flag IS the widening command. The freshness note
  already got this right (run_stale_index_advice_is_runnable.ps1 section D);
  the resolver note had not.

  THE CONTROLS:
    * a LIBRARY (folder) database still gets the `<dir>` form -- correct there
    * the project remedy actually RUNS: `index --project <dpr> --db <db>
      --resolve-only` exits 0 and clears the owed verdict
    * the remedy names the real database path, not a `<db>` placeholder

  Needs python (sqlite3) to plant an old resolver stamp -- the same dependency
  run_info_index_newer_than_engine.ps1 has. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_resolver_advice_form_$PID"
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
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  Write-Host 'SKIP: python not on PATH -- planting a fingerprint needs sqlite3'
  exit 0
}
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$proj = Join-Path $WorkDir 'proj'
$lib  = Join-Path $WorkDir 'lib'
New-Item -ItemType Directory -Force -Path (Join-Path $proj '_D-RAG'), $lib | Out-Null
$unit = @'
unit uA;
interface
procedure Go;
implementation
procedure Go;
begin
end;
end.
'@
W (Join-Path $proj 'uA.pas') $unit
W (Join-Path $lib  'uA.pas') $unit
W (Join-Path $proj 'App.dpr') @'
program App;
uses
  uA in 'uA.pas';
begin
end.
'@
$dpr   = Join-Path $proj 'App.dpr'
$dbP   = Join-Path $proj '_D-RAG\App.sqlite'
$dbL   = Join-Path $WorkDir 'Lib.sqlite'
$py    = Join-Path $WorkDir 'exec.py'
[IO.File]::WriteAllText($py,
  "import sqlite3,sys`nc=sqlite3.connect(sys.argv[1])`nc.execute(sys.argv[2])`nc.commit();c.close()`n",
  [Text.Encoding]::ASCII)

& $exePath index --project $dpr --db $dbP 2>&1 | Out-Null
& $exePath index $lib --db $dbL 2>&1 | Out-Null
Check 'V both fixture indexes were built' ((Test-Path $dbP) -and (Test-Path $dbL)) ''

function InfoRow([string]$Db) {
  $j = (& $exePath info --json --db $Db 2>$null) -join "`n"
  $i = $j.IndexOf('{')
  if ($i -lt 0) { return $null }
  try { return ($j.Substring($i) | ConvertFrom-Json).indexes[0] } catch { return $null }
}
function PlantOldResolver([string]$Db) {
  $row = InfoRow $Db
  $rfp = [string]$row.resolver_fingerprint
  if ($rfp -notmatch '^r=[^;]+;') { throw "FIXTURE: unexpected resolver stamp '$rfp' on $Db" }
  $old = $rfp -replace '^r=[^;]+;', 'r=0.0.1-alpha;'
  & python $py $Db "UPDATE schema_meta SET value='$old' WHERE key='resolver_fingerprint'" | Out-Null
}
function StderrNote([string]$Db) {
  # A read verb prints the freshness notes once, on stderr.
  return ((& $exePath query --name Go --db $Db 2>&1 | ForEach-Object { "$_" }) -join "`n")
}

PlantOldResolver $dbP
PlantOldResolver $dbL

# ---- project DB --------------------------------------------------------------
$pr = InfoRow $dbP
Check 'V project DB: info says resolve-owed' (($null -ne $pr) -and ($pr.verdict -eq 'resolve-owed')) "verdict='$($pr.verdict)'"
Check 'T1 project DB: info remedy names `index --project`' ([string]$pr.remedy -match 'index --project ') "remedy='$($pr.remedy)'"
Check 'T1b project DB: info remedy never names `index <dir>`' (-not ([string]$pr.remedy -match 'index <dir>')) "remedy='$($pr.remedy)'"
Check 'T1c project DB: info remedy names the real DB path' ([string]$pr.remedy -match [regex]::Escape($dbP)) "remedy='$($pr.remedy)'"
$pn = StderrNote $dbP
$pLine = (($pn -split "`n") | Where-Object { $_ -match 'resolver: edges were derived' }) -join ' '
Check 'V project DB: the stderr resolver note fires' ($pLine -ne '') $pn
Check 'T2 project DB: the stderr note names `index --project ... --resolve-only`' ($pLine -match 'index --project .*--resolve-only') $pLine
Check 'T2b project DB: the stderr note never names `index <dir>`' (-not ($pLine -match 'index <dir>')) $pLine

# ---- library DB (control) ----------------------------------------------------
$lr = InfoRow $dbL
Check 'P1 CONTROL library DB: info remedy keeps the `<dir>` form' ([string]$lr.remedy -match 'index <dir> .*--resolve-only') "remedy='$($lr.remedy)'"
$ln = StderrNote $dbL
$lLine = (($ln -split "`n") | Where-Object { $_ -match 'resolver: edges were derived' }) -join ' '
Check 'P1b CONTROL library DB: the stderr note keeps the `<dir>` form' ($lLine -match 'index <dir> .*--resolve-only') $lLine

# ---- the advice runs ---------------------------------------------------------
& $exePath index --project $dpr --db $dbP --resolve-only 2>&1 | Out-Null
$rc = $LASTEXITCODE
Check 'P2 the advised project command exits 0' ($rc -eq 0) "exit=$rc"
$after = InfoRow $dbP
Check 'P2b and clears the owed verdict' (($null -ne $after) -and ($after.verdict -eq 'current')) "verdict='$($after.verdict)'"

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("C:\TEMP\draglint_resolver_advice_form_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
