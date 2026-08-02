# ConvRules editor -- feature backlog (raised 2026-07-30)

> **STATUS 2026-08-02 -- Phase G is DELIVERED.** Everything specced below as "SPEC BELOW"
> has since been designed, built, reviewed and verified. Read this header before reading
> the rest of the file: the item table immediately after it is the ORIGINAL 2026-07-30
> snapshot and is kept only for the history in item 1.
>
> | Phase G | Deliverable | State |
> |---|---|---|
> | G1 | Theme: follow the IDE, else Light/Dark (`ConvRules.Theme.pas`, VCL styles) | **DONE** |
> | G2 | Toolbar: 19 of 22 loose buttons consolidated | **DONE** |
> | G3 | Go to definition in the IDE + enum-member listing | **DONE** -- live IDE jump verified end-to-end 2026-08-02 |
> | G4 | `#mapping` / `#apply` conditional enum -> property rules (**editor only**) | **DONE** |
> | G5 | Examine harvests `uses` clauses into the Unit Rules FROM list | **DONE** |
> | G6 | Deferred items -- recorded so nobody files them as bugs | **DEFERRED BY DESIGN** |
> | G7 | ReFind BDE->FireDAC corpus | **DONE** -- imported as PRODUCT files in the new top-level `convrules\`, not as test fixtures |
> | G8 | Documentation deliverable (DSL design message + human manual) | **NOT STARTED** |
>
> Spec, including every as-built deviation: `docs\superpowers\specs\2026-07-30-converter-editor-phase-g-design.md`.
> Plan: `docs\superpowers\plans\2026-07-30-converter-editor-phase-g.md`.
> Suite at completion: **543 pass / 0 fail / 0 skip**.
>
> **The rule books moved.** `docs\examples\convrules\sample.rules` is now
> `convrules\sample.rules`, alongside `convrules\FireDAC_Migrate_BDE.rules` and
> `convrules\FireDAC_Rename_Units.rules`.
>
> Still open from this file after Phase G: the two "Also found this session" items below
> -- **event-coverage assertions in the Usage scanner fixtures** and **tests for the grid
> search boxes** -- neither of which Phase G addressed.

Six items were raised in one pass. Three are **done** and recorded here so nobody
re-implements them; three need design before code and are specced below.

**(The table below is the 2026-07-30 original. Items 3, 5 and 6 became G1, G3 and G4 and
are now DONE -- see the status header above.)**

| # | Item | State |
|---|------|-------|
| 1 | From/To search boxes disappeared | **DONE** -- regression, fixed by merging `feat/converter-editor` into `main` |
| 2 | Green-highlight actually-used properties **and events** | **ALREADY SHIPPED** -- including events; see below |
| 4 | Show the type on To properties | **DONE** -- `PropCellText`, 7 checks |
| 3 | Dark / Light modes | **SPEC BELOW** |
| 5 | Jump to a type's definition in the IDE | **SPEC BELOW** (raised explicitly as a TODO) |
| 6 | Conditional enum -> property-value rules in the DSL | **SPEC BELOW** -- the largest of the three |

## Item 1 -- what actually happened (keep, it will recur)

`main` and `feat/converter-editor` diverged at `3949ec3` and never reconverged. Each
carried half the product: `main` had the proptree ancestor-scope repair and the editor
fixes; `feat/converter-editor` had the grid search boxes (`29f6386`) and Examine
(`34992bd`). Deploying a build from either branch silently removed the other half.
Merged at `fe34e79`; all three overlapping source files auto-merged, suite 369 -> 376.

**Rule going forward: never deploy the editor from a feature branch.** Build from `main`
and confirm `main` contains the branch you were just working on.

## Item 2 -- already done, events included (do NOT rebuild this)

`ConvRules.Usage.pas` + the Examine button already mark used From rows green, from the
**union of .dfm and .pas** evidence. Events need no separate support: in Delphi an event
IS a published property whose type is a method pointer, so it is already a proptree leaf
(`cxButtons.TcxButton` published surface: 23 `On*` leaves, all `is_writable=True`).
`ScanDfmText` sees `OnClick = btnOKClick` as an ordinary DFM assignment, and
`ScanPasText` sees `.OnClick`. The Object Inspector's Properties/Events split is a UI
convention, not a language one.

Two real gaps, both small:
- **No test asserts event coverage.** Add an `On*` case to the DFM and PAS scanner
  fixtures so this stays true rather than being true by accident.
- **The green marking is FROM-side only.** Marking used **To** rows is not meaningful
  yet (nothing has been converted), but once `convert-apply` runs, the same scan over the
  OUTPUT would show which To properties the conversion actually produced.

## Item 3 -- Dark / Light modes (VCL Styles)

Delphi ships this: `Vcl.Themes.TStyleManager`. Styles are `.vsf` resources linked via
*Project > Options > Application > Appearance*; switching is
`TStyleManager.TrySetStyle('Windows11 Modern Dark')` at runtime, and `'Windows'` is the
un-styled default.

Design notes:
- The editor builds its entire UI in code (no .dfm), so there is no designer state to
  fight. A `Style` submenu enumerating `TStyleManager.StyleNames` is ~20 lines.
- **Persist the choice.** Everything else the editor remembers is process-lifetime only;
  a style needs to survive restart. Registry (`HKCU\Software\DragLint\ConvRulesEditor`)
  matches what the graph viewer already does for its HWND.
- **The load-bearing constraint is item 2's green highlight.** Examine marks rows with a
  light-green background. Under a dark style that green must be re-derived, not
  hard-coded, or it will be an unreadable white-on-pale block. Take the colour from
  `StyleServices.GetStyleColor`/`GetSystemColor` and blend, or keep two constants and
  select on `TStyleManager.ActiveStyle.IsSystemStyle`. Same applies to any custom
  `OnDrawCell` in the mapping grid.
- `TStringGrid` fixed cells and `TListBox` honour styles automatically; owner-drawn cells
  do NOT. Audit every `OnDrawCell`/`OnDrawItem` before calling this done.

## Item 5 -- jump to a type's definition in the IDE (TODO)

**Motivating case:** the From side shows `Style: TabcButtonStyle`. To choose the right
TcxButton target you must know what `TabcButtonStyle` *is* -- today that means leaving the
editor and searching by hand.

Every piece already exists; this is wiring, not invention:
1. **Resolve the type to a location.** `drag-lint query --name TabcButtonStyle --db <db>
   --json` returns file + line. The editor already shells out to `drag-lint` through
   `ConvRules.Engine`'s adapter, so this is one more verb on an existing boundary.
2. **Open it in the running IDE.** The named-pipe open-source contract already exists and
   is already used by the graph viewer -- see `docs/ipc-open-source-contract.md` and the
   plugin's `OpenSourceAt` (which forces the `.pas` code editor). The viewer also
   publishes its HWND to `HKCU\Software\DragLint` for discovery.
3. **UI.** Right-click a grid cell or pool row -> "Go to definition of `<Type>`". The type
   token is already parsed out of the cell by `TypeOfCell`, which item 4 just pinned with
   tests. **This is why item 4 matters beyond display: the To column now carries a type
   token for this feature to act on.**

Degrade honestly: if no IDE is listening, show the resolved `file:line` and offer to copy
it, rather than failing silently.

Worth doing at the same time: show the type's **enum members** inline when it resolves to
an enumeration -- that is exactly the information needed, and it feeds item 6 directly.

## Item 6 -- conditional enum -> property-value rules

**The problem.** Today a `#link` maps one From leaf to one To leaf through a cast. Real
conversions are not always shaped that way. Using the user's (deliberately invented)
example:

```pascal
type TButtonStyle = (stOK, stCancel, stHelp, stNormal);   // FROM: one enum property
// TO: several booleans, plus a ModalResult
```

The mapping is **one From property -> several To properties, selected by value**:

```
Style = stOK      ->  Default := True;  ModalResult := mrOk
Style = stCancel  ->  Cancel  := True;  ModalResult := mrCancel
Style = stHelp    ->  ...
Style = stNormal  ->  (nothing)
```

This is NOT the existing enum->enum conversion. Two things make it different: the target
is a **value**, not a property-to-property link; and there may be **several targets per
source value**. The To path may also be **nested** (`Style.ModalResult.Default := True`),
so the target is a path into an owned sub-object, not a top-level property.

### Proposed DSL

Keep it a superset of the current reFind-style syntax and keep one node per line:

```
#convert Abcbtn.TabcToggleBtn -> cxButtons.TcxButton
  #when Style = stOK      #set Default := True    #set ModalResult := mrOk
  #when Style = stCancel  #set Cancel  := True    #set ModalResult := mrCancel
  #else                   #set ModalResult := mrNone
```

Design constraints this must satisfy:
- **`#when` consumes the From leaf** the way `#link` does, so `Style` must count as
  assigned and leave the To pool consistent. Otherwise the editor will keep offering it.
- **Every `#set` target is validated against the real To property tree**: the path must
  exist, be `is_writable`, and the literal must be assignable to that leaf's type. This is
  the same gate `IsCastable` already applies -- extended from type->type to value->type.
  Enum literals validate against the target enum's members; `True`/`False` against
  `Boolean`.
- **Nested To paths already work** -- proptree emits `Colors.Button.Text` style paths and
  `PropCellText` renders them, so `#set A.B.C := V` needs no new path model.
- **Exhaustiveness is a warning, not an error.** If the From enum has four members and
  only three have a `#when`, say so; `stNormal -> nothing` is a legitimate choice.
- **`#else`** covers the unlisted remainder and keeps the common case short.
- `convert-apply` emits these as real assignments in the generated code; `convert-validate`
  must check them without needing the IDE.

### Editor UI

The grid's To cell for such a row cannot show a single target. Suggest rendering it as
`<conditional: 4 cases>` and opening a small editor: left column = the From enum's members
(fetched via item 5's enum-member lookup -- **these two features want to be built in that
order**), right column = the `#set` list per member, each row validated live against the To
tree. Auto-Match should leave conditional rows alone.

### Open questions for the spec proper

1. Can a `#when` condition test anything other than equality (ranges, `in [...]`)? Start
   with equality only.
2. Do conditions ever need to read TWO From properties? Not in any case seen so far --
   defer until one appears.
3. What happens when the From property is an enum the index cannot resolve? Probably the
   same "unknown type" path that `ResolveUnknownTypes` already handles, but it needs a
   decision.

## Also found this session

- **The grid search boxes have no automated tests.** `GridRowMatchesFilter` was
  deliberately made a pure, forward-declared free function *for* testability, and then no
  test was written. Cheap to add; would have caught the regression in item 1 far earlier
  than a human noticing an empty toolbar.
