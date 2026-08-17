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

## Related, unexamined

`resolve-uses` (`src\cli\DRagLint.CLI.pas:3405`) carries the same single-`--db`
shape -- `TSQLiteSymbolStore.Create(AArgs.DbPath)`, one store, no
`ResolveConsumerDbs`. It was not measured or touched. Its `UsedUnits` set has
the identical hiding property described above (the `AlreadyUsed` +1000 scoring
term at `:3472` is inert whenever the `--in` file is not in the store being
scanned).
