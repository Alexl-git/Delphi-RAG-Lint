# Delphi coding conventions for an AI agent (drag-lint + YADF)

> **Give this file to your coding agent.** Paste it into `CLAUDE.md` /
> `AGENTS.md`, or point the agent at it. It exists so generated code passes
> `drag-lint lint-all` and `YADF` on the FIRST try, instead of generating a
> backlog of warnings someone has to clear afterwards.

Every rule below states the drag-lint rule id it satisfies, so the two can be
checked against each other. **If you change the linter's naming config, change
this file in the same commit** -- a convention doc that drifts from the rules it
claims to encode is worse than none, because the agent follows it confidently
and the linter disagrees.

The authoritative source is always the tool:

```
drag-lint rules --json          # every rule, its severity, and its parameters
drag-lint rules | findstr naming
```

---

## 1. Naming

These map 1:1 onto the `naming` rule family and its configured parameters
(`field_prefix=F`, `method_case=PascalCase`, `local_case=PascalCase`,
`const_case=PascalCase,UPPER_CASE`).

| Thing | Rule | Convention | Good | Bad |
|---|---|---|---|---|
| Class / record type | `type-name-prefix` | `T` prefix | `TQueryRule` | `QueryRule` |
| Interface type | `type-name-prefix` | `I` prefix | `ISymbolStore` | `SymbolStore` |
| Exception class | `type-name-prefix` | `E` prefix | `EPipeError` | `TPipeError` |
| Pointer type | `type-name-prefix` | `P` prefix | `PNodeRec` | `NodeRecPtr` |
| **Object field** | `field-name-prefix` | **`F` prefix**, PascalCase after | `FCount`, `FOwner` | `Count`, `fcount` |
| **Local variable** | `local-var-casing` | **PascalCase, NO `F`** | `Idx`, `NodeCount` | `nodeCount` |
| **Local variable** | `local-field-prefix` | **never wear `F`** | `Name` | `FName` (reads as a field) |
| Method / routine | `method-pascalcase` | PascalCase | `ApplyDelta` | `applyDelta`, `apply_delta` |
| Constant | `const-casing` | PascalCase or `UPPER_CASE` | `MaxRows`, `AUTO_TOKEN` | `maxRows` |
| Parameter | `param-name-prefix` | `p`/`A` prefix **only if configured** | see below | -- |
| Unit | `unit-name-matches-file` | unit name = file base name | `unit DRagLint.Doc.Drift;` in `DRagLint.Doc.Drift.pas` | mismatch |

### The two that agents get wrong most often

**`F` belongs to object fields and nothing else.** A local named `FName` inside
a method compiles, but every reader parses it as a field of the class. That is
`local-field-prefix`. It is the single most valuable naming rule in the set,
because unlike casing it changes what a reader *believes* about the code.

**Single-letter loop counters are fine.** `for i := 0 to High(A)` is idiomatic
and `local-var-casing` deliberately **exempts 1-character names** -- do not
"fix" `i` to `I`. Two characters and up must be PascalCase (`fi` -> `Fi` is
wrong for a different reason: it invents an `F` prefix -- use `Idx`).

### Parameter prefixes are project-scoped

`param_prefix` ships **empty**, i.e. the rule is OFF by default. Some
codebases in this ecosystem use `p` (`pDelta`) and some use `A` (`ADelta`).
**Read the project's own config before assuming** -- `drag-lint rules | findstr
param-name-prefix` shows the active value. Do not introduce a prefix the
project has not configured; a wrong prefix is worse than none.

---

## 2. Documentation (CDD)

Required on every **public/published** type, method and interface. Private
helpers only when an invariant, ownership rule or thread-safety constraint is
non-obvious. Format is **DocInsight** (`///` triple-slash XML), NOT Doxygen.

```pascal
/// <summary>Streams pending row deltas into the target memtable.</summary>
/// <param name="ADelta">Accumulated change set; must not be nil. Caller owns it.</param>
/// <returns>Number of rows applied.</returns>
/// <exception cref="EPipeError">Raised if the pipe closes mid-write.</exception>
/// <remarks>Not thread-safe; call from the owning thread only.</remarks>
function ApplyDelta(const ADelta: IDeltaSet): Integer;
```

Rules that police this: `missing-doc`, `doc-drift`, `doc-param-no-description`,
`doc-param-not-in-signature`.

Three things the engine has opinions about:

- **A constructor gets no `<returns>`.** It has no return type, so the engine
  emits none and the linter does not ask for one. It writes a `constructor`
  marker into the managed facts block instead (`local` rule:
  `ddConstructorNotMarked`).
- **Never hand-edit inside `<!-- drag-lint:auto BEGIN -->` / `END`.** That block
  is regenerated on every `document` run; your edit is destroyed. Write prose
  *outside* the fence -- it is preserved verbatim.
- **`<exception cref>` is only graded on a routine that HAS a body.** Documenting
  what implementors must raise on an interface method is correct and expected.

---

## 3. Formatting -- YADF

drag-lint checks *semantics*; **YADF** owns *layout*. Do not hand-format to
guess YADF's output -- write reasonable code and let YADF normalise it. Running
both is the point: a file that satisfies drag-lint and YADF needs no style
review at all.

Non-negotiables YADF will not fix for you, because they are file-level:

- **Strict 7-bit ASCII.** No UTF-8, no BOM, no smart quotes, no em-dashes in
  source. Use `--` in comments.
- **CRLF line endings.** A scripted or regex-based edit that writes LF silently
  converts the whole file; `tests\autotest\run_encoding_guard.ps1` fails on it.
- Provide **complete units** (interface + implementation), not fragments.

---

## 4. Resource and error handling

The rules with the highest real-bug yield. Generated code should satisfy these
by construction:

| Rule | What it wants |
|---|---|
| `object-leak`, `create-inside-try` | `try-finally` around every manual `Create`, with the `Create` **outside** the `try` |
| `try-except-swallowed`, `bare-except`, `empty-except` | Never swallow. Re-raise, or log with a reason. `except` with an empty body is always a defect |
| `double-free`, `unprotected-object-free` | Free once, and guard the path |
| `raise-bare-exception` | `raise EMyThing.Create('why')`, never bare `raise Exception.Create` with no context |
| `function-result-not-set`, `out-param-not-set` | Assign `Result` (and every `out`) on **every** path |
| `dataset-open-without-close` | Pair `Open` with `Close`, normally in `try-finally` |
| `missing-inherited-ctor` | Call `inherited Create` |

Prefer the RTL / Spring4D / DevExpress / FireDAC facility over hand-rolled code;
Spring4D-managed lifetimes need no `try-finally`.

---

## 5. Verify before you claim done

```
drag-lint index <dir> --db <db>          # index must match disk FIRST
drag-lint lint-all --db <db> --config drag-lint-lint.json
yadf <changed files>
```

**Reindex before linting.** A stale index makes the linter report on code that
no longer exists -- and, worse, makes a doc pass compute facts from stale data.
The `relint` skill automates the whole loop; see `docs/AI-USAGE.md`.

Two honest caveats, so you calibrate:

- **A finding is not automatically a defect.** Some are the rule being wrong.
  If you believe a finding is a false positive, say so with the reason rather
  than contorting the code to silence it -- false positives are tracked in
  `docs/BACKLOG-lint-false-positives.md` and fixing the *rule* is often correct.
- **There is currently no inline suppression.** A `// drag-lint:ignore <rule>`
  comment does **nothing** -- nothing parses it. Suppress via config
  (`disabled` / `exclude_paths` in `drag-lint-lint.json`), not comments.
