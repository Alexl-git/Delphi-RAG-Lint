# drag-lint Linter -- Backlog & Resume Point

> Saved 2026-06-21 before a session reset. Companion docs:
> [REPORT-1-delphi-lint-landscape.md](REPORT-1-delphi-lint-landscape.md) (the field),
> [REPORT-2-draglint-implementation-plan.md](REPORT-2-draglint-implementation-plan.md) (the plan + changelog).
> This file = what is DONE, how to resume, and what is NOT done yet (ideas/plans).

---

## 1. Status (what shipped)

**10 GitHub releases, v0.47.0-alpha .. v0.56.0-alpha (each "Latest"), all on `main`.** ~53 distinct
lint rule ids. Harness `tests/lint/run_lint_tests.ps1` = **51 fixtures green**; `selftest unused-locals`
PASS. Win64+Win32 zips bundle the `rules/` folder + `INSTALL.md` (self-contained).

Categories covered: bug-patterns (empty/bare except, raise-bare/reraise/raise-in-finally,
off-by-one, not-in/not-comparison precedence, comparison-same-operands, division-by-zero,
self-assignment, code-after-exit, nil/boolean/classname compares, redundant-not-not, empty-conditional/
loop/case), resource+lifetime (unprotected-object-free, use-after-free, freeandnil-on-interface,
missing-inherited-ctor/dtor, control-flow-in-finally, **interface-reference-cycle** ARC),
concurrency (**ui-access-in-thread**), security (sql-injection-concat, hardcoded credential/
connection-string/ip/path), platform (win64-pointer-cast, locale-sensitive-conversion, float-equality
incl. TDateTime, gettickcount-wraparound, inline-assembly), complexity/structure (too-many-parameters/
locals, method-too-long, deep-nesting, god-class, public-field, with-multiple-items, **layering-violation**
config-driven, unused-public-symbol), FireDAC (firedac-open-execsql-mismatch), plus assert-call,
uppercase-compare, outputdebugstring, length-zero-compare, magic numbers, etc.

Infra: `// drag-lint:ignore [rule...]` suppression; `lint --disable id1,id2`; `lint --rules-dir <dir>`;
`lint-project --db <idx> [--layers <json>]` (project-wide rules); bundled `rules/`; `build/pack-lint-release.ps1`.

---

## 2. Resume point (start here next session)

- Repo `C:\Projects\Delphi-RAG-lint`, branch **`main`** (single branch; the feature branch was merged + deleted).
- **Two rule engines:** (A) external `.scm`+`.json` in `rules\` (hot-loaded, no recompile); (B) Pascal
  built-ins in `src\diagnostics\DRagLint.Diagnostics.AstChecks.pas` (class `TAstChecker`) + project-wide
  rules in `src\lint\DRagLint.Lint.ProjectRules.pas`.
- **Add a `.scm` rule:** drop `rules\<id>.scm` + `<id>.json`; add `tests\lint\<id>.pas` + `<id>.expected`;
  run `pwsh tests\lint\run_lint_tests.ps1`. No rebuild.
- **Add a built-in:** new `class function TAstChecker.CheckXxx(const AFile): TArray<TLintFinding>` (copy an
  existing one's parse boilerplate); wire one line in `DoLint` (CLI ~line 3979+) + add the id to the
  `--rule` allow-list (CLI, the `unknown rule` guard) + its message; add a `tests\lint` fixture; rebuild.
- **Add a project rule:** extend `TProjectLintRules` (Store-based) or call a `TAstChecker` file-list fn
  from `DoLintProject`; test via `tests\lint-project\` (index a fixture, run `lint-project --db`).
- **Build (Win64 Release):** `build\pack-lint-release.ps1 -Version X` builds win64+win32, deploys the win64
  exe to `third_party\dll-win64`, and zips with `rules\`. (Or plain msbuild; ~7s.)
- **Release:** bump `VERSION` const (CLI.pas line 6), CHANGELOG top entry, `rules\README.md`; commit; push;
  `git tag vX` ; `gh release create vX --repo Alexl-git/Delphi-RAG-Lint --latest --notes-file ... <zips>`.
- **CRITICAL gotchas:** Edit/Write emit LF -> **normalize touched `.pas` to CRLF** before commit
  (`(t -replace "\r\n","\n") -replace "\n","\r\n"`, UTF8-no-BOM); strict 7-bit ASCII; DocInsight `///` on
  new public decls. A NEW unit must be added to BOTH the `.dpr` `uses ... in '..'` AND the `.dproj`
  `<DCCReference>` (the .dpr uses is what the compiler resolves; missing it = F2613). The canonical
  `third_party\dll-win64\drag-lint.exe` is gitignored (ships via release zip, not git).
- **tree-sitter node kinds:** discover via `C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse <f>`.
  Key: a NO-paren call (`X.Open`, `GetTickCount`) is `exprDot`/`identifier`, NOT `exprCall`; anon method =
  `lambda`; `if`(no else) vs `ifElse`; `TFoo.Create` no-paren = `exprDot`. `.` anchors work for concrete
  node kinds but an anchored `(_)` wildcard does NOT constrain child count.

---

## 3. Big-ticket NOT done: a cross-unit type resolver

The single largest remaining investment. Several shipped rules are HEURISTIC because there is no real
type resolution: `float-equality-comparison`, `win64-pointer-cast`, `freeandnil-on-interface` use a
flat per-file name->type map (string prefixes), and `interface-reference-cycle` uses the I-prefix
convention. A resolver would make them EXACT and unlock new precise rules.

