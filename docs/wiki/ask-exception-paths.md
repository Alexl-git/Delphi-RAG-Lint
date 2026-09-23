# ask: exception-paths

**What can this routine raise, and where is each exception caught?** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question exception-paths --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the routine under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question exception-paths -Target <Unit.Class.Method> -DbPath <project.sqlite> [-Depth 3] [-Cap N]
```

## You select

A method or routine.

## The chart shows

For the selected routine:

* the exception types it RAISES, each anchored to its raise site;
* the types it HANDLES in its own body (`try ... except` / `on E: T do`);
* for every raised type, WHERE it is caught up the caller chain -- walked call edge by call edge.

A routine can catch an exception on one call and let it escape on another; the chart draws both paths.

## Parameters

* `-Depth` (default 3) -- how many caller levels each exception is followed.
* `-Cap` -- the maximum number of callers walked per level; the rest are counted, not dropped silently.

## Read it carefully

* **Solid vs dashed.** A "caught" edge is SOLID only when the call site is verified to sit inside the handler's `try`. Otherwise it is dashed and tagged `[inferred]`.
* **Re-raise does not stop the walk.** A handler that re-raises (`raise;`) is drawn, and the exception keeps going up.
* **External ancestry.** When a handler's class ancestry is not in the index (a library type the project index does not hold), the edge reads "may catch -- ancestry not in this index".
* **It never says "unhandled".** It says where the walk ENDED: "escapes after N levels", "no resolved caller of its own", or "N callers not walked (cap)". Absence of a handler in the index is not proof that none exists at runtime.
* **Callers the index does not bind are not walked.** Parenless calls such as `NextId` bind from resolver 1.7.0-alpha; on an index resolved earlier, those callers are missing until `index --all --resolve-only` runs.

## It stands on

The raise and handler sites in the routine bodies, resolved `call_edges` for the caller walk, and the index's type ancestry to decide whether `on E: T do` catches a given exception class.
