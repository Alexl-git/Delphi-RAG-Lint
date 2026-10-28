---
id: charts-and-the-ide
title: Charts and the IDE
summary: Ask a chart question, open the answer, read a round-trip trace, jump to RAD Studio
product: DL
group: diagrams-charts
order: 80004
since: 1.20.1-alpha
status: shipped
updated: 1.36.0-alpha
---

# Charts and the IDE

Ask a chart question, open the answer, read a round-trip trace, jump to RAD Studio.

Read this when you first ask a chart question: how to ask one from drag-lint > Reports or with drag-lint ask, where the answer lands, how to read a round-trip trace, and the one-time draglint:// registration that makes a chart row open its line in RAD Studio. Needs a fresh project index, and Graphviz for the pictures (the installer brings it). No PowerShell is needed.

## Where to click

* RAD Studio main menu: **drag-lint > Reports**
   1. Put the caret on a routine, field, type or unit
   2. drag-lint > Reports, then pick a question
   3. Click a chart row to jump to its line (needs drag-lint protocol register once)

**Needs:** index, graphviz

## Details

**How to ask a chart question, where the answer lands, how to read it, and how
to jump from it into RAD Studio.** Companion to
[Diagrams and Charts](chart-questions.md), which lists the questions. For a step-by-step
recipe on one field (the Blueprint Operation Name benchmark) from the drag-lint >
Reports menu, see Field Round-Trip Report.

Status, 6 October 2026: **27 of the 28 catalogue questions ship**; only
`compare` does not (parked by the owner). The newest is `path` (every shortest
call path from one routine to another; on the Reports menu with the plugin's next
question-list update, from the scripts today). The chart
tool-set lives in the `charts\` folder of the repository. **In RAD Studio every
question is on the drag-lint > Reports menu** (below). Every question is answered in-process by the engine's `ask`
verb (`drag-lint ask`), so no PowerShell is needed.

### From RAD Studio: drag-lint > Reports

1. Put the caret on the symbol -- a routine, a field, a grid column, a type.
   Save first; the menu offers to save all when the unit has unsaved changes,
   because the caret line must match the index.
2. Pick the question from **drag-lint > Reports**. Questions are grouped by
   what you select: *Routine at the cursor*, *Field, property or grid column*,
   *Type at the cursor*, *This unit*, *This project*, *Table or column*.
3. A prompt shows the full name the caret resolved to (via `typeat`); press
   Enter, or edit it. Table questions ask for the table name; project
   questions ask nothing.
4. The report runs in the background -- the IDE stays usable.
5. The chart opens in your browser. The text answer is put on the clipboard and
   shown in a small window, formatted as a DocInsight block:

   ```text
   /// <remarks>
   /// Who writes Blueprint4.ViewModel.TBlueprint_ViewModel.FName (drag-lint report, 2026-10-05):
   /// ...
   /// </remarks>
   ```

   Paste it above the declaration. It carries no `drag-lint:auto` marker, so
   Auto Document preserves it byte for byte.

When the index is stale the menu says so and offers the incremental reindex
command; when a question is refused (an ambiguous target, a missing index
pair) the reason is shown. The menu runs `drag-lint ask` (described
below); no PowerShell is needed, and for pictures it needs
Graphviz. **Forms for testers (CSV)...** sits on the same submenu.

### What a chart is

One formal question about one selection -- a method, a field, a unit, a form
control, a table column -- answered from the drag-lint index and nothing else.
Every box, row and arrow is a fact with a file and a line behind it. A hop the
index cannot make is shown as a stop, never guessed. `round-trip` answers with
a text trace; every other question answers with a picture (Graphviz).

### What you need

* The engine (`drag-lint.exe`) and Graphviz (`dot.exe`, 16.1). The engine and
  the repository's chart scripts find them by the first of: `-Engine` / `-Dot`; `DRAGLINT_ENGINE` /
  `DRAGLINT_DOT`; the `engine` / `dot` key of `%APPDATA%\drag-lint\settings.json`;
  the installed layout beside the scripts; then the shared defaults
  (`C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`, `dot.exe` on
  PATH, `C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe`). A path you SET that
  does not exist is an error naming where it was set -- a typo never silently picks
  another file. The full order is in `charts\README.md` ("Where the engine and
  Graphviz are found").
* `drag-lint ask` reads the live indexes (`--project <P.dproj>`, `--in <U.pas>`
  or `--db <index>`) and refuses a stale one (exit 3; stderr names the reindex
  command) unless you pass `--allow-stale`. No PowerShell is needed.
* Keep the output folder short: `dot.exe` cannot write a path of 260 characters
  or more, and the script refuses one before it runs.

### Asking a question

Run `drag-lint ask` with a question, a target and the project (or index).
`--open` opens the result in your browser.

**A chart question** -- callers and callees of one method:

```text
drag-lint ask butterfly --target Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation ^
    --project CLIENT\Micronite2027.dproj --open
