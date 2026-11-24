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
drag-lint rules --standard cwe        # only rules labelled with a CWE (or cert / misra); --json adds a compliance object per rule
```

Built-in rules carry their category/severity/params from an in-code registry
(`DRagLint.Lint.RuleCatalog`); external `.scm` rules contribute id/severity/message
from their sidecar `.json`. This command replaces the hand-maintained rule tables
below as the canonical inventory.

## Compliance labels

`rules\compliance.json` maps every rule id to the standards ids it answers: one line per rule, sorted by id, an unlabelled rule is `{}`:

```json
{
  "hardcoded-credential": {"cwe": ["CWE-798", "CWE-259"], "cert": ["MSC41-C"]},
  "wait-while-holding-lock": {"cwe": ["CWE-833"], "cert": ["LCK09-J"], "weak": ["CWE-833", "LCK09-J"]}
}
```r

Id formats (checked by `tests\autotest\run_compliance_labels_guard.ps1` and by the loader): `CWE-<n>`; CERT `ABC12-C|CPP|J`; MISRA `MISRA-C-2012-R<n>.<n>` / `D<n>.<n>`, `MISRA-CPP-2008-<n>-<n>-<n>`. `weak` lists the ids (a subset of the entry's own) whose fit is only plausible; everything not listed is confident, meaning the rule's title IS the weakness. The file is not a rule sidecar: the catalog skips it by name. Every rule must have an entry.

## Rule files

Each rule is a pair:

- `<name>.scm` ? the tree-sitter query
- `<name>.json` ? optional metadata

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
| `exclude_if_preceded_by` | none | Regexes (case-insensitive); `{name}` is replaced by the regex-escaped text of capture `@name`. A match is DROPPED when a regex matches the source text of the enclosing routine before the picked node (a pattern ending in `$` reads only the last 512 bytes of it). A pattern naming a capture the match did not bind never excludes. Example: `off-by-one-count` skips `for i := 0 to Length(A)` after `SetLength(X, Length(A) + 1)`. |
| `require_ancestor` | none | Node kinds; a match COUNTS ONLY inside one of them. |
| `require_file_text` | none | Substrings; the rule does not run at all against a file whose text contains NONE of them. Case-insensitive, matched against the whole file. |
| `needs_compiler` | `0` | (1.38.0) The oldest CompilerVersion (37 = Delphi 13, 36 = 12, 35 = 11, 33 = 10.3, 24 = XE3 ...) that accepts what the rule advises. Under `--target-compiler` / config `target_compiler` older than this the rule reports nothing. The same key on ONE entry of `fix` gates only that pattern: a match whose first applicable entry is gated is dropped (`nonminimal-bool`'s `not in` entry, `pos-for-contains`'s `Contains` entries). `0` = any compiler. |
| `compat_since` | `0` | (1.38.0) For a rule of category `compat` (a downgrade rule): the CompilerVersion that introduced the construct it reports. Ship it `"enabled": false`; it is switched ON for a run whose target is older than this. `--enable <id>` runs it at any target. |

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
| `#in? @cap "nodeType" ["nameRegex"]` / `#not-in?` | **drag-lint's own (2026-09-16):** some ANCESTOR of the captured node has that node type and, when the regex is given, its `name:` field matches it. Walks parents, so it needs no knowledge of which syntactic context the capture sits in. Put it last -- it runs only for matches that passed the cheaper predicates. Born for `hardcoded-ip-address`: `(#not-in? @warn "declConst" "(?i)version")` keeps a dotted-quad VERSION const from reading as an IPv4 address |
| `#parent? @cap "nodeType" ["field"]` / `#not-parent?` | **drag-lint's own (2026-11-18):** the DIRECT parent of the captured node has that node type and, when the field is given, the node sits in that field of it. Unlike `#in?` it does not walk ancestors. Born for `ifthen-to-if-expression`: `(#not-parent? @warn "ifElse" "else")` skips the tail of an else-if chain without skipping an if/else nested in a begin..end branch |

