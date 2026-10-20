# About and Status

*drag-lint > About*

The plugin's status window: what versions are running, whether each component is
reachable, **which index files are actually being used**, which settings are
misconfigured, and how much memory the IDE is holding. It also hosts the
diagnostic actions that used to live under a *Diagnostics & Tests* menu section.

## Why it exists

For several months the IDE answered hover, go-to-definition and completion from
a 1.5 GB library index left over from before the 2026-08-11 layout change.
Nothing appeared broken, because a stale index answers confidently -- just with
older and fewer results. Rebuilding the library indexes changed nothing, which
made it look like a rebuild problem rather than a resolution problem.

The cause was a manifest lookup built from `Settings.ExePath`, which defaults to
the bare name `drag-lint.exe`. `ExtractFilePath` of that is empty, so the plugin
looked for a *relative* `drag-lint.json` against the IDE's working directory,
found none, and fell back -- silently, through four separate exits that recorded
nothing.

**One line of UI would have exposed it in seconds instead of a day.** That line
is now the first thing in the Indexes group.

## The groups

| Group | What it tells you |
|---|---|
| **Versions** | Plugin version and BPL build time, engine version and build date, tree-sitter grammar versions, whether the graph viewer is deployed. |
| **Connections** | LSP state (connected / starting / DOWN, with the reason), whether the engine exe was found, and whether every resolved index exists on disk. |
| **Indexes in use** | The active project and platform, then **the library index path actually in use, its size and write date, and the rule that chose it**. Then every other resolved index. |
| **Configuration** | Settings that misconfigure the plugin without any visible symptom -- a bare-name `ExePath`, a `DbPathTemplate` predating the `_D-RAG` layout, a disabled library index, a missing manifest. |
| **Process** | Free system RAM, the IDE's private bytes and handle count. The IDE is a 32-bit process, so these are real operating limits rather than trivia. |

Values are coloured: **green** healthy, **amber** suspicious, **red** broken. A
red line is the one to act on.

### Colours follow the IDE theme

The window registers with `IOTAIDEThemingServices` and repaints for the active
light or dark theme, and every status colour is lifted to a **WCAG 4.5:1**
contrast ratio against the themed background before it is used.

That second part is not decoration. Plain `clRed` and `clGreen` fall close to
unreadable on a dark background, and on a screen where the colour *is* the
message, the colour carrying the warning must not be the one you cannot read.

(The IDE themes itself through `IOTAIDEThemingServices`, **not** the global VCL
`TStyleManager` -- `TStyleManager.IsCustomStyleActive` reads False and the global
`StyleServices` stays light even while the IDE is visibly dark. Anything reading
the global services instead of the IDE's own appears to do nothing.)

### Fix buttons

A finding the plugin can correct itself shows a **Fix** button beside it. Only
settings with **one unambiguous correct value** get one -- a button that guesses
would turn a visible warning into an invisible wrong setting.

Two are offered today:

| Warning | What Fix writes |
|---|---|
| `Settings.ExePath` is a bare name, empty, or missing | The engine path actually in use, resolved the same way every spawn resolves it |
| `DB path template` has no `<projname>` | The current `<projdir>\_D-RAG\<projname>.sqlite` default |

Fix always shows the exact **before and after** and asks for confirmation before
writing, because it edits your registry settings. After a successful change the
whole window re-reads itself -- correcting `ExePath` changes which manifest
resolves, which can change the library index reported two groups above, and
showing a corrected setting beside the stale consequence it caused would be its
own small lie.

**Worth doing on a default install.** `ExePath` defaults to the bare name
`drag-lint.exe`. Spawning still works, because Windows resolves it through
`PATH` -- but `ExtractFilePath` of it is empty, so anything needing the engine's
*directory* silently fails. That is precisely the bug described above.

### Reading the library line

The most important line in the window is the rule that chose the library index:

* **`manifest <path> -> outDir <dir>, platform Win32`** -- trustworthy. The
  index was selected from the manifest for the active project's platform.
* **`FALLBACK -- ...`** -- shown in red. The manifest rule declined, and the
  message says exactly why (no manifest at that path, no `indexes.outDir`, no
  `library-<platform>.sqlite` in the outDir, or a parse failure). A fallback is
  treated as a defect rather than a lesser mode, because a fallback index may be
  from any era.

## Actions

| Button | What it does |
|---|---|
| **Diagnose Current State** | Builds the full text report and shows it in a copyable window. This is what to paste into an issue. |
| **Copy Report** | The same report, straight to the clipboard. |
| **Refresh** | Re-reads every group. |
| **Open Plugin Log** | The plugin's own log -- start here when a menu item misbehaves. |
| **Run Diagnostics (didSave)** | The diagnostics pass the editor integration fires on save. |
| **Run AST Checks** | The built-in AST checks only, on the current file. |
| **Lint Buffer (Unsaved)** | Lints the editor buffer, including unsaved edits. |
| **Copy Diagnostics (Current File)** | The current file's findings, to the clipboard. |
| **Recover Buffer-Compile Files** | Recovers temporary files an interrupted buffer compile left behind. |
| **Import Build Log...** | Loads an external build log so its errors become browsable findings. |

## Performance

Opening this window does **not** open a database. Index facts come from the file
system only -- path, size, write time.

This is a deliberate constraint, not an optimisation. On the 3 GB
`library-Win32.sqlite`, `schema --format json` takes **38 seconds**, because it
runs `COUNT(*)` on every table; opening the same file and doing an indexed
lookup takes **0.5 seconds**. A status screen that is slow does not get opened,
and a status screen nobody opens reports nothing.

(That 38-second figure also caused a wrong diagnosis once: it was read as "a
large index is slow to open" and produced a filed defect aimed at the wrong
target. The real cost of opening a multi-GB index is half a second.)

## The connection indicator

When the LSP server is down the top-level menu caption becomes **`drag-lint (!)`**
and stays that way while the condition holds. The plugin retries the connection
after 30 seconds, lazily -- on the next action that needs the server, not on a
timer.

There is deliberately no modal dialog. The previous one announced *"LSP
initialize handshake failed"* for a handshake that had actually **succeeded**,
56 seconds after the client stopped waiting -- and that sentence sent a day of
debugging at the server when the real cause was the plugin's own process storm
saturating the machine. The window shows the recorded error verbatim instead of
paraphrasing it into a claim.

## See also

* [IDE Menu Reference](IDE-Menu-Reference)
* [Maintenance](Maintenance)
