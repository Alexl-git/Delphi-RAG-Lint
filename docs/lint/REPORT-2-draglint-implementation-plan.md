# Report 2 — drag-lint Lint Implementation Plan

> Companion to [REPORT-1-delphi-lint-landscape.md](REPORT-1-delphi-lint-landscape.md).
> This document maps the landscape onto **what drag-lint can actually build**, given its
> engine, and lays out a prioritized, TDD-able build order.
>
> Status legend: ✅ shipped this effort · 🔜 planned · 🧱 needs infra first · 🔬 needs type-resolution (future).

---

## 1. Our engine, in one screen

Two rule engines emit a common `TLintFinding` (`RuleId, Severity, Message, FilePath, Start/End Line/Col`);
the CLI serializes to text or `--json`; exit code 1 if any findings.

- **Path A — external tree-sitter rules** (`rules\*.scm` + `<same>.json`). *Data-driven, no recompile,*
  hot-loaded by `TQueryRule`/`TQueryRuleLoader` at `TLinter.Create`. The `.scm` is a tree-sitter query;
  capture the offending node `@warn`; narrow with predicates `#eq?`/`#not-eq?`/`#match?`/`#any-of?`.
  The `.json` supplies `id`, `severity` (`info|warning|error`), `message`, `warn_capture`.
  **This is the primary path** — lowest risk, fastest, safe for unattended work.
- **Path B — Pascal built-ins** (`TAstChecker` class methods in `DRagLint.Diagnostics.AstChecks.pas`,
  or walks in `DRagLint.Lint.Linter.pas`). Needed when a single tree-sitter query can't express the
  logic: DB/refs lookups (`ISymbolStore`), cross-statement/scope reasoning, loop/finally context,
  multi-line text scanning. Requires a Win64 rebuild and CLI wiring (`DoLint` + `--rule` list).

**Inputs available:** tree-sitter `TTSNode` (NodeType, child/field access, Start/EndPoint 0-based,
IsError/IsMissing), `NodeText(node,src)` helper, and `ISymbolStore` typed queries over the **schema-v9
SQLite index** — `symbols` (kind, visibility/modifiers, parent_id, section, decl range, `impl_start/end_line`,
signature), `refs` (kind ∈ {read,write,call,type_use,event-binding,di-*}), `unit_uses` (interface/impl,
resolved target), `symbol_docs`. Node kinds seen in the grammar: `exprCall`, `exprBinary`, `defProc`,
`declVar`, `identifier`, `with`, `case`, `caseLabel`, `literalNumber`, `kEq`/`kTrue`/`kAs`, `comment`,
`goto`, `inherited`, `ERROR`/`MISSING` (each rule verifies kinds against the grammar before shipping).

### Engine constraints that shape the plan
1. **No type resolution in the lint engine yet.** Any check needing "is this a `Double`?", "does this
   class descend from `TStream`?", or "is this `=` between strings?" is **🔬 future** — can only be
   approximated heuristically (e.g. declared-type text from the symbol table) until a type-resolver is
   plumbed in. (`string-equality-comparison` already over-fires for exactly this reason — a cautionary tale.)
2. **`.scm` rules can't be individually enabled/disabled or `--rule`-selected** — every `.scm` always runs.
   So Path A rules must be **high-signal / low-false-positive**, or be gated behind the new selection infra (§3).