**Escaping in `#match?` regexes.** A backslash escape does not reliably survive the engine's predicate handling, so write a metacharacter as a one-member class instead: `[$]` for a dollar sign, `[[]` for `[` and `[]]` for `]` (see `rules\mixed-case-hex.scm`). A literal dot is `[.]`; `\\.` also works inside the `.scm` string, as in `ifthen-both-branches.scm`.

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
| `writeln-in-source` | info | Direct `WriteLn` call ? use a logger |
| `goto-statement` | warning | `goto` statement is generally considered harmful |
| `with-statement` | info | `with` statement makes symbol scope ambiguous |
| `empty-procedure-body` | info | Empty `procedure`/`function` body (begin..end with no statements) |
| `large-magic-number` | info | Numeric literal not in the common-constants allow-list; case labels, enum ordinals in a type declaration, `dispid N`, array subscripts (`Params[3]`) and the first argument of `Reg(<int>, ..)` are exempt (1.51.1) |
| `string-equality-comparison` | info | **Off by default** (opt in via `--rule` or config `"enabled"`). `=` comparison on expressions ? fires on all `=` binary expressions until type-resolution is plumbed in (v0.19+) |

## Shipped rules (v0.31)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `parser-error` | error | Tree-sitter `ERROR` node ? malformed syntax that the parser could not recover |

## Shipped rules (v0.32)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `compiler-magic-comments` | info | Comment contains TODO/FIXME/HACK/XXX ? track in issue tracker |
| `nested-with` | warning | Nested `with` statement ? scope becomes highly ambiguous |
| `assert-call` | info | `Assert()` call ? ensure the second argument provides a descriptive message |
| `case-magic-numbers` | info | `case` label is an integer literal ? consider naming the constant |

## Shipped rules (v0.35)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `boolean-comparison-true` | info | `X = True` or `X = False` -- redundant boolean comparison |
| `redundant-as-tobject` | info | `(X as TObject)` -- every Delphi object is already a TObject |
| `inherited-bare` | info | Bare `inherited;` call -- verify it invokes the intended ancestor method; not reported in Destroy / Assign / AssignTo or as the `if not (X is T) then inherited else` fallback (1.51.1) |

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
| `nil-comparison` | info | **Off by default** (opt in via `--rule` or config `"enabled"`). Prefer `Assigned(X)` over `X = nil` / `X <> nil` |
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
| `division-by-zero-literal` | warning | Float division by a literal zero (`X / 0`, `X / 0.0`) -- always raises EZeroDivide; `div 0` / `mod 0` are compile errors (dcc E2098) and are not reported (1.51.1) |
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
| `criticalsection-not-released` | error | lock `Enter`/`Acquire`, or `TMonitor.Enter(L)`, without a `finally` `Leave`/`Release`/`TMonitor.Exit(L)` |
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
  lines, nesting > 5). Use `--disable <id>` to turn any off. `deep-nesting` counts CONTROL statements only:
  if, case, loops, with, try..except; an if-EXPRESSION and try..finally are not levels (1.51.1).
- **`mutable-global-variable`**: the IDE form variable of a form unit (name / type = the `.dfm` root
  object, `frmX: TfrmX`) is not reported (1.51.1).
- **`missing-doc`**: not reported on the Get<X> / Set<X> accessors of a documented property X of the same
  class, on methods declared `override`, or on event handlers bound by the unit's own `.dfm` (1.51.1);
  undocumented properties and same-named handlers in unrelated units still fire.

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
- **`ui-access-in-thread`** (warning): VCL/FMX UI access (`.Caption :=`, `.SetFocus`, `.BringToFront`,
  `Application.ProcessMessages`, ...) in thread code the file itself proves: `Execute` of a class whose base chain
  in that file reaches a `*thread*` name, or a lambda passed to `TThread.CreateAnonymousThread`,
  `TTask.Run`/`Create`/`Future` or `TParallel.For`. Not inside `Synchronize`/`Queue`/`ForceQueue`. Needs no
  index; the typed answer is the project rule `ui-access-in-thread-typed`.

Index-wide rules (need `--db`, run via `drag-lint lint-project`): **`god-class`**, **`unused-public-symbol`**,
**`interface-reference-cycle`** (class A holds an interface implemented by B and vice-versa -- ARC leak;
mark one side `[weak]`/`[unsafe]`), **`layering-violation`** (config-driven architecture enforcement via
`--layers <file.json>` -- flags forbidden cross-layer `uses`; see CHANGELOG for the config shape).

Plus `field-by-name-in-loop` from the linter core, and
`unit-not-in-dpr` (project check).

