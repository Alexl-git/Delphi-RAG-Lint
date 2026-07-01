# drag-lint -- lint features in other packages, not (yet) here

Gap checklist vs the commercial/established Delphi & Pascal linters: **Peganza Pascal
Analyzer (PAL)** (the breadth leader, ~188 checks), **TMS FixInsight** (~60), **SonarDelphi**
(~148), and the **Delphi compiler's own** hints/warnings. Grounded in the 2026-06-29 coverage
analysis (`docs/lint/REPORT-1-delphi-lint-landscape.md`) cross-checked against the shipped
inventory (`rules/*.scm`, `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas`,
`src/lint/DRagLint.Lint.ProjectRules.pas`).

**Where we stand (updated v0.74.0-alpha):** ~132 rules, roughly **77-81%** of the catalogued
breadth. **M1 (type/hierarchy resolver), M2 (CFG/data-flow engine), naming wave (#1), dead-code
tail (#2), the cast rules (#4, incl. the store-aware exhaustive-enum-case), the autofix subsystem
(#12), and the #5/#6/#7/#8 pure-AST tails all SHIPPED.** We **lead** on security, architecture/
layering, and exception handling. The remaining gaps are **clone detection + cognitive complexity +
the CK suite** (#6), the **flow/type store-backed rules** (#4 lossy casts / nullability; #5
abstract-method-instantiation), and the **#9/#10/#11 pure-AST tails** (next).

Legend: `[ ]` not started · `[x]` shipped · **(now)** = pure-AST/index, doable without new engines ·
**(M1)** = uses the type/hierarchy resolver (SHIPPED v0.66) · **(M2)** = uses the control-flow/def-use
engine (SHIPPED v0.66).

---

## 1. Naming conventions  -- SHIPPED v0.68-0.69 (9 rules, `info`, config-driven)  **(now)**
- [x] Type prefix: `T`/`E`/`I`/`P` for class/exception/interface/pointer types -- shipped v0.68 as `type-name-prefix`
- [x] Field prefix `F` -- shipped v0.68 as `field-name-prefix`; getter/setter/event prefixes deferred
- [x] Const / enum-member casing; PascalCase methods; param prefix convention -- shipped v0.68 as `const-casing`, `method-pascalcase`, `param-name-prefix`
- [x] Unit name must equal file name -- shipped v0.68 as `unit-name-matches-file`
- [x] Local variable casing -- shipped v0.68 as `local-var-casing`
- [x] Reserved-word casing (lowercase keywords); Hungarian/short-identifier flags -- shipped v0.69 D3 as `reserved-word-casing` (ON) + `hungarian-or-short-identifier` (OFF). Closes #1.
> 9 config-driven rules shipped. Defaults match CLAUDE.md conventions. Disable any check via `"param_prefix": ""` / `[]` or the `disabled` list.

## 2. Dead / redundant code  -- partial  **(now, except where noted)**
Have: `code-after-exit`, `self-assignment`, `comparison-same-operands`, `redundant-assigned-free`,
`redundant-as-tobject`, `redundant-not-not`, `boolean-comparison-true`,
`boolean-result-returned-directly`, `inherited-bare`, `empty-*`, `unused-public-symbol`,
`unused-local`.
- [x] `unused-private-member` (method/field/const/type)  -- shipped v0.68 (store-backed, `warning`)
- [x] `unused-parameter`  -- shipped v0.68 (AST, `warning`, with override/event-handler guards)
- [x] `unused-unit-in-uses`  -- shipped v0.68 (store-backed, `warning`, conservative allow-list)
- [x] `write-only-field` / `assigned-never-read`  -- shipped v0.66 as `write-only-local` **(M2)**
- [x] `overwrite-before-read` (value clobbered before use)  -- shipped v0.66 **(M2)**
- [x] `identical-then-else`  -- shipped v0.68 (AST, `warning`)
- [x] `redundant-parentheses`  -- shipped v0.70 (AST, `hint`; flags '((X))' and lone-term '(X)'/'(1)';
      skips const/var initializer + arr/rec constructor contexts where '(x)' is required; 0 FP over src sanity)
- [x] `commented-out-code`  -- shipped v0.70 (AST, `hint`; whole-comment-is-a-statement heuristic: anchored
      'lhs := rhs;' or 'idpath(...);'; skips directives + doc comments; 0 FP over src after tightening from a
      20/20-FP first cut that merely matched ':=' quoted in prose)
- [x] `function-result-ignored`  -- shipped v0.71 **OFF by default** (AST, `hint`, opt-in via
      `"enabled": ["function-result-ignored"]` or `--rule`). Same-unit only (flags a bare-statement call to a
      same-unit function -- a declProc with a return-type `type` field; no store). Shipped OFF because a real src/
      sanity gave 73 findings on clean code, ~all INTENTIONAL discards (builder/adder/runner functions) -- discarding
      a result is common+usually-intentional in Delphi and no pure-AST heuristic separates bug from intent. A future
      store-backed + purity/effect-aware pass could make it default-on; cross-unit resolution is the next step.
- [ ] `multiple-statements-per-line` -- deferred (low-FP + easy, but a pure style rule; pick up in a later chunk)

## 3. Data-flow / uninitialized variables  -- SHIPPED v0.66 (the long pole, now covered)  **(M2)**
PAL's crown jewel; the compiler does some (W1035/W1036). The M2 per-routine CFG + monotone def-use
engine (`DRagLint.Analysis.Cfg`/`.DataFlow`/`.Flow.Lattices` + `Diagnostics.FlowChecks`) shipped in
v0.66 with definite=warning / possible=info FP stance and managed-type exactness via the M1 store.
- [x] `used-before-assignment` (definite + possible-via-opaque-call)  -- shipped v0.66
- [x] `function-result-not-set` on some path  -- shipped v0.66 (`function-result-not-set`)
- [x] `set-never-referenced`  -- shipped v0.66 as `write-only-local`
- [x] for-loop variable read after the loop (`loop-var-after-loop`); out-param never written (`out-param-not-set`)  -- shipped v0.66
- [x] `referenced-never-set` (read of a never-assigned non-local field) -- shipped v0.68 (single-unit private field scan, `warning`)
> Was *most* of the distance from ~60% to PAL parity. Largely closed by the M2 engine; the remaining
> tail (cross-routine field def-use, possible-via-opaque refinement) is incremental, not a new engine.

## 4. Type-system / casts  -- pure-AST casts SHIPPED v0.71; store-backed deferred  **(M1 for the rest)**
Have: `redundant-as-tobject` (lexical), `freeandnil-on-interface`, plus the v0.71 cast pair below.
- [x] `redundant-cast`  -- shipped v0.71 (AST, `hint`; `TFoo(x)` where `x` is declared exactly `TFoo`,
      via the per-file type map; T-prefixed class-like target + single-identifier arg; near-0 FP).
      **Autofixable** (`lint --fix` strips the cast).
- [x] `unsafe-typecast-without-is`  -- shipped v0.71 **OFF by default** (AST, `warning`; hard cast
      `TFoo(x)` of an object ref to a *different* class with no guarding `x is TFoo`. Fires only on
      genuine down/cross-casts -- value/record casts, `TObject` upcasts, redundant + guarded casts are
      skipped. src FP-sanity = 3, all `T...(Sender)` handler casts. Opt in via config/`--rule`).
- [ ] `non-linear-cast` / `platform-dependent-cast`
- [ ] lossy Ansi<->Unicode cast (compiler W1057/W1058 -- needs real types)  **(M1, deferred -- untestable in the file harness)**
- [x] `exhaustive-enum-case`  -- shipped v0.74 (AST, `warning`, **OFF by default**; a case on an
      enum-typed selector that omits members and has no else. Enum members resolve from a same-file
      map (declEnum, no --db needed) OR the store (skEnum children) for cross-unit enums. Opt in via
      `"enabled"` / `--rule` -- built for enum-heavy code like ORM3. src FP: 0 same-file)
- [ ] interface/object mixing (needs deeper type analysis)  **(M1, deferred)**
- [ ] nullability / not-assigned-interface use  **(M1, deferred -- flow-based)**

## 5. Resource / memory  -- strong, some gaps  **(now; cross-call ones M1/M2)**
Have: `unprotected-object-free`, `use-after-free`, `criticalsection-not-released`,
`dataset-open-without-close`, `missing-inherited-ctor/-dtor`, `virtual-method-in-constructor`,
`interface-reference-cycle`.
- [x] `destructor-without-override`  -- shipped v0.72 (AST, `warning`; a class-declaration
      destructor with no virtual/dynamic/override/abstract directive hides the inherited
      virtual Destroy and leaks. Excludes `class destructor` + impl signatures; src FP = 0)
- [ ] `create-inside-try` (object created inside the try it's protected by)
- [ ] `double-free`
- [ ] `stream/file/bitmap created-not-freed` pairing (same technique as criticalsection)
- [ ] `abstract-method-instantiation` (needs the store: is-the-class-abstract)  **(M1, deferred)**
- [x] true ownership/lifetime across calls (created here, leaked on some path)  -- shipped v0.66 as `object-leak` (store-backed interprocedural ownership oracle)  **(M2)**

## 6. Complexity / metrics  -- partial  **(now, index-backed)**
Have: `cyclomatic-complexity`, `deep-nesting`, `method-too-long`, `too-many-parameters`,
`too-many-locals`, `too-many-exit-points`, `god-class`.
- [x] `boolean-expression-complexity`  -- shipped v0.72 (AST, `info`, threshold=4; flags an
      and/or/xor expression with more than N operators, once at the top of the chain)
- [x] `case-with-too-few-branches`  -- shipped v0.72 (AST, `hint`, threshold=2; a case with
      fewer than N `caseCase` arms reads better as an if)
- [x] `unit-too-large`  -- shipped v0.74 (AST, `info`, threshold=2000; flags a unit exceeding N
      source lines. Configurable via `"thresholds": { "unit-too-large": N }`)
- [ ] cognitive complexity (weighted-nesting metric)  -- moderate; its own chunk
- [ ] CK suite: DIT / NOC / CBO / RFC / LCOM; fan-in / fan-out  -- needs the uses/type graph
- [ ] **clone / duplicate-code detection** (PAL CLON1-2)  -- the biggest remaining item; a token-hash pass

## 7. Exceptions  -- strong (near parity)
Have: `empty-except`, `empty-on-handler`, `empty-finally`, `bare-except`,
`raise-bare-exception`, `reraise-loses-stack`, `raise-in-finally`, `control-flow-in-finally`,
`try-except-swallowed`.
- [x] `exception-constructed-but-not-raised`  -- shipped v0.72 (AST, `warning`; a bare-statement
      `E...Create(...)` on an exception-looking class with no `raise` -- a forgotten `raise`)
- [x] `duplicate-on-class` in a try/except  -- shipped v0.72 as `duplicate-exception-handler`
      (AST, `warning`; two `on <Class>` for the same class in one try -- the second is unreachable)

## 8. Control-flow / expression  -- strong
Have: `with-statement`, `nested-with`, `goto-statement`, `off-by-one-count`,
`not-in-precedence`, `constant-condition`, `ifthen-both-branches`,
`loop-executes-at-most-once`, `division-by-zero-literal`, `float-equality-comparison`.
- [x] `property-references-itself`  -- shipped v0.73 (AST, `warning`; a property whose read/write
      accessor names the property itself -> infinite recursion. Counts declProp identifiers matching
      the property name, excluding the name node + type subtree; src FP = 0)
- [x] `repeated-else-if-condition`  -- shipped v0.73 (AST, `warning`; the same condition text repeats
      in one if/else-if chain -- the later branch is unreachable. Walks the chain via the `else` field)

## 9. Portability / Win64 / locale  -- strong/leading
Have: `win64-pointer-cast` (heuristic), `sizeof-pointer-assumption`, `pchar-arithmetic`,
`gettickcount-wraparound`, `locale-sensitive-conversion`, `deprecated-rtl-function`,
`inline-assembly`, `unsafe-string-api`.
- [ ] `nativeint-truncation`; `default-encoding-io`  (exact ones need types -- **M1**)
- [ ] `variant-record-type-punning`

## 10. Security  -- LEADING the field (ahead of PAL/FixInsight/Sonar)
Have: `sql-injection-concat`, `unsafe-shellexecute`, `path-traversal`, `hardcoded-credential`,
`hardcoded-connection-string`, `hardcoded-ip-address`, `hardcoded-absolute-path`,
`unsafe-string-api`, `format-argument-count`, `format-specifier-type-mismatch`.
- [ ] `weak-random-for-security` (Random for tokens)
- [ ] `dfm-hardcoded-credential` (scan DFM property values)
- [ ] `insecure-temp-file`; `unvalidated-deserialization`

## 11. Architecture  -- LEADING (resolved uses-graph layering is unique)
Have: `layering-violation`, `interface-reference-cycle`, `god-class`, `unit-not-in-dpr`,
`unit-not-in-project`.
- [ ] `circular-uses` report (cycle listing, not just the cross-check)
- [ ] DIT/CBO depth metrics (overlaps #6)

## 12. Ergonomics / output  -- DONE (SARIF, --fail-on, baseline, drag-lint-lint.json v0.66; autofix v0.71)
- [x] **SARIF output** (CI integration) -- shipped v0.66
- [x] baseline / suppression file; per-rule severity overrides + **rule on/off profiles** -- shipped v0.66
- [x] **quick-fixes / autofixes** -- autofix subsystem shipped v0.71: `lint <file> --fix [--apply]`
      (and `lint-all`), a new `tekReplaceInLine` char-range primitive, dry-run by default, `--apply`
      writes with a `.bak`. Fixes: `self-assignment` (delete line), `redundant-parentheses` (strip
      parens), `redundant-cast` (`TFoo(x)`->`x`). More `.scm`-defined-rule fixes need an explicit
      fix-spec payload on `TLintFinding` (deferred -- span-surgery from message text is fragile).

---

## 13. Refactoring + settings UI  -- SHIPPED v0.69 (CLI + Lint Options tab; IDE refactor tab deferred)
Spec: `docs/superpowers/specs/2026-06-30-v069-settings-refactor-design.md`. Value prop: drag-lint's
persisted, deterministic SQLite index is the substrate the IDE's own (flaky async-LSP) Refactor lacks.
- [x] **v0.69 D1a:** `drag-lint rules [--json]` rule catalog (single source of truth + counts) -- shipped v0.69 D1a.
- [x] **v0.69 D1b:** 4th IDE-dock **"Lint Options"** tab -- enable/disable every check by section + item,
  tri-state category header, inline param editors, reads/writes `drag-lint-lint.json` via `TLintConfigWriter` --
  shipped v0.69 D1b. (Manual IDE click-test is a separate human gate.)
- [x] **v0.69 D2:** refactor CLI, packaging the EXISTING `TRenameRefactoring` / `resolve-uses` / dead-code engines
  (dry-run preview + `--apply`): `rename --kind symbol` (cross-unit), `rename --kind param` (routine-local --
  the `param-name-prefix` autofix), `find-unit` (add-to-uses), `safe-delete` -- shipped v0.69 D2a+D2b.
- [ ] **DEFERRED (v0.70+):** in-IDE **"Refactor" tab + OTAPI apply** (Delphi-style Refactorings-Pane preview;
  edits applied to editor buffers) -- the v0.69 CLI commands are its deterministic foundation.
- [ ] **DEFERRED (hard -- need type inference / call-site rewrite):** Change Parameters, Extract Method,
  Extract Interface/Superclass, Pull Up / Push Down, Move, Inline, Declare/Introduce Variable/Field.
> Native Delphi 11/12 Refactor catalog + why it degraded (flaky async LSP / background compiler):
> `docs/lint/Comprehensive report on the refactor.md` + `.superpowers/sdd/delphi-refactor-research.md`.

> **Decision -- `undeclared-identifier` excluded from the `rules` catalog and Lint Options tab (D1a/D1b
> follow-up):** `undeclared-identifier` is an index-backed `check-ast` diagnostic, not a file-based lint
> rule that `drag-lint-lint.json` enables/disables/thresholds. The `drag-lint rules` catalog and the Lint
> Options tab expose only the configurable lint rule set; surfacing a non-configurable index diagnostic
> there would misleadingly imply it is toggleable via the JSON config. Index-only `check-ast` diagnostics
> of this kind are intentionally excluded from the catalog.

---

## Highest-leverage next additions (coverage per effort) -- post-v0.71 (M1+M2+#1+#2+#4-casts+#12-autofix shipped)
1. **Pure-AST tail across #5/#6/#7** -- resource pairing (`destructor-without-override`, `create-inside-try`),
   complexity metrics (`case-with-too-few-branches`, `boolean-expression-complexity`, cognitive complexity,
   `unit-too-large`), exception patterns (`exception-constructed-but-not-raised`, `duplicate-exception-handler`).
   All pure-AST/index, console-testable, no new engine. **The v0.72 chunk.**
2. **Clone / duplicate-code detection (#6)** -- the biggest remaining single item; a token-hash pass. Its own chunk.
3. **Store-backed cast rules (#4)** -- lossy Ansi<->Unicode, exhaustive enum-case, nullability. Need the M1
   enum-member set / exact cross-unit types; untestable in the file-only harness -> a `check-ast --db` path.
4. **More `.scm`-rule autofixes (#12)** -- needs a fix-spec payload on `TLintFinding`. Rule-accuracy / FP polish ongoing.

## Verdict
"Everything the commercial tools do" is **not** reachable on a pure-AST path, but the major engine milestones
are now behind us: **M1 (type resolver), M2 (data-flow/CFG), naming wave (#1), and dead-code tail (#2)
all shipped by v0.68**. We sit at **~72-78%** of the catalogued breadth and **lead** on security and
architecture. The realistic ceiling is **~80-85%** via the remaining cheap index tail + M1-backed cast rules;
the last stretch (clone detection, full CK suite, cross-routine field flow, autofix) is incremental. We
already exceed FixInsight's breadth and approach SonarDelphi's on the dimensions we cover.
