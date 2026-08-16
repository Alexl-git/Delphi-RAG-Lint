> **RETIRED to INBOX-Done/ on 2026-08-15.** DEFECT WHOSE FIX IS SHIPPED and guarded by a green regression runner in the full battery.
>
> Original note follows unchanged.

# INBOX -- `document --project` ignores ownRoots and writes into third-party code

> **REOPENED AND RE-FIXED 2026-08-13: the SECOND entry point had the same bug.**
>
> The 2026-08-12 fix below repaired `document --project`. It did not repair
> `lint-all --project --fix`, which reaches the writer by a different route and
> was still unscoped:
>
> ```pascal
> TDocLintRules.FixEditsForDocDrift(AStore)   // the store, and NOTHING else
> ```
>
> It took no findings, so it walked every documented public decl in the whole
> database. One `doc-drift` finding in YADF's own code was enough to make
> `lint-all --project YADF.dproj --fix` plan **22 edits into
> `C:\Projects\DelphiAST`** on the same run that printed
> `8 file(s) outside the project's own roots skipped`. Reproduced at small scale
> in `tests\autotest\run_autofix_apply_accounting.ps1`, where `--apply` really
> does write the vendored file and leave a `.bak` beside it.
>
> **Fixed** by giving it the targeted findings, exactly as its sibling
> `FixEditsForMissingDoc(AStore, ATargeted)` -- two functions away in the same
> class -- already did. The finding set has been through the ownership and
> `--project` filters before it gets there, so scoping to it inherits both.
>
> **Lesson for the next one:** the ownership fix was applied per COMMAND. There
> are two writer entry points and only one was fixed. Anything else that reaches
> `TDocumenter.BuildFor` from a store-wide walk is suspect until checked.

> **FIXED 2026-08-12, two independent ways -- both wanted.**
>
> 1. **`TDocBatch.DocumentProject` now filters the closure through `TOwnRoots`**,
>    the same declaration `lint-all` reads, and NAMES each skipped root with its
>    file count instead of dropping it silently. `--document-third-party` is the
>    escape hatch, mirroring `--lint-third-party`. This is the declarative half:
>    it lives in the repo and travels to any checkout.
> 2. **DelphiAST was added to the IDE Library path** (Win32 and Win64,
>    `Source` + `Source\SimpleParser`; previous values backed up). This was the
>    owner's suggestion and it is the architecturally correct home -- the closure
>    resolver ALREADY excludes library-path units, and `DocumentProject` already
>    passed `TProjectResolver.ResolveLibraryPaths` into it, so the machinery was
>    present and merely unconfigured. A vendored parser several projects may use
>    belongs in the library index, not in every project's closure.
>
> Measured effect on `document --project C:\Projects\YADF\YADF.dproj`:
> **945 decls -> 53**, "nothing to document", DelphiAST working tree clean.
> DelphiAST itself was reverted to `master@dfb2326` and its 8 stale `.pas.bak`
> files deleted.
>
> Bonus finding: with autodoc no longer reaching into a dependency, **the YADF
> autodoc cycle converges** -- a second pass is a no-op. The long-suspected
> "autodoc oscillates on YADF" was at least partly this, plus the empty
> `call_edges` fixed earlier the same day.
>
> Follow-on still owed: `index --all --only YADF --rebuild`, so DelphiAST drops
> out of YADF's project index too (it is still in there from before the library
> path change), and a library reindex if DelphiAST should be queryable.

**Found:** 2026-08-12, while checking whether the YADF autodoc cycle converges.
**Severity:** high -- it modifies source outside the project under a command the
user aimed at their own project.

## Symptom

```
drag-lint document --project C:\Projects\YADF\YADF.dproj --db ...\YADF.sqlite --apply
  -> doc: 1/945 decl(s) documented, 2 edit(s) applied
```

Zero files under `C:\Projects\YADF\` changed. The two edits landed in

```
C:\Projects\DelphiAST\Source\SimpleParser\SimpleParser.Lexer.pas
```

a VENDORED THIRD-PARTY parser in its own git repo, producing a 4,287-line diff
(2,495 insertions / 1,792 deletions).

## Root cause

`lint-all` learned ownership on 2026-08-12: it reports only code declared in
`<project folder>\_D-RAG\drag-lint-project.json` (`ownRoots`), defaulting to the
project file's folder, and names skipped third-party roots rather than dropping
them silently. **`document --project` never got the same treatment.** It still
walks the project's entire compile closure, which for YADF includes all of
DelphiAST.

Note the two commands disagree on the SAME project: `lint-all --project
YADF.dproj` reported exactly 8 YADF files, while `document --project
YADF.dproj` reached 945 declarations across the closure.

## Blast radius, as found

`C:\Projects\DelphiAST` (separate repo, `master` @ `dfb2326`) was ALREADY dirty
from earlier sessions -- 8 modified sources plus 8 `.pas.bak` files, i.e. prior
autodoc runs with backups enabled. Only `SimpleParser.Lexer.pas` carries today's
timestamp. So this has been happening for a while, unnoticed, because nobody
looks at a vendored dependency's working tree.

Second-order effect: those edits are inside the compile closure, so they are
INDEXED, and the index is what doc facts are computed from. Autodoc has been
partly documenting its own output in a dependency and feeding it back. That is a
plausible contributor to the long-standing "autodoc oscillates on YADF"
complaint, which is what this session was trying to measure when it found this.

## Why the diff is so large even on an already-documented file

DelphiAST's committed HEAD already contains `drag-lint:auto` blocks. Today's run
REWROTE them into the current format:

* `Called from: ... ?` -> `Used by: ...` (the unverified `?` marker is gone)
* `TmwBasePasLex caller` -> `declaration` (Phase C B11 stopped fabricating a
  caller name for a declaration-position ref)

So this particular churn is a one-time reformat from engine improvements, NOT
oscillation. Worth separating the two when measuring convergence.

## Fix

1. `document --project` (and `document-all`, and `--unit` when the unit resolves
   outside the own roots) must honour `ownRoots` exactly as `lint-all` does --
   same loader, same default, same "skipped third-party root, named, with its
   file count" reporting. Add `--document-third-party` as the escape hatch,
   mirroring `--lint-third-party`.
2. Until then, `document --project` on any project with vendored sources in its
   closure is unsafe to run with `--apply`.

## Reproduce

```
drag-lint document --project C:\Projects\YADF\YADF.dproj --db C:\Projects\YADF\_D-RAG\YADF.sqlite --apply --no-backup
git -C C:\Projects\DelphiAST status --porcelain
```

## Also noticed

YADF has NO `_D-RAG\drag-lint-project.json`. It happens not to need one for
`lint-all` (the `.dproj` sits at the root of the code it owns, so the default is
correct), but declaring it explicitly would make the intent legible and would be
picked up by the `document` fix above.
