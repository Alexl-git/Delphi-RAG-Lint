# Results, parameters, nested addresses and overlays (lane FLOW, 1.54)

Eight rules that run in `lint` and `lint-all`, in the IDE and in VS Code.

```
drag-lint lint <unit.pas> --db <project.sqlite> --rule managed-result-read-first
drag-lint lint-all --db <project.sqlite> --enable constant-return,redundant-field-init
```

| rule | severity | default | needs the index |
|---|---|---|---|
| `managed-result-read-first` | warning | ON | no (type names of other units: yes) |
| `same-variable-two-var-params` | warning | ON | yes |
| `address-of-nested-routine` | warning | ON | no |
| `absolute-overlay` | hint | OFF | no |
| `constant-return` | hint | OFF | yes |
| `redundant-field-init` | hint | OFF | no |
| `var-param-never-written` | hint | OFF | yes |
| `value-param-assigned` | hint | OFF | no |

Turn one off with `"disabled": ["absolute-overlay"]` in the lint config, on with `"enabled": [..]` or `--enable`, or approve
one line with a `dl:ok` marker. The OFF rules cost nothing while they are off.

## managed-result-read-first

The result of a function that returns a string, a dynamic array, an interface or a Variant is a hidden `var` parameter: on
entry it can hold what the caller's variable held. The rule reports the first place where the function uses `Result` before
every path has set it:

```pascal
function Join(const A: TArray<string>): string;
begin
  for var S in A do
    Result := Result + S;      // in a loop of the caller the old text stays in front
end;
```

Also `SetLength(Result, Length(Result) + 1)`, `if Result = nil` and `while Length(Result) < N`. One finding per function.

Silent when every path sets `Result` first (assignment, own name, `Exit(value)`, an element or a field of it); `Result` is
passed to a routine that can fill it (`SetLength(Result, N)`, `Fill(Result)`, `@Result`); a nested routine or an anonymous
method uses it; the read stands under the same condition as an assignment before it; the result is a record, a short string
or an unmanaged type; the routine holds `asm`.

## same-variable-two-var-params

`Swap(S, S)`: one variable, two parameters that can both write it. Also `Parse(const S: string; out S)`, where the call clears
the text it is about to read. The callee must be the one certain target in the index.

Silent for untyped parameters (`Move`), for a `const` with a `var`, for `const` with `out` of an unmanaged type, for different
fields or indexes (`A[I]`, `A[J]`), and when the two arguments are not written the same way.

## address-of-nested-routine

`@Nested` and `Addr(Nested)` of a routine declared inside another routine. Measured with Delphi 13: on Win64 the arguments of
a call through the pointer arrive shifted even when the nested routine uses no outer local (`EnumWindows(@Nested, 42)` gave
32767 for the 42); on both platforms the first use of an outer local is an access violation.

Silent for unit routines, methods and variables, and when a parameter or local variable hides the routine's name, and
when the address goes to a routine of the unit that holds `asm`.

## absolute-overlay

`GAlias: Integer absolute GBytes`: two names for one memory cell, no conversion and no size check. A hint, for review.

Silent when the target is an untyped parameter (`absolute Buf` on `var Buf`): that is the way to give it a type; or when both sides are object references
(or type names nobody knows).

## constant-return (OFF)

A function with at least two `Result := ..` / `Exit(..)` that all give the same literal. Either a branch does not do what it
says, or the function needs no result.

Silent for one assignment (a stub), for a function that raises, reads `Result`, passes it on or sets it in a nested routine,
and where somebody else dictates the signature: virtual, override, message, external, `stdcall` / `cdecl`, published methods,
a `Sender` parameter, a method name an interface of the project has, a class that lists interfaces, a routine used as a value.

## redundant-field-init (OFF)

`FCount := 0` (or `nil`, `False`, `''`) among the first statements of a constructor: a new object is already zero.

Silent for records, inherited fields, properties, class fields, after the first statement that is not `inherited` or a plain
assignment, when the field was set before, when the class replaces `NewInstance`, and after a call that can run code of the
class (`inherited Create`, a `T.Create(Self)`) when the class has virtual routines, messages, interfaces or a form file and
another routine of it names the field.

## var-param-never-written (OFF)

A typed `var` parameter that is read and never written, passed on, or changed through a method of a record.

Silent in the same signature cases as `constant-return`, and for a routine with `asm`.

## value-param-assigned (OFF)

A by-value parameter that is assigned (or `Inc` / `Dec`) and so used as a local variable. One finding per parameter.

## What the rules add over the compiler

dcc64 37.0 with all warnings and hints compiles every positive fixture without a message about these cases. W1035 covers
unmanaged results only; H2077 does not see any of them.

## Measured

2026-11-24, copies of project indexes and a private index of the Delphi 37 `source\vcl` folder, one rule at a time.

| corpus | result-first | same-var | nested | overlay | constant | field-init | var-unwritten | value-set |
|---|---|---|---|---|---|---|---|---|
| drag-lint (448 files) | 1 | 1 | 0 | 0 | 2 | 12 | 10 | 46 |
| Micronite2027 (583 units) | 0 | 0 | 0 | 3 | 0 | 43 | 0 | 40 |
| Loader2025 | 0 | 0 | 0 | 1 | 0 | 2 | 0 | 0 |
| TableTools370P | 0 | 0 | 0 | 3 | 0 | 0 | 0 | 12 |
| YADF GuardTest | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 2 |
| VCL (126 files) | 6 | 0 | 0 | 1 | 0 | 23 | 7 | 420 |

* `managed-result-read-first`: 7 of 7 right (read in source; a test program shows the old value for string, array, interface and
  Variant on Win32 and Win64). `same-variable-two-var-params`: 1 of 1 right (the `const` text arrives empty). Both ON.
* `address-of-nested-routine`: the 5 of the VCL go through an `asm` thunk that pushes the frame; that shape is silent now; re-measured with the final engine: VCL 0, Micronite 0, so nothing left to be wrong on those corpora. ON.
* `absolute-overlay`: the VCL and 4 of 7 Micronite findings were one object reference over another (a cast without a check);
  that shape is silent now. Re-measured with the final engine: VCL 1 (TColor under TRGBTriple), Micronite 3 (a Single bitcast to Cardinal), all deliberate bit casts: a reviewer would dismiss every one, so OFF (owner may switch it on).
* `constant-return`: 1 of 2 is a command handler with a uniform signature: OFF. `var-param-never-written`: 1 of 17 reads a field the callee
  changes on the way, 2 unsure: OFF. `redundant-field-init`: no false one found, style only: OFF. `value-param-assigned`: OFF, 420 in one corpus.
