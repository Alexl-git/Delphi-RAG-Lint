# MEASURED: interprocedural purity v2 -- corpus re-resolve, 2026-09-22

Task 8 of `docs\superpowers\plans\2026-09-21-interprocedural-purity-v2.md`.
This is the record the owner reads. Nearly every number below was produced by a
command that is quoted beside it; the two exceptions are assertion 24's table and
the witness-class split, whose per-row SQL is not individually reprinted (the
witness-class split does name the `CASE` expression it used). Nothing is
extrapolated, and nothing that was not run is reported as a result -- both tables'
figures were independently re-verified correct, they are simply not each beside
their own quoted command.

## Engines and tree

| | |
|---|---|
| Branch | `feat/purity-v2`, worktree `C:\Projects\Delphi-RAG-lint-wt\purity-v2` |
| Baseline commit (first engine that writes the three columns) | `6cd676a3` (Task 3; stage landed in `65d0206f`) |
| Measured commit | `69274948` (Task 7 + its fix round) |
| Engine binary | `third_party\dll-win64\drag-lint.exe`, product **1.16.0-alpha**, extractor **1.17.0-alpha**, resolver **1.5.1-alpha**, built 2026-09-22 14:22:50 |

### The engine had to be rebuilt before anything could be measured

The binary deployed in the worktree when this task started was built at
**13:40:44** and reported resolver **1.5.0-alpha**. HEAD (`69274948`, committed
14:10:27) bumps `DRAGLINT_RESOLVER_VERSION` to **1.5.1-alpha** and changes two
things that this record depends on:

* `DRagLint.Analysis.PurityStage.pas` -- the **stored effect witness**. Before the
  fix, `symbol_facts.touches` was printed raw, so witnesses read
  `touches file system|` and `|starts, commits, rolls back`.
* `DRagLint.Lint.ProjectRules.pas` -- rule 14.1 no longer fires on a result used
  across a line wrap.

Measuring with the 13:40 binary would have written dirty witnesses into every
corpus DB and reported inflated 14.1 counts. The engine was therefore rebuilt
from HEAD (`build\build_draglint_win64.bat`, clean, no `[dcc] Error`) and the
whole resolve pass was re-run on it. **Both facts below are post-rebuild
verification, not assumption:**

```
sql --query "SELECT sum(effect_witness LIKE '%|%') ... FROM symbol_facts WHERE effect_free=0"
  CLIENT        -> 0 witnesses containing '|'   (38 'touches...' witnesses, all clean)
  DragLint-Cli  -> 0 witnesses containing '|'   (172 'touches...' witnesses, all clean)
```

## THE CAVEAT that applies to every corpus number below

**`e71abafb` (2026-09-21 22:36:52) changed what the SymbolFacts extractor emits
without bumping `DRAGLINT_EXTRACTOR_VERSION`.** It taught `WalkFieldRW` to record
an indexed-then-dotted field write (`FRows[i].Skipped := X`). `symbol_facts` rows
are re-emitted only when a file is RE-PARSED, and this task re-RESOLVED the
corpus without re-parsing it.

**Direction of the error: OPTIMISTIC.** A missing field write is a missing
effect, so a stale DB *over*-counts `proven` and *under*-counts `not_proven`. It
cannot err the other way. Every `proven` figure below is an UPPER BOUND.

