> **RETIRED to INBOX-Done/ on 2026-08-15.** FIXED: guarded by tests/autotest/run_proptree_ancestor_climb.ps1, green in the full battery. Three REPLY notes on the same topic (ancestor-climb, ancestor-scope, branch-collision) were also retired.
>
> Original note follows unchanged.

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

**ROOT CAUSE, added 2026-07-29 -- this supersedes the framing below. The disambiguation logic is
not missing; the data it depends on is empty.**

Ancestor resolution happens at INDEX time in `ResolveAncestry`
(`src/storage/DRagLint.Storage.SQLite.pas:3477-3641`), which writes `type_ancestors`. `proptree`
only reads it: `ClassChain` (`src/report/DRagLint.Convert.PropTree.pas:278-304`) calls
`GetTransitiveAncestors` once and silently skips any row that is not `Resolved`.

`ResolveAncestry` ALREADY disambiguates same-named ancestors, via `CandInScope` (`:3490`), which
tests membership of `unit_uses.target_file_id`. When several candidates exist and none is in scope
it deliberately declines -- `ancestor_symbol_id = NULL, ancestor_kind = '?'`, with the comment
*"FP policy: when unsure, don't claim"*.

**Every `unit_uses` row for `Vcl.StdCtrls.pas` (file_id 4597) has `target_file_id = NULL`** --
`ResolveUnitUseTargets` never resolved that file's uses. So `CandInScope` sees zero in-scope
candidates against the two global `TWinControl` candidates and declines. Verified directly in
`library-Win64.sqlite`: `Vcl.StdCtrls.TCustomEdit`'s row is `(0, 'TWinControl', '?', NULL, NULL)`.

So the name-ambiguity pattern documented below correctly describes WHICH hops fail -- a hop
survives only where no disambiguation is needed -- but the fix is not "add a scope rule". It is
"make the existing rule's input work, and add a fallback for the indexes already on disk".

**A spec and implementation plan exist**, in the converter repo on `feat/converter-editor`:
`docs/superpowers/specs/2026-07-29-proptree-ancestor-scope-design.md` and
`docs/superpowers/plans/2026-07-29-proptree-ancestor-scope.md`. The design pairs a **query-time
fallback** -- `ResolveTypeNameToClass`'s `PickCandidate`/`LoadScopeNames` (`:2458-2551`) matches
unit names TEXTUALLY and needs no `target_file_id`, and `ResolveViaBridgedAncestry.Climb`
(`PropTree.pas:477-537`) already climbs per-hop with the inheriting class's own FileId -- with the
index-time repair of `ResolveUnitUseTargets`. The query-time half matters because it repairs
EXISTING indexes with no re-index, and a full library rebuild currently aborts (sibling INBOX
note), so a re-index-only fix would be blocked behind a second unfixed bug.

Take it, adapt it, or discard it -- the engine is yours. We have not touched engine code for this.

---

The climb resolves an ancestor by name. When the ancestor lives in a different unit AND that
name exists in more than one unit, the hop is abandoned and the walk silently ends there.

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

**Both of the obvious explanations are DISPROVED (2026-07-29). Please do not spend time on them:**

1. *Forward declaration shadowing the real class.* `TcxCustomButton` does have two class rows --
   `TcxCustomButton = class;` at `cxButtons.pas:53` and the real declaration at `:531` -- but
   `IsForwardDeclClass` (`PropTree.pas:231-234`) already distinguishes them by empty heritage and
   `EndLine <= StartLine`, and `ResolveAncestry` step 1b already drops stubs.
2. *Multi-line class header losing the ancestor.* The real header does span lines with interfaces
   (`class(TcxBaseButton,` / `IdxSkinSupport,` / `IcxLookAndFeelContainer,` ...), but
   `HeritageTextOf` (`src/parser/DRagLint.Parser.Delphi13.pas:397-436`) walks AST `typeref`
   children rather than text lines, and the heritage is captured INTACT as
   `'TcxBaseButton, IdxSkinSupport, IcxLookAndFeelContainer, ...'`.

Our current belief is that this is the same NULL `target_file_id` problem as defect 1 -- the
resolver declines rather than failing to see the ancestor -- but we did not confirm it for this
specific pair, so it is still listed separately. `cxButtons.TcxBaseButton` IS indexed
(`cxButtons.pas:527`), so the target exists.

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

## Heads-up: `main` moved on 2026-07-28, from our side

Two commits you did not make are on `main`, both from the converter workstream, both with the
user's explicit approval. Flagging them so they are not a surprise:

- **`4536c20`** merges `feat/converter-editor` into `main`. It resolved the long-owed `f65fb9c`
  cherry-pick KEEP-BOTH, so `main` now has proptree/2 **and** `--refs-as-leaves`. Verified after
  the merge: `run_proptree.ps1` 20/0, `run_convert_rules.ps1` 26/0, and on `cxButtons.TcxButton`
  the flag takes 11074 -> 7748 leaves, composing with `--min-visibility published` for 592 -> 404.
- **`674706a`** fixes a latent bug that came in with `f65fb9c`: `TPropTreeOptions` is a record of
  unmanaged fields, so a local is uninitialised stack memory, and five of its six construction
  sites set only `Depth`/`ToPersistent` -- leaving `TreatRefsAsLeaves` garbage in
  `DoConvertValidate`, `DoConvertReemit`, `DoConvertScaffold`, `DoConvertApply` and
  `BuildApplyPlan` (`DRagLint.Convert.Apply.pas:994`). Fixed with
  `Opts := Default(TPropTreeOptions);` at every site, which also protects the next field added to
  the record. No behaviour change beyond removing the nondeterminism: the convert verbs now
  deterministically get the documented default `False`, and only the `proptree` verb sets the
  field from `--refs-as-leaves`.

Nothing is pushed -- `main` is local-only at `674706a`.

One caveat on that fix worth knowing: the existing fixtures never exercise a TComponent-typed
property through the `convert-*` verbs, so output was byte-identical before and after. The bug was
real but silent under current coverage, and there is still no regression tripwire for that class
of defect.
