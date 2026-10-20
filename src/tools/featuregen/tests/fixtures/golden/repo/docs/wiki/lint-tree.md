# lint-tree

Answers one question `lint-all` cannot: **does an interface edit to this unit
reach any dependent?** It fingerprints the unit's interface section, diffs it
against the OLD side, and reports every reference across the dependent closure
that no longer resolves or whose target changed. Reach for it before you save
(or commit) an edit to a unit other units use.

Why it exists: removing an interface symbol that dependents still use produces
ZERO `lint-all` findings -- the count actually goes DOWN, because the removed
code no longer exists to be linted (measured 2026-09-10).

## Running it from the CLI

```
drag-lint lint-tree --unit <B.pas> --db <file.sqlite> [--buffer <buf>] [--project <.dproj>]
                    [--baseline <f.json>] [--write-baseline <f.json>] [--platform win32|win64]
                    [--with-rules] [--compile] [--format json|text]
```

* `--write-baseline <f.json>` captures the OLD side once per edit episode;
  `--baseline <f.json>` diffs against it. Without a baseline the OLD side is the
  live index, which is right for CLI/manual use only.
* `--buffer <f>` reads an UNSAVED editor buffer as the NEW side.
* `--compile` also compiles the dependents in a shadow directory.
* `--with-rules` runs the ordinary lint rules over the affected dependents too.
* Exit 0 whether or not anything was found; exit 2 means it could NOT run.

## What it reports

`stale-interface-reference`, at every BOUND reference to a changed or removed
declaration. The kinds it can report are the ones the resolver binds by id:
routines, properties, fields and -- since resolver 1.6.0-alpha -- **enum
members**. Anything else is listed under `not_reportable` in the JSON report
rather than silently counted as handled.

The wording depends on what happened, because the consequence differs:

* **Removed** declaration -- "this reference will not compile until it is
  updated".
* **Changed** declaration on a routine, property or field -- a signature
  change, same wording.
* **Changed** declaration on an ENUM MEMBER -- dropping an earlier member shifts
  every later member's ordinal, so `if C = cmdDelta then` keeps compiling. The
  finding says so: "this reference still compiles, but the member ordinal has
  moved -- any ordinal already persisted or transmitted now means a different
  member".

## What it needs

An index, resolved at `DRAGLINT_RESOLVER_VERSION` 1.6.0-alpha or later for the
enum-member findings (`index --all --resolve-only` on an older one). On an
older index enum reads are unbound and `lint-tree` reports nothing for them --
exactly as before.

## Reaching it in the IDE

The IDE plugin runs it for an edit episode on the active unit, capturing the
baseline when the episode starts. From the CLI, capture the baseline yourself
before editing.

## Example

Illustrative:

```
drag-lint lint-tree --unit C:\Projects\MyApp\Protocol.pas --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --write-baseline C:\TEMP\protocol.json
(edit Protocol.pas)
drag-lint lint-tree --unit C:\Projects\MyApp\Protocol.pas --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --baseline C:\TEMP\protocol.json --format text
```
