# Expression and source-text rules (lane EXPR, 1.54)

Six checks for expressions that read as one thing and do another, and for source text that hides code. They run in
`lint` and `lint-all`, in the IDE and in VS Code. None needs the index.

```
drag-lint lint <unit.pas> --rule duplicate-logical-operand
drag-lint lint-all --db <project.sqlite> --rule contradictory-condition
```

Turn one off with `"disabled": ["boolean-comparison-precedence"]` in the lint config, or approve one line with a `dl:ok` marker.

## duplicate-logical-operand (warning, bug-patterns)

`(A = 1) or (A = 1)`, `Assigned(P) and Assigned(P)`: the same operand twice in one `and` / `or` chain, the second one
adds nothing (usually a copy-paste that forgot to change the second test). Reported once per operand, at its second occurrence.

An operand counts only when it is provably Boolean and effect-free: a comparison, a `not`, a Boolean RTL function
(`Assigned`, `Odd`, `SameText`, `StartsText`, ...) or an `and` / `or` of those, with no other call in it. Silent for
`Next(Q) or Next(Q)` (a call may have a side effect), for a bare name (`Flags and Flags` can be an integer mask) and for
different operands.

## contradictory-condition (warning, bug-patterns)

`(X > 5) and (X < 3)`, `(X = 1) and (X = 2)`, `(X = 1) and (X <> 1)`: comparisons of one variable with literals in one
`and` chain that cannot all hold, so the whole chain is always False. The variable is a name or a dotted name, the literal a
number (also `$FF`, negative, left of the operator). Intervals are judged over the reals, so `(X > 5) and (X < 6)` stays
silent although no integer fits. Silent for `or`, for two variables, and for a call on either side.

## boolean-comparison-precedence (warning, bug-patterns)

`Flag and Other = False` is `(Flag and Other) = False`, because `and` binds tighter than `=`. `Flag = True and Other` is
`Flag = (True and Other)`. Reported only when a literal `True` / `False` proves the operands Boolean. `Flags and 4 = 0`
(a bit test) and any parenthesised form are silent.

## function-name-reads-itself (warning, bug-patterns)

`Counter := Counter + X` in a function `Counter` without parameters calls `Counter` again; it does not read the value just
assigned. Judged only for a function without parameters whose body also assigns its own name (the author uses the name
as the result variable). Silent for a call with parentheses, `Obj.Name`, `@Name`, a function that only uses `Result`,
and for reads inside a nested routine or an anonymous method.

## warnings-off-not-restored (hint, bug-patterns)

A `{$WARNINGS OFF}` (or `(*$WARNINGS OFF*)`) with no `{$WARNINGS ON}` after it in the file hides every warning after it.
Reported at the directive. Silent when the switch is restored later in the same file (also in another conditional
branch), when only the final `end.` follows it, for directives in strings and comments, and for include files (they are
not linted on their own). Library units are not told apart: add them to the lint exclusions.

## homoglyph-identifier (warning, security)

An identifier with Latin letters and at least one Cyrillic or Greek letter that looks like a Latin one (`Counter` with a
Cyrillic o): two names that print alike are different identifiers. The check reads the file bytes and judges only valid
UTF-8. Silent for a name written in one script (`Name_` + a whole Cyrillic word with a non-look-alike letter in it is a
real word), for strings, comments, and for files in a code page (bytes above 127 are then letters of that page).

## What the rules add over the compiler

dcc64 37.0 compiles all six without a message by default: a repeated or impossible condition is legal, `and` / `=` are legal
on Booleans, a function name read is a legal recursive call, `{$WARNINGS OFF}` is a switch, and a Cyrillic letter is a legal
identifier character.

## Measured

Read-only copies of five project indexes (drag-lint, Micronite, Loader2025, TableTools370P, YADF GuardTest), 2026-11-24, one rule
and one process at a time. The final build reports 0 findings for all six rules on all five corpora, so all six ship ON as
proposed and are marked "not measured in the field" (no true positive was seen either). The first run found 8 false positives
of duplicate-logical-operand on drag-lint: `(C >= 'A')` and `(C >= 'a')` were read as equal (the key was lower-cased inside character
literals), and `T.TryGetValue(.., Cnt) and (Cnt = 1) and U.TryGetValue(.., Cnt) and (Cnt = 1)` (a call in between changes Cnt). Both are fixed
(literals keep their case; an operand that is not effect-free clears the operands seen so far) and are negative fixtures.
Not measured: DFM-only identifiers (homoglyph-identifier reads .pas / .dpr / .dpk only).
