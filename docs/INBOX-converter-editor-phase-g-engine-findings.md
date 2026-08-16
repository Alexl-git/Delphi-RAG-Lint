> # 2026-08-16 (session 22): the one concrete ask is DONE. The note stays open.
>
> **Done:** `convert-validate` no longer rejects `#mapping` / `#apply`. They are
> recognised and SKIPPED -- accepted as well-formed, no rule emitted, no error.
> The original repro in section 1 now prints `OK` / exit 0 instead of four
> `unknown directive` lines, so a rule book carrying them saves cleanly.
>
> Deliberately NO evaluation semantics: emitting a rule kind would invite
> `convert-apply` to act on a mapping it cannot correctly evaluate. G6.1
> (conditional per-instance application) remains untouched and unimplemented.
>
> `DRagLint.Convert.Rules.pas`; assertions added to
> `tests\autotest\run_convert_rules.ps1`, where the pre-existing `#frobnicate`
> check is the positive control -- it still exits 1, so unknown-directive
> detection was narrowed, not switched off.
>
> **Still open in this note:** findings 2.4-2.11 (2.1/2.2/2.3 were already fixed
> and are acknowledged in the revision log above). 2.11 (strong type aliases
> `T = type X` never indexed) is called out as HIGH and as the same defect class
> as the already-fixed 2.1, so it is the obvious next one. The status line below
> ("NOT pushed, NOT merged, NOT deployed. Deliberate.") describes the CONVERTER
> WORKSTREAM's own branch and is unaffected by any of this.

# INBOX -- Converter editor Phase G: what shipped, and 8 engine/index findings

**From:** converter-editor workstream (Claude session, 2026-08-01 -> 2026-08-02)
**To:** drag-lint engine team (currently on `feat/autodoc-phase3`)
**Branch:** `merge/converter-into-main`, head `fb53ae1`, **21 commits ahead of `main` (5d5bee1)**
**Worktree:** `C:\TEMP\claude\c--Projects-Delphi-RAG-lint\wt-merge-converter`
**Status:** NOT pushed, NOT merged, NOT deployed. Deliberate.

> **REVISION LOG -- this file has been APPENDED TO since you first read it.** You flagged that
> it grew mid-session; sorry, that was us. From now on every addition is dated here so you can
> see at a glance what is new without re-reading the whole thing.
>
> | Added | Sections | Note |
> |---|---|---|
> | 2026-08-02 (initial) | 1, 2.1 - 2.8, 3, 4, 5 | first delivery |
> | 2026-08-02 (later) | **2.9**, **2.10** | `--refs-as-leaves` not pruning; `--name` case-sensitivity |
> | 2026-08-02 (latest) | **2.11** | strong type aliases (`T = type X`) never indexed |
>
> Already FIXED by you and gratefully received: **2.2** (context bundle omitted the routine's
> own body) and **2.3** (stale incremental skip), cherry-picked as `13e7fb0`; and **2.1**
> (procedural/method-pointer types never indexed) as `41973bd`. **2.11 below is the same shape
> as 2.1** -- a declaration form the grammar parses but no emitter claims -- so it may well be a
> near-identical fix in the same place.

Nothing in here needs action from you before we merge. It is a record of what the editor now
emits, plus every place the index or CLI did not answer a question it should have. All eight
findings are also one line each in `stats\draglint-gaps.log`.

---

## 1. What Phase G shipped (editor side only -- engine untouched)

Ten tasks, all reviewed. Console suite **376 -> 572 pass, 0 fail / 0 skip** throughout.

- Pure theme model + IDE-following theming (reads `HKCU\Software\Embarcadero\BDS\<ver>\Theme`).
- 19 of 22 loose buttons consolidated into one gated toolbar.
- **Go to definition**: right-click a type cell -> jump in a running RAD Studio over
  `\\.\pipe\drag-lint-open-source`. Verified end-to-end against a live IDE on 2026-08-02.
