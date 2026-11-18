---
id: v1511-res-fixes
title: Library bindings for bare reads, paren-less calls and function-result receivers
summary: Bare reads of library vars (Application), paren-less library calls and members on a library function result bind to refs.external_target
product: DL
group: indexing
order: 10014
since: 1.51.1-alpha
status: shipped
updated: 1.51.1-alpha
---

# Library bindings for bare reads, paren-less calls and function-result receivers

Bare reads of library vars (Application), paren-less library calls and members on a library function result bind to refs.external_target.

Read this when usages shows a library name such as Application as name-only, when a paren-less call of a library function is missing from purity or caller answers, or when a member called on a library function's result (Printer.Canvas, a var inferred from it) has no library target. Since 1.51.1 the resolve pass binds all three and marks a read with refs.external_kind value, parenless-call or proc-value.

## How to run it

```text
drag-lint usages --name <X> | --in <file> --line <L> [--col <C>] [--scope symbol|project|group|everywhere] [--group <x.groupproj>] [--width narrow|wide|very-wide] [--db <path>] [--depth N] [--format json|--json] [--limit N] [--rw] [--in <file> [--no-create]] [--library-db <lib.sqlite>]
```

Example:

```text
drag-lint usages --name Application --db <file.sqlite> --library-db <lib.sqlite> --json
```

Full flag list: [usages in the CLI reference](../cli.md#usages).

```text
drag-lint index <path> [--db <file.sqlite>] [--watch [--interval N]] [--library-db <lib.sqlite> ...] [--wait-library <min>] [--require-library] [--stall-exit-min <min>] [--target-compiler <ver|auto>]
```

Example:

```text
drag-lint index --project <X.dproj> --db <file.sqlite> --library-db <lib.sqlite>
```

Full flag list: [index in the CLI reference](../cli.md#index).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A project index resolves calls into platform units (System, Vcl, FireDAC ...) against the
platform LIBRARY database (`library-Win32.sqlite` / `library-Win64.sqlite`). A manifest section
opts in with `"libraryResolve": true` (default false). If the library is not ready when the
project is indexed, the project is still indexed - but its library-bound edges are missing, and
the engine records that instead of pretending.

### What `index` does

Before the walk, `index --all` / `index --project` probe the section's platform library (platform
= `--platform`, else the project DB `plat=` stamp, else the `.dproj` platform, else the manifest
default) and print one line:

```text
library: <path> (<platform>) READY
library: <path> (<platform>) NOT READY -- <why>
```

Not-ready reasons: rebuilding, stale extractor, schema old, never completed, missing.

| Situation | Behaviour |
|---|---|
| ready | resolve against the library; marker `bound` |
| not ready (default) | continue against the project only; print `library: PENDING ...`; marker `pending` |
| not ready, `--wait-library <min>` | poll every 30 s for up to `<min>` minutes, then fall back to the default |
| not ready, `--require-library` | error, exit 2, nothing is marked |

`index --all --dry-run` lists `library: <path> (<platform>, <state>)` per opted-in section.

### The marker

`schema_meta.library_resolve_state` holds a small JSON object: `state` (`pending` | `bound`),
`platform`, `library`, `reason`, `since_unix`, `last_check_unix`, `engine`. No schema bump.
A later `index` run with a ready library re-runs the resolve pass once (as `--resolve-only`) and
flips `pending` to `bound`. Only writers touch the marker; readers never write it.

### What readers say

* `context` prints one NOTE on stderr for a pending DB: the answer is INCOMPLETE for callers and
  callees into the platform library, with the exact remedy.
* JSON envelopes of such a DB carry `index_notes[]` with `kind: library-pending`, `reason`,
  `since_unix` and `remedy`.
* `info --json --db <file>` gives the verdict `library-resolve-owed` and a
  `library_resolve {state, reason, since_unix, library_state}` object; the text form adds a
  `library_resolve` line.

### Repair

Once the library is ready: `drag-lint index --project <X.dproj> --resolve-only` (the NOTE prints
the exact command). Check with `drag-lint info --db <file>`: verdict `current`.

### What binds to the library (1.51.1)

Besides calls and member accesses, the resolve pass binds these to `refs.external_target`:

| Source | Bound to | `refs.external_kind` |
|---|---|---|
| a bare read of a library var / const / inherited field or property: `Application` in a `.dpr` main block | `Vcl.Forms.Application` | `value` |
| a bare read of a library function that needs no argument: `if AFlag and GetTickCount64 > T then` | the function; purity takes its effect summary as for a call | `parenless-call` |
| a library routine named as a value: `@LibFn`, a procedural argument | the routine (identity, not a call) | `proc-value` |
| a member called on a library function's result: `Printer.Canvas`, `LibFn().M`, `var R := LibFn; R.M` | the member of the function's declared result type | (as for any call) |

A read stays unbound when the project declares the name where the site can see it (a type, an enum
value, a unit-level declaration anywhere in the index, a local, a member of the enclosing class),
when an enclosing `with` target may supply it, when two used library units declare it, or when it
names an overloaded function not every overload of which can be called without arguments. Library
enum values (`alClient`) are not bound. All of it needs the library store: without `--library-db`
(or the section's library) the targets are NULL, and a resolve pass run without it clears them.
See also: Index-DB-Schema (`schema_meta` keys), [info](info.md).

### Resolver fixes (1.52)

- A generic type receiver is typed: `TObjectList<TFoo>.Create` binds to the project type when the generic head is
  the project's, else to the library by name plus generic arguments (`TArray<..>` excluded).
- A `Name(...)` receiver keeps `Name` as its type text only when it reads as a type (a built-in, or T/I/E/P plus a
  capital); `Copy(...)` and `StyleServices(...)` give an empty type text.
- `index --resolve-only` with no library store attached KEEPS the library bindings (calls, member accesses and
  library reads) of the last library run and warns `library bindings are kept from the last library run, not
  refreshed`; the `external_stores` key is marked partial so the next library run resolves whole.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