3. **The `rules\` dir isn't shipped next to the Win64 exe** → the 14 existing `.scm` rules are dormant in the
   installed binary. Must be fixed (§3) or new `.scm` rules won't fire in the field.

---

## 2. Feasibility tiers (master catalogue → our engine)

| Tier | Meaning | Examples |
|---|---|---|
| **T1 — pure `.scm`** | one tree-sitter query, structural/lexical, low FP | `with`, nested `with`, `goto`, empty `except`/`finally`/`then`/`else`, bare `raise Exception.Create`, `raise E` re-raise, `= True`/`= False`, redundant `as TObject`, `Assert` w/o msg, `Format` literal scan, off-by-one `0..Count`, `inherited` bare, `case` magic labels, commented-out markers, `WriteLn` |
| **T2 — `.scm` + light Pascal** | query + a small Pascal post-filter or multi-node check | empty method body, `Create` inside `try`, missing `else` on enum `case` (needs enum member count), self-assignment, code-after-Exit |
| **T3 — Pascal built-in (AST/scope/text)** | needs scope/flow/loop/finally context or text scan | code after `Exit`/`raise`/`Break`, `raise` inside `finally`, swallowed exception (no log/re-raise), missing `inherited` in ctor/dtor, FreeAndNil-guard redundancy, magic-number-in-context, TODO/FIXME density |
| **T4 — Pascal + DB/refs (the differentiators)** | needs the symbol/refs/uses index | unused **public** symbol project-wide, unused unit-in-uses (resolved), write-only field, unused private member, fan-in/out, **architecture/layering over uses-graph**, cross-unit dead code, deep inheritance (DIT), god class |
| **T5 — 🔬 needs type resolution** | requires real types | float `=` comparison, Ansi/Unicode lossy cast, FreeAndNil-on-interface (vs object), stream-not-freed (type ancestry), non-linear cast, locale Date/Str overload disambiguation, FireDAC API-sequence |

The plan front-loads **T1/T2** (cheap, safe, no recompile) and the **T4 differentiators** (where our
index beats the AST-only tools), and defers **T5** behind a type-resolution milestone.

---

## 3. Infrastructure to add (small, enables everything)

These are prerequisites/multipliers; do them alongside the first rules.

1. **🧱→✅ Ship `rules\` next to the binary.** Fix the deploy so the installed Win64 exe finds its rules
   (copy `rules\` in the build/package step; and/or fall back to the repo `rules\` if `<exe>\rules` is absent).
   *Without this, every new `.scm` rule is dead in the field.* — **highest priority.**
2. **Per-rule selectability for `.scm` rules.** Let `--rule <id>` (repeatable) and a new
   `--disable <id>` filter the external rules too (today only 6 built-ins are filterable). Drive it from
   the rule's `id`. Also honor an `"enabled": true|false` default in each `.json`.
3. **Suppression comments.** Support `// drag-lint:ignore[ <rule-id>]` (line-level) and a file-level
   `{ drag-lint:disable <rule-id> }` — parity with FixInsight's `//FI:` and Sonar's `// NOSONAR`.
4. **SARIF output** (`--format sarif`) for CI, alongside the existing JSON/text. The newest OSS Delphi
   analyzers ship SARIF; it unlocks GitHub code-scanning.
