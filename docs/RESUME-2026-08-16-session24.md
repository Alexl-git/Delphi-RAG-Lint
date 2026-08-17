# RESUME -- session 24 close (2026-08-16 -> 08-17)

## State

| | |
|---|---|
| branch | `main`, HEAD **`8376022`** |
| working tree | clean |
| unpushed | **118 commits, ON PURPOSE.** Do not push. The owner lifts this gate. |
| battery | **315/315 pass, 0 fail, 15.7 min** (316 runners now; the count rises with each new suite) |
| INBOX | **8 open / 105 retired** |
| ORM3 `lint-all` | **320 s** (was 572 s), report byte-identical |
| `unused-public-symbol` | **6** across all four consumers (was 12); all 6 genuine |

## What shipped, ten commits

| commit | what |
|---|---|
| `243e961` | VCL/FMX framework preference in `query --name`; closes `converter-editor-phase-g` |
| `5a17029` | the measurement record that killed the `unresolved-name` premise |
| `16456a2` | `find-unit`: read every `--db`; never invent a second `uses` clause |
| `d780a17` | **memoise `OverloadArityTag` -- 572 s -> 320 s (-44%)** |
| `8605017` | an extra store's caller gets its overload tag from THAT store |
| `c761b5f` | `resolve-uses`: read every `--db`; stop suggesting already-imported units |
| `bd30afa` | **per-file index resume** -- a killed engine-change reindex continues |
| `fc2d613` | `unused-public-symbol` consults the siblings a shared unit NAMES (12 -> 6) |
| `8376022` | the battery now counts the 68 legacy `.bat` tests it does NOT run |

Every new suite was run against the **UNFIXED** build and went RED. Five suites
added; none of them was accepted on a green run alone.

---

## The two things worth reading before doing anything else

### 1. The profiler attributed a cost to the wrong thing for three sessions

`unresolved-name` was 269 s of a 530 s run and was read as
"`FindUnresolvedNameCallers`, once per declaration". **Both halves were wrong.**
That query costs **2.41 s**, and its in-process 0.56 ms/call AGREES with the
external replay -- so **the famous ~80x in-process gap never existed**. The timer
simply enclosed more than its name said.

Killed on the strength of that bad attribution: the uses-reach CTE, a missing
name index, missing `sqlite_stat1`, and the `NOT IN (SELECT ref_id FROM
call_edges)` predicate. A unary `+` plan pin and a bounded ANALYZE were
**shipped** for it. All aimed at a statement costing two and a half seconds.

**What hid it was a timer with no CALL COUNT beside it.** The counts are
permanent now. Do not remove them.

### 2. A backlog note is a record of what someone believed on one day

`rule-hardening-plan` had ten rows. Exactly ONE needed the fix it described --
and even that one had the wrong counts ("8 alive + 3 dead" out of 9). Five rows
were stale and fired zero times. One was fixed for a completely different reason
than the one written down. The `index-runs-are-not-resumable` plan was wrong
twice: it reused `ForceReparse` (which is set for three reasons, only one of
which may resume) and its test fixture would have tested nothing.

**Re-measure before coding is not advice in this repo. It is the finding.**

---

## Next, in the order the owner set

### Carried backlog (remaining)

| note | shape |
|---|---|
| `68-bat-tests-are-invisible-to-the-battery` | **NEW, and the cheap half is done** -- the battery now prints the count. What remains is TRIAGE: convert what still describes current behaviour to `run_*.ps1`, DELETE what does not. Do NOT bulk-repoint them at the Win64 exe and run them; that turns an unknown into unattributed red inside the gate. |
| `buildfor-defaulted-args-...` | `ABaseDir` / `AIncludeSince` / `AExtraStores` / `AComplexityMin` defaulted on the repair path. `AExtraStores` is the risky one -- use a cross-DB fixture. |
| `exception-class-unit-...` | Feature. 64 distinct messages on ORM3 (not the 400 that would have killed it). Build Stage 1. |
| `incremental-index-hangs-on-large-db` | The "hang" is the whole-DB resolve. A session-23 suspicion that the affected-set is O(corpus) was REFUTED on real code -- do not carry it forward. |
| `ide-lsp-ram-and-shim-todo` | **Needs a live IDE. Cannot be done headless.** |
| `yadf-share-review-marker-hash` | Owner request; 249 markers across three repos, so the cheap window has closed. |
| `find-unit-silently-uses-only-the-last-db` | All three defects fixed and covered. Open only as the pointer to the `.bat` triage above. |
| `index-runs-are-not-resumable` | Headline shipped. Open only for redirected output arriving in blocks -- **and its stated cause is UNVERIFIED**: the note blames the engine's stdout buffering; what was observed was PowerShell's `2>`. Measure which before changing either. |

### Then the perf list (all of it newly visible because doc-drift shrank 328 -> 78 s)

* **`per-file scan` is now the dominant phase: 141 s of 320 (44%). NEVER PROFILED.** Cheapest big win.
* `class-metrics` 56 s -- never looked at.
* `seealso` 17.6 s -- largest remaining doc-drift sub-item.
* `unused-unit-in-uses` ~17 s.

## Traps this session paid for

* **`git add` aborts ENTIRELY on one stale pathspec** -- a commit landed with only
  a rename in it. Check `git show --stat` after committing, not just the exit code.
* **`git mv` stages the OLD blob** when the file has unstaged edits.
* **`git stash push -- <path> --quiet` reads `--quiet` as a PATHSPEC**, so the
  stash silently does not happen -- and the "unfixed" build still has the fix,
  making a RED check pass and look like a vacuous guard. Caught only from the
  error line.
* **Stashing one file of a multi-file change breaks the build** (an interface
  declaring a method with no implementation). For a RED check, disable the
  DECISION surgically instead.
* **PowerShell buffers `2>` to a file** -- a long run's stderr stays 0 bytes until
  exit. Not a hang.
* **You cannot rebuild while a measurement run holds the exe.** Sequence them.
* Standing: kill orphaned `drag-lint` before diagnosing anything DB-shaped;
  PowerShell has no heredoc (`git commit -F`); `.dpr` suites compile the engine
  from source, so never edit source during a battery.

## Outside this repo

Unchanged: `C:\Projects\DataCopy` and `C:\Projects\YADF` (Mercurial) still carry
session 23's uncommitted edits; `Loader2019` still holds its verified
`FreeAndNil` leak fix.
