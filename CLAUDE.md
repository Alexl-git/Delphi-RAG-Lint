# Delphi-RAG-lint -- project instructions

## THE DOCS-IN-SYNC RULE (highest priority in this repo)

**`--help`, `README.md`, and `docs\AI-USAGE.md` are part of the product. A change
to the CLI surface is not finished until all three match the code.**

This is not style advice. It was written after a session found, in one afternoon:

* **four shipping verbs missing from `--help`** -- `usages`, `outline`,
  `ghost-check`, `ghost-recover`. They worked; the banner simply never listed
  them. They were discovered only because the IDE plugin issued them as command
  strings.
* **the entire autofix flag set undocumented** -- `--file`, `--fix`,
  `--fix-line`, `--fix-rule`, `--apply`, `--no-preprocess` on `lint` /
  `lint-all`. 22 of 173 rules are auto-fixable and **a user reading `--help`
  could not discover autofix at all.**
* **`README.md` and `INSTALL.md` claiming "130+ rules"** against a real 173.
* **`docs\AI-*.md` pointing at deleted databases** (`.drag-lint\ORM3-*.sqlite`,
  `DataCopy.sqlite`) months after the `_D-RAG` layout landed.

The common thread: each was correct when written, and nothing failed when it
stopped being correct. **Silence is the failure mode**, so the rule is enforced
by a guard, not by memory.

### What "in sync" means, concretely

| Surface | Must satisfy |
|---|---|
| `--help` | every verb the CLI accepts is listed; every flag a verb accepts is listed on that verb's line |
| `README.md` | rule counts match `drag-lint rules --json`; the verb list is not missing whole features |
| `docs\AI-USAGE.md` | verb list covers the real surface; no DB path that no longer exists |

### The guard

`tests\autotest\run_docs_sync_guard.ps1` runs in the battery and FAILS on drift.
If you add or change a verb or a flag, update the banner and the docs in the
SAME change; do not "fix the docs later".

If the guard is wrong, fix the guard deliberately -- do not weaken it to get
green. A guard that only ever passes is the thing that produced the list above.

## Index layout (do not guess a path)

