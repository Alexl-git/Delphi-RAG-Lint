> **RETIRED to INBOX-Done/ on 2026-08-15.** FIXED 2026-08-14 (84be4c9): ResolveConsumerDbs now applies OrderDbsByMembership for a named target file, after the --project promotion -- the same ordering resolve-dbs --in always had. NOTE the new test case is non-discriminating on its fixture and says so; the fix is reasoned, not proven.
>
> Original note follows unchanged.

# A bare `lint <file>` opens the manifest's FIRST index, not the one holding the file

Found 2026-08-13, immediately after fixing the `--project` half of the same
defect family (commit `d9afbd9`, plan Task 0).

## Reproducer

    > drag-lint lint C:\Projects\YADF\YADF.Groups.pas --fix --fix-rule field-name-prefix
    index schema v19 < v21: run "drag-lint index <dir> --db <db>" to migrate
    autofix: no fixable findings (of 2 finding(s))

YADF's own index had just been rebuilt and is at the current schema. The v19
database is `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite` -- the
manifest's FIRST section, and an index that does not contain the file being
linted.

## Mechanism

`ResolveConsumerDbs` now honours `--project` (Task 0). With no `--project` it
still returns the manifest's platform-filtered list in **declaration order**, and
callers take `[0]`. Nothing consults the file actually being linted.

## The machinery to do this already exists

`resolve-dbs --in <file>` answers exactly this question, via
`OrderDbsByMembership(Paths, ActiveDb, AArgs.InFile, DbContainsFile)` in
`DRagLint.Index.Manifest`. It promotes the DBs that CONTAIN the file, leaves the
order alone when none do (the library-source case), and breaks ties toward the
active project. `DoResolveDbsList` calls it; `ResolveConsumerDbs` does not.

So the fix is to apply the same ordering inside `ResolveConsumerDbs` when a
target file is known (`AArgs.InFile` / `AArgs.Path`), after the `--project`
promotion that is already there. Note `OrderDbsByMembership` returns its input
unchanged when the path is empty, so wiring it in is a no-op for the commands
that have no file -- but confirm that per caller rather than assuming it.

## Why it matters beyond a confusing warning

Every store-backed per-file rule and every index-dependent autofix silently
consults a foreign project's symbols: `CheckTypeAware`, the naming autofixes,
hover, `find-unit`. The failure is quiet -- a wrong-but-plausible answer, or a
refusal with a misleading reason -- which is exactly the shape that cost a
session on the `--project` half.

## What this is NOT

It is **not** the cause of the `field-name-prefix` "advertises fixable, refuses
to fix" contradiction (plan Task 6). That was the obvious suspect and it is
wrong: passing `--db C:\Projects\YADF\_D-RAG\YADF.sqlite` explicitly, so the
correct fresh index is used, still gives

    autofix: no fixable findings (of 2 finding(s))

Two independent defects that happened to surface in the same command. See
`INBOX-field-name-prefix-fixable-flag-lies.md`.

## Suggested guard

Extend `tests\autotest\run_lint_project_db_resolution.ps1` -- it already builds
two projects in separate folders with their own indexes and a manifest that
declares the wrong one first. Add a case that lints a file from project A with
NO `--project` and NO `--db`, and asserts the finding set matches the explicit
`--db` run. The fixture is already exactly the shape this needs.