### Tip

If you want to discover what AST nodes look like for a fragment of Delphi
code, run the tree-sitter CLI on a sample file:

```cmd
pwsh -File tools\ts-parse.ps1 path\to\sample.pas
```

Use that output to write your query. Do not call `tree-sitter.exe parse` bare: it picks the
grammar from `C:\Projects` by extension (`.pas`/`.dpr` match both the delphi13 and the pascal
grammar) and compiles it into `%LOCALAPPDATA%\tree-sitter\lib` from whatever the working
copy holds that day, so the tree can differ from what drag-lint's rules see. `tools\ts-parse.ps1`
forces `--scope source.delphi`, names the grammar directory and its git state, and warns when it
is newer than the engine's `tree-sitter-delphi13.dll`.

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
  "param_prefix": "p",
  "param_prefixes": ["p", "A"],
  "param_exempt": ["Value", "Source", "Owner"],
  "param_hungarian": "allowed",
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
| `param_prefix` | string | `"p"` | PREFERRED parameter prefix: the one the `param-name-prefix` autofix adds. Legacy single-prefix key: set alone it is also the whole accepted list, and `""` disables the rule |
| `param_prefixes` | array | `["p","A"]` | ACCEPTED parameter prefixes for `param-name-prefix` (1.52.2); `[]` disables the rule. When `param_prefix` is absent the first entry is the preferred one |
| `param_exempt` | array | `["Value","Source","Owner"]` | Parameter names `param-name-prefix` never reports (whole name, case-insensitive; 1.54.0, owner ruling 2026-11-23). A list given here REPLACES the default; `[]` exempts nothing |
| `param_hungarian` | string | `"allowed"` | `"allowed"`: a typed (Hungarian/Microsoft) prefix from `hungarian_prefixes` (`strName`, `bDone`) also satisfies `param-name-prefix` -- accepted, not required. `"off"`: it does not |
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
| `param-name-prefix` | info | **ON by default since 1.52.2.** Routine parameter names must start with one of the accepted prefixes (`param_prefixes`, default `p`, `A`; next character uppercase), or a typed Hungarian prefix while `param_hungarian` is `"allowed"`. A parameter wearing the field prefix (`FName`) is ALWAYS reported, even if `F` is listed. Skips `Self`, `Sender` (the VCL/FMX event signature), the names in `param_exempt` (default `Value`, `Source`, `Owner`) and single-letter names (`N`, `S`, `B`, ...; owner ruling 2026-11-20). **Autofix is OPT-IN** (owner ruling 2026-11-20): the rule reports by default, but its fix runs only when the run names it (`--rule param-name-prefix`, `--enable param-name-prefix` or `--fix-rule param-name-prefix`), never in a blanket `lint --fix --apply` / `lint-all --fix --apply`. The fix (`--fix`) adds the preferred prefix (`param_prefix`, default `p`; `FName` -> `pName`) at the declaration, the implementation header and every body use; it DECLINES (reported as a note, nothing written) for a virtual / override / dynamic / abstract / message method, a method of an interface type, and a non-private method of a class that implements an interface -- that parameter list is shared with partners the fix does not rename. |
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

### Enum rules and the type-level `dl:ok` (ENUMRULES, 2026-10-28)

| Rule id | Severity | Path | Description |
|---------|----------|------|-------------|
| `enum-ordinal-cast` | warning | `lint <file>` (index-widened) | `TEnum(<literal>)`, `Ord(e) <cmp> <literal>`, `case Ord(e) of` with literal labels. Exempt: `Ord()` vs `Ord()`, a negative sentinel `TEnum(-1)`, an enum whose values are all pinned (`= N`). |
| `unused-global` | hint | `lint-all --db` / `lint-project --db` | ON by default. A unit-level `const` / `var` / type that no ref names. Implementation section (const, var, type alias, class, record, interface): nothing in the declaring file names it (exact, unit-private). Interface section (const, var, type alias only -- interface classes/records/enums are public API): nothing in ANY indexed file names it; a unit other projects list is judged across their indexes too (a missing or stale one withholds the verdict, with a stderr note). Name-keyed; a ref-less candidate gets a whole-word text count (a compiler directive or a string leaves no ref) over its scope and the sibling projects' own files: a mention in code, a directive or a string (multi-line strings included) keeps it silent, a mention in a comment does not. Not covered by `unused-public-symbol` (interface routines only) or `unused-private-member` (private class members only). Fixture: `tests\lint-project\unused-global\run_unused_global.ps1` |
| `unused-enum-value` | hint | `lint-all --db` / `lint-project --db` | ON by default. An enum value no ref names, in a type with at least one named value and no implicit use (Low/High, Succ/Pred/Inc/Dec, a cast, `Ord`, RTTI, a streamed property). A FILLER value named for its own ordinal (`Dummy0` at 0) is exempt. |

