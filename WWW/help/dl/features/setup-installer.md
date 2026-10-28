---
id: setup-installer
title: Setup installer
summary: One Inno Setup installer for the engine, Graphviz dot, the IDE plugin, ConvRulesEditor, drag-lint-graph and YADF
product: DL
group: editor-integration
order: 110020
since: 1.28.3-alpha
status: experimental
updated: 1.36.0-alpha
---

# Setup installer

One Inno Setup installer for the engine, Graphviz dot, the IDE plugin, ConvRulesEditor, drag-lint-graph and YADF.

`drag-lint-setup-<version>.exe` installs the whole tool set per user or for all users, registers the IDE plugins only where RAD Studio 13 is installed, and uninstalls only what it wrote.

## Details

`drag-lint-setup-<version>.exe` installs the whole drag-lint tool set in one go:
the engine, its rules and parser DLLs, the `draglint://` helper, Graphviz `dot`, the
RAD Studio plugin, ConvRulesEditor, drag-lint-graph and YADF. It is an Inno
Setup 6 installer; **status: experimental** until it has passed a clean-machine
test.

For the manual, zip-based route see [Installation](installation.md).

### What you choose

**Who it is for.** The first page asks *Just for me* (the default -- no admin
rights, installs under `%LOCALAPPDATA%\Programs\drag-lint`) or *All users*
(Windows asks for admin rights, installs under `Program Files`). The IDE plugin
registration and the `draglint://` links are per user in both modes.
Per user means the account that RUNS setup: if Windows asks for a different
administrator account, the plugin and links are registered for that account,
not yours -- install *Just for me* from your own account instead.

**Components.** Everything is ticked in a full install.

| Component | What you get |
|---|---|
| engine, rules and chart scripts | always installed |
| ConvRulesEditor | the conversion-rules editor |
| drag-lint-graph | the call-graph tool |
| Graphviz dot | `dot.exe` and its DLLs -- the charts need it |
| IDE plugin (32-bit IDE / 64-bit IDE) | the `drag-lint` menu in RAD Studio 13 |
| YADF formatter | `YADF.exe` and `YADFSetup.exe` (its settings editor) |
| YADF IDE plugin (32-bit IDE / 64-bit IDE) | YADF's RAD Studio menu and Options page |

An IDE plugin is offered only for an IDE that is actually installed: on a
machine without RAD Studio 13 those lines are greyed out and say why. A BPL
loads only in the IDE version it was built for, and this release builds for
RAD Studio 13 (37.0) only.

**Tasks.**

* *Register draglint:// links* (ticked) -- clicking a node in a chart opens that
  line in the IDE. If links are already registered, setup asks before replacing
  them.
* *Register drag-lint as an MCP server* (not ticked) -- for Claude Code and
  VS Code.

### What it needs

* **Windows x64.**
* **No PowerShell.** Every chart question is answered by the engine itself; setup
  neither bundles nor looks for PowerShell and installs no `.ps1` file.
* **RAD Studio must be closed** when installing or uninstalling a plugin -- a
  loaded BPL is locked. Setup refuses with that message rather than half-copying.

### What it changes, and what uninstall undoes

| Change | Uninstall |
|---|---|
| files under the install folder | removed |
| `bin\drag-lint.json` (starter index manifest, no projects) | **kept** -- after the first run it is your file |
| one `Known Packages` value per plugin, named by its installed path | that value removed; other packages untouched |
| plugin setting `HKCU\Software\drag-lint\DelphiPlugin\ExePath` | removed only if it still points at this install |
| `HKCU\Software\YADF\ExePath` | removed only if it still points at this install |
| `draglint://` registration | unregistered only if this setup registered it |
| MCP entries (if ticked) | removed |

Setup never overwrites an `ExePath` that already points at a working engine or
YADF elsewhere without asking, and a silent install never overwrites one.

If the same plugin is already registered from another folder (a developer's
repository build, say), setup warns: two copies of one package make the IDE
refuse to load one of them. A silent install does not ask: it skips that plugin and
says so in the setup log.

### Updating

Run the newer setup over the old one; it upgrades in place and keeps your
settings and `drag-lint.json`. *drag-lint > About > Check for Updates* in the
IDE tells you when a newer release exists.

If a release changes the extractor version, every index on the machine is
re-parsed on its next use -- the release notes say when.

### Building the setup

```text
pwsh -File installer\Build-Installer.ps1            # -> installer\Output\drag-lint-setup-<version>.exe
pwsh -File installer\Build-Installer.ps1 -DryRun    # checks only
```

The version comes from `DRAGLINT_VERSION`; the build stops if the engine being
shipped reports a different one, or if any source file is missing. Sources
default to the deployed `third_party\dll-win64` / `dll-win32`, `C:\Projects\YADF`
(Release builds) and the Graphviz 16.1.0 `bin` folder; each is a parameter.
Licences shipped: drag-lint (MIT), tree-sitter and both grammars (MIT),
delphi-tree-sitter (MIT), Graphviz (EPL-2.0), YADF.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
