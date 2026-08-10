<#
  run_index_scope_eviction.ps1 -- OUT-OF-SCOPE EVICTION.

  WHAT PRUNE CANNOT DO
  ---------------------------------------------------------------------------
  Prune-by-default deletes indexed files that vanished from DISK. Nothing
  deleted a file that still EXISTS and is no longer in SCOPE. That is why the
  YADF index carried 5 `.private\` archive copies and 104 files from a sibling
  repo through every reindex, and why dropping a unit from a .dproj left its
  symbols in the index forever -- answering queries, feeding find-callers, and
  counting toward coverage, from source the project does not compile.

  THE TWO SCAN TYPES HAVE DIFFERENT IN-SCOPE SETS, so both are asserted:
    * PROJECT -- the expanded compile closure (ExpandProjectScope).
    * LIBRARY -- the walked tree MINUS the exclude globs, so ADDING an exclude
      removes what it now covers instead of leaving it indexed forever.

  BOUNDED, LIKE PRUNE. Eviction only ever touches files under the roots THIS
  run walked. Group 2 pins that: two projects in one DB, recompile one, the
  other survives untouched.

  THE FTS5 TRAP (group 1f, 3d)
  ---------------------------------------------------------------------------
  string_literals is kept in sync with its FTS5 shadow tables by AFTER DELETE
  TRIGGERS, and SQLite fires triggers for rows removed by an FK CASCADE only
  when recursive_triggers is on. An eviction that deleted `files` and left
  string_literals to the cascade would strand the FTS entries, and text search
  would go on matching source the DB no longer holds. Asserted through a MATCH
  against string_fts ITSELF, not through `query --text`: the CLI joins the match
  back to string_literals, so it cannot see a stranded entry.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. Needs `python` on PATH.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_scopeevict'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

$projA = Join-Path $scratch 'projA'
$projB = Join-Path $scratch 'projB'
$lib   = Join-Path $scratch 'lib'
New-Item -ItemType Directory -Path $projA | Out-Null
New-Item -ItemType Directory -Path $projB | Out-Null
New-Item -ItemType Directory -Path $lib   | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- fixture: project A, two members ----------------------------------------
function Write-ProjA([bool]$WithMember2) {
  if ($WithMember2) {
    Write-Ascii (Join-Path $projA 'App.dpr') @'
program App;

uses
  Member1 in 'Member1.pas',
  Member2 in 'Member2.pas';

begin
  Member1.RunOne;
  Member2.RunTwo;
end.
'@
    $refs = "        <DCCReference Include=`"Member1.pas`"/>`r`n        <DCCReference Include=`"Member2.pas`"/>"
  } else {
    Write-Ascii (Join-Path $projA 'App.dpr') @'
program App;

uses
  Member1 in 'Member1.pas';

begin
  Member1.RunOne;
end.
'@
    $refs = "        <DCCReference Include=`"Member1.pas`"/>"
  }
  Write-Ascii (Join-Path $projA 'App.dproj') @"
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>App.dpr</MainSource>
        <ProjectVersion>20.3</ProjectVersion>
        <Platform>Win64</Platform>
        <Config Condition="'`$(Config)'==''">Debug</Config>
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="App.dpr">
            <MainSource>MainSource</MainSource>
        </DelphiCompile>
$refs
    </ItemGroup>
</Project>
"@
}

Write-Ascii (Join-Path $projA 'Member1.pas') @'
unit Member1;

interface

procedure RunOne;

implementation

const
  ONE_MARK = 'zzqqmemberonemarker';

procedure RunOne;
var
  S: string;
begin
  S:= ONE_MARK;
end;

end.
'@

# Member2 carries a marker string so the FTS5 shadow tables can be probed for it
# directly after it leaves the project.
Write-Ascii (Join-Path $projA 'Member2.pas') @'
unit Member2;

interface

type
  TSecondThing = class(TObject)
  public
    procedure Alpha;
    function Beta: Integer;
  end;

procedure RunTwo;

implementation

const
  TWO_MARK = 'zzqqmembertwomarker';

procedure TSecondThing.Alpha;
begin
end;

function TSecondThing.Beta: Integer;
begin
  Result:= 0;
end;

procedure RunTwo;
var
  S: string;
begin
  S:= TWO_MARK;
end;

end.
'@

Write-ProjA $true

# --- fixture: project B, a SIBLING project that must never be touched -------
Write-Ascii (Join-Path $projB 'Other.dpr') @'
program Other;

uses
  BUnit in 'BUnit.pas';

begin
  BUnit.RunB;
end.
'@

Write-Ascii (Join-Path $projB 'Other.dproj') @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>Other.dpr</MainSource>
        <ProjectVersion>20.3</ProjectVersion>
        <Platform>Win64</Platform>
        <Config Condition="'$(Config)'==''">Debug</Config>
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="Other.dpr">
            <MainSource>MainSource</MainSource>
        </DelphiCompile>
        <DCCReference Include="BUnit.pas"/>
    </ItemGroup>
</Project>
'@

Write-Ascii (Join-Path $projB 'BUnit.pas') @'
unit BUnit;

interface

procedure RunB;

implementation

procedure RunB;
var
  S: string;
begin
  S:= 'zzqqbunitmarker';
end;

end.
'@

# --- fixture: a library tree of three units ---------------------------------
Write-Ascii (Join-Path $lib 'LibOne.pas') @'
unit LibOne;

interface

function OneName: string;

implementation

function OneName: string;
begin
  Result:= 'lib one';
end;

end.
'@

Write-Ascii (Join-Path $lib 'LibTwo.pas') @'
unit LibTwo;

interface

type
  TTwoHolder = class(TObject)
  public
    function Tag: string;
  end;

implementation

function TTwoHolder.Tag: string;
begin
  Result:= 'zzqqlibtwomarker';
end;

end.
'@

Write-Ascii (Join-Path $lib 'LibThree.pas') @'
unit LibThree;

interface

function ThreeName: string;

implementation

function ThreeName: string;
begin
  Result:= 'lib three';
end;

end.
'@

# --- probes -----------------------------------------------------------------
# Content snapshot: one line per indexed file, lowercased path + symbol count.
$snapPy = Join-Path $scratch 'snap.py'
@'
import sqlite3, sys, os
db = sys.argv[1]
if not os.path.exists(db):
    print('MISSING-DB')
    sys.exit(0)
c = sqlite3.connect(db)
try:
    rows = c.execute(
        "SELECT LOWER(f.path), COUNT(s.id) FROM files f "
        "LEFT JOIN symbols s ON s.file_id = f.id "
        "GROUP BY f.id ORDER BY LOWER(f.path)").fetchall()
    print(';'.join('%s=%d' % (r[0], r[1]) for r in rows))
except sqlite3.Error as e:
    print('ERROR:' + str(e))
c.close()
'@ | Set-Content $snapPy -Encoding ascii

# rows.py <db> files|symbols|orphans [pattern]
#   files   -- COUNT(*) of files rows whose path matches %pattern%
#   symbols -- COUNT(*) of symbols reachable from such a file
#   orphans -- symbols whose file_id names no files row (a cascade that failed)
$rowsPy = Join-Path $scratch 'rows.py'
@'
import sqlite3, sys, os
db, what = sys.argv[1], sys.argv[2]
pat = ('%' + sys.argv[3].lower() + '%') if len(sys.argv) > 3 else '%'
if not os.path.exists(db):
    print('MISSING-DB')
    sys.exit(0)
c = sqlite3.connect(db)
try:
    if what == 'files':
        n = c.execute("SELECT COUNT(*) FROM files WHERE LOWER(path) LIKE ?", (pat,)).fetchone()[0]
    elif what == 'symbols':
        n = c.execute("SELECT COUNT(*) FROM symbols s JOIN files f ON f.id = s.file_id "
                      "WHERE LOWER(f.path) LIKE ?", (pat,)).fetchone()[0]
    else:
        n = c.execute("SELECT COUNT(*) FROM symbols WHERE file_id NOT IN "
                      "(SELECT id FROM files)").fetchone()[0]
    print(n)
