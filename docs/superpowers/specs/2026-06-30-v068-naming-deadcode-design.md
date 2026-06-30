# v0.68 -- Naming (#1), Dead-code tail (#2), referenced-never-set (#3) -- design

> Status: approved 2026-06-30 (brainstorming). Closes MISSING-FEATURES sections **#1
> (naming, ~0% today -> the biggest cheap breadth gap)**, the unstarted **#2
> (dead/redundant code)** items, and **finishes #3 (data-flow)** via the last open
> item `referenced-never-set`. Decomposes into a `writing-plans` implementation plan.
> 12 new rules. Workflow: design -> plan -> handoff/clear -> (fresh session) implement
> -> publish v0.68.

---

## 1. Goal

Add the highest coverage-per-effort breadth left after M1/M2/#12: a configurable
**naming-convention** rule family, the achievable **dead/redundant-code** rules, and
the final **data-flow** item. All near-zero-FP, enabled by default, consistent with
the v0.66 config system.

**12 new rules:** 7 naming + 4 dead-code + 1 referenced-never-set.

## 2. Architecture

Three delivery vehicles, chosen per rule's information needs:

- **Naming (#1) -> config-driven built-ins.** Naming rules must read *configurable*
  conventions (prefixes / casing) from `drag-lint-lint.json`, so they cannot be static
  `.scm` queries (which can't read config). New unit **`DRagLint.Diagnostics.NamingChecks`**
  (`TNamingChecker.Check(const AFile: string; const ANaming: TNamingConfig; const AStore: ISymbolStore = nil; AFileId: Int64 = 0)`),
  pure AST. Runs on `lint <file>` with `AStore = nil` (naming is syntactic); `check-ast --db`
  / `lint-all --db` pass the store so the single exception-class sub-check (E-prefix) can resolve
  `Exception` ancestry via M1 -- the same store-optional pattern as `CheckTypeAware`.
- **Dead-code (#2) -> split.** The AST-only rules (`unused-parameter`, `identical-then-else`)
  + the data-flow rule (#3) go in a new unit **`DRagLint.Diagnostics.DeadCodeChecks`**
  (`TDeadCodeChecker.Check(const AFile: string)`), `lint <file>` path. The index-backed
  rules (`unused-private-member`, `unused-unit-in-uses`) extend the existing store-backed
  **`DRagLint.Lint.ProjectRules`** (run in `lint-all --db` / project path), like
  `unused-public-symbol`/`god-class`.
- **Config -> `TLintConfig` extension.** Add a `TNamingConfig` sub-record parsed from a
  `naming` block in `drag-lint-lint.json`, with built-in defaults matching the project's
  CLAUDE.md conventions. `LoadLintConfig` (CLI) passes `Cfg.Naming` into `TNamingChecker.Check`.

**Wiring (per the established built-in pattern):** each new `lint <file>` built-in is added
to the `DoLint` `--rule` allow-list, the help string, the `DoLint` dispatch, and the
`DoLintAll` dispatch. New units register in `drag-lint.dpr` + `drag-lint.dproj`. All
findings flow through the v0.66 `FinalizeAndOutput` tail, so config severity-remap and
`disabled`/`enabled` already apply (no per-rule on/off plumbing needed -- "enabled by
default" = simply emit; a user disables via the config `disabled` list).

## 3. Config schema (new `naming` block)

```json
"naming": {
  "type_prefix": { "class": "T", "exception": "E", "interface": "I", "pointer": "P" },
  "field_prefix": "F",
  "param_prefix": "p",
  "method_case": "PascalCase",
  "const_case":  ["PascalCase", "UPPER_CASE"],
  "local_case":  "PascalCase"
}
```

- **Built-in defaults** equal the above (the project's conventions: `TMyClass`, `EMyException`,
  `IMyInterface`, `PMyType`, `FMyField`, `pMyParam`, PascalCase methods). So with **no config
  file**, the rules already match this codebase -- zero false positives, zero setup.
- **Disabling a specific check:** set its value to `""` (string checks) or `[]` (case lists).
  E.g. `"param_prefix": ""` turns off only the param-prefix check; the rest still run.
- `TNamingConfig` record fields mirror the JSON; `TLintConfig.Load` parses the `naming`
  object (absent -> all defaults). Casing values: `PascalCase` | `UPPER_CASE` | `camelCase`
  (a small enum; unknown -> ignored/default).

## 4. Section #1 -- naming rules (7, default `info`, `lint <file>`)

Each rule resolves its convention from `ANaming`; an empty/disabled convention skips that rule.

1. **`type-name-prefix`** -- a class type name must start with `type_prefix.class` (`T`); an
   interface with `type_prefix.interface` (`I`); a pointer type with `type_prefix.pointer` (`P`).
   An **exception class** (one whose ancestry reaches `Exception`) must start with
   `type_prefix.exception` (`E`) -- this single sub-check uses the **M1 resolver**
   (`IsDescendantOf`/ancestry) when a store is present; with no store, fall back to the syntactic
   `T` rule (don't guess exception-ness). Emitted as one rule id with a per-kind message.
2. **`field-name-prefix`** -- a class instance field (`declField`) name must start with
   `field_prefix` (`F`). Skip published auto-generated component fields on form/frame classes
   (the DFM `Name: TType` dump) to avoid noise.
3. **`param-name-prefix`** -- a routine parameter (`declArg`) name must start with `param_prefix`
   (`p`). Skip `Self`; skip when `param_prefix = ''`.
4. **`method-pascalcase`** -- a method/routine name must be PascalCase (per `method_case`).
5. **`const-casing`** -- a declared constant / enum member name must match one of `const_case`
   (default allows `PascalCase` or `UPPER_CASE`).
6. **`unit-name-matches-file`** -- the `unit X;` identifier must equal the file's base name
   (case-insensitive on Windows; report if different). One finding per unit.
7. **`local-var-casing`** -- a local variable name must match `local_case` (PascalCase) and must
   NOT carry the reserved `field_prefix`/`param_prefix` (a local named `FFoo`/`pFoo` is a smell).

**FP policy:** when a name's category can't be determined syntactically (e.g. exception-ness with
no store), do not guess -- skip. All are `info`.

## 5. Section #2 -- dead/redundant-code rules (4)

1. **`unused-private-member`** (store-backed, `warning`) -- a `private`/`strict private` method,
   field, const, or nested type with **zero references** in the index. Mirrors
   `unused-public-symbol` but scoped to private visibility (lower FP -- privates can't be used
   cross-unit). Guards: skip published fields; skip RTTI/`{$M+}`-streamed members; skip if any
   reference exists. Runs in the project/`lint-all --db` path.
2. **`unused-unit-in-uses`** (store-backed, `warning`) -- a unit in a `uses` clause none of whose
   exported symbols are referenced by the using unit. Guards (near-zero-FP): skip units whose only
   "use" is plausibly an operator overload, a class/record helper, or an `initialization`/`finalization`
   side effect -- i.e. only flag when we can affirmatively see zero referenced symbols AND the unit
   is not in a small allow-list of known side-effect units. Conservative: when unsure, don't report.
3. **`unused-parameter`** (AST, `warning`) -- a parameter never read in the routine body. **Guards
   (essential):** skip parameters of (a) `override` methods, (b) interface-method implementations,
   (c) event-handler signatures (e.g. a `Sender: TObject` + matching shape) and message methods
   (`message` directive), (d) routines with assembler/external bodies -- all of which must keep the
   parameter for signature compatibility. Skip `out`/`var` params (caller-visible).
4. **`identical-then-else`** (AST, `warning`) -- an `if C then S1 else S2` where `S1` and `S2` are
   syntactically identical statements (a real copy-paste bug). Compare normalized subtree text.

**Deferred (NON-GOALS, see 8):** `function-result-ignored` (FP-prone without types),
`multiple-statements-per-line` (floods this codebase's one-liner style), `commented-out-code`,
`redundant-parentheses`.

## 6. Section #3 -- referenced-never-set (1, finishes data-flow)

**`referenced-never-set`** (AST, single-unit, `warning`, `lint <file>`):

- For each class declared in the unit: collect its field declarations; scan **all** of that class's
  method bodies (across the unit) and classify each reference to a field as a **write** (assignment
  target `FX := ...`, or passed as `var`/`out` argument) or a **read** (any other use). Reuse the
  M2 assignment-target classification logic (`AssignmentBaseIndex`-style).
- **Flag** a field that has **>= 1 read and 0 writes** anywhere in the class -- it is read but never
  set, so it always holds its zero value (a latent bug).
- **Rationale for single-unit (not store-backed):** Delphi `private`/`strict private` fields are
  *unit-scoped* -- only the declaring `.pas` can access them -- so the whole-class def-use set lives
  in one file. No DB needed; runs live on `lint <file>`. (Cross-unit `protected`-field writes by a
  descendant in another unit are the only gap; excluded by the guard below, revisitable store-backed
  later.)
- **Guards (near-zero-FP):** only `private`/`strict private` fields (skip `protected`/`public` --
  potentially written from elsewhere); **skip published fields and form/frame/`TComponent`-streamed
  classes** (DFM/RTTI streaming writes them invisibly); skip a field initialized in its declaration.

## 7. Severity & enablement policy

- **Naming + casing (#1):** `info`. **Dead-code (#2) + `referenced-never-set` (#3):** `warning`.
- **All 12 enabled by default.** A user silences any via the v0.66 config `disabled` list (or
  `--disable`), or re-levels via `severity`. No new on/off mechanism required -- findings flow
  through `FinalizeAndOutput`.
- **Default behavior for the existing harness:** the new rules must not regress current fixtures.
  Because they emit new rule ids, existing `.expected` files are unaffected unless a fixture happens
  to contain a newly-flagged construct -- the plan verifies the full harness stays green and adds
  `!<rule>` guards where an existing fixture would otherwise newly fire.

## 8. Non-goals (v0.68)

- `function-result-ignored`, `multiple-statements-per-line`, `commented-out-code`,
  `redundant-parentheses` (deferred per Section 5).
- Hungarian / short-identifier flags, reserved-word (keyword) casing,
  identifiers-differing-only-by-case (subjective / cross-symbol -- deferred per Section 4).
- Cross-unit `protected`-field write resolution for `referenced-never-set` (single-unit only).
- Autofix for any naming/dead-code finding (the #12 autofix milestone owns mutation).

## 9. Testing

- **TDD fixture per rule** (positive fires + negative does not). `tests/lint/*.pas` + `.expected`
  for the `lint <file>` built-ins (naming, `unused-parameter`, `identical-then-else`,
  `referenced-never-set`). `tests/lint-project/*` DB fixtures (index + `lint-all --db` /
  `check-ast --db`) for the store-backed `unused-private-member` / `unused-unit-in-uses`, mirroring
  the existing `objleak-interproc` / `managed-class` harnesses.
- **Config fixtures:** assert a `naming` override (e.g. `param_prefix:""`) disables only that check;
  a non-default prefix changes what fires.
- **Guard fixtures:** an `override` method's unused param does NOT fire; a published form field does
  NOT fire `field-name-prefix`/`referenced-never-set`; an exception class missing `E` fires only
  with a store.
- The existing harness (currently 94/94) stays green.

## 10. Internal phasing (one milestone, staged commits)

1. **`TNamingConfig` + `naming` parsing** in `TLintConfig` + `LoadLintConfig` wiring + config unit
   test (defaults + override + disable-one).
2. **`DRagLint.Diagnostics.NamingChecks`** + the 7 naming rules + CLI wiring + fixtures (incremental:
   prefixes first, then casing, then unit-name).
3. **`DRagLint.Diagnostics.DeadCodeChecks`** -- `unused-parameter` + `identical-then-else` +
   `referenced-never-set` + guards + fixtures.
4. **`DRagLint.Lint.ProjectRules`** extension -- `unused-private-member` + `unused-unit-in-uses` +
   `tests/lint-project` DB fixtures.
5. **Docs + CHANGELOG v0.68** ("Naming + dead-code + referenced-never-set"), MISSING-FEATURES
   updates (mark #1 shipped, #2 items, #3 DONE), `rules/README` naming-config section; real-code
   sanity on ORM3.

Each stage: fixture(red) -> code -> rebuild CLI (delphi-build skill) -> deploy exe ->
harness green -> normalize CRLF/ASCII -> commit. v0.68 ships after (merge if on a branch + pack +
tag + GitHub prerelease).

## 11. Definition of done

All 12 rules live, enabled by default, config-driven where specified, each with a passing TDD
fixture (positive + guarded negative); the existing harness stays green; `drag-lint-lint.json`
gains a documented `naming` block; CHANGELOG + MISSING-FEATURES + `rules/README` updated; real-code
sanity on ORM3 shows the naming/dead-code findings are accurate (spot-checked, near-zero-FP). Then
publish **v0.68.0-alpha**.
