---
id: uses-always-break
title: Break uses one-per-line
summary: Always break uses clauses one unit per line.
group: uses-clauses
order: 10
default: "true"
ini: UsesAlwaysBreak
since: "1.0.0.0"
status: "stable"
---

# Break uses one-per-line

When true (default), every uses-style clause is rendered
one identifier per line, comma-first, with the closing
semicolon on its own line at the same column as the commas:

    uses
      System.SysUtils
    , System.Classes
    ;

When false, the clause stays on a single line if it fits in
MaxLen and contains no `in 'path'` items; otherwise it breaks
(and the closing semicolon still goes on its own line).

## Related

- [Comma-last uses layout](uses-comma-last.md) - Style of the broken (multi-line) uses clause. False (default) is comma-FIRST (leading comma, semicolon on its own line) -- the diff-friendly layout. True is comma-LAST (trailing comma per unit, semicolon on the last unit's line: "System.Classes;"). Only affects the multi-line form; the inline single-line form is unchanged.
