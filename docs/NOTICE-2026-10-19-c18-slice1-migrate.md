# NOTICE for CONVERTER -- C18 slice 1: `#migrate` rename + `DL_NONE` (2026-10-19)

From: ENGINE. Branch `feat/122-c18` (from `rel/1.22`), not yet on main.
Spec: `docs/superpowers/specs/2026-10-11-member-replacement-design.md` (owner answers Q1-Q5).

## Gate

`drag-lint info --json` -> `capabilities.migrate_members` is the JSON literal `true`.
An engine without the key ignores `#migrate` inside a `#convert` block (it parses, never applies).

## Rule syntax (inside a `#convert From -> To` block only)

| Line | Effect at each bound `.pas` access site of the block's converted instances |
|---|---|
| `#migrate Old -> New` | member token renamed: `btnTop.Click` -> `btnTop.Press`, `btnTop.OnClick := H` -> `btnTop.OnPress := H` (methods, events, properties) |
| `#migrate Old -> DL_NONE` | member access wrapped, old text kept (owner Q2): `N := btnTop.Count;` -> `N := DL_NONE(btnTop.Count);`; `Self.btnTop.X` wraps whole |

`Old` and `New` are plain identifiers; `DL_NONE` is matched case-insensitively.
NOT applied in slice 1 (one `migrate-check` per rule, no edit): a scope prefix
(`Class:` / `obj.`), a call or assignment template (`ABC(...) -> ...`, `ABC := -> ...`),
trailing uses units (`, Unit`), `@user`, and a member a `#link` of the same block
(or a file-scope `#link`) already renames or casts, or an earlier `#migrate` of the
block already covers. A `#migrate` before the first `#convert` is unchanged
(not applied, not reported) -- globals are slice 3.

## apply/1 JSON

New `items[]` kinds (appended; existing kinds unchanged):

| kind | field | set |
|---|---|---|
| `migrate-applied` | `access_sites` | `instance`, `file`, `line`, `rule_line`, `path` = Old, `value` = New, `old_value` = the member as written |
| `deliberate-break` | `todos` | `instance`, `file`, `line`, `rule_line`, `path` = Old, `value` = `DL_NONE`, `old_value` = the wrapped text (`btnTop.Count`) |
| `migrate-check` | `warnings` | `rule_line`, `path` = Old, `value` = New; per site also `instance`, `line` (rule-level: `instance` '' and `line` 0) |

`migrate-check` reasons (in `text`): a `with <inst> do` line (never rewritten),
a receiver the index cannot vouch for, a line changed since indexing, a rule form
slice 1 does not realise, a member already converted by another line. A
`deliberate-break` whose `text` says `already DL_NONE-marked` made no edit (re-run).

`pas_uses[]`: a member a realised `#migrate` covers is status `mapped` (a `#link`
covering the same member keeps its own status). Same rows, same fields.

## Behaviour the editor can rely on

* Sites = the `#link` rename's own discovery + binding (FindMemberAccessSites /
  BoundAccessSites): an unconverted receiver of the same type is never touched.
* Idempotent: a renamed site no longer names Old; a wrapped site is not wrapped twice.
* A DL_NONE unit fails dcc64 on exactly the wrapped lines (E2003 `DL_NONE`).
* Guard: `tests/autotest/run_convert_apply_migrate.ps1`.
