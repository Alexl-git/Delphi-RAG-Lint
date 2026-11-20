# GH #18 slice 2: symbol-id reuse (1.53.0) and the incremental calls stage (1.53.1) -- design

Status: DRAFT for controller review (lane GH18-DESIGN, v1523 run, 2026-11-20). Owner away; every
open choice below was decided by the lane and is marked **Decision**.
Plan for the 1.53.0 half: `docs\superpowers\plans\2026-11-20-gh18-symid.md`.
Earlier steps: 1.52.0 scoped resolve, 1.52.1 INCR18 (61c8f8e7d local names out of scope +
scope refs selected once; 2b183184f closure cache; 09c46adbc scoped purity), IDXPERF 98199e908.

## 1. Problem

A one-file incremental index of drag-lint's own CLI project still spends most of its time in the
calls stage (GitHub #18 comment 2026-11-20: ~10 s of a 35 s run on a loaded box; section 4 has the
lane's own numbers). The remaining causes named on the issue are:

1. **Name scope.** `MaterializeResolveScope` re-resolves every ref anywhere whose name is one the
   changed file declares (non-local names, before and after the write).
2. **Widening.** `ArgPassFilter` / `WidenDerivedScope` widen that set through ref chains.
3. **Per-pass whole-DB setup** in the call-target streams and the whole-table rebuild passes
   (`ResolveAncestry`, `ResolveHelpers`, `ResolveDispatch`, `RebuildInitDeps`).

Cause 1 exists because of HOW a file is re-emitted, not because the names changed:
`OpenFileTx` deletes every `symbols` row of the file and `UpsertSymbol` inserts fresh rows with new
ids. The delete fires the foreign-key actions on 30 columns that reference `symbols(id)` (measured
2026-11-20, section 4.3): `refs.symbol_id` in EVERY other file goes NULL (`ON DELETE SET NULL`),
`call_edges` / `member_accesses` / `dispatch_edges` rows that target the file cascade away. The
scoped pass must then rebind all of those refs, and the only handle it has on them is their name.
A body edit that changes no declaration therefore costs a rebind of every ref in the project that
names any routine, type, field or constant of the edited unit.

## 2. Goal and non-goals

Goal (1.53.0, this spec's normative part): **a re-emitted symbol whose identity and
resolution-relevant attributes are unchanged keeps its id**, so no foreign row loses its binding,
and the name scope shrinks to the names of symbols that were really added, removed or changed.

Goal (1.53.1, section 7, design direction only): the calls stage's fixed cost (stream setup and
whole-table rebuild passes) scales with the scope, not with the database.

Non-goals: no extractor or resolver version bump for 1.53.0 (rows written are the same, only their
ids differ -- see A6); no change to a full `--rebuild`; no change to the LSP's one-file write path
beyond what it inherits from `OpenFileTx` / `UpsertSymbol` (it uses the same store).

## 3. Design

### 3.1 Identity key and fingerprint

* **Identity key** of a symbol row (per file): `(kind, lower(qualified_name), signature,
  parent identity key, occurrence)` where `occurrence` is the 0-based index among rows of the same
  file with the same preceding tuple, in emission order. Measured: 920 groups on the CLI project
  share `(file, kind, qname, signature)` -- 831 `local_var`, 85 `param`, 4 `class` -- so the
  occurrence ordinal is required.
  Two columns are written AFTER the insert and so cannot be in the key: `inc_variant`
  (`TagSymbolIncVariant`, inside the file tx) and a property's `signature`
  (`MemoizePropertyType`, by the resolver, outside the file tx). **Decision**: the key leaves
  `inc_variant` out, and for `kind = 'property'` leaves `signature` out.
* **Fingerprint**: a hash of every `symbols` column EXCEPT `id`, `file_id`, `parent_id` (compared
  through the parent's identity key) and the positions (`start_line`, `start_col`, `end_line`,
  `end_col`, `impl_start_line`, `impl_end_line`). Positions are excluded on purpose: a ref in
  another file never resolves by the target's position; refs in the changed file are re-resolved
  anyway (scope point 1). **Decision**: the fingerprint is compared at `CommitFileTx`, after every
  in-tx tag (`inc_variant`) has landed, against the snapshot taken at `OpenFileTx`. A property
  whose old signature was memoized by the resolver reads as CHANGED (its name enters the scope):
  sound, and rare (a redeclared `property Foo;` only); the claimed row gets the emitted signature
  back and the resolver re-memoizes it as on a fresh index.
* **Decision**: `signature` is part of the KEY, not only the fingerprint. An inserted overload then
  shifts no ids between overloads (the occurrence ordinal only breaks exact ties), and a signature
  edit is an id change (removed + added), which puts the name in scope -- the conservative answer
  for overload resolution.

### 3.2 Write path: update in place, delete only what disappeared

**Decision: in-place diff (option B).** Rejected alternatives:

* A -- delete, then re-insert with the old id: the delete has already fired SET NULL / CASCADE on
  the foreign rows; SQLite cannot switch `foreign_keys` inside the open file transaction, and
  `defer_foreign_keys` defers checks, not actions.
* C -- delete, then remap foreign rows old id -> new id: needs a full snapshot of 30 columns of
  foreign rows before the delete; the cascaded rows (`call_edges`, `dispatch_edges`) would have to
  be re-inserted, i.e. a second resolver. More code, more risk, same result.

Shape of B:

1. `OpenFileTx` stops deleting the file's `symbols` rows. It loads the file's old rows into an
   in-memory map `identity key -> (id, fingerprint)` (one indexed SELECT, the same query
   `NoteScopeRemoval` already runs, widened by the columns) and still deletes the file's
   own-emitted, file-keyed rows (`refs`, DI bindings, string literals, unit uses, ...) exactly as
   today.
2. `UpsertSymbol` computes the key of the incoming row. On a hit that is not yet claimed: claim it,
   `UPDATE symbols SET <all columns> WHERE id = :old` (positions included), return the old id. On a
   miss: `INSERT` as today. The fingerprint comparison decides only the SCOPE (3.3), not the write.
3. `CommitFileTx` (before the savepoint is released) deletes the unclaimed old ids. Their foreign
   rows get the FK actions exactly as today -- for the removed symbols only.
4. **Emit-owned, symbol-keyed tables of the file are cleared explicitly** for every claimed id,
   because the cascade that used to clear them no longer fires. Classification of the 30 FK
   columns + 3 non-FK id columns (section 4.3) is Task 1 of the plan and is pinned by a schema
   guard: a new column that references `symbols` fails the guard until it is classified as
   (E) emit-owned -> cleared at OpenFileTx, (R) resolver-written, cross-file -> kept for a claimed
   id, (D) derived whole-table -> rebuilt by its pass as today, or (P) purity verdict -> cleared
   for every claimed routine so scoped purity sees "no verdict" and re-derives it.
   Known members: E = `symbol_docs`, `symbol_trigrams` (skip when the name is unchanged -- the
   name is in the key), `symbol_search`, `symbol_facts` emit columns, `data_flows`, `attributes`;
   R = `refs.symbol_id`, `call_edges.*`, `member_accesses.*`, `ref_types`, `ref_element_types`,
   `ref_host_bindings`, `classref_args`, `dfm_objects`, `string_literals.symbol_id`,
   `comment_facts`, `fb_*`; D = `type_ancestors`, `type_helpers`, `dispatch_edges`, `init_deps`;
   P = `symbol_facts.effect_*` columns. The plan's Task 1 verifies each against the writer.
5. `symbols.parent_id` of a claimed row is rewritten by the UPDATE; the parent is always emitted
   before the child (IndexFileBody maps `IdxToId` in emission order), so the parent's id is known.

### 3.3 Scope after the write

`NoteScopeRemoval` keeps taking its snapshot at open, but the scope sets are filled at
`CommitFileTx`: only names of symbols that were unclaimed (removed), inserted (added) or claimed
with a different fingerprint (changed) enter `FScopeNames` / `FScopeLocalNames` /
`FScopeTypesBefore` / `FScopeTypesAfter`. The receiver closure (150-RS2 (6)) and the purity "old users" query run over the
unclaimed-or-changed ids only, at commit, instead of over every symbol of the file at open.
Everything else in the soundness argument on `ScopedResolveIsSound` is unchanged: refs IN the
changed file are re-resolved (point 1), type additions widen (4a), out-of-tx deletes go whole (5).

**Decision -- includes stay on today's path.** When a changed file hosts or is an include
(`FScopeIncludeTouched`, the INCR18 test), every old name enters the scope as today: a routine
body split over an include gives a ref in one file an enclosing symbol in another.

**Escape hatch** `DRAGLINT_NO_SYMBOL_ID_REUSE=1`: delete + insert as in 1.52 (the A/B and the
roll-back). **Test seam** `DRAGLINT_TEST_SYMID_NO_FP=1`: claim on key alone and
treat every claimed row as unchanged -- a deliberately WRONG scope, the positive control.

## 4. Measurements (lane, 2026-11-20)

Numbers in section 8. The finding that shapes the design: on a leaf unit the name scope is
already small (6 names, 8 foreign refs) and the calls stage is fixed cost; on a hub unit the
scope is the symbol-id churn -- 231 of 231 symbols get new ids, 72 names pull 13,747 refs of 379
files into the pass, and the calls stage takes 40 s. Every one of those 231 symbols is unchanged
by key AND fingerprint (forced-stale = an identical re-emit, which is also what a body edit or a
blank line produces, positions aside). So reuse takes the hub's name scope from 72 names to 0;
1.53.1's job is the fixed cost that remains (section 7).

### 4.3 Columns that hold a symbol id (measured on the CLI DB, sqlite_master)

30 FK columns `REFERENCES symbols(id)`: SET NULL on `refs.symbol_id`, `refs.enclosing_symbol_id`,
`fb_relations.sql_table_symbol_id`, `fb_columns.sql_column_symbol_id`,
`call_edges.receiver_type_symbol_id`, `type_helpers.target_symbol_id`,
`string_literals.symbol_id`, `member_accesses.accessor_symbol_id`,
`member_accesses.receiver_type_symbol_id`, `ref_types.type_symbol_id`,
`ref_element_types.type_symbol_id`, `dfm_objects.symbol_id`, `comment_facts.anchor_symbol_id`,
`ref_host_bindings.symbol_id`, `attributes.symbol_id`; CASCADE on `symbols.parent_id`,
`symbol_trigrams`, `symbol_docs`, `call_edges.target_symbol_id`, `type_helpers.helper_symbol_id`,
`symbol_facts`, `type_ancestors.symbol_id`, `member_accesses.member_symbol_id`,
`dispatch_edges.base_symbol_id` / `impl_symbol_id`, `classref_args.param_symbol_id` /
`class_symbol_id`, `symbol_search`, `data_flows`, `init_deps.unit_symbol_id`.
3 non-FK holders: `orm_links.delphi_symbol_id`, `orm_links.sql_symbol_id`,
`type_ancestors.ancestor_symbol_id`. Post-insert writers of `symbols`: `TagSymbolIncVariant`
(inc_variant), `MemoizePropertyType` (property signature), `PurgeLocals` (out-of-tx delete).

## 5. Acceptance criteria (EARS)

* A1 (Ubiquitous) THE store SHALL give a re-emitted symbol whose identity key matches an old row
  of the same file that old row's id.
* A2 (Event-driven) WHEN a file is re-emitted THE store SHALL delete exactly the old rows whose
  key was not claimed, and their foreign rows SHALL receive the FK actions they receive in 1.52.
* A3 (Unwanted) IF a claimed row's fingerprint differs from the old one THEN the scoped pass SHALL
  re-resolve every ref named like it (its name enters the name scope).
* A4 (Ubiquitous) THE incremental index with reuse SHALL produce a database `index_db_diff`
  reports IDENTICAL to (a) the same incremental with `DRAGLINT_NO_SYMBOL_ID_REUSE=1` and (b) a
  fresh full index, on every edit scenario of the plan (including the INCR18 Part 1 / 1c ones).
* A5 (Unwanted) IF the seam `DRAGLINT_TEST_SYMID_NO_FP=1` is set THEN the
  signature-type-change scenario SHALL show diff rows (the guard can fail).
* A6 (Ubiquitous) THE change SHALL write no row that 1.52 does not write, other than ids: no
  extractor or resolver bump; `run_extractor_version_guard` / `run_resolver_version_guard` re-pin
  hash-only with that reason if the source hash moves.
* A7 (State-driven) WHILE a changed file hosts or is an include THE scope SHALL contain every old
  and new name of the file (1.52.1 behaviour).
* A8 (Event-driven) WHEN `DRAGLINT_NO_SYMBOL_ID_REUSE=1` is set THE store SHALL delete and
  re-insert the file's symbols as in 1.52.
* A9 (Ubiquitous) ON drag-lint's CLI project, a forced-stale or blank-line edit of
  `DRagLint.Analysis.Cfg.pas` (the hub case) SHALL keep 100 % of the file's symbol ids, null 0
  foreign `refs.symbol_id`, put 0 names of that file in the name scope, and the calls stage
  median of 3 SHALL be at most 10 s against the section 8 baseline of 40.6 s (same machine, load
  stated). The leaf case (`DRagLint.CLI.Hover.pas`) SHALL keep 100 % of its ids and not be slower
  than its 4.2 s baseline.
* A10 (Unwanted) IF a new column referencing `symbols(id)` appears without a classification THEN
  the schema guard SHALL fail naming it.

## 6. Risks

* R1 **Stale emit-owned rows.** A table that used to be cleared by the cascade and is missed in
  the E/P classification keeps an old row for a claimed id (worst: a stale purity verdict).
  Mitigation: the A10 guard, A4 diffs over every table (index_db_diff compares 20+ tables by
  natural key), and the P class clears verdicts of every claimed routine.
* R2 **Id-order tie-breaks.** Any resolver or query that breaks ties by `ORDER BY id` / `MIN(id)`
  will see claimed rows keep LOW ids where 1.52 gave them high ones. Today's incremental already
  reorders ids against a fresh index and A4 holds, but reuse creates a new order. Mitigation:
  Task 1 audit of `ORDER BY ... id` / `MIN(id)` in Storage.SQLite and Index.CallResolver
  (`query --text`), plus an ambiguous-overload scenario in the A4 set.
* R3 **Rowid reuse.** `symbols.id` is `INTEGER PRIMARY KEY` without AUTOINCREMENT: SQLite may hand
  a deleted max id to the next insert. Non-FK holders (`orm_links.*_symbol_id`,
  `type_ancestors.ancestor_symbol_id`, in-memory caches such as the purity scope id sets) could
  then name an unrelated symbol. Pre-existing, but reuse changes which ids get deleted.
  Mitigation: the plan records the max id before the run and asserts no unclaimed-deleted id is
  re-issued within the run (or documents why it cannot matter for each holder).
* R4 **Fingerprint too narrow.** An attribute the resolver reads that is not a `symbols` column
  (e.g. a property accessor binding, a DFM link) and changes while the symbol row is identical.
  Mitigation: such data lives in its own file-keyed rows that the changed file re-emits and that
  the R-class resolver passes rebuild for the file; A4 is the check. Scenario list includes a
  property accessor rename and a field type change.
* R5 **Batch / savepoint path.** `OpenFileTx` runs inside a PR #10 file batch with savepoints; the
  unclaimed delete must sit inside the same savepoint, and a rollback must restore the old rows
  (it does, by the savepoint) and drop the in-memory claim map.
* R6 **LSP writer.** The LSP reindexes through the same store; its in-memory id caches (hover,
  find-callers) see stable ids now -- a benefit -- but any cache that assumed "re-emit = new ids"
  to invalidate must be checked (plan Task 1 audit, report only).

## 7. 1.53.1 -- incremental calls stage (direction, not normative)

After reuse the name scope of a body-only edit is near-empty, so the calls stage is dominated by
fixed per-pass cost. Leaf profile (section 8): 4.2 s, of which streams 2.2 s (ref-receivers 0.95
over 16,266 receiver texts, arg-uses 0.53 over 6,367 reads) and ~2 s outside any stream
(init-deps rewrites all 384 rows; the remainder is unattributed -- 1.53.1 first adds profile
points). Directions, in order of measured cost:

0. `ref-receivers` and `arg-uses` join whole-DB universes: drive both from `dl_scope_refs`.
1. Whole-table rebuild passes (`ResolveAncestry`, `ResolveHelpers`, `ResolveDispatch`,
   `RebuildInitDeps`) each `DELETE FROM <table>` and rebuild. Make each one scoped by the changed
   type set (types of changed files plus their descendants through `type_ancestors`), with the
   same "whole when the type set changes shape" fallback the resolve scope uses.
2. Stream setup that loads universes (all enum values, all routines for parenless, all accessors)
   before filtering by scope: drive each stream from `temp.dl_scope_refs` and load only the
   candidate rows whose names appear in the scoped refs.
3. Skip a stream outright when `dl_scope_refs` holds no ref of the kind it binds.

Each item ships with the same proof shape as INCR18: scoped = whole = fresh by index_db_diff plus
a positive control seam. A separate plan is written in 1.53.1 from the 1.53.0 numbers.

## 8. Baseline numbers

Engine: `lane/v1523-gh18-design` = `lane/v1522-int` efaf5d914, 1.52.2-alpha Win64 Debug, built in
the lane. DB: copy of `src\cli\_D-RAG\drag-lint.sqlite` (426 files, 90,243 symbols, 708,160 refs),
brought current by one incremental run of the lane engine (41.9 s, 2 files). Each run: fresh copy
of that base, one file forced stale (`sha256='forced'`, `size=NULL`; a real re-parse, no source
written -- the same re-emit as a blank-line edit, positions aside), `index --project
src\cli\drag-lint.dproj`, `DRAGLINT_PROFILE=1 DRAGLINT_PROFILE_CALLS=1`. 2026-11-20 15:42-16:00,
after the v1522 battery; CPU load before each run in the table (other lanes were running).

| stage (s) | leaf Hover r1 / r2 / r3 | leaf median | hub Cfg r1 / r2 / r3 | hub median |
|---|---|---|---|---|
| load before run (%) | 18 / 16 / 26 | | 26 / 33 / 84 | |
| ancestry | 0.1 / 0.1 / 0.1 | 0.1 | 0.1 / 0.3 / 0.5 | 0.3 |
| helpers | 0.6 / 0.6 / 0.6 | 0.6 | 0.6 / 0.6 / 0.7 | 0.6 |
| **calls** | 4.2 / 4.3 / 4.2 | **4.2** | 39.1 / 48.2 / 40.6 | **40.6** |
| dispatch | 0.5 / 0.4 / 0.4 | 0.4 | 0.7 / 0.4 / 0.4 | 0.4 |
| purity | 2.0 / 1.7 / 1.6 | 1.7 | 4.7 / 3.9 / 3.1 | 3.9 |
| index "Done." | ~9.9 | ~9.9 | 58.6 / 73.6 / 56.8 | 58.6 |
| process wall | 25.7 / 27.2 / 27.0 | 27.0 | 62.2 / 76.9 / 61.1 | 62.2 |

The leaf runs had the rule cache on: `rule-cache: warmed 10 finding(s) in 13.7s` is 14 s of the
27 s wall, after "Done." (the hub runs set `DRAGLINT_RULE_CACHE=0`, as the issue did). Index walk
0.37 s, parse + write of the file 0.08 s, closure cache 826 scans reused.

Calls-stage streams (`DRAGLINT_PROFILE_CALLS`, run 2):

| stream | leaf | hub |
|---|---|---|
| main | 0.22 | 21.66 |
| ref-receivers | 0.95 | 10.20 |
| arg-uses | 0.53 | 5.44 |
| parenless | 0.09 | 2.94 |
| value-reads | 0.14 | 0.73 |
| ref-types | 0.02 | 0.54 |
| others (8 streams) | 0.25 | 0.65 |
| scoped refs | 123 refs, 41 edges | 13,130 refs, 3,197 edges |
| `ref-receivers` joined | 15,749 of 16,266 texts | 164,375 of 174,436 texts |
| `arg-uses` | 14 of 6,367 reads | 216 of 70,080 reads |

Symbol-id churn (`churn.py`, base vs after, the edited file):

| | leaf Hover | hub Cfg |
|---|---|---|
| symbols before / after | 33 / 33 | 231 / 231 |
| ids kept today | 0 | 0 |
| under reuse: claimed-same / changed / added / removed | 33 / 0 / 0 / 0 | 231 / 0 / 0 / 0 |
| foreign rows bound before (refs / call_edges / member_accesses / ref_types) | 2 / 2 / 0 / 0 | 458 / 194 / 708 / 566 |
| name scope today -> foreign refs (files) | 6 -> 8 (2) | 72 -> 13,747 (379) |
| name scope under reuse | 0 | 0 |

Reading: on the hub the calls stage is ~90 % churn (13,130 scoped refs against 123 for the leaf),
and reuse removes it; the leaf's 4.2 s is the fixed cost (ref-receivers and arg-uses scan whole-DB
universes, `init-deps` rewrites 384 rows, ~2 s outside any stream), which is 1.53.1.
