# Batch A — forms-csv multi-DB, AutoDoc `<returns>` enumeration, AutoDoc facts multi-DB

Design doc. Date: 2026-07-08. Author: Alexander Liberov (+ Claude Opus 4.8).

## Purpose

Three related changes, batched because two of them (items 1 and 3 below) share one
root cause: **a consumer that opens a single index DB misses relationships whose
other end lives in a different DB of the manifest set** (e.g. CLIENT project DB vs
COMMON's `uPLANLIST.PAS`). The proven remedy already exists for `query find-callers`
and `hover` — resolve `ResolveConsumerDbs` and aggregate across stores. We extend
the same idiom to forms-csv and AutoDoc, and independently reuse the hover Returns
miner inside AutoDoc.

Numbering follows the user's queue:

- **Item 1** — AutoDoc `<returns>` enumeration + `drag-lint.json` docs config.
- **Item 2** — AutoDoc facts (called-from / used-in) multi-DB awareness.
- **Item 3** — forms-csv multi-DB (root-cause fix for "reachable forms shown DEAD").

"Develop now, test later" applies to the two AutoDoc items (unit/headless tests
written; broad IDE smoke deferred). **Item 3 is fully autotestable headlessly** and
gets real automated verification in this batch — no IDE, no human tester needed.

---

## Background / root-cause evidence

### forms-csv (item 3)

The forms-csv navigation walk is correct and already resolves the polymorphic /
interface-dispatched chain (verified against the full ORM3 DB):
`frmMAIN -> ... -> frmControlPlan2 -> 'Plan' -> <plan-editor form>`. Button captions
in the chain (`RenderPath`/`THop`, `FormsMap.pas:1043-1054`) and the interface hop
("resolves for free" because the caller query matches bare `name_text` with no
receiver-type filter, `FormsMap.pas:560-564`) are present, spec-compliant, and
asserted by `run_formsmap.ps1`. **Nothing was lost or reverted.**

The only real failure is DB scope. The single-DB assumption is baked in at three
layers:

| Layer  | Location                         | Today |
|--------|----------------------------------|-------|
| IDE    | `DragLint.Plugin.Editor.pas:2298` | passes `GetActiveProjectDb` — one per-project `.sqlite` |
| CLI    | `DRagLint.CLI.pas:9675` (`DoFormsCsv`) | uses only `AArgs.DbPaths[0]` |
| Engine | `DRagLint.FormsMap.pas` (`GenerateFormsCsv`) | opens ONE store; all caller/landing queries run against it |

When the active project is the CLIENT, `EditForm` (defined in
`COMMON\OBJECTS\uPLANLIST.PAS`) is not in the DB, so the plan-editor forms resolve to
nothing and print `(no path from MAIN)` / "DEAD FORM" in the deployed CSV. The v4
"Layer 0" detection only writes a **stderr note the CSV consumer never sees**
(`FormsMap.pas:1281-1321`).

Decision: do **not** add a hedge cell ("callers may be in another index"). The tool
must either produce the real chain (by seeing all DBs) or declare DEAD FORM
definitively. So the fix feeds forms-csv the full manifest DB set.

### AutoDoc (items 1 & 2)

- Returns are emitted by `TDocRegions.MergeComment` as a bare
  `<returns>TODO: describe.</returns>` (fresh: `Regions.pas:168-169`; existing:
  `Regions.pas:229-233`). `MergeComment`'s only return input is a boolean
  `AHasReturn`. Body lines ARE already read upstream in `TDocFactsBuilder.Build`
  for Calls/Raises (`Facts.pas:456-513`).
- Called-from / Calls / Used-in facts come from direct in-process `ISymbolStore`
  queries in `TDocFactsBuilder.Build` — NOT a CLI shell-out. So the JSON-parse /
  merged-stderr bug class fixed in hover **cannot occur here**. The real (different)
  gap is single-store: `Build` takes one `ISymbolStore`, so callers in other DBs are
  invisible — the same scope problem as forms-csv.

---

## Item 1 — AutoDoc `<returns>` enumeration + docs config

### Goal

Generated `<returns>` docs enumerate the routine's actual return cases (mined
`Result := <rhs>` / value-form `Exit(<rhs>)`) instead of a bare placeholder, capped
at a configurable count (default 20), so a human editing the doc starts from the real
values rather than nothing.

### Mining

- Reuse `DRagLint.Hover.Returns.MineReturnExpressions(ABodyLines): TArray<string>`
  (pure, already shared, dedupes in first-seen order). No new I/O — `Build` already
  reads the body lines for Calls/Raises (`Facts.pas:456-513`); reuse the same lines.
- Add field `ReturnCases: TArray<string>` to `TDocFacts`. Populated only for routines
  with a return type (functions); empty for procedures.
