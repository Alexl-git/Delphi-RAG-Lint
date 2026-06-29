# drag-lint -- "All Possible Lints" Completeness Roadmap

> Status: approved 2026-06-28
> Companions: [REPORT-1-delphi-lint-landscape.md](../../lint/REPORT-1-delphi-lint-landscape.md)
> (the field), [REPORT-2-draglint-implementation-plan.md](../../lint/REPORT-2-draglint-implementation-plan.md)
> (original waves), [BACKLOG.md](../../lint/BACKLOG.md) (idea backlog + type-resolver big-ticket).
> Supersedes the wave plan in REPORT-2 ss4 (most of which has shipped) and the
> per-release plan in [2026-06-28-new-lint-rules-v062-v063-design.md](2026-06-28-new-lint-rules-v062-v063-design.md).

---

## 1. Goal

Drive drag-lint to **catalogue-complete** lint coverage -- every distinct check type in
REPORT-1 ss7 (categories A-I) plus the ss8 semantic frontier -- across a sequence of
releases, while first fixing the robustness/UX issues that surfaced running the linter at
scale on ORM3 (slow, silent, false positives, DB-lock collisions).

This is a **roadmap spec**: one through-line document that decomposes into **per-release
implementation plans**. Each release (R1, R2, ...) and each rule wave gets its own
`writing-plans` plan when work on it begins. The user stays in the loop release-by-release.

---

## 2. Where we are (2026-06-28, post v0.63.0-alpha)

~90 distinct rules shipped: 56 `.scm` + ~36 `TAstChecker` built-ins + project rules
(`god-class`, `unused-public-symbol`, `interface-reference-cycle`, `layering-violation`,
`unit-not-in-dpr`, `unit-not-in-project`).

**Strong coverage already:** exceptions (empty/bare/swallowed except, raise-bare/reraise/
raise-in-finally), control-flow (off-by-one, not-in/not-comparison precedence, constant-
condition, loop-executes-at-most-once, ifthen-both-branches), resource basics (unprotected-
object-free, use-after-free, freeandnil-on-interface, missing-inherited-ctor/dtor,
criticalsection-not-released, dataset-open-without-close, virtual-method-in-constructor),
metrics (cyclomatic, deep-nesting, too-many-params/locals, method-too-long, god-class),
security (sql-injection-concat, hardcoded credential/conn-string/ip/path, unsafe-shellexecute,
path-traversal, unsafe-string-api), platform (win64-pointer-cast, locale-sensitive-conversion,
float-equality heuristic, gettickcount-wraparound, sizeof-pointer-assumption, pchar-arithmetic,
deprecated-rtl-function, inline-assembly), Format checks, and the index differentiators
(layering, unused-public-symbol, interface-reference-cycle, ui-access-in-thread).

**Infra shipped:** `// drag-lint:ignore` suppression, `--disable`, `--rules-dir`, bundled
`rules/`, `lint-all` batch, two-DB model, IDE "Run Lint All" menu, TDD harness (75/75).

---

## 3. Gap analysis vs REPORT-1 ss7/ss8 (what remains)

Grouped by what unlocks them. (Shipped items omitted.)

**No type resolver needed (cheap AST/index):**
- Dead/redundant: `unused-unit-in-uses`, `unused-private-member`, `write-only-field`,
  `unused-parameter`, `commented-out-code`, `redundant-parentheses`, `identical-then-else`,
  `odd-else-if-repeated-test`, `function-result-ignored`.
- Exceptions: `missing-raise` (constructed not raised), `duplicate-on-class`.
- Resource: `create-inside-try`, `double-free`, `stream-not-freed` / `file-not-closed`
  (Create/Free + Open/Close pairing, like CheckCriticalSection), `destructor-missing-override`.
- Control/expr: `property-references-itself`.
- Maintainability: `magic-string` / literal-replaceable-by-const, `duplicated-code` (clones),
  `multiple-statements-per-line`.
- Metrics: `cognitive-complexity`, `too-many-nested-routines`, `unit-too-large`,
  `case-too-small`, `boolean-expression-complexity`, fan-in/fan-out (index),
  CK suite DIT/NOC/CBO/RFC/LCOM (index).
- Security: `weak-random-for-security`, `dfm-hardcoded-credential` (DFM-aware),
  `insecure-temp-file`, `tstringlist-delimiter-pitfall`.
- Platform: `variant-record-type-punning`, `default-encoding-io`, `nativeint-truncation` (heuristic).

**Needs the type resolver (M1):**
- `float-equality-comparison` (exact), `freeandnil-on-interface` (exact),
  `win64-pointer-cast` (exact), `interface-reference-cycle` (exact, drop I-prefix guess) --
  these ship today as heuristics; M1 makes them exact.
