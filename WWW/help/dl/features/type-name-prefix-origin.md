---
id: type-name-prefix-origin
title: "type-name-prefix: expected letter from the ancestor chain"
summary: type-name-prefix picks E or T from the ancestor chain (project, then library index); untraceable ancestors are an index gap; autofix uses the finding's letter
product: DL
group: linting
order: 30026
since: 1.31.4-alpha
status: shipped
updated: 1.36.0-alpha
---

# type-name-prefix: expected letter from the ancestor chain

type-name-prefix picks E or T from the ancestor chain (project, then library index); untraceable ancestors are an index gap; autofix uses the finding's letter.

Before 1.31.4 a class whose ancestry left the project index was judged by its project-only chain, so EKeyViolation = class(EDatabaseError) was told to start with T and the fix renamed it TEKeyViolation.

## How to run it

```text
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>]
```

Example:

```text
lint <unit> --db <proj> --library-db <lib> --rule type-name-prefix
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

```text
drag-lint lint-all [--db <file.sqlite>] [--project <.dproj>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess]
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

```text
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>]
```

Example:

```text
lint <unit> --db <proj> --fix --fix-naming --rule type-name-prefix
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--rule` | `<id>` |  |  |
| `--disable` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |
| `--json` |  |  |  |
| `--labels` |  |  |  |
| `--no-preprocess` |  |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--db` | `<index.sqlite>` |  |  |
| `--project-rules` |  |  |  |
| `--stand-in-for` | `<realpath>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--project` | `<.dproj>` |  |  |
| `--rule` | `<id>` |  |  |
| `--disable` |  |  |  |
| `--output` | `<report.txt>` |  |  |
| `--json` |  |  |  |
| `--labels` |  |  |  |
| `--quiet` |  | suppress per-file progress lines written to stderr |  |
| `--lint-third-party` |  |  |  |
| `--no-preprocess` |  |  |  |
| `--fix` |  |  |  |
| `--fix-naming` |  |  |  |
| `--apply` |  |  |  |
| `--rule` | `<id>` |  |  |
| `--disable` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |
| `--json` |  |  |  |
| `--labels` |  |  |  |
| `--no-preprocess` |  |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--db` | `<index.sqlite>` |  |  |
| `--project-rules` |  |  |  |
| `--stand-in-for` | `<realpath>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Pitfalls

* lint `<file>` is a strict SUBSET: project-wide rules can only fire in lint-all.

## Details

`type-name-prefix` decides whether a class should start with `T` or `E` (or `I`
for interfaces) by tracing its declared ancestor chain. Since 1.31.4-alpha the
chain is followed through the project index **and** the library index, and the
`--fix-naming` autofix uses the letter the finding reports, so the checker and
the fixer cannot disagree.

### What the rule decides

For a class declaration the rule computes an **origin** (the root the class
descends from) and derives the expected prefix from it:

- origin `Exception` -> `E` (or the configured exception prefix);
- origin `TObject` (or a class with no ancestor) -> `T`;
- an interface type -> `I`.

A finding is reported only when the declared name does not start with the
expected prefix. An origin the rule cannot determine is **never** guessed at.

### Example

```pascal
type
  EKeyViolation = class(EDatabaseError);  // EDatabaseError -> ... -> Exception
```

`EDatabaseError` is declared in the library (Data.DB), not in the project. The
project index alone stops at `EDatabaseError`, so a project-only walk could not
tell that this class is an exception. With the library index the chain reaches
`Exception`, the expected letter is `E`, and no finding is raised.

### How the origin is decided

The rule walks the ancestor chain of the class and applies these steps in
order. The first step that matches decides the result.

| # | Condition | Result |
|---|-----------|--------|
| 1 | No exception prefix is configured (`ExceptionPrefix` is empty) | Class: the class prefix (`T`) applies; no chain is traced |
| 2a | The class is not in the project index at all (stale index: unit edited after indexing) | Silent; no letter, no gap finding, never auto-fixed |
| 2 | The project chain reaches `Exception` | `E` |
| 3 | The project chain has no unresolved leaves | `T` |
| 4 | A leaf is `TObject`; it counts as a known plain-class root, even with no library store | Known root; continue to the verdict on the remaining leaves |
| 5 | A library index is open, and a leaf descends from `Exception` | `E` (the cross-store hop) |
| 6 | A library index is open, and every leaf is known to the library | `T` |
| 7 | A leaf is in **neither** the project nor the library index | Error-severity **index gap** finding; no prefix is guessed |
| - | No library index, or no `--db` at all | Silent for untraceable classes. Only a missing ancestor or `TObject` (`T`) or `Exception` (`E`) decides the letter |

Notes on the table:

- The library index is the manifest-resolved library store, or the path given
  with `--library-db` (`lint` and `lint-all`).
- The index-gap finding names the ancestor and the class, for example:
  `Ancestor "X" of class "Y" is in neither the project nor the library index ...`.
  It is reported once, at ERROR severity.
- The 1.31.3 name heuristic (an `E` name prefix on the direct ancestor decides
  the letter) no longer picks a letter. An unknown origin is an index gap, not a
  guess.

### Fix-parity rule

`lint --fix --fix-naming` reads the prefix **from the finding's own message**
rather than recomputing it. The checker decides once; the fixer applies that
decision. Consequences:

- `EKeyViolation` is never renamed to `TEKeyViolation`.
- An index-gap finding is **never** auto-fixed, because it carries no letter.
- Any change to the origin logic reaches the fixer automatically, with no second
  copy of the chain walk to keep in step.

### Fixture and runner

- Runner: `tests\autotest\run_type_prefix_exception_ancestor.ps1`
- Fixture: `tests\lint-project\typeprefix-split`, with two folders, `app` (the
  project) and `lib` (the library), so the cross-store hop is exercised for real.
- Sections:
  - **A** (X1..X5) -- store-less, no `--db`;
  - **Y** (Y1..Y3) -- store-backed, with the library store forced to nil;
  - **B** (B0a-d premises, B1..B11) -- `lint --db <app> --library-db <lib>`. The
    gap cases B6/B7/B8 (unknown origin) each get ONE finding at severity
    `error`, with the message `Ancestor "...`, and no prefix finding;
  - **B-all** -- the same lines through `lint-all --db <app> --db <lib>`, for
    parity with B;
  - **C** (C1..C5) -- `lint --fix --fix-naming --apply` on a copy: `KeyDup` ->
    `EKeyDup`, `Widget` -> `TWidget`, and `Foo` / `EKeyViolation` untouched.
- Positive control: `TFoo = class(TObject)` named `Foo` still fires with `T`.
  A test that only asserts the false finding is gone would pass with the rule
  switched off.

### Related

- Backlog record: `docs\INBOX-type-name-prefix-exception-ancestry.md` (gitignored; closed in 1.31.4-alpha).
- Release notes: `CHANGELOG.md`, section v1.31.4-alpha.
- Caveat on renames: `docs\AI-USAGE.md`, section 4b.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
