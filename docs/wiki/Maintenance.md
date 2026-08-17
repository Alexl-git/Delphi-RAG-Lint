# Maintenance

Almost every "drag-lint gave me a wrong answer" turns out to be a stale or
mis-scoped index. This page is about keeping that from happening, and about
recognising it when it does.

---

## Where indexes live

**One database per project, beside the project file:**

```
<folder containing the .dproj>\_D-RAG\<project file base name>.sqlite
```

Named after the **project file**, not the folder -- one folder can host several
projects.

**One database per platform for the library** (RTL, VCL, DevExpress, other
third-party). These have no owning project folder, so they live together:

```
C:\Projects\.drag-lint\library-Win64.sqlite
C:\Projects\.drag-lint\library-Win32.sqlite
```

### Never guess a path -- ask the tool

```
drag-lint resolve-dbs --platform win64
drag-lint resolve-dbs --project C:\path\MyApp.dproj
drag-lint resolve-dbs --in      C:\path\SomeUnit.pas
```

---

## The manifest

`drag-lint.json`, beside the exe, lists every index as a **section** and lets
consumers (`query`, `lint-all`, `lsp`, `serve`, `graph`) pick the right database
with no `--db`.

A section's **type is declared by its target**: an `include` entry ending in
`.dpr`/`.dproj` makes a **project** section; a folder makes a **library** or
folder section. The **mode is chosen per run**: `--rebuild` (from scratch) or
`--recompile` (incremental, the default).

A **project index is exactly the compile closure** -- the `.dproj` members, the
units they transitively use, each unit's sibling `.dfm`, `{$I}` includes, and the
project file. Units on the Delphi Library/Browsing path are excluded (they belong
to the library index), and loose unreferenced files in the project folder are
excluded.

### Which databases may answer a question

**The authoritative set is the platform library index plus the one project
index -- and nothing else.** Another project's database is noise: a name match
there is not a caller here. Passing extra databases is how unrelated units once
got written into a project's documentation.

Authority is also **per question**: the library index is right for *"which unit
declares X"* and wrong for *"who calls X"*.

---

## Routine reindexing

```
drag-lint index --all --only <SectionName>      # one section, incremental
drag-lint index --all --jobs 0                  # everything
drag-lint index --all --dry-run                 # preview the plan
```

**Reindex a project section by name.** Do not point a folder scan at a project
database (`index <dir> --db <projectdb>`) -- a project index is a compile
closure, and a folder walk changes what the section owns.

**Reindex after a build that changed symbols**, incrementally. Do not full-rescan
the tree after every build.

### After an upgrade

The index records an **indexer fingerprint** -- engine version, schema, whether
preprocessing was on, and the effective platform. When it changes, every file in
scope is re-parsed, because a newer engine may extract symbols the stored parse
missed. This is deliberate: the alternative is silently stale parses.

Consequence: **a release upgrade re-parses every index once.** For a large
library index that is a long walk. Two things make it survivable:

* **Per-file resume** -- an interrupted re-parse continues where it stopped
  instead of restarting.
* **The whole-database announce** -- a long call-target resolve now says so, with
  its reason, *before* it runs.

---

## Reading a long run

Set `DRAGLINT_PROFILE=1` for a per-phase breakdown on **stderr**.

```
set DRAGLINT_PROFILE=1
cd C:\tools\drag-lint
.\drag-lint.exe lint-all --db <index> --quiet
```

If you see this, the run is **working, not hung**:

```
resolve: calls  starting WHOLE-DB pass over all 6993 indexed file(s)
resolve: calls  ... whole database because this run rewrote more than one file
                    in three (236 changed, limit 235)
resolve: calls  ... this is the expensive shape (~37 min on a 2 GB index)
                    -- it is running, not hung
```

The call-target resolve has two shapes: a **scoped** pass that re-resolves only
what changed, and a **whole-database** pass. The scoped one is several times
faster; the message names the reason the scoped one was declined.

---

## Troubleshooting

### "database is locked"

An orphaned `drag-lint.exe` (or `drag_lint_graph.exe`) still holds it. **Check
first, before diagnosing anything else:**

```
Get-Process drag-lint
```

Note that piping a run through `Select-Object -First N` does **not** kill the
process -- it detaches and keeps indexing, and the lock then looks like a broken
tool. The IDE plugin also holds a handle on the project's database for the whole
session.

### An answer is missing a symbol you can see in the source

The index is stale. **Reindex that section and retry** rather than concluding the
tool cannot find it.

```
drag-lint index --all --only <Section>
```

A database several engine versions old will answer from an older parser --
quietly, and with fewer results rather than an error.

### Output appears only when the run finishes

That is the shell, not the engine. **PowerShell holds a native process's stderr
until the process exits.** For long runs redirect through `cmd.exe`, or use
`Start-Process -RedirectStandardError`, and poll the file.

### The wrong binary answered

If a before/after comparison shows an implausible change, check *which exe ran*.
With `NoDefaultCurrentDirectoryInExePath` set, a bare `drag-lint ...` after a
`cd` resolves from `PATH`, not the current folder. Use `.\drag-lint.exe`. The
quickest tell is the `DRAGLINT_PROFILE` breakdown **format**, which changes
whenever the profiler does -- an old-format report means an old binary.

### A batch `index --all` reported success but one index is missing

Section builds are independent; a section that fails prints `ERROR building
section <name>` and the sweep continues. **Read the log for `ERROR`, do not trust
the exit code alone.** If you hit an intermittent
`FOREIGN KEY constraint failed`, keep the log and the database rather than
re-running -- a re-run usually succeeds, which is why it stays undiagnosed.

---

## Third-party library updates

Updating a large third-party suite (DevExpress and similar) changes many library
units at once, so the library index goes stale and needs a reindex:

```
drag-lint index --all --only Library --jobs 0
```

Expect a whole-database call-target resolve: new units bring new type names,
which is exactly the condition that declines the scoped pass. It will announce
itself with its reason. Budget accordingly, and let it finish.