- **New DSL: `#mapping` / `#apply`** -- a reusable, conditional enum-to-property mapping,
  declared once and narrowed to a source enum plus one or more target classes.
- Pure validation for it (`ConvRules.Mappings.pas`) + a mapping editor UI.
- Examine now harvests `uses` clauses into the Unit Rules FROM list.
- The two Embarcadero reFind instruction files imported as **product rule books** under a new
  top-level `convrules\` directory (`sample.rules` moved there too).

### The one thing that concerns the engine

**`convert-apply` cannot apply `#mapping` / `#apply`.** This is by design for this phase and is
recorded in the spec's G6.1 -- the editor authors rules the engine does not yet evaluate. It
needs conditional, per-instance evaluation. **Please do not file it as a bug.** The DSL forms:

```
#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton, cxButtons.TcxBigButton
#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk
#mapping XYZStyle #else -> ModalResult = mrNone
#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton
  #apply XYZStyle
```

The model stays **flat** -- one node per physical line, no clause tree. `#apply` is NOT `#use`.

#### ...and one concrete ask that IS worth your time (found 2026-08-02, after the note above)

`convert-validate` does not merely ignore the new directives -- it **rejects them**:

```
Validate: line 1: unknown directive: #mapping
(exit code 1)
```

Measured. The consequence is user-visible: **every save of a rule book containing a `#mapping`
or `#apply` now surfaces a validation error in the editor**, even though the book is
well-formed by the editor's own parser and round-trips byte-exactly.

That is worse than the deferral we agreed to. "The engine cannot yet APPLY `#mapping`" is fine
and expected; "the engine reports the file as invalid" makes the feature look broken.

**Minimal ask, no evaluation semantics required:** teach the engine's rule parser to *recognise
and skip* `#mapping` and `#apply` -- accept them as well-formed, do nothing with them, do not
error. That decouples authoring from application and lets the two halves ship independently.
Full conditional per-instance evaluation remains the larger, later piece (G6.1).

Related, minor: `ConvRules.Model.pas:5`'s header points readers at `docs\CONVERSION-RULES.md`,
which is the engine-side document and does not cover `#mapping`/`#apply`. Our new
`docs\converter\convrules-dsl.md` is now the reference for the editor-side DSL; the two should
probably cross-link once the engine recognises the directives.

### Deployment trap, if you ever ship these together

`ConvRulesEditor.exe` and `drag-lint.exe` **must deploy as a PAIR**. The editor passes
`--refs-as-leaves`; an older engine treats it as FATAL. Shipping the editor alone is worse
than the bug it fixes.

---

## 2. Engine / index findings

Severity is our read; re-triage freely.

### 2.1 Method-pointer / procedural types are not indexed at all -- HIGH
Already filed separately as `INBOX-procedural-types-not-indexed.md`; repeating the headline so
this note is self-contained. `TNotifyEvent`, `TMouseEvent`, `TKeyPressEvent`, `TThreadMethod`,
`TGetStrProc` all return **0 rows**, while plain aliases (`TColor`, `kind=type`) index fine.
`System.Classes.pas` IS indexed -- `TAlignment` at line 176 of the same file resolves. So
`X = procedure(...) of object;` declarations appear not to be extracted.
Consequence for us: "Go to definition" on any event property (`OnClick`) cannot work; the
editor now says so rather than jumping somewhere wrong.

### 2.2 `context --task` omits the target's own implementation body -- HIGH (renderer bug)
Two independent hits, and the second narrows the diagnosis usefully:
- `context --task "modify ConvRules.Model.TRuleBook.ParseLine"` returned only the interface /
  unit-header slice. The reviewer needed the body (the classification logic) and fell back to
  Grep+Read.
- `context --task "modify ConvRules.MainForm.TConvRulesForm.DoExamine"` -- same, and we checked
  the DB: **`impl_start_line=1708` / `impl_end_line=1792` ARE present.**

