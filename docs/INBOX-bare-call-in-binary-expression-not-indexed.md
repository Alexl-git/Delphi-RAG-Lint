# INBOX: a bare parameterless call used as a BINARY-EXPRESSION OPERAND records no ref

**Filed:** 2026-08-02 (during Auto-Document Phase 3, Task 9 part 2)
**Class:** `unsupported` (parser / ref-walk extraction gap)
**Index/DB:** any -- reproduced on a fresh scratch index built by the current
`third_party\dll-win64\drag-lint.exe`
**Status:** open. Worked around in the T9 fixture; NOT fixed.

## What happens

A parameterless routine called **without parentheses**, as an operand of a
binary expression, produces **no `refs` row at all**. Neither `dump-refs` nor
`query find-callers` sees it, so the call edge is missing from the graph.

This is NOT the general "bare RHS identifier" bug (Batch D / Task 4, "Bug B",
covered by `tests/callresolve/run_bare_rhs_refs.ps1`). That one -- the lone
identifier that is the WHOLE right-hand side -- is fixed and still works. The
residual gap is strictly the nested-in-an-expression case.

## Reproducing it

```pascal
unit hd3;

interface

function A: Integer;
function Lone: Integer;
function Binary: Integer;
function Arg: Integer;

implementation

function A: Integer;
begin
  Result := 1;
end;

function Lone: Integer;
begin
  Result := A;            // line 19
end;

function Binary: Integer;
begin
  Result := A + 1;        // line 24
end;

function Arg: Integer;
begin
  Result := Abs(A);       // line 29
end;

end.
```

```
drag-lint index <dir> --db <db>
drag-lint dump-refs <dir>\hd3.pas --db <db>
```

**Expected:** a ref for `A` at lines 19, 24 and 29.
**Actual:**

```
A|19|3|Lone
A|29|5|Arg
```

Line 24 is missing. Adding empty parentheses -- `Result := A() + 1;` -- makes
the ref appear, which is the workaround used in
`tests/autodoc/fixtures/docp3/harvest_drift.pas`.

## Why it matters beyond a missing edge

Missing call edges are not only a `find-callers` problem; they silently change
what the **autodoc** engine will write. A symbol with no facts gets no doc block
at all, and the batch path's facts-only filter then drops even a fresh create
that carried a harvested `<summary>`. Concretely, with the bare-operand form:

* `drag-lint document --qname <unit>.<Sym> --apply` documents the symbol.
* `drag-lint document --unit <file> --apply` reports **"nothing to document"**
  for the same symbol.

That divergence cost most of a debugging cycle in Task 9 part 2 and is worth
naming here even though the ref gap is the root cause.

## Probable location

`DRagLint.Parser.Delphi13.pas`, `Walk`'s ref emission. The Bug B fix added a
targeted arm: the `assignment` case additionally inspects
`ANode.ChildByField('rhs')` and emits a `read` when that field is *itself* a
bare `identifier` node. An `A + 1` RHS is a binary-expression node, not an
identifier node, so the arm does not fire and nothing descends into the
operands.

The fix is presumably to walk a binary expression's operands and emit a read for
a bare `identifier` operand -- but note the over-capture guard that
`run_bare_rhs_refs.ps1` exists to enforce: it must NOT become "any identifier
node is a read", or every declaration name and type reference gains a spurious
`read` ref. Any fix needs that test's negative assertions extended to the new
shape.

## Suggested test

Extend `tests/callresolve/run_bare_rhs_refs.ps1` with the three-way probe above
(lone / binary operand / call argument) so the fixed shape and the two already
working ones are asserted together, plus the existing type-name negative
control.
