# convert-apply #migrate (member rename / DL_NONE)

Member replacement, slice 1 (C18). Inside a `#convert From -> To` block of a
conversion-rules book, `#migrate` now changes the CODE that uses a converted
component: a method, event or property of the From type that the To type
spells differently is renamed at every access site, or marked for hand
conversion with `DL_NONE`.

## Rule forms
```
#convert TSrcBtn -> TDstBtn
#link Caption <- Caption
#migrate Click -> Press        { btnTop.Click        -> btnTop.Press }
#migrate OnClick -> OnPress    { btnTop.OnClick := H -> btnTop.OnPress := H }
#migrate Count -> DL_NONE      { N := btnTop.Count   -> N := DL_NONE(btnTop.Count) }
```
`DL_NONE` is a deliberate break: the old text is kept inside the marker, and
the unit fails to compile on exactly those lines until someone converts them.

## Running it from the CLI
```
drag-lint convert-apply --unit Form1.pas --rules book.rules --db x.sqlite [--apply] [--format json]
```
JSON `items[]` gains `migrate-applied` (field `access_sites`),
`deliberate-break` (field `todos`) and `migrate-check` (field `warnings`);
`pas_uses[]` reports a covered member as `mapped`.

## What is never rewritten
A member reached through `with btnTop do`, a site whose receiver the index
cannot tie to the converted field, a scoped or template `#migrate` (slice 2),
and a member a `#link` already converts -- each is a `migrate-check` warning.

## Gate
`drag-lint info --json` -> `capabilities.migrate_members: true`.
Contract for the converter editor: `docs/NOTICE-2026-10-19-c18-slice1-migrate.md`.