So this is a **renderer bug, not an extractor gap** -- the data is there and the bundle does not
emit it. Worth fixing: the docs promise "doc + class surface + the target's own body + capped
callers", and the body is usually the whole reason for asking. It is the single change that
would most improve context-bundle usefulness for us.

### 2.3 Incremental `index <dir>` reports `skipped N up-to-date` for content it does not have -- HIGH
Twice, on different days:
- `query --name TestMappingRules` -> 0 matches for a procedure that exists at
  `ConvRulesModelTests.dpr:2810`. `index <dir> --db` printed `skipped 16 up-to-date` and did not
  refresh. Only `touch`-ing the file forced a reparse. The mtime skip was holding a pre-Task-5
  snapshot -- symbols past ~line 2700 simply absent.
- `query find-callers --name GetProptree` -> 2 call sites; the true answer was **8** (2 in the
  form + 6 in the test `.dpr`). The 6 appeared only after a forced reindex.

**Why this one is nastier than it looks:** a stale 0-match is indistinguishable from "this symbol
does not exist". It does not fail, it answers confidently and wrongly, which silently undermines
every index-first lookup. Our standing mitigation is now "after any reindex, query for a symbol
you just added and confirm it comes back" -- but that is a workaround, not a fix. Likely
mtime-tick granularity (a write landing inside the same tick as the previous index).

### 2.4 `query --name` is a substring match with no exact/anchored option -- MEDIUM
`--name TNotifyEvent` returns local variables named `ANotifyEvent`. Every caller must therefore
filter to an exact `name` match itself, and "take the first hit" is always wrong. We now do the
filtering client-side. An `--exact` flag would remove a whole class of caller bug.

Related: **`--name` rejects a qualified name.** `--name Abcbtn.TabcButtonStyle` -> `[]`, exit 1.
Callers must pass the bare identifier and qualify at selection time.

### 2.5 Ties are resolved by row order, and the order is not contractual -- MEDIUM
`--name TAlignment` returns **three** rows all equally type-like: `System.Classes.TAlignment`
(enum), `dxRichEdit.Dialogs.TableStyle.TdxRichEditTableStyleDialogForm.TAlignment` (record),
`dxSplashForms.TdxSplashFormBase.TAlignment` (enum). All `section=interface`,
`usable_from_other_units=true` -- so nothing in the row distinguishes them. The right answer wins
only because `System.Classes` happened to be indexed first.

Worse in practice, measured against `library-Win64.sqlite`:
`TEdit` -> `FMX.Edit.TEdit`, `TButton` -> `FMX.StdCtrls.TButton`, `TLabel` -> `FMX.StdCtrls.TLabel`
(and ~32 further names). **A VCL tool asking for a bare class name gets the FMX declaration.**

We now report the tie to the user ("2 classes carry that name; used FMX.Edit.TEdit") rather than
picking silently, and deliberately did **not** invent a VCL-over-FMX preference -- that is a
product decision, and arguably one the engine is better placed to express (a platform/framework
hint on the query, or a documented deterministic ordering).

### 2.6 Enum members are indexed but not reachable by any query -- MEDIUM
An enum is `kind="enum"` and carries **no `members` field**. Members ARE indexed, as separate
symbols: `kind="enum_value"`, `qualified_name = "<EnumQName>.<member>"` (e.g.
`System.Classes.TAlignment.taLeftJustify`). But there is no way to ask for them:
- `query --qname <Enum>` returns only the enum itself.
- `surface --qname <Enum>` refuses: "requires a class, record, or interface".
- `hover --qname <Enum>` does not list them.

We work around it by reading the enum's declaration source range (`file` + `start_line`..`end_line`)
and parsing the parenthesised identifier list. That works, but it means a consumer must read
source to get data the index already holds. A `--children` / prefix query, or `surface` accepting
an enum, would remove the workaround.

