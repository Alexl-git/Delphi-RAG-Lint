# Diagrams and Charts

**Ask the index a question, get a chart back.** The `ask` verb family turns
one formal question about one selected symbol into a clickable diagram: who
calls this, what breaks if I change it, which tests reach it, what does this
form wire, where does this protocol command travel. It ships in the **charts
release**; the chart pipeline behind it (`New-DiagramArtifact.ps1`) runs today.

drag-lint is not a model, and these charts are not drawn from prose. Every
diagram comes from a FORMAL CALL -- a question id, a selection and parameters
-- and every row in it is a fact from the index with a file and a line.

## The call

```
drag-lint ask --list --at <file.pas>:<line>:<col> --db <project.sqlite> --json
drag-lint ask --question <id> --at <file.pas>:<line>:<col> --db <project.sqlite>
              [--depth N] [--format svg|mermaid|json]
```

* `--list` resolves the selection and returns ONLY the questions valid for its
  kind -- a method gets `butterfly`, `who-calls`, `effects`...; a unit gets
  `deps` and `cycles`; a form class gets `lifecycle` and `event-wiring`. An
  editor never hard-codes the menu; it asks and renders what comes back.
* `--at` is a caret position, resolved exactly as
  [Type at Cursor](Type-at-Cursor) (`typeat`) resolves one.
* `--db` is the project index, as everywhere else -- and the platform library
  index after it when an RTL/VCL ancestor or type should resolve.

The same questions by NAME, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question <id> -Target <Unit.TType.Member | Unit | project> -DbPath <project.sqlite>
                        [-Depth N] [-Cap N] [-OutRoot <dir>] [-Open]
```

## The questions

| Question | You select | The chart shows |
|---|---|---|
| [`butterfly`](ask-butterfly) | method | callers and callees in one chart |
| [`who-calls`](ask-who-calls) | method | N-deep caller tree, cycle-guarded |
| [`what-it-calls`](ask-what-it-calls) | method | N-deep callee tree |
| [`who-writes`](ask-who-writes) | field / property | every routine that assigns it |
| [`who-reads`](ask-who-reads) | field / property | every routine that reads it |
| [`change-impact`](ask-change-impact) | method / type | everything a change here could break, by zone and hop |
| [`tested-by`](ask-tested-by) | any symbol | the DUnitX tests whose call trees reach it |
| [`effects`](ask-effects) | method | what it mutates, and whether it is **Effect-free (proven)** |
| [`touches-tables`](ask-touches-tables) | method | which database tables it reads and writes |
| [`class-surface`](ask-class-surface) | type | members by visibility |
| [`hierarchy`](ask-hierarchy) | type | ancestors above, descendants below |
| [`deps`](ask-deps) | unit | used-by and uses, grouped by source directory |
| [`cycles`](ask-cycles) | unit / project | circular dependencies, every edge drawn |
| [`wiring`](ask-wiring) | interface | Spring4D registrations and resolve sites |
| [`lifecycle`](ask-lifecycle) | form class | create -> show -> destroy: wired / implemented-not-wired / absent |
| [`event-wiring`](ask-event-wiring) | form class | which handler runs on which control event |
| [`architecture`](ask-architecture) | project | units as source-directory zones, back-edges in red |
| [`protocol-trace`](ask-protocol-trace) | command constant / method | where a protocol command travels |
| [`crosses-boundary`](ask-crosses-boundary) | method | whether and where the work leaves the process |
| [`shown-where`](ask-shown-where) | database column | which forms and controls display it |
| [`exception-paths`](ask-exception-paths) | method | what it raises, what it handles, and where each exception is caught up the caller chain |
| [`consumers`](ask-consumers) | table / column | the routines that read and write it, plus its triggers, procedures and indexes |

Two more questions are **shipping with the charts release**. What each one
answers is fixed; their parameters are still settling, so they are described
here without syntax:

| Question | Answers |
|---|---|
| [`feeds-from`](ask-feeds-from) | the chain behind a data-aware control: control -> datasource -> dataset -> table |
| [`lands-where`](ask-lands-where) | where a field's value ends up: field -> dataset -> table.column |

## What you get

Every answer is a **bundle** written to one folder named after the question
and the selection:

| File | What it is |
|---|---|
| `graph.svg` | The chart. Every row is a real link (see *Click to source*) |
| `graph.png`, `graph.pdf` | Raster and document exports of the SAME layout |
| `graph.dot`, `graph.plain` | The Graphviz input and the layout geometry. One `dot` run writes all four outputs, so the picture and its hit-test geometry cannot drift |
| `index.html` | A browser shell around the chart, with the counts in its header |
| `meta.json` | The index fingerprint (path, size, mtime), every count the question produced, and the exact command that regenerates the bundle -- so a stale chart is DETECTABLE, not merely suspected |
| `xref.txt` | A DocInsight `<remarks>` block to paste into the unit, pointing at the chart |

**These are not autodocumentation.** A chart is large, slow to produce and
stable over time, so nothing generates one on a build. You ask deliberately and
paste the REFERENCE; the volatility lives in the file (a stable path plus a
regenerated artifact), never in the comment.

## How to read one

* **Rows, not nodes.** Symbols are clickable text rows inside one rounded box
  per unit (or per source directory), so 30 routines read as 6 boxes and every
  row keeps its own file and line.
* **Nothing is dropped silently.** When a cap hides rows the chart says
  `+N more ... not shown`; the header always carries the totals.
* **Certain vs inferred.** A row reached by a resolved edge is certain; a row
  reached only by NAME (another routine that happens to share the name) is
  marked, and an inferred edge is drawn dashed.
* **A refusal is an answer.** `touches-tables` on an index that owns no
  database connection, or `wiring` on a class, refuses with the reason instead
  of drawing an empty chart that would read as "nothing".

## Click to source

Each row in `graph.svg` links to `draglint://open?file=<path>&line=<n>`. With
the protocol registered (one HKCU key, no elevation:
`Register-DragLintProtocol.ps1`; `-Unregister` undoes it), a click opens the
line in RAD Studio through the drag-lint IDE plugin's open-source pipe
(`\\.\pipe\drag-lint-open-source`), or in the default editor when no IDE is
listening.

