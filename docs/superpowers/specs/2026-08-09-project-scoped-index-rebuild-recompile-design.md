# Design: project-scoped indexing, with rebuild / recompile

- **Created:** 2026-08-09
- **Status:** design approved in conversation; not implemented
- **Supersedes the deferred half of:** `docs/INBOX-lint-scope-stale-files-and-project-members.md`
  ("a per-project section wants a 'project units only, libraries come from the Library DB' mode")
- **Closes:** `docs/INBOX-ignored-files-already-indexed-are-never-evicted.md`
- **Related:** `docs/lint/PLAN-autodoc-phaseC-2026-08-09.md` (the autodoc queue this interrupts)

---

## The rule, in the user's words

> "Project index must reflect the project. Not more and not less. The only exception to it is used
> library units which are indexed in the library index."

> "We know dpr or dproj members. We know Library member units. The rest might be candidates on
> either library membership or files that should be included in dpr and dproj but were forgotten.
> If a unit is used and is not in project or library, the Linter should issue a warning."

> "When we rebuild or recompile a project it is always the current project from the IDE and each
> project has their own database."

Two ideas do the work here, and they are worth separating because only one of them is new:

1. **Membership is DECLARATIVE, never inferred from paths.** The `.dproj` says who is a member.
   The library index says who is a library. Nothing is classified by "which folder is it in".
2. **The gap between those two sets is a DIAGNOSTIC, not a guess.** A unit that is used but is in
   neither set is still compiled by Delphi, so it is still indexed -- and it is reported, because
   "forgotten from the .dproj" is what it usually means.

## What already exists (most of this)

`DRagLint.Index.Closure.TClosureResolver` already resolves a `.dpr`/`.dproj` to exactly the right
file set. Its own header states the contract:

> member units, every unit they pull in transitively via `uses` that resolves to a project-local
> file (**NOT under a Delphi Library/Browsing path**), plus any `{$I}`/`{$INCLUDE}` include files.
> **Loose files sitting in the project folders that nothing references are NOT included.**

That is the rule above, already implemented and already relied on by `lint-all --project`.
`ReadDCCReferences` (`DRagLint.Lint.ProjectChecks.Parse.pas:213`) reads the member list.

**It has simply never been wired into `index`.** `index --project` today resolves the project's
SEARCH PATHS and walks those folders -- which is why it drags in Spring4D and every loose file
sitting next to the project. The closure resolver is the fix, not new machinery.

