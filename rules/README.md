# External Lint Rules

Drop tree-sitter S-expression query files here. `drag-lint lint` loads every
`*.scm` from this directory on startup, compiles each against the Delphi 13
grammar, and runs all of them against every file. Match captures produce
`TLintFinding` rows.

## The rule catalog (`drag-lint rules`)

`drag-lint rules` is the single machine-readable source of truth for every rule --
built-in and external `.scm`:

```
drag-lint rules                       # grouped text table + a "N rules across M categories" header
drag-lint rules --json                # structured catalog: [{id,category,title,default_severity,default_enabled,source,params}] + summary
drag-lint rules --category naming      # only one category
drag-lint rules --rules-dir <dir>      # point at a specific rules folder (default <exe-dir>\rules)
```

Built-in rules carry their category/severity/params from an in-code registry
(`DRagLint.Lint.RuleCatalog`); external `.scm` rules contribute id/severity/message
from their sidecar `.json`. This command replaces the hand-maintained rule tables
below as the canonical inventory.

## Rule files

Each rule is a pair:

- `<name>.scm` — the tree-sitter query
- `<name>.json` — optional metadata

If the `.json` is missing, defaults apply (severity = "warning", message =
the rule id, warn capture name = `warn`).

### .json schema

```json
{
  "id": "rule-id",
  "severity": "info | warning | error",
  "message": "Human-readable message printed with each finding.",
  "warn_capture": "name-of-the-capture-to-pin-the-finding-to",
  "enabled": false,
  "exclude_if_ancestor": ["declConst"],
  "require_ancestor": ["for", "while", "repeat"],
  "require_file_text": ["vcl.", "{$r *.dfm}"]
}
```

| key | default | meaning |
|---|---|---|
| `id` | the `.scm` file name | Rule id, as reported and as written in a `dl:ok` marker. |
| `severity` | `warning` | `info` / `warning` / `error`. |
| `message` | the rule id | Printed with each finding. |
| `warn_capture` | `warn` | Which capture the finding is pinned to. |
| `enabled` | `true` | `false` ships the rule OFF; `--enable <id>` turns it back on. |
| `exclude_if_ancestor` | none | Node kinds; a match is DROPPED when the picked node has an ancestor of any listed kind. |
| `require_ancestor` | none | Node kinds; a match COUNTS ONLY inside one of them. |
| `require_file_text` | none | Substrings; the rule does not run at all against a file whose text contains NONE of them. Case-insensitive, matched against the whole file. |

If `warn_capture` is omitted (or no capture by that name is present in a
match), the finding is pinned to the **first** capture in the match.

**Ancestor keys are STRUCTURE; `require_file_text` is SCOPE.** A tree-sitter
pattern matches a subtree shape and cannot ask "has some ancestor of kind K",
which is what the two ancestor keys are for -- `concat-in-loop` names the three
loop kinds so `S := S + X` executed once is not reported as quadratic.
`require_file_text` answers a different question: whether the rule is
MEANINGFUL in this file at all. `sleep-in-vcl` requires `vcl.` or `{$r *.dfm}`,
because a headless console or test unit has no UI to freeze -- unscoped it fired
11 times in one DUnitX unit whose uses clause names no VCL unit.

Do not confuse `require_file_text` with the internal literal pre-filter, which
is DERIVED from the query as an optimisation and is not settable here.

### .scm format

Standard tree-sitter S-expression query syntax. Captures use `@name`.

```
((exprCall
  entity: (identifier) @callee) @warn)
```

### Supported predicates (v0.3)

The runner evaluates these standard tree-sitter predicates:

| Predicate | Meaning |
|---|---|
| `#eq? @cap "lit"` / `#not-eq?` | Capture text equals the literal |
| `#eq? @c1 @c2` / `#not-eq?` | Two captures have identical text |
| `#match? @cap "re"` / `#not-match?` | Capture text matches the regex (TRegEx) |
| `#any-of? @cap "a" "b" ...` / `#not-any-of?` | Capture text equals any of the listed |

