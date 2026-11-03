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
## Output contract for consumers (G1, G2, G5)

The engine stands behind these statements for the `#migrate` items of `convert-apply --json`
(confirmed by bytes 2026-10-23). A consumer such as the rules editor may rely on them.

* **Item texts are verbatim (G1).** `access_sites[]`, `todos[]` and `warnings[]` hold the item `text`
  verbatim, one entry per item, so a consumer may match on the exact text. The engine does not reword an
  item without a version note.
* **Silences (G2).** (a) A block with no converted instance in the unit yields no item for any of its lines
  (a scoped line in such a block is silent too). (b) `#migrate X -> X` (identity) yields no item; the editor's
  pre-check speaks for identity, the engine stays silent. (c) A `#migrate` line before the first header
  yields no item.
* **Block extent (G5).** A block is a header line up to the next header line or the end of the file. Blank
  lines and comments inside a block are not separately specified; a consumer must not depend on them.

Also shipped from the same list (no action): the native deliberate-break status (G4), `rules_file` on
`pas_uses` rows (G7), `DL_NONE` left out of the uses reconciliation (G8), `from_type` / `to_type` filled (G9),
a diagnostic for the `with` site (G10) and `old_value` on `migrate-check` items (G11). Open ask for a later
slice: `convert-validate` echoing the refusal text per `#migrate` line, so it is visible before a run.
## Gate
`drag-lint info --json` -> `capabilities.migrate_members: true`.
Contract for the converter editor: `docs/NOTICE-2026-10-19-c18-slice1-migrate.md`.