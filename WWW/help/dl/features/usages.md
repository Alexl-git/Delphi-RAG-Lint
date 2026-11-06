---
id: usages
title: usages
summary: Finds usage sites of a named symbol, with a choice of report width
product: DL
group: search-navigation
order: 20034
since: 0.33.0-alpha
status: shipped
updated: 1.44.0-alpha
---

# usages

Finds usage sites of a named symbol, with a choice of report width.

Read this when you want every place a symbol is used: usages (also behind Find Usages in the IDE) lists the grouped usage sites of a named symbol, with a narrow, wide or very-wide report width.

## How to run it

Full flag list: [usages in the CLI reference](../cli.md#usages).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<X>` |  |  |
| `--width` |  |  |  |
| `--db` | `<path>` |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |
| `--limit` | `N` |  |  |
| `--rw` |  |  |  |
| `--in` | `<file>` |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--no-create` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Find Usages...**
   1. Put the caret on the symbol in the editor
   2. Choose drag-lint > Find Usages...
   3. Read the grouped usage sites

## Details

Finds usage sites of a named symbol, with a choice of report width. Reach for
it when you want a usages listing outside the IDE, or want to understand what
backs the "Usages" search kind in the Symbol Search dialog.

### Running it from the CLI
```text
drag-lint usages --name <X> [--width narrow|wide|very-wide] [--db <path>] [--depth N] [--format json] [--limit N]
```
`--limit N` keeps the first N rows of each JSON group and adds `"limit"` and
`"totals"` (every group's full count); `declarations` is a group too, so it is capped like the others. Without it the document is unchanged.

**`--db` is required.** Unlike `query` / `find-callers`, `usages` never reads the manifest: without `--db` it exits 2 (`usages does not read the manifest`). A qualified call such as `FHost.Feed(x)` is counted once (the stored call + member-access pair is collapsed at read time).

**`--in <file>` instead of `--db`** lets the file find its own project. When that project has no index yet, a deployed engine builds it at its proper path and says so on one stderr line (since 1.44, the same rule as `query --project`); `--no-create` keeps the old error, which prints the index command. A private engine copy never builds, and neither do the `lsp` and `serve` servers.
`--name <X>` is the symbol to search for. `--width` controls report width
(`narrow`, `wide`, or `very-wide`). `--depth N` is in the usage line with no
further description -- not documented. `--format json` is the only format the
usage line lists.

### What it needs
Optional, per the feature map's Index column.

### Example
Illustrative only:
```text
drag-lint usages --name TCustomerOrder --width wide --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format json
```
This would list usage sites of `TCustomerOrder` as JSON, at "wide" report
width.

### Readers and writers (`--rw`)
`usages --rw --name TFoo.Plain --db <db>` answers "who reads this and who writes it", even when
the property has no getter or setter method:
- for a **property**: its accesses, the mentions of a plain backing field, and direct calls of its accessor methods;
- for a **field**: the same, for every property it backs, plus its own mentions;
- for a **getter**: reads only; for a **setter**: writes only;
- for a routine that is no accessor: its callers, under `calls`.

A site the index stores as a read is reclassified from the source when you ask: the whole argument of `Inc`/`Dec` is a writer (`arg: inc-dec`), the whole argument of a `var` parameter of a resolved call is a reader and a writer (`var-arg`), and of an `out` parameter a writer (`out-arg`). An argument of an unresolved or ambiguous call, or one inside a longer expression (`F + 1`, `F.X`, `@F`, `F[I]`), stays a reader.

Each row names the route it came by (`property`, `field`, `getter`, `setter`, `direct`). A bare name gives
one block per declaration and counts the unbound name matches separately; a qualified name leaves them out.
`--json` gives `targets[]` with `readers`, `writers`, `calls`, `totals`, `read_accessor` / `write_accessor` and
`backs_properties`. Sites are per line. A symbol nobody declares or mentions exits 1.

Limit: directions are the index's, so a `var`/`out` argument and `Inc`/`Dec` of a field count as reads.

### No `--db`: name the unit (`--in`)
A unit does not exist by itself, so `usages --name X --in <file.pas>` with no `--db` finds its context:
1. The project: a `.dproj`, `.dpr` or `.dpk` in the file's folder or an ancestor that names it, or whose index holds it, or a manifest project whose index holds it. Its database answers; stderr says which.
2. That project has no index: exit 2 and the `drag-lint index --project ... --db ...` command to create it.
3. Two projects own it: exit 2, both named with their `--db`. Nothing is guessed.
4. No project: a library unit on an assumed platform (stderr says which), answered from the library index, or `--library-db`. If it uses units that library lacks, exit 2 and the message names them and asks for the project. A file the library itself holds is not asked about.

The CLI cannot prompt: every "ask" is a message on stderr and a non-zero exit, with stdout left empty.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
