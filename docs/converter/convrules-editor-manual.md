# ConvRules editor -- user manual

A task-oriented guide to `ConvRulesEditor.exe`, the visual editor for conversion rule
books. If you want the rule language itself -- every directive, its syntax and its limits
-- read [`convrules-dsl.md`](convrules-dsl.md). This document is about driving the tool.

---

## What the editor is for

You are converting a legacy Delphi component to a modern one -- an Orpheus or in-house
control to a DevExpress one, a BDE dataset to FireDAC. The mechanical part is deciding,
property by property, what becomes what. The editor puts the source type's real property
tree beside the target type's real property tree -- both read from the drag-lint index, so
they are the actual deep trees including inherited and nested members -- and lets you pair
them up.

The output is a **rule book**: a `.rules` text file the drag-lint engine can apply. The
editor never converts anything itself; it authors the plan.

## Where rule books live

Top-level `convrules\` in this repository:

| File | What it is |
|---|---|
| `convrules\sample.rules` | a small worked example (two `#convert` blocks) |
| `convrules\FireDAC_Migrate_BDE.rules` | Embarcadero's BDE -> FireDAC migration rules, imported verbatim |
| `convrules\FireDAC_Rename_Units.rules` | Embarcadero's unit-rename rules, imported verbatim (211 lines) |

The two imported files are product data, not test fixtures -- open them like any other
book. See [`refind-corpus.md`](refind-corpus.md) for where they came from.

## Opening one

Toolbar **Open...**. The dialog filter is `Conversion rules (*.rules;*.txt)`, so both our
`.rules` books and a raw reFind `.txt` instruction file are offered by default.

On load the status line reports what arrived:

```
Loaded 18 line(s), 2 rule(s). Select a rule to edit its mapping.
```

The first rule is auto-selected so the grid has content immediately.

---

## The main window

```
+-----------------------------------------------------------------------------+
| View                                                                        |  menu
+-----------------------------------------------------------------------------+
| Open... Save Validate Curate... | + New Conversion  Fill From-classes  ...   |  toolbar
+-----------------------------------------------------------------------------+
| status line                                                                 |
| From Unit: [v]                        Surface: [DFM (published props)  v]   |  pickers
| From: [v]  ->  To: [v]                FROM [Win32 v]   TO [Win64 v]         |
| C:\...\my.rules                                                             |
+---------------+-----------------------------------------+-------------------+
| Rules Library | Find in From: [   ] [Clear]  Find in To: |  To (unassigned   |
| Raw DSL       |-----------------------------------------|  pool) -- search:  |
| Unit Rules    | From property (: type) | To (assigned) | |  [            ]   |
|               |------------------------|---------------| |  [ list       ]   |
|  [ list ]     | Caption : string       | Text : string | |                   |
+---------------+-----------------------------------------+-------------------+
| Ready.                                                                      |  status bar
+-----------------------------------------------------------------------------+
```

**The rule list** (left, *Rules Library* tab) has three columns -- From, To and `%`, the
share of the block's source properties that have been decided. A filter box above it
narrows the list by From/To substring. Two more tabs sit beside it:

* **Raw DSL (all directives)** -- the whole book as text, in Consolas. This is where
  `#migrate` and raw PCRE lines are edited, since the grid cannot express them.
* **Unit Rules** -- `#use` / `#unuse` / `#useswap` directives, with columns
  Kind / Old / New(s) / Flag. A unit that is both added and removed is flagged
  `(!) ADD wins`.

**The property grid** (centre) is the working surface: one row per source property, three
columns -- `From property (: type)`, `To (assigned)` and `cast`. Both property columns
render as `Path : Type`, so a leaf's type is visible at the moment you assign it. Two
filter boxes above the grid narrow it by From and/or To substring (ANDed when both are
set), each with its own `Clear` button.

**The pool** (right) lists the To properties **not yet assigned**, with its own search box.
Assigning a leaf removes it from the pool; unassigning puts it back.