5. **A real lint test harness.** `tests\lint\` with paired `*.pas` fixtures + `*.expected.json`
   (rule-id + line) and a `run_lint_tests.ps1` that runs `drag-lint lint <fixture> --json` and diffs.
   This is the TDD substrate for every rule below (write the `.expected` first → red → green).

---

## 4. Prioritized build order

### Wave 1 — high-signal `.scm` rules (no recompile, ship-safe) 🔜
Each is one `.scm`+`.json`, with a fixture + expected-findings test written first.

| # | rule id | detects | sev | tier | FP risk |
|---|---|---|---|---|---|
| 1 | `empty-except` | `except ... end` with no statements (swallows all) | warning | T1 | very low |
| 2 | `empty-finally` | empty `finally` block | warning | T1 | very low |
| 3 | `empty-then` / `empty-else` | `then;` / `else;` no-op branch | warning | T1 | low |
| 4 | `raise-bare-exception` | `raise Exception.Create(...)` (root class) | warning | T1 | low |
| 5 | `reraise-loses-stack` | `raise E;` re-raising the caught instance | warning | T1 | low |
| 6 | `bare-except` | `except` not followed by `on` (catch-all) | info | T1 | medium |
| 7 | `off-by-one-count` | `for .. to X.Count do` / `to Length(..)` (missing `-1`) | warning | T1 | low |
| 8 | `boolean-literal-compare` | `= True` / `<> False` etc. (refine existing `boolean-comparison-true`) | info | T1 | low |
| 9 | `empty-method-body` | routine `begin end` with no statements (non-virtual) | info | T2 | low |
| 10 | `nil-comparison` | `X = nil` / `X <> nil` (prefer `Assigned(X)`) | info | T1 | medium |
| 11 | `assert-without-message` | `Assert(expr)` single-arg | info | T1 | low |
| 12 | `inherited-then-nothing` | override body is only `inherited;` | info | T2 | low |
| 13 | `address-of-string-char` | `@S[1]`/`@S[0]` (use `PChar`) | warning | T1 | low |
| 14 | `todo-marker` | TODO/FIXME/HACK/XXX/BUG in comments (refine existing) | info | T1 | none |
| 15 | `multiple-statements-per-line` | `;`-separated statements on one line | info | T1 | medium |

### Wave 2 — Pascal built-ins on the AST (scope/flow) 🔜
Rebuild Win64; each gets a `DoSelfTest<Rule>` mirroring `DoSelfTestUnusedLocals`.

| # | rule id | detects | sev | tier |
|---|---|---|---|---|
| 16 | `code-after-exit` | statements after unconditional `Exit`/`raise`/`Break`/`Continue`/`Halt` | warning | T3 |
| 17 | `raise-in-finally` | `raise` inside a `finally` block | warning | T3 |
| 18 | `swallowed-exception` | `except` that neither re-raises nor calls a logger | warning | T3 |
| 19 | `missing-inherited-ctor` | constructor override w/o `inherited` | warning | T3 |
| 20 | `missing-inherited-dtor` | destructor w/o `inherited` | warning | T3 |
| 21 | `create-inside-try` | `TFoo.Create` as first statement inside `try` (use create-before-try) | warning | T3 |
| 22 | `self-assignment` | `X := X` (field/var to itself) | warning | T3 |
| 23 | `redundant-assigned-free` | `if Assigned(X) then X.Free` (guard redundant) | info | T3 |

### Wave 3 — index/refs differentiators (the moat) 🔜🧱
Pascal built-ins using `ISymbolStore`. Highest unique value; medium effort.

| # | rule id | detects | sev | tier |
|---|---|---|---|---|
| 24 | `unused-unit-in-uses` | uses-clause entry with zero refs to its symbols (resolved) | warning | T4 |
| 25 | `unused-private-member` | private field/method/property, ref-count 0 in unit | warning | T4 |
| 26 | `write-only-field` | field with only `write` refs, never `read` | warning | T4 |
| 27 | `unused-public-symbol` | public symbol with no callers/refs across the whole index | info | T4 |
| 28 | `deep-inheritance` | ancestry depth > N (CK DIT) | info | T4 |
| 29 | `too-many-parameters` | routine param count > N (from signature) | info | T4 |
| 30 | `god-class` | class with #methods>M ∧ #fields>F ∧ fan-out>D | info | T4 |
| 31 | `layering-violation` | unit in layer X uses a unit in a forbidden layer (config DAG over `unit_uses`) | warning | T4 |

### Wave 4 — security + DFM (the neglected niche) 🔜
| # | rule id | detects | sev | tier |
|---|---|---|---|---|
| 32 | `sql-string-concat` | SQL keyword literal (`SELECT`/`WHERE`/…) joined with `+` to a variable | warning | T2 |
| 33 | `hardcoded-secret` | string literal assigned to ident matching `passw|secret|key|token|pwd` | warning | T2 |
| 34 | `format-arg-count` | `Format('...%s...', [..])` specifier count ≠ array length | warning | T2 |
| 35 | `dfm-hardcoded-credential` | password/connection-string property value in `.dfm` (DFM-aware) | warning | T3 |

### Wave 5 — 🔬 type-aware (after a type-resolution milestone)
Float `=` comparison · Ansi/Unicode lossy cast · FreeAndNil-on-interface · stream-not-freed ·
non-linear cast · locale Date/Str overloads · FireDAC API-sequence · interface ref-cycles ·
UI-thread violations · nullability. These are the semantic frontier from Report 1 §8 — large,
high-value, and the long-term differentiator; they require type/hierarchy resolution first and are
**out of scope for the immediate autonomous build**, documented here so the path is clear.

---

## 5. Per-rule contract (every rule, both paths)

- **TDD/CDD first:** write the fixture (`tests\lint\<rule>.pas`) and `<rule>.expected.json` (rule-id +
  line) **before** the rule; confirm red; implement; confirm green. For Path B also add a `DoSelfTest`.
- **DocInsight `///`** on any new public Pascal declaration; rationale comment block at the top of each `.scm`.
- **Encoding:** `.pas` strict 7-bit ASCII + CRLF, no BOM; `.scm`/`.json` may be UTF-8 but keep messages ASCII.
- **Severity vocabulary:** `info` / `warning` / `error` (+ `hint`), matching the plugin/LSP mapping.
- **Low false positives:** since `.scm` rules currently can't be disabled, ship only confident rules in
  Path A until §3.2 (selectability) lands; park anything noisy behind a default-off `"enabled": false`.

