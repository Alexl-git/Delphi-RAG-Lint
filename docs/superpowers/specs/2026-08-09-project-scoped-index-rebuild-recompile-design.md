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

## Two independent axes: SCAN TYPE and MODE

These are different things and conflating them is what made the first draft of this spec awkward
(it bolted `--rebuild` onto `--library` as a special case). They are orthogonal:

- **SCAN TYPE -- what is in scope.** `Project` (the `.dproj` closure) or `Library` (a folder and
  its subfolders, everything).
- **MODE -- how much is redone.** `Rebuild` (from scratch) or `Recompile` (incremental).

All four combinations are meaningful:

| | **Recompile** (incremental, default) | **Rebuild** (from scratch) |
|---|---|---|
| **Project** scan | the everyday IDE action on the current project | after an engine upgrade, or when the DB is not trusted |
| **Library** scan | pick up newly installed / updated library units | full re-scan of a library tree |

### Scan type is DECLARED, mode is CHOSEN per run

Scan type is a property of the target, not a flag you toggle: a `.dproj` is a project scan, a
folder root is a library scan. The manifest section declares it by what it points at, and the IDE
knows it has a project open. So there is no `--scan` flag to get wrong, and -- the part that
matters -- **a project can never silently degrade into a library scan.** A missing or unreadable
`.dproj` fails loudly instead of falling back to "index everything", which would walk the whole
defect straight back in.

Mode is the run-time choice: `--rebuild`, or `--recompile` (default). Named to match the IDE's own
vocabulary, because that is where they are invoked from.

### Why Library scan exists at all

In the user's words: *"since we don't know what units will be used, we are forced to index all
units in the folder+subfolders."* A library has no `.dproj` to ask, and its consumers add and drop
units on the fly, so no member list could be authoritative. Completeness is the correct policy
there -- the exact opposite of the project rule, which is why it is a distinct scan type rather
than a looser setting on the same one.

### Eviction applies to both scan types

Its input is just "what is in scope now":

- **Project scan:** the closure. A unit removed from the `.dproj` is evicted even though the file
  is still on disk -- which is precisely what prune cannot do.
- **Library scan:** the folder tree minus the section's `exclude` globs. The `Library` section
  already excludes `SourceD3`, `Delphi5`, `Delphi7`, `BuildD3`... and today, adding an exclude
  leaves everything it now covers indexed forever. Same defect as `.private`, other scan type.

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
  `includeOnly` filter) become **Library-scan** sections. That is what they already do; the scan
  type now has a name.
## ORM3 converts to separate projects

Decided 2026-08-09: *"These are in fact several projects."* The union DB
`C:\Projects\DB\ORM3\drag-lint.sqlite` is replaced by one project section per `.dproj`:

| project | file |
|---|---|
| Micronite2027 | `CLIENT\Micronite2027.dproj` |
| MicroniteMW1Service | `SERVER\MicroniteMW1Service.dproj` |
| Interfaces | `PACKAGE\Interfaces.dproj` |
| TestMicroniteObjects | `PACKAGE\TestMicroniteObjects.dproj` |
| MicroniteTests | `TESTER\Tests\MicroniteTests.dproj` |
| TestCachedUpdates | `TESTER\CachedUpdates\TestCachedUpdates.dproj` |
| PdfOcrImportTests | `TESTER\PdfOcrImport\PdfOcrImportTests.dproj` |
| TEST_uSetupDefaultsFrm | `TESTER\TEST_uSetupDefaultsFrm\TEST_uSetupDefaultsFrm.dproj` |

`COMMON\` is shared by CLIENT and SERVER, so it is indexed into both DBs. That is the accepted
duplication.

**This retires the arrangement the dead-form investigation relied on.** That investigation reached
a false "dead form" conclusion from a CLIENT-only DB, because the callers lived outside it, and the
fix at the time was "use the full ORM3 db". After this change there is no full ORM3 db -- so the
answer has to come from querying the group, which is why the next section exists rather than
leaving it as a caveat.

### Cross-project search must be DISCOVERABLE, not remembered

The user's own objection: *"In situations where AI need to work on both projects at once, AI would
need to know to use 2 index files for a search."* Requiring anyone to remember eight DB paths is
how the dead-form mistake happens a second time.

- Sections gain an optional **`group`** (e.g. `"ORM3"`).
- **`resolve-dbs --group ORM3`** returns every DB in that group, for consumers that already accept
  repeated `--db`.
- A single-project answer that could plausibly be wrong across projects -- `find-callers`,
  `unused-public-symbol`, dead-form style reasoning -- should say which DB it searched, so
  "no callers" is never mistaken for "no callers anywhere".

### Migration -- do not delete the union DB first

`C:\Projects\CLAUDE.md` documents `C:\Projects\DB\ORM3\drag-lint.sqlite` as the canonical ORM3
index, and the auto-memory references it too. Build the per-project set, verify it, update those
references, and only then retire the union DB. A half-migrated state where the docs name a DB that
no longer exists is worse than either end state.

## Accepted cost: shared units are indexed into every project DB that uses them

`src\core\*` lands in both the CLI DB and the wizard-BPL DB; ORM3's `COMMON\` lands in both CLIENT
and SERVER. This is inherent to one-DB-per-project and was accepted explicitly.

The sharp edge is not the duplication, it is that **`call_edges.target_symbol_id` is a rowid in ONE
database** -- cross-DB edges are not representable (architectural, already recorded). So each DB
answers correctly *for its own project*, and a cross-project question needs several `--db` flags.
Anyone reading a single project DB and concluding "nothing calls this" is making exactly the
mistake the dead-form investigation made -- which is what `resolve-dbs --group` and the
which-DB-did-I-search reporting above are there to prevent.

## Testing

- `index --project` yields the closure and NOTHING else: a loose unreferenced `.pas` beside the
  project, a unit under a library path, and an ignored file are all absent; a member, a
  transitively-used project-local unit, its `.dfm`, and an `{$I}` include are all present.
- **Eviction**, the regression that matters: index a project, remove a unit from the `.dproj`
  (leaving the file ON DISK, which is what prune cannot catch), recompile, assert the unit's rows
  are gone -- symbols and refs with them.
- **Eviction is scoped**: two projects, two DBs; recompiling one never touches the other.
- `--rebuild` and `--recompile` converge to identical content on the same input. This is the
  claim the design rests on, so it is asserted rather than argued -- and it is asserted for BOTH
  scan types, since the axes are independent and a bug could easily hit only one pairing.
- **Library scan indexes what Project scan refuses to**: the same fixture's loose unreferenced
  `.pas` is ABSENT under Project scan and PRESENT under Library scan. Asserting both directions on
  one fixture is what proves the two are genuinely different policies rather than the same walk
  with a filter bolted on.
- **A project scan never degrades to a library scan**: point it at a missing / malformed `.dproj`
  and it must fail loudly, not index the folder. This is the guard on the whole design.
- Library-scan eviction: add an `exclude` glob covering already-indexed files, recompile, assert
  they are gone.
- The used-but-not-a-member diagnostic fires, names the unit, and is a warning.
- Full battery green (237 at time of writing).

## Not in scope

Option 4 (bare cross-unit calls), intrinsics classification, the five approved doc features and the
final remeasure remain queued behind this in `PLAN-autodoc-phaseC-2026-08-09.md`.
