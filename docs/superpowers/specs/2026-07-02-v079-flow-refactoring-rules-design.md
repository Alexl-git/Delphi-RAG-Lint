# Design: v0.79 -- M2-flow rules + Fowler refactoring-catalog pure-AST batch

> Authored 2026-07-02 (autonomous, after v0.78 shipped). Design decisions made by the controller
> per the user's explicit directive to build these rules; no interactive brainstorm (user away).
> Scout map of the flow engine: see the FlowChecks scout in this session. Ships as **v0.79**.

## Scope

Two groups plus a cleanup (cleanup dispatched separately as Task A):

**Group B -- Fowler refactoring-catalog pure-AST rules** (new category `refactoring`; register it in
`tests/rules-catalog/RuleCatalogTests.dpr` `CanonicalBuckets`). Each: implement the detection in the
existing per-file AST checkers, FP-sanity over `src/`, ship **ON** if clean else **OFF-by-default**
(opt-in), configurable threshold where noted. Add-a-rule pattern (v0.7x-verified): branch in
`DeadCodeChecks.Visit` (`EmitAt`) or a `CheckXxx` in `AstChecks`; CLI allow-list + help + DoLint dispatch
(DoLintAll auto-covers DeadCodeChecks); `B(id,'refactoring',sev,title[,enabled][,params])` in RuleCatalog;
`tests/lint/<id>.pas` + `.pas.expected` (+ `.config.json` if OFF/thresholded).

