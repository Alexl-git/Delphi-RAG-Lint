<!-- dl:backlog status=open last-measured=2026-09-23 -->
# dl-Charts

## Summary
Create the staged charting and diagram pipeline for the Archify-parity work, keeping the code isolated under `charts\` until it is proven and ready to move into the main `src\report\` and CLI flow.

## Goal
Deliver a typed diagram IR, deterministic emitters, and a browser-renderable Mermaid/Graphviz pipeline that can show architecture and call-flow diagrams with file/line provenance for every node and edge.

## Scope
- Typed diagram IR with validation
- Architecture emitter
- Sequence emitter driven from callgraph data
- Dot emission for Graphviz and JSON backfeed
- Mermaid rendering inside the HTML shell
- Compare / before-delta-after flow

## Non-goals
- Prose-to-diagram authoring
- A `guide` verb
- Unverifiable nodes or edges without file/line fact data

## Definition of done
- The typed IR accepts valid architecture and sequence facts only.
- Every emitted node/edge includes file and line provenance.
- The diagram pipeline can emit Dot and read back Graphviz JSON layout.
- The HTML/Mermaid shell displays the diagram in a browser.
- The compare workflow can show delta output in a reproducible way.

## Notes
This work lives in the staging tree described in `charts\README.md` and follows the order already recorded in `docs\PLAN-archify-ir-workstream.md`.

The current tracked sequence is:
1. HTML shell around the existing `graph --format mermaid`
2. Typed diagram IR + validator
3. Architecture emitter
4. Sequence emitter from `callgraph --direction callees`
5. Renderer: Mermaid in the HTML shell
6. Compare (before / delta / after)

## Status
Open. **26 of 27 catalogue questions ship** (2026-09-23; `round-trip` 2026-09-28), as PowerShell
emitters under `charts\src\` over the frozen index clones; only `compare` is
not built (parked by the owner, and it is the one that needs the typed IR).
Scoreboard: `charts\STATUS-questions.md`. Syntax, answers and caveats:
`charts\question-catalogue.md`.

The last four shipped DERIVED rather than from the facts first planned for
them, and each carries its caveat on the chart:

* `exception-paths` (`-Target <Unit.Class.Method> -DbPath <clone> [-Depth 3]`)
  -- exception refs classified by source token; no raise/handle fact exists.
* `consumers` (`-Target TABLE|TABLE.COLUMN -DbPath <Delphi clone> -SqlDbPath <SQL clone>`)
  -- facts `[certain]`, SQL-verb literals `[inferred]`; schema = the SQL scripts.
* `feeds-from` (`-Target <Form>.<Control> -DbPath <Delphi clone> -SqlDbPath <SQL clone>`)
  -- stops rather than guess; per-control coverage printed.
* `lands-where` (`-Target <Tmc/Imc property | field | Form.Control> -DbPath <CLIENT> -ServerDbPath <SERVER> -SqlDbPath <SQL>`)
  -- TABLE.COLUMN by naming convention, `[inferred]`, coverage printed.

The twenty-sixth is a TEXT question (a `trace.dlgraph` bundle, no picture yet):

* `round-trip` (`-Target <control | field | TABLE.COLUMN> -DbPath <CLIENT> -ServerDbPath <SERVER> -SqlDbPath <SQL>`)
  -- the Interface report's trace core: Form A text, conditions from fresh source (an `if` verbatim; the `try` / `except` and `case` forms marked), STOPS where the index ends.
  The page is a document: each `@File.pas:line` anchor is a `draglint://` link that opens the line in the IDE (DOC-R1).
  A direction that stops after the anchor notes each tier it did not reach as `not walked`, and the title claims only the walked direction.
  ALSO is owner-accepted (2026-09-28): all callers count; the anchor dataset's scope; anchors only.

Engine defects the charts disclosed -- D1 (parenless calls), D12 (effects), D13
(who-writes), D18 (multi-line SQL.Add reads), D19 (quoted identifiers) -- are FIXED
in extractor 1.19 / resolver 1.8 (re-baselined 2026-09-24); the detectors stay as
guards. who-writes still lists writes BOUND to the member that find-callers does
not report (the D13 fix gave them no member-access row). D6 (butterfly duplicate
rows) is fixed in the emitter.
