<!-- dl:backlog status=open last-measured=2026-09-22 -->
# charts\ -- staging area for the Archify-parity diagram work

Everything for the typed diagram IR, the emitters and the HTML/Graphviz
rendering loop is developed HERE first, and moves into the main tree
(`src\report\`, `src\cli\`, `tests\autotest\`) only when it earns its place.

Opened 2026-09-22 in worktree `C:\Projects\Delphi-RAG-lint-wt\archify-ir`
(branch `feat/archify-ir`, based on `main` at `4ccd1779`).

## Why a staging subfolder

The engine queue (bookmarks, shared-unit prefixes, project-facts, interface
dispatch, the exception fact) keeps moving on `main` in parallel. New files in
`charts\` can never conflict with it. The single real conflict point is
`src\cli\DRagLint.CLI.pas` -- so the CLI verb is added LAST, as one contiguous
block, when the rest is proven.

## Layout

```
charts\
  README.md            this file
  src\                 Delphi units under development (move to src\report\ later)
  shell\               the HTML/Mermaid shell and its assets
  fixtures\            small hand-written IR / dot samples for tests
  scratch\             throwaway output -- never committed
```

## Graphviz -- present and verified 2026-09-22

* `C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe` -- version 16.1.0
  (20260904.0139). Parent folder is **GraphWiz**, product folder **Graphviz**.
* Supported outputs include `json`, `json0`, `xdot_json`, `svg`, `plain`.
* **Use `-Tjson` for LAYOUT, not `-Tsvg`.** The viewer needs hit-testing;
  coordinates give it, an opaque SVG does not. This was already decided in
  `docs\BACKLOG-archify-parity.md` ("Interactivity forks the renderer").
* We never PARSE dot -- dot is Graphviz's INPUT. We emit it and read back JSON.
* Bundling it later is a dependency + EPL-1.0 review; for now it is a local tool
  invoked by path.

## The rendering loop being built

```
index  ->  typed diagram IR  ->  dot  ->  dot -Tjson  ->  coordinates
                             \->  mermaid  ->  HTML shell  ->  browser
```

The viewer half already exists and is NOT built here:
`C:\Projects\Delphi-RAG-Lint-Graph` (standalone Win32/Win64 exe, named-pipe
open-source contract to the IDE, `TPaintBox`/`TCanvas` today).

## Order (from docs\PLAN-archify-ir-workstream.md)

0. HTML shell around the EXISTING `graph --format mermaid` -- hours, ship first.
1. Typed diagram IR + validator -- 1-2 weeks, the keystone, deserves a spec.
2. Emitter: architecture -- 2-3 d.
3. Emitter: sequence (from `callgraph --direction callees`) -- 2-3 d.
4. Renderer: Mermaid in the HTML shell -- 2-3 d (borrow; do not hand-roll SVG).
5. `compare` (before/delta/after) -- 3-5 d.

Excluded on purpose: prose-to-diagram authoring and the `guide` verb. Every node
and edge must be a fact with a file and a line.

## House rules that apply here too

* PowerShell only, never Bash. Wait by BLOCKING, never polling.
* Engine by path: `..\third_party\dll-win64\drag-lint.exe` (1.16.0-alpha seeded
  2026-09-22 until the first local build).
* Self-index only as
  `index --project src\cli\drag-lint.dproj --db src\cli\_D-RAG\drag-lint.sqlite`.
* Strict 7-bit ASCII, CRLF, no BOM in every `.pas` / `.ps1` / `.bat`.
* `scratch\` is throwaway; nothing there is ever committed.
* Commit by explicit pathspec. Never push.

## What is built (2026-09-23)

Two questions run end to end. `New-DiagramArtifact.ps1 -Question <q> -Target <t>
-DbPath <db>` dispatches on the question exactly as `drag-lint ask --question`
will, and writes an 8-file bundle plus the xref to paste into the unit.

| question | select | rows are | clusters are | measured |
|---|---|---|---|---|
| `butterfly` | a method | methods | units | SendDeltaOperation 9+8+focus = 18 rows, 18 click targets |
| `deps` | a unit | units | directories | Blueprint4.ViewModel 3 used-by + 18 uses = 21 rows, 21 click targets |

Verified against Graphviz 16.1.0, not assumed:

* ONE `dot` run emits `-Tsvg`, `-Tplain`, `-Tpng` and `-Tpdf`, so the picture and
  the hit-test geometry come from the SAME layout and cannot drift.
* `HREF` on an HTML-like `TD` survives into the SVG as a real `<a xlink:href>`,
  one anchor per row -- so clickable text rows cost nothing.

`Test-FormA.ps1` is the executable verification walk for the Form A grammar:
99/99 lines classified, counts recomputed, verb set regenerated, and proven to
FAIL on five mutations of the golden.

### Two traps worth knowing

* **`unit_name_norm` is the LAST DOTTED SEGMENT, lowercased.**
  `Blueprint4.ViewModel` and `Blueprint4.CADImport.ViewModel` both normalise to
  `viewmodel`. Matching on it either misses everything or over-matches across
  namespaces. Join on the resolved `target_file_id` instead.
* **`butterfly/1` JSON nests the CALLEES tree under a field named `callers`.**
  Reading `callees.root.callees` returns nothing with no error.

`scratch\` and `artifacts\` are gitignored -- both are regenerable, and each
bundle's `meta.json` carries the command that regenerates it.
## Click-to-source WORKS (verified live 2026-09-23)

`docs\BACKLOG-archify-parity.md` calls the IDE plugin's pipe server "the one
piece genuinely missing". **That was true when written on 2026-09-16 and is not
true now.** Measured:

* `src\delphi-plugin\DragLint.Plugin.OpenSourceServer.pas` (dated 2026-09-11) is
  in the `.dpk`, started at `DragLint.Plugin.Wizard.pas:117`, torn down at `:75`.
* `\\.\pipe\drag-lint-open-source` was LISTENING in the running IDE:
  `PIPE_ACCESS_INBOUND`, byte mode, `PIPE_UNLIMITED_INSTANCES`, `SEP=#9`,
  `TERM=#10` -- exactly the contract in
  `docs\INBOX-graph-viewer-open-source-pipe-contract.md`.
* It implements `DoOpenInIDE(AFile, ALine, ACol)`, i.e. the v2 three-field form,
  which answers open question Q3 of that contract.
* A live write of `<file><TAB><line><LF>` navigated the IDE.

So the viewer -> IDE path has been ready since 2026-09-11. What was missing is
only the BROWSER hop, because a browser cannot write to a named pipe:

* `src\Open-DragLintUri.ps1` -- parses `draglint://open?file=..&line=..[&col=..]`
  and writes the contract payload. Degrades a garbled line number to 1 rather
  than rejecting (as the contract asks), and falls back to ShellExecute when no
  server answers, mirroring the standalone viewer.
* `src\Register-DragLintProtocol.ps1` -- one HKCU key, no elevation,
  `-Unregister` to undo. Nothing else on the machine is touched.
## Fact POPULATION, measured 2026-09-23 -- check this before planning a question

A column EXISTING in schema 23 does not mean it holds rows. We made that mistake
twice (orm_links, then covered_by). Measured on ORM3:

| fact | CLIENT | SERVER | usable? |
|---|---|---|---|
| `call_edges` | 20,409 | - | yes |
| `effect_summary` | 7,254 | 5,284 | yes -- the richest fact available |
| `dfm_event` | 762 | 37 | yes, CLIENT-side (UI tier) |
| `ui_affinity` | 230 | 37 | partial |
| `sql_writes` / `sql_reads` | **0 / 0** | 148 / 19 | **SERVER ONLY** |
| `covered_by` | **0** | **0** | **no -- never populated** |
| `orm_links`, `fb_*` | **0** | **0** | **no -- needs a live Firebird** |

`sql_reads`/`sql_writes` being 0 on the CLIENT is CORRECT, not a gap: the client
owns TFDMemTables only and has no FireDAC connection at all. A `touches-tables`
question must SAY that when asked on a client index rather than draw an empty
chart.

### `effect_summary` token legend

Documented on the declaration in `src\analysis\DRagLint.Analysis.Purity.pas`
(`TEffectSummary.Encode` / `.Decode`, tokens at :252-255):

| token | flag | meaning |
|---|---|---|
| `g` | `efGlobal` | writes global state |
| `h` | `efHeap` | heap allocation / free |
| `s` | `efSelfFields` | writes its own fields |
| `p<k>` | | writes through parameter k, 0-based, ascending |
| `?` | `efUnknown` | a blocker this build could not analyse |
| *(empty)* | | effect-free |

Stored values are comma-joined in that order, e.g. `g,p0,p3,?`. Most common on
ORM3 CLIENT: `?` (3,128), `s` (2,500), `s,?` (871), `g,?` (238).