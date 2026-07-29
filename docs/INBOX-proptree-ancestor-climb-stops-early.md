# INBOX (engine): `proptree`'s ancestor climb drops the inherited surface on most control chains

- Date: 2026-07-28 (revised same day -- an earlier draft of this note over-generalised; see
  "Correction" at the end)
- From: component-conversion workstream (`feat/converter-editor`, worktree
  `C:\Projects\Delphi-RAG-lint-converter`)
- Exe under test: `C:\Projects\Delphi-RAG-lint-converter\third_party\dll-win64\drag-lint.exe`
  (`drag-lint 1.1.0-alpha`, Jul 21 build). Worth re-confirming against main's 1.2.1-alpha.
- Index: `C:\Projects\.drag-lint\library-Win64.sqlite` (schema 18, healthy) and
  `C:\Projects\DB\ORM3\drag-lint.sqlite`. NOT `library-Win32.sqlite` -- broken fragment, see
  `INBOX-index-all-win32-library-rebuild-aborts.md`.

## What we need

**`proptree` must return the COMPLETE inherited property surface, up to `TComponent`, for BOTH
sides of a conversion.** Concretely, for a target like `cxButtons.TcxButton` these must appear
as top-level leaves and today do not: `Name`, `Tag`, `Left`, `Top`, `Width`, `Height`,
`Visible`, `Hint`, `TabOrder`, `Cursor`, `Anchors`, `Constraints`, `PopupMenu`, `ShowHint`,
`ParentShowHint`, `HelpContext` -- i.e. everything `TControl`/`TWinControl`/`TComponent`
declares. The conversion editor can only offer what `proptree` returns, so a property missing
from the tree is a property the user cannot map.

Two independent defects produce the loss. Both are reproducible on one index with one command
each.

## Defect 1 -- a cross-unit ancestor hop fails when the ancestor NAME is not globally unique

The climb resolves an ancestor by name. When the ancestor lives in a different unit AND that
name exists in more than one unit, the hop is abandoned and the walk silently ends there. It
does not appear to consult the declaring unit's `uses` clause to disambiguate.

