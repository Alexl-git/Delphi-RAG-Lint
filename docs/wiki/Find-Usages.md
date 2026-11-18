# Find Usages...

Lists every reference to the symbol under the editor caret across the
indexed project. Reach for it before changing or removing a symbol, to see
everywhere it is used.

## Reaching it in the IDE
drag-lint > Find Usages...

Keyboard shortcut: Ctrl+Alt+F.

## Running it from the CLI
There is no standalone CLI verb for this menu item (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin. The
bundled language server exposes find-references over stdio to other
editors -- the [Features](Features) page lists find-references among the
methods `drag-lint lsp` implements -- but that is a stdio protocol server,
not a one-shot CLI command.

This is a different feature-map row from the right-click "Find Usages"
action on a Structure-tree node, which does have an underlying verb -- see
[Find Usages (context)](Find-Usages-context).

## Scope: this symbol, project, group or everywhere (1.52)
Find Usages answers in one of four scopes. The default is **This symbol**: the
usages of exactly the object the caret is on, in this project -- the declaration
the index bound that reference to, not every field, property or routine that
happens to share its name. The other three widen the question to the NAME:

| Scope | Lists | CLI |
|---|---|---|
| This symbol (default) | the declaration the caret is bound to, this project | `usages --in <file> --line <L> --col <C>` (or a qualified `--name`) |
| Project | every object of that name in this project | `usages --name <X> --scope project` |
| Group | the name in every project of the open project group | `usages --name <X> --scope group --group <x.groupproj>` |
| Everywhere | the name in every index the manifest knows | `usages --name <X> --scope everywhere` |

Pick a scope from drag-lint > Find Usages > This symbol / Project / Group /
Everywhere, from the same submenu on the editor right-click drag-lint menu, or
from the scope box on the results panel (changing it re-runs the search). The
Find Usages tab of the drag-lint panel has the same box in place of its old
Narrow / Wide switch. When the caret is not on a bound reference (a typed name,
an unresolved call), This symbol is answered as Project and the title says so.
The LSP's find-references follows the same default (setting
`dragLint.usagesScope`), and the MCP server has a `find_usages` tool with a
`scope` argument.

## Where the answer comes from
When the language server is running and its databases cover the query (scopes This symbol and Project), the form asks it (`draglint/usages`) and starts no process. Otherwise, and when the server has not answered within 10 s or answers an error (an older engine), it runs `drag-lint usages`. Both give the same rows.

## What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs an open editor with the caret on the target symbol.

## Example
Illustrative: with the caret on `TCustomerOrder.Total`, choose "Find
Usages..." to list every reference to `Total` across the indexed project.
