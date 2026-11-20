; GetTickCount returns a 32-bit millisecond counter that WRAPS after ~49.7 days,
; so naive elapsed-time math (Now - Start) is wrong across the wrap. Use
; GetTickCount64. Matches the identifier in both 'GetTickCount' and 'GetTickCount()'.
;
; SLZ-RULE1 2026-11-19: only the TIMING shapes fire -- GetTickCount as the whole
; right-hand side of an assignment or an inline-var / const initialiser (the
; stored start tick a later difference reads) and as an operand of a binary
; expression (the subtraction or comparison itself). GetTickCount used only as
; a NAME or SEED -- a Format argument, IntToStr(Int64(GetTickCount)) glued into a
; temp-dir name -- wraps harmlessly and is not reported. Self-LoopZero found 3/3
; such findings in drag-lint's own CLI (temp-dir names), all false.
((assignment rhs: [(identifier) @warn (exprCall entity: (identifier) @warn)])
  (#match? @warn "(?i)^gettickcount$"))
((defaultValue [(identifier) @warn (exprCall entity: (identifier) @warn)])
  (#match? @warn "(?i)^gettickcount$"))
((exprBinary lhs: [(identifier) @warn (exprCall entity: (identifier) @warn)])
  (#match? @warn "(?i)^gettickcount$"))
((exprBinary rhs: [(identifier) @warn (exprCall entity: (identifier) @warn)])
  (#match? @warn "(?i)^gettickcount$"))