How stale, measured (`sql --query "SELECT count(*), sum(parsed_at < 1790048212) FROM files"`,
where 1790048212 is `e71abafb`'s commit time):

| DB | files | parsed BEFORE `e71abafb` | oldest parse | newest parse |
|---|---:|---:|---|---|
| ORM3 CLIENT | 625 | **625 (100%)** | 2026-09-17 18:48 | 2026-09-20 17:31 |
| DataCopy | 39 | **39 (100%)** | 2026-09-17 18:47 | 2026-09-20 10:04 |
| YADF | 9 | **9 (100%)** | 2026-09-17 18:47 | 2026-09-17 18:47 |
| DragLint-Cli (main tree) | 128 | **125 (98%)** | 2026-09-17 18:47 | 2026-09-22 06:31 |
| library-Win64 | 7,001 | **7,001 (100%)** | 2026-09-17 19:06 | 2026-09-17 21:00 |
| library-Win32 | 7,139 | **7,139 (100%)** | 2026-09-17 19:10 | 2026-09-17 21:03 |
| DragLint-Cli (worktree) | 130 | **0 (0%)** | 2026-09-22 19:44 | 2026-09-22 19:47 |

Full write-up, repro and remedy cost: `docs\INBOX-symbolfacts-stale-since-e71abafb.md`
(gitignored, local-only -- not in the commit, so a reader without this working tree
does not have this file).

## Commands actually run

| What | Command | Log |
|---|---|---|
| Resolve pass, 33 PROJECT sections (engine 1.5.0, superseded) | `drag-lint index --all --resolve-only --only <33 names> --jobs 2` | `C:\TEMP\claude\C--Projects-Delphi-RAG-lint-wt-purity-v2\purity-resolve-only-projects.log` -- `33/33 sections OK`, exit 0, 311.6s |
| Engine rebuild to HEAD | `build\build_draglint_win64.bat` | `...\build-engine-head.log` -- exit 0 |
| **Resolve pass, 33 PROJECT sections (engine 1.5.1 -- the measured run)** | `drag-lint index --all --resolve-only --only <33 names> --jobs 2` | `...\purity-resolve-only-projects-HEAD.log` -- `33/33 sections OK`, exit 0, 303.8s |
| Self-DB BEFORE | `drag-lint index --project <wt>\src\cli\drag-lint.dproj --db <wt>\src\cli\_D-RAG\drag-lint.sqlite --resolve-only` | `...\selfdb-before-resolve.log` |
| Self-DB AFTER | `... --rebuild` | `...\selfdb-rebuild.log` |
| Rule counts | `drag-lint lint-all --db <db> --enable discarded-effect-free-result,query-name-with-effect --json` | `...\lint-<DB>.json` |
| Battery | `pwsh -File tests\run_battery.ps1 -LogDir C:\TEMP\battery-purity` | `...\battery.log` |
| **library-Win32** | `drag-lint index --all --resolve-only --only Library --platform win32 --jobs 1` | `...\library-Win32-resolve.log` -- exit 0, **4,459.3s (74.3 min)**, ran 15:31:48 - 16:46:07 [^win32-started] |
| **library-Win64** | `drag-lint index --all --resolve-only --only Library --platform win64 --jobs 1` | `...\library-Win64-resolve.log` -- exit 0, **4,276.4s (71.3 min)**, ran 16:46:30 - 17:57:44 |

The 33 sections are every non-`Library` section of
`third_party\dll-win64\drag-lint.json`.

[^win32-started]: `library-Win32-resolve.log`'s own wrapper line labels its FINISH
timestamp as `STARTED=16:46:07` (a mislabel in the log, not in this record). The
`ran 15:31:48 - 16:46:07` figure above is correct and matches the process's actual
start/end; a reader cross-checking the raw log against this table should expect
that label to say something it did not measure.

**The two library passes were owner-gated; the gate was released at 14:19 local
and they were run under the stated conditions**: after the project sections,
their measurements and the full battery had all finished; one at a time, never
concurrently with each other or with anything else; `--resolve-only` only (no
`--rebuild`, no folder target) against the owner's real DBs; worktree engine; no
build while a pass ran; quiet box confirmed before each.

**Section-name discrepancy, recorded because it would silently select nothing.**
The brief and the gate both name the sections `library-Win32` / `library-Win64`.
The manifest has ONE section named `Library` carrying
`platforms: ["Win32","Win64"]`. Targeting was confirmed with a dry run before
either pass:

```
index --all --only Library --platform win32 --dry-run
  [Library[Win32]] mode=library db=C:\Projects\.drag-lint\library-Win32.sqlite
index --all --only Library --platform win64 --dry-run
  [Library[Win64]] mode=library db=C:\Projects\.drag-lint\library-Win64.sqlite
```

`--only library-Win32` matches no section.

Banner seen on every section of the measured run:
`Resolver changed since this DB was resolved (r=1.5.0-alpha;schema=23 -> r=1.5.1-alpha;schema=23): re-deriving every edge.`

## Headline counts

`sql --query "SELECT count(*) AS routines, sum(effect_free=1) AS proven, sum(effect_free=0) AS not_proven, sum(effect_free IS NULL) AS not_computed FROM symbol_facts WHERE ifnull(body_loc,0) > 0"`

| DB | routines | proven | not proven | not computed |
|---|---:|---:|---:|---:|
| ORM3 CLIENT | 10,150 | **2,896** | 7,254 | 0 |
| DataCopy | 572 | 62 | 510 | 0 |
| YADF | 243 | 33 | 210 | 0 |
| DragLint-Cli (main tree) | 2,846 | 170 | 2,676 | 0 |
| DragLint-Cli (worktree, fresh parses) | 2,934 | 194 | 2,740 | 0 |
| **library-Win64** | 420,234 | **132,569** | 287,665 | 0 |
| **library-Win32** | 415,182 | **131,768** | 283,414 | 0 |

The library-Win64 figures reproduce Task 3's scratch-copy measurement exactly
(420,234 routines / 132,569 effect-free), which is an independent corroboration
of both runs rather than a coincidence worth passing over.

**Before this task, the four corpus DBs had no `effect_free` column at all** --
the same query answered `ERROR: no such column: effect_free`. The columns were
added by the migration this pass performed. So the "before" is not a smaller
number; it is the absence of the fact.

## `resolve: purity` lines, verbatim

Attribution note: the pass ran `--jobs 2`, so two sections interleave on one
stdout. Each line below was attributed by matching its routine count against the
DB's own `SELECT count(*) ... FROM symbol_facts WHERE body_loc > 0` -- every count
matched exactly one DB -- and the CLIENT timings were cross-checked against its
`BEGIN 14:23:14` / `158.9s` total. Adjacency alone was NOT trusted; it is wrong
for CLIENT.

**ORM3 CLIENT**
```
resolve: purity -- 10150 routine(s), 2896 effect-free (29%), 13843 unbound call ref(s) [top: format (2029), tcommandid (1045), fieldbyname (995), free (794), syserrormessage (517), create (470), getbytes (467), add (352), disablecontrols (238), enablecontrols (238)], 0 unlexable call(s), 0 stale file(s), 4 gated (local table incomplete), 2 pass(es)
```

**DataCopy**
```
resolve: purity -- 572 routine(s), 62 effect-free (11%), 1682 unbound call ref(s) [top: format (358), combine (73), syserrormessage (67), free (63), trim (56), create (43), append (38), exists (34), logerror (34), sametext (29)], 0 unlexable call(s), 0 stale file(s), 0 gated (local table incomplete), 2 pass(es)
```

**YADF**
```
resolve: purity -- 243 routine(s), 33 effect-free (14%), 815 unbound call ref(s) [top: append (152), free (113), add (94), trim (63), format (46), charinset (29), sametext (29), trimleft (25), trimright (24), create (22)], 0 unlexable call(s), 0 stale file(s), 1 gated (local table incomplete), 2 pass(es)
```

**DragLint-Cli (main tree)**
```
resolve: purity -- 2846 routine(s), 170 effect-free (6%), 10539 unbound call ref(s) [top: free (1067), add (727), trim (701), sametext (663), lowercase (483), parambyname (463), format (422), fieldbyname (396), addpair (382), create (361)], 0 unlexable call(s), 3 stale file(s), 0 gated (local table incomplete), 2 pass(es)
```

**library-Win64** (ran 16:46:30 - 17:57:44)
```
resolve: purity -- 420234 routine(s), 132569 effect-free (32%), 343400 unbound call ref(s) [top: add (31202), free (16281), create (11444), assert (4394), clear (3915), assign (3586), cos (3155), pbyte (2571), indexof (2376), apply (2152)], 154 unlexable call(s), 0 stale file(s), 2212 gated (local table incomplete), 2 pass(es)
```

**library-Win32** (ran 15:31:48 - 16:46:07)
```
resolve: purity -- 415182 routine(s), 131768 effect-free (32%), 332028 unbound call ref(s) [top: add (30790), free (15863), create (11288), assert (4394), clear (3751), assign (3456), cos (3156), pbyte (2522), indexof (2318), apply (2147)], 162 unlexable call(s), 0 stale file(s), 2213 gated (local table incomplete), 2 pass(es)
```

The libraries are the only DBs with a non-zero `unlexable call` count (154 and
162) and a large `gated` count (2,212 and 2,213). Both are reported here rather
than folded away: they are the routines the model declined to decide, not
routines it proved anything about.

## Witness-class split

Using the protocol's `CASE` expression, on `effect_free = 0`:

| class | CLIENT | DataCopy | YADF | DragLint-Cli |
|---|---:|---:|---:|---:|
| write | 3,773 | 135 | 29 | 328 |
| other | 1,341 | 199 | 42 | 776 |
| unbound member | 1,159 | 94 | 85 | 499 |
| unbound call | 638 | 74 | 53 | 572 |
| inherited | 184 | 8 | 1 | 20 |
| with | 159 | 0 | 0 | 2 |
| stale file | 0 | 0 | 0 | 479 |

Libraries (same classifier):

| class | library-Win64 | library-Win32 |
|---|---:|---:|
| other | 166,404 | 165,189 |
| write | 71,298 | 70,105 |
| unbound call | 41,679 | 40,269 |
| with | 6,953 | 6,531 |
| inherited | 1,331 | 1,320 |
| unbound member | 0 | 0 |
| stale file | 0 | 0 |

**The protocol's classifier under-counts `unbound call`, and that is a defect in
the protocol, not in the data.** Its pattern is `'calls % (unbound)%'`, but the
engine emits three other real shapes that fall into `other`. Top of CLIENT's
`other` bucket, measured:

```
calls LogMessage (virtual/interface dispatch)   140
calls GetID (virtual/interface dispatch)        137
calls WriteB (unbound callee inside)            133
calls read (unbound callee inside)              125
calls Log (unbound callee inside)                64
touches file system                              37
calls FieldByName (unbound; receiver Dat...)     30
```

So `other` is overwhelmingly more unbound/virtual-dispatch calls, plus the
`touches` facts. Read the CLIENT split as roughly *4,000 real writes* against
*~3,100 binding gaps*, not as 1,341 mysteries.

`DragLint-Cli`'s 479 `stale file` rows are a property of the MAIN TREE DB, whose
source moved on after it was indexed; the pass reported
`3 file(s) WITHHELD -- their source no longer matches the index`.

## Assertion 24 -- the four CLIENT anchors

All four read `effect_free = 0`, each with an exact witness. **PASS.**

| symbol | effect_free | witness |
|---|:-:|---|
| `BASICSF.AssignRecord` | 0 | `accesses Destination.FieldCount (unbound member)` |
| `BASICSF.CopyRecords` | 0 | `accesses Destination.FieldCount (unbound member)` |
| `uINSPRSLT.TmcINSPRSLT.AssignTo` | 0 | `with statement` |
| `uPLANLIST.Register` | 0 | `calls RegisterComponents (unbound)` |

## Assertion 25 (before-binding half) -- `System.SysUtils.Trim`: PASS

Measured on library-Win64 after its 16:46-17:57 resolve pass:

| symbol | effect_free | witness |
|---|:-:|---|
| `System.SysUtils.Trim` | **0** | `calls SubString (unbound; receiver S)` |

The assertion required `0` with a witness containing `SubString` and `unbound`.
Both strings are present. The AFTER half (what this becomes once `SubString`
binds) belongs to Phase 4 and is not claimed here.

Before the gate was released this line read "owner-gated, not yet measured", and
the claim was backed by a read-only probe rather than left as an assumption:
`sql --db library-Win64.sqlite ... WHERE qualified_name='System.SysUtils.Trim'`
returned `ERROR: no such column: f.effect_free`, i.e. the purity migration had
genuinely never run on that DB.

## Section 17 falsifier -- purity seconds < calls seconds

The `calls` stage genuinely EXECUTED on every DB below (`starting WHOLE-DB pass`,
because the resolver fingerprint changed 1.5.0 -> 1.5.1). No number here comes
from a skipped stage.

| DB | calls | purity | ratio | falsifier |
|---|---:|---:|---:|---|
| ORM3 CLIENT | 146.1s | 10.4s | 14.0x | **holds** |
| DataCopy | 12.8s | 0.7s | 18.3x | **holds** |
| YADF | 7.5s | 0.3s | 25.0x | **holds** |
| DragLint-Cli (main) | 81.4s | 3.6s | 22.6x | **holds** |
| DragLint-Cli (worktree) | 112.5s | 4.6s | 24.5x | **holds** |
| **library-Win32** | **3,641.4s** | **726.8s** | **5.0x** | **holds** |
| **library-Win64** | **3,500.6s** | **635.3s** | **5.5x** | **holds** |

The library `calls` stage EXECUTED on both passes (`Resolver changed ...
re-deriving every edge`, 1.4.0-alpha -> 1.5.1-alpha, then a WHOLE-DB pass over
7,139 and 7,001 files). Neither number comes from a skipped stage, so T8-R1's
"not evaluable" wording is not needed anywhere in this table.

Today's library-Win64 numbers are close to, but not the same as, Task 3's
scratch-copy measurement (`calls 3368.1s vs purity 600.5s`, 5.6x). That earlier
figure is cited as attributed prior evidence and is NOT substituted for today's:
the live run printed 3,500.6s and 635.3s, and those are what is recorded.

**Caveat on the library-Win64 timing specifically.** The box was verified quiet
before the pass started (16:46), but at ~16:55 three engines that I did not
start appeared -- two running the MAIN tree's
`C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` (pids 17356,
50000) and one VS Code `globalStorage` engine. Per the gate I did not kill
anything I had not started. They could have taken CPU from the measurement, so
library-Win64's 3,500.6s/635.3s should be read as an upper bound on time rather
than a clean-box figure. The pass itself reported no `used by another process`
error and exited 0. The **ratio** -- which is what the falsifier tests -- is
robust to that, since both stages ran under the same contention.

CLIENT's timings deserve their provenance stated: its `stage: calls -- done in
146.1s` and `stage: purity -- started 14:25:42` lines sit in the log among
another section's output. They are CLIENT's because CLIENT began at 14:23:14 and
its section total was 158.9s (14:23:14 + ~2s setup + 146.1 + 10.4 + checkpoint =
14:25:53), and because the adjacent `resolve: purity -- 8102 routine(s)` line
belongs to MicroniteMW1Service, whose DB really does hold 8,102 bodied routines
while CLIENT holds 10,150.

## Ruling 14 bracket -- CLIENT proven in [2,500 .. 3,500]

**2,896. INSIDE the bracket.** No INBOX note is owed on this, and
`docs\INBOX-purity-count-outside-bracket.md` was not written.

Subject to the caveat above: 2,896 is an upper bound, and the true value on
freshly parsed sources is <= 2,896. The bracket's lower bound is 2,500, so the
result would survive a debt of up to 396 routines before it left the bracket.
Nothing measured here says whether it would.

## Acceptance 34 and rule 14.2 -- the two new rules

Both rules ship **OFF**; measured with an explicit `--enable`, on DBs that had
already been re-resolved by this task (a pre-purity DB structurally cannot fire
either rule: `effect_free` defaults to -1 and the rules test for exactly 1 and
exactly 0).

| DB | total findings | 14.1 `discarded-effect-free-result` | 14.2 `query-name-with-effect` | spec's 14.2 guess |
|---|---:|---:|---:|---:|
| ORM3 CLIENT | 48,738 | **3** | **6** | 7 |
| DataCopy | 557 | **0** | **5** | 4 |
| YADF | 114 | **0** | **0** | 13 |
| DragLint-Cli (main) | 2,378 | **0** | **54** | 104 |
| **14.1 total** | | **3** | | spec expected 4 |

Section 17's falsifier for 14.1 is "more than ~20 means the statement-position
test is wrong". **3 is well inside that**, so the statement-position test is not
indicted and the rule stays OFF as shipped. No INBOX note is owed.

**Why 3 and not the spec's 4.** The rule's statement-position gate requires the
preceding non-blank code line to end at a statement boundary it can classify, and
stays SILENT (no finding) when it cannot -- Task 7's line-wrap fix (commit
`69274948`) is exactly this gate refusing to fire across a wrapped result use, so
it is conservative by design and can under-count a genuinely discarded call. This
is offered as a consistent explanation for the shortfall, not a claim that the
missing 4th spec case IS that shape -- that has not been shown.

YADF's 14.2 = 0 against a spec guess of 13 is the largest single divergence.
These are brackets, not equalities -- the spec's numbers were modelled on
2026-09-15 pre-1.17.0 indexes with a Python prototype -- and YADF is also the
smallest DB here (243 bodied routines, 9 files). It is recorded as a divergence,
not as a failure, and not investigated in this task.

## Staleness debt measured on one DB (ruling T4-R2a)

The worktree self-DB was rebuilt to put a number on the `e71abafb` debt.

| | files | symbols | refs | routines | proven |
|---|---:|---:|---:|---:|---:|
| BEFORE (`--resolve-only`, resolver 1.5.1, existing parses) | 130 | 23,216 | 185,348 | 2,934 | 194 |
| AFTER (`--rebuild`, full re-parse) | 130 | 23,216 | 185,348 | 2,934 | 194 |
| delta | 0 | 0 | 0 | 0 | **0** |

**The delta is zero, and that does NOT mean the debt is small.** It means this
particular DB had no debt to pay: all 130 of its files were parsed on
2026-09-22 19:44-19:47 UTC, i.e. entirely AFTER `e71abafb`, because the worktree
and its index were both created after that commit landed. The rebuild is a
valid negative control -- it confirms `--rebuild` is idempotent on an
already-fresh index and that no other drift crept in -- but it measures nothing
about CLIENT, DataCopy, YADF or the libraries, whose files are 98-100%
pre-`e71abafb`.

**No measurement in this task sizes the corpus debt.** Obtaining one requires
the re-parse that would fix it (~3h17m for the whole corpus, measured
2026-09-17). That decision is the owner's; see the INBOX note (gitignored,
local-only -- see the caveat section above for the same note).

## Battery

`pwsh -File tests\run_battery.ps1 -LogDir C:\TEMP\battery-purity`, full run, no
narrowing. Printed denominator, verbatim:

```
  runners found under tests\ (run_*.ps1, recursive) : 568
  excluded by policy                               : 1
      tests/run_battery.ps1  -- this driver itself
  runners to execute                               : 567
  counted in: C:\Projects\Delphi-RAG-lint-wt\purity-v2  @ 69274948 (clean)

  560 pass / 7 fail / 0 timeout out of 567 executed  (of 568 found)
  wall clock: 40.4 min
```

**One of the seven reds was this branch's, and it is fixed.**

| runner | cause | status |
|---|---|---|
| `run_backlog_index_guard.ps1` | **MINE** -- the new `docs\INBOX-symbolfacts-stale-since-e71abafb.md` lacked the `dl:backlog status=` header the guard requires on every `docs\INBOX-*.md` | **FIXED** (header added); re-run standalone -> **PASS**, exit 0 |
| `run_lsp_proxy_lifecycle_guard.ps1` | ordering: needs `LspStubServer.exe`, which is built by `run_lsp_proxy_relay_guard.ps1` -- and that runner is #324, i.e. AFTER this one (#323) | not the branch's; re-run standalone -> **PASS**, exit 0 |
| `run_lsp_switch_guard.ps1` | `third_party\dll-win64\drag-lint-switch.exe` was never built in this worktree (it exists in the main tree) | not the branch's |
| `run_lsp_switch_params_guard.ps1` | same missing binary | not the branch's |
| `run_mcp_protocol_guard.ps1` | missing fixture `tests\calls.sqlite` | not the branch's |
| `run_doctests_v021.ps1` | `FAIL: build failed` compiling a Delphi fixture project | not the branch's |
| `run_legacy_cli_fixtures.ps1` | `FAIL: build failed` on 6 IDE-plugin fixture cases (T28 notifier, T29 settings, T32 completionform, T34 save_setting, T51 structure, T54 settings_scan_libraries) | not the branch's |

Evidence for "not the branch's" on the last six: `git diff --name-only
42668dfb..HEAD` lists **no** file under `src\delphi-plugin\`, `src\tools\lsp-switch\`,
`tests\lspproxy`, the doctest fixtures or the legacy CLI fixtures. The branch's
54 changed files are the purity engine, its tests, the CLI, storage, docs and the
two version baselines.

**Effective result after the one branch-caused red was fixed: 562 pass / 5 fail**,
the five being missing worktree prerequisites (an unbuilt `drag-lint-switch.exe`,
an absent `calls.sqlite`, and a Delphi fixture build that does not run in this
worktree). They are reported, not dismissed.

The two guards previously called "pre-existing reds" were **both green** in this
run, as the brief predicted: `run_lsp_reader_guard.ps1` PASS (5.3s),
`run_flag_verb_map.ps1` PASS (4.5s).

Purity-specific suites, all green: `run_purity_emit` PASS, `run_purity_model`
PASS, `run_purity_stage` PASS (5.0s), `run_purity_storage` PASS,
`tests/lint-project/purity-rules/run_purity_rules.ps1` PASS (3.4s),
`run_resolver_version_guard` PASS (6.6s), `run_exe_freshness` PASS (6.6s).

## What is absent from this record

Nothing is owner-gated any more: the gate was released at 14:19 local and both
library passes ran. What remains genuinely unmeasured, and is not estimated,
extrapolated or inferred anywhere above:

1. **The size of the `e71abafb` staleness debt on any DB except the worktree
   self-DB** (where it is zero for the reason given). Every `proven` count in
   this record is an upper bound. Measuring it requires the re-parse that would
   fix it.
2. **The AFTER half of assertion 25** -- what `System.SysUtils.Trim` becomes once
   `SubString` binds. That is Phase 4 and is not claimed.
3. **A clean-box wall-clock for library-Win64** -- see the contention caveat in
   the falsifier section. The ratio is sound; the absolute seconds are an upper
   bound.

## Phase 2 migration -- DEFERRED (plan ruling 10)

Task 9 of the plan. **No `document --apply` was run anywhere in this task** --
not on this repo, not on DataCopy, not on YADF -- and no corpus DB was
re-indexed or re-resolved. Everything below is a dry run or a read-only count.

**Why this is still deferred, restated.** The plan originally deferred Phase 2
because of an autodoc fixed-point defect (stacked orphan blocks never
converging). That defect is FIXED on this branch (C1 + N1, commits `99d4147f`,
`47720953`, folded into `42668dfb`), and this task's own dry run below finds no
trace of it recurring (0 overlapping/duplicate edit ranges in 442 checked). **The
deferral now stands for a different reason: the owner ruled on 2026-09-22 that
corpus-wide doc regeneration across four repositories is theirs to run, not an
agent's**, per the hard constraint in this task's brief. Nothing technical is
blocking `--apply` any more; the decision to run it is what is being deferred.

### Step 1 -- the drift counted three ways, per project

The brief's literal instruction -- "count `doc-drift` findings whose `message`
mentions `Pure`" -- does not work as written: `lint-all --json`'s `doc-drift`
`message` field is the fixed generic string `managed facts block is out of date`
on every DB checked (self, DataCopy, YADF); it never contains the word `Pure` or
`Effect-free`. That is a gap between the brief's assumption and the tool's actual
output, not a drag-lint defect -- the rule fires correctly, it just does not name
what changed in its message. The counts below use the same method Task 5 used
(a literal search for the stored tag `<para>Pure</para>`), cross-checked against
`lint-all`'s real `doc-drift` count so the difference is visible rather than
asserted.

**This repo (drag-lint / `DragLint-Cli`), three numbers for one question:**

| Scope | Command | Result |
|---|---|---|
| Whole `src\` tree (every project sharing this repo) | `grep -ro "<para>Pure</para>" src\ --include=*.pas \| wc -l` (and `-l` for files) | **850 lines in 121 files** -- matches Task 5 exactly |
| This project's compile closure (`drag-lint query --text`) | `drag-lint query --text "<para>Pure</para>" --db src\cli\_D-RAG\drag-lint.sqlite --source pas --json` | **603 lines in 103 files** |
| `lint-all`'s reported scope (`ownRoots` = `src\cli` folder only) | `drag-lint lint-all --db src\cli\_D-RAG\drag-lint.sqlite --json` -> `doc-drift` findings, filtered to the 2 files that hold `Pure` text | **6 findings** (7 raw `<para>Pure</para>` lines exist in those same 2 files -- `DRagLint.Hover.Renderer.pas`, `DRagLint.Hover.Returns.pas`; 1 of the 7 is not currently flagged as drifted) |

**The 850-vs-6 gap, explained, not just reported.** The three numbers form a
funnel and each step's shortfall is fully accounted for:

* **850 -> 603** (247 lines / 18 files dropped): every one of the 18 missing
  files lives under `src\tools\convrules-editor\` -- a *different* tool with its
  own `.dproj` and its own DB, not part of `drag-lint.dproj`'s compile closure.
  Confirmed by diffing the raw file list against the `query --text` result set:
  the 18-file remainder is exactly, and only, that directory. This is the
  "another team's uncommitted work" this worktree is known to carry (see this
  repo's own CLAUDE.md); it is correctly out of scope for THIS project's index,
  by the per-project-DB design, not a bug or a stale index.
* **603 -> 6** (597 lines / 101 files dropped): `lint-all --db <db>` only
  *reports* findings under the project's declared `ownRoots`, which defaults (no
  `drag-lint-project.json` present) to the project file's own folder -- `src\cli`
  alone. The DB indexes the whole compile closure (103 files with `Pure` text),
  but `lint-all` only ever prints findings for files physically inside
  `src\cli`, of which exactly 2 contain `Pure` text. **A count taken from
  `lint-all` alone understates the true drift here by two orders of
  magnitude** (6 vs 850), exactly as the task brief warned.

**DataCopy** (`C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite`, project file at the
repo root so `ownRoots` defaults to the whole repo -- no such gap here):

| Command | Result |
|---|---|
| `grep -ro "<para>Pure</para>" . --include=*.pas` (repo root, excluding `BACKUP*`, `__history`, `__recovery`, `DCU`, `Win32`, `Win64`) | **259 lines in 23 files** -- matches the spec's guess exactly |
| `drag-lint lint-all --db C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite --json` -> `doc-drift` count | **249 findings in 27 files** (superset: all 23 `Pure`-bearing files are among the 27; the other 4 are drifted for unrelated reasons -- stale `Calls`/`Reads`/`Used in units` facts, nothing to do with purity) |

DataCopy shows no ownRoots gap because its project file sits at the repo root,
so its own folder already covers everything -- `lint-all` here is a reasonably
complete proxy for the real drift, unlike this repo.

**YADF** (`C:\Projects\YADF\_D-RAG\YADF.sqlite`):

| Command | Result |
|---|---|
| `grep -ro "<para>Pure</para>" . --include=*.pas` (repo root, same exclusions, plus `vendor`) | **0 lines** in YADF's own 12 units |
| Same search including `vendor\` | 11 lines, all in `vendor\drag-lint\DRagLint.Lint.ReviewMarker.pas` -- a **vendored copy of this repo's own source**, not YADF code |
| `drag-lint lint-all --db C:\Projects\YADF\_D-RAG\YADF.sqlite --json` -> `doc-drift` count | 39 findings, none touching a `Pure` line (there are none to touch) |

The spec guessed 62 for YADF; the measured real number is **0** in YADF's own
code. This is recorded as a divergence, not investigated further here, and it
matches the pattern already noted elsewhere in this record (YADF's 14.2 count
was also the largest divergence from its spec guess) -- YADF is the smallest
project measured and its own units simply never had a stored `Pure` fact stamped
on them. `document --project` skips vendored roots by default (`--help`: "Vendored
roots are named and skipped; `--document-third-party` writes to them too"), so
the owner's YADF command below will not touch the vendored copy either way.

### Step 2 -- dry run `document` on DataCopy (no `--apply`)

```
drag-lint document --project C:\Projects\DataCopy\DataCopy.dproj --db C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite
```

Exit 0. Tool's own summary line: `doc: 493/652 decl(s), 935 edit(s) -- pass
--apply to write`. No `--apply` was passed; nothing was written.

**What the dry run actually does to the 259 stored `Pure` lines, verified
line-by-line, not sampled:** every one of the 259 `<para>Pure</para>` source
lines falls inside a `delete lines X..Y` range the dry run reports for that same
file (259/259 covered -- confirmed by mapping each line against the parsed
delete ranges). Of those 259:

* **~45** land in a block whose replacement text contains
  `<para>Effect-free (proven)</para>` -- these routines are still provably
  effect-free under the new interprocedural engine and get relabeled.
* **~214** land in a block whose replacement text has **no purity fact at
  all** -- not a stray old wording, not a wrong label, simply absent. Spot-checked
  on `DPPRoutines.StripSerialSeparator` (line 144): `sql --db DataCopy.sqlite
  --query "SELECT s.name, sf.effect_free, sf.effect_witness FROM symbol_facts sf
  JOIN symbols s ON s.id = sf.symbol_id WHERE s.name = 'StripSerialSeparator'"`
  returns `effect_free = 0`, witness `accesses AValue.Trim (unbound member)`.
  **This is correct, expected behaviour, not a defect**: the tool only ever
  emits a positive `Effect-free (proven)` fact, never a negative one, so a
  routine the new (stricter, interprocedural) engine can no longer prove pure
  correctly loses its stale, over-optimistic `Pure` label rather than keeping
  it or being mislabelled. Anyone running `--apply` should expect **most of the
  259 stored `Pure` claims to disappear outright**, and only a minority
  (~45, roughly matching DataCopy's headline 62 `effect_free=1` routines, the
  remainder of which never had a stored `Pure` fact to begin with) to survive
  as `Effect-free (proven)`.
* Total `<para>Effect-free (proven)</para>` insertions anywhere in the dry run:
  **54** (`grep -c` on the log) -- the ~9 beyond the ~45 above are decls gaining
  the fact for the first time, not a relabel of a stale `Pure` line.

**No fixed-point / stacked-block defect observed.** 442 `delete lines` ranges
were parsed out of the log; **0 overlap** within the same file (no duplicate or
stacked block for the same declaration). The 29 occurrences of `Used in units:`
in the diff are ordinary, correctly-formed regenerations of an unrelated
class-usage fact that happens to sit in the same drifted blocks -- not the
defect the brief asked to watch for. The only remaining occurrences of the bare
word `Pure` in the whole log (44 of them) are hand-written English prose inside
`<summary>`/`<remarks>` text (e.g. "Pure. Performs no I/O...", "carry one. Pure;
no allocation is retained.") -- untouched by the tool, correctly out of scope
for a machine-generated-fact migration. The exact managed tag
`<para>Pure</para>` appears **zero** times anywhere in the new content.

### Step 3 -- the owner's runbook

DB paths below are resolved, not guessed: `drag-lint resolve-dbs --project
<X.dproj> --json` against the worktree's engine returned exactly these three
paths (section names in parentheses):

* `C:\Projects\Delphi-RAG-lint\src\cli\drag-lint.dproj` -> `DragLint-Cli` ->
  `C:\Projects\Delphi-RAG-lint\src\cli\_D-RAG\drag-lint.sqlite`
* `C:\Projects\DataCopy\DataCopy.dproj` -> `DataCopy-App` ->
  `C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite`
* `C:\Projects\YADF\YADF.dproj` -> `YADF` -> `C:\Projects\YADF\_D-RAG\YADF.sqlite`

**Order matters -- do this FIRST, on the MAIN tree (not this worktree), before
any of the three commands below:**

1. Merge this branch to `main` (Task 9 is the last task; nothing here should run
   from a worktree engine against the owner's live DBs).
2. **Re-parse, not just re-resolve, every DB before regenerating docs from it.**
   The caveat at the top of this record stands: `symbol_facts` on DataCopy, YADF
   and this repo's main-tree DB is up to 100% pre-`e71abafb`, so every
   `effect_free=1` currently on file is an upper bound -- some of what looks
   "still provably pure" above may not survive a fresh parse. Regenerating docs
   against a stale parse would bake a wrong, permanent-looking "Effect-free
   (proven)" claim into source, which is a *worse* failure than the `Pure`
   wording it replaces, because it reads as freshly verified. `--reindex` on
   `document --project` only self-freshens hover/LSP after the write; it does
   not re-parse source, so it does not pay this debt.
3. Confirm the engine deployed for the real run reports resolver `1.5.1-alpha`
   or later (`drag-lint --version`), matching this record's measured binary.

**The three commands, exactly as the owner would paste them** (unchanged from
the brief, now cross-checked against `document --help` -- `--project` accepts
`--apply` and `--reindex` together: "self-freshens so hover/LSP are correct
immediately after"):

```
drag-lint document --project C:\Projects\Delphi-RAG-lint\src\cli\drag-lint.dproj --db C:\Projects\Delphi-RAG-lint\src\cli\_D-RAG\drag-lint.sqlite --apply --reindex
drag-lint document --project C:\Projects\DataCopy\DataCopy.dproj --db C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite --apply --reindex
drag-lint document --project C:\Projects\YADF\YADF.dproj --db C:\Projects\YADF\_D-RAG\YADF.sqlite --apply --reindex
```

Expected duration: each is a `document --project` pass over one project's own
declarations (493/652 decls measured for DataCopy above), not a re-parse or
re-resolve -- seconds, not minutes, per repository. `--reindex` adds a
self-freshen pass on top, still small relative to the corpus `calls`/`purity`
resolve times measured elsewhere in this record (DataCopy: 12.8s + 0.7s).

**Note the `drag-lint.dproj` command targets `src\cli` only.** Per Step 1, most
of this repo's 850 `Pure` lines (818 of them, in `src\analysis`, `src\lint`,
`src\index` etc. and the separate `src\tools\convrules-editor` project) are
either outside `drag-lint.dproj`'s `ownRoots` or outside its compile closure
entirely and will NOT be touched by this command. If the owner wants the rest of
this repo's own `Pure` text migrated, that needs the other project files in this
tree documented separately (each has its own `.dproj`/DB) -- this is named here,
not solved, since it is outside Task 9's three-repository scope.

**Check afterward** (acceptance 35, adjusted for what Step 1 found about
message text): `doc-drift`'s message is generic and will not literally say
`Pure` or `Effect-free`, so the executable check is a text search, not a
`lint-all` grep on the message field:

```
drag-lint query --text "<para>Pure</para>" --db <db> --source pas --json
```

should return **zero rows** on each of the three DBs above once `--apply` has
run and the DB has been reindexed. Additionally confirm `<para>Effect-free
(proven)</para>` count is unchanged or higher than before (it should never drop
for a routine that was already correctly proven), and spot-check a handful of
routines whose `Pure` label disappeared (the ~214-of-259 case measured above for
DataCopy) against `symbol_facts.effect_free` to confirm each is genuinely `0` or
`NULL`, not a resolver miss.

**Second-drift warning (spec section 13, cited in the plan but not itself
present in this tree).** The plan records that this set grows again after Phase
4 binding work lands -- i.e. this is not a one-time migration. Plan for two
passes: this one now, and a second after Phase 4 changes which routines resolve
and which do not.

### The other three repositories

**DataCopy** and **YADF** are Mercurial repos; **ORM3 CLIENT** is Mercurial with
a **per-folder** repo layout (four separate `hg` roots, none at the top level --
see this project's own memory note on that). None of the three is this plan's
to run:

* DataCopy and YADF: the two `document --apply --reindex` commands above are
  ready to paste once the owner chooses to run them; they write to a Mercurial
  working copy, so the owner should `hg status` clean first and review the diff
  with `hg diff` before `hg commit`, the same discipline this repo's CLAUDE.md
  already states for `.hg`-tracked trees.
* ORM3 CLIENT was not measured for `Pure` line count in this task (out of the
  three repos named in the brief). If the owner wants it included, the same
  three-step method above applies, but CLIENT's `hg` root for its own folder
  must be identified first (`hg root` from inside that folder) rather than
  assumed to be a single repo-wide commit.

### Risks and order

1. **Reindex/re-parse before regenerating, not after.** Covered above -- this is
   the single largest risk, because a stale-parse `document --apply` writes a
   confident-looking but wrong `Effect-free (proven)` claim, which is worse than
   the `Pure` wording it replaces.
2. **This is not idempotent for every line.** Most of DataCopy's 259 stored
   `Pure` lines will simply vanish, not relabel, on the real run (measured
   above). That is correct, but it means a line-count diff after `--apply`
   should show far FEWER `Pure`+`Effect-free` lines combined than 259 existed
   before, not the same count relabelled -- do not treat a smaller total as a
   defect.
3. **`src\cli`'s command does not reach this repo's other `Pure` text.** Named
   above; a full self-repo migration needs more than the one command in the
   owner's three-line list.
4. **Two passes, not one**, per the spec's second-drift warning.
5. **After `--apply`**, verify with the `query --text` zero-row check above on
   all three DBs, and re-run this repo's own guard battery
   (`tests\autotest\run_docs_sync_guard.ps1` and friends) since `--help`/README
   sync is this repo's own highest-priority rule and a doc-comment rewrite at
   this scale is exactly the kind of change that rule exists for.
