# Design -- the project `_D-RAG` home, and declared code ownership for lint

Date: 2026-08-11. Status: approved, not yet implemented.
Supersedes nothing; extends `2026-08-09-project-scoped-index-rebuild-recompile-design.md`
(the per-project DB split) by giving each project DB a home beside its project
file, and by teaching lint which of the files in that DB are actually ours.

## 1. The problem

`lint-all` lints every `.pas` file the index contains. A project index is the
project's **compile closure**, which correctly includes vendored third-party
source, so lint inherits the indexer's answer to a different question.

Measured on YADF (2026-08-11): **1,072 findings, 768 of them (72%) in
`C:\Projects\DelphiAST`** -- a vendored parser YADF neither owns nor can fix.
182 of the 183 `inherited-bare` findings were DelphiAST's. YADF's own code has
**304** findings: 0 errors, 70 warnings, 231 info, 3 hints (pre-implementation
estimate, grep-filtered from a whole-corpus 16-file report -- see the
correction below).

**Correction (2026-08-11, final whole-branch review):** a genuinely scoped
`lint-all` run reports **305**, not 304 -- clone detection is set-relative, so
a scoped run claims a slightly different, overlapping set of windows in one
repetitive region of `YadfMain.pas` than grep-filtering the whole-corpus
report did. After the subsequent rule fortifications and YADF source fixes,
the current count is **259**. Treat 259, not 304 or 305, as today's baseline
-- an acceptance run reporting 259 has NOT failed.

This is a SCOPE defect, not a false-positive problem. Indexing scope and linting
scope are different questions and lint is currently answering with the indexer's
answer.

### 1.1 Why ownership cannot be inferred

The obvious heuristics were measured against every configured project index and
each fails on this corpus:

| candidate rule | fails because |
|---|---|
| "under the project file's folder" | ORM3-Micronite2027 has 641 `.pas`, only 270 under `CLIENT\`; 295 of the rest are `ORM3\COMMON\OBJECTS` -- the user's own business objects |
| "under the project's VCS root" | identical result: Mercurial repositories here are per-folder, so `CLIENT`, `SERVER`, `COMMON` and `OBJECTS` are each their own hg root |
| "a different VCS repo means third-party" | classifies those same 295 own files as third-party, AND classifies `PDFlibPas` (no repo at all) as ours -- wrong in both directions |

Per-folder hg repositories are an artefact of the tool, not a statement of
ownership. Ownership is a human fact about a codebase and must be **declared**.

Measured spread of "outside the project folder" per index:

| index | `.pas` | outside | what is out there |
|---|---|---|---|
| YADF | 16 | 8 | `DelphiAST` -- third-party |
| ORM3-Micronite2027 | 641 | 371 | 295 `ORM3\COMMON` (**ours**) + 76 `PDFlibPas` |
| ORM3-MicroniteMW1Service | 459 | 313 | mostly `ORM3\COMMON` (**ours**) |
| TableTools370P | 18 | 9 | 8 `ORM3\COMMON`/`SERVER` (**ours**) + 1 `tzdb` |
| Loader, DataCopy | -- | 0 | nothing outside |
| DragLint-*, Graph-* | -- | corrected: not 0 | this row originally measured "outside" against the REPOSITORY ROOT; the code's default own-root is the project FILE'S OWN folder (e.g. `src\cli` for DragLint-Cli), which is a much narrower scope -- these self-hosting indexes needed explicit `ownRoots` declarations for exactly that reason (a Critical finding from the final review, already fixed by configuration) |

## 2. Non-goals

* Changing what the INDEXER covers. A project index stays the compile closure;
  symbol resolution needs the vendored source and would break without it.
* Moving `library-{platform}.sqlite` or the SQL index. They have no project
  folder. The resulting layout is deliberately mixed.
* Rewriting historical records. `.superpowers/sdd/*` reports, dated plans and
  old RESUME docs keep their stale `C:\Projects\.drag-lint\...` paths; they are
  dated records of what was true then. Only current-state documents are updated.
* Putting third-party dependencies on the IDE Library Path. That was considered
  as an alternative fix and rejected: it cannot express `ORM3\COMMON`, and it
  makes lint scope depend on IDE registry state.

## 3. Section A -- `_D-RAG` is the project's drag-lint home

`_D-RAG` already exists as a convention: the ghost-compile engine writes
`*.ghost-journal`, `*.ghost-orig` and `*.crash-buffer` into a hidden `_D-RAG`
beside the `.dproj` (`DragLint.Plugin.Editor.pas`, `run_ghost_ownership.ps1`).
Both `C:\Projects\YADF\_D-RAG` and `C:\Projects\DB\ORM3\CLIENT\_D-RAG` exist
today. This extends that folder into the project's whole drag-lint home.

### 3.1 The rule

A manifest section whose first `include` target is a `.dproj`, `.dpr` or `.dpk`
(27 of the 29 configured sections) has its DB at:

```
<directory of the project file>\_D-RAG\<project file base name>.sqlite
```

Named after the **project file**, never the folder and never the section name.
Five folders host more than one project and would collide otherwise:

| folder | projects |
|---|---|
| `C:\Projects\YADF` | YADF, YADFOT, YADFSetup |
| `C:\Projects\TableTools` | TableTools370P, MemTableFieldWizard |
| `C:\Projects\DataCopy` | DataCopy, SortTest |
| `C:\Projects\DB\ORM3\PACKAGE` | Interfaces, TestMicroniteObjects |
| `C:\Projects\Delphi-RAG-Lint-Graph\src\pkg` | DragLintGraph, DragLintGraphDb |

### 3.2 Manifest

* `db` becomes OPTIONAL for a project section and is derived by the rule above
  when omitted.
* An explicit `db` still wins, unchanged -- the escape hatch for a project that
  must keep its index elsewhere (read-only source trees, network shares).
* Section `name` is untouched, so `index --all --only ORM3-Micronite2027` and
  every `--db` path a human has memorised keep working.
* `outDir` survives for the two non-project sections and as the default for any
  future folder-scan section.

### 3.3 Migration

A `migrate-dbs` verb, `--dry-run` by default, `--apply` to act:

1. Refuse to run if RAD Studio is running. The IDE's LSP holds these files open
   and a move would fail halfway. Name the process in the error.
2. For each project section: checkpoint WAL (`PRAGMA wal_checkpoint(TRUNCATE)`),
   create `_D-RAG` if absent, move `.sqlite` **together with** its `-wal` and
   `-shm` siblings -- all 27 have both today.
3. Verify each moved DB opens and reports the same `files` row count as before
   the move.
4. Rewrite the manifest: drop the now-derivable `db` from project sections.
5. Print the VCS-ignore instructions (3.4).

292 MB across 27 databases. **No reindex is required**: `schema_meta` holds only
`indexer_fingerprint` and `schema_version`, and no table stores the database's
own path. This was verified before choosing a plain file move.

### 3.4 VCS hygiene -- the one new hazard

The DB now lives inside a working copy and must not be committed.

* **git** (YADF, Delphi-RAG-lint, Graph, DelphiAST): the migration writes
  `_D-RAG\.gitignore` containing `*`, which makes the folder self-ignoring.
  The indexer does the same whenever it creates a `_D-RAG`.
* **Mercurial** (ORM3 CLIENT/SERVER/COMMON/OBJECTS/PACKAGE, TableTools,
  Loader2019, DataCopy): hg has no self-ignore. The migration PRINTS the exact
  line and the exact `.hgignore` path per repository and does not edit them --
  a tool that silently rewrites a repo's ignore file is worse than one that
  tells you what to paste.

## 4. Section B -- declared ownership, and what lint does with it

### 4.1 The declaration

```
<project folder>\_D-RAG\drag-lint-project.json
{ "ownRoots": ["C:\\Projects\\DB\\ORM3"] }
```

`ownRoots` is a list of directory roots, each either absolute or **relative to
the project folder the declaration sits in**. A file is OURS when it sits under
any of them (prefix match on the normalised path, case-insensitive, matching
`DRagLint.Storage.FileMembership.NormalizeForLookup`). Relative entries keep a
declaration portable and short -- ORM3's eight sections each declare `[".."]`
rather than repeating an absolute path that breaks if the tree moves.

**Default when the file is absent, unreadable, or declares no roots: the
project file's own folder.** That suffices only where the `.dproj` sits AT the
root of the code it owns -- YADF, DataCopy, Loader, OCRPDF.

**CORRECTED 2026-08-12, after the final review measured it.** An earlier draft
of this section claimed the default also covered `DragLint-*` and `Graph-*`.
That was wrong, and the error is worth recording because it is easy to repeat:
the measurement behind it was taken against each project's **repository root**,
while the code defaults to the **project file's folder**. Those differ whenever
the `.dproj` lives in a subdirectory. `drag-lint`'s own project file is at
`src\cli\drag-lint.dproj`, so the default own-root was `src\cli` -- three files,
with the other 94 units of the engine classified as third-party. Nine of the 27
configured sections were affected.

Declarations actually required across the corpus:

| project | `ownRoots` |
|---|---|
| all 8 ORM3 sections | `[".."]`, or `["..\\.."]` from the four `TESTER\*` folders |
| TableTools (both) | `[".", "C:\\Projects\\DB\\ORM3"]` |
| DragLint-Cli / -Wizard / -CorpusScan, all 5 Graph sections | `["..\\.."]` |
| DragLint-Tests | `[".."]` |

The lesson generalises: **the default is only right when the project file sits
at the root of its own code.** A `.dproj` in a subdirectory always needs a
declaration, and the skip report is what surfaces that -- on `drag-lint` itself
it read "94 file(s) outside the project's own roots skipped", which is exactly
the signal the report exists to give.

An empty `ownRoots: []` is a usage error, not "own nothing" -- the same
reasoning as the existing refusal to lint an empty `--project` scope, because
scoping to nothing reports a clean project.

### 4.2 Finding the declaration

`lint-all` resolves the project anchor from the DB path it was given: with the
DB at `<proj>\_D-RAG\<name>.sqlite`, the anchor is simply the parent of the
`_D-RAG` folder. No manifest lookup, and none of the CWD-sensitivity that the
existing `drag-lint-lint.json` discovery suffers from (already documented in
this repo's own config: the YADF pipeline runs from `C:\TEMP` and never found
it).

Fallbacks, in order: `--project` if given; else the `_D-RAG` parent; else the
manifest section whose `db` matches; else no filtering at all with a stated
reason on stderr.

### 4.3 Where the filter applies

In `DoLintAll` (`DRagLint.CLI.pas`), the own-roots test goes **beside
`Cfg.IsPathExcluded`**, before the scan, so an out-of-scope file never reaches
the scanner and the banner counts what was actually scanned.

The same predicate is then applied to the findings of the PROJECT-WIDE pass,
next to the existing `ScopeSet` filter. Without that, god-class, clone
detection, layering, doc rules and `used-unit-not-resolvable` read the whole
store and walk the third-party noise straight back in -- this is exactly the
failure the `--project` scope filter already documents.

### 4.4 Interaction with what exists

* `exclude_paths` keeps working and now has a clean meaning: **vendored INSIDE
  your own roots**, e.g. drag-lint's `third_party\delphi-tree-sitter`. Own-roots
  is the whitelist, `exclude_paths` the blacklist within it; both apply.
* `--project` is unchanged and composes as an intersection: compile closure AND
  own roots.
* `--lint-third-party` restores today's behaviour exactly, for a deliberate
  sweep of a vendored dependency.

### 4.5 Reporting

A scope filter that reports nothing is indistinguishable from a clean codebase.
Skipped files are always named by root, with the fix spelled out:

```
lint-all: scanning 8 .pas file(s)
lint-all: 8 file(s) outside the project's own roots skipped
            8  C:\Projects\DelphiAST
          declare in C:\Projects\YADF\_D-RAG\drag-lint-project.json to include
lint-all: 304 finding(s) -- 0 error(s), 70 warning(s), 231 info, 3 hint
```

(Sample numbers as originally measured -- see the 305/259 correction in
section 1; the per-severity breakdown for 305/259 was not separately
recorded, so this illustration keeps the original, internally-consistent
304 figures rather than mixing a corrected total with a stale breakdown.)

Grouping is defined precisely, because "group by directory" would print two
lines for DelphiAST (`Source` and `Source\SimpleParser`) instead of naming the
dependency: start from each skipped file's directory, then repeatedly merge
groups that share a common parent directory, stopping before any parent that is
an ancestor of one of the project's own roots. YADF's eight files collapse to
`C:\Projects\DelphiAST` (the next merge would reach `C:\Projects`, an ancestor
of the own root `C:\Projects\YADF`); ORM3's collapse to `C:\Projects\PDFlibPas`
by the same stop condition. Capped at the 10 largest groups with a "+N more"
line. The report file gets the same block. On `--json` / `--format sarif` these
lines go to stderr, per `docs\INBOX-lint-all-json-stdout-banner.md`.

Expected effect: YADF 1,072 -> 305 as originally scoped (now 259 after
subsequent rule fortifications and YADF source fixes -- see the correction in
section 1). ORM3-Micronite2027 keeps all 295 `COMMON\OBJECTS` files and drops
the 76 `PDFlibPas` ones.

## 5. Testing

* `tests\autotest\run_lint_own_roots.ps1` (new) -- fixture tree with a project
  and a sibling `vendor` folder:
  1. bare run skips the vendor files;
  2. the banner NAMES the skipped root (not just a count);
  3. `--lint-third-party` brings them back, restoring the old total;
  4. an `ownRoots` declaration naming the sibling widens the scope to include
     it -- proving the declaration is read, not just the default applied;
  5. a project-wide rule (`duplicate-code`) does not report a clone whose only
     other copy is in the vendor folder.
* `tests\autotest\run_manifest.ps1` -- derived DB path for a section with no
  `db`, including two projects in one folder resolving to distinct files, and
  an explicit `db` still winning.
* `tests\autotest\run_migrate_dbs.ps1` (new) -- dry-run lists every move without
  touching disk; apply moves `.sqlite` + `-wal` + `-shm`, preserves the `files`
  row count, and writes `_D-RAG\.gitignore`.
* Full battery must return to its known 249/253 baseline (4 known failures) and
  lint fixtures to 161/161.

## 6. Risks and mitigations

| risk | mitigation |
|---|---|
| A move fails half way, leaving a project with no index | Move `.sqlite`+`-wal`+`-shm` per project and verify before the next; a failure stops the run naming the project. Worst case is a reindex of one project. |
| The IDE holds a DB open | Refuse to run while RAD Studio is running. |
| A DB gets committed into a working copy | `.gitignore` written automatically; printed instructions for the four hg repos. |
| The default silently hides own code in a project not yet declared | The skip is always reported by root with the fix spelled out; `--lint-third-party` is one flag away. |
| Stale absolute paths in docs/scripts | 4 `.pas` files, 6 battery scripts and ~12 current-state docs are updated, plus `C:\Projects\CLAUDE.md` and the auto-memory index. Historical records are left alone by design (section 2). |

## 7. Files expected to change

* `src\index\DRagLint.Index.Manifest.pas` -- derived DB path, optional `db`.
* `src\cli\DRagLint.CLI.pas` -- own-roots resolution + filter in `DoLintAll`,
  `--lint-third-party`, the `migrate-dbs` verb, help text.
* `src\project\DRagLint.Project.OwnRoots.pas` (NEW) -- reads
  `drag-lint-project.json`, applies the default, answers "is this file ours?".
  A dedicated unit rather than another responsibility on `DRagLint.Lint.Config`,
  for the reason `DRagLint.Storage.FileMembership` gives: consumers that need
  only this one question (the LSP, the IDE plugin) must not drag in the lint
  config machinery to ask it.
* `src\delphi-plugin\DragLint.Plugin.DbResolver.pas`, `...Editor.pas`,
  `...Settings.pas` -- `_D-RAG` in the DB path template and resolution order.
* `src\storage\DRagLint.Storage.SQLite.pas` -- the hardcoded default path.
* Battery: `run_manifest.ps1`, `run_wiring.ps1`, `run_exe_freshness.ps1`,
  `run_qname_row_order.ps1`, `run_hover_qname_row_order.ps1`,
  `run_battery.ps1`, plus the two new scripts.
* Docs: `README.md`, `docs\INDEXING-AND-DB-ARCHITECTURE.md`,
  `docs\SCAN-DATABASES.md`, `docs\INSTALL.md`, `docs\editors\*`,
  `CHANGELOG.md`, `skills\relint\SKILL.md`, `C:\Projects\CLAUDE.md`.

## 8. Sequencing

Section A lands first (layout + migration + consumers green), because Section B
resolves its declaration from the DB's `_D-RAG` parent. Both ship this session;
the battery is the gate between them.