```

**`round-trip`** -- one edited grid field, both ways through the pipe. It reads
three indexes: the client project, the server project and the SQL-script index.

```text
drag-lint ask round-trip --target frmBlueprint4.dxDBGrid1OperationVName ^
    --project CLIENT\Micronite2027.dproj ^
    --server-db SERVER\_D-RAG\MicroniteMW1Service.sqlite ^
    --sql-db SQL\_D-RAG\drag-lint-sql.sqlite --open
```

A `round-trip` target can be a control (`<Form>.<Control>` or
`<Unit>.<TForm>.<Control>`), a TField variable (`<Unit>.<TClass>.<FieldVar>`)
or `TABLE.COLUMN`. The default depth is 4 call levels (`-Depth`). A
`TABLE.COLUMN` loaded by more than one dataset stops and lists the datasets --
pass the control or the dataset field instead.

The target form differs per question (a unit name for `deps`, a form class for
`event-wiring`, `TABLE` or `TABLE.COLUMN` for `consumers`); the question pages
linked from [Diagrams and Charts](chart-questions.md) give each one.

### One command, for AI agents and scripts

`drag-lint ask` asks any question with no setup and prints the
answer as text; the engine answers it itself and starts no PowerShell:

```text
drag-lint ask round-trip --target frmBlueprint4.dxDBGrid1FtrsVNum `
    --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj
```

* It finds the project's index with the engine's `resolve-dbs` (`--project`, or
  `--in` with any `.pas` / `.dfm` of the project) and takes the server and SQL
  indexes that belong with it from `charts\report-pairs.json`.
* It checks every index it will read for freshness first. A stale one stops the
  run (exit 3) with the incremental `index` command on stderr; it never indexes.
* The bundle goes under `%TEMP%\drag-lint-reports`. By default stdout is a
  DocInsight `/// <remarks>` block, byte for byte what the IDE's drag-lint >
  Reports menu puts on the clipboard, ready to paste above a declaration; it
  carries no `BUNDLE` / `INDEX` lines. With `--plain` stdout is
  `BUNDLE <folder>`, one `INDEX <db>` line per index read, then the answer:
  the whole trace for `round-trip`, otherwise a `CHART` header with the
  counts and one `<name> @File.pas:line` line per row, ending with a
  `... not shown (-Cap N; raise -Cap to see them)` line when the chart drew
  fewer rows than it counted.
* Exit codes: 0 answered, 1 the question refused (reason on stderr), 2 setup
  (what to pass or edit), 3 stale.

Use it when the answer is a path or a set that crosses units, forms or
processes; for one member in one file, `drag-lint query` / `find-callers` or a
text search is enough. `charts\README.md` ("For AI agents") has the details.

### Where the answer goes

One folder per answer under `%TEMP%\drag-lint-reports` (change the root with
`--out-root <dir>`). Asking again overwrites it.

| File | Chart questions | `round-trip` |
|---|---|---|
| `index.html` | the page to open: chart, counts, notes | the page to open: the trace as text, each `@File.pas:line` a link |
| `graph.svg`, `.png`, `.pdf` | the picture; SVG rows are links | -- |
| `graph.dot`, `graph.plain` | Graphviz input and layout geometry | -- |
| `trace.dlgraph` | -- | the trace itself (Form A text) |
| `meta.json` | index fingerprint, every count, and the command that regenerates the folder | same |
| `xref.txt` | a DocInsight `<remarks>` block that points a unit at this folder | same |

### Viewing it

Open `index.html` in any browser (or pass `-Open`). There is **no chart viewer
inside RAD Studio**. The IDE's docked graph window
(drag-lint > drag-lint Graph (dockable)) hosts the separate call-graph viewer,
`drag_lint_graph.exe`; it does not open chart folders.

