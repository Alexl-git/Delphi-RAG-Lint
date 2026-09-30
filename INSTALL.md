# drag-lint -- Installation & Linter Quick Start

`drag-lint` is a self-contained command-line tool (plus an optional RAD Studio
IDE plugin). This guide covers the **CLI** from the release archive: what you
need, how to unpack and check it, how to describe your projects in the
manifest, how to build and refresh an index, the optional charts, and what to
do when something goes wrong.

Contents:
[Requirements](#requirements) |
[1. Install](#1-install-cli) |
[1a. Unpack and verify](#1a-unpack-and-verify) |
[2. Build an index](#2-build-an-index-for-querynavigation-features) |
[2a. The manifest](#2a-the-manifest) |
[2b. Your first project index](#2b-your-first-project-index) |
[3. Lint a unit](#3-lint-a-unit) |
[4. What it checks](#4-what-it-checks) |
[5. IDE plugin](#5-ide-plugin-optional) |
[6. Editors](#6-vs-code-zed-and-other-editors-optional) |
[7. Charts](#7-charts-optional) |
[8. Troubleshooting](#8-troubleshooting) |
[9. Uninstall](#9-uninstall)

## Requirements

| Needed for | Requirement | Notes |
|---|---|---|
| everything | Windows x64 | `drag-lint.exe` is a native Win64 program. |
| the CLI, the indexer and the linter | nothing else | No RAD Studio, no .NET, Python or Node. The three tree-sitter DLLs ship beside the exe. |
| the platform library index (RTL/VCL/third-party) | RAD Studio installed | The `Library` manifest section reads the Library/Browsing paths RAD Studio registers (section 2a). |
| the IDE plugin | RAD Studio 37.0 (Delphi 13) | The plugin is a design-time package and is not in the release archive (section 5). |
| the charts, and the test scripts in a source checkout | PowerShell 7 (`pwsh`) | |
| the charts | Graphviz 16.1 (`dot.exe`) | Where the chart scripts look for it: section 7. |

## 1. Install (CLI)

1. Download the Win64 archive: `drag-lint-vX.Y.Z-win64.zip`.
2. **Unzip the whole folder, keeping every file together.** The archive holds
   one top folder, `drag-lint-vX.Y.Z-win64\`, containing:

   ```
   drag-lint.exe                 the engine: CLI, indexer, linter, LSP server
   tree-sitter-delphi13.dll      } parser DLLs -- must sit next to the exe
   tree-sitter-dfm.dll           }
   tree-sitter.dll               }
   rules\                        external lint rules (*.scm + *.json)  <-- REQUIRED for linting
     builtin-symbols.txt
     README.md                   the rule list with one-line descriptions
   ConvRulesEditor.exe           visual component-conversion rule editor (win64 archive ONLY)
   casts.castlib                 class + enum casts (convert-apply --castlib; also read by the editor)
   convrules\                    starter conversion rule books (sample, BDE-to-FireDAC, vendor\)
   README.md  CHANGELOG.md  LICENSE  INSTALL.md
   docs\AI-USAGE.md              the CLI reference written for AI agents
   docs\PARSING-LAYERS.md/.html  background on the parsing layer
   docs\CONVERSION-RULES.md
   docs\converter\               the rule language, and the editor manual (win64)
   docs\lint\                    REPORT-1 / REPORT-2 (lint design background)
   ```

   **Not in the archive:** the manifest `drag-lint.json` (you write it --
   section 2a), the IDE plugin (section 5), the VS Code extension (section 6)
   and the chart scripts (section 7).

   `ConvRulesEditor.exe` is **Win64 only** -- it is built by `dcc64` from a `.dpr`
   with no Win32 configuration. The win32 archive still has `convrules\`,
   `casts.castlib` and the `convert-*` verbs, so the same rule books are authored
   and applied from the CLI there; only the GUI is absent.

   **Known issue -- the win32 archive.** The release script
   (`build\pack-lint-release.ps1`) still builds and zips a
   `drag-lint-vX.Y.Z-win32.zip` beside the win64 one, although the Win64 engine
   is the supported build. Whether the win32 archive keeps being published is an
   open question. Use the win64 archive. (A 32-bit engine also refuses a
   database larger than its size guard; see `--size-guard-mb` / `--force32` in
   `drag-lint --help`.)

3. (Optional) add the folder to your `PATH`, or call `drag-lint.exe` by full
   path -- and read the note on bare names in section 1a first.

> **Important for the linter:** the `.scm` lint rules load from a `rules\` folder
> **next to `drag-lint.exe`**. Keep `rules\` beside the exe (the archive already
> places it there). If you move the exe, move `rules\` with it, or pass
> `--rules-dir <path>`. If no rules load, `drag-lint lint` prints a one-line note
> to stderr (the built-in checks still run).

## 1a. Unpack and verify

**Where to unzip.** Any folder you can write to. The examples below assume the
contents of the archive's top folder were placed in `C:\Tools\drag-lint\`.
Avoid `C:\Program Files\`: the manifest `drag-lint.json` lives beside the exe,
and `register-project --apply` edits it there.

**Upgrading.** Stop everything that runs the old exe first (section 8,
"used by another process"), then copy the new files over the old ones, or use
the new folder and copy your `drag-lint.json` into it.

The examples from here on are PowerShell and call the engine through a
variable holding its full path. Sections 2-6 write `drag-lint` for short; run
it the same way.

```
$dl = 'C:\Tools\drag-lint\drag-lint.exe'
& $dl --version        # one line: drag-lint <version>
& $dl info             # version, build date, tree-sitter ABI, the DLLs it loaded, exe path, platform
& $dl info --json      # the same as one JSON document ("schema":"info/1")
& $dl rules            # first line: "<N> rules across <M> categories"
```

Check that `info` reports `platform: Win64`, that `exe` is the file you meant to
run, and that both tree-sitter DLL paths are the ones beside it. `rules` must
report the rule count stated in section 4; a smaller number (the built-in rules
only) means `rules\` was not found beside the exe.

**The index verdict.** `info --json --db <index.sqlite>` (repeat `--db` for
several) adds one `indexes` entry per database, with a `verdict`. It compares
the index with THIS ENGINE -- it is what to check after an upgrade. It does not
look at your source files; edited sources are reported differently (section 8).

| `verdict` | Meaning | What to do |
|---|---|---|
| `current` | parsed and resolved by this engine's extractor and resolver | nothing |
| `resolve-owed` | parses are current, call edges come from an older resolver | run the command in `remedy` (a `--resolve-only` pass; minutes) |
| `reparse-owed` | parsed by an older extractor | run the command in `remedy` (a full re-parse; a large library index takes hours) |
| `index-newer` | written by a NEWER engine | reads work; indexing with this engine is refused -- use the newer engine |
| `missing` | no file at that path | build it (section 2b) |
| `unreadable` | the file exists but cannot be read as an index | check the path; rebuild it |

The `remedy` field is present for `resolve-owed`, `reparse-owed` and
`index-newer`, and absent otherwise. Without `--json`, `info --db <index>`
prints the same verdict as one `index: <path>  verdict: <v>` line per
database, followed by an indented `remedy: ...` line when one is owed.

**Always run the engine by full path, or as `.\drag-lint.exe` from its own
folder.** When the Windows environment variable
`NoDefaultCurrentDirectoryInExePath` is set, `cmd.exe` does not look in the
current folder, so a bare `drag-lint` resolves through `PATH` -- possibly to an
older copy. PowerShell never runs a program from the current folder by bare
name. To see which copy a bare name would run:

```
Get-Command drag-lint -All
where.exe drag-lint
```

## 2. Build an index (for query/navigation features)

```
drag-lint index --project C:\path\to\MyApp.dproj --db C:\path\to\_D-RAG\MyApp.sqlite
drag-lint query --name TMyClass --db C:\path\to\_D-RAG\MyApp.sqlite
drag-lint query find-callers --name DoStuff --db C:\path\to\_D-RAG\MyApp.sqlite
```

(The linter below does **not** require an index -- it works straight on a `.pas` file.)

Sections 2a and 2b explain where index files belong, how to let the manifest
name them, and how to keep them fresh.

## 2a. The manifest

`drag-lint.json` **beside `drag-lint.exe`** names every index you want. It is
read by `index --all`, `resolve-dbs`, `register-project`, and by every verb you
run without `--db`. `index --all` and `resolve-dbs` also take
`--config <path>` to read a different file.

**The archive does not ship one.** Without it, `index --all --dry-run` prints
`Sections to build: 0` and `index --all` does nothing and exits 0.

A minimal manifest (JSON: double every backslash):

```
{
  "settings": { "defaultPlatform": "Win64", "maxJobs": 0 },
  "indexes": {
    "outDir": "C:\\Tools\\drag-lint\\indexes",
    "exclude": [ "*BACKUP*", "* - Copy.pas" ],
    "sections": [
      { "name": "MyApp",   "include": [ "C:\\Code\\MyApp\\MyApp.dproj" ] },
      { "name": "Vendor",  "include": [ "C:\\Code\\Vendor" ] },
      { "name": "Library", "db": "library-{platform}.sqlite",
        "source": "registry-libraries", "platforms": [ "Win32", "Win64" ] }
    ]
  }
}
```

`indexes` is an OBJECT holding `outDir`, `exclude` and the `sections` array --
not an array. A key of the wrong JSON type is named, with its path and both
types: `indexes: expected object, got array`, or
`indexes.sections[1].sqlOnlyMS: expected boolean, got string`. Text that is not
JSON at all reads `(root): not valid JSON -- <parser detail>`. The same goes
for the `.drag-lint.json` defaults keys (`docs.captureLooseComments: expected
boolean, got string`). A WRITE verb -- `index` (even with `--db`), `index --all`
(`--config` included), `refresh-findings` without `--db`, `register-project`
(and `purge-locals` when the bad key is in `.drag-lint.json`, which may be what
named its `db`) -- REFUSES with exit 2 and
`ERROR: <verb>: refusing to write -- the manifest could not be parsed: <file>: <key path>: expected <type>, got <type>`;
a bad local `.drag-lint.json` never quietly hands the run to the global
manifest. `compile-check` still compiles and reports, but caches nothing. A
read verb prints `WARNING: could not parse config at <file>: <key path>: ...`
once and carries on with whatever did parse.

What a section's target makes it, and where its database lands:

| Section | Type (`--dry-run` shows `mode=`) | Database |
|---|---|---|
| `include` names a `.dproj` / `.dpr` | **Project** (`closure`): the compile closure only | `<project folder>\_D-RAG\<project file base name>.sqlite` |
| `include` names a folder | **Library / folder** (`folderTree`): every file under it | `<outDir>\<section name>.sqlite`, or the section's `"db"` |
| `"source": "registry-libraries"` | **Platform library** (`library`), one per listed platform | `<outDir>\library-Win32.sqlite`, `<outDir>\library-Win64.sqlite` |

Other section keys you will see in a full manifest: `db` (an explicit
database path), `exclude` and `includeOnly` (glob lists), `useIgnoreFiles`,
`sqlOnlyMS`.

Add a project without hand-editing (the manifest must already exist):

```
& $dl register-project C:\Code\MyApp\MyApp.dproj           # dry run: prints the section and the manifest path
& $dl register-project C:\Code\MyApp\MyApp.dproj --apply   # writes it
```

Build and inspect:

```
& $dl index --all --dry-run                          # the plan: each section, its mode and its database path
& $dl index --all --jobs 0                           # build every section
& $dl index --all --only MyApp                       # one section
& $dl index --all --only Library --platform win64    # one platform's library index
& $dl resolve-dbs --platform win64                   # the databases query / lsp / serve read
& $dl resolve-dbs --project C:\Code\MyApp\MyApp.dproj  # the ONE database that owns this project
```

* `--jobs 0` (or no `--jobs`) uses the manifest's `maxJobs`, and when that is
  also 0, a count sized from the CPUs.
* The `Library` sections cover every folder RAD Studio registers and are by
  far the slowest to build. Build them once, on their own.
* `resolve-dbs --platform` prints only databases that exist. A configured but
  never-built one is a `NOTE:` line on stderr naming the command that builds
  it: `index --all --only <Section>`, plus `--platform <P>` for a library
  database (`--only Library --platform Win64`) and `--config <path>` when
  `resolve-dbs` was given one.
* `resolve-dbs --project` exits 2 and says so when no section, or more than
  one, claims the project. Never guess a database path; ask it.

## 2b. Your first project index

```
$proj = 'C:\Code\MyApp\MyApp.dproj'
$db   = & $dl resolve-dbs --project $proj           # when the project is in the manifest
# not in the manifest? name it yourself:  $db = 'C:\Code\MyApp\_D-RAG\MyApp.sqlite'

& $dl index --project $proj --db $db --dry-run      # prints the compile closure; writes nothing
& $dl index --project $proj --db $db                # build it, or refresh it
& $dl info --json --db $db                          # verdict "current"
& $dl query --name TMyClass --db $db
```

**Always pass `--db`.** Give it the path `resolve-dbs --project` printed, or
the `_D-RAG` path above. An explicit path is the only one you can read back
from your own command line.

Without `--db` (and with no `"db"` in a `.drag-lint.json`, which counts as an
explicit `--db`), a `--project` run -- or `index` given a `.dpr`/`.dproj`
directly -- touches only the project's OWN database: its exact manifest
section, else `<project dir>\_D-RAG\<project>.sqlite`. `index` and
`refresh-findings` write there; readers open it plus the platform library and
no other project's database. Two sections claiming the project make `index`
and `refresh-findings` refuse, naming both. `compile-check` caches only into an
explicit `--db` or the project's unique manifest section, and otherwise reports
without caching. `purge-locals` always needs an explicit `--db`. Before 1.20.4
an unregistered project could be indexed into the FIRST manifest section's
database -- another project's.

**What a project index holds.** The compile closure: the project members, the
project-local units they use (transitively), each unit's sibling `.dfm`, its
`{$I}` includes, and the project file. Units on a Delphi Library/Browsing path
belong to the library index; loose `.pas` files nobody uses are left out.

**Incremental vs `--rebuild`.** The default mode (`--recompile`) re-parses only
files whose path, time or content changed. A re-indexed unit is replaced
whole, and a unit dropped from the `.dproj` is removed. `--rebuild` empties the
index of source first and re-parses everything; use it when section 8 tells
you to (`files` greater than `walked`) or when a `remedy` says so.
`--force-reparse` re-parses every file without emptying the index.

**Never `index <folder> --db <project database>`.** A folder target turns a
project database into a folder database: it adds every `.pas` under the
folder, loose and unused ones included, and an incremental project run can
never remove them again. Use `index --project <x.dproj>` for a project index,
and give a folder its own section and database.

**Check the project file is complete.** A unit that is used but not listed in
the `.dproj` / `.dpr` is not indexed, and nothing warns you. After the first
index, run the dry run below and read the units it lists as missing:

```
& $dl reconcile-project $proj --db $db --json        # dry run; --apply edits the project file
```

## 3. Lint a unit

```
drag-lint lint C:\path\to\MyUnit.pas
```

Text output is `file:line:col [severity] rule-id: message`; add `--json` for tooling:

```
drag-lint lint MyUnit.pas --json
```

Useful options:

| Option | Meaning |
|---|---|
| `--json` | machine-readable findings (`rule`, `severity`, `file_path`, `start_line`, ...) |
| `--rule <id>` | run only one built-in rule (e.g. `--rule code-after-exit`) |
| `--rules-dir <dir>` | load external `.scm` rules from `<dir>` instead of `<exe-dir>\rules` |
| `--project <file.dproj>` | also run project-level checks (e.g. `unit-not-in-dpr`) |

Exit code is `1` when any findings are reported, `0` when clean.

### Suppressing a finding

Add a line comment on the offending source line:

```pascal
SomeQuery.SQL.Text := 'SELECT * FROM t WHERE id=' + Id;  // drag-lint:ignore sql-injection-concat
X := X;  // drag-lint:ignore           <-- suppress ALL rules on this line
```

`// drag-lint:ignore` (alone) silences every rule on that line; followed by one
or more rule ids it silences only those. Applies to both `.scm` and built-in rules.

## 4. What it checks

This release ships **189 rules** (159 enabled by default, 23 with an auto-fix)
across 16 categories: exceptions, control-flow
/ dead code, expression bugs, resource/lifetime, naming, and security (SQL
injection, hardcoded credentials). Run `drag-lint rules` for the full,
always-current catalog. The list with one-line descriptions is also in
[`rules\README.md`](rules/README.md); the design rationale and the wider Delphi
lint landscape are in [`docs\lint\`](docs/lint/) (REPORT-1 / REPORT-2).

External rules (the `*.scm` files in `rules\`) are plain text -- you can add your
own; see `rules\README.md` for the format.

## 5. IDE plugin (optional)

The RAD Studio plugin (`dclDragLintWizard.bpl`) surfaces these diagnostics live
in the editor. It spawns `drag-lint.exe`; make sure that exe has its `rules\`
folder beside it (or is launched with `--rules-dir`).

The plugin is not in the release archive. It is built from the source
repository (`src\delphi-plugin\README.md`) and installed through
**Component > Install Packages... > Add**. Its settings pages are described in
[`docs\INSTALL.md`](docs/INSTALL.md).

## 6. VS Code, Zed and other editors (optional)

drag-lint ships a stdio language server -- `drag-lint lsp` -- giving hover,
go-to-definition, **find-references**, **workspace symbols**, completion and
signature help from the index, across every project in your manifest at once.
(DelphiLSP implements neither find-references nor workspace symbols, so those
two are not duplicated features.)

* **VS Code** -- an extension is included in the source repository (not in the
  release archive); install it from `editors\vscode\drag-lint\`.
* **Zed** -- highlighting works today via the tree-sitter grammars; registering
  the language server needs a small Rust/WASM extension that is **not yet
  built**. It is fully specified so anyone with `rustup` can finish it.
* **Neovim / Helix / anything else** -- point it at `drag-lint lsp` over stdio.

Full instructions, settings and the Rust extension specification:
[docs/EDITORS.md](docs/EDITORS.md).

## 7. Charts (optional)

Charts answer PATH and SET questions (who calls, who writes, where a grid
field lands) as a picture plus a text trace. They are PowerShell scripts in the
source repository's `charts\src\`, **not in the release archive**: you need a
clone of the repository, PowerShell 7, Graphviz, and an index for the project
(section 2b) that is listed in the manifest.

**Graphviz.** Graphviz is not bundled. Install Graphviz 16.1.0 so that this
file exists, then check it:

```
& 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe' -V
# dot - graphviz version 16.1.0 (20260904.0139)
```

(The parent folder is `GraphWiz`, the product folder `Graphviz-...`.)

**Where the scripts look.** Every `charts\src\Emit-*.ps1` has two parameters
with built-in defaults:

* `-Dot` -- `C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe`
* `-Engine` -- `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`

`Ask-Report.ps1` and `New-DiagramArtifact.ps1` do not pass either one on
(`Ask-Report.ps1 -Engine` is used only for its own index-resolution and
freshness calls). So either keep Graphviz and the engine at those two paths,
or run an `Emit-*.ps1` directly with `-Dot <path> -Engine <path>`.

A clone at `C:\Projects\Delphi-RAG-lint` gives the right folder but not the
engine: `*.exe` is gitignored. Build it (`build\build_draglint_win64.bat`
deploys to `third_party\dll-win64\`), or copy the release's `drag-lint.exe`
and `rules\` there (the three DLLs are already in the clone). That folder also
holds the repository's own `drag-lint.json`, which names the maintainer's
projects; replace it with your manifest (section 2a), or `Ask-Report.ps1`
cannot resolve your project.

**One question, as text:**

```
pwsh -NoProfile -File C:\Projects\Delphi-RAG-lint\charts\src\Ask-Report.ps1 -Question who-calls -Target MyUnit.TMyClass.DoStuff -Project C:\Code\MyApp\MyApp.dproj
```

It finds the index with `resolve-dbs`, refuses a stale one (exit 3, with the
reindex command on stderr), writes the bundle under
`%TEMP%\drag-lint-reports`, and prints `BUNDLE <folder>`, one `INDEX <db>` line
per index read, then the answer. Exit codes: 0 answered, 1 the question
refused (reason on stderr), 2 setup (what to pass or edit), 3 stale. The
question ids are listed in `charts\question-catalogue.md`.

**Clickable `draglint://` links** (a chart row opening the line in RAD Studio)
need a one-time, per-user registration -- one key under
`HKCU:\Software\Classes\draglint`, no elevation:

```
pwsh -NoProfile -File C:\Projects\Delphi-RAG-lint\charts\src\Register-DragLintProtocol.ps1 -DryRun   # shows what it would write; writes nothing
pwsh -NoProfile -File C:\Projects\Delphi-RAG-lint\charts\src\Register-DragLintProtocol.ps1           # registers
```

It copies the handler to `%LOCALAPPDATA%\drag-lint\Open-DragLintUri.ps1` and
registers the copy. It refuses a script that sits in a `*-wt\` worktree
unless you add `-Force`. A click reaches the IDE only when RAD Studio is
running with the plugin loaded; otherwise the file opens in Notepad.

Everything else -- the questions, reading a trace, the bundle files, what the
link handler will and will not open -- is in
[docs\wiki\Charts-and-the-IDE.md](docs/wiki/Charts-and-the-IDE.md).

## 8. Troubleshooting

### "used by another process" or "database is locked"

Another process holds the exe or the index: the IDE plugin's or VS Code's
language-server engine, an `index --watch` run, or an orphaned `drag-lint.exe`
left by an interrupted command (a pipeline cut short, e.g. by
`| Select-Object -First N`, can leave the engine running).

```
Get-Process drag-lint | Select-Object Id, StartTime, Path
& $dl shutdown --dry-run      # lists the running `lsp` engines it would ask to stand down
& $dl shutdown                # asks them to close every index and exit
Stop-Process -Id <Id>         # a leftover that is not an lsp engine -- check Path and StartTime first
```

The VS Code extension runs its own engine copies from
`%APPDATA%\Code\User\globalStorage\drag-lint.drag-lint\engine\`; they appear in
`Get-Process` too. To replace the exe while RAD Studio stays open, close the
IDE, or see `ide-release` in `drag-lint --help`.

### A stale index

Two different things are called stale:

1. **Your source changed after indexing.** Queries print a note on stderr:

   ```
   drag-lint: note: 1 of 2 indexed file(s) changed since this index was built e.g. MyUnit.pas.
   Answers may be stale -- this is a PROJECT index, so refresh it with:
   drag-lint index --project <file.dproj> --db <db>   (or: drag-lint index --all --only <Section>)
   ```

   Run that command (incremental; seconds for a small change). JSON output
   carries the same fact as `stale` / `stale_files` on the verbs that report
   it (see `drag-lint --help`).

2. **The engine was upgraded.** `& $dl info --json --db <db>` gives the
   `verdict` and, when work is owed, the `remedy` command (table in
   section 1a).

### `files` greater than `walked` on a section summary

`index --all` ends each section with a line like:

```
=== MyApp -> C:\Code\MyApp\_D-RAG\MyApp.sqlite : files=2 symbols=2 refs=2 walked=2 attempted=0 up-to-date=2 [0.2s, n/a] ===
```

`files` counts every file row in the database; `walked` counts the files this
run's walk admitted. When `files` is larger, the database holds files that
this project's walk never visits -- usually swept in by an earlier
`index <folder> --db <this database>`. An incremental run cannot remove them.
Rebuild:

```
& $dl index --project C:\Code\MyApp\MyApp.dproj --db <db> --rebuild
```

### `find-callers` returns 0 callers

`find-callers` matches the BARE member name. `--name TMyClass.DoStuff` returns
`0 caller(s)` (exit 1); `--name DoStuff` returns the call sites. Check the name
form first, then that `--db` is the database that owns the code, then
staleness. `--resolved` lists precise callers from the resolved call edges.

### `index --all` built nothing

`Sections to build: 0` in the dry run means no manifest was found beside the
exe (or at `--config`); that still exits 0, so read the dry run. A malformed
manifest (beside the exe, a local `.drag-lint.json`, or `--config`) makes
`index` refuse with exit 2 and
`ERROR: index --all: refusing to write -- the manifest could not be parsed: <file>: indexes: expected object, got array`
-- the file, the key path and both types (`indexes` must be an object,
section 2a).

### No lint rules load

`rules` reports fewer rules than section 4 states, and `lint` prints a note on
stderr: `rules\` is not beside the exe. Move it back, or pass
`--rules-dir <path>`.

## 9. Uninstall

1. Stop every running engine (section 8, "used by another process").
2. Delete the install folder: the exe, the DLLs, `rules\`, and your
   `drag-lint.json`.
3. Delete the indexes you built: each project's `_D-RAG\` folder beside its
   `.dproj`, and the manifest's `outDir` (the library and folder-section
   databases).
4. If you registered `draglint://`, remove it (add `-DryRun` first to see what
   it would remove):

   ```
   pwsh -NoProfile -File C:\Projects\Delphi-RAG-lint\charts\src\Register-DragLintProtocol.ps1 -Unregister
   ```

   It removes `HKCU:\Software\Classes\draglint` and the handler copy in
   `%LOCALAPPDATA%\drag-lint\`.
5. Delete `%LOCALAPPDATA%\drag-lint\` (the handler log and the control-channel
   audit log live there).
6. IDE plugin: in RAD Studio, **Component > Install Packages...**, select the
   drag-lint package, **Remove**, then restart the IDE. Its settings are under
   `HKCU\Software\drag-lint\DelphiPlugin`; delete that key to remove them.
7. VS Code: uninstall the extension from the Extensions view.

---

drag-lint is **alpha** -- expect rough edges and breaking changes.
Issues & feedback: https://github.com/Alexl-git/Delphi-RAG-Lint/issues
