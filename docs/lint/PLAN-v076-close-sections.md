# Plan: close MISSING-FEATURES #4/#5/#6 (+#9/#10/#11) -> v0.76+

> Authored 2026-07-01 as the handoff plan after v0.75.0-alpha shipped (`main`=`e31a595`).
> Goal (user): "close completely #4, #5, #6, + if not too big also #9, #10, #11, release as 0.76."
> This doc is the executable plan for the next (fresh-context) session. Read `docs/lint/BACKLOG.md`
> top first, then this.

## Honest scope up front (READ THIS)

"Close COMPLETELY #4/#5/#6" is a **multi-release** effort, not one v0.76. The pure-AST fruit is
already picked (v0.71-v0.75). **Every remaining item in #4/#5/#6 needs either the M1 symbol store,
the uses/type graph, or the M2 flow engine** -- and the file-only `lint <file>` harness CANNOT test
store/flow rules. So the real blocker is **infrastructure: a `check-ast --db` fixture harness**
(Phase 0). Without it, store rules ship untested (unacceptable given this project's quality bar).

Realistic release mapping:
- **v0.76** = Phase 0 (store test harness) + Phase 1 (the last pure-AST rules) + Phase 2 (the
  cheap store/graph rules: abstract-method-instantiation, nativeint-truncation, circular-uses,
  DIT/CBO). This closes #9, #10, #11 and MOST of #5, and dents #4/#6.
- **v0.77** = Phase 3 (the big ones: clone detection, CK suite RFC/LCOM/NOC, nullability [M2],
  double-free [M2]). This is what "completely closes" #4 and #6.

If the user insists on a single v0.76, ship Phase 0+1+2 as v0.76 and clearly document #4/#6's
flow/clone items as the remaining tail. Do NOT rush nullability/double-free/clone under time pressure
-- they are correctness-critical and FP-sensitive.

---

## Remaining OPEN items (verified against MISSING-FEATURES.md at v0.75)

| # | Item | Approach | Phase | Closes? |
|---|------|----------|-------|---------|
| #10 | `dfm-hardcoded-credential` | DFM AST scan (Password/Pwd props w/ literal string) | 1 (pure-AST) | closes #10 |
| #10 | `insecure-temp-file` | heuristic: GetTempPath/GetTempFileName + write, or hardcoded temp path | 1 | closes #10 |
| #10 | `unvalidated-deserialization` | fuzzy; likely DEFER + document (no clean signal) | - | note |
| #2  | `multiple-statements-per-line` | lexical/AST: 2+ statements sharing a source line | 1 (bonus) | closes #2 |
| #9  | `variant-record-type-punning` | AST: record with a `case` variant part read via a different field -- HARD pure-AST; assess, likely DEFER | 1/def | - |
| #9  | `nativeint-truncation` | store-exact: 32-bit cast of a NativeInt/pointer-sized value (like win64-pointer-cast but M1-typed) | 2 (store) | closes #9 (with above) |
| #9  | `default-encoding-io` | store: TFileStream/TStringList IO without explicit encoding -- M1; assess | 3 | - |
| #5  | `abstract-method-instantiation` | store: `TFoo.Create` where TFoo has an abstract method (store knows abstract) | 2 (store) | closes #5 (mostly) |
| #5  | `double-free` | M2 flow: X.Free reachable twice with no reassignment between | 3 (flow) | closes #5 |
| #5  | stream/file/bitmap created-not-freed | LIKELY ALREADY COVERED by `object-leak` (M2, shipped v0.66) -- verify; if so, mark done | 2 (verify) | closes #5 |
| #11 | `circular-uses` report | store uses-graph: DFS over GetUnitUsesForFile for unit cycles (distinct from interface-reference-cycle) | 2 (store) | closes #11 |
| #11 | DIT / CBO depth metrics | store class-hierarchy graph (GetTransitiveAncestors) | 2 (store) | closes #11 (with above) |
| #6  | CK suite: NOC/RFC/LCOM (DIT/CBO via #11) | store class graph -- LCOM/RFC are non-trivial | 3 | closes #6 (partial) |
| #6  | clone / duplicate-code detection | token-hash pass over routine bodies (rolling hash of normalized token windows) -- BIG standalone | 3 | closes #6 |
| #4  | `nullability` / not-assigned-interface | M2 flow + types: interface var used (method call) before assignment | 3 (flow) | closes #4 |
| #4  | interface/object mixing | store type analysis; assess -- may fold into nullability | 3 | closes #4 |

---

## Phase 0 -- the `check-ast --db` fixture harness (DO FIRST; unblocks all store rules)

**Problem:** `tests/lint/run_lint_tests.ps1` runs `lint <file>` with NO `--db`, so store-backed
findings never fire. Store rules (abstract-method, nativeint, circular-uses, DIT/CBO, nullability,
double-free, CK) need a store.

**Design (recommended):** a sibling harness `tests/lint-store/run_store_tests.ps1` + a
`tests/lint-store/<case>/` layout:
- Each `<case>/` holds one or more `.pas` files (the enum/class/uses spread across units) + a
  `expected.txt` (same directive format: `<rule> <file>:<line>` present / `!<rule> ...` absent).
- The harness: for each case dir, `drag-lint index <case> --db <tmp>.sqlite` then
  `drag-lint lint-all --db <tmp> --output <report>` (lint-all runs the store path -- CheckTypeAware
  with store, FlowChecks, ProjectRules), parse the report, compare to expected. Clean up the tmp DB.
- `lint-all` already runs every store-backed check unconditionally, so any store rule auto-covers
  once wired into DoLintAll. `check-ast --db <file>` is the single-file store path if per-file is
  preferred.
- Verified this session: `drag-lint index <dir> --db <db>` (Files/Symbols/Refs) then
  `lint-all --db <db> --output <f>` works and the store resolves enums (skEnum->FindAllChildSymbols).
  CAVEAT: full `lint-all` on a large index (ORM3, 747 files) takes >5 min -- keep fixture cases tiny.

**Deliverable:** the harness script + 1-2 smoke cases + a line in the release checklist. Then every
Phase-2/3 store rule gets a `tests/lint-store/<rule>/` case instead of a `tests/lint/` fixture.

---

## Phase 1 -- last pure-AST rules (v0.76, fast, use the existing file harness)

Follow the **v0.75-verified add-a-rule pattern**: branch in `DeadCodeChecks.Visit` (or a Check* in
AstChecks) -> `EmitAt`/manual finding; CLI edits (allow-list ~4753, help ~4761, DoLint dispatch,
DoLintAll auto-covers for DeadCodeChecks); `B()` in RuleCatalog; `tests/lint/<id>.pas`+`.expected`
(+`.config.json` if OFF-by-default or thresholded); normalize CRLF+ASCII; build
`build\build_draglint_win64.bat`; `run_lint_tests.ps1`; FP-sanity over `src/`.

1. **`dfm-hardcoded-credential`** (security, warning) -- scan `.dfm` files. The DFM tree-sitter path
   exists (`DRagLint.Parser.DFM.pas` uses node type `property` with `WalkProperty`; there are
   `tests/lint/*.dfm` fixtures + the harness already lints `.dfm`). Flag a DFM `property` whose name
   matches password/pwd/secret/apikey AND whose value is a non-empty string literal. Add a
   `CheckDfmCredentials(AFile)` (new; the DFM checks live where `dfm-broken`/`global-form-variable.dfm`
   are handled). Fixture: a `.dfm` with `Password = 'hunter2'`. Low-FP.
2. **`insecure-temp-file`** (security, warning) -- heuristic: a call to `GetTempPath`/`GetTempFileName`
   whose result feeds a `TFileStream.Create`/`WriteAllText` for a sensitive file, OR a hardcoded
   `\Temp\`/`C:\Temp` path in a file API. Start conservative (hardcoded temp path in a file-write API
   call). Pure-AST heuristic; ship warning, maybe OFF-by-default if noisy. FP-sanity first.
3. **`multiple-statements-per-line`** (#2 loose end, hint) -- 2+ `statement`/`assignment` nodes whose
   StartPoint.Row is the same line (excluding `begin`/single-line `if..then X`). Pure-AST/lexical.
   Ship hint; likely OFF-by-default (pure style). Closes the last #2 item.
4. **`variant-record-type-punning`** (#9) -- ASSESS. A `case` variant part in a record read via a
   different field than written needs flow -> likely DEFER + document (no clean pure-AST signal).

## Phase 2 -- cheap store/graph rules (v0.76, need Phase 0 harness)

Wire into the store-bearing path (`CheckTypeAware(Store,...)` / a new store Check in DoLintAll ~5718+;
these run in `lint-all` with the store). Test via `tests/lint-store/`.

5. **`abstract-method-instantiation`** (#5, warning) -- `TFoo.Create` where the store says TFoo (or
   an ancestor) declares an `abstract` method that TFoo doesn't override. Store API: FindSymbolsByExactName
   -> skClass; check its methods for the abstract directive (procAttribute kAbstract) via
   FindAllChildSymbols + GetTransitiveAncestors. MEDIUM. Closes most of #5.
6. **`nativeint-truncation`** (#9, warning) -- like `win64-pointer-cast` (already in CheckTypeAware)
   but store-exact: a 32-bit cast (Integer/Cardinal/LongInt/LongWord) of a value whose store type is
   NativeInt/NativeUInt/pointer-sized. Extend CheckTypeAware's win64 block to use CatOf/store when
   present. Closes #9 (with variant-record deferred).
7. **`circular-uses`** report (#11, info/warning) -- a project-wide check (like interface-reference-cycle)
   but over the UNIT uses-graph: DFS/Tarjan over `GetUnitUsesForFile` for each file id; report each
   unit cycle once. Lives in `ProjectRules` (runs in DoLintAll after the file loop). Closes #11 (part).
8. **DIT / CBO metrics** (#11/#6, info) -- DIT = depth of `GetTransitiveAncestors`; CBO = count of
   distinct classes a class references. Store class-hierarchy graph. Parameterized thresholds. Closes
   #11 + dents #6.
9. **Verify** stream/file/bitmap-not-freed is subsumed by `object-leak` (M2) -- if yes, mark #5 item
   done in the doc; if there is a real gap (e.g. TFileStream specifically), add a targeted store check.

## Phase 3 -- the big ones (v0.77; do NOT rush into v0.76)

10. **clone / duplicate-code detection** (#6) -- biggest single item. Rolling-hash (e.g. Rabin-Karp)
    over normalized token windows of routine bodies; report pairs of routines with a long identical
    token run above a threshold. New engine-ish module; its own design doc. Closes #6 (with CK).
11. **CK suite RFC/LCOM/NOC** (#6) -- NOC = child count (store); RFC = methods + distinct called
    methods; LCOM = method-field cohesion (non-trivial). Store class graph. Closes #6.
12. **`nullability` / not-assigned-interface** (#4) -- M2 flow: an interface-typed local used (method
    call / `as`) on a path where it was never assigned. Extends the FlowChecks def-use lattice to
    interface refs. Correctness-critical + FP-sensitive -> careful. Closes #4.
13. **`double-free`** (#5) -- M2 flow: `X.Free`/`FreeAndNil(X)` reachable twice with no reassignment
    between. Extends FlowChecks. Closes #5 fully.
14. **interface/object mixing** (#4), **default-encoding-io** (#9), **unvalidated-deserialization**
    (#10) -- assess; fold in or document as won't-fix if no clean signal.

---

## Release recipe (unchanged, v0.75-verified)

1. Implement + wire + fixtures; build Win64 (`build\build_draglint_win64.bat` via PowerShell
   `Start-Process -Wait`; **kill `drag-lint.exe` first** or the copy silently keeps a stale exe).
2. `run_lint_tests.ps1` (file harness) + `run_store_tests.ps1` (Phase 0) + `run_rulecatalog_tests.ps1`
   all green; FP-sanity over `src/` for each new ON rule.
3. Bump `VERSION` (`src/cli/DRagLint.CLI.pas:6`); CHANGELOG "Unreleased" -> `## v0.76.0-alpha`;
   mark items `[x]` in MISSING-FEATURES + refresh "where we stand".
4. `build\pack-lint-release.ps1 -Version 0.76.0-alpha` (builds Win64+Win32); verify BOTH exes report
   0.76 (`--version`) -- test the canonical `third_party\dll-win64\drag-lint.exe` (has DLLs), NOT the
   bare `src\cli\Win64\Release\` one (missing tree-sitter DLLs -> silent no output).
5. `git tag v0.76.0-alpha`; `git push origin main`; `git push origin v0.76.0-alpha`;
   `gh release create v0.76.0-alpha <win64.zip> <win32.zip> --prerelease --title ... --notes ...`.
6. Update BACKLOG + memory + wiki.

## Gotchas carried from this session (will bite a cold start)

- **Use the drag-lint SELF-INDEX, not Grep**, for Delphi symbol lookups: `Delphi-RAG-lint.sqlite`
  (outDir `C:\Projects\.drag-lint\`); `drag-lint query --name X --db <db>` / `context --task "modify X"`.
  Self-index is dated ~Jun 29 -> MISSES today's new symbols; reindex incrementally when querying
  just-changed code. Log substitutions to `stats/draglint-usage.log`.
- A `case` node's NAMED children INCLUDE the keyword tokens (`kCase`/`kOf`/`kElse`/`kEnd`) -- so
  `NamedChild(0)` is `kCase`, not the selector. Pick the first named child not `caseCase`/`statement`
  and not `k`-prefixed. `else` = presence of a `kElse` child.
- A paren-less `TFoo.Create` is an `exprDot` (NOT `exprCall`); with parens it's `exprCall(entity=exprDot)`.
- Calling `.NodeType` on a NULL `TTSNode` **access-violates in tree-sitter.DLL** -- always guard with
  `.IsNull` first (short-circuit `and`).
- `assignment` node fields: `lhs:` / `operator:` (`kAssign`) / `rhs:`. `defProc` has `header` + `body`
  fields; a defProc's `header` IS a `declProc` (so guard destructor-style rules by name-kind:
  identifier=decl vs genericDot=impl).
- Enum store path: `FindSymbolsByExactName('TEnum')` -> pick `skEnum` -> `FindAllChildSymbols(id)` ->
  `skEnumValue` children. `declType`>`declEnum`>`declEnumValue` (name field) for the same-file map.
- Metric thresholds: cognitive scores HIGHER than cyclomatic (nesting multiplier) -> its default is 25
  not 15 (216 findings@15 vs cyclomatic 115@15 on `src/`). Calibrate any new metric's default against
  `src/` noise before shipping ON.
- Catalog tests are RELATIVE (naming=9, total self-checked) -> no count bump needed when adding rules.
- OFF-by-default pattern: add id to `DefDisabled` in DoLint + the DoLintAll `FinalizeAndOutput` list +
  catalog `B(..,False)`; test via a `<base>.config.json` `"enabled":[id]` sidecar.
