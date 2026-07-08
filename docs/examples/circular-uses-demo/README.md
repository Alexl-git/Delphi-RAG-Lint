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
          line 16: TOrder  [class]  -> move/extract this
```

### `cycles --plan` -- a followable refactoring playbook

```
# Cycle refactoring playbook

## Cycle 1: customers <-> orders

Files:
- `customers` -> ...\Customers.pas
- `orders`    -> ...\Orders.pas

### Why it cycles
- `customers` interface uses `TOrder` (class) at `Customers.pas:16`; declared in `Orders.pas:10`.

### Recommended fix
**Extract the shared contract** into a new leaf unit both can depend on (it must use NEITHER unit in this cycle).

Steps:
1. For each symbol under "Why it cycles", create/reuse a leaf unit (e.g. `<Unit>.Contracts.pas`) holding ONLY that declaration.
2. Move the declaration there; add the new unit to the declaring unit's uses.
3. In each consumer, replace the cycle-partner in the **interface** uses with the new contracts unit.
4. Register the new unit in the .dpr/.dproj.
5. Build.
6. **Verify:** `drag-lint cycles --db <db>` -- cycle 1 should be gone.
```

The report is best-effort (the index can miss some references, e.g. `set` types),
so build after applying the fix and re-run `cycles` to confirm the group is gone.
