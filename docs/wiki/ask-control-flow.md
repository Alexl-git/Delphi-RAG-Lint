# ask: control-flow

**The control-flow graph of one routine, with a node cap that says where it stops.** Each box is a basic block (a run of statements with one way in), each arrow a possible jump: `if`, loops, `case`, `try`, `exit`, `raise`. One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

Answered in-process by the engine (`drag-lint ask`) (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask control-flow --target MyApp.Orders.TOrder.Submit --db <project.sqlite>
```

`--cap N` bounds the blocks drawn (default 40). When the routine has more, the chart's footer reads `stops at N of M blocks (cap N): K block(s) and E edge(s) not shown`, so a cut graph is never mistaken for the whole one.

## You select

A method, procedure, function, constructor or destructor, by bare or qualified name. A routine with no body in the index, or one that uses `goto` or inline `asm`, is refused with the reason.

## The chart shows

Blocks are numbered by the builder (B0 entry, B1 exit, then the statement blocks); a block's caption is its first statement, `(+n)` counts the others. Blocks are drawn breadth-first from the entry, so the cap keeps the start of the routine and cuts the tail. A block that ends in `raise`, `Halt` or `Abort` is tinted and marked `[no return]`. Each block is anchored to its first statement.

## It stands on

The routine's own source: the index names the routine and its body line, the file is parsed again and the routine goes through the same graph builder the flow lint rules use (`TCfgBuilder`). It is not stored in the index.

## Read it carefully

* The graph is built from the file on disk, not from the index snapshot: an edited but not re-indexed file can show a different graph than the index describes (the routine is found by its indexed body line; if that no longer matches, the question refuses).
* A call to a routine the index stores as `noreturn` is not treated as ending its block here; only `raise`, `Halt` and `Abort` are.
* Exception edges of `try` are drawn as the builder models them, not as every possible throw site.
