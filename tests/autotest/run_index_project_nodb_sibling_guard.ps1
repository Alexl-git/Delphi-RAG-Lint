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
    eng\drag-lint.json   sections Hello (..\proj\Hello.dpr), Hello3 (..\proj\Hello3.dpr),
                         FolderSec (..\fold, a FOLDER section), Library
                         (registry-libraries, db library-{platform}.sqlite, Win64)
    eng2\drag-lint.json  sections Hello, Hello2, Hello2a -- the last two both
                         claim Hello2.dpr (the ambiguity case)
    proj\Hello*.dpr      each uses uGreet.pas; Hello ALSO uses uHelloOnly.pas, so
                         Hello.sqlite holds a symbol no sibling closure has
    fold\Orphan.dpr      an unregistered project under the FOLDER section
    lib\uLibDecoy.pas    indexed into eng\library-Win64.sqlite (the "platform
                         library"): LibOnlyProc and a raise site
  Hello2, Hello4 and Hello5 are NOT registered in eng\drag-lint.json.
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
$fold = Join-Path $root 'fold'
$lib  = Join-Path $root 'lib'
$cfg  = Join-Path $root 'cfg'
New-Item -ItemType Directory $eng, $eng2, $proj, $fold, $lib, $cfg | Out-Null

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
  @{ name = 'Hello';     include = @('..\proj\Hello.dpr')  },
  @{ name = 'Hello3';    include = @('..\proj\Hello3.dpr') },
  @{ name = 'FolderSec'; include = @('..\fold') },
  @{ name = 'Library';   db = 'library-{platform}.sqlite'; source = 'registry-libraries'; platforms = @('Win64') }
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
Write-Ascii (Join-Path $proj 'uHelloOnly.pas') @'
unit uHelloOnly;

interface

procedure HelloOnlyProc;

implementation

procedure HelloOnlyProc;
begin
end;

end.
'@
foreach ($app in 'Hello', 'Hello2', 'Hello3', 'Hello4', 'Hello5') {
  $extraUse = if ($app -eq 'Hello') { ",`r`n  uHelloOnly in 'uHelloOnly.pas'" } else { '' }
  Write-Ascii (Join-Path $proj "$app.dpr") @"
program $app;

uses
  uGreet in 'uGreet.pas'$extraUse;

begin
  SayHello;
end.
"@
}
Write-Ascii (Join-Path $fold 'uOrph.pas') @'
unit uOrph;

interface

procedure OrphProc;

implementation

procedure OrphProc;
begin
end;

end.
'@
Write-Ascii (Join-Path $fold 'Orphan.dpr') @'
program Orphan;

uses
  uOrph in 'uOrph.pas';

begin
  OrphProc;
end.
'@
Write-Ascii (Join-Path $lib 'uLibDecoy.pas') @'
unit uLibDecoy;

interface

uses
  System.SysUtils;

procedure LibOnlyProc;

implementation

procedure LibOnlyProc;
begin
  raise Exception.Create('library decoy message');
end;

end.
'@
# An exceptions config at the fixture root, so exceptions-sync (section 6b) would
# really WRITE if it picked a store -- "it refused" is then not vacuous.
Write-Ascii (Join-Path $root 'drag-lint-lint.json') '{ "exceptions": {} }'

$helloDb  = Join-Path $proj '_D-RAG\Hello.sqlite'
$hello2Db = Join-Path $proj '_D-RAG\Hello2.sqlite'
$hello3Db = Join-Path $proj '_D-RAG\Hello3.sqlite'
$hello4Db = Join-Path $proj '_D-RAG\Hello4.sqlite'
$hello5Db = Join-Path $proj '_D-RAG\Hello5.sqlite'
$orphanDb = Join-Path $fold '_D-RAG\Orphan.sqlite'
$folderDb = Join-Path $eng  'FolderSec.sqlite'
$libDb    = Join-Path $eng  'library-Win64.sqlite'
$cfgDb    = Join-Path $root 'x.sqlite'

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
  # a relative path is the ENGINE's, and every engine run here starts in $root
  return ([IO.Path]::GetFullPath($A, $root).TrimEnd('\') -ieq [IO.Path]::GetFullPath($B, $root).TrimEnd('\'))
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
# eng2 is a SECOND engine copy with its own manifest; it is isolated separately.
$rd2All  = Invoke-Engine $exe2 $root @('resolve-dbs', '--platform', 'win64')
$rd2Proj = Invoke-Engine $exe2 $root @('resolve-dbs', '--project', 'proj\Hello2.dpr')
$foreign2 = @(($rd2All.Text + "`n" + $rd2Proj.Text) -split "`r?`n" |
  Where-Object { $_ -match '[A-Za-z]:\\' -and $_ -notmatch [regex]::Escape($root) })
$isolated2 = ($foreign2.Count -eq 0) -and ($rd2All.Text -notmatch 'loaded defaults from') -and
             ($rd2Proj.Code -ne 0) -and ($rd2Proj.Text -match 'section: Hello2a')
Check 'eng2: resolve-dbs names only temp-root paths, and sees ITS manifest (Hello2 claimed twice)' `
  $isolated2 ("foreign=[{0}] project=[{1}]" -f ($foreign2 -join ' ; '), $rd2Proj.Text.Trim())
if (-not ($isolated -and $isolated2)) {
  Write-Host 'ISOLATION FAILED -- no write verb was run.' -ForegroundColor Red
  Write-Host $rdAll.Text
  Write-Host $rd2All.Text
  exit 1
}

# Fixture DBs built with an EXPLICIT --db (safe on any engine): the "platform
# library" and the FOLDER section's DB.
$null = Invoke-Engine $exe1 $root @('index', $lib,  '--db', $libDb)
$null = Invoke-Engine $exe1 $root @('index', $fold, '--db', $folderDb)
Check 'fixture: library-Win64.sqlite and FolderSec.sqlite exist' ((Test-Path $libDb) -and (Test-Path $folderDb))
$rdLib = Invoke-Engine $exe1 $root @('resolve-dbs', '--platform', 'win64')
Check 'fixture: the Library SECTION resolves to library-Win64.sqlite' ($rdLib.Text -match [regex]::Escape($libDb)) ($rdLib.Text.Trim())
$libStamp    = Get-Stamp $libDb
$folderStamp = Get-Stamp $folderDb

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
# OWN vs SIBLING: HelloOnlyProc lives only in Hello.sqlite. A reader that keeps
# sibling DBs behind the owner still finds it; the ruling says it must not.
$qhc = Invoke-Engine $exe1 $root @('query', '--name', 'HelloOnlyProc', '--project', 'proj\Hello.dpr')
Check 'control: query --project Hello finds HelloOnlyProc (it is in Hello.sqlite)' ($qhc.Text -match 'uHelloOnly\.HelloOnlyProc') ($qhc.Text.Trim())
$qhs = Invoke-Engine $exe1 $root @('query', '--name', 'HelloOnlyProc', '--project', 'proj\Hello2.dpr')
Check 'query --project Hello2 does NOT find HelloOnlyProc (sibling Hello.sqlite is not read)' `
  ($qhs.Text -notmatch 'uHelloOnly\.HelloOnlyProc') ($qhs.Text.Trim())
$qlib = Invoke-Engine $exe1 $root @('query', '--name', 'LibOnlyProc', '--project', 'proj\Hello2.dpr')
Check 'control: query --project Hello2 DOES find LibOnlyProc (the platform library stays in the set)' `
  ($qlib.Text -match 'uLibDecoy\.LibOnlyProc') ($qlib.Text.Trim())
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
# 6b) A SOURCE WRITER never takes the platform LIBRARY as the project store.
#     Hello4 has no index; the consumer list is library-only. exceptions-sync
#     --apply would otherwise harvest the library's raise site into a new unit.
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '6b) exceptions-sync with an owner-less --project' -ForegroundColor Cyan
$es = Invoke-Engine $exe1 $root @('exceptions-sync', '--project', 'proj\Hello4.dpr', '--apply')
Check 'exceptions-sync --project Hello4 --apply (no --db) refuses, naming --db' `
  (($es.Code -eq 2) -and ($es.Text -match 'no drag-lint index found') -and ($es.Text -match '--db')) "exit=$($es.Code) $($es.Text.Trim())"
$written = @(Get-ChildItem -Path $root -Recurse -Filter 'uExceptionDefinitions.pas' -ErrorAction SilentlyContinue)
Check 'no exceptions unit was written anywhere' ($written.Count -eq 0) (($written | ForEach-Object { $_.FullName }) -join ',')
Check 'library-Win64.sqlite untouched' ($libStamp -eq (Get-Stamp $libDb)) "$libStamp -> $(Get-Stamp $libDb)"
$wi = Invoke-Engine $exe1 $root @('wiring', '--qname', 'IGreeter', '--project', 'proj\Hello4.dpr')
Check 'wiring --project Hello4 (no --db) refuses rather than reading the library as the project' `
  (($wi.Code -eq 2) -and ($wi.Text -match 'no drag-lint index found')) "exit=$($wi.Code) $($wi.Text.Trim())"

# -------------------------------------------------------------------------------
# 6c) A POSITIONAL project file is the same project-scoped scan, so it takes the
#     same rule -- no folder-prefix match, no OutDir\<Section>.sqlite name.
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '6c) positional index <x.dpr>, no --db' -ForegroundColor Cyan
# Run from the ENGINE dir with ABSOLUTE targets: that is the shape under which the
# old folder-prefix loop (includes resolved against the process CWD) matched.
$p5 = Invoke-Engine $exe1 $eng @('index', (Join-Path $proj 'Hello5.dpr'))
Check 'positional Hello5 (unregistered) -> its own _D-RAG DB' (Test-SamePath (Get-DatabaseLine $p5.Text) $hello5Db) "exit=$($p5.Code) Database=[$(Get-DatabaseLine $p5.Text)]"
$po = Invoke-Engine $exe1 $eng @('index', (Join-Path $fold 'Orphan.dpr'))
Check 'positional Orphan.dpr under a FOLDER section -> its own _D-RAG DB, not the section''s' `
  (Test-SamePath (Get-DatabaseLine $po.Text) $orphanDb) "exit=$($po.Code) Database=[$(Get-DatabaseLine $po.Text)]"
Check 'FolderSec.sqlite untouched by the positional project index' ($folderStamp -eq (Get-Stamp $folderDb)) "$folderStamp -> $(Get-Stamp $folderDb)"
Check 'Hello.sqlite untouched by the positional unregistered runs' ($helloStamp -eq (Get-Stamp $helloDb))
$ph = Invoke-Engine $exe1 $eng @('index', (Join-Path $proj 'Hello.dpr'))
Check 'positional Hello.dpr (registered) -> the section DB (ExpandSectionDb), not eng\Hello.sqlite' `
  (Test-SamePath (Get-DatabaseLine $ph.Text) $helloDb) "exit=$($ph.Code) Database=[$(Get-DatabaseLine $ph.Text)]"
Check 'no eng\Hello.sqlite (the dead OutDir name) was created' (-not (Test-Path (Join-Path $eng 'Hello.sqlite')))
$helloStamp = Get-Stamp $helloDb   # the registered re-index legitimately touched it

# -------------------------------------------------------------------------------
# 6d) A "db" key in a .drag-lint.json IS an explicit --db (owner ruling in Run).
# -------------------------------------------------------------------------------
Write-Host ''
Write-Host '6d) .drag-lint.json "db" counts as an explicit --db' -ForegroundColor Cyan
Write-Ascii (Join-Path $cfg '.drag-lint.json') ((@{ db = $cfgDb } | ConvertTo-Json))
$hello2Stamp = Get-Stamp $hello2Db
$rc = Invoke-Engine $exe1 $cfg @('index', '--project', (Join-Path $proj 'Hello2.dpr'))
Check 'index --project Hello2 from a folder with .drag-lint.json {db: x.sqlite} writes x.sqlite' `
  ((Test-SamePath (Get-DatabaseLine $rc.Text) $cfgDb) -and (Test-Path $cfgDb)) "exit=$($rc.Code) Database=[$(Get-DatabaseLine $rc.Text)]"
Check 'Hello2.sqlite untouched when the config names another db' ($hello2Stamp -eq (Get-Stamp $hello2Db)) "$hello2Stamp -> $(Get-Stamp $hello2Db)"
$rcl = Invoke-Engine $exe1 $cfg @('index', '--project', (Join-Path $proj 'Hello2.dpr'), '--db', $hello2Db)
Check 'control: a command-line --db REPLACES the config db' (Test-SamePath (Get-DatabaseLine $rcl.Text) $hello2Db) "Database=[$(Get-DatabaseLine $rcl.Text)]"
$hello2Stamp = Get-Stamp $hello2Db

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
# Not vacuous: the compile must have RUN (a JSON findings array came back) and the cache
# write must have MOVED Hello.sqlite -- a run that failed before resolving a DB
# prints no skip warning either.
Check 'control: compile-check <registered .dpr> compiled, cached into Hello.sqlite, and printed no skip warning' `
  (($cr.Out -match '(?m)^\s*\[') -and ($cr.Text -notmatch 'no database resolved for this target') -and
   ($helloStamp -ne (Get-Stamp $helloDb))) "stamp $helloStamp -> $(Get-Stamp $helloDb); $($cr.Text.Trim())"

$microAfter = Get-Stamp $micronite
Write-Host ''
Write-Host "Micronite2027.sqlite after:  $microAfter"
Check 'Micronite2027.sqlite size+mtime unchanged' ($microBefore -eq $microAfter) "$microBefore -> $microAfter"

Write-Host ''
if ($script:Failed) { Write-Host 'INDEX --project NO-DB SIBLING GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'INDEX --project NO-DB SIBLING GUARD: PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path -LiteralPath $WorkDir)) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
