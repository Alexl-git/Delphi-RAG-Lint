# warm-rule-cache

Fills the `lint <file>` rule cache for a project index, so the next lint of any
unit in that project reads the whole-project rules (`circular-uses`,
`enum-helper-separate-units`, `duplicate-global-decl`) from the cache instead of
computing them. Every project `index` run already warms it for you (or starts it
in the background); run it by hand when you want the cache warm right now.

## Running it from the CLI

```
drag-lint warm-rule-cache --db <project.sqlite> [--library-db <lib.sqlite>]
```

It runs in this process and prints `rule-cache: warmed N finding(s) in Xs`.
Without a `--db` that exists it exits 2. `--detached` is the form an index run
starts: every line of output goes to NUL, since that process has no console.

A project `index` run (and each project section of `index --all`, the `--jobs N` children included) runs the
same warm before it returns, or hands it to a detached background process:

```
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

## Reaching it in the IDE

No IDE surface of its own -- the IDE's `lint <file>` calls are what read the
cache this fills.

## What it needs

A project index (`--db`). The library index is `--library-db` when given, else
the one a plain `lint <file>` would open. `DRAGLINT_RULE_CACHE=0` turns the
cache, and therefore the warm, off.

## Example

Illustrative:

```
drag-lint index --project C:\Projects\MyApp\MyApp.dproj
drag-lint lint C:\Projects\MyApp\uMain.pas
```

The index run warms the cache before it returns, so the lint reads the
whole-project rules from the cache. With `--rule-cache-warm background` the index
returns as soon as the index itself is written, and the lint is a hit once the
background warm has finished.
