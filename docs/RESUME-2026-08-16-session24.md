# RESUME -- session 24 close (2026-08-16, late)

## State

| | |
|---|---|
| branch | `main`, HEAD **`d780a17`** |
| working tree | clean |
| unpushed | **110 commits, ON PURPOSE.** Do not push. The owner lifts this gate. |
| battery | **311/311 pass, 0 fail, 15.5 min** -- run at `16456a2`+memo, AFTER every change below |
| INBOX | **9 open / 104 retired** |
| ORM3 `lint-all` | **320.02 s** (was 572.31 s), report byte-identical |

## What shipped, four commits

| commit | what |
|---|---|
| `243e961` | VCL/FMX framework preference in `query --name`; closes `converter-editor-phase-g` |
| `5a17029` | the measurement record that killed the `unresolved-name` premise |
| `16456a2` | `find-unit`: read every `--db`; never invent a second `uses` clause |
| `d780a17` | memoise `OverloadArityTag` -- **572 s -> 320 s** |

Both new suites were run against the **UNFIXED** build and went RED
(`run_query_framework_preference` 3 of 15 asserts; `run_find_unit_multidb` 6 of 6).

---

## 1. The thing worth reading before anything else

`unresolved-name` was 269 s of a 530 s run and was read, for three sessions, as
"`FindUnresolvedNameCallers`, once per declaration". **Both halves were wrong.**

Splitting the timer and adding a CALL COUNT to each part:

```
unresolved-name                    255.26 s
  ambiguity-gate                     0.01 s (   49 call(s), 0.30 ms/call)
  primary-query                      2.41 s ( 4293 call(s), 0.56 ms/call)
  rest-of-window                   252.83 s
overload-arity-tag                 255.48 s (24286 call(s), 10.52 ms/call)
```

That query costs **2.41 s**. Its in-process 0.56 ms/call **agrees** with the
external replay's 0.78, so **the ~80x in-process gap never existed** -- the
timer enclosed `LeafNameIsUnambiguous` and the `ToFactRef` loop as well, and the
two measurements were never of the same thing.

Killed on the strength of that bad attribution, across three sessions: the
uses-reach CTE, a missing `refs.name_text` index, missing `sqlite_stat1`, and
(this session) the `NOT IN (SELECT ref_id FROM call_edges)` predicate. A unary
`+` plan pin and a bounded ANALYZE were **shipped** for it. All of it aimed at a
statement costing two and a half seconds.

**A timer with no CALL COUNT beside it is what hid this.** The counts are
permanent now. Do not remove them.

The real cost was `OverloadArityTag` -- `FindAllChildSymbols` per rendered
caller row, materialising every sibling of the parent class to count same-named
ones. Memo keyed on **(store pointer, symbol id)**; ids are per-DB, so a bare id
key returns one DB's answer for another DB's symbol.

## 2. Next, in the note's own ranking

| item | shape |
|---|---|
| **`per-file scan`** | The NEW dominant phase: **141 s of 320 (44%)**, purely because everything else shrank. **Never profiled.** Cheapest big win available. |
| `class-metrics` | 56 s, never looked at. |
| `seealso` | 17.6 s, the largest remaining doc-drift sub-item. |
| **cross-DB `ToFactRef` bug** | **CORRECTNESS, not perf.** In the extra-store loop `ToFactRef` closes over the PRIMARY store while `RC.EnclosingSymbolId` came from the EXTRA store, so `OverloadArityTag` is handed an id from the wrong DB. Needs its own fix AND test. |
| `resolve-uses` | Same single-`--db` shape `find-unit` had (`CLI.pas:3405`), unexamined. Its `AlreadyUsed` +1000 scoring term is inert whenever the `--in` file is not in the scanned store. |
| `index-runs-are-not-resumable` | Group B 5b, still the plan's HIGHEST-RISK item, not started. The stamp must sit inside the transaction `CommitFileTx` closes. |
| `rule-hardening-plan-2026-08-13` | One live item: `unused-public-symbol` (12). Needs `TProjectLintRules.Run` to accept extra stores. |

## 3. Traps this session paid for

* **A `git add` with one stale pathspec aborts the WHOLE add** -- the first
  commit landed with only a rename in it and had to be amended. Check
  `git show --stat` after committing, not just the exit code.
* **`git mv` stages the OLD blob** when the file had unstaged edits: the edit
  must be `git add`ed separately or the banner silently does not ship.
* **PowerShell buffers `2>` redirection** -- a long run's stderr file stays 0
  bytes until the process exits. Not a hang.
* **You cannot rebuild while a measurement run holds the exe** -- the staging
  copy fails. Sequence long runs and builds; do not overlap them.
* Standing, and all re-confirmed: kill orphaned `drag-lint` before diagnosing
  anything DB-shaped; PowerShell has no heredoc (`git commit -F`); `.dpr` suites
  compile the engine from source, so do not edit source during a battery.

## 4. Outside this repo

Unchanged from session 23 -- `C:\Projects\DataCopy` and `C:\Projects\YADF`
(Mercurial) still carry that session's uncommitted edits, and `Loader2019` still
holds its verified `FreeAndNil` leak fix.
