---
id: impact-blast-radius-symbol
title: Impact / Blast Radius (symbol)
summary: Reports what would be affected if a chosen symbol changes -- the set of code to retest
product: DL
group: graphs-reports
order: 70014
since: 0.17.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# Impact / Blast Radius (symbol)

Reports what would be affected if a chosen symbol changes -- the set of code to retest.

Read this before changing a widely used method or type: it lists what would be affected if that symbol changes, so you know which code to retest. Give it the qualified name and, optionally, how many levels out to trace.

## How to run it

Full flag list: [impact in the CLI reference](../cli.md#impact).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.Bar>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |
| `--all-projects` |  |  |  |
| `--platform` | `win32\|win64` |  |  |
| `--config` | `<manifest>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Impact / Blast Radius (symbol)...**
   1. Needs an index of the project
   2. drag-lint > Uses & Dependencies > Impact / Blast Radius (symbol)...
   3. Enter the symbol; the affected code to retest is listed

## Details

Reports what would be affected if a chosen symbol changes -- the set of code
to retest. Reach for it before changing a widely-used method or type.

### Running it from the CLI
```text
drag-lint impact --qname <Foo.Bar> [--db <file.sqlite> | --all-projects [--platform win32|win64] [--config <manifest>]] [--depth N] [--format text|json]
```
`--qname` is the fully qualified symbol; `--depth` bounds how far impact is
traced; `--format` selects `text` or `json`.

### Across every project: `--all-projects`
With `--all-projects` the verb asks every database the manifest names instead of
one, and prints one block per section. `--db` is refused with it; `--platform`
narrows the library sections and `--config` names another manifest.

- A **project** database answers callers per depth and implementors. An interface
  member lists the implementing methods, an interface type the implementing classes.
- A **library** database answers where the symbol is declared, and never who calls
  it: its own callers are not counted.
- An interface declared only in the library has no symbol in a project database, so
  that project's classes are matched on the interface name in their heritage and
  tagged `by-name`, with no method-level answer.
- A project that holds neither the declaration nor a library that does has its
  name matches left out and reported as `by_name_refs`: they are another symbol of
  that name, or a unit that project's closure lacks. The report cannot tell which.

#### What it does not do for you
This is not a complete answer by itself. It reports what the indexes hold, and
you judge the rest:

- A section with no database is a `NOT INDEXED` line; an old schema or an unreadable
  file gets a line too; a section whose files changed since indexing is marked
  `STALE`. Each names the command that repairs it. **You run that command**; this
  verb never indexes anything. Any of these makes `complete` false and adds
  `INCOMPLETE` to the coverage line.
- `complete` only covers the sections the manifest names. A project that is not in
  the manifest is not seen, and nothing can count it: add it with `register-project`.
- A project index is only as complete as its `.dproj`/`.dpr`. Check with
  `reconcile-project`.
- Caller counts are the same name-based walk as the single-database verb, so a
  same-named routine in the same project is counted. Check a surprising number with
  `query find-callers --resolved`.

Exit 0 when the symbol was found somewhere, also when sections did not answer; read
`complete` before trusting a low number. Exit 1 when it was found nowhere, exit 2
when `--db` was given or the manifest did not load.

```text
drag-lint impact --qname CustomerOrder.ICustomerOrder.Total --all-projects --depth 2
```

### What it needs
Optional. An index is not marked required, but the impact trace is read from
whatever has been indexed, so a stale or missing index gives an incomplete answer.

### Example
Illustrative only:
```text
drag-lint impact --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --depth 3
```
This would report what is affected, up to 3 levels out, if the `Total`
member of `TCustomerOrder` changes.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
