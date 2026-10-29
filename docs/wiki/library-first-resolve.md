# Library-first resolve

A project index resolves calls into platform units (System, Vcl, FireDAC ...) against the
platform LIBRARY database (`library-Win32.sqlite` / `library-Win64.sqlite`). A manifest section
opts in with `"libraryResolve": true` (default false). If the library is not ready when the
project is indexed, the project is still indexed - but its library-bound edges are missing, and
the engine records that instead of pretending.

## What `index` does

Before the walk, `index --all` / `index --project` probe the section's platform library (platform
= `--platform`, else the project DB `plat=` stamp, else the `.dproj` platform, else the manifest
default) and print one line:

```
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

## The marker

`schema_meta.library_resolve_state` holds a small JSON object: `state` (`pending` | `bound`),
`platform`, `library`, `reason`, `since_unix`, `last_check_unix`, `engine`. No schema bump.
A later `index` run with a ready library re-runs the resolve pass once (as `--resolve-only`) and
flips `pending` to `bound`. Only writers touch the marker; readers never write it.

## What readers say

* `context` prints one NOTE on stderr for a pending DB: the answer is INCOMPLETE for callers and
  callees into the platform library, with the exact remedy.
* JSON envelopes of such a DB carry `index_notes[]` with `kind: library-pending`, `reason`,
  `since_unix` and `remedy`.
* `info --json --db <file>` gives the verdict `library-resolve-owed` and a
  `library_resolve {state, reason, since_unix, library_state}` object; the text form adds a
  `library_resolve` line.

## Repair

Once the library is ready: `drag-lint index --project <X.dproj> --resolve-only` (the NOTE prints
the exact command). Check with `drag-lint info --db <file>`: verdict `current`.

See also: [[Index-DB-Schema]] (`schema_meta` keys), [[info]].