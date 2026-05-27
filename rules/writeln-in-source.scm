; v0.3: predicates now work. The (#eq?) clause filters down to ONLY calls
; whose callee identifier equals "WriteLn" (case-sensitive).
((exprCall
  entity: (identifier) @callee) @warn
  (#eq? @callee "WriteLn"))
