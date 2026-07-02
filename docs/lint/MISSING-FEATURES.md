# drag-lint -- lint features in other packages, not (yet) here

Gap checklist vs the commercial/established Delphi & Pascal linters: **Peganza Pascal
Analyzer (PAL)** (the breadth leader, ~188 checks), **TMS FixInsight** (~60), **SonarDelphi**
(~148), and the **Delphi compiler's own** hints/warnings. Grounded in the 2026-06-29 coverage
analysis (`docs/lint/REPORT-1-delphi-lint-landscape.md`) cross-checked against the shipped
inventory (`rules/*.scm`, `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas`,
`src/lint/DRagLint.Lint.ProjectRules.pas`).

**Where we stand (updated v0.79.0-alpha):** ~162 rules, roughly **83-86%** of the catalogued
breadth. **M1 (type resolver), M2 (CFG/data-flow), naming (#1), dead-code (#2), the cast rules
(#4, incl. store-aware exhaustive-enum-case + lossy-cast), autofix (#12), the #5/#6/#7/#8 pure-AST
tails, cognitive complexity (#6), the v0.76 store/AST tails (#5 abstract-method, #9
nativeint-truncation, #10 dfm-credential/insecure-temp, #11 circular-uses), #6
clone/duplicate-code detection (v0.77), the #6/#11 CK class-metric suite (v0.78:
DIT/NOC/CBO/RFC/LCOM4), the #4/#5 M2-flow rules (v0.79: not-assigned-interface + double-free),
and the v0.79 Fowler refactoring-catalog batch (magic-literal / boolean-flag-parameter /
message-chain / public-writable-field / loop-control-flag, category `refactoring`) all SHIPPED.**
As of v0.77 the IDE (LSP) surfaces the same rules as the CLI and honors an up-tree
`drag-lint-lint.json` config. We **lead** on security, architecture/layering, and exception
handling. The remaining gaps are small deferred tails (#9 default-encoding-io; #4 interface/object
mixing; CK fan-in/fan-out; the store-backed refactoring signals middle-man/feature-envy/repeated-type-switch; and a few
low-signal items documented as won't-fix).

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
- [x] `multiple-statements-per-line` -- **DONE v0.76** (`hint`, off by default; one finding per line)

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
- [x] lossy Ansi<->Unicode cast  -- shipped v0.75 as `lossy-cast` (AST, `info`; an Ansi-narrowing
      cast `AnsiString`/`AnsiChar`/`ShortString`/`RawByteString`(x) of a Unicode-string operand
      drops characters outside the code page, compiler W1057; src FP = 2 real)
- [x] `exhaustive-enum-case`  -- shipped v0.74 (AST, `warning`, **OFF by default**; a case on an
      enum-typed selector that omits members and has no else. Enum members resolve from a same-file
      map (declEnum, no --db needed) OR the store (skEnum children) for cross-unit enums. Opt in via
      `"enabled"` / `--rule` -- built for enum-heavy code like ORM3. src FP: 0 same-file)
- [ ] interface/object mixing (needs deeper type analysis)  **(M1, deferred)**
- [x] nullability / not-assigned-interface use  **(M2 flow) -- DONE v0.79** as `not-assigned-interface` (`warning`, ON): an interface-typed local dereferenced (`X.member`/`X as T`) on a path where it was never assigned. Reuses the definite-assignment lattice for the interface subset used-before-assignment skips; warning(Must)/info(May). Known limitation: short-circuit `and`/`or` seeding is a safe-direction false-negative (see CHANGELOG).

## 5. Resource / memory  -- strong, some gaps  **(now; cross-call ones M1/M2)**
Have: `unprotected-object-free`, `use-after-free`, `criticalsection-not-released`,
`dataset-open-without-close`, `missing-inherited-ctor/-dtor`, `virtual-method-in-constructor`,
`interface-reference-cycle`.
- [x] `destructor-without-override`  -- shipped v0.72 (AST, `warning`; a class-declaration
      destructor with no virtual/dynamic/override/abstract directive hides the inherited
      virtual Destroy and leaks. Excludes `class destructor` + impl signatures; src FP = 0)
- [x] `create-inside-try`  -- shipped v0.75 (AST, `warning`; a try..finally whose FIRST protected
      statement is `X := TFoo.Create` -- if the constructor raises, the finally frees an undefined
      reference. Handles paren-less + parenthesised constructors; FixInsight-parity)
- [x] `double-free` -- **DONE v0.79** (`warning`, ON, M2): a raw `X.Free` reachable twice on a path with no reassignment/nil-ing between (frees a dangling pointer). New forward `TFreedState` lattice; `FreeAndNil`/`DisposeOf` clears the dangling state so FreeAndNil-then-Free is silent; warning(Must)/info(May). Aliased frees are a documented false-negative.
- [ ] `stream/file/bitmap created-not-freed` pairing (same technique as criticalsection) -- first VERIFY the M2 `object-leak` oracle doesn't already cover it before adding a targeted rule.
- [x] `abstract-method-instantiation` -- **DONE v0.76** (store-backed: virtual method with no body, unoverridden across the hierarchy)
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
- [x] cognitive complexity  -- shipped v0.75 as `cognitive-complexity` (AST, `info`, threshold=25;
      SonarSource-style: each control-flow structure adds 1 + its nesting depth, each and/or/xor
      adds 1. Default 25 -- cognitive scores higher than cyclomatic. Configurable)
- [x] CK suite: DIT / NOC / CBO / RFC / LCOM  -- **DONE v0.78** as `deep-inheritance` / `too-many-children` /
      `high-coupling` / `high-response` / `low-cohesion` (category `metrics`, `info`, ON, store-backed,
      per-rule `threshold`). LCOM shipped as LCOM4 (connected components). fan-in / fan-out still open.
- [x] **clone / duplicate-code detection** (PAL CLON1-2)  -- **DONE v0.77** as `duplicate-code` (complexity, `info`, ON,
      `threshold` default 90). New unit `DRagLint.Diagnostics.CloneChecks.pas`: Type-2 (renamed-identifier tolerant)
      Rabin-Karp maximal-match over normalized-token streams (ids+literals -> placeholders; unique per-routine barriers),
      with coverage-based overlap suppression to collapse self-similar regions. `Check` (within-file, CLI `DoLint`) +
      `CheckProject` (within+cross-file, `DoLintAll`); also wired into the LSP `BuildDiagnostics` so it shows in the IDE.

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
- [x] `nativeint-truncation` -- **DONE v0.76** (`warning`; 32-bit cast of a NativeInt/pointer-sized value, sibling of win64-pointer-cast). `default-encoding-io` still open (needs **M1**).
- [ ] `variant-record-type-punning` -- deferred (needs flow; no clean pure-AST signal)

## 10. Security  -- LEADING the field (ahead of PAL/FixInsight/Sonar)
Have: `sql-injection-concat`, `unsafe-shellexecute`, `path-traversal`, `hardcoded-credential`,
`hardcoded-connection-string`, `hardcoded-ip-address`, `hardcoded-absolute-path`,
`unsafe-string-api`, `format-argument-count`, `format-specifier-type-mismatch`.
- [x] `weak-random-for-security`  -- shipped v0.75 (AST, `warning`; a security-named variable
      (token/password/secret/salt/nonce/apikey/...) assigned from System.Random/RandomRange -- not
      a CSPRNG. src FP = 0)
- [x] `dfm-hardcoded-credential` -- **DONE v0.76** (`warning`; credential-named DFM property with a literal string value)
- [x] `insecure-temp-file` -- **DONE v0.76** (`warning`; hardcoded temp path in a file API). `unvalidated-deserialization` still open (no clean signal).

## 11. Architecture  -- LEADING (resolved uses-graph layering is unique)
Have: `layering-violation`, `interface-reference-cycle`, `god-class`, `unit-not-in-dpr`,
`unit-not-in-project`.
- [x] `circular-uses` report -- **DONE v0.76** (`warning`, store-backed; Tarjan SCC over the unit uses-graph, one finding per cycle)
- [x] DIT/CBO depth metrics (overlaps #6) -- **DONE v0.78** with the CK suite (NOC/RFC/LCOM), shipped as one store-backed bundle.

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
2. **Clone / duplicate-code detection (#6)** -- **DONE v0.77** (`duplicate-code`; Rabin-Karp token-hash pass).
3. **CK class-metric suite (#6/#11)** -- **DONE v0.78** (DIT/NOC/CBO/RFC/LCOM4, store-backed, `tests/lint-store` harness, one bundle).
4. **M2-flow rules (#4/#5) -- NEXT (v0.79)** -- nullability/not-assigned-interface (#4), double-free (#5); extend `FlowChecks`.
5. **Fowler refactoring-catalog signals (#14)** -- a fresh batch of pure-AST/store rules distilled from the
   refactoring catalog (magic-literal, boolean-flag-parameter, message-chain, public-writable-field, ...). See section 14.
6. **More `.scm`-rule autofixes (#12)** -- needs a fix-spec payload on `TLintFinding`. Rule-accuracy / FP polish ongoing.

## Verdict
"Everything the commercial tools do" is **not** reachable on a pure-AST path, but the major engine milestones
are now behind us: **M1 (type resolver), M2 (data-flow/CFG), naming wave (#1), and dead-code tail (#2)
all shipped by v0.68**; by v0.77 clone/duplicate-code detection + full CLI/IDE(LSP) rule parity are in; and
v0.78 adds the **CK class-metric suite** (#6/#11: DIT/NOC/CBO/RFC/LCOM4). We sit at **~82-85%** of the
catalogued breadth and **lead** on security and architecture. The realistic ceiling is **~85%**; the last
stretch -- the **M2-flow rules** (#4 nullability, #5 double-free, slated for **v0.79**), the Fowler
refactoring-catalog batch (#14), then cross-routine field flow, autofix breadth, and the deferred in-IDE
Refactor tab (#13) -- is incremental or UX-heavy, not new-engine work. We already exceed FixInsight's breadth
and approach SonarDelphi's on the dimensions we cover.

---

## 14. Fowler refactoring-catalog signals -- candidate rules  (researched 2026-07-02)

From <https://refactoring.com/catalog/>: many refactorings are triggered by a **statically detectable**
"before" state. Most catalog entries are already covered by existing rules (Extract Function ->
`method-too-long`/complexity; Extract Class -> `god-class`+CK suite; Remove Dead Code -> `code-after-exit`/
`unused-*`; Change Function Declaration/long params -> `too-many-parameters`; Duplicated Code ->
`duplicate-code`; Replace Nested Conditional w/ Guard Clauses -> `deep-nesting`; Consolidate/Decompose
Conditional -> `boolean-expression-complexity`). The **new** detectable signals worth adding:

Pure-AST (no new engine), good value -- **all 5 DONE v0.79** (category `refactoring`):
- [x] `magic-literal` (Replace Magic Literal) -- **DONE v0.79** (`hint`, OFF-by-default). Numeric literals only;
      exempt 0/1/-1/2 + const/enum/case/range/initializer contexts. src/ FP=696 -> OFF (opt-in).
- [x] `boolean-flag-parameter` (Remove Flag Argument) -- **DONE v0.79** (`hint`, OFF-by-default). Boolean param
      driving an if/case/while condition; skips overrides + Sender handlers. src/ FP=42.
- [x] `message-chain` (Hide Delegate) -- **DONE v0.79** (`hint`, **ON**, threshold 4). Left-nested `exprDot`
      spine; qualified type/unit names excluded structurally. src/ FP=0.
- [x] `public-writable-field` (Encapsulate Variable) -- **DONE v0.79** (`info`, OFF-by-default). `public` class
      field (excludes `published` DFM components + records). src/ FP=44.
- [x] `loop-control-flag` (Replace Control Flag with Break) -- **DONE v0.79** (`hint`, OFF-by-default). Boolean
      flag assigned True/False in a loop body + referenced in its condition. src/ FP=1.

Store-backed:
- [ ] `middle-man` (Remove Middle Man) -- a class most of whose methods just delegate to one field/object.
- [ ] `feature-envy` (Move Function) -- a method that references another class's members more than its own
      (overlaps CBO; needs member-access attribution -- harder given name-based refs).
- [ ] `repeated-type-switch` (Replace Conditional w/ Polymorphism) -- the same enum/type-code `case` selector
      appearing across multiple methods (a polymorphism candidate).
- [ ] generalize `global-form-variable` -> `mutable-global-variable` (Global Data) -- any writable unit-level
      global var, not just form types.

Needs M2 flow:
- [ ] `split-variable` (Split Variable) -- one local reused for two unrelated purposes (distinct def-use spans).
- [ ] `separate-query-from-modifier` -- a function that both returns a value and mutates state (noisy; assess).

Deferred / low-signal: Replace Temp with Query, Replace Derived Variable with Query, Primitive Obsession,
Speculative Generality, Data Clumps (Introduce Parameter Object) -- weak/expensive static signals.
