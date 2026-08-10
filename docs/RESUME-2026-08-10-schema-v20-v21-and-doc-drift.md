# RESUME -- schema v20/v21, the 77-caller bug, and doc-drift 355 -> 13

Date: 2026-08-10. Branch `main` = **cf64a88, PUSHED (0 unpushed)**.
66 commits published to github.com/Alexl-git/Delphi-RAG-Lint.

## Status -- what shipped

| | start | end |
|---|---|---|
| `lint-all` | 3,321 | **2,773** |
| `doc-drift` | 355 | **13** |
| `TQueryRule.Create` callers | 77 | **1** (resolved, unmarked) |
| battery | (owed) | **251/252** |
| convergence gate | failing | **0 pending edits** |

Eleven fixes, in dependency order:

1. **514 false `doc-drift`** -- `TDocDrift.Analyze` regenerated managed blocks with
   `AIncludeSeeAlso=False` (the `Build` default) while `document` writes them True, so the
   staleness compare measured the OPTION difference, not drift. Flag threaded.
2. **`<param>` carries its DECLARED TYPE** (owner ruling). No schema change --
   `symbols.signature` already held types. `doc-param-no-description` 574 -> 0.
3. **Cross-DB callers silently dropped** -- the `N = 1` leaf-name gate is wrong for EXTRA
   stores, where `N = 0` is normal (an extra DB supplies CALLERS, not the declaration).
4. **Schema v20 `refs.receiver_text`** -- the call-site receiver, written by the resolve pass
   (which already computed it and threw it away).
5. **Receiver-aware caller filter** -- ends the fabricated caller lists.
6. **Generic receivers read as EMPTY** -- `TArray<string>.Create` looked like a BARE call.
7. **Paren-less `TFoo.Create;`** was kind `member-access`, so it formed no edge AND never
   reached the unresolved bucket -- invisible to every caller surface.
8. **Unit-qualified `Unit.TType.Create`** never resolved (`TypeReceiver` bailed on the first `.`).
9. **doc-drift graded implementation-section decls** the writer never touches -- 171 -> 0.
10. **Schema v21 `refs.external_target`** -- cross-DB calls resolved BY NAME.
11. **Malformed-fence guard + `<returns>` type baseline** -- doc-drift 130 -> 13.

## Resume point -- the ONE job owed

**Library Win32 + Win64 at schema v21.**

```
drag-lint index --all --only Library --platform win64 --recompile
drag-lint index --all --only Library --platform win32 --recompile
```

Win64 is currently at schema **20**, `PRAGMA quick_check` **ok**, 6,978 files / 2.2M symbols.
A 43-minute run did the schema work and was then stopped: it targeted v20 while the engine had
moved to v21, and it held a Windows lock on `third_party/dll-win64/drag-lint.exe` that blocked
every deploy. Expect ~45+ minutes each. It is a LOCAL artifact and blocks nothing.

Do NOT start it while you intend to rebuild/deploy the exe -- see Gotchas.

## Not done yet (ordered)

1. **Library DBs at v21** (above).
2. **`duplicate-code` 267 + `field-by-name-in-loop` 340** -- the real remaining lint debt. Both
   were SAMPLED and judged real earlier; they need code changes, not rule changes.
3. **5 x `documented <exception cref> but the body never raises it`** -- small, human judgement
   per site.
4. **7 x `function returns a value but has no <returns> tag`** -- the residual after the type
   baseline: the index could not recover a return type, so the engine correctly emits nothing
   rather than a blank row.
5. **PHASE 4 live runs on YADF / DataCopy** -- BRANCH FIRST. `document --apply` rewrites source
   in other repos, YADF is git and DataCopy is hg, and DataCopy shipped to a tester.
6. **Auto-open the library DB from the manifest** -- v21 ships `--library-db` as an EXPLICIT
   flag so `index` never silently changes what it reads. Manifest-driven auto-open is the
   natural follow-up.
7. Two INBOX notes remain open and untracked under `docs/`:
   `INBOX-returns-type-baseline-destroys-malformed-blocks.md` (now SUPERSEDED -- the guard landed,
   see commit b601b41) and the two indexer-gap notes (both CLOSED by d626dd1 / 6f05695).

## Gotchas -- what will bite a cold start

* **THE SCHEMA VERSION GATE IS HARD.** A v19/v20 database returns **ZERO results** under this
  engine, with only a one-line stderr note (`index schema vNN < v21: run "drag-lint index ..."`).
  Every project DB and ~4 GB of Library indexes need one `index` pass. Until then, failures look
  like "symbol not found", not like "your database is stale". Say this in any release note.
* **`run_exe_freshness` failing means "your deploy did not happen".** A `cp` over
  `third_party/dll-win64/drag-lint.exe` SILENTLY FAILS while any drag-lint process is running --
  Windows locks the running binary. That produced three phantom battery failures once.
* **`run_encoding_guard` fails on 4 lone-LF `tools/lsp-diag/*.ps1`** from a CONCURRENT
  workstream. Not ours. A red there is not yours.
* **Never commit** `FEATURES.txt`, `docs/lint/PLAN-autodoc-and-backlog-2026-08-06.md`, or
  `third_party/dll-win32|64/dclDragLintWizard.{bpl,dcp}` -- another workstream owns them.
* **Run the pipeline in the owner's order:** reindex -> autodoc -> reindex -> lint-all
  (`C:\TEMP\claude\ordered_pipeline.sh`). Running autodoc BEFORE a reindex computes facts from a
  stale DB and was the entire cause of the 514-finding regression.
* **`query find-callers` is name-based and kind-blind** -- it takes the LEAF name, not a
  qualified one. Passing `Unit.TType.Method` returns 0 and looks like a defect.
* Battery needs `pwsh`, ~14 min, 252 runners. Runners accept `-Exe`, so a fresh build can be
  tested WITHOUT overwriting the deployed one.

## The pattern worth carrying forward

Half of these bugs are ONE shape: **a checker and a writer disagreeing.** About OPTIONS
(`<seealso>`), OWNERSHIP (`AUTO_TYPE`), SCOPE (implementation section), and PROTECTION (the
malformed fence). Whenever a rule regenerates or re-derives what another component produced, the
two must agree on all four, or the rule measures the disagreement instead of the code.

Two more, cheaply stated:

* **A receiver is not always a TYPE.** `TUnknownA.Create` is a type reference; `U.Run` is a VALUE
  whose type could not be inferred and whose NAME says nothing about the other end. Rejecting the
  second deletes callers the engine deliberately surfaces marked ` ?`.
* **Protection that depends on having nothing to say is not protection.** The malformed doc block
  survived only because the engine had no output for it; the moment `<returns>` always emitted,
  it was destroyed.

## Full diagnosis + designs

`docs/DESIGN-2026-08-10-autodoc-convergence-and-receiver-text.md`
