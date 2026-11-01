---
id: warm-rule-cache
title: warm-rule-cache
summary: Fills the lint rule cache for a project index; index runs warm it, or start it in the background (--rule-cache-warm)
product: DL
group: linting
order: 30029
since: 1.39.0-alpha
status: shipped
updated: 1.39.2-alpha
---

# warm-rule-cache

Fills the lint rule cache for a project index; index runs warm it, or start it in the background (--rule-cache-warm).

Computes the whole-project lint rules (circular-uses, enum-helper-separate-units, duplicate-global-decl) for a project index and stores them, so the next lint of any unit is a cache hit. Every project index run warms it; --rule-cache-warm background detaches it (the run returns at once), off skips it, DRAGLINT_RULE_CACHE_WARM sets the default. It writes only if no index changed meanwhile. A warm stops at once on drag-lint shutdown (exit 4), and an index of the same database stops a stale warm. Contributed by Jonathas Paiva (PR #1).

## How to run it

Full flag list: [warm-rule-cache in the CLI reference](../cli.md#warm-rule-cache).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<project.sqlite>` |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--detached` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

**Needs:** index

## Details

Fills the `lint <file>` rule cache for a project index, so the next lint of any
unit in that project reads the whole-project rules (`circular-uses`,
`enum-helper-separate-units`, `duplicate-global-decl`) from the cache instead of
computing them. Every project `index` run already warms it for you (or starts it
in the background); run it by hand when you want the cache warm right now.

### Running it from the CLI

```text
drag-lint warm-rule-cache --db <project.sqlite> [--library-db <lib.sqlite>]
```

It runs in this process and prints `rule-cache: warmed N finding(s) in Xs`.
Without a `--db` that exists it exits 2. `--detached` is the form an index run
starts: every line of output goes to NUL, since that process has no console.

A project `index` run (and each project section of `index --all`, the `--jobs N` children included) runs the
same warm before it returns, or hands it to a detached background process:

```text
drag-lint index --project <x.dproj> [--rule-cache-warm background|wait|off]
```

`wait` is the default and warms inside the index run; `background` starts the
warm in a detached process and returns at once; `off` skips the warm.
`DRAGLINT_RULE_CACHE_WARM=<mode>` sets the default for every index run. The warm
recomputes the whole-project rules -- minutes on a large project -- so
`background` suits a frequent incremental index (an agent, a daily reindex). It
keeps the index OPEN until it ends, and Windows will not delete an open file, so a
script that deletes the index right after indexing keeps `wait`. The warm writes
the cache only if no index changed while it ran, and until it finishes the next
`lint <file>` fills the cache itself. A newer background warm of the same index
stops the older one, whose answer would be stale anyway. Only a process running the same engine FILE is stopped -- compared by volume and file index, so an engine started by its 8.3 short path or through a junction is still recognised.

### What it needs

A project index (`--db`). The library index is `--library-db` when given, else
the one a plain `lint <file>` would open. `DRAGLINT_RULE_CACHE=0` turns the
cache, and therefore the warm, off.

### Example

Illustrative:

```text
drag-lint index --project C:\Projects\MyApp\MyApp.dproj
drag-lint lint C:\Projects\MyApp\uMain.pas
```

The index run warms the cache before it returns, so the lint reads the
whole-project rules from the cache. With `--rule-cache-warm background` the index
returns as soon as the index itself is written, and the lint is a hit once the
background warm has finished.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
