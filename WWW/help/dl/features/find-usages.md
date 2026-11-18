---
id: find-usages
title: Find Usages
summary: "Lists every reference to the symbol under the editor caret, in one of four scopes: this bound symbol (default), project, group or everywhere"
product: DL
group: search-navigation
order: 20011
since: 0.33.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Find Usages

Lists every reference to the symbol under the editor caret, in one of four scopes: this bound symbol (default), project, group or everywhere.

Read this before changing or removing a symbol, to see every place it is used. With the caret on the symbol choose drag-lint > Find Usages... (Ctrl+Alt+F): by default it lists the usages of exactly that object in this project. drag-lint > Find Usages > This symbol / Project / Group / Everywhere (also on the editor right-click drag-lint submenu) and the scope box on the results panel widen it to every object of the name in the project, the project group or every index; the same list comes from the command line as `drag-lint usages --scope <scope>`.

## Where to click

* RAD Studio main menu: **drag-lint > Find Usages...**
   1. Needs an index of the project
   2. Put the editor caret on the symbol
   3. drag-lint > Find Usages...
* RAD Studio main menu: **drag-lint > Find Usages > This symbol**
   1. Needs an index of the project
   2. Put the editor caret on the symbol
   3. drag-lint > Find Usages > This symbol
* RAD Studio main menu: **drag-lint > Find Usages > Project**
   1. Needs an index of the project
   2. Put the editor caret on the symbol
   3. drag-lint > Find Usages > Project
* RAD Studio main menu: **drag-lint > Find Usages > Group**
   1. Needs an index of the project
   2. Put the editor caret on the symbol
   3. drag-lint > Find Usages > Group
* RAD Studio main menu: **drag-lint > Find Usages > Everywhere**
   1. Needs an index of the project
   2. Put the editor caret on the symbol
   3. drag-lint > Find Usages > Everywhere
* Right-click in the Editor: **drag-lint > Find Usages > This symbol**
   1. Put the caret on the symbol
   2. Right-click in the code editor and open drag-lint > Find Usages
   3. Choose This symbol
* Right-click in the Editor: **drag-lint > Find Usages > Project**
   1. Put the caret on the symbol
   2. Right-click in the code editor and open drag-lint > Find Usages
   3. Choose Project
* Right-click in the Editor: **drag-lint > Find Usages > Group**
   1. Put the caret on the symbol
   2. Right-click in the code editor and open drag-lint > Find Usages
   3. Choose Group
* Right-click in the Editor: **drag-lint > Find Usages > Everywhere**
   1. Put the caret on the symbol
   2. Right-click in the code editor and open drag-lint > Find Usages
   3. Choose Everywhere

## Details

Lists every reference to the symbol under the editor caret across the
indexed project. Reach for it before changing or removing a symbol, to see
everywhere it is used.

### Running it from the CLI
There is no standalone CLI verb for this menu item (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin. The
bundled language server exposes find-references over stdio to other
editors -- the Features page lists find-references among the
methods `drag-lint lsp` implements -- but that is a stdio protocol server,
not a one-shot CLI command.

This is a different feature-map row from the right-click "Find Usages"
action on a Structure-tree node, which does have an underlying verb -- see
[Find Usages (context)](find-usages-context.md).

### Scope: this symbol, project, group or everywhere (1.52)
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

### Where the answer comes from
When the language server is running and its databases cover the query (scopes This symbol and Project), the form asks it (`draglint/usages`) and starts no process. Otherwise, and when the server has not answered within 10 s or answers an error (an older engine), it runs `drag-lint usages`. Both give the same rows.

### What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs an open editor with the caret on the target symbol.

### Example
Illustrative: with the caret on `TCustomerOrder.Total`, choose "Find
Usages..." to list every reference to `Total` across the indexed project.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
