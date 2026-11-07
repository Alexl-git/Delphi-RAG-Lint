<!-- dl:backlog status=open last-measured=2026-11-06 -->
# E-PARITY-ARCHIFY: architecture diagrams from the index (design + phase 1)

Lane x3, wave 146. **Branch NOT FOR MERGE until the owner has looked at the picture.** Background,
costs and the Archify review: `docs\BACKLOG-archify-parity.md` (2026-09-15/16). This note decides
what is left after what shipped since then.

## 1. What a user already has

| surface | gives | does not give |
|---|---|---|
| `graph --format dot\|mermaid` | one unit-to-unit edge list | layers, folders; every edge comes from a NAME join (`LOWER(s.name) = LOWER(r.name_text)`), so a common name makes an edge between unrelated units |
| `graph --format json\|html` (lane k4, branch lane/146-k4, not in this branch) | the same edges as `drag-lint.graph/1` and a page holding an edge LIST | a drawing: the HTML is `<ul>` rows plus the embedded JSON |
| `ask architecture` (charts) | folder zones, measured arrows from `unit_uses.target_file_id`, back-edges, third-party groups, as svg/png/pdf | no picture without Graphviz `dot.exe`; at most 6 units per zone (`MAX_PER_ZONE`); no way from an arrow to the `uses` lines behind it; no vertical order: dot ranks the zones, nobody says which is the foundation |
| `drag-lint Graph` viewer (`drag_lint_graph.exe`) | live symbol and flow graphs | a separate exe, not a file you can attach to a ticket |
| `lint-project --layers` | checks a layer order the USER wrote | it does not find one |

## 2. What Archify-style adds beyond them

Archify's value is a typed IR compiled into **one self-contained HTML file** a reader can open anywhere,
click around in, and keep. Applied to us, derived from the index and never authored:

1. **Measured layers.** The index declares no layer order; the diagram computes one from the `uses`
   facts (section 4) and draws it top to bottom: who sits on what, at a glance. That order is new
   output: no verb says it today, `lint-project --layers` could later be seeded from it.
2. **No Graphviz.** One file, no dot, no Node, no CDN, no fonts fetched. Mail it, attach it to a ticket.
3. **Evidence one click away.** Click a folder: all its units with `file:line` and the arrows in and out.
   Click an arrow: the unit pairs and `uses` lines behind the number. A back-edge stops being a red
   number and becomes the list of lines to fix. The rule "every node and edge is a fact with a file and
   a line" comes from the backlog's review of what NOT to take from Archify.
4. **Detectable staleness.** The file names the DB, the indexer fingerprint and the counts it came from.
5. **A typed IR.** `--json` prints the same model the page embeds, so a later `compare` (before/delta/after,
   the backlog's item 7) and other diagram types have a contract.

## 3. Options

| | option | verdict |
|---|---|---|
| A | Add `--format html` drawing to `graph` | No. `graph`'s edges are the name join; k4 already defined that format as the list page |
| B | HTML + Mermaid as the renderer | No for a file with no dependency: Mermaid is 2-3 MB of JS to inline or a CDN to fetch, its layout has no layers |
| C | HTML + `dot -Tsvg`, i.e. wrap `ask architecture` | No: keeps Graphviz, and the charts report shape is a bundle, not one file |
| D | **New verb, own small layered layout, SVG by string concatenation** | **Chosen.** The layer IS the rank, so layout is a row per layer and an order inside the row. That is the small end of the backlog's "Option C": no crossing-minimisation beyond barycentre, no edge routing |
| E | Archify itself as the renderer | No: Node at render time (recorded decision against it); licence unchecked |

Option D is also the reversible one: a new verb and a new unit, nothing else moves.

## 4. Phase 1 (this branch)

`drag-lint arch-diagram --db <db> [--output <file.html>] [--json]`, read-only.

**Model.** Zones are source folders below the common root, with the same helpers and the same edges as
`ask architecture` (`CommonRootLen`, `PathZone`, `unit_uses.target_file_id`), so the two can never
disagree about a zone or a count.

**Layers.**
1. Aggregate `uses` edges zone to zone; a zone's edge to itself is not drawn.
2. **Back-edge**: of a pair used in both directions, the smaller direction; on a tie the second zone
   in (units desc, name) order is the source. This is the rule of `ask architecture`, same words: never
   called a violation, because the index declares no order.
3. **Tangle**: the rest can still cycle (a to b to c to a). Strongly connected components of the forward
   edges share one layer; an edge inside one is kind `tangle`.
4. **Layer** = longest forward path down to a zone that uses nothing. Layer 0 is the foundation, drawn at
   the BOTTOM; arrows run downwards except back-edges.
5. **Order in a row**: two barycentre sweeps, ties by name. Deterministic.

**Output.** One HTML file: inline CSS, inline SVG, a few lines of inline JS for the click panel, the model
in `<script type="application/json" id="graph">`. No timestamp: the same DB gives the same bytes.

**What it reuses from k4.** Not k4's code: this branch is not based on it, lanes do not merge, and its SQL
is the name join. It reuses the CONTRACT: the same embedding (`id="graph"`, `<` written `<`), a
versioned `schema` key and `{"from","to","weight"}` on every edge, so a reader of `drag-lint.graph/1` edges
reads these (zone-level) edges with the same three keys. Once both land, a shared embed helper is one small
refactor; `graph --format html` could link here in its text.

## 5. Later phases (not built)

1. `--compare <old.sqlite>`: before/delta/after over two models, the case nothing else draws.
2. Click to open in the IDE, over the existing `drag-lint-open-source` pipe: a browser cannot write a pipe,
   so this goes through `drag-lint://`-style links or the viewer. Needs its own design.
3. Same IR, other diagrams: `callgraph` as sequence, `ask round-trip` as data flow, lifecycle from exception
   facts. Data flow stays capped by the property-refs gap named in the backlog.
4. IDE menu item: generate, then `ShellExecute` the file. Hours; waits for the owner's verdict on the picture.
5. `--seed-layers`: write the measured order as a `lint-project --layers` config.

## 6. Assumptions the owner can reverse

* **Verb, not a flag.** `arch-diagram` is a new verb. `graph --format arch` would be one line to alias.
* **Folder = zone**, as in `ask architecture`. Delphi namespaces (`DRagLint.Charts.*`) would be a `--by`
  switch later; folders were the row's wording.
* **`interface` and `implementation` uses both count.** An implementation use is a real dependency though
  it cannot make a compile cycle. The model keeps `interface` per edge so this can change without a re-index.
* **External units are left out** (`target_file_id IS NULL`): the third-party groups stay in `ask architecture`.
* **Entry `status: internal`**: not advertised until the owner says so.