Also already present, and NOT the problem: prune-by-default on a folder walk. It deletes indexed
files that no longer exist **on disk**. It has no concept of a file that still exists and is no
longer in scope, which is why `.private\` copies and 104 `C:\Projects\DelphiAST\` files survive
every reindex of YADF.

## Scope of a project index

| | in the index |
|---|---|
| `.dproj` / `.dpr` / `.dpk` member units | yes |
| units reached transitively via `uses`, resolving project-local | yes, **and reported** (see Diagnostic) |
| sibling `.dfm` of any member form | yes |
| `{$I}` include files reached along the way | yes |
| units resolving under a Delphi Library/Browsing path | **no** -- they belong to the library index |
| loose `.pas` in the project folder that nothing references | **no** |
| anything under an ignored path (`.gitignore` etc.) | **no** |

## The three modes

Named to match the IDE's own vocabulary, because that is where they are invoked from.

- **`--recompile`** (default for a project): reparse changed files, drop files that vanished from
  disk, **and evict files that are no longer in scope**. Incremental.
- **`--rebuild`**: wipe the project's DB **content** and index from scratch. It deletes rows, not
  the file -- the schema, its migrations and any settings survive, and no file handle is dropped,
  which matters because the IDE plugin may hold the DB open.
- **`--library`**: index every unit in a folder **and its subfolders**, with no membership concept
  at all.

### Why Library is a separate mode and not a project with loose rules

In the user's words: *"since we don't know what units will be used, we are forced to index all
units in the folder+subfolders."* A library has no `.dproj` to ask, and its consumers add and drop
units on the fly, so there is no member list that could be authoritative. Completeness is the
correct policy there, and it is the exact opposite of the project rule -- which is why it must be
a mode you choose, not a fallback the indexer slides into when it cannot find a project file.
A project that silently degraded to "index everything" would reintroduce the whole defect.

**Library mode is a SCOPE, so it still needs a freshness choice.** The library DBs are large and a
full re-scan is expensive, so `--library` is incremental by default and accepts `--library
--rebuild` for a from-scratch pass. Decided rather than asked, because losing incremental library
indexing would be a regression; say so if you want one Library button and nothing else.

Eviction applies in Library mode too, driven by the section's `exclude` globs rather than by
membership: the `Library` section already excludes `SourceD3`, `Delphi5`, `Delphi7`, `BuildD3`...
so adding an exclude must remove what it now covers, not leave it behind forever. That is the same
defect as `.private`, in the other mode.

**Rebuild is a safety valve, not a correctness requirement.** Once eviction exists, recompile
converges to the same content as rebuild. Rebuild exists for the cases where the incremental state
is not trusted: an engine upgrade that extracts something new (today's `--force-reparse`), schema
migration, or a corrupted DB. Saying this explicitly matters -- otherwise the next person assumes
recompile is the lossy one and reaches for rebuild by default, which is slow for no gain.

### Out-of-scope eviction is the load-bearing new behaviour

After the walk and BEFORE the resolve passes (so uses / ancestry / call edges are recomputed
against the survivors -- the same ordering `PruneMissingFiles` already uses), delete every indexed
file that is not in the current scope set. Reuse the existing cascade: every file-owned table
declares `REFERENCES files(id) ON DELETE CASCADE` and `PRAGMA foreign_keys = ON` is set, so one
`DELETE FROM files` takes symbols / refs / unit_uses / docs with it.

**`string_literals` must still be deleted explicitly first**, exactly as prune does today: its FTS5
shadow tables are synced by `AFTER DELETE` triggers, and SQLite fires triggers for FK-cascaded rows
only when `recursive_triggers` is on. Left to the cascade, `query --text` goes on matching deleted
source. This is a known trap in this codebase, recorded here so the eviction path does not
rediscover it the hard way.

Report what was evicted, with counts, the way prune reports vanished files. A corpus that has been
quietly wrong for months should announce itself once.

## Diagnostic: used, but neither member nor library

A unit reached via `uses`, resolving to a project-local file, that is **not** in the `.dproj`
member list, is indexed and reported. Two surfaces:

- **At index time**, a count plus the unit names. Cheap, immediate, and it is the safety net for
  the "or skip something" failure -- without it, a scope change silently drops source.
- **As a lint rule.** `unit-not-in-dpr` already exists on `lint --project`; check whether it
  already covers this before adding a rule. If it does, wire it, do not duplicate it.

Severity is **warning**, not error: the code compiles, and the fix is a project-file edit, not a
code change.

## DB location

The manifest keeps declaring it. A project's DB path is **derived only when the manifest does not
know that project** -- the IDE opening something unregistered -- as `<outDir>\<ProjectName>.sqlite`,
which is how existing relative section db names already resolve.

Explicit config wins, so nothing already configured moves: `YADF.sqlite` stays in the YADF folder.
On a derived-name collision (two projects sharing a base name in different folders), refuse and
report rather than silently sharing a DB.

## What does NOT change

- The `Library` sections (`source: registry-libraries`) and `SQL` (MS\*.sql, a folder walk with an
  `includeOnly` filter) become **Library-mode** sections. That is what they already do; the mode
  now has a name.
- **ORM3 keeps its union DB, by staying a Library-mode section.**
  `C:\Projects\DB\ORM3\drag-lint.sqlite` unions CLIENT and SERVER, and that union is what the
  dead-form investigation needed -- a CLIENT-only DB produced a false "dead form" because the
  callers lived outside it. Calling ORM3 a "library" is semantically odd and is a transitional
  arrangement, not an endorsement; converting it to two project sections is a separate decision,
  deliberately not taken here.

## Accepted cost: shared units are indexed into every project DB that uses them

`src\core\*` lands in both the CLI DB and the wizard-BPL DB. This is inherent to one-DB-per-project
and was accepted explicitly.

The sharp edge is not the duplication, it is that **`call_edges.target_symbol_id` is a rowid in ONE
database** -- cross-DB edges are not representable (architectural, already recorded). So each DB
answers correctly *for its own project*, and a cross-project question needs several `--db` flags.
Anyone reading a single project DB and concluding "nothing calls this" is making the same mistake
the dead-form investigation made.

## Testing

- `index --project` yields the closure and NOTHING else: a loose unreferenced `.pas` beside the
  project, a unit under a library path, and an ignored file are all absent; a member, a
  transitively-used project-local unit, its `.dfm`, and an `{$I}` include are all present.
- **Eviction**, the regression that matters: index a project, remove a unit from the `.dproj`
  (leaving the file ON DISK, which is what prune cannot catch), recompile, assert the unit's rows
  are gone -- symbols and refs with them.
- **Eviction is scoped**: two projects, two DBs; recompiling one never touches the other.
- `--rebuild` and `--recompile` converge to identical content on the same input. This is the
  claim the design rests on, so it is asserted rather than argued.
- **`--library` indexes what project mode refuses to**: the same fixture's loose unreferenced
  `.pas` IS present in Library mode. Asserting both directions on one fixture is what proves the
  two modes are genuinely different policies rather than the same walk with a filter bolted on.
- Library-mode eviction: add an `exclude` glob covering already-indexed files, recompile, assert
  they are gone.
- The used-but-not-a-member diagnostic fires, names the unit, and is a warning.
- Full battery green (237 at time of writing).

## Not in scope

Option 4 (bare cross-unit calls), intrinsics classification, the five approved doc features and the
final remeasure remain queued behind this in `PLAN-autodoc-phaseC-2026-08-09.md`.
