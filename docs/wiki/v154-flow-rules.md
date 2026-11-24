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
| `absolute-overlay` | hint | ON | no |
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

Silent for unit routines, methods and variables, and when a parameter or local variable hides the routine's name.

## absolute-overlay

`GAlias: Integer absolute GBytes`: two names for one memory cell, no conversion and no size check. A hint, for review.

Silent when the target is an untyped parameter (`absolute Buf` on `var Buf`): that is the way to give it a type.

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

@MEASURED@
