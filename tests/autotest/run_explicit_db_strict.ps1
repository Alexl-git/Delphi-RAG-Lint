<#
  run_explicit_db_strict.ps1 --
  An explicit `--db` naming a file that does not exist must REFUSE the run.

  THE DEFECT. Most verbs do `if not TFile.Exists(Db) then Continue;` -- they drop
  the missing database and answer from whatever is left, exit 0, with nothing on
  either stream. So `convert-scaffold --db app --db lib-typo` drafts rules from
  the app index alone, `convert-validate` then validates against that same short
  corpus and succeeds, and `convert-apply` rewrites a form on the strength of it.
  Every downstream step inherits the error while reporting success.

  Reported by the converter team 2026-09-09 against `proptree`; the owner ruled on
  2026-09-14 that it must be strict everywhere -- "without stricter type matching
  we cannot reliably convert or create conversion rules". A full audit then found
  40 sites, 31 needing the change, including three `query` subcommands (so `query`
  was not even self-consistent) and `lint <file>`, which silently drops the
  store-backed rules and reports FEWER findings: measured 429 with a good index
  vs 422 with a missing one, same exit code, silence on both streams.

  WHAT MAKES THIS GUARD HONEST. T1-T7 assert the refusal. On their own they would
  all pass against a build that exits 2 unconditionally -- i.e. against a
  completely broken engine. P1-P4 are the positive controls that forbid that
  reading, and V is the vacuity check. Do not delete a P row to make a run green.

  THE RED REQUIREMENT. Run this against the SHIPPED exe BEFORE building the fix.
  T1-T7 must FAIL for the lenient verbs and PASS for `query` (already strict); P1-P4
  must already PASS. A guard that is green before the fix is not evidence.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_explicit_db_strict",
  [switch]$ListRedOnly   # print a RED/GREEN matrix and exit 0 -- for capturing evidence pre-fix
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

# An orphaned engine holding a fixture DB turns every row below into a lock error
# that reads as a failure. Say so up front rather than letting it look like one.
$orphans = @(Get-Process drag-lint -ErrorAction SilentlyContinue)
if ($orphans.Count -gt 0) {
  Write-Host "NOTE: $($orphans.Count) drag-lint process(es) already running (LSP servers are normal)." -ForegroundColor DarkYellow
}

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
$srcA = Join-Path $WorkDir 'a'; $srcB = Join-Path $WorkDir 'b'
New-Item -ItemType Directory -Path $srcA -Force | Out-Null
New-Item -ItemType Directory -Path $srcB -Force | Out-Null

Write-Ascii (Join-Path $srcA 'uAlpha.pas') @'
unit uAlpha;

interface

type
  TAlphaBase = class(TObject)
  private
    FTag: Integer;
  public
    procedure Touch;
    property Tag: Integer read FTag write FTag;
  end;

implementation

procedure TAlphaBase.Touch;
var
  Scratch: Integer;
begin
  if FTag > 0 then
    Scratch := FTag * 2;
  FTag := Scratch;
end;

end.
'@

Write-Ascii (Join-Path $srcB 'uBeta.pas') @'
unit uBeta;

interface

type
  TBetaThing = class(TObject)
  public
    procedure Run;
  end;

implementation

uses
  System.SysUtils;

procedure TBetaThing.Run;
var
  I: Integer;
  S: string;
begin
  for I := 0 to 3 do
    if I > 1 then
      S := IntToStr(I);
  if S = '' then
    Exit;
end;

end.
'@

# A form + its .dfm, so the four convert-* verbs have something real to convert.
# All four must be in the stale matrix: each resolves types through its OWN db
# loop, and a verb left out of the matrix stays lenient without anything saying so.
Write-Ascii (Join-Path $srcA 'uForm.pas') @'
unit uForm;

interface

uses
  uAlpha;

type
  TMyForm = class(TObject)
  published
    alpha1: TAlphaBase;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $srcA 'uForm.dfm') @'
object MyForm: TMyForm
  object alpha1: TAlphaBase
    Tag = 1
  end
end
'@

