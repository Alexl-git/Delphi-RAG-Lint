<!-- dl:backlog status=open last-measured=2026-09-23 -->
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
* Engine by path: the SHARED deployed engine
  `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` (1.18.0-alpha /
  resolver 1.9.0-alpha since 2026-09-27), never this worktree's own build.
* Self-index only as
  `index --project src\cli\drag-lint.dproj --db src\cli\_D-RAG\drag-lint.sqlite`.
* Strict 7-bit ASCII, CRLF, no BOM in every `.pas` / `.ps1` / `.bat`.
* `scratch\` is throwaway; nothing there is ever committed.
* Commit by explicit pathspec. Never push.

## What is built

**25 of the 26 catalogue questions ship** (2026-09-23); only `compare` does
not, parked by the owner. The scoreboard is `STATUS-questions.md`, the question
set and each question's caveat is `question-catalogue.md`, the gate is
`src\Test-Emitters.ps1`, and `src\New-ExampleGallery.ps1` renders a worked
example of every shipped question into `docs\examples\index.html`.

### The last four (PLAN-last-four-verbs.md)

```
New-DiagramArtifact.ps1 -Question exception-paths -Target <Unit.Class.Method> -DbPath <clone> [-Depth 3] [-Cap 20]
New-DiagramArtifact.ps1 -Question consumers  -Target TABLE|TABLE.COLUMN -DbPath <Delphi clone> -SqlDbPath <SQL clone>
New-DiagramArtifact.ps1 -Question feeds-from -Target <Form>.<Control>    -DbPath <Delphi clone> -SqlDbPath <SQL clone>
New-DiagramArtifact.ps1 -Question lands-where -Target <Tmc/Imc property | field | Form.Control> `
                        -DbPath <CLIENT> -ServerDbPath <SERVER> -SqlDbPath <SQL>
```

* `exception-paths` -- raises, handlers and where each type is caught or
  escapes up the callers. There is no raise/handle fact: refs are CLASSIFIED by
  the source token before them, on sha256-fresh files only. A walk that ends
  says "no resolved caller", never "unhandled".
* `consumers` -- readers, writers, triggers, procedures and indexes of a table
  or column. Facts `[certain]`, SQL-verb literals `[inferred]` (`sql_reads`
  misses SQL passed through a variable, `SQL.Add(sTmp)`; engine D18, the
  multi-line `SQL.Add` gap, is fixed in extractor 1.19); the schema is the SQL
  SCRIPTS, not the live DB.
* `feeds-from` -- a control's value, hop by hop, to TABLE.COLUMN. It stops
  rather than guess, and prints its per-control coverage.
* `lands-where` -- an ORM property's server write/read path, TABLE.COLUMN and
  triggers. TABLE.COLUMN is a naming convention, `[inferred]`, with its
  measured coverage printed.

Column states they can show (one function, `Get-SqlColumnState`, decides for
`consumers`, `feeds-from` and `lands-where`): `column`, `quoted` (a quoted
identifier the SQL index does not extract -- none since extractor 1.19 fixed
engine D19; kept as a guard), `older-only`, `server-sql`, `[stale source]` (not
scanned -- not known, never an absence), `not-a-column`.

### Engine defects the charts disclose

Re-baselined 2026-09-24 against the extractor 1.19 / resolver 1.8 clones, which
FIXED D1, D12, D13, D18 and D19. A fixed limit is no longer claimed; each
detector stays as a guard and is exercised by the gate (synthetically where no
real row reaches it any more).

| | affects | handling |
|---|---|---|
| D1 parenless calls never bound -- FIXED (resolver 1.7/1.8; CLIENT call edges 20,409 -> 23,790) | every caller/callee walk | walks follow RESOLVED edges only, so a call the resolver cannot bind is still missing: a short list is a lower bound |
| D6 butterfly duplicate rows | butterfly | fixed in the emitter; gate `A-BF6-*` fails on a duplicate |
| D12 own-name result write scored global -- FIXED (0 witnesses on every clone) | effects | guard kept: a `g` whose witness names the routine moves to a dashed D12 disclosure (`A-FX12-DETECT`, synthetic) |
| D13 `write` refs unbound -- FIXED (21,916 of 32,909 CLIENT writes bound) | who-writes | since engine 1.18 (D31, 2026-09-27) `find-callers --resolved` reports a bare write BOUND to the member, so it is in the writers wing (FConnected 4, FNoRecursion 48); what is still unbound (a `with` body; bare in-class reads, FConnected 3) is listed by name in BOTH directions; a count is "N resolved write(s) reported by find-callers + ...", never a bare zero beside a population the index holds (ruling R26, also in the bundle header) |
| D18 `sql_reads` misses multi-line `SQL.Add` -- FIXED (SERVER read facts 19 -> 112) | consumers, touches-tables, lands-where | literals stay `[inferred]` beside the facts: 38 of 40 DataService loads still without a read fact pass their SQL through a variable |
| D19 quoted identifiers not extracted -- FIXED (`FOLDERCOUNT.TABLE`, `IPCHART.ACTION`) | consumers, feeds-from, lands-where | the `quoted` column state is kept as a guard (`A-COLSTATE-QUOTED`, synthetic) |

### dot.exe and MAX_PATH

`dot.exe` is not long-path aware: an output path of 260 characters or more
makes it write NO SVG (measured: 259 writes, 260 fails). `Invoke-DotRun` in
`src\Emit-Common.ps1` is the one place dot runs; it refuses an over-long path
BEFORE dot runs, naming the path, clears stale outputs first, and attaches
dot's own messages when no SVG appears. Keep `-OutDir` / `-OutRoot` short.

