# Design: Converter Editor -- Unit-Replacement Rules (Milestone 1)

Date: 2026-07-20. Status: **approved, pre-implementation.**
Project name (working): **converter editor**.
Branch: `feat/converter-editor` (isolated worktree at `C:\Projects\Delphi-RAG-lint-converter`).

> All design/state MD for this project lives under `docs/converter/` to stay clear
> of a second Opus working concurrently on drag-lint `main`.

## 1. Purpose & context

The **converter editor** (`ConvRulesEditor.exe`, `src/tools/convrules-editor/`) is
a standalone plain-VCL front-end that **authors/edits `conversion.rules` DSL files**.
It does not itself convert -- the engine (`convert-apply`) consumes the rules. The
long-term vision, in the user's phasing:

1. **(this milestone) Finish the editor** so it can author a *complete, growing
   library* of conversion rules -- covering component conversion **and unit
   replacement**.
2. **(later) The actual replacement** -- extend the apply engine to execute the new
   rules.
3. **(throughout) AI exposure** -- the `.rules` files are already a **token-free
   mechanism**: an AI agent reuses/curates rulebooks as files instead of hand-
   reasoning each conversion. Discovery/apply-by-name is formalized in a later phase.

### Workflow decision (user)
- **Library-first, then form-driven.** Build the reusable-rulebook authoring path
  first (From/To type pickers already exist; the gap is *complete* authoring,
  especially unit replacement). The form-driven DFM-inventory flow layers on after.
- **Single growing `.rules` file for now.** Split into per-rulebook files later only
  if navigation/apply gets slow. Blocks are kept self-contained so a later split is
  mechanical. (Apply cost does not scale with library size -- the engine matches only
  the `#convert` blocks whose component classes actually appear in the target form.)

## 2. Scope

**In scope (Milestone 1):**
- First-class **unit-replacement rules**: standalone, one-to-many, hand-authored
  and auto-derived (new DSL directives `#use` / `#useswap`).
- **Auto-derive** unit changes from `#convert` blocks (resolve declaring units), with
  library-wide **dedup** ("no doubles").
- A structured **Unit Rules** editor surface (today unit directives are raw-text only).
- **Search/filter** on the rules-library list (growing-file navigation).
- Extend validation so Save stays green with the new directives.

**Deferred (explicit):**
- The **apply engine** executing `#use`/`#useswap` -> Phase 2 ("the actual replacement").
- **DFM inventory** / form-driven flow -> layers on after library-first.
- **Value/enum property casts** (the old "Feature B") -> out unless pulled in.
- **AI apply-by-name / library discovery** wiring -> later phase.
- Structured tabs for `#default` / `#ignore` / `#remove` -> keep using the Raw DSL
  tab for now (not requested for this milestone).

## 3. The DSL extension

Two new directives; `#useswap` is human-facing sugar over the atomic `#use`/`#unuse`.

| Directive | Meaning |
|---|---|
| `#use <unit>` | Ensure `<unit>` is in the target `.pas` `uses` clause (add if absent; idempotent). The missing companion to the existing `#unuse <unit>` (remove). |
| `#useswap <Old> -> <New1>[, <New2> ...]` | Replace `<Old>` with one-or-more `<New>` units. Canonically **equivalent to** `#unuse Old` + `#use New1` + `#use New2` ... |

### 3.1 Normalization -- the single "no doubles" rule
Used by both the editor's checks and (later) the apply engine:

- **ADD set** = union of every `#use`, every `#useswap` right-side, **and** every
  `#convert`'s trailing `, unit` uses-add.
- **REMOVE set** = union of every `#unuse` and every `#useswap` left-side.
- Apply = add each ADD unit **only if not already present** (dedup); remove each
  REMOVE unit **only if no surviving type still needs it**. A unit in **both** sets
  -> **ADD wins** (something introduced still needs it), flagged for the user.

Unit directives are **file-level** (outside any `#convert` block), so a pure swap
(`#useswap FOLDERDEF -> imcFOLDERS`) stands alone and persists independent of any
component rule.

**Two evaluation times, one rule.** "Already present" / "still needed" are resolved
against the *target unit's actual `uses` clause* at **apply time (Phase 2)**. In
**Phase 1 the editor** applies the same normalization to the *rulebook itself* --
collapsing duplicate `#use`/`#unuse`/`#useswap` directives and flagging ADD/REMOVE
conflicts -- so what it authors is already dedup-clean before any file is touched.

