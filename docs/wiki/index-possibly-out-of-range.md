# index-possibly-out-of-range (lane IDXRANGE, 1.52)

An `ERangeError` that reaches an application user tells them nothing: it is the compiler's
last-resort guard (and with `{$R-}` there is no guard at all, only a silent overrun). A
subrange-typed index does not help either -- it only moves the range error to the assignment.
This rule warns where an array index can leave the array's bounds BEFORE the runtime check
fires, and points at the line that made it so: the write of the index, not the access.

Default **ON** (owner ruling C3; the first false-positive gate measured 6 FP in 12 samples, fixed by lane BK-RULEFP; the FPM2 re-measure found 21 FP in 36, fixed by lane IDXRANGE3 and re-measured 0 FP: YADF 0/12, ORM3 CLIENT 0/12, ORM3 SERVER 0/5), category `bug-patterns`, severity `warning` (`hint` for an unguarded
parameter). Disable it with `"disabled": ["index-possibly-out-of-range"]` in the lint config; run only it with
`drag-lint lint <file> --rule index-possibly-out-of-range`.

## What it reports

For each `A[idx]` where `A` is a static `array[lo..hi]`, a dynamic or open array (`array of`,
`TArray<T>`, `TBytes`) and `idx` is a local or parameter of the routine:

| Case | Reported |
|---|---|
| `i := Calc; A[i]` | warning on the `i :=` line |
| `while i < Length(A) do begin Inc(i); A[i] ... end` | warning on the `Inc` (it breaks the loop guard) |
| `i := i - 1; if i < Length(A) then A[i]` | warning: only the upper side is guarded |
| `i: TSmall` (a subrange) `i := Calc; A[i]` | warning: the subrange is not a guard |
| `while (A[i] = 0) and (i <= 8) do Inc(i)` | warning: `A[i]` is read before the bound check |
| `function F(Idx: Integer) ... D[Idx]` | hint on the access: the caller's value is unknown |

## What keeps it silent

- `for i := Low(A) to High(A)`, `for i := 0 to Length(A) - 1`, `downto` the same;
- an `if` / `while` condition bounding both sides: `(i >= Low(A)) and (i <= High(A))`,
  `(i >= 0) and (i < Length(A))`, `InRange(i, Low(A), High(A))`, literal bounds inside a static
  array's range;
- an earlier `if (i < Low(A)) or (i > High(A)) then Exit;` (or `raise`, `Continue`, `Break`,
  `if not InRange(...) then ...`);
- a short-circuit guard: `while (i < Length(A)) and (A[i] <> 0)` (the left side holds when the
  right side runs); an if-expression `if i < Length(A) then A[i] else 0`;
- a local written once as `n := Length(A)` used in the guard (`while i < n`);
- grow-on-demand: an earlier `if i >= Length(A) then SetLength(A, ...)`;
- every write of `i` that can reach the access keeping it in range by itself (`i := 0` ...
  `Inc(i)` under `while i < Length(A)`); a later reuse of `i` after the access does not count;
- a variable that never reaches an array access (a counter, a result);
- a literal index (that is `constant-index-out-of-range`), a string index;
- v1 cuts (silent, not proven): `for` loops with other bounds, `case i of`, `repeat ... until`
  conditions on `i`, `Assert`, field / global indexes, routines with `with` or `goto`, an index a
  nested routine or a lambda can write, `TList.Count`.

A write between the guard and the access cancels the guard.

## Symbolic bounds and other collections (1.52, IDXRANGE2)

Bounds are `count(Base) + Off`: SetLength size expressions, static bounds, `X.Count`, Length aliases.
A field or global array uses the size every SetLength in the file agrees on.

- **Parallel arrays (C1):** an index guarded against another collection (`i < Names.Count`) is silent only when
  that bound is proven within this array's (same SetLength count, static bounds within, or every local caller
  sizing the parameter array from the guarded count); otherwise a warning names the bound. A `for` running
  to another collection's bound reports on the `for` line.
- **Index parameters (C2):** cleared when EVERY local call passes an index proven in range (depth 1; only
  routines whose every use in the file is a plain call).
- **Lookups:** an index read from `GetValueOrDefault`, `Items[]` or `Map[k]` is a hint (its range is invisible).

## Value bounds, windows and sizes (1.52, IDXRANGE3)

- **Value bounds:** the least / greatest value of the index from its writes in text order (a dominating
  write resets, a conditional one joins, `Inc` in a `for` counts its trips, writes in a loop around the
  access flow back), through chains of locals (`j := i + 1`, `i := j`), guards right after a write
  (`P := Find(..); if P < 0 then Exit`), a for counter copied out of its loop, `Floor(Abs(x) * c + d)`
  behind an `Abs(x) > k` Exit, a counter with a constant cap (`N := 0` plus N straight-line `Inc`).
- **Windows:** from the SetLength that dominates the access to the end of the loops around it, a local, a
  field path or `Length(X)` that nothing there changes reads as one value (`SetLength(A, N); while i < N`).