Unknown predicates pass through (don't suppress) so future tree-sitter
extensions don't silently filter matches.

## Suppressing a finding

Put a line comment on the offending source line:

- `// drag-lint:ignore` -- silence **all** rules on that line.
- `// drag-lint:ignore <rule-id> [<rule-id> ...]` -- silence only those rule ids.

Works for both external `.scm` rules and the built-in checks.

## Shipped rules (v0.28)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `writeln-in-source` | info | Direct `WriteLn` call — use a logger |
| `goto-statement` | warning | `goto` statement is generally considered harmful |
| `with-statement` | info | `with` statement makes symbol scope ambiguous |
| `empty-procedure-body` | info | Empty `procedure`/`function` body (begin..end with no statements) |
| `large-magic-number` | info | Numeric literal not in the common-constants allow-list |
| `string-equality-comparison` | info | `=` comparison on expressions — fires on all `=` binary expressions until type-resolution is plumbed in (v0.19+) |

## Shipped rules (v0.31)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `parser-error` | error | Tree-sitter `ERROR` node — malformed syntax that the parser could not recover |

## Shipped rules (v0.32)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `compiler-magic-comments` | info | Comment contains TODO/FIXME/HACK/XXX — track in issue tracker |
| `nested-with` | warning | Nested `with` statement — scope becomes highly ambiguous |
| `assert-call` | info | `Assert()` call — ensure the second argument provides a descriptive message |
| `case-magic-numbers` | info | `case` label is an integer literal — consider naming the constant |

## Shipped rules (v0.35)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `boolean-comparison-true` | info | `X = True` or `X = False` -- redundant boolean comparison |
| `redundant-as-tobject` | info | `(X as TObject)` -- every Delphi object is already a TObject |
| `inherited-bare` | info | Bare `inherited;` call -- verify it invokes the intended ancestor method |

## Shipped rules (v0.47 -- lint expansion, Wave 1)

New high-signal, low-false-positive rules (see `docs/lint/REPORT-2-draglint-implementation-plan.md`).
Each has a TDD fixture under `tests/lint/` verified by `tests/lint/run_lint_tests.ps1`.

| Rule id | Severity | Description |
|---------|----------|-------------|
| `empty-except` | warning | Empty `except` block silently swallows every exception |
| `empty-on-handler` | warning | `on E: ... do ;` -- empty exception handler swallows that exception |
| `empty-finally` | warning | Empty `finally` block does nothing |
| `bare-except` | info | `except` with no `on E: ... do` clause catches everything (incl. EOutOfMemory) |
| `empty-conditional` | warning | Empty `then`/`else` branch -- stray `;` after `then`/`else` |
| `raise-bare-exception` | warning | `raise Exception.Create(...)` raises the root class -- use a subclass |
| `reraise-loses-stack` | warning | `raise E;` resets the stack trace -- use a bare `raise;` |
| `off-by-one-count` | warning | `for I := 0 to X.Count/Length(X)` runs one past the end |
| `nil-comparison` | info | Prefer `Assigned(X)` over `X = nil` / `X <> nil` |
| `not-in-precedence` | warning | `not X in S` parses as `(not X) in S` -- write `not (X in S)` |
| `classname-string-compare` | warning | `X.ClassName = 'TFoo'` is fragile -- use `is` / `InheritsFrom` |
| `inline-assembly` | info | `asm ... end` block -- not portable across platforms |
| `self-assignment` | warning | `X := X` is a no-op self-assignment -- likely a copy-paste error |
| `with-multiple-items` | warning | `with A, B do` -- multiple objects make name resolution highly ambiguous |
| `empty-loop-body` | warning | `while/for ... do ;` or `repeat until` with no body -- stray `;` or busy-wait |
| `redundant-assigned-free` | info | `if Assigned(X) then X.Free` -- guard redundant (Free/FreeAndNil handle nil) |
| `sql-injection-concat` | warning | SQL string literal concatenated with a variable -- injection risk (CWE-89) |
| `hardcoded-credential` | warning | secret-named variable OR const set to a string literal -- hardcoded credential (CWE-798) |
| `comparison-same-operands` | warning | `X = X` / `X < X` -- both operands identical, result is constant (likely a typo) |
| `division-by-zero-literal` | warning | `X div 0` / `X / 0` / `X mod 0` -- always raises a runtime division error |
| `empty-case-branch` | info | `1: ;` -- case branch with a label but no statement |
| `not-comparison-precedence` | warning | `not A = B` parses as `(not A) = B` -- write `not (A = B)` |
| `redundant-not-not` | info | `not not X` -- redundant double negation, simplify to `X` |
| `public-field` | info | public data field on a class -- breaks encapsulation; use a property |
| `locale-sensitive-conversion` | warning | `StrToFloat`/`FloatToStr`/`StrToDate`/... without a `TFormatSettings` |
| `uppercase-compare` | warning | `UpperCase(X) = 'literal'` -- fragile/slow; use `SameText` |
| `outputdebugstring` | info | `OutputDebugString` debug tracing left in code |
| `length-zero-compare` | info | `Length(X) = 0` / `> 0` -- prefer `X = ''` for strings |
| `hardcoded-connection-string` | warning | string literal with connection-string keywords (CWE-798) |
| `gettickcount-wraparound` | warning | `GetTickCount` wraps after ~49.7 days -- use `GetTickCount64` |
| `hardcoded-ip-address` | info | string literal that is an IPv4 address |

Refined existing rules: `boolean-comparison-true` now also matches `<> True`/`<> False`;
`assert-call` now fires only on single-argument `Assert` (no message); `compiler-magic-comments`
also matches `BUG`.

## Shipped rules (v0.62 -- Phase 1, pure `.scm`)

Nine new query-only rules -- no exe rebuild is needed to add a `.scm` rule. Each
has a TDD fixture under `tests/lint/` verified by `tests/lint/run_lint_tests.ps1`.

| Rule id | Severity | Description |
|---------|----------|-------------|
| `unsafe-string-api` | warning | Calls to `StrCopy`/`StrCat`/`StrPCopy`/`StrMove`/`StrPos`/`StrLen` -- unbounded PChar routines |
| `deprecated-rtl-function` | info | `OemToAnsi`/`AnsiToOem`/`StrPas` -- obsolete RTL routines |
| `sleep-in-vcl` | warning | `Sleep()` on the main thread freezes the VCL UI |
| `constant-condition` | warning | `if True`/`if False`/`while False` -- always-constant condition (`while True` is left alone) |
| `ifthen-both-branches` | warning | `SysUtils.IfThen` evaluates both branches unconditionally -- does NOT fire when both branches are literal (string/number/`True`/`False`/`nil`); a plain identifier argument still fires (parenless-call ambiguity, see Task 9b) |
| `sizeof-pointer-assumption` | warning | `SizeOf(Pointer) = 4`/`8` bakes in a platform assumption |
| `pchar-arithmetic` | warning | `+`/`-` on a PChar-named variable -- unsafe pointer arithmetic |
| `boolean-result-returned-directly` | info | redundant `if/else` assigning `True`/`False` to `Result` |
| `concat-in-loop` | info | `S := S + X` self-concatenation is O(n^2) |

## Shipped rules (v0.63 -- Phase 2, built-ins)

Eleven new built-in (`TAstChecker`) rules -- compiled into the exe, no `.scm`/`.json`.
Each has a TDD fixture under `tests/lint/` verified by `tests/lint/run_lint_tests.ps1`.

| Rule id | Severity | Description |
|---------|----------|-------------|
| `unsafe-shellexecute` | error | `WinExec`/`ShellExecute`/`CreateProcess` with a non-literal command (CWE-78) |
| `path-traversal` | warning | concatenated path to `AssignFile`/`FileOpen`/`CreateFile`/`TFile.Open` (CWE-22) |
| `loop-executes-at-most-once` | warning | `for`/`while`/`repeat` whose first body statement is `Exit`/`Break`/`raise` |
| `format-argument-count` | error | `Format` specifier count != argument count |
| `format-specifier-type-mismatch` | error | literal `Format` argument type incompatible with its specifier |
| `try-except-swallowed` | warning | `try..except` with no raise/log/`HandleException` |
| `dataset-open-without-close` | warning | dataset opened without a matching `Close` in a `finally` |
| `criticalsection-not-released` | error | lock `Enter`/`Acquire` without a `finally` `Leave`/`Release` |
| `too-many-exit-points` | info | routine with more than 5 `Exit` statements |
| `cyclomatic-complexity` | info | routine decision-point count over 15 |
| `virtual-method-in-constructor` | warning | constructor calls a `virtual`/`dynamic`/`override` method of its own class |
| `used-before-assignment` | warning/info | unmanaged local read before assignment (warning = on every path; info = on some path) |
| `function-result-not-set` | warning/info | function `Result` not assigned (warning = never; info = not on every path) |
| `out-param-not-set` | warning/info | `out` parameter not assigned on every path |
| `overwrite-before-read` | info | local assigned then overwritten/discarded before any read (dead store) |
| `write-only-local` | info | local assigned at least once but never read |
| `loop-var-after-loop` | warning | a `for` loop control variable is read after the loop (value undefined) |
| `object-leak` | info | a local object created via a constructor is neither freed nor transferred on some path |

### Built-in rules (compiled into the exe, not `.scm`)

Some rules need scope/flow analysis a single tree-sitter query can't express, so they live in
Pascal (`src/diagnostics/DRagLint.Diagnostics.AstChecks.pas`) and run from `drag-lint lint <file>`
(single `.pas`/`.inc`): `unused-local` (H2164), `syntax-error`, `unbalanced-begin-end`,
`undeclared-identifier` (needs `--db`), and -- new in v0.47:
- **`raise-in-finally`** (warning): a `raise` inside a `finally` masks the in-flight exception
  (walks the finally subtree, not descending into nested `try`).
- **`code-after-exit`** (warning): unreachable statement directly after an unconditional
  `Exit`/`raise`/`Break`/`Continue`/`Halt` (same statement list; a terminator nested in an if/case
  does not flag code after the if/case).
- **`missing-inherited-ctor`** / **`missing-inherited-dtor`** (warning): a constructor/destructor whose
  body never calls `inherited` (skips ancestor init/cleanup). Class ctors/dtors and asm bodies skipped.
- **`control-flow-in-finally`** (warning): `Exit`/`Break`/`Continue`/`Halt` inside a `finally` block
  silently discards the in-flight exception (companion to `raise-in-finally`).
- **`too-many-parameters`** / **`too-many-locals`** / **`method-too-long`** / **`deep-nesting`** (info):
  routine size/complexity metrics with conservative defaults (params > 7, locals > 25, body > 120
  lines, nesting > 5). Use `--disable <id>` to turn any off.

- **`float-equality-comparison`** (warning) / **`freeandnil-on-interface`** (warning): type-aware
  checks using a lightweight per-file name-to-type map (`=`/`<>` on float operands; `FreeAndNil`
  on an interface-typed variable).
- **`firedac-open-execsql-mismatch`** (warning): `Open` on a DML statement or `ExecSQL` on a SELECT
  (correlates a literal `X.SQL.Text := '...'` with a later `X.Open`/`X.ExecSQL` on the same variable).
- **`unprotected-object-free`** (warning): a locally-created object freed without `try-finally`
  (leaks if code between creation and `Free`/`FreeAndNil` raises).
- **`use-after-free`** (warning): use of an object after a raw `X.Free` (dangling reference) before
  `X` is reassigned (block-scoped; `FreeAndNil` clears tracking).
- **`win64-pointer-cast`** (warning): a 32-bit cast (`Integer`/`Cardinal`/...) of a pointer-typed
  value -- truncates on Win64; use `NativeInt`/`NativeUInt`.
- **`ui-access-in-thread`** (warning): VCL/FMX UI access (`.Caption :=`, `.SetFocus`, ...) inside a
  `TThread.Execute` not wrapped in `Synchronize`/`Queue` -- VCL/FMX is not thread-safe.

Index-wide rules (need `--db`, run via `drag-lint lint-project`): **`god-class`**, **`unused-public-symbol`**,
**`interface-reference-cycle`** (class A holds an interface implemented by B and vice-versa -- ARC leak;
mark one side `[weak]`/`[unsafe]`), **`layering-violation`** (config-driven architecture enforcement via
`--layers <file.json>` -- flags forbidden cross-layer `uses`; see CHANGELOG for the config shape).

Plus `field-by-name-in-loop` and `inline-comment-in-multiline-args` from the linter core, and
`unit-not-in-dpr` (project check).

### Tip

If you want to discover what AST nodes look like for a fragment of Delphi
code, run the tree-sitter CLI on a sample file:

```cmd
C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe parse path\to\sample.pas
```

Use that output to write your query.

## CI / output ergonomics (v0.66)

`lint`, `lint-all`, and `check-ast` share an output tail:

- `--format sarif` -- SARIF 2.1.0 to stdout (alongside the existing `text` / `json`/`--json`).
- `--fail-on error|warning|info|none` -- process exits nonzero iff a surviving finding is at/above that level; `none` always exits 0. Absent => the historic exit code (1 if any finding).
- `--baseline <file>` -- report only findings NOT in the baseline. `--write-baseline <file>` records the current findings and exits 0. Fingerprints are line-shift stable (rule + path + hashed source-line text), so inserting unrelated lines does not re-surface a baselined finding.

  Note: `--baseline` filters which findings are *reported*, but on its own it does not change the exit code -- `lint --baseline X` still exits non-zero whenever the file had any findings (you'll see "0 finding(s)" yet a non-zero exit). For a CI gate that fails only on NEW findings, pair them: `lint --baseline X --fail-on warning` (or your chosen level) -- `--fail-on` ranks the post-baseline survivors (the new findings).

- Config file `drag-lint-lint.json` (auto-discovered in CWD, or `--config <path>`):

  ```json
  {
    "disabled":  ["rule-id"],
    "enabled":   ["rule-id"],
    "severity":  { "rule-id": "error|warning|info|hint" },
    "thresholds":{ "too-many-parameters": 7, "too-many-locals": 25,
                   "method-too-long": 120, "deep-nesting": 5,
                   "cyclomatic-complexity": 15, "too-many-exit-points": 5 },
    "profiles":  { "ci": { "disabled": ["deep-nesting"], "enabled": [] } }
  }
  ```

  - `--enable id1,id2` and `--disable id1,id2` compose with the config.
  - `--profile <name>` merges a named profile's `disabled`/`enabled` over the top level.
  - A `.scm` rule whose sidecar `.json` has `"enabled": false` ships off-by-default; list its id under `enabled` (or `--enable`) to turn it on.
  - **From the IDE:** right-click a project node in the Project Manager and choose
    **"drag-lint: Project Rules..."** to open the drag-lint dock's Lint Options tab,
    scoped to that project's `drag-lint-lint.json` -- an alternative to hand-editing
    the file directly (both edit the same file; either way works).

With no config, no baseline, and no `--fail-on`, every command behaves exactly as before.

## Naming conventions (v0.68-0.69)

Nine config-driven naming rules (seven in v0.68, two in v0.69). All are `info` severity, enabled by
default, and run on the `lint <file>` path. They read conventions from the `naming`
block in `drag-lint-lint.json`; if no config file is present, built-in defaults apply.
Built-in defaults follow common Delphi conventions; tune the `naming` block per project.

### `naming` block schema (with built-in defaults)

```json
"naming": {
  "type_prefix":  { "class": "T", "exception": "E", "interface": "I", "pointer": "P" },
  "field_prefix": "F",
  "param_prefix": "",
  "method_case":  "PascalCase",
  "const_case":   ["PascalCase", "UPPER_CASE"],
  "local_case":   "PascalCase",
  "keyword_case": "lowercase",
  "min_identifier_len": 3,
  "hungarian_prefixes": ["lpsz", "psz", "sz", "lp", "int", "str", "dw", "b", "p", "n"],
  "short_identifier_check": false
}
```

**Field descriptions:**

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `type_prefix.class` | string | `"T"` | Required prefix for class type declarations |
| `type_prefix.exception` | string | `"E"` | Required prefix for exception class types (M1 ancestry check when DB present) |
| `type_prefix.interface` | string | `"I"` | Required prefix for interface type declarations |
| `type_prefix.pointer` | string | `"P"` | Required prefix for pointer type declarations |
| `field_prefix` | string | `"F"` | Required prefix for class instance fields |
| `param_prefix` | string | `""` | Prefix for routine parameters -- **empty = disabled by default**; set `"p"`, `"A"`, etc. to enable |
| `method_case` | string | `"PascalCase"` | Required casing for method/routine names |
| `const_case` | string or array | `["PascalCase","UPPER_CASE"]` | Allowed casing(s) for constants and enum members |
| `local_case` | string | `"PascalCase"` | Required casing for local variable names |
| `keyword_case` | string | `"lowercase"` | Required casing for reserved words; `""` disables `reserved-word-casing` |
| `min_identifier_len` | int | `3` | Shortest allowed identifier for `hungarian-or-short-identifier` |
| `hungarian_prefixes` | array | `["lpsz","psz","sz","lp","int","str","dw","b","p","n"]` | Type-prefix denylist for `hungarian-or-short-identifier` |
| `short_identifier_check` | bool | `false` | Master on/off for `hungarian-or-short-identifier` (**off by default**) |

Supported casing values: `"PascalCase"` | `"UPPER_CASE"` | `"camelCase"`.

**Disabling a single check:** set its value to `""` (string fields) or `[]` (array
fields). For example, to disable only the param-prefix check:

```json
"naming": {
  "param_prefix": ""
}
```

All other naming rules continue to use their defaults. To disable a naming rule
entirely by id, use the top-level `disabled` list:

```json
"disabled": ["param-name-prefix", "local-var-casing"]
```

### Shipped naming rules (v0.68-0.69)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `type-name-prefix` | info | Class/interface/pointer/exception type names must carry the configured prefix (`T`/`I`/`P`/`E`). Exception-class detection uses M1 ancestry when a DB is present; falls back to the `T` rule on the no-DB path. |
| `field-name-prefix` | info | Class instance field names must start with the configured prefix (`F`). Published/DFM-generated fields on form and frame classes are skipped. |
| `param-name-prefix` | info | Routine parameter names must start with the configured prefix. **Disabled by default** (`param_prefix: ""`); set a prefix like `"p"` or `"A"` to enable. Skips `Self`; override/interface-impl/event-handler/message-method parameters are also skipped (signature compatibility). |
| `method-pascalcase` | info | Method and free-routine names must be PascalCase (configurable via `method_case`). |
| `const-casing` | info | Declared constants and enum members must match one of the configured casing styles (default: `PascalCase` or `UPPER_CASE`). |
| `local-var-casing` | info | Local variable names must be PascalCase (configurable via `local_case`) and must not carry the field or param prefix (`FFoo`/`pFoo` as a local is a naming smell). |
| `unit-name-matches-file` | info | The `unit X;` identifier must equal the file's base name (case-insensitive on Windows). One finding per unit. |
| `reserved-word-casing` | info | Pascal reserved words / keywords must be written in lowercase (`begin`/`end`/`var`/...). **On by default** (`keyword_case: "lowercase"`); `True`/`False`/`nil` are convention-exempt. |
| `hungarian-or-short-identifier` | info | Parameter and local-variable names must not be overly short (< `min_identifier_len`) or use a Hungarian type prefix (`lpszName`, `intCount`). **Off by default** (`short_identifier_check: false`); loop counters `i`/`j`/`k`/`n`/`x`/`y` exempt. FP-prone -- opt in per project. |

### False-positive hardening (naming rules)

The naming rules include several guards that make them near-zero-FP on real Delphi,
VCL, and DevExpress code:

- **`type-name-prefix` / `field-name-prefix`**: accept the prefix followed by any
  letter, so `TfrmMain` (T + lowercase form convention), `FfID`, and DevExpress component
  types such as `TdxBarManager` / `TcxGrid` (T + lowercase) are recognized -- not flagged.
- **`field-name-prefix`**: auto-generated published DFM component fields on form/frame
  classes (the implicit-first section, any component type including DevExpress controls)
  are skipped; only fields in explicit `private`/`protected`/`public` sections are checked.
- **`method-pascalcase` / `local-var-casing`**: short all-caps abbreviations (`OK`,
  `ID`, `GLE`, `FF`, length <= 4) are exempt from the PascalCase requirement.
- **`method-pascalcase`**: methods in a `published` or implicit-first section (form event
  handlers such as `btnOkClick`) are skipped.
- **`unused-parameter`**: VCL/FMX event handlers -- a routine whose first parameter is
  `Sender` -- are skipped entirely (all params are signature-bound); plus the existing
  override / interface / message / asm / external / var / out guards.
- **`unit-name-matches-file`**: basename comparison is path-separator-robust (handles
  both `/` and `\`).
- **`reserved-word-casing`**: only keyword (`kXxx`) tokens are checked, never
  identifiers; symbol operators and the `True`/`False`/`nil` literals are exempt.
- **`hungarian-or-short-identifier`**: ships **off** (`short_identifier_check:
  false`); scoped to parameter and local-variable declarations only; loop-counter
  names `i`/`j`/`k`/`n`/`x`/`y` are exempt. Domain abbreviations and legitimate
  short names mean this rule is opt-in.
- **`unused-private-member`**: property getter/setter accessors and read/write-clause
  backing fields are excluded -- a property's `read GetX write SetX` accessors are not
  flagged as unused even though the index does not link them via the property clause.

### Known limitations (store-backed rules)

- **`unused-private-member`**: the index does not track all intra-class private
  method-to-method calls, so a private method called only by another method of the same
  class may still be reported (a residual false positive, shared with
  `unused-public-symbol`).
- **`unused-unit-in-uses`**: near-zero-FP by construction (it only over-credits
  references, so it never flags a genuinely-used unit), but a unit used ONLY for
  operator overloads, class/record helpers, or `initialization`/`finalization` side
  effects without a referenced symbol may be flagged unless it is in the built-in
  side-effect allow-list (which is intentionally small). Expand the allow-list or
  disable per-project if needed.

## Shipped rules (v0.68 -- dead/redundant-code tail)

Five new dead-code rules. Three run on the `lint <file>` path (AST/data-flow); two
run on the `lint-all --db` / `lint-project --db` path (store-backed). All are `warning`.

| Rule id | Severity | Path | Description |
|---------|----------|------|-------------|
| `unused-parameter` | warning | `lint <file>` | Parameter declared but never read in the routine body. Guards: skips `override`, interface-impl, event-handler-shaped (first param is `Sender`), `message`, `assembler`, and `external` routines; skips `out`/`var` parameters. |
| `identical-then-else` | warning | `lint <file>` | `if C then S1 else S2` where S1 and S2 are syntactically identical (normalized text). Real copy-paste bug -- result is the same regardless of the condition. |
| `referenced-never-set` | warning | `lint <file>` | A `private`/`strict private` class field with >= 1 read and 0 writes anywhere in the declaring unit. Field always holds its zero value. Guards: skips `published` fields, form/frame/`TComponent`-streamed classes, and fields with initializers. |
| `unused-private-member` | warning | `lint-all --db` / `lint-project --db` | A `private`/`strict private` method, field, const, or nested type with zero references in the symbol index. Mirrors `unused-public-symbol` for private scope. Guards: skips published fields, RTTI/`{$M+}`-streamed members, and property accessor methods/fields. See Known limitations above for a residual intra-class FP. |
| `unused-unit-in-uses` | warning | `lint-all --db` / `lint-project --db` | A unit in a `uses` clause with zero of its exported symbols referenced by the using unit. Conservative: skips plausible operator-overload / helper / side-effect-only units and a known allow-list. A unit used only for operator overloads or side effects without a referenced symbol may still be flagged; see Known limitations above. |
