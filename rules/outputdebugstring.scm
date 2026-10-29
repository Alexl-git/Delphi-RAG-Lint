; OutputDebugString is debug tracing -- usually left in by accident. Remove it,
; or guard it behind {$IFDEF DEBUG} / route it through your logging abstraction.
; Fix-bound form FIRST (first pattern wins): the call is a plain statement of a begin..end list,
; so deleting the statement cannot orphan an 'if .. then' / 'else' / loop body. Any other
; position (a then/else/loop body) stays report-only: the fix declines it.
((block (statement (exprCall entity: (identifier) @inblk) @warn))
  (#match? @inblk "(?i)^outputdebugstring$"))

((exprCall entity: (identifier) @callee) @warn
  (#match? @callee "(?i)^outputdebugstring$"))
