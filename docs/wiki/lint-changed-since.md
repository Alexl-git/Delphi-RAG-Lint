# Lint only what changed since a revision

`drag-lint lint-all --changed-since <rev>` runs the whole project lint and then keeps only the findings on lines
that changed since the revision. Use it as a gate for new work: old findings on untouched lines stay out of the
report, the exit code and `--write-baseline`.

```
drag-lint lint-all --db <db> --changed-since HEAD~5          (git)
drag-lint lint-all --db <db> --changed-since tip              (hg)
drag-lint lint-all --project <App.dproj> --changed-since v1.55.0
```

It works in a git and in a Mercurial (hg) working copy. The engine runs `git` or `hg` from PATH, reads their
answer and writes nothing: no index refresh, no commit, no file.

## What counts as changed

The working copy as it is on disk now (committed, staged and not yet committed edits together) is compared
with the revision.

| Case | Result |
|---|---|
| a line added or modified since the revision | changed |
| lines deleted | no line of the present file is changed by a deletion |
| a line that only moved down or up because lines above it changed | not changed |
| a file the revision does not hold: added, renamed to this name, or not tracked yet | every line is changed |
| a file your ignore rules exclude | not changed |
| a file outside the working copy (a library, another repository) | dropped, counted in the note |
| a finding that names no file | dropped, counted in the note |

A rename is never detected by similarity, in either tool: a renamed file is a new file. A finding is kept when
its span (`start_line` to `end_line`) overlaps a changed run of lines.

The whole project is still linted first, so project-wide rules (unused-public-symbol, the uses rules) see the
complete index; only the report is narrowed. The text run prints one note line:

```
lint-all: --changed-since v1.55.0 (git 4f0c2a91d3e7, working copy C:\Work\App) -- 4 of 216 finding(s) are on lines changed since it, in 9 changed file(s); dropped: 210 on unchanged lines, 2 outside the working copy, 0 without a file
```

Under `--json` / `--format json|sarif` the note is not printed; stdout is the narrowed document.

## Which working copy

* With `--project <file.dproj>`: the working copy that holds the project file's folder.
* Without it: the working copy that holds the current directory, as `git` and `hg` themselves read it.

The nearest folder upwards with a `.git` or a `.hg` is the root. The `--db` path is never used for this: an
index may live anywhere.

## It refuses instead of guessing

Every case below ends with `ERROR: lint-all: --changed-since <rev>: <reason>. Nothing was answered.` and exit
code 2. All but the last row are refused before the scan starts, so a wrong flag never costs a whole lint run;
none of them ever produces an unfiltered report.

| Situation | Reason given |
|---|---|
| the revision is not known to the tool | `unknown revision "<rev>" in the git working copy <root>` plus the tool's own line |
| the folder is in no working copy | `the folder <dir> is under no version control (no .git or .hg in it or in any parent folder)` |
| one folder holds both a `.git` and a `.hg` | `the folder <dir> holds both a .git and a .hg, and the tool is not chosen for you` |
| an hg revset that names several changesets | `"<rev>" names <n> changesets ...; give one` |
| `git` / `hg` is not on PATH | `<tool> could not be started in <root> (Windows error <n>; is it on PATH?)` |
| a revision with a leading `-`, a double quote, a control character or a trailing backslash | `is not a revision name this flag passes on` |
| the tool's diff fails or has a shape the engine cannot read | the tool, the step and the diff line |

## Keep the index current

Findings carry the line numbers of the files as lint-all scanned them; the diff is taken from the same files
on disk. Reindex after editing (`drag-lint index --project <App.dproj> --db <db>`) as for any lint-all run.

## For tool authors

The changed-lines reader is `DRagLint.Query.Vcs` (`FindWorkingCopy`, `ResolveRevision`, `ChangedLinesSince`,
`IVcsChangedLines`); `DRagLint.CLI.ChangedSince` is its first caller. Guard:
`tests\autotest\run_v156_VCS1.ps1` builds a scratch git and a scratch hg repository and checks the kept
findings, the note and every refusal above except the missing tool. Not an extractor change;
`DRAGLINT_EXTRACTOR_VERSION` is untouched.
