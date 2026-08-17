> # CLOSED 2026-08-17. All three defects fixed and covered; the last loose end is discharged.
>
> | defect | state |
> |---|---|
> | `find-unit` read only the LAST `--db` | fixed `16456a2`, `run_find_unit_multidb.ps1` (RED 6/6) |
> | `Build` invented a SECOND `uses` clause when the store did not index the file -- under `--apply`, code that does not compile | fixed `16456a2` |
> | `resolve-uses` carried the same single-`--db` shape, and its empty already-imported set made the +1000 bonus apply to everything | fixed `c761b5f`, `run_resolve_uses_multidb.ps1` (RED 4/7) |
> | **the `.bat` coverage gap that let (3) survive** | **closed** -- all 60 legacy `.bat` tests are now driven; see `INBOX-Done\INBOX-68-bat-tests-are-invisible-to-the-battery.md` |
>
> **The through-line, and the reason this note produced three fixes rather than
> one:** `resolve-uses` DID have a test, and it passed -- because it put both
> units in ONE database, the single configuration in which the bug cannot
> appear. A test that exercises only the shape where the defect is impossible is
> indistinguishable from no test at all, except that it also stops anyone
> looking. Chasing why nobody had noticed is what uncovered the 68 invisible
> `.bat` files, which in turn uncovered a live `generate-docs` regression.
>
> ---
>
# INBOX -- `find-unit` silently uses only the LAST `--db`, so its answer depends on flag order

**Found** 2026-08-16 (session 24), while checking whether the VCL/FMX tie fixed in
`query --name` also reached the other name-based verbs. It does not reach
`find-unit` -- but something worse does.

**Class:** `wrong` (the index answers, incorrectly). Not stale, not out-of-scope.

## The defect

`DoFindUnit` (`src\cli\DRagLint.CLI.pas:9939`) opens **`AArgs.DbPath`** -- a
single path -- and never calls `ResolveConsumerDbs`:

```pascal
if AArgs.DbPath = '' then begin Writeln('ERROR: --db required'); Exit(2); end;
Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
Edits:= TFindUnitRefactoring.Build(Store, AArgs.Name, AArgs.InFile, ...);
```

(An earlier draft of this note cited `:3405`. That is `resolve-uses`, a
DIFFERENT function that carries a near-identical single-DB shape -- worth its
own look, but it is not the verb measured below.)

`ParseArgs` assigns `Result.DbPath:= ParamStr(i)` on **every** `--db` while also
appending to `Result.DbPaths`. So `DbPath` holds whichever `--db` came **last**,
and every earlier one is accepted without complaint and then discarded.

Consequence: `find-unit` answers a different question depending on the ORDER of
flags that a caller has every reason to believe are commutative.

## Repro (measured, `library-Win64` + `DataCopy`)

```
drag-lint find-unit --name TEdit --in C:\Projects\DataCopy\uMainZeissCopy.pas ^
    --db C:\Projects\.drag-lint\library-Win64.sqlite ^
    --db C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite
  -> Could not resolve a unit declaring "TEdit".        (exit 1)

drag-lint find-unit --name TEdit --in ... (the SAME two DBs, ORDER SWAPPED)
    --db ...DataCopy.sqlite --db ...library-Win64.sqlite
  -> insert after line 2176: uses Vcl.StdCtrls;         (exit 0)

drag-lint find-unit --name TEdit --in ... --db ...library-Win64.sqlite
  -> insert after line 2176: uses Vcl.StdCtrls;         (exit 0)
```

Same for a symbol only the library can possibly declare:

```
drag-lint find-unit --name TFDQuery --in ... --db <library> --db <project>
  -> Could not resolve a unit declaring "TFDQuery".
```

## THE WORSE HALF, found while verifying the fix: `--apply` could write code that does not compile

Chasing the order-dependence turned up a second, independent defect underneath
it, and this one CORRUPTS SOURCE rather than merely refusing.

`TFindUnitRefactoring.Build` (`src\refactor\DRagLint.Refactor.TextEdit.pas:607`)
branches on `HaveLast`, i.e. "did the file's uses rows yield a last entry". When
they did not, it emits **a fresh `uses <Unit>;` block after the `implementation`
line**. But an empty uses set has TWO causes, and they demand opposite actions:

* **(a)** the file genuinely declares no uses clause -- a fresh block is right;
* **(b)** `AUnitStore` does not INDEX the file at all -- we know nothing, and a
  fresh block is a guess.

`InFileId` separates them and nothing consulted it. Measured, before the fix:

```
drag-lint find-unit --name TEdit --in C:\Projects\DataCopy\uMainZeissCopy.pas ^
    --db C:\Projects\.drag-lint\library-Win64.sqlite
  -> insert after line 2176:
     uses Vcl.StdCtrls;
```

Line 2176 of that unit is `implementation`, and the unit **already has an
implementation uses clause at lines 2180-2200**. Under `--apply` that writes a
SECOND uses clause into the same section, which does not compile.

The keyword scan in that branch cannot catch it: it reads the file only to
locate the `implementation`/`interface` keyword and never asks whether a uses
clause already follows.

**Fixed by refusing rather than guessing:** `if InFileId <= 0 then Exit;` --
no edits, so the caller reports "No edit computed" and exits 1, the same shape
as the pre-existing `KeywordLine = 0` refusal three lines below. Deliberately
NOT "scan the text for an existing uses clause": a line scan cannot tell code
from a comment or a string, which is a defect family this repo has already been
bitten by repeatedly.

Verified after the fix:

```
--db <library only>          -> No edit computed.                (exit 1)
--db <library> --db <project> -> insert at L2199:C16: , Vcl.StdCtrls  (exit 0)
```

Note the second line is the REAL fix showing through: it appends inside the
existing clause at 2199 instead of inventing one at 2176.

## Why this one matters more than its size suggests

1. **It contradicts the standing rule agents are told to follow.** `C:\Projects\CLAUDE.md`
   says the authoritative set is *platform library + project DB*. A caller doing
   exactly that, in the natural order (library first, project second), gets
   `Could not resolve` for `TEdit`, `TFDQuery`, and every other RTL/VCL type --
   i.e. for precisely the symbols `find-unit` exists to answer.
2. **A wrong answer here EDITS SOURCE.** `find-unit --apply` writes a `uses`
   entry. "Could not resolve" is the benign half; the dangerous half is a
   project DB that happens to declare a same-named type, which would be reported
   as the unit to import.
3. **It fails silently in both directions.** No warning that extra `--db` flags
   were dropped. The failure is indistinguishable from "no such symbol", which is
   the same confusion INBOX finding 2.10 (`--name` case sensitivity) was filed
   for.

## Not a regression from the framework-preference change

The VCL/FMX preference shipped the same session touches `DoQuery` only
(`ResolveFrameworkContextDb` / `PreferFrameworkFirst` / `GuiFrameworkInUse` have
exactly one call site each, in `DoQuery`). `DoFindUnit` reads `AArgs.DbPath` and
did so before. Checked, not assumed.

## FIXED 2026-08-16 (same session)

**The two halves are different questions, which is why one store could never
serve both.** "Which unit declares `TEdit`" is a LIBRARY fact; the `--in` file's
id, its existing uses clause and the insertion point are PROJECT facts, and file
ids are per-DB.

`TFindUnitRefactoring.Build` **already had a two-store overload**
(`ANameStore, AUnitStore`), added for `convert-apply`, which hit exactly this
problem. `DoFindUnit` simply never used it. So the fix is wiring, not new
mechanism: resolve the DB list with `ResolveConsumerDbs`, then find each store
INDEPENDENTLY and in scan order --

* `UnitStore` = the first index whose `FindFileIdByPath` resolves `--in`;
* `NameStore` = the first index that declares `--name`.

Scan order means the project index (which `ResolveConsumerDbs` promotes to the
front) wins the NAME when it declares it too. That is the right precedence: a
project's own type beats a same-named RTL one.

Degradation is deliberate and preserves today's behaviour exactly: when no index
contains the target file, `UnitStore` falls back to `NameStore`, which is the
single-store situation the verb was always in.

### What still needs a POSITIVE CONTROL when a test is written

`AlreadyUsed`. With one library DB the `--in` lookup finds nothing and the
already-imported set is silently EMPTY -- so a test asserting only "TEdit
resolves" passes with that set still empty and proves nothing about the fix.
Assert that an already-imported unit is actually reported as already used in the
MULTI-DB case, which is only possible once `AUnitStore` is the project index.

Still open, and NOT fixed here: whether repeated `--db` should scan all
(consistent with `query`, and what this now does) or be rejected. Silent
last-wins is the one option that was never defensible.

## `resolve-uses` -- SAME DEFECT, ALSO FIXED (2026-08-16)

`DoResolveUses` carried the identical shape --
`TSQLiteSymbolStore.Create(AArgs.DbPath)`, one store, no `ResolveConsumerDbs` --
in the verb `docs\AI-USAGE.md` names as THE way to ask "which unit do I add to
my uses clause?".

**And it mattered more here than the order-dependence alone suggests.** The
already-imported set comes from the `--in` file's own uses rows, which exist
only in the store that INDEXES that file. Ask a library-only index and
`InFileId` is 0, the set stays EMPTY, and every candidate silently collects the
"not already used" **+1000** bonus -- so a unit the caller ALREADY imports is
ranked and offered as a fresh add. That reads as a plausible answer, not an
error, which is how it survived.

Why it survived a test, specifically: the only existing coverage was
`tests\fixtures\T_resolve_uses.bat` -- a `.bat`, so **the battery never ran it**
(the battery collects `run_*.ps1`), pointing at the retired Win32
`third_party\dll\drag-lint.exe` path, and putting BOTH units in ONE db, which is
exactly the configuration where the bug cannot appear.

Fixed the same way as `find-unit`, with the two facts gathered from different
places on purpose: declarations from every store (each symbol's path resolved
through the store that OWNS it, since file ids are per-DB), and the
already-imported set from whichever store contains `--in`. Also switched to
`OpenReadOnlyStore` -- a read-only query verb should not `Migrate`, and
migrating several indexes to answer one question would be worse.

Covered by `tests\autotest\run_resolve_uses_multidb.ps1`, **RED on 4 asserts**
against the unfixed build. Its positive control is `<already in uses>` across
two databases, unsatisfiable by any single-store implementation. Note that on
the unfixed build the two NEGATIVE assertions ("not suggested", "not told it
already uses it") pass VACUOUSLY -- nothing is found at all -- which is exactly
why each is paired with a positive one.

**The old `.bat` fixture is left in place and still stale**, and counting it
turned out to be worth doing: there are **68 `.bat` tests under `tests\`, none
of which the battery runs**, and **43 of them point at the retired Win32
`third_party\dll\drag-lint.exe`, which still exists and still runs**. Filed
separately as `INBOX-68-bat-tests-are-invisible-to-the-battery.md`. Until that
is dealt with, anything covered only by a `.bat` under `tests\` is effectively
uncovered -- `resolve-uses` is the proof.
