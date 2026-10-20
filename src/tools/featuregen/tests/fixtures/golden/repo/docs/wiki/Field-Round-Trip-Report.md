# Field Round-Trip Report (the Blueprint "Operation Name" benchmark)

**How to produce the text trace and the pictures for one edited grid field --
the report we have used as a benchmark on the Blueprint4 form's Operation Name
column (`OPERAT.NAME`) -- from RAD Studio, and from a terminal.**

Checked on 5 October 2026 against engine 1.20.6-alpha and the live ORM3
indexes. Companion to [Charts and the IDE](Charts-and-the-IDE), which explains
every output file and how to read a trace.

## What you get

| Part | Question | Output | Time (measured) |
|---|---|---|---|
| **Text**: how `OPERAT.NAME` reaches the grid column and how an edit goes back (client -> pipe -> server -> SQL and back) | `round-trip` | `index.html` (the trace, every `@File.pas:line` a link) + `trace.dlgraph` | ~55 s; 76 steps, 31 conditions, 4 process crossings, 2 unresolved |
| **Pictures**: who calls the save routine and what it calls | `butterfly` (and any other chart question) | `graph.svg`, `graph.png`, `graph.pdf` + `index.html` | ~5 s; 9 callers / 9 callees |

The names to use:

* the grid column: `frmBlueprint4.dxDBGrid1OperationVName`
  (`Blueprint4.TfrmBlueprint4.dxDBGrid1OperationVName : TcxGridDBColumn`);
* the routine that sends the edit to the server:
  `Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation`.

`OPERAT.NAME` itself is not a usable target: five datasets load table `OPERAT`,
so the trace stops and lists them. Pass the grid column (above) instead.

## Inside RAD Studio -- what exists today

