# convert-apply -- the component-conversion apply verb (all surfaces): design

**Date:** 2026-07-10
**Status:** Approved (design); implement via TDD AFTER sub-project A ships
**Sub-project:** B of the "full component-conversion apply" milestone. B DEPENDS
ON A (ref-gap G, `member-access` indexing). B is the real-life-testable deliverable:
a CLI verb that converts a real component in a real `.pas` + `.dfm`, rewriting all
five surfaces so the result compiles (modulo the runtime-creator TODO markers).
**Dependency note:** surface #4's exact query is finalized after A ships and the
`member-access` row shape is confirmed on a real fixture. This spec marks that as a
DEPENDENCY, not a guess; the rest of B is buildable independent of A and can start
with #1-3+#5 if desired.

## What it delivers (the value vs GExperts)

GExperts converts a selected component but rewrites the DFM ONLY, does 1-level type
mapping, and cannot map events. `convert-apply` rewrites FIVE surfaces and handles
moved-depth properties + events, using the AST/index:

1. `.pas` DECLARATION type (`Edit1: TOvcEdit;` -> `Edit1: TcxTextEdit;`).
2. `.pas` USES clause (add T's unit via `find-unit`; `#unuse` F's unit if asked).
3. `.dfm` component block -- the shipped 2a-i `ReemitComponent` structured re-emit
   (moved-depth, events, collections, binary).
4. `.pas` PROPERTY/EVENT ACCESS at every converted-instance use site
   (`Edit1.Caption := x` -> `Edit1.Text := x`) -- via ref-gap G (`member-access`).
5. `.pas` RUNTIME-CREATION sites (`Edit1 := TOvcEdit.Create(...)`) -- rewrite the
   type name, emit a generic creator from the index's available `TXYZ`
   constructors, and drop a `{ TODO: verify creator ... }` marker (T's ctor/init
   may differ from F's).

## CLI surface

```
drag-lint convert-apply --unit <MyForm.pas> --rules <f.rules> --db <app.sqlite>
    [--only Edit1,Edit2] [--apply] [--no-backup]
```

- Operates on ONE unit: `--unit MyForm.pas` and its SIBLING `MyForm.dfm` (same base
  name in the same folder; error if the .dfm is missing when the rules touch DFM).
- Converts every instance whose CLASS matches a `#convert FromType -> ToType` rule
  in the rules file. `--only Edit1,Edit2` restricts to named instances.
- **Dry-run by default:** prints a unified diff of every file it WOULD change + the
  structured report (converted instances, per-surface changes, TODO markers, and
  the property-access sites). NO writes.
- `--apply` performs the writes with the backup/recovery protocol below.
- `--no-backup` skips the `.BCK<n>` backups (fast, for a scratch copy / git-clean
  tree). Default is to back up.
- Exit 0 = clean (dry-run produced a diff, or --apply succeeded); 1 = a hard
  problem (stale index refused, unparseable unit, missing .dfm); 2 = bad args.
- Re-validate the rule set (reuse `ValidateConversionRules`) before applying; a rule
  set with errors -> refuse (exit 1) with the errors.

## Selection model (this batch = per-unit; class/named scopes)

- ALL instances of a class (every `TOvcEdit` in the unit) -- the default, driven by
  the `#convert` rules present.
- NAMED instances (`--only Edit1,Edit2`).
- (KIND groups and PROJECT scope are a later loop over units -- NOT this batch.)

## The five rewrite surfaces (detail)

### #1 .pas declaration type
Find the published field declaration `Edit1: TOvcEdit;` in the form class
(the instance name + its type). Rewrite the TYPE token to `ToType`. Reuse the
existing rename/edit-applier infrastructure (`TTextEditApplier`) for the byte edit.
The instance NAMES to convert come from the .dfm object list (or the .pas field
list) filtered to classes named in `#convert` rules (and `--only`).

### #2 .pas uses clause
For each distinct `ToType`, add its declaring unit via the shipped
`TFindUnitRefactoring.Build` (the `find-unit` engine already resolves the unit +
produces a uses-clause edit, with `--apply/--no-backup` proven). If the rules carry
`#unuse <FUnit>` and F's unit is no longer referenced after conversion, remove it
(optional; conservative default = leave it, since other code may use it).

### #3 .dfm component block
Locate the component's `object <Name>: <FromType> ... end` block in the sibling
.dfm (match by instance name + FromType). Feed that block text + the rules + the
F/T property trees (built via `BuildPropTree` from the index) to the shipped
`ReemitComponent` (2a-i). Replace the F block bytes with the returned T block.
Surface `ReemitComponent`'s report (dropped/mismatched/ownedParts/notes) in the
convert-apply report. OWNED-part-vs-child recognition is 2a-i's (marker-based in
2a-i; the real index container check is a later refinement).

