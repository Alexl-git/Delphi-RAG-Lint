# INBOX sweep 2026-08-16 (session 21) -- measured status per note

Owner asked to "go through the 57 notes" before LoopZero and before the LSP fix.
This file is the running record so the sweep survives a context reset. **Every
row is MEASURED, not read off the note**, because the dominant failure mode in
this backlog is a note recording the world as it was when written.

Legend: **CONFIRMED** = reproduced today · **REFUTED** = claim no longer true,
retire the note · **PARTIAL** = some claims stand, some do not ·
**UNTESTED** = not yet measured in this sweep.

## Measurement traps hit while doing this (read before adding rows)

1. **`Select-Object -First N` on a native command corrupts `$LASTEXITCODE`.**
   It terminates the upstream process early, so an exe that exits 0 reports 1.
   Two notes were nearly recorded as "now exits non-zero" because of it.
   Capture the whole output to a variable first, THEN read `$LASTEXITCODE`.
2. **A rule filter test needs a file that actually has findings for BOTH rules**,
   otherwise "no difference" proves nothing (hit on `lint` vs `lint-all`).
3. **`--rule <id>` rejects query-rule ids outright** unless `--rules-dir` is
   passed -- the built-in AST rules and the 56 `.scm`/`.json` rules are two
   different registries at the CLI surface. That is arguably its own defect.

## Priority 3 -- silent no-ops and wrong-scope commands

| note | status | measurement |
|---|---|---|
| `index-only-nonmatching-section-is-a-silent-noop` | **CONFIRMED** | `index --all --only "NoSuchSectionXYZ"` -> **exit 0**, two lines of output, no error, nothing indexed. Dry-run likewise exit 0 with no "matched nothing" message. |
| `context-bundle-empty-for-bare-name` | **CONFIRMED** | `context --task "modify TypeIsRefCountedOrValue"` -> exit 0, `Token count (estimated): 0`, 194 chars. Qualified name -> exit 0, 1435 tokens, 4637 chars. Third confirmation, three separate days. |
| `lint-rule-filter-leaks-other-rules` | **CONFIRMED** | `lint <f> --rule write-only-local --json --rules-dir rules` returned findings whose only rule id was **`bare-except`** -- i.e. the requested rule was absent and an unrequested one was emitted. The `--rule` filter does not reach the query-rule pass at all. |
| `lint-all-json-stdout-banner` | **REFUTED -- retire** | `lint-all --db <db> --json --quiet` stdout begins with `[` and round-trips through `ConvertFrom-Json`. The banner is no longer on stdout. |
| `lint-single-file-silently-omits-lint-all-rules` | **CONFIRMED, worse than stated** | Fixture: one `.pas` carrying a stranded `// dl:ok bare-except@dead`. `lint <file>` -> **`0 finding(s)`**. `lint-all` over the same one file -> **`2 finding(s)` (1 info, 1 hint)**, including `review-marker-unused`. Same file, same DB, same rules dir. (First attempt was INVALID -- used a file with no marker, so nothing could fire either way.) |
| `lint-all-never-scans-dpr-files` | **CONFIRMED** | Fixture: `SweepProg.dpr` containing a real bare `except` + one `.pas`. `lint-all` -> `0 finding(s) ... **1 file(s) scanned**` for a two-file project, and the `.dpr`'s `bare-except` is absent. Corroborated on our own tree: the ONLY rule id appearing on any `.dpr` line in `lint-report-20260816.txt` is `unit-not-in-dpr`, a project-level rule that reports *at* the `.dpr` without scanning it. So `.dpr` bodies -- `Application.CreateForm`, init logic, exception handling -- are never linted anywhere. |
| `index-all-only-silently-does-nothing` | **REFUTED -- retire, merge into the note above** | Its symptom is `index --all --only DragLint-Cli --recompile` producing NO output and indexing nothing. Measured: exit 0, `files=102 symbols=13496`, 1.4s. A **real** section name works. What survives is only the **non-matching** section case, which is `index-only-nonmatching-section-is-a-silent-noop`. Two notes, one live defect -- fix it once, in that note. |
| `lint-config-not-discovered-beside-project` | **CONFIRMED, but currently harmless on YADF** | A live instance exists: `C:\Projects\YADF\drag-lint-lint.json` (untracked) disables `commented-out-code` per an owner ruling of 2026-08-12, and is being ignored. Measured impact today: **nil** -- `commented-out-code` fires nowhere in YADF's current report either way. So the defect is real but is not inflating any current count; do not justify the fix with a number it does not produce. Clean A/B on a synthetic project. `drag-lint-lint.json` = `{"disabled":["bare-except"]}`. Beside the `.dproj`, auto-discovered: `bare-except` **still reported**. Same file passed as `--config`: **suppressed**. So the file is honoured only when named explicitly. |
| `cross-project-symbol-use-defeats-single-project-rules` | **CONFIRMED by design, not a regression** | Structural: `unused-public-symbol` asks a whole-corpus question while the authoritative DB set is deliberately one project + platform library (owner ruling 2026-08-13). Not fixable by widening the DB set without reopening that ruling -- the fix has to be a scope-aware rule that declines to answer, or an explicit cross-project mode. Reclassify from "silent no-op" to a design constraint. |
| `lint-scope-stale-files-and-project-members` | **UNTESTED** | Bug 1 (index never prunes vanished files) is testable: index a dir, remove a file, reindex, see if it still yields findings. |
| `whole-db-resolve-degrades-a-stale-index` | **UNTESTED** | Needs a deliberately staled index; more setup than the rest. |