### 2.7 An ad-hoc `index <dir> --db <db>` DB has no FTS5 text tables -- LOW (or a docs gap)
`query --text "<anything>"` against a DB we built with `drag-lint index <dir> --db <new.sqlite>`
returns 0 matches for every substring, though `FTS5 probe: AVAILABLE` is printed at index time.
Either the text tables are only built through the manifest path, or the ad-hoc path should say so.
Minor for us -- we fell back to Grep for one property-assignment check -- but it makes `--text`
quietly useless on any DB not built via `drag-lint.json`.

### 2.8 Two CLI contract details worth documenting -- LOW
Neither is a bug; both cost us time to discover, and both would bite the next consumer.
- **Zero hits => stdout `[]` and process EXIT CODE 1.** Success is 0. Exit 1 means "no hits", not
  failure. A naive caller reports a spurious engine error for an unindexed symbol.
- **`(loaded defaults from ...)` goes to STDERR**, and stdout alone is clean parseable JSON.
  Any consumer that merges the streams (e.g. `SI.hStdError := WritePipe`, or PowerShell `2>&1`)
  corrupts the JSON. It bit us twice while measuring, and our editor's `RunCapture` does merge
  them -- we work around it by slicing the array with a balanced-bracket scan rather than
  changing the capture. A `--quiet` flag, or moving the banner behind a verbosity switch, would
  be kinder than documenting it.

Output shape, for the record, since our plan's fixtures had guessed it wrong in every particular:
a **bare top-level JSON array** (no `{"results": ...}` wrapper), objects carrying
`id, kind, name, qualified_name, signature, modifiers, section, usable_from_other_units,
file_id, file, start_line, start_col, end_line, end_col, impl_start_line, impl_end_line`.
The line field is **`start_line`**, not `line`.

---

### 2.9 `--refs-as-leaves` does not prune component-reference roots -- HIGH (new, 2026-08-02)

Found while assembling a real BDE -> FireDAC conversion library from the corpus.

`drag-lint proptree --min-visibility published --refs-as-leaves` against
`library-Win64.sqlite` for `FireDAC.Comp.Client.TFDUpdateSQL` returns **364 leaves, of which
354 are phantom** -- the walk descends into component-typed references that the flag exists
precisely to stop at. **7 reference roots were not pruned.**

Repro:
```
drag-lint proptree --qname FireDAC.Comp.Client.TFDUpdateSQL ^
  --min-visibility published --refs-as-leaves --db C:\Projects\.drag-lint\library-Win64.sqlite
```
Expected: component-typed properties appear as LEAVES, not as sub-trees.
Actual: 7 of them expand, contributing ~354 spurious leaves.

Why it matters beyond noise: the editor's Auto-Match pairs a source leaf against target leaves,
so a 36x inflated target surface is 36x more chances to mis-pair. We worked around it by pruning
the phantom roots from the input before matching (the match rule itself was left untouched), so
the shipped library is clean -- but any other consumer calling `proptree --refs-as-leaves` and
trusting the result is being handed mostly noise.

This is the same flag whose ABSENCE was fatal in the 2026-07-30 deploy trap. It is parsed and
accepted; it just does not fully do what it says.

### 2.10 `query --name` is CASE-SENSITIVE, and silently so -- MEDIUM (new, 2026-08-02)

```
drag-lint query --name TFDRDBMSDataSet --db library-Win64.sqlite   ->  []   (exit 1)
drag-lint query --name Rdbms           --db library-Win64.sqlite   ->  finds it
```
The real declared name is `TFDRdbmsDataSet`. Because zero hits returns `[]` and exit 1 -- which
also means "no such symbol" -- a caller who types the name in the wrong case gets a confident,
indistinguishable "does not exist". We hit this on a type we knew for a fact was indexed.

Related and previously logged: the row SET also varies with case
(`TEdit` -> 2 rows, `tEdit` -> 2 *different* rows, `tedit` -> 10 rows), so this is not simply
"exact match, case-sensitive" -- the matching semantics themselves shift.

Ask: make `--name` case-insensitive, or add an explicit `--exact`/`--ignore-case` pair and say
which is the default. Either is fine; the current behaviour is the one that cannot be relied on.