**The drag-lint menu runs every chart question: *drag-lint > Reports*** (see
[IDE Menu Reference](IDE-Menu-Reference#reports)). For this report: put the
caret on the grid column's declaration or any use of it
(`dxDBGrid1OperationVName` in `Blueprint4.pas`), then *drag-lint > Reports >
Field round-trip (grid -> server -> SQL)...*. The plugin resolves the caret,
rewrites `Blueprint4.TfrmBlueprint4.dxDBGrid1OperationVName` to
`frmBlueprint4.dxDBGrid1OperationVName` from the DFM, shows it in a prompt, and
runs `drag-lint ask` in the background. The trace opens in your browser, and
the text comes back as a DocInsight block on the clipboard and in a small
window. The picture is *Reports > Callers and callees (butterfly chart)...* with
the caret on `SendDeltaOperation`. (The engine `ask` verb is still planned; the
menu runs the same scripts as the terminal form below.)

The IDE takes part in two more ways:

1. **The Tools-entry fallback**: RAD Studio's own *Tools > Configure Tools*
   entry, set up once below, runs the same command with a typed target. Use it
   where the plugin is not installed, or to keep the console open with
   `-NoExit`.
2. **The report jumps back into the IDE**: every `@File.pas:line` in the page is
   a `draglint://` link; a click opens that file at that line in the running
   IDE (needs the drag-lint plugin loaded and the link handler registered).

The pictures open in your browser, not in an IDE window. The docked
*drag-lint > drag-lint Graph* window is a different tool (the call graph).

### One-time setup: a Tools menu entry

*Tools > Configure Tools... > Add*, then fill in:

| Field | Value |
|---|---|
| Title | `drag-lint: field round-trip` |
| Program | `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` |
| Working dir | `C:\Projects\Delphi-RAG-lint` (users: your clone, see below) |
| Parameters | `ask round-trip --in "$EDNAME" --open --target $PROMPT` |

Add a second entry for the pictures, identical except:

| Field | Value |
|---|---|
| Title | `drag-lint: callers/callees chart` |
| Parameters | `ask butterfly --in "$EDNAME" --open --target $PROMPT` |

* `$EDNAME` is the file in the active editor tab: the script uses it only to
  find the project's index (any `.pas`/`.dfm` of the project works).
* `$PROMPT` makes RAD Studio show the parameter line before running it; type the
  target at the end (`frmBlueprint4.dxDBGrid1OperationVName` for the text,
  `Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation` for the
  picture).
* `-NoExit` keeps the console open so you can read the text answer and any
  error; `-Open` opens `index.html` in your browser.

> The command line behind these entries is verified from a terminal (below);
> the two entries themselves have not yet been clicked in a live IDE. If a macro
> expands differently on your RAD Studio version, run the terminal form.

### Producing the benchmark report from the IDE

1. Open any unit of the Micronite client, e.g. `Blueprint4.pas`, so it is the
   active editor tab.
2. **Save all** (*File > Save All*). Then make sure the index is fresh: the
   script refuses a stale index (exit 3) and prints the exact `index` command
   to run -- run it, then repeat this step.
3. *Tools > drag-lint: field round-trip*, append
   `frmBlueprint4.dxDBGrid1OperationVName` in the prompt, OK.
4. The console prints `BUNDLE <folder>`, the three `INDEX` lines, then the
   trace; the browser opens the same trace as a page.
5. *Tools > drag-lint: callers/callees chart* with
   `Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation` for the
   picture.
6. Click any `@Blueprint4.ViewModel.pas:NNNN` in the page to land on that line
   in the IDE.

## From a terminal (the same thing, verified)

From the repository folder:

```
drag-lint ask round-trip `
    --target frmBlueprint4.dxDBGrid1OperationVName `
    --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj --open

drag-lint ask butterfly `
    --target Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation `
    --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj --open
```

* Answers land in `%TEMP%\drag-lint-reports\<question>-<target>\`.
* `-ResolveOnly` prints the three indexes it would read and stops -- a quick
  check that setup is right.
* Exit codes: 0 answered, 1 refused (reason on stderr), 2 setup, 3 stale index.
* For a folder kept under the repository instead (`charts\artifacts\...`), use
  `New-DiagramArtifact.ps1`; see [Charts and the IDE](Charts-and-the-IDE).

## Setup: owner's machine

Everything is in place except the link handler, which is **stale**: it still
points at the old `archify-ir` worktree and at a versioned PowerShell folder
that the next PowerShell update deletes. Re-register once from the main
checkout:

```
drag-lint protocol register --dry-run
drag-lint protocol register
```

Then add the two Tools entries above.

## Setup: other users

The release zip (`drag-lint-v*-win64.zip`) carries the engine, the rules, the
rule-book editor and the docs. It does **not** carry the chart scripts or the
IDE plugin. To produce this report you need:

1. **A clone of the repository** (`git clone
   https://github.com/Alexl-git/Delphi-RAG-Lint.git`) -- the scripts live in its
   `charts\` folder.
2. **The engine** (`drag-lint.exe` with its `.dll` files and `rules\`); no
   PowerShell is needed.
4. **Graphviz 16.1** for the pictures. The engine uses the `dot.exe` named by
   the `DRAGLINT_DOT` environment variable, else the one in its settings, else
   `C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe` -- set the variable
   or install Graphviz to that folder. The text trace (`round-trip`) needs no
   Graphviz.
5. **The three indexes**, built with the engine: the client project, the server
   project and the SQL scripts. Find each with
   `drag-lint resolve-dbs --project <your .dproj>` and build it with
   `drag-lint index --project <your .dproj> --db <that path>`.
6. **Tell the scripts which server and SQL index belong to your client
   project**: edit `charts\report-pairs.json` (one object per project; check
   each path with `resolve-dbs` first).
7. **For the jump into the IDE**: the drag-lint IDE plugin installed in RAD
   Studio, and `drag-lint protocol register` run once.

Then add the two Tools entries, with your clone's path in place of
`C:\Projects\Delphi-RAG-lint`, and follow the steps above with your own form
and column.

## Not yet

* The *drag-lint > Reports* menu runs `drag-lint ask` (no PowerShell);
  the Tools entries above remain the fallback without the plugin.
* `round-trip` as a picture; today it is text.
* A Graphviz location setting for the chart scripts.