### Jumping from a chart into RAD Studio

Every row of a chart, and every `@File.pas:line` anchor of a `round-trip` page,
is a link of the form

```text
draglint://open?file=<url-encoded absolute path>&line=<n>
```

A browser cannot talk to the IDE directly, so a small protocol handler carries
the link across. A `round-trip` anchor stays plain text when the three indexes
hold its file name at no path or at several (126 of 126 anchors are links on
the `OPERAT.NAME` trace).

#### One-time registration

Per Windows user, no administrator rights. Run it from the install (or the main
checkout):

```text
drag-lint protocol register --dry-run   # show, write nothing
drag-lint protocol register             # register
drag-lint protocol unregister           # undo
drag-lint protocol status               # ours | legacy-powershell | foreign | none
```

What it writes: one registry key, `HKCU\Software\Classes\draglint`, whose command
runs `drag-lint-open.exe` (a GUI helper, no PowerShell) from where it sits beside
`drag-lint.exe`. A handler inside a `*-wt\` worktree, or a key that belongs to
another program, is refused unless you pass `--force`. `--dry-run` prints what
would be written and touches nothing; `unregister --dry-run` lists what it would
remove. **Re-register after the merge:** a registration made with the old
PowerShell script reads `legacy-powershell` in `status`, and `register` replaces
it. Full details: [the draglint:// handler](protocol-handler.md).

#### What a click does

1. The browser hands the link to the handler (it may ask first). The page shows
   a note naming the file and line it asked for, and the command to run once
   if nothing opens.
2. The handler checks the link, then writes `<file><TAB><line><LF>` to the
   named pipe `\\.\pipe\drag-lint-open-source`. The drag-lint IDE plugin
   listens there while it is loaded and opens the file at that line.
3. If no IDE answers within one second, the handler opens the file in
   **Notepad** (the line is not positioned there) -- never with the file's
   default program, which for a source file may load a project or connect to a
   database.

#### What the handler will and will not open

It opens only a file on a **local drive path** (`X:\...`) with a source
extension: `.pas .dfm .dpr .inc .sql .fmx`. It refuses, before it touches the
file or the pipe:

* network and device paths (`\\server\...`, `\\?\`, `\\.\`), relative paths,
  NTFS streams (`a.exe:b.pas`), wildcards, a path segment ending in a dot or a
  space, and reserved device names (`CON`, `NUL`, `COM1`, ...);
* project and package files (`.dproj`, `.groupproj`, `.dpk`) and every other
  extension;
* a line or column that is not ASCII digits (a missing line, or line 0 -- a
  chart's focus row -- opens at line 1), a key given twice, a control
  character, and anything but exactly one argument.

A refusal exits 2 and writes one line to
`%LOCALAPPDATA%\drag-lint\logs\uri-handler.log`; the handler logs every link it
handles there too, each logged message capped at 512 characters. A drive
letter does not prove a file is local: a mapped drive can be a network share,
so the handler reaches only servers you have already mapped, never one a link
names.

**Requirements for the jump:** the drag-lint IDE plugin installed, RAD Studio
running with the plugin loaded, and the handler registered. The pipe and the
plugin were checked against a running IDE on 23 September; that the page now
passes the click to the browser was checked in a headless browser on 28
September. A live click from a browser into RAD Studio is still to be checked
on the owner's machine.

### Reading a round-trip trace

A trace is a header, then sections in a fixed order: `ANCHOR`, `DERIVED` (only
for a calculated field), `WRITE`, `SERVER`, `DATABASE`, `RESPONSE`, `READ`,
`ALSO`, and a closing count line. A real excerpt:

```text
[06] CALLS TBlueprint_ViewModel.DoAfterPostFtrs @Blueprint4.ViewModel.pas:3553 -- on FMTFtrs.AfterPost, wired at :636 in Create
       UNLESS "FSuppressEvents" @Blueprint4.ViewModel.pas:3555 -- ask E1
[07] CALLS TBlueprint_ViewModel.SendDeltaFtrs 'AfterPost' @Blueprint4.ViewModel.pas:3565 -- in TBlueprint_ViewModel.DoAfterPostFtrs; from :3556
       UNLESS "FMTFtrs.ChangeCount = 0" @Blueprint4.ViewModel.pas:3582 -- else Exit(True); ask E1
