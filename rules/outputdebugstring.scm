; OutputDebugString is debug tracing -- usually left in by accident. Remove it,
; or guard it behind {$IFDEF DEBUG} / route it through your logging abstraction.
((exprCall entity: (identifier) @callee) @warn
  (#match? @callee "(?i)^outputdebugstring$"))
