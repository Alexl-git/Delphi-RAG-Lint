# convert-apply #migrate (member, type and enum rename / DL_NONE)

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

## Types, enums and other identifiers (1.38)
A `#migrate` at FILE scope (before the first `#convert`), or one inside a block
that names a uses unit or whose target is an enum value, renames an IDENTIFIER
in the code, not a member of a converted instance:
```
#migrate TDBScreenCursor -> TFDGUIxScreenCursor, FireDAC.UI.Intf
#migrate dcrOther -> gcrNone        { explicit member line: overrides the name match }
```
* Every bare `Old` token outside comments and string literals is renamed: var,
  param, field and result types, casts, `is` / `as`, generic arguments, enum
  literals. `items[]` kind `migrate-applied` (no instance).
* The target `New` must resolve in a supplied `--db` (the platform library or
  the project index); otherwise each site is a `migrate-check` and nothing is
  renamed. The `Old` side is trusted: a type no index knows any more is still
  renamed.
* Two enums: each member of `Old` is mapped to the member of `New` with the
  same name after the lowercase prefix (`dcrHourGlass` -> `gcrHourGlass`),
  never by ordinal. An explicit `#migrate` member line wins. A member with no
  counterpart that the unit uses is a `migrate-check` on its line.
* A qualified site (`Data.DB.TUpdateKind`, `obj.Old`) is a `migrate-check`,
  not rewritten; `TEnumOld.member` (the From enum as qualifier) is renamed.
* `Old` declared in the unit itself, or converted by a `#convert`, is a
  `migrate-check` per site.
* The unit declaring `New` is added to uses (the interface uses when a site is
  there).
Gate: `info --json` -> `capabilities.migrate_identifiers: true`.
Guard: `tests\autotest\run_convert_apply_migrate_type.ps1`.
## Gate
`drag-lint info --json` -> `capabilities.migrate_members: true`.
Contract for the converter editor: `docs/NOTICE-2026-10-19-c18-slice1-migrate.md`.