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

## Building

Use the `delphi-build` skill. For the CLI specifically,
`build\build_draglint_win64.bat` is the right entry point: it builds Win64 Debug,
stages the tree-sitter companions beside the linked exe, syncs `rules\` to both
exe directories, and deploys to `third_party\dll-win64\`. The deployed binary is
Win64 **Debug**, not Release.

Never invoke the engine by bare name -- `NoDefaultCurrentDirectoryInExePath` is
set, so `drag-lint ...` resolves off PATH to a stale build. Use `.\drag-lint.exe`
or a full path.