- **Sizes:** `A := F(P)` / `F(P, A)` where F starts with `SetLength(Result or A, P.Count)` (this unit, or
  another unit through `--db`); an array of the enclosing routine; two arrays sized by the same
  expression in a row, or made equal by `if Length(A) <> Length(B) then Exit`; `SetLength(A, n + 1); A[n]`.
- A write followed by `Exit` / `Continue`, or in the other branch of an if / else, does not undo a guard.

## Arrays of another unit (1.52.3, IDXRANGE-TP)

With `--db`, an accessed array that this unit does not declare is looked up in the index: a const or var
array declared in the INTERFACE of another unit (`MscConst.NssDistConvert: array [0 .. 4] of 0 .. 8`) is
checked, but reported only on a PROVEN overrun: the index's known bound leaves the array's range, e.g.
`while (H[i] = 0) and (i <= 4) do Inc(i); X := NssDistConvert[i]` lets `i` reach 5 (uINSPRSLT:5575). An
index whose bound is unknown or within range (a clamp, `i < High(A)`, a limit picked by the same
condition as the array) is not reported for such an array. A declaration this unit
can see always wins (a local const of the same name shadows it); a name declared twice with different
bounds is skipped; routine-local and implementation-section consts of other units never count. Without
`--db` such an access is not checked.

## One side at a time: guards, writes, callers, lengths (1.53, SLZ-IDXFP)

When the checks above leave a side open, the rule asks for that side alone, at the access, and follows the index
back: the guards that dominate the point, the writes that reach it, and what those writes read. A chain that comes
back to itself through a write holds by induction, unless it drifted towards the bound. New silent shapes:

- **Binary search:** `Mid := (Lo + Hi) shr 1` / `div 2` (also `+ 1`) under `Lo <= Hi` / `Lo < Hi`, with `Lo := Mid + 1`,
  `Hi := Mid - 1`.
- **Scans from a counter:** `J := I - 1; while (J >= 0) and A[J] ..` in `for I := 1 to High(A)`.
- **Found index:** `K := -1; for I .. if .. then K := I; if K >= 0 then A[K]`, whatever sized `A`; look up or append
  (`if K < 0 then begin K := Length(A); SetLength(A, K + 1) end`); a retry branch that ends in its own leave guard.
- **Guard forms:** `I + 1 < Length(A)`; `(I = Length(A)) or (A[I] ..)` under `I <= Length(A)`; a Boolean function of this
  file whose body is one `Result := ..` on that parameter; `if E < 0 then 0 else E`; `if Length(A) = 0 then Exit`
  before `A[0]`; a minimum (`if Length(B) < N then N := Length(B)`).
- **Index lists and queues** the routine fills itself with in-range values (`Order := Order + [I]`, `List.Add(I)`,
  `Work.Enqueue(I)`), read by `for I in Order`, `Order[J]`, `Work.Dequeue`. A list that comes from elsewhere is reported.
- **Callers and results:** a parameter of a private method (or of a routine of the implementation section) that every
  call in this file passes in range, several calls deep; the result, or an out / var argument, of a function of this file.
- **Equal lengths:** two arrays only ever changed together (appended, reset or sized side by side); rows swapped whole
  (`Prev := Cur`, `Prev := Copy(Cur)`) with one SetLength size; `A := Copy(B)`; one append per trip of `for x in B`;
  `if Length(A) < Length(B) then SetLength(A, Length(B))`; the branch of `Length(A) <> Length(B)` where they are equal; a size
  local or size field that is assigned once.
- **Unsigned index, capped read:** a `Cardinal` index is never negative; `N := Read(Buf, SizeOf(Buf) - 1)` is at most that.
- **By value (`--db`):** passing the index to another unit's routine that takes it by value is no write.

**One finding per start value:** an element that was already read on every path to the access (same index, not moved
towards the bound since) is not reported again; the first access carries the finding.

Still reported: an index from an unproven parameter, a list or queue filled elsewhere, a call without a guard on its
not-found value, an array parameter bounded by another parameter's length.
## Autofix (risky, MANUAL ONLY)

`drag-lint lint --in <f.pas> --fix --fix-rule index-possibly-out-of-range [--apply]` inserts,
on its own line before the statement holding the access, at its indentation:

```pascal
if not InRange(i, Low(A), High(A)) then raise EArgumentOutOfRangeException.CreateFmt('A index %d outside %d..%d in TFoo.Bar', [i, Low(A), High(A)]);
```

and adds `System.Math` / `System.SysUtils` to the uses clause when they are missing. The class
is the rule param `exception_class`:

```json
{ "params": { "index-possibly-out-of-range": { "exception_class": "EMyIndexError" } } }
```

An access inside a condition or a one-statement branch (`if X then A[i] := 1`) gets no edit --
the message says `no autofix` -- because an inserted line would change what the branch guards.
The fix is flagged risky and manual-only (`fix_manual_only: true` in `rules --json`): it changes behaviour (a raise instead of a range error or overrun), so a batch `--fix` (no `--fix-rule`) withholds it with a stderr note;
only `--fix-rule index-possibly-out-of-range` (the IDE's Fix it) applies it. Edit the inserted message text afterwards.

Spec: `docs\superpowers\specs\2026-11-16-index-possibly-out-of-range-design.md`.
