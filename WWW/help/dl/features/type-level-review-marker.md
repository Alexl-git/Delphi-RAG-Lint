---
id: type-level-review-marker
title: "Type-level dl:ok review"
summary: "One dl:ok on an enum type declaration reviews every unused-enum-value or enum-ordinal-cast finding of that type, in any unit"
product: DL
group: linting
order: 30026
since: 1.38.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Type-level dl:ok review

One dl:ok on an enum type declaration reviews every unused-enum-value or enum-ordinal-cast finding of that type, in any unit.

Read this when an enum mirrors ordinals stored outside the code (a DB byte, a wire protocol, streaming) and its filler values or ordinal casts are deliberate: one `dl:ok <rule-id>` on the type line reviews them all, instead of one marker per value or cast.

## Details

One `dl:ok` marker on an enum TYPE declaration reviews every finding of that
rule for that type -- every unused value, every hard-coded ordinal cast -- in
any unit. Owner rule, 2026-10-28 (lane ENUMRULES, 1.38).

### When to reach for it

Some enums mirror ordinals stored outside the code: a DB byte column, a wire
protocol, a streamed component property. Such a type can carry FILLER values
whose only job is to push a real value onto its stored ordinal (65 dummies so
`LotStatus_InspNotStarted` lands at `ord('A') = 65`), and its code casts
`TEnum(B)` and `Ord(E)` on purpose. Reviewing that once, on the type, is the
honest record; one marker per value or per cast is noise.

### How to write it

Put the marker on the line that declares the type -- the line with
`<Name> = (`:

```pascal
type
  LotStatusCodes = (  // dl:ok unused-enum-value -- REVIEWED 2026-10-28 values mirror stored DB ordinals
    LotStatus_Dummy0, LotStatus_Dummy1, ...
```

```pascal
  TCommandID = (  // dl:ok enum-ordinal-cast -- REVIEWED 2026-10-28 ordinals are the wire protocol
```

Accepted forms are the usual ones: `dl:ok <rule-id>`, `dl:ok <rule-id>@<hash>`,
`dl:ok <rule-id> -- <reason>`, `dl:ok <rule-id>: <reason>`. Two rules can share
one marker (`dl:ok unused-enum-value, enum-ordinal-cast -- <reason>`).

### Which rules honour it

| Rule | What the type marker silences |
|---|---|
| `unused-enum-value` | every unnamed value of the type |
| `enum-ordinal-cast` | every `TEnum(<literal>)`, `Ord(e) <cmp> <literal>` and `case Ord(e) of` on the type, in any unit |

Each finding of these rules carries its type's declaration as a SCOPE
(`TLintFinding.ScopeFile` / `ScopeLine`); the marker check in `lint`, `lint-all`,
`lint-project` and the editor gutter (LSP) reads that line as well as the
finding's own.

### How it stays honest

* **Hash.** Without `@hash` the marker suppresses and `review-marker-stale` says
  once (on the type line, not per finding) that it cannot be checked, with the
  hash to add. With a hash, it is the hash of the TYPE line; re-shaping that line
  re-reports the findings with a `review-marker-stale` hint.
* **Unused.** `lint-all` reports `review-marker-unused` for a type marker that
  suppresses nothing (the type has no finding of the rule). `lint <file>` does
  not judge a type marker on an enum declaration line: the casts it reviews may
  live in units that run never looked at.

### Filler values need no marker

`unused-enum-value` already skips a value named for its own ordinal --
`Dummy0` at 0, `None64` at 64 -- and any type with an implicit use (a cast,
`Ord`, `Low`/`High`, RTTI, a streamed property). The type marker is for what is
left.

### Related

* [allow](allow.md) -- record a line-level `dl:ok` for one finding
* [rules](lint-rules.md#unused-enum-value) -- `unused-enum-value`, `enum-ordinal-cast`

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