Both rules honour ONE marker on the enum TYPE declaration line -- `// dl:ok unused-enum-value -- <reason>` or `// dl:ok enum-ordinal-cast -- <reason>` -- which reviews every finding of that rule for the type, in any unit (findings carry the type as `ScopeFile` / `ScopeLine`). `lint-all` reports such a marker `review-marker-unused` when it suppresses nothing; `lint <file>` does not judge it. Wiki: `Type-Level-Review-Marker`.

## Shipped rules (v1.51.0-alpha -- wave v151)

106 new rules (80 ON by default, 19 of them external `.scm`). Each has a fixture under
`tests\lint\` (or a `tests\lint-project\` runner for store-backed rules). `drag-lint rules --json` is the
authoritative catalog; `rules\compliance.json` carries their CWE labels.

| Rule id | Category | Severity | Default | Source | Title |
|---------|----------|----------|---------|--------|-------|
| `anonymous-thread-not-started` | bug-patterns | warning | ON | built-in | Anonymous thread is created but never started |
| `blocking-call-in-main-thread` | bug-patterns | warning | ON | built-in | Form or frame method waits with no time limit (WaitFor, WaitForSingleObject INFINITE, TTask.WaitForAll, TThread.Sleep) -- the UI freezes |
| `char-count-as-bytes` | bug-patterns | warning | ON | built-in | Character count used as a byte count |
| `char-to-pchar` | bug-patterns | warning | ON | `.scm` | PChar of a Char variable: the character code becomes the address. Cast a one-character string instead: PChar(string(C)). |
| `component-default-mismatch` | bug-patterns | warning | ON | built-in | Property default value differs from the value the constructor sets -- forms that kept the default load the wrong value |
| `component-missing-free-notification` | bug-patterns | warning | ON | built-in | Component-typed property stores a linked component without FreeNotification -- the field dangles when that component is freed |
| `component-setter-without-invalidate` | bug-patterns | hint | OFF | built-in | Property setter changes a field Paint reads but never calls Invalidate -- the control shows the old value |
| `control-char` | bug-patterns | warning | ON | built-in | Control character or invalid UTF-8 byte in the source text |
| `createprocess-readonly-commandline` | bug-patterns | warning | ON | built-in | CreateProcess with a read-only command line |
| `dataset-edit-without-post` | bug-patterns | warning | ON | built-in | Dataset Edit/Append/Insert whose record is changed but never posted or cancelled |
| `delimited-text-without-strict` | bug-patterns | warning | ON | `.scm` | DelimitedText is parsed after Delimiter was set, but StrictDelimiter is never set in this routine: without it the list also splits at every blank and honours the quote character. Set StrictDelimiter := True next to the Delimiter assignment. |
| `destroy-called-directly` | bug-patterns | warning | ON | built-in | Destroy called instead of Free |
| `dfm-circular-datasource` | bug-patterns | warning | ON | built-in | Master/detail or data source links in the form file form a cycle |
| `dfm-control-field-type-mismatch` | bug-patterns | warning | ON | built-in | Data-aware control does not suit the type of the persistent field it is bound to |
| `dfm-duplicate-binding` | bug-patterns | warning | ON | built-in | Two input controls in the form file are bound to the same data source and field |
| `dfm-master-without-fields` | bug-patterns | warning | ON | built-in | Dataset has a MasterSource but no MasterFields in the form file |
| `dfm-required-field-without-control` | bug-patterns | warning | ON | built-in | Required persistent field has no visible data-aware control |
| `dictionary-get-without-check` | bug-patterns | warning | ON | built-in | Dictionary read with no key check -- raises when the key is missing |
| `dll-export-unsafe` | bug-patterns | warning | ON | built-in | Exported routine has no calling convention |
| `duplicate-interface-guid` | bug-patterns | warning | ON | built-in | Two interfaces declare the same GUID |
| `equals-without-gethashcode` | bug-patterns | warning | ON | built-in | Equals overridden without GetHashCode (or the reverse) |
| `event-call-without-assigned` | bug-patterns | warning | ON | built-in | Event field called without an Assigned check |
| `except-handler-order` | bug-patterns | warning | ON | built-in | A later exception handler is shadowed by an earlier one |
| `exception-freed` | bug-patterns | warning | ON | built-in | Exception object freed by hand in its handler |
| `filename-compare-case` | bug-patterns | warning | ON | `.scm` | A file or path name is compared with = or <>, which is case-sensitive although Windows file names are not (and the path form may differ by delimiter or relative parts). Compare with SameText (SameFileName where the unit is available) instead. |
| `first-char-address` | bug-patterns | warning | ON | `.scm` | @S[1] on a string fails for an empty string (range check error under {$R+}, garbage without). Use PChar(S) or Pointer(S) and guard the empty case. |
| `form-access-before-create` | bug-patterns | warning | ON | built-in | The creation code of an auto-created form or data module reads the global variable of a module the .dpr creates later -- it is still nil |
| `form-autocreate-and-manual` | bug-patterns | warning | ON | built-in | The .dpr auto-creates a form and the code also assigns a new instance to the same global variable -- the first instance is orphaned |
| `form-field-type-mismatch` | bug-patterns | warning | ON | built-in | A published form field is declared with a class the form file's object of that name is not -- the field holds an object of another class |
| `form-field-without-object` | bug-patterns | warning | ON | built-in | A published field of the form class has no object of that name in the form file -- it stays nil after the form loads |
| `form-object-without-field` | bug-patterns | hint | ON | built-in | An object of the form file has no field in the form class -- code cannot reach it by name and the designer re-adds the field |
| `form-resource-missing` | bug-patterns | warning | ON | built-in | The unit declares the class of its form file but includes no form resource ({$R *.dfm}) -- creating the form raises EResNotFound |
| `global-formatsettings-modified` | bug-patterns | warning | ON | `.scm` | The process-wide FormatSettings (or one of the deprecated global format variables) is assigned: every thread and every later conversion sees the change. Keep a local TFormatSettings (TFormatSettings.Create / TFormatSettings.Invariant) and pass it to the conversion instead. |
| `inherited-form-handler-without-inherited` | bug-patterns | warning | ON | built-in | An inherited form re-declares an event handler of its ancestor form under the same name without calling inherited -- the ancestor's handler no longer runs |
| `inherited-order` | bug-patterns | warning | OFF | built-in | Destructor calls inherited before freeing its members |
| `inherited-without-ancestor` | bug-patterns | warning | ON | built-in | inherited in a method no ancestor declares |
| `inherited-wrong-method` | bug-patterns | warning | ON | built-in | Override calls inherited of a different method |
| `loop-off-by-one` | bug-patterns | warning | ON | `.scm` | For-loop bound runs one past the last valid index (High/Length/Count used as an upper index, or counting down from the count). |
| `managed-type-raw-memory` | bug-patterns | warning | ON | built-in | FillChar, Move or GetMem on a managed type |
| `message-handler-without-inherited` | bug-patterns | warning | ON | built-in | Message handler without inherited or default handler |
| `missing-inherited-call` | bug-patterns | warning | ON | built-in | Component hook override without inherited |
| `money-as-float` | bug-patterns | warning | ON | built-in | Money amount held as floating point |
| `null-compare` | bug-patterns | hint | ON | built-in | Variant compared with Null using = or <> instead of VarIsNull |
| `parallel-for-shared-write` | bug-patterns | warning | ON | built-in | Parallel loop or task-in-loop body writes a variable declared outside it without a lock -- the iterations race |
| `path-concat-without-delimiter` | bug-patterns | warning | ON | `.scm` | A folder name without trailing path delimiter is joined to a file or folder name with +, giving a name with the delimiter missing (Dir + 'file.txt' reads 'Dirfile.txt'). Use TPath.Combine(Dir, Name) or IncludeTrailingPathDelimiter(Dir) + Name. |
| `pchar-of-temporary` | bug-patterns | warning | ON | built-in | PChar of a temporary string is stored or posted |
| `pos-arguments-swapped` | bug-patterns | warning | ON | `.scm` | The searched-for part comes FIRST in Pos/PosEx/StartsStr/EndsStr and relatives; here a string literal is passed as the text to search, so the arguments look swapped (the call is only true when both are equal). Write Pos('literal', Variable). |
| `processmessages-in-handler` | bug-patterns | info | OFF | built-in | Application.ProcessMessages directly in an event handler |
| `processmessages-in-loop` | bug-patterns | warning | ON | `.scm` | Application.ProcessMessages inside a loop lets other handlers (including this one) run mid-loop; move the work to a thread or use a timer, or guard against re-entry. |
| `queue-nil-in-package` | bug-patterns | warning | ON | built-in | TThread.Queue(nil, ...) in a package unit |
| `self-as-interface-in-constructor` | bug-patterns | warning | ON | built-in | Self handed out as an interface while construction can still free the object |
| `self-free-in-event-handler` | bug-patterns | warning | ON | built-in | A form frees itself in its own event handler -- the VCL still uses the object after the handler returns; use Release |
| `string-index-base` | bug-patterns | warning | ON | `.scm` | String positions are 1-based: Copy/Delete/Insert with index 0 starts before the first character, and Pos never returns -1 (it returns 0 for not found), so a comparison with -1 is always the same answer. Use 1 as the first index and compare Pos with 0. |
| `stringlist-objects-leak` | bug-patterns | warning | ON | built-in | Object stored in a string list that does not own its objects |
| `stringlist-unsorted` | bug-patterns | warning | ON | built-in | Find or Duplicates used on a string list that is never sorted |
| `synchronize-in-destructor` | bug-patterns | warning | ON | built-in | Synchronize called from the destructor of a thread class |
| `task-exception-unobserved` | bug-patterns | warning | ON | built-in | TTask started with an unguarded body and never waited or read -- an exception raised in it is lost without a trace |
| `thread-loop-without-terminated` | bug-patterns | warning | ON | built-in | Loop in a thread's Execute path never tests Terminated |
| `thread-unsafe-increment` | bug-patterns | warning | ON | built-in | Thread code increments a global or class var without a lock -- concurrent Inc/Dec lose updates; use TInterlocked |
| `thread-use-after-free-on-terminate` | bug-patterns | warning | ON | built-in | Thread used after Start although it frees itself on termination |
| `threadvar-managed` | bug-patterns | warning | ON | built-in | threadvar of a managed type is never finalized |
| `transaction-without-rollback` | bug-patterns | warning | ON | built-in | Transaction is started and committed but never rolled back |
| `ui-call-in-console-or-service` | bug-patterns | warning | ON | built-in | Dialog call in a console program or a Windows service |
| `unchecked-conversion` | bug-patterns | hint | OFF | `.scm` | User input (a control's Text, a grid cell, ParamStr) is converted straight away: invalid text raises EConvertError. Use TryStrToInt/StrToIntDef (TryStrToFloat, TryStrToDate ...) or wrap the conversion in a try..except that tells the user what is wrong. |
| `unrelated-class-cast` | bug-patterns | warning | ON | built-in | Hard cast between two classes neither of which descends from the other |
| `missing-begin-update` | complexity | hint | ON | `.scm` | Items are added to a visual list in a loop without BeginUpdate; wrap the loop in BeginUpdate / try..finally EndUpdate to avoid a repaint per item. |
| `setlength-in-loop` | complexity | warning | ON | `.scm` | SetLength(A, Length(A) + 1) in a loop reallocates and copies the array on every iteration; size it once up front or grow it in larger steps. |
| `override-only-inherited` | dead-code | hint | ON | built-in | Override that only calls inherited |
| `unneeded-forward-declaration` | dead-code | hint | OFF | built-in | Forward declaration that is not needed |
| `legacy-stack-queue` | modernize | hint | OFF | built-in | Non-generic stack or queue read through a cast |
| `legacy-tlist` | modernize | hint | OFF | built-in | Non-generic list read through a cast |
| `component-palette-icon` | other | hint | OFF | built-in | Registered component has no palette bitmap in the .dcr / .res the unit includes |
| `dunitx-test-without-assert` | other | info | ON | built-in | DUnitX test method that checks nothing |
| `hardcoded-string` | other | hint | OFF | built-in | String literal with text for people in a statement: use a resourcestring |
| `todo-comment` | other | hint | OFF | built-in | Comment starts with an open-work marker (TODO, FIXME) |
| `asm-without-win64-variant` | platform | warning | ON | built-in | asm block without a 64-bit variant |
| `component-fixed-pixels` | platform | hint | OFF | built-in | Drawing call in a paint / resize routine uses a fixed pixel value -- too small above 96 dpi |
| `component-hardcoded-color` | platform | hint | OFF | built-in | Paint routine uses a hard-coded colour -- ignores system colours and VCL styles |
| `control-fixed-bounds` | platform | hint | OFF | built-in | Control bounds set to a fixed pixel value in code -- does not follow screen scaling |
| `registry-hklm-write` | platform | info | ON | built-in | Registry write below HKEY_LOCAL_MACHINE |
| `writeln-in-gui-app` | platform | warning | ON | built-in | Write / WriteLn in a program without a console |
| `contract-unit-declares-class` | policy | info | OFF | built-in | Contract unit (Intf / Interfaces / Contracts) declares a class |
| `disallowed-dfm-property` | policy | warning | ON | built-in | Form-file property forbidden by the project policy table (disallowed.names entries starting dfm:) |
| `file-header` | policy | hint | OFF | built-in | File does not start with the header from drag-lint-header.txt |
| `boolean-assign-if` | refactoring | info | ON | `.scm` | if/else only assigns True and False to the same variable; assign the condition directly (V := Cond, or V := not Cond). |
| `missing-begin-end` | refactoring | hint | OFF | `.scm` | The body of this if/else/for/while/with is a single statement without begin..end; bracket it so a later added statement stays inside the branch. |
| `prefer-case` | refactoring | hint | OFF | `.scm` | An if/else-if chain compares the same name with three or more ordinal constants; a case statement states this directly. |
| `redundant-begin-end` | refactoring | hint | OFF | `.scm` | begin..end around a single statement; the brackets can be removed. |
| `string-if-chain` | refactoring | hint | OFF | `.scm` | An if/else-if chain compares the same string against three or more literals; a lookup (TDictionary, IndexText + case) reads and extends better. |
| `trivial-accessor` | refactoring | hint | OFF | built-in | Accessor method only reads or writes a field |
| `destructor-not-nil-safe` | resource-lifetime | warning | ON | built-in | Destructor dereferences a field that a raising constructor may have left nil |
| `field-free-without-nil` | resource-lifetime | warning | ON | built-in | Field freed outside the destructor keeps its dangling reference |
| `field-ownership-unclear` | resource-lifetime | hint | OFF | built-in | Field created by the class, never freed by it and handed out -- ownership unclear |
| `handle-leak` | resource-lifetime | warning | ON | built-in | Windows handle is not closed |
| `ota-notifier-not-removed` | resource-lifetime | warning | ON | built-in | IDE notifier / wizard / binding registered through the Open Tools API is never removed -- the IDE calls freed code after unload |
| `raw-memory-leak` | resource-lifetime | warning | ON | built-in | GetMem or New without release |
| `bidi-control` | security | warning | ON | built-in | Bidirectional control character in the source: the code can read differently from how it compiles |
| `invisible-char` | security | warning | ON | built-in | Invisible or zero-width character in the source text |
| `random-without-randomize` | security | info | ON | built-in | Random is used but the project never calls Randomize |
| `tls-verification-disabled` | security | warning | ON | built-in | TLS certificate verification is switched off |
| `weak-cipher` | security | warning | ON | built-in | Broken cipher or mode (DES, 3DES, RC2, RC4, ECB) |
| `default-parameter` | structure | hint | OFF | built-in | Parameter with a default value |
| `foreign-form-control-access` | structure | hint | ON | built-in | Code reaches a control of another unit's form through its global variable (Form2.Edit1) -- the units are coupled to the form layout |
| `method-order` | structure | hint | OFF | built-in | Method bodies are not in the order of the class declaration |
| `sql-select-star` | structure | info | OFF | `.scm` | SELECT * returns whatever columns the table has today -- name the columns you need. |
| `write-only-property` | structure | hint | OFF | built-in | Property has a write accessor but no read accessor |
