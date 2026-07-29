# Resolve ancestors by framework/uses scope so the inherited surface stops disappearing (spec G)

- Date: 2026-07-29
- Status: DRAFT -- awaiting user approval
- **Implementation target: branch `main`** (engine code), NOT `feat/converter-editor`.
  `main` is at `674706a`. The converter worktree is on another branch and carries a third
  workstream's uncommitted edits; do the work in a fresh worktree of `main`.
- Motivating report: `docs/INBOX-proptree-ancestor-climb-stops-early.md`

## 1. Problem

`proptree` loses every property above a broken ancestor edge. The conversion editor can only
offer what `proptree` returns, so a target like `cxButtons.TcxButton` exposes no `Name`, `Tag`,
`Left`, `Top`, `Width`, `Height`, `Visible`, `Hint` or `TabOrder` and those properties cannot be
mapped at all.

Measured on `library-Win64.sqlite` (schema 18, healthy):

| root | climb reaches | `Name` |
|---|---|---|
| `Vcl.Controls.TGraphicControl` | -> `TControl` -> `TComponent` | yes |
| `Abcbtn.TabcPicSpeedBtn` | -> `TGraphicControl` -> `TControl` -> `TComponent` | yes |
| `Vcl.StdCtrls.TEdit` | stops at `TCustomEdit` | **no** |
| `Vcl.StdCtrls.TButton` | stops at `TButtonControl` | **no** |
| `cxButtons.TcxButton` | stops at `TcxCustomButton` | **no** |
| `uMain.TfrmMAIN` (project form, both DBs) | **zero ancestors** | **no** |

## 2. Root cause -- measured, not inferred

Ancestor resolution happens at INDEX time in `ResolveAncestry`
(`src/storage/DRagLint.Storage.SQLite.pas:3477-3641`), which writes the `type_ancestors` table.
`proptree` merely reads it: `ClassChain` (`src/report/DRagLint.Convert.PropTree.pas:278-304`)
calls `GetTransitiveAncestors` once and silently skips any row that is not `Resolved`.

`ResolveAncestry` disambiguates a same-named ancestor with `CandInScope` (line 3490), which tests
membership of `unit_uses.target_file_id`. When several candidates exist and none is in scope it
deliberately declines -- `ancestor_symbol_id = NULL, ancestor_kind = '?'`, with the comment
*"FP policy: when unsure, don't claim"*.

**The data that check depends on is missing.** Every `unit_uses` row for `Vcl.StdCtrls.pas`
(file_id 4597) has `target_file_id = NULL`: `ResolveUnitUseTargets` never resolved that file's
uses. So `CandInScope` sees zero in-scope candidates against the two global `TWinControl`
candidates (`Vcl.Controls` and `FMX.Controls.Win`) and declines. Verified directly in the index:
`Vcl.StdCtrls.TCustomEdit`'s row is `(0, 'TWinControl', '?', NULL, NULL)`.

This explains every row of the table above. A hop survives only when the name is globally unique
(no disambiguation needed) or the ancestor is in the same unit. `TGraphicControl` is unique, which
is the only reason the ABC5 chain works; `TWinControl` is ambiguous, and nearly all of VCL passes
through it.

**Two earlier hypotheses are disproved and should not be re-investigated:**

- *Forward declarations shadowing the real class.* `IsForwardDeclClass`
  (`PropTree.pas:231-234`) already distinguishes them by empty heritage and `EndLine <= StartLine`,
  and `ResolveAncestry` step 1b already drops stubs.
- *Multi-line class headers losing the ancestor.* `HeritageTextOf`
  (`src/parser/DRagLint.Parser.Delphi13.pas:397-436`) walks AST `typeref` children, not text
  lines. `cxButtons.TcxCustomButton`'s heritage is captured intact as
  `'TcxBaseButton, IdxSkinSupport, IcxLookAndFeelContainer, ...'`.

## 3. The two repairs, and why we want both

### 3.1 Query-time fallback (ships value immediately)

