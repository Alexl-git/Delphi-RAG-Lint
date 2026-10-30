---
id: about-and-status
title: About and Status
summary: The plugin's status window -- versions, connection health, and which indexes are actually in use
product: DL
group: maintenance
order: 120001
since: 0.15.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# About and Status

The plugin's status window -- versions, connection health, and which indexes are actually in use.

Read this when hover or go-to-definition seems to answer from the wrong place, or you need to know what is running. The status window shows the versions in use, whether each component is reachable, which index files are actually being used, misconfigured settings and how much memory the IDE holds.

## How to run it

```text
drag-lint info [--json] [--db <file.sqlite>]... (engine self-info: product/extractor/resolver versions, build date, MIT, tree-sitter + capabilities; read-only)
```

Full flag list: [info in the CLI reference](../cli.md#info).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--json` |  |  |  |
| `--db` | `<file.sqlite>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > About**
   1. Choose drag-lint > About
   2. Read the version, connection-health, index-file, settings and memory groups
   3. Use Refresh to re-read every group, or Diagnose Current State to get a report to paste into an issue
* drag-lint About window, button **Check for Updates**
   1. Choose drag-lint > About
   2. Click Check for Updates to look for a newer release
* drag-lint About window, button **Close**
   1. Choose drag-lint > About
   2. Click Close to dismiss the window
* drag-lint About window, button **For help and additional information refer to:**
   1. Choose drag-lint > About
   2. Click the website link at the top of the window to open https://www.delphi-rag-lint.com
* drag-lint About window, button **Website (Help)**
   1. Choose drag-lint > About
   2. Click Website (Help), or the link at the top of the window, to open https://www.delphi-rag-lint.com for help, articles and downloads
* drag-lint About window, button **Copy Diagnostics (Current File)**
   1. Choose drag-lint > About
   2. Click Copy Diagnostics (Current File) to put the current file's findings on the clipboard
* drag-lint About window, button **Copy Report**
   1. Choose drag-lint > About
   2. Click Copy Report to put the full status report on the clipboard
* drag-lint About window, button **Diagnose Current State**
   1. Choose drag-lint > About
   2. Click Diagnose Current State to build the full text report and show it in a copyable window
* drag-lint About window, button **Import Build Log...**
   1. Choose drag-lint > About
   2. Click Import Build Log... and pick an external build log so its errors become browsable findings
* drag-lint About window, button **Lint Buffer (Unsaved)**
   1. Choose drag-lint > About
   2. Click Lint Buffer (Unsaved) to lint the editor buffer including unsaved edits
* drag-lint About window, button **Open Plugin Log**
   1. Choose drag-lint > About
   2. Click Open Plugin Log to see the plugin's own log
* drag-lint About window, button **Recover Buffer-Compile Files**
   1. Choose drag-lint > About
   2. Click Recover Buffer-Compile Files to recover temporary files an interrupted buffer compile left behind
* drag-lint About window, button **Refresh**
   1. Choose drag-lint > About
   2. Click Refresh to re-read every group
* drag-lint About window, button **Run AST Checks**
   1. Choose drag-lint > About
   2. Click Run AST Checks to run the built-in AST checks on the current file
* drag-lint About window, button **Run Diagnostics (didSave)**
   1. Choose drag-lint > About
   2. Click Run Diagnostics (didSave) to run the diagnostics pass the editor fires on save

## Details

*drag-lint > About*

The plugin's status window: what versions are running, whether each component is
reachable, **which index files are actually being used**, which settings are
misconfigured, and how much memory the IDE is holding. It also hosts the
diagnostic actions that used to live under a *Diagnostics & Tests* menu section.

### Why it exists

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

### The groups

| Group | What it tells you |
|---|---|
| **Versions** | Plugin version and BPL build time, engine version and build date, tree-sitter grammar versions, whether the graph viewer is deployed. |
| **Connections** | LSP state (connected / starting / DOWN, with the reason), whether the engine exe was found, and whether every resolved index exists on disk. |
| **Indexes in use** | The active project and platform, then **the library index path actually in use, its size and write date, and the rule that chose it**. Then every other resolved index. |
| **Configuration** | Settings that misconfigure the plugin without any visible symptom -- a bare-name `ExePath`, a `DbPathTemplate` predating the `_D-RAG` layout, a disabled library index, a missing manifest. |
| **Process** | Free system RAM, the IDE's private bytes and handle count. The IDE is a 32-bit process, so these are real operating limits rather than trivia. |

Values are coloured: **green** healthy, **amber** suspicious, **red** broken. A
red line is the one to act on.

#### Colours follow the IDE theme

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

#### Fix buttons

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

#### Reading the library line

The most important line in the window is the rule that chose the library index:

* **`manifest <path> -> outDir <dir>, platform Win32`** -- trustworthy. The
  index was selected from the manifest for the active project's platform.
* **`FALLBACK -- ...`** -- shown in red. The manifest rule declined, and the
  message says exactly why (no manifest at that path, no `indexes.outDir`, no
  `library-<platform>.sqlite` in the outDir, or a parse failure). A fallback is
  treated as a defect rather than a lesser mode, because a fallback index may be
  from any era.

### Actions

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

### Performance

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

### The connection indicator

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

### See also

* [IDE Menu Reference](ide-menu-reference.md)
* [Maintenance](maintenance.md)

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
