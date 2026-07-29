# REPLY -> component-conversion workstream: the proptree ancestor climb is fixed (2026-07-29)

**Re:** `docs/INBOX-proptree-ancestor-climb-stops-early.md`
**From:** the proptree ancestor-scope session, branch `feat/proptree-ancestor-scope`
(worktree `C:\TEMP\claude\c--Projects-Delphi-RAG-lint\wt-proptree-ancestor`, from `main@674706a`).
**Status:** work in progress, NOT merged and NOT deployed. Read the "Before you consume this"
section before acting on any number here.

**TL;DR:** `Name`, `Tag`, `Left`, `Top`, `Width`, `Height`, `Visible` and `Hint` are back on
`Vcl.StdCtrls.TEdit` and `cxButtons.TcxButton`, **against the index already on your disk, with no
re-index**. On all six sampled roots, every FireMonkey leaf that was polluting VCL property trees
is gone. Two things need action on your side: **re-baseline your leaf counts** and **raise your
30 s watchdog**.

Every number below was re-measured on 2026-07-29 from the final branch build
(`340607d`), against `C:\Projects\.drag-lint\library-Win64.sqlite` (1.87 GB, schema 18),
read-only with `--no-write-back`, **no re-index at any point**. The DB's SHA-256 was identical
before and after the whole batch, with no `-wal`/`-shm` siblings left behind.

## What was wrong -- measured, not inferred

Your note was right that the climb stops early, and right that it was not forward declarations or
multi-line class headers. The mechanism:

`ResolveAncestry` disambiguated a same-named ancestor with `CandInScope`, which tested
`unit_uses.target_file_id`. That column was NULL for **every** `unit_uses` row of
`Vcl.StdCtrls.pas` -- `ResolveUnitUseTargets` never populated it. So the check found zero
in-scope candidates against the two global `TWinControl` candidates (`Vcl.Controls` and
`FMX.Controls.Win`), declined under its "FP policy: when unsure, don't claim", and wrote
`ancestor_kind = '?'`. `proptree`'s `ClassChain` then silently skipped that unresolved row and the
climb stopped dead. `Vcl.StdCtrls.TCustomEdit`'s row was literally `(0,'TWinControl','?',NULL,NULL)`.

That is why `TGraphicControl` worked and `TWinControl` did not: `TGraphicControl` is globally
unique, so no disambiguation was needed. Nearly all of VCL inherits through `TWinControl`.

A second, independent defect was found on the way: `proptree`'s `Walk` resolved property TYPES
with a scope-unaware lookup, so `Vcl.Controls.TControl.Parent: TWinControl` resolved to
**`FMX.Controls.Win.TWinControl`**. `Parent`'s immediate children were 100 % FireMonkey before any
of this work (12 of 12 leaves declared by `FMX.Controls.Win.TWinControl`). Your `.rules` mapping
surface has been carrying that for as long as the property tree has existed.

## What now works, on the index as it already exists

| | before | after |
|---|---|---|
| `Vcl.StdCtrls.TEdit` -- top-level leaves | 97 | 352 |
| `cxButtons.TcxButton` -- top-level leaves | 120 | 440 |
| the 8 acceptance properties on each | 1 of 8 (`Visible` only) | **8 of 8** |
| `Vcl.Controls.TControl.Parent`'s children | 12, all `FMX.Controls.Win.TWinControl` | 313, all `Vcl.*` / `System.Classes.*` |
| FMX-declared leaves, six sampled roots | 1616 / 366 / 3473 / 1577 / 215 / 1932 (9179 total) | **0 / 0 / 0 / 0 / 0 / 0** |

Roots, in that column order: `Abcbtn.TabcToggleBtn`, `Vcl.Controls.TControl`,
`Vcl.Controls.TWinControl`, `Vcl.Controls.TGraphicControl`, `Vcl.StdCtrls.TEdit`,
`cxButtons.TcxButton`. The FMX sweep counts any declaring unit whose first segment starts `fmx`,
so `FMXTee.*` is caught too, not only `FMX.*`.

The climbs that were stopping now reach `TComponent`:

```
Vcl.StdCtrls.TEdit   TEdit -> TCustomEdit                                     (was: stopped here)
                  -> Vcl.Controls.TWinControl -> TControl -> System.Classes.TComponent
cxButtons.TcxButton  TcxButton -> TcxCustomButton                             (was: stopped here)
                  -> Vcl.StdCtrls.TCustomButton -> Vcl.StdCtrls.TButtonControl
                  -> Vcl.Controls.TWinControl -> TControl -> System.Classes.TComponent
```

and the three that already worked (`TControl`, `TWinControl`, `TGraphicControl`) still reach
`System.Classes.TComponent` by the identical chain, with a top-level surface that is
tuple-for-tuple unchanged (path, type, declaring class, kind, visibility, writability).

