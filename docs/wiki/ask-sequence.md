# ask: sequence

**The calls one routine makes, in source order, as a sequence diagram.** One column per participant (the routine's own class first, then every class or unit it calls into, in order of first call), one numbered arrow per call. One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

Answered in-process by the engine (`drag-lint ask`) (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask sequence --target MyApp.Orders.TOrder.Submit --db <project.sqlite>
```

`--cap N` bounds the calls drawn (default 40); the rest is counted in the chart's footer.

## You select

A method, procedure or function, by bare or qualified name. A routine that makes no calls in the index is refused.

## The chart shows

The routine's `call` references in the order the index recorded them (line, then column), drawn top to bottom, numbered 1..n. The receiver of a call is the class that declares the called routine (the unit, for a free routine); a call the resolver could not tie to a declaration lands in the column "(unresolved)". Each arrow is anchored to its call site, each column header to its class.

## It stands on

`refs` of kind `call` with the routine as `enclosing_symbol_id`, and `call_edges` (the resolved target and its declaring type). The order is the refs order of the routine, nothing is re-sorted by target.

## Read it carefully

* Only the calls written in the routine's own body are drawn; the diagram is one level deep (use [`what-it-calls`](ask-what-it-calls) or [`path`](ask-path) for the transitive tree).
* The order is source order, not execution order: a call inside a loop or an `if` is drawn once, where it is written.
* A call through an interface or a virtual method is drawn to the declaring type the resolver chose, not to every possible implementor.
