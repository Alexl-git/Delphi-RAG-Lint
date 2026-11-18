---
id: v152-attrrules
title: debug-display-placeholder + attribute-aware member-could-be-private
summary: Warning (OFF in 1.52) on a DebuggerDisplay placeholder naming no member; member-could-be-private reads attributes from the index
product: DL
group: linting
order: 30068
since: 1.52.0-alpha
status: shipped
updated: 1.52.0-alpha
---

# debug-display-placeholder + attribute-aware member-could-be-private

Warning (OFF in 1.52) on a DebuggerDisplay placeholder naming no member; member-could-be-private reads attributes from the index.

Read this to see what debug-display-placeholder reports, when it stays silent, and how member-could-be-private now uses the attributes index fact instead of the source line.

## How to run it

```text
drag-lint lint <file> --rule debug-display-placeholder --db <db> (default OFF in 1.52; a [DebuggerDisplay('..{Name}..')] placeholder naming no member of the type, read from the attributes index fact; category bug-patterns, warning)
```

Example:

```text
drag-lint lint <file> --rule debug-display-placeholder --db <db>
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--rule` | `<id>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

1.52 indexes every custom attribute and the declaration it decorates (the `attributes` table,
see [Index-DB-Schema](v152-attributes-fact.md)). Two rules read it instead of the source text.

### debug-display-placeholder (warning, bug-patterns, default OFF)

A `[DebuggerDisplay('...')]` attribute on a class or record whose template names a member the
type does not have: the debugger then shows the placeholder or an error instead of the value.

```pascal
[DebuggerDisplay('Nmae={Nmae}')]   // reported: TTypo has no member Nmae
TTypo = class
public
  Name: string;
end;
```

Run it with `drag-lint lint <file> --rule debug-display-placeholder --db <db>` or
`drag-lint lint-all --db <db> --rule debug-display-placeholder`. Delphi itself ships no
DebuggerDisplay attribute and dcc never checks the template; the rule judges any attribute named
`DebuggerDisplay` or `DebuggerDisplayAttribute` (unit-qualified or not).

What it checks: the first argument must be ONE string literal; every `{...}` placeholder is
judged by its leading identifier (`{Count,nq}` -> Count, `{Owner.Name}` -> Owner) against the
members of the type and its class ancestors, case-insensitively. A doubled `{{` is a literal brace.

It stays silent whenever it cannot prove the member absent:

| Case | Why silent |
|---|---|
| the index has no attributes table (built before 1.52) | no fact to read |
| the first argument is not one string literal (a constant, a concatenation) | the template is not known |
| a placeholder that does not start with an identifier (`{ }`, `{1+2}`) | not a member reference |
| `{Self}` | the object itself |
| an ancestor that neither the project nor the library index places | its members are unknown |
| the attribute decorates something other than a class or record | not a type display |

Without a library index, `TObject`'s own members (`ClassName`, `ToString`, ...) come from a
built-in list. Not checked: whether a named property is readable.

### member-could-be-private reads attributed members from the index

`member-could-be-private` (see [v152-atlb-rules](v152-atlb-rules.md)) never reports a member that
carries an attribute. It now asks the attributes table which symbol each attribute decorates, so
an attribute split from its member by a comment or spread over several lines still exempts it,
and a member that merely follows a line starting with a PARAMETER attribute (`[ref] const B`) is
judged like any other. An index without the table falls back to the old one-line source peek.

### rtti-unavailable

`rtti-unavailable` has no attribute peek to drop: its six sub-kinds read compiler directives
and explicit enum ordinals, which no index fact holds. Unchanged.

Guard: `tests\autotest\run_v152_BK-ATTRRULES.ps1`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
