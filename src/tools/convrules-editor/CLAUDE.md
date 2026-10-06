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

* **The class cast IS realized on the `.pas` side (corrected 2026-10-05); the
  `.dfm` image half is UNVERIFIED.** This bullet said `#link OptionsImage.Glyph <-
  Picture : AssignGraphic` was skipped on the `.pas` side and that `--castlib`
  ran enum blocks only. Engine commit `52d9a1b9` realized class casts on the
  `.pas` side. Whether the `.dfm` re-emit still reports `dropped Picture.Data`
  (twenty buttons losing their glyphs) has NOT been re-measured since -- check a
  real convert-apply on VARINSP before repeating either claim.
* **Real conversions are ON HOLD for projects re-stamped to 1.21.0 (2026-10-05)**
  until the engine session sends "done". 34 of 36 DBs (Micronite2027 among
  them) were re-stamped by an unreviewed 1.21.0 build, and the 1.20.6 pin
  refuses to WRITE them -- the Convert tab's reindex-before-apply would fail.
  Read-only verbs (convert-validate, proptree, query, sql) still answer.
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

* **Model tests:** `tests\ConvRulesModelTests.exe` with `CONVRULES_TEST_ENGINE` =
  the 1.22.0 pin -> **`model-tests: 1646 pass / 5 fail / 0 skip / 1651 total`**
  (measured 2026-10-06 after C8 Task 8; 1616 / 5 / 1 skip on the 1.21.1 pin after the
  fix wave; 1422 / 5 / 0 before C8; 1329 / 5 before C6); `inherited.live` RUNS now
  (the engine reports `inherited_instances`) and SKIPs on an older pin; the 5 are the VARINSP fixture (`picker.unit.has.VARINSP`,
  `fill.from-unit.nonempty` / `.has.TOvcController` / `.has.TPanel` /
  `.has.TOvcTable`). A full run measured 98-178 s on 2026-10-06 (recorded
  earlier as ~6 min, the live runner test ~3 min of it); a build or redeploy of `dll-win64` mid-run kills it -- discard that run.
* **GUI drivers** (`tests\gui\`, run by hand as `pwsh -NoProfile -File <driver>
  -Exe <ConvRulesEditor.exe>`, the exe beside a frozen `drag-lint.exe` whose
  Win64 library index answers -- a staged copy, never `dll-win64`). Expected
  on the final build (measured 2026-10-06 on a staged copy of the 1.22.0 pin,
  all 10 green; the same counts on the 1.21.1 pin before C8 Task 8):

  | driver | checks | covers |
  |---|---|---|
  | `drive-unit-rules-toolbar.ps1` | 41 | menu bar items, toolbar gone, Uses Units commands, Swap flow |
  | `drive-unit-picker.ps1` | 20 | unit picker |
  | `drive-unit-harvest.ps1` | 21 | Unit Rules harvest (`-ProofNoDestination` control) |
  | `drive-file-menu.ps1` | 19 | New / Save As / Exit, the guard, delete-in-place makes dirty |
  | `drive-owning-open.ps1` | 6 | cross-book double-click goes through `ConfirmDiscard` |
  | `drive-engine-wait.ps1` | 9 | progress window: appears after `SHOW_DELAY_MS`, Cancel closes it and stops the To tree, retry after cancel, a fast load shows no window, a re-load is cached (`wait.reload.*`) |
  | `drive-book-depth.ps1` | 13 | depth combo shows the book's `#depth`, gated on `book_depth`, absent `#depth` not added on save, New file shows the default, `depth.change.*` (an engine without `book_depth` gives 10 + 1 SKIP line) |
  | `drive-convert-tab.ps1` | 20 | Convert tab end to end on a temp fixture (`Fix.dproj` + `Loose.pas`): unindexed refusal, File > Save / Save As / Curate locked mid-run and unlocked after, in-place convert, `.BCK1` for `.pas` and `.dfm`, both named in the grid and the report, report UTF-8 without BOM with the final-reindex line; since C8 also: no E7 order dialog on a fixture with no inherited instance |
  | `drive-validate-scope.ps1` | 18 | scoped validation on Save (warnings, unchanged re-save fast), progress window + Cancel, owed block revalidated, Exit without a prompt, `automatch.*` |
  | `drive-inherited-offer.ps1` | 15 | C8: ancestor-first prompt (No / Yes inserts above), row note on the status bar (incl. an E2b code-only use), order warning (No runs nothing), the E10 run note branching on the staged engine's `inherited_instances` (`engine.refusal.note.absent` on 1.22.0, `engine.refusal.note` on a 1.21.1 pin copy -- run BOTH stages; `-ProofNoInheritance` control) |

  `drive-convert-tab.ps1 -ProofNoIndex` skips the fixture index: 10 pass / 9
  fail is the proof the conversion checks (and the mid-run menu lock) can fail. It stops at "Cannot read
  the project index" (no DB), not at the unindexed refusal; that refusal is
  proven by `Loose.pas` in the normal run. `drive-inherited-offer.ps1
  -ProofNoInheritance` gives 8 pass / 6 fail on the 1.22.0 pin (7 / 7 on the 1.21.1
  pin, where the E10 refusal note is the seventh FAIL; on 1.22.0 its `.absent` twin
  passes vacuously): the C8 checks can fail.
* **Driver traps recorded on this branch:** `LB_GETTEXT` is system-marshalled
  -- read it into a LOCAL buffer, not remote memory; screen capture of a CHILD
  window here returns another control's pixels -- use `PrintWindow(hwnd, dc,
  0)`; an owner-drawn row's state is read from its pixels, with an "ink" count
  so an unpainted row cannot pass as "not red"; the Open dialog is driven by
  class `Edit` + `&Open` (English Windows only).

## Book depth, progress window, refusals -- hand-over notes (feat/engine-1206-adoption, 2026-09-30)

The editor side of engine 1.20.6's interface change: a per-book `#depth N`, a
cancellable progress window for property-tree loads, and a `refused` row status
on the Convert tab. Built and verified against the 1.20.3 pin (which has none of
the three capabilities); the depth-change path is proven only once 1.20.6 is
pinned. Plan / spec (gitignored, main tree):
`docs\superpowers\plans\2026-09-30-engine-1206-adoption.md`,
`docs\superpowers\specs\2026-09-30-engine-1206-adoption-design.md`; ledger with
every ruling: `.superpowers\sdd\2026-09-30-engine-1206-adoption\progress.md` in
the `convrules-depth` worktree.