### 3.2 Auto-derive
"Derive units from conversions" scans every `#convert F -> T`:
- each distinct **To**-type -> resolve declaring unit (`ResolveClassQName`) ->
  emit `#use <unit>`;
- each distinct **From**-type -> resolve unit -> candidate `#unuse <unit>`.

The derived set is deduped against what is already present. Auto-derive emits the
**atomic** `#use`/`#unuse` (a real Orpheus->DevEx batch adds N and drops M units,
rarely 1:1); the user hand-authors the **`#useswap`** form when thinking in swaps. A
To-type that does not resolve is **skipped with a note** in the summary (never
fabricated).

### 3.3 Engine-parser recognition (the one core-file touch)
Verified at branch base `cf372f8`: `ParseConversionRules`
(`src/report/DRagLint.Convert.Rules.pas`) records an unrecognized `#word` as a
ParseError, and `ValidateConversionRules` folds ParseErrors into its error output --
so `convert-validate` on a file containing `#use`/`#useswap` prints
`unknown directive: #use` and exits 1, turning the editor's Save-validate red.

Fix: add `rkUse`/`rkUseSwap` rule kinds + two parse arms + a grammar doc-comment
line. **No validation checks** -- they join the `rkUnuse`/`rkRemove`/`rkMigrate`
no-check family (those carry no index-checkable paths). ~10 additive lines; no
behavior change to any existing directive.

### 3.4 Example library fragment
```
; --- unit rules (hand-authored) ---
#useswap FOLDERDEF -> imcFOLDERS
#useswap ovcTable   -> cxGrid, cxGridDBTableView

; --- a component conversion + its auto-derived units ---
#convert Abcbtn.TabcToggleBtn -> cxButtons.TcxButton
#link Down <- Down
#use   cxButtons        ; auto-derived: TcxButton is declared in cxButtons
#unuse Abcbtn           ; auto-derived: TabcToggleBtn's old unit
```

## 4. Editor UX

**New "Unit Rules" tab** in the left PageControl, beside *Rules Library* and *Raw
DSL*. Shows **every** unit directive (`#useswap`/`#use`/`#unuse`) gathered into one
list regardless of physical position in the file. Columns: **Kind, Old, New(s),
Source** (hand vs derived), and a **flag** column for duplicates/conflicts.

**Authoring controls:**
- **`+ Swap`** -> `#useswap Old -> New1[, New2 ...]`: editable *Old* combo + comma-
  list *New* field. Both are combos with autocomplete from project units + units
  already in the book; free text always allowed; `ResolveUnitFile` validates
  (unresolved = yellow warning, still allowed).
- **`+ Add unit`** (`#use`) and **`+ Remove unit`** (`#unuse`) for the atomic cases.
- **Edit / Delete** on the selected row. Every edit writes through `TRuleBook`
  (model is the single source of truth).

**`Derive units from conversions`** -> runs auto-derive (3.2). Derived lines are
inserted **immediately after their originating `#convert` block** (traceable). A
status summary reports e.g. *"added 3 #use, 4 #unuse; 2 duplicates skipped."*

**`Check units`** (also auto-run on Save) -> computes the normalized ADD/REMOVE sets
(3.1) and reports: duplicates collapsed, **conflicts** (a unit in both sets -> ADD
wins, flagged), and unresolved units. This is the visible "no doubles" guarantee.

**Growing-file navigation:** a **filter box** above the *Rules Library* list (type
"ovc" -> only matching `#convert` rows).

**On-disk layout at Save:** hand-authored `#useswap` swaps grouped in a top section
under a `; --- unit rules ---` comment; auto-derived `#use`/`#unuse` stay adjacent to
their `#convert` block. The Unit Rules tab shows them unified either way.

## 5. Architecture

Most logic lives in pure/testable units; the UI holds no truth.

1. **New pure unit `ConvRules.Units.pas`** -- no UI/engine deps:
   - normalized ADD/REMOVE-set computation (3.1): dedup, conflict (ADD wins),
     `#useswap` decomposition;
   - **pure auto-derive**: given `(FromType, ToType)` pairs **plus a resolver
     callback** `TypeName -> unit`, returns the add/remove sets. Unit-testable with a
     stub resolver -- no engine/UI needed.
