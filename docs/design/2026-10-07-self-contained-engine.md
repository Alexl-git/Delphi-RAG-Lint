# A self-contained engine, configured inside the analysed repository

Status: done (E1, E4, E2, E3a, E3b, S4). Rulings by the contributing team (a Delphi 10.3 shop,
a production codebase) on 2026-10-06/07/08 and 2026-10-14; "the team" below. This document records WHAT was
decided and WHY; the CHANGELOG `Unreleased` section has the per-change detail and measurements,
and the commit messages the implementation notes.

## Why

On 2026-10-06 the team found that one ordinary `index` of a Delphi 10.3 project depended on
three things outside both the tool and the project:

- the `sqlite3.dll` loaded was whichever one PATH reached first -- RAD Studio 13's;
- every Studio path and registry key was pinned to 37.0 (Delphi 13), so the 10.3 project got
  Delphi 13's Library path and `VER370`, unless an environment variable (`BDS`) and a hand-made
  copy of the `.dproj` said otherwise;
- the configuration came from six files with six search rules, two of them relative to the CWD
  and one to the exe's sibling folders, so the same command answered differently depending on
  where the shell stood.

That conflicts with the goal the team set: **drag-lint is a separate, self-contained tool that
will become an MCP server.** Nothing may depend on the CWD, on PATH, on a Delphi install's DLLs,
on a fixed registry version or on a global manifest. The project is alpha, so structural changes
go in now, even when they break compatibility.

## Rulings

