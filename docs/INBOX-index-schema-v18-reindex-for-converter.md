# INBOX -> component-conversion workstream: index is now schema v18 + full reindex (2026-07-23)

**For:** whoever works on the component converter (`convert-apply`, `convert-validate`,
`convert-scaffold`, the convrules editor, and the `proptree` engine that feeds them).
**From:** the hover/indexing session, 2026-07-23.
**TL;DR:** every drag-lint index on this machine was rebuilt to **schema_version 18**,
which adds one **additive** table (`symbol_facts`). Nothing the converter reads was
removed or renamed, but **symbol IDs were reassigned by the reindex** and the library
DBs were rebuilt -- re-resolve by `qualified_name`, don't trust cached `symbols.id`.

## What changed

1. **Schema bumped v17 -> v18.** The only structural change is a new table
   `symbol_facts` (per-routine analysis facts: cyclomatic + body LOC, own-field
   reads/writes, SQL tables touched, paired-`.dfm` event wiring, returned-object
   ownership). It is keyed by `symbol_id` and purely additive. Full column reference:
   `docs/INDEX-SCHEMA.md` section **2.15** (updated this session). The version gate is a
   `>=` check, so this is backward-safe: a consumer that ignores `symbol_facts` is
   unaffected, and a pre-v18 DB simply has no such table.

2. **Every index was reindexed to v18 in one pass (2026-07-23):**
   - Projects: `ORM3`, `SQL`, `Loader`, `TableTools`, `DragLint` (self), `DragLintGraph`,
     `OCRPDF` -- all at `schema_version = 18`.
   - Libraries: `C:\Projects\.drag-lint\library-Win64.sqlite` (v18) and
     `library-Win32.sqlite` (rebuilding to v18 as of this writing -- confirm it reads 18
     before relying on it).

3. **`symbols.id` (rowids) were REASSIGNED.** A full reindex re-creates the `symbols`
   rows, so any `symbols.id` the converter persisted or cached across sessions
   (property-tree caches, id-keyed maps, saved convrules that stored ids) is now stale.
   **Re-resolve everything by `qualified_name`** at query time. This is the one thing
   most likely to bite the converter.

4. **`symbols.prop_access` (added v17) is now populated across all reindexed DBs.**
   Previously the ORM3 sample had NOT been reindexed since v17, so `prop_access` read
   NULL everywhere; it now carries real `ro`/`rw`/`wo` values. The `proptree` engine's
   `is_writable` resolution therefore has real data to work with on every DB now -- if
   the converter tuned any behavior around `prop_access` being empty, re-check it.

5. **The deployed Win64 CLI (`third_party\dll-win64\drag-lint.exe`) is being replaced**
   with a newer build. This session's code changes were LSP/hover-only
   (`document`/`hover` symbol resolution + a plugin popup theme fix) -- the
   `proptree` / `convert-*` verbs are unchanged in behavior. Just be aware the exe the
   converter spawns is a fresh build.

## Action items for the converter

- [ ] Accept `schema_version = 18` anywhere the converter checks/pins a version (the
      gate is `>=`; treat 18 as "17 + symbol_facts").
- [ ] Stop trusting any persisted `symbols.id`; re-resolve by `qualified_name` after
      this reindex.
- [ ] Re-run any convrules validation (`convert-validate`) against the fresh DBs -- the
      library property trees were rebuilt (grammar/parser improvements since the last
      library index are now reflected), so `#link` / `#default` path resolution may see
      slightly different trees.
- [ ] (Optional) `symbol_facts` is available if useful to conversion analysis --
      e.g. `dfm_event` (which published method a component event is wired to),
      `reads_fields`/`writes_fields`, or `sql_reads`/`sql_writes`. Ignore it otherwise.

## Not relevant to the converter (context only)

- Fixed an LSP hover bug: hovering a qualified call like `TFoo.Create(...)` resolved to
  an arbitrary same-named symbol (often an alphabetically-first library hit) instead of
  the real member; now anchored to the file's home store + qualifier via
  `TTypeAtResolver`. Regression test `tests/autotest/run_hover_callsite.ps1`.
- Fixed the hover popup ignoring a dark VCL IDE theme (rebuilt `dclDragLintWizard.bpl`).

Questions -> see `docs/INDEX-SCHEMA.md` (v18) and the SDD ledger
`.superpowers/sdd/progress.md` (Auto-Document Phase 2, which introduced `symbol_facts`).
