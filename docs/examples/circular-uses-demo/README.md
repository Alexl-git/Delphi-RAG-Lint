# Example: detecting and untangling a circular unit dependency

A tiny, **compiling** two-unit project with a circular `uses` dependency, and the
report `drag-lint` generates to untangle it.

## The cycle

- [`Customers.pas`](Customers.pas) -- a `TCustomer` holds `TArray<TOrder>`, so its
  **interface** section `uses Orders`.
- [`Orders.pas`](Orders.pas) -- a `TOrder.Describe` reads the placing customer's
  name, so its **implementation** section `uses Customers`.

That is a real dependency cycle (`customers -> orders -> customers`). It compiles,
because Delphi only forbids a *mutual interface-section* cycle -- the closing edge
here is in the implementation section. (If you make BOTH edges interface-section,
the compiler rejects it outright: `F2047 Circular unit reference`.)

## How drag-lint reports it

`circular-uses` is a **built-in lint rule, ON by default**, so `drag-lint
lint-project` / `lint-all` flags the cycle automatically as a `warning`. For the
detailed "how do I fix this" report, use the `cycles` verb.

First index the example (any folder works):

```
drag-lint index path\to\circular-uses-demo --db demo.sqlite
```

The full, verbatim output for all three report levels is in
[REPORT.md](REPORT.md). The key excerpts:

### `cycles --edges` -- the cycle and its edges

<!-- dl:verbatim-cycles --edges -->
```
1 circular unit group(s) found:
  [2 units] customers <-> orders   (has interface coupling -- widest recompile blast radius)
      customers uses orders  [interface  <-- move-to-implementation candidate]
      orders uses customers  [implementation]
```

### `cycles --causes` -- the exact symbol that forces the cycle

<!-- dl:verbatim-cycles --causes -->
```
1 circular unit group(s) found:
  [2 units] customers <-> orders   (has interface coupling -- widest recompile blast radius)
      * customers's INTERFACE needs orders via:
          line 13: TOrder  [class]  -> move/extract this
```

### `cycles --plan` -- a mechanical refactoring playbook

An excerpt (the full output is in [REPORT.md](REPORT.md)):

<!-- dl:excerpt-cycles --plan -->
```
### Step 1: what moves where
Nothing can be moved mechanically.

**MANUAL -- not mechanical.** These symbols cannot be moved by the recipes above; their edge stays until you cut it by hand:
- `TOrder` (class, `Orders.pas` line 10): refused: base-class -- `Customers.pas:13`: `TOrder` is used here as something other than a parameter type (a field, variable, cast or type argument).
```

`TOrder` cannot move (its method bodies use `TCustomer`), and a base class may
stand in for it only where every use is a `const` or value parameter that its
routine merely reads members of or compares with nil. `Customers.pas` keeps a
FIELD of `TOrder` (line 13), so the plan refuses with `base-class` and names that
line instead of guessing; the rest of the playbook (uses decisions, edits, a
checklist ending in the exact `cycles` output) is in [REPORT.md](REPORT.md).
