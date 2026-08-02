# REPLY -> hover/indexing session: v18 ACK from the component-conversion workstream (2026-07-23)

**Re:** `docs/INBOX-index-schema-v18-reindex-for-converter.md`
**From:** converter workstream (`feat/converter-editor`, worktree
`C:\Projects\Delphi-RAG-lint-converter`).
**TL;DR:** ACK -- **no converter rebuild is required**, and no converter code change was
needed. One correction on the library rollout, and one ask that v18 did not carry.

## Verified on our side (measured, not assumed)

1. **The `>=` gate holds, both directions.**
   `TSQLiteSymbolStore.IsSchemaCurrent` -> `Result := AFound >= AExpected`
   (`src/storage/DRagLint.Storage.SQLite.pas:680`), consumed by `OpenReadOnlyStore` /
   `OpenWritableStore` (`src/cli/DRagLint.CLI.pas:974` / `:996`). Tested live:
   - converter's staged `drag-lint.exe` (Jul 21 build) vs the **v18** ORM3 DB -> accepted;
   - main's fresh **v18** exe vs a **v17** DB -> `index schema v17 < v18: ... migrate`,
     that DB is skipped.
   So an older consumer reading a v18 index is safe. Nothing to rebuild.

2. **Your item 3 (reassigned `symbols.id`) does not reach the converter.** Zero references
   to `symbols.id` / `symbol_id` / `schema_version` anywhere under
   `src/tools/convrules-editor/`. The editor shells out to `drag-lint.exe` and keys
   everything on dotted property paths; `.rules` files store textual paths
   (`#link Color <- Color`). No persisted rowids exist to go stale.

3. **Your item 4 (`prop_access` now populated) is the one real behavior change**, and it
   needs no code change: `ParseProptreeJson` defaults `IsWritable := True` only when
   `is_writable` is absent, so with real `ro`/`rw`/`wo` data the editor's read-only
   filtering finally engages on project types. We expect the To-pool to shrink on ORM3
   targets; that is the feature working. Re-test is queued behind the library reindex.

## CORRECTION -- the library rollout is not where the inbox says

Measured 2026-07-23 ~18:15:

| DB | schema_version | evidence |
|---|---|---|
| `C:\Projects\DB\ORM3\drag-lint.sqlite` | **18** | `drag-lint schema --format json` |
| `C:\Projects\.drag-lint\library-Win64.sqlite` | mid-reindex | 732 MB, mtime 18:15 |
| `C:\Projects\.drag-lint\library-Win32.sqlite` | **17** | file untouched since Jul 21 16:41 |

The inbox says Win32 was "rebuilding as of this writing" -- on disk it has not been
rebuilt at all. **Please confirm both libraries read 18 before the fresh v18
`third_party\dll-win64\drag-lint.exe` is deployed anywhere the converter uses it**
(your item 5). A v18 exe SKIPS a v17 DB rather than aborting, and the editor's default
`--from-platform both` draws on Win32, so the failure mode is a silently thinner From
pool -- the stale-schema line is discarded by the editor's JSON slicer. We are holding
the Jul 21 exe staged in the worktree until you confirm.

## STILL OWED -- `--refs-as-leaves` did not make it into v18

Verified by diffing the `proptree` usage lines of the staged Jul-21 exe and main's v18
exe: byte-identical, both `schema proptree/2`, neither accepts the flag. So BLOCKER 1
from `docs/lint/` / `docs/converter/2026-07-21-proptree-v17-integration-blockers.md`
survives the v18 rebuild -- `TcxCheckBox` still expands without bound (~6982 leaves,
public surface times out) and our 30 s watchdog is still the only guard. The ask is
unchanged: cherry-pick converter commit `f65fb9c` (`TPropTreeOptions.TreatRefsAsLeaves`
+ the CLI flag) into `main`, and/or add a size/cycle guard to the R3 concrete-type
recursion.

## Also worth knowing (converter-side trap, no action for you)

`feat/converter-editor` branched before both bumps -- its
`src/storage/DRagLint.Storage.Schema.pas` still reads `SCHEMA_VERSION = 16`. Reading is
fine, but a CLI built from that worktree would stamp v16 on anything it indexes. We will
merge `main` before ever building the CLI there; the editor exe links none of the storage
layer.

## Our action items from your list

- [x] Accept `schema_version = 18` -- nothing to change, the gate is already `>=` and the
      converter pins no version.
- [x] Stop trusting persisted `symbols.id` -- none were ever persisted.
- [ ] Re-run `convert-validate` against the fresh library trees -- **blocked** until both
      libraries read 18.
- [ ] (Optional) evaluate `symbol_facts` (`dfm_event` looks directly useful for event
      wiring during conversion) -- deferred, not on the current branch.

Status doc on our side: `docs/converter/STATUS.md`, section "LATEST (2026-07-23)".
