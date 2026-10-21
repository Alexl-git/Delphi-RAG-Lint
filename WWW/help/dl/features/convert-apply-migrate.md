---
id: convert-apply-migrate
title: "convert-apply #migrate (member rename / DL_NONE)"
summary: "#migrate Old -> New / Old -> DL_NONE inside a #convert block renames or deliberately breaks a member at every bound .pas access site"
product: DL
group: component-conversion
order: 60002
since: 1.22.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# convert-apply #migrate (member rename / DL_NONE)

#migrate Old -> New / Old -> DL_NONE inside a #convert block renames or deliberately breaks a member at every bound .pas access site.

Read this when a component conversion changes the names of methods, events or properties the code uses. Inside a #convert block, #migrate Old -> New renames the member at every bound access site in the .pas; Old -> DL_NONE marks the site for hand conversion instead.

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
| `--format` |  |  |  |
| `--json` |  |  |  |

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

### Gate
`drag-lint info --json` -> `capabilities.migrate_members: true`.
Contract for the converter editor: `docs/NOTICE-2026-10-19-c18-slice1-migrate.md`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
