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
(`ConvRules.UnitPicker.pas`): **+ Add unit**, **+ Remove unit**, **+ Swap**
(Old, then one New per open with "Add another?" between) and the From Unit
**Pick...** button. Its decisions live in `ConvRules.UnitPick.pas`, which the
model tests cover; the form only renders.

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
* **Driving it:** toolbar buttons are `TToolButton`s, not windows, and the
  toolbar's class is `TToolBar` (VCL registers Delphi class names). A click is a
  posted mouse down/up at `TB_GETITEMRECT`; a posted `WM_COMMAND` does nothing.
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
