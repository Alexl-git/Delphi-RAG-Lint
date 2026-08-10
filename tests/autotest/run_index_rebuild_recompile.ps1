<#
  run_index_rebuild_recompile.ps1 -- the index MODE axis: --rebuild vs --recompile.

  THE TWO AXES
  ---------------------------------------------------------------------------
  SCAN TYPE (Project = the .dproj compile closure, Library = a whole folder
  tree) is declared by what the target IS. MODE (Rebuild = from scratch,
  Recompile = incremental) is chosen per run. They are independent, so a bug
  can hit exactly one pairing -- which is why the convergence claim below is
  asserted for BOTH scan types, not just the one that was easiest to write.

  THE CLAIM: CONVERGENCE
  ---------------------------------------------------------------------------
  For the same scope, `--rebuild` and `--recompile` must end up with the SAME
  index content. If they diverge, one of the two modes is lying about what the
  code contains, and there is no way to tell which from the outside: both
  report a files/symbols count and exit 0.

  WHY IT IS NOT A VACUOUS CLAIM
  ---------------------------------------------------------------------------
  Convergence on its own would pass trivially if --rebuild did nothing. Group 3
  pins the difference the flag actually makes: a DB polluted with a file that
  is NOT in the project's scope, and that lies OUTSIDE the roots this run
  walked, keeps that file under --recompile and LOSES it under --rebuild.
  Out-of-scope EVICTION (run_index_scope_eviction.ps1) is bounded to the walked
  roots exactly as --prune is, so it cannot reach the polluter here -- which is
  what keeps group 3 a live test of --rebuild rather than of eviction.

  THE FTS5 TRAP (group 3d)
  ---------------------------------------------------------------------------
  string_literals is kept in sync with its FTS5 shadow tables by AFTER DELETE
  TRIGGERS, and SQLite fires triggers for rows removed by an FK CASCADE only
  when recursive_triggers is on. A ClearAllFiles that deleted `files` and left
  string_literals to the cascade would strand the FTS index entries, and text
  search would go on matching source the DB no longer holds. Asserted through
  a MATCH against string_fts itself, NOT through `query --text`: the CLI joins
  the match back to string_literals, so it cannot see a stranded entry.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. Needs `python` on PATH.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_rebuildmode'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

$proj = Join-Path $scratch 'proj'
$lib  = Join-Path $scratch 'lib'
New-Item -ItemType Directory -Path $proj | Out-Null
New-Item -ItemType Directory -Path $lib  | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- fixture 1: a project (closure scan) ------------------------------------
Write-Ascii (Join-Path $proj 'App.dpr') @'
program App;

uses
  Member1 in 'Member1.pas',
  FormUnit in 'FormUnit.pas';

begin
  Member1.RunIt;
end.
'@

Write-Ascii (Join-Path $proj 'Member1.pas') @'
unit Member1;

interface

procedure RunIt;

implementation

const
  GREETING = 'member one speaking';

procedure RunIt;
var
  S: string;
begin
  S:= GREETING;
end;

end.
'@

Write-Ascii (Join-Path $proj 'FormUnit.pas') @'
unit FormUnit;

interface

