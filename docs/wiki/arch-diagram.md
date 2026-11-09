# arch-diagram

Draws one HTML file showing which folder of a project sits on which, with the layers measured from the `uses` clauses. Reach for it when you want the shape of a project in a file you can open anywhere or attach to a ticket. It needs no Graphviz and fetches nothing.

## Running it from the CLI

```
drag-lint arch-diagram --db <db> --output <file.html>
drag-lint arch-diagram --db <db> --json
```

Without `--output` the page goes to stdout. `--json` prints the model (`drag-lint.arch/1`) instead of the page. The verb only reads; the same DB gives the same bytes, since nothing in the output depends on the clock.

## Reading the picture

* A box is a source folder below the project's common root, with its most used units.
* A folder sits above what it uses. Layer 0, at the bottom, is the foundation.
* The number on an arrow is the count of `uses` entries, in both interface and implementation sections.
* Click a folder for all its units with `file:line` and its arrows. Click an arrow for the `uses` lines behind it. Click the background to clear. The drawing and its tooltips work without script; the click panel does not.

| arrow | meaning |
|---|---|
| solid grey | forward: the larger direction of its pair, or the only one. Faint when a longer forward path also implies it (`implied` in the model); shown in full when its folder is picked |
| dashed red | back-edge: the smaller direction of a pair used both ways. A measurement, not a violation: the index declares no layer order |
| dotted amber | tangle: inside a cycle of forward arrows, so those folders share a layer |

## Read it carefully

* **Externals are left out.** A `uses` entry with no target in the index (RTL, a library) is counted in the header and not drawn. `ask architecture` shows the third-party groups.
* **A unit missing from the project is missing here.** The index is the compile closure; run `reconcile-project` first.
* **Stale index, stale picture.** The page names the DB and its indexer fingerprint; reindex and regenerate.
* **Non-ASCII names** follow `--output-encoding`, as every `--output` does: the default writes them as `\uXXXX`.

See also: [ask: architecture](ask-architecture), [Export Graph (DOT)](Export-Graph-DOT).
