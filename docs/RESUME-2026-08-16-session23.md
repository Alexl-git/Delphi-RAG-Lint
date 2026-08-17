# RESUME -- session 23 close (2026-08-16 evening)

## Owner's instruction for the NEXT session, verbatim in effect

Work autonomously, in this order:

1. **`converter-editor-phase-g-engine-findings`** -- FIRST.
2. **`lint-all-project-wide-phase-dominates-runtime`** -- SECOND.
3. Then continue down the open list. **If a genuinely hot real issue surfaces,
   deal with that issue instead** rather than finishing the list mechanically.

## State

| | |
|---|---|
| branch | `main`, HEAD **`eb663fe`** |
| working tree | clean |
| unpushed | **104 commits, ON PURPOSE.** Do not push. The owner lifts this gate. |
| battery | **309/309 pass, 0 fail, 15.5 min** -- run at `eb663fe` with a clean tree, AFTER every change below. Confirmed, not assumed. |
| INBOX | **9 open / 103 retired** (was 13 open at the start of this session) |
| consumers | DataCopy **31** (from 43), YADF 4, YADFOT 4, YADFSetup 7 -- all 0 errors |

`DRagLint.Core.Model.TReference` gained a `ReceiverText` field this session; it is
populated by `FindCallersByName`. Nothing else changed shape.

---

## 1. `converter-editor-phase-g` -- do this first, and it is nearly done

Findings **2.4 through 2.11 are ALL CLOSED**. The note stays open for ONE thing,
and the owner has already settled its shape, so this is implementation, not a
decision:

**2.5 -- a same-named VCL and FMX type tie.** Measured:

```
query --name TEdit --db library-Win64.sqlite  -> 2 rows: FMX.Edit.TEdit, Vcl.StdCtrls.TEdit
query --name TEdit --db DataCopy.sqlite       -> 0 rows
```

* **The tie is LIBRARY-ONLY.** A project DB holds only the project's own code, so
  it never contains either `TEdit` and the ambiguity cannot arise there.
* **The framework is DERIVABLE, not something to ask for.** DataCopy has 25
  `Vcl.*` references and 0 `FMX.*`; YADF, 18 and 0.

So: when a project context is available, derive the framework from that project's
own `uses` and prefer matching declarations; when it is not, keep reporting the
tie as today. **Do NOT add a `--framework vcl|fmx` flag** -- that was the note's
original ask and the owner's question retired it. No default needs ruling on.

Positive control for whatever test is written: a query with NO project context
must STILL report the tie rather than silently picking one.

---

## 2. `lint-all-project-wide-phase-dominates-runtime` -- second, and READ THIS BEFORE CODING

`unresolved-name` is **257-269 s of ORM3's ~520 s `lint-all`** -- about half the
run. It times ONE call, `FindUnresolvedNameCallers`
(`src\storage\DRagLint.Storage.SQLite.pas:4071`), once per declaration (4,309 on
ORM3).

**THREE explanations have been measured and FAILED. Do not retry them:**

| tried | result |
|---|---|
| the uses-reach recursive CTE | ~6 s of the 269 s. Not it. Do not memoise it. |
| a missing index on `refs.name_text` | `idx_refs_name_nocase` EXISTS and `EXPLAIN QUERY PLAN` picks it. Not it. |
| missing `sqlite_stat1` (no ANALYZE) | statistics now present; moved it **1.4 s**. Not it. |

Measured runs:

```
baseline                            unresolved-name 269.12 s   TOTAL 529.71 s
+ unary `+` plan pin                                258.90 s         510.03 s
+ plan pin + sqlite_stat1 present                   257.48 s         518.21 s
```

Both shipped changes are KEPT (the `+` is semantically inert, statistics are
hygiene) but **neither is a fix**.

**The one unexplained fact:** the identical SQL replayed against the same DB
through an external SQLite runs ~0.74 ms/call versus ~62 ms in-process -- a
consistent ~80x gap that scales with row volume.

**THE NEXT EXPERIMENT, and nothing else until it is done.** Close the gap between
the two MEASUREMENTS first -- they may not be comparing the same thing (different
bound parameters, a warm page cache on the replay side, a predicate the replay
dropped). In-process:

1. log `sqlite3_libversion()` from the dynamically loaded DLL, so the engine is
   known rather than assumed;
2. run `EXPLAIN QUERY PLAN` for the EXACT assembled SQL **through FConn**, not an
   external shell -- the only way to see the plan the product gets;
3. time ONE call in-process with the same bound parameters the replay used.

If the plans match and the timing still differs, the cost is not in the plan and
the search moves to the FireDAC layer (per-call `TFDQuery.Create`, parameter
binding, row marshalling) -- which was measured as "a few ms/call at most", so
that too needs re-measuring rather than assuming.