- `exhaustive-enum-case` (enum member set), `lossy-ansi-unicode-cast`, `non-linear-cast`,
  `redundant-cast`, `abstract-method-instantiation`, `unsafe-typecast-without-is`,
  `generics-rtti-misuse` (TObjectList OwnsObjects), FireDAC sequence extended
  (`transaction-not-committed`, `dataset-opened-twice`, `connection-query-leak`, FetchAll),
  WinAPI contract misuse, **nullability** (`X := Find(...); X.Name` w/o Assigned).

**Naming category B (enabled by default per decision):**
- `class-not-t-prefixed`, `exception-not-e-prefixed`, `interface-not-i-prefixed`,
  `pointer-not-p-prefixed`, `field-not-f-prefixed`, `constant-casing`, `method-pascalcase`,
  `param-prefix`, `short-identifier` (<3), `names-differ-only-by-case`, `unit-name-vs-file`,
  `getter-setter-name`, `enum-value-prefix`, `keyword-lowercase`.

**Cross-call-graph frontier (REPORT-1 ss8, largest):**
- ownership/resource-lifetime flow across the call graph, thread-safety (shared mutable
  field touched without a lock), component lifecycle/ownership-through-Owner.

**Infra still missing:** SARIF output, per-`.scm` `enabled` default + `--enable`,
`drag-lint-lint.json` config (thresholds/severity/disabled), CI exit-code-by-severity,
baseline file, quick-fixes/autofix.

---

## 4. Decisions (brainstorming, 2026-06-28)

1. **Queue (item 5):** serialize the heavy one-shot jobs (reindex / lint-all / forms-csv /
   graph) through one background-job queue so they never collide on the SQLite DB; the
   interactive LSP server stays live and responsive.