except sqlite3.Error as e:
    print('ERROR:' + str(e))
c.close()
'@ | Set-Content $rowsPy -Encoding ascii

# FTS5 shadow-table probe. MATCH reads the fts index itself, so it still sees
# entries whose string_literals row has been deleted -- exactly the stranded
# state a cascade-only delete leaves behind.
$ftsPy = Join-Path $scratch 'fts.py'
@'
import sqlite3, sys, os
db, term = sys.argv[1], sys.argv[2]
if not os.path.exists(db):
    print('MISSING-DB')
    sys.exit(0)
c = sqlite3.connect(db)
try:
    n = c.execute("SELECT COUNT(*) FROM string_fts WHERE string_fts MATCH ?", (term,)).fetchone()[0]
    print(n)
except sqlite3.Error as e:
    print('NOFTS:' + str(e))
c.close()
'@ | Set-Content $ftsPy -Encoding ascii

# schema_meta sentinel. A section build that DELETED and recreated its .sqlite
# would take this row with it, so it is the proof that `index --all` keeps the
# database (and the open file handle the IDE plugin holds) rather than dropping
# it -- and the proof that group 5's eviction assertion is not passing merely
# because the whole DB was thrown away.
$metaPy = Join-Path $scratch 'meta.py'
@'
import sqlite3, sys, os
db, mode = sys.argv[1], sys.argv[2]
if not os.path.exists(db):
    print('MISSING-DB')
    sys.exit(0)
c = sqlite3.connect(db)
try:
    if mode == 'set':
        c.execute("INSERT OR REPLACE INTO schema_meta(key, value) VALUES "
                  "('evict_sentinel', 'survives-a-recompile')")
        c.commit()
        print('SET')
    else:
        r = c.execute("SELECT value FROM schema_meta WHERE key = 'evict_sentinel'").fetchone()
        print(r[0] if r else 'GONE')
except sqlite3.Error as e:
    print('ERROR:' + str(e))
c.close()
'@ | Set-Content $metaPy -Encoding ascii

function Snap([string]$Db) { return ((& python $snapPy $Db) -join '') }
function Sentinel([string]$Db, [string]$Mode) { return ((& python $metaPy $Db $Mode) -join '') }
function Rows([string]$Db, [string]$What, [string]$Pat = '') {
  if ($Pat -eq '') { return ((& python $rowsPy $Db $What) -join '') }
  return ((& python $rowsPy $Db $What $Pat) -join '')
}
function FtsHits([string]$Db, [string]$Term) { return ((& python $ftsPy $Db $Term) -join '') }
function HasContent([string]$Snap) {
  return ($Snap -ne '') -and ($Snap -notlike 'MISSING-DB*') -and ($Snap -notlike 'ERROR:*')
}
function Leaves([string]$Snap) {
  if ($Snap -eq '') { return '' }
  return (($Snap -split ';' | ForEach-Object { (Split-Path ($_ -replace '=\d+$','') -Leaf) + ($_ -replace '^.*(=\d+)$','$1') }) -join ',')
}

$dprojA = Join-Path $projA 'App.dproj'
$dprojB = Join-Path $projB 'Other.dproj'

