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
  `kind`, `caption`, `captionKey`, `handler`, `source`, `confidence`, `children`;
  an external root has `ident` and `identPath` (the file whose code names the
  identifier -- for a DFM item, the form's own `.pas`) instead of a caption.
  Two forms that each own an item called `mnuTools` give two external roots.
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
| a call that passes a node, an anonymous method, or a menu-typed component the index knows (`AddMenuItem(mnuTools, ..)`) | the callee's body is walked with its parameters bound -- this is how helpers such as `AddItem(Parent, 'Caption', Handler)` are recognised: by what their body does, never by their name. A parent passed in from outside keeps the CALLER's name: the external root is `mnuTools` in the form's file, not the helper's parameter |
| `if .. then .. else` | both branches; the same node added on both is one root |

A node created with `Create(nil)` and never added is a root; any other node
never added is a note (`unparented item`).

Builders are found through the index: routines whose body references
`TMenuItem` (or a descendant) and that take no menu-item parameter themselves
(those are helpers, walked from their call sites).

## Drift against the registry: `menu-drift`

```
drag-lint menu-drift --project <X.dproj> --db <db> --registry <features dir> [--format text|json] [--output <f>]
```

Compares the live tree with the `ide-menu` surfaces of `<features dir>\entries\*.json`
(and the `captions` of `exemptions.json`) by PATH key -- the same caption /
path keys featuregen uses (`&&` -> `&`, `...` dropped, punctuation trimmed,
lowercase, segments joined with ` > `).

| Class | When | Printed with |
|---|---|---|
| `MISSING` | a registered path the code does not build, and its caption is nowhere else | `renamed? -> '<caption>'` when a live, unregistered item under the same parent shares at least 12 leading key characters |
| `MOVED` | a registered path whose caption now lives under another parent | `now at <live path>` |
| `UNREGISTERED` | a built item no surface covers (exact path, or a caption prefix of at least 12 characters under the same parent) and not exempted | a skeleton surface line to paste |
| `NOTE` | dynamic captions, unparented items, an exempted caption that is now a submenu / header / root (the exemption is no longer needed) | -- |

Separators, headers, submenus and external roots are never `UNREGISTERED`; a
registered path that names a live submenu is not `MISSING`; a registered path
under a parent that holds a dynamic item is never `MISSING` (the dynamic item
may be it -- its note says so). Order inside a submenu is not compared.

Summary line: `menu-drift: missing=N unregistered=N moved=N notes=N`. Exit 0 no
drift, 1 drift, 2 usage / setup, 3 stale index. `--format json` writes
`menu-drift/1` (`missing`, `moved`, `unregistered`, `notes`, `summary`).

The battery runs it on the IDE plugin itself (`tests\autotest\run_menu_drift_guard.ps1`):
positive controls on the fixture (a deleted entry -> `UNREGISTERED`, a changed
caption -> `MISSING` with `renamed?`, a changed parent -> `MOVED`, a renamed
helper -> no drift, a caption made dynamic -> a note, a touched unit -> exit 3),
then the real run, which passes only on exit 0. The plugin index is a
`tests\autotest\prepare_battery.ps1` artifact (`src\delphi-plugin\_D-RAG\dclDragLintWizard.sqlite`).
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

## forms-csv (algorithm v8)

`forms-csv` runs the same walker and grafts every external root whose
identifier is a `TMenuItem` of the form's own `.dfm` (and is named in that
form's `.pas`) under that item: code-added items and submenus then appear in
`How to open` (`Main menu: Tools > Code Reports`) and their handlers feed the
launch trace. Separators, headers and dynamic captions are not grafted. A walk
that cannot run (stale index, setup problem) prints one
`forms-csv: code-built menu items skipped (..)` line on stderr and the CSV is
written from the `.dfm` menus alone. Guard: `tests\autotest\run_forms_csv_v8.ps1`
(fixture `tests\fixtures\formsmap-v8`).

## Limits (v1)

DevExpress `TdxBar*` items, shortcuts and menu order are not compared;
context menus, About-form buttons and tool windows are out of scope. A
`TMainMenu` / `TPopupMenu` named as a parent (`MainMenu1.Items.Add(X)`,
`AMenu.Items.Add(X)`) is an external root but is not grafted by forms-csv.
The tree is computed on demand -- there is no persisted `menu_items` table yet.
