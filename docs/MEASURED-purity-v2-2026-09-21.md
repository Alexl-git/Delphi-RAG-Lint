# MEASURED: interprocedural purity v2 -- corpus re-resolve, 2026-09-22

Task 8 of `docs\superpowers\plans\2026-09-21-interprocedural-purity-v2.md`.
This is the record the owner reads. Every number below was produced by a command
that is quoted beside it. Nothing is extrapolated, and nothing that was not run
is reported as a result.

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

Full write-up, repro and remedy cost: `docs\INBOX-symbolfacts-stale-since-e71abafb.md`.

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
| **library-Win32** | `drag-lint index --all --resolve-only --only Library --platform win32 --jobs 1` | `...\library-Win32-resolve.log` -- exit 0, **4,459.3s (74.3 min)**, ran 15:31:48 - 16:46:07 |
| **library-Win64** | `drag-lint index --all --resolve-only --only Library --platform win64 --jobs 1` | `...\library-Win64-resolve.log` -- exit 0, **4,276.4s (71.3 min)**, ran 16:46:30 - 17:57:44 |

The 33 sections are every non-`Library` section of
`third_party\dll-win64\drag-lint.json`.

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
2026-09-17). That decision is the owner's; see the INBOX note.

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