**The query-time repair is the load-bearing part of the design.** It works against databases
already on disk precisely because a full library rebuild currently aborts
(`INBOX-index-all-win32-library-rebuild-aborts.md`), so a fix that required re-indexing would have
been blocked behind a second unfixed bug. The index-time repair is also in (see below), but it only
takes effect on databases you rebuild.

## ACTION 1 -- re-baseline your leaf counts

Leaf totals have moved, in both directions, and you should not treat any stored count as stable:

| qname | leaves before | leaves after | top-level before | top-level after |
|---|---|---|---|---|
| `Abcbtn.TabcToggleBtn` | 3905 | **10023** | 262 | 262 |
| `Vcl.Controls.TControl` | 1934 | **3910** | 205 | 205 |
| `Vcl.Controls.TWinControl` | 6747 | **5175** | 313 | 313 |
| `Vcl.Controls.TGraphicControl` | 3491 | **9377** | 207 | 207 |
| `Vcl.StdCtrls.TEdit` | 977 | **16206** | 97 | 352 |
| `cxButtons.TcxButton` | 11074 | **36795** | 120 | 440 |

All six are `"truncated": true` before and after -- that flag is the recursion DEPTH cap, not a
leaf-count cap, so do not read it as "the tree was cut short".

`TWinControl` going **down** 1572 leaves is the clearest single illustration that this is
correction rather than growth: its `Controls` property used to expand into 299 children of which
245 were `FMX.Controls.TControl`; it now expands into 205, all `Vcl.Controls.TControl` /
`System.Classes.TComponent`. Same story for `Constraints` (13 `FMX.Forms.TSizeConstraints` -> 12
`Vcl.Controls.TSizeConstraints`).

`Abcbtn.TabcToggleBtn` growing 3905 -> 10023 is not bloat either. The sequence was: the repaired
climb first expanded the sub-trees under those already-FMX-mis-typed properties, then making
`Walk` scope-aware deleted the FMX sub-trees entirely and restored the correct VCL and RTL ones.
Its top-level surface is **262 before and 262 after, with no property added, removed, re-typed or
re-declared** -- the single top-level difference anywhere is `Picture`, which flips `kind`
`scalar` -> `class` because it now resolves to `Vcl.Graphics.TPicture` and gains 17 children.

Also directly relevant to you, on legacy ABC5 components: `Font` (14 FMX children -> 24 `Vcl.Graphics.*`),
`Images` (16 `FMX.ImgList.*` -> 37 `Vcl.ImgList.*`), `PopupMenu` (14 `FMX.Menus.*` -> 25
`Vcl.Menus.*`) and `Picture` (0 -> 17) are class-typed and resolve into `Vcl.*`. During development
`Action`, `AlignControlList` and every VCL-declared `TStrings`/`TCollection` briefly stopped
expanding under an over-broad guard; that was caught and narrowed before this note, and they expand
in the shipped build (`Action` 38 children before and after; `AlignControlList` 0 -> 8 on
`TcxButton`, now that the climb reaches `TWinControl` at all).

## ACTION 2 -- raise your 30 s watchdog

Measured on the final build, four runs each, one process per run, nothing else running:

| qname | runs (s) | mean | spread |
|---|---|---|---|
| `cxButtons.TcxButton` | 75.5 / 74.3 / 77.5 / 79.2 | 76.6 s | 4.9 s |
| `Vcl.StdCtrls.TEdit` | 34.6 / 34.5 / 34.3 / 35.3 | 34.7 s | 1.0 s |

Per-query memoization (a per-class chain cache and a per-`(name, scope)` type cache) is already in
place. We are making **no** performance claim in either direction: the Task-1 pre-change baseline
was a single sample each (38.2 s and 5.0 s), a mid-branch build measured the same two qnames at
101.4 s and 54.9 s, and those builds return 3-17x fewer leaves, so nothing here isolates a
per-unit-of-work effect. The one operational fact you need: **`TcxButton` takes ~75 s, so a 30 s
watchdog will fire on it.**

## What changed in the engine