$dbA   = Join-Path $WorkDir 'a.sqlite'
$dbB   = Join-Path $WorkDir 'b.sqlite'
$ghost = Join-Path $WorkDir 'ghost.sqlite'
$ghos2 = Join-Path $WorkDir 'ghost2.sqlite'
$rules = (Resolve-Path "$PSScriptRoot\..\..\rules").Path

# Conversion rules + a DFM object block for convert-reemit. The rules file is a
# DIRECTIVE format, not JSON -- a JSON body parses as prose and the verb bails
# before it ever opens a database, which would fake a pass on every stale row.
$convRules = Join-Path $WorkDir 'rules.txt'
$convBlock = Join-Path $WorkDir 'block.txt'
Write-Ascii $convRules "#convert TAlphaBase -> TBetaThing, uBeta`r`n"
Write-Ascii $convBlock "object alpha1: TAlphaBase`r`n  Tag = 1`r`nend`r`n"

& $exePath index $srcA --db $dbA 2>&1 | Out-Null
& $exePath index $srcB --db $dbB 2>&1 | Out-Null

$out = Join-Path $WorkDir 'o.txt'
$err = Join-Path $WorkDir 'e.txt'

# THE GHOST MUST BE DELETED BEFORE EVERY SINGLE RUN, AND THIS IS NOT FUSSINESS.
#
# The first version of this harness created the ghost path once and let the
# matrix run. Some verb OPENED it for write, and SQLite happily created an empty
# database there -- so every verb that ran later in the matrix was handed an
# existing (empty) index and legitimately exited 0. Those zeroes were recorded as
# "still lenient" when they were nothing of the kind, and a verb already strict
# (`query --name`) appeared lenient purely because it ran fifteenth.
#
# A guard whose own fixture is mutated by the thing under test measures the order
# of its rows. So: reset before each invocation, and record WHO created the file,
# which is itself a finding worth reporting rather than a nuisance to suppress.
$script:creators = @()
function Reset-Ghosts {
  foreach ($g in @($ghost, $ghos2)) { if (Test-Path $g) { Remove-Item $g -Force -ErrorAction SilentlyContinue } }
}

# stdout and stderr SPLIT: T3 asserts stdout stays empty, which a merged stream
# could not see.
function Run-Verb([string[]]$VerbArgs, [int]$TimeoutSec = 90, [string]$Label = '') {
  Reset-Ghosts
  $p = Start-Process -FilePath $exePath -ArgumentList $VerbArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WorkingDirectory 'C:\TEMP'
  if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill($true) } catch {}; return @{ Code = -1; Out=''; Err='(timed out)' } }
  $made = @(@($ghost, $ghos2) | Where-Object { Test-Path $_ } | ForEach-Object { Split-Path $_ -Leaf })
  if ($made.Count -gt 0 -and $Label -ne '') { $script:creators += ("{0} -> {1}" -f $Label, ($made -join '+')) }
  Reset-Ghosts
  return @{
    Code = $p.ExitCode
    Out  = ((Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue) + '')
    Err  = ((Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue) + '')
  }
}

