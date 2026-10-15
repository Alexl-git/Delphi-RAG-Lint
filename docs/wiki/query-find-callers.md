# query find-callers

Lists callers of a routine by name, with an option to restrict results to
precise, resolved callers. Reach for it to see who calls a given routine
across the index -- and, with `--resolved`, who reads or writes a property or
field and who reads an enum value.

## Running it from the CLI

```
drag-lint query find-callers --name <callee-name> [--context N] [--resolved] [--db ...] [--json]
```

`--name` is the callee to look up -- the **bare member name**. `--name
TFoo.Bar` silently returns 0 rows; `--name Bar` returns the call sites.
`--context N` adds N lines of surrounding source.

Several `--db` give ONE answer: `--json` is a single array holding every
database's rows, and the text form ends with one `N caller(s)` total.

## Plain vs `--resolved`

Without `--resolved` the answer is every site whose NAME matches -- complete,
but a same-named routine elsewhere is listed too. `--resolved` answers from
what the resolver bound, grouped by target:

| You name | `--resolved` lists | Tag |
|---|---|---|
| a routine | its resolved call sites (`call_edges`) | `certain` or `ambiguous` |
| a property or field | every bound access (`member_accesses`) | `[certain, read]` / `[certain, write]` |
| an **enum value** | every bound READ, bare (`cmdDelta`) or qualified (`TCommandID.cmdDelta`) -- one row per site | `[certain, read]` |

A write through `Self` (`Self.FFlag := False`) is listed as `[certain, write]` on
an index parsed with extractor 1.20.0-alpha or later -- earlier it was indexed as
a READ -- and it always names the field, even when a local of the same name is
in scope.

The enum-value rows need an index resolved at resolver 1.6.0-alpha or later;
an older index answers 0 until `index --all --resolve-only` has run. A read the
resolver DECLINED (two visible candidates, or a same-named local, constant or
member in scope) is not listed, so an absent caller means "not bound with
certainty", never "not present".

**Which line a row names.** Every `--resolved` row -- call, property/field
access, enum-value read, parenless call, callback -- names the CALL SITE: the
text form prints `(<file>:<site line>)` and the JSON `line` key is the same
number. The caller routine's own declaration line is a separate JSON key,
`caller_line`, omitted when the enclosing routine is unknown (a unit-level
reference). Key order: `caller_qname, file, confidence, target_qname, line,
caller_line, mode, resolution`. Before 2026-09-23 the JSON `line` on every row except a
callback was the caller's DECLARATION line, and the text form printed no line
for those rows.

**`resolution` -- how sure each row is (XERJ item 3).** Every `--json` row of
`find-callers` (both forms), `find-callees` and `usages`, and the `context`
bundle, carries a derived `resolution`, always the LAST key: `exact` (a certain
call edge, or a reference the resolver bound), `ambiguous` (an ambiguous edge,
e.g. overloads), `external` (the callee lives in a library DB, via
`refs.external_target`), `name-only` (no edge and no external target: the row
matched by NAME alone, e.g. a `--resolved` callback reach, or a call on a
receiver the index cannot type). Nothing is stored for it; it is read from
`call_edges` and `refs`. Text output ends `N callers (9 exact, 1 ambiguous, 2
name-only)` and marks non-exact rows `[name-only]` / `[ambiguous]`. `context`
JSON gains a `caller_resolution` count object. Guard
`tests\autotest\run_resolution_kind.ps1`.

**One known wrong-bind risk, on BARE enum reads only.** Inside a `with`
whose target the index cannot type (since resolver 1.8.0-alpha the `with` scope
is modelled, and wherever the target types a with member wins), a bare name can
bind to an enum value the compiler would not have chosen. Verify such a binding
against the declaration. A bare read of a `{$SCOPEDENUMS ON}` value is never
bound to the value since resolver E14 (1.36.0); lint rule `enum-bare-read-scoped`
reports it -- a warning when the name binds to another symbol and the types say
the enum may be meant, a hint when unbound.
Qualified reads (`TEnum.Value`) are unaffected.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | at least one caller listed |
| `1` | **zero callers** -- a valid answer, not an error. Text prints `0 caller(s)`; `--json` prints `[]` (with or without `--resolved`) |
| `2` | usage error (no `--name`), or a `--db` that is missing or at an old schema; also a manifest-resolved list whose every database is stale |
| `3` | fatal: an unrecognised flag or an exception (message on stderr) |

Zero callers is exit `1` on purpose (grep's convention): it is the only signal a
script has for "nothing calls this" without parsing the text. A handler wired
only from a `.dfm` has no call site, so it answers `1` too.

## Reaching it in the IDE

Not reachable through a main-menu item. The plugin's CodeLens cache
(`DragLint.Plugin.CodeLensCache.pas`) runs it to power the inline
caller-count annotations in the editor.

## What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example

Illustrative:

```
drag-lint query find-callers --name DoWork --resolved --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
drag-lint query find-callers --name cmdDelta --resolved --json --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

The first lists every resolved caller of every routine named `DoWork`,
grouped by target as certain or ambiguous. The second lists every bound read
of the enum value `cmdDelta`, tagged `[certain, read]`.

For the same data as a chart, see [`ask who-calls`](ask-who-calls) and
[`ask protocol-trace`](ask-protocol-trace).