**The toolbar** is one strip in four groups, separated by dividers:

| Group | Buttons |
|---|---|
| file / working set | `Open...`, `Save`, `Validate`, `Curate...` |
| mapping | `+ New Conversion`, `Fill From-classes`, `Auto-Match`, `<- Assign`, `Unassign ->`, `Find in From`, `Only this type`, `Mappings...` |
| examine | `Examine...`, `Clear marks` |
| unit rules | `+ Swap`, `+ Add unit`, `+ Remove unit`, `Delete unit rule`, `Derive units`, `Check units` |

Buttons that act on a selection are **disabled until that selection exists**, rather than
being enabled and complaining when pressed. Every button carries a hint; hover for it.

**Two status lines.** The one under the toolbar carries the current message and turns red
for a blocked action; the bar at the bottom of the window repeats it, so a message is still
visible when the window is short.

---

## Creating a conversion

1. Pick the source class in **From:** and the target class in **To:**. Both combos filter
   as you type. The **FROM** and **TO** platform selectors decide which library index the
   pickers read (Win32, Win64 or Both).
2. Press **+ New Conversion**. The block is created, both property trees are fetched, and
   **Auto-Match** runs immediately:

   ```
   Conversion Vcl.StdCtrls.TEdit -> Vcl.StdCtrls.TMemo set and auto-matched. Review, then Save.
   ```

3. Review the grid and finish the rows Auto-Match left alone.

**Surface** decides which target properties are offered at all: *DFM (published props)* --
the DFM-streamable surface, the usual choice -- or *PAS (public props + fields)*. Read-only
leaves are never offered on either.

If you are starting from a form rather than from a class pair, pick the unit in
**From Unit:** and press **Fill From-classes**: every component class on that form is added
as a From-only conversion, and you then choose a To class for each one you actually want.

---

## Assigning and unassigning

Select a **From** row in the grid, highlight a **To** leaf in the pool, press
**`<- Assign`**. That writes a `#link ToPath <- FromPath` (plus a cast when one is needed):

```
Assigned Size <- Size : Round
```

**`Unassign ->`** removes the selected row's `#link` and returns the target to the pool.

Assign refuses, on the status line in red, when:

* the target is read-only -- *"Blocked: X is read-only -- not a valid assignment target."*
* no cast exists between the two types -- *"Blocked: cannot map A (T1) to B (T2) -- no
  known cast."*
* the source property is **already decided by an applied `#mapping`** -- *"Blocked: Style
  is already decided by an applied #mapping (4 case(s)). Edit that mapping instead..."*

**Auto-Match** creates every unambiguous, castable pairing: a source leaf whose name
matches exactly one unassigned target leaf, case-insensitively, and whose types can be
cast. Ambiguous names are left for you.

```
Auto-Match: 37 unambiguous assignment(s) created.
```

Two helpers for the awkward rows: **Find in From** selects the grid row whose property has
the same name as the highlighted pool leaf, and **Only this type** toggles the pool down to
leaves whose type matches the highlighted one.

### `<conditional: N cases>` in the To column

A source property with no `#link` may still be spoken for. When an applied `#mapping`
decides it, the To cell shows `<conditional: 4 cases>` instead of reading as unassigned --
N being one per `#when` clause on that property plus one for the mapping's `#else`.
Auto-Match skips such rows, and Assign blocks on them.

---

## Examine -- find out what a form actually uses

A real target class has hundreds of properties; a real form assigns a dozen. **Examine...**
tells you which dozen.

1. Select a conversion first (Examine marks the From properties of the **active** rule).
2. Press **Examine...** and pick one or more `.dfm` and/or `.pas` files -- multi-select is
   allowed. The editor only ever READS them.
3. Every source property those files actually assign or reference is marked with a green
   row background in the grid. The colour is derived from the active theme's window colour,
   so it stays readable in dark mode.

```
Examined 2 file(s): 14 of 117 From properties used; 22 unit(s) offered on the Unit Rules tab.
```

