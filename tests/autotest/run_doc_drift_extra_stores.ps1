<#
  run_doc_drift_extra_stores.ps1 -- `document` and `lint-all` must agree on
  WHICH of several --db is the PRIMARY store, so a managed facts block written
  by one verb is accepted by the other.

  THE CONVENTION (owner ruling, 2026-08-25): THE FIRST --db IS THE PRIMARY.
  Every later --db is an extra store. This is the rule `lint-all`, `find-unit`,
  `resolve-uses`, `typeat` and `convert-apply` already followed, and the one
  docs\AI-USAGE.md already stated ("Repeat --db to search multiple indexes
  (first one wins)"). `document` was the outlier -- it read AArgs.DbPath, which
  ParseArgs left holding the LAST --db because every flag overwrote it.

  THE DEFECT THIS CLOSES, as reproduced 2026-08-24:
  `document --qname X --db A --db B --apply` wrote a block naming a caller, and
  `lint-all --db A --db B` -- the SAME two --db, same order -- then reported

      doc-drift: managed facts block is out of date

  against the block `document` had just written. A permanent false finding: the
  block could never be made clean, and re-running `document` did not silence it.
  The cause was the primary disagreement, not the extra stores:

      document  primary = AArgs.DbPath          = the LAST  --db  (B)
      lint-all  primary = ResolveConsumerDbs[0] = the FIRST --db  (A)

  and the fact at issue -- a RESOLVED call edge, which lives only in B -- is
  contributed ONLY by the primary store. Extra stores are searched for NAME-based
  callers and used-in units, not resolved edges, so handing the checker B as an
  extra does not reproduce what the documenter rendered with B as primary.

  THE FIXTURE:

    shared\thing.pas   TThing.DoIt          -- indexed by BOTH sections
    bside\user.pas     calls TThing.DoIt    -- indexed by section B ONLY

    section A -> dbA : ["shared"]            so dbA has NO caller for DoIt
    section B -> dbB : ["shared", "bside"]   so dbB RESOLVES user.Go -> DoIt

  The call is a RESOLVED edge in B, not a name match. That is deliberate and it
  is what makes the fixture discriminating: a resolved edge is contributed ONLY
  by the primary store, so the block can be reproduced only by the verb that
  opened B as primary.

  WHAT IS ASSERTED:

    2  document --db B --db A --apply    writes a block naming B's caller
    3  lint-all --db A           REPORTS drift   <- POSITIVE CONTROL
    4  lint-all --db B --db A    REPORTS NOTHING <- the agreement under test
    5  document --db A --apply   removes the block entirely (the churn, recorded)

  NOTE THE ORDER IN 2 AND 4: B FIRST. B is the store that owns the fact, so
  under the first-wins convention it is the one to pass first, and BOTH verbs
  then open it as primary. Passing `--db A --db B` (the old convention's order)
  makes both verbs agree on A instead -- also self-consistent, and it renders no
  caller at all; the contradiction is gone either way, which is the point.

  RED AGAINST THE UNFIXED BUILD: with the old last-wins rule, `--db B --db A`
  gave `document` primary A (no caller written) while `lint-all` used primary B
  (renders the caller), so steps 2 AND 4 both fail. Verified 2026-08-25 before
  the ParseArgs change landed.

  STEP 3 IS LOAD-BEARING. With one store the entry genuinely is unaccountable,
  so drift SHOULD be reported. Without that assertion, a "fix" that simply
  stopped reporting doc-drift at all would satisfy step 4 and destroy the
  signal -- and two earlier versions of this file both failed in exactly that
  direction.

  THREE THINGS THIS FIXTURE GOT WRONG BEFORE, all of which read as "the engine
  is fine" -- kept so the next version does not repeat them:

  1. NO REINDEX AFTER --apply. doc-drift's population comes from
     ListDocumentedSymbols, i.e. from the INDEX. `document --apply` writes the
     source; until the index is refreshed the checker examines nothing and
     reports nothing, which reads exactly like "no drift".
  2. ASSERTING ONLY THE ABSENCE of a finding, with no positive control -- step 3
     exists for that reason.
  3. REUSING LEFTOVER SCRATCH STATE from a previous run instead of recreating
     the fixture.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_dborder_extrastores'
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
  $d2 = (& $exePath document --qname $QNAME --db $dbB --db $dbA --apply 2>&1 | Out-String)
  Check '2. document --db B --db A wrote a managed block naming B''s caller' `
        (BlockHasCaller) `
        $(($d2 -split "`n" | Where-Object { $_ -match '(?i)doc:' } | Select-Object -First 1))
  Reindex

  # --- 3. one store -> the entry is PRESERVED, not called stale -------------
  # INVERTED 2026-09-02. This used to assert that dbA alone REPORTS drift, on
  # the reasoning that the caller entry "genuinely is unaccountable" there.
  # That reasoning is what DataCopy's report overturned: dbA cannot see
  # bside's user.pas at all, so its silence is a blind spot, not a fact, and
  # reporting on it led straight to a repair that DELETED a true caller. Fact
  # reconciliation now applies to any block carrying entries this index cannot
  # vouch for, marked or not -- so the entry is forgiven and no drift is
  # reported. That is the fix, asserted here rather than left implicit.
  $l3 = (& $exePath lint-all --db $dbA --quiet 2>&1 | Out-String)
  Check '3. lint-all --db A alone does NOT report drift on an unvouchable entry' `
        (-not (DriftReported $l3)) `
        'dbA cannot see the bside caller, so its absence is a blind spot, not evidence'

  # --- ON THE LIVENESS CONTROL STEP 3 USED TO PROVIDE ----------------------
  # Step 3 also proved doc-drift CAN report on this file, which steps 4 and 5
  # need because both assert an ABSENCE. That role cannot be filled here any
  # more, and the reason is a property of the fixture, not an oversight:
  #
  #   dbA renders NO managed block for DoIt at all (it compiles thing.pas but
  #   calls nothing in it). Once the stored block holds entries only another
  #   project could have written, the empty-render rule in
  #   TSharedFacts.BlockDrifted exits BEFORE any comparison -- including the
  #   intrinsic byte compare. So NO drift of any kind is reportable on this
  #   symbol with dbA. That rule predates this change and is deliberate: a
  #   project that renders nothing has nothing to say about the block.
  #
  # Two candidate controls were written and both failed against a CORRECT
  # engine before this was understood -- an in-scope ghost entry, and a planted
  # intrinsic 'Complexity:' line. Neither is reportable here, for that reason.
  #
  # The liveness control for the facts checker therefore lives where the fresh
  # render is non-empty: CONTROL-1 in run_doc_drift_unseen_units.ps1, which
  # asserts an in-scope ghost IS still reported and still fixable. Step 5 below
  # is also a POSITIVE assertion now (the block must still name the caller),
  # which is what keeps this suite from passing on absences alone.

  # --- 4. THE BUG: the same two stores that wrote it must accept it ---------
  $l4 = (& $exePath lint-all --db $dbB --db $dbA --quiet 2>&1 | Out-String)
  $drift4 = DriftReported $l4
  Check '4. lint-all --db B --db A reports NO doc-drift on the block it just wrote' `
        (-not $drift4) `
        ('still reported: ' + (($l4 -split "`r?`n" | Where-Object { $_ -match 'doc-drift|doc-opts' }) -join ' // '))
  if ($drift4) {
    # WHAT DIVERGED. The checker rebuilds the block and byte-compares, so the
    # only useful evidence is the two texts side by side: what is ON DISK, and
    # what the documenter would write right now under the same two stores.
    Write-Host '      --- block ON DISK ---' -ForegroundColor DarkGray
    (Get-Content $thing) | Where-Object { $_ -match '///' } | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
    Write-Host '      --- what document --db B --db A would write now ---' -ForegroundColor DarkGray
    (& $exePath document --qname $QNAME --db $dbB --db $dbA 2>&1) |
      ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
  }

  # --- 5. the churn this suite RECORDED is now CURED ------------------------
  # This step used to assert the defect: `document` with a NARROWER store set
  # stripped the whole managed block, so two legitimate invocations gave
  # opposite results on one file -- and the IDE passes the project DB alone, so
  # the destructive one is the common case. It was recorded rather than
  # asserted as desirable, with no owner for the fix.
  #
  # DataCopy hit the same mechanism through the one-DB-per-project layout, where
  # it is not a two-store edge case but the DEFAULT: a production closure can
  # never hold a test caller. The writer now preserves entries whose unit the
  # primary store cannot vouch for, so the narrow invocation is non-destructive
  # and the two agree. The assertion is inverted to pin the cure.
  & $exePath document --qname $QNAME --db $dbA --apply 2>&1 | Out-Null
  Check '5. CURED: document --db A alone PRESERVES the block written by A+B' `
        (BlockHasCaller) `
        'the narrow invocation is no longer destructive -- was RECORDED as a defect until 2026-09-02'
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
