# drag-lint -- lint features in other packages, not (yet) here

Gap checklist vs the commercial/established Delphi & Pascal linters: **Peganza Pascal
Analyzer (PAL)** (the breadth leader, ~188 checks), **TMS FixInsight** (~60), **SonarDelphi**
(~148), and the **Delphi compiler's own** hints/warnings. Grounded in the 2026-06-29 coverage
analysis (`docs/lint/REPORT-1-delphi-lint-landscape.md`) cross-checked against the shipped
inventory (`rules/*.scm`, `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas`,
`src/lint/DRagLint.Lint.ProjectRules.pas`).

**Where we stand:** ~100 rules, roughly **55-65%** of the catalogued breadth. We **lead** on
security, architecture/layering, and exception handling. We are **weak/absent** on naming,
data-flow, and deep type-system casts.

Legend: `[ ]` not started · **(now)** = pure-AST/index, doable without new engines ·
**(M1)** = needs the type/hierarchy resolver · **(M2)** = needs a control-flow/def-use engine.

---

## 1. Naming conventions  -- ~0% today (biggest, cheapest gap)  **(now)**
- [ ] Type prefix: `T`/`E`/`I`/`P` for class/exception/interface/pointer types
- [ ] Field prefix `F`; getter/setter `Get*`/`Set*`; event prefix `On*`/`Do*`
- [ ] Const / enum-member casing; PascalCase methods; param prefix convention
- [ ] Unit name must equal file name; identifiers differing only by case
- [ ] Reserved-word casing (lowercase keywords); Hungarian/short-identifier flags
> ~14 deterministic, near-zero-FP `.scm` rules. The single best breadth-per-effort win.

## 2. Dead / redundant code  -- partial  **(now, except where noted)**
Have: `code-after-exit`, `self-assignment`, `comparison-same-operands`, `redundant-assigned-free`,
`redundant-as-tobject`, `redundant-not-not`, `boolean-comparison-true`,
`boolean-result-returned-directly`, `inherited-bare`, `empty-*`, `unused-public-symbol`,
`unused-local`.
- [ ] `unused-private-member` (method/field/const/type)  -- index already has the refs
- [ ] `unused-parameter`
- [ ] `unused-unit-in-uses`  -- the resolved uses-graph already exists
- [ ] `write-only-field` / `assigned-never-read`  **(M2)**
- [ ] `overwrite-before-read` (value clobbered before use)  **(M2)**
- [ ] `function-result-ignored` at call sites
- [ ] `commented-out-code` detection
- [ ] `redundant-parentheses`, `identical-then-else`, `multiple-statements-per-line`

## 3. Data-flow / uninitialized variables  -- ~5% (the hard frontier)  **(M2)**
PAL's crown jewel; the compiler does some (W1035/W1036). Needs a per-routine CFG + def-use pass.
- [ ] `used-before-assignment` (definite + possible-via-opaque-call)
- [ ] `function-result-not-set` on some path
- [ ] `referenced-never-set` / `set-never-referenced`
- [ ] for-loop variable read after the loop; out-param never written
> This cluster is *most* of the distance from ~60% to PAL parity. Engine work, not rule-writing.

## 4. Type-system / casts  -- weak  **(M1)**
Have heuristics only: `redundant-as-tobject` (lexical), `freeandnil-on-interface`.
- [ ] `non-linear-cast` / `redundant-cast` / `platform-dependent-cast`
- [ ] `unsafe-typecast-without-is` (hard cast where `is`/`as` is safer)
- [ ] lossy Ansi<->Unicode cast (compiler W1057/W1058 -- needs real types)
- [ ] interface/object mixing; `exhaustive-enum-case` (needs the enum member set)
- [ ] nullability / not-assigned-interface use

## 5. Resource / memory  -- strong, some gaps  **(now; cross-call ones M1/M2)**
Have: `unprotected-object-free`, `use-after-free`, `criticalsection-not-released`,
`dataset-open-without-close`, `missing-inherited-ctor/-dtor`, `virtual-method-in-constructor`,
`interface-reference-cycle`.
- [ ] `create-inside-try` (object created inside the try it's protected by)
- [ ] `double-free`
- [ ] `stream/file/bitmap created-not-freed` pairing (same technique as criticalsection)
- [ ] `abstract-method-instantiation`; `destructor-missing-override`
- [ ] true ownership/lifetime across calls (created here, leaked on some path)  **(M2)**

## 6. Complexity / metrics  -- partial  **(now, index-backed)**
Have: `cyclomatic-complexity`, `deep-nesting`, `method-too-long`, `too-many-parameters`,
`too-many-locals`, `too-many-exit-points`, `god-class`.
- [ ] cognitive complexity; boolean-expression complexity
- [ ] CK suite: DIT / NOC / CBO / RFC / LCOM; fan-in / fan-out
- [ ] `unit-too-large`; `case-with-too-few-branches`
- [ ] **clone / duplicate-code detection** (PAL CLON1-2)

## 7. Exceptions  -- strong (near parity)
Have: `empty-except`, `empty-on-handler`, `empty-finally`, `bare-except`,
`raise-bare-exception`, `reraise-loses-stack`, `raise-in-finally`, `control-flow-in-finally`,
`try-except-swallowed`.
- [ ] `exception-constructed-but-not-raised` (missing `raise`)
- [ ] `duplicate-on-class` in a try/except

## 8. Control-flow / expression  -- strong
Have: `with-statement`, `nested-with`, `goto-statement`, `off-by-one-count`,
`not-in-precedence`, `constant-condition`, `ifthen-both-branches`,
`loop-executes-at-most-once`, `division-by-zero-literal`, `float-equality-comparison`.
- [ ] `property-references-itself`
- [ ] `repeated-else-if-condition` (same test twice)

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

## 12. Ergonomics / output  -- gap (adoption, not analysis)
- [ ] **SARIF output** (CI integration)
- [ ] **quick-fixes / autofixes** (SonarDelphi ships ~14; we have 0)
- [ ] baseline / suppression file; per-rule severity overrides + **rule on/off profiles** (v0.66 Tier 5)

---

## Highest-leverage next additions (coverage per effort)
1. **Naming wave (#1)** -- cheap, deterministic, closes the worst breadth gap.
2. **M1 type/hierarchy resolver** -- makes 4 shipped heuristics exact + unblocks #4.
3. **M2 data-flow/CFG engine** -- unlocks #3, the real path to PAL parity. Biggest effort.
4. **Cheap index tail** (#2 unused-* family, #6 metrics + clones) + **SARIF/quick-fixes** (#12).

## Verdict
"Everything the commercial tools do" is **not** reachable on a pure-AST path: ~60% today,
**~70-80% attainable** with the naming wave + M1, and true PAL parity gated on the M2 data-flow
engine (the long pole). We already **lead** on security and architecture.