### #4 .pas property/event access  (DEPENDS ON sub-project A)
For each `#link ToMember <- FromMember` rule that RENAMES a member (ToMember !=
FromMember), rewrite every `member-access` ref (from ref-gap G) where:
- the member `NameText` = FromMember, AND
- the companion base-identifier `read` ref at the same site names one of the
  converted instances (Edit1/Edit2/...), within this unit.
Rewrite the member token bytes FromMember -> ToMember via `TTextEditApplier`.
Events (`OnClick` etc.) are the same shape (a `#link` renaming the handler-property
name). **Query finalized after A ships** -- this spec fixes the CONTRACT (rename the
member token at instance-scoped access sites); the exact join is confirmed on A's
real `member-access` rows. If A is not yet done, #4 degrades to a REPORT of the
access sites (from the base-identifier reads) for manual fixup, and convert-apply
still does #1-3+#5.

### #5 .pas runtime-creation sites
For each site the index shows constructing the converted instance's type
(`Edit1 := TOvcEdit.Create(...)`, resolved via the receiver-typed `call_edges` /
the `TOvcEdit.Create` read ref), REWRITE the type name `TOvcEdit` -> `TcxTextEdit`.
Because T's constructor / required initialization may differ from F's, DO NOT
silently keep F's argument list as correct. Instead:
- pick a GENERIC creator from the index: query `TcxTextEdit`'s available public
  constructors (kind=constructor children of the class + inherited); prefer a
  `Create(AOwner: TComponent)` if present (the VCL norm), else the simplest;
- emit the rewritten call using that constructor's shape;
- insert a marker comment immediately above (or at end of) the line:
  `{ TODO: drag-lint convert -- verify creator for TcxTextEdit (was TOvcEdit.Create); T's ctor/init may differ }`.
This makes runtime-created instances SAFE-BY-DEFAULT: the type is converted, and the
uncertainty is flagged rather than silently mis-called. Design-time (DFM-streamed)
instances need no creator rewrite -- #5 only touches explicit `.Create` sites.

## Safety: backup + recovery (the user's design)

On `--apply` (unless `--no-backup`):

1. **Back up each file to be touched** to the NEXT-FREE versioned name:
   `MyForm.pas.BCK<n>` / `MyForm.dfm.BCK<n>`, where `<n>` is the lowest positive
   integer not already used for THAT file (scan the folder; never clobber an
   existing `.BCK<k>`). Per-file counter (the .pas and .dfm may get different n).
2. **Write the recovery record FIRST**, before any conversion write: APPEND a
   timestamped block to `recovery.txt` in the unit's own folder:
   ```
   [2026-07-10 14:30:22] convert-apply --rules tovc-to-cx.rules
     MyForm.pas -> MyForm.pas.BCK3
     MyForm.dfm -> MyForm.dfm.BCK2
   ```
   Writing the recovery record BEFORE the conversion means a crash mid-write still
   leaves a complete recovery map + the untouched .BCK backups.
3. **Perform the conversion** (write the rewritten .pas + .dfm).
4. **Prepend an in-file comment block** atop the converted `.pas` with the same
   mapping:
   ```
   // drag-lint convert-apply 2026-07-10 14:30:22
   //   backup: MyForm.pas.BCK3 / MyForm.dfm.BCK2 ; rules: tovc-to-cx.rules
   ```
   (In-file trace so anyone opening the unit sees how to undo it. "For now while
   testing" per the user; a dedicated `convert-revert` verb is a later nicety, not
   this batch.)

Dry-run does NONE of this (no backups, no recovery.txt, no writes) -- it only prints
the diff + report.

## Freshness guard (required)

