# Menu Tree (code-built menus)

`drag-lint menu-tree` recovers, statically, the menu tree a Delphi program
BUILDS IN CODE -- `TMenuItem.Create` + `Caption :=` + `Parent.Add` / `Insert`,
wrapper helpers, data-driven submenus -- from the project index plus a
tree-sitter re-parse of only the routines that build menus. Nothing runs; no
IDE is needed.

## CLI

```
drag-lint menu-tree --project <X.dproj> --db <db> [--root <QName>] [--format text|json|paths] [--output <f>]
```

* `text` (default): an indented tree, `[kind] caption  -> handler  (file:line, confidence)`,
  then one `NOTE` line per note.
* `paths`: one leaf per line, `path<TAB>handler<TAB>file:line<TAB>confidence`;
  external roots follow, each after a `## external <ident>` line.
* `json`: schema `menu-tree/1` -- `roots`, `external`, `notes`; every node has
  `kind`, `caption`, `captionKey`, `handler`, `source`, `confidence`, `children`.
* `--root <QName>` walks one builder routine (and what it reaches) only.

Exit codes: 0 it ran; 2 usage or setup (no `--db`, project not in the db,
unknown `--root`); 3 stale index -- a file the walk must read changed since it
was indexed, so it refuses and prints the reindex command instead of answering
from old code.

## What it recognises

| Shape | Result |
|---|---|
| `X := TMenuItem.Create(O)` (or a `TMenuItem` descendant, inline `var` too) | a node, unparented until added |
| `X.Caption := E` | literal, `'a' + 'b'`, `Format('pattern', ...)` and const identifiers evaluate (certain); `ARR[I].Field` over a const array of records and a `case`-of-literals function expand to one node per value (derived); anything else is ONE `dynamic` node plus a note |
| `X.OnClick := H` | the handler, qualified through the index; a wrapper class built from a handler (`W := TWrapper.Create(H); X.OnClick := W.HandleClick`) is followed one level |
| `X.Enabled := False`, or no OnClick and no children | a header |
| caption `'-'` | a separator |
| `P.Add(X)` / `P.Insert(i, X)` | X under P; `MainMenu.Items.Add(X)` or `AddActionMenu(.., X, ..)` makes X a root; a menu-typed field / component / variable that is not a node of this run (a DFM item, a looked-up IDE menu) becomes an external root |
| a call that passes a node or an anonymous method | the callee's body is walked with its parameters bound -- this is how helpers such as `AddItem(Parent, 'Caption', Handler)` are recognised: by what their body does, never by their name |
| `if .. then .. else` | both branches; the same node added on both is one root |

A node created with `Create(nil)` and never added is a root; any other node
never added is a note (`unparented item`).

Builders are found through the index: routines whose body references
`TMenuItem` (or a descendant) and that take no menu-item parameter themselves
(those are helpers, walked from their call sites).

## Confidence

`certain` (literal caption, direct parenting or a recognised helper),
`derived` (const / case expansion, a callback binding), `unknown` (a dynamic
caption).

## Controls

`tests\fixtures\menutree` holds every shape above; `tests\autotest\run_menu_tree_guard.ps1`
compares `--format paths` with the hand-written `expected-paths.txt` cell by
cell, checks the JSON schema, exit 2 without `--db` and exit 3 on a touched
unit. `tests\autotest\run_menu_tree_tests.ps1` runs the unit tests, including
the renamed-helper control (rename `AddItem` to `PutItem` in a copy: the tree
does not change).

## Limits (v1)

DevExpress `TdxBar*` items, shortcuts and menu order are not compared;
context menus, About-form buttons and tool windows are out of scope. The tree
is computed on demand -- there is no persisted `menu_items` table yet.
