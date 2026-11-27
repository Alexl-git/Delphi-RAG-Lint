# Value Charts (value-origin, value-use)

**Where a value comes from, and where it goes.** Two chart questions over the `data_flows` facts of the
project index (`DRagLint.Charts.Q.ValueFlow`), numeric, Boolean and date-time values included since 1.56:

```
drag-lint ask value-origin --target U.TOrder.FTotal --project P.dproj
drag-lint ask value-use    --target U.TOrder.FQty   --project P.dproj --depth 3
```

## What you can ask

| Target | value-origin | value-use |
|---|---|---|
| a field `U.TOrder.FTotal` | every value written into it | every place its value reaches |
| a unit variable `U.GLastTotal` | the same | the same |
| a property `U.TOrder.Total` | writes through the property | reads through the property (not its backing field) |
| a parameter `U.Feed.pCount` | the arguments callers pass | where the routine sends it |
| a function `U.Twice` | what its result is built from | who consumes its result |
| a procedure | refused: it returns no value | - |

## Reading the chart

The selection is the focus node. **Step 1** is one row per flow that ends in the selection
(value-origin) or starts at it (value-use); **step 2** explains every step-1 row the same way, up to
`--depth` (default 2). Every row is clickable and opens the line where the value lands. An arrow points
the way the value flows; a dashed arrow is a flow on some paths only.

A row carries the **value class** of the flow in brackets:

| Tag | Meaning |
|---|---|
| `[int]` `[float]` `[currency]` `[datetime]` `[bool]` | a value row of the 1.56 extractor: the class the value had where it first became a scalar |
| no tag | a row every extractor since 1.26 writes: a string, an object, or a value the extractor could not class. It is NOT a claim that the value is text |

The emitter fields of `meta.json` keep the two sets apart: `ValueRows` counts tagged rows only,
`FlowRows` untagged rows only, `IntRows` .. `BoolRows` one class each. `ValueTracking` is false when the
index holds no value row at all.

## Where it stops, and says so

| Case | What the chart shows |
|---|---|
| index built before 1.56, or not re-parsed since | the focus says numeric, Boolean and date-time values are NOT tracked; string and object flows are still drawn. Re-index the project |
| a field assigned only from literals or constants | no row; the focus names the write sites it found ("a literal or a constant writes no row") |
| a local variable | not a node: the row joins the two ends and says "through a local" |
| a callee or member outside the index (`IntToStr`) | drawn by name, "not in this index", not followed |
| a call on an object (`Order.Total`) | the extractor reports the OBJECT as the source, not the method's result |
| a var / out argument or parameter | drawn, not followed |
| more rows than `--cap` in one step | counted on a "+N more rows not drawn" line |
| ends left at the last step | "stopped after N steps: M ends not followed -- ask again with a larger --depth" |

A chart with no numeric source on an index without value rows is silence, not proof.

## Flags

`--depth N` steps (default 2), `--cap N` rows drawn per step (default 20); the common `ask` flags
(`--project` / `--db`, `--out-root`, `--plain`) apply. See [Diagrams and Charts](Diagrams-and-Charts).
