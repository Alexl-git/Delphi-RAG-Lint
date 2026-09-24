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

```
1 circular unit group(s) found:
  [2 units] customers <-> orders   (has interface coupling -- widest recompile blast radius)
      customers uses orders  [interface  <-- move-to-implementation candidate]
      orders uses customers  [implementation]
```

### `cycles --causes` -- the exact symbol that forces the cycle

```
1 circular unit group(s) found:
  [2 units] customers <-> orders   (has interface coupling -- widest recompile blast radius)
      * customers's INTERFACE needs orders via:
          line 13: TOrder  [class]  -> move/extract this
```

### `cycles --plan` -- a mechanical refactoring playbook

An excerpt (the full output is in [REPORT.md](REPORT.md)):

```
### Step 1: what moves where
1. `TOrder` -- **class with methods**, declared at `Orders.pas` lines 6-19; method bodies at `Orders.pas` lines 30-35, 37-44.
   - Recipe: **extract a base class** and keep `TOrder` where it is. Why: its method bodies use `TCustomer`, which live in units of this cycle; moving the class would mean moving those bodies (lines 30-35, 37-44) AND everything they use.
   - New class `TOrderBase` in `Orders.Contracts` carries exactly what the units below use: nothing (an empty base).
   - `TOrder` stays in `Orders.pas` and becomes `TOrder = class(TOrderBase)`; the members above are deleted from it.
   - Units that switch to `TOrderBase` (the name is replaced on these lines): `Customers.pas` lines 13, 16, 30.

### Step 2: uses clauses -- keep, move or remove the old unit
- `Customers.pas` / `Orders`: nothing from it is used there any more -> **remove** it from the interface uses.
```

It goes on with the full text of the new unit, every edit with its current and
new text (bottom-up), and a checklist that ends in the exact output `cycles`
must print afterwards -- here `No circular unit dependencies found.`

The index can miss some references (e.g. `set` types), so the checklist compiles
the project and re-runs `cycles`; it lists what to do for each compile error the
edits can produce.