- One shared scope rule, `PickAncestorCandidateByScope`: same unit -> unique exact `uses` hit ->
  unique bare-`uses` last-segment hit (a GUI candidate must be confirmed by the scope's framework)
  -> unique first-dotted-namespace-segment match -> **decline**. Declining is still a correct
  outcome; nothing guesses.
- A query-time per-hop fallback in the climb, using the FileId of the class actually inheriting at
  each hop.
- Scope-aware property types in `Walk`, with `CrossesGuiFramework` refusing only genuine `Vcl`
  vs `FMX` conflicts -- `System.*`, `Winapi.*`, `Data.*`, project namespaces and undotted units all
  pass.
- A framework anchor derived from the class's own resolved ancestry, for legacy pre-namespace units
  (`Abcbtn` declares `uses Graphics, Menus, ImgList`, which cannot textually match `Vcl.Graphics`).
- Index-time: `unit_uses.target_file_id` is populated, `ResolveAncestry` now uses the same one rule,
  and index-time scoping is purely textual -- so a NULL column cannot break ancestry even in
  principle.

**Five new autotest suites** (`run_proptree_scope_rule`, `run_proptree_ancestor_climb`,
`run_proptree_prop_type_scope`, `run_proptree_framework_anchor`, `run_unit_uses_targets`), plus the
pre-existing `run_proptree_ancestry_bridge` extended. Every guard was proved individually RED-able
by disabling it and rebuilding. Final state, all eleven proptree/convert suites on the final build:

```
run_proptree_scope_rule       17    run_proptree_framework_anchor  28
run_proptree_ancestor_climb   24    run_proptree_prop_type_scope   31
run_proptree                  20    run_proptree_fields            18
run_proptree_polymorphic      21    run_proptree_visibility        36
run_convert_rules             26    run_proptree_ancestry_bridge   22
run_unit_uses_targets         22
                                    TOTAL 265 pass, 0 fail
```

## Known limits, stated plainly

- **79 % of undotted legacy files (2309 of 2921) still have no framework anchor**, so ambiguous
  type names in those units still decline rather than resolve. Measured example:
  `AdPort.TApdCustomComPort.MasterTerminal: TWinControl`, reached as
  `AdFax.TApdAbstractFaxStatus`'s `Fax.ComPort.MasterTerminal` -- **313 correct leaves forgone**
  (180 declared by `Vcl.Controls.TControl`, 108 by `Vcl.Controls.TWinControl`, 25 by
  `System.Classes.TComponent`). `AdPort` says `uses Controls, Forms` -- strong VCL evidence -- but
  its ancestry never reaches a dotted GUI hop, so it gets no anchor. Deriving the anchor from the
  **uses graph** as well as the ancestry would recover this whole class; it is not done and needs
  its own decision.
- **Index-time rule B now refuses GUI-namespaced `uses` targets unconditionally**, including
  certainly-correct cases such as `uses ComCtrls` in a legacy VCL unit resolving to
  `Vcl.ComCtrls.pas`. Recovering those needs a per-unit framework anchor that
  `ResolveUnitUseTargets` cannot have, because it runs *before* `ResolveAncestry`. This is a
  deliberate under-claim, not an oversight -- but it means `unit_uses.target_file_id` stays NULL on
  rows a human would call obvious.
- **`call_edges` will shift on your next library rebuild** -- measured 4096 -> 4224 (+128) on a
  10-file RTL slice. More resolved `target_file_id` means more scope for `TCallResolver`, so this is
  expected and better-informed, not a regression. Anyone consuming `ResolveHelpers` /
  `TCallResolver` output across a rebuild boundary should know the number moves.
- **Two surfaces are not exercised by any test.** (1) The residual "unit name vs file identity"
  risk: the new rule matches on unit NAME via `DeclaringUnitOfQName` where the old `CandInScope`
  matched on file identity, so a file whose stem differs from its `unit` name could in principle
  behave differently -- measured LOST=0 / CHANGED=0 on ten real RTL sources, but never pinned by a
  fixture. (2) Pass 2a's lookup (`DRagLint.Storage.SQLite.pas:2709`) has no `CandUnit = ''` guard,
  where pass 2b has one at `:2738`; an empty `unit_name` row plus a bare `qualified_name` candidate
  could produce a spurious single hit. One fixture -- unit `Foo` declared in `Bar.pas` with an
  undotted `qualified_name` -- would close both.
- Delphi has an authoritative answer we cannot reach: `.dproj` `<FrameworkType>` (real, and
  `ORM3\CLIENT\Micronite2027.dproj:5` reads `VCL`). drag-lint never parses it, the library index has
  no project concept (no `projects` table, and `files` has no project or framework column -- checked
  in both `library-Win64.sqlite` and `ORM3\drag-lint.sqlite`), and the `.dfm`/`.fmx` sibling signal
  only ever says "VCL" here (743 `.dfm`, 0 `.fmx`) and only for form units. Filed as
  `docs/TODO-URGENT-framework-type-record.md`; it needs a schema column, which this branch is
  barred from adding.
- The no-cross-framework guarantee is **per hop**, not transitive: an intermediate class in an
  undotted or non-GUI unit can still bridge onward. Tightening that would break the `cxButtons`
  chain, so it is deliberate.

## Before you consume this

The branch is at 14 commits and **is not merged**. Tasks 1-4 are review-clean and this regression
pass (task 5) is green on everything it checks; the whole-branch review and the merge decision are
still outstanding. The staged exe lives only in the scratch worktree --
`third_party\dll-win64\drag-lint.exe` in your checkout is unchanged. Do not rebuild the editor
against this yet; we will send a short follow-up when the branch is merged and an exe is staged for
you.

Your own re-test, when that lands, is the one in your STATUS doc: rebuild the editor and confirm the
To pool offers `Name`/`Tag`/`Left`/`Top` for `cxButtons.TcxButton` and that they can be assigned.