type
  TfrmDemo = class(TObject)
    procedure btnGoClick(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TfrmDemo.btnGoClick(Sender: TObject);
begin
end;

end.
'@

Write-Ascii (Join-Path $proj 'FormUnit.dfm') @'
object frmDemo: TfrmDemo
  Left = 0
  Top = 0
  Caption = 'rebuild mode fixture'
  object btnGo: TButton
    Left = 8
    Top = 8
    Caption = 'Go'
    OnClick = btnGoClick
  end
end
'@

Write-Ascii (Join-Path $proj 'App.dproj') @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>App.dpr</MainSource>
        <ProjectVersion>20.3</ProjectVersion>
        <Platform>Win64</Platform>
        <Config Condition="'$(Config)'==''">Debug</Config>
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="App.dpr">
            <MainSource>MainSource</MainSource>
        </DelphiCompile>
        <DCCReference Include="Member1.pas"/>
        <DCCReference Include="FormUnit.pas"/>
    </ItemGroup>
</Project>
'@

# --- fixture 2: a plain folder tree (library scan) ---------------------------
Write-Ascii (Join-Path $lib 'LibAlpha.pas') @'
unit LibAlpha;

interface

function AlphaName: string;

implementation

function AlphaName: string;
begin
  Result:= 'alpha of the library tree';
end;

end.
'@

Write-Ascii (Join-Path $lib 'LibBeta.pas') @'
unit LibBeta;

interface

type
  TBetaHolder = class(TObject)
  public
    function Tag: string;
  end;

implementation

function TBetaHolder.Tag: string;
begin
  Result:= 'beta of the library tree';
end;

end.
'@

# --- fixture 3: the OUT-OF-SCOPE file used to pollute a DB -------------------
# It sits in neither tree, so no walk of proj\ or lib\ ever reaches it; --prune
# never touches it (prune only removes files that are GONE from disk, and this
# one exists); and out-of-scope eviction never touches it either, because it
# lies outside the roots either walk covers. Only a rebuild can take it out.
$outsider = Join-Path $scratch 'Outsider.pas'
Write-Ascii $outsider @'
unit Outsider;

interface

const
  OUTSIDER_MARK = 'zzqqoutsidermarker';

procedure NotInAnyScope;

implementation

procedure NotInAnyScope;
var
  S: string;
begin
  S:= 'zzqqoutsidermarker again';
end;

end.
'@

# --- helpers ----------------------------------------------------------------
# Content snapshot: one line per indexed file, lowercased path + its symbol
# count. That is the whole comparable surface of an index for this purpose --
# which files, and how much was extracted from each.
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

# schema_meta sentinel: proves --rebuild deletes ROWS, not the FILE. A dropped
# and recreated database would take this row with it.
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
                  "('rebuild_sentinel', 'survives-a-rebuild')")
        c.commit()
        print('SET')
    else:
        r = c.execute("SELECT value FROM schema_meta WHERE key = 'rebuild_sentinel'").fetchone()
        print(r[0] if r else 'GONE')
except sqlite3.Error as e:
    print('ERROR:' + str(e))
c.close()
'@ | Set-Content $metaPy -Encoding ascii

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

function Snap([string]$Db)      { return ((& python $snapPy $Db) -join '') }
function Sentinel([string]$Db, [string]$Mode) { return ((& python $metaPy $Db $Mode) -join '') }
function FtsHits([string]$Db, [string]$Term)  { return ((& python $ftsPy $Db $Term) -join '') }
# A snapshot only counts as CONTENT when it is neither empty nor one of the
# probe's own error markers -- 'MISSING-DB' compares equal to 'MISSING-DB', and
# a convergence assertion that passes because BOTH runs failed is worthless.
function HasContent([string]$Snap) {
  return ($Snap -ne '') -and ($Snap -notlike 'MISSING-DB*') -and ($Snap -notlike 'ERROR:*')
}
function Leaves([string]$Snap)  {
  if ($Snap -eq '') { return '' }
  return (($Snap -split ';' | ForEach-Object { (Split-Path ($_ -replace '=\d+$','') -Leaf) + ($_ -replace '^.*(=\d+)$','$1') }) -join ',')
}

$dproj = Join-Path $proj 'App.dproj'