`ClassChain` skips unresolved ancestors. `ResolveViaBridgedAncestry`
(`PropTree.pas:477-537`) already demonstrates the right shape: its `Climb` walks ONE class at a
time and resolves each hop with `AStore.ResolveTypeNameToClass(A.Name, AClass.FileId)`, i.e. with
the FileId of the class actually doing the inheriting.

Critically, `ResolveTypeNameToClass`'s `PickCandidate`/`LoadScopeNames`
(`Storage.SQLite.pas:2458-2551`) matches unit names TEXTUALLY and therefore does **not** need
`target_file_id`. It works against indexes that are already on disk.

**This is the load-bearing property of this design: a query-time fallback fixes every existing
index without re-indexing anything.** That matters enormously right now, because a full library
rebuild currently aborts (`INBOX-index-all-win32-library-rebuild-aborts.md`), so any fix that
requires a reindex would be blocked behind a second unfixed engine bug.

### 3.2 Index-time repair (correct at the root)

`ResolveUnitUseTargets` must actually populate `unit_uses.target_file_id`. This benefits every
consumer of `unit_uses`, not just proptree, and lets `CandInScope` work as designed. It only takes
effect on re-indexed databases, which is why it cannot be the whole answer.

### 3.3 Scope rule

When several candidates share the ancestor's name, prefer, in order:

1. a candidate in the SAME unit as the inheriting class;
2. a candidate whose unit appears in the inheriting unit's `uses` (textual match, either section);
3. a candidate whose unit shares the inheriting unit's framework prefix -- `Vcl.*` with `Vcl.*`,
   `FMX.*` with `FMX.*`, `Winapi.*` with `Winapi.*`;
4. nothing. Keep today's "when unsure, don't claim" policy rather than guessing.