# The engine prints "(loaded defaults from ...)" on stderr on every run, and the
# lint verbs print a progress channel there too. Neither is an answer, so T3's
# "stdout is empty" must ignore banner-ish stdout lines only.
function StdoutIsSilent([string]$T) {
  $lines = @(($T -split "`r?`n") | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\(loaded defaults' })
  return ($lines.Count -eq 0)
}

# Each row: Name, args WITHOUT --db, whether it is an already-strict control.
# Arguments were taken from `--help` verbatim: a wrong flag exits 3 ("Unknown
# argument") which would look exactly like strictness and fake a pass. V below
# catches that by requiring the good-DB run to actually work.
$fileA = (Join-Path $srcA 'uAlpha.pas')
$matrix = @(
  @{ N='proptree';          A=@('proptree','--qname','uAlpha.TAlphaBase','--depth','1'); Strict=$false }
  @{ N='reverse-calltree';  A=@('reverse-calltree','--qname','uAlpha.TAlphaBase.Touch'); Strict=$false }
  @{ N='butterfly';         A=@('butterfly','--qname','uAlpha.TAlphaBase.Touch');        Strict=$false }
  @{ N='hover';             A=@('hover','--qname','uAlpha.TAlphaBase');                  Strict=$false }
  @{ N='usages';            A=@('usages','--name','Touch');                              Strict=$false }
  @{ N='typeat';            A=@('typeat',"$($fileA):8:15");                              Strict=$false }
  @{ N='find-unit';         A=@('find-unit','--name','TBetaThing','--in',$fileA);         Strict=$false }
  @{ N='lint';              A=@('lint',$fileA,'--rules-dir',$rules);                      Strict=$false }
  @{ N='lint-all';          A=@('lint-all','--rules-dir',$rules);                         Strict=$false }
  @{ N='check-ast';         A=@('check-ast',$fileA);                                      Strict=$false }
  @{ N='wiring';            A=@('wiring','--coverage');                                   Strict=$false }
  @{ N='exceptions-sync';   A=@('exceptions-sync');                                       Strict=$false }
  @{ N='deps-report';       A=@('deps-report');                                           Strict=$false }
  @{ N='convert-scaffold';  A=@('convert-scaffold','--from','uAlpha.TAlphaBase','--to','uBeta.TBetaThing'); Strict=$false }
  @{ N='query --name';      A=@('query','--name','TAlphaBase');                            Strict=$true  }
  @{ N='query type-usage';  A=@('query','type-usage','--in',$fileA,'--names','TAlphaBase'); Strict=$false }
)

Check 'V the verb matrix is populated' ($matrix.Count -ge 15) "only $($matrix.Count) verb(s)"

# ---- P1 POSITIVE CONTROL: every verb actually WORKS with two good DBs --------
# Without this, T1-T7 pass against a build that exits 2 for everything.
$brokenGood = @()
foreach ($m in $matrix) {
  $r = Run-Verb ($m.A + @('--db',$dbA,'--db',$dbB))
  # 0 = answered; 1 = a legitimate "not found / findings present" answer for
  # several of these verbs. 2 or 3 means the invocation itself is wrong.
  if ($r.Code -ge 2) { $brokenGood += ("{0} (exit {1}: {2})" -f $m.N, $r.Code, (($r.Out + $r.Err) -split "`r?`n" | Where-Object { $_ -match 'ERROR|FATAL|Unknown' } | Select-Object -First 1)) }
}
Check 'P1 POSITIVE CONTROL every verb answers with two GOOD --db' ($brokenGood.Count -eq 0) `
      ("these did not work even with valid databases, so their T-rows would be meaningless: " + ($brokenGood -join ' | '))

# ---- P3 POSITIVE CONTROL: silence when everything exists ---------------------
$quiet = Run-Verb (@('proptree','--qname','uAlpha.TAlphaBase','--depth','1','--db',$dbA,'--db',$dbB))
Check 'P3 POSITIVE CONTROL two good --db produce NO "does not exist" line' `
      (($quiet.Err -notmatch 'does not exist') -and ($quiet.Out -notmatch 'does not exist')) `
      'the error fires when nothing is wrong'

# ---- T1/T2/T3: the refusal ---------------------------------------------------
$t1 = @(); $t2 = @(); $t3 = @()
foreach ($m in $matrix) {
  $r = Run-Verb ($m.A + @('--db',$dbA,'--db',$ghost)) 90 $m.N
  if ($r.Code -ne 2) { $t1 += ("{0}=exit{1}" -f $m.N, $r.Code) }
  $both = $r.Out + "`n" + $r.Err
  if (($both -notmatch 'ghost\.sqlite') -or ($both -notmatch '#2 of 2')) {
    $t2 += ("{0}[{1}]" -f $m.N, $(if($both -match 'ghost\.sqlite'){'no-ordinal'}else{'unnamed'}))
  }
  if (-not (StdoutIsSilent $r.Out)) { $t3 += $m.N }
}
Check 'T1 a missing explicit --db exits 2 on every verb' ($t1.Count -eq 0) `
      ("still not 2: " + ($t1 -join ', '))
Check 'T2 the message names the ghost path AND its ordinal (#2 of 2)' ($t2.Count -eq 0) `
      ("incomplete message: " + ($t2 -join ', '))
Check 'T3 stdout carries NO partial answer when a --db is missing' ($t3.Count -eq 0) `
      ("answered anyway on stdout: " + ($t3 -join ', '))

# ---- T4: a single missing --db --------------------------------------------
$t4 = @()
foreach ($m in $matrix) {
  $r = Run-Verb ($m.A + @('--db',$ghost)) 90 $m.N
  if (($r.Code -ne 2) -or ($($r.Out + $r.Err) -notmatch '#1 of 1')) { $t4 += ("{0}=exit{1}" -f $m.N, $r.Code) }
}
Check 'T4 a single missing --db exits 2 and says "#1 of 1"' ($t4.Count -eq 0) `
      ("degraded silently or mis-numbered: " + ($t4 -join ', '))

# ---- T6: ordinal is the POSITION, not a constant ----------------------------
$first = Run-Verb @('proptree','--qname','uAlpha.TAlphaBase','--db',$ghost,'--db',$dbA)
$last  = Run-Verb @('proptree','--qname','uAlpha.TAlphaBase','--db',$dbA,'--db',$ghost)
Check 'T6 the ordinal tracks the position in the argument list' `
      ((($first.Out + $first.Err) -match '#1 of 2') -and (($last.Out + $last.Err) -match '#2 of 2')) `
      "first-position run should say '#1 of 2', last-position '#2 of 2'"

# ---- T7: EVERY missing path is named, not just the first --------------------
$two = Run-Verb @('proptree','--qname','uAlpha.TAlphaBase','--db',$ghost,'--db',$ghos2)
$twoText = $two.Out + $two.Err
Check 'T7 two missing --db name BOTH (one run, not two)' `
      (($twoText -match 'ghost\.sqlite') -and ($twoText -match 'ghost2\.sqlite')) `
      'only the first missing path was reported, so a second typo costs another round trip'

# ---- V: the refusal must not CREATE what it refused -------------------------
# `serve` creates an empty SQLite file at a missing --db path today. Any verb
# that does this manufactures an authoritative-looking empty index from a typo.
Check 'V no verb CREATED the database it was told did not exist' `
      ($script:creators.Count -eq 0) `
      ("these manufactured an empty index from a typo, which then answers 'nothing' convincingly: " +
       (($script:creators | Select-Object -Unique) -join ', '))

# ---- P2 POSITIVE CONTROL: the manifest path is untouched --------------------
# With NO --db the engine resolves through the manifest, which already drops
# absent files. If the new check leaked into that path, this turns red.
$noDb = Run-Verb @('proptree','--qname','uAlpha.TAlphaBase','--depth','1')
Check 'P2 POSITIVE CONTROL a run with NO --db is not hit by the new error' `
      (($noDb.Err -notmatch 'does not exist:') -and ($noDb.Out -notmatch 'does not exist:')) `
      "manifest-resolved runs must be unaffected; got exit $($noDb.Code)"

# =============================================================================
# T5 -- THE STALE-SCHEMA HALF. A --db that EXISTS but sits at an old schema.
#
# Same hazard as a missing one, different cause: the verb answers from fewer
# stores than the operator named and exits 0. The CLI already contradicted
# itself here -- single-DB verbs refuse a stale DB with a non-zero exit while
# the multi-DB loops skipped it and carried on.
#
# TWO THINGS THIS ARM GETS RIGHT THAT THE OBVIOUS VERSION GETS WRONG:
#
# 1. THE STALE DB GOES FIRST (--db v12 --db a). Measured 2026-09-14: with the
#    stale db SECOND, proptree / butterfly / reverse-calltree / hover resolve the
#    qname from `a`, Break, and NEVER OPEN the stale database -- so the site under
#    test never runs and the row passes for a reason that has nothing to do with
#    staleness. Stale-first is the only ordering that reaches the code.
#
# 2. THE FIXTURE IS RECREATED BEFORE EVERY RUN. Measured the same day: a stale
#    db handed to `usages`, `typeat` or `deps-report` was MIGRATED IN PLACE
#    (schema_version 12 -> 22, 4 tables -> 31, 28 KB -> 320 KB, exit 0, silence).
#    One such row leaves every later row reading a CURRENT database. This is the
#    ghost-DB lesson again: a guard whose fixture is mutated by the thing under
#    test measures the order of its rows.
#
#    Those three verbs were kept OUT of this matrix while C3 shipped, because C3
#    did not fix them and a guard that is red for unfixed work teaches people to
#    ignore it. They joined on 2026-09-14 (session 93, W1) as the RED half of
#    their fix -- T5d is the row that turns green when they stop migrating, and
#    P5 is what proves they still answer afterwards.
# =============================================================================
$py   = Join-Path $WorkDir 'mk_v12.py'
$dbV12 = Join-Path $WorkDir 'v12.sqlite'
# THE STALE FIXTURE MUST CONTAIN THE FILES, NOT JUST THE SCHEMA.
#
# An EMPTY v12 database is a weaker fixture than it looks. `query unit-usage` and
# `query type-usage` call DbContainsFile(db, file) BEFORE they open the store, and
# an empty `files` table makes that probe answer "not mine" -- truthfully -- so
# the stale-schema check below it never runs and the row passes for the wrong
# reason. A real stale project index DOES hold the file. So the fixture inserts
# one row per source file, spelled the way DbContainsFile normalises a path:
# ExpandFileName, backslashes, upper-case drive letter.
Write-Ascii $py @'
import sqlite3, sys, os
c = sqlite3.connect(sys.argv[1])
c.executescript("""
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta(key, value) VALUES ('schema_version', '12');
CREATE TABLE files (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE,
  mtime_unix INTEGER NOT NULL, sha256 TEXT NOT NULL,
  parsed_at INTEGER NOT NULL, language TEXT NOT NULL);
CREATE TABLE symbols (id INTEGER PRIMARY KEY,
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  parent_id INTEGER REFERENCES symbols(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, name TEXT NOT NULL, qualified_name TEXT NOT NULL,
  signature TEXT, modifiers TEXT, section TEXT, heritage TEXT,
  is_virtual INTEGER, start_line INTEGER NOT NULL, start_col INTEGER NOT NULL,
  end_line INTEGER NOT NULL, end_col INTEGER NOT NULL,
  impl_start_line INTEGER, impl_end_line INTEGER);
CREATE TABLE refs (id INTEGER PRIMARY KEY,
  symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL,
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, name_text TEXT NOT NULL,
  start_line INTEGER NOT NULL, start_col INTEGER NOT NULL,
  end_line INTEGER NOT NULL, end_col INTEGER NOT NULL);
""")
for i, f in enumerate(sys.argv[2:], start=1):
    p = os.path.abspath(f).replace('/', '\\')
    if len(p) > 1 and p[1] == ':':
        p = p[0].upper() + p[1:]
    c.execute("INSERT INTO files(id, path, mtime_unix, sha256, parsed_at, language)"
              " VALUES (?, ?, 0, '', 0, 'pascal')", (i, p))
c.commit(); c.close()
'@

function Reset-StaleDb {
  foreach ($s in @($dbV12, "$dbV12-wal", "$dbV12-shm")) {
    if (Test-Path $s) { Remove-Item $s -Force -ErrorAction SilentlyContinue }
  }
  python $py $dbV12 $fileA (Join-Path $srcA 'uForm.pas') 2>&1 | Out-Null
}
function Get-StaleSchemaVersion {
  # 'NONE' when schema_meta is gone; the number otherwise. A migration moves it.
  $q = 'import sqlite3,sys' + "`n" +
       'c=sqlite3.connect(sys.argv[1])' + "`n" +
       'try:' + "`n" +
       '    r=c.execute("select value from schema_meta where key=' + "'schema_version'" + '").fetchone()' + "`n" +
       '    print(r[0] if r else "NONE")' + "`n" +
       'except Exception:' + "`n" +
       '    print("ERR")' + "`n"
  $qf = Join-Path $WorkDir 'ver.py'
  Write-Ascii $qf $q
  return (python $qf $dbV12 2>&1 | Select-Object -Last 1)
}

function Get-StaleFileCount {
  $qf = Join-Path $WorkDir 'cnt.py'
  Write-Ascii $qf ("import sqlite3,sys" + "`n" +
                   "c=sqlite3.connect(sys.argv[1])" + "`n" +
                   "try:" + "`n" +
                   "    print(c.execute('select count(*) from files').fetchone()[0])" + "`n" +
                   "except Exception:" + "`n" +
                   "    print('ERR')" + "`n")
  return (python $qf $dbV12 2>&1 | Select-Object -Last 1)
}

Reset-StaleDb
$havePython = (Test-Path $dbV12) -and ((Get-StaleSchemaVersion) -eq '12')
Check 'V the stale-schema fixture is really at v12 (python available)' $havePython `
      'no usable python3 / sqlite3 -- T5 cannot run, and a skipped arm is not a pass'
# Without this the fixture can silently regress to an empty `files` table, and the
# membership pre-check in the two unit/type-usage verbs then skips the stale db
# truthfully -- passing T5 without ever reaching the code it is meant to test.
Check 'V the stale fixture CONTAINS the source files (membership probe must say yes)' `
      ((Get-StaleFileCount) -eq '2') `
      "files rows = $(Get-StaleFileCount), expected 2 -- an empty stale index is skipped as 'not mine' before the schema is ever checked"

if ($havePython) {
  # Stale db FIRST. Args are the same shape as the matrix above, plus the four
  # convert verbs, which need a unit/rules/block of their own.
  #
  # `uses-fix <unit>` requires --project or it exits 2 with a usage line before
  # opening any database. The file only has to EXIST -- DoUsesFix opens the
  # store before it uses the project -- so a one-line stub is enough and keeps
  # the row honest without dragging a buildable project into this fixture.
  $dummyDproj = Join-Path $WorkDir 'stub.dproj'
  Write-Ascii $dummyDproj '<Project></Project>'

  $staleMatrix = @(
    @{ N='proptree';         A=@('proptree','--qname','uAlpha.TAlphaBase','--depth','1') }
    @{ N='reverse-calltree'; A=@('reverse-calltree','--qname','uAlpha.TAlphaBase.Touch') }
    @{ N='butterfly';        A=@('butterfly','--qname','uAlpha.TAlphaBase.Touch') }
    @{ N='find-unit';        A=@('find-unit','--name','TBetaThing','--in',$fileA) }
    @{ N='resolve-uses';     A=@('resolve-uses','--name','TBetaThing','--in',$fileA) }
    @{ N='query --name';     A=@('query','--name','TAlphaBase') }
    @{ N='query --text';     A=@('query','--text','hello world') }
    @{ N='query type-usage'; A=@('query','type-usage','--in',$fileA,'--names','TAlphaBase') }
    @{ N='query unit-usage'; A=@('query','unit-usage','--unit','uAlpha','--in',$fileA) }
    @{ N='convert-scaffold'; A=@('convert-scaffold','--from','uAlpha.TAlphaBase','--to','uBeta.TBetaThing') }
    # --from/--to are LOAD-BEARING here: convert-validate's TreeFor returns
    # immediately on an empty qname, so without them the verb never opens a
    # database at all and the row would pass without testing anything.
    @{ N='convert-validate'; A=@('convert-validate','--rules',$convRules,
                                 '--from','uAlpha.TAlphaBase','--to','uBeta.TBetaThing') }
    @{ N='convert-reemit';   A=@('convert-reemit','--from-block',$convBlock,'--rules',$convRules,
                                 '--from','uAlpha.TAlphaBase','--to','uBeta.TBetaThing') }
    @{ N='convert-apply';    A=@('convert-apply','--unit',(Join-Path $srcA 'uForm.pas'),'--rules',$convRules) }
    # The three MIGRATE-ON-READ verbs (INBOX-read-verbs-migrate-the-db). Each
    # opened every --db read-write and called Migrate before reading, so a v12
    # fixture came back at the current schema. `usages` never used
    # OpenReadOnlyStore at all; `typeat` and `deps-report` open EVERY --db, so
    # stale-first is not even needed to reach their sites -- but it is kept for
    # uniformity with the rows above.
    @{ N='usages';           A=@('usages','--name','Touch') }
    @{ N='typeat';           A=@('typeat',"$($fileA):8:15") }
    @{ N='deps-report';      A=@('deps-report') }
    # uses-report is deps-report's twin (same OpenStores shape) and the INBOX
    # note missed it; --output is REQUIRED or the verb exits 2 before it opens
    # any database, which would fake a pass on this row.
    @{ N='uses-report';      A=@('uses-report','--output',(Join-Path $WorkDir 'uses.csv')) }
    # ---- the 14 read-shaped verbs audited 2026-09-16 (BACKLOG-94 row 1) ------
    # Each one opened a CALLER-SUPPLIED --db read-write and called .Migrate
    # before reading, so a v12 fixture came back silently migrated to the
    # current schema -- the same defect v1.12.0-alpha fixed for four verbs, on
    # fourteen more. run_migrate_site_guard.ps1 went `unaudited: 14` -> 0.
    #
    # EVERY ROW BELOW IS ARGUMENT-COMPLETE, and that is the whole discipline
    # here: a verb that exits 2 BEFORE it opens any database passes all four of
    # T5/T5b/T5c/T5d without testing anything. Each was run against a CURRENT
    # database first and confirmed to answer; the P5 positive control below
    # loops this same matrix and asserts exactly that, so a row that stops
    # reaching a store later turns P5 red rather than going quietly green.
    #
    # `uses-fix` appears TWICE ON PURPOSE -- with a <unit> target it is
    # DoUsesFix, with no target it is DoUsesFixSweep. One verb, two routines,
    # and the sweep form was the one that would otherwise go untested.
    # --project is REQUIRED for the targeted form (it exits 2 with a usage line
    # otherwise, which would fake a pass); the .dproj need not be buildable,
    # only present, because the store is opened before the project is used.
    @{ N='hover';            A=@('hover','--qname','uAlpha.TAlphaBase.Touch') }
    @{ N='wiring';           A=@('wiring','--qname','uAlpha.TAlphaBase') }
    @{ N='wiring --coverage';A=@('wiring','--coverage') }
    @{ N='impact';           A=@('impact','--qname','uAlpha.TAlphaBase.Touch') }
    @{ N='slice';            A=@('slice','--qname','uAlpha.TAlphaBase') }
    @{ N='bench-context';    A=@('bench-context','--n','1') }
    @{ N='generate-docs';    A=@('generate-docs','--qname','uAlpha.TAlphaBase.Touch') }
    @{ N='find-deadcode';    A=@('find-deadcode') }
    @{ N='check-unit';       A=@('check-unit',$fileA,'--resolve-uses') }
    @{ N='cycles';           A=@('cycles') }
    @{ N='uses-audit';       A=@('uses-audit',$fileA) }
    @{ N='uses-fix sweep';   A=@('uses-fix') }
    @{ N='uses-fix';         A=@('uses-fix',$fileA,'--project',$dummyDproj) }
    @{ N='generate-test';    A=@('generate-test','--qname','uAlpha.TAlphaBase.Touch') }
    @{ N='check-ast';        A=@('check-ast',$fileA) }
  )
  Check 'V the stale matrix covers all four convert-* verbs' `
        (@($staleMatrix | Where-Object { $_.N -like 'convert-*' }).Count -eq 4) `
        'a convert verb missing from this matrix stays lenient on stale, silently'
  Check 'V the stale matrix covers the four migrate-on-read verbs (usages, typeat, deps-report, uses-report)' `
        (@($staleMatrix | Where-Object { $_.N -in @('usages','typeat','deps-report','uses-report') }).Count -eq 4) `
        'a verb dropped from this matrix can go back to migrating a database it was told to read, silently'

  # The 2026-09-16 audit's own coverage check. Named individually rather than
  # counted, so a row deleted later fails with the NAME of what stopped being
  # tested instead of an off-by-one.
  $auditedRows = @('hover','wiring','wiring --coverage','impact','slice','bench-context',
                   'generate-docs','find-deadcode','check-unit','cycles','uses-audit',
                   'uses-fix sweep','uses-fix','generate-test','check-ast')
  $missingAudited = @($auditedRows | Where-Object { $_ -notin @($staleMatrix.N) })
  Check 'V the stale matrix covers all 15 rows of the 2026-09-16 read-verb audit' `
        ($missingAudited.Count -eq 0) `
        ("dropped from the matrix, so these can silently migrate a --db again: " + ($missingAudited -join ', '))

  function Run-Stale([string[]]$VerbArgs) {
    Reset-StaleDb
    $p = Start-Process -FilePath $exePath -ArgumentList $VerbArgs -NoNewWindow -PassThru `
          -RedirectStandardOutput $out -RedirectStandardError $err -WorkingDirectory 'C:\TEMP'
    if (-not $p.WaitForExit(90000)) { try { $p.Kill($true) } catch {}; return @{ Code=-1; Out=''; Err='(timed out)'; Ver='?' } }
    return @{
      Code = $p.ExitCode
      Out  = ((Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue) + '')
      Err  = ((Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue) + '')
      Ver  = (Get-StaleSchemaVersion)
    }
  }

  $t5 = @(); $t5b = @(); $t5c = @(); $t5d = @()
  foreach ($m in $staleMatrix) {
    $r = Run-Stale ($m.A + @('--db',$dbV12,'--db',$dbA,'--db',$dbB))
    if ($r.Code -ne 2) { $t5 += ("{0}=exit{1}" -f $m.N, $r.Code) }
    if ($r.Out -match 'index schema v') { $t5b += $m.N }
    if (-not (StdoutIsSilent $r.Out))   { $t5c += $m.N }
    if ($r.Ver -ne '12')                { $t5d += ("{0}->v{1}" -f $m.N, $r.Ver) }
  }

  Check 'T5 a stale-schema explicit --db exits 2 on every verb' ($t5.Count -eq 0) `
        ("still answered from the remaining stores: " + ($t5 -join ', '))
  Check 'T5b the schema line is on STDERR, never stdout' ($t5b.Count -eq 0) `
        ("printed the schema line to stdout, which corrupts --format json|sarif: " + ($t5b -join ', '))
  Check 'T5c stdout carries NO partial answer when a --db is stale' ($t5c.Count -eq 0) `
        ("answered anyway on stdout: " + ($t5c -join ', '))
  Check 'T5d a refused run does NOT migrate the stale database' ($t5d.Count -eq 0) `
        ("migrated a database it was told to read, as a side effect of a query: " + ($t5d -join ', '))

  # ---- P5 POSITIVE CONTROL: the stale matrix's verbs WORK on current DBs ------
  # Without this, T5/T5b/T5c pass against a build that exits 2 for these verbs
  # unconditionally -- which is exactly the failure T5 is meant to forbid.
  $p5 = @()
  foreach ($m in $staleMatrix) {
    $r = Run-Verb ($m.A + @('--db',$dbA,'--db',$dbB))
    if ($r.Code -ge 2) { $p5 += ("{0}=exit{1}" -f $m.N, $r.Code) }
    if ($r.Out -match 'index schema v') { $p5 += ("{0}=spurious-schema-line" -f $m.N) }
  }
  Check 'P5 POSITIVE CONTROL the stale matrix verbs still answer on CURRENT --db' ($p5.Count -eq 0) `
        ("these broke on good databases, so their T5 rows prove nothing: " + ($p5 -join ', '))
}

Write-Host ''
if ($ListRedOnly) { Write-Host 'evidence run -- exit 0 regardless' -ForegroundColor DarkGray; exit 0 }
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
