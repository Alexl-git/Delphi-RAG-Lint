# index-possibly-out-of-range (lane IDXRANGE, 1.52)

An `ERangeError` that reaches an application user tells them nothing: it is the compiler's
last-resort guard (and with `{$R-}` there is no guard at all, only a silent overrun). A
subrange-typed index does not help either -- it only moves the range error to the assignment.
This rule warns where an array index can leave the array's bounds BEFORE the runtime check
fires, and points at the line that made it so: the write of the index, not the access.

Default **OFF**, category `bug-patterns`, severity `warning` (`hint` for an unguarded
parameter). Enable it with `"enabled": ["index-possibly-out-of-range"]` in the lint config, or
name it: `drag-lint lint <file> --rule index-possibly-out-of-range`.

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

## Autofix (risky, opt-in)

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
The fix is flagged risky: it changes behaviour (a raise instead of a range error or overrun).

Spec: `docs\superpowers\specs\2026-11-16-index-possibly-out-of-range-design.md`.
