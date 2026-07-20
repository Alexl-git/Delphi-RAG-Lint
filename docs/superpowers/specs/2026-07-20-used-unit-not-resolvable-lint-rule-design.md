# Design: `used-unit-not-resolvable` lint rule

- Date: 2026-07-20
- Status: Approved (brainstorming complete; ready for implementation plan)
- Author: drag-lint session (resume LATEST-56 -> post-resume plan item 2)

## Motivation

Micronite2027 exists to convert Micronite2022 from BDE -> FireDAC/Firebird,
**unit by unit**. The user brings a 2022 unit into the 2027 tree (ORM3\CLIENT),
then converts it. A brought-in unit typically still `uses` legacy units that no
longer resolve in the 2027 build:

- Orpheus (`ovctcmmn`, `ovctcmdt`, ...) -- the source folder was removed from the
  IDE library path, so these resolve nowhere until replaced with DevExpress.
- BDE (`Bde.DBTables`) -- 32-bit only; a Win64 build cannot resolve it.
- Un-migrated app units (`FLDRDefs`, `onoffRecord`) -- exist in Micronite2022 but
  have not been brought into 2027 yet.

Today the only way to discover these is to compile. A compile of a legacy unit in
the 2027 context is unreliable (see LATEST-56: headless full-build is a dead end).
A **static** rule that flags every `uses X` where `X` resolves to no known unit
gives the exact conversion signal with **no compile** -- the single highest-value
feature for this workflow.

The user's three downstream fix-paths for each flagged unit are: **comment it
out**, **replace it** (Orpheus->DevExpress, BDE->FireDAC), or **add it to the
project**. The rule must NOT presume "add it" -- it surfaces the decision.

## The existing rule this reframes

`unit-not-in-project` (`TProjectChecks.CheckUnitMembership`,
`src/lint/DRagLint.Lint.ProjectChecks.pas:141`; RuleCatalog
`src/lint/DRagLint.Lint.RuleCatalog.pas:205`; wired into `lint-project` at
`src/cli/DRagLint.CLI.pas:7331`) already walks used units and checks each against
a library DB + the project `.dpr`/`.dproj`. But its purpose is **project
registration**, not **resolvability**:

- it requires a `.dproj` and flags "not fully registered in the project
  (.dpr + .dproj)";
- it attaches findings to the `.dproj` file at line 0, not the `uses X` line;
- its message presumes the fix is "add it to the project".

Decision (user): **reframe this rule in place** rather than add a parallel one.
The registration semantics are the wrong question for a conversion; resolvability
is the right one.

## Section 1 -- Rule identity & semantics

- **RuleId:** rename `unit-not-in-project` -> `used-unit-not-resolvable`
  (internal id; the old name misdescribes the new meaning). Update the RuleCatalog
  entry and both CLI dispatch sites (`src/cli/DRagLint.CLI.pas:7250` and `:7331`).
- **Finding location:** the `uses X` token itself. `unit_uses` already stores
  `start_line`/`start_col`/`end_line`/`end_col` per used unit
  (`src/core/DRagLint.Core.Model.pas:266`), and the finding attaches to the
  **source unit's file** (the file doing the `uses`), not the `.dproj`.
- **No `.dproj` required.** The rule runs against the DB alone, so it works on a
  single brought-in unit before it is registered anywhere. The `.dproj` parameter
  is dropped (or ignored).