---

## 6. What I am implementing now (this autonomous session)

Order chosen for **safety + value under unattended execution** (Path A first — no build risk):

1. **Infra:** lint test harness `tests\lint\` + `run_lint_tests.ps1` (§3.5); fix `rules\` deploy (§3.1).
2. **Wave 1** `.scm` rules #1–#15, each TDD'd via the harness.
3. **Wave 2** Pascal built-ins #16–#23 (rebuild Win64, self-tests) — if the build stays green.
4. Begin **Wave 3** index rules #24–#27 as time allows.
5. Document progress in this file's changelog and commit each rule separately.

Waves 4–5 and infra items §3.2–3.4 (selectability, suppression, SARIF) are queued for review when
the user is back, since they touch the CLI surface and FP policy.

---

## 7. Changelog (implementation progress)

_(updated as rules land)_

- 2026-06-21 — Reports 1 & 2 written. Beginning infra + Wave 1.
- 2026-06-21 — Lint test harness added (`tests/lint/` + `run_lint_tests.ps1`, TDD: fixture +
  `.expected` per rule). **Wave 1 landed (8 new `.scm` rules, all TDD-green, 11/11 harness tests):**
  `empty-except`, `empty-finally`, `bare-except`, `empty-conditional`, `raise-bare-exception`,
  `reraise-loses-stack`, `off-by-one-count`, `nil-comparison`. Refined existing: `boolean-comparison-true`
  (+`<>`), `assert-call` (single-arg only), `compiler-magic-comments` (+`BUG`).
  Engine note: tree-sitter `.` anchors work for concrete node kinds (used for the empty-* rules) but
  an anchored `(_)` wildcard did NOT constrain child count — single-arg `Assert` instead uses a
  `#not-match? @args ","` text heuristic. Deploy: harness syncs `rules/` -> `<exe-dir>/rules`
  (gitignored); permanent in-exe deploy + `--rules-dir` flag + per-`.scm` selectability deferred to
  the Wave 2 CLI rebuild.
- 2026-06-21 — Wave 1 (cont.): 3 more near-zero-FP `.scm` rules (14/14 harness green):
  `not-in-precedence` (`not X in S` precedence bug -- real defect), `classname-string-compare`
  (W538: `X.ClassName = 'literal'`), `inline-assembly` (`asm` block, portability). **Total: 11 new
  rules this session.** Next: Wave 2 Pascal built-ins (need a Win64 rebuild + self-tests) and the
  rules-dir deploy/`--rules-dir`/selectability infra (same rebuild).
- 2026-06-21 — **Wave 2 started: first Pascal built-in `raise-in-finally`** (#17) -- a real bug the
  `.scm` engine can't express (needs a finally-subtree walk that stops at nested `try`). Added
  `TAstChecker.CheckRaiseInFinally` (DocInsight-documented), wired into `DoLint` and the `--rule`
  allow-list; Win64 Release rebuilt (clean) + redeployed to `third_party/dll-win64/`. Harness 16/16
  (fixture asserts fire-in-finally + no-fire-in-try-body). Confirmed no regression
  (`selftest unused-locals` PASS). The canonical exe is gitignored (ships via the release zip, not
  git), so only source is committed; a release rebuild will carry the rule to users.
  **Session total: 13 new rules (12 `.scm` + 1 built-in).**