### 2.11 Strong type aliases (`T = type <ExistingType>`) are never indexed -- HIGH (new, 2026-08-02)

**Almost certainly the same defect class as 2.1**, which you have just fixed: the grammar parses
the declaration, no emitter handler claims it, so no symbol row is written.

Measured against `library-Win64.sqlite` -- "is there a DECLARATION row for this name?":

| Type | Declared as | Decl row? |
|---|---|---|
| `TFileName` | `type string` | **NONE** |
| `TCaption` | `type string` | **NONE** |
| `TDate` | `type TDateTime` | **NONE** |
| `TTime` | `type TDateTime` | **NONE** (only an unrelated `property` row) |
| `TColor` | subrange | `type` -- fine |
| `TCursor` | subrange | `type` -- fine |
| `TAlignment` | enum | `enum` -- fine |

So the trigger is precisely the **`type` keyword in the declaration** -- the strong / distinct
alias form. Subranges, enums and plain aliases all index correctly.

The index is not wholly blind to these names: they appear inside *other* symbols' signatures
(e.g. `Abcbtn.TabcWaveFileBtn.FileName : TFileName`). There is simply no row that says what
`TFileName` *is*.

**Why it matters to us, concretely.** The converter's Auto-Match pairs a source property with a
target property only when it can prove the assignment is legal. `Bde.DBTables.TTable.TableName`
is `TFileName`; `FireDAC.Comp.Client.TFDTable.TableName` is `String`. Same name, top-level on
both sides, and in Delphi the assignment is perfectly legal -- `TFileName` IS a string. But
because there is no declaration row, the engine cannot know that, cannot prove the cast, and
declines the match. A human then has to hand-write a `#link` for a pair that should have been
automatic.

This is not one property. Every RTL/VCL `type string` and `type Integer` alias silently blocks an
otherwise-obvious match, everywhere, for every consumer doing type-aware work.

Repro:
```
drag-lint query --name TFileName --db C:\Projects\.drag-lint\library-Win64.sqlite
```
Expected: one row, `kind=type`, for `System.SysUtils.TFileName`.
Actual: `[]`, exit 1 -- "no exact match", offering properties merely *typed* `TFileName`.

(Checked under `TFileName` / `TFilename` / `tfilename`, so this is not 2.10's case-sensitivity.)

## 3. Suggested priority, if you want one

1. **2.2** (`context` omits the body) -- data is already in the DB; biggest usefulness win.
2. **2.3** (stale skip answering confidently and wrongly) -- correctness of every index-first lookup.
3. **2.1** (procedural types unindexed) -- already filed; blocks event-property navigation.
4. **2.5 / 2.4** (tie ordering + no `--exact`) -- both are "the API invites a caller bug".
5. **2.6, 2.7, 2.8** -- convenience and documentation.

## 4. Where to look

- Full decision log for the whole plan, incl. every human ruling:
  `<worktree>\.superpowers\sdd\2026-07-30-converter-editor-phase-g\progress.md`
- Corpus conformance and what it is *actually* worth (9 lines of 69):
  `docs\converter\refind-corpus.md`
- Reconciled spec: `docs\superpowers\specs\2026-07-30-converter-editor-phase-g-design.md`
- Raw gap lines: `stats\draglint-gaps.log` (9 entries); wins: `stats\draglint-usage.log`

## 5. Unrelated defect found in our own build scripts, flagged in case you inherit the pattern

`build\_build_convrules_editor.bat` and `_build_convrules_tests.bat` hard-coded
`C:\Projects\Delphi-RAG-lint\...` for **both** the `cd` and the staging destination. Run from a
worktree they built and staged the **main checkout** while printing `BUILD_EXITCODE=0` -- green
evidence for code that was never compiled. Now fixed to forward to the `%~dp0`-relative `_local`
twins, and the previously-ungated `RC_EXITCODE` is checked. If any engine-side `.bat` shares that
shape, it has the same trap.