2. **Type resolver (item 6):** build it **early** -- it lands before the rule-expansion waves
   so every new rule (and the rewrite of today's heuristic rules) can use it.
3. **Naming (item 6 / category B):** ship **enabled by default**. Prefix checks are
   deterministic (true positives, not guesses); `--disable` / config silences them per project.
4. **FP policy (item 1):** "when unsure, do not report -- but keep the rule." Suppress
   uncertain findings rather than deleting rules, so a later, clearer engine can re-enable them.

---

## 5. Release sequence

| Phase | Theme | Target | Big infra? |
|---|---|---|---|
| **R1** | Robustness & visibility (items 4, 2, 1) | v0.64 | no |
| **R2** | IDE job queue (item 5) | v0.65 | no (plugin) |
| **M1** | Type & hierarchy resolver | v0.66-0.67 | yes (early) |
| **Wave A** | No-resolver AST/index rules | v0.68+ | no |
| **Wave B** | Naming/conventions (on by default) | next | no |
| **Wave C** | Metrics / CK suite | next | index |
| **Wave D** | Type-dependent rules (unlocked by M1) | next | uses M1 |
| **Wave E** | Cross-call-graph frontier | last | call-graph |

Infra items (SARIF, per-rule enable, config file, CI exit codes, baseline, autofix) are
threaded into whichever release first needs them (noted per phase below).

---

## 6. Phase detail

### R1 -- v0.64 "Robustness & visibility"

**Item 4 -- lint-all progress.**
- CLI `lint-all` streams `lint-all: [i/N] <file>` to **stderr** (stdout stays clean for the
  report/JSON), throttled to ~1% milestones (or every K files), keeping the existing final
  summary. A `--quiet` flag suppresses it for scripts.
- IDE Run Lint All reads the child pipe **incrementally** -- replace the block-until-done
  `RunCaptureStdout` (DragLint.Plugin.ProcRun.pas) with a reader `TThread` that
  `Synchronize`-posts throttled progress (`Lint-all: 34% (250/735)`) to the Messages view
  and the IDE status bar; final summary line unchanged.

**Item 2 -- parse-once refactor.**
- Today each `TAstChecker.CheckXxx` creates its own `TTSParser` + `TTSTree` and re-reads the
  file. Introduce a parse-once entry point: read bytes + parse once per file, hand the shared
  `TTSTree` (+ src bytes) to every check. Refactor the ~30 `CheckXxx` signatures to accept the
  shared tree (or a small `TParsedFile` record), and update the 3 dispatch sites (`DoLint`,
  `DoLintAll`, the `Check` aggregator). Pure speedup + the substrate M1 builds on. TDD: the
  existing 75 fixtures must stay green (behavior-preserving refactor).

**Item 1 -- FP-1 fix + fortification pass.**
- FP-1: `syntax-error` suppresses ERROR/MISSING nodes plausibly caused by conditional-
  compilation the grammar cannot balance (`{$IF}...{$IFEND}`; audit other directive forms).
  Detect directive imbalance near the error span and skip. Keep firing on genuine typos.
  Regression fixture from CLIENT\MStreams.pas pattern.
- Fortification audit: re-run `lint-all` on ORM3, diff the FP-heavy rules
  (`string-equality-comparison`, `large-magic-number`, others from
  CLIENT\LINT-FALSE-POSITIVES-20260628.md), and add uncertainty guards (skip ambiguous
  cases / raise thresholds) per the FP policy. Document each guard with a fixture.

### R2 -- v0.65 "IDE job queue" (item 5)

- A serialized **background-job queue** in the plugin: enqueue {reindex, lint-all, forms-csv,
  graph}; run one at a time on a worker thread; coalesce duplicate enqueues (a new
  reindex-on-save supersedes a pending one). Surface "running X; N queued" in Messages.
- The LSP server (hover/lint/completion) is a separate long-running process and keeps serving
  concurrently -- the queue governs only the heavy DB-touching jobs, eliminating the
  "database is locked" collisions seen in the field.
- Reuse R1's incremental pipe reader + the existing `DragLint.Plugin.JobObject` for clean
  cancel/teardown.

### M1 -- v0.66-0.67 "Type & hierarchy resolver" (BACKLOG ss3, built early)

Staged; each stage could be its own release:
1. `ISymbolStore` additions: given (unit, identifier) -> declared type; given a type name ->
   kind (class/interface/enum/record/alias) + ancestry chain (cross-unit) + (for enums) the
   member set. Backed by the existing `symbols.signature` + `unit_uses` graph.
2. Per-routine scope chain: locals -> params -> fields -> unit-level -> used-units, so an
   identifier resolves to a symbol -> type (today's flat name->type map ignores scope/shadowing).
3. Rewrite the heuristic rules (`float-equality-comparison`, `win64-pointer-cast`,
   `freeandnil-on-interface`, `interface-reference-cycle`) to be exact; retire the I-prefix /
   string-prefix guesses.

### Wave A -- v0.68+ "No-resolver rules"

All ss3 "no type resolver" items above. `.scm` where one query suffices; `TAstChecker`
built-ins for pairing/flow/scope (`create-inside-try`, `double-free`, `stream-not-freed`,
`unused-private-member`, `write-only-field`, `unused-unit-in-uses`, `commented-out-code`,
`multiple-statements-per-line`, `redundant-parentheses`, `identical-then-else`,
`function-result-ignored`, `missing-raise`, `cognitive-complexity`, `too-many-nested-routines`,
`weak-random-for-security`, `variant-record-type-punning`, `default-encoding-io`,
`property-references-itself`, `dfm-hardcoded-credential`, `duplicated-code`). Ship the
**`drag-lint-lint.json` config + per-rule `enabled`** infra here (Wave B needs it for
per-project naming control) and **SARIF output**.

### Wave B -- "Naming / conventions" (enabled by default)

All of category B. Mostly `.scm` (deterministic prefix/casing checks) + a couple built-ins
(`unit-name-vs-file` needs filename, `names-differ-only-by-case` needs cross-symbol compare).

### Wave C -- "Metrics / CK suite"

Index-backed: DIT, NOC, CBO, RFC, LCOM, fan-in/fan-out, `unit-too-large`, `case-too-small`,
`boolean-expression-complexity`. A `metrics` report mode aggregating ranked lists (PAL-style).

### Wave D -- "Type-dependent rules" (unlocked by M1)

`exhaustive-enum-case`, `lossy-ansi-unicode-cast`, `non-linear-cast`, `redundant-cast`,
`abstract-method-instantiation`, `unsafe-typecast-without-is`, `generics-rtti-misuse`,
FireDAC sequence extended (`transaction-not-committed`, `dataset-opened-twice`,
`connection-query-leak`), WinAPI contract misuse, **nullability**.

### Wave E -- "Cross-call-graph frontier"

Ownership/resource-lifetime flow across the call graph, thread-safety (shared mutable field
without a lock), component lifecycle/ownership-through-Owner. Largest; uses M1 + the refs/
call graph. Quick-fixes/autofix (the SonarDelphi differentiator) ships here or as its own
release once the rule set is broad enough to make autofix worthwhile.

---

## 7. Per-rule contract (unchanged from REPORT-2 ss5)

- **TDD/CDD first:** write `tests/lint/<id>.pas` + `.expected` (or a `tests/lint-project/`
  fixture for index/DB rules) **before** the rule; red -> green. Harness must stay 100% green.
- **DocInsight `///`** on every new public Pascal declaration; rationale header on each `.scm`.
- **Encoding:** `.pas` strict 7-bit ASCII + CRLF, no BOM; `.scm`/`.json` keep messages ASCII.
- **Severity:** `info` / `warning` / `error` (+ `hint`).
- **FP policy:** when unsure, do not report; keep the rule. Park genuinely noisy rules behind
  the per-rule `enabled:false` default once that infra lands (Wave A).
- **Build:** built-ins need a Win64 (+Win32) rebuild via `build/pack-lint-release.ps1`; `.scm`
  rules hot-load with no rebuild.

---

## 8. Decomposition

Each phase above becomes its own `writing-plans` plan at the time it is started:
`docs/superpowers/plans/YYYY-MM-DD-lint-<phase>.md`. R1 is planned first. The roadmap is the
stable index; phases may be re-ordered only by explicit decision (recorded here).
