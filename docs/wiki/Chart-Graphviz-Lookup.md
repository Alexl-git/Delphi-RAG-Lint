# Where the charts find Graphviz

**The charts draw their pictures with Graphviz `dot.exe`; this page says where the
engine looks for it and how to point it somewhere else.** The text answers of
`drag-lint ask` and the Reports menu never need Graphviz: when no `dot.exe` is found
the text is still delivered, with `NOTE the chart could not be drawn`.

## The order

The engine takes the first candidate that exists:

| step | where | how to set it |
|---|---|---|
| 1 | `DRAGLINT_DOT` | environment variable naming `dot.exe` |
| 2 | `%APPDATA%\drag-lint\settings.json`, key `dot` | `{ "dot": "C:\\Graphviz\\bin\\dot.exe" }` |
| 3 | `graphviz\bin\dot.exe` in the charts files folder | an installed copy |
| 4 | `graphviz\bin\dot.exe` one folder above it | the [Setup installer](Setup-Installer) layout |
| 5 | `graphviz\bin\dot.exe` in the folder above `charts\` | an earlier installed layout |
| 6 | `dot.exe` on `PATH` | a Graphviz you installed yourself |
| 7 | `C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe` | the shared default of a development machine |

A missing or unreadable `settings.json`, a missing key or an unset variable is
skipped. A path someone SET -- `DRAGLINT_DOT` or the `settings.json` key -- that does
not exist is an error naming where it was set, so a typo never silently picks another
file. When nothing exists the error names every place looked at, in order. `PATH` is
walked entry by entry; the current folder is never searched.

## Examples

```
$env:DRAGLINT_DOT = 'C:\Graphviz\bin\dot.exe'     (this session only)
```

or, for good, in `%APPDATA%\drag-lint\settings.json`:

```
{ "dot": "C:\\Graphviz\\bin\\dot.exe" }
```

## See also

[Charts and the IDE](Charts-and-the-IDE), [Diagrams and Charts](Diagrams-and-Charts),
[ask](ask). Code: `src\charts\DRagLint.Charts.Tools.pas` (`ResolveGraphvizDot`).
