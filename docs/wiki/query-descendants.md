# query descendants

The reverse of [`query ancestors`](query-ancestors.md): lists every **class**
that descends from a given ancestor, across all scanned databases. Reach for it
to answer "what derives from this?" -- it is what fills the conversion editor's
control-class pickers.

## Running it from the CLI

```
drag-lint query descendants --of <ancestor> [--db ...] [--json]
```

`--of <ancestor>` is required; there is no `--name` form.

## Classes only -- and that is deliberate

Derived **interfaces are excluded**. This verb backs class pickers, which must
never be offered an interface, so `--of <an interface>` lists the classes that
implement it and never the sub-interfaces that extend it.

That has a consequence worth knowing: an ancestor whose only descendants are
interfaces answers **nothing**. On the platform library,
`query descendants --of IFIBObject` prints no rows even though the index holds
`IFIBConnect`, `IFIBSQLObject` and `IFIBTransaction`.

**If you want the interface side, hover the interface instead.**
`drag-lint hover --qname <Unit.IFoo>` reports both, labelled separately:

```
- Implemented by: TFIBCustomDataSet, TFIBDatabase, ... (+14 more)
- Extended by: IFIBConnect, IFIBDataSet, IFIBQuery, IFIBSQLObject, IFIBTransaction
```

## Exit codes

`0` found at least one descendant · `1` no such ancestor (**not** an error --
it is the answer) · `2` usage error, or a stale/unusable `--db`.

The exit-1 case is load-bearing: an unconditional `0` would destroy the only
signal a caller has for "no such ancestor".

## Reaching it in the IDE

No IDE surface -- CLI only. The conversion rules editor consumes it through the
engine adapter.

## What it needs

`--db` is optional; drag-lint auto-resolves the index when it is omitted. An
index must exist.

## Example

Illustrative:

```
drag-lint query descendants --of TControl --db C:\Projects\.drag-lint\library-Win64.sqlite
```

This would list every `TControl` descendant in the Win64 platform library --
the set the conversion editor offers as conversion targets.