- Apply the cap in `Build`: take the first N distinct cases, N =
  `Manifest.Docs.MaxReturnCases` (default 20).

### Emission

- Thread `ReturnCases` through `TDocumenter.BuildFor` → `TDocRegions.MergeComment`.
- Format (single, human-editable line; preserves the `TODO: describe.` marker so
  AutoDoc's own stub-detection and drift checks keep working):

  ```
  /// <returns>TODO: describe. Observed: False; rlines &lt;> 0.</returns>
  ```

  - Cases are joined with `; `. XML-escape `<`, `>`, `&` in each case.
  - Miner finds nothing, or routine is a procedure → unchanged
    `<returns>TODO: describe.</returns>`. Zero regression.
- **Idempotency (explicit invariant + test):** re-running AutoDoc on an
  already-emitted `Observed:` line must be byte-identical. The `Observed:` suffix
  regenerates deterministically from the same body. The existing merge logic
  preserves author-edited `<returns>` text; the regenerated `Observed:` list must not
  duplicate or churn. If an author has replaced the whole `<returns>` body with real
  prose (no `TODO: describe.` marker left), we do NOT re-inject `Observed:` — author
  text wins (matches current "don't clobber author edits" behavior).

### Config — `drag-lint.json` docs section

- Add a `Docs` sub-record to `TIndexManifest` (`DRagLint.Index.Manifest.pas`):

  ```pascal
  TDocSettings = record
    MaxReturnCases: Integer;   // default 20
    class function Defaults: TDocSettings; static;
  end;
  ```

- Wire through the existing manifest plumbing exactly as `TIndexSettings` is:
  `Defaults` / `ParseTextEx` (parse `"docs"` object) / `ToJson` (emit `"docs"`) /
  `Validate` (reject `max_return_cases < 0`). Round-trips via `Save`.
- JSON shape:

  ```json
  { "settings": { }, "docs": { "max_return_cases": 20 }, "indexes": { } }
  ```

- `Build` reads `AManifest.Docs.MaxReturnCases`. No manifest / no `docs` section →
  const default 20. Hover's own cap stays 10, independent.

### Units touched (item 1)

`DRagLint.Doc.Facts.pas` (mine + field + cap), `DRagLint.Doc.Document.pas` (thread),
`DRagLint.Doc.Regions.pas` (emit), `DRagLint.Index.Manifest.pas` (docs config),
`DRagLint.CLI.pas` (pass manifest docs config into the doc build path).

---

## Item 2 — AutoDoc facts multi-DB awareness

### Goal

AutoDoc's caller-facing facts see across the manifest DB set, so callers / used-in
whose call site lives in another DB (e.g. COMMON) are not invisible.

### Scope — only the cross-DB queries

- `TDocFactsBuilder.Build` gains an optional
  `AExtraStores: TArray<ISymbolStore>` parameter. Empty = today's exact single-store
  behavior (fully backward-compatible).
- Only these three **caller-facing** queries also consult the extra stores and merge:
  - `FindResolvedCallers` (`Facts.pas:396`)
  - `FindUnresolvedNameCallers` (`Facts.pas:404`)
  - `FindCallersByName` — used-in (`Facts.pas:526`)
- Everything else stays on the **primary store** (owns the documented symbol):
  symbol resolution, body-scan, and calls-*out* (`GetCallEdgesFromSymbol`) are
  intra-unit — a symbol's own body and outgoing calls live where the symbol is
  defined. No fan-out for those.
- Dedupe key across stores: `(file, line, enclosing symbol)` so a caller surfaced by
  two overlapping DBs is listed once.

### Wiring

- The `document` CLI verbs resolve `ResolveConsumerDbs(AArgs)`, open the primary store
  (owns the documented symbol) + the rest as extra stores, and pass them to `Build`.
  Mirrors `find-callers` (`CLI.pas:2201-2247`) and the item-3 forms-csv change.

### Alternatives ruled out

- `TMergedStore` decorator implementing `ISymbolStore` over N stores — cleaner
  abstraction but every method must merge; far bigger surface for a 3-query need.
- Leave single-store — the gap the user chose to close.

### Units touched (item 2)

`DRagLint.Doc.Facts.pas` (extra-stores param + merge on the 3 queries),
`DRagLint.Doc.Document.pas` / `DRagLint.Doc.Batch.pas` (thread the param),
`DRagLint.CLI.pas` (resolve + open + pass the store list).

---

## Item 3 — forms-csv multi-DB (root-cause fix)

### Goal

forms-csv resolves and queries the full manifest DB set, so a form reachable via a
launch-body in another DB (COMMON) produces its real navigation chain; only forms
unreachable across **all** indexes are declared DEAD FORM.

### Engine

- `GenerateFormsCsv(const ADbPaths: TArray<string>; const AProject, ARoot: string)` —
  contract: **`ADbPaths[0]` is authoritative** for which forms to enumerate and for
  the "PAS lines" / unit facts (the project scope); `ADbPaths[1..]` are additional
  **caller search scope** only. The caller/landing-resolution queries
  (`FindNearestFormCaller`, `FindFormViaHook`) run against **all** stores and merge.
  Passing a single DB reproduces today's output exactly.
- A form with no caller/landing in ANY store → still DEAD FORM (definitive).
- Keep `FORMS_CSV_ALGORITHM` provenance footer; no bump required (output semantics
  unchanged for single-DB callers — passing one DB reproduces today's output).

### CLI

- `DoFormsCsv` passes all of `AArgs.DbPaths` (already parsed from repeated `--db`)
  instead of `[0]`. If none given, resolve via `ResolveConsumerDbs(AArgs)`.

### IDE menu

- `InvokeGenerateFormsCsv` emits repeated `--db` from
  `ResolveActiveIndexDbs(LoadSettings)` (the same call the hover fix used) instead of a
  single `GetActiveProjectDb`. The first `--db` remains the active project DB (so form
  enumeration / "PAS lines" stay project-scoped); the rest (SQL, COMMON/library, etc.)
  are search scope for callers.

### Exe-version guard

- The CSV footer already carries `FORMS_CSV_ALGORITHM`. On the IDE path, before opening
  the produced CSV, compare the running exe's algorithm constant against the footer of
  the file just generated; if they differ (stale exe produced an old-format file), warn
  in the plugin log + a `ShowMessage`. This rules out the stale-exe hypothesis for any
  future "deployed CSV looks wrong" report. (Cheap: both values are already in hand.)

### Units touched (item 3)

`DRagLint.FormsMap.pas` (engine takes a DB list; caller/landing queries fan out +
merge), `DRagLint.CLI.pas` (`DoFormsCsv` passes the list / resolves),
`DragLint.Plugin.Editor.pas` (`InvokeGenerateFormsCsv` emits the multi-`--db` command
+ exe-version guard).

---

## Testing (all headless / automated)

### Item 3 — new multi-DB forms fixture (the regression, locked down)

- Fixture: two DBs — a "CLIENT" DB that indexes the form + the launching form but NOT
  the launch-body unit, and a "COMMON" DB that indexes the launch-body
  (`<obj>.EditForm` calling the plan-editor form).
- Assert:
  1. forms-csv against CLIENT-only → the plan-editor form shows DEAD FORM /
     `(no path from MAIN)` (reproduces the bug).
  2. forms-csv against `[CLIENT, COMMON]` → the SAME form resolves to its real chain
     with the button caption in it (`... -> 'Plan' -> <form>`).
  3. The output file contains the `FORMS_CSV_ALGORITHM` footer / version line.
- Extend `run_formsmap.ps1` (or a sibling `run_formsmap_multidb.ps1`) following the
  existing fixture-project → generate → assert-chain pattern. `run_*.ps1` naming =
  battery membership.

### Item 1 — returns enumeration + config

- `MineReturnExpressions` reused → `<returns>` for a function with two distinct
  returns emits `Observed: <a>; <b>`; a procedure emits bare `TODO: describe.`
- Cap: a function with >N returns lists exactly N; `max_return_cases` in a fixture
  `drag-lint.json` changes N; absent config → default 20.
- Idempotency: run document twice → byte-identical output.
- XML-escaping: a return like `Result := a < b` emits `a &lt; b`.

### Item 2 — facts multi-DB

- Document a symbol whose callers live in a SECOND DB → generated called-from /
  used-in facts include them; with no extra stores → unchanged single-store output.
- Dedupe: a caller present in two overlapping DBs is listed once.

---

## Out of scope (explicitly)

- No `TMergedStore` abstraction.
- No forms-csv algorithm change (interface-dispatch resolution already works).
- No CSV hedge cell for scope-severed forms.
- No IDE live-smoke in this batch beyond the exe-version guard (headless tests cover
  behavior); broad IDE smoke is a later verification pass.
- The future "D5 indexer" precision hardening (real interface-impl edges via
  `type_ancestors` / receiver-type) stays deferred.

## Order of implementation

1. **Item 3** first — highest user value, fully testable, and it establishes the
   multi-DB fan-out pattern in forms-csv that item 2 mirrors.
2. **Item 2** — reuses the same `ResolveConsumerDbs` + multi-store aggregation.
3. **Item 1** — independent (miner reuse + manifest docs config); can proceed in
   parallel but sequenced last to keep the manifest change isolated.