- **B1 `magic-literal`** (Replace Magic Literal). A numeric literal used in an expression that is not a
  named const. **Numbers only by default** (string literals are far too common -> a separate opt-in
  `include_strings` config later, not now). Exempt by default: `0, 1, -1, 2` and the literal inside a
  `const`/`resourcestring` declaration, an enum-value assignment, an array/set range bound, and a case
  label. Configurable extra-allow list via `"thresholds"` is not a fit (it's a set, not an int) -> read an
  allow-list from config `"magic_literal_allow": [ ... ]` (add a `TArray<Integer>`-ish config field OR keep
  the hardcoded exempt set for v0.79 and note config as a follow-up). **Ship OFF-by-default** (medium-FP),
  `hint`, opt-in via `--rule`/`"enabled"`. Verify the numeric-literal node name against the grammar with a
  throwaway fixture first (candidates: `literalNumber`, `numberLiteral`, `intLiteral`).
- **B2 `boolean-flag-parameter`** (Remove Flag Argument). A routine (`defProc`/`declProc` header) with a
  parameter whose type is `Boolean` AND that parameter identifier appears in an `if`/`case`/`while`
  condition inside the routine body (it selects behavior). Skip if the routine is an override/virtual
  (interface contract) and skip event handlers. `hint`. FP-sanity -> ON if clean else OFF.
- **B3 `message-chain`** (Hide Delegate). A member-access chain `a.b.c.d...` deeper than N hops -- count
  the depth of a left-nested `exprDot` spine in EXPRESSION context. Threshold default **4** (fires at 5+).
  Exempt: qualified unit/type names (a chain whose segments are a known unit path -- heuristic: skip when
  the base identifier is a unit name, or simply require the chain to be the entity of a value expression,
  not a `typeref`/`genericDot`). `hint`, configurable threshold. FP-sanity -> likely ON at a conservative
  threshold.
- **B4 `public-writable-field`** (Encapsulate Variable). A `skField`/`declField` under a **`public`**
  visibility section of a **class** (NOT a record, NOT `published`, NOT private/protected). `published`
  fields are DFM components (auto-generated) -> MUST be excluded (huge noise). Records legitimately expose
  fields -> excluded. `info`. FP-sanity -> ON if clean (public class fields are a genuine Delphi smell)
  else OFF.
- **B5 `loop-control-flag`** (Replace Control Flag with Break). A `while`/`repeat` whose condition
  references a Boolean local that is assigned inside the loop body (the flag-to-exit pattern) -> suggest
  `Break`. Heuristic, FP-prone -> `hint`, **OFF-by-default** unless FP-sanity is very clean. This is the
  riskiest of the batch; if it can't be made low-FP, ship OFF or defer + document.

## Group C -- M2-flow rules (extend the existing FlowChecks engine; category `data-flow`)

Engine facts (from the scout): `TFlowChecker.Check(AFile, AStore=nil, AFileId=0)` is a per-file driver;
per-`defProc` it builds a CFG (`TCfgBuilder.Build`), solves lattices with
`TDataFlowSolver<TValue>.Solve`, and emits via a local `Emit(rule,sev,msg,line,col)` closure. Lattices
live in `DRagLint.Analysis.Flow.Lattices.pas` (`TDefAsgnVal{Must,May}` definite-assignment;
`TEscape` may-open for object-leak). `TRoutineVarTable` carries per-var `TypeText`;
`DetectFreedVar(node,src,vars): Integer` detects `X.Free`/`FreeAndNil(X)`/`DisposeOf` -> var index.
`FlowChecks.IsManagedType` shows the `AStore.ResolveTypeCategory(TypeText,FileId)` + `'I'+uppercase`
fallback pattern. `TCfg.Skipped` (goto/asm) -> bail. Wiring: emit inside `Check`; add the rule id to the
`DoLint` `--rule` allow-list + help; catalog `B(id,'data-flow',sev,title)`; test with the **file harness**
(`tests/lint/`), nil-store path. Unit-test a new lattice via `tests/flowengine/FlowEngineTests.dpr`.

- **C1 `not-assigned-interface`** (#4 nullability). An **interface-typed local** dereferenced (`X.member`
  or `X as T`) on a path where it was never assigned -> nil-interface call (EAccessViolation/EInvalidCast).
  `used-before-assignment` already computes definite-assignment (Must/May) but **skips managed types**
  (interfaces included). This rule fills that gap for the interface subset:
  - Restrict to locals where `ResolveTypeCategory(V.TypeText, AFileId) = tcInterface` (store) or the
    `'I'+uppercase` naming fallback (nil store).
  - "Use" = a **dereference**: an `exprDot` whose lhs base identifier is the interface var, or an `as`
    expression on it. A plain copy `Y := X` is NOT a deref (don't flag).
  - Reuse `TDefiniteAssignment` Must/May + the per-item replay used by `used-before-assignment`. Emit
    `not-assigned-interface`: `warning` when Must-not-assigned (never assigned on any path to here),
    `info` when May (assigned on some path, not all). Out-param/`Supports(...,Y)` assignment already counts
    as a def (CollectCallArgs CallDefs) -> low FP.
  - Fixture pins: use-before-any-assign (warning), assign-then-use (absent), assign-on-one-branch-only-then-use
    (info), out-param-assigned-then-use (absent). Verify severity split.
- **C2 `double-free`** (#5). `X.Free` reachable twice on a path with **no reassignment and no nil-ing**
  between. Nuance (drives FP-correctness): a raw `X.Free` leaves `X` DANGLING (non-nil) -> a second free
  crashes; `FreeAndNil(X)` sets `X := nil` -> a subsequent `X.Free` is safe (nil.Free is a no-op) BUT
  `FreeAndNil` on an already-dangling `X` also double-frees. State machine per var:
  - New lattice `TFreedState` in `Flow.Lattices.pas`: per-var 2-state `{ Unknown, Dangling }` tracked as
    Must/May arrays (copy the `TDefAsgnVal` Must/May shape: forward, Join = Must:=and (both dangling),
    May:=or). Transfer per CFG item, using `DetectFreedVar`:
    - raw `X.Free` on var v: if v May-Dangling on entry -> emit `double-free` (`warning` if Must-Dangling,
      else `info`); then set v -> Dangling.
    - `FreeAndNil(v)`/`DisposeOf(v)`: if v May-Dangling on entry -> emit (freeing a dangling temp); then set
      v -> Unknown (nil-ed / disposed-safe).
    - assignment to v (whole-identifier LHS, incl. `v := TFoo.Create` / `v := nil` / `v := other`): set v ->
      Unknown (re-pointed).
  - `DetectFreedVar` must distinguish raw `.Free` from `FreeAndNil`/`DisposeOf` (the scout notes it handles
    all three) -- extend it or wrap it to return WHICH kind, so the transfer can pick the post-state. If it
    only returns the index, add a sibling that also returns a kind enum.
  - Guard: managed/interface types don't have `.Free` -> naturally excluded. `with` opaque items -> the CFG
    marks them Opaque; treat an opaque item conservatively (do not emit; do not change state). `TCfg.Skipped`
    -> bail. Aliasing (`Y := X; X.Free; Y.Free`) is name-based -> not caught -> fewer FPs (acceptable).
  - Fixtures: linear `X.Free; X.Free;` (warning), `X.Free; X := TFoo.Create; X.Free;` (absent -- reassigned),
    `FreeAndNil(X); X.Free;` (absent -- nil-ed), branch where only one path frees then a common free (info),
    `if Assigned(X) then X.Free;` single (absent), try/finally single free (absent).
  - **Severity/default:** `double-free` is a real crash bug -> `warning`, **ON**. `not-assigned-interface`
    -> `warning`, ON. BUT gate both on `src/` FP-sanity: if either is noisy on clean code, downgrade to
    `info` and/or OFF-by-default + document (the plan warned these are FP-sensitive; do NOT ship a noisy
    flow warning).

## Cross-cutting (Global Constraints)
- `.pas`/`.dfm`/fixtures strict 7-bit ASCII, CRLF, no BOM. DocInsight `///` on any new public type/method.
- Build Win64 via `build\build_draglint_win64.bat` (kill `drag-lint.exe` first; script prints `OK: staged`,
  success = no `[dcc] Error`/`Fatal` + fresh exe timestamp). Test exe = `third_party\dll-win64\drag-lint.exe`.
- Harnesses: `tests\lint\run_lint_tests.ps1` (file; flow + pure-AST rules), `tests\lint-store\run_store_tests.ps1`,
  `tests\rules-catalog\run_rulecatalog_tests.ps1`. All green before release.
- Every ON rule: FP-sanity over `src/` before locking severity/default. Report counts + sample findings.
- New category `refactoring` -> register in `RuleCatalogTests.dpr` `CanonicalBuckets`.

## Release
Bundle as v0.79.0-alpha (VERSION `CLI.pas:6`, CHANGELOG, pack win64+win32, tag, gh prerelease, BACKLOG +
memory + MISSING-FEATURES). If M2-flow (C) proves too FP-heavy to ship cleanly in the window, ship v0.79
with Task A + Group B and defer C to v0.80 (documented) -- do NOT rush a noisy flow rule.
