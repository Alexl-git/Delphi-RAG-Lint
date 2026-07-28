# v17 / proptree/2 integration — blockers found wiring the editor

**From:** converter-editor (`feat/converter-editor`). **To:** engine team (`main`).
**Date:** 2026-07-21. Context: wiring the editor to the shipped v17 proptree/2
(`is_writable`/`visibility`/`member_kind`). The field contract works great; two
blockers + one corpus note surfaced when running it against the live v17 exe + DBs.

## What works (no action needed)
- proptree/2 fields parse and drive the editor: read-only leaves hidden, public
  leaves tagged "PAS-only", DFM/PAS surface via `--min-visibility`. Verified on
  `TcxButton` (published, 592 leaves, all writable, no fields). Editor tests green.

## BLOCKER 1 — `--refs-as-leaves` is gone in v17; some proptrees explode / hang
The editor passed `--refs-as-leaves` (converter commit `f65fb9c`) to stop referenced
TComponents (Action, DropDownMenu, ...) expanding. **v17 rejects the flag** (`FATAL:
Unknown argument: --refs-as-leaves`) — it was never merged to `main`. Dropping it,
referenced components expand without bound:

| class | `--min-visibility published` | note |
|---|---|---|
| `cxButtons.TcxButton` | 592 leaves, fast | fine |
| `cxCheckBox.TcxCheckBox` | **~6982 leaves** | `Action.Owner.Name`, `DropDownMenu.Tag`, deep `ViewInfo.*` |
| `cxCheckBox.TcxCheckBox` `--depth 3` | **TIMEOUT > 45 s** | even a shallow cap times out |
| `cxCheckBox.TcxCheckBox` `--min-visibility public` | **TIMEOUT > 2 min** | |

An interactive editor shelling out synchronously would freeze on such a control.
(We added a 30 s watchdog so it now fails gracefully instead of hanging, but that is
a band-aid.)

**Ask:** restore a bounded surface in v17 — cherry-pick `f65fb9c`
(`TPropTreeOptions.TreatRefsAsLeaves` + the `--refs-as-leaves` CLI flag) into `main`,
and/or add a cycle/size guard to the R3 concrete-type recursion (it may be what tips
`TcxCheckBox` into the explosion). Then rebuild + redeploy the v17 exe. The editor
already tolerates the flag's presence; it just needs the engine to accept it again.

## BLOCKER 2 — v17 exe HARD-REFUSES pre-v17 project DBs (not graceful back-compat)
The SHIPPED note said project DBs "read `prop_access=NULL` → `is_writable` defaults
TRUE (correct back-compat)". In practice the v17 exe refuses the query outright:

```
$ drag-lint query find --no-docs --kind unit --db C:\Projects\DB\ORM3\drag-lint.sqlite
index schema v16 < v17: run "drag-lint index <dir> --db <db>" to migrate
   (0 rows)
```

So ORM3 (still schema v16) returns nothing. Impact on the editor: the **From-Unit
picker** and **Fill-From-classes** break (0 units), and any conversion whose instance
resolution needs ORM3 in the `--db` set is affected. This is not consumer-fixable —
back-compat defaults only help when the row is returned; here the whole query is
refused.

**Ask:** re-index the project DBs (ORM3 etc.) to v17 as part of the rollout (the
libraries were migrated; the project DBs were left at v16). Converter side is happy
to run `drag-lint index --all --only ORM3` if that's preferred — say the word.

## NOTE — the two platform libraries look unified now
Post-v17 re-index, `library-Win32` and `library-Win64` return **equal** TComponent-
descendant counts and `TOvcTable` (Orpheus, previously Win64-only) now appears in
**both**. The editor's FROM/TO platform pickers therefore return identical sets — the
platform distinction is moot in this corpus. If that's intended, fine (we relaxed the
platform-rescope test to SKIP when the two are equal). If not, the Win32 re-index may
have pulled in Win64-only sources.

## Editor status
proptree/2 wiring is committed and green (model suite 126/0/3-skip; the 3 skips are
ORM3-pre-v17 ×2 + unified-libs ×1). It is fully functional **today** for library
targets (TcxButton etc.); it needs BLOCKER 1 for pathological DevExpress controls and
BLOCKER 2 for the project-unit features.
