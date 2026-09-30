# convrules-editor -- converter stream instructions

## THE ENGINE UNDER THIS EDITOR IS PINNED. CHECK IT BEFORE YOU WORK.

The rule editor shells out to `drag-lint.exe` for six verbs (`proptree`,
`query descendants`, `query find`, `query --name`, `convert-scaffold`,
`convert-validate` -- all in `ConvRules.Engine.pas`). The **engine stream builds
that exe from the same working tree we develop in.**

On 2026-09-14 the deployed engine was rebuilt at **12:55 and again at 14:02
during one converter session**. Verification done at 12:55 was, by 14:02, a
statement about bytes that no longer existed at that path. Nothing announced it;
the file simply changed.

So: **the editor runs against a pinned snapshot, and the first thing any session
here does is check whether that pin has fallen behind.**

### Run this at session start, and again before any GUI or engine-touching work

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\check-engine-drift.ps1
```

| exit | meaning | what to do |
|---|---|---|
| 0 | pin matches the deployed engine, no new INBOX notes | carry on |
| 1 | **action needed** -- engine drifted, or new/open notes addressed to us | read the listed notes, then decide whether to re-pin |
| 2 | **cannot answer** -- pin or engine missing/unreadable | fix that first; never read a 2 as "fine" |

**Match on the exit code, not on the text.** Exit 2 exists precisely so a
misconfigured check cannot pass silently.

The script is read-only and keeps no "last checked" state, so running it can
never itself become the thing that drifts. Its baseline is always the pin's own
manifest.

### >>> THE TRAP: the version STRING is not a drift signal

Both the 12:55 and the 14:02 builds reported `drag-lint 1.11.0-alpha`. Only the
SHA256 and the build timestamp moved. **Never conclude "same engine" from a
matching version.** The check compares bytes for this reason; so should you.

### Where the pin lives, and how the editor finds it

`third_party\engine-pinned\<version>-<yyyyMMdd-HHmmss>\`, holding
`drag-lint.exe`, its tree-sitter DLLs, `drag-lint.json`, the full `rules\` tree
(111 files) and `ENGINE-PIN.json` -- the manifest recording version, build stamp,
SHA256 and what was verified at pin time.

`ConvRulesEditor.exe` is copied in beside it, and
`ResolveDragLintExe` (`ConvRulesEditor.dpr:48-50`) prefers a `drag-lint.exe`
sitting next to `ParamStr(0)`. **Launch the editor FROM the pin directory and it
uses the pinned engine with no code change.** Launch it from anywhere else and it
falls through to `third_party\dll-win64\` -- the live, rebuilt-without-warning
one.

The snapshot is gitignored (`third_party/engine-pinned/`); the rule and the check
that govern it are tracked. `*.exe` alone was not enough -- it would have hidden
the binaries and still committed 111 rule files.

### Re-pinning

Copy the `dll-win64` tree to a new `<version>-<stamp>\` folder, write a fresh
`ENGINE-PIN.json`, and **verify the new pin RUNS before trusting it**: `info`
must report the *pinned* paths for its tree-sitter DLLs, `rules` must report a
non-zero count, and one real query must answer. A pin that exists but cannot
answer is worse than no pin -- it is an authoritative-looking baseline for an
engine that was never checked.

Re-pin when the engine change is *settled*, not mid-sweep. A pin taken halfway
through a breaking change buys nothing.

## Standing state with the engine stream (as of 2026-09-14)

* **`resolved_defaults` HAS SHIPPED (corrected 2026-09-16).** This entry said it
  "was never built (zero occurrences in `src\`)" and told the next session not to
  start anything consuming `convert-apply` findings until it landed. It landed as
  `7f5ce20`: a real run on VARINSP prints `ResolvedDefaults: 8 property value(s)
  carried from their declared defaults (--format json lists each)`. The advice was
  correct when written and became a brake on work that was already unblocked.

* **`convert-apply` needs the unit to be INDEXED, and says something else when it
  is not (2026-09-16).** It reports `could not locate .dfm object block for "<x>:
  <Type>"` -- an assertion about the .dfm's content that is FALSE. Measured: a
  261-byte fixture with the block at depth 1 fails; index that folder and the
  identical run converts. VARINSP produced 20 of these and converted 0 of 20;
  indexed into its own DB it converts **20 of 20, 60 edits**. Do not go looking in
  the .dfm -- check the `--db` set first. Filed as
  `docs\INBOX-2026-09-16-converter-to-engine-dfm-block-needs-indexed-unit.md`.

* **The class cast is still not realized, and the .dfm half DROPS the image.**
  `#link OptionsImage.Glyph <- Picture : AssignGraphic` is skipped on the `.pas`
  side, and the re-emit reports `dropped Picture.Data` -- so twenty buttons lose
  their glyphs silently. `--castlib` executes **enum blocks only** (its own help
  says so); `TCastDef.PasTemplate` is parsed at
  `src\report\DRagLint.Convert.CastLib.pas:375` and read nowhere in `src\`. This
  is engine item 6, `realize-class-casts`, 3-5 d, planned in
  `PLAN-SESSION-95-OPEN-NOTES.md`. It is the ONLY remaining gap in the
  conversion; everything else lands.
* **The `--db` strictness sweep has LANDED, and the "costs us nothing" reading of
  it was WRONG (corrected 2026-09-15).** The claim recorded here was that our DB
  set is three hardcoded paths that all exist, so strictness could not touch us.
  That measured EXISTENCE. The strictness is about **SCHEMA**: a read verb now
  refuses an index at an older schema, and on 2026-09-15 the ORM3
  `Micronite2027.sqlite` sat at v21 against an engine wanting v22.

  It cost 12 test failures (`picker.*`, `platform.rescope.*`, `proptree.bareclass.*`)
  and would have blocked a GUI session at the first class pick. **A stale DB is a
  file that exists perfectly.**

  Two properties worth knowing before you debug this shape again:

  * **One stale `--db` fails the WHOLE query.** The error is `exit 2` with
    "Nothing was answered", even though the other DBs in the list are healthy and
    could answer. So a single stale index takes down every editor query, and the
    message names the stale DB -- read it, do not assume the engine broke.
  * **The migration is nearly free when the sources have not changed.** The fix
    was `index --project Micronite2027.dproj --db <db>`: **2.0 s, 624 files, all
    624 "up-to-date"** -- a schema migration, NOT a re-parse. Do not budget hours
    for this or route around it; just run it.

  `DbArgsFor` (`ConvRules.Engine.pas:544`) filtering empty entries is still true
  and still irrelevant to this. Note also that `--project-db ''` does NOT disable
  the project DB: `ConvRulesEditor.dpr:205-206` re-defaults an empty value to the
  hardcoded `ProjectDb`.
* **The stdout -> stderr move for engine errors is a non-event here.**
  `RunCapture` sets `SI.hStdError := WritePipe` (`ConvRules.Engine.pas:580`) --
  both streams already land in one pipe, and we gate on the exit code.
* **`query descendants` exit-1-on-success is fixed** in the pinned engine
  (verified: 6,324 names -> exit 0; unknown ancestor -> exit 1). The `Code = 2`
  workaround at `ConvRules.Engine.pas:756` stays *correct* either way; removing
  it is optional cleanup, not a fix.

## Replying to the engine stream

Notes arrive as `docs\INBOX-*engine-to-converter*.md`; ours go back as
`docs\INBOX-REPLY-*.md`. The drift check lists both, newest first. **Re-verify an
inherited claim against the tree before repeating it** -- the 2026-09-14 ledger
found five items that read as open in the correspondence and were already done,
and one that read as answered and was not.

## Left lists (class picker) -- hand-over notes (Task 13, 2026-09-20)

Line numbers below are deliberately omitted (this unit moved ~600 lines in
ONE DAY during this branch, and a cited `:NNNN` is wrong by the next session)
-- resolve a routine name with `drag-lint outline --file <U.pas> --db <db>` or
get its full context with `drag-lint context --task "modify <Unit.Routine>"
--db <db>`.

* **Skip file location:** `<rules folder>\convrules-editor-skip.txt`, beside the
  `.rules` book(s) -- shared via source control, not per-user. Format is plain
  text, one `skip <ClassName>` line per marked class (`SkipFilePath`,
  `ConvRules.SkipList.pas`).
* **The class-picker's own index is PER-UNIT and PERSISTENT**, under
  `%LOCALAPPDATA%\DragLint\ConvRulesEditor\scratch\<stem>-<hash>.sqlite` --
  ONE database per unit, keyed on the upper-cased full path, so two units
  sharing a stem cannot collide. This is only used by the `OutlineClasses`
  path (the From-Unit "Browse..." button next to `FCbUnit`, wired to
  `DoBrowseFromUnit` -> `HarvestUnitFile` -> `HarvestUnitClasses`, which calls
  `FEngine.OutlineClasses` and merges the result into `FFormTypeRows` via
  `MergeClassRows`). **It is NOT used by "Open form..." / `HarvestFormTypes`**,
  which parses `.dfm` text only (`ScanDfmTypes`/`MergeFormTypes`) and never
  touches the engine or any index -- that is why opening a form is always fast
  regardless of cold/warm state, and why a `dfm`-only unit's checklist never
  shows a `pas`-origin row unless the unit was ALSO picked via "Browse...".
* **Cold-pick cost, measured 2026-09-20:** a small unindexed unit (7 lines, 1
  class) costs **0.55 s**; VARINSP.PAS (4,000+ lines, 3,946 symbols) costs
  **27.7 s** (the `calls` resolve pass is 16.5 s of that; nothing skips it).
  Warm re-index of either, unchanged file, is **0.09-0.13 s**. The 27.7 s
  figure is the worst case on this corpus, not the typical one -- quote both
  numbers or the feature reads as slow when the common case is half a second.
* **The three-column layout is an owner ruling, 2026-09-20 (spec R4.1a):** the
  class panel (`TabClasses`, `FormTypesPanel` and everything parented to it)
  is the DEFAULT `Classes` tab of `FTabs`, the leftmost page control's own
  first tab -- not a fourth column beside it. The form went from four columns
  to three the same day the old `FormTypesPanel`/`SplitForms` column was
  retired; the accepted cost is that the checklist is hidden while `Raw DSL`
  or `Unit Rules` is the active tab.
* **Skip marks are re-applied on EVERY row rebuild, `HarvestFormTypes`
  included** (`ApplySkipMarks` runs after every `MergeFormTypes`/
  `MergeClassRows` call that replaces `FFormTypeRows`). Task 9 filed this as a
  Critical when the "Open form..." button path was the one omitting it --
  every rebuild site needs the same call or a re-Examine silently erases
  marks the skip file still has, and the next `SaveSkipList` then persists the
  erasure.
* **`ApplySkipMarks` stamps memory only; `SaveSkipList` writes every row.**
  The two are not symmetric -- `ApplySkipMarks` sets `FFormTypeRows[i].Skipped`
  from `FSkipList` in memory and touches no file; only `SaveSkipList` (called
  from every toggle site: `ToggleFormTypeSkip`, `FormTypeCheckClick`,
  `ApplyNamedFilterClick`) writes the skip file, and it writes the FULL current
  row set, which is what makes un-marking a class persist (a naive
  additive-only writer would leak a stale `skip` line forever).
* **`ConvRules.MainForm.pas` is OUTSIDE the tests project's compile closure.**
  `ConvRulesModelTests.dpr` links the pure model/engine units directly; it does
  not, and cannot, pull in the VCL form unit. Decision logic that needs a test
  belongs in `ConvRules.FormTypes.pas` / `ConvRules.RuleCatalog.pas` /
  `ConvRules.SkipList.pas`, not in `MainForm.pas` -- and the tests build can
  NEVER detect a `MainForm.pas` compile break on its own. Always build
  `_build_convrules_editor_local.bat` too, not just the tests.
* **A double-click on an ALREADY-SELECTED rule row forces the grid load
  directly.** VCL does not re-fire `OnSelectItem`/`LBN_SELCHANGE` when the
  selection does not change, so `FormTypeDblClick` cannot rely on the
  single-click handler having just run for that row -- it loads the grid
  itself rather than assuming `FormTypeClick` already did.
* **A per-task "touched hunks" lint gate has a real blind spot: a line whose
  TEXT is unchanged can still be swept into a LATER task's diff** when
  surrounding lines are inserted/deleted around it (git attributes the whole
  replaced region to the new commit even where content did not change). Task
  13 found 13 `--enable`'d findings on `MainForm.pas` branch-authored lines
  that no single task's own per-task lint run had reported: 9 on the `BtnSkip`
  creation line (last rewritten by the "several rules... warn" task, whose own
  commit was ABOUT splitting statements onto one per line and still missed
  this one) and 4 on the `LeftPanel`/`FTabs` creation lines (swept into the
  "retire the placeholder Rules Library tab" task's replaced region). Only the
  WHOLE-BRANCH diff (`cfe19ec9..HEAD`) caught them -- run that, not just the
  latest commit's own diff, before calling a branch lint-clean.

### Pre-existing oddities noticed in passing (not fixed -- for the owner)

* `HeaderIndexFor`/`LoadFile` emits a stale-index message with a BLANK
  filename on a cross-book reopen.
* `BlockPercent` (`ConvRules.MainForm.pas`) is dead code since the `%` column
  became `File` -- `H2219 Private symbol 'BlockPercent' declared but never
  used` on every build.
* The `{ "Fill From-classes": ... }` hand comment block directly above
  `HarvestUnitFile` describes an unrelated feature -- stale prose, not stale
  facts (autodoc does not touch hand-written comments).
* `HarvestFormTypes`'s own hand comment still says "manual re-enable/override"
  language that predates the current skip-mark carry-forward design.
* `FormTypeDrawItem`'s 4px text inset is a literal written THREE separate
  times -- the `TextOut` call, then the strikethrough's `MoveTo` and `LineTo`
  -- each with its own `dl:ok magic-literal` review instead of one named
  constant.

## Unit picker -- hand-over notes (feat/unit-picker, 2026-09-24)

Every place the editor asks for a unit name opens `TUnitPickerForm`
(`ConvRules.UnitPicker.pas`): **Uses Units > Add unit... / Remove unit /
Swap...** (toolbar buttons `+ Add unit` / `+ Remove unit` / `+ Swap` until 2026-09-29)
and the From Unit **Pick...** button. Its decisions live in
`ConvRules.UnitPick.pas`, which the model tests cover; the form only renders.

* **Swap is row-driven, and the replacement picker is multi-pick (2026-09-29).**
  The ROW is the Old unit: a right-click on a unit-list row (`FUnitPopup`:
  Swap <Old> with... / Accept scope rename / Remove unit / Add unit / Delete)
  or **Uses Units > Swap...** with exactly one row selected opens ONLY the
  replacement picker (`TUnitPickerForm.ExecuteMulti`, caption
  `Replacements for <Old>`). There a double-click, Enter or Space ADDS the unit
  to a Replacements list with no confirmation; OK finishes; a chosen entry is
  removed by double-click or Delete. The Old picker opens only when no row is
  selected. `SwapUnit` MERGES into an existing `#useswap` for the same Old.
  `AddPickedUnit` refuses blanks, repeats (any case) and the Old unit itself.
* **Why (the defect it fixed):** every rule change rebuilds the list
  (`Items.Clear`), dropping the selection, so the second **+ Swap** opened the
  Old picker EMPTY -- indistinguishable from a replacement picker -- and the
  replacement picked there became an Old unit. Guard:
  `tests\gui\drive-unit-rules-toolbar.ps1` sections 4b/4c (the driver has 41
  checks since the menu bar replaced the toolbar; the file name is historical).
* **`IfThen` evaluates BOTH arguments.** `IfThen(Row <> nil, Format(..,
  [Row.SubItems[1]]), '')` is an access violation on a nil row -- the popup
  crashed on a right-click over empty space until it became if/else. The
  `ifthen-both-branches` lint rule flags every such call; take it seriously.
* **`#unuse` from selected rows no longer asks** (owner ruling 2026-09-29): a
  rule row is undone by Delete. Delete of more than one row still asks.

* **The lists come from `sql`, not `query find`.** `query find --no-docs` is a
  FILTER (undocumented symbols only) -- the From Unit combo used it and listed
  2,103 of library-Win64's 5,646 units. `TEngineAdapter.ListUnits` now runs one
  `sql ... WHERE kind='unit'` per DB with `--limit` (the `sql` default cap is
  200). Engine ask filed: `docs\INBOX-2026-09-24-converter-to-engine-list-units-and-object-leak.md`.
* **Cost, measured 2026-09-24:** ~5.5 s per library DB, ~0.9 s for the project
  DB, once per session (cached in `FPick*`); a reopen measured 0.4 s.
* **Side -> platform:** a To unit (#use, a swap's New) lists the TO platform's
  library, a From unit (#unuse, a swap's Old, From Unit) the FROM one. On
  `Both` a unit present in only one library gets a note under the lists.
* **The platform dropdowns now write `GEditorFromPlatform` /
  `GEditorToPlatform`** -- those globals are the session's TO/FROM platform,
  not just the command-line defaults.
* **Setting a conversion adds its unit rules** (`AddDerivedUnitRules`):
  `#unuse <From type's unit>` + `#use <To type's unit>`, skipping any the book
  already says (`MissingUnitNodes`). They are atomic; deciding whether a unit
  is still needed, already present or must move to the interface is the
  ENGINE's job at apply time -- not built yet (next spec).
* **Unit inserts shift every `#convert` index.** `InsertUnitNode` re-derives
  `FActiveHdr`; any other index a caller holds must be re-found by NODE (see the
  set-conversion path).
* **Driving it (rewritten 2026-09-29 -- the toolbar is GONE):** every command
  is a main-menu item, invoked by PATH: `[W]::InvokeMenu($main, 'Uses
  Units|Swap...')` in the drivers' shared `W` block. `GetMenu(main)` returns 0
  on this form -- the always-on VCL style detaches the native menu and paints
  its own bar -- so the drivers ask the form for its HMENU with the registered
  message `MAIN_MENU_QUERY_MSG` (`'ConvRulesEditor.MainMenuHandle'`) and post
  `WM_COMMAND` with the item's id. Details in the menu-bar section below.
  Raw DSL's memo has no window until its tab has been shown.

## Unit Rules harvest -- hand-over notes (feat/unit-harvest, 2026-09-28)

The Unit Rules tab lists the units a SOURCE uses (pasted or dropped text,
`.pas` / `.dpr` / `.dproj` files) and classifies each against a DESTINATION
`.dproj`, so a unit the destination cannot resolve shows as MISSING before
anything is converted. Spec and plan (gitignored, main tree):
`docs\superpowers\specs\2026-09-28-unit-rules-harvest-and-missing-design.md`,
`docs\superpowers\plans\2026-09-28-unit-rules-harvest-and-missing.md`.

* **Three pure units own the logic; the tests cover all three.**
  `ConvRules.UsesHarvest` -- text / `.dpr` / `.dproj` parsing, `HarvestFiles`,
  the merge. `ConvRules.UnitStatus` -- `TDestinationResolver`, which classifies
  a unit against the destination. `ConvRules.UnitMask` -- the session masks and
  the display order. `ConvRules.DropTarget` is Windows glue only.
* **The resolver is `TDestinationResolver`, NOT `TUnitResolver`.**
  `ConvRules.Units` already declares an unrelated `TUnitResolver` (a
  reference-to-function type for `DeriveUnits`); the two compiled side by side
  only by uses order. Do not "restore" the plan's name.
* **A destination MEMBER is a `.dpr` entry WITH an `in` path.** A plain entry
  (`Vcl.Forms`) is not a member; it resolves through the file / library / scope
  steps like any other name. Counting it as a member reported library units as
  `project` and defeated the hide-library mask.
* **`MainForm` is wiring only.** Every decision a test can check lives in the
  three pure units; `MainForm.pas` is outside the tests' compile closure (see
  above), so build the editor too.
* **Harvested rows are `Data = nil` with Kind `(used)`** (Examine candidates are
  `(candidate)`, also `Data = nil`). They are session state, never written to
  the book. A harvested name that is also an Examine candidate shows ONCE, as
  the harvested row -- it carries the status and used-by that a candidate row
  lacks -- but only while that harvested row is actually LISTED (rulings R7,
  R16): `RefreshUnitList` computes the shown rows once, first, and a candidate
  yields only to a name in that set (`IndexOfRow`). A harvested twin the check
  boxes or masks hide does not hide the candidate.
* **Which harvested rows are listed is pure: `ConvRules.UnitMask.FilterHarvestRows`**
  (rows, Find missing, Include unqualified, a has-rule predicate, the mask) ->
  `THarvestView` = the shown rows in display order + `Masked` + `Filtered`.
  Every row lands in exactly one bucket (shown + masked + filtered = total; the
  tests pin it). A row the check boxes drop or a rule covers is `Filtered` even
  when a mask would also hide it. `MainForm` only renders the result and the
  `N listed, M masked, F filtered` label.
* **Delete acts on every selected row** (MultiSelect is on): a rule row deletes
  its node, a `(used)` / `(candidate)` row is dismissed from its own session
  set. More than one row asks first.
* **Nothing about the destination is cached between classifies (ruling R13).**
  `EnsureResolver` frees and rebuilds `TDestinationResolver` on EVERY classify:
  it re-reads the `.dproj` and its `.dpr`, and the new resolver lists each
  folder at most once, for that classify only. A session-long cache (the old
  `<DPROJ>|<platform>` key) kept reporting MISSING after the owner copied the
  unit into the destination. Only the library unit list is cached, by
  `EnsurePickLists` -- the engine query is the expensive part; a failed load is
  not cached and is retried. Classifies happen only on user actions: a harvest,
  a destination commit, a platform change, dismissing harvested rows. A check
  box or mask change NEVER reclassifies; it re-filters (`RefreshUnitList`).
  `cpBoth` classifies as Win64 and says so in the status line.
* **The Destination row shows `Platform: Win64` / `Win32` / `Both -> Win64`**
  (`DestPlatformLabel`, ruling R17), set at build and by `PlatformChanged`. The
  TO platform box is the only control; the label is read-only.
* **Enter in the Destination edit commits it** (`DestKeyPress`, ruling R18),
  exactly like leaving the edit; the key is swallowed so the edit does not beep.
* **Pasted text without the word `uses` is a LIST** (`HarvestText`): comments
  (`{..}`, `(*..*)`, `//..`) and quoted strings are removed first, the reserved
  word `in` is dropped, then it splits on `,` `;` and whitespace. So a `.dpr`
  uses-clause selection (`U1 in 'U1.pas' {Form1}, // old DM`) yields only the
  unit names. It is deliberately NOT read as `'uses ' + text + ';'` through the
  scanner (ruling R14's first proposal): the scanner stops at the first `;` and
  keeps one name per comma entry, which measurably dropped `DB, Data.DB` from
  `Forms, Vcl.Dialogs; DB` + newline + `Data.DB` and would collapse a
  one-name-per-line list to its first name. Known limit: a selection that runs
  PAST the clause's `;` into code (`begin`, `Application.Run`) lists those
  identifiers too. Prose containing the word `uses` is still read as source.
* **`.dproj` reading is deliberately narrow:** only the `'$(Base)'!=''` and
  `'$(Base_<P>)'!=''` property groups are read; a search-path entry holding a
  macro (`$(Platform)`, `$(Config)`, ...) is skipped and COUNTED in the status
  line, never guessed at.
* **Degraded classification goes red.** Destination unreadable, library list
  unavailable (MISSING is then over-reported) or classification stopped part
  way sets `FDestWarn`, and the harvest status line goes out through
  `SetError`, not `SetStatus`. The informational notes (macros skipped, TO =
  Both) stay on `SetStatus`. Exceptions from the `.dproj`/`.dpr` read and the
  classify loop are caught and reported -- a bad project must not crash a drop.
* **The strip's height is `HarvestRowResize`'s job, not `TPanel.AutoSize`.**
  Each flow row AutoSizes to its wrapped content; the strip's height is set to
  the sum of the rows on each row's `OnResize`. `AutoSize` on the strip itself
  measurably did not re-run after the rows wrapped, and the list covered the
  folder edit.
* **The OLE drop target is on the FORM**, registered in `CreateWnd` (a VCL
  style switch recreates the handle) and revoked in `DestroyWindowHandle`, NOT
  `DestroyWnd` -- `TWinControl.Destroy` calls `DestroyWindowHandle` directly,
  so a `DestroyWnd` revoke is skipped at form destruction.
* **A drop hands its payload on with `TThread.ForceQueue`,** after `Drop`
  returns, so Explorer's drag loop is never held while the editor reads files
  or queries the engine.
* **Paste catches `EClipboardException` only**, around the clipboard READ, and
  reports "another program has the clipboard open" through `SetError`. A driven
  run hung on the old modal "Cannot open clipboard: Access is denied".
* **GUI check: `tests\gui\drive-unit-harvest.ps1 -Exe <ConvRulesEditor.exe>`**
  (a frozen `drag-lint.exe` beside the exe whose Win64 library index answers).
  It needs NO real project: it writes a FIXTURE in a fresh temp folder --
  `dest\Dest.dproj` (the IDE's Base / Base_Win64 group shape, `Vcl` a Win64
  scope name), `dest\Dest.dpr` with one member `Local in 'Local.pas'`, and a
  source `source\Src.pas` using `Local, Forms, NoSuchUnitXyz, FileOnlyXyz` --
  and deletes it on exit. It sets the Destination edit (WM_SETTEXT) and commits
  it with Enter (WM_CHAR), then asserts EXACT statuses: NoSuchUnitXyz
  `MISSING`, Forms `via scope -> Vcl.Forms`, Local not listed with Find missing
  on. Also: a CF_HDROP file-list paste (FileOnlyXyz comes only from Src.pas), a
  held clipboard (any editor dialog = FAIL), and the R13 case -- `uses
  LateUnit;` is MISSING, LateUnit.pas is written into the fixture destination,
  the same paste then reads `project`. `-ProofNoDestination` leaves the
  Destination edit empty: the status assertions then FAIL, which is the proof
  the check can fail. RED on the pre-feature build (no Paste button). It is NOT
  wired into the `tests\autotest` battery -- run it by hand, like
  `drive-unit-picker.ps1`. Explorer drag-drop itself, a real Ctrl+V keypress
  and the visual checks (bold MISSING, the platform label, wrapped strip at
  other widths) are owner checks.

## Menu bar + Convert tab -- hand-over notes (feat/convert-tab, 2026-09-29)

The toolbar became a main menu (File / Conversion / Mapping / Uses Units /
View), File gained New / Save As / Exit behind one unsaved-changes guard, and a
**Convert** tab applies checked rule books to a list of source units IN PLACE,
with a numbered backup per unit. Plan and spec (gitignored, main tree):
`docs\superpowers\plans\2026-09-29-menu-bar-and-convert-tab.md`; ledger and
per-task reports: `.superpowers\sdd\2026-09-29-menu-bar-and-convert-tab\` in the
`convert-tab` worktree.

### Menu bar

* **The toolbar is gone; every command is a menu item** built by `BuildMenu`
  through `AddMenuCmd(AParent, ACaption, AHint, AHandler, AShortCut)`.
  `UpdateToolbarEnabled` is now `UpdateMenuEnabled`; `Only this type` is a
  `Checked` toggle, not a caption change. Menu hints go to the status line
  (`WM_ENTERMENULOOP` / `AppHint` / `WM_EXITMENULOOP` restores it) -- not
  covered by any driver; an owner check.
* **Shortcuts are Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+Shift+S -- nothing else, and
  never a bare key** (Delete, Enter, a letter): a main-menu shortcut fires
  inside the Raw DSL memo and every edit control.
* **`GetMenu(main)` returns 0 on this form.** The always-on VCL style
  (`TFormStyleHook`) detaches the native menu and paints its own bar. The form
  answers the registered window message `MAIN_MENU_QUERY_MSG`
  (`'ConvRulesEditor.MainMenuHandle'`) with `Menu.Handle`, from its `WndProc`
  override; every other message goes to `inherited`. This exists for the GUI
  drivers (owner-accepted automation hook, ledger Task 2). Drivers invoke by
  PATH -- `[W]::InvokeMenu($main, 'File|Save As...')`, `[W]::MenuCaptions` to
  list -- never by toolbar rectangle; the `W` block is copied between drivers.
* **Status text is readable only from the `TStatusBar`.** `FLblStatus` is a
  `TLabel` (no window); `SetStatus` / `SetError` mirror to the status bar, with
  a `[!] ` prefix on errors. Assert on the status bar.

### File > New / Save As / Exit and the unsaved-changes guard

* **Unsaved = `FBook.Snapshot <> FSnapshot`** (`TRuleBook.Snapshot` is the
  canonical re-emit, so a non-canonical file does not load dirty, and an
  incomplete `#convert` block never makes a book dirty). `FSnapshot` is taken
  at `LoadText` (every open / New / Curate reload) and in `SaveBook` once the
  bytes reached disk.
* **`ConfirmDiscard` is the one guard** -- New, Open, Exit, the window X
  (`FormCloseQueryHandler`), the Convert tab's open-book check
  (`ConfirmOpenBookSaved`) and a cross-book double-click in the Classes list
  (`OpenOwningRuleEntry`, which is an Open under the spec). `DoCurate` keeps
  its OWN save-first prompt (keyed on `FBook.Nodes.Count > 0`) -- a second,
  coarser notion of unsaved, deliberately not unified yet.
* **Exit's handler is `DoExitClick`, not `DoExit`** -- `TWinControl.DoExit` is
  a dynamic method and a same-named handler hides it (W1010).
* **`SaveBook(APromptPath)` restores the old path and title ONLY when no bytes
  were written** (`LBytesWritten`). Once `TFile.WriteAllText` succeeded, the new
  path is kept and `FSnapshot` refreshed even if validate / rescan then raise.
  A cancelled Save As exits before anything changes (`saveas.cancel.keeps.path`).
  The written-then-raised path has no automated test (needs fault injection;
  MainForm is outside the model tests' closure).

### Convert tab

* **Three layers.** Pure decisions in `ConvRules.ConvertRun` (model-tested:
  `SharedBackupPaths`, `BookKindOfText`, `MoveEntry`,
  `ExpandSources`, `Preflight`, `ParseApplyJson`, `UnitInIndex`, `SourceRowText`);
  execution in
  `ConvRules.ConvertRunner` (`RunConversion` / `RunConversionUnits`); UI in
  `ConvRules.ConvertTab` (`TConvertTab`, a code-built `TPanel`, editor-only --
  not in the tests' closure). `Conversion > Convert...` shows the tab.
* **Backups:** full file name + `.BCK<N>`, ONE N per unit shared by its `.pas`
  and `.dfm` (`SharedBackupPaths`): one above the highest existing N over BOTH
  `X.pas.BCK*` and `X.dfm.BCK*`, so `X.pas.BCK1` + `X.dfm.BCK3` give both
  `.BCK4` (gaps are not reused; the probe window is 50). `TConvertRow` carries
  `Backup` and `BackupDfm`; the grid has a `Backup .dfm` column, and the report
  and every Note that names a backup (`rolled back`, `FAILED -- NOT restored`)
  name both. A unit that no VALID book touched keeps no `.BCK`.
* **Cancel is honoured between UNITS only**, never between two books of one
  unit. A unit listed twice (file + `.dproj`, any case) is converted once
  (`ExpandSources` dedupes). A listed unit gone from disk gets a
  `unit skipped` row and no engine call.
* **Failure is per unit, and the row set never lies.** Rows are buffered per
  unit and emitted when the unit finishes. Statuses (`TConvertStatus`,
  `ConvertStatusText`): `converted`; `FAILED -- restored` (the unit was copied
  back from its `.BCK`); `rolled back` (an earlier book on this unit converted,
  a later one failed, the restore undid it); `book skipped` (invalid book --
  reported once, skipped for every unit); `unit skipped` (missing, the reindex
  before its first book failed, or the backup copy failed); `FAILED -- NOT
  restored` (the restore itself failed; backups kept
  and named -- the summary LEADS with these). File I/O exceptions are handled
  per unit; nothing escapes the runner.
* **Book validity comes from convert-apply's own `rule_errors`.** A separate
  `convert-validate` without `--from`/`--to` checks syntax only (measured), so
  it is not used for this.
* **`ParseApplyJson` cuts at the LAST `}` and skips leading noise.** The engine
  prints `(loaded defaults from ...)` AFTER the JSON document; before the fix
  every real apply parsed as "unparseable" and every unit was restored.
  `HasCapability` slices `info --json` the same way.
* **Testable runner:** the `RunConversionUnits(AUnits, ABooks, AApply, AIndex,
  ...)` overload takes `TApplyFn` / `TIndexFn` function references; the
  `TEngineAdapter` overload binds `ApplyConversion` / `IndexProject`. The fault
  checks (`runner.rollback.*`, `runner.backup.failure`,
  `runner.restore.failure`) use fakes; `runner.live.*` uses the real engine.
* **The index is refreshed BEFORE each unit's first book** as well as after
  every book: convert-apply patches the `.dfm` at the index's line ranges, so a
  unit edited in the IDE since the last index would be patched in the wrong
  place. A failed refresh gives `unit skipped` with `reindex before apply
  failed: <output>` -- no backup, no engine apply -- and the run continues with
  the next unit (`runner.reindex.before.*`).
* **The project file is ALWAYS the DB's own** -- `ProjectFileForDb(
  GEditorProjectDb)`, i.e. `<dir>\<Name>.dproj` for `<dir>\_D-RAG\<Name>.sqlite`
  -- never the Unit Rules Destination: `index --project <other.dproj> --db
  <editor's DB>` would re-scope the editor's project DB to another project.
  Convert refuses (`Convert refused: the project index <db> has no project file
  on disk -- expected <path>.`) when it does not exist. The Destination field
  only classifies harvested units.
* **Captured at Convert time:** units, books, project file / DB and the rules
  folder (`FRunRulesFolder`) -- File > Open / New during a run cannot move the
  report (`convert-run-yyyymmdd-hhnnss.txt`, tab-separated, UTF-8 WITHOUT a BOM
  so non-ASCII engine text survives, in that folder). After the rows it lists
  every unit a cancel kept from running (`not reached (cancelled)`, also added
  to the grid), then `Run<TAB>completed` or `Run<TAB>cancelled -- N unit(s) not
  reached`, then `Final reindex<TAB>ok` / `FAILED: ...` / `not run`. The
  never-reached set comes from counting cancel polls: `RunConversionUnits`
  polls `ACancelled` exactly once just before each unit (documented contract).
* **Mid-run locks:** File > Save / Save As / Curate are disabled while a run is
  in progress (`TConvertHost.RunStateChanged`, fired from `SetRunning`) -- a
  book saved mid-run would change the rules the run's later units get. Open and
  New stay enabled. A drop (or any `AddSources` call) during a run is refused
  with `A conversion is running -- sources cannot be added until it finishes.`
* **Unindexed source units are flagged on their row:** owner-drawn, bold red,
  display text + ` -- not in the project index`; the ITEM text stays the raw
  path (the job consumes it). "Indexed" means the unit's FULL PATH is in the
  project DB's `files` table (`TEngineAdapter.ListIndexedFiles`, one `sql
  SELECT path FROM files` with `--limit 1000000`; `UnitInIndex` compares
  `ExpandFileName`'d paths case-insensitively) -- NOT the unit name: the engine
  finds the `.dfm` by path, and `M2022\DM1.pas` must be refused when the
  project indexes its own `DM1.pas` (`convertrun.pre.same.name.foreign.path`).
  The index set is refreshed on add, on tab show (skipped when the list is
  empty) and after a run. Convert refuses while any listed unit is unindexed
  (`Preflight`, same `UnitInIndex`), and refuses without the project file on
  disk (see above).
* **The form refuses to close while a run is in progress** (File > Exit and the
  window X). `Application.Terminate` or a Windows shutdown still bypasses it.
* **Measured cost:** a 3-file fixture takes ~94-106 s per engine call
  (convert-apply); a whole driven run of one unit x one book was 105 s.
  `CONVERT_TIMEOUT_MS = 600000` for conversion calls; `ENGINE_TIMEOUT_MS =
  180000` stays for every other call. A book list of M books on N units is up
  to M x N such calls.

### Engine gaps (open INBOX notes, main tree `docs\`)

* **Unit rules are not applied by the engine.** Unit-rules-only books are
  listed greyed `(unit rules: engine support pending)` and cannot be checked;
  mixed books run their `#convert` blocks with `(unit rules not applied:
  engine)`. `info --json` -> `capabilities.apply_unit_rules: true` lifts both
  (read once per session, re-probed by the tab's Refresh):
  `INBOX-2026-09-29-converter-to-engine-apply-unit-rules.md`.
* **`BDE-to-FireDAC.rules` fails convert-apply validation** (every `#link`
  "not found"): `INBOX-2026-09-29-converter-to-engine-convert-apply-bde-book-fails-validation.md`.
* **`lint-all --rule doc-drift --fix --apply` de-indents** a two-space `///`
  block above a column-0 routine (hand-written lines too). After ANY use of the
  fixer here, check non-`///` lines and `git diff --stat` with and without
  `-w`, and delete its `.bak` files:
  `INBOX-2026-09-29-converter-to-engine-doc-drift-fix-dedents-indented-blocks.md`.
* **Lint false positives held by `dl:ok` reviews** (try-except-swallowed on a
  catch-and-check test; unused-unit-in-uses when an implementation-only
  routine's return type is the only use; per-file `lint` of a `.dpr` reporting
  EVERY marker as `review-marker-unused`):
  `INBOX-2026-09-29-converter-to-engine-lint-false-positives-convert-tab.md`.
  Judge the tests `.dpr`'s markers with `lint-all`, never per-file.

### Verification kit

* **Model tests:** `tests\ConvRulesModelTests.exe` -> **1243 pass / 5 fail**;
  the 5 are the VARINSP fixture (`picker.unit.has.VARINSP`,
  `fill.from-unit.nonempty` / `.has.TOvcController` / `.has.TPanel` /
  `.has.TOvcTable`). A full run is ~6 min (the live runner test is ~3 min of
  it); a build or redeploy of `dll-win64` mid-run kills it -- discard that run.
* **GUI drivers** (`tests\gui\`, run by hand as `pwsh -NoProfile -File <driver>
  -Exe <ConvRulesEditor.exe>`, the exe beside a frozen `drag-lint.exe` whose
  Win64 library index answers -- a staged copy, never `dll-win64`). Expected
  on the final build:

  | driver | checks | covers |
  |---|---|---|
  | `drive-unit-rules-toolbar.ps1` | 41 | menu bar items, toolbar gone, Uses Units commands, Swap flow |
  | `drive-unit-picker.ps1` | 20 | unit picker |
  | `drive-unit-harvest.ps1` | 21 | Unit Rules harvest (`-ProofNoDestination` control) |
  | `drive-file-menu.ps1` | 19 | New / Save As / Exit, the guard, delete-in-place makes dirty |
  | `drive-owning-open.ps1` | 6 | cross-book double-click goes through `ConfirmDiscard` |
  | `drive-convert-tab.ps1` | 20 | Convert tab end to end on a temp fixture (`Fix.dproj` + `Loose.pas`): unindexed refusal, File > Save / Save As / Curate locked mid-run and unlocked after, in-place convert, `.BCK1` for `.pas` and `.dfm`, both named in the grid and the report, report UTF-8 without BOM with the final-reindex line |

  `drive-convert-tab.ps1 -ProofNoIndex` skips the fixture index: 10 pass / 9
  fail is the proof the conversion checks (and the mid-run menu lock) can fail. It stops at "Cannot read
  the project index" (no DB), not at the unindexed refusal; that refusal is
  proven by `Loose.pas` in the normal run.
* **Driver traps recorded on this branch:** `LB_GETTEXT` is system-marshalled
  -- read it into a LOCAL buffer, not remote memory; screen capture of a CHILD
  window here returns another control's pixels -- use `PrintWindow(hwnd, dc,
  0)`; an owner-drawn row's state is read from its pixels, with an "ink" count
  so an unpainted row cannot pass as "not red"; the Open dialog is driven by
  class `Edit` + `&Open` (English Windows only).
