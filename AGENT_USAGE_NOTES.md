# drag-lint — Agent Usage Log & Feature Gaps

Running log of how the coding agent uses drag-lint, plus notes on anything it
needed but the tool could not provide. Append-only; newest session on top.

## Tally (running)
- Commands run: 7  (query x4, hover x2, surface x1)
- Useful (gave what I needed): 6
- Gaps hit: 2 minor (see below; `surface` mostly closes them)

## Feature gaps / wishes (updated after testing hover + surface)
1. **No per-symbol signature lookup.** `query --name X` => kind|name|qname only.
   `hover --qname X` => only the **doc comment** ("found but has no doc comment"
   when none). Neither gives the parameter list / return type for a single method.
   **Workaround that works great:** `surface --qname <ContainingType>` prints the
   full class with every member's real signature AND distinguishes overloads.
   Wish: let `hover --qname <Method>` (or `query --sig`) fall back to printing the
   AST declaration signature when there is no doc comment — so I don't have to
   surface the whole type just to see one method's params.
2. **Overload disambiguation in `query`** — `query --name` shows N identical rows
   for overloads. Minor now that `surface` shows them with params; could fold the
   signature into `query` output too.

Both gaps are low-severity: `surface --qname <Type>` is the reliable
agent-friendly path to signatures+overloads. Consider documenting that in
`--help` ("to see a method's signature, surface its type").

3. **No interface-vs-implementation (usability) flag.** HIGH VALUE. drag-lint
   indexes implementation-section symbols the same as interface ones. Example:
   `TdxPDFDocumentExport` (dxPDFDocument, start_line 613) is declared in the
   *implementation* section (unit `implementation` keyword at line 587), so it is
   NOT usable from another unit -- but `query`/`surface` happily returned it and I
   wrote code against it that failed to compile (E2003 Undeclared identifier).
   The real public API was the global wrappers `dxPDFDocumentExportToBitmap` /
   `dxPDFDocumentExportToImageEx` declared in the interface (lines 566-578).
   **Wish:** add a `section: interface|implementation` (and ideally `usable_from_other_units: bool`)
   field to symbol records + show it in `query`/`surface`/`--json`. This is the
   single most useful thing for an agent deciding "can I call this?".

## Session log

### 2026-06-02 — PDF fragment experiment (TEST_PDFFragments)
DB used: `tests/devexpress.sqlite` (DevExpress symbols), CLI v0.30.0-alpha.
- `query --name ExportToBitmapByZoomFactor --db devexpress.sqlite` -> OK,
  `dxPDFDocument.TdxPDFDocumentExport.ExportToBitmapByZoomFactor` (2 overloads).
  Gap #2 (couldn't tell overloads apart) + Gap #1 (no signature).
- `query --name TcxRotationAngle` -> OK, enum `cxCustomCanvas.TcxRotationAngle`.
- `query --name ra0` -> OK, `cxCustomCanvas.TcxRotationAngle.ra0`. (This is the
  win that grep would have made painful - pinned the exact unit instantly.)

TODO next time: try `hover --qname` and `surface --qname` for signatures/members
before falling back to source reading; record whether they close Gap #1.

## Resolutions (2026-06-03)
- **Gap #1 (signature) FIXED.** `query --name` now prints `... : <signature>` in
  text output and emits `"signature"` in `--json`. So a method's params/return
  show without needing `surface`. (Parser captures field/property/method-return
  types into symbols.signature.)
- **Gap #2 (overload disambiguation) FIXED.** With signatures shown inline,
  overloaded rows are now distinguishable in plain `query` output.
- **Gap #3 (interface vs implementation) FIXED -- HIGH VALUE.** Symbols now carry
  a `section` ('interface' | 'implementation'). `query` text shows `[impl-only]`
  for implementation-section symbols; `--json` adds `"section"` and
  `"usable_from_other_units": bool`. So an agent can tell "can I call this from
  another unit?" before writing code. (schema v7; reindex required.)