Push-Location C:\TEMP
try {
  # ==========================================================================
  # 1. PROJECT SCAN: a unit dropped from the .dproj is evicted, even though the
  #    file is STILL ON DISK. This is precisely what --prune cannot catch.
  # ==========================================================================
  $dbA = Join-Path $scratch 'projA.sqlite'
  $o = & $exePath index --project $dprojA --db $dbA --platform Win64 --quiet 2>&1
  $rc = $LASTEXITCODE
  Check '1a. initial index of project A exits 0' ($rc -eq 0) "exit=$rc; $(($o | Select-Object -Last 2) -join ' | ')"
  $before = Snap $dbA
  Check '1a. both members are indexed' (($before -like '*member1.pas*') -and ($before -like '*member2.pas*')) (Leaves $before)
  $m1Before = Rows $dbA 'symbols' 'member1.pas'
  Check '1a. Member1 has symbols' ([int]$m1Before -gt 0) "symbols=$m1Before"
  $m2Before = Rows $dbA 'symbols' 'member2.pas'
  Check '1a. Member2 has symbols' ([int]$m2Before -gt 0) "symbols=$m2Before -- a zero here makes 1d vacuous"
  $ftsBefore = FtsHits $dbA 'zzqqmembertwomarker'

  # Drop Member2 from the project. THE FILE STAYS ON DISK.
  Write-ProjA $false
  Check '1b. Member2.pas is still on disk' (Test-Path (Join-Path $projA 'Member2.pas')) `
    'the whole point: prune only removes files that are GONE'

  $o = & $exePath index --project $dprojA --db $dbA --platform Win64 --recompile --quiet 2>&1
  $rc = $LASTEXITCODE
  Check '1c. recompile after the scope change exits 0' ($rc -eq 0) "exit=$rc; $(($o | Select-Object -Last 2) -join ' | ')"
  Check '1c. the run REPORTS what it evicted' `
    (@($o | Where-Object { $_.ToString() -like '*Member2.pas*' -and $_.ToString() -match '(?i)evict' }).Count -ge 1) `
    'a corpus that has been quietly wrong must announce itself once'

  $afterFiles = Rows $dbA 'files' 'member2.pas'
  Check '1d. Member2 has NO files row' ($afterFiles -eq '0') "files rows=$afterFiles"
  $afterSyms = Rows $dbA 'symbols' 'member2.pas'
  Check '1d. Member2 has NO symbols' ($afterSyms -eq '0') "symbols=$afterSyms"
  Check '1d. no orphaned symbols were left behind' ((Rows $dbA 'orphans') -eq '0') `
    "symbols with no files row=$(Rows $dbA 'orphans')"

  $m1After = Rows $dbA 'symbols' 'member1.pas'
  Check '1e. Member1 is untouched' ($m1After -eq $m1Before) "before=$m1Before after=$m1After"
  Check '1e. the .dpr survived (it is the closure root)' ((Snap $dbA) -like '*app.dpr*') (Leaves (Snap $dbA))

  if ($ftsBefore -like 'NOFTS*') {
    Write-Host "  (skip 1f: this python sqlite3 has no FTS5 -- $ftsBefore)" -ForegroundColor Yellow
  } else {
    Check '1f. the marker WAS in the fts index before eviction' ([int]$ftsBefore -gt 0) `
      "hits=$ftsBefore -- a zero here would make the next assertion vacuous"
    Check '1f. eviction left NO stranded fts5 entries' ((FtsHits $dbA 'zzqqmembertwomarker') -eq '0') `
      "string_literals must be deleted explicitly, not left to the FK cascade"
  }

  # ==========================================================================
  # 2. EVICTION IS SCOPED. Bounded to the roots THIS run walked, exactly like
  #    prune -- indexing one project must never purge another.
  # ==========================================================================
  # 2a. separate DBs: recompiling A does not reach into B's database at all.
  $dbB = Join-Path $scratch 'projB.sqlite'
  & $exePath index --project $dprojB --db $dbB --platform Win64 --quiet 2>&1 | Out-Null
  $bBefore = Snap $dbB
  Check '2a. project B indexed' (HasContent $bBefore) (Leaves $bBefore)
  & $exePath index --project $dprojA --db $dbA --platform Win64 --recompile --quiet 2>&1 | Out-Null
  Check '2a. recompiling A leaves B''s DB byte-for-byte unchanged' ((Snap $dbB) -eq $bBefore) `
    "before=$(Leaves $bBefore) after=$(Leaves (Snap $dbB))"

  # 2b. the sharper case -- ONE DB holding two projects. B's files lie outside
  #     A's roots, so A's eviction must not see them.
  $dbBoth = Join-Path $scratch 'both.sqlite'
  & $exePath index --project $dprojA --db $dbBoth --platform Win64 --quiet 2>&1 | Out-Null
  & $exePath index --project $dprojB --db $dbBoth --platform Win64 --quiet 2>&1 | Out-Null
  $bothBefore = Snap $dbBoth
  Check '2b. the shared DB holds both projects' `
    (($bothBefore -like '*bunit.pas*') -and ($bothBefore -like '*member1.pas*')) (Leaves $bothBefore)
  & $exePath index --project $dprojA --db $dbBoth --platform Win64 --recompile --quiet 2>&1 | Out-Null
  $bothAfter = Snap $dbBoth
  Check '2b. recompiling A did NOT evict project B from the shared DB' `
    ($bothAfter -like '*bunit.pas*') (Leaves $bothAfter)
  Check '2b. and it still holds A' ($bothAfter -like '*member1.pas*') (Leaves $bothAfter)

  # ==========================================================================
  # 3. LIBRARY SCAN: adding an exclude glob removes what it now covers. Same
  #    defect as the project arm, other scan type -- this is the shape that
  #    left 5 `.private\` copies in the YADF index through every reindex.
  # ==========================================================================
  $dbL = Join-Path $scratch 'lib.sqlite'
  $o = & $exePath index $lib --db $dbL --platform Win64 --quiet 2>&1
  $rc = $LASTEXITCODE
  Check '3a. initial library index exits 0' ($rc -eq 0) "exit=$rc; $(($o | Select-Object -Last 2) -join ' | ')"
  $libBefore = Snap $dbL
  Check '3a. all three units are indexed' `
    (($libBefore -like '*libone.pas*') -and ($libBefore -like '*libtwo.pas*') -and ($libBefore -like '*libthree.pas*')) (Leaves $libBefore)
  $l1Before   = Rows $dbL 'symbols' 'libone.pas'
  $l3Before   = Rows $dbL 'symbols' 'libthree.pas'
  $ftsLBefore = FtsHits $dbL 'zzqqlibtwomarker'

  $o = & $exePath index $lib --db $dbL --platform Win64 --recompile --exclude 'LibTwo.pas' --quiet 2>&1
  $rc = $LASTEXITCODE
  Check '3b. recompile with a new exclude exits 0' ($rc -eq 0) "exit=$rc; $(($o | Select-Object -Last 2) -join ' | ')"
  Check '3c. the newly excluded unit is GONE' ((Rows $dbL 'files' 'libtwo.pas') -eq '0') `
    "files rows=$(Rows $dbL 'files' 'libtwo.pas')"
  Check '3c. its symbols went with it' ((Rows $dbL 'symbols' 'libtwo.pas') -eq '0') `
    "symbols=$(Rows $dbL 'symbols' 'libtwo.pas')"
  Check '3c. LibOne survived untouched' ((Rows $dbL 'symbols' 'libone.pas') -eq $l1Before) `
    "before=$l1Before after=$(Rows $dbL 'symbols' 'libone.pas')"
  Check '3c. LibThree survived untouched' ((Rows $dbL 'symbols' 'libthree.pas') -eq $l3Before) `
    "before=$l3Before after=$(Rows $dbL 'symbols' 'libthree.pas')"
  Check '3c. no orphaned symbols' ((Rows $dbL 'orphans') -eq '0') "orphans=$(Rows $dbL 'orphans')"

  if ($ftsLBefore -like 'NOFTS*') {
    Write-Host "  (skip 3d: this python sqlite3 has no FTS5 -- $ftsLBefore)" -ForegroundColor Yellow
  } else {
    Check '3d. the library marker WAS in the fts index' ([int]$ftsLBefore -gt 0) "hits=$ftsLBefore"
    Check '3d. library eviction left NO stranded fts5 entries' ((FtsHits $dbL 'zzqqlibtwomarker') -eq '0') `
      "hits after=$(FtsHits $dbL 'zzqqlibtwomarker')"
  }

  # ==========================================================================
  # 4. CONVERGENCE AFTER A SCOPE CHANGE, for BOTH scan types. The axes are
  #    independent, so a bug can hit exactly one pairing. An index recompiled
  #    across a scope change must hold exactly what a from-scratch rebuild of
  #    the SAME scope holds -- otherwise eviction is only approximately right,
  #    and no count printed by either run would reveal it.
  # ==========================================================================
  $dbPFresh = Join-Path $scratch 'projA_fresh.sqlite'
  & $exePath index --project $dprojA --db $dbPFresh --platform Win64 --rebuild --quiet 2>&1 | Out-Null
  $recompiled = Snap $dbA
  $fresh      = Snap $dbPFresh
  Check '4a. PROJECT: recompile-after-eviction == a fresh rebuild' ($recompiled -eq $fresh) `
    "recompiled=$(Leaves $recompiled) vs fresh=$(Leaves $fresh)"
  Check '4a. and the converged content is real' (HasContent $fresh) "($fresh)"

  $dbLFresh = Join-Path $scratch 'lib_fresh.sqlite'
  & $exePath index $lib --db $dbLFresh --platform Win64 --rebuild --exclude 'LibTwo.pas' --quiet 2>&1 | Out-Null
  $libRecompiled = Snap $dbL
  $libFresh      = Snap $dbLFresh
  Check '4b. LIBRARY: recompile-after-eviction == a fresh rebuild' ($libRecompiled -eq $libFresh) `
    "recompiled=$(Leaves $libRecompiled) vs fresh=$(Leaves $libFresh)"
  Check '4b. and the converged content is real' (HasContent $libFresh) "($libFresh)"

  # ==========================================================================
  # 5. THE MANIFEST ARM EVICTS TOO. `index --all` is the run that maintains the
  #    shared corpora, so an eviction that only worked for `index --project`
  #    would leave every big index exactly as wrong as it is today.
  # ==========================================================================
  Write-ProjA $true   # put Member2 back so the section starts complete
  $mdb = 'evict.sqlite'
  $cfg = Join-Path $scratch 'manifest.drag-lint.json'
  @"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "EvictSection", "db": "$mdb", "include": ["projA\\App.dproj"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii
  $sectionDb = Join-Path $scratch "out\$mdb"

  & $exePath index --all --config $cfg --only EvictSection --jobs 1 2>&1 | Out-Null
  $secBefore = Snap $sectionDb
  Check '5a. the section indexed both members' `
    (($secBefore -like '*member1.pas*') -and ($secBefore -like '*member2.pas*')) (Leaves $secBefore)
  Sentinel $sectionDb 'set' | Out-Null

  Write-ProjA $false  # drop Member2 again, file still on disk
  $o = @(& $exePath index --all --config $cfg --only EvictSection --jobs 1 --recompile 2>&1)
  $rc = $LASTEXITCODE
  Check '5b. index --all --recompile exits 0' ($rc -eq 0) "exit=$rc"
  # WITHOUT this the rest of group 5 is vacuous: a section build that deletes
  # and recreates its .sqlite passes every "the dropped member is gone" check
  # for the wrong reason, and would keep passing after eviction was reverted.
  Check '5b. the section DB was NOT recreated -- this run was incremental' `
    ((Sentinel $sectionDb 'get') -eq 'survives-a-recompile') `
    "sentinel=$(Sentinel $sectionDb 'get'); a dropped-and-recreated DB loses it (and the IDE's open handle)"
  Check '5b. the section evicted the dropped member' ((Rows $sectionDb 'files' 'member2.pas') -eq '0') `
    "files rows=$(Rows $sectionDb 'files' 'member2.pas')"
  Check '5b. and kept the one still in the project' ((Rows $sectionDb 'files' 'member1.pas') -eq '1') `
    "files rows=$(Rows $sectionDb 'files' 'member1.pas')"
  Check '5b. no orphaned symbols in the section DB' ((Rows $sectionDb 'orphans') -eq '0') `
    "orphans=$(Rows $sectionDb 'orphans')"
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
