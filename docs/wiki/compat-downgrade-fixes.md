# Downgrade fixes (compat rules)

Status: planned for 1.38.1.

The reverse of the modernize fixes. Each `compat` rule reports a construct the run's [target compiler](target-compiler) cannot compile, and its fix rewrites it to classic syntax: `X := if C then A else B` back to an `if` statement, `X is not T` to `not (X is T)`, `A not in S` to `not (A in S)`, `S.Contains(Sub)` to `Pos(Sub, S) > 0`, `InRange(X, A, B)` to `(X >= A) and (X <= B)`, digit separators removed, and inline `var` declarations hoisted into the routine's `var` section.

A compat rule runs exactly when the target is older than its construct (`compat_since`), so one switch -- `--target-compiler` -- both silences the modernize advice and enables its reverse; the pair is never active together. The fixes run like every other fix: `lint <file> --fix --target-compiler 12` is a dry run, `--apply` writes.

The 1.38.0 engine already has the switch, the `compat` category and the `compat_since` sidecar key; the rules ship in 1.38.1.
