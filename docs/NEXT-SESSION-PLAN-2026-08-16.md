# Next session plan -- the 23 open notes, sorted, with owner instructions

Written 2026-08-16 at the end of session 21, at the owner's request, so the three
groups survive a context clear. `docs\INBOX-INDEX.md` carries the same split;
this file adds the owner's instructions for what to do with each group.

---

## GROUP A -- 11 verifiable now. **Work these.**

Owner instruction: *"Deal with 11 verifiable errors."*

| # | note | state at end of session 21 |
|---|---|---|
| 1 | `exception-cref-transitive-raise` | **Start here, and see the special instruction below.** Measured with a worked example: `FormsMap.pas:76` documents the SINGULAR `GenerateFormsCsv` overload, whose body at `:1561` is a one-line delegation; the `raise` lives in the array overload at `:1545`. Accounts for **3 of the 6** doc-drift findings that survive a converged autodoc. |
| 2 | `docdrift-4-survive-a-converged-autodoc` | MEASURED: autodoc converges on pass 1 (no oscillation) yet **6** survive, not 4. Three are item 1 above. The other three are `TreeSitter.pas` "managed facts block is out of date" -- **the doc WRITER and the doc CHECKER disagree about the same block**, which is this note's real content. |
| 3 | `qualified-type-receiver-does-not-resolve` | RE-DIAGNOSED: `TypeReceiver` already has a Kind 7 rung for unit-qualified receivers. Measurement shows **no call ref is emitted for that shape at all** -- the gap is in ref EXTRACTION. Do not start at `CallResolver`. |
| 4 | `used-before-assignment-real-shape-is-intra-item-ordering` | Partly addressed -- `and`/`or` left-to-right sequencing is modelled (`CollectAndOrLeftDefs`); the general position-ordered case is not. |
| 5 | `whole-db-resolve-degrades-a-stale-index` | Needs a deliberately staled index. Small setup; simply not done yet. |
| 6 | `autodoc-caller-list-fabricates-callers-for-common-method-names` | Its own banner warns that only `Create` was re-measured before it was called closed. Re-measure other common names first. |
| 7 | `autodoc-returns-section-incomplete` | Inbound from YADF, 2026-07-27. Not re-measured this session. |
| 8 | `buildfor-defaulted-args-diverge-between-entry-points` | Two entry points render the same declaration's facts block differently. `BuildFor`'s defaulted tail; the CLI passes manifest caps explicitly, the back-compat overload takes defaults. |
| 9 | `cycles-scope-and-local-var-refs` | A local variable resolved to another unit's field. |
| 10 | `parse-error-shellshock-units` | Needs the named units to reproduce. |
| 11 | `loader2019-formcreate-inifile-leak` | External-project finding. **Re-check against this session's object-leak fixes before treating it as open** -- self-linking construction and `Result.`/`Self.` writes both changed. |

### Special instruction for item 1

Owner: *"For `exception-cref-transitive-raise` call Fable subagent to devise a
plan."*

Give Fable this context, which is already worked out and must not be re-derived:

* The check is `Doc.Drift.pas:821-830`, gated on `ASym.ImplStartLine > 0`.
* **The cheap fix is wrong.** Reusing the bodyless carve-out directly above it
  (skip when `Facts.Raises` is empty and `Facts.Calls` is not) would stop
  grading the tag almost everywhere -- "calls something, raises nothing itself"
  describes most routines. Narrowing to exactly one call is arbitrary.
* **The correct fix resolves the callee.** `TDocFacts` carries `Calls` and
  `Raises`; `TDocDrift.Analyze` already receives `AStore`. One level is enough
  for all three known cases.
* Cost is why it was not done: per-callee facts (or a store query for raises)
  inside a checker that currently does no such lookup.

---

## GROUP B -- 7 NOT verifiable in a normal session. **Do not work these yet.**

Owner instruction: *"Leave 7 non-verifiable for now for future research... For
now ask Fable subagent to review these. Maybe Fable will find a solution in our
current setup."*

Each needs a large corpus, an hours-long rebuild, or a live IDE. **None was
re-measured on 2026-08-16** -- that is a statement of fact, not a guess at their
status.

| # | note | why it cannot be checked here | what it would take |
|---|---|---|---|
| 1 | `library-reindex-25x-slower-on-large-db` | Needs the ~1.4 GB platform library DB | A full library reindex (hours). Note says **cause identified and measured**, three hypotheses tested and refuted -- so this is closer to fixable than the rest. |
| 2 | `incremental-index-hangs-on-large-db` | Reproduces only at large-DB scale | A large DB plus a long observation window |
| 3 | `indexer-livelock-when-two-platforms-run-concurrently` | Needs two concurrent platform indexers | **DIAGNOSED 2026-08-11** -- the original concurrency theory in the note was wrong; read the diagnosis, not the headline |
| 4 | `index-all-win32-library-rebuild-aborts` | Win32 library rebuild | Hours, and Win32 is the platform nothing else builds |
| 5 | `lint-all-project-wide-phase-dominates-runtime` | Needs a large project (ORM3) to time | **Largely FIXED 2026-08-12** -- only "what is left" remains |
| 6 | `index-runs-are-not-resumable` | Cost is measured in hours, repeatedly | **CONFIRMED 2026-08-16**: the only checkpoint machinery is `PRAGMA wal_checkpoint`, unrelated to resuming a run |
| 7 | `codelens-cache-has-no-eviction` | Lives in the IDE plugin BPL | **CONFIRMED 2026-08-16**: `Clear` + per-file `Remove`, no size bound anywhere. Fixing needs a BPL build with the IDE CLOSED |

**Ask Fable to review this group for anything solvable in the current setup.**
Two are already diagnosed (#3, #6) and two are partly done (#1, #5), so the
question for Fable is narrower than it looks: *which of these can be fixed
without the environment that would let you verify them, and how would we gain
confidence without it?*

---

## GROUP C -- 5 not defects. **Leave.**

Owner instruction: *"Leave 5 non-defects."* Listed so they are not lost, and so
nobody counts them as engine debt again.

| # | note | what it actually is |
|---|---|---|
| 1 | `rule-hardening-plan-2026-08-13` | A PLAN answering an owner question about reducing false positives -- not a defect report |
| 2 | `exception-class-unit-and-generated-exception-types` | Feature request + design question. Its own status line: *"Not implemented."* |
| 3 | `converter-editor-phase-g-engine-findings` | Workstream status. Its own status line: *"NOT pushed, NOT merged, NOT deployed. Deliberate."* |
| 4 | `ide-lsp-ram-and-shim-todo` | Items 1-2 DONE; items 3-4 BLOCKED on the IDE being startable |
| 5 | `yadf-share-review-marker-hash` | Owner request to share the marker-hashing helper with YADF. **Note: the hash changed this session** (window hash for lone-keyword anchors), so any shared helper must ship that behaviour or the two will disagree |

---

## Also relocated, not closed

`docs\BACKLOG-editor-integration\` -- 6 notes, one programme, four senders. Moved
out of the defect INBOX because they are features. Its README records the thing
that matters most: **the VS Code client had never once completed a start**, so
every design in that folder assumed a working client that did not exist. Fixed
in this session, which makes "start it and see what works" cheaper than another
design round.