2. **Model `ConvRules.Model.pas`** -- add `rnkUse` + `rnkUseSwap` to
   `TRuleNodeKind`; fields (`UseUnit`; `SwapOld` + `SwapNew: TArray<string>`);
   `ParseLine` arms + `Emit` cases (canonical, ASCII/CRLF); a `UnitNodes` gatherer
   (mirrors `ConvertHeaders`). Loss-less round-trip preserved.
3. **Engine adapter `ConvRules.Engine.pas`** -- add thin
   `DeclaringUnitOf(typeName): string` (wraps `ResolveClassQName`, takes the unit
   prefix). Autocomplete source = existing `ListProjectUnits` + units already in the
   book; `ResolveUnitFile` is the validator.
4. **Engine parser `src/report/DRagLint.Convert.Rules.pas`** (only core file) --
   `rkUse`/`rkUseSwap` kinds + two parse arms + grammar doc-comment; no validate
   checks (3.3).
5. **UI `ConvRules.MainForm.pas`** -- build the Unit Rules tab + handlers
   (`DoAddSwap/AddUse/AddUnuse/EditUnit/DeleteUnit/DeriveUnits/CheckUnits/
   RefreshUnitRules`) + the library filter box.
6. **Docs** -- additive grammar rows in `docs/CONVERSION-RULES.md`; design of record
   here in `docs/converter/`.

### Data flow
UI (Unit Rules tab) -> `TRuleBook` model (rnkUse/rnkUseSwap nodes) -> `SaveToString`
-> `.rules` file -> `convert-validate` (engine, now recognizes them) -> OK.
Auto-derive: model `#convert` pairs -> engine `DeclaringUnitOf` -> `ConvRules.Units`
derive -> model nodes.

### Error handling
- Unresolved unit name -> yellow warning, never blocks.
- To-type that will not resolve in auto-derive -> skipped with a note (never
  fabricated).
- Malformed `#useswap` (no `->`, empty side) -> flagged by `Check units`, never
  silently dropped (model keeps it, worst case as `rnkUnknown`).
- `drag-lint.exe`/`convert-validate` unavailable -> existing engine-error path
  (`SetError`), unchanged.

## 6. Testing (TDD)

Extend the in-process console runner `tests/ConvRulesModelTests.dpr` (~109 tests
today; skip-not-fail when a real DB/exe is absent):

- **Model:** `#use` and `#useswap` (1->1 and 1->many) load->emit **byte-faithful**;
  dirty re-emit canonical; existing directives unaffected.
- **`ConvRules.Units`:** ADD/REMOVE computation; dedup; conflict (ADD wins);
  `#useswap` == `#unuse`+`#use`; auto-derive with a stub resolver, incl. multi-
  `#convert` dedup and the "no doubles" guarantee.
- **Engine parser** (`tests/autotest/run_convert_rules.ps1`): `#use`/`#useswap`
  parse clean **and `convert-validate` exits 0** -- proving the Save-validate gate
  stays green.

## 7. Build / deploy

- Baseline first (before any edit): build the editor + run the model tests at
  `cf372f8`, confirm green, so any later failure is unambiguously ours.
- Editor: `build/_build_convrules_editor.bat`; tests:
  `build/_build_convrules_tests.bat`.
- **Rebuild `drag-lint.exe` too** (`build/build_draglint_win64.bat`, redeploy to
  `third_party/dll-win64/`): `convert-validate` lives in the CLI, and the editor
  shells the deployed exe -- an old exe would still reject the new directives.
- All `.pas` stay strict 7-bit ASCII + CRLF (verify after each write).

## 8. Isolation / coordination

- Work happens in the worktree `C:\Projects\Delphi-RAG-lint-converter` on
  `feat/converter-editor` (branched from `main@cf372f8`), so it cannot collide with
  the other Opus on `main`.
- The **only** shared/core file we touch is
  `src/report/DRagLint.Convert.Rules.pas` (additive parser recognition). Low conflict
  risk; reconcile at merge.
- Everything else is under `src/tools/convrules-editor/` and `docs/converter/`.