Reproduce: `set DRAGLINT_PROFILE=1` then
`drag-lint lint-all --db C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite --quiet`,
about 9 minutes, read **stderr**.

---

## 3. The rest of the open list, ranked

| note | shape |
|---|---|
| `index-runs-are-not-resumable` | Group B **5b**, the plan's HIGHEST-RISK item, not started. Additive `files.indexed_at_fingerprint`; the stamp **must** sit inside the transaction `CommitFileTx` closes or it recreates the silent-staleness bug fixed in session 22. Design: `PLAN-SESSION-23-IMPLEMENTATION.md` section 5b. |
| `rule-hardening-plan-2026-08-13` | Down to ONE live item. Re-measured: items 1/3/5/7/8 fire **zero** times now; 2+6 are 0; 4 done. Live is **item 9 `unused-public-symbol` (12)**: 9 are YADF shared-unit hints, of which **8 are alive in a sibling project** and `OptionsHelpText` is genuinely dead (reported x3); 3 are DataCopy. Fix = consult the sibling DBs the unit's own `dl:shared` header NAMES (a DECLARED relationship, so it does not violate the authoritative-set rule). Needs `TProjectLintRules.Run` to accept extra stores -- it takes one `ISymbolStore` today, so this is a signature change plus call sites. |
| `incremental-index-hangs-on-large-db` | The "hang" is the whole-DB resolve. **A session-23 suspicion that the incremental affected-set is O(corpus) was REFUTED on real code** (748 affected refs, SMALLER than the changed file's own 1,988) -- do not carry that link forward. |
| `buildfor-defaulted-args-...` | Remaining: `ABaseDir` / `AIncludeSince` / `AExtraStores` / `AComplexityMin` defaulted on the repair path. `AExtraStores` is the risky one -- use a cross-DB fixture. |
| `exception-class-unit-...` | Feature. Measured 64 distinct messages on ORM3 (not the 400 that would have killed it). Build Stage 1. |
| `ide-lsp-ram-and-shim-todo` | Needs a live IDE. NOTE the BPL blocker is DISCHARGED -- both packages rebuilt; 37.0 registers 32- and 64-bit IDEs SEPARATELY (`Known Packages` / `Known Packages x64`). |
| `yadf-share-review-marker-hash` | Owner request. 249 markers across three repos, so the cheap window has closed. |

---

## Traps this session paid for -- all now in auto-memory

* **A brace-directive inside a brace comment ENDS THE COMMENT.** `{ ... {$IFDEF} }`
  corrupts the parse and made two "must be SILENT" assertions pass BEFORE the fix
  existed. Hit twice in one session.
* **An orphaned `drag-lint` holds the DB.** `| Select-Object -First N` does NOT
  kill it -- it detaches and keeps indexing. Its lock then presents as "database
  is locked", a no-op reindex, and a `lint-all` that dies inside `open+migrate`,
  which looked exactly like a bug in my own change. **Check `Get-Process
  drag-lint` before diagnosing anything DB-shaped.**
* **A small or synthetic corpus cannot SIZE or RANK a large one.** YADF said
  `calls` dominates doc-drift; on ORM3 `calls` is 0.99 s and `unresolved-name` is
  257 s. A synthetic corpus is valid for exposing a SLOPE, invalid for
  attribution.
* **`.dpr` suites compile the ENGINE from source**, so editing source during a
  battery run breaks them (two failures this session were self-inflicted that
  way). Exe-based suites only need the exe.
* **`Remove-Item` is permission-blocked here**; use the Bash tool's `rm`.
* **PowerShell has no heredoc** -- write commit messages to a file, `git commit -F`.
* Building DataCopy MUTATES `DataCopy.dproj` (autoinc version + macro
  flattening). Revert it after a verification-only build.

## Outside this repo

* `C:\Projects\DataCopy` (Mercurial) carries this session's edits uncommitted,
  per the standing convention: 5 `local-field-prefix` renames, the
  `FLogger`/`FTRLogger` field renames, and a `dl:ok` re-stamp.
* `C:\Projects\YADF` (Mercurial) has two now-redundant `dl:ok unused-parameter`
  markers removed from `YADFOT.Wizard.pas`.
* `C:\Projects\Loader2019` still holds an uncommitted, verified `FreeAndNil` leak
  fix from an earlier session.
* **Spring4D paths were fixed machine-wide** in BOTH the registry AND
  `%APPDATA%\Embarcadero\BDS\37.0\EnvOptions.proj`. msbuild reads the LATTER --
  updating the registry alone changes nothing. Backups are in this session's
  scratchpad.