A project's index is `<project folder>\_D-RAG\<project file base name>.sqlite` --
named after the PROJECT FILE, not the folder. Only the per-platform library
indexes live in `C:\Projects\.drag-lint\`.

Resolve, never guess: `drag-lint resolve-dbs --project <X.dproj>` /
`--in <X.pas>` / `--platform <p>`.

## A PROJECT INDEX IS ONLY AS COMPLETE AS ITS `.dproj` / `.dpr`

**After every full reindex, and before trusting any `lint-all`, reconcile the
project's member list against the units it actually uses.**

Since the 2026-08-11 move to one DB per project, an index is built from the
COMPILE CLOSURE -- the `.dproj`/`.dpr` members plus transitively-used
project-local units. That makes the manifest load-bearing in a way it never was
when a folder walk swept up everything:

* a unit that exists on disk and is USED but is not listed is **not indexed**;
* so `query`, `find-callers`, `lint-all` and the doc facts for that project are
  all silently INCOMPLETE -- not wrong-looking, just short;
* and a project DB is authoritative for membership (`query --name <Unit> --db
  <projectDb> --exact` -- a miss IS non-membership), so the gap answers
  confidently.

**This is the failure mode the per-project layout traded for its speed, and
nothing detects it on its own.** A missing unit produces no error, no warning
and no empty result -- only a smaller answer than the truth.

The engine already carries both checks; the standing requirement is to RUN them:

```
drag-lint reconcile-project <App.dproj> --db <db> --json        (dry run FIRST)
drag-lint lint --project <App.dproj> --rule unit-not-in-dpr
```

Dry-run before `--apply`, always -- `--apply` edits the project file. Fix the
`.dproj`/`.dpr`, then re-index that project INCREMENTALLY (`index --project
<x.dproj> --db <db>`; **never** `index <dir> --db <projectDb>`, which widens a
project DB into a directory DB). Verify the closure actually grew by comparing
`files=` on the section summary before and after.

`files=` is a STOCK -- every row in the database, whichever run wrote it -- so
it is the right field for that before/after comparison and its name is stable.
The same line also carries `walked=`, the unique paths this run ADMITTED to the
walk: `files - walked` is the rows the run never visited and never evicted
(eviction is bounded to the evict roots), which is how a project DB that was
once widened by a folder-target index keeps reporting more files than its
closure has. `attempted=` and `up-to-date=` were previously called `parsed=`
and `skipped=`; the values are unchanged, but `attempted` counts attempts made
BEFORE the parse, so it legitimately exceeds `files=` when a parse fails, and
`up-to-date` is a DIFFERENT population from the log's `SKIP` lines.

Procedure, triage rules and the per-project run list:
`docs\PLAN-project-completeness-sweep.md`.

## Two version constants, and why they are separate

* `DRAGLINT_VERSION` -- the product version. Bump freely for a release.
* `DRAGLINT_EXTRACTOR_VERSION` -- **part of the indexer fingerprint.** Bumping it
  re-parses EVERY database (hours: ~7,000 library files plus every project
  index).

Bump the extractor version ONLY when extraction genuinely changes -- parser or
grammar, an extractor emitting different symbols/refs/uses/call edges, or the
preprocessor changing which branches are parsed. NOT for lint rules, output
formatting, docs, the IDE plugin, or the LSP.

Guarded by `tests\autotest\run_extractor_version_guard.ps1`, which fails when
extractor sources change without the constant moving. The failure mode it
introduces, stated plainly: forgetting to bump after a real extractor change
leaves SILENTLY STALE PARSES, which is worse than a redundant re-parse, because
the index then looks complete and answers confidently with fewer results.

## Encoding

`.pas`, `.dpr`, `.dfm`, `.bat`, `.ps1`: strict 7-bit ASCII, CRLF, no BOM. The
Write/Edit tools emit LF -- normalise after editing or `run_encoding_guard.ps1`
will fail.

## Backing out working-tree changes: STASH, never `checkout --`, and CLEAN UP

**This tree usually holds another team's uncommitted work** (~28 dirty entries
under `src\tools\convrules-editor\` and `src\report\DRagLint.Convert.CastLib.pas`
at the time of writing). Their changes are not committed, not pushed, and some
are not even tracked -- so a destructive working-tree command here can erase work
that has no copy anywhere.

### The rule

* **Never `git checkout -- <paths>`** to back out an experiment. It is
  irreversible, and a path list that is one glob too wide destroys someone
  else's day with no recovery and no prompt.
* **Never a bare `git stash`.** With no pathspec it stashes EVERYTHING, the
  other team's files included, and hands you a single blob to untangle.
* **Do this instead** -- always with an explicit pathspec and an identifying
  message:

  ```
  git stash push -m "agent:<task> -- <why>" -- <path> <path> ...
  ```

  Flags go BEFORE the `--`. `git stash push -- <path> --quiet` parses `--quiet`
  as a pathspec and silently does the wrong thing.

### The cleanup is part of the task, not an afterthought

A stash you created is a loose end, and an orphaned one is indistinguishable
from someone else's. **Before you report, resolve every stash you made:**

* keeping the work -> `git stash pop` (then commit it, or leave it dirty and say so);
* discarding it deliberately -> `git stash drop <ref>`, and say in your report
  that you dropped it and why;
* genuinely unable to resolve it -> **name the exact `stash@{n}` ref and its
  message in your report** so the next person can find it. Never just leave it.

End by running `git stash list` and confirming what you created is gone -- or
accounted for by name. "I think I cleaned up" is not a verification.

The scratchpad-copy-then-revert pattern is no longer needed: a stash IS the
backup, and unlike a copy in `C:\TEMP` it survives in the repo and is visible to
anyone who looks.

## Building

Use the `delphi-build` skill. For the CLI specifically,
`build\build_draglint_win64.bat` is the right entry point: it builds Win64 Debug,
stages the tree-sitter companions beside the linked exe, syncs `rules\` to both
exe directories, and deploys to `third_party\dll-win64\`. The deployed binary is
Win64 **Debug**, not Release.

Never invoke the engine by bare name -- `NoDefaultCurrentDirectoryInExePath` is
set, so `drag-lint ...` resolves off PATH to a stale build. Use `.\drag-lint.exe`
or a full path.
