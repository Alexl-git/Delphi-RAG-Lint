---
id: chart-engine-dot-lookup
title: Where the charts find Graphviz
summary: The charts find dot.exe by DRAGLINT_DOT, settings.json, the installed layout, PATH, then the shared default
product: DL
group: diagrams-charts
order: 80002
since: 1.26.1-alpha
status: shipped
updated: 1.33.0-alpha
---

# Where the charts find Graphviz

The charts find dot.exe by DRAGLINT_DOT, settings.json, the installed layout, PATH, then the shared default.

Point the charts at a different Graphviz without editing anything: set DRAGLINT_DOT, or put a dot key in %APPDATA%\drag-lint\settings.json. A path you set that does not exist is an error naming where it was set; nothing set means the installed layout, then dot.exe on PATH, then the shared default.

## Details

**The charts draw their pictures with Graphviz `dot.exe`; this page says where the
engine looks for it and how to point it somewhere else.** The text answers of
`drag-lint ask` and the Reports menu never need Graphviz: when no `dot.exe` is found
the text is still delivered, with `NOTE the chart could not be drawn`.

### The order

The engine takes the first candidate that exists:

| step | where | how to set it |
|---|---|---|
| 1 | `DRAGLINT_DOT` | environment variable naming `dot.exe` |
| 2 | `%APPDATA%\drag-lint\settings.json`, key `dot` | `{ "dot": "C:\\Graphviz\\bin\\dot.exe" }` |
| 3 | `graphviz\bin\dot.exe` in the charts files folder | an installed copy |
| 4 | `graphviz\bin\dot.exe` one folder above it | the [Setup installer](setup-installer.md) layout |
| 5 | `graphviz\bin\dot.exe` in the folder above `charts\` | an earlier installed layout |
| 6 | `dot.exe` on `PATH` | a Graphviz you installed yourself |
| 7 | `C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe` | the shared default of a development machine |

A missing or unreadable `settings.json`, a missing key or an unset variable is
skipped. A path someone SET -- `DRAGLINT_DOT` or the `settings.json` key -- that does
not exist is an error naming where it was set, so a typo never silently picks another
file. When nothing exists the error names every place looked at, in order. `PATH` is
walked entry by entry; the current folder is never searched.

### Examples

```text
$env:DRAGLINT_DOT = 'C:\Graphviz\bin\dot.exe'     (this session only)
```

or, for good, in `%APPDATA%\drag-lint\settings.json`:

```text
{ "dot": "C:\\Graphviz\\bin\\dot.exe" }
```

### See also

[Charts and the IDE](charts-and-the-ide.md), [Diagrams and Charts](chart-questions.md),
[ask](ask.md). Code: `src\charts\DRagLint.Charts.Tools.pas` (`ResolveGraphvizDot`).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