### The first two (2026-09-22)

Two questions ran end to end first. `New-DiagramArtifact.ps1 -Question <q> -Target <t>
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
## Fact POPULATION, measured 2026-09-23, re-measured 2026-09-24 (1.19 clones) -- check this before planning a question

A column EXISTING in schema 23 does not mean it holds rows. We made that mistake
twice (orm_links, then covered_by). Measured on ORM3:

| fact | CLIENT | SERVER | usable? |
|---|---|---|---|
| `call_edges` | 23,790 | 28,693 | yes |
| `effect_summary` | 7,234 | 5,264 | yes -- the richest fact available |
| `dfm_event` | 764 | 37 | yes, CLIENT-side (UI tier) |
| `ui_affinity` | 240 | 38 | partial |
| `sql_writes` / `sql_reads` | **0 / 0** | 148 / 112 | **SERVER ONLY** |
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
## `covered_by` is deliberately unwritten -- and `tested-by` is still SHIPPABLE

Engine session, 2026-09-23. I filed `symbol_facts.covered_by` being empty as a
gap in the same bucket as `orm_links`. **It is not, and the answer is better.**

`covered_by` is **RESERVED and never written, permanently, by design**
(`src\doc\DRagLint.Doc.SymbolFacts.pas`, the "TASK 5 OVERRIDE (CoveredBy)" block
at :57-71). Covered-by is a REVERSE edge -- a TEST calls the target -- so
index-time population would be ORDER-DEPENDENT: index `Foo.pas` before
`FooTests.pas` (the usual alphabetical order) and the test->code edge is not yet
in `call_edges` when Foo's row is written, so the fact comes out empty; index the
other order and it is populated. That breaks the "same DB -> same facts" mandate,
so the column is left unwritten ON PURPOSE.

Instead `ComputeCoveredBy` computes it **LAZILY AT RENDER TIME**, exactly as
`Called from:` already does. **No live test run is needed** -- it is a static
scan. So `tested-by` is answerable from the index alone, just not from that
column, and it is back on the SHIP list.

### THE TRAP: a resolved-only reverse walk is confidently almost-empty

This is the part that will silently ruin a naive implementation, and the engine
team proved it with a live RED/GREEN cycle:

> `TCallResolver.TypeReceiver` types every BARE (non-dotted) call site to the
> CALLING routine's own enclosing class/unit and never considers a target in a
> different unit.

A DUnitX `[Test]` method calling a free function, or another class's method under
test, is **exactly that shape** -- so it never earns a `call_edges` row and
surfaces only through the NAME-based bucket. A reverse walk built on
`FindResolvedCallers` alone therefore misses essentially every real test caller
and returns a confident, nearly-empty answer.

**`ComputeCoveredBy` hand-rolls a bounded BFS that UNIONS
`FindResolvedCallers` + `FindUnresolvedNameCallers` AT EVERY HOP** -- the same
two-bucket union `Called from:` uses. Copy that shape.

**UPDATE 2026-09-23: the verification was run and `reverse-calltree` PASSED -- see the WITHDRAWN section at the end of this file. The original text is kept below for the record.** Before shipping `who-calls`, VERIFY whether
`reverse-calltree` does the two-bucket union or resolved-only. If resolved-only,
`who-calls` has the same silent-undercount defect and must union too. Do not
assume; measure it against a known test caller.

**Cross-project caveat**, which bites in exactly the ORM3 shape: computed from a
project-only index, covered-by finds only callers INSIDE that index. A production
project DB cannot hold a test caller, because its closure is the compile closure.
Cross-project coverage needs the test project's own index and the same
absence-tolerant join GAP 1 needs.
## WITHDRAWN: `reverse-calltree` does NOT silently drop callers

Earlier on 2026-09-23 this README carried a "trap" saying a resolved-only
reverse walk returns an empty caller wing for unit-level routines. **That was
wrong and is withdrawn.** It is recorded rather than deleted because the way it
happened is the lesson.

What went wrong, in order:

1. `--format json` splices a human staleness note INTO the JSON document, so
   `ConvertFrom-Json` failed and my helper returned `-1`.
2. I reported those `-1`s as `0`.
3. I inspected the RAW output for ONE of three symbols, saw a genuinely empty
   `callers: []`, and generalised to all three without checking the other two.
4. For that one genuine zero I counted name matches instead of READING them.

Re-measured with the note stripped: `Pipes.Protocol.WriteString` = **13**,
`MStreams.ReverseBytes` = **9**. Both correct. And `BASICSF.ProcessMessages` =
**0, which is also correct** -- its 63 "callers" are every
`Application.ProcessMessages;` in the codebase, i.e.
`Vcl.Forms.TApplication.ProcessMessages`, a different symbol sharing a name.
Nobody calls `BASICSF.ProcessMessages`.

**COUNT, THEN READ.** A name-bucket count is a hypothesis, not evidence. My own
filing contained the caveat "some of those could be same-named symbols
elsewhere" and I did not act on it. Reading three source lines would have caught
it in under a minute.

**`refs.symbol_id IS NULL` mostly means OUT OF CLOSURE, not "missed".** A call
to `Application.ProcessMessages`, `Ini.WriteString`, `Sleep` or `Format` cannot
bind: the closure is the project's own units and there is no cross-store
binding. Do not read an unbound-ref ratio as a defect rate.

The bare-call concern itself is real and documented -- `TypeReceiver` types a
bare call to the calling routine's own enclosing class, which is why
`ComputeCoveredBy` unions both buckets. It is simply NOT demonstrated by any
measurement here. The fixture that would demonstrate it: a routine in unit A
called BARE from a method of a class in unit B, with a name UNIQUE in the index.