| # | Question | Ruling |
|---|---|---|
| R1 | Which SQLite? | Ship the SAME `sqlite3.dll` 3.45.3 that built every existing database (from Studio 37.0 `bin64`), beside the exe. Upgrade later, on purpose and measured. |
| R2 | Where does the Delphi version come from? | Stop reading `BDS`. Order: `--delphi`, then the project's `"delphi"` in `config.json`, then the `.dproj` `<ProjectVersion>` through a table of VERIFIED ranges only; an explicit `--delphi` or `"delphi"` that cannot be used is an error naming the fix; a `<ProjectVersion>` that does not map, or names a Delphi not installed, falls back to the default Studio with a note on stderr (a setup that worked before keeps working). |
| R3 | Where do index and configuration live? | "Like CodeGraph, simple and practical": ONE `_D-RAG\` folder at the ROOT of the analysed repository (not one per `.dproj`), found by walking up like git. No global manifest. |
| R4 | What about version control of the analysed repo? | `_D-RAG\` is the only thing drag-lint writes there; source files stay read-only. It is ignored like `.codegraph\` (`.gitignore` inside it, a `.cvsignore` line for CVS; an SVN working copy simply leaves it unversioned). |
| R5 | Where do the per-platform library indexes go? | Beside the engine: `<exe dir>\library\<bds>\library-<platform>.sqlite` -- they describe a Delphi install, not a repository. Building them was deferred ("not now", 2026-10-08). |
| R6 | How to land E3? | In two phases, each with a green battery: E3a adds the new discovery with priority; E3b gives `config.json` every key the old sources answered. **The old sources STAY** (ruling 2026-10-14, replacing "E3b removes them"): nothing an existing user relies on -- the manifest beside the exe, `.drag-lint.json`, the loose `drag-lint-*.json` files, the IDE plugin's manifest lookup -- may break. |
| R7 | The preprocess test oracle lives outside the repo. | For now a check that cannot run is an explicit SKIP with its reason; bringing the JS oracle in comes later. |
| R8 | Scoped purity (S4) | The scoped result must be IDENTICAL to a whole pass -- proved differentially, row by row -- not "close enough". |

## Steps

### E1 -- the engine ships its SQLite

`third_party\dll-win64\sqlite3.dll` (record in `third_party\SQLITE-VERSION.txt`) is staged
beside the exe by the build and the release packer; one `TFDPhysSQLiteDriverLink.VendorLib`
pins every connection to `<exe dir>\sqlite3.dll`. A missing file is exit 3 naming the path;
PATH is never consulted. Same bytes as before, so every existing database reads identically.

### E4 -- an oracle that is not there is a SKIP

The preprocess runners look for the oracle in `tests\preprocess\oracle\` and for `node`; when
either is missing, each oracle comparison prints `[SKIP] ... -- <reason>`, the runner exits 77,
and the battery counts SKIP apart from PASS. Other machine-dependent tests are listed as an open
follow-up (they should get the same treatment).

### E2 -- the Delphi target comes from the project

`TStudioEnv` holds a target resolved per run (R2). The project resolver, the closure, compile
check and the preprocessor's `VER<N>` / `CompilerVersion` follow it. The closure searches the
Library search path after the project's own path, as dcc does, and only Studio-owned folders
count as library -- on ProjectA 67.7% of the call edges target component folders only the Library
path names. Acceptance: the real `.dproj` with no `BDS` produced the same closure and the same
call edges as the old environment-variable-plus-copy setup.

### E3a -- `init` and `<root>\_D-RAG\config.json`

`drag-lint init` writes the config (projects with their Delphi, plus the `lint` and `layers`
blocks that replace the loose JSON files); every verb walks up from its own path argument, else
the CWD. A config found that way wins over every older source and is merged with none, so a
repository answers the same from any subfolder. `index` with no target builds every project, each
in its own process so each gets its own Delphi. A run naming no project takes the Delphi all
configured projects agree on.

Considered and rejected: merging `config.json` with the old sources during the transition (the
answer would again depend on where the shell stands); one `_D-RAG\` per `.dproj` (the first
reading of the ruling, corrected to R3 by the team); a global manifest listing repositories
(R3).

### E3b -- config.json answers everything the old sources answered

Inside a configured repository `config.json` now carries `"ownRoots"`, the `.drag-lint.json` run
defaults (`"rule"`, `"watch"`, `"docs"`), works as `--config` on the manifest verbs, feeds the
LSP's `"lint"` block, and `register-project` there points at `init --project`. Outside a
configured repository every old source answers exactly as before, and inside one the loose
`drag-lint-*.json` files still answer for a key `config.json` does not set.

### S4 -- purity re-derives only what an incremental can move

Chosen by the team from a performance review of the index (2026-10-07). After a scoped call
pass, only the routines whose verdict can move are re-derived; the rest keep their stored
verdict as constants. For the scoped and whole runs to write the same rows, the witness had to
become canonical (per strongly connected component). S4 ships in the index-speed pull
request, with the resolver bump it needs.
Measured: a typical form edit 32.9 s -> 9.5 s, 0 of 36,027 rows different.
`DRAGLINT_NO_SCOPED_PURITY=1` is the escape hatch and the reference the tests compare against.

## Known consequences and open items

- **The IDE plugin and the Config tool read `config.json`.** The plugin resolves a configured
  repository's indexes from it before the global manifest; the Config tool shows a configured
  repository's projects read-only and never saves them into the global manifest.
- **`<exe dir>\library\` must be writable**; an engine installed under `Program Files` cannot
  build a library index there. The index run now says so -- folder, reason, and that library
  indexes live beside the engine -- instead of a FATAL.
- **`init` in an SVN working copy** prints (does not run) the `svn propset svn:ignore` command
  that keeps `_D-RAG\` out of `svn status`; CVS gets a `.cvsignore` line, git a `.gitignore`.
- **Suspicion, unconfirmed:** after moving a database from the old setup to the real `.dproj`
  (E2), its call edges had drifted from a full derivation (unbound refs 167,981 -> 108,680 once a
  whole pass ran). The likely cause is that a change of the project's recorded namespaces does not
  force a whole call pass.
- **Deferred:** building the library indexes (R5), the in-repo JS oracle (R7), loading only part
  of the database in the purity stage (~8 s left in the typical case).

## Compatibility

Nothing an existing setup uses is removed: without a `_D-RAG\config.json` above the path or the
CWD, every verb finds its configuration and indexes exactly as before (global manifest,
`.drag-lint.json`, loose `drag-lint-*.json`, `<project dir>\_D-RAG\<project>.sqlite`). The only
behaviour that changes for everyone is E2 -- `$BDS` is no longer read; the Delphi comes from
`--delphi` or the project -- and E1, the bundled `sqlite3.dll`.

## Migrating a repository

```
drag-lint init <repo root>                         (review the projects and their "delphi")
drag-lint init <repo root> --project <x.dproj>     (add one it did not find, or one left out)
drag-lint index                                    (from inside the repository: every project)
```

An existing project index can be moved to `<root>\_D-RAG\<name>.sqlite` instead of rebuilt; the
first incremental re-derives what the version constants require.