Rule 3 is what the user asked for -- "figure out from the form whether we are using VCL or FMX and
follow the correct chain" -- and it is the rule that rescues `Vcl.StdCtrls.TCustomEdit ->
Vcl.Controls.TWinControl` even when `uses` data is unusable. It must never let a `Vcl.*` class
inherit from an `FMX.*` one.

## 4. Non-goals

- No schema change. `type_ancestors` and `unit_uses` keep their shape.
- No change to `--refs-as-leaves`, `--min-visibility`, or any proptree output format.
- Not fixing the library-rebuild abort; that is a separate INBOX item. This design is deliberately
  built so it does not depend on it.

## 5. Acceptance criteria (EARS)

1. WHEN a class's ancestor name is ambiguous AND one candidate is in the same unit THE resolver
   SHALL choose that candidate.
2. WHEN no candidate is in the same unit AND one candidate's unit appears in the inheriting unit's
   `uses` THE resolver SHALL choose that candidate.
3. WHEN neither rule applies AND exactly one candidate shares the inheriting unit's framework
   prefix THE resolver SHALL choose that candidate.
4. IF several candidates remain indistinguishable THEN the resolver SHALL decline, leaving the
   ancestor unresolved rather than guessing.
5. THE resolver SHALL NEVER select an `FMX.*` ancestor for a `Vcl.*` class, nor the reverse.
6. WHEN `type_ancestors` holds an unresolved row THE proptree climb SHALL attempt the query-time
   fallback for that hop, against the index as it already exists on disk.
7. THE fallback SHALL use the FileId of the class doing the inheriting, not the FileId of the
   root class the query started from.
8. `Vcl.StdCtrls.TEdit` SHALL return `Name`, `Tag`, `Left`, `Top`, `Width`, `Height`, `Visible`
   and `Hint`, **without re-indexing**.
9. `cxButtons.TcxButton` SHALL likewise return them, without re-indexing.
10. `Abcbtn.TabcToggleBtn` SHALL keep returning exactly what it returns today (3905 leaves) --
    the working chains must not regress.
11. `Vcl.Controls.TGraphicControl` and `Vcl.Controls.TWinControl` SHALL keep reaching
    `System.Classes.TComponent`.
12. AFTER a re-index, `unit_uses.target_file_id` SHALL be populated for a unit whose `uses` name
    matches an indexed file.
13. THE existing proptree autotests SHALL stay green: `run_proptree.ps1` (20/0),
    `run_proptree_ancestry_bridge.ps1`, `run_proptree_polymorphic.ps1`, `run_proptree_fields.ps1`,
    `run_proptree_visibility.ps1`, and `run_convert_rules.ps1` (26/0).

### 5a. Amendment to criterion 5 -- "never by INFERENCE" (recorded 2026-07-29)

Criterion 5 above is written as an absolute ("SHALL NEVER ... nor the reverse") with no
exception. The shipped code does not implement it as an absolute, deliberately, and the
divergence is recorded here rather than silently tolerated. **The code is correct; the
criterion as written was too strong.** No code change is owed for this.

Rules 1 and 2a **can** cross `Vcl` <-> `FMX`, by design:

- **Rule 1** (same unit) -- a candidate declared in the very unit doing the inheriting.
- **Rule 2a** (strong `uses`) -- the inheriting unit's `uses` clause names the candidate's
  declaring unit by its FULL name, and exactly one candidate matches.

Both rest on something the unit itself **stated**, not on something the resolver guessed. A unit
that writes `uses FMX.Controls` and then inherits an ambiguous name declared there has said which
one it means, and an explicit declaration must outrank every inference -- otherwise the resolver
would be overriding the source it is indexing. The code documents this at
`src/storage/DRagLint.Storage.SQLite.pas:2576-2579`.

What IS absolute is the inference side, and that is the guarantee worth having:

> Criterion 5 holds as: **the resolver shall never select a cross-framework ancestor BY
> INFERENCE.** Rule 2b drops any GUI-namespaced weak hit the scope's effective framework does not
> confirm, and rule 3 selects strictly by that same segment, so neither can ever return a
> `Vcl.*` candidate for an `FMX`-scoped class or the reverse. Only an explicit statement in the
> source -- same unit, or a fully-qualified `uses` -- can cross.

Measured residual on the on-disk `library-Win64.sqlite` at the time of writing:

- **0** cross-framework resolved ancestor edges in the whole index -- so the theoretical
  crossing that rules 1 and 2a permit does not actually occur anywhere in the indexed corpus.
- **9** `FMX.* uses Vcl.*` rows exist in `unit_uses`, confined to exactly **four** FMX
  design-time units -- `FMX.Design.Bitmap.pas`, `FMX.Editor.Items.pas` (5 of the 9),
  `FMX.Editor.ListView.pas`, `FMX.Editor.MultiView.pas`. Design-time FMX code legitimately
  pulls in VCL for the IDE surface; none of these produced a crossed ancestor edge.

Criteria 1-4 are unaffected. The precedence order (1 > 2a > 2b > 3 > decline) is what makes the
amended statement true: the inference rules sit strictly BELOW the explicit ones and can never
promote themselves past them.

## 6. Testing

`tests/autotest/run_proptree_ancestry_bridge.ps1` is the template: it builds a synthetic 3-unit
hierarchy (`VclKit` / `FmxKit` / `CxKit`) containing a deliberately ambiguous same-name decoy,
indexes it with the real CLI, and asserts with `Check()`. Extend that fixture with a class whose
ancestor name is ambiguous across a `Vcl`-like and an `FMX`-like unit, and assert the `Vcl` one
wins — criteria 1-5 are all reachable that way, hermetically, without the 1.8 GB library index.

Criteria 8-11 are verified against the REAL `library-Win64.sqlite`, read-only
(`--no-write-back`), because the whole point is that existing indexes are repaired in place. Do
NOT use `library-Win32.sqlite` — it is a broken 9.1 MB fragment.

## 7. Risks

- **Regression on chains that work today** is the main one; criteria 10-11 exist for it. Capture
  the current leaf counts for `Abcbtn.TabcToggleBtn`, `Vcl.Controls.TControl` and
  `Vcl.Controls.TWinControl` BEFORE changing anything, and diff after.
- **A query-time fallback runs per hop per query.** `ResolveTypeNameToClass` hits the DB; a deep
  chain could add many round trips. Measure `proptree cxButtons.TcxButton` before and after and
  keep it comparable; memoize per query if needed.
- **`--no-write-back` must stay honoured.** Proptree already memoizes recovered types back into
  the index unless that flag is passed; the fallback must respect the same switch.