[09] CROSSES process boundary @Blueprint4.ViewModel.pas:3594 -- in TBlueprint_ViewModel.SendDeltaFtrs; cmdDelta via ExecuteCommand
```

| You see | It means |
|---|---|
| `[NN] VERB subject @File.pas:line -- note` | one numbered step: what happens (`CALLS`, `SETS`, `SENDS`, `ROUTES`, `APPLIES`...), where it is, then context |
| `WHEN "cond"` | the path continues when this condition is TRUE |
| `UNLESS "cond"` | the path continues when this condition is FALSE; the note says what happens otherwise (`-- else Exit`) |
| the text inside the quotes | an `if` condition copied **verbatim** from the source; `... raises` marks a `try`/`except` guard and `case X of` a case, both with generated words |
| `[by name]` | the link is a name match, not a resolved reference |
| `[inferred]` | the link is deduced (a naming convention, a literal), not a stored fact |
| `CROSSES process boundary` | the value leaves the process; indented lines name the transport and the command |
| `STOPS reason @anchor` | the index cannot make the next hop; the step is counted as unresolved and says why |
| `OMITS n step(s) ...` | branches for other tables that were not walked, with their conditions |
| `-- not walked: ...` | a section the trace never reached because an earlier step stopped |
| `ask E1` ... `E4` | the engine fact that would remove this limit |
| `END TRACE 76 steps, 31 conditions, ...` | the totals, recomputed from the trace |

The trace reads conditions from the source files, so a file that changed since
it was indexed makes the question refuse by name rather than quote stale code.

### A calculated field offers its sources

A grid column bound to a **calculated field** (one its dataset's
`OnCalcFields` handler writes) has no table column to reach. The trace stops
at its anchor, says why, and offers the fields it is computed from:

```text
TITLE "Why frmBlueprint4.dxDBGrid1FtrsVFtrName cannot be traced -- it is calculated"
...
DERIVED
  -- FtrName is calculated from 18 fields -- trace one of them instead ...:
[10] FROM MSCLIST.NOTATION VIA FfFtrs_Notation [inferred] @Blueprint4.ViewModel.pas:987 -- in FtrsOnCalcFields; ...
       REGENERATE drag-lint ask round-trip --target "Blueprint4.ViewModel.TBlueprint_ViewModel.FfFtrs_Notation" ...
```

* The `STOPS` step names where the field is created and computed, with the
  handler's own guards as its conditions; the call that computes it is named,
  its body not walked.
* `DERIVED` lists one numbered row per source field. A field the value is
  chosen by -- read in a `case` selector or in the condition of an `if` around
  a write -- is a row too, marked `chooses the value (case at :N)` or
  `(if at :N)`. A field whose every write is a constant can therefore still
  offer rows (`calculated from no field, but its value is chosen by 2 ...`).
* A local variable set once from one field is followed one hop; a local set in
  several places, or any other value the walk cannot map, is a named row
  (`not mapped: ...`) with no command. A row marked `(calculated)` is itself a
  calculated field.
* Each `REGENERATE` line is a complete `drag-lint ask round-trip` command: run
  it in any shell to trace that field instead.

A field set in another event handler, or a lookup field, stops with a named
reason and offers nothing.

### Worked examples

`charts\src\New-ExampleGallery.ps1` renders three or four real examples per
shipped question to `charts\docs\examples\index.html`, including three
`round-trip` traces. The folder is generated, not committed: run the script to
build it. It reads the same clones under `charts\scratch\db\`. It is dev-only and not shipped (the installer excludes it); since 2026-10-14 every example is rendered by `drag-lint ask`. A gallery built
before 28 September has `round-trip` pages without links; rebuild it to get
them.

### Not yet

* **No chart viewer inside RAD Studio.** Charts open in a browser.
* **`round-trip` as a chart.** It answers in text today; a picture drawn from
  that text is the next step.
* **One engine verb, `ask`.** Shipped: `drag-lint ask` runs in-process, and the
  IDE menu and the terminal both call it (the PowerShell scripts under
  `charts\src` remain only as dev tooling).
* `compare` (before / delta / after) is parked.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