### `#depth` in the model

* **`#depth` lives in `ConvRules.Model`**: node kind `rnkDepth`, consts
  `BOOK_DEPTH_DEFAULT` (5) / `BOOK_DEPTH_MIN` (1) / `BOOK_DEPTH_MAX` (10),
  `TRuleBook.Depth`, `DepthState` (`bdsAbsent` / `bdsValid` / `bdsInvalid` /
  `bdsDuplicate`), `DepthNodes` (private), `SetDepth`. **The engine accepts
  ONE `#depth` per book, decimal digits only, 1..10** (`DRagLint.Convert.Rules`,
  `IsDecimalDigits`): a second `#depth` -- whatever either value is -- and a
  sign, ``$` or `0x` value are validation ERRORS, so `convert-apply` reports
  `rule_errors` and the Convert tab skips the book. `ParseLine` matches it
  (`IsDecimalDigits` + range; `depth.parse.digits.only`). `Depth` is the FIRST
  line's value when valid, else 5; `DepthState` precedence is `bdsDuplicate` >
  `bdsInvalid` > `bdsValid` (`depth.duplicate.first.invalid`: an invalid first
  line plus a valid second is still `bdsDuplicate`).
* **`SetDepth` inserts before the first `#convert`** when the book has no
  `#depth`, which shifts EVERY header index after it. Re-find by NODE, never
  keep an index: `DepthChanged` captures the active header node, calls
  `SetDepth`, then `FActiveHdr:= FBook.Nodes.IndexOf(Hdr)` and
  `RefreshRulesList` (the list items' header indices are stale too).
* **An explicit depth change REPAIRS a `bdsDuplicate` book** (ruling R11):
  `SetDepth` updates the first `#depth` and DELETES (frees) every other one; the
  state becomes `bdsValid` (`depth.set.duplicate.repairs`; the header is
  re-found by node, `depth.set.duplicate.header.found.by.node`). An update
  re-emits the line canonically (`#depth  3` becomes `#depth 3`).
* **Opening and saving a book without `#depth` never adds one** -- only a user
  change writes the directive (`depth.absent.roundtrip`; driver
  `depth.absent.not.added`, which also proves a save really happened).
* **A From-only `#convert X -> ` keeps its From type** (fixed 2026-10-05; it
  had been lost on every load). `ParseLine` trims the line, which takes the
  arrow's right-hand space with it, so `SplitArrow(' -> ')` never matched
  `X ->`; it now splits `Body + ' '`. The `, Unit` form always parsed. Guards:
  `model.convert.from.only.roundtrip` / `.with.unit.roundtrip` -- load,
  Snapshot + reload, and a DIRTY re-emit + reload. Note that Save / Snapshot
  still DROP a block that maps nothing (`BlockMapsSomething`), so a stub with
  no `#link` / `#apply` / `#ignore` is still not written -- unchanged policy.
  `#useswap` parses the same way (`SplitArrow(Body, ...)`) and was deliberately
  NOT changed: an Old-only `#useswap X -> ` is not a form the editor can create
  (the replacement picker's OK refuses an empty list), and a hand-written one
  reads as nothing useful to the engine either (`DRagLint.Convert.Rules` takes
  `X ->` as the Old unit name).
* `ConvRules.BlockFile`'s `FILE_SCOPE_DIRECTIVES` includes `#depth`, so a
  `#depth` after the last block opens a trailing file-scope block.
* `TRuleBook.ParseLine` carries one comma-list review for method-too-long /
  too-many-exit-points / cyclomatic / cognitive: every directive adds one arm
  and one exit. `SetDepth` carries a `function-result-not-set` review that is an
  ENGINE false positive (a leading `if .. then raise` guard is counted as a path
  that skips Result; filed, see below).

### Capabilities and engine arguments

* **Capabilities are probed ONCE, in `TConvRulesForm.Create`**, by one
  `TEngineAdapter.CapabilityNames` (`info --json`, `ParseCapabilityNames`):
  `FBookDepthOk` from `CAPABILITY_BOOK_DEPTH`, `FEngine.ProgressLines` from
  `CAPABILITY_PROGRESS_LINES`. A re-pin needs an EDITOR RESTART. The probe has
  its OWN bound, `INFO_TIMEOUT_MS` = 15 s (`TEngineAdapter.InfoTimeoutMs`, set by
  `Create`; writable for the tests only), via `RunCaptureTimed` -- not the 180 s
  `ENGINE_TIMEOUT_MS`, because it runs on the UI thread during start-up. A
  timeout reads as NO capabilities, i.e. the old-engine behaviour
  (`caps.timeout.is.none`: a sleeping `.cmd` stand-in gives [] inside a 1.5 s
  bound; `caps.standin.answers` is its positive control).
  `HasCapability` is now case-insensitive, and it goes through `CapabilityNames`,
  so the Convert tab's `apply_unit_rules` probe has the same 15 s bound (a
  timeout = False = unit rules greyed, as on an old engine).
* **`--depth N` only with `book_depth`; `--progress-interval S` only with
  `progress_lines`** -- an older engine exits 3 on either flag. `DepthArgs(ADepth,
  AProgress)` builds both; `ADepth = 0` omits `--depth`. `PrepareEngineForTrees`
  sets `FEngine.TreeDepth:= if FBookDepthOk then FBook.Depth else 0` before
  every tree load. `GetProptree` passes `DepthArgs(FTreeDepth, FProgressLines)`;
  `convert-scaffold` passes `DepthArgs(FTreeDepth, False)` (no progress). Both
  come from the IN-MEMORY book, never `--rules FILE`.
* **The depth combo (`FCbDepth`, 1..10) is disabled** with the hint
  `DEPTH_HINT_UNSUPPORTED` when the engine lacks `book_depth`. `FLblDepthNote`
  says `(default)`, `(from book)`, `(book value invalid -- using 5)` or
  `(several #depth lines -- the engine rejects this book; pick a depth to repair
  it)` (the last two in red). `RefreshDepthControl` runs in `LoadText` (every
  open / New / Curate reload), in `Create`, in `DepthChanged`, and in
  `ChooseTargetForNewRule` right after the new-file `FBook.Clear` (Task 5 fix
  I1). It also stops a pending depth commit (`FDepthTimer`, `FDepthPending`).
* **A depth change reloads the grid EXACTLY ONCE** (`DepthChanged` ->
  `LoadGridForBlock`); `RefreshRulesList` does not fire a second load.
  `FCbDepth.OnChange` (`DepthComboChange`) does NOT commit: it marks
  `FDepthPending` and, on the CLOSED combo (mouse wheel, arrow keys), restarts
  `FDepthTimer` (`DEPTH_COMMIT_DELAY_MS` = 600 ms); with the list dropped down it
  waits for `OnCloseUp` (`DepthComboCloseUp`). Either path calls `DepthChanged`,
  which writes unless `TRuleBook.DepthPickWrites` says the book already holds
  exactly that one valid value -- so a SELCHANGE/CLOSEUP pair for one pick
  (Windows does not fix their order) still reloads once, and opening and closing
  the list without a pick writes nothing. **An explicit pick is recorded**: the
  default (5) on a book WITHOUT `#depth` WRITES `#depth 5` (owner decision
  2026-10-04, `depth.pick.default.on.absent.writes`); only opening and saving
  must never add the line. On `bdsDuplicate` / `bdsInvalid` the write is the repair.
* **A depth commit never runs inside another operation** (fix round 2). The
  timer runs in ANY message pump (`LoadGridForBlock`'s `ProcessMessages`, the
  progress window, `MessageDlg`, the Open dialog), so `DepthTimerFire` and
  `DepthComboCloseUp` DEFER -- step kept pending, timer re-armed -- while
  `DepthCommitBlocked`: `FTreeLoads > 0` (set with try/finally by
  `LoadGridForBlock` and by the `LongCallRunner` wrapper in `Create`, so New
  Conversion's class checks count too), a menu loop (`FMenuOpen` for the main
  menu, `InMenuLoop` = `GetGUIThreadInfo` for popup / system menus, whose loop a
  VCL `TPopupMenu` runs on its own window), `Screen.ActiveForm <> Self` (a modal
  form) or the main window disabled (a common dialog). A pending pick is
  COMMITTED (not cancelled) by `CommitPendingDepth` at the top of
  `ConfirmDiscard` (Open, New, Exit / window X, cross-book double-click, the
  Convert tab's check), `SaveBook` (Save, Save As), `DoCurate` and
  `DoNewConversion` -- so the unsaved-changes guard sees it; the commit costs one
  reload even when the book is then replaced. **Esc in the dropped list cancels**:
  `DepthComboWndProc` (a `WindowProc` hook) records `CBN_SELENDCANCEL` ONLY between
  `CBN_DROPDOWN` and `CBN_CLOSEUP` (`FDepthDropped`) -- a drop-down-list combo
  also sends it on EVERY focus loss with the list closed, with no close-up after
  it, and a flag set then stuck and swallowed later steps (fix round 3);
  `CBN_SETFOCUS` clears a stale cancel; a cancelled pick re-syncs the combo to
  the book (`SyncDepthCombo`). `DepthComboCloseUp` then drops the pending pick (a queued reset also drops a
  SELCHANGE that follows the close-up), so an explicit cancel never modifies the
  book, not even as a repair.
  Proven by instrumentation in Task 5; a double load is a second slow engine
  call (the double-click path shipped one once, ~161 s).

### Streaming runner and the progress window

* **`TEngineAdapter.RunCaptureStreaming` = two pipes.** Stdout is `AOutput`;
  stderr is split into lines (`TLineSplitter`), progress lines
  (`TryParseProgressLine`) go to `AOnProgress` and NEVER reach `AOutput`; any
  other stderr text (a `FATAL: ...`) is kept and returned
  (`stream.stderr.kept`). It returns the CHILD's exit code unchanged -- the
  engine's own 3 is FATAL (unknown flag, DB cannot be opened or is locked) and
  reaches `GetProptree`'s generic failure branch with its output
  (`stream.exit3.not.timeout`, `stream.exit3.fatal.kept`,
  `engine.proptree.exit3.is.failure`). Its own outcomes are NEGATIVE so they can
  never collide with an exit code: `ENGINE_OUTCOME_TIMEOUT` = -2,
  `ENGINE_OUTCOME_CANCELLED` = -3 (-1 = not started; `exit.codes.distinct`).
  `RunCaptureTimed` is unchanged and still reports ITS timeout as 3. The child is killed on every
  exit path, including a raising progress callback (`ReapChild` in a finally;
  `stream.raise.kills`), and each drain reads at most `MAX_READS_PER_DRAIN` (16)
  chunks so Cancel and the deadline stay responsive. `StartHiddenProcess` is
  shared with `RunCaptureTimed`.
* **Only `GetProptree` streams.** Every other verb stays on the merged-pipe
  `RunCaptureTimed`. The proptree bound is `CONVERT_TIMEOUT_MS` (600 s).
* **`ConvRules.EngineWait` is editor-only** (`RunWithProgressDialog`,
  `TEngineWaitForm`; not in the tests' compile closure). With `LongCallRunner`
  nil the work runs inline, with no window and no cancel; the model tests
  install FAKE runners (`TestProptreeCancelState`: one returns
  `ENGINE_OUTCOME_CANCELLED`, one the engine's exit 3, one
  `ENGINE_OUTCOME_TIMEOUT`, one raises). `TConvRulesForm.Create` sets
  `FEngine.LongCallRunner` to a wrapper that counts `FTreeLoads` around
  `RunWithProgressDialog`.
* **The window appears only after `SHOW_DELAY_MS` (400 ms)** -- a fast load
  shows nothing (`wait.fast.no.window`). Never raise the delay to hide a slow
  call; measure the call.
* **One Cancel stops From AND To.** `GetProptree` resets `LastCancelled` at its
  TOP (before any early exit) and sets it on `ENGINE_OUTCOME_CANCELLED`; the block load checks it
  after the From tree and does not start the To tree
  (`wait.cancel.stops.to.tree`: no second window within 3 s). A cancelled load
  clears BOTH trees, so the grid is left EMPTY (a To cancel no longer leaves the
  From leaves), sets `FActiveHdr:= -1` and QUEUES a deselect of the rules list
  (`TThread.ForceQueue`), so selecting the rule again really retries
  (`wait.retry.after.cancel`); it must not count as loaded. Because of that a
  depth change after a cancel does NOT reload; the status says to change the
  depth first, THEN select the rule again (the depth part only when the engine
  has `book_depth`). The proptree timeout text likewise names the Depth box only
  when `TreeDepth > 0` (`engine.timeout.text.depth.box` / `.no.depth.box`).
* **`FLastLoadCancelled` (form) is per call, `FEngine.LastCancelled` is per
  engine call.** `LoadGridForBlock` sets the former; `OpenOwningRuleEntry` and
  `DoNewConversion`'s select step RESET it before the load they own, so a cancel
  left over from an earlier call (New Conversion's From check) can no longer
  suppress `Opened the rule ...` / `Loaded ...` when no load ran.
* **Cancel texts are accurate per caller** (`DoNewConversion`: "New conversion
  cancelled while checking the From class X -- nothing was created." / the To
  class). After a cancelled load of a From-only
  stub, New Conversion no longer treats it as completing the stub
  (`FActiveHdr = -1`) and shows the same-book prompt (deferred minor).
* **The cancel message stays on screen** (`SetStatusAfterCancel`): Auto-Match,
  Mappings, Assign, Find in From, Only this type and `SurfaceChanged` APPEND
  their text to `FCancelStatus` (the text the cancel wrote) while
  `FLastLoadCancelled` is set AND that text is still what the status line
  starts with -- so a cancel from an earlier book never comes back once
  anything else wrote the status, and repeated clicks do not stack. No
  automated test (MainForm); a manual check.
* **Known gap (deferred):** the class-name resolve (`ResolveClassQName`,
  0.5-1 s) still runs on the UI thread and cannot be cancelled.

### Refusals on the Convert tab

* **`TApplyRow.Refused`** is `(not Ok) and refused = true` in the apply/1 JSON
  (`ParseApplyJson`); `TApplyRow.Error` then holds the engine's `reason`
  (`convert-apply refused the unit and gave no reason` when empty).
* **`csRefused` (last member of `TConvertStatus`, text `refused -- not
  changed`) takes the FAILURE path**: `FailUnit(AReason, csRefused)` restores
  the unit and rolls back earlier books on it, exactly like
  `csFailedRestored`; notes say "was refused" instead of "failed". **Except
  when nothing had changed the unit yet** (the refused book was its first, or
  every earlier one was skipped): the engine left the file untouched, so nothing
  is restored, the row's `Backup` / `BackupDfm` are '' and the unneeded `.BCK<N>`
  files are DROPPED, as for a skipped book (owner decision 2026-10-04;
  `runner.refused.first.drops.backup`). After an earlier book converted the unit,
  the restore needs the backup and keeps it (`runner.refused.later.keeps.backup`). The summary
  adds `N unit(s) refused by the engine and left unchanged`, THEN (if any)
  `N earlier conversion(s) on those units were rolled back by a later failure or
  refusal` -- after the refused sentence, because a roll-back can follow a
  refusal and the old "rolled back with them" read as caused by "0 failed".
* **A refusal is a refusal even when it also lists `rule_errors`**: the
  book-invalid branch in `RunBook` is guarded `and not Row.Apply.Refused`, so
  `refused:true` with a non-empty `rule_errors[]` gives `csRefused` for that
  unit and the book stays VALID for the next one
  (`runner.refused.with.rule.errors.is.refused`: two units, two apply calls,
  two refused rows). Engine 1.20.6 never sends that combination; the guard is
  for a later engine that might.

### Drivers (`tests\gui\`, by hand, on a staged pin copy)

* **`drive-engine-wait.ps1` -- 8 checks** (`wait.main`, `.window.appears`,
  `.cancel.button`, `.cancel.closes`, `.cancel.status`, `.cancel.stops.to.tree`,
  `.retry.after.cancel`, `.fast.no.window`). It waits out the start-up engine
  calls first. The slow fixture is a TcxButton block; the fast one is
  `#convert TNoSuchClassXyz -> , NoSuchUnitXyz` (58-93 ms).
* **`drive-book-depth.ps1` -- 10 checks + 1 SKIP line** on the 1.20.3 pin. The
  SKIP line covers the three `depth.change.*` checks (`invoke.save`,
  `one.line`, `saved`), which run only when the engine reports `book_depth`.
  **They become REQUIRED after the 1.20.6 re-pin:** 13 pass, no SKIP. Its
  `Choose` sends CBN_SELCHANGE to the CLOSED combo, so it now exercises the
  wheel / arrow-key path (`FDepthTimer`), and waits 1.5 s before File > Save; the
  drop-down + `OnCloseUp` path is an owner check.
* **Both drivers open a class with `--form` plus a double-click on the rule
  row** -- opening a book loads NO tree, so a driver that only opens a book
  never sees the window.
* **`drive-unit-rules-toolbar.ps1` ignores `TEngineWaitForm`** when it counts
  top-level windows, and waits up to `ENGINE_IDLE_SEC = 900` for the window to
  go (Task 5 fix; it had read the progress window as New Conversion's second
  dialog and dropped to 30/11). The window is intended behaviour; the driver
  changed, not the product.
* **Machine load, measured 2026-09-30 ~18:05:** the pinned 1.20.3 CLI
  `proptree --qname cxButtons.TcxButton --min-visibility published
  --refs-as-leaves --format json --db library-Win64` took **37.5 s** (6.96 s in
  July), with the engine session's proptree runs and three LSP engines on the
  box. Driver timeouts were raised for that; PRODUCT timeouts were not.

### Waiting on engine 1.20.6 (plan Task 8 PENDING)

* **Owner checks after the re-pin:** a real TFDQuery load shows `depth x of y`
  progress in the window; Cancel stops it; changing the depth changes the leaf
  count; `drive-book-depth.ps1` runs 13/0 with no SKIP; confirm the refusal
  key names (`refused`, `reason`) against the merge notice.
* **Plan Task 8: show the engine's unreachable-member warnings** (owner
  requirement 2026-09-30: a rule through an inaccessible member is KEPT in the
  book; engine and editor WARN, "never applied unless a descendant class
  changes the visibility of <Member>"). The editor shows the ENGINE's warnings
  and does not judge accessibility itself. Engine contract (T2h, commits
  a92b45a7 + 9d4b98bf, not merged yet):
  * text line on STDOUT: `line N: warning: <path>: <Member> is <visibility> in
    <DeclaringClass>; never applied unless a descendant class changes its
    visibility`;
  * `convert-validate`: TEXT ONLY (no `--json`); an unreachable warning does
    not change the exit code;
  * `convert-apply`: a text Warnings block, plus apply/1 `unreachable[]`
    (always present) of `{line, path, member, visibility, class, reason:
    "unreachable", message}`; `warnings[]` stays STRINGS and also carries each
    message; `items[]` kind `rule-path-unreachable`. Schema stays apply/1.
  * BDE-to-FireDAC.rules measured on the engine branch: exit 0, 16 warnings
    (lines 274-277, 374-377, 478-485).
* **Owner decisions still open:**
  * a refused unit keeps an IDENTICAL `.BCK<N>` beside it (the `FailUnit` path
    takes the backup before the engine refuses) -- keep, or delete on refusal?
  * the combo on a `bdsInvalid` book already shows 5, so picking 5 does not
    fire `OnChange`; the user must pick another value first (`SetDepth` then
    repairs the line). On `bdsDuplicate` a change rewrites only the first
    line and the red note stays. Accept, or repair / collapse the lines?
* **Other deferred minors (ledger):** summary order reads oddly when a refusal
  caused the roll-back.
* **Fixed on fix/editor-open-issues (2026-10-05):** `TLineSplitter.Feed` is
  linear (scans from a start index, cuts the consumed head once per call, also
  when the sink raises; `split.many.lines.one.chunk`, 10,000 lines in one
  chunk); a From-only `#convert X -> ` keeps its From type on reload (see the
  model section); `FDepthDropped` is cleared after `CBN_CLOSEUP` in a finally,
  so an exception from the close-up's commit cannot leave it set.

## Scoped validation on Save -- hand-over notes (fix/validate-edited-blocks, 2026-10-05)

Owner ruling: "The edited saved block should be validated. Stuff that is
unchanged is presumed validated earlier."

* **Why:** `convert-validate --from F --to T` checks EVERY `#convert` block
  against that ONE pair. Save used the active block's pair, so a multi-block book
  showed bogus errors (BDE-to-FireDAC.rules with TQuery -> TFDQuery: 145 error
  lines, exit 1). And warnings (`line N: warning: ...`, e.g. an unreachable
  protected member) never change the exit code, so the old Save -- which read
  only a failing exit's first line -- lost every one of them.
* **Save now runs:** one syntax-only pass (no pair, ~0.6 s) over the saved text,
  keeping everything; plus, for each block that CHANGED against `FSnapshot`
  (keyed by header line + occurrence; a new header counts; a block that `#apply`s
  a changed `#mapping` counts), one pass with THAT block's own pair, keeping only
  the diagnostics on its lines and on the `#mapping` lines it applies. From-only
  blocks get no pair pass. An unchanged save is the syntax pass only (driven:
  0.3-0.5 s vs 20-39 s for a save with one changed TTable block on this loaded box;
  CLI: 10-15 s per block). **File > Validate** = syntax pass + the ACTIVE block.
* **OK / failed comes from the kept diagnostics, never the exit code.** A
  non-`line N:` line that is not noise (`OK`, `(loaded defaults ...)`,
  `resolver: ...`) is an error on line 0 (FATAL etc.). Status:
  `Validate: OK, N warning(s) -- see marked rules`, or the first error +
  `(+N more)` through `SetError` (it stays red across the post-save rescan).
* **Pure logic: `ConvRules.ValidateScope`** (parse, blocks, changed blocks,
  filter, `RunScopedValidation` with an injected `TValidateFn`, marks). Tests:
  `validate.*` in the model tests, on REAL pinned-engine captures in
  `tests\fixtures\validate\` (taken 2026-10-05 10:52, before the 1.21.1 re-parse;
  TQuery capture = 145 errors, warnings only on the known 274-277 / 374-377 /
  482-485 lines).
* **Line -> rule:** `TRuleBook.SaveCompleteWithMap` returns the saved text AND the
  node per line (`SaveCompleteToString` is it with the map dropped). Marks are
  `TRuleNode.Marks` -- session state, never emitted, not in `Snapshot`/dirty, gone
  with the node on Open / New / Curate. A revalidated block's marks are replaced;
  other blocks keep theirs; syntax marks are replaced every pass.
* **Display:** rules list column `Check` (`2 err` / `4 warn`) + info tip; grid
  cast column painted with `[!] ` / `[w] ` (text unchanged) + hint. Owner checks:
  the visuals were not driven.
* **`ValidateText` now uses separate pipes** (`RunCaptureStreaming`): over the
  merged pipe a driven Save showed `Validate: s, not a re-parse). (+3 more)` --
  the tail of stderr's `resolver:` advisory cut off by a stdout chunk.
* **GUI driver `tests\gui\drive-validate-scope.ps1`** -- 11 checks: New
  Conversion TTable -> TFDTable (book `#depth 2`), Save shows `4 warning(s)`, an
  unchanged re-save is fast and `OK`. RED on the main build
  (`Validate: OK`, no warnings; its unchanged re-save took 19.9 s).
* **Progress window + Cancel (follow-up, same branch):** every pass runs on
  `FEngine.LongCallRunner` (`RunWithProgressDialog`, so `FTreeLoads` is counted
  and no depth commit fires inside). The window shows after `SHOW_DELAY_MS`;
  Cancel kills the running engine call and starts no further pass. The book is
  already on disk, so nothing is undone and it stays clean. Blocks not validated
  keep their marks and go into `FValidatePending` (pure: `NextPending`,
  `ChangedBlockJobs(..., APending)`), so the NEXT Save validates them although they
  no longer differ from the snapshot; the set is dropped when the book is
  replaced. Status: `Validate: cancelled -- N changed block(s) not checked: <From
  types>; checked so far: ...`. Driver now 16 checks (window, Cancel, owed block
  revalidated, unchanged re-save fast, Exit without a prompt).
* **Known cost:** passes still run one after another: a new book with many blocks
  is N x 10-40 s, now cancellable.

## Editor minors -- hand-over notes (fix/editor-minors, job C6, 2026-10-05)

* **Model tests choose their engine EXPLICITLY** (`ChooseTestEngine` in the
  tests `.dpr`): `drag-lint.exe` beside the runner, else the exe named by
  `CONVRULES_TEST_ENGINE`, else none (live tests SKIP; the runner prints its
  first line `engine: ...` with the reason). The silent fallbacks to
  `third_party\dll-win64` are gone -- that is the live, rebuilt-without-warning
  engine. Stage a COPY of a pin beside the runner.
* **`build\_build_convrules_editor_local.bat` no longer stages to dll-win64**
  unless given `stage`. The release pack ships
  `src\tools\convrules-editor\ConvRulesEditor.exe` (not the dll-win64 copy) and
  passes `stage` so dll-win64's editor keeps step with the drag-lint.exe it syncs
  (`run_release_pack_payload_guard.ps1` still PASS).
* **Every engine verb now reads stdout on its own pipe.** `RunCaptureTimed` (and
  so `RunCapture`) wraps `RunCaptureStreaming`: stdout whole, stderr's lines
  after it; its timeout code stays 3. Guard: `pipes.*` -- `.cmd` stand-ins write a
  stderr line in the MIDDLE of a stdout JSON line (`info --json`, `sql --json`).
* **`ResolveClassQName` runs inside `GetProptree`'s long-call work** -- under the
  progress window, cancellable before either call starts, `FTreeLoads` counted
  by the editor's runner (`resolve.*` tests). Measured: the resolve query is
  0.5-1.2 s (`query --name TcxButton`, library-Win64 + Micronite2027), which the
  UI thread no longer blocks on.
* **Resolutions are CACHED for the session** (`TEngineAdapter.FResolveCache`,
  key = upper-cased name + `#0` + `DbArgs`; NEGATIVE answers cached too). Without
  it every rule click paid the query under the window and a trivial load flashed
  it. Cleared by `SetDbs`, by `IndexProject`, by `ClearResolveCache`, and by the
  form when a Convert run ends (that run reindexes through its OWN adapter). A
  failed lookup (query exit other than 0/1) and a lookup cancelled before it ran
  are never cached (`rcache.*`). `drive-engine-wait.ps1` now checks the RE-load
  (`wait.reload.no.window`, `wait.reload.query.cached` = one engine child,
  proptree only); both FAIL on the uncached build. The first uncached load is not
  asserted; `wait.window.appears` is the positive control.
* **Mapping > Auto-Match is disabled while no rule is loaded**
  (`UpdateMenuEnabled`; driver `automatch.*` in `drive-validate-scope.ps1`, RED
  on main).

## Inherited instances (C8) -- hand-over notes (feat/c8-inherited-editor, 2026-10-06)

Spec: `docs\superpowers\specs\2026-10-05-c8-inherited-instances-design.md` (E1-E11;
the engine half N1-N5 is the ENGINE stream's). Plan:
`docs\superpowers\plans\2026-10-05-c8-inherited-instances-editor.md`. Ledger with
every ruling: `.superpowers\sdd\2026-10-05-c8-inherited-instances-editor\progress.md`
in the `c8-inherited` worktree.

### Where things live

* **Decisions: `ConvRules.Inheritance`** (model-tested). `ScanDfmInheritance` /
  `FindDfmObject` share one header walk (`WalkDfmHeaders`) that skips `<` / `(` /
  `{` values whole, so a collection's `item`/`end` never closes a component.
  `AnalyzeUnit` / `AnalyzeUnits` walk the class chain through a `TClassLookup` and
  read ancestor .dfm files through a `TDfmTextReader`; the row notes, the offer,
  the list insert, the order warning, the Convert gate and the no-capability run
  notes are all pure routines here. Two helpers are not pure: `DiskTextReader`
  (the real reader, `TFile.ReadAllText`, which drops a BOM) and `CachingLookup`
  (fills a caller-owned cache).
* **Run-side decisions are NOT in `ConvRules.Inheritance`** (model-tested too):
  `InheritedLeftNote` / `InheritedReportNote` (the engine's `inherited[]` as a row
  note / a report note), `ConvertedRowNote` and `SourcesAddRefusal` live in
  `ConvRules.ConvertRun`;
  `InheritedReportLines`, `UnitsConvertedIn` and `CodeUseNoteDue` live in
  `ConvRules.ConvertRunner`.
* **The reader answers `TDfmRead`:** `drMissing` (no .dfm -- a class with no .dfm
  declares no component), `drUnreadable` (exists, read raised), `drRead`.
* **Engine binders: `ConvRules.InheritanceEngine`** -- `EngineClassLookup`
  (`LookupClass` + `ListClassFields`), `EngineCodeUses` (`ListCodeRefs` through
  `CodeUseName`), `IsStaleIndexError`, `AnalyzeRetryingStale`. The ONE place the
  binding is made; the model tests drive it against a fixture index.
* **Engine reads (`ConvRules.Engine`) share `SqlRowsOfDb`.** `LookupClass`:
  `symbols` kind `class` JOIN `files` LEFT JOIN `type_ancestors` ordinal 0,
  `COLLATE NOCASE`; only `IsPlainIdentifier` names are spliced in. One file = found;
  two or more files = ambiguous = outside, never guessed. `ListClassFields` reads
  only the From-typed fields the class itself declares, PINNED to the .pas the
  lookup found. The C8 reads pass `ARequireFresh`: a STALE answer is a failure
  (`INDEX_STALE_MARKER`), not data. `ParseClassLookupRows` / `ParseFieldRows` /
  `ParseCodeRefRows` are test-only entry points over the same row mappers (held by
  `dl:ok unused-public-symbol`).
* **`MainForm.pas` / `ConvertTab.pas` are outside the tests' closure** -- as before,
  build the editor too.

### What the analysis decides

* **The declaring ancestor is NOT always the parent.** Measured on DMTEST:
  `dmCPData`'s `inherited tblFtrs: TTable` is declared in `DMREADINGS`, two levels
  up; `PathToData.dfm` never mentions it. The walk continues past an ancestor that
  does not open the instance.
* **`TAncestorState`: `asUnconverted` / `asConverted` / `asMismatched` / `asOutside` /
  `asUnknown`.** `asConverted` = the declaring object has the To type of a checked pair
  whose From is the instance's type; **`asMismatched` (Task 8, 2026-10-06; REVERSES
  preflight ruling C4, which read every non-From type as converted)** = it has neither
  (the engine's `mismatched`; `TInstanceVerdict.FoundType` names the type). Its row note
  is `inherits N <types> instance(s) from <Unit>, where they are <Found> -- not this
  book's From or To type`; it is NOT offered (E6) and NOT warned about (E7) -- converting
  that ancestor with this book would not help. `ResolveInstance` therefore takes the
  pairs. `asUnknown` = the walk could not decide: the index could not be asked (failed or
  stale read), the chain loops or passes `MAX_CHAIN_DEPTH` (32), or an IN-INDEX
  ancestor's .dfm is binary (`TPF0`) or unreadable. The verdict's `Reason` names the
  cause; `AnalyzeUnit` then makes the unit `Known = False` with an `Error` carrying
  the engine's own text. **Unknown is never a row note** -- the reason goes to the
  status line (`UnknownUnitsText`). `asOutside` = the chain left the project index
  (a library ancestor, an ambiguous class) or ended at an indexed class with no
  ancestor; with no ancestor class named at all the note is the no-ancestor wording
  (`OUTSIDE_NO_ANCESTOR`, `OutsideNote`).
* **`inline` blocks are the unit's OWN frames** and are not verdicts; their
  `inherited` children are, resolved from the frame class. **Frame fallback:** when
  the form chain does not declare an instance, every enclosing block's class
  (`TInheritedInstance.Enclosing`, innermost outward, up to the innermost `inline`)
  is walked next, and the chains are MERGED; `TChainUnit.Depth` is one shared
  counter, so a frame unit always sits above every form that re-opens its child.
* **The chain offered (E2a / E6) is only the units whose .dfm declares or re-opens
  one of the descendant's instances** (plus, for a code use, the unit declaring the
  field), topmost first -- ancestors that never mention it are not offered.
* **E2b code uses: Fields first.** An identifier the unit's own class's methods use
  (implicit Self, or a receiver's first segment) is matched against the From-typed
  `Fields` each ancestor declares (`ListClassFields`); a name no ancestor declares is
  dropped WITHOUT reading any .dfm, so it can never make the unit unknown. Only a
  real hit walks the chain again reading .dfm files. The index leaves implicit-Self
  refs unresolved, so `ListCodeRefs` matches by enclosing class + name. Accepted
  gap: a closer ancestor redeclaring the name with a non-From type (shadowing) is
  absent from the filtered Fields, so a further ancestor's From field of that name
  counts.
* **Cost:** one pass measured 1.5-2.1 s per unit on DMTEST `dmCPData`. Each pass
  has its OWN class cache (`CachingLookup` over a per-pass dictionary; a failed
  answer is never cached) and one .dfm cache, so a retry asks afresh.

### The Convert tab

* **Analysis runs behind the progress window** (`FHost.RunLongCall`,
  cancellable). `FEngineProbe` is then used on the window's worker thread; that is
  safe only because the runner is MODAL and a drop is refused while `FAnalyzing`
  (class remarks of `TConvertTab`). A non-modal runner would break it.
* **A drop is refused under ANY C8 prompt too** (fix wave M2): OLE delivers drops
  inside a `MessageDlg`'s modal loop, and the E6 offer, the Convert gate and the E7
  warning were each built from the list as it was when they opened -- a unit dropped
  under the E6 prompt was wiped by Yes (`SetSources`), one dropped under the gate /
  E7 was listed but not run. `AskBlockingDrops` sets `FPrompting` around each of the
  three; `AddSources` asks `SourcesAddRefusal(FRunning, FAnalyzing or FPrompting)`
  (pure, `tab.add.*`). `ConvertClick` also reads the list only AFTER the
  open-book save prompt.
* **A stale read triggers ONE incremental reindex of the editor's own project**
  (`ProjectFileForDb` of the project DB, as the runner does) and one retry of the
  stale units (`AnalyzeRetryingStale`); a second failure leaves them unknown with
  `; reindex failed: ...` or the retry's own reason. After any such reindex the tab
  calls `TConvertHost.ProjectReindexed`, which clears the MAIN adapter's resolve cache
  (`FEngine.ClearResolveCache`), as `RunStateChanged(False)` does after a run (M6;
  wiring only, no automated check).
* **Re-analysis cadence:** added units on add; the whole list when the CHECKED PAIRS
  change (`ReanalyzeAll(False)` is a no-op otherwise, so showing the tab costs
  nothing), always on Convert -- AFTER `Preflight`, so a refused run never pays the
  analysis -- and after a run (converted ancestors answer differently). The pairs key
  is committed only for a completed pass.
* **E6 offer:** a unit whose chain has units not yet listed asks
  `Add <chain> ahead of <unit>?`. **Insertion (amended 2026-10-05):** each MISSING
  chain unit, topmost first, goes directly before the earliest LISTED unit among the
  later chain units and the descendant (appended when none is listed); listed units
  never move, so a pre-existing misorder stays and E7 still warns about it.
* **Convert order (fix wave M3):** the no-project-file refusal is checked right after
  `Preflight` and BEFORE the C8 re-analysis, gate and E7 -- a run that will be refused
  asks nothing.
* **Convert gate (`InheritanceGate`):** a CANCELLED check stops the Convert
  (`GATE_CANCELLED_TEXT`, nothing runs); a FAILED check asks once
  `Could not check inherited instances for <units> -- convert anyway?` with the
  reason on the status line; No stops with `InheritanceGateStopText`. Never a
  refusal (E9). Covered by model tests only -- the fixture analysis finishes before
  the 400 ms window delay.
* **E7 order warning:** one dialog listing every descendant listed above an
  unconverted ancestor; No runs nothing.
* **Dialog text is mirrored on the status line** (the E6 prompt, the gate question,
  the E7 warning) because a `TMessageForm`'s text is a windowless `TLabel`;
  `drive-inherited-offer.ps1` asserts the status bar.
* **Capability gate:** `inherited_instances`, read with `apply_unit_rules` in ONE
  `CapabilityNames` call in `RefreshBooks`; `TConvertJob.InheritedSupported` comes
  from that probe. Without it: `EngineRefusalNotes` says the engine will refuse each
  Known unit with a .dfm verdict (code uses do not count -- the engine does not
  refuse on code), and the refusal path is unchanged. With it (engine 1.22.0 on,
  pin `1.22.0-alpha-20261006-040048`): the engine converts around inherited instances
  and never refuses for them; a converted row's note (`ConvertedRowNote`) lists
  `N inherited instance(s) left: <words>` (`InheritedLeftNote`) and the report adds
  one 8-column `inherited left` line per instance (`InheritedReportLines`,
  `<name>: <type> line N -- <words> (<reason>)`, the reason left out when the words
  carry it). The words per `ancestor_state`:

  | state | words |
  |---|---|
  | `unconverted` | `ancestor <U> not converted` |
  | `converted` | `ancestor <U> converted -- retype pending (engine N2)` -- N1 still SKIPS it; the descendant's .dfm stays byte-unchanged |
  | `mismatched` | `ancestor <U> has <Found> (neither <From> nor <To>)`, read from the engine's reason `declared in <U> as <Found>, neither <From> nor <To> -- ...`; any other reason shape gives `ancestor <U> has another type -- <reason>` |
  | `outside` | `ancestor not determinable -- <reason>` (the engine sends `ancestor_unit` ""; a missing / binary ancestor .dfm lands here with the file named) |
  | anything else | `ancestor <U>: <state>` |

  Grouping is by the words, i.e. (state, unit) plus the type found / the reason.
  A .dfm holding ONLY inherited instances answers `component_part:
  "skipped-no-instances"`, ok, exit 0: a CONVERTED row with `; no component of its own
  to convert` (`TApplyRow.ComponentPart`; `runner.inherited.skipped.no.instances`). Its
  `.BCK<N>` is kept like any converted row's, although nothing changed. The editor's
  own pre-run analysis keeps treating an unreadable / binary IN-INDEX ancestor .dfm as
  unknown (status line); the engine's post-run `outside` reports it per instance.
* **R4 -- an ancestor converted EARLIER IN THE SAME RUN is not "left" -- in the
  editor-side code-use note ONLY** (`UnitsConvertedIn`). The code-use note
  (`N inherited code use(s) left: ...`, `CodeUseLeftNote`) appears ONCE per unit
  (`CodeUseNoteDue`), not once per book. **The engine's own `inherited[]` is shown
  UNFILTERED** in the converted row's note and in the report's `inherited left` lines
  (controller ruling, fix wave M4): the engine answers after the runner's reindex and
  is authoritative. `InheritedLeftOmitting` was deleted with that ruling; guards
  `tab.r4.runner.engine.unfiltered`, `tab.report.lines.engine.unfiltered`,
  `tab.r4.left.engine.all`.
* **Not built:** E4 (the index's inherited/inline `modifiers` flag) -- the .dfm text
  read is the only source. The E11 live test `inherited.live` RUNS on the 1.22.0 pin
  (6 checks; it SKIPs on an engine without `inherited_instances`). Its Task 6
  expectation (descendant retyped) was a guess; a real run showed N1 leaves the
  descendant's `inherited Label1: TLabel` byte-unchanged and reports it `converted`,
  so the test now asserts that (Task 8).
* **Deferred minors (ledger):** a multi-file drop of N descendants of one unlisted
  base prompts once per descendant on No (no "No to all"); the Convert gate's Yes /
  No has no GUI check; `drive-inherited-offer.ps1` still has a fixed 2 s sleep after
  an answer.