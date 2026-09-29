<#
  run_index_project_nodb_sibling_guard.ps1 -- `index --project X.dpr` with NO
  --db must write ONLY to X's own database, never to another project's.

  THE DEFECT (2026-09-29, spec docs\superpowers\specs\2026-09-29-filed-defects-map.md
  section 1). Run defaulted Args.DbPath to ResolveConsumerDbs(Args)[0] for every
  verb that had --project. For a project the manifest does not register, that is
  simply the FIRST manifest section whose DB exists -- and ResolveIndexDb then
  honoured the defaulted DbPath as if the user had typed it. A read-only repro of
  this exact bug wrote two rows into C:\Projects\DB\ORM3\CLIENT\_D-RAG\
  Micronite2027.sqlite and changed its project_tag.

  The rule under test (owner ruling 2026-08-13: the authoritative set is the
  platform library plus the project's OWN DB, nothing else):
    a --project run's DB is (1) an explicit --db, else (2) the exact manifest
    owner of the project file, else (3) <project dir>\_D-RAG\<base>.sqlite.
    Two sections claiming the project REFUSE; a guessed owner is never used.

  ISOLATION IS PART OF THE TEST, NOT A COURTESY. Every run below uses an ENGINE
  COPY in %TEMP% with its OWN drag-lint.json beside it, from a working directory
  under %TEMP%. The engine reads <exe dir>\drag-lint.json and walks the CWD up
  for .drag-lint.json, so the shared engine directory -- whose manifest names
  real project DBs -- is never consulted. The first thing the test does is PROVE
  that with resolve-dbs, and it runs no write verb at all if the proof fails.

  FIXTURE
    eng\drag-lint.json   sections Hello (..\proj\Hello.dpr), Hello3 (..\proj\Hello3.dpr)
    eng2\drag-lint.json  sections Hello, Hello2, Hello2a -- the last two both
                         claim Hello2.dpr (the ambiguity case)
    proj\Hello.dpr / Hello2.dpr / Hello3.dpr / Hello4.dpr, each using uGreet.pas
  Hello2 and Hello4 are NOT registered in eng\drag-lint.json.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-nodb-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe    = (Resolve-Path $Exe).Path
$exeDir = Split-Path -Parent $Exe

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$root = (New-Item -ItemType Directory -Force -Path $WorkDir).FullName
$eng  = Join-Path $root 'eng'
$eng2 = Join-Path $root 'eng2'
$proj = Join-Path $root 'proj'
New-Item -ItemType Directory $eng, $eng2, $proj | Out-Null

# --- the engine copies: the exe, every dll beside it, and the rule catalogue ---
foreach ($dst in @($eng, $eng2)) {
  Copy-Item $Exe (Join-Path $dst 'drag-lint.exe') -Force
  Get-ChildItem -Path $exeDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $dst $_.Name) -Force }
  $rulesSrc = Join-Path $exeDir 'rules'
  if (Test-Path $rulesSrc) { Copy-Item $rulesSrc (Join-Path $dst 'rules') -Recurse -Force }
}
$exe1 = Join-Path $eng  'drag-lint.exe'
$exe2 = Join-Path $eng2 'drag-lint.exe'

function Write-Manifest([string]$Dir, [object[]]$Sections) {
  $m = @{
    settings = @{ defaultPlatform = 'Win64'; maxJobs = 1 }
    indexes  = @{ sections = $Sections }
  } | ConvertTo-Json -Depth 8
  Write-Ascii (Join-Path $Dir 'drag-lint.json') $m
}
Write-Manifest $eng  @(
  @{ name = 'Hello';  include = @('..\proj\Hello.dpr')  },
  @{ name = 'Hello3'; include = @('..\proj\Hello3.dpr') }
)
Write-Manifest $eng2 @(
  @{ name = 'Hello';   include = @('..\proj\Hello.dpr')  },
  @{ name = 'Hello2';  include = @('..\proj\Hello2.dpr') },
  @{ name = 'Hello2a'; include = @('..\proj\Hello2.dpr') }
)

# --- fixture source ------------------------------------------------------------
Write-Ascii (Join-Path $proj 'uGreet.pas') @'
unit uGreet;

interface

procedure SayHello;

implementation

procedure SayHello;
var
  Unused: Integer;
begin
end;

end.
'@
foreach ($app in 'Hello', 'Hello2', 'Hello3', 'Hello4') {
  Write-Ascii (Join-Path $proj "$app.dpr") @"
program $app;

uses
  uGreet in 'uGreet.pas';

begin
  SayHello;
end.
"@
}

$helloDb  = Join-Path $proj '_D-RAG\Hello.sqlite'
$hello2Db = Join-Path $proj '_D-RAG\Hello2.sqlite'
$hello3Db = Join-Path $proj '_D-RAG\Hello3.sqlite'
$hello4Db = Join-Path $proj '_D-RAG\Hello4.sqlite'

function Invoke-Engine([string]$ExePath, [string]$Cwd, [string[]]$Argv, [int]$TimeoutSec = 180) {
  $o = Join-Path $root 'out.txt'; $e = Join-Path $root 'err.txt'
  # Start-Process joins -ArgumentList with spaces and does NOT quote, so an
  # argument with a space (a SQL query) must be quoted here.
  $quoted = @($Argv | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
  $p = Start-Process $ExePath -ArgumentList $quoted -WorkingDirectory $Cwd `
         -PassThru -NoNewWindow -RedirectStandardOutput $o -RedirectStandardError $e
  if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ Code = -1; Text = 'TIMEOUT' } }
  $so = [string](Get-Content $o -Raw -ErrorAction SilentlyContinue)
  $t  = ($so + "`n" + (Get-Content $e -Raw -ErrorAction SilentlyContinue))
  return [pscustomobject]@{ Code = $p.ExitCode; Text = $t; Out = $so }
}
function Get-DatabaseLine([string]$Text) {
  $l = ($Text -split "`r?`n") | Where-Object { $_ -match '^Database:\s' } | Select-Object -First 1
  if ($l) { return ($l -replace '^Database:\s*', '').Trim() } else { return '' }
}
function Get-FilePaths([string]$Db) {
  # `sql --json` rows are POSITIONAL arrays -- map them onto columns[].name.
  $r = Invoke-Engine $exe1 $root @('sql', '--query', 'select path from files order by path', '--db', $Db, '--json')
  $j = $null
  try { $j = ($r.Out | ConvertFrom-Json) } catch { return ,@() }
  $ix = [array]::IndexOf(@($j.columns | ForEach-Object { $_.name }), 'path')
  if ($ix -lt 0) { return ,@() }
  return ,@($j.rows | ForEach-Object { [string]$_[$ix] })
}
function Get-Stamp([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 'absent' }
  $g = Get-Item -LiteralPath $Path
  return ('{0}|{1}' -f $g.Length, $g.LastWriteTimeUtc.Ticks)
}
function Test-SamePath([string]$A, [string]$B) {
  if (($A -eq '') -or ($B -eq '')) { return $false }
  return ([IO.Path]::GetFullPath($A).TrimEnd('\') -ieq [IO.Path]::GetFullPath($B).TrimEnd('\'))
}

$micronite = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite'
$microBefore = Get-Stamp $micronite
Write-Host "Micronite2027.sqlite before: $microBefore"

# -------------------------------------------------------------------------------
# 0) ISOLATION PROOF. No write verb runs until the copy is shown to see only the
#    fixture manifest.
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '0) isolation: the engine copy sees only the fixture manifest' -ForegroundColor Cyan
$rdAll  = Invoke-Engine $exe1 $root @('resolve-dbs', '--platform', 'win64')
$rdProj = Invoke-Engine $exe1 $root @('resolve-dbs', '--project', 'proj\Hello.dpr')
$foreign = @(($rdAll.Text + "`n" + $rdProj.Text) -split "`r?`n" |
  Where-Object { $_ -match '[A-Za-z]:\\' -and $_ -notmatch [regex]::Escape($root) })
$isolated = ($foreign.Count -eq 0) -and ($rdAll.Text -notmatch 'loaded defaults from') -and
            (Test-SamePath $rdProj.Text.Trim() $helloDb)
Check 'resolve-dbs names only paths under the temp root, loads no global defaults, and resolves Hello to the fixture DB' `
  $isolated ("foreign=[{0}] project=[{1}]" -f ($foreign -join ' ; '), $rdProj.Text.Trim())
if (-not $isolated) {
  Write-Host 'ISOLATION FAILED -- no write verb was run.' -ForegroundColor Red
  Write-Host $rdAll.Text
  exit 1
}

# -------------------------------------------------------------------------------
# 1) A REGISTERED project indexed for the FIRST time with no --db goes to its
#    manifest section's DB (ExpandSectionDb), not to <cwd>\_D-RAG.
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '1) registered project, first index, no --db' -ForegroundColor Cyan
$r3 = Invoke-Engine $exe1 $root @('index', '--project', 'proj\Hello3.dpr')
$db3 = Get-DatabaseLine $r3.Text
Check 'Hello3 (registered, not yet indexed) -> Database: names its section DB' (Test-SamePath $db3 $hello3Db) "exit=$($r3.Code) Database=[$db3]"
Check 'Hello3.sqlite was created' (Test-Path $hello3Db) $hello3Db
Check 'nothing was created under <cwd>\_D-RAG' (-not (Test-Path (Join-Path $root '_D-RAG'))) (Join-Path $root '_D-RAG')

# -------------------------------------------------------------------------------
# 2) POSITIVE CONTROL: a registered project that already has its DB re-indexes
#    into it with no --db. (Bootstrapped with an explicit --db, so this control
#    holds on the pre-fix engine too.)
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '2) positive control: registered project re-index, no --db' -ForegroundColor Cyan
$null = Invoke-Engine $exe1 $root @('index', '--project', 'proj\Hello.dpr', '--db', $helloDb)
$r1 = Invoke-Engine $exe1 $root @('index', '--project', 'proj\Hello.dpr')
$db1 = Get-DatabaseLine $r1.Text
Check 'Hello (registered) -> Database: names the section DB' (Test-SamePath $db1 $helloDb) "exit=$($r1.Code) Database=[$db1]"
$helloFiles = Get-FilePaths $helloDb
Check 'Hello.sqlite holds Hello.dpr (the snapshot is not vacuous)' (@($helloFiles | Where-Object { $_ -match '\\hello\.dpr$' }).Count -eq 1) ($helloFiles -join ',')
$helloStamp = Get-Stamp $helloDb
$hello3Stamp = Get-Stamp $hello3Db

# -------------------------------------------------------------------------------
# 3) THE DEFECT: an UNREGISTERED project, no --db. Must write its own
#    <proj>\_D-RAG\Hello2.sqlite and leave Hello.sqlite / Hello3.sqlite alone.
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '3) unregistered project, no --db' -ForegroundColor Cyan
$r2 = Invoke-Engine $exe1 $root @('index', '--project', 'proj\Hello2.dpr')
$db2 = Get-DatabaseLine $r2.Text
Check 'index --project Hello2 exits 0' ($r2.Code -eq 0) "exit=$($r2.Code)"
Check 'Database: names Hello2.sqlite (the project''s own _D-RAG DB)' (Test-SamePath $db2 $hello2Db) "Database=[$db2]"
Check 'Hello2.sqlite exists' (Test-Path $hello2Db) $hello2Db
$h2Files = if (Test-Path $hello2Db) { Get-FilePaths $hello2Db } else { @() }
Check 'Hello2.sqlite holds Hello2.dpr' (@($h2Files | Where-Object { $_ -match '\\hello2\.dpr$' }).Count -eq 1) ($h2Files -join ',')
$helloFilesAfter = Get-FilePaths $helloDb
Check 'Hello.sqlite file list is UNCHANGED' (($helloFiles -join '|') -eq ($helloFilesAfter -join '|')) ("before=[{0}] after=[{1}]" -f ($helloFiles -join ','), ($helloFilesAfter -join ','))
Check 'Hello.sqlite does not hold Hello2.dpr' (@($helloFilesAfter | Where-Object { $_ -match '\\hello2\.dpr$' }).Count -eq 0)
Check 'Hello.sqlite size+mtime unchanged' ($helloStamp -eq (Get-Stamp $helloDb)) "$helloStamp -> $(Get-Stamp $helloDb)"
Check 'Hello3.sqlite size+mtime unchanged' ($hello3Stamp -eq (Get-Stamp $hello3Db)) "$hello3Stamp -> $(Get-Stamp $hello3Db)"

# -------------------------------------------------------------------------------
# 4) AMBIGUITY: two sections claim Hello2.dpr -> refuse, naming both.
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '4) two sections claim the project, no --db' -ForegroundColor Cyan
$hello2Stamp = Get-Stamp $hello2Db
$ra = Invoke-Engine $exe2 $root @('index', '--project', 'proj\Hello2.dpr')
Check 'index --project refuses (non-zero exit)' ($ra.Code -ne 0) "exit=$($ra.Code)"
Check 'the refusal names BOTH claiming sections' `
  (($ra.Text -match '(?m)section:\s*Hello2\s*$') -and ($ra.Text -match '(?m)section:\s*Hello2a\s*$')) ($ra.Text.Trim())
Check 'no Database: line was printed (nothing was opened)' ((Get-DatabaseLine $ra.Text) -eq '') (Get-DatabaseLine $ra.Text)
Check 'Hello2.sqlite untouched by the refused run' ($hello2Stamp -eq (Get-Stamp $hello2Db)) "$hello2Stamp -> $(Get-Stamp $hello2Db)"
Check 'Hello.sqlite untouched by the refused run' ($helloStamp -eq (Get-Stamp $helloDb))

# -------------------------------------------------------------------------------
# 5) THE READ SIDE (same ruling): a read verb for an unregistered project with no
#    index of its own must not answer from another project's DB.
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '5) read verbs never borrow another project''s DB' -ForegroundColor Cyan
$qc = Invoke-Engine $exe1 $root @('query', '--name', 'SayHello', '--project', 'proj\Hello.dpr')
Check 'control: query --project Hello (registered) answers from Hello.sqlite' ($qc.Text -match 'uGreet\.SayHello') ($qc.Text.Trim())
$qo = Invoke-Engine $exe1 $root @('query', '--name', 'SayHello', '--project', 'proj\Hello2.dpr')
Check 'query --project Hello2 (unregistered, own DB exists) answers from its own DB' ($qo.Text -match 'uGreet\.SayHello') ($qo.Text.Trim())
$q4 = Invoke-Engine $exe1 $root @('query', '--name', 'SayHello', '--project', 'proj\Hello4.dpr')
Check 'query --project Hello4 (unregistered, never indexed) does NOT answer from a sibling DB' `
  ($q4.Text -notmatch 'uGreet\.SayHello') ($q4.Text.Trim())
Check 'and it SAYS no index owns the project' ($q4.Text -match 'no index owns') ($q4.Text.Trim())
$l4 = Invoke-Engine $exe1 $root @('lint-all', '--project', 'proj\Hello4.dpr')
Check 'lint-all --project Hello4 refuses rather than linting against a sibling DB' `
  (($l4.Code -ne 0) -and ($l4.Text -match 'no drag-lint index found')) "exit=$($l4.Code) $($l4.Text.Trim())"
Check 'no DB was created for Hello4 by a read verb' (-not (Test-Path $hello4Db))
Check 'Hello.sqlite size+mtime unchanged by the read verbs' ($helloStamp -eq (Get-Stamp $helloDb))

# -------------------------------------------------------------------------------
# 6) THE OTHER WRITE VERBS. purge-locals must refuse without an EXPLICIT --db
#    even when the project resolves (its message has always said so).
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '6) purge-locals needs an explicit --db' -ForegroundColor Cyan
$pl = Invoke-Engine $exe1 $root @('purge-locals', '--project', 'proj\Hello.dpr')
Check 'purge-locals --project Hello (no --db) refuses' (($pl.Code -ne 0) -and ($pl.Text -match 'needs an explicit --db')) "exit=$($pl.Code) $($pl.Text.Trim())"
Check 'Hello.sqlite size+mtime unchanged by purge-locals' ($helloStamp -eq (Get-Stamp $helloDb)) "$helloStamp -> $(Get-Stamp $helloDb)"

# -------------------------------------------------------------------------------
# 7) THE COMPILER-FINDINGS WRITERS (need a working dcc). uGreet carries an unused
#    local, so every compile yields a hint and a cache write MOVES the DB file --
#    which is what makes "Hello.sqlite unchanged" able to fail.
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '7) refresh-findings / compile-check write only to the project''s own DB' -ForegroundColor Cyan
$rf = Invoke-Engine $exe1 $root @('refresh-findings', '--project', 'proj\Hello2.dpr', '--full') 300
Check 'refresh-findings --project Hello2 (no --db) resolved a DB (not the usage/no-db exit 2)' ($rf.Code -ne 2) "exit=$($rf.Code) $($rf.Text.Trim())"
Check 'refresh-findings left Hello.sqlite alone' ($helloStamp -eq (Get-Stamp $helloDb)) "$helloStamp -> $(Get-Stamp $helloDb)"
$cp = Invoke-Engine $exe1 $root @('compile-check', 'proj\Hello2.dpr', '--project', 'proj\Hello2.dpr', '--format', 'json') 300
Check 'compile-check --project Hello2 (unregistered) does not cache, and says so' ($cp.Text -match 'no database resolved for this target') ($cp.Text.Trim())
$cu = Invoke-Engine $exe1 $root @('compile-check', 'proj\uGreet.pas', '--format', 'json') 300
Check 'compile-check <unit> with no project does not cache through a FOLDER match, and says so' ($cu.Text -match 'no database resolved for this target') ($cu.Text.Trim())
Check 'compile-check left Hello.sqlite alone' ($helloStamp -eq (Get-Stamp $helloDb)) "$helloStamp -> $(Get-Stamp $helloDb)"
$cr = Invoke-Engine $exe1 $root @('compile-check', 'proj\Hello.dpr', '--format', 'json') 300
Check 'control: compile-check <registered .dpr> still caches into its own DB (no skip warning)' `
  ($cr.Text -notmatch 'no database resolved for this target') ($cr.Text.Trim())

$microAfter = Get-Stamp $micronite
Write-Host ''
Write-Host "Micronite2027.sqlite after:  $microAfter"
Check 'Micronite2027.sqlite size+mtime unchanged' ($microBefore -eq $microAfter) "$microBefore -> $microAfter"

Write-Host ''
if ($script:Failed) { Write-Host 'INDEX --project NO-DB SIBLING GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'INDEX --project NO-DB SIBLING GUARD: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-nodb-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
