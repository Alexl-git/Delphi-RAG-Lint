<#
  PENDING -- deliberately named `pending_*` so the battery's `run_*.ps1`
  discovery does NOT pick it up. It is the fixture for work that is not
  implemented (INBOX-buildfor-defaulted-args, the AExtraStores residue), and a
  test for an unbuilt feature belongs outside the battery, not inside it as a
  standing red.

  THE DEFECT, as finally reproduced 2026-08-24 -- and it is NOT AExtraStores
  ---------------------------------------------------------------------------
  `document --qname X --db A --db B --apply` writes a block naming a caller.
  `lint-all --db A --db B` -- the SAME two --db, same order -- then reports

      doc-drift: managed facts block is out of date

  against the block document just wrote. A permanent false finding: the block
  can never be made clean, and re-running `document` does not silence it.

  THE CAUSE IS WHICH STORE IS *PRIMARY*, not which are extra. The two verbs
  disagree about that, from an identical command line:

      document  primary = AArgs.DbPath          = the LAST  --db  (B)
      lint-all  primary = ResolveConsumerDbs[0] = the FIRST --db  (A)

  and the fact at issue -- a RESOLVED call edge, which lives only in B -- is
  contributed ONLY by the primary store. AExtraStores is searched for NAME-based
  callers and used-in units, not resolved edges, so handing the checker B as an
  extra does not reproduce what document rendered with B as primary. Measured
  directly: with primary=A and extra=B, `document` proposes to DELETE the block
  (renders no facts at all); with primary=B it renders the caller.

  The AExtraStores threading that landed alongside this fixture is still a real
  fix -- lint-all was excluding the WRONG store from its extras (it dropped B,
  the one it had not opened, and handed back A, the one already primary) -- but
  it does not close THIS gap, and step 4 stays red until the two verbs agree on
  a primary. That is a behaviour change with real blast radius (it decides which
  index answers every query for one of the verbs) and is an owner call.

  2026-08-25 CORRECTION: `document`'s last-`--db` rule is DELIBERATE, and the
  two verbs' conventions are OPPOSITE. Do not "align" one to the other.

  Changing `document` to open the FIRST `--db` (to match `lint-all`) was tried
  and REVERTED the same day. It broke `tests\autotest\run_doc_multidb.ps1` and
  `run_doc_multidb_overload_tag.ps1`, whose headers document the rule as a
  convention and depend on it:

      "document --unit opens its PRIMARY store from the LAST --db flag ... So the
       target unit's own db must be passed LAST; any earlier --db is an extra
       store searched (name-only) for callers/used-in."

  So the two verbs document OPPOSITE orderings for the same flags:

      document   the target's own DB goes LAST
      lint-all   the project DB goes FIRST  (`--db <proj> --db <lib>`)

  A user passing one `--db` list to both cannot satisfy both. THAT is the defect
  -- a UX/contract contradiction, not a wrong line of code -- and it cannot be
  fixed by silently flipping either side.

  ALSO CORRECTED: extras are NOT useless for callers. run_doc_multidb's scenario
  B surfaces `Called from: uApp.Run` from an extra store by NAME. What the extras
  path does not surface is this fixture's shape -- `T.DoIt`, a member access on a
  typed receiver, which the CalledFrom bucket ambiguity-gates. A plain call by
  name (`Compute(21)`) comes through fine. The earlier claim here that extras
  contribute nothing was drawn from this one fixture and was too broad.

  THREE THINGS THIS FIXTURE GOT WRONG BEFORE, all of which read as "the engine
  is fine" -- recorded so the fourth version does not repeat them:

  1. NO REINDEX AFTER --apply (2026-08-17). doc-drift's population comes from
     ListDocumentedSymbols, i.e. from the INDEX. `document --apply` writes the
     SOURCE only, so until the file is re-indexed the declaration is not
     "documented" as far as the checker is concerned and is never examined.
     Reindex after EVERY step that rewrites the source.

  2. `--fix` WITHOUT `--apply` IS A DRY RUN (2026-08-24). It reports what it
     would change and writes nothing ("DRY RUN WITHOUT --apply", drag-lint
     --help). The previous version drove the whole suite through `lint-all
     --fix --quiet`, so the file was never touched: steps 2 and 3 passed
     because nothing happened, and the positive control failed for the same
     reason.

  3. doc-drift IS NOT ACTUALLY AUTOFIXED (2026-08-24, and this is a separate
     defect). `rules --json` advertises "fixable": true, but BOTH autofix
     routes refuse it:

         lint-all --db A --fix --apply   ->  autofix: no fixable findings (of 2 finding(s))
         lint     --file t.pas --fix     ->  autofix: no fixable findings (of 1 finding(s))

     So the note's "--fix deletes it" mechanism does not exist on this build.
     What actually deletes the block is `document` run with a NARROWER store
     set -- `document --db A --apply` prints `doc: removed` and takes the whole
     managed block out. That is the churn: two legitimate invocations produce
     opposite results on one source file, and the IDE passes the project DB
     alone.

  THE FIXTURE:

    shared\thing.pas   TThing.DoIt          -- indexed by BOTH sections
    bside\user.pas     calls TThing.DoIt    -- indexed by section B ONLY

    section A -> dbA : ["shared"]            so dbA has NO caller for DoIt
    section B -> dbB : ["shared", "bside"]   so dbB RESOLVES user.Go -> DoIt

  The call is a RESOLVED edge in B, not a name match. That is deliberate and it
  is what makes the fixture discriminating: a resolved edge is contributed ONLY
  by the primary store, so the block can be reproduced only by the verb that
  opened B as primary -- which is exactly the asymmetry under test.

  WHAT IS ASSERTED, and which one is red today:

    2  document --db A --db B --apply     writes a block naming B's caller
    3  lint-all --db A            REPORTS drift   <- POSITIVE CONTROL
    4  lint-all --db A --db B     REPORTS NOTHING <- THE BUG (red today)
    5  document --db A --apply    removes the block entirely (the churn, recorded)

  STEP 3 IS LOAD-BEARING. With one store the entry genuinely is unaccountable,
  so drift SHOULD be reported. Without that assertion, a "fix" that simply
  stopped reporting doc-drift at all would satisfy step 4 and destroy the
  signal -- and the two earlier versions of this file both failed in exactly
  that direction.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_c1_extrastores'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $scratch 'shared') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $scratch 'bside')  | Out-Null

