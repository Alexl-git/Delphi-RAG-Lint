# Features

Everything drag-lint does, grouped. Counts on this page were taken from the
running build (`drag-lint rules --json`), not written by hand.

Three surfaces expose these: the **CLI** (`drag-lint <verb>`), the **RAD Studio
plugin** (see [IDE Menu Reference](IDE-Menu-Reference)), and the **language
server** (`drag-lint lsp`).

Inside the plugin, not everything lives on the main menu. **Auto-fix and
"allow this finding" are reachable only by right-clicking a node in the
Structure form** -- see [Fix it](Fix-it), [Fix all in unit](Fix-all-in-unit),
[Fix all in project](Fix-all-in-project) and
[Allow this message](Allow-this-message). There is also a Project Manager
right-click item, [drag-lint: Project Rules...](drag-lint-Project-Rules).

## Notes carried over from the hand-written page

These were prose on the hand-written Features page and have no registry field. Each belongs on the page that owns its topic; move it there and delete it here.

### Linting

**Newest -- the coupling rules.** `global-only-uses-edge` (a global variable is
the only reason unit A depends on unit B, so relocating it deletes the `uses`
edge), `uses-global-census` (how heavy that edge is), `duplicate-global-decl`
(the same interface-level name in two units, so `uses` order decides which one
compiles), `with-hides-outer-symbol` and `stat-gated-destructive`. The first
three are `project-wide` and therefore only reachable through `lint-all` --
`lint <path>` is a genuine subset and never runs them.

Formatting: drag-lint drives **YADF** (the Delphi formatter) for the current
unit or the whole active project, straight from the IDE menu -- see
[Format with YADF](Format-with-YADF) and
[Format Whole Project with YADF](Format-Whole-Project-with-YADF).
**Formatting does not invalidate suppressions.** A `dl:ok` hash is computed over
a normalised line -- whitespace stripped, identifiers lowercased -- so
reindenting and re-spacing cannot change it. Verified on a real file: 10 markers
in, 10 markers out, whitespace the only difference.

Suppression:

* `// drag-lint:ignore [rule-id ...]` -- silence a line.
* `// dl:ok <rule-id>@<hash> -- reason` -- a **reviewed marker**: it carries a
  hash of the line's code tokens and **re-reports itself if the code changes**,
  so a review cannot outlive the code it reviewed. Reindentation and case
  changes do not invalidate it.
* `REVIEWED <yyyy-mm-dd>` anywhere in a marker's reason records when a human last
  re-read it (`-- REVIEWED 2026-09-23 the loop is bounded`). It is a comment, so it
  never changes the hash. `review-marker-reason-unreviewed` (OFF by default)
  reports a missing, invalid, future or too-old stamp (`max_age_days`, default 180).
* `review-marker-placeholder-hash` (ON) reports a marker whose `@hash` was never
  computed (`@0000`, `@xxxx`), including an `@0000` one written in a block
  comment, where no marker is read -- it suppresses nothing.

### Diagrams and charts

Ask a formal question about one symbol and get a clickable chart back. In RAD
Studio, put the caret on the symbol and pick the question from **drag-lint >
Reports**; the chart opens in the browser and the text answer is copied as a
DocInsight `/// <remarks>` block that Auto Document leaves alone. Outside the IDE,
`charts\src\Ask-Report.ps1` asks the same questions. Twenty-five questions: `round-trip`, `butterfly`,
`who-calls`, `what-it-calls`, `who-writes`, `who-reads`, `change-impact`,
`tested-by`, `effects`, `touches-tables`, `class-surface`, `hierarchy`, `deps`,
`cycles`, `wiring`, `lifecycle`, `event-wiring`, `architecture`,
`protocol-trace`, `crosses-boundary`, `shown-where`, `exception-paths`,
`consumers`, `feeds-from` and `lands-where`. Every row in a chart is a fact with a file and a line, and links
back to it.