**Plan (multi-step, each could be its own release):**
1. Expose a symbol's resolved declared type from the index (the `symbols` table has `signature`; the
   `unit_uses` graph gives scope). Add an `ISymbolStore` query: given a unit + identifier, return its
   declared type, and given a type name, return its kind (class/interface/enum/record/alias) + ancestry.
2. Build a per-routine scope chain (locals -> params -> fields -> unit-level -> used-units) so an
   identifier resolves to a symbol -> type. (Today's flat map ignores scope/shadowing.)
3. Resolve type ancestry (class parent chain, implemented interfaces) cross-unit -> makes
   interface-reference-cycle exact (no I-prefix guess) and enables `non-linear-cast` (hard cast between
   unrelated classes), `redundant-cast` (X already that type), exact Ansi/Unicode lossy cast.
4. Rewrite the heuristic rules to use the resolver; add the new exact rules above + `exhaustive-enum-case`
   (case over an enum missing values -- needs enum member count), `stringlist-duplicates-unsorted`,
   `format-argument-type-mismatch`.

This is infrastructure first; budget it as a milestone, not a single rule.

---

## 4. Rule-idea backlog (no type resolver needed -- "more small batches")

Detectable from AST / index today; pick batches of these:

- **FireDAC:** `parambyname-in-loop` (extend the existing `field-by-name-in-loop` walk to `.ParamByName`);
  `dataset-open-without-close` (Open/Connected:=True without try-finally Close -- flow-ish);
  `query-created-without-owner-never-freed` (flow); `fetchall-on-large` (low signal).
- **Resource:** `stream-not-freed` / `criticalsection-not-released` / `file-not-closed` (Enter/Leave,
  FileOpen/CloseFile pairing per routine, like CheckUnprotectedFree); `double-free` (X.Free twice).
- **Security:** `unsanitized-shellexecute` (ShellExecute/CreateProcess/WinExec with a non-literal arg);
  `weak-random-for-security` (Random near token/password identifiers); `unsafe-string-api`
  (StrCopy/StrCat/StrPCopy -- unbounded); `path-traversal` (file API with concatenated path var).
- **Control-flow / expr:** `constant-condition` (`if True`/`while False`); `loop-executes-at-most-once`
  (unconditional Exit/Break/raise in a loop body); `ifthen-both-branches` (SysUtils.IfThen evaluates both
  args -- a pitfall); `assignment-result-ignored` (function called as a statement).
- **Maintainability:** `commented-out-code` (comment that parses as Pascal -- info, FP-prone);
  `duplicated-code` / clones (token-hash across impl ranges); `magic-string`; `multiple-statements-per-line`
  (needs same-line sibling detection -> built-in).
- **Metrics:** `cyclomatic-complexity` / `cognitive-complexity` (count decision points incl. and/or in a
  routine body -- verify `kAnd`/`kOr` node names first); `too-many-nested-routines`; `too-many-exit-points`.
- **Platform:** `pchar-arithmetic`; `variant-record-type-punning`; `deprecated-rtl-function` (StrCopy, Str/Val,
  GetMem-without-FreeMem); `sizeof-pointer-assumption` (`SizeOf(Pointer) = 4`).
- **Naming (low-FP subset already partly covered):** `field-not-f-prefixed`, `class-not-t-prefixed`,
  `interface-not-i-prefixed`, `exception-not-e-prefixed`, `param-prefix`, `unit-name-mismatch-file`
  (needs unit name vs filename) -- ship OFF-by-default or as a separate "conventions" profile to avoid noise.

---

## 5. Infra / UX backlog (high adoption value)

- **SARIF output** (`--format sarif`) for GitHub code-scanning / CI. (JSON + text exist.)
- **Per-`.scm` enable/disable**: honor `"enabled": false` in each `.json` + `--enable <id>` (today only
  `--disable` exists; `.scm` rules otherwise always run). Lets naming/style rules ship off-by-default.
- **Persistent config file** `drag-lint-lint.json` (CWD): `{ "disabled":[...], "enabled":[...],
  "thresholds": { "too-many-parameters": 7, ... }, "severity": { "<id>":"warning" } }`. Today thresholds
  are hardcoded conservative defaults; `--disable` is per-run only.
- **IDE-plugin deploy of `rules\`**: confirm the OTAPI plugin ships/points `rules\` beside the spawned exe
  (or passes `--rules-dir`); otherwise `.scm` rules are dormant in the IDE.
- **Quick-fixes / autofix** (the SonarDelphi/DelphiLint differentiator): e.g. `Assigned(X)` for `X <> nil`,
  remove redundant `as TObject`, `- 1` for off-by-one, `SameText` for uppercase-compare.
- **Baseline / suppression file** (ignore the existing N findings; only flag new ones) for adoption on
  large legacy codebases.
- **CI exit-code policy** by severity (fail build on `error`/`warning` but not `info`).
- **A unified test runner** that also exercises the `lint-project` rules (index a fixture + assert) -- today
  those are manual (`tests/lint-project/README.md`).

---

## 6. Pointers

- Rule list (user-facing): `rules/README.md`. Per-file harness: `tests/lint/`. Project-rule fixtures:
  `tests/lint-project/`. Release script: `build/pack-lint-release.ps1`.
- The two research reports (landscape + plan) sit beside this file in `docs/lint/`.