Push-Location C:\TEMP
try {
  # ==========================================================================
  # 1. PROJECT scan: the two modes converge on the same content
  # ==========================================================================
  $dbPR = Join-Path $scratch 'proj_rebuild.sqlite'
  $dbPC = Join-Path $scratch 'proj_recompile.sqlite'

  $o = & $exePath index --project $dproj --db $dbPR --platform Win64 --rebuild --quiet 2>&1
  $rc = $LASTEXITCODE
  Check 'index --project --rebuild exits 0' ($rc -eq 0) "exit=$rc; $(($o | Select-Object -Last 2) -join ' | ')"

  $o = & $exePath index --project $dproj --db $dbPC --platform Win64 --recompile --quiet 2>&1
  $rc = $LASTEXITCODE
  Check 'index --project --recompile exits 0' ($rc -eq 0) "exit=$rc; $(($o | Select-Object -Last 2) -join ' | ')"

  $snapA = Snap $dbPR
  $snapB = Snap $dbPC
  Write-Host ("  project rebuild  : {0}" -f (Leaves $snapA))
  Write-Host ("  project recompile: {0}" -f (Leaves $snapB))
  Check 'PROJECT scan: rebuild and recompile converge' ($snapA -eq $snapB) `
    "A=$(Leaves $snapA) vs B=$(Leaves $snapB)"
  Check 'PROJECT scan: the converged content is real' (HasContent $snapA) `
    "an empty or unreadable index would make the convergence assertion vacuous ($snapA)"

  # --recompile passed explicitly must be indistinguishable from passing neither
  $dbPD = Join-Path $scratch 'proj_default.sqlite'
  & $exePath index --project $dproj --db $dbPD --platform Win64 --quiet 2>&1 | Out-Null
  Check 'PROJECT scan: --recompile == the default (no mode flag)' ((Snap $dbPD) -eq $snapB)

  # ==========================================================================
  # 2. LIBRARY scan (a folder tree): the same convergence
  # ==========================================================================
  $dbLR = Join-Path $scratch 'lib_rebuild.sqlite'
  $dbLC = Join-Path $scratch 'lib_recompile.sqlite'

  $o = & $exePath index $lib --db $dbLR --platform Win64 --rebuild --quiet 2>&1
  $rc = $LASTEXITCODE
  Check 'index <folder> --rebuild exits 0' ($rc -eq 0) "exit=$rc; $(($o | Select-Object -Last 2) -join ' | ')"

  $o = & $exePath index $lib --db $dbLC --platform Win64 --recompile --quiet 2>&1
  $rc = $LASTEXITCODE
  Check 'index <folder> --recompile exits 0' ($rc -eq 0) "exit=$rc; $(($o | Select-Object -Last 2) -join ' | ')"

  $snapC = Snap $dbLR
  $snapD = Snap $dbLC
  Write-Host ("  library rebuild  : {0}" -f (Leaves $snapC))
  Write-Host ("  library recompile: {0}" -f (Leaves $snapD))
  Check 'LIBRARY scan: rebuild and recompile converge' ($snapC -eq $snapD) `
    "C=$(Leaves $snapC) vs D=$(Leaves $snapD)"
  Check 'LIBRARY scan: the converged content is real' (HasContent $snapC) "($snapC)"

  # ==========================================================================
  # 3. WHAT --rebuild ACTUALLY DOES. Same scope, but the DB already holds a
  #    file that scope does not contain.
  # ==========================================================================
  $dbPol = Join-Path $scratch 'polluted.sqlite'
  & $exePath index --project $dproj --db $dbPol --platform Win64 --quiet 2>&1 | Out-Null
  & $exePath index $outsider --db $dbPol --platform Win64 --quiet 2>&1 | Out-Null

  $polluted = Snap $dbPol
  Check '3a. the pollution landed' ($polluted -like '*outsider.pas*') (Leaves $polluted)
  Sentinel $dbPol 'set' | Out-Null
  $ftsBefore = FtsHits $dbPol 'zzqqoutsidermarker'

  # the CONTROL: --recompile leaves the out-of-scope file alone, because it sits
  # OUTSIDE the roots this run walked, and eviction -- like prune -- is bounded
  # to those roots. Indexing one project must never purge another's rows from a
  # shared DB.
  $dbPol2 = Join-Path $scratch 'polluted_recompile.sqlite'
  Copy-Item $dbPol $dbPol2 -Force
  & $exePath index --project $dproj --db $dbPol2 --platform Win64 --recompile --quiet 2>&1 | Out-Null
  Check '3b. CONTROL: --recompile KEEPS the out-of-root file' ((Snap $dbPol2) -like '*outsider.pas*') `
    'if this ever fails, eviction stopped being bounded and the convergence assertions above stopped meaning anything'

  # the REBUILD
  $o = & $exePath index --project $dproj --db $dbPol --platform Win64 --rebuild --quiet 2>&1
  $rc = $LASTEXITCODE
  Check '3c. --rebuild over a polluted DB exits 0' ($rc -eq 0) "exit=$rc; $(($o | Select-Object -Last 2) -join ' | ')"
  $rebuilt = Snap $dbPol
  Check '3c. --rebuild REMOVED the out-of-scope file' (-not ($rebuilt -like '*outsider.pas*')) (Leaves $rebuilt)
  Check '3c. --rebuild converged on the clean project content' ($rebuilt -eq $snapA) `
    "rebuilt=$(Leaves $rebuilt) vs clean=$(Leaves $snapA)"

  # 3d. the FTS5 shadow tables went with it
  $ftsAfter = FtsHits $dbPol 'zzqqoutsidermarker'
  if ($ftsBefore -like 'NOFTS*') {
    Write-Host "  (skip 3d: this python sqlite3 has no FTS5 -- $ftsBefore)" -ForegroundColor Yellow
  } else {
    Check '3d. the marker WAS in the fts index before the rebuild' ([int]$ftsBefore -gt 0) `
      "hits=$ftsBefore -- a zero here would make the next assertion vacuous"
    Check '3d. --rebuild left NO stranded fts5 entries' ($ftsAfter -eq '0') `
      "hits after rebuild=$ftsAfter (string_literals must be deleted explicitly, not left to the FK cascade)"
  }

  # 3e. rows, not the file: the schema_meta sentinel survived
  Check '3e. --rebuild deletes ROWS, not the DB file' ((Sentinel $dbPol 'get') -eq 'survives-a-rebuild') `
    'a dropped-and-recreated DB would lose this schema_meta row (and any settings beside it)'

  # ==========================================================================
  # 4. --rebuild is idempotent -- running it twice neither doubles nor loses
  # ==========================================================================
  & $exePath index --project $dproj --db $dbPol --platform Win64 --rebuild --quiet 2>&1 | Out-Null
  Check '4. a second --rebuild produces identical content' ((Snap $dbPol) -eq $snapA) (Leaves (Snap $dbPol))

  # ==========================================================================
  # 5. --dry-run must not wipe. "Show me what you would do" that empties the
  #    index on the way past is the worst possible reading of the flag.
  # ==========================================================================
  $dbDry = Join-Path $scratch 'dryrun.sqlite'
  & $exePath index --project $dproj --db $dbDry --platform Win64 --quiet 2>&1 | Out-Null
  $beforeDry = Snap $dbDry
  & $exePath index --project $dproj --db $dbDry --platform Win64 --rebuild --dry-run --quiet 2>&1 | Out-Null
  Check '5. --rebuild --dry-run leaves the index untouched' ((Snap $dbDry) -eq $beforeDry) `
    "before=$(Leaves $beforeDry) after=$(Leaves (Snap $dbDry))"

  # ==========================================================================
  # 6. the two modes are mutually exclusive -- a usage error, not a precedence
  #    rule nobody can remember
  # ==========================================================================
  $bout = & $exePath index --project $dproj --db (Join-Path $scratch 'both.sqlite') --rebuild --recompile 2>&1
  $brc  = $LASTEXITCODE
  Check '6. --rebuild --recompile together exits 2' ($brc -eq 2) "exit=$brc; $(($bout | Select-Object -Last 2) -join ' | ')"
  Check '6. the error names both flags' `
    (@($bout | Where-Object { $t = $_.ToString(); ($t -like '*ERROR*') -and ($t -like '*--rebuild*') -and ($t -like '*--recompile*') }).Count -ge 1) `
    (($bout | Select-Object -Last 2) -join ' | ')

  # ==========================================================================
  # 7. THE MANIFEST ARM HONOURS THE MODE AXIS.
  #
  #    It did not. BuildPlanItem DELETED each section's .sqlite before the walk,
  #    so every `index --all` was an unconditional full rebuild, `--recompile`
  #    was accepted and ignored (it warned and continued), and the file handle
  #    went out from under anyone holding the DB open -- the IDE design-time
  #    plugin holds one for a whole session.
  #
  #    Now the mode decides: --rebuild clears ROWS (ClearAllFiles, the file and
  #    its handle survive), --recompile (the default) walks incrementally. The
  #    warning is gone because the flag no longer lies. What must NOT come back
  #    is a warning on a run where the mode was merely DEFAULTED -- nobody asked
  #    for anything else, and a warning on every run is a warning nobody reads.
  # ==========================================================================
  $mdb = 'section.sqlite'
  $cfg = Join-Path $scratch 'manifest.drag-lint.json'
  @"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "ModeSection", "db": "$mdb", "include": ["proj\\App.dproj"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii
  $sectionDb = Join-Path $scratch "out\$mdb"

  function WarnLines($Out) {
    return @($Out | Where-Object { $t = $_.ToString(); ($t -like '*--recompile*') -and (($t -like '*WARNING*') -or ($t -like '*NOTE:*')) })
  }

  # 7a. the baseline: a plain `index --all`, mode defaulted.
  Remove-Item $sectionDb -Force -ErrorAction SilentlyContinue
  $aout = @(& $exePath index --all --config $cfg --only ModeSection --jobs 1 2>&1)
  $arc  = $LASTEXITCODE
  Check '7a. a plain index --all exits 0' ($arc -eq 0) "exit=$arc"
  Check '7a. NO warning when the mode was merely defaulted' ((WarnLines $aout).Count -eq 0) `
    "a warning on every run is a warning nobody reads (matched=$((WarnLines $aout).Count))"
  $asnap = Snap $sectionDb
  Check '7a. it built a correct index' `
    ((HasContent $asnap) -and ($asnap -like '*app.dpr*') -and ($asnap -like '*formunit.dfm*')) (Leaves $asnap)

  # 7b. --recompile is HONOURED now: no warning, no wipe, same content. The
  #     sentinel is the load-bearing part -- it is the only assertion that can
  #     tell an incremental walk apart from a full rebuild that happens to
  #     produce the same rows.
  Sentinel $sectionDb 'set' | Out-Null
  $bout2 = @(& $exePath index --all --config $cfg --only ModeSection --jobs 1 --recompile 2>&1)
  $brc2  = $LASTEXITCODE
  Check '7b. index --all --recompile exits 0' ($brc2 -eq 0) "exit=$brc2"
  Check '7b. NO warning -- the flag now does what it says' ((WarnLines $bout2).Count -eq 0) `
    "matched=$((WarnLines $bout2).Count); $(($bout2 | Where-Object { $_.ToString() -like '*--recompile*' } | Select-Object -First 1) -join '')"
  Check '7b. --recompile did NOT recreate the section DB' ((Sentinel $sectionDb 'get') -eq 'survives-a-rebuild') `
    "sentinel=$(Sentinel $sectionDb 'get') -- a deleted-and-recreated .sqlite loses it, and drops the handle the IDE plugin holds"
  Check '7b. and the content is unchanged' ((Snap $sectionDb) -eq $asnap) (Leaves (Snap $sectionDb))

  # 7c. --rebuild on the manifest arm: clears ROWS, keeps the FILE. Pollute the
  #     section DB with the out-of-root Outsider first, so "cleared" is visible.
  & $exePath index $outsider --db $sectionDb --platform Win64 --quiet 2>&1 | Out-Null
  Check '7c. the pollution landed' ((Snap $sectionDb) -like '*outsider.pas*') (Leaves (Snap $sectionDb))
  $cout = @(& $exePath index --all --config $cfg --only ModeSection --jobs 1 --rebuild 2>&1)
  $crc  = $LASTEXITCODE
  Check '7c. index --all --rebuild exits 0' ($crc -eq 0) "exit=$crc"
  Check '7c. --rebuild removed the out-of-scope file' (-not ((Snap $sectionDb) -like '*outsider.pas*')) (Leaves (Snap $sectionDb))
  Check '7c. --rebuild deletes ROWS, not the DB file' ((Sentinel $sectionDb 'get') -eq 'survives-a-rebuild') `
    'a dropped-and-recreated DB would lose this schema_meta row (and any settings beside it)'
  Check '7c. --rebuild converged on the clean section content' ((Snap $sectionDb) -eq $asnap) (Leaves (Snap $sectionDb))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
