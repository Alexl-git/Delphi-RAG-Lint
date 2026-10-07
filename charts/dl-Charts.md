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

The twenty-sixth answers in TEXT (a `trace.dlgraph` bundle) and, since R5, with a chart drawn from that text:

* `round-trip` (`-Target <control | field | TABLE.COLUMN> -DbPath <CLIENT> -ServerDbPath <SERVER> -SqlDbPath <SQL>`)
  -- the Interface report's trace core: Form A text, conditions from fresh source (an `if` verbatim; the `try` / `except` and `case` forms marked), STOPS where the index ends.
  The page is a document: each `@File.pas:line` anchor is a `draglint://` link that opens the line in the IDE (DOC-R1).
  A direction that stops after the anchor notes each tier it did not reach as `not walked`, and the title claims only the walked direction.
  ALSO is owner-accepted (2026-09-28): all callers count; the anchor dataset's scope; anchors only.
  A selection bound to a CALCULATED field stops at its anchor and offers, in a `DERIVED` section, the fields it is computed from and the fields that choose its value (a `case` selector, an `if` around a write), each with a ready command to trace it instead (gate `RT-CALC`: FtrName 18 fields).

Two helpers since 2026-09-28: `src\Ask-Report.ps1` asks any question in one command on the live indexes (README "For AI agents"), and a click on a chart row or a trace anchor reaches RAD Studio through `src\Register-DragLintProtocol.ps1` / `src\Open-DragLintUri.ps1`, a handler that opens only a local Delphi source file and falls back to Notepad (README "Click-to-source").

Engine defects the charts disclosed -- D1 (parenless calls), D12 (effects), D13
(who-writes), D18 (multi-line SQL.Add reads), D19 (quoted identifiers) -- are FIXED
in extractor 1.19 / resolver 1.8 (re-baselined 2026-09-24); the detectors stay as
guards. The who-writes "bound, not reported" disclosure the D13 fix needed is
RETIRED (2026-09-27): engine 1.18 (D31) makes `find-callers --resolved` report those
writes, so they are the writers wing; what stays unbound (a write in a `with` body,
bare in-class reads) is listed by name. D6 (butterfly duplicate rows) is fixed in
the emitter.
