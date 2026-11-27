# noreturn-contract: calls that never come back (lane FA-1, 1.56)

Delphi 13 has the `noreturn` directive: `procedure Fail(const AText: string); noreturn;` promises that a call of
`Fail` never comes back. Since 1.56 the index stores that promise for every routine (the fact `symbol_extras.noreturn`),
also for the routines of the RTL, and the rule `noreturn-contract` uses it.

```
drag-lint lint <unit.pas> --db <project.sqlite> --rule noreturn-contract
drag-lint lint-all --db <project.sqlite> --rule noreturn-contract
```

| rule | severity | default | needs the index |
|---|---|---|---|
| `noreturn-contract` | warning (code after the call), hint (routine not marked) | ON | yes |

Turn it off with `"disabled": ["noreturn-contract"]` in the lint config, or approve one line with a `dl:ok` marker.

## What it reports

### Code after a call that never comes back (warning)

```pascal
procedure Import(const AFile: string);
begin
  if not FileExists(AFile) then
  begin
    Fail('no such file');     // Fail is declared noreturn, in another unit
    Log('import skipped');    // reported: this line is never reached
  end;
```

The finding is on the first statement after the call. The compiler says nothing here: it reports only an assignment
whose value is never used (H2077), and only sometimes.

Silent when the statement after the call is `Result := ..`, `<function name> := ..` or `Exit`. Those lines are written to
keep a compiler quiet that does not know the callee never returns, and the Delphi 13 compiler reports them itself.

### A routine that never returns and does not say so (hint)

```pascal
procedure RaiseImportError(const AText: string);   // reported: add noreturn
begin
  raise EImport.Create(AText);
end;
```

Every way through the routine ends in `raise`, `Halt`, `Abort` or a call to a `noreturn` routine. Declare it `noreturn`
and the compiler and drag-lint both know that code after a call of it is dead, and that a function calling it last need
not set its result.

Silent for:

* a method that is `virtual`, `dynamic`, `override`, `abstract` or a `message` handler, and a method of a class that
  lists an interface or has an ancestor the index cannot see (the ancestor or the interface dictates the directives;
  dropping or adding one is compiler error E2037 / E2211);
* a constructor or destructor, an `external` routine, an event handler (first parameter `Sender`);
* a routine that only loops forever, and a routine whose exception is caught by its own `except` block;
* a code base whose indexed RTL does not declare `Abort` with `noreturn` (a compiler before Delphi 13 has no such
  directive, so the advice would not compile).

## What it leaves to the compiler

Measured with dcc64 37.0 (`tests\fixtures\v156-fa1\compiler-probe`, output in `dcc64-37.0-output.txt`):

| case | compiler |
|---|---|
| a `noreturn` routine that can return: falls off the end, `Exit`, ends in a call to a routine that returns (same or other unit), swallowed exception, procedural variable, `Break` out of a loop | W1080 in every shape |
| an override that drops the directive | E2037 |
| an interface implementation that drops the directive | E2211 |
| code after a call to a `noreturn` routine | nothing (H2077 for an unused assignment only) |
| a routine that never returns and is not marked | nothing |

The rule reports the last two rows only; it does not repeat W1080.

## How the callee is found

1. The exact callee of the call site, when the index resolved the call for certain: its stored `noreturn` fact decides.
2. Otherwise, for a bare name or a name qualified by `System` / `SysUtils` / `System.SysUtils` / `Winapi.Windows`: the
   call never returns when EVERY symbol of that name in the project index and the library index is a routine with the
   fact. One variable, field or returning routine of the same name anywhere makes the answer "may return".
3. Anything else (a call through a variable, a generic call, an unresolved method): "may return", no finding.

The fact is 1 for a declaration that carries the directive, 2 for the RTL routines the compiler treats as never
returning on older versions (`Halt`, `RunError`, `Abort`, `RaiseLastOSError`, ...). Both count as "never returns".

Re-index after adding or removing a `noreturn` directive: the rule reads the stored fact, not the other unit's source.

## The flow graph

`TCfgBuilder.Build` (`DRagLint.Analysis.Cfg`) takes an optional oracle, `TCfgNoReturnCall`. With it, a call statement
the oracle knows as never returning ends its block like a `raise`: an edge to the routine exit marked `NoReturn`, and
nothing after it is part of the graph. `TNoReturnFacts` (`DRagLint.V156.FACTA.Support`) is that oracle on the stored
fact. Without an oracle the graph is exactly the one of 1.55, which is what the index-time passes use: a stored fact
must never depend on which other file was indexed first.

In 1.56 the rule above is the caller that passes the oracle. The older flow rules (`function-result-not-set`,
`out-param-not-set`, `object-leak`, ...) still build the graph without it.

## Limits

* A routine declared only inside the second or a later define context of an include file that is parsed in several
  contexts has no stored fact (the merged parse keeps the facts of the first context). A call of it is "may return".
* A `noreturn` function called inside an expression (`X := NeverReturns(1)`) is not seen: only call statements are.
* There is no automatic fix for the hint; add the directive to the declaration by hand.

## Measured

Fixture `tests\fixtures\v156-fa1`, runner `tests\autotest\run_v156_FA1.ps1`: 11 lines that must report, 17 routines
that must stay silent. Not measured in the field yet (no real project was re-indexed with the 1.56 facts when the rule
was written).