## Requirements

* A project index (`<project folder>\_D-RAG\<project>.sqlite`), fresh -- a
  stale index draws a stale chart, and `meta.json` records which one was used.
* Graphviz `dot` (layout engine) on the machine.
* `protocol-trace` and `crosses-boundary` need an index resolved at resolver
  1.6.0-alpha or later (enum-value binding); run `index --all --resolve-only`
  once on an older index.

## Samples -- drag-lint's own code

All three were produced by the chart pipeline against a COPY of drag-lint's
self-index (`src\cli\_D-RAG\drag-lint.sqlite`, engine 1.17.0-alpha, resolver
1.6.0-alpha). The SVG files are in the repository under
`docs/Images/charts/`; their rows link back to the source.

### change-impact: one function feeds closure, parse and lint

![change-impact of ProfileFromDproj](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/change-impact-ProfileFromDproj.png)

Question `change-impact`, target `DRagLint.Preprocess.Profile.ProfileFromDproj`,
depth 3: **15 routines** over 1 unit reach it within 3 caller hops --
`pp-profile` and `ResolveIndexProfile` directly, then the project closure
(`BuildProjectFileScope`), `index`, `lint`, `lint-all`, `reconcile-project` and
`document --project`. That is why the platform-PropertyGroup fix to this one
function moved the extractor version. Command:
`Emit-ChangeImpact.ps1 -Target DRagLint.Preprocess.Profile.ProfileFromDproj -DbPath <copy of drag-lint.sqlite> -Depth 3 -Cap 16`
(the question's emitter, run directly so all 16 rows show; `New-DiagramArtifact.ps1`
uses 8 rows per zone and discloses the rest).
[SVG](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/change-impact-ProfileFromDproj.svg)

### deps: where the linter sits in the layering

![deps of DRagLint.Lint.Linter](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/deps-Lint-Linter.png)

Question `deps`, target `DRagLint.Lint.Linter`: **6 units use it** (the CLI unit and
program file, two LSP units, the MCP server, one lint unit) and **it uses 9** (core, parser,
diagnostics, tree-sitter, three lint units), each grouped by `src\` folder.
Dashed = an implementation-section `uses`. Command:
`New-DiagramArtifact.ps1 -Question deps -Target DRagLint.Lint.Linter -DbPath <copy of drag-lint.sqlite>`.
The whole-project [`architecture`](ask-architecture) question on the same index
draws 129 units in 23 zones with 598 internal edges -- accurate and too dense
to read at page size, which is why a one-unit `deps` is the sample here.
[SVG](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/deps-Lint-Linter.svg)

### butterfly: the enum-value binding entry point

![butterfly of ResolveEnumValueRead](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/butterfly-ResolveEnumValueRead.png)

Question `butterfly`, target
`DRagLint.Index.CallResolver.TCallResolver.ResolveEnumValueRead`, depth 2:
**2 callers** (the store's enum-value and call-target resolve passes) and
**14 callee rows** (scope checks, the identical-copy collapse, and the symbol
store lookups). Command:
`New-DiagramArtifact.ps1 -Question butterfly -Target DRagLint.Index.CallResolver.TCallResolver.ResolveEnumValueRead -DbPath <copy of drag-lint.sqlite> -Depth 2`.
[SVG](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/butterfly-ResolveEnumValueRead.svg)

## Related verbs that print graphs as text

[`butterfly`](butterfly), [`callgraph`](callgraph), `reverse-calltree`,
`graph --format dot|mermaid`, `cycles`, [`deps-report`](deps-report) and
`impact` print the underlying data as dot, mermaid, text or JSON. The `ask`
questions render it -- grouped, capped with disclosure, and clickable.