- **Severity:** `warning` (this engine's severities are error/warning/info/hint;
  "severe warning" maps to `warning`, matching the rule's current severity).
- **Message (neutral about the fix):**

  > `Unit 'ovctcmmn' is used but resolves to no known unit (not a project member,`
  > `not in the Win32 library, not a known alias). Convert it: comment it out,`
  > `replace it (e.g. Orpheus->DevExpress, BDE->FireDAC), or add it to the project.`

  The platform name in the message reflects the platform actually used for
  library resolution.

## Section 2 -- Resolution model (what counts as *resolvable*)

A used unit is **resolvable** (NOT flagged) if any of these hold. Evaluated in
this order; first hit wins:

1. **Project member** -- an indexed unit in the DB being linted: its
   `unit_uses.target_file_id` is set, or its trailing-segment stem matches a
   `files` row. Covers sibling units already brought into 2027. Scope = the single
   store being linted (the ORM3 DB indexes CLIENT+SERVER+COMMON together, so one
   store already covers the project). Multi-DB project membership is a follow-up.
2. **Platform library** -- its `unit_name_norm` exists in the
   `library-<platform>.sqlite` symbols table (queried as today,
   `SELECT 1 FROM symbols WHERE unit_name_norm = :n`). This is the
   platform-conditional crux: `Bde.DBTables` resolves for Win32, flags for Win64.
   The caller passes the platform-matching library DB; platform is selected via
   the existing plumbing (`--platform`, default = manifest `defaultPlatform`
   (Win32) or `.dproj` detection -- same path `ResolveConsumerDbs` uses).
3. **Standard unit alias** -- the used name is the left side of a classic Delphi
   unit alias. Built-in table (MVP): `WinTypes`, `WinProcs` (-> Windows);
   `DbiTypes`, `DbiProcs`, `DbiErrs` (-> BDE). An alias LHS is treated as
   resolvable directly (the compiler guarantees its target exists). Reading a
   project's `.dproj` `DCC_UnitAlias` is a later add, not MVP.
4. **RTL-namespace safety net** -- a dotted-namespace allowlist
   (`System.*`, `Vcl.*`, `Fmx.*`, `Winapi.*`, `Data.*`, `Datasnap.*`, `Soap.*`,
   `Web.*`, `FireDAC.*`, plus the classic bare RTL names already skipped:
   `Forms`, `SysUtils`, `Classes`, `Windows`, `Messages`, `Variants`, `Graphics`,
   `Controls`, `Dialogs`, `Menus`, `StdCtrls`, `System`, `SysInit`). Reuses and
   extends the skip-list the rule already carries. Belt-and-suspenders: incomplete
   library-index coverage can never false-flag core RTL.

**M2022.sqlite is deliberately NOT a resolution source** (user decision). A `uses`
of an un-migrated M2022 unit still flags -- that is the "migrate or convert this"
signal. M2022.sqlite remains a *reference/lookup* index (post-resume plan item 1,
deferred), never a membership source for this rule.

If none of 1-4 hold, the unit is **unresolvable -> flag**.

**Uses with an explicit `in '<path>'` locator are skipped.** `unit_uses.in_path`
is non-empty only for the `uses X in 'X.pas'` form (`.dpr`/`.dpk` entries and rare
qualified uses). That form names the file directly, so a problem there is a
build-config/disk question, not an index-resolvability one -- skipping it keeps
every flag a high-confidence "this bare `uses` resolves to nothing known".

## Section 3 -- Precision & the trailing-segment caveat

The engine resolves units **namespace-blind**: `unit_name_norm` is the lowercased
*trailing* segment (`Bde.DBTables` -> `dbtables`,
`src/storage/DRagLint.Storage.SQLite.pas:3142`). This is exact for the flat legacy
names that matter (`ovctcmmn` -> `ovctcmmn`; `onoffRecord` -> `onoffrecord`), with
one honest failure mode:

- **False-resolution on trailing-segment collision.** A genuinely-missing dotted
  unit could look resolved if some unrelated indexed/library unit shares its last
  segment (e.g. a missing `Foo.DBTables` masked by a real `DBTables`). This
  **under-flags** (misses a few) and never over-flags -- the safe direction for a
  conversion aid: **every flag is high-confidence** (the unit resolves nowhere by
  trailing segment).

**Decision (MVP): keep namespace-blind matching** -- consistent with the whole
engine, zero new infra. Because `unit_uses.unit_name` stores the full dotted
verbatim name (`src/core/DRagLint.Core.Model.pas:268`), a later precision pass can
compare full dotted names when a dotted `uses` is involved. Documented follow-up,
not built now.

## Section 4 -- Surfacing & scope (MVP)

- **Runs in `lint-project`** -- exactly where the rule runs today
  (`src/cli/DRagLint.CLI.pas:7331`): default-on when no `--rule` filter is given,
  and addressable via `--rule used-unit-not-resolvable`. No new command.
- **Findings carry the real `uses` line/col**, so they are clickable-to-line in
  the plugin's existing lint report / Full Sweep dock. That satisfies "just mark
  visible" through existing plumbing.
- **Out of scope for MVP** (user: "MVP = just mark visible"):
  - live LSP editor squiggles on the `uses` line while editing (follow-up);
  - any autofix for the three fix-paths (comment-out / replace / add) (follow-up);
  - `.dproj` `DCC_UnitAlias` ingestion (follow-up);
  - full-dotted-name precision matching (follow-up, see Section 3);
  - multi-DB project-membership resolution (follow-up, see Section 2).

## Architecture / components

Designed so the resolution decision is a **pure function testable in isolation**,
separate from the file/`unit_uses` walking and from the finding emission.

1. **`TUnitResolver` (new logic, in `DRagLint.Lint.ProjectChecks` or a small
   sibling unit).** The pure resolvability decision:
   - `function ResolveUsedUnit(const AUnitName: string): TUnitResolution` where
     `TUnitResolution` records `Resolvable: Boolean` and `Via` (project / library /
     alias / rtl-namespace / none).
   - Dependencies injected: a "is this stem a project member?" predicate (over the
     linted store), a "is this norm in the library?" predicate (over the passed
     library DB), the built-in alias table, and the RTL-namespace allowlist.
   - No file walking, no DB opening inside the decision -- predicates are passed
     in, so tests drive it with in-memory stubs.
2. **Reframed walker** (`CheckUnitMembership` -> `CheckUsedUnitResolvable`):
   iterates `unit_uses` across the store's files, calls `ResolveUsedUnit` per used
   unit, and on `not Resolvable` emits a `TLintFinding` at the use's line/col on
   the source file. Drops the `.dproj` membership branch.
3. **RuleCatalog** (`src/lint/DRagLint.Lint.RuleCatalog.pas:205`): rename id +
   description ("Used unit resolves to no known unit (project/library/alias)").
4. **CLI wiring** (`src/cli/DRagLint.CLI.pas:7250`, `:7331`): rename the rule id in
   both dispatch sites; ensure the platform-matching `library-<platform>.sqlite`
   is the library DB passed to the check (via the existing platform selection).

## Testing (TDD)

Unit-test the pure resolver in isolation, then a thin integration test of the
walker over a fixture DB:

- **Resolver unit tests** (in-memory predicates): `ovctcmmn` (no project, no lib,
  no alias) -> **flag**; `Bde.DBTables` with a Win32 lib predicate that knows
  `dbtables` -> no flag; same with a Win64 predicate that does not -> **flag**;
  `WinTypes` -> no flag (alias); `System.SysUtils` -> no flag (RTL namespace);
  `Vcl.Forms` -> no flag; a sibling unit present as a project member -> no flag.
- **Walker integration test**: a fixture source unit whose `uses` mixes the above;
  assert exactly the expected units flag, each at the correct `uses` line, and
  that the finding attaches to the source file (not a `.dproj`).
- **Regression**: confirm a clean unit (all `uses` resolvable) yields zero findings.

## Out of scope / follow-ups (recorded, not built)

- Live LSP diagnostics (editor squiggles) for this rule.
- Autofix / quick-fix for comment-out / replace / add.
- `.dproj` `DCC_UnitAlias` ingestion.
- Full-dotted-name precision resolution for dotted `uses`.
- Multi-DB project-membership (resolve project members across sibling DBs).
- Post-resume plan item 1 (wire M2022.sqlite into query/LSP resolution) -- separate
  work; this rule intentionally does not consult M2022.

## Open questions

None blocking. Platform defaulting reuses existing plumbing; severity and MVP
scope are settled above.
