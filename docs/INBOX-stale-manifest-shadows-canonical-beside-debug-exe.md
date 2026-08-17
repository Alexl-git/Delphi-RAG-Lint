# INBOX -- a stale manifest beside the DEBUG exe shadows the canonical one

**Found 2026-08-16 (session 23)**, while chasing what looked like a `resolve-dbs`
bug. It was not one. Recording it because the false trail is the point.

## What happens

`TManifestIO.Load(EngineDir, GetCurrentDir)` looks for `drag-lint.json` **beside
the exe first**. There is one beside the DEBUG build output:

```
src\cli\Win64\Debug\drag-lint.json      2026-08-09, 5,501 bytes   <- STALE
third_party\dll-win64\drag-lint.json    current, canonical
```

The stale copy predates the 2026-08-11/12 layout migration, so it still names DBs
in the deleted shared-folder layout. Same command, two exes, two answers:

```
third_party\dll-win64\drag-lint.exe  resolve-dbs --project C:\Projects\YADF\YADF.dproj
    -> C:\Projects\YADF\_D-RAG\YADF.sqlite            CORRECT

src\cli\Win64\Debug\drag-lint.exe    resolve-dbs --project C:\Projects\YADF\YADF.dproj
    -> C:\Projects\YADF\YADF.sqlite                   WRONG (file does not exist)
```

and for DataCopy the debug exe answers `C:\Projects\.drag-lint\DataCopy-App.sqlite`
-- `<OutDir>\<SectionName>.sqlite`, the pre-migration derivation.

## The engine is NOT at fault

`ExpandSectionDb` already implements the current rule (a project section defaults
to `<project folder>\_D-RAG\<project file base>.sqlite`) and the deployed exe
proves it. **The difference is entirely which manifest got loaded.** I spent
several steps concluding `resolve-dbs --project` was broken before noticing I was
running the debug build; that conclusion was wrong and is corrected here so the
next reader does not repeat it.

## Exposure -- measured, and currently zero for the battery

* **75** of the 308 suites default to `src\cli\Win64\Debug\drag-lint.exe`.
* **0** of them run a command that auto-resolves a DB -- every one passes an
  explicit `--db` or builds its own. So the battery is unaffected today.

That zero is luck, not design. A suite added later that omits `--db` would
silently resolve against a 2026-08-09 view of the world and either fail
confusingly or, worse, read a DB that still exists but is no longer authoritative.

Interactive use is affected NOW: anyone who runs the debug build directly -- the
natural thing to do right after `msbuild` -- gets stale DB paths from the verb
whose entire job is to stop people guessing them. `CLAUDE.md` tells agents "Do not
guess a DB path -- ask the tool", so the tool answering wrongly in that build is
exactly the failure mode the instruction exists to prevent.

## Proposed fix (NOT applied -- the delete was declined)

**Delete `src\cli\Win64\Debug\drag-lint.json`.** It is gitignored and untracked,
so nothing depends on it being present; removing it makes the debug exe fall
through to the CWD walk like any other consumer. Refreshing it instead would
create a second copy to keep in sync -- the same trap as the two gitignored
deploy dirs that already make rule edits inert until hand-copied.

Then add a guard: a suite asserting the deployed exe and the debug exe return the
**same** `resolve-dbs --project` answer for a known project. That is a
one-command check and it fails loudly the next time a stale manifest appears
beside any build output. **It would fail today**, which is what makes it worth
having.

Cost XS. The only judgement call is whether anything relies on that file being
present in a fresh checkout -- I believe not, since it is gitignored, but the
owner should confirm before it is deleted.