Before trusting the index for the F/T property trees and the access/creator refs,
verify the F and T component TYPES are indexed and CURRENT: compare the indexed
source file's mtime/sha against disk. On a stale or unindexed type -> WARN (dry-run)
or REFUSE (--apply, exit 1) with a clear message ("TOvcEdit's source is newer than
the index; re-index before applying"). A stale index -> wrong T-tree shape -> broken
re-emit, so this guard is load-bearing for --apply.

## Report (dry-run and --apply both emit it)

Structured (text + optional --json), covering:
- converted instances (name, FromType -> ToType, per unit);
- per-surface change counts (decl / uses / dfm / access-rewrites / creator-sites);
- the 2a-i re-emit report per instance (dropped/mismatched/ownedParts/notes);
- the TODO creator markers emitted;
- (if A not done / #4 in report-only mode) the property-access sites needing manual
  fixup.

## Files (sub-project B)

- NEW `src/report/DRagLint.Convert.Apply.pas` (or `src/convert/...`) -- the applier
  engine: locate instances, drive surfaces #1-#5, produce the edit set + report.
  Reuses `ReemitComponent` (2a-i), `TFindUnitRefactoring` (find-unit),
  `TTextEditApplier`, `BuildPropTree`, `ParseConversionRules`/`ValidateConversionRules`,
  and the ref index (`member-access` from A + `call_edges` for #5).
- NEW backup/recovery helper (small pure-ish unit or a section of the applier):
  next-free `.BCK<n>`, `recovery.txt` append, in-file comment prepend.
- `src/cli/DRagLint.CLI.pas` -- the `convert-apply` verb (`DoConvertApply`) + args
  (`--unit`, `--rules`, `--only`, `--apply`, `--no-backup`) + dispatch + help text
  (this one IS documented, unlike the hidden convert-reemit).
- `src/cli/drag-lint.dproj` -- DCCReference for any new unit.
- Test `tests/autotest/run_convert_apply.ps1` -- a fixture unit (.pas + .dfm) + a
  rules file; assert the dry-run diff, then --apply, then the converted files +
  the .BCK<n> backups + recovery.txt + the in-file comment + the TODO markers.
- Docs: CONVERSION-RULES.md (the apply workflow), README/AI-USAGE, CHANGELOG.

## Global constraints

- Encoding: all new/edited `.pas` + `.ps1` strict 7-bit ASCII, no BOM, CRLF.
- DocInsight on every public type/function; comment and test agree.
- TDD: failing test first, implement to green, evidence both.
- Reuse shipped engines; NO new analysis engine beyond the applier orchestration.
- Dry-run is the DEFAULT and writes NOTHING; --apply is explicit.
- The applier is CLI + headless; NO IDE, NO LLM (the model is the DSL rules file).

## Build order within B (each provable headless)

1. Instance location (from .dfm object list + .pas field list, filtered by
   `#convert` + `--only`) + surfaces #1 (decl) and #2 (uses via find-unit).
2. Surface #3 (.dfm re-emit via ReemitComponent) wired to real file bytes.
3. The backup/recovery protocol + dry-run/--apply/--no-backup contract + freshness
   guard + the report.
4. Surface #5 (runtime creators + generic creator + TODO markers) via call_edges.
5. Surface #4 (property/event access rewrite) via ref-gap G -- LAST, since it
   depends on A. Until A + #4 land, #4 runs in report-only mode.

(Steps 1-4 are a real, testable convert-apply on their own; step 5 upgrades it to a
compiles-clean rename-aware conversion.)

## Self-review notes

- Every decision from the 2026-07-10 apply brainstorm is reflected: per-unit input,
  all five surfaces (with #4 gated on ref-gap G and #5 = the user's runtime-creator
  TODO idea), the `.BCK<n>` + recovery.txt + in-file-comment safety exactly as the
  user specified (next-free n, recovery.txt written FIRST, appended, beside the
  unit), dry-run default, freshness guard, and reuse of the shipped find-unit /
  ReemitComponent / edit-applier infrastructure.
- The A-dependency for #4 is explicit and degradable (report-only until A ships), so
  B is not blocked on A for steps 1-4 -- the build order lets a real conversion land
  before the property-access rewrite.
- One clear responsibility per unit: the applier orchestrates; the re-emit, uses-fix,
  edit-apply, proptree, and rules-parse engines are reused, not reimplemented.