## Notes carrying a genuine closed banner (retire, do not re-investigate)

| note | banner |
|---|---|
| `bare-except-anchor-defeats-a-hand-written-marker` | FIXED 2026-08-16 (session 21), guarded 6/6 |
| `create-inside-try-qualified-lhs-not-flagged` | `Status: RESOLVED (2026-08-11, Fix 4)` -- **but the INDEX still lists it under priority 2 as an open false positive.** Verify which is right before retiring; note-vs-index drift is exactly what this sweep exists to catch. |

## Priority 2 -- measured on the four consumer projects (2026-08-16, post-anchor-fix)

All four reindexed first, then `lint-all --project`. Non-zero exit is just
"findings present", not a failure.

| project | total | 0 err | bare-except | review-marker-unused | scanned |
|---|---|---|---|---|---|
| YADF | 14 | yes | 4 | **4** | 8 |
| YADFOT | 12 | yes | 3 | **3** | 9 |
| YADFSetup | 15 | yes | 3 | **3** | 9 |
| DataCopy | 60 | yes (15 warn) | 8 | **8** | 15 |

### The dominant remaining category is MY OWN unpaid churn, and it is now exact

`review-marker-unused` equals `bare-except` in **every** project. That is the
`bare-except` anchor move (`430fd37`): each stranded marker now costs TWO
findings -- the `bare-except` it no longer suppresses, plus the `unused` hint on
the marker itself. It is **8 of 14, 6 of 12, 6 of 15 and 16 of 60** of what is
left.

**So the single highest-value next action for all four projects is the 12-marker
re-stamp**, not any rule work: move each marker from the statement line up onto
its `except`, and re-hash. Expected result YADF 14->6, YADFOT 12->6,
YADFSetup 15->9, DataCopy 60->44.

Do NOT hand-write the markers -- `drag-lint allow <file> --fix-line <L>
--fix-rule bare-except --apply` is the only code path that formats one. **Open
question to settle first: whether `allow` preserves the hand-written reason text**
(`-- rethrown by the caller`, etc.). If it does not, the reasons must be
re-attached by hand or they are lost, which would be a real regression in the
accountability story.

### Notes settled by this measurement

| note | status |
|---|---|
| `object-leak-is-systematically-false` | **CONFIRMED at the corrected count** -- 1 / 1 / 1 across the three YADF projects, i.e. the SAME finding in a shared unit, exactly as the note's own re-measurement says. Not the 3/7/7 the original text claimed. |
| `yadfot-loopzero-remainder-2026-08-13` | **STALE** -- remainder is now 12, dominated by the marker churn above, so its itemisation predates two rule fixes. Re-derive after the re-stamp rather than reading it. |
| `yadf-triage-2026-08-12-out-param-and-object-leak-false-alarms` | **PARTIALLY STALE** -- `out-param-not-set` does not appear in any YADF project now (2 remain in DataCopy only). |

## Score so far -- 11 of 58 notes settled

| outcome | count | notes |
|---|---|---|
| **CONFIRMED** (still real) | 6 | `index-only-nonmatching-section`, `context-bundle-empty-for-bare-name`, `lint-rule-filter-leaks-other-rules`, `lint-single-file-silently-omits-lint-all-rules`, `lint-all-never-scans-dpr-files`, `lint-config-not-discovered-beside-project` |
| **REFUTED** (retire) | 2 | `lint-all-json-stdout-banner`, `index-all-only-silently-does-nothing` |
| **Reclassified** | 1 | `cross-project-symbol-use-defeats-single-project-rules` -> design constraint |
| **Already closed** | 2 | `bare-except-anchor` (today), `create-inside-try` (verify vs index) |

**Priority 3 is now fully swept except two** (`lint-scope-stale-files`,
`whole-db-resolve-degrades-a-stale-index`).

### The cheap fix cluster this sweep exposes

Four of the six CONFIRMED items are the SAME shape -- *a command narrows its work
and reports success for the narrowed set as if it were the whole set*:

* `--only <nonmatching>` indexes nothing, exit 0
* `--rule <id>` does not reach the query-rule pass (asked for `write-only-local`,
  got `bare-except`)
* `lint <file>` reports `0 finding(s)` where `lint-all` on that one file reports 2
* `lint-all` skips `.dpr` bodies entirely, and says `1 file(s) scanned`

Each is small on its own. Fixing them as ONE change -- *"a command that could not
do what was asked must say so and exit non-zero, and a scanned-count must name
what it excluded"* -- is better value than four separate patches, and it is the
same principle the `lint-all` ownRoots work already applied to third-party roots
(named, with a count, not silently dropped).

## Still to sweep

Priority 1 (2) · Priority 2 (~11) · Priority 3 (2 left) · Priority 4 (~7) ·
Priority 5 (~8) · Priority 6 (~6) · Not-defects (~10). **47 remaining.**