function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}

WriteAscii (Join-Path $scratch 'shared\thing.pas') @'
unit thing;

interface

type
  TThing = class
  public
    procedure DoIt;
  end;

implementation

procedure TThing.DoIt;
begin
end;

end.
'@

WriteAscii (Join-Path $scratch 'bside\user.pas') @'
unit user;

interface

procedure Go;

implementation

uses
  thing;

procedure Go;
var
  T: TThing;
begin
  T := TThing.Create;
  T.DoIt;
  T.Free;
end;

end.
'@

$cfg = Join-Path $scratch 'manifest.drag-lint.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "SecA", "db": "a.sqlite", "include": ["shared"] },
      { "name": "SecB", "db": "b.sqlite", "include": ["shared", "bside"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii

$dbA    = Join-Path $scratch 'out\a.sqlite'
$dbB    = Join-Path $scratch 'out\b.sqlite'
$thing  = Join-Path $scratch 'shared\thing.pas'
$QNAME  = 'thing.TThing.DoIt'

function BlockHasCaller { (Get-Content $thing -Raw) -match '(?i)(Called from|Used by)[^\r\n]*Go' }
function DriftReported([string]$Out) { $Out -match '(?m)^\s*\S+thing\.pas:\d+:\d+\s+\[\w+\]\s+doc-drift\b' }

# REINDEX BOTH SECTIONS. Load-bearing after EVERY step that rewrites the source:
# doc-drift's population is ListDocumentedSymbols, i.e. the INDEX, so a run
# against a stale index examines nothing and reports nothing -- which reads
# exactly like "no drift" and is failure mode 1 above.
function Reindex {
  & $exePath index --all --config $cfg --only SecA --jobs 1 2>&1 | Out-Null
  & $exePath index --all --config $cfg --only SecB --jobs 1 2>&1 | Out-Null
}

Push-Location C:\TEMP
try {
  Reindex
  Check '1. SANITY: both section DBs exist' ((Test-Path $dbA) -and (Test-Path $dbB))

  # --- 2. document with BOTH stores -----------------------------------------
  $d2 = (& $exePath document --qname $QNAME --db $dbA --db $dbB --apply 2>&1 | Out-String)
  Check '2. document --db A --db B wrote a managed block naming B''s caller' `
        (BlockHasCaller) `
        $(($d2 -split "`n" | Where-Object { $_ -match '(?i)doc:' } | Select-Object -First 1))
  Reindex

  # --- 3. POSITIVE CONTROL: one store -> the entry IS unaccountable ---------
  # Must stay green. If this ever goes red, the checker has stopped reporting
  # drift at all and step 4 below is worthless.
  $l3 = (& $exePath lint-all --db $dbA --quiet 2>&1 | Out-String)
  Check '3. POSITIVE CONTROL: lint-all --db A alone REPORTS drift' `
        (DriftReported $l3) `
        'with only dbA open the caller entry genuinely is unaccountable'

  # --- 4. THE BUG: the same two stores that wrote it must accept it ---------
  $l4 = (& $exePath lint-all --db $dbA --db $dbB --quiet 2>&1 | Out-String)
  $drift4 = DriftReported $l4
  Check '4. lint-all --db A --db B reports NO doc-drift on the block it just wrote' `
        (-not $drift4) `
        ('still reported: ' + (($l4 -split "`r?`n" | Where-Object { $_ -match 'doc-drift|doc-opts' }) -join ' // '))
  if ($drift4) {
    # WHAT DIVERGED. The checker rebuilds the block and byte-compares, so the
    # only useful evidence is the two texts side by side: what is ON DISK, and
    # what the documenter would write right now under the same two stores.
    Write-Host '      --- block ON DISK ---' -ForegroundColor DarkGray
    (Get-Content $thing) | Where-Object { $_ -match '///' } | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
    Write-Host '      --- what document --db A --db B would write now ---' -ForegroundColor DarkGray
    (& $exePath document --qname $QNAME --db $dbA --db $dbB 2>&1) |
      ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
  }

  # --- 5. the churn, recorded rather than asserted as desirable -------------
  # document with a NARROWER store set removes the whole managed block. This is
  # what actually alternates the file, not `lint-all --fix` (which refuses
  # doc-drift outright -- see failure mode 3 in the header).
  & $exePath document --qname $QNAME --db $dbA --apply 2>&1 | Out-Null
  Check '5. RECORDED: document --db A alone strips the block written by A+B' `
        (-not (BlockHasCaller)) `
        'two legitimate invocations, opposite results on one file -- the IDE passes the project DB alone'
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
