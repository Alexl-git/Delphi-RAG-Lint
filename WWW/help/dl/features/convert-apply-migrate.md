---
id: convert-apply-migrate
title: "convert-apply #migrate (member, type and enum rename / DL_NONE)"
summary: "#migrate renames or DL_NONE-breaks a member at its .pas access sites; at file scope (or with a uses unit) it renames a type, enum or identifier"
product: DL
group: component-conversion
order: 60002
since: 1.22.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# convert-apply #migrate (member, type and enum rename / DL_NONE)

#migrate renames or DL_NONE-breaks a member at its .pas access sites; at file scope (or with a uses unit) it renames a type, enum or identifier.

Read this when a component conversion changes the names of methods, events or properties the code uses. Inside a #convert block, #migrate Old -> New renames the member at every bound access site in the .pas; Old -> DL_NONE marks the site for hand conversion instead. A #migrate at file scope (or naming a uses unit) renames a type or enum identifier in the code -- declarations, casts, is/as, generic arguments, enum literals -- maps enum members by name, adds the new unit to uses, and warns on every site it does not rename.

## How to run it

Full flag list: [convert-apply in the CLI reference](../cli.md#convert-apply).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--unit` | `<F.pas>` |  |  |
| `--rules` | `<file>` |  |  |
| `--db` | `PATH` |  |  |
| `--only` |  |  |  |
| `--castlib` | `<file>` |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--no-warn-unlinked` |  |  |  |
| `--no-reconcile-uses` |  |  |  |
| `--no-reindex` |  |  |  |
| `--old-platform-db` | `<file>` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

**Needs:** index

## Details

Member replacement, slice 1 (C18). Inside a `#convert From -> To` block of a
conversion-rules book, `#migrate` now changes the CODE that uses a converted
component: a method, event or property of the From type that the To type
spells differently is renamed at every access site, or marked for hand
conversion with `DL_NONE`.

### Rule forms
```text
#convert TSrcBtn -> TDstBtn
#link Caption <- Caption
#migrate Click -> Press        { btnTop.Click        -> btnTop.Press }
#migrate OnClick -> OnPress    { btnTop.OnClick := H -> btnTop.OnPress := H }
#migrate Count -> DL_NONE      { N := btnTop.Count   -> N := DL_NONE(btnTop.Count) }
```
`DL_NONE` is a deliberate break: the old text is kept inside the marker, and
the unit fails to compile on exactly those lines until someone converts them.

### Running it from the CLI
```text
drag-lint convert-apply --unit Form1.pas --rules book.rules --db x.sqlite [--apply] [--format json]
```
JSON `items[]` gains `migrate-applied` (field `access_sites`),
`deliberate-break` (field `todos`) and `migrate-check` (field `warnings`);
`pas_uses[]` reports a covered member as `mapped`.

### What is never rewritten
A member reached through `with btnTop do`, a site whose receiver the index
cannot tie to the converted field, a scoped or template `#migrate` (slice 2),
and a member a `#link` already converts -- each is a `migrate-check` warning.

### Types, enums and other identifiers (1.38)
A `#migrate` at FILE scope (before the first `#convert`), or one inside a block
that names a uses unit or whose target is an enum value, renames an IDENTIFIER
in the code, not a member of a converted instance:
```text
#migrate TDBScreenCursor -> TFDGUIxScreenCursor, FireDAC.UI.Intf
#migrate dcrOther -> gcrNone        { explicit member line: overrides the name match }
```
* Every bare `Old` token outside comments and string literals is renamed: var,
  param, field and result types, casts, `is` / `as`, generic arguments, enum
  literals. `items[]` kind `migrate-applied` (no instance).
* The target `New` must resolve in a supplied `--db` (the platform library or
  the project index); otherwise each site is a `migrate-check` and nothing is
  renamed, plus ONE rule-level `migrate-check` (line 0) per rule (1.42 MIGTGT,
  owner ruling 2026-10-28) -- the converter's editor shows it as a warning mark on
  the `#migrate` line. The `Old` side is trusted: a type no index knows any more is still
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
* No component instance needed (1.42): a unit with NO sibling `.dfm`, or a
  `.dfm` no `#convert` block matches, still gets its identifier `#migrate`
  sites renamed (`component_part` reads as before: `skipped-no-dfm`, `skipped-no-instances` or `applied`). A unit
  with no `#migrate` site keeps the old answer when the book has a `#convert` block (`sibling .dfm not found`,
  exit 1; `no convertible instances found`). A book with none says what is wrong with it, exit 1 (1.46):
  `no #migrate line of the rules file has a site in <unit>`, `the rules file holds no rules`,
  `the rules file has no #convert block, unit rule or #migrate line`; a parse error is named first
  (`conversion rules failed validation: line N: ...`), with or without a sibling `.dfm`.
* Old platform (1.43 ENUMMAP): `--old-platform-db <file>` (repeatable) names the index of the platform the
  code was written against, for example a Delphi 5 library DB. The From enum's members are read from it first
  and today's `--db` members are added after it, so a member today's enum lost still maps by name and is
  never silent. An enum only the old platform declares maps too. It never answers for a target: `New` must
  resolve in `--db`. A path that is no readable index exits 2. Without the flag the From enum is today's.
  Build that index once, on its own: `drag-lint index <D5 root>\Source --db <d5.sqlite>`.
  Capability `old_platform_enum_map`; guard `tests\autotest\run_convert_apply_old_platform_enum.ps1`.
Gate: `info --json` -> `capabilities.migrate_identifiers: true`.
Guards: `tests\autotest\run_convert_apply_migrate_type.ps1`; inherited `[n]` headers, a
whole-streamed collection and a file-scope `#migrate` in one D5-shaped child:
`tests\autotest\run_convert_apply_inherited_collection.ps1`.
### Output contract for consumers (G1, G2, G5)

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
### Gate
`drag-lint info --json` -> `capabilities.migrate_members: true`.
Contract for the converter editor: `docs/NOTICE-2026-10-19-c18-slice1-migrate.md`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
