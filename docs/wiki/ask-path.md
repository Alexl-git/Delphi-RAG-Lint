# ask: path

**Every shortest call path from routine A to routine B.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

**Planned engine verb -- `drag-lint ask` is not shipped yet.** Today ask this question with the chart pipeline command below, or with `Ask-Report.ps1` (see [Charts and the IDE](Charts-and-the-IDE)).

```
New-DiagramArtifact.ps1 -Question path -Target MyApp.Orders.TOrderService.Post -To MyApp.Db.TConnection.Commit -DbPath <project.sqlite>
```

The drag-lint > Reports menu entry for this question arrives with the IDE plugin's next question-list update; until then use the script.

## You select

Two routines: A (`-Target`) and B (`-To`).

## The chart shows

Every SHORTEST route of calls from A to B. Each arrow is one call, labelled with its call site (file:line; several sites when A calls B from more than one line) and its grade: `certain` (bound to this routine) or `ambiguous` (bound to it, but another candidate survived on the type chain). More than `-Cap` paths (default 20) are drawn as the first 20 plus "+N more shortest paths not shown" -- the count is exact.

## It stands on

The engine's `call-path` decides the question (found, and how many calls the shortest route takes); every route of that length is then enumerated over the same resolved `call_edges`, and `call-path`'s own path must be one of them or nothing is drawn.

## Parameters

`-Cap` (paths drawn, default 20). Run `charts\src\Emit-Path.ps1` directly for `-MaxDepth` (longest route searched, default 20 calls -- `call-path`'s own default).

## Read it carefully

Only RESOLVED calls are on a path: a call the index matched by name alone has no call edge, so it is never drawn (the Legend says so). "No call path from A to B" within the depth cap is a refusal, not an empty chart; so are A = B and a routine the index does not know. For everything within N hops of one routine, both ways, ask [`butterfly`](ask-butterfly) with `-Depth N` -- there is no separate "neighbours" question.
