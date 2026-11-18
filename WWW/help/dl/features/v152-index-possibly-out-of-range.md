---
id: v152-index-possibly-out-of-range
title: Array index possibly out of range lint rule (index-possibly-out-of-range)
summary: Warns (OFF in 1.52) on the write of an array index that no dominating guard bounds on both sides before the access; the InRange guard autofix is manual-only
product: DL
group: linting
order: 30071
since: 1.52.0-alpha
status: shipped
updated: 1.52.0-alpha
---

# Array index possibly out of range lint rule (index-possibly-out-of-range)

Warns (OFF in 1.52) on the write of an array index that no dominating guard bounds on both sides before the access; the InRange guard autofix is manual-only.

Read this to see when index-possibly-out-of-range warns, how it treats another collection's bound and index parameters, and how its manual-only autofix inserts an InRange check.

## How to run it

```text
drag-lint lint <file.pas> [--rule index-possibly-out-of-range] [--fix --fix-rule index-possibly-out-of-range [--apply]] (default OFF in 1.52, category bug-patterns, warning; hint on an unguarded parameter or a lookup-derived index; param exception_class; the autofix is manual only: a batch --fix withholds it, --fix-rule applies it; rules --json carries fix_manual_only: true)
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--rule` | `<id>` |  |  |
| `--fix` |  |  |  |
| `--fix-rule` | `<id>` |  |  |
| `--apply` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

An `ERangeError` that reaches an application user tells them nothing: it is the compiler's
last-resort guard (and with `{$R-}` there is no guard at all, only a silent overrun). A
subrange-typed index does not help either -- it only moves the range error to the assignment.
This rule warns where an array index can leave the array's bounds BEFORE the runtime check
fires, and points at the line that made it so: the write of the index, not the access.

Default **OFF** in 1.52 (owner ruling C3 = ON; lane BK-RULEFP fixed the six classes of the first 6/12 gate, but the FPM2 re-measure on ORM3 + YADF still found 21 FP in 36 samples -- short-circuit and while-top guards, SetLength(A, N) then an N-bound loop, a Length equality Exit, one-Inc-per-trip counters, constant-capped counters on fixed arrays -- so it ships OFF; enable it with `--rule index-possibly-out-of-range` or `"enabled": ["index-possibly-out-of-range"]` in the config), category `bug-patterns`, severity `warning` (`hint` for an unguarded
parameter). Run only it with
`drag-lint lint <file> --rule index-possibly-out-of-range`.

### What it reports

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

### What keeps it silent

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

### Symbolic bounds and other collections (1.52, IDXRANGE2)

Bounds are `count(Base) + Off`: SetLength size expressions, static bounds, `X.Count`, Length aliases.
A field or global array uses the size every SetLength in the file agrees on.

- **Parallel arrays (C1):** an index guarded against another collection (`i < Names.Count`) is silent only when
  that bound is proven within this array's (same SetLength count, static bounds within, or every local caller
  sizing the parameter array from the guarded count); otherwise a warning names the bound. A `for` running
  to another collection's bound reports on the `for` line.
- **Index parameters (C2):** cleared when EVERY local call passes an index proven in range (depth 1; only
  routines whose every use in the file is a plain call).
- **Lookups:** an index read from `GetValueOrDefault`, `Items[]` or `Map[k]` is a hint (its range is invisible).

### Autofix (risky, MANUAL ONLY)

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

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