(the `14 of 117` is real: measured against `C:\Projects\DB\ORM3\CLIENT\SelectData.dfm` for a
`Vcl.StdCtrls.TEdit -> Vcl.StdCtrls.TMemo` rule.)

If the files use names that have no row in this grid, a report window lists them
(*"Examine -- used names with no grid row"*) -- usually a sign you picked the wrong From
class.

**Examine also harvests `uses` clauses.** The same `.pas` texts are scanned for their
interface and implementation `uses` clauses, and each unit named becomes a **candidate**
row at the bottom of the Unit Rules tab, marked `(candidate)` / `from Examine`.

Candidates are **candidates only**. Examine never creates, edits or deletes a rule; the
rule book is not touched. A candidate disappears from the list as soon as you author a
`#use`, `#unuse` or `#useswap` for that unit, and **Delete unit rule** dismisses a
candidate you do not want. Expect `System.*` and `Vcl.*` noise on a real form -- there is
no filter yet.

Two documented scanner limits, both pinned by tests: brace comments do not nest (the first
`}` closes, which is Delphi's own rule), and `$IFDEF` arms are not evaluated, so a
discarded arm still contributes its units.

**Clear marks** drops the current examination -- both the green marks and the harvested
candidates. The rule book is untouched either way.

---

## Authoring a conditional mapping

The case: `TabcToggleBtn.Style` is an enum, and each of its values means *several* target
properties take *particular* values on `TcxButton`. A `#link` cannot say that. A
`#mapping` can, and can be reused across every control in the family.

Worked example, end to end:

1. Select the `#convert` block you are working on and press **Mappings...**.
2. You are asked for a name -- an existing one, or a new name to create. Mappings already
   in the file are listed in the prompt. Type `XYZButtonStyle`.
3. The mapping window opens. Fill the three declaration boxes at the top:
   * **Source enum type** -- `XYZ.TXYZButtonStyle`. Qualify it if you can; a bare name is
     resolved but may tie (see below).
   * **From property** -- `Style`. This is the source property every `#when` reads.
   * **Target classes** -- comma-separated classes this mapping may be applied to. When
     you are creating a new mapping from inside a block, the block's To class is pre-filled
     as the only honest guess.
4. Press **Load members**. The editor resolves the enum through drag-lint and fills the
   left-hand list with one row per member, plus a final `(#else)` row. A row already
   mapped shows its assignment count, e.g. `stOK   (2)`.
5. Select a member and fill the `To path` / `Value` grid on the right. There is always one
   blank row past the last, so typing into it adds a target -- `+ Add target` is a
   convenience, not the only way in. `Remove` drops the selected target row.

   ```
   stOK       ->  Default = True,  ModalResult = mrOk
   stCancel   ->  Cancel  = True,  ModalResult = mrCancel
   (#else)    ->  ModalResult = mrNone
   ```

   Target paths may be multi-level: `Style.ModalResult.Default` is one path.
6. Watch the **issue strip** above the buttons. Each finding is one line, prefixed
   `ERROR` or `WARNING`, and the status bar totals them:

   ```
   ERROR    XYZButtonStyle: Defalt is not a property of TcxButton
   WARNING  XYZButtonStyle: stHelp has neither a #when nor an #else
   ```
   ```
   1 error(s), 1 warning(s).
   ```

   **Errors disable OK. Warnings do not** -- when only warnings remain the status bar says
   so explicitly: `0 error(s), 2 warning(s). Warnings do not block OK.` A warning means
   either that a member is uncovered (legitimate authoring intent) or that a `#when` value
   is not in the member list -- and that list may itself be wrong, so it is reported, never
   enforced. See [the DSL doc](convrules-dsl.md#validation-and-severities).

   One extra gate that is not an issue kind: **a source enum type is required**. Without it
   no declaration line can be written and every `#apply` naming the mapping would be
   undefined, so OK stays disabled and the status bar says
   `A source enum type is required before this mapping can be saved.`

   If the member list could not be trusted, the status bar appends why -- e.g.
   `Enum members NOT resolved: ...`, `3 declarations are named TAlignment; the member list
   came from one of them.`, or `The member list is the values already written here, not
   XYZ.TXYZButtonStyle's.` Do not read `No issues.` beside one of those notes as a clean
   bill of health.

   Editing the **Source enum type** box drops the member list on purpose (`Source enum type
   edited -- press "Load members" to check values against it.`), because checking new
   values against the previous enum's members produces confidently wrong verdicts.
7. Press **OK**. The mapping's lines are spliced into the book, and **an `#apply
   <Name>` is added to the current `#convert` block automatically** if it did not already
   have one -- a mapping nobody applies does nothing.

   ```
   Mapping "XYZButtonStyle": 4 line(s) written and #apply added to this conversion.
   ```

Pressing OK without having changed anything is treated as a no-op: the mapping is not
rewritten, so an untouched `#mapping` line keeps its byte-for-byte round-trip.

---

## Go to definition

Choosing a target for `Style : TabcButtonStyle` means knowing what that type IS.
**Right-click a grid cell or a pool row** whose text carries a type; the menu offers
*Go to definition of TabcButtonStyle*. When the cell has no type the menu does not appear
at all.

* **With RAD Studio running**, the editor asks the IDE to open the declaration over the
  named pipe `\\.\pipe\drag-lint-open-source` (served by the drag-lint IDE plugin):

  ```
  Opened in the IDE: TEditCharCase -- C:\...\System.UITypes.pas:70  (ecNormal, ecUpperCase, ecLowerCase)
  ```

  When the type is an enumeration its members ride along in parentheses -- usually the
  actual question being asked.

* **With no IDE listening** -- none running, or its plugin BPL not loaded -- nothing fails
  silently. The resolved location is copied to the clipboard and reported:

  ```
  No IDE is listening -- copied to the clipboard: TEditCharCase -- C:\...\System.UITypes.pas:70
  ```

### The honest caveats

* **Event and method-pointer types are not indexed at all.** `TNotifyEvent`, `TMouseEvent`
  and friends are a genuine gap in the index, not a lookup mistake, and the editor says so
  rather than jumping somewhere wrong:

  ```
  "TNotifyEvent" is not in the current index set. Method-pointer types (TNotifyEvent and
  friends) are among the declarations the index does not carry, and a type from an
  unindexed library will not be here either.
  ```

* **A bare name can tie.** `--name` is a substring match and several declarations
  routinely share one name -- `TAlignment` has three, `TColor` two, `TEdit` two (VCL and
  FireMonkey). The editor reports the tie instead of presenting one answer as the answer:

  ```
  2 declarations named TColor; opened Vcl.Graphics.  TColor -- C:\...\Vcl.Graphics.pas:37
  ```

  Since 2026-08-02 the pick **prefers the VCL declaration on a tie** -- among rows already
  tied on kind, non-FireMonkey beats `FMX.*`, top-level beats nested, and `System.*` then
  `Vcl.*` come before everything else. That makes the answer right far more often (measured:
  298 names stopped resolving to FireMonkey), but it does not make the tie go away, so the
  count is still reported. When it matters, type the qualified name.

* The lookup runs on the UI thread, so the window is briefly unresponsive; the wait cursor
  says so.

---

## Themes

**View > Theme** offers **Follow IDE** (the default), **Light** and **Dark**.

*Follow IDE* reads RAD Studio's own setting out of
`HKCU\Software\Embarcadero\BDS\<highest version>\Theme` and matches it; if that key is
absent or unreadable the editor falls back to Light. The choice is saved under
`HKCU\Software\DragLint\ConvRulesEditor` and survives a restart.

The grid is hand-painted, so its colours (including Examine's green marking) are derived
from the active style rather than hard-coded -- a marked row stays readable in dark mode,
and a selected cell paints the style's highlight colour rather than the green.

---

## Saving

Toolbar **Save**. Three things happen, in order:

1. **Backup.** The existing file is copied to `<name>.rules.bak`. If that name is taken the
   editor tries `.bak.2`, `.bak.3` ... up to `.bak.99`, so an earlier backup is never
   clobbered. **A failed backup aborts the save** -- nothing is written.
2. **Write.** The canonical DSL is written as ASCII with CRLF endings. Lines you did not
   edit are written back byte-for-byte.
3. **Validate.** `convert-validate` runs over what was just written and its first error, if
   any, lands on the status line:

   ```
   Saved my.rules (backup my.rules.bak). Validate: OK
   ```

   Unit conflicts (a unit both added and removed) are reported after every save as a
   separate note, `Note: unit conflicts (ADD wins): ...`.

### Two warnings worth reading before you trust a save

**A `#convert` block that maps nothing is DROPPED.** A block is kept only if its body
contains at least one `#link`, `#apply` or `#ignore`. A From/To pair you created but never
filled in is scratch and is not persisted; so is a block whose body is only `#mapping`,
`#default`, `#remove`, `#migrate`, `#note` or comments. The only notice you get is a count:

```
Saved my.rules (backup my.rules.bak) (1 empty rule(s) not saved). Validate: OK
```

**A book containing `#mapping` / `#apply` will fail the post-save validate.** The engine's
parser does not know those two directives yet (deferred by design -- see G6.1), so it
reports them as unknown:

```
Saved my.rules (backup my.rules.bak). Validate: line 1: unknown directive: #mapping
```

The file on disk is correct and complete. The message is the engine saying it has not
caught up, not a problem with your rule book.

**Curate...** opens the block-level curation window, which works on the file **on disk** --
so it offers to save first. Answering No curates the on-disk version and discards nothing;
answering Yes and having the save fail stops the whole operation rather than curating a
stale file.

---

## Troubleshooting

**"X is not in the current index set" for a type you know exists.**
Most often the index is stale rather than wrong -- the type was added or moved after the
index was last built. Reindex the relevant tree and try again. **Do not trust the
`skipped N up-to-date` line**: during development `drag-lint index` reported a file as
up-to-date that it had not in fact indexed, and only touching the file forced a reparse.
After any reindex, verify by querying a symbol you *know* is there before concluding the
symbol does not exist.

**A "go to definition" opened the wrong unit.** Read the status line: if it starts
`N declarations named ...` you hit a tie, and the editor is telling you which one it chose.
Type the qualified name into the box or cell you are working from.

**"Load members" produced an empty or suspicious list.** Check the note appended to the
mapping window's status bar. An unresolvable or ambiguous enum turns the bad-literal and
exhaustiveness checks OFF -- `No issues.` beside such a note means "nothing was checked",
not "everything is fine".

**The green Examine marks look wrong.** Two documented behaviours that are not bugs: a leaf
matches when its **full path or its last segment** equals a used name, so `Margins.Left` is
marked alongside `Left`; and a conversion whose From class is a sub-object type (`TFont`,
say) marks nothing on any real form, because Examine matches DFM blocks by CLASS and
`TFont` is never a DFM component.

**The editor and `drag-lint.exe` must be deployed as a PAIR.** The editor passes
`--refs-as-leaves`, which an older engine treats as fatal. Shipping the editor alone is
worse than the bug it fixes.

---

## See also

* [`convrules-dsl.md`](convrules-dsl.md) -- the rule language: every directive, `#mapping`
  in depth, validation severities, known limits.
* [`refind-corpus.md`](refind-corpus.md) -- the imported Embarcadero rule books.
* [`..\CONVERSION-RULES.md`](../CONVERSION-RULES.md) -- the engine verbs that consume a
  rule book, and what applying one does on disk.
* [`BACKLOG-editor-features.md`](BACKLOG-editor-features.md) -- what is still open.