Measured (`--no-write-back`; "climb" = distinct `declared_in` of TOP-LEVEL leaves, i.e. how far
the root's own ancestor walk got):

| root | climb reached | `Name` | `Left` |
|---|---|---|---|
| `Vcl.Controls.TGraphicControl` | `TGraphicControl` -> `TControl` -> `TComponent` | 1 | 1 |
| `Vcl.Controls.TWinControl` | `TWinControl` -> `TControl` -> `TComponent` | 1 | 1 |
| `Abcbtn.TabcPicSpeedBtn` (ABC5) | 3 `Abcbtn` classes -> `TGraphicControl` -> `TControl` -> `TComponent` | 1 | 1 |
| **`Vcl.StdCtrls.TEdit`** | `TEdit` -> `TCustomEdit`, **stops** | 0 | 0 |
| **`Vcl.StdCtrls.TButton`** | `TButton` -> `TCustomButton` -> `TButtonControl`, **stops** | 0 | 0 |

The pattern fits every row above once you look at name uniqueness in the index:

| hop | ancestor unique? | same unit? | result |
|---|---|---|---|
| `TGraphicControl` -> `TControl` | no (4 units) | **yes** (`Vcl.Controls`) | works |
| `TabcCustomPicSpeedBtn` -> `TGraphicControl` | **yes** | no | works |
| `TControl` -> `TComponent` | **yes** | no | works |
| `TCustomEdit` -> `TWinControl` | **no** | no | **fails** |
| `TButtonControl` -> `TWinControl` | **no** | no | **fails** |

The ambiguous names, straight from the index:

```
TWinControl      -> FMX.Controls.Win.TWinControl, Vcl.Controls.TWinControl
TControl         -> FMX.Controls.TControl, Vcl.Controls.TControl,
                    Winapi.Microsoft.UI.Xaml.ControlsRT.TControl, Winapi.UI.Xaml.ControlsRT.TControl
TCustomEdit      -> FMX.Edit.TCustomEdit, Vcl.StdCtrls.TCustomEdit
TGraphicControl  -> Vcl.Controls.TGraphicControl            (unique)
TComponent       -> System.Classes.TComponent               (unique)
```

`TWinControl` is the load-bearing one: it is ambiguous **and** every windowed VCL control passes
through it, so the entire `TWinControl`/`TControl`/`TComponent` surface is lost for nearly all of
VCL. `TGraphicControl` is unique, which is the only reason the ABC5 chain works.

Corroboration that the data is present and the walk itself is capable: `TWinControl` as a ROOT
climbs to `TComponent` perfectly. It is only reaching it as an ANCESTOR that fails.

Reproduce:

```
drag-lint proptree --qname Vcl.StdCtrls.TEdit          --no-write-back --format json --db <library-Win64>
drag-lint proptree --qname Vcl.Controls.TWinControl    --no-write-back --format json --db <library-Win64>
```

The first has no `Name`/`Left`; the second does.

## Defect 2 -- a SAME-unit ancestor hop fails for `cxButtons.TcxCustomButton`

`cxButtons.TcxButton` stops after two `cxButtons` classes, so the whole DevExpress button surface
below `TcxCustomButton` is lost. Here the ancestor name IS globally unique
(`cxButtons.TcxBaseButton`, `cxButtons.pas:527`) and IS in the same unit, so defect 1 does not
explain it.

Two things to look at:

1. **`TcxCustomButton` has TWO class rows** -- a forward declaration `TcxCustomButton = class;`
   at `cxButtons.pas:53` (cols 3-27), and the real declaration at `cxButtons.pas:531`. If the
   resolver takes the forward declaration, it finds no ancestor and the walk ends.
2. **The real declaration is a multi-line header with interfaces:**
   `TcxCustomButton = class(TcxBaseButton,` / `IdxSkinSupport,` / `IcxLookAndFeelContainer,` ...
   A parser that expects `class(Ancestor)` on one line would yield no ancestor edge.

Reproduce:

```
drag-lint proptree --qname cxButtons.TcxCustomButton --no-write-back --format json --db <library-Win64>
```

Climb reaches `cxButtons.TcxCustomButton` and nothing else.

## Defect 3 (related) -- a project class climbs ZERO levels, even with both databases

```
drag-lint proptree --qname uMain.TfrmMAIN --no-write-back --format json \
  --db C:\Projects\DB\ORM3\drag-lint.sqlite --db C:\Projects\.drag-lint\library-Win64.sqlite
```

94 leaves, `Name`=0, `Tag`=0, and the climb list is `uMain.TfrmMAIN` alone -- not one ancestor.
A `TForm` descendant should reach `TForm` -> `TCustomForm` -> `TScrollingWinControl` ->
`TWinControl` -> `TControl` -> `TComponent`. Note `TForm`, `TCustomForm` and
`TScrollingWinControl` are all ambiguous VCL/FMX names, so defect 1 may fully explain this --
but please confirm, because **ancestor resolution must span every supplied `--db`**: a project
class's ancestors live in the library index, and the consumer already passes both
(`--db project --db library`). If the resolver only searches the index the class was found in,
that is a fourth issue.

## What it is NOT (all checked)

- **Not a visibility filter.** Absent with no `--min-visibility` at all (11074 leaves for
  `TcxButton`) as well as with `--min-visibility published` (592).
- **Not the `TPersistent` stop.** `--no-to-persistent` returns byte-identically 11074 leaves.
- **Not missing data.** `System.Classes.TComponent` is indexed, and its properties surface fine
  through NESTED paths -- `cxButtons.TcxButton`'s tree contains `Action.Name`, `Action.Tag`,
  `Action.ActionComponent.Name`, all `declared_in: System.Classes.TComponent`.
- **Not multi-db.** Adding the project DB to a library query changes nothing (11074 either way).

## Why it matters here

The conversion editor builds its From and To pools from `proptree`. Today the FROM side of the
user's real conversion works (`Abcbtn.TabcToggleBtn` returns `Name`, `Tag`, `Left`, `Top`,
`Width`, `Height`, `Visible`, `Hint`) while the TO side does not (`cxButtons.TcxButton` returns
none of them). The user sees a `Name` row he cannot assign, because there is no `Name` in the
target pool. The same holds for every geometry property, and their real `.dfm` files assign
exactly these -- e.g. `CLIENT\VARINSP.dfm` sets `Left`, `Top`, `Width`, `Height`, `GroupIndex`,
`Caption`, `Images`, `Layout`, `Picture.Data` on a `TabcToggleBtn`.

There is no editor-side workaround: synthesising the VCL surface in the editor would duplicate
the index and drift from it.

## Correction to the earlier draft of this note

An earlier version said inherited properties are missing generally, citing `TcxButton` and
`TButton`. That was too broad: `Abcbtn.TabcToggleBtn` and both `Vcl.Controls` base classes return
the full surface correctly. The failure is specific to the hops described above. The working
cases are the useful part of this report -- they show the walk is capable and narrow the search
to ancestor NAME RESOLUTION rather than to the walk or the